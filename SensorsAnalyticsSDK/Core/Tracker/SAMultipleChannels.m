//
// SAMultipleChannels.m
// SensorsAnalyticsSDK
//
// Created by 张艳能 on 2022/7/14.
// Copyright © 2015-2022 Sensors Data Co., Ltd. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#if ! __has_feature(objc_arc)
#error This file must be compiled with ARC. Either turn on ARC for the project or use -fobjc-arc flag on this file.
#endif

#import "SAMultipleChannels.h"
#import "NSString+SAHashCode.h"
#import "SAGzipUtility.h"
#import "SAModuleManager.h"
#import "SAObject+SAConfigOptions.h"
#import "SANetwork.h"
#import "SALog.h"
#import "SAJSONUtil.h"
#import "SensorsAnalyticsSDK+Private.h"
#if __has_include("SAConfigOptions+Encrypt.h")
#import "SAConfigOptions+Encrypt.h"
#endif

#import "SADatabase.h"


static NSString *kUrlKey = @"url_key";
static NSString *kHeaderKey = @"header_key";
static NSString *kBodyKey = @"body_key";

typedef id(^BodyCallBack)(NSArray *events);


@interface SAMultipleChannels ()

@property(nonatomic, strong) NSMutableDictionary *cacheChannels;

@property (nonatomic, strong) dispatch_semaphore_t flushSemaphore;

@property (nonatomic, strong) dispatch_semaphore_t mulFlushSemaphore;

@property (nonatomic, readonly) BOOL isDebugMode;

@property (nonatomic, strong, readonly) NSURL *serverURL;

@property (nonatomic, readonly) BOOL flushBeforeEnterBackground;

@property (nonatomic, readonly) BOOL enableEncrypt;

@property (nonatomic, copy, readonly) NSString *cookie;

@end


@implementation SAMultipleChannels

- (void)addChannle:(NSString *)url header:(NSDictionary *)header body:(id (^)(NSArray *records))bodyCallback {
    NSMutableDictionary *channel = [NSMutableDictionary dictionary];
    
    if (url.length) {
        [channel setValue:url forKey:kUrlKey];
    }
    
    if (header) {
        [channel setValue:header forKey:kHeaderKey];
    } else {
        [channel setValue:@{} forKey:kHeaderKey];
    }
    
    if (bodyCallback) {
        [channel setValue:bodyCallback forKey:kBodyKey];
    }
    
    if (self.cacheChannels) {
        [self.cacheChannels setValue:channel forKey:url];
    } else {
        self.cacheChannels = [NSMutableDictionary dictionary];
        [self.cacheChannels setValue:channel forKey:url];
    }
    
}


- (dispatch_semaphore_t)flushSemaphore {
    if (!_flushSemaphore) {
        _flushSemaphore = dispatch_semaphore_create(0);
    }
    return _flushSemaphore;
}

- (dispatch_semaphore_t)mulFlushSemaphore {
    if (!_mulFlushSemaphore) {
        _mulFlushSemaphore = dispatch_semaphore_create(0);
    }
    return _mulFlushSemaphore;
}


// 1. 先完成这一系列 Json 字符串的拼接
- (NSString *)buildFlushJSONStringWithEventRecords:(NSArray<SAEventRecord *> *)records {
    NSMutableArray *contents = [NSMutableArray arrayWithCapacity:records.count];
    for (SAEventRecord *record in records) {
        NSString *flushContent = [record flushContent];
        if (flushContent) {
            [contents addObject:flushContent];
        }
    }
    return [NSString stringWithFormat:@"[%@]", [contents componentsJoinedByString:@","]];
}

- (NSString *)buildFlushEncryptJSONStringWithEventRecords:(NSArray<SAEventRecord *> *)records {
    // 初始化用于保存合并后的事件数据
    NSMutableArray *encryptRecords = [NSMutableArray arrayWithCapacity:records.count];
    // 用于保存当前存在的所有 ekey
    NSMutableArray *ekeys = [NSMutableArray arrayWithCapacity:records.count];
    for (SAEventRecord *record in records) {
        if (!record.ekey) continue;

        NSInteger index = [ekeys indexOfObject:record.ekey];
        if (index == NSNotFound) {
            [record removePayload];
            [encryptRecords addObject:record];

            [ekeys addObject:record.ekey];
        } else {
            [encryptRecords[index] mergeSameEKeyRecord:record];
        }
    }
    return [self buildFlushJSONStringWithEventRecords:encryptRecords];
}

- (NSURLRequest *)buildFlushRequestWithServerURL:(NSURL *)serverURL header:(NSDictionary *)header HTTPBody:(NSData *)HTTPBody {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:serverURL];
    request.timeoutInterval = 30;
    request.HTTPMethod = @"POST";
    request.HTTPBody = HTTPBody;
    [header enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        [request setValue:obj forHTTPHeaderField:key];
    }];

    //Cookie
    [request setValue:self.cookie forHTTPHeaderField:@"Cookie"];

    return request;
}

