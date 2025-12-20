#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Global variables
static UIWindow *infoWindow = nil;
static NSDictionary *capturedInfo = nil;
static NSTimer *monitorTimer = nil;

// Get top-most view controller
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

void updateInfoBox(NSString *title, NSString *message, BOOL showButtons) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (infoWindow) {
            [infoWindow removeFromSuperview];
            infoWindow = nil;
        }

        CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
        infoWindow = [[UIWindow alloc] initWithFrame:CGRectMake(10, 100, screenWidth - 20, 0)];
        infoWindow.windowLevel = UIWindowLevelStatusBar + 1;
        infoWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        infoWindow.layer.cornerRadius = 15;
        infoWindow.layer.masksToBounds = YES;
        infoWindow.layer.borderWidth = 2;
        infoWindow.layer.borderColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0].CGColor;

        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    infoWindow.windowScene = scene;
                    break;
                }
            }
        }

        infoWindow.hidden = NO;

        // Container view
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screenWidth - 20, 0)];
        CGFloat yOffset = 15;

        // Title
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, yOffset, screenWidth - 60, 0)];
        titleLabel.text = title;
        titleLabel.textColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:1.0];
        titleLabel.font = [UIFont boldSystemFontOfSize:16];
        titleLabel.numberOfLines = 0;
        [titleLabel sizeToFit];
        [container addSubview:titleLabel];
        yOffset += titleLabel.frame.size.height + 10;

        // Message
        UILabel *messageLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, yOffset, screenWidth - 60, 0)];
        messageLabel.text = message;
        messageLabel.textColor = [UIColor whiteColor];
        messageLabel.font = [UIFont systemFontOfSize:14];
        messageLabel.numberOfLines = 0;
        [messageLabel sizeToFit];
        [container addSubview:messageLabel];
        yOffset += messageLabel.frame.size.height + 15;

        if (showButtons) {
            // Button container
            UIView *buttonContainer = [[UIView alloc] initWithFrame:CGRectMake(15, yOffset, screenWidth - 60, 40)];
            
            // Copy button
            UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            copyBtn.frame = CGRectMake(0, 0, (screenWidth - 70) / 3 - 5, 40);
            [copyBtn setTitle:@"Copy" forState:UIControlStateNormal];
            [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            copyBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:1.0];
            copyBtn.layer.cornerRadius = 8;
            copyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
            [copyBtn addTarget:copyBtn action:@selector(handleCopyButton) forControlEvents:UIControlEventTouchUpInside];
            [buttonContainer addSubview:copyBtn];

            // Redeem button
            UIButton *redeemBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            redeemBtn.frame = CGRectMake((screenWidth - 70) / 3 + 5, 0, (screenWidth - 70) / 3 - 5, 40);
            [redeemBtn setTitle:@"Redeem" forState:UIControlStateNormal];
            [redeemBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            redeemBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:1.0];
            redeemBtn.layer.cornerRadius = 8;
            redeemBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
            [redeemBtn addTarget:redeemBtn action:@selector(handleRedeemButton) forControlEvents:UIControlEventTouchUpInside];
            [buttonContainer addSubview:redeemBtn];

            // Hide button
            UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            hideBtn.frame = CGRectMake((screenWidth - 70) / 3 * 2 + 10, 0, (screenWidth - 70) / 3, 40);
            [hideBtn setTitle:@"Hide" forState:UIControlStateNormal];
            [hideBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            hideBtn.backgroundColor = [UIColor colorWithRed:0.7 green:0.2 blue:0.2 alpha:1.0];
            hideBtn.layer.cornerRadius = 8;
            hideBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
            [hideBtn addTarget:hideBtn action:@selector(handleHideButton) forControlEvents:UIControlEventTouchUpInside];
            [buttonContainer addSubview:hideBtn];

            [container addSubview:buttonContainer];
            yOffset += 55;
        } else {
            yOffset += 10;
        }

        container.frame = CGRectMake(0, 0, screenWidth - 20, yOffset);
        [infoWindow addSubview:container];
        
        infoWindow.frame = CGRectMake(10, 100, screenWidth - 20, yOffset);
    });
}

