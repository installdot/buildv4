/*
 * KeychainSpy — Network Interceptor + Keychain Dumper + UDID Patcher
 *
 * Load order:
 *   1. ksNetworkInit()  __attribute__((constructor(101)))
 *      → registers NSURLProtocol IMMEDIATELY, before any app code runs
 *      → no hook, no delay, intercept is live from first byte
 *
 *   2. %ctor  (Logos constructor, runs after all __attribute__ constructors)
 *      → registers Logos hooks
 *      → spawns overlay after 1.5s
 *
 * Intercept target : https://app.tnspike.com:2087/verify_udid
 * Spoofed response : VIP · 100yr · legit dates · dynamic day count
 *
 * Random UDID (generated): 00008020-F41FCBF78457528B
 */

#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <Foundation/Foundation.h>

// =============================================================================
//  MARK: - Constants
// =============================================================================

static NSString *const kInterceptHost  = @"app.tnspike.com";
static NSString *const kInterceptPath  = @"/verify_udid";
static NSString *const kHandledKey     = @"KSSpoofHandled";

#define kTargetService   @"com.tnnguy.auth"
#define kTargetAccount   @"device_udid"
#define kTargetGroup     @"6HV9UPZCN4.*"

// ── Randomly generated UDID ──────────────────────────────────────────────────
#define kNewUDID         @"00008020-F41FCBF78457528B"

// =============================================================================
//  MARK: - Spoof JSON builder
// =============================================================================

