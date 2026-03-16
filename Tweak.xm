/*
 * KeychainSpy - iOS Keychain Dumper Tweak
 * - Floating draggable button injects into every app
 * - Tap to dump ALL keychain items → <App Documents>/keychain_dump.txt
 * - No auto-logging of keychain calls
 */

#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <Foundation/Foundation.h>

static BOOL gInsideDump = NO;

// ─────────────────────────────────────────────
// MARK: - Dump
// ─────────────────────────────────────────────

static NSString *DocumentsPath(void) {
    return [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
}

static void DumpAllKeychainItems(void) {
    NSMutableString *report = [NSMutableString string];

    [report appendFormat:
        @"========================================\n"
         "KEYCHAIN FULL DUMP\n"
         "Date  : %@\n"
         "Bundle: %@\n"
         "========================================\n\n",
        [NSDate date],
        [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown"];

    gInsideDump = YES;

    CFTypeRef classes[] = {
        kSecClassGenericPassword,
        kSecClassInternetPassword,
        kSecClassCertificate,
        kSecClassKey,
        kSecClassIdentity
    };
    NSArray *names = @[
        @"GenericPassword", @"InternetPassword",
        @"Certificate", @"Key", @"Identity"
    ];

    for (int i = 0; i < 5; i++) {
        [report appendFormat:@"─── %@ ───\n", names[i]];

        NSDictionary *query = @{
            (__bridge id)kSecClass           : (__bridge id)classes[i],
            (__bridge id)kSecMatchLimit       : (__bridge id)kSecMatchLimitAll,
            (__bridge id)kSecReturnAttributes : @YES,
            (__bridge id)kSecReturnData       : @YES
        };

        CFTypeRef cfResult = NULL;
        OSStatus status = SecItemCopyMatching(
            (__bridge CFDictionaryRef)query, &cfResult);

        if (status == errSecSuccess && cfResult) {
            id raw = CFBridgingRelease(cfResult);
            NSArray *items = [raw isKindOfClass:[NSArray class]] ? raw : @[raw];
            [report appendFormat:@"  Count: %lu\n", (unsigned long)items.count];

            for (NSDictionary *item in items) {
                [report appendString:
                    @"  ┌────────────────────────────────────\n"];
                for (NSString *key in item) {
                    id val = item[key];
                    if ([val isKindOfClass:[NSData class]]) {
                        NSData *data = (NSData *)val;
                        NSString *str = [[NSString alloc]
                            initWithData:data
                                encoding:NSUTF8StringEncoding];
                        if (str)
                            [report appendFormat:
                                @"  │ %-28@ = \"%@\"\n", key, str];
                        else
                            [report appendFormat:
                                @"  │ %-28@ = <data %lu B> %@\n",
                                key, (unsigned long)data.length,
                                [data description]];
                    } else {
                        [report appendFormat:
                            @"  │ %-28@ = %@\n", key, val];
                    }
                }
                [report appendString:
                    @"  └────────────────────────────────────\n"];
            }
        } else if (status == errSecItemNotFound) {
            [report appendString:@"  (no items)\n"];
        } else {
            [report appendFormat:@"  OSStatus error: %d\n", (int)status];
        }
        [report appendString:@"\n"];
    }

    gInsideDump = NO;

    NSString *path = [DocumentsPath()
        stringByAppendingPathComponent:@"keychain_dump.txt"];
    NSError *err = nil;
    [report writeToFile:path
             atomically:YES
               encoding:NSUTF8StringEncoding
                  error:&err];
    NSLog(@"[KeychainSpy] Dump → %@  err=%@", path, err);
}

// ─────────────────────────────────────────────
// MARK: - Floating Window
// ─────────────────────────────────────────────

@interface KSWindow : UIWindow
+ (instancetype)create;
@end

@implementation KSWindow

+ (instancetype)create {
    KSWindow *win = nil;

    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] &&
                s.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene *)s; break;
            }
        }
        if (!scene) {
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]]) {
                    scene = (UIWindowScene *)s; break;
                }
            }
        }
        if (scene)
            win = [[KSWindow alloc] initWithWindowScene:scene];
    }

    if (!win)
        win = [[KSWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    win.windowLevel            = UIWindowLevelAlert + 100;
    win.backgroundColor        = [UIColor clearColor];
    win.userInteractionEnabled = YES;
    win.hidden                 = NO;
    win.rootViewController     = [UIViewController new];
    [win buildUI];
    return win;
}

- (void)buildUI {
    UIVisualEffectView *card = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:
            UIBlurEffectStyleSystemThickMaterialDark]];
    card.frame              = CGRectMake(0, 0, 195, 100);
    card.layer.cornerRadius = 16;
    card.layer.borderWidth  = 0.5;
    card.layer.borderColor  =
        [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    card.clipsToBounds      = YES;

    UILabel *lbl = [[UILabel alloc]
        initWithFrame:CGRectMake(12, 9, 171, 18)];
    lbl.text      = @"🔑 KeychainSpy";
    lbl.font      = [UIFont boldSystemFontOfSize:12];
    lbl.textColor =
        [UIColor colorWithRed:0.3 green:1.0 blue:0.5 alpha:1.0];
    [card.contentView addSubview:lbl];

    UIView *sep = [[UIView alloc]
        initWithFrame:CGRectMake(12, 30, 171, 0.5)];
    sep.backgroundColor =
        [UIColor colorWithWhite:1.0 alpha:0.15];
    [card.contentView addSubview:sep];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame              = CGRectMake(10, 36, 175, 36);
    btn.backgroundColor    =
        [UIColor colorWithRed:0.10 green:0.72 blue:0.35 alpha:1.0];
    btn.layer.cornerRadius = 10;
    btn.clipsToBounds      = YES;
    [btn setTitle:@"⬇  Dump All Keychain"
         forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor blackColor]
             forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [btn addTarget:self
            action:@selector(dumpTapped:)
  forControlEvents:UIControlEventTouchUpInside];
    [card.contentView addSubview:btn];

    CGSize screen = [UIScreen mainScreen].bounds.size;
    card.center = CGPointMake(screen.width - 107, 130);
    [self addSubview:card];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    card.userInteractionEnabled = YES;
    [card addGestureRecognizer:pan];
}

