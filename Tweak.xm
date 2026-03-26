// Tweak.xm
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface Unitoreios : NSObject
- (void)activehack:(NSString *)title message:(NSString *)message font:(UIFont *)font;
- (void)showOfflineNoticeIfNeeded;
@end

static NSString *getDateString() {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [fmt stringFromDate:[NSDate date]];
}

static void showDebugBanner() {
    // Dùng runtime để tránh lỗi linker
    Class unitoreiosClass = objc_getClass("Unitoreios");
    if (!unitoreiosClass) return;

    id instance = [unitoreiosClass new];
    if (!instance) return;

    NSString *msg = [NSString stringWithFormat:@"Hôm nay là ngày: %@", getDateString()];

    SEL sel = NSSelectorFromString(@"activehack:message:font:");
    if ([instance respondsToSelector:sel]) {
        UIFont *font = [UIFont fontWithName:@"AvenirNext-Bold" size:13];
        ((void (*)(id, SEL, NSString *, NSString *, UIFont *))
            objc_msgSend)(instance, sel, @"Xumod.vn: Đẹp trai có gì sai?", msg, font);
    }
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
        showDebugBanner();
    });
}

%end

%ctor {
    NSLog(@"[UnitoreiosDebug] ctor fired — hooks active");
    %init;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        showDebugBanner();
    });
}
