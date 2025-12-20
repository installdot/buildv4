#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Global variables
static UIWindow *infoWindow = nil;
static UIWindow *toggleButton = nil;
static NSDictionary *capturedInfo = nil;
static NSString *lastUserId = nil;
static CGPoint dragOffset;

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

void showToggleButton() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (toggleButton) {
            toggleButton.hidden = NO;
            return;
        }

        toggleButton = [[UIWindow alloc] initWithFrame:CGRectMake(20, 150, 60, 60)];
        toggleButton.windowLevel = UIWindowLevelStatusBar + 2;
        toggleButton.backgroundColor = [UIColor clearColor];

        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    toggleButton.windowScene = scene;
                    break;
                }
            }
        }

        toggleButton.hidden = NO;

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(0, 0, 60, 60);
        btn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
        btn.layer.cornerRadius = 15;
        btn.layer.borderWidth = 2;
        btn.layer.borderColor = [UIColor whiteColor].CGColor;
        [btn setTitle:@"Mochi" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:28];
        [btn addTarget:btn action:@selector(handleToggleButton) forControlEvents:UIControlEventTouchUpInside];
        [toggleButton addSubview:btn];

        // Add pan gesture
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:toggleButton action:@selector(handlePan:)];
        [toggleButton addGestureRecognizer:pan];
    });
}

void hideToggleButton() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (toggleButton) {
            toggleButton.hidden = YES;
        }
    });
}

void updateInfoBox(NSString *title, NSString *message, BOOL showButtons) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (infoWindow) {
            [infoWindow removeFromSuperview];
            infoWindow = nil;
        }

        CGFloat boxWidth = 140;
        CGFloat screenHeight = UIScreen.mainScreen.bounds.size.height;
        
        infoWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, screenHeight / 2 - 100, boxWidth, 0)];
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

        // Add pan gesture for dragging
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:infoWindow action:@selector(handlePan:)];
        [infoWindow addGestureRecognizer:pan];

        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, boxWidth, 0)];
        CGFloat yOffset = 12;

        // Title
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, yOffset, boxWidth - 20, 0)];
        titleLabel.text = title;
        titleLabel.textColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:1.0];
        titleLabel.font = [UIFont boldSystemFontOfSize:13];
        titleLabel.numberOfLines = 0;
        [titleLabel sizeToFit];
        CGRect titleFrame = titleLabel.frame;
        titleFrame.size.width = boxWidth - 20;
        titleLabel.frame = titleFrame;
        [container addSubview:titleLabel];
        yOffset += titleLabel.frame.size.height + 8;

        // Message
        UILabel *messageLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, yOffset, boxWidth - 20, 0)];
        messageLabel.text = message;
        messageLabel.textColor = [UIColor whiteColor];
        messageLabel.font = [UIFont systemFontOfSize:11];
        messageLabel.numberOfLines = 0;
        [messageLabel sizeToFit];
        CGRect msgFrame = messageLabel.frame;
        msgFrame.size.width = boxWidth - 20;
        messageLabel.frame = msgFrame;
        [container addSubview:messageLabel];
        yOffset += messageLabel.frame.size.height + 12;

        if (showButtons) {
            // Copy button
            UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            copyBtn.frame = CGRectMake(10, yOffset, boxWidth - 20, 32);
            [copyBtn setTitle:@"Copy" forState:UIControlStateNormal];
            [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            copyBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:1.0];
            copyBtn.layer.cornerRadius = 6;
            copyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
            [copyBtn addTarget:copyBtn action:@selector(handleCopyButton) forControlEvents:UIControlEventTouchUpInside];
            [container addSubview:copyBtn];
            yOffset += 38;

            // Redeem button
            UIButton *redeemBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            redeemBtn.frame = CGRectMake(10, yOffset, boxWidth - 20, 32);
            [redeemBtn setTitle:@"Redeem" forState:UIControlStateNormal];
            [redeemBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            redeemBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:1.0];
            redeemBtn.layer.cornerRadius = 6;
            redeemBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
            [redeemBtn addTarget:redeemBtn action:@selector(handleRedeemButton) forControlEvents:UIControlEventTouchUpInside];
            [container addSubview:redeemBtn];
            yOffset += 38;

            // Hide button
            UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            hideBtn.frame = CGRectMake(10, yOffset, boxWidth - 20, 32);
            [hideBtn setTitle:@"Hide" forState:UIControlStateNormal];
            [hideBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            hideBtn.backgroundColor = [UIColor colorWithRed:0.7 green:0.2 blue:0.2 alpha:1.0];
            hideBtn.layer.cornerRadius = 6;
            hideBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
            [hideBtn addTarget:hideBtn action:@selector(handleHideButton) forControlEvents:UIControlEventTouchUpInside];
            [container addSubview:hideBtn];
            yOffset += 40;
        } else {
            yOffset += 8;
        }

        container.frame = CGRectMake(0, 0, boxWidth, yOffset);
        [infoWindow addSubview:container];
        
        infoWindow.frame = CGRectMake(infoWindow.frame.origin.x, infoWindow.frame.origin.y, boxWidth, yOffset);
    });
}

