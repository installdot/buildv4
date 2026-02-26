#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

// ─── Notification Helper ───────────────────────────────────────────────────

static void sendLocalNotification(NSString *title, NSString *body) {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                          completionHandler:^(BOOL granted, NSError *error) {
        if (!granted) return;

        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title = title;
        content.body  = body;
        content.sound = [UNNotificationSound defaultSound];

        UNTimeIntervalNotificationTrigger *trigger =
            [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.1 repeats:NO];

        NSString *identifier = [NSString stringWithFormat:@"hook-%f", [[NSDate date] timeIntervalSince1970]];
        UNNotificationRequest *request =
            [UNNotificationRequest requestWithIdentifier:identifier
                                                 content:content
                                                 trigger:trigger];

        [center addNotificationRequest:request withCompletionHandler:nil];
    }];
}

// ─── Hook UIKeyboard ───────────────────────────────────────────────────────

%hook UIKeyboard

- (void)activate {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        sendLocalNotification(@"🎹 Keyboard Hooked", @"Keyboard is now open and being monitored.");
        NSLog(@"[KeyHook] Keyboard activated");
    });
}

- (void)deactivate {
    %orig;
    NSLog(@"[KeyHook] Keyboard deactivated");
}

%end

// ─── Hook UITextField input ────────────────────────────────────────────────

%hook UITextField

- (void)insertText:(NSString *)text {
    %orig;
    if (text && text.length > 0) {
        NSLog(@"[KeyHook] UITextField input: %@", text);
        sendLocalNotification(@"⌨️ TextField Input", [NSString stringWithFormat:@"User typed: \"%@\"", text]);
    }
}

- (BOOL)deleteBackward {
    BOOL result = %orig;
    NSLog(@"[KeyHook] UITextField: Backspace pressed");
    sendLocalNotification(@"⌫ Backspace", @"User pressed backspace in TextField");
    return result;
}

%end

// ─── Hook UITextView input ─────────────────────────────────────────────────

%hook UITextView

- (void)insertText:(NSString *)text {
    %orig;
    if (text && text.length > 0) {
        NSLog(@"[KeyHook] UITextView input: %@", text);
        sendLocalNotification(@"⌨️ TextView Input", [NSString stringWithFormat:@"User typed: \"%@\"", text]);
    }
}

- (void)deleteBackward {
    %orig;
    NSLog(@"[KeyHook] UITextView: Backspace pressed");
    sendLocalNotification(@"⌫ Backspace", @"User pressed backspace in TextView");
}

%end

// ─── Hook UISearchBar input (bonus) ───────────────────────────────────────

%hook UISearchBar

- (void)insertText:(NSString *)text {
    %orig;
    if (text && text.length > 0) {
        NSLog(@"[KeyHook] UISearchBar input: %@", text);
        sendLocalNotification(@"🔍 SearchBar Input", [NSString stringWithFormat:@"User typed: \"%@\"", text]);
    }
}

%end