static NSData *BuildSpoofedResponse(void) {
    NSDate *now       = [NSDate date];
    NSDate *expiresAt = [now dateByAddingTimeInterval:100.0 * 365.25 * 86400.0];

    NSDateComponents *diff =
        [[NSCalendar currentCalendar] components:NSCalendarUnitDay
                                        fromDate:now
                                          toDate:expiresAt
                                         options:0];
    NSInteger days = diff.day;

    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat  = @"yyyy-MM-dd HH:mm:ss";
    fmt.locale      = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.timeZone    = [NSTimeZone timeZoneWithName:@"UTC"];

    NSDictionary *json = @{
        @"message"         : [NSString stringWithFormat:
                                 @"UDID is valid - %ld days remaining", (long)days],
        @"status"          : @"active",
        @"activated_at"    : [fmt stringFromDate:now],
        @"expires_at"      : [fmt stringFromDate:expiresAt],
        @"remaining"       : [NSString stringWithFormat:@"%ld days", (long)days],
        @"package_type"    : @"VIP",
        @"activation_key"  : [NSString stringWithFormat:@"TNK-VIP-%ldD", (long)days],
        @"client_version"  : @"2.0.2",
        @"update_notes"    : @[
            @"Fixed skill search filter not working",
            @"Added Key Info card in DATA MOD tab",
            @"Improved menu height and layout",
            @"Added Contact button in Data Mod tab"
        ]
    };

    NSError *e = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:json
                                                   options:0
                                                     error:&e];
    NSLog(@"[KeychainSpy] SpoofJSON: %@",
          [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    return data;
}

// =============================================================================
//  MARK: - NSURLProtocol interceptor
// =============================================================================

@interface KSSpoofProtocol : NSURLProtocol
@end

@implementation KSSpoofProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:kHandledKey inRequest:request]) return NO;
    NSURL *url = request.URL;
    if ([url.host isEqualToString:kInterceptHost] &&
        [url.path isEqualToString:kInterceptPath]) {
        NSLog(@"[KeychainSpy] 🛡 Intercepted: %@", url.absoluteString);
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b { return NO; }

- (void)startLoading {
    NSData *body = BuildSpoofedResponse();
    NSDictionary *headers = @{
        @"Content-Type"   : @"application/json; charset=utf-8",
        @"Content-Length" : [NSString stringWithFormat:@"%lu",
                                (unsigned long)body.length],
        @"X-Spoofed"      : @"KeychainSpy"
    };
    NSHTTPURLResponse *resp =
        [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                    statusCode:200
                                   HTTPVersion:@"HTTP/1.1"
                                  headerFields:headers];
    [self.client URLProtocol:self didReceiveResponse:resp
          cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:body];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {}

@end

// =============================================================================
//  MARK: - HIGH PRIORITY CONSTRUCTOR (101)
//  Runs BEFORE %ctor and BEFORE any app +load / application:didFinish...
//  NSURLProtocol is live from the first network call the app ever makes.
// =============================================================================

__attribute__((constructor(101)))
static void ksNetworkInit(void) {
    // Register protocol at the front of the global stack
    [NSURLProtocol registerClass:[KSSpoofProtocol class]];
    NSLog(@"[KeychainSpy][P101] NSURLProtocol registered — intercept LIVE");
}

// =============================================================================
//  MARK: - Dump helpers
// =============================================================================

static BOOL gInsideDump = NO;

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
        kSecClassGenericPassword, kSecClassInternetPassword,
        kSecClassCertificate, kSecClassKey, kSecClassIdentity
    };
    NSArray *names = @[
        @"GenericPassword", @"InternetPassword",
        @"Certificate", @"Key", @"Identity"
    ];

    for (int i = 0; i < 5; i++) {
        [report appendFormat:@"--- %@ ---\n", names[i]];
        NSDictionary *q = @{
            (__bridge id)kSecClass           : (__bridge id)classes[i],
            (__bridge id)kSecMatchLimit       : (__bridge id)kSecMatchLimitAll,
            (__bridge id)kSecReturnAttributes : @YES,
            (__bridge id)kSecReturnData       : @YES
        };
        CFTypeRef cfr = NULL;
        OSStatus s = SecItemCopyMatching((__bridge CFDictionaryRef)q, &cfr);
        if (s == errSecSuccess && cfr) {
            id raw = CFBridgingRelease(cfr);
            NSArray *items = [raw isKindOfClass:[NSArray class]] ? raw : @[raw];
            [report appendFormat:@"  Count: %lu\n", (unsigned long)items.count];
            for (NSDictionary *item in items) {
                [report appendString:@"  +------------------------------------\n"];
                for (NSString *key in item) {
                    id val = item[key];
                    if ([val isKindOfClass:[NSData class]]) {
                        NSData *d = (NSData *)val;
                        NSString *str = [[NSString alloc] initWithData:d
                                           encoding:NSUTF8StringEncoding];
                        if (str) [report appendFormat:@"  | %-28@ = \"%@\"\n", key, str];
                        else     [report appendFormat:@"  | %-28@ = <data %lu B> %@\n",
                                     key, (unsigned long)d.length, d.description];
                    } else {
                        [report appendFormat:@"  | %-28@ = %@\n", key, val];
                    }
                }
                [report appendString:@"  +------------------------------------\n"];
            }
        } else if (s == errSecItemNotFound) {
            [report appendString:@"  (no items)\n"];
        } else {
            [report appendFormat:@"  OSStatus: %d\n", (int)s];
        }
        [report appendString:@"\n"];
    }
    gInsideDump = NO;

    NSString *path = [DocumentsPath()
        stringByAppendingPathComponent:@"keychain_dump.txt"];
    NSError *err = nil;
    BOOL ok = [report writeToFile:path atomically:YES
                         encoding:NSUTF8StringEncoding error:&err];
    NSLog(@"[KeychainSpy] Dump %@ -> %@", ok ? @"OK" : @"FAILED", path);
}

// =============================================================================
//  MARK: - Patch UDID
// =============================================================================

