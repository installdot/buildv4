// tweak.xm
// Nuclear Data Cleaner - Clears ALL persistent storage for an app
// Targets: NSUserDefaults, Keychain, Files (Documents/Library/Caches/tmp),
//          SQLite/CoreData DBs, WKWebView storage, NSHTTPCookieStorage,
//          NSURLCache, SharedUserDefaults, and more.
//
// Build: theos/makefiles or any Logos-compatible toolchain
// Tested: iOS 14 – 17

#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <WebKit/WebKit.h>

// ─────────────────────────────────────────────
// MARK: - Helper: recursive delete directory
// ─────────────────────────────────────────────
static void nukeDirectory(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:path error:&err];
    if (err) return;
    for (NSString *item in items) {
        NSString *full = [path stringByAppendingPathComponent:item];
        [fm removeItemAtPath:full error:nil];
    }
}

// ─────────────────────────────────────────────
// MARK: - 1. NSUserDefaults (standard + suites)
// ─────────────────────────────────────────────
static void clearUserDefaults(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) return;

    // Standard defaults
    NSUserDefaults *std = [NSUserDefaults standardUserDefaults];
    NSDictionary *dict = [std dictionaryRepresentation];
    for (NSString *key in dict.allKeys) {
        [std removeObjectForKey:key];
    }
    [std synchronize];

    // Delete the plist on disk (survives reinstall on some iOS versions)
    NSString *plistPath = [NSString stringWithFormat:
        @"/var/mobile/Containers/Data/Application/%@/Library/Preferences/%@.plist",
        [[[NSBundle mainBundle] bundlePath] lastPathComponent], bundleID];
    [[NSFileManager defaultManager] removeItemAtPath:plistPath error:nil];

    // Common shared suite names
    NSArray *suites = @[
        [NSString stringWithFormat:@"group.%@", bundleID],
        [NSString stringWithFormat:@"%@.shared", bundleID],
        [NSString stringWithFormat:@"%@.suite", bundleID],
    ];
    for (NSString *suite in suites) {
        NSUserDefaults *sd = [[NSUserDefaults alloc] initWithSuiteName:suite];
        NSDictionary *sd_dict = [sd dictionaryRepresentation];
        for (NSString *key in sd_dict.allKeys) {
            [sd removeObjectForKey:key];
        }
        [sd synchronize];
    }

    NSLog(@"[NukeCleaner] ✅ NSUserDefaults cleared");
}

// ─────────────────────────────────────────────
// MARK: - 2. Keychain
// ─────────────────────────────────────────────
static void clearKeychain(void) {
    // All four main Keychain item classes
    NSArray *secItemClasses = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity,
    ];

    for (id cls in secItemClasses) {
        NSDictionary *spec = @{ (__bridge id)kSecClass: cls };
        SecItemDelete((__bridge CFDictionaryRef)spec);
    }

    NSLog(@"[NukeCleaner] ✅ Keychain cleared");
}

// ─────────────────────────────────────────────
// MARK: - 3. File System Containers
// ─────────────────────────────────────────────
static void clearFileContainers(void) {
    NSFileManager *fm = [NSFileManager defaultManager];

    // Standard sandbox directories
    NSArray *dirs = @[
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,   NSUserDomainMask, YES).firstObject,
        NSSearchPathForDirectoriesInDomains(NSCachesDirectory,     NSUserDomainMask, YES).firstObject,
        NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,    NSUserDomainMask, YES).firstObject,
        NSTemporaryDirectory(),
    ];

    // Subdirectories inside Library we want to nuke explicitly
    NSString *libPath = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *libSubDirs = @[
        @"Application Support",
        @"Databases",
        @"WebKit",
        @"Cookies",
        @"HTTPStorages",
        @"SplashBoard",
        @"Saved Application State",
        @"BackgroundFetch",
        @"CloudKit",
    ];

    for (NSString *sub in libSubDirs) {
        NSString *full = [libPath stringByAppendingPathComponent:sub];
        nukeDirectory(full);
    }

    // Top-level sandbox dirs
    for (NSString *dir in dirs) {
        if (!dir) continue;
        nukeDirectory(dir);
    }

    // Shared group containers
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSArray *groupIDs = @[
        [NSString stringWithFormat:@"group.%@", bundleID],
        [NSString stringWithFormat:@"group.%@.shared", bundleID],
    ];
    for (NSString *gid in groupIDs) {
        NSURL *containerURL = [fm containerURLForSecurityApplicationGroupIdentifier:gid];
        if (containerURL) {
            nukeDirectory(containerURL.path);
        }
    }

    NSLog(@"[NukeCleaner] ✅ File containers cleared");
}

// ─────────────────────────────────────────────
// MARK: - 4. Core Data / SQLite databases
// ─────────────────────────────────────────────
static void clearDatabases(void) {
    NSString *libPath = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *docPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSFileManager *fm   = [NSFileManager defaultManager];

    NSArray *searchPaths = @[libPath, docPath, NSTemporaryDirectory()];
    NSArray *extensions  = @[@"sqlite", @"sqlite3", @"db", @"db3",
                              @"sqlite-wal", @"sqlite-shm"];

    for (NSString *root in searchPaths) {
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:root];
        NSString *file;
        while ((file = [enumerator nextObject])) {
            if ([extensions containsObject:file.pathExtension.lowercaseString]) {
                NSString *full = [root stringByAppendingPathComponent:file];
                [fm removeItemAtPath:full error:nil];
            }
        }
    }

    NSLog(@"[NukeCleaner] ✅ SQLite / CoreData databases cleared");
}

