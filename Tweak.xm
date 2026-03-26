// Tweak.xm
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@interface Unitoreios : NSObject
- (void)activehack:(NSString *)title message:(NSString *)message font:(UIFont *)font;
- (void)showOfflineNoticeIfNeeded;
@end

static NSString *getDateString() {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [fmt stringFromDate:[NSDate date]];
}

%hook Unitoreios

- (BOOL)isNetworkAvailable {
    return NO;
}

- (BOOL)canUseCachedSession {
    return YES;
}

- (void)showOfflineNoticeIfNeeded {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSString *msg = [NSString stringWithFormat:@"Hôm nay là ngày: %@", getDateString()];
        [self activehack:@"DEBUG: Offline mode - dev"
                 message:msg
                    font:[UIFont fontWithName:@"AvenirNext-Bold" size:13]];
    });
}

%end

%ctor {
    NSLog(@"[UnitoreiosDebug] ctor fired — hooks active");
    %init;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSString *msg = [NSString stringWithFormat:@"Hôm nay là ngày: %@", getDateString()];
        Unitoreios *instance = [Unitoreios new];
        [instance activehack:@"Xumod: Crack:3"
                     message:msg
                        font:[UIFont fontWithName:@"AvenirNext-Bold" size:13]];
    });
}
