/*
 * KeychainSpy - iOS Keychain Monitor & Dumper Tweak
 * Author: Security Research Tweak
 * Platform: iOS (Jailbroken), Theos + Logos
 *
 * Features:
 *  - Floating button to dump ALL keychain items → Documents/keychain_dump.txt
 *  - Continuous live log of: Add / Read / Update / Delete keychain calls
 *  - Auto-starts on any app launch (via SpringBoard injection or per-app)
 *  - Logs written to Documents/keychain_log.txt
 */

#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <Foundation/Foundation.h>

// ─────────────────────────────────────────────
// MARK: - Logger Helper
// ─────────────────────────────────────────────

@interface KSLogger : NSObject
+ (instancetype)shared;
- (void)log:(NSString *)message;
- (NSString *)logFilePath;
- (NSString *)dumpFilePath;
@end

@implementation KSLogger {
    NSFileHandle *_fileHandle;
    dispatch_queue_t _queue;
}

+ (instancetype)shared {
    static KSLogger *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[KSLogger alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.keychainspy.logger", DISPATCH_QUEUE_SERIAL);
        [self openLogFile];
    }
    return self;
}

- (NSString *)documentsPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths firstObject];
}

- (NSString *)logFilePath {
    return [[self documentsPath] stringByAppendingPathComponent:@"keychain_log.txt"];
}

- (NSString *)dumpFilePath {
    return [[self documentsPath] stringByAppendingPathComponent:@"keychain_dump.txt"];
}

