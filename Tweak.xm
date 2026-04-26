// tweak.xm
// Nuclear Data Cleaner — floating ☢ button always on top via its own UIWindow
// Clears: NSUserDefaults, Keychain, Files, SQLite/CoreData,
//         HTTP Cache, Cookies, WebKit storage, iCloud KV Store
//
// Build: theos / Logos  |  iOS 14+

#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <WebKit/WebKit.h>

// ─────────────────────────────────────────────
// MARK: - Helpers
// ─────────────────────────────────────────────
static void nukeDirectory(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:path error:&err];
    if (err || !items) return;
    for (NSString *item in items)
        [fm removeItemAtPath:[path stringByAppendingPathComponent:item] error:nil];
}

// ─────────────────────────────────────────────
// MARK: - 1. NSUserDefaults
// ─────────────────────────────────────────────
static void clearUserDefaults(void) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSUserDefaults *std = [NSUserDefaults standardUserDefaults];
    for (NSString *k in [[std dictionaryRepresentation] allKeys]) [std removeObjectForKey:k];
    [std synchronize];
    for (NSString *suite in @[[NSString stringWithFormat:@"group.%@", bid],
                               [NSString stringWithFormat:@"%@.shared", bid]]) {
        NSUserDefaults *sd = [[NSUserDefaults alloc] initWithSuiteName:suite];
        for (NSString *k in [[sd dictionaryRepresentation] allKeys]) [sd removeObjectForKey:k];
        [sd synchronize];
    }
    NSLog(@"[NukeCleaner] ✅ NSUserDefaults cleared");
}

// ─────────────────────────────────────────────
// MARK: - 2. Keychain
// ─────────────────────────────────────────────
static void clearKeychain(void) {
    for (id cls in @[(__bridge id)kSecClassGenericPassword,
                     (__bridge id)kSecClassInternetPassword,
                     (__bridge id)kSecClassCertificate,
                     (__bridge id)kSecClassKey,
                     (__bridge id)kSecClassIdentity])
        SecItemDelete((__bridge CFDictionaryRef)@{ (__bridge id)kSecClass: cls });
    NSLog(@"[NukeCleaner] ✅ Keychain cleared");
}

// ─────────────────────────────────────────────
// MARK: - 3. File Containers
// ─────────────────────────────────────────────
static void clearFileContainers(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,  NSUserDomainMask, YES).firstObject;
    NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    for (NSString *sub in @[@"Application Support",@"Databases",@"WebKit",
                             @"Cookies",@"HTTPStorages",@"Caches",
                             @"Saved Application State",@"CloudKit"])
        nukeDirectory([lib stringByAppendingPathComponent:sub]);
    nukeDirectory(doc);
    nukeDirectory(NSTemporaryDirectory());
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSURL *grp = [fm containerURLForSecurityApplicationGroupIdentifier:
                  [NSString stringWithFormat:@"group.%@", bid]];
    if (grp) nukeDirectory(grp.path);
    NSLog(@"[NukeCleaner] ✅ File containers cleared");
}

// ─────────────────────────────────────────────
// MARK: - 4. SQLite / CoreData
// ─────────────────────────────────────────────
static void clearDatabases(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *roots = @[
        NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,  NSUserDomainMask, YES).firstObject,
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject,
        NSTemporaryDirectory(),
    ];
    NSArray *exts = @[@"sqlite",@"sqlite3",@"db",@"db3",@"sqlite-wal",@"sqlite-shm"];
    for (NSString *root in roots)
        for (NSString *file in [fm enumeratorAtPath:root])
            if ([exts containsObject:file.pathExtension.lowercaseString])
                [fm removeItemAtPath:[root stringByAppendingPathComponent:file] error:nil];
    NSLog(@"[NukeCleaner] ✅ Databases cleared");
}

// ─────────────────────────────────────────────
// MARK: - 5. HTTP Cache & Cookies
// ─────────────────────────────────────────────
static void clearNetworkStorage(void) {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    NSHTTPCookieStorage *cs = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *c in cs.cookies) [cs deleteCookie:c];
    NSLog(@"[NukeCleaner] ✅ HTTP Cache & Cookies cleared");
}

// ─────────────────────────────────────────────
// MARK: - 6. WebKit
// ─────────────────────────────────────────────
static void clearWebKitStorage(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[WKWebsiteDataStore defaultDataStore]
            removeDataOfTypes:[WKWebsiteDataStore allWebsiteDataTypes]
                modifiedSince:[NSDate dateWithTimeIntervalSince1970:0]
            completionHandler:^{ NSLog(@"[NukeCleaner] ✅ WebKit cleared"); }];
    });
}

// ─────────────────────────────────────────────
// MARK: - 7. iCloud KV
// ─────────────────────────────────────────────
static void clearICloudKV(void) {
    NSUbiquitousKeyValueStore *kv = [NSUbiquitousKeyValueStore defaultStore];
    for (NSString *k in [[kv dictionaryRepresentation] allKeys]) [kv removeObjectForKey:k];
    [kv synchronize];
    NSLog(@"[NukeCleaner] ✅ iCloud KV cleared");
}

