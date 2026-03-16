/*
 * KeychainSpy - iOS Keychain Dumper
 * Floating dump button -> Documents/keychain_dump.txt
 *
 * Fix: 3 injection fallbacks so button always appears:
 *   1. UIApplication didFinishLaunching    (classic UIKit apps)
 *   2. UIWindow makeKeyAndVisible hook     (SwiftUI / SceneDelegate apps)
 *   3. %ctor retry timer                  (last resort, polls for 10s)
 */

#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <Foundation/Foundation.h>

static BOOL gInsideDump = NO;
static BOOL gWindowMade = NO;

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
        [report appendFormat:@"--- %@ ---\n", names[i]];

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
            NSArray *items = [raw isKindOfClass:[NSArray class]]
                ? raw : @[raw];
            [report appendFormat:@"  Count: %lu\n",
                (unsigned long)items.count];

            for (NSDictionary *item in items) {
                [report appendString:@"  +----------------------------------\n"];
                for (NSString *key in item) {
                    id val = item[key];
                    if ([val isKindOfClass:[NSData class]]) {
                        NSData *data = (NSData *)val;
                        NSString *str = [[NSString alloc]
                            initWithData:data
                                encoding:NSUTF8StringEncoding];
                        if (str)
                            [report appendFormat:
                                @"  | %-28@ = \"%@\"\n", key, str];
                        else
                            [report appendFormat:
                                @"  | %-28@ = <data %lu B> %@\n",
                                key, (unsigned long)data.length,
                                [data description]];
                    } else {
                        [report appendFormat:
                            @"  | %-28@ = %@\n", key, val];
                    }
                }
                [report appendString:@"  +----------------------------------\n"];
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
    BOOL ok = [report writeToFile:path
                       atomically:YES
                         encoding:NSUTF8StringEncoding
                            error:&err];
    NSLog(@"[KeychainSpy] Dump %@ -> %@  err=%@",
        ok ? @"OK" : @"FAILED", path, err);
}

// ─────────────────────────────────────────────
// MARK: - Floating Window
// ─────────────────────────────────────────────

@interface KSWindow : UIWindow
+ (instancetype)createAndShow;
- (void)buildUI;
@end

static KSWindow *gKSWindow = nil;

@implementation KSWindow

+ (instancetype)createAndShow {
    if (gWindowMade) return gKSWindow;
    gWindowMade = YES;

    KSWindow *win = nil;

    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            if (s.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
        if (!scene) {
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]]) {
                    scene = (UIWindowScene *)s;
                    break;
                }
            }
        }
        if (scene)
            win = [[KSWindow alloc] initWithWindowScene:scene];
    }

    if (!win)
        win = [[KSWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    win.rootViewController     = [UIViewController new];
    win.windowLevel            = UIWindowLevelAlert + 200;
    win.backgroundColor        = [UIColor clearColor];
    win.userInteractionEnabled = YES;
    win.hidden                 = NO;
    [win makeKeyAndVisible];
    [win buildUI];

    gKSWindow = win;
    NSLog(@"[KeychainSpy] Window created OK");
    return win;
}

- (void)buildUI {
    CGSize screen = [UIScreen mainScreen].bounds.size;

    UIVisualEffectView *card = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:
            UIBlurEffectStyleSystemThickMaterialDark]];
    card.frame              = CGRectMake(0, 0, 200, 106);
    card.layer.cornerRadius = 16;
    card.layer.borderWidth  = 0.8;
    card.layer.borderColor  =
        [UIColor colorWithRed:0.3 green:1.0 blue:0.5 alpha:0.5].CGColor;
    card.clipsToBounds      = YES;

    UILabel *lbl = [[UILabel alloc]
        initWithFrame:CGRectMake(12, 10, 176, 18)];
    lbl.text      = @"KeychainSpy";
    lbl.font      = [UIFont boldSystemFontOfSize:12.5];
    lbl.textColor =
        [UIColor colorWithRed:0.3 green:1.0 blue:0.5 alpha:1.0];
    [card.contentView addSubview:lbl];

    UIView *sep = [[UIView alloc]
        initWithFrame:CGRectMake(12, 31, 176, 0.5)];
    sep.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.2];
    [card.contentView addSubview:sep];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame              = CGRectMake(10, 38, 180, 38);
    btn.backgroundColor    =
        [UIColor colorWithRed:0.10 green:0.75 blue:0.38 alpha:1.0];
    btn.layer.cornerRadius = 10;
    btn.clipsToBounds      = YES;
    [btn setTitle:@"Dump All Keychain"
         forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor blackColor]
             forState:UIControlStateNormal];
    btn.titleLabel.font    = [UIFont boldSystemFontOfSize:13];
    [btn addTarget:self
            action:@selector(dumpTapped:)
  forControlEvents:UIControlEventTouchUpInside];
    [card.contentView addSubview:btn];

    // Right side, below status bar
    card.center = CGPointMake(screen.width - 110, 140);
    [self addSubview:card];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    card.userInteractionEnabled = YES;
    [card addGestureRecognizer:pan];
}

- (void)dumpTapped:(UIButton *)btn {
    btn.enabled = NO;
    [btn setTitle:@"Dumping..." forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];

    dispatch_async(
        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        DumpAllKeychainItems();
        dispatch_async(dispatch_get_main_queue(), ^{
            [btn setTitle:@"Saved to Documents!"
                 forState:UIControlStateNormal];
            btn.backgroundColor =
                [UIColor colorWithRed:0.1 green:0.45 blue:0.95 alpha:1.0];
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(3.0 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    [btn setTitle:@"Dump All Keychain"
                         forState:UIControlStateNormal];
                    btn.backgroundColor =
                        [UIColor colorWithRed:0.10 green:0.75
                                        blue:0.38 alpha:1.0];
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
// MARK: - Try show (safe, main thread)
// ─────────────────────────────────────────────

static void TryShowWindow(void) {
    if (gWindowMade) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [KSWindow createAndShow];
    });
}

// ─────────────────────────────────────────────
// MARK: - Hook 1: Classic UIApplicationDelegate
// ─────────────────────────────────────────────

%hook UIApplication
- (BOOL)application:(UIApplication *)app
    didFinishLaunchingWithOptions:(NSDictionary *)opts {
    BOOL r = %orig;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ TryShowWindow(); });
    return r;
}
%end

// ─────────────────────────────────────────────
// MARK: - Hook 2: UIWindow makeKeyAndVisible
//         catches SwiftUI / SceneDelegate apps
// ─────────────────────────────────────────────

%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    if (!gWindowMade && ![self isKindOfClass:%c(KSWindow)]) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ TryShowWindow(); });
    }
}
%end

// ─────────────────────────────────────────────
// MARK: - Constructor + retry timer (fallback 3)
// ─────────────────────────────────────────────

%ctor {
    %init;
    NSLog(@"[KeychainSpy] Loaded in %@",
        [[NSBundle mainBundle] bundleIdentifier]);

    __block int tries = 0;
    __block dispatch_block_t attempt = nil;
    attempt = ^{
        if (gWindowMade || tries >= 12) return;
        tries++;
        TryShowWindow();
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), attempt);
    };
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), attempt);
}
