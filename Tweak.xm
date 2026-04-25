// DevApiHook.xm  —  v5
// Changes from v4:
//  • Auto-logging of i.imgur.com URLs restored
//  • Menu is now a custom floating overlay card (no sheet/modal)
//    — tapping the DEV button toggles a panel that animates in-place
//      near the button; tapping outside dismisses it. Navigation
//      between sub-screens slides horizontally inside the card.
//  • All API hooks default to OFF:
//    kHookCheckHud, kHookValidate, kHookNotifications,
//    kHookConnection, kHookTabs, kHookImgur → @NO

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ═══════════════════════════════════════════════════════════════
// MARK: - UserDefaults Keys
// ═══════════════════════════════════════════════════════════════

static NSString *const kSuite             = @"com.dev.apihook.settings";

static NSString *const kHookCheckHud      = @"hook_check_hud";
static NSString *const kHookValidate      = @"hook_validate";
static NSString *const kHookNotifications = @"hook_notifications";
static NSString *const kHookConnection    = @"hook_connection";
static NSString *const kHookTabs          = @"hook_tabs";
static NSString *const kHookImgur         = @"hook_imgur";

static NSString *const kJsonCheckHud      = @"json_check_hud";
static NSString *const kJsonValidate      = @"json_validate";
static NSString *const kJsonNotifications = @"json_notifications";
static NSString *const kJsonConnection    = @"json_connection";
static NSString *const kJsonTabs          = @"json_tabs";

static NSString *const kImgurMap          = @"imgur_url_map";

static NSString *const kIconURL           = @"icon_url";
static NSString *const kIconLocalPath     = @"icon_local_path";
static NSString *const kIconUseLocal      = @"icon_use_local";

// ═══════════════════════════════════════════════════════════════
// MARK: - ImgurLinkStore
// ═══════════════════════════════════════════════════════════════

@interface ImgurLinkStore : NSObject
+ (instancetype)shared;
- (void)logURL:(NSString *)rawURL;
- (NSString *)replacementFor:(NSString *)rawURL;
- (void)setReplacement:(NSString *)rep forKey:(NSString *)normalizedURL;
- (void)removeKey:(NSString *)normalizedURL;
- (NSArray<NSString *> *)allKeys;
@end

@implementation ImgurLinkStore {
    NSMutableDictionary<NSString *, NSString *> *_map;
    NSUserDefaults *_ud;
}

+ (instancetype)shared {
    static ImgurLinkStore *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [ImgurLinkStore new]; });
    return s;
}
- (instancetype)init {
    self = [super init];
    _ud  = [[NSUserDefaults alloc] initWithSuiteName:kSuite];
    NSDictionary *saved = [_ud dictionaryForKey:kImgurMap];
    _map = saved ? [saved mutableCopy] : [NSMutableDictionary new];
    return self;
}
- (NSString *)normalizeURL:(NSString *)raw {
    if (!raw.length) return raw ?: @"";
    NSURL *u = [NSURL URLWithString:raw];
    if (!u) return raw;
    return [NSString stringWithFormat:@"%@://%@%@",
            u.scheme ?: @"https", u.host ?: @"i.imgur.com", u.path ?: @"/"];
}
- (void)logURL:(NSString *)rawURL {
    if (!rawURL.length) return;
    NSString *key = [self normalizeURL:rawURL];
    @synchronized (self) {
        if (_map[key] == nil) { _map[key] = @""; [self _save]; }
    }
}
- (NSString *)replacementFor:(NSString *)rawURL {
    if (!rawURL.length) return @"";
    NSString *key = [self normalizeURL:rawURL];
    @synchronized (self) { return _map[key] ?: @""; }
}
- (void)setReplacement:(NSString *)rep forKey:(NSString *)key {
    if (!key.length) return;
    @synchronized (self) { _map[key] = rep ?: @""; [self _save]; }
}
- (void)removeKey:(NSString *)key {
    if (!key.length) return;
    @synchronized (self) { [_map removeObjectForKey:key]; [self _save]; }
}
- (NSArray<NSString *> *)allKeys {
    @synchronized (self) {
        return [_map.allKeys sortedArrayUsingSelector:@selector(compare:)];
    }
}
- (void)_save {
    [_ud setObject:[_map copy] forKey:kImgurMap];
    [_ud synchronize];
}
@end

// ═══════════════════════════════════════════════════════════════
// MARK: - DevSettings   (all hooks default OFF)
// ═══════════════════════════════════════════════════════════════

@interface DevSettings : NSObject
@property (nonatomic, strong) NSUserDefaults *ud;
+ (instancetype)shared;
- (BOOL)isEnabled:(NSString *)key;
- (void)setEnabled:(BOOL)v forKey:(NSString *)key;
- (NSString *)jsonStringForKey:(NSString *)key;
- (void)setJsonString:(NSString *)s forKey:(NSString *)key;
- (NSDictionary *)jsonDictForKey:(NSString *)key;
- (NSString *)stringForKey:(NSString *)key;
- (void)setString:(NSString *)s forKey:(NSString *)key;
@end

