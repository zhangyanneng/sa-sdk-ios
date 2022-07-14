//
// DemoController.m
// SensorsAnalyticsSDK
//
// Created by ZouYuhan on 1/19/16.
// Copyright © 2015-2022 Sensors Data Co., Ltd. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "TestTableViewController.h"
#import "TestCollectionViewController.h"
#import <Foundation/Foundation.h>

#import "zlib.h"

#import "DemoController.h"

@implementation DemoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.tableView.sensorsAnalyticsDelegate = self;
    
    // 请求参数拦截
    [[SensorsAnalyticsSDK sharedInstance] customBodyCallBack:^id _Nonnull(NSArray * _Nonnull eventRecords) {
        NSArray *json = [self buildJSONData:eventRecords];
        return @{@"list":json};
    }];
    
    // 添加渠道
    [[SensorsAnalyticsSDK sharedInstance]
     addChannelUrl:@"http://beta-global.popmazxrt.com/track/v1/track/track-events/1/track-full"
                                             httpHeader:
         @{
            @"Content-Type":@"application/json;charset=UTF-8"
        }
     bodyFormat:^id _Nonnull(NSArray * _Nonnull eventRecords) {
        NSArray *json = [self buildJSONData:eventRecords];
        return @{@"list":json};
    }];
}


//转化数据结构
//
- (NSArray *)buildJSONData:(NSArray *)array {
    NSMutableArray *arrM = [NSMutableArray array];
    [array enumerateObjectsUsingBlock:^(NSDictionary *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        NSString *type = [obj objectForKey:@"event"];
        NSDictionary *properties = [obj objectForKey:@"properties"];
        
        NSMutableDictionary *dictM = [NSMutableDictionary dictionary];
        dictM[@"topic"] = @"app";
        dictM[@"time"] =  [obj objectForKey:@"time"] ? [obj objectForKey:@"time"] : @(0);
        dictM[@"type"] = type ? [self deleteSpecial:type] : @"";
        dictM[@"resume_from_background"] = @(NO);
        dictM[@"anonymous_id"] = [obj objectForKey:@"anonymous_id"] ? [obj objectForKey:@"anonymous_id"] : @"";
        dictM[@"distinct_id"] = [obj objectForKey:@"distinct_id"] ? [obj objectForKey:@"distinct_id"] : @"";
        dictM[@"login_id"] = [obj objectForKey:@"login_id"] ? [obj objectForKey:@"login_id"] : @"";
        dictM[@"properties"] = @{
            @"app_id":[properties objectForKey:@"$app_id"] ? [properties objectForKey:@"$app_id"] : @"",
            @"app_name": [properties objectForKey:@"$app_name"] ? [properties objectForKey:@"$app_name"] : @"",
            @"app_version": [properties objectForKey:@"$app_version"] ? [properties objectForKey:@"$app_version"] : @"",
            @"is_first_day": [properties objectForKey:@"$is_first_day"] ? [properties objectForKey:@"$is_first_day"] : @(NO),
            @"is_login_id": [properties objectForKey:@"is_login_id"] ? [properties objectForKey:@"is_login_id"] : @(NO),
            @"manufacturer": [properties objectForKey:@"$manufacturer"] ? [properties objectForKey:@"$manufacturer"] : @"",
            @"model":[properties objectForKey:@"$model"] ? [properties objectForKey:@"$model"] : @"",
            @"network_type": [properties objectForKey:@"$network_type"] ? [properties objectForKey:@"$network_type"] : @"",
            @"os": [properties objectForKey:@"$os"] ? [properties objectForKey:@"$os"] : @"",
            @"os_version": [properties objectForKey:@"$os_version"] ? [properties objectForKey:@"$os_version"] : @"",
            @"scene":[properties objectForKey:@"$screen_name"] ? [properties objectForKey:@"$screen_name"] : @"",
            @"screen_height": [properties objectForKey:@"$screen_height"] ? [properties objectForKey:@"$screen_height"] : @"",
            @"screen_width": [properties objectForKey:@"$screen_width"] ? [properties objectForKey:@"$screen_width"] : @0,
            @"ip":[properties objectForKey:@"ip"] ? [properties objectForKey:@"ip"] : @"",
        };
        
        
        [arrM addObject:dictM];
    }];
    
    return arrM.copy;
}

