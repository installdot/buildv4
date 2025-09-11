#import <UIKit/UIKit.h>
#import <DeviceCheck/DeviceCheck.h>

@interface UIWindow (Overlay)
@end

@implementation UIWindow (Overlay)

- (void)layoutSubviews {
    [super layoutSubviews];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIButton *overlayButton = [UIButton buttonWithType:UIButtonTypeSystem];
        overlayButton.frame = CGRectMake(50, 100, 180, 40);
        [overlayButton setTitle:@"Generate Token" forState:UIControlStateNormal];
        overlayButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        overlayButton.tintColor = [UIColor whiteColor];
        overlayButton.layer.cornerRadius = 8;
        overlayButton.clipsToBounds = YES;

        [overlayButton addTarget:self
                          action:@selector(_generateDeviceCheckToken)
                forControlEvents:UIControlEventTouchUpInside];

        [self addSubview:overlayButton];
    });
}

- (void)_generateDeviceCheckToken {
    if (![DCDevice currentDevice].isSupported) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
            message:@"DeviceCheck not supported"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
        return;
    }

    [[DCDevice currentDevice] generateTokenWithCompletionHandler:^(NSData * _Nullable data, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *msg;
            if (error) {
                msg = [NSString stringWithFormat:@"Error: %@", error.localizedDescription];
            } else if (data) {
                NSString *token = [data base64EncodedStringWithOptions:0];
                msg = [NSString stringWithFormat:@"Token:\n%@", token];

                // copy to clipboard
                [UIPasteboard generalPasteboard].string = token;

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
                        NSString *alertMsg;
                        if (error) {
                            alertMsg = [NSString stringWithFormat:@"Send failed: %@", error.localizedDescription];
                        } else {
                            alertMsg = [NSString stringWithFormat:@"Token sent!\n%@", token];
                        }

                        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Device Token"
                            message:alertMsg
                            preferredStyle:UIAlertControllerStyleAlert];
                        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
                    });
                }] resume];
            }
        });
    }];
}

@end
