#import <UIKit/UIKit.h>
#import <DeviceCheck/DeviceCheck.h>

@interface UIWindow (Overlay)
@end

@implementation UIWindow (Overlay)

- (void)layoutSubviews {
    [super layoutSubviews];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // === Floating Label near home bar ===
        UILabel *floatingLabel = [[UILabel alloc] initWithFrame:CGRectMake(20,
                                                                           self.bounds.size.height - 60,
                                                                           self.bounds.size.width - 40,
                                                                           30)];
        floatingLabel.text = @"Tool by MochiTeyvat";
        floatingLabel.textAlignment = NSTextAlignmentCenter;
        floatingLabel.textColor = [UIColor whiteColor];
        floatingLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
        floatingLabel.layer.cornerRadius = 8;
        floatingLabel.clipsToBounds = YES;
        floatingLabel.font = [UIFont boldSystemFontOfSize:14];
        floatingLabel.userInteractionEnabled = NO;
        floatingLabel.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
        [self addSubview:floatingLabel];

        // === Popup on App Open ===
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIAlertController *welcome = [UIAlertController alertControllerWithTitle:@"Tool by MochiTeyvat"
                                                                             message:@"Chào mừng bạn đã mở ứng dụng!"
                                                                      preferredStyle:UIAlertControllerStyleAlert];
            [welcome addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:welcome
                                                                                         animated:YES
                                                                                       completion:nil];
        });

        // === Generate Token Button ===
        UIButton *generateButton = [UIButton buttonWithType:UIButtonTypeSystem];
        generateButton.frame = CGRectMake(50, 100, 180, 40);
        [generateButton setTitle:@"Generate Token" forState:UIControlStateNormal];
        generateButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        generateButton.tintColor = [UIColor whiteColor];
        generateButton.layer.cornerRadius = 8;
        generateButton.clipsToBounds = YES;
        [generateButton addTarget:self action:@selector(_generateDeviceCheckToken)
                 forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:generateButton];

        // === Set URL Button ===
        UIButton *urlButton = [UIButton buttonWithType:UIButtonTypeSystem];
        urlButton.frame = CGRectMake(50, 150, 180, 40);
        [urlButton setTitle:@"Set URL" forState:UIControlStateNormal];
        urlButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        urlButton.tintColor = [UIColor whiteColor];
        urlButton.layer.cornerRadius = 8;
        urlButton.clipsToBounds = YES;
        [urlButton addTarget:self action:@selector(_setCustomURL)
             forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:urlButton];
    });
}

#pragma mark - File Helpers

- (NSString *)_urlFilePath {
    NSString *docDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [docDir stringByAppendingPathComponent:@"server_url.txt"];
}

- (void)_saveURLToFile:(NSString *)url {
    NSString *path = [self _urlFilePath];
    [url writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (NSString *)_loadURLFromFile {
    NSString *path = [self _urlFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    }
    return nil;
}

#pragma mark - Set URL

- (void)_setCustomURL {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Set URL"
                                                                   message:@"Enter the server URL"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        NSString *saved = [self _loadURLFromFile];
        if (saved) textField.text = saved;
        textField.placeholder = @"https://example.com/token.php";
    }];

    UIAlertAction *saveAction = [UIAlertAction actionWithTitle:@"Save"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
        NSString *inputURL = alert.textFields.firstObject.text;
        if (inputURL.length > 0) {
            [self _saveURLToFile:inputURL];

            NSString *msg = [NSString stringWithFormat:@"Current URL: %@", inputURL];
            UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Saved!"
                                                                             message:msg
                                                                      preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:confirm
                                                                                         animated:YES
                                                                                       completion:nil];
        }
    }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];

    [alert addAction:saveAction];
    [alert addAction:cancelAction];

    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert
                                                                                 animated:YES
                                                                               completion:nil];
}

#pragma mark - Generate Token

- (void)_generateDeviceCheckToken {
    if (![DCDevice currentDevice].isSupported ) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                       message:@"DeviceCheck not supported"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
        return;
    }

    [[DCDevice currentDevice] generateTokenWithCompletionHandler:^(NSData * _Nullable data, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSString *msg = [NSString stringWithFormat:@"Error: %@", error.localizedDescription];
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:msg
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
                return;
            }

            if (data) {
                NSString *token = [data base64EncodedStringWithOptions:0];
                [UIPasteboard generalPasteboard].string = token; // Copy to clipboard

                NSString *urlString = [self _loadURLFromFile];
                if (!urlString) {
                    urlString = @"https://chillysilly.frfrnocap.men/tokenlapi.php"; // default fallback
                }

                NSURL *url = [NSURL URLWithString:urlString];
                NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
                req.HTTPMethod = @"POST";
                [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

                NSDictionary *json = @{@"device_token": token};
                NSData *body = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
                req.HTTPBody = body;

                [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSString *msg;
                        if (error) {
                            msg = [NSString stringWithFormat:@"Send failed: %@", error.localizedDescription];
                        } else {
                            msg = [NSString stringWithFormat:@"Cảm ơn bạn đã sử dụng!\nTool by MochiTeyvat"];
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

@end
