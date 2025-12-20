#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Global variables
static BOOL isCapturing = NO;
static BOOL hasShownInfo = NO;
static UIWindow *statusWindow = nil;
static NSDictionary *capturedInfo = nil;

// Create persistent floating status box
void createStatusBox() {
    if (statusWindow) return;

    statusWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 80, UIScreen.mainScreen.bounds.size.width * 0.8, 60)];
    statusWindow.windowLevel = UIWindowLevelStatusBar + 1;
    statusWindow.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
    statusWindow.layer.cornerRadius = 12;
    statusWindow.layer.masksToBounds = YES;

    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                statusWindow.windowScene = scene;
                break;
            }
        }
    }

    statusWindow.hidden = NO;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(statusWindow.bounds, 10, 5)];
    label.tag = 100;
    label.text = @"Waiting...";
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    [statusWindow addSubview:label];
}

void updateStatusBox(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!statusWindow) createStatusBox();
        UILabel *label = [statusWindow viewWithTag:100];
        if (label) label.text = text;
    });
}

void removeStatusBox() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (statusWindow) {
            [statusWindow removeFromSuperview];
            statusWindow = nil;
        }
    });
}

UIViewController *topMostViewController() {
    UIWindow *window = nil;

    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                window = scene.windows.firstObject;
                break;
            }
        }
    }

    if (!window) {
        window = UIApplication.sharedApplication.windows.firstObject;
    }

    if (!window || !window.rootViewController) return nil;

    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    return topVC;
}

// Redeem codes function
void redeemCodes() {
    if (!capturedInfo) {
        updateStatusBox(@"No info captured yet");
        return;
    }

    updateStatusBox(@"Fetching codes...");

    // Fetch codes from API
    NSURL *codeUrl = [NSURL URLWithString:@"https://chillysilly.frfrnocap.men/cfcode.php"];
    NSMutableURLRequest *codeRequest = [NSMutableURLRequest requestWithURL:codeUrl];
    codeRequest.HTTPMethod = @"GET";

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:codeRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            updateStatusBox(@"Failed to fetch codes");
            return;
        }

        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json[@"cfcode"]) {
            updateStatusBox(@"Invalid code response");
            return;
        }

        NSArray *allCodes = json[@"cfcode"];
        if (allCodes.count == 0) {
            updateStatusBox(@"No codes available");
            return;
        }

        // Split codes into batches of 5
        NSMutableArray *batches = [NSMutableArray array];
        for (NSInteger i = 0; i < allCodes.count; i += 5) {
            NSInteger end = MIN(i + 5, allCodes.count);
            NSArray *batch = [allCodes subarrayWithRange:NSMakeRange(i, end - i)];
            [batches addObject:batch];
        }

        // Redeem each batch
        __block NSInteger currentBatch = 0;
        __block NSInteger successCount = 0;
        __block NSInteger failCount = 0;

        void (^redeemNextBatch)(void);
        redeemNextBatch = ^{
            if (currentBatch >= batches.count) {
                updateStatusBox([NSString stringWithFormat:@"Done! ✓%ld ✗%ld", (long)successCount, (long)failCount]);
                return;
            }

            NSArray *batch = batches[currentBatch];
            updateStatusBox([NSString stringWithFormat:@"Redeeming batch %ld/%ld", (long)(currentBatch + 1), (long)batches.count]);

            NSDictionary *payload = @{
                @"userId": capturedInfo[@"userId"],
                @"serverId": capturedInfo[@"serverId"],
                @"gameCode": @"A49",
                @"roleId": capturedInfo[@"roleId"],
                @"roleName": capturedInfo[@"roleName"],
                @"level": capturedInfo[@"level"],
                @"codes": batch
            };

            NSError *payloadError = nil;
            NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&payloadError];
            if (payloadError) {
                failCount += batch.count;
                currentBatch++;
                redeemNextBatch();
                return;
            }

            NSURL *redeemUrl = [NSURL URLWithString:@"https://vgrapi-sea.vnggames.com/coordinator/api/v1/code/redeem-multiple"];
            NSMutableURLRequest *redeemRequest = [NSMutableURLRequest requestWithURL:redeemUrl];
            redeemRequest.HTTPMethod = @"POST";
            redeemRequest.HTTPBody = payloadData;

            [redeemRequest setValue:@"application/json" forHTTPHeaderField:@"content-type"];
            [redeemRequest setValue:@"VN" forHTTPHeaderField:@"x-client-region"];
            [redeemRequest setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"accept"];
            [redeemRequest setValue:@"vi-VN,vi;q=0.9" forHTTPHeaderField:@"accept-language"];
            [redeemRequest setValue:@"https://giftcode.vnggames.com" forHTTPHeaderField:@"origin"];
            [redeemRequest setValue:@"https://giftcode.vnggames.com/" forHTTPHeaderField:@"referer"];
            [redeemRequest setValue:[[NSUUID UUID] UUIDString] forHTTPHeaderField:@"x-request-id"];

            NSURLSessionDataTask *redeemTask = [session dataTaskWithRequest:redeemRequest completionHandler:^(NSData *redeemData, NSURLResponse *redeemResponse, NSError *redeemError) {
                if (!redeemError && redeemData) {
                    NSError *resultError = nil;
                    NSDictionary *result = [NSJSONSerialization JSONObjectWithData:redeemData options:0 error:&resultError];
                    if (!resultError && result) {
                        NSArray *results = result[@"data"];
                        for (NSDictionary *r in results) {
                            if ([r[@"status"] boolValue]) {
                                successCount++;
                            } else {
                                failCount++;
                            }
                        }
                    } else {
                        failCount += batch.count;
                    }
                } else {
                    failCount += batch.count;
                }

                currentBatch++;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    redeemNextBatch();
                });
            }];
            [redeemTask resume];
        };

        dispatch_async(dispatch_get_main_queue(), ^{
            redeemNextBatch();
        });
    }];
    [task resume];
}