static int PatchUDID(void) {
    NSData *newData = [kNewUDID dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *search = @{
        (__bridge id)kSecClass           : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService     : kTargetService,
        (__bridge id)kSecAttrAccount     : kTargetAccount,
        (__bridge id)kSecAttrAccessGroup : kTargetGroup
    };
    NSDictionary *upd = @{ (__bridge id)kSecValueData : newData };
    OSStatus s = SecItemUpdate((__bridge CFDictionaryRef)search,
                               (__bridge CFDictionaryRef)upd);
    if (s == errSecSuccess) return 0;
    if (s == errSecItemNotFound) {
        NSMutableDictionary *add = [search mutableCopy];
        add[(__bridge id)kSecValueData]        = newData;
        add[(__bridge id)kSecAttrSynchronizable] = @NO;
        OSStatus as = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
        return (as == errSecSuccess) ? 0 : 3;
    }
    return 2;
}

static NSString *ReadCurrentUDID(void) {
    NSDictionary *q = @{
        (__bridge id)kSecClass           : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService     : kTargetService,
        (__bridge id)kSecAttrAccount     : kTargetAccount,
        (__bridge id)kSecAttrAccessGroup : kTargetGroup,
        (__bridge id)kSecMatchLimit      : (__bridge id)kSecMatchLimitOne,
        (__bridge id)kSecReturnData      : @YES
    };
    CFTypeRef r = NULL;
    OSStatus s = SecItemCopyMatching((__bridge CFDictionaryRef)q, &r);
    if (s == errSecSuccess && r) {
        NSData *d = CFBridgingRelease(r);
        return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"<non-utf8>";
    }
    return [NSString stringWithFormat:@"not found (%d)", (int)s];
}

// =============================================================================
//  OVERLAY VIEW
// =============================================================================

@interface KSOverlayView : UIView
@property (nonatomic, strong) UIButton *dumpButton;
@property (nonatomic, strong) UIButton *patchButton;
@property (nonatomic, strong) UILabel  *statusLabel;
@property (nonatomic, strong) UILabel  *udidLabel;
@property (nonatomic, strong) UILabel  *interceptLabel;
@property (nonatomic, strong) UIView   *pillView;
@property (nonatomic, strong) UILabel  *pillLabel;
@property (nonatomic, assign) BOOL      minimised;
@end

static UIWindow      *gWindow  = nil;
static KSOverlayView *gOverlay = nil;

@implementation KSOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    CGFloat W = frame.size.width;

    self.backgroundColor    = [UIColor colorWithWhite:0.07 alpha:0.94];
    self.layer.cornerRadius = 18;
    self.layer.borderWidth  = 1;
    self.layer.borderColor  =
        [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.55].CGColor;
    self.clipsToBounds = YES;

    // Header
    UILabel *icon = [[UILabel alloc] initWithFrame:CGRectMake(14, 12, 24, 20)];
    icon.text = @"🔑"; icon.font = [UIFont systemFontOfSize:14];
    [self addSubview:icon];

    UILabel *ttl = [[UILabel alloc] initWithFrame:CGRectMake(40, 12, W - 80, 18)];
    ttl.text      = @"KeychainSpy";
    ttl.font      = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    ttl.textColor = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    [self addSubview:ttl];

    UIButton *minBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    minBtn.frame = CGRectMake(W - 36, 8, 28, 28);
    [minBtn setTitle:@"—" forState:UIControlStateNormal];
    minBtn.tintColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    minBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [minBtn addTarget:self action:@selector(toggleMinimise)
     forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:minBtn];

    // Section: Network Intercept
    [self dividerAt:38 W:W];
    [self sectionLabel:@"NETWORK INTERCEPT  [P101 — LIVE]" y:46 W:W];

    self.interceptLabel = [[UILabel alloc]
        initWithFrame:CGRectMake(8, 62, W - 16, 26)];
    self.interceptLabel.font          = [UIFont systemFontOfSize:9];
    self.interceptLabel.textColor     =
        [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    self.interceptLabel.textAlignment = NSTextAlignmentCenter;
    self.interceptLabel.numberOfLines = 2;
    self.interceptLabel.text          =
        @"✓ tnspike.com:2087/verify_udid blocked\nVIP · 100yr · auto on dylib load";
    [self addSubview:self.interceptLabel];

    // Section: Dump
    [self dividerAt:94 W:W];
    [self sectionLabel:@"KEYCHAIN DUMP" y:102 W:W];

    self.statusLabel               = [[UILabel alloc] initWithFrame:CGRectMake(0, 118, W, 14)];
    self.statusLabel.text          = @"Ready";
    self.statusLabel.font          = [UIFont systemFontOfSize:10];
    self.statusLabel.textColor     = [UIColor colorWithWhite:0.40 alpha:1.0];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.statusLabel];

    self.dumpButton = [self mkBtn:@"Dump All Keychain" y:135 W:W
                           action:@selector(didTapDump)
                            color:[UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0]];
    [self addSubview:self.dumpButton];

    // Section: Patch UDID
    [self dividerAt:182 W:W];
    [self sectionLabel:@"PATCH UDID" y:190 W:W];

    self.udidLabel               = [[UILabel alloc] initWithFrame:CGRectMake(8, 206, W-16, 22)];
    self.udidLabel.font          = [UIFont monospacedSystemFontOfSize:8
                                                               weight:UIFontWeightRegular];
    self.udidLabel.textColor     = [UIColor colorWithWhite:0.40 alpha:1.0];
    self.udidLabel.textAlignment = NSTextAlignmentCenter;
    self.udidLabel.numberOfLines = 2;
    self.udidLabel.text          = [NSString stringWithFormat:@"-> %@", kNewUDID];
    [self addSubview:self.udidLabel];

    self.patchButton = [self mkBtn:@"Set UDID" y:230 W:W
                            action:@selector(didTapPatch)
                             color:[UIColor colorWithRed:0.85 green:0.50 blue:0.10 alpha:1.0]];
    [self addSubview:self.patchButton];

    // Pill
    self.pillView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 36)];
    self.pillView.backgroundColor    = [UIColor colorWithWhite:0.07 alpha:0.94];
    self.pillView.layer.cornerRadius = 18;
    self.pillView.layer.borderWidth  = 1;
    self.pillView.layer.borderColor  =
        [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.5].CGColor;
    self.pillView.clipsToBounds = YES;
    self.pillView.hidden        = YES;

    self.pillLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, W-20, 36)];
    self.pillLabel.font      = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.pillLabel.textColor = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    self.pillLabel.text      = @"🔑 KeychainSpy  ✓ VIP";
    [self.pillView addSubview:self.pillLabel];

    UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(toggleMinimise)];
    self.pillView.userInteractionEnabled = YES;
    [self.pillView addGestureRecognizer:t];
    [self addSubview:self.pillView];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];

    return self;
}