void hideInfoBox() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (infoWindow) {
            [infoWindow removeFromSuperview];
            infoWindow = nil;
        }
    });
}

void redeemCodes() {
    if (!capturedInfo) {
        updateInfoBox(@"Error", @"No info captured yet", NO);
        return;
    }

    updateInfoBox(@"Redeem", @"Fetching codes...", NO);

    NSURL *codeUrl = [NSURL URLWithString:@"https://chillysilly.frfrnocap.men/cfcode.php"];
    NSMutableURLRequest *codeRequest = [NSMutableURLRequest requestWithURL:codeUrl];
    codeRequest.HTTPMethod = @"GET";
    codeRequest.timeoutInterval = 10;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:codeRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            updateInfoBox(@"Error", @"Failed to fetch codes", NO);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                hideInfoBox();
            });
            return;
        }

        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json[@"cfcode"]) {
            updateInfoBox(@"Error", @"Invalid code response", NO);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                hideInfoBox();
            });
            return;
        }

        NSArray *allCodes = json[@"cfcode"];
        if (allCodes.count == 0) {
            updateInfoBox(@"Error", @"No codes available", NO);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                hideInfoBox();
            });
            return;
        }

        NSMutableArray *batches = [NSMutableArray array];
        for (NSInteger i = 0; i < allCodes.count; i += 5) {
            NSInteger end = MIN(i + 5, allCodes.count);
            NSArray *batch = [allCodes subarrayWithRange:NSMakeRange(i, end - i)];
            [batches addObject:batch];
        }

        __block NSInteger currentBatch = 0;
        __block NSInteger successCount = 0;
        __block NSInteger failCount = 0;

        typedef void (^RedeemBlock)(void);
        __block RedeemBlock redeemNextBatch;
        
        redeemNextBatch = ^{
            if (currentBatch >= batches.count) {
                NSString *result = [NSString stringWithFormat:@"Completed!\n✓ Success: %ld\n✗ Failed: %ld", (long)successCount, (long)failCount];
                updateInfoBox(@"Redeem Result", result, NO);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    hideInfoBox();
                });
                return;
            }

            NSArray *batch = batches[currentBatch];
            NSString *progress = [NSString stringWithFormat:@"Redeeming batch %ld/%ld...\n✓ %ld  ✗ %ld", 
                (long)(currentBatch + 1), (long)batches.count, (long)successCount, (long)failCount];
            updateInfoBox(@"Redeem", progress, NO);

            NSDictionary *payload = @{
                @"userId": capturedInfo[@"userId"] ?: @"",
                @"serverId": capturedInfo[@"serverId"] ?: @"101",
                @"gameCode": @"A49",
                @"roleId": capturedInfo[@"roleId"] ?: @"",
                @"roleName": capturedInfo[@"roleName"] ?: @"",
                @"level": capturedInfo[@"level"] ?: @"1",
                @"codes": batch
            };

            NSError *payloadError = nil;
            NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&payloadError];
            if (payloadError) {
                failCount += batch.count;
                currentBatch++;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    redeemNextBatch();
                });
                return;
            }

            NSURL *redeemUrl = [NSURL URLWithString:@"https://vgrapi-sea.vnggames.com/coordinator/api/v1/code/redeem-multiple"];
            NSMutableURLRequest *redeemRequest = [NSMutableURLRequest requestWithURL:redeemUrl];
            redeemRequest.HTTPMethod = @"POST";
            redeemRequest.HTTPBody = payloadData;
            redeemRequest.timeoutInterval = 10;

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
                    if (!resultError && result && result[@"data"]) {
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
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    redeemNextBatch();
                });
            }];
            [redeemTask resume];
        };

        redeemNextBatch();
    }];
    [task resume];
}

