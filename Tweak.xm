#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Global variables
static BOOL isCapturing = NO;
static BOOL hasShownInfo = NO;
static UIWindow *statusWindow = nil;

// Create persistent floating status box (smaller size)
void createStatusBox() {
    if (statusWindow) return;

    // Smaller frame: width 80% of screen, height 60
    statusWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 80, UIScreen.mainScreen.bounds.size.width * 0.8, 60)];
    statusWindow.windowLevel = UIWindowLevelStatusBar + 1;
    statusWindow.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
    statusWindow.layer.cornerRadius = 12;
    statusWindow.layer.masksToBounds = YES;

    // Modern scene handling
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

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!completionHandler || !request || !request.URL) {
        return %orig;
    }

    NSString *urlString = request.URL.absoluteString;

    if ([urlString hasPrefix:@"https://oauth.vnggames.app/oauth/v1/token"]) {
        // Continuous monitoring: always reset on new request
        isCapturing = YES;
        hasShownInfo = NO;
        updateStatusBox(@"Capturing...");

        void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            // Call original without any app-side triggers
            %orig(request, completionHandler);  // Ensure original behavior is preserved exactly

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

            // Use a separate session to avoid triggering app detection
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

                    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                                       style:UIAlertActionStyleDefault
                                                                     handler:^(UIAlertAction * _Nonnull action) {
                        removeStatusBox();
                    }];

                    [alert addAction:copyAction];
                    [alert addAction:okAction];

                    UIViewController *topVC = topMostViewController();
                    if (topVC) {
                        [topVC presentViewController:alert animated:YES completion:nil];
                    }

                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        removeStatusBox();
                    });
                });
            }];
            [roleTask resume];
        };

        // Return orig with wrapped handler for interception without altering app flow
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