void hideInfoBox() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (infoWindow) {
            [infoWindow removeFromSuperview];
            infoWindow = nil;
        }
        showToggleButton();
    });
}

void redeemCodes() {
    if (!capturedInfo) {
        updateInfoBox(@"Error", @"No info yet", NO);
        return;
    }

    updateInfoBox(@"Redeem", @"Fetching...", NO);

    NSURL *codeUrl = [NSURL URLWithString:@"https://chillysilly.frfrnocap.men/cfcode.php"];
    NSMutableURLRequest *codeRequest = [NSMutableURLRequest requestWithURL:codeUrl];
    codeRequest.HTTPMethod = @"GET";
    codeRequest.timeoutInterval = 15;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:codeRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            updateInfoBox(@"Error", @"Fetch failed", NO);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                hideInfoBox();
            });
            return;
        }

        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json[@"cfcode"]) {
            updateInfoBox(@"Error", @"Invalid data", NO);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                hideInfoBox();
            });
            return;
        }

        NSArray *allCodes = json[@"cfcode"];
        if (allCodes.count == 0) {
            updateInfoBox(@"Error", @"No codes", NO);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                hideInfoBox();
            });
            return;
        }

        // Split into batches of 5
        NSMutableArray *batches = [NSMutableArray array];
        for (NSInteger i = 0; i < allCodes.count; i += 5) {
            NSInteger end = MIN(i + 5, allCodes.count);
            NSArray *batch = [allCodes subarrayWithRange:NSMakeRange(i, end - i)];
            [batches addObject:batch];
        }

        __block NSInteger sent = 0;
        NSInteger total = batches.count;

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            for (NSArray *batch in batches) {
                @autoreleasepool {
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
                        sent++;
                        continue;
                    }

                    NSURL *redeemUrl = [NSURL URLWithString:@"https://vgrapi-sea.vnggames.com/coordinator/api/v1/code/redeem-multiple"];
                    NSMutableURLRequest *redeemRequest = [NSMutableURLRequest requestWithURL:redeemUrl];
                    redeemRequest.HTTPMethod = @"POST";
                    redeemRequest.HTTPBody = payloadData;
                    redeemRequest.timeoutInterval = 10;

                    [redeemRequest setValue:@"application/json" forHTTPHeaderField:@"content-type"];
                    [redeemRequest setValue:@"VN" forHTTPHeaderField:@"x-client-region"];
                    [redeemRequest setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"accept"];
                    [redeemRequest setValue:@"https://giftcode.vnggames.com" forHTTPHeaderField:@"origin"];
                    [redeemRequest setValue:@"https://giftcode.vnggames.com/" forHTTPHeaderField:@"referer"];
                    [redeemRequest setValue:[[NSUUID UUID] UUIDString] forHTTPHeaderField:@"x-request-id"];

                    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

                    NSURLSessionDataTask *redeemTask = [session dataTaskWithRequest:redeemRequest completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                        sent++;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            updateInfoBox(@"Redeem", [NSString stringWithFormat:@"Sent %ld/%ld", (long)sent, (long)total], NO);
                        });
                        dispatch_semaphore_signal(semaphore);
                    }];
                    [redeemTask resume];

                    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
                    [NSThread sleepForTimeInterval:0.5];
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                updateInfoBox(@"Done", [NSString stringWithFormat:@"Sent %ld batches", (long)total], NO);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    hideInfoBox();
                });
            });
        });
    }];
    [task resume];
}

