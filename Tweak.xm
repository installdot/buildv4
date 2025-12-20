#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Global variables
static UIWindow *infoWindow = nil;
static UIWindow *toggleButton = nil;
static NSDictionary *capturedInfo = nil;
static NSString *lastUserId = nil;
static CGPoint dragOffset;

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
        btn.layer.cornerRadius = 30;
        btn.layer.borderWidth = 2;
        btn.layer.borderColor = [UIColor whiteColor].CGColor;
        [btn setTitle:@"📱" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:28];
        [btn addTarget:btn action:@selector(handleToggleButton) forControlEvents:UIControlEventTouchUpInside];
        [toggleButton addSubview:btn];

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
    if (!capturedInfo || !capturedInfo[@"userId"]) {
        updateInfoBox(@"Error", @"No userId", NO);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            hideInfoBox();
        });
        return;
    }

    updateInfoBox(@"Redeem", @"Processing...", NO);

    NSString *urlString = [NSString stringWithFormat:@"https://chillysilly.frfrnocap.men/gifttool.php?userid=%@", capturedInfo[@"userId"]];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 30;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            updateInfoBox(@"Error", @"Request failed", NO);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                hideInfoBox();
            });
            return;
        }

        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json) {
            updateInfoBox(@"Error", @"Invalid response", NO);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                hideInfoBox();
            });
            return;
        }

        // Check if success
        if ([json[@"status"] isEqualToString:@"success"]) {
            NSDictionary *userDetail = json[@"userDetail"];
            if (userDetail) {
                capturedInfo = @{
                    @"roleName": userDetail[@"roleName"] ?: @"Unknown",
                    @"roleId": userDetail[@"roleId"] ?: @"Unknown",
                    @"userId": userDetail[@"userId"] ?: @"Unknown",
                    @"level": userDetail[@"level"] ?: @"1",
                    @"serverId": userDetail[@"serverId"] ?: @"101"
                };
            }

            NSString *message = json[@"message"] ?: @"Done!";
            NSString *redeemed = json[@"redeemed"] ? [NSString stringWithFormat:@"\nRedeemed: %@", json[@"redeemed"]] : @"";
            
            updateInfoBox(@"Success", [NSString stringWithFormat:@"%@%@", message, redeemed], NO);
        } else {
            NSString *message = json[@"message"] ?: @"Failed";
            updateInfoBox(@"Error", message, NO);
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            hideInfoBox();
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

void showUserInfo(NSString *userId) {
    capturedInfo = @{
        @"userId": userId
    };

    NSString *message = [NSString stringWithFormat:@"UserID: %@", userId];
    hideToggleButton();
    updateInfoBox(@"Mochi•Teyvat", message, YES);
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

                    if ([userId isEqualToString:lastUserId]) return;
                    
                    lastUserId = [userId copy];
                    showUserInfo(userId);
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
