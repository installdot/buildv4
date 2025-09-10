#import <UIKit/UIKit.h>
#import <DeviceCheck/DeviceCheck.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end

%hook AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig;

    if (@available(iOS 11.0, *)) {
        if ([DCDevice currentDevice].isSupported) {
            [[DCDevice currentDevice] generateTokenWithCompletionHandler:^(NSData * _Nullable token, NSError * _Nullable error) {
                if (token && !error) {
                    NSString *base64 = [token base64EncodedStringWithOptions:0];
                    NSLog(@"[Tweak] Device token: %@", base64);

                    dispatch_async(dispatch_get_main_queue(), ^{
                        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Send Device Token"
                                                                                       message:@"Do you want to send your device token to the server?"
                                                                                preferredStyle:UIAlertControllerStyleAlert];

                        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel"
                                                                         style:UIAlertActionStyleCancel
                                                                       handler:nil];

                        UIAlertAction *accept = [UIAlertAction actionWithTitle:@"Accept"
                                                                         style:UIAlertActionStyleDefault
                                                                       handler:^(UIAlertAction * _Nonnull action) {
                            // Build POST request
                            NSURL *url = [NSURL URLWithString:@"https://chillysilly.frfrnocap.men/dtoken.php"];
                            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
                            [request setHTTPMethod:@"POST"];

                            NSString *body = [NSString stringWithFormat:@"token=%@", base64];
                            [request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
                            [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

                            NSURLSession *session = [NSURLSession sharedSession];
                            [[session dataTaskWithRequest:request] resume];
                        }];

                        [alert addAction:cancel];
                        [alert addAction:accept];

                        // Present alert on topmost view controller
                        UIWindow *window = UIApplication.sharedApplication.keyWindow;
                        UIViewController *rootVC = window.rootViewController;
                        while (rootVC.presentedViewController) {
                            rootVC = rootVC.presentedViewController;
                        }
                        [rootVC presentViewController:alert animated:YES completion:nil];
                    });
                } else {
                    NSLog(@"[Tweak] Failed to generate token: %@", error);
                }
            }];
        }
    }

    return result;
}

%end