- (void)openLogFile {
    NSString *path = [self logFilePath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        [fm createFileAtPath:path contents:nil attributes:nil];
    }
    _fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    [_fileHandle seekToEndOfFile];

    // Write session start marker
    NSString *header = [NSString stringWithFormat:
        @"\n========================================\n"
        @"[KeychainSpy] Session started: %@\n"
        @"App: %@  PID: %d\n"
        @"========================================\n",
        [NSDate date],
        [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown",
        (int)getpid()
    ];
    [_fileHandle writeData:[header dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)log:(NSString *)message {
    dispatch_async(_queue, ^{
        NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                     dateStyle:NSDateFormatterNoStyle
                                                     timeStyle:NSDateFormatterMediumStyle];
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, message];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        [self->_fileHandle writeData:data];

        // Also print to syslog / Xcode console
        NSLog(@"[KeychainSpy] %@", message);
    });
}

@end

// ─────────────────────────────────────────────
// MARK: - Query → Human-Readable Description
// ─────────────────────────────────────────────

static NSString *DescribeQuery(CFDictionaryRef query) {
    if (!query) return @"(null query)";
    NSDictionary *q = (__bridge NSDictionary *)query;
    NSMutableString *desc = [NSMutableString string];

    // Class
    id cls = q[(__bridge id)kSecClass];
    if (cls) [desc appendFormat:@"class=%@ ", cls];

    // Account / Service / Label
    id account = q[(__bridge id)kSecAttrAccount];
    id service  = q[(__bridge id)kSecAttrService];
    id label    = q[(__bridge id)kSecAttrLabel];
    id accGroup = q[(__bridge id)kSecAttrAccessGroup];
    id server   = q[(__bridge id)kSecAttrServer];

    if (account)  [desc appendFormat:@"account=\"%@\" ", account];
    if (service)  [desc appendFormat:@"service=\"%@\" ", service];
    if (label)    [desc appendFormat:@"label=\"%@\" ",   label];
    if (accGroup) [desc appendFormat:@"accessGroup=%@ ", accGroup];
    if (server)   [desc appendFormat:@"server=%@ ",      server];

    // Value (data) - show hex preview
    id valueData = q[(__bridge id)kSecValueData];
    if ([valueData isKindOfClass:[NSData class]]) {
        NSData *d = (NSData *)valueData;
        // Try UTF-8 first
        NSString *str = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (str) {
            NSString *preview = str.length > 60 ? [str substringToIndex:60] : str;
            [desc appendFormat:@"value(utf8)=\"%@%@\" ", preview, str.length > 60 ? @"…" : @""];
        } else {
            NSString *hex = [d description]; // <aabb cc>
            [desc appendFormat:@"value(hex)=%@ ", hex.length > 40 ? [hex substringToIndex:40] : hex];
        }
    }

    return desc.length ? desc : @"(no notable attrs)";
}

// ─────────────────────────────────────────────
// MARK: - Full Keychain Dump
// ─────────────────────────────────────────────

static void DumpAllKeychainItems(void) {
    KSLogger *logger = [KSLogger shared];
    NSMutableString *report = [NSMutableString string];

    [report appendFormat:@"========================================\n"];
    [report appendFormat:@"KEYCHAIN FULL DUMP\n"];
    [report appendFormat:@"Date : %@\n", [NSDate date]];
    [report appendFormat:@"App  : %@\n", [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown"];
    [report appendFormat:@"========================================\n\n"];

    // All item classes to dump
    NSArray *classes = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];

    NSArray *classNames = @[
        @"GenericPassword",
        @"InternetPassword",
        @"Certificate",
        @"Key",
        @"Identity"
    ];

    for (NSUInteger i = 0; i < classes.count; i++) {
        id secClass   = classes[i];
        NSString *name = classNames[i];

        NSDictionary *query = @{
            (__bridge id)kSecClass            : secClass,
            (__bridge id)kSecMatchLimit        : (__bridge id)kSecMatchLimitAll,
            (__bridge id)kSecReturnAttributes  : @YES,
            (__bridge id)kSecReturnData        : @YES,
            (__bridge id)kSecReturnRef         : @NO
        };

        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

        [report appendFormat:@"── %@ ──\n", name];

        if (status == errSecSuccess && result) {
            NSArray *items = (__bridge_transfer NSArray *)result;
            if (![items isKindOfClass:[NSArray class]]) {
                items = @[(__bridge id)result];
            }

            [report appendFormat:@"  Found %lu item(s)\n", (unsigned long)items.count];

            for (NSDictionary *item in items) {
                [report appendString:@"  ┌─ Item ─────────────────────────────\n"];
                for (NSString *key in item.allKeys) {
                    id val = item[key];

                    // Decode data values
                    if ([val isKindOfClass:[NSData class]]) {
                        NSData *d = (NSData *)val;
                        NSString *strVal = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
                        if (strVal) {
                            [report appendFormat:@"  │  %@ = \"%@\"\n", key, strVal];
                        } else {
                            [report appendFormat:@"  │  %@ = <data:%lu bytes> %@\n",
                                key, (unsigned long)d.length, [d description]];
                        }
                    } else if ([val isKindOfClass:[NSDate class]]) {
                        [report appendFormat:@"  │  %@ = %@\n", key, val];
                    } else {
                        [report appendFormat:@"  │  %@ = %@\n", key, val];
                    }
                }
                [report appendString:@"  └────────────────────────────────────\n"];
            }
        } else if (status == errSecItemNotFound) {
            [report appendString:@"  (no items)\n"];
        } else {
            [report appendFormat:@"  Error: OSStatus %d\n", (int)status];
        }

        [report appendString:@"\n"];
    }

    // Write to dump file
    NSString *dumpPath = [logger dumpFilePath];
    NSError *err = nil;
    BOOL ok = [report writeToFile:dumpPath atomically:YES encoding:NSUTF8StringEncoding error:&err];

    if (ok) {
        [logger log:[NSString stringWithFormat:@"[DUMP] Full dump saved → %@", dumpPath]];
    } else {
        [logger log:[NSString stringWithFormat:@"[DUMP] Write error: %@", err]];
    }
}

// ─────────────────────────────────────────────
// MARK: - Floating Button UI
// ─────────────────────────────────────────────

@interface KSFloatingButton : UIWindow
@end

@implementation KSFloatingButton

- (instancetype)init {
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = nil;
        for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (s.activationState == UISceneActivationStateForegroundActive) {
                scene = s; break;
            }
        }
        self = [super initWithWindowScene:scene ?: (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject]];
    } else {
        self = [super initWithFrame:[UIScreen mainScreen].bounds];
    }

    if (self) {
        self.windowLevel      = UIWindowLevelAlert + 100;
        self.backgroundColor  = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.hidden = NO;

        // ── Floating Panel ──────────────────────────
        UIVisualEffectView *blur = [[UIVisualEffectView alloc]
            initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
        blur.frame = CGRectMake(0, 0, 180, 90);
        blur.layer.cornerRadius = 16;
        blur.clipsToBounds = YES;

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 8, 160, 18)];
        titleLabel.text = @"🔑 KeychainSpy";
        titleLabel.font = [UIFont boldSystemFontOfSize:12];
        titleLabel.textColor = [UIColor colorWithRed:0.4 green:1.0 blue:0.6 alpha:1.0];
        [blur.contentView addSubview:titleLabel];

        // Dump Button
        UIButton *dumpBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        dumpBtn.frame = CGRectMake(10, 32, 160, 34);
        dumpBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.8 blue:0.4 alpha:0.9];
        dumpBtn.layer.cornerRadius = 10;
        dumpBtn.clipsToBounds = YES;
        [dumpBtn setTitle:@"⬇ Dump All Keychain" forState:UIControlStateNormal];
        [dumpBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        dumpBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [dumpBtn addTarget:self action:@selector(onDumpTapped:) forControlEvents:UIControlEventTouchUpInside];
        [blur.contentView addSubview:dumpBtn];

        // Position panel
        CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
        CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
        blur.center = CGPointMake(screenW - 100, screenH * 0.15);

        [self addSubview:blur];

        // Make draggable
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
            initWithTarget:self action:@selector(onPan:)];
        [blur addGestureRecognizer:pan];
        blur.userInteractionEnabled = YES;
    }
    return self;
}