@implementation DevSettings
+ (instancetype)shared {
    static DevSettings *i; static dispatch_once_t t;
    dispatch_once(&t, ^{ i = [DevSettings new]; });
    return i;
}
- (instancetype)init {
    self = [super init];
    _ud = [[NSUserDefaults alloc] initWithSuiteName:kSuite];
    [self _registerDefaults];
    return self;
}
- (NSString *)_pretty:(NSDictionary *)d {
    NSData *data = [NSJSONSerialization dataWithJSONObject:d
                                                   options:NSJSONWritingPrettyPrinted error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}
- (void)_registerDefaults {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSDictionary *defs = @{
        // ── All hooks OFF by default ──────────────────────────
        kHookCheckHud:      @NO,
        kHookValidate:      @NO,
        kHookNotifications: @NO,
        kHookConnection:    @NO,
        kHookTabs:          @NO,
        kHookImgur:         @NO,
        // ─────────────────────────────────────────────────────
        kIconURL: @"", kIconUseLocal: @NO,
        kJsonCheckHud: [self _pretty:@{
            @"success": @YES, @"hud_enabled": @YES,
            @"message": @"HUD Control is active",
            @"reason":  @"Admin is testing the remote control feature."
        }],
        kJsonValidate: [self _pretty:@{
            @"success": @YES, @"message": @"License validated successfully",
            @"data": @{
                @"subscription_type": @"daily", @"expiry_date": @"2026-03-24 17:41:33",
                @"remaining_days": @0, @"remaining_hours": @22,
                @"activated_at": @"2026-03-23 17:41:33", @"is_trial": @NO, @"is_pro": @1
            }
        }],
        kJsonNotifications: [self _pretty:@{
            @"success": @YES, @"count": @1,
            @"notifications": @[@{
                @"id": @7, @"title": @"Dev", @"message": @"Tested by Hải",
                @"time": @"09/12/2025", @"priority": @2,
                @"created_at": @"2025-12-09 17:06:20"
            }]
        }],
        kJsonConnection: [self _pretty:@{
            @"status": @"success", @"message": @"Server is online",
            @"timestamp": @((long long)now),
            @"server_name": @"CheatiOSVip.VN", @"version": @"1.0.0"
        }],
        kJsonTabs: [self _pretty:@{
            @"success": @YES,
            @"server_time": @((long long)now),
            @"server_datetime": [f stringFromDate:[NSDate date]],
            @"tabs": @{
                @"aimbot": @1, @"esp": @1, @"msl": @1, @"weapons": @1,
                @"profile": @1, @"other": @YES, @"kill_switch": @0,
                @"shield": @0, @"video_set": @0, @"troll_enabled": @0
            },
            @"signin_button": @YES, @"key_field": @YES,
            @"start_button": @YES, @"music_enabled": @NO,
            @"main_tabs": @{
                @"home": @YES, @"notifications": @YES,
                @"account": @YES, @"settings": @YES
            }
        }],
    };
    [_ud registerDefaults:defs];
}
- (BOOL)isEnabled:(NSString *)k                  { return [_ud boolForKey:k]; }
- (void)setEnabled:(BOOL)v forKey:(NSString *)k  { [_ud setBool:v forKey:k]; [_ud synchronize]; }
- (NSString *)jsonStringForKey:(NSString *)k     { return [_ud stringForKey:k] ?: @"{}"; }
- (void)setJsonString:(NSString *)s forKey:(NSString *)k { [_ud setObject:s forKey:k]; [_ud synchronize]; }
- (NSDictionary *)jsonDictForKey:(NSString *)k {
    NSData *d = [[_ud stringForKey:k] dataUsingEncoding:NSUTF8StringEncoding];
    if (!d) return @{};
    NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : @{};
}
- (NSString *)stringForKey:(NSString *)k         { return [_ud stringForKey:k] ?: @""; }
- (void)setString:(NSString *)s forKey:(NSString *)k { [_ud setObject:(s ?: @"") forKey:k]; [_ud synchronize]; }
@end

// ═══════════════════════════════════════════════════════════════
// MARK: - HookURLProtocol
// ═══════════════════════════════════════════════════════════════

@interface HookURLProtocol : NSURLProtocol
@end
@implementation HookURLProtocol

+ (NSString *)_bodyOf:(NSURLRequest *)r {
    NSData *d = r.HTTPBody;
    if (!d && r.HTTPBodyStream) {
        NSInputStream *s = r.HTTPBodyStream; NSMutableData *m = [NSMutableData data];
        [s open]; uint8_t b[1024]; NSInteger n;
        while ((n = [s read:b maxLength:sizeof(b)]) > 0) [m appendBytes:b length:n];
        [s close]; d = m;
    }
    return d ? ([[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"") : @"";
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)req {
    NSURL *url = req.URL; if (!url) return NO;
    if ([NSURLProtocol propertyForKey:@"DevHookDone" inRequest:req]) return NO;
    NSString *host = url.host.lowercaseString;
    NSString *path = url.path;
    NSString *meth = req.HTTPMethod.uppercaseString;
    DevSettings *s = DevSettings.shared;

    if ([host isEqualToString:@"i.imgur.com"]) {
        [ImgurLinkStore.shared logURL:url.absoluteString];  // auto-log restored
        if (![s isEnabled:kHookImgur]) return NO;
        return [ImgurLinkStore.shared replacementFor:url.absoluteString].length > 0;
    }

    if (![host isEqualToString:@"api.cheatiosvip.vn"]) return NO;
    if ([s isEnabled:kHookConnection] && [path isEqualToString:@"/check_connection.php"]) return YES;
    if ([s isEnabled:kHookTabs]       && [path isEqualToString:@"/apitab.php"])           return YES;
    if ([path isEqualToString:@"/api.php"]) {
        if ([meth isEqualToString:@"GET"] && [s isEnabled:kHookNotifications] &&
            [url.query containsString:@"action=get_notifications"]) return YES;
        if ([meth isEqualToString:@"POST"]) {
            NSString *body = [self _bodyOf:req];
            if ([s isEnabled:kHookCheckHud] && [body containsString:@"action=check_hud_control"]) return YES;
            if ([s isEnabled:kHookValidate] && [body containsString:@"action=validate"] &&
                [body containsString:@"key="] && [body containsString:@"hwid="])           return YES;
        }
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }

- (void)startLoading {
    NSURL *url     = self.request.URL;
    NSString *host = url.host.lowercaseString;
    NSString *path = url.path;
    NSString *meth = self.request.HTTPMethod.uppercaseString;
    DevSettings *s = DevSettings.shared;
    NSData *data   = nil;

    if ([host isEqualToString:@"i.imgur.com"]) {
        NSString *rep = [ImgurLinkStore.shared replacementFor:url.absoluteString];
        NSURL *repURL = [NSURL URLWithString:rep];
        if (repURL) {
            NSMutableURLRequest *fwd = [NSMutableURLRequest requestWithURL:repURL];
            [NSURLProtocol setProperty:@YES forKey:@"DevHookDone" inRequest:fwd];
            [[[NSURLSession sharedSession] dataTaskWithRequest:fwd
                                             completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                if (d && r) {
                    [self.client URLProtocol:self didReceiveResponse:r
                          cacheStoragePolicy:NSURLCacheStorageNotAllowed];
                    [self.client URLProtocol:self didLoadData:d];
                    [self.client URLProtocolDidFinishLoading:self];
                } else {
                    [self.client URLProtocol:self didFailWithError:
                     e ?: [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorUnknown userInfo:nil]];
                }
            }] resume];
            return;
        }
    } else if ([path isEqualToString:@"/check_connection.php"]) {
        NSMutableDictionary *d = [[s jsonDictForKey:kJsonConnection] mutableCopy];
        d[@"timestamp"] = @((long long)[[NSDate date] timeIntervalSince1970]);
        data = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
    } else if ([path isEqualToString:@"/apitab.php"]) {
        NSMutableDictionary *d = [[s jsonDictForKey:kJsonTabs] mutableCopy];
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSDateFormatter *fmt = [NSDateFormatter new]; fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        d[@"server_time"]     = @((long long)now);
        d[@"server_datetime"] = [fmt stringFromDate:[NSDate date]];
        data = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
    } else if ([meth isEqualToString:@"GET"] &&
               [url.query containsString:@"action=get_notifications"]) {
        data = [NSJSONSerialization dataWithJSONObject:
                [s jsonDictForKey:kJsonNotifications] options:0 error:nil];
    } else if ([meth isEqualToString:@"POST"]) {
        NSString *body = [HookURLProtocol _bodyOf:self.request];
        NSDictionary *dict = [body containsString:@"action=check_hud_control"]
            ? [s jsonDictForKey:kJsonCheckHud] : [s jsonDictForKey:kJsonValidate];
        data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    }

    if (!data) data = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc]
        initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1"
        headerFields:@{
            @"Content-Type":   @"application/json",
            @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)data.length],
            @"X-Dev-Hook":     @"1"
        }];
    [self.client URLProtocol:self didReceiveResponse:resp
          cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

// ═══════════════════════════════════════════════════════════════
// MARK: - DevOverlayPanel
//
// A custom floating card rendered directly on the key window.
// Tapping the DEV button toggles it. Tapping outside dismisses.
// Internal navigation uses a lightweight push/pop stack that
// slides content horizontally inside the card — no UINavController.
//
// Card layout:
//  ┌─────────────────────────────┐
//  │ ● Dev API Hook          [✕] │  ← dark header (always visible)
//  ├─────────────────────────────┤
//  │ [‹ Back]    Sub-title       │  ← sub-nav (hidden on root)
//  ├─────────────────────────────┤
//  │                             │
//  │        content area         │  ← clips & slides per screen
//  │                             │
//  └─────────────────────────────┘
// ═══════════════════════════════════════════════════════════════

// ─── Section model ────────────────────────────────────────────
typedef NS_ENUM(NSInteger, OverlaySec) {
    OSecIcon = 0, OSecImgur,
    OSecCheckHud, OSecValidate, OSecNotifications, OSecConnection, OSecTabs,
    OSecCount
};

static NSString *OSecTitle(OverlaySec s) {
    switch(s){
        case OSecIcon:          return @"Menu Icon";
        case OSecImgur:         return @"Imgur Hook";
        case OSecCheckHud:      return @"Check HUD";
        case OSecValidate:      return @"Validate Key";
        case OSecNotifications: return @"Notifications";
        case OSecConnection:    return @"Connection";
        case OSecTabs:          return @"Tabs";
        default:                return @"";
    }
}
static NSString *OSecHookKey(OverlaySec s) {
    switch(s){
        case OSecCheckHud:      return kHookCheckHud;
        case OSecValidate:      return kHookValidate;
        case OSecNotifications: return kHookNotifications;
        case OSecConnection:    return kHookConnection;
        case OSecTabs:          return kHookTabs;
        default:                return nil;
    }
}
static NSString *OSecJsonKey(OverlaySec s) {
    switch(s){
        case OSecCheckHud:      return kJsonCheckHud;
        case OSecValidate:      return kJsonValidate;
        case OSecNotifications: return kJsonNotifications;
        case OSecConnection:    return kJsonConnection;
        case OSecTabs:          return kJsonTabs;
        default:                return nil;
    }
}
static NSString *OSecFooter(OverlaySec s) {
    switch(s){
        case OSecIcon:          return @"Image shown on the floating button.";
        case OSecImgur:         return @"imgur requests are auto-logged. Enable hook + set replacements to redirect.";
        case OSecCheckHud:      return @"POST /api.php  action=check_hud_control";
        case OSecValidate:      return @"POST /api.php  action=validate + key + hwid";
        case OSecNotifications: return @"GET  /api.php?action=get_notifications";
        case OSecConnection:    return @"GET  /check_connection.php";
        case OSecTabs:          return @"GET  /apitab.php";
        default:                return @"";
    }
}

static const CGFloat kPanelW      = 300.f;
static const CGFloat kPanelH      = 480.f;
static const CGFloat kPanelRadius = 18.f;
static const CGFloat kHeaderH     = 48.f;
static const CGFloat kSubNavH     = 38.f;

// ─── Tag constants for sub-tables ────────────────────────────
static const NSInteger kTagImgurTable = 1001;

@interface DevOverlayPanel : UIView
    <UITableViewDataSource, UITableViewDelegate,
     UIImagePickerControllerDelegate, UINavigationControllerDelegate>

// Overlay chrome
@property (nonatomic, strong) UIView   *dimView;
@property (nonatomic, strong) UIView   *card;
@property (nonatomic, strong) UILabel  *headerTitle;
@property (nonatomic, strong) UIView   *subNavBar;
@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) UILabel  *subNavTitle;
@property (nonatomic, strong) UIView   *contentContainer;

