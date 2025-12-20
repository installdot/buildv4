#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Global variables to track status and avoid duplicate alerts
static BOOL isCapturing = NO;
static BOOL hasShownInfo = NO;
static UIWindow *statusWindow = nil;

// Create a persistent floating status box
void createStatusBox() {
    if (statusWindow) return;

    statusWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 80, [UIScreen mainScreen].bounds.size.width - 40, 100)];
    statusWindow.windowLevel = UIWindowLevelStatusBar + 1;
    statusWindow.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
    statusWindow.layer.cornerRadius = 12;
    statusWindow.layer.masksToBounds = YES;
    statusWindow.hidden = NO;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(statusWindow.bounds, 15, 10)];
    label.tag = 100;
    label.text = @"🔍 Waiting for login...";
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont boldSystemFontOfSize:17];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    [statusWindow addSubview:label];

    // Make it tappable to dismiss later (optional)
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:nil action:nil];
    [statusWindow addGestureRecognizer:tap];
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

// Helper to get top view controller
UIViewController *topMostViewController() {
    UIWindow *keyWindow = UIApplication.sharedApplication.keyWindow;
    if (!keyWindow) {
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
    }
    UIViewController *topVC = keyWindow.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    return topVC;
}

// Main hook
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!completionHandler || !request || !request.URL) {
        return %orig;
    }

    NSString *urlString = request.URL.absoluteString;

    // Continuously monitor for the OAuth token endpoint
    if ([urlString hasPrefix:@"https://oauth.vnggames.app/oauth/v1/token"]) {
        if (!isCapturing) {
            isCapturing = YES;
            hasShownInfo = NO;
            updateStatusBox(@"🔄 Capturing login response...");
        }

        void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            completionHandler(data, response, error);

            if (error || !data || hasShownInfo) return;

            NSError *jsonError = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (jsonError || ![json[@"status"] boolValue]) return;

            NSString *userId = json[@"userId"];
            if (!userId || userId.length == 0) return;

            updateStatusBox(@"✅ Got UserID!\nFetching character info...");

            // Build role request with required header
            NSString *roleUrlStr = [NSString stringWithFormat:@"https://vgrapi-sea.vnggames.com/coordinator/api/v1/code/role?gameCode=A49&serverId=101&userIds=%@", userId];
            NSURL *roleUrl = [NSURL URLWithString:roleUrlStr];
            NSMutableURLRequest *roleRequest = [NSMutableURLRequest requestWithURL:roleUrl];
            roleRequest.HTTPMethod = @"GET";

            // Required headers (including x-client-region)
            [roleRequest setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"accept"];
            [roleRequest setValue:@"vi-VN,vi;q=0.9" forHTTPHeaderField:@"accept-language"];
            [roleRequest setValue:@"VN" forHTTPHeaderField:@"x-client-region"];  // Added as requested

            NSURLSession *session = [NSURLSession sharedSession];
            NSURLSessionDataTask *roleTask = [session dataTaskWithRequest:roleRequest completionHandler:^(NSData *roleData, NSURLResponse *roleResponse, NSError *roleError) {
                if (roleError || !roleData) {
                    updateStatusBox(@"❌ Failed to fetch role info");
                    return;
                }

                NSError *roleJsonError = nil;
                NSDictionary *roleJson = [NSJSONSerialization JSONObjectWithData:roleData options:0 error:&roleJsonError];
                if (roleJsonError) {
                    updateStatusBox(@"❌ JSON parse error");
                    return;
                }

                NSArray *dataArray = roleJson[@"data"];
                if (dataArray.count == 0) {
                    updateStatusBox(@"❌ No character found");
                    return;
                }

                NSDictionary *roleInfo = dataArray[0];
                NSString *charName = roleInfo[@"roleName"] ?: @"Unknown";
                NSString *roleId = roleInfo[@"roleId"] ?: @"Unknown";
                NSString *uid = roleInfo[@"userId"] ?: @"Unknown";
                NSString *level = roleInfo[@"level"] ?: @"Unknown";
                NSString *serverId = roleInfo[@"serverId"] ?: @"101";

                // Final message for popup
                NSString *message = [NSString stringWithFormat:
                    @"Character name: %@\n"
                    @"RoleID: %@\n"
                    @"UserID: %@\n"
                    @"Level: %@\n"
                    @"ServerId: %@\n"
                    @"gameCode: A49",
                    charName, roleId, uid, level, serverId];

                hasShownInfo = YES;

                dispatch_async(dispatch_get_main_queue(), ^{
                    updateStatusBox(@"✅ Success! Showing info...");

                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Character Info"
                                                                                   message:message
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *copyAction = [UIAlertAction actionWithTitle:@"Copy All"
                                                                         style:UIAlertActionStyleDefault
                                                                       handler:^(UIAlertAction *action) {
                        UIPasteboard.generalPasteboard.string = message;
                    }];
                    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                                       style:UIAlertActionStyleDefault
                                                                     handler:^(UIAlertAction *action) {
                        [self removeStatusBox];
                    }];
                    [alert addAction:copyAction];
                    [alert addAction:okAction];

                    [topMostViewController() presentViewController:alert animated:YES completion:nil];

                    // Auto-hide status box after a few seconds
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [self removeStatusBox];
                    });
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
        createStatusBox();  // Show initial box when app launches
    });
}
