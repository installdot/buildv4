/*
 * KeychainSpy - iOS Keychain Dumper + Patcher
 * - Dump All Keychain -> Documents/keychain_dump.txt
 * - Patch UDID: sets v_Data of com.tnnguy.auth / device_udid
 *   to "00008020-00161D3E0288003A"
 */

#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <Foundation/Foundation.h>

static BOOL gInsideDump = NO;

// =============================================================================
//  MARK: - Dump
// =============================================================================

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
            NSArray *items = [raw isKindOfClass:[NSArray class]] ? raw : @[raw];
            [report appendFormat:@"  Count: %lu\n", (unsigned long)items.count];

            for (NSDictionary *item in items) {
                [report appendString:@"  +------------------------------------\n"];
                for (NSString *key in item) {
                    id val = item[key];
                    if ([val isKindOfClass:[NSData class]]) {
                        NSData *data = (NSData *)val;
                        NSString *str = [[NSString alloc]
                            initWithData:data encoding:NSUTF8StringEncoding];
                        if (str)
                            [report appendFormat:@"  | %-28@ = \"%@\"\n", key, str];
                        else
                            [report appendFormat:@"  | %-28@ = <data %lu B> %@\n",
                                key, (unsigned long)data.length, [data description]];
                    } else {
                        [report appendFormat:@"  | %-28@ = %@\n", key, val];
                    }
                }
                [report appendString:@"  +------------------------------------\n"];
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
    BOOL ok = [report writeToFile:path atomically:YES
                         encoding:NSUTF8StringEncoding error:&err];
    NSLog(@"[KeychainSpy] Dump %@ -> %@  err=%@",
          ok ? @"OK" : @"FAILED", path, err);
}

// =============================================================================
//  MARK: - Patch UDID
//  Targets: service=com.tnnguy.auth  account=device_udid
//  Sets v_Data to "00008020-00161D3E0288003A"
// =============================================================================

#define kTargetService  @"com.tnnguy.auth"
#define kTargetAccount  @"device_udid"
#define kTargetGroup    @"6HV9UPZCN4.*"
#define kNewUDID        @"00008020-00161D3E0288003A"

