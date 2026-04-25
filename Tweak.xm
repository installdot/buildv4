// DevApiHook.xm  —  v2
// • Auto-logs every i.imgur.com URL seen at runtime
// • Per-URL replacement map (saved, persists across launches)
// • New imgur links appear automatically in the Manage Links screen
// • Floating icon button → main menu → Imgur map / JSON editors / toggles

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
static NSString *const kHookImgur         = @"hook_imgur";   // master: apply replacements

static NSString *const kJsonCheckHud      = @"json_check_hud";
static NSString *const kJsonValidate      = @"json_validate";
static NSString *const kJsonNotifications = @"json_notifications";
static NSString *const kJsonConnection    = @"json_connection";
static NSString *const kJsonTabs          = @"json_tabs";

// Imgur: dict { normalizedOriginalURL -> replacementURL or "" }
static NSString *const kImgurMap          = @"imgur_url_map";

static NSString *const kIconURL           = @"icon_url";
static NSString *const kIconLocalPath     = @"icon_local_path";
static NSString *const kIconUseLocal      = @"icon_use_local";

// ═══════════════════════════════════════════════════════════════
// MARK: - ImgurLinkStore
// Logs every i.imgur.com URL seen; stores per-URL replacements
// ═══════════════════════════════════════════════════════════════

@interface ImgurLinkStore : NSObject
+ (instancetype)shared;
- (void)logURL:(NSString *)rawURL;
- (NSString *)replacementFor:(NSString *)rawURL;   // "" = no replacement
- (void)setReplacement:(NSString *)rep forKey:(NSString *)normalizedURL;
- (void)removeKey:(NSString *)normalizedURL;
- (NSArray<NSString *> *)allKeys;                  // sorted normalized URLs
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

// Strip query/fragment; keep scheme+host+path as the stable key
- (NSString *)normalizeURL:(NSString *)raw {
    NSURL *u = [NSURL URLWithString:raw];
    if (!u) return raw;
    return [NSString stringWithFormat:@"%@://%@%@",
            u.scheme ?: @"https",
            u.host   ?: @"i.imgur.com",
            u.path   ?: @"/"];
}

- (void)logURL:(NSString *)rawURL {
    if (!rawURL.length) return;
    NSString *key = [self normalizeURL:rawURL];
    @synchronized (self) {
        if (_map[key] == nil) {
            _map[key] = @"";
            [self _save];
        }
    }
}

- (NSString *)replacementFor:(NSString *)rawURL {
    NSString *key = [self normalizeURL:rawURL];
    @synchronized (self) { return _map[key] ?: @""; }
}

- (void)setReplacement:(NSString *)rep forKey:(NSString *)key {
    @synchronized (self) {
        _map[key] = rep ?: @"";
        [self _save];
    }
}