@interface UIButton (Actions)
- (void)handleCopyButton;
- (void)handleRedeemButton;
- (void)handleHideButton;
- (void)handleToggleButton;
@end

@implementation UIButton (Actions)
- (void)handleCopyButton {
    if (capturedInfo) {
        NSString *message = [NSString stringWithFormat:
            @"Name: %@\nRoleID: %@\nUserID: %@\nLvl: %@\nSvr: %@",
            capturedInfo[@"roleName"] ?: @"?",
            capturedInfo[@"roleId"] ?: @"?",
            capturedInfo[@"userId"] ?: @"?",
            capturedInfo[@"level"] ?: @"?",
            capturedInfo[@"serverId"] ?: @"101"];
        UIPasteboard.generalPasteboard.string = message;
        
        updateInfoBox(@"Copied", @"Copied!", NO);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
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

- (void)handleToggleButton {
    hideToggleButton();
    if (capturedInfo) {
        NSString *message = [NSString stringWithFormat:
            @"Name: %@\nRole: %@\nUser: %@\nLv: %@\nSv: %@",
            capturedInfo[@"roleName"] ?: @"?",
            capturedInfo[@"roleId"] ?: @"?",
            capturedInfo[@"userId"] ?: @"?",
            capturedInfo[@"level"] ?: @"?",
            capturedInfo[@"serverId"] ?: @"101"];
        updateInfoBox(@"Info", message, YES);
    } else {
        updateInfoBox(@"Waiting", @"No data yet", NO);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            hideInfoBox();
        });
    }
}
@end

@interface UIWindow (Drag)
- (void)handlePan:(UIPanGestureRecognizer *)recognizer;
@end

@implementation UIWindow (Drag)
- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    CGPoint translation = [recognizer translationInView:self.superview];
    CGPoint center = self.center;
    
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        dragOffset = CGPointMake(center.x - self.frame.origin.x, center.y - self.frame.origin.y);
    }
    
    center.x += translation.x;
    center.y += translation.y;
    self.center = center;
    
    [recognizer setTranslation:CGPointZero inView:self.superview];
}
@end

void fetchUserInfo(NSString *userId) {
    if ([userId isEqualToString:lastUserId]) {
        return;
    }
    
    lastUserId = [userId copy];
    
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
        if (!dataArray || dataArray.count == 0) return;

        NSDictionary *roleInfo = dataArray[0];
        
        capturedInfo = @{
            @"roleName": roleInfo[@"roleName"] ?: @"Unknown",
            @"roleId": roleInfo[@"roleId"] ?: @"Unknown",
            @"userId": roleInfo[@"userId"] ?: @"Unknown",
            @"level": roleInfo[@"level"] ?: @"1",
            @"serverId": roleInfo[@"serverId"] ?: @"101"
        };

        NSString *message = [NSString stringWithFormat:
            @"Name: %@\nRole: %@\nUser: %@\nLv: %@\nSv: %@",
            capturedInfo[@"roleName"],
            capturedInfo[@"roleId"],
            capturedInfo[@"userId"],
            capturedInfo[@"level"],
            capturedInfo[@"serverId"]];

        hideToggleButton();
        updateInfoBox(@"Mochi•Teyvat", message, YES);
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
                @autoreleasepool {
                    NSError *jsonError = nil;
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                    if (jsonError) return;
                    
                    if (![json[@"status"] boolValue]) return;

                    NSString *userId = json[@"userId"];
                    if (!userId || userId.length == 0) return;

                    fetchUserInfo(userId);
                }
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