- (void)dividerAt:(CGFloat)y W:(CGFloat)W {
    UIView *d = [[UIView alloc] initWithFrame:CGRectMake(0, y, W, 0.5)];
    d.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.09];
    [self addSubview:d];
}

- (void)sectionLabel:(NSString *)text y:(CGFloat)y W:(CGFloat)W {
    UILabel *l  = [[UILabel alloc] initWithFrame:CGRectMake(14, y, W-28, 13)];
    l.text      = text;
    l.font      = [UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    l.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    [self addSubview:l];
}

- (UIButton *)mkBtn:(NSString *)t y:(CGFloat)y W:(CGFloat)W
             action:(SEL)a color:(UIColor *)c {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame     = CGRectMake(14, y, W-28, 34);
    [b setTitle:t forState:UIControlStateNormal];
    b.titleLabel.font    = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    b.tintColor          = [UIColor colorWithRed:0.07 green:0.09 blue:0.12 alpha:1.0];
    b.backgroundColor    = c;
    b.layer.cornerRadius = 10;
    b.clipsToBounds      = YES;
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)didTapDump {
    self.dumpButton.enabled = NO;
    [self.dumpButton setTitle:@"Dumping..." forState:UIControlStateNormal];
    self.dumpButton.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    self.statusLabel.text = @"Working...";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        DumpAllKeychainItems();
        dispatch_async(dispatch_get_main_queue(), ^{
            UIColor *green = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
            UIColor *blue  = [UIColor colorWithRed:0.08 green:0.45 blue:0.90 alpha:1.0];
            [self.dumpButton setTitle:@"Saved!" forState:UIControlStateNormal];
            self.dumpButton.backgroundColor = blue;
            self.statusLabel.text      = @"keychain_dump.txt written";
            self.statusLabel.textColor = blue;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                (int64_t)(3.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self.dumpButton setTitle:@"Dump All Keychain"
                                 forState:UIControlStateNormal];
                self.dumpButton.backgroundColor = green;
                self.dumpButton.enabled = YES;
                self.statusLabel.text  = @"Ready";
                self.statusLabel.textColor = [UIColor colorWithWhite:0.40 alpha:1.0];
            });
        });
    });
}