// Returns: 0=success, 1=not found, 2=update failed, 3=add failed
static int PatchUDID(void) {
    NSData *newData = [kNewUDID dataUsingEncoding:NSUTF8StringEncoding];

    // ── Try update first (item already exists) ───────────────────────────────
    NSDictionary *searchQuery = @{
        (__bridge id)kSecClass           : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService     : kTargetService,
        (__bridge id)kSecAttrAccount     : kTargetAccount,
        (__bridge id)kSecAttrAccessGroup : kTargetGroup
    };

    NSDictionary *updateAttrs = @{
        (__bridge id)kSecValueData : newData
    };

    OSStatus status = SecItemUpdate(
        (__bridge CFDictionaryRef)searchQuery,
        (__bridge CFDictionaryRef)updateAttrs);

    NSLog(@"[KeychainSpy] SecItemUpdate status=%d", (int)status);

    if (status == errSecSuccess) {
        return 0; // patched via update
    }

    if (status == errSecItemNotFound) {
        // Item doesn't exist yet — add it fresh
        NSDictionary *addQuery = @{
            (__bridge id)kSecClass           : (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService     : kTargetService,
            (__bridge id)kSecAttrAccount     : kTargetAccount,
            (__bridge id)kSecAttrAccessGroup : kTargetGroup,
            (__bridge id)kSecValueData       : newData,
            (__bridge id)kSecAttrSynchronizable : @NO
        };
        OSStatus addStatus = SecItemAdd(
            (__bridge CFDictionaryRef)addQuery, NULL);
        NSLog(@"[KeychainSpy] SecItemAdd status=%d", (int)addStatus);
        return (addStatus == errSecSuccess) ? 0 : 3;
    }

    return 2;
}

// Read back to verify
static NSString *ReadCurrentUDID(void) {
    NSDictionary *query = @{
        (__bridge id)kSecClass           : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService     : kTargetService,
        (__bridge id)kSecAttrAccount     : kTargetAccount,
        (__bridge id)kSecAttrAccessGroup : kTargetGroup,
        (__bridge id)kSecMatchLimit      : (__bridge id)kSecMatchLimitOne,
        (__bridge id)kSecReturnData      : @YES
    };
    CFTypeRef cfResult = NULL;
    OSStatus s = SecItemCopyMatching((__bridge CFDictionaryRef)query, &cfResult);
    if (s == errSecSuccess && cfResult) {
        NSData *data = CFBridgingRelease(cfResult);
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
               ?: @"<non-utf8>";
    }
    return [NSString stringWithFormat:@"not found (status %d)", (int)s];
}

// =============================================================================
//  OVERLAY VIEW
// =============================================================================

@interface KSOverlayView : UIView
@property (nonatomic, strong) UIButton *dumpButton;
@property (nonatomic, strong) UIButton *patchButton;
@property (nonatomic, strong) UILabel  *statusLabel;
@property (nonatomic, strong) UILabel  *udidLabel;
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

    // ── Header ───────────────────────────────────────────────────────────────
    UILabel *icon = [[UILabel alloc] initWithFrame:CGRectMake(14, 12, 24, 20)];
    icon.text = @"🔑";
    icon.font = [UIFont systemFontOfSize:14];
    [self addSubview:icon];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(40, 12, W - 80, 18)];
    title.text      = @"KeychainSpy";
    title.font      = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    title.textColor = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    [self addSubview:title];

    UIButton *minBtn       = [UIButton buttonWithType:UIButtonTypeSystem];
    minBtn.frame           = CGRectMake(W - 36, 8, 28, 28);
    [minBtn setTitle:@"—" forState:UIControlStateNormal];
    minBtn.tintColor           = [UIColor colorWithWhite:0.5 alpha:1.0];
    minBtn.titleLabel.font     = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [minBtn addTarget:self action:@selector(toggleMinimise)
     forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:minBtn];

    // ── Divider 1 ─────────────────────────────────────────────────────────────
    [self dividerAt:38 W:W];

    // ── Section: Dump ─────────────────────────────────────────────────────────
    [self sectionLabel:@"KEYCHAIN DUMP" y:46 W:W];

    self.statusLabel               = [[UILabel alloc] initWithFrame:CGRectMake(0, 62, W, 16)];
    self.statusLabel.text          = @"Ready";
    self.statusLabel.font          = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    self.statusLabel.textColor     = [UIColor colorWithWhite:0.40 alpha:1.0];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.statusLabel];

    self.dumpButton = [self makeButton:@"Dump All Keychain"
                                     y:80 W:W
                                action:@selector(didTapDump)
                                 color:[UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0]];
    [self addSubview:self.dumpButton];

    // ── Divider 2 ─────────────────────────────────────────────────────────────
    [self dividerAt:126 W:W];

    // ── Section: Patch ────────────────────────────────────────────────────────
    [self sectionLabel:@"PATCH UDID" y:134 W:W];

    // Current UDID display
    self.udidLabel               = [[UILabel alloc] initWithFrame:CGRectMake(8, 150, W - 16, 26)];
    self.udidLabel.font          = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    self.udidLabel.textColor     = [UIColor colorWithWhite:0.40 alpha:1.0];
    self.udidLabel.textAlignment = NSTextAlignmentCenter;
    self.udidLabel.numberOfLines = 2;
    self.udidLabel.text          = [NSString stringWithFormat:@"→ %@", kNewUDID];
    [self addSubview:self.udidLabel];

    self.patchButton = [self makeButton:@"Set UDID"
                                      y:180 W:W
                                 action:@selector(didTapPatch)
                                  color:[UIColor colorWithRed:0.85 green:0.50 blue:0.10 alpha:1.0]];
    [self addSubview:self.patchButton];

    // ── Pill ─────────────────────────────────────────────────────────────────
    self.pillView                    = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 36)];
    self.pillView.backgroundColor    = [UIColor colorWithWhite:0.07 alpha:0.94];
    self.pillView.layer.cornerRadius = 18;
    self.pillView.layer.borderWidth  = 1;
    self.pillView.layer.borderColor  =
        [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.5].CGColor;
    self.pillView.clipsToBounds      = YES;
    self.pillView.hidden             = YES;

    self.pillLabel           = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, W - 20, 36)];
    self.pillLabel.font      = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.pillLabel.textColor = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    self.pillLabel.text      = @"🔑 KeychainSpy";
    [self.pillView addSubview:self.pillLabel];

    UITapGestureRecognizer *pillTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(toggleMinimise)];
    self.pillView.userInteractionEnabled = YES;
    [self.pillView addGestureRecognizer:pillTap];
    [self addSubview:self.pillView];

    // ── Drag ─────────────────────────────────────────────────────────────────
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];

    return self;
}

// ── UI helpers ────────────────────────────────────────────────────────────────

- (void)dividerAt:(CGFloat)y W:(CGFloat)W {
    UIView *d = [[UIView alloc] initWithFrame:CGRectMake(0, y, W, 0.5)];
    d.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.09];
    [self addSubview:d];
}