// Nav stack
@property (nonatomic, strong) NSMutableArray<UIView *>   *navStack;
@property (nonatomic, strong) NSMutableArray<NSString *> *titleStack;

// Root table
@property (nonatomic, strong) UITableView *rootTable;

// Imgur sub-screen state
@property (nonatomic, strong) NSArray<NSString *> *imgurKeys;

// JSON editor state
@property (nonatomic, copy)   NSString    *editingJsonKey;
@property (nonatomic, strong) UITextView  *jsonTV;
@property (nonatomic, strong) UILabel     *jsonStatus;

+ (instancetype)shared;
- (void)show;
- (void)dismiss;
@end

@implementation DevOverlayPanel

+ (instancetype)shared {
    static DevOverlayPanel *p; static dispatch_once_t t;
    dispatch_once(&t, ^{ p = [DevOverlayPanel new]; });
    return p;
}

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _navStack   = [NSMutableArray new];
    _titleStack = [NSMutableArray new];
    [self _buildChrome];
    return self;
}

// ─────────────────────────────────────────────────────────────
// MARK: Build chrome
// ─────────────────────────────────────────────────────────────

- (void)_buildChrome {
    // Dim backdrop
    _dimView = [[UIView alloc] initWithFrame:CGRectZero];
    _dimView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    _dimView.alpha = 0;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(dismiss)];
    [_dimView addGestureRecognizer:tap];

    // Card
    _card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPanelW, kPanelH)];
    _card.backgroundColor    = UIColor.systemGroupedBackgroundColor;
    _card.layer.cornerRadius = kPanelRadius;
    _card.layer.shadowColor  = UIColor.blackColor.CGColor;
    _card.layer.shadowRadius = 28;
    _card.layer.shadowOpacity = 0.30f;
    _card.layer.shadowOffset = CGSizeMake(0, 10);
    _card.clipsToBounds = NO;

    // ── Header ────────────────────────────────────────────────
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPanelW, kHeaderH)];
    header.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.07 alpha:0.97];
    header.layer.cornerRadius = kPanelRadius;
    header.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;

    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(14, 17, 14, 14)];
    dot.backgroundColor    = [UIColor colorWithRed:0.25 green:1.0 blue:0.45 alpha:1];
    dot.layer.cornerRadius = 7;
    [header addSubview:dot];

    _headerTitle = [[UILabel alloc] initWithFrame:CGRectMake(36, 0, kPanelW - 80, kHeaderH)];
    _headerTitle.text      = @"Dev API Hook";
    _headerTitle.font      = [UIFont boldSystemFontOfSize:15];
    _headerTitle.textColor = [UIColor colorWithRed:0.25 green:1.0 blue:0.45 alpha:1];
    [header addSubview:_headerTitle];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(kPanelW - 44, 0, 44, kHeaderH);
    [closeBtn setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    closeBtn.tintColor = [UIColor colorWithWhite:1 alpha:0.55];
    [closeBtn addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:closeBtn];
    [_card addSubview:header];

    // ── Sub-nav bar ───────────────────────────────────────────
    _subNavBar = [[UIView alloc] initWithFrame:CGRectMake(0, kHeaderH, kPanelW, kSubNavH)];
    _subNavBar.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _subNavBar.hidden = YES;

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, kSubNavH - 0.5, kPanelW, 0.5)];
    sep.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.2];
    [_subNavBar addSubview:sep];

    _backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _backBtn.frame = CGRectMake(0, 0, 80, kSubNavH);
    [_backBtn setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    [_backBtn setTitle:@"Back" forState:UIControlStateNormal];
    _backBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    _backBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    _backBtn.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 0);
    [_backBtn addTarget:self action:@selector(_popScreen) forControlEvents:UIControlEventTouchUpInside];
    [_subNavBar addSubview:_backBtn];

    _subNavTitle = [[UILabel alloc] initWithFrame:CGRectMake(80, 0, kPanelW - 160, kSubNavH)];
    _subNavTitle.textAlignment = NSTextAlignmentCenter;
    _subNavTitle.font          = [UIFont boldSystemFontOfSize:14];
    _subNavTitle.textColor     = UIColor.labelColor;
    [_subNavBar addSubview:_subNavTitle];
    [_card addSubview:_subNavBar];

    // ── Content container ─────────────────────────────────────
    _contentContainer = [[UIView alloc] initWithFrame:
        CGRectMake(0, kHeaderH, kPanelW, kPanelH - kHeaderH)];
    _contentContainer.clipsToBounds = YES;
    [_card addSubview:_contentContainer];
}