// 去除$符号
- (NSString *)deleteSpecial:(NSString *)special {
    return [special stringByReplacingOccurrencesOfString:@"$" withString:@""];
}


- (NSDictionary *)getTrackProperties {
    return @{@"shuxing" : @"Gaga"};
}

- (NSString *)getScreenUrl {
    return @"WoShiYiGeURL";
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    
}

- (void)testTrack {
    [[SensorsAnalyticsSDK sharedInstance] track:@"testTrack" withProperties:@{@"testName":@"testTrack 测试"}];
}

- (void)testTrackSignup {
    [[SensorsAnalyticsSDK sharedInstance] login:@"newId"];
}

- (void)testTrackInstallation {
    [[SensorsAnalyticsSDK sharedInstance] trackAppInstallWithProperties:nil];
}

- (void)testProfileSet {
    [[SensorsAnalyticsSDK sharedInstance] set:@"name" to:@"caojiang"];
}

- (void)testProfileAppend {
    [[SensorsAnalyticsSDK sharedInstance] append:@"array" by:[NSSet setWithObjects:@"123", nil]];
}

- (void)testProfileIncrement {
    [[SensorsAnalyticsSDK sharedInstance] increment:@"age" by:@1];
}

- (void)testProfileUnset {
    [[SensorsAnalyticsSDK sharedInstance] unset:@"age"];
}

- (void)testProfileDelete {
    [[SensorsAnalyticsSDK sharedInstance] deleteUser];
}

- (void)testFlush {
    [[SensorsAnalyticsSDK sharedInstance] flush];
}

- (void)testCodeless {
    
}

- (NSDictionary *)sensorsAnalytics_tableView:(UITableView *)tableView autoTrackPropertiesAtIndexPath:(NSIndexPath *)indexPath {
    return @{@"sensorsDelegatePath":[NSString stringWithFormat:@"tableView:%ld-%ld",(long)indexPath.section,(long)indexPath.row]};
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUInteger row = [indexPath row];
    switch (row) {
        case 0:{
            NSLog(@"测试track");
            [self testTrack];
            TestTableViewController *vc =  [[TestTableViewController alloc] init];
            //TestCollectionViewController *collectionVC = [[TestCollectionViewController alloc]init];
            [self.navigationController pushViewController:vc  animated:YES];
        }
            break;
        case 1l: {
            NSLog(@"测试track_signup");
            [self testTrackSignup];
            TestCollectionViewController_A *collectionVC = [[TestCollectionViewController_A alloc] init];
            [self.navigationController pushViewController:collectionVC animated:YES];
        }
            break;
        case 2l:{
            NSLog(@"测试track_installation");
            [self testTrackInstallation];
            TestCollectionViewController_B *vc =  [[TestCollectionViewController_B alloc] init];
            //TestCollectionViewController *collectionVC = [[TestCollectionViewController alloc]init];
            [self.navigationController pushViewController:vc  animated:YES];
            break;
        }
        case 3l:
            NSLog(@"测试profile_set");
            [self testProfileSet];
            break;
        case 4l:
            NSLog(@"测试profile_append");
            [self testProfileAppend];
            break;
        case 5l:
            NSLog(@"测试profile_increment");
            [self testProfileIncrement];
            break;
        case 6l:
            NSLog(@"测试profile_unset");
            [self testProfileUnset];
            break;
        case 7l:
            NSLog(@"测试profile_delete");
            [self testProfileDelete];
            break;
        case 8l:
            NSLog(@"测试flush");
            [self testFlush];
            break;
        case 9l:
            NSLog(@"进入全埋点测试页面");
            [self testCodeless];
            break;
        default:
            break;
    }
}

@end
