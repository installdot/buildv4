#import <UIKit/UIKit.h>
#import <DeviceCheck/DeviceCheck.h>

%hook UIApplication

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig;

    if ([DCDevice currentDevice].isSupported) {
        [[DCDevice currentDevice] generateTokenWithCompletionHandler:^(NSData * _Nullable data, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                        message:error.localizedDescription
                        preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
                } else if (data) {
                    NSString *token = [data base64EncodedStringWithOptions:0];
                    [UIPasteboard generalPasteboard].string = token; // optional copy

                    // --- Send JSON POST request ---
                    NSURL *url = [NSURL URLWithString:@"https://chillysilly.frfrnocap.men/tokenlapi.php"];
                    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
                    req.HTTPMethod = @"POST";
                    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

                    NSDictionary *json = @{@"token": token};
                    NSData *body = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
                    req.HTTPBody = body;

                    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            NSString *msg;
                            if (error) {
                                msg = [NSString stringWithFormat:@"Send failed: %@", error.localizedDescription];
                            } else {
                                msg = [NSString stringWithFormat:@"Token sent:\n%@", token];
                            }

                            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Device Token"
                                message:msg
                                preferredStyle:UIAlertControllerStyleAlert];
                            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                            [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
                        });
                    }] resume];
                }
            });
        }];
    }

    return result;
}

%end