- (void)removeKey:(NSString *)key {
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
// MARK: - DevSettings
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
    NSData *data = [NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingPrettyPrinted error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (void)_registerDefaults {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"yyyy-MM-dd HH:mm:ss";

    NSDictionary *defs = @{
        kHookCheckHud: @YES, kHookValidate: @YES,
        kHookNotifications: @YES, kHookConnection: @YES,
        kHookTabs: @YES, kHookImgur: @YES,
        kIconURL: @"", kIconUseLocal: @NO,

        kJsonCheckHud: [self _pretty:@{
            @"success": @YES, @"hud_enabled": @YES,
            @"message": @"HUD Control is active",
            @"reason":  @"Admin is testing the remote control feature. This will be re-enabled shortly."
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
            @"server_time": @((long long)now), @"server_datetime": [f stringFromDate:[NSDate date]],
            @"tabs": @{
                @"aimbot": @1, @"esp": @1, @"msl": @1, @"weapons": @1,
                @"profile": @1, @"other": @YES, @"kill_switch": @0,
                @"shield": @0, @"video_set": @0, @"troll_enabled": @0
            },
            @"signin_button": @YES, @"key_field": @YES, @"start_button": @YES, @"music_enabled": @NO,
            @"main_tabs": @{ @"home": @YES, @"notifications": @YES, @"account": @YES, @"settings": @YES }
        }],
    };
    [_ud registerDefaults:defs];
}

- (BOOL)isEnabled:(NSString *)k              { return [_ud boolForKey:k]; }
- (void)setEnabled:(BOOL)v forKey:(NSString *)k { [_ud setBool:v forKey:k]; [_ud synchronize]; }
- (NSString *)jsonStringForKey:(NSString *)k { return [_ud stringForKey:k] ?: @"{}"; }
- (void)setJsonString:(NSString *)s forKey:(NSString *)k { [_ud setObject:s forKey:k]; [_ud synchronize]; }
- (NSDictionary *)jsonDictForKey:(NSString *)k {
    NSData *d = [[_ud stringForKey:k] dataUsingEncoding:NSUTF8StringEncoding];
    return d ? ([NSJSONSerialization JSONObjectWithData:d options:0 error:nil] ?: @{}) : @{};
}
- (NSString *)stringForKey:(NSString *)k { return [_ud stringForKey:k] ?: @""; }
- (void)setString:(NSString *)s forKey:(NSString *)k { [_ud setObject:s forKey:k]; [_ud synchronize]; }

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
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"";
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)req {
    NSURL *url = req.URL; if (!url) return NO;
    if ([NSURLProtocol propertyForKey:@"DevHookDone" inRequest:req]) return NO;
    NSString *host = url.host.lowercaseString;
    NSString *path = url.path;
    NSString *meth = req.HTTPMethod.uppercaseString;
    DevSettings *s = DevSettings.shared;

    // ── imgur: always log, intercept only if replacement exists ──
    if ([host isEqualToString:@"i.imgur.com"]) {
        [ImgurLinkStore.shared logURL:url.absoluteString];
        if (![s isEnabled:kHookImgur]) return NO;
        return [ImgurLinkStore.shared replacementFor:url.absoluteString].length > 0;
    }

    if (![host isEqualToString:@"api.cheatiosvip.vn"]) return NO;
    if ([s isEnabled:kHookConnection] && [path isEqualToString:@"/check_connection.php"]) return YES;
    if ([s isEnabled:kHookTabs]       && [path isEqualToString:@"/apitab.php"])           return YES;
    if ([path isEqualToString:@"/api.php"]) {
        if ([meth isEqualToString:@"GET"] && [s isEnabled:kHookNotifications] &&
            [url.query containsString:@"action=get_notifications"])                        return YES;
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
    NSMutableURLRequest *tagged = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"DevHookDone" inRequest:tagged];

    NSURL *url   = self.request.URL;
    NSString *host = url.host.lowercaseString;
    NSString *path = url.path;
    NSString *meth = self.request.HTTPMethod.uppercaseString;
    DevSettings *s = DevSettings.shared;
    NSData *data   = nil;

    // ── Imgur redirect ──────────────────────────────────────
    if ([host isEqualToString:@"i.imgur.com"]) {
        NSString *rep = [ImgurLinkStore.shared replacementFor:url.absoluteString];
        NSURL *repURL = [NSURL URLWithString:rep];
        if (repURL) {
            [[[NSURLSession sharedSession] dataTaskWithURL:repURL completionHandler:
              ^(NSData *d, NSURLResponse *r, NSError *e) {
                if (d && r) {
                    [self.client URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
                    [self.client URLProtocol:self didLoadData:d];
                    [self.client URLProtocolDidFinishLoading:self];
                } else {
                    [self.client URLProtocol:self didFailWithError:
                     e ?: [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil]];
                }
            }] resume];
            return;
        }
    }

    // ── check_connection — live timestamp ───────────────────
    else if ([path isEqualToString:@"/check_connection.php"]) {
        NSMutableDictionary *d = [[s jsonDictForKey:kJsonConnection] mutableCopy];
        d[@"timestamp"] = @((long long)[[NSDate date] timeIntervalSince1970]);
        data = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
    }
    // ── apitab — live timestamp ─────────────────────────────
    else if ([path isEqualToString:@"/apitab.php"]) {
        NSMutableDictionary *d = [[s jsonDictForKey:kJsonTabs] mutableCopy];
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSDateFormatter *fmt = [NSDateFormatter new]; fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        d[@"server_time"]     = @((long long)now);
        d[@"server_datetime"] = [fmt stringFromDate:[NSDate date]];
        data = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
    }
    // ── GET notifications ────────────────────────────────────
    else if ([meth isEqualToString:@"GET"] && [url.query containsString:@"action=get_notifications"]) {
        data = [NSJSONSerialization dataWithJSONObject:[s jsonDictForKey:kJsonNotifications] options:0 error:nil];
    }
    // ── POST api.php ─────────────────────────────────────────
    else if ([meth isEqualToString:@"POST"]) {
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
    [self.client URLProtocol:self didReceiveResponse:resp cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {}
@end

// ═══════════════════════════════════════════════════════════════
// MARK: - JSONEditorVC
// ═══════════════════════════════════════════════════════════════

@interface JSONEditorVC : UIViewController <UITextViewDelegate>
@property (nonatomic, copy) NSString *jsonKey, *titleStr;
@property (nonatomic, strong) UITextView *tv;
@property (nonatomic, strong) UILabel *status;
@end
@implementation JSONEditorVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _titleStr;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(done)];

    _tv = [[UITextView alloc] initWithFrame:self.view.bounds];
    _tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tv.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    _tv.text = [DevSettings.shared jsonStringForKey:_jsonKey];
    _tv.autocorrectionType = UITextAutocorrectionTypeNo;
    _tv.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _tv.delegate = self;
    [self.view addSubview:_tv];

    _status = [UILabel new]; _status.translatesAutoresizingMaskIntoConstraints = NO;
    _status.font = [UIFont systemFontOfSize:12]; _status.textAlignment = NSTextAlignmentCenter;
    _status.textColor = UIColor.systemGreenColor; _status.text = @"✓ Valid JSON";
    [self.view addSubview:_status];
    [NSLayoutConstraint activateConstraints:@[
        [_status.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [_status.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
    ]];
}
- (void)textViewDidChange:(UITextView *)tv {
    NSData *d = [tv.text dataUsingEncoding:NSUTF8StringEncoding]; NSError *e;
    [NSJSONSerialization JSONObjectWithData:d options:0 error:&e];
    _status.textColor = e ? UIColor.systemRedColor : UIColor.systemGreenColor;
    _status.text = e ? [NSString stringWithFormat:@"✗ %@", e.localizedDescription] : @"✓ Valid JSON";
}
- (void)save {
    NSData *d = [_tv.text dataUsingEncoding:NSUTF8StringEncoding]; NSError *e;
    [NSJSONSerialization JSONObjectWithData:d options:0 error:&e];
    if (e) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Invalid JSON"
                                    message:e.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil]; return;
    }
    [DevSettings.shared setJsonString:_tv.text forKey:_jsonKey]; [self done];
}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

// ═══════════════════════════════════════════════════════════════
// MARK: - ImgurMapVC  (per-URL replacement list)
// ═══════════════════════════════════════════════════════════════

@interface ImgurMapVC : UITableViewController
@property (nonatomic, strong) NSArray<NSString *> *keys;
@end
@implementation ImgurMapVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Imgur Links";
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self action:@selector(reload)],
        [[UIBarButtonItem alloc] initWithTitle:@"Clear All" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(clearAll)]
    ];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"C"];
    [self reload];
}