@interface UIButton (Actions)
- (void)handleCopyButton;
- (void)handleRedeemButton;
- (void)handleHideButton;
@end

@implementation UIButton (Actions)
- (void)handleCopyButton {
    if (capturedInfo) {
        NSString *message = [NSString stringWithFormat:
            @"Name: %@\nRoleID: %@\nUserID: %@\nLvl: %@\nSvr: %@\nGame: A49",
            capturedInfo[@"roleName"] ?: @"Unknown",
            capturedInfo[@"roleId"] ?: @"Unknown",
            capturedInfo[@"userId"] ?: @"Unknown",
            capturedInfo[@"level"] ?: @"Unknown",
            capturedInfo[@"serverId"] ?: @"101"];
        UIPasteboard.generalPasteboard.string = message;
        
        updateInfoBox(@"Copied", @"Info copied to clipboard!", NO);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            hideInfoBox();
        });
    }
}

- (void)handleRedeemButton {
    redeemCodes();
}

- (void)handleHideButton {
    hideInfoBox();
}
@end

void fetchUserInfo(NSString *userId) {
    NSString *roleUrlStr = [NSString stringWithFormat:@"https://vgrapi-sea.vnggames.com/coordinator/api/v1/code/role?gameCode=A49&serverId=101&userIds=%@", userId];
    NSURL *roleUrl = [NSURL URLWithString:roleUrlStr];
    NSMutableURLRequest *roleRequest = [NSMutableURLRequest requestWithURL:roleUrl];
    roleRequest.HTTPMethod = @"GET";
    roleRequest.timeoutInterval = 10;

    [roleRequest setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"accept"];
    [roleRequest setValue:@"vi-VN,vi;q=0.9" forHTTPHeaderField:@"accept-language"];
    [roleRequest setValue:@"VN" forHTTPHeaderField:@"x-client-region"];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    NSURLSessionDataTask *roleTask = [session dataTaskWithRequest:roleRequest completionHandler:^(NSData *roleData, NSURLResponse *roleResponse, NSError *roleError) {
        if (roleError || !roleData) return;

        NSError *roleJsonError = nil;
        NSDictionary *roleJson = [NSJSONSerialization JSONObjectWithData:roleData options:0 error:&roleJsonError];
        if (roleJsonError || !roleJson) return;

        NSArray *dataArray = roleJson[@"data"];
        if (dataArray.count == 0) return;

        NSDictionary *roleInfo = dataArray[0];
        NSString *charName = roleInfo[@"roleName"] ?: @"Unknown";
        NSString *roleId = roleInfo[@"roleId"] ?: @"Unknown";
        NSString *uid = roleInfo[@"userId"] ?: @"Unknown";
        NSString *level = roleInfo[@"level"] ?: @"Unknown";
        NSString *serverId = roleInfo[@"serverId"] ?: @"101";

        capturedInfo = @{
            @"roleName": charName,
            @"roleId": roleId,
            @"userId": uid,
            @"level": level,
            @"serverId": serverId
        };

        NSString *message = [NSString stringWithFormat:
            @"Name: %@\nRoleID: %@\nUserID: %@\nLevel: %@\nServer: %@",
            charName, roleId, uid, level, serverId];

        updateInfoBox(@"Info Captured", message, YES);
    }];
    [roleTask resume];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!completionHandler || !request || !request.URL) {
        return %orig;
    }

    NSString *urlString = request.URL.absoluteString;

    if ([urlString hasPrefix:@"https://oauth.vnggames.app/oauth/v1/token"]) {
        void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            completionHandler(data, response, error);

            if (error || !data) return;

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSError *jsonError = nil;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                if (jsonError || ![json[@"status"] boolValue]) return;

                NSString *userId = json[@"userId"];
                if (!userId || userId.length == 0) return;

                fetchUserInfo(userId);
            });
        };

        return %orig(request, wrappedHandler);
    }

    return %orig;
}

%end

%ctor {
    %init;
}
