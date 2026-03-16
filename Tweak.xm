/*
 * KeychainSpy - iOS Keychain Monitor & Dumper Tweak
 * Platform: iOS (Jailbroken), Theos + Logos
 *
 * Features:
 *  - Floating draggable button to dump ALL keychain items
 *    → <App Documents>/keychain_dump.txt
 *  - Continuous live log of Add / Read / Update / Delete calls
 *    → <App Documents>/keychain_log.txt
 *  - Auto-runs on every app launch via dylib injection
 */

#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <Foundation/Foundation.h>

// ─────────────────────────────────────────────
// MARK: - Logger
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
    dispatch_once(&onceToken, ^{ instance = [self new]; });
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
    return [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
}
- (NSString *)logFilePath  { return [[self documentsPath] stringByAppendingPathComponent:@"keychain_log.txt"];  }
- (NSString *)dumpFilePath { return [[self documentsPath] stringByAppendingPathComponent:@"keychain_dump.txt"]; }

- (void)openLogFile {
    NSString *path = [self logFilePath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path])
        [fm createFileAtPath:path contents:nil attributes:nil];

    _fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    [_fileHandle seekToEndOfFile];

    NSString *header = [NSString stringWithFormat:
        @"\n========================================\n"
         "[KeychainSpy] Session start: %@\n"
         "Bundle: %@  PID: %d\n"
         "========================================\n",
        [NSDate date],
        [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown",
        (int)getpid()];
    [_fileHandle writeData:[header dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)log:(NSString *)message {
    dispatch_async(_queue, ^{
        NSString *ts = [NSDateFormatter
            localizedStringFromDate:[NSDate date]
                          dateStyle:NSDateFormatterNoStyle
                          timeStyle:NSDateFormatterMediumStyle];
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, message];
        [self->_fileHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        NSLog(@"[KeychainSpy] %@", message);
    });
}

@end

// ─────────────────────────────────────────────
// MARK: - Query Description Helper
// ─────────────────────────────────────────────

static NSString *DescribeQuery(CFDictionaryRef query) {
    if (!query) return @"(null query)";
    NSDictionary *q = (__bridge NSDictionary *)query;
    NSMutableString *desc = [NSMutableString string];

    id cls      = q[(__bridge id)kSecClass];
    id account  = q[(__bridge id)kSecAttrAccount];
    id service  = q[(__bridge id)kSecAttrService];
    id label    = q[(__bridge id)kSecAttrLabel];
    id accGroup = q[(__bridge id)kSecAttrAccessGroup];
    id server   = q[(__bridge id)kSecAttrServer];
    id valueData= q[(__bridge id)kSecValueData];

    if (cls)      [desc appendFormat:@"class=%@ ",       cls];
    if (account)  [desc appendFormat:@"account=\"%@\" ", account];
    if (service)  [desc appendFormat:@"service=\"%@\" ", service];
    if (label)    [desc appendFormat:@"label=\"%@\" ",   label];
    if (accGroup) [desc appendFormat:@"group=%@ ",       accGroup];
    if (server)   [desc appendFormat:@"server=%@ ",      server];

    if ([valueData isKindOfClass:[NSData class]]) {
        NSData *d = (NSData *)valueData;
        NSString *str = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (str) {
            NSString *preview = (str.length > 64) ? [str substringToIndex:64] : str;
            [desc appendFormat:@"value(utf8)=\"%@%@\" ",
                preview, (str.length > 64) ? @"…" : @""];
        } else {
            NSString *hex = [d description];
            [desc appendFormat:@"value(hex)=%@ ",
                (hex.length > 40) ? [hex substringToIndex:40] : hex];
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
    [report appendFormat:
        @"========================================\n"
         "KEYCHAIN FULL DUMP\n"
         "Date  : %@\n"
         "Bundle: %@\n"
         "========================================\n\n",
        [NSDate date],
        [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown"];

    CFTypeRef classes[] = {
        kSecClassGenericPassword,
        kSecClassInternetPassword,
        kSecClassCertificate,
        kSecClassKey,
        kSecClassIdentity
    };
    NSArray *classNames = @[
        @"GenericPassword", @"InternetPassword",
        @"Certificate", @"Key", @"Identity"
    ];

    for (int i = 0; i < 5; i++) {
        [report appendFormat:@"── %@ ──\n", classNames[i]];

        NSDictionary *query = @{
            (__bridge id)kSecClass            : (__bridge id)classes[i],
            (__bridge id)kSecMatchLimit        : (__bridge id)kSecMatchLimitAll,
            (__bridge id)kSecReturnAttributes  : @YES,
            (__bridge id)kSecReturnData        : @YES
        };

        CFTypeRef cfResult = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &cfResult);

        if (status == errSecSuccess && cfResult) {
            // Use CFBridgingRelease instead of __bridge_transfer (works with/without ARC)
            id rawResult = CFBridgingRelease(cfResult);
            NSArray *items = [rawResult isKindOfClass:[NSArray class]]
                ? (NSArray *)rawResult : @[rawResult];

            [report appendFormat:@"  Found %lu item(s)\n", (unsigned long)items.count];

            for (NSDictionary *item in items) {
                [report appendString:@"  ┌─────────────────────────────────────\n"];
                for (NSString *key in item.allKeys) {
                    id val = item[key];
                    if ([val isKindOfClass:[NSData class]]) {
                        NSData *d = (NSData *)val;
                        NSString *str = [[NSString alloc]
                            initWithData:d encoding:NSUTF8StringEncoding];
                        if (str)
                            [report appendFormat:@"  │  %@ = \"%@\"\n", key, str];
                        else
                            [report appendFormat:@"  │  %@ = <data %lu bytes> %@\n",
                                key, (unsigned long)d.length, [d description]];
                    } else {
                        [report appendFormat:@"  │  %@ = %@\n", key, val];
                    }
                }
                [report appendString:@"  └─────────────────────────────────────\n"];
            }
        } else if (status == errSecItemNotFound) {
            [report appendString:@"  (no items)\n"];
        } else {
            [report appendFormat:@"  Error OSStatus: %d\n", (int)status];
        }
        [report appendString:@"\n"];
    }

    NSString *path = [logger dumpFilePath];
    NSError *err = nil;
    if ([report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err])
        [logger log:[NSString stringWithFormat:@"[DUMP] Saved → %@", path]];
    else
        [logger log:[NSString stringWithFormat:@"[DUMP] Write error: %@", err]];
}

// ─────────────────────────────────────────────
// MARK: - Floating Button Window
// ─────────────────────────────────────────────

@interface KSFloatingWindow : UIWindow
@end

@implementation KSFloatingWindow

- (instancetype)init {
    if (@available(iOS 13.0, *)) {
        UIWindowScene *target = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                target = (UIWindowScene *)scene;
                break;
            }
        }
        if (!target)
            target = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
        self = [super initWithWindowScene:target];
    } else {
        self = [super initWithFrame:[UIScreen mainScreen].bounds];
    }

    if (self) {
        self.windowLevel         = UIWindowLevelAlert + 100;
        self.backgroundColor     = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.hidden              = NO;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    // Blur container
    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
    blur.frame = CGRectMake(0, 0, 190, 96);
    blur.layer.cornerRadius  = 16;
    blur.layer.borderWidth   = 0.5;
    blur.layer.borderColor   = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
    blur.clipsToBounds       = YES;

    // Title label
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 8, 170, 18)];
    title.text      = @"🔑 KeychainSpy";
    title.font      = [UIFont boldSystemFontOfSize:12];
    title.textColor = [UIColor colorWithRed:0.35 green:1.0 blue:0.55 alpha:1.0];
    [blur.contentView addSubview:title];

    // Dump button
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(10, 33, 170, 36);
    btn.backgroundColor      = [UIColor colorWithRed:0.12 green:0.75 blue:0.38 alpha:0.95];
    btn.layer.cornerRadius   = 10;
    btn.clipsToBounds        = YES;
    [btn setTitle:@"⬇  Dump All Keychain" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    btn.titleLabel.font      = [UIFont boldSystemFontOfSize:12];
    [btn addTarget:self action:@selector(dumpTapped:) forControlEvents:UIControlEventTouchUpInside];
    [blur.contentView addSubview:btn];

    // Initial position — top-right
    CGSize screen = [UIScreen mainScreen].bounds.size;
    blur.center = CGPointMake(screen.width - 105, screen.height * 0.14);
    [self addSubview:blur];

    // Drag support
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    blur.userInteractionEnabled = YES;
    [blur addGestureRecognizer:pan];
}

- (void)dumpTapped:(UIButton *)sender {
    [[KSLogger shared] log:@"[UI] Dump button tapped — starting full dump…"];
    sender.enabled = NO;
    [sender setTitle:@"⏳  Dumping…" forState:UIControlStateNormal];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        DumpAllKeychainItems();
        dispatch_async(dispatch_get_main_queue(), ^{
            [sender setTitle:@"✅  Saved!" forState:UIControlStateNormal];
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    [sender setTitle:@"⬇  Dump All Keychain" forState:UIControlStateNormal];
                    sender.enabled = YES;
            });
        });
    });
}