- (void)reload { _keys = [ImgurLinkStore.shared allKeys]; [self.tableView reloadData]; }

- (void)clearAll {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Clear all imgur logs?"
                                message:@"Replacements will also be removed."
                                preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Clear All" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_){
        for (NSString *k in self.keys) [ImgurLinkStore.shared removeKey:k];
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return MAX(1, (NSInteger)_keys.count); }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return [NSString stringWithFormat:@"%lu imgur URL%@ captured — tap to set replacement",
            (unsigned long)_keys.count, _keys.count == 1 ? @"" : @"s"];
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return @"Swipe left to remove a URL from the log. Empty replacement = pass-through.";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"C"];
    if (_keys.count == 0) {
        cell.textLabel.text = @"No imgur links captured yet — run the app to populate";
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.textLabel.numberOfLines = 2;
        cell.userInteractionEnabled = NO;
        return cell;
    }
    NSString *key = _keys[ip.row];
    NSString *rep = [ImgurLinkStore.shared replacementFor:key];
    BOOL hasRep   = rep.length > 0;

    // filename as title, full URL as subtitle
    cell.textLabel.text       = key.lastPathComponent;
    cell.textLabel.font       = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightSemibold];
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    if (hasRep) {
        cell.detailTextLabel.text      = [NSString stringWithFormat:@"→ %@", rep];
        cell.detailTextLabel.textColor = UIColor.systemGreenColor;
        cell.imageView.image = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"];
        cell.imageView.tintColor = UIColor.systemGreenColor;
    } else {
        cell.detailTextLabel.text      = key;
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.imageView.image = [UIImage systemImageNamed:@"photo"];
        cell.imageView.tintColor = UIColor.systemGrayColor;
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (_keys.count == 0) return;
    NSString *key = _keys[ip.row];
    NSString *cur = [ImgurLinkStore.shared replacementFor:key];

    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Set Replacement URL"
        message:key
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = cur;
        tf.placeholder = @"https://i.imgur.com/other.jpeg";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.keyboardType = UIKeyboardTypeURL;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Clear (pass-through)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_){
        [ImgurLinkStore.shared setReplacement:@"" forKey:key]; [self reload];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        [ImgurLinkStore.shared setReplacement:a.textFields.firstObject.text ?: @"" forKey:key];
        [self reload];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip { return _keys.count > 0; }
- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)es forRowAtIndexPath:(NSIndexPath *)ip {
    if (es == UITableViewCellEditingStyleDelete) { [ImgurLinkStore.shared removeKey:_keys[ip.row]]; [self reload]; }
}