// ─────────────────────────────────────────────────────────────
// MARK: Show / Dismiss
// ─────────────────────────────────────────────────────────────

- (void)show {
    UIWindow *win = [self _win]; if (!win) return;
    if (self.superview) { [win bringSubviewToFront:self]; return; }

    self.frame    = win.bounds;
    _dimView.frame = win.bounds;
    [self addSubview:_dimView];

    // Position card: anchored top-right below status bar
    UIEdgeInsets safe = win.safeAreaInsets;
    CGFloat cardX = win.bounds.size.width  - kPanelW - 16 - safe.right;
    CGFloat cardY = safe.top + 10;
    cardX = MAX(8, cardX);
    if (cardY + kPanelH > win.bounds.size.height - 20)
        cardY = win.bounds.size.height - kPanelH - 20;
    _card.frame     = CGRectMake(cardX, cardY, kPanelW, kPanelH);
    _card.transform = CGAffineTransformMakeScale(0.86, 0.86);
    _card.alpha     = 0;
    [self addSubview:_card];

    // Reset to root
    [_navStack removeAllObjects];
    [_titleStack removeAllObjects];
    for (UIView *v in _contentContainer.subviews) [v removeFromSuperview];
    _contentContainer.frame = CGRectMake(0, kHeaderH, kPanelW, kPanelH - kHeaderH);
    _subNavBar.hidden = YES;
    [self _buildRootTable];

    [win addSubview:self];

    [UIView animateWithDuration:0.30 delay:0
           usingSpringWithDamping:0.74 initialSpringVelocity:0.4 options:0
                       animations:^{
        self->_dimView.alpha = 1;
        self->_card.alpha    = 1;
        self->_card.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dismiss {
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self->_dimView.alpha = 0;
        self->_card.alpha    = 0;
        self->_card.transform = CGAffineTransformMakeScale(0.88, 0.88);
    } completion:^(BOOL done) {
        [self removeFromSuperview];
        for (UIView *v in self->_contentContainer.subviews) [v removeFromSuperview];
        [self->_navStack removeAllObjects];
        [self->_titleStack removeAllObjects];
        self->_subNavBar.hidden = YES;
    }];
}

// ─────────────────────────────────────────────────────────────
// MARK: Root table
// ─────────────────────────────────────────────────────────────

- (void)_buildRootTable {
    _rootTable = [[UITableView alloc] initWithFrame:_contentContainer.bounds
                                              style:UITableViewStyleInsetGrouped];
    _rootTable.dataSource       = self;
    _rootTable.delegate         = self;
    _rootTable.backgroundColor  = UIColor.clearColor;
    _rootTable.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_contentContainer addSubview:_rootTable];
}

// ─────────────────────────────────────────────────────────────
// MARK: Internal push / pop (horizontal slide)
// ─────────────────────────────────────────────────────────────

- (void)_pushView:(UIView *)newView title:(NSString *)title {
    UIView *outgoing = _contentContainer.subviews.lastObject;

    // Expand content container to add sub-nav space on first push
    if (_navStack.count == 0) {
        _contentContainer.frame = CGRectMake(0, kHeaderH + kSubNavH,
                                             kPanelW, kPanelH - kHeaderH - kSubNavH);
    }
    newView.frame = CGRectMake(kPanelW, 0, kPanelW, _contentContainer.bounds.size.height);
    [_contentContainer addSubview:newView];

    [_navStack   addObject:newView];
    [_titleStack addObject:title ?: @""];
    _subNavTitle.text = title;
    _subNavBar.hidden = NO;

    CGRect outgoingDest = CGRectMake(-kPanelW, 0, kPanelW, _contentContainer.bounds.size.height);
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        outgoing.frame = outgoingDest;
        newView.frame  = self->_contentContainer.bounds;
    } completion:nil];
}

