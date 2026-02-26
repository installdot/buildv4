#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

// ─── UI Alert Helper (for errors only) ────────────────────────────────────

static void showAlert(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;

        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    window = scene.windows.firstObject;
                    break;
                }
            }
        }

        if (!window) {
            window = [UIApplication sharedApplication].keyWindow;
        }

        if (!window) {
            NSLog(@"[KeyHook] ERROR - No window available to show alert: %@ - %@", title, message);
            return;
        }

        UIViewController *rootVC = window.rootViewController;
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:@"Dismiss"
                                                  style:UIAlertActionStyleDestructive
                                                handler:nil]];

        [rootVC presentViewController:alert animated:YES completion:nil];
    });
}

// ─── Notification Helper ───────────────────────────────────────────────────

static void sendLocalNotification(NSString *title, NSString *body) {
    @try {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title = title;
        content.body  = body;
        content.sound = [UNNotificationSound defaultSound];

        UNTimeIntervalNotificationTrigger *trigger =
            [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1 repeats:NO];

        NSString *identifier = [NSString stringWithFormat:@"keyhook-%f", [[NSDate date] timeIntervalSince1970]];
        UNNotificationRequest *request =
            [UNNotificationRequest requestWithIdentifier:identifier
                                                 content:content
                                                 trigger:trigger];

        [center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
            if (error) {
                NSLog(@"[KeyHook] Notification error: %@", error.localizedDescription);
                showAlert(@"❌ Notification Error", [NSString stringWithFormat:@"Failed to send notification.\n\nReason: %@", error.localizedDescription]);
            }
        }];
    } @catch (NSException *exception) {
        NSLog(@"[KeyHook] Exception in sendLocalNotification: %@", exception.reason);
        showAlert(@"💥 Notification Crash", [NSString stringWithFormat:@"Exception: %@\n\nReason: %@", exception.name, exception.reason]);
    }
}

// ─── Request Notification Permission ──────────────────────────────────────

static void requestNotificationPermission() {
    @try {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                              completionHandler:^(BOOL granted, NSError *error) {
            if (error) {
                NSLog(@"[KeyHook] Permission error: %@", error.localizedDescription);
                showAlert(@"❌ Permission Error", [NSString stringWithFormat:@"Could not request notification permission.\n\nReason: %@", error.localizedDescription]);
            } else if (!granted) {
                NSLog(@"[KeyHook] Notification permission denied by user");
                showAlert(@"⚠️ Permission Denied", @"Notification permission was denied.\n\nPlease enable notifications for this app in Settings to receive keyboard hook alerts.");
            } else {
                NSLog(@"[KeyHook] Notification permission granted");
            }
        }];
    } @catch (NSException *exception) {
        NSLog(@"[KeyHook] Exception requesting permission: %@", exception.reason);
        showAlert(@"💥 Permission Crash", [NSString stringWithFormat:@"Exception while requesting permission:\n\n%@", exception.reason]);
    }
}

// ─── Constructor ───────────────────────────────────────────────────────────

%ctor {
    @try {
        NSLog(@"[KeyHook] Tweak loaded into: %@", [[NSBundle mainBundle] bundleIdentifier]);

        dispatch_async(dispatch_get_main_queue(), ^{
            requestNotificationPermission();

            @try {
                [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardDidShowNotification
                                                                  object:nil
                                                                   queue:[NSOperationQueue mainQueue]
                                                              usingBlock:^(NSNotification *note) {
                    @try {
                        NSLog(@"[KeyHook] Keyboard appeared");
                        sendLocalNotification(@"🎹 Keyboard Hooked", @"Keyboard is open and being monitored.");
                    } @catch (NSException *e) {
                        showAlert(@"💥 Keyboard Hook Error", [NSString stringWithFormat:@"Error inside keyboard observer:\n\n%@", e.reason]);
                    }
                }];
            } @catch (NSException *exception) {
                NSLog(@"[KeyHook] Failed to register keyboard observer: %@", exception.reason);
                showAlert(@"❌ Observer Error", [NSString stringWithFormat:@"Failed to register keyboard observer.\n\nReason: %@", exception.reason]);
            }
        });
    } @catch (NSException *exception) {
        NSLog(@"[KeyHook] Fatal error in %%ctor: %@", exception.reason);
        // Can't show alert here safely yet, log only
    }
}

// ─── Hook UITextField ──────────────────────────────────────────────────────

%hook UITextField

- (void)insertText:(NSString *)text {
    @try {
        %orig;
        if (text && text.length > 0) {
            NSLog(@"[KeyHook] UITextField typed: %@", text);
            sendLocalNotification(@"⌨️ Input Detected", [NSString stringWithFormat:@"TextField → Typed: \"%@\"", text]);
        }
    } @catch (NSException *exception) {
        %orig;
        NSLog(@"[KeyHook] UITextField insertText error: %@", exception.reason);
        showAlert(@"❌ TextField Hook Error", [NSString stringWithFormat:@"insertText failed:\n\n%@", exception.reason]);
    }
}

- (void)deleteBackward {
    @try {
        %orig;
        NSLog(@"[KeyHook] UITextField backspace");
        sendLocalNotification(@"⌫ Backspace", @"User deleted a character (TextField)");
    } @catch (NSException *exception) {
        %orig;
        NSLog(@"[KeyHook] UITextField deleteBackward error: %@", exception.reason);
        showAlert(@"❌ TextField Hook Error", [NSString stringWithFormat:@"deleteBackward failed:\n\n%@", exception.reason]);
    }
}

%end

// ─── Hook UITextView ───────────────────────────────────────────────────────

%hook UITextView

- (void)insertText:(NSString *)text {
    @try {
        %orig;
        if (text && text.length > 0) {
            NSLog(@"[KeyHook] UITextView typed: %@", text);
            sendLocalNotification(@"⌨️ Input Detected", [NSString stringWithFormat:@"TextView → Typed: \"%@\"", text]);
        }
    } @catch (NSException *exception) {
        %orig;
        NSLog(@"[KeyHook] UITextView insertText error: %@", exception.reason);
        showAlert(@"❌ TextView Hook Error", [NSString stringWithFormat:@"insertText failed:\n\n%@", exception.reason]);
    }
}

- (void)deleteBackward {
    @try {
        %orig;
        NSLog(@"[KeyHook] UITextView backspace");
        sendLocalNotification(@"⌫ Backspace", @"User deleted a character (TextView)");
    } @catch (NSException *exception) {
        %orig;
        NSLog(@"[KeyHook] UITextView deleteBackward error: %@", exception.reason);
        showAlert(@"❌ TextView Hook Error", [NSString stringWithFormat:@"deleteBackward failed:\n\n%@", exception.reason]);
    }
}

%end

// ─── Hook UISearchTextField (iOS 13+) ─────────────────────────────────────

%hook UISearchTextField

- (void)insertText:(NSString *)text {
    @try {
        %orig;
        if (text && text.length > 0) {
            NSLog(@"[KeyHook] UISearchTextField typed: %@", text);
            sendLocalNotification(@"🔍 Search Input", [NSString stringWithFormat:@"SearchField → Typed: \"%@\"", text]);
        }
    } @catch (NSException *exception) {
        %orig;
        NSLog(@"[KeyHook] UISearchTextField insertText error: %@", exception.reason);
        showAlert(@"❌ SearchField Hook Error", [NSString stringWithFormat:@"insertText failed:\n\n%@", exception.reason]);
    }
}

%end