@end

// ═══════════════════════════════════════════════════════════════
// MARK: - DevMenuVC  (main menu)
// ═══════════════════════════════════════════════════════════════

typedef NS_ENUM(NSInteger, Sec) {
    SecIcon = 0, SecImgur,
    SecCheckHud, SecValidate, SecNotifications, SecConnection, SecTabs,
    SecCount
};

@interface DevMenuVC : UITableViewController
    <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@end
@implementation DevMenuVC

static NSString *secTitle(Sec s) {
    switch(s){
        case SecIcon:          return @"Menu Icon";
        case SecImgur:         return @"Imgur Hook";
        case SecCheckHud:      return @"Check HUD Control";
        case SecValidate:      return @"Validate Key";
        case SecNotifications: return @"Get Notifications";
        case SecConnection:    return @"Check Connection";
        case SecTabs:          return @"Get Tabs";
        default: return @"";
    }
}
static NSString *secFooter(Sec s) {
    switch(s){
        case SecIcon:          return @"Image shown on the floating button. Set URL or pick from Photos.";
        case SecImgur:         return @"All i.imgur.com requests are logged automatically. Enable replacements to redirect them. Tap 'Manage Links' to assign per-URL redirects.";
        case SecCheckHud:      return @"POST /api.php  body: action=check_hud_control";
        case SecValidate:      return @"POST /api.php  body: action=validate + key + hwid";
        case SecNotifications: return @"GET  /api.php?action=get_notifications";
        case SecConnection:    return @"GET  /check_connection.php  — timestamp auto-injected from device clock";
        case SecTabs:          return @"GET  /apitab.php  — server_time & server_datetime auto-injected from device clock";
        default: return @"";
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Dev API Hook";
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return secTitle((Sec)s); }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return secFooter((Sec)s); }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv                     { return SecCount; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == SecIcon)  return 3;   // URL | Photos | Preview
    if (s == SecImgur) return 2;   // toggle | manage links
    return 2;                      // toggle | edit JSON
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    DevSettings *s = DevSettings.shared;
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"C"];

    // Icon section
    if (ip.section == SecIcon) {
        if (ip.row == 0) {
            c.textLabel.text = @"Icon URL";
            NSString *u = [s stringForKey:kIconURL];
            c.detailTextLabel.text = u.length ? u.lastPathComponent : @"Not set";
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (ip.row == 1) {
            c.textLabel.text = @"Load from Photos";
            c.imageView.image = [UIImage systemImageNamed:@"photo.on.rectangle"];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            c.textLabel.text = @"Preview Icon";
            UIImage *img = [self _localIcon];
            if (img) {
                UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0,0,36,36)];
                iv.image = img; iv.contentMode = UIViewContentModeScaleAspectFill;
                iv.clipsToBounds = YES; iv.layer.cornerRadius = 8; c.accessoryView = iv;
            } else { c.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
        }
        return c;
    }

    // Imgur section
    if (ip.section == SecImgur) {
        if (ip.row == 0) {
            c.textLabel.text = @"Apply Replacements";
            UISwitch *sw = [UISwitch new]; sw.on = [s isEnabled:kHookImgur];
            [sw addTarget:self action:@selector(imgurToggle:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
        } else {
            NSUInteger n = ImgurLinkStore.shared.allKeys.count;
            c.textLabel.text = @"Manage Links";
            c.detailTextLabel.text = [NSString stringWithFormat:@"%lu captured", (unsigned long)n];
            c.imageView.image = [UIImage systemImageNamed:@"link.badge.plus"];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        return c;
    }

    // API sections
    NSString *hk = [self _hookKey:(Sec)ip.section];
    if (ip.row == 0) {
        c.textLabel.text = @"Enable Hook";
        UISwitch *sw = [UISwitch new]; sw.on = [s isEnabled:hk];
        sw.tag = ip.section * 10;
        [sw addTarget:self action:@selector(apiToggle:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
    } else {
        c.textLabel.text = @"Edit Response JSON";
        c.imageView.image = [UIImage systemImageNamed:@"doc.text"];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];

    if (ip.section == SecIcon) {
        if (ip.row == 0) {
            [self _promptURL:@"Icon URL" current:[DevSettings.shared stringForKey:kIconURL] done:^(NSString *v){
                [DevSettings.shared setString:v forKey:kIconURL];
                [DevSettings.shared setEnabled:NO forKey:kIconUseLocal];
                [tv reloadSections:[NSIndexSet indexSetWithIndex:SecIcon] withRowAnimation:UITableViewRowAnimationNone];
                [DevMenuManager.shared refreshButtonIcon];
            }];
        } else if (ip.row == 1) {
            [self _pickPhoto];
        } else {
            [self _previewIcon];
        }
        return;
    }

    if (ip.section == SecImgur && ip.row == 1) {
        [self.navigationController pushViewController:[ImgurMapVC new] animated:YES]; return;
    }

    if (ip.row == 1) {
        NSString *jk = [self _jsonKey:(Sec)ip.section]; if (!jk) return;
        JSONEditorVC *ed = [JSONEditorVC new]; ed.jsonKey = jk;
        ed.titleStr = [NSString stringWithFormat:@"%@ Response", secTitle((Sec)ip.section)];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:ed];
        [self presentViewController:nav animated:YES completion:nil];
    }
}

- (void)imgurToggle:(UISwitch *)sw { [DevSettings.shared setEnabled:sw.on forKey:kHookImgur]; }
- (void)apiToggle:(UISwitch *)sw {
    NSString *k = [self _hookKey:(Sec)(sw.tag / 10)];
    if (k) [DevSettings.shared setEnabled:sw.on forKey:k];
}

- (NSString *)_hookKey:(Sec)s {
    switch(s){
        case SecCheckHud: return kHookCheckHud; case SecValidate: return kHookValidate;
        case SecNotifications: return kHookNotifications; case SecConnection: return kHookConnection;
        case SecTabs: return kHookTabs; default: return nil;
    }
}
- (NSString *)_jsonKey:(Sec)s {
    switch(s){
        case SecCheckHud: return kJsonCheckHud; case SecValidate: return kJsonValidate;
        case SecNotifications: return kJsonNotifications; case SecConnection: return kJsonConnection;
        case SecTabs: return kJsonTabs; default: return nil;
    }
}

- (UIImage *)_localIcon {
    DevSettings *s = DevSettings.shared;
    if ([s isEnabled:kIconUseLocal]) { NSString *p = [s stringForKey:kIconLocalPath]; if (p.length) return [UIImage imageWithContentsOfFile:p]; }
    return nil;
}

- (void)_pickPhoto {
    UIImagePickerController *p = [UIImagePickerController new];
    p.sourceType = UIImagePickerControllerSourceTypePhotoLibrary; p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}
- (void)imagePickerController:(UIImagePickerController *)p didFinishPickingMediaWithInfo:(NSDictionary *)info {
    [p dismissViewControllerAnimated:YES completion:nil];
    UIImage *img = info[UIImagePickerControllerOriginalImage]; if (!img) return;
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"dev_icon.jpg"];
    [UIImageJPEGRepresentation(img, 0.9) writeToFile:path atomically:YES];
    [DevSettings.shared setString:path forKey:kIconLocalPath];
    [DevSettings.shared setEnabled:YES forKey:kIconUseLocal];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SecIcon] withRowAnimation:UITableViewRowAnimationNone];
    [DevMenuManager.shared refreshButtonIcon];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)p { [p dismissViewControllerAnimated:YES completion:nil]; }