- (void)_popScreen {
    if (_navStack.count == 0) return;

    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:UITextViewTextDidChangeNotification object:_jsonTV];

    UIView *outgoing = _navStack.lastObject;
    [_navStack   removeLastObject];
    [_titleStack removeLastObject];

    BOOL goingToRoot = (_navStack.count == 0);
    UIView *incoming = goingToRoot ? _rootTable : _navStack.lastObject;

    incoming.frame = CGRectMake(-kPanelW, 0, kPanelW, _contentContainer.bounds.size.height);
    [_contentContainer addSubview:incoming];

    if (goingToRoot) {
        _subNavBar.hidden = YES;
        _contentContainer.frame = CGRectMake(0, kHeaderH, kPanelW, kPanelH - kHeaderH);
        incoming.frame = CGRectMake(-kPanelW, 0, kPanelW, _contentContainer.bounds.size.height);
    } else {
        _subNavTitle.text = _titleStack.lastObject;
    }

    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        outgoing.frame = CGRectMake(kPanelW, 0, kPanelW, self->_contentContainer.bounds.size.height);
        incoming.frame = self->_contentContainer.bounds;
    } completion:^(BOOL done) {
        [outgoing removeFromSuperview];
        if (goingToRoot) [self->_rootTable reloadData];
    }];
}

// ─────────────────────────────────────────────────────────────
// MARK: UITableView DataSource / Delegate
// ─────────────────────────────────────────────────────────────

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    if (tv == _rootTable) return OSecCount;
    return 1;
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)sec {
    if (tv == _rootTable) {
        if (sec == OSecIcon)  return 3;
        if (sec == OSecImgur) return 2;
        return 2;
    }
    // Imgur sub-table
    return MAX(1, (NSInteger)_imgurKeys.count);
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)sec {
    if (tv == _rootTable) return OSecTitle((OverlaySec)sec);
    return [NSString stringWithFormat:@"%lu URL%@ captured",
            (unsigned long)_imgurKeys.count, _imgurKeys.count == 1 ? @"" : @"s"];
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)sec {
    if (tv == _rootTable) return OSecFooter((OverlaySec)sec);
    return @"Tap to set replacement. Swipe left to delete.";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {

    // ── Imgur sub-table ───────────────────────────────────────
    if (tv != _rootTable) {
        UITableViewCell *c = [[UITableViewCell alloc]
            initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"I"];
        if (_imgurKeys.count == 0) {
            c.textLabel.text      = @"No imgur links captured yet";
            c.textLabel.textColor = UIColor.secondaryLabelColor;
            c.userInteractionEnabled = NO;
            return c;
        }
        NSString *key = _imgurKeys[ip.row];
        NSString *rep = [ImgurLinkStore.shared replacementFor:key];
        BOOL hasRep   = rep.length > 0;
        c.textLabel.text = key.lastPathComponent;
        c.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
        c.detailTextLabel.numberOfLines = 2;
        c.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
        if (hasRep) {
            c.detailTextLabel.text      = [NSString stringWithFormat:@"→ %@", rep];
            c.detailTextLabel.textColor = UIColor.systemGreenColor;
            c.imageView.image           = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"];
            c.imageView.tintColor       = UIColor.systemGreenColor;
        } else {
            c.detailTextLabel.text      = key;
            c.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            c.imageView.image           = [UIImage systemImageNamed:@"photo"];
            c.imageView.tintColor       = UIColor.systemGrayColor;
        }
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }

    // ── Root table ────────────────────────────────────────────
    DevSettings *s  = DevSettings.shared;
    UITableViewCell *c = [[UITableViewCell alloc]
        initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"R"];
    OverlaySec sec = (OverlaySec)ip.section;

    if (sec == OSecIcon) {
        if (ip.row == 0) {
            c.textLabel.text       = @"Icon URL";
            NSString *u            = [s stringForKey:kIconURL];
            c.detailTextLabel.text = u.length ? u.lastPathComponent : @"Not set";
            c.accessoryType        = UITableViewCellAccessoryDisclosureIndicator;
        } else if (ip.row == 1) {
            c.textLabel.text  = @"Load from Photos";
            c.imageView.image = [UIImage systemImageNamed:@"photo.on.rectangle"];
            c.accessoryType   = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            c.textLabel.text = @"Preview Icon";
            UIImage *img = [self _localIcon];
            if (img) {
                UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0,0,34,34)];
                iv.image = img; iv.contentMode = UIViewContentModeScaleAspectFill;
                iv.clipsToBounds = YES; iv.layer.cornerRadius = 7;
                c.accessoryView = iv;
            } else {
                c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
        }
        return c;
    }

    if (sec == OSecImgur) {
        if (ip.row == 0) {
            c.textLabel.text      = @"Apply Replacements";
            UISwitch *sw          = [UISwitch new];
            sw.on                 = [s isEnabled:kHookImgur];
            [sw addTarget:self action:@selector(_imgurToggle:)
                forControlEvents:UIControlEventValueChanged];
            c.accessoryView       = sw;
            c.selectionStyle      = UITableViewCellSelectionStyleNone;
        } else {
            NSUInteger n           = ImgurLinkStore.shared.allKeys.count;
            c.textLabel.text       = @"Manage Links";
            c.detailTextLabel.text = [NSString stringWithFormat:@"%lu captured", (unsigned long)n];
            c.imageView.image      = [UIImage systemImageNamed:@"link.badge.plus"];
            c.accessoryType        = UITableViewCellAccessoryDisclosureIndicator;
        }
        return c;
    }

    // API sections
    NSString *hk = OSecHookKey(sec);
    if (ip.row == 0) {
        c.textLabel.text      = @"Enable Hook";
        UISwitch *sw          = [UISwitch new];
        sw.on                 = hk ? [s isEnabled:hk] : NO;
        sw.tag                = (NSInteger)sec * 10;
        [sw addTarget:self action:@selector(_apiToggle:)
            forControlEvents:UIControlEventValueChanged];
        c.accessoryView       = sw;
        c.selectionStyle      = UITableViewCellSelectionStyleNone;
    } else {
        c.textLabel.text  = @"Edit Response JSON";
        c.imageView.image = [UIImage systemImageNamed:@"doc.text"];
        c.accessoryType   = UITableViewCellAccessoryDisclosureIndicator;
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];

    // ── Imgur sub-table ───────────────────────────────────────
    if (tv != _rootTable) {
        if (_imgurKeys.count == 0) return;
        NSString *key = _imgurKeys[ip.row];
        NSString *cur = [ImgurLinkStore.shared replacementFor:key];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Set Replacement"
            message:key preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.text = cur; tf.placeholder = @"https://i.imgur.com/other.jpg";
            tf.autocorrectionType = UITextAutocorrectionTypeNo;
            tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
            tf.keyboardType = UIKeyboardTypeURL;
            tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        [a addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *_) {
            [ImgurLinkStore.shared setReplacement:@"" forKey:key];
            [self _reloadImgurTable:tv];
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_) {
            [ImgurLinkStore.shared setReplacement:(a.textFields.firstObject.text ?: @"") forKey:key];
            [self _reloadImgurTable:tv];
        }]];
        [[self _topVC] presentViewController:a animated:YES completion:nil];
        return;
    }

    // ── Root table ────────────────────────────────────────────
    OverlaySec sec = (OverlaySec)ip.section;

    if (sec == OSecIcon) {
        if (ip.row == 0) { [self _promptIconURL]; return; }
        if (ip.row == 1) { [self _pickPhoto];     return; }
        [self _previewIcon]; return;
    }
    if (sec == OSecImgur && ip.row == 1) { [self _pushImgurMap]; return; }
    if (ip.row == 1) {
        NSString *jk = OSecJsonKey(sec);
        if (jk) [self _pushJsonEditor:jk
                                title:[NSString stringWithFormat:@"%@ Response", OSecTitle(sec)]];
    }
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    return tv != _rootTable && _imgurKeys.count > 0;
}
- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)es
                                    forRowAtIndexPath:(NSIndexPath *)ip {
    if (es == UITableViewCellEditingStyleDelete) {
        [ImgurLinkStore.shared removeKey:_imgurKeys[ip.row]];
        [self _reloadImgurTable:tv];
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Toggle actions
// ─────────────────────────────────────────────────────────────

- (void)_imgurToggle:(UISwitch *)sw {
    [DevSettings.shared setEnabled:sw.on forKey:kHookImgur];
}
- (void)_apiToggle:(UISwitch *)sw {
    NSString *k = OSecHookKey((OverlaySec)(sw.tag / 10));
    if (k) [DevSettings.shared setEnabled:sw.on forKey:k];
}

// ─────────────────────────────────────────────────────────────
// MARK: Sub-screens
// ─────────────────────────────────────────────────────────────

// ── Imgur map ─────────────────────────────────────────────────
- (void)_pushImgurMap {
    _imgurKeys = [ImgurLinkStore.shared allKeys];

    UITableView *tv = [[UITableView alloc] initWithFrame:CGRectZero
                                                   style:UITableViewStyleInsetGrouped];
    tv.dataSource      = self;
    tv.delegate        = self;
    tv.backgroundColor = UIColor.clearColor;
    tv.tag             = kTagImgurTable;

    // "Clear All" header button
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [clearBtn setTitle:@"Clear All" forState:UIControlStateNormal];
    clearBtn.tintColor  = UIColor.systemRedColor;
    clearBtn.frame      = CGRectMake(0, 0, kPanelW, 36);
    [clearBtn addTarget:self action:@selector(_imgurClearAll:)
         forControlEvents:UIControlEventTouchUpInside];
    tv.tableHeaderView = clearBtn;

    [self _pushView:tv title:@"Imgur Links"];
}

- (void)_imgurClearAll:(id)sender {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Clear all imgur logs?"
        message:@"Replacements will also be removed."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Clear All" style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *_) {
        for (NSString *k in self->_imgurKeys) [ImgurLinkStore.shared removeKey:k];
        for (UIView *v in self->_navStack) {
            if ([v isKindOfClass:[UITableView class]] && v.tag == kTagImgurTable)
                [self _reloadImgurTable:(UITableView *)v];
        }
    }]];
    [[self _topVC] presentViewController:a animated:YES completion:nil];
}