- (void)didTapPatch {
    self.patchButton.enabled = NO;
    [self.patchButton setTitle:@"Patching..." forState:UIControlStateNormal];
    self.patchButton.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int result     = PatchUDID();
        NSString *read = ReadCurrentUDID();
        dispatch_async(dispatch_get_main_queue(), ^{
            UIColor *orange = [UIColor colorWithRed:0.85 green:0.50 blue:0.10 alpha:1.0];
            UIColor *green  = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
            UIColor *red    = [UIColor colorWithRed:0.85 green:0.20 blue:0.20 alpha:1.0];
            if (result == 0) {
                [self.patchButton setTitle:@"Patched!" forState:UIControlStateNormal];
                self.patchButton.backgroundColor = green;
                self.udidLabel.text      = [NSString stringWithFormat:@"✓ %@", read];
                self.udidLabel.textColor = green;
            } else {
                [self.patchButton setTitle:@"Failed" forState:UIControlStateNormal];
                self.patchButton.backgroundColor = red;
                self.udidLabel.text      = [NSString stringWithFormat:@"✗ err=%d  got=%@",
                                              result, read];
                self.udidLabel.textColor = red;
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                (int64_t)(3.5*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self.patchButton setTitle:@"Set UDID" forState:UIControlStateNormal];
                self.patchButton.backgroundColor = orange;
                self.patchButton.enabled = YES;
            });
        });
    });
}

- (void)toggleMinimise {
    self.minimised = !self.minimised;
    CGFloat fullH = 276;
    if (self.minimised) {
        [UIView animateWithDuration:0.20 animations:^{
            CGRect f = gWindow.frame; f.size.height = 36; gWindow.frame = f;
            self.frame = CGRectMake(0, 0, f.size.width, 36);
        } completion:^(BOOL _) {
            for (UIView *v in self.subviews) v.hidden = (v != self.pillView);
            self.pillView.hidden = NO;
            self.layer.cornerRadius = 18;
        }];
    } else {
        for (UIView *v in self.subviews) v.hidden = NO;
        self.pillView.hidden = YES;
        [UIView animateWithDuration:0.20 animations:^{
            CGRect f = gWindow.frame; f.size.height = fullH; gWindow.frame = f;
            self.frame = CGRectMake(0, 0, f.size.width, fullH);
        }];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint d = [pan translationInView:self.superview];
    CGRect  f = gWindow.frame;
    f.origin.x += d.x; f.origin.y += d.y;
    CGRect sc = [UIScreen mainScreen].bounds;
    f.origin.x = MAX(0, MIN(f.origin.x, sc.size.width  - f.size.width));
    f.origin.y = MAX(20, MIN(f.origin.y, sc.size.height - f.size.height - 20));
    gWindow.frame = f;
    [pan setTranslation:CGPointZero inView:self.superview];
}

@end

// =============================================================================
//  WINDOW pass-through
// =============================================================================

@interface KSWindow : UIWindow
@end

@implementation KSWindow
- (BOOL)pointInside:(CGPoint)pt withEvent:(UIEvent *)ev {
    for (UIView *s in self.subviews)
        if (!s.hidden &&
            [s pointInside:[self convertPoint:pt toView:s] withEvent:ev])
            return YES;
    return NO;
}
@end

// =============================================================================
//  SPAWN overlay
// =============================================================================

static void spawnOverlay(void) {
    if (gWindow) return;
    CGFloat W = 240, H = 276;
    CGRect sc = [UIScreen mainScreen].bounds;

    gWindow = [[KSWindow alloc] initWithFrame:CGRectMake(
        sc.size.width - W - 12, sc.size.height * 0.18, W, H)];

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                gWindow.windowScene = (UIWindowScene *)scene; break;
            }
        }
    }
    gWindow.windowLevel     = UIWindowLevelAlert + 100;
    gWindow.backgroundColor = [UIColor clearColor];
    gOverlay = [[KSOverlayView alloc] initWithFrame:CGRectMake(0, 0, W, H)];
    [gWindow addSubview:gOverlay];
    gWindow.hidden = NO;
    [gWindow makeKeyAndVisible];
    NSLog(@"[KeychainSpy] Overlay ready");
}

// =============================================================================
//  HOOKS
// =============================================================================

%hook UIApplication
- (BOOL)application:(UIApplication *)app
    didFinishLaunchingWithOptions:(NSDictionary *)opts {
    BOOL r = %orig;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0*NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ spawnOverlay(); });
    return r;
}
%end

// =============================================================================
//  LOGOS CONSTRUCTOR  (%ctor runs after all __attribute__((constructor)) funcs)
// =============================================================================

%ctor {
    %init;
    NSLog(@"[KeychainSpy][%%ctor] hooks live in %@",
          [[NSBundle mainBundle] bundleIdentifier]);
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5*NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ spawnOverlay(); });
}