- (void)dumpTapped:(UIButton *)btn {
    btn.enabled = NO;
    [btn setTitle:@"⏳  Dumping…" forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1.0];

    dispatch_async(
        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        DumpAllKeychainItems();
        dispatch_async(dispatch_get_main_queue(), ^{
            [btn setTitle:@"✅  Saved to Documents!"
                 forState:UIControlStateNormal];
            btn.backgroundColor =
                [UIColor colorWithRed:0.1 green:0.4 blue:0.9 alpha:1.0];
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(3.0 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                [btn setTitle:@"⬇  Dump All Keychain"
                     forState:UIControlStateNormal];
                btn.backgroundColor =
                    [UIColor colorWithRed:0.10 green:0.72
                                    blue:0.35 alpha:1.0];
                btn.enabled = YES;
            });
        });
    });
}

- (void)handlePan:(UIPanGestureRecognizer *)rec {
    CGPoint d = [rec translationInView:self];
    rec.view.center = CGPointMake(
        rec.view.center.x + d.x,
        rec.view.center.y + d.y);
    [rec setTranslation:CGPointZero inView:self];
}

- (BOOL)pointInside:(CGPoint)pt withEvent:(UIEvent *)event {
    for (UIView *v in self.subviews)
        if (!v.hidden &&
            [v pointInside:[self convertPoint:pt toView:v]
                 withEvent:event])
            return YES;
    return NO;
}

@end

// ─────────────────────────────────────────────
// MARK: - App Hook
// ─────────────────────────────────────────────

static KSWindow *gKSWindow = nil;

%hook UIApplication

- (BOOL)application:(UIApplication *)app
    didFinishLaunchingWithOptions:(NSDictionary *)opts {
    BOOL r = %orig;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            if (!gKSWindow)
                gKSWindow = [KSWindow create];
    });
    return r;
}

%end

// ─────────────────────────────────────────────
// MARK: - Constructor
// ─────────────────────────────────────────────

%ctor {
    %init;
    NSLog(@"[KeychainSpy] Injected → %@",
        [[NSBundle mainBundle] bundleIdentifier]);
}