- (void)_reloadImgurTable:(UITableView *)tv {
    _imgurKeys = [ImgurLinkStore.shared allKeys];
    [tv reloadData];
}

// ── JSON editor ───────────────────────────────────────────────
- (void)_pushJsonEditor:(NSString *)jsonKey title:(NSString *)title {
    _editingJsonKey = jsonKey;

    UIView *wrap = [[UIView alloc] initWithFrame:CGRectZero];
    wrap.backgroundColor = UIColor.systemBackgroundColor;

    _jsonTV = [[UITextView alloc] initWithFrame:CGRectZero];
    _jsonTV.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _jsonTV.text = [DevSettings.shared jsonStringForKey:jsonKey];
    _jsonTV.autocorrectionType      = UITextAutocorrectionTypeNo;
    _jsonTV.autocapitalizationType  = UITextAutocapitalizationTypeNone;
    _jsonTV.backgroundColor         = UIColor.systemBackgroundColor;
    [wrap addSubview:_jsonTV];

    _jsonStatus = [UILabel new];
    _jsonStatus.font          = [UIFont systemFontOfSize:11];
    _jsonStatus.textAlignment = NSTextAlignmentCenter;
    _jsonStatus.textColor     = UIColor.systemGreenColor;
    _jsonStatus.text          = @"✓ Valid JSON";
    [wrap addSubview:_jsonStatus];

    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [saveBtn setTitle:@"Save" forState:UIControlStateNormal];
    saveBtn.titleLabel.font   = [UIFont boldSystemFontOfSize:15];
    saveBtn.backgroundColor   = [UIColor colorWithRed:0.07 green:0.07 blue:0.07 alpha:0.92];
    saveBtn.layer.cornerRadius = 10;
    [saveBtn setTitleColor:[UIColor colorWithRed:0.25 green:1.0 blue:0.45 alpha:1]
                  forState:UIControlStateNormal];
    [saveBtn addTarget:self action:@selector(_saveJson)
            forControlEvents:UIControlEventTouchUpInside];
    [wrap addSubview:saveBtn];

    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(_jsonTextChanged)
        name:UITextViewTextDidChangeNotification object:_jsonTV];

    [self _pushView:wrap title:title];

    // Layout after push (frame is now valid)
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect b = wrap.bounds;
        self->_jsonTV.frame     = CGRectMake(0, 0, b.size.width, b.size.height - 80);
        self->_jsonStatus.frame = CGRectMake(0, b.size.height - 78, b.size.width, 20);
        saveBtn.frame           = CGRectMake(12, b.size.height - 52, b.size.width - 24, 40);
    });
}

- (void)_jsonTextChanged {
    NSData *d = [_jsonTV.text dataUsingEncoding:NSUTF8StringEncoding]; NSError *e;
    [NSJSONSerialization JSONObjectWithData:d options:0 error:&e];
    _jsonStatus.textColor = e ? UIColor.systemRedColor : UIColor.systemGreenColor;
    _jsonStatus.text = e ? [NSString stringWithFormat:@"✗ %@", e.localizedDescription]
                         : @"✓ Valid JSON";
}