- (void)handlePan:(UIPanGestureRecognizer *)rec {
    UIView *v     = rec.view;
    CGPoint delta = [rec translationInView:self];
    v.center = CGPointMake(v.center.x + delta.x, v.center.y + delta.y);
    [rec setTranslation:CGPointZero inView:self];
}

// Pass touches through when not over our subviews
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *sub in self.subviews)
        if (!sub.hidden &&
            [sub pointInside:[self convertPoint:point toView:sub] withEvent:event])
            return YES;
    return NO;
}

@end

// ─────────────────────────────────────────────
// MARK: - Logos Hooks  (let %hookf + %init handle everything)
// ─────────────────────────────────────────────

%hookf(OSStatus, SecItemAdd, CFDictionaryRef attributes, CFTypeRef *result) {
    [[KSLogger shared] log:[NSString stringWithFormat:@"[ADD]    %@", DescribeQuery(attributes)]];
    OSStatus s = %orig;
    [[KSLogger shared] log:[NSString stringWithFormat:@"[ADD]    → status=%d", (int)s]];
    return s;
}

%hookf(OSStatus, SecItemCopyMatching, CFDictionaryRef query, CFTypeRef *result) {
    [[KSLogger shared] log:[NSString stringWithFormat:@"[READ]   %@", DescribeQuery(query)]];
    OSStatus s = %orig;
    [[KSLogger shared] log:[NSString stringWithFormat:@"[READ]   → status=%d", (int)s]];
    return s;
}