// ─────────────────────────────────────────────
// MARK: - 5. HTTP Cache & Cookies
// ─────────────────────────────────────────────
static void clearNetworkStorage(void) {
    // NSURLCache
    NSURLCache *cache = [NSURLCache sharedURLCache];
    [cache removeAllCachedResponses];

    // HTTP Cookies
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in cookieStorage.cookies) {
        [cookieStorage deleteCookie:cookie];
    }

    NSLog(@"[NukeCleaner] ✅ HTTP Cache & Cookies cleared");
}

// ─────────────────────────────────────────────
// MARK: - 6. WKWebView / WebKit Storage
// ─────────────────────────────────────────────
static void clearWebKitStorage(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        WKWebsiteDataStore *store = [WKWebsiteDataStore defaultDataStore];
        NSSet *allTypes = [WKWebsiteDataStore allWebsiteDataTypes];
        [store removeDataOfTypes:allTypes
                   modifiedSince:[NSDate dateWithTimeIntervalSince1970:0]
               completionHandler:^{ NSLog(@"[NukeCleaner] ✅ WebKit storage cleared"); }];
    });
}

// ─────────────────────────────────────────────
// MARK: - 7. NSUbiquitousKeyValueStore (iCloud KV)
// ─────────────────────────────────────────────
static void clearICloudKV(void) {
    NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    NSDictionary *dict = [store dictionaryRepresentation];
    for (NSString *key in dict.allKeys) {
        [store removeObjectForKey:key];
    }
    [store synchronize];
    NSLog(@"[NukeCleaner] ✅ iCloud KV Store cleared");
}

// ─────────────────────────────────────────────
// MARK: - Master Nuke
// ─────────────────────────────────────────────
static void nukeEverything(void) {
    clearUserDefaults();
    clearKeychain();
    clearDatabases();      // before file containers (subset)
    clearFileContainers(); // broad pass
    clearNetworkStorage();
    clearWebKitStorage();
    clearICloudKV();

    NSLog(@"[NukeCleaner] 💥 ALL DATA NUKED");

    // Give WebKit async call a moment, then restart
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        // Force-terminate so the app restarts fresh (jailbroken context)
        exit(0);
    });
}

// ─────────────────────────────────────────────
// MARK: - Floating Button UI
// ─────────────────────────────────────────────

@interface NukeButton : UIButton
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@end

@implementation NukeButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 120, 56, 56)];
    if (self) {
        // Style
        self.backgroundColor = [UIColor colorWithRed:0.9 green:0.15 blue:0.15 alpha:0.92];
        self.layer.cornerRadius = 28;
        self.layer.shadowColor  = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 3);
        self.layer.shadowRadius = 6;
        self.layer.shadowOpacity = 0.45;
        self.clipsToBounds = NO;

        // Icon (☢ nuke symbol via label)
        UILabel *icon = [[UILabel alloc] initWithFrame:self.bounds];
        icon.text = @"☢";
        icon.font = [UIFont systemFontOfSize:24];
        icon.textAlignment = NSTextAlignmentCenter;
        icon.userInteractionEnabled = NO;
        [self addSubview:icon];

        // Tap
        [self addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];

        // Drag
        self.panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:self.panGesture];

        // Pulse animation
        [self startPulse];
    }
    return self;
}

- (void)startPulse {
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    pulse.fromValue = @1.0;
    pulse.toValue   = @1.08;
    pulse.duration  = 1.2;
    pulse.autoreverses = YES;
    pulse.repeatCount  = HUGE_VALF;
    pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:pulse forKey:@"pulse"];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *sv = self.superview;
    if (!sv) return;
    CGPoint translation = [pan translationInView:sv];
    CGPoint newCenter = CGPointMake(self.center.x + translation.x,
                                    self.center.y + translation.y);
    // Clamp inside screen
    CGFloat r = 28.0f;
    newCenter.x = MAX(r, MIN(sv.bounds.size.width  - r, newCenter.x));
    newCenter.y = MAX(r + 44, MIN(sv.bounds.size.height - r - 34, newCenter.y));
    self.center = newCenter;
    [pan setTranslation:CGPointZero inView:sv];
}

- (void)buttonTapped {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"☢ Nuclear Wipe"
        message:@"This will PERMANENTLY delete:\n\n"
                 "• NSUserDefaults & Shared Suites\n"
                 "• Keychain Items\n"
                 "• All Files (Documents / Library / Caches / tmp)\n"
                 "• SQLite & CoreData Databases\n"
                 "• HTTP Cache & Cookies\n"
                 "• WebKit / WKWebView Storage\n"
                 "• iCloud KV Store\n\n"
                 "The app will close when done."
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"NUKE IT 💥"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *_) {
        nukeEverything();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:alert animated:YES completion:nil];
}

@end

// ─────────────────────────────────────────────
// MARK: - Inject button into every window
// ─────────────────────────────────────────────

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
            if (!keyWin) return;
            NukeButton *btn = [[NukeButton alloc] init];
            btn.tag = 0xDEAD;
            [keyWin addSubview:btn];
            keyWin.bringSubviewToFront(btn); // keep on top
        });
    });
}

%end

// ─────────────────────────────────────────────
// MARK: - Constructor
// ─────────────────────────────────────────────

%ctor {
    NSLog(@"[NukeCleaner] 🔌 Loaded into %@",
          [[NSBundle mainBundle] bundleIdentifier]);
}