- (void)sectionLabel:(NSString *)text y:(CGFloat)y W:(CGFloat)W {
    UILabel *l  = [[UILabel alloc] initWithFrame:CGRectMake(14, y, W - 28, 13)];
    l.text      = text;
    l.font      = [UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    l.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    [self addSubview:l];
}

- (UIButton *)makeButton:(NSString *)title y:(CGFloat)y W:(CGFloat)W
                  action:(SEL)action color:(UIColor *)color {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame     = CGRectMake(14, y, W - 28, 36);
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font    = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    btn.tintColor          = [UIColor colorWithRed:0.07 green:0.09 blue:0.12 alpha:1.0];
    btn.backgroundColor    = color;
    btn.layer.cornerRadius = 10;
    btn.clipsToBounds      = YES;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

// ── Dump ──────────────────────────────────────────────────────────────────────

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
            self.statusLabel.text = @"keychain_dump.txt written";
            self.statusLabel.textColor = blue;

            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    [self.dumpButton setTitle:@"Dump All Keychain"
                                    forState:UIControlStateNormal];
                    self.dumpButton.backgroundColor = green;
                    self.dumpButton.enabled = YES;
                    self.statusLabel.text = @"Ready";
                    self.statusLabel.textColor = [UIColor colorWithWhite:0.40 alpha:1.0];
            });
        });
    });
}

// ── Patch UDID ────────────────────────────────────────────────────────────────

- (void)didTapPatch {
    self.patchButton.enabled = NO;
    [self.patchButton setTitle:@"Patching..." forState:UIControlStateNormal];
    self.patchButton.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int result = PatchUDID();
        NSString *verified = ReadCurrentUDID();

        dispatch_async(dispatch_get_main_queue(), ^{
            UIColor *orange = [UIColor colorWithRed:0.85 green:0.50 blue:0.10 alpha:1.0];
            UIColor *red    = [UIColor colorWithRed:0.85 green:0.20 blue:0.20 alpha:1.0];
            UIColor *green  = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];

            if (result == 0) {
                [self.patchButton setTitle:@"Patched!" forState:UIControlStateNormal];
                self.patchButton.backgroundColor = green;
                self.udidLabel.text  = [NSString stringWithFormat:@"✓ %@", verified];
                self.udidLabel.textColor = green;
                NSLog(@"[KeychainSpy] UDID patched. Verified: %@", verified);
            } else {
                [self.patchButton setTitle:@"Failed (see log)" forState:UIControlStateNormal];
                self.patchButton.backgroundColor = red;
                self.udidLabel.text  = [NSString stringWithFormat:@"✗ err=%d  now=%@", result, verified];
                self.udidLabel.textColor = red;
                NSLog(@"[KeychainSpy] Patch FAILED result=%d verified=%@", result, verified);
            }

            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    [self.patchButton setTitle:@"Set UDID" forState:UIControlStateNormal];
                    self.patchButton.backgroundColor = orange;
                    self.patchButton.enabled = YES;
            });
        });
    });
}

// ── Minimise / expand ─────────────────────────────────────────────────────────

- (void)toggleMinimise {
    self.minimised = !self.minimised;
    CGFloat fullH  = 226;
    if (self.minimised) {
        [UIView animateWithDuration:0.20 animations:^{
            CGRect f = gWindow.frame; f.size.height = 36; gWindow.frame = f;
            self.frame = CGRectMake(0, 0, f.size.width, 36);
        } completion:^(BOOL _) {
            for (UIView *v in self.subviews) v.hidden = (v != self.pillView);
            self.pillView.hidden    = NO;
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

// ── Drag ──────────────────────────────────────────────────────────────────────

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint delta  = [pan translationInView:self.superview];
    CGRect  f      = gWindow.frame;
    f.origin.x    += delta.x;
    f.origin.y    += delta.y;
    CGRect screen  = [UIScreen mainScreen].bounds;
    f.origin.x     = MAX(0, MIN(f.origin.x, screen.size.width  - f.size.width));
    f.origin.y     = MAX(20, MIN(f.origin.y, screen.size.height - f.size.height - 20));
    gWindow.frame  = f;
    [pan setTranslation:CGPointZero inView:self.superview];
}

@end

// =============================================================================
//  WINDOW (pass-through)
// =============================================================================

@interface KSWindow : UIWindow
@end

@implementation KSWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *sub in self.subviews)
        if (!sub.hidden &&
            [sub pointInside:[self convertPoint:point toView:sub] withEvent:event])
            return YES;
    return NO;
}
@end

// =============================================================================
//  SPAWN
// =============================================================================

static void spawnOverlay(void) {
    if (gWindow) return;

    CGFloat W = 240, H = 226;
    CGRect screen = [UIScreen mainScreen].bounds;

    gWindow = [[KSWindow alloc] initWithFrame:CGRectMake(
        screen.size.width - W - 12,
        screen.size.height * 0.22,
        W, H)];

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                gWindow.windowScene = (UIWindowScene *)scene;
                break;
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
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ spawnOverlay(); });
    return r;
}
%end

// =============================================================================
//  CONSTRUCTOR
// =============================================================================

%ctor {
    NSLog(@"[KeychainSpy] Loaded in %@",
          [[NSBundle mainBundle] bundleIdentifier]);
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ spawnOverlay(); });
}