// ─────────────────────────────────────────────
// MARK: - Master Nuke
// ─────────────────────────────────────────────
static void nukeEverything(void) {
    clearUserDefaults();
    clearKeychain();
    clearDatabases();
    clearFileContainers();
    clearNetworkStorage();
    clearWebKitStorage();
    clearICloudKV();
    NSLog(@"[NukeCleaner] 💥 ALL DATA NUKED");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ exit(0); });
}

// ─────────────────────────────────────────────
// MARK: - Passthrough window (lets touches reach app below)
// ─────────────────────────────────────────────
@interface NukePassthroughWindow : UIWindow
@end
@implementation NukePassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // Only intercept touches that land on our own subviews
    return (hit == self) ? nil : hit;
}
@end

// ─────────────────────────────────────────────
// MARK: - Minimal root VC
// ─────────────────────────────────────────────
@interface NukeRootVC : UIViewController
@end
@implementation NukeRootVC
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
}
@end

// ─────────────────────────────────────────────
// MARK: - Draggable nuke button
// ─────────────────────────────────────────────
@interface NukeButton : UIButton
@end
@implementation NukeButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor     = [UIColor colorWithRed:0.88 green:0.10 blue:0.10 alpha:0.93];
    self.layer.cornerRadius  = frame.size.width / 2.0;
    self.layer.shadowColor   = [UIColor blackColor].CGColor;
    self.layer.shadowOffset  = CGSizeMake(0, 4);
    self.layer.shadowRadius  = 8;
    self.layer.shadowOpacity = 0.5;
    self.clipsToBounds       = NO;

    UILabel *lbl = [[UILabel alloc] initWithFrame:self.bounds];
    lbl.text            = @"☢";
    lbl.font            = [UIFont systemFontOfSize:26];
    lbl.textAlignment   = NSTextAlignmentCenter;
    lbl.userInteractionEnabled = NO;
    [self addSubview:lbl];

    [self addTarget:self action:@selector(onTap)
   forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [self addGestureRecognizer:pan];

    // Pulse animation
    CABasicAnimation *a  = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    a.fromValue          = @(1.0);
    a.toValue            = @(1.08);
    a.duration           = 1.3;
    a.autoreverses       = YES;
    a.repeatCount        = HUGE_VALF;
    a.timingFunction     = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:a forKey:@"pulse"];

    return self;
}

- (void)onPan:(UIPanGestureRecognizer *)pan {
    UIView *sv = self.superview;
    if (!sv) return;
    CGPoint t = [pan translationInView:sv];
    CGFloat r = self.bounds.size.width / 2.0;
    self.center = CGPointMake(
        MIN(MAX(self.center.x + t.x, r), sv.bounds.size.width  - r),
        MIN(MAX(self.center.y + t.y, r + 50), sv.bounds.size.height - r - 40)
    );
    [pan setTranslation:CGPointZero inView:sv];
}

- (void)onTap {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"☢ Nuclear Wipe"
        message:
            @"Will permanently erase:\n\n"
             "• NSUserDefaults & shared suites\n"
             "• All Keychain items\n"
             "• Documents / Library / Caches / tmp\n"
             "• SQLite & CoreData databases\n"
             "• HTTP Cache & Cookies\n"
             "• WebKit / WKWebView storage\n"
             "• iCloud KV Store\n\n"
             "App will close when finished."
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"💥 NUKE IT"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *_) { nukeEverything(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}
@end

// ─────────────────────────────────────────────
// MARK: - Install overlay window
// ─────────────────────────────────────────────
static NukePassthroughWindow *gOverlayWindow = nil;

static void installOverlayWindow(void) {
    if (gOverlayWindow) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        // Find active UIWindowScene
        UIWindowScene *scene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                scene = (UIWindowScene *)s;
                if (s.activationState == UISceneActivationStateForegroundActive) break;
            }
        }

        NukePassthroughWindow *win;
        if (scene) {
            win = [[NukePassthroughWindow alloc] initWithWindowScene:scene];
        } else {
            win = [[NukePassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }

        win.windowLevel            = UIWindowLevelAlert + 100;
        win.backgroundColor        = [UIColor clearColor];
        win.userInteractionEnabled = YES;
        win.hidden                 = NO;

        NukeRootVC *vc = [[NukeRootVC alloc] init];
        win.rootViewController = vc;

        // Position button bottom-left, above home indicator
        CGRect s = [UIScreen mainScreen].bounds;
        CGFloat sz = 58.0;
        NukeButton *btn = [[NukeButton alloc] initWithFrame:
            CGRectMake(16, s.size.height - sz - 80, sz, sz)];
        [vc.view addSubview:btn];

        gOverlayWindow = win;
        NSLog(@"[NukeCleaner] 🪟 Overlay window installed, level=%f", win.windowLevel);
    });
}

// ─────────────────────────────────────────────
// MARK: - Hook: applicationDidBecomeActive
// ─────────────────────────────────────────────
%hook UIApplication

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            installOverlayWindow();
        });
    });
}

%end

// ─────────────────────────────────────────────
// MARK: - Constructor
// ─────────────────────────────────────────────
%ctor {
    NSLog(@"[NukeCleaner] 🔌 Loaded — %@",
          [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown");

    // Belt-and-suspenders: also try after 3 seconds
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        installOverlayWindow();
    });
}
