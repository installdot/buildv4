#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Updated Tweak.xm - Now shows a popup alert on screen with the extracted character details
// instead of just NSLog. Uses UIAlertController (modern iOS) presented from the top view controller.

@interface UIViewController (TopMost)
+ (UIViewController *)topMostViewController;
@end

@implementation UIViewController (TopMost)

+ (UIViewController *)topMostViewController {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) {
        // Fallback to any window if keyWindow is nil (rare on modern iOS)
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
    }
    if (!keyWindow) return nil;

    UIViewController *topVC = keyWindow.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    return topVC;
}

@end

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    if (!completionHandler || !request || !request.URL) {
        return %orig;
    }

    NSString *urlString = request.URL.absoluteString;

    // Intercept the OAuth token response
    if ([urlString hasPrefix:@"https://oauth.vnggames.app/oauth/v1/token"]) {
        void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            completionHandler(data, response, error); // Call original first

            if (error || !data) return;

            NSError *jsonError = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (jsonError || ![json[@"status"] boolValue]) return;

            NSString *userId = json[@"userId"];
            if (!userId || userId.length == 0) return;

            // Trigger the second request
            NSString *roleUrlStr = [NSString stringWithFormat:@"https://vgrapi-sea.vnggames.com/coordinator/api/v1/code/role?gameCode=A49&serverId=101&userIds=%@", userId];
            NSURL *roleUrl = [NSURL URLWithString:roleUrlStr];
            NSMutableURLRequest *roleRequest = [NSMutableURLRequest requestWithURL:roleUrl];
            roleRequest.HTTPMethod = @"GET";
            [roleRequest setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"accept"];
            [roleRequest setValue:@"vi-VN,vi;q=0.9" forHTTPHeaderField:@"accept-language"];

            NSURLSession *session = [NSURLSession sharedSession];
            NSURLSessionDataTask *roleTask = [session dataTaskWithRequest:roleRequest completionHandler:^(NSData *roleData, NSURLResponse *roleResponse, NSError *roleError) {
                if (roleError || !roleData) return;

                NSError *roleJsonError = nil;
                NSDictionary *roleJson = [NSJSONSerialization JSONObjectWithData:roleData options:0 error:&roleJsonError];
                if (roleJsonError) return;

                NSArray *dataArray = roleJson[@"data"];
                if (![dataArray isKindOfClass:[NSArray class]] || dataArray.count == 0) return;

                NSDictionary *roleInfo = dataArray[0];
                NSString *charName = roleInfo[@"roleName"] ?: @"Unknown";
                NSString *roleId = roleInfo[@"roleId"] ?: @"Unknown";
                NSString *uid = roleInfo[@"userId"] ?: @"Unknown";
                NSString *level = roleInfo[@"level"] ?: @"Unknown";
                NSString *serverId = roleInfo[@"serverId"] ?: @"101";

                // Build message string
                NSString *message = [NSString stringWithFormat:
                    @"Character name: %@\n"
                    @"RoleID: %@\n"
                    @"UserID: %@\n"
                    @"Level: %@\n"
                    @"ServerId: %@\n"
                    @"gameCode: A49",
                    charName, roleId, uid, level, serverId];

                // Dispatch to main thread for UI
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIViewController *topVC = [UIViewController topMostViewController];
                    if (!topVC) return;

                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Character Info Extracted"
                                                                                   message:message
                                                                            preferredStyle:UIAlertControllerStyleAlert];

                    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                                       style:UIAlertActionStyleDefault
                                                                     handler:nil];
                    [alert addAction:okAction];

                    [topVC presentViewController:alert animated:YES completion:nil];
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
}