- (void)_saveJson {
    NSData *d = [_jsonTV.text dataUsingEncoding:NSUTF8StringEncoding]; NSError *e;
    [NSJSONSerialization JSONObjectWithData:d options:0 error:&e];
    if (e) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Invalid JSON"
            message:e.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[self _topVC] presentViewController:a animated:YES completion:nil];
        return;
    }
    [DevSettings.shared setJsonString:_jsonTV.text forKey:_editingJsonKey];
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:UITextViewTextDidChangeNotification object:_jsonTV];
    [self _popScreen];
}

// ── Icon URL ──────────────────────────────────────────────────
- (void)_promptIconURL {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Icon URL"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text             = [DevSettings.shared stringForKey:kIconURL];
        tf.placeholder      = @"https://...";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.keyboardType     = UIKeyboardTypeURL;
        tf.clearButtonMode  = UITextFieldViewModeWhileEditing;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *_) {
        NSString *v = a.textFields.firstObject.text ?: @"";
        [DevSettings.shared setString:v forKey:kIconURL];
        [DevSettings.shared setEnabled:NO forKey:kIconUseLocal];
        [self->_rootTable reloadData];
        [DevMenuManager.shared refreshButtonIcon];
    }]];
    [[self _topVC] presentViewController:a animated:YES completion:nil];
}

// ── Photo picker ──────────────────────────────────────────────
- (void)_pickPhoto {
    UIImagePickerController *p = [UIImagePickerController new];
    p.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    p.delegate   = self;
    [[self _topVC] presentViewController:p animated:YES completion:nil];
}
- (void)imagePickerController:(UIImagePickerController *)p
      didFinishPickingMediaWithInfo:(NSDictionary *)info {
    [p dismissViewControllerAnimated:YES completion:nil];
    UIImage *img = info[UIImagePickerControllerOriginalImage]; if (!img) return;
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"dev_icon.jpg"];
    NSData *jpeg   = UIImageJPEGRepresentation(img, 0.9); if (!jpeg) return;
    [jpeg writeToFile:path atomically:YES];
    [DevSettings.shared setString:path forKey:kIconLocalPath];
    [DevSettings.shared setEnabled:YES forKey:kIconUseLocal];
    [_rootTable reloadData];
    [DevMenuManager.shared refreshButtonIcon];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)p {
    [p dismissViewControllerAnimated:YES completion:nil];
}

// ── Icon preview ──────────────────────────────────────────────
- (void)_previewIcon {
    UIImage *local = [self _localIcon];
    if (local) { [self _showPreview:local]; return; }
    NSString *urlStr = [DevSettings.shared stringForKey:kIconURL];
    if (!urlStr.length) return;
    NSURL *url = [NSURL URLWithString:urlStr]; if (!url) return;
    [[[NSURLSession sharedSession] dataTaskWithURL:url
                                 completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (!d) return; UIImage *img = [UIImage imageWithData:d]; if (!img) return;
        dispatch_async(dispatch_get_main_queue(), ^{ [self _showPreview:img]; });
    }] resume];
}
- (void)_showPreview:(UIImage *)img {
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectZero];
    wrap.backgroundColor = UIColor.blackColor;
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectZero];
    iv.image = img; iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [wrap addSubview:iv];
    [self _pushView:wrap title:@"Icon Preview"];
    dispatch_async(dispatch_get_main_queue(), ^{ iv.frame = wrap.bounds; });
}

// ─────────────────────────────────────────────────────────────
// MARK: Helpers
// ─────────────────────────────────────────────────────────────

- (UIImage *)_localIcon {
    if ([DevSettings.shared isEnabled:kIconUseLocal]) {
        NSString *p = [DevSettings.shared stringForKey:kIconLocalPath];
        if (p.length) return [UIImage imageWithContentsOfFile:p];
    }
    return nil;
}
- (UIWindow *)_win {
    UIWindow *found = nil;
    if (@available(iOS 15, *)) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)sc).windows) {
                if (w.isKeyWindow) { found = w; break; }
            }
            if (found) break;
        }
    }
    if (!found) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        found = UIApplication.sharedApplication.keyWindow;
#pragma clang diagnostic pop
    }
    return found;
}
- (UIViewController *)_topVC {
    return [self _topmostVC:[self _win].rootViewController];
}
- (UIViewController *)_topmostVC:(UIViewController *)root {
    if (!root) return nil;
    if (root.presentedViewController) return [self _topmostVC:root.presentedViewController];
    if ([root isKindOfClass:[UINavigationController class]])
        return [self _topmostVC:((UINavigationController *)root).visibleViewController] ?: root;
    if ([root isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tab = (UITabBarController *)root;
        return tab.selectedViewController ? [self _topmostVC:tab.selectedViewController] : root;
    }
    return root;
}
@end

// ═══════════════════════════════════════════════════════════════
// MARK: - Floating Button
// ═══════════════════════════════════════════════════════════════

static const CGFloat kBtnSize = 60.f;

@interface DevFloatingBtn : UIButton
- (void)refreshIcon;
@end
@implementation DevFloatingBtn

- (instancetype)initWithFrame:(CGRect)f {
    if (CGRectIsEmpty(f)) f = CGRectMake(0, 0, kBtnSize, kBtnSize);
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.layer.cornerRadius  = f.size.width / 2;
    self.layer.shadowColor   = UIColor.blackColor.CGColor;
    self.layer.shadowRadius  = 10;
    self.layer.shadowOpacity = 0.55f;
    self.layer.shadowOffset  = CGSizeMake(0, 4);
    self.clipsToBounds       = NO;
    self.layer.borderColor   = [UIColor colorWithWhite:1 alpha:0.2].CGColor;
    self.layer.borderWidth   = 1.5f;
    [self _applyGlyph];
    [self refreshIcon];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(_pan:)];
    [self addGestureRecognizer:pan];
    return self;
}

- (void)refreshIcon {
    DevSettings *s = DevSettings.shared;
    if ([s isEnabled:kIconUseLocal]) {
        NSString *p = [s stringForKey:kIconLocalPath];
        if (p.length) {
            UIImage *img = [UIImage imageWithContentsOfFile:p];
            if (img) { [self _applyImage:img]; return; }
        }
    }
    NSString *urlStr = [s stringForKey:kIconURL];
    if (urlStr.length) {
        NSURL *url = [NSURL URLWithString:urlStr];
        if (url) {
            [self _applyGlyph];
            [[[NSURLSession sharedSession] dataTaskWithURL:url
                                         completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                if (!d) return; UIImage *img = [UIImage imageWithData:d]; if (!img) return;
                dispatch_async(dispatch_get_main_queue(), ^{ [self _applyImage:img]; });
            }] resume];
            return;
        }
    }
    [self _applyGlyph];
}