- (void)_promptURL:(NSString *)title current:(NSString *)cur done:(void(^)(NSString *))done {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.text = cur; tf.placeholder = @"https://...";
        tf.autocorrectionType = UITextAutocorrectionTypeNo; tf.keyboardType = UIKeyboardTypeURL;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        done(a.textFields.firstObject.text ?: @"");
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)_previewIcon {
    UIImage *local = [self _localIcon];
    if (local) { [self _showPreview:local]; return; }
    NSString *url = [DevSettings.shared stringForKey:kIconURL]; if (!url.length) return;
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url]
                                 completionHandler:^(NSData *d, NSURLResponse *r, NSError *e){
        if (!d) return; UIImage *img = [UIImage imageWithData:d]; if (!img) return;
        dispatch_async(dispatch_get_main_queue(), ^{ [self _showPreview:img]; });
    }] resume];
}
- (void)_showPreview:(UIImage *)img {
    UIViewController *vc = [UIViewController new]; vc.view.backgroundColor = UIColor.blackColor;
    UIImageView *iv = [[UIImageView alloc] initWithFrame:vc.view.bounds];
    iv.image = img; iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:iv];
    [self.navigationController pushViewController:vc animated:YES];
}

@end

// ═══════════════════════════════════════════════════════════════
// MARK: - Floating Button
// ═══════════════════════════════════════════════════════════════