- (void)requestWithUrl:(NSString *)url records:(NSArray<SAEventRecord *> *)records completion:(void (^)(BOOL success))completion {
    [SAHTTPSession.sharedInstance.delegateQueue addOperationWithBlock:^{
        BOOL isEncrypted = self.enableEncrypt && records.firstObject.isEncrypted;
        // 拼接 json 数据
        NSString *jsonString = isEncrypted ? [self buildFlushEncryptJSONStringWithEventRecords:records] : [self buildFlushJSONStringWithEventRecords:records];
        // 网络请求回调处理
        SAURLSessionTaskCompletionHandler handler = ^(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error) {
            if (error || ![response isKindOfClass:[NSHTTPURLResponse class]]) {
                SALogError(@"%@ network failure: %@", self, error ? error : @"Unknown error");
                return completion(NO);
            }

            NSInteger statusCode = response.statusCode;

            NSString *urlResponseContent = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSString *messageDesc = nil;
            if (statusCode >= 200 && statusCode < 300) {
                messageDesc = @"\n【valid message】\n";
            } else {
                messageDesc = @"\n【invalid message】\n";
                if (statusCode >= 300 && self.isDebugMode) {
                    NSString *errMsg = [NSString stringWithFormat:@"%@ flush failure with response '%@'.", self, urlResponseContent];
                    [SAModuleManager.sharedInstance showDebugModeWarning:errMsg];
                }
            }

            NSDictionary *dict = [SAJSONUtil JSONObjectWithString:jsonString];
            SALogDebug(@"%@ %@: %@", self, messageDesc, dict);

            if (statusCode != 200) {
                SALogError(@"%@ ret_code: %ld, ret_content: %@", self, statusCode, urlResponseContent);
            }

            // 1、开启 debug 模式，都删除；
            // 2、debugOff 模式下，只有 5xx & 404 & 403 不删，其余均删；
            BOOL successCode = (statusCode < 500 || statusCode >= 600) && statusCode != 404 && statusCode != 403;
            BOOL flushSuccess = self.isDebugMode || successCode;
            completion(flushSuccess);
        };

        // 转换成发送的 http 的 body
        NSDictionary *parmas = [self.cacheChannels objectForKey:url];
        NSDictionary *header = [parmas objectForKey:kHeaderKey];
        BodyCallBack callBack = [parmas objectForKey:kBodyKey];
        NSArray *array = [SAJSONUtil JSONObjectWithString:jsonString];
        id jsonBody = callBack(array);
        NSData *HTTPBody = [[SAJSONUtil stringWithJSONObject:jsonBody] dataUsingEncoding:NSUTF8StringEncoding];
        NSURLRequest *request = [self buildFlushRequestWithServerURL:[NSURL URLWithString:url] header:header HTTPBody:HTTPBody];
        NSURLSessionDataTask *task = [SAHTTPSession.sharedInstance dataTaskWithRequest:request completionHandler:handler];
        [task resume];
    }];
}



- (void)flushMultipleChannelsEventRecords:(NSArray<SAEventRecord *> *)records {
    [self.cacheChannels.allKeys enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSMutableArray *arrM = [NSMutableArray arrayWithArray:records];
        // 获取上一次失败的缓存数据
        NSArray *oldArray = [self.dataBase selectChannelRecordsWithChannel:obj];
        if (oldArray.count) {
            // 合并数据
            [arrM addObjectsFromArray:oldArray];
        }
        // 数据缓存
        [self.dataBase insertOrUpdateRecords:arrM channelUrl:obj];
        
        [self flushEventWithUrl:obj records:arrM completion:^(BOOL success) {
            if (success) {
                // 成功 删除缓存
                [self.dataBase deleteRecordsWithChannel:obj];
            } else {
                // 失败
            }
            
            dispatch_semaphore_signal(self.mulFlushSemaphore);
        }];
        dispatch_semaphore_wait(self.mulFlushSemaphore, DISPATCH_TIME_FOREVER);
    }];
}

- (void)flushEventWithUrl:(NSString *)url records:(NSArray<SAEventRecord *> *)records completion:(void (^)(BOOL success))completion {
    __block BOOL flushSuccess = NO;
    // 当在程序终止或 debug 模式下，使用线程锁
    BOOL isWait = self.flushBeforeEnterBackground || self.isDebugMode;
    [self requestWithUrl:url records:records completion:^(BOOL success) {
        if (isWait) {
            flushSuccess = success;
            dispatch_semaphore_signal(self.flushSemaphore);
        } else {
            completion(success);
        }
    }];
    if (isWait) {
        dispatch_semaphore_wait(self.flushSemaphore, DISPATCH_TIME_FOREVER);
        completion(flushSuccess);
    }
}

- (BOOL)isDebugMode {
    return SAModuleManager.sharedInstance.debugMode != SensorsAnalyticsDebugOff;
}

- (NSURL *)serverURL {
    return [SensorsAnalyticsSDK sdkInstance].network.serverURL;
}

- (BOOL)flushBeforeEnterBackground {
    return SensorsAnalyticsSDK.sdkInstance.configOptions.flushBeforeEnterBackground;
}

- (BOOL)enableEncrypt {
#if TARGET_OS_IOS && __has_include("SAConfigOptions+Encrypt.h")
    return [SensorsAnalyticsSDK sdkInstance].configOptions.enableEncrypt;
#else
    return NO;
#endif
}


- (NSString *)cookie {
    return [[SensorsAnalyticsSDK sdkInstance].network cookieWithDecoded:NO];
}


@end