%hookf(OSStatus, SecItemUpdate, CFDictionaryRef query, CFDictionaryRef attrs) {
    [[KSLogger shared] log:[NSString stringWithFormat:@"[UPDATE] query:%@  newAttrs:%@",
        DescribeQuery(query), DescribeQuery(attrs)]];
    OSStatus s = %orig;
    [[KSLogger shared] log:[NSString stringWithFormat:@"[UPDATE] → status=%d", (int)s]];
    return s;
}

%hookf(OSStatus, SecItemDelete, CFDictionaryRef query) {
    [[KSLogger shared] log:[NSString stringWithFormat:@"[DELETE] %@", DescribeQuery(query)]];
    OSStatus s = %orig;
    [[KSLogger shared] log:[NSString stringWithFormat:@"[DELETE] → status=%d", (int)s]];
    return s;
}

// ─────────────────────────────────────────────
// MARK: - App Lifecycle Hook
// ─────────────────────────────────────────────

static KSFloatingWindow *gWindow = nil;

%hook UIApplication

- (BOOL)application:(UIApplication *)app
    didFinishLaunchingWithOptions:(NSDictionary *)opts {
    BOOL result = %orig;
    [[KSLogger shared] log:@"[LIFECYCLE] application:didFinishLaunchingWithOptions:"];
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            if (!gWindow)
                gWindow = [KSFloatingWindow new];
    });
    return result;
}

%end

// ─────────────────────────────────────────────
// MARK: - Constructor
// %hookf macros + %init() handle all hooking automatically.
// NO manual MSHookFunction needed.
// ─────────────────────────────────────────────

%ctor {
    // %init initialises all %hook / %hookf blocks defined above
    %init;
    [[KSLogger shared] log:@"[INIT] KeychainSpy loaded — all hooks active ✓"];
    NSLog(@"[KeychainSpy] Injected → %@", [[NSBundle mainBundle] bundleIdentifier]);
}