- (void)onDumpTapped:(UIButton *)sender {
    [[KSLogger shared] log:@"[UI] Dump button tapped — starting full dump…"];
    sender.enabled = NO;
    [sender setTitle:@"⏳ Dumping…" forState:UIControlStateNormal];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        DumpAllKeychainItems();
        dispatch_async(dispatch_get_main_queue(), ^{
            [sender setTitle:@"✅ Dump Saved!" forState:UIControlStateNormal];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [sender setTitle:@"⬇ Dump All Keychain" forState:UIControlStateNormal];
                sender.enabled = YES;
            });
        });
    });
}

- (void)onPan:(UIPanGestureRecognizer *)rec {
    UIView *view = rec.view;
    CGPoint delta = [rec translationInView:self];
    view.center = CGPointMake(view.center.x + delta.x, view.center.y + delta.y);
    [rec setTranslation:CGPointZero inView:self];
}

// Allow touches to pass through to underlying app when not on our subviews
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *sub in self.subviews) {
        if (!sub.hidden && [sub pointInside:[self convertPoint:point toView:sub] withEvent:event]) {
            return YES;
        }
    }
    return NO;
}

@end

// ─────────────────────────────────────────────
// MARK: - Logos Hooks  (Security.framework)
// ─────────────────────────────────────────────

%hookf(OSStatus, SecItemAdd, CFDictionaryRef attributes, CFTypeRef *result) {
    NSString *desc = DescribeQuery(attributes);
    [[KSLogger shared] log:[NSString stringWithFormat:@"[ADD]    %@", desc]];
    OSStatus status = %orig;
    [[KSLogger shared] log:[NSString stringWithFormat:@"[ADD]    → status=%d", (int)status]];
    return status;
}

%hookf(OSStatus, SecItemCopyMatching, CFDictionaryRef query, CFTypeRef *result) {
    NSString *desc = DescribeQuery(query);
    [[KSLogger shared] log:[NSString stringWithFormat:@"[READ]   %@", desc]];
    OSStatus status = %orig;
    [[KSLogger shared] log:[NSString stringWithFormat:@"[READ]   → status=%d  result=%@",
        (int)status, result ? (__bridge id)*result : @"nil"]];
    return status;
}

%hookf(OSStatus, SecItemUpdate, CFDictionaryRef query, CFDictionaryRef attrs) {
    NSString *qDesc = DescribeQuery(query);
    NSString *aDesc = DescribeQuery(attrs);
    [[KSLogger shared] log:[NSString stringWithFormat:@"[UPDATE] query: %@  newAttrs: %@", qDesc, aDesc]];
    OSStatus status = %orig;
    [[KSLogger shared] log:[NSString stringWithFormat:@"[UPDATE] → status=%d", (int)status]];
    return status;
}

%hookf(OSStatus, SecItemDelete, CFDictionaryRef query) {
    NSString *desc = DescribeQuery(query);
    [[KSLogger shared] log:[NSString stringWithFormat:@"[DELETE] %@", desc]];
    OSStatus status = %orig;
    [[KSLogger shared] log:[NSString stringWithFormat:@"[DELETE] → status=%d", (int)status]];
    return status;
}

// ─────────────────────────────────────────────
// MARK: - UIApplication Hook → inject UI + start
// ─────────────────────────────────────────────

static KSFloatingButton *gFloatingWindow = nil;

%hook UIApplication

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    BOOL result = %orig;

    [[KSLogger shared] log:@"[LIFECYCLE] application:didFinishLaunchingWithOptions: called"];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!gFloatingWindow) {
            gFloatingWindow = [[KSFloatingButton alloc] init];
        }
    });

    return result;
}

%end

// ─────────────────────────────────────────────
// MARK: - Constructor
// ─────────────────────────────────────────────

%ctor {
    // Hook Security framework functions by symbol
    MSHookFunction((void *)SecItemAdd,         (void *)$replaced$SecItemAdd,         (void **)&$original$SecItemAdd);
    MSHookFunction((void *)SecItemCopyMatching,(void *)$replaced$SecItemCopyMatching,(void **)&$original$SecItemCopyMatching);
    MSHookFunction((void *)SecItemUpdate,      (void *)$replaced$SecItemUpdate,      (void **)&$original$SecItemUpdate);
    MSHookFunction((void *)SecItemDelete,      (void *)$replaced$SecItemDelete,      (void **)&$original$SecItemDelete);

    %init; // Initialize Logos UIApplication hook

    [[KSLogger shared] log:@"[INIT] KeychainSpy loaded and hooks installed ✓"];
    NSLog(@"[KeychainSpy] Injected into: %@", [[NSBundle mainBundle] bundleIdentifier]);
}
