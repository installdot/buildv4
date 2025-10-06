#import <UIKit/UIKit.h>
#import <DeviceCheck/DeviceCheck.h>
#import <UserNotifications/UserNotifications.h>

@interface UIWindow (Overlay)
@end

@implementation UIWindow (Overlay)

- (void)layoutSubviews {
    [super layoutSubviews];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Optional overlay button (for manual trigger)
        UIButton *overlayButton = [UIButton buttonWithType:UIButtonTypeSystem];
        overlayButton.frame = CGRectMake(50, 100, 180, 40);
        [overlayButton setTitle:@"Generate Token" forState:UIControlStateNormal];
        overlayButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        overlayButton.tintColor = [UIColor whiteColor];
        overlayButton.layer.cornerRadius = 8;
        overlayButton.clipsToBounds = YES;
        [overlayButton addTarget:self
                          action:@selector(_generateAndSendToken)
                forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:overlayButton];

        // 🔔 Ask for notification permissions & start the debug loop
        [self _setupRepeatingTokenSender];
    });
}

#pragma mark - 🔔 Setup repeating notifications

- (void)_setupRepeatingTokenSender {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                          completionHandler:^(BOOL granted, NSError * _Nullable error) {
        if (granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self _scheduleRepeatingNotificationAndToken];
            });
        }
    }];
}

- (void)_scheduleRepeatingNotificationAndToken {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center removeAllPendingNotificationRequests];

    // ⏱️ Debug trigger every 10 seconds
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:10 repeats:YES];

    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Auto Device Token (Debug)";
    content.body = @"Generating and sending new token...";
    content.sound = [UNNotificationSound defaultSound];

    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"auto_token_debug"
                                                                          content:content
                                                                          trigger:trigger];
    [center addNotificationRequest:request withCompletionHandler:nil];

    // Immediately trigger first token generation
    [self _generateAndSendToken];

    // 🔁 Repeat every 10 s using NSTimer for active debugging
    [NSTimer scheduledTimerWithTimeInterval:10
                                     target:self
                                   selector:@selector(_generateAndSendToken)
                                   userInfo:nil
                                    repeats:YES];
}

#pragma mark - 🧩 Generate + Send Token

- (void)_generateAndSendToken {
    if (![DCDevice currentDevice].isSupported) {
        [self _showNotificationWithTitle:@"Error" body:@"DeviceCheck not supported"];
        return;
    }

    [[DCDevice currentDevice] generateTokenWithCompletionHandler:^(NSData * _Nullable data, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [self _showNotificationWithTitle:@"DeviceCheck Error" body:error.localizedDescription];
                return;
            }

            if (data) {
                NSString *token = [data base64EncodedStringWithOptions:0];
                [UIPasteboard generalPasteboard].string = token; // optional for debug

                NSURL *url = [NSURL URLWithString:@"https://chillysilly.frfrnocap.men/tokenlapi.php"];
                NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
                req.HTTPMethod = @"POST";
                [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

                NSDictionary *json = @{@"token": token};
                NSData *body = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
                req.HTTPBody = body;

                [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (error) {
                            [self _showNotificationWithTitle:@"Send Failed" body:error.localizedDescription];
                        } else {
                            [self _showNotificationWithTitle:@"Token Sent!" body:token];
                        }
                    });
                }] resume];
            }
        });
    }];
}

#pragma mark - 🔔 Helper: Show Local Notification

- (void)_showNotificationWithTitle:(NSString *)title body:(NSString *)body {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = title;
    content.body = body;
    content.sound = [UNNotificationSound defaultSound];

    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1 repeats:NO];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[NSString stringWithFormat:@"notif_%@", title]
                                                                          content:content
                                                                          trigger:trigger];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
}

@end
