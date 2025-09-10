#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// FIRMessaging delegate callback
%hook AppDelegate

- (void)messaging:(id)messaging didReceiveRegistrationToken:(NSString *)fcmToken {
    %orig; // call original
    
    NSLog(@"🔥 [Hook] Got FCM Token: %@", fcmToken);
    
    // Example: write to file so you can grab it later
    NSString *path = @"/var/mobile/Documents/fcm_token.txt";
    [fcmToken writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

%end