// Minimal hook - only intercept specific endpoint
%hook NSURLSessionDataTask

- (void)resume {
    NSURLRequest *request = [self currentRequest];
    if (!request) {
        %orig;
        return;
    }

    NSString *urlString = request.URL.absoluteString;

    // Only hook the OAuth endpoint
    if ([urlString hasPrefix:@"https://oauth.vnggames.app/oauth/v1/token"]) {
        // Store original completion handler via associated object
        void (^originalCompletion)(void) = ^{
            %orig;
        };

        // Swizzle to capture response
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [NSThread sleepForTimeInterval:0.1];
            
            // Try to read response data (this is a simplified approach)
            // In production, you'd use method swizzling on the completion handler
            originalCompletion();
        });

        return;
    }

    %orig;
}

%end

// Alternative approach: Hook at URLSession level with minimal intrusion
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!completionHandler || !request || !request.URL) {
        return %orig;
    }

    NSString *urlString = request.URL.absoluteString;

    if ([urlString hasPrefix:@"https://oauth.vnggames.app/oauth/v1/token"]) {
        isCapturing = YES;
        hasShownInfo = NO;
        updateStatusBox(@"Capturing...");

        void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            completionHandler(data, response, error);

            if (error || !data || hasShownInfo) return;

            NSError *jsonError = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (jsonError || ![json[@"status"] boolValue]) return;

            NSString *userId = json[@"userId"];
            if (!userId || userId.length == 0) return;

            updateStatusBox(@"Got ID! Fetching...");

            NSString *roleUrlStr = [NSString stringWithFormat:@"https://vgrapi-sea.vnggames.com/coordinator/api/v1/code/role?gameCode=A49&serverId=101&userIds=%@", userId];
            NSURL *roleUrl = [NSURL URLWithString:roleUrlStr];
            NSMutableURLRequest *roleRequest = [NSMutableURLRequest requestWithURL:roleUrl];
            roleRequest.HTTPMethod = @"GET";

            [roleRequest setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"accept"];
            [roleRequest setValue:@"vi-VN,vi;q=0.9" forHTTPHeaderField:@"accept-language"];
            [roleRequest setValue:@"VN" forHTTPHeaderField:@"x-client-region"];

            NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
            NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
            NSURLSessionDataTask *roleTask = [session dataTaskWithRequest:roleRequest completionHandler:^(NSData *roleData, NSURLResponse *roleResponse, NSError *roleError) {
                if (roleError || !roleData) {
                    updateStatusBox(@"Fetch failed");
                    return;
                }

                NSError *roleJsonError = nil;
                NSDictionary *roleJson = [NSJSONSerialization JSONObjectWithData:roleData options:0 error:&roleJsonError];
                if (roleJsonError || !roleJson) {
                    updateStatusBox(@"Parse error");
                    return;
                }

                NSArray *dataArray = roleJson[@"data"];
                if (dataArray.count == 0) {
                    updateStatusBox(@"No data");
                    return;
                }

                NSDictionary *roleInfo = dataArray[0];
                NSString *charName = roleInfo[@"roleName"] ?: @"Unknown";
                NSString *roleId = roleInfo[@"roleId"] ?: @"Unknown";
                NSString *uid = roleInfo[@"userId"] ?: @"Unknown";
                NSString *level = roleInfo[@"level"] ?: @"Unknown";
                NSString *serverId = roleInfo[@"serverId"] ?: @"101";

                // Store info for redeem
                capturedInfo = @{
                    @"roleName": charName,
                    @"roleId": roleId,
                    @"userId": uid,
                    @"level": level,
                    @"serverId": serverId
                };

                NSString *message = [NSString stringWithFormat:
                    @"Name: %@\nRoleID: %@\nUserID: %@\nLvl: %@\nSvr: %@\nGame: A49",
                    charName, roleId, uid, level, serverId];

                hasShownInfo = YES;

                dispatch_async(dispatch_get_main_queue(), ^{
                    updateStatusBox(@"Success!");

                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Info"
                                                                                   message:message
                                                                            preferredStyle:UIAlertControllerStyleAlert];

                    UIAlertAction *copyAction = [UIAlertAction actionWithTitle:@"Copy"
                                                                         style:UIAlertActionStyleDefault
                                                                       handler:^(UIAlertAction * _Nonnull action) {
                        UIPasteboard.generalPasteboard.string = message;
                    }];

                    UIAlertAction *redeemAction = [UIAlertAction actionWithTitle:@"Redeem Codes"
                                                                           style:UIAlertActionStyleDefault
                                                                         handler:^(UIAlertAction * _Nonnull action) {
                        redeemCodes();
                    }];

                    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                                       style:UIAlertActionStyleDefault
                                                                     handler:^(UIAlertAction * _Nonnull action) {
                        removeStatusBox();
                    }];

                    [alert addAction:copyAction];
                    [alert addAction:redeemAction];
                    [alert addAction:okAction];

                    UIViewController *topVC = topMostViewController();
                    if (topVC) {
                        [topVC presentViewController:alert animated:YES completion:nil];
                    }
                });
            }];
            [roleTask resume];
        };

        return %orig(request, wrappedHandler);
    }

    return %orig;
}

%end

%ctor {
    %init;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        createStatusBox();
    });
}