- (void)_applyImage:(UIImage *)src {
    if (!src) { [self _applyGlyph]; return; }
    CGFloat sz = self.bounds.size.width; if (sz <= 0) sz = kBtnSize;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(sz, sz), NO, 0);
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0,0,sz,sz)] addClip];
    [src drawInRect:CGRectMake(0,0,sz,sz)];
    UIImage *round = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!round) { [self _applyGlyph]; return; }
    [self setImage:round forState:UIControlStateNormal];
    self.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.backgroundColor       = UIColor.clearColor;
    for (UIView *v in self.subviews)
        if ([v isKindOfClass:[UILabel class]] && v.tag == 999) [v removeFromSuperview];
}

- (void)_applyGlyph {
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightMedium];
    [self setImage:[UIImage systemImageNamed:@"ant.circle.fill" withConfiguration:cfg]
          forState:UIControlStateNormal];
    self.tintColor       = [UIColor colorWithRed:0.25 green:1.0 blue:0.45 alpha:1];
    self.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.07 alpha:0.92];
    if (![self viewWithTag:999]) {
        UILabel *lb = [UILabel new]; lb.tag = 999;
        lb.text = @"DEV"; lb.font = [UIFont boldSystemFontOfSize:7];
        lb.textColor = [UIColor colorWithRed:0.25 green:1.0 blue:0.45 alpha:1];
        lb.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:lb];
        [NSLayoutConstraint activateConstraints:@[
            [lb.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [lb.bottomAnchor  constraintEqualToAnchor:self.bottomAnchor constant:-6]
        ]];
    }
}

- (void)_pan:(UIPanGestureRecognizer *)gr {
    UIView *sv = self.superview; if (!sv) return;
    CGPoint dt = [gr translationInView:sv];
    CGFloat r  = self.bounds.size.width / 2;
    UIEdgeInsets safe = sv.safeAreaInsets;
    self.center = CGPointMake(
        MAX(r + 8,            MIN(sv.bounds.size.width  - r - 8,               self.center.x + dt.x)),
        MAX(r + 8 + safe.top, MIN(sv.bounds.size.height - r - 8 - safe.bottom, self.center.y + dt.y))
    );
    [gr setTranslation:CGPointZero inView:sv];
    if (gr.state == UIGestureRecognizerStateEnded) {
        CGFloat snapX = (self.center.x < sv.bounds.size.width / 2)
            ? r + 12 : sv.bounds.size.width - r - 12;
        [UIView animateWithDuration:0.28 delay:0
               usingSpringWithDamping:0.7 initialSpringVelocity:0 options:0
                           animations:^{ self.center = CGPointMake(snapX, self.center.y); }
                           completion:nil];
    }
}
@end

// ═══════════════════════════════════════════════════════════════
// MARK: - DevMenuManager
// ═══════════════════════════════════════════════════════════════

@interface DevMenuManager : NSObject
@property (nonatomic, weak) DevFloatingBtn *btn;
+ (instancetype)shared;
- (void)install;
- (void)refreshButtonIcon;
- (void)openMenu;
@end

@implementation DevMenuManager {
    BOOL _installed;
    id   _becomeActiveObserver;
}

+ (instancetype)shared {
    static DevMenuManager *m; static dispatch_once_t t;
    dispatch_once(&t, ^{ m = [DevMenuManager new]; });
    return m;
}

- (UIWindow *)_win {
    UIWindow *found = nil;
    if (@available(iOS 15, *)) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)sc).windows) {
                if (w.isKeyWindow) { found = w; break; }
            }
            if (found) break;
        }
    }
    if (!found) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        found = UIApplication.sharedApplication.keyWindow;
#pragma clang diagnostic pop
    }
    return found;
}

- (void)install {
    if (_installed) return;
    __weak typeof(self) weak = self;
    _becomeActiveObserver =
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *n) {
            __strong typeof(weak) strong = weak;
            if (!strong || strong->_installed) return;
            UIWindow *win = [strong _win]; if (!win) return;
            strong->_installed = YES;
            [[NSNotificationCenter defaultCenter] removeObserver:strong->_becomeActiveObserver];
            strong->_becomeActiveObserver = nil;
            CGFloat sz = kBtnSize;
            CGFloat x  = win.bounds.size.width  - sz - 14;
            CGFloat y  = win.bounds.size.height  - sz - 120;
            DevFloatingBtn *b = [[DevFloatingBtn alloc] initWithFrame:CGRectMake(x, y, sz, sz)];
            b.autoresizingMask =
                UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
            [b addTarget:strong action:@selector(openMenu)
                forControlEvents:UIControlEventTouchUpInside];
            [win addSubview:b];
            strong.btn = b;
        }];
}

- (void)refreshButtonIcon {
    dispatch_async(dispatch_get_main_queue(), ^{ [self.btn refreshIcon]; });
}

- (void)openMenu {
    DevOverlayPanel *panel = DevOverlayPanel.shared;
    UIWindow *win = [self _win];
    if (panel.superview) {
        [panel dismiss];
    } else {
        [panel show];
        // Keep floating button on top of the overlay
        if (win && _btn) [win bringSubviewToFront:(UIView *)_btn];
    }
}
@end

// ═══════════════════════════════════════════════════════════════
// MARK: - Bootstrap
// ═══════════════════════════════════════════════════════════════

static void RegisterHook(void) {
    static dispatch_once_t t;
    dispatch_once(&t, ^{ [NSURLProtocol registerClass:[HookURLProtocol class]]; });
}

__attribute__((constructor(101))) static void init_dev_hook(void) {
    RegisterHook();
    [[DevMenuManager shared] install];
}

%hook NSURLSessionConfiguration
- (NSArray *)protocolClasses {
    NSArray *orig = %orig;
    NSMutableArray *a = [NSMutableArray arrayWithObject:[HookURLProtocol class]];
    if (orig) for (id cls in orig) { if (cls != [HookURLProtocol class]) [a addObject:cls]; }
    return [a copy];
}
%end

%hook NSURLSession
+ (NSURLSession *)sharedSession { RegisterHook(); return %orig; }
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)r {
    RegisterHook(); return %orig;
}
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)r
                           completionHandler:(void(^)(NSData*,NSURLResponse*,NSError*))c {
    RegisterHook(); return %orig;
}
%end

%hook NSURLConnection
+ (instancetype)connectionWithRequest:(NSURLRequest *)r delegate:(id)d {
    RegisterHook(); return %orig;
}
%end

%ctor { RegisterHook(); }