@interface DevFloatingBtn : UIButton
- (void)refreshIcon;
@end
@implementation DevFloatingBtn

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.layer.cornerRadius  = f.size.width / 2;
    self.layer.shadowColor   = UIColor.blackColor.CGColor;
    self.layer.shadowRadius  = 10; self.layer.shadowOpacity = 0.55;
    self.layer.shadowOffset  = CGSizeMake(0, 4);
    self.clipsToBounds       = NO;
    self.layer.borderColor   = [UIColor colorWithWhite:1 alpha:0.2].CGColor;
    self.layer.borderWidth   = 1.5;
    [self refreshIcon];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_pan:)];
    [self addGestureRecognizer:pan];
    return self;
}

- (void)refreshIcon {
    DevSettings *s = DevSettings.shared;
    UIImage *img = nil;
    if ([s isEnabled:kIconUseLocal]) {
        NSString *p = [s stringForKey:kIconLocalPath];
        if (p.length) img = [UIImage imageWithContentsOfFile:p];
    }
    if (!img) {
        NSString *urlStr = [s stringForKey:kIconURL];
        if (urlStr.length) {
            [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:urlStr]
                                         completionHandler:^(NSData *d, NSURLResponse *r, NSError *e){
                if (!d) return; UIImage *remote = [UIImage imageWithData:d]; if (!remote) return;
                dispatch_async(dispatch_get_main_queue(), ^{ [self _applyImage:remote]; });
            }] resume];
            [self _applyGlyph]; return;  // show glyph while loading
        }
        [self _applyGlyph]; return;
    }
    [self _applyImage:img];
}

- (void)_applyImage:(UIImage *)src {
    CGFloat sz = self.bounds.size.width;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(sz, sz), NO, 0);
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0,0,sz,sz)] addClip];
    [src drawInRect:CGRectMake(0,0,sz,sz)];
    UIImage *round = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [self setImage:round forState:UIControlStateNormal];
    self.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.backgroundColor = UIColor.clearColor;
    for (UIView *v in self.subviews) if ([v isKindOfClass:[UILabel class]]) [v removeFromSuperview];
}

- (void)_applyGlyph {
    [self setImage:[UIImage systemImageNamed:@"ant.circle.fill"
                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:30
                                                                                             weight:UIImageSymbolWeightMedium]]
          forState:UIControlStateNormal];
    self.tintColor = [UIColor colorWithRed:0.25 green:1 blue:0.45 alpha:1];
    self.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.07 alpha:0.92];
    // tiny badge
    if (![self viewWithTag:999]) {
        UILabel *lb = [UILabel new]; lb.tag = 999;
        lb.text = @"DEV"; lb.font = [UIFont boldSystemFontOfSize:7];
        lb.textColor = [UIColor colorWithRed:0.25 green:1 blue:0.45 alpha:1];
        lb.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:lb];
        [NSLayoutConstraint activateConstraints:@[
            [lb.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [lb.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6]
        ]];
    }
}

- (void)_pan:(UIPanGestureRecognizer *)gr {
    UIView *sv = self.superview; if (!sv) return;
    CGPoint dt = [gr translationInView:sv];
    CGFloat r  = self.bounds.size.width / 2;
    UIEdgeInsets safe = sv.safeAreaInsets;
    self.center = CGPointMake(
        MAX(r+8, MIN(sv.bounds.size.width  - r - 8, self.center.x + dt.x)),
        MAX(r+8+safe.top, MIN(sv.bounds.size.height - r - 8 - safe.bottom, self.center.y + dt.y))
    );
    [gr setTranslation:CGPointZero inView:sv];
    if (gr.state == UIGestureRecognizerStateEnded) {
        CGFloat snapX = self.center.x < sv.bounds.size.width/2 ? r+12 : sv.bounds.size.width-r-12;
        [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.7
              initialSpringVelocity:0 options:0
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
@implementation DevMenuManager

+ (instancetype)shared { static DevMenuManager *m; static dispatch_once_t t; dispatch_once(&t,^{m=[DevMenuManager new];}); return m; }

- (UIWindow *)_win {
    if (@available(iOS 15, *)) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            for (UIWindow *w in ((UIWindowScene *)sc).windows) if (w.isKeyWindow) return w;
        }
    }
    return UIApplication.sharedApplication.keyWindow;
}

- (void)install {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = [self _win]; if (!win) return;
        CGFloat sz = 60;
        DevFloatingBtn *b = [[DevFloatingBtn alloc] initWithFrame:
            CGRectMake(win.bounds.size.width - sz - 14, win.bounds.size.height - sz - 120, sz, sz)];
        b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
        [b addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
        [win addSubview:b];
        _btn = b;
    });
}

- (void)refreshButtonIcon { dispatch_async(dispatch_get_main_queue(), ^{ [_btn refreshIcon]; }); }

- (void)openMenu {
    UIWindow *win = [self _win]; if (!win) return;
    UIViewController *top = win.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    DevMenuVC *menu = [DevMenuVC new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:menu];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15, *)) {
        UISheetPresentationController *sh = nav.sheetPresentationController;
        sh.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                       UISheetPresentationControllerDetent.largeDetent];
        sh.prefersGrabberVisible = YES;
    }
    [top presentViewController:nav animated:YES completion:nil];
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [[DevMenuManager shared] install]; });
}

%hook NSURLSessionConfiguration
- (NSArray *)protocolClasses {
    NSMutableArray *a = [NSMutableArray arrayWithObject:[HookURLProtocol class]];
    NSArray *o = %orig; if (o) [a addObjectsFromArray:o]; return a;
}
%end

%hook NSURLSession
+ (NSURLSession *)sharedSession                                       { RegisterHook(); return %orig; }
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)r       { RegisterHook(); return %orig; }
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)r
                           completionHandler:(void(^)(NSData*,NSURLResponse*,NSError*))c
                                                                      { RegisterHook(); return %orig; }
%end
%hook NSURLConnection
+ (instancetype)connectionWithRequest:(NSURLRequest *)r delegate:(id)d { RegisterHook(); return %orig; }
%end

%ctor { RegisterHook(); }
