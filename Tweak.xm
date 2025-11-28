// Tweak.xm
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - CONFIG: set these to match server hex keys
static NSString * const kHexKey = @"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"; // CHANGE
static NSString * const kHexHmacKey = @"fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"; // CHANGE
static NSString * const kServerURL = @"https://chillysilly.frfrnocap.men/iost.php";
static BOOL g_hasShownCreditAlert = NO;

static NSString * const kBGImageURLDefaultsKey = @"LM_MenuBGURL";
static NSString * const kBGImageFileName = @"lm_menu_bg.png";

@class LMUIHelper;

#pragma mark - Helpers
static NSData* dataFromHex(NSString *hex) {
    NSMutableData *d = [NSMutableData data];
    for (NSUInteger i = 0; i + 2 <= hex.length; i += 2) {
        NSRange r = NSMakeRange(i, 2);
        NSString *byteStr = [hex substringWithRange:r];
        unsigned int byte = 0;
        [[NSScanner scannerWithString:byteStr] scanHexInt:&byte];
        uint8_t b = (uint8_t)byte;
        [d appendBytes:&b length:1];
    }
    return d;
}
static NSString* base64Encode(NSData *d) {
    return [d base64EncodedStringWithOptions:0];
}
static NSData* base64Decode(NSString *s) {
    return [[NSData alloc] initWithBase64EncodedString:s options:0];
}
#pragma mark - AES-256-CBC encrypt/decrypt + HMAC-SHA256
static NSData* encryptPayload(NSData *plaintext, NSData *key, NSData *hmacKey) {
    uint8_t ivBytes[16];
    arc4random_buf(ivBytes, sizeof(ivBytes));
    NSData *iv = [NSData dataWithBytes:ivBytes length:16];
    size_t outlen = plaintext.length + kCCBlockSizeAES128;
    void *outbuf = malloc(outlen);
    size_t actualOut = 0;
    CCCryptorStatus st = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                 key.bytes, key.length,
                                 iv.bytes,
                                 plaintext.bytes, plaintext.length,
                                 outbuf, outlen, &actualOut);
    if (st != kCCSuccess) { free(outbuf); return nil; }
    NSData *cipher = [NSData dataWithBytesNoCopy:outbuf length:actualOut freeWhenDone:YES];
    NSMutableData *forHmac = [NSMutableData data];
    [forHmac appendData:iv];
    [forHmac appendData:cipher];
    unsigned char hmac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, hmacKey.length, forHmac.bytes, forHmac.length, hmac);
    NSData *hmacData = [NSData dataWithBytes:hmac length:CC_SHA256_DIGEST_LENGTH];
    NSMutableData *box = [NSMutableData data];
    [box appendData:iv];
    [box appendData:cipher];
    [box appendData:hmacData];
    return box;
}
static NSData* decryptAndVerify(NSData *box, NSData *key, NSData *hmacKey) {
    if (box.length < 16 + 32) return nil;
    NSData *iv = [box subdataWithRange:NSMakeRange(0,16)];
    NSData *hmac = [box subdataWithRange:NSMakeRange(box.length - 32, 32)];
    NSData *cipher = [box subdataWithRange:NSMakeRange(16, box.length - 16 - 32)];
    NSMutableData *forHmac = [NSMutableData data];
    [forHmac appendData:iv];
    [forHmac appendData:cipher];
    unsigned char calc[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, hmacKey.length, forHmac.bytes, forHmac.length, calc);
    NSData *calcData = [NSData dataWithBytes:calc length:CC_SHA256_DIGEST_LENGTH];
    if (![calcData isEqualToData:hmac]) return nil;
    size_t outlen = cipher.length + kCCBlockSizeAES128;
    void *outbuf = malloc(outlen);
    size_t actualOut = 0;
    CCCryptorStatus st = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                 key.bytes, key.length,
                                 iv.bytes,
                                 cipher.bytes, cipher.length,
                                 outbuf, outlen, &actualOut);
    if (st != kCCSuccess) { free(outbuf); return nil; }
    NSData *plain = [NSData dataWithBytesNoCopy:outbuf length:actualOut freeWhenDone:YES];
    return plain;
}
#pragma mark - App UUID persistence
static NSString* appUUID() {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/uuid.txt"];
    NSError *err = nil;
    NSString *uuid = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
    if (!uuid || uuid.length == 0) {
        uuid = [[NSUUID UUID] UUIDString];
        [uuid writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return uuid;
}
#pragma mark - UI helpers
static UIWindow* firstWindow() {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) return w;
            }
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}
static UIViewController* topVC() {
    UIWindow *win = firstWindow();
    UIViewController *root = win.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}
#pragma mark - Force close
static void killApp() {
    exit(0);
}
#pragma mark - Save lastTimestamp for verification
static NSString *g_lastTimestamp = nil;

#pragma mark - Forward declarations for menus
static void showMainMenu();
static void showPlayerMenu();
static void showDataMenu();
static void showFileActionMenu(NSString *fileName);

#pragma mark - Regex patch helpers
static NSString* dictToPlist(NSDictionary *d) {
    NSError *err = nil;
    NSData *dat = [NSPropertyListSerialization dataWithPropertyList:d format:NSPropertyListXMLFormat_v1_0 options:0 error:&err];
    if (!dat) return nil;
    return [[NSString alloc] initWithData:dat encoding:NSUTF8StringEncoding];
}
static NSDictionary* plistToDict(NSString *plist) {
    if (!plist) return nil;
    NSData *dat = [plist dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err = nil;
    id obj = [NSPropertyListSerialization propertyListWithData:dat options:NSPropertyListMutableContainersAndLeaves format:NULL error:&err];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}
static BOOL silentApplyRegexToDomain(NSString *pattern, NSString *replacement) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSDictionary *domain = [defs persistentDomainForName:bid] ?: @{};
    NSString *plist = dictToPlist(domain);
    if (!plist) return NO;
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&err];
    if (!re) return NO;
    NSString *modified = [re stringByReplacingMatchesInString:plist options:0 range:NSMakeRange(0, plist.length) withTemplate:replacement];
    NSDictionary *newDomain = plistToDict(modified);
    if (!newDomain) return NO;
    [defs setPersistentDomain:newDomain forName:bid];
    [defs synchronize];
    return YES;
}

#pragma mark - LMUIHelper interface

static char kFileNameAssocKey;
static char kSidebarTabKey;
static char kFullIDFieldKey;
static char kImportTextViewKey;

@interface LMUIHelper : NSObject <UITextFieldDelegate>
@property (nonatomic, strong) UIView *currentOverlay;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIView *sidebarView;
@property (nonatomic, strong) UIImage *backgroundImage;
@property (nonatomic, copy) void (^creditCompletion)(void);
@property (nonatomic, strong) NSString *currentFileName;
@property (nonatomic, strong) NSString *activeTab;
@property (nonatomic, strong) UIView *loadingOverlay;
+ (instancetype)shared;
- (void)showMainMenu;
- (void)showPlayerMenu;
- (void)showDataCategoryMenu;
- (void)showFileActionMenuWithName:(NSString *)fileName;
- (void)showGemsInput;
- (void)showSimpleMessageWithTitle:(NSString *)title message:(NSString *)message;
- (void)showCreditWithCompletion:(void(^)(void))completion;
- (void)showDataFilesForCategory:(NSString *)category;
- (void)showSettings;
- (void)backgroundUpdatedSuccess;
- (void)backgroundUpdatedFailed:(NSString *)msg;
- (void)hideKeyboardTapped;
- (void)showTab:(NSString *)tabName;
- (void)showLoadingWithMessage:(NSString *)msg;
- (void)hideLoading;
@end

#pragma mark - Network: verify then open menu
static void verifyAccessAndOpenMenu() {
    NSData *key = dataFromHex(kHexKey);
    NSData *hmacKey = dataFromHex(kHexHmacKey);
    if (!key || key.length != 32 || !hmacKey || hmacKey.length != 32) {
        killApp();
        return;
    }
    
    // show loading spinner
    dispatch_async(dispatch_get_main_queue(), ^{
        [[LMUIHelper shared] showLoadingWithMessage:@"Verifying..."];
    });
    
    NSString *uuid = appUUID();
    NSString *timestamp = [NSString stringWithFormat:@"%lld", (long long)[[NSDate date] timeIntervalSince1970]];
    g_lastTimestamp = timestamp;
    NSDictionary *payload = @{@"uuid": uuid, @"timestamp": timestamp, @"encrypted": @"yes"};
    NSData *plain = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSData *box = encryptPayload(plain, key, hmacKey);
    if (!box) { killApp(); return; }
    NSString *b64 = base64Encode(box);
    NSDictionary *post = @{@"data": b64};
    NSData *postData = [NSJSONSerialization dataWithJSONObject:post options:0 error:nil];
    NSURL *url = [NSURL URLWithString:kServerURL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 10.0;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = postData;
    NSURLSession *s = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [s dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err){
        if (err || !data) { killApp(); return; }
        NSDictionary *outer = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (!outer || !outer[@"data"]) { killApp(); return; }
        NSString *respB64 = outer[@"data"];
        NSData *respBox = base64Decode(respB64);
        if (!respBox) { killApp(); return; }
        NSData *plainResp = decryptAndVerify(respBox, key, hmacKey);
        if (!plainResp) { killApp(); return; }
        NSDictionary *respJSON = [NSJSONSerialization JSONObjectWithData:plainResp options:0 error:nil];
        if (!respJSON) { killApp(); return; }
        NSString *r_uuid = respJSON[@"uuid"];
        NSString *r_ts = respJSON[@"timestamp"];
        BOOL allow = [respJSON[@"allow"] boolValue];
        if (!r_uuid || ![r_uuid isEqualToString:uuid]) { killApp(); return; }
        if (!r_ts || ![r_ts isEqualToString:g_lastTimestamp]) { killApp(); return; }
        if (!allow) { killApp(); return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[LMUIHelper shared] hideLoading];
            showMainMenu();
        });
    }];
    [task resume];
}

#pragma mark - Patch helpers with new UI feedback
static void applyPatchWithAlert(NSString *title, NSString *pattern, NSString *replacement) {
    BOOL ok = silentApplyRegexToDomain(pattern, replacement);
    [[LMUIHelper shared] showSimpleMessageWithTitle:(ok ? @"Success" : @"Failed")
                                            message:[NSString stringWithFormat:@"%@ %@", title, ok ? @"applied" : @"failed"]];
}
#pragma mark - Gems/Reborn/Bypass/PatchAll
static void patchGems() {
    [[LMUIHelper shared] showGemsInput];
}
static void patchRebornWithAlert() {
    applyPatchWithAlert(@"Reborn", @"(<key>\\d+_reborn_card</key>\\s*<integer>)\\d+", @"$11");
}
static void silentPatchBypass() {
    silentApplyRegexToDomain(@"(<key>OpenRijTest_\\d+</key>\\s*<integer>)\\d+", @"$10");
}
static void patchAllExcludingGems() {
    NSDictionary *map = @{
        @"Characters": @"(<key>\\d+_c\\d+_unlock.*\\n.*)false",
        @"Skins": @"(<key>\\d+_c\\d+_skin\\d+.*\\n.*>)[+-]?\\d+",
        @"Skills": @"(<key>\\d+_c_.*_skill_\\d_unlock.*\\n.*<integer>)\\d",
        @"Pets": @"(<key>\\d+_p\\d+_unlock.*\\n.*)false",
        @"Level": @"(<key>\\d+_c\\d+_level+.*\\n.*>)[+-]?\\d+",
        @"Furniture": @"(<key>\\d+_furniture+_+.*\\n.*>)[+-]?\\d+"
    };
    for (NSString *k in map) {
        NSString *pattern = map[k];
        NSString *rep = @"$1";
        if ([k isEqualToString:@"Characters"] || [k isEqualToString:@"Pets"]) rep = @"$1True";
        else if ([k isEqualToString:@"Skins"] || [k isEqualToString:@"Skills"]) rep = @"$11";
        else if ([k isEqualToString:@"Level"]) rep = @"$18";
        else if ([k isEqualToString:@"Furniture"]) rep = @"$15";
        silentApplyRegexToDomain(pattern, rep);
    }
    silentApplyRegexToDomain(@"(<key>\\d+_reborn_card</key>\\s*<integer>)\\d+", @"$11");
    silentPatchBypass();
    [[LMUIHelper shared] showSimpleMessageWithTitle:@"Patch All" message:@"Applied (excluding Gems)"];
}
#pragma mark - Document helpers (hide .new)
static NSArray* listDocumentsFiles() {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil] ?: @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *f in files) {
        if (![f hasSuffix:@".new"]) [out addObject:f];
    }
    return out;
}

#pragma mark - Forwarding menus to LMUIHelper

static void showPlayerMenu() {
    [[LMUIHelper shared] showPlayerMenu];
}
static void showDataMenu() {
    [[LMUIHelper shared] showDataCategoryMenu];
}
static void showFileActionMenu(NSString *fileName) {
    [[LMUIHelper shared] showFileActionMenuWithName:fileName];
}
static void showMainMenu() {
    [[LMUIHelper shared] showMainMenu];
}

#pragma mark - LMUIHelper implementation

@implementation LMUIHelper

+ (instancetype)shared {
    static LMUIHelper *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[LMUIHelper alloc] init];
        [shared loadBackgroundImageFromDisk];
    });
    return shared;
}

- (NSString *)bgImagePath {
    NSString *lib = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    return [lib stringByAppendingPathComponent:kBGImageFileName];
}

- (void)loadBackgroundImageFromDisk {
    NSString *path = [self bgImagePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data) {
            self.backgroundImage = [UIImage imageWithData:data];
        }
    }
}

#pragma mark - Loading overlay

- (void)showLoadingWithMessage:(NSString *)msg {
    if (self.loadingOverlay.superview) return;
    UIWindow *win = firstWindow();
    if (!win) return;
    
    UIView *ov = [[UIView alloc] initWithFrame:win.bounds];
    ov.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
    
    CGFloat bw = 180.0;
    CGFloat bh = 110.0;
    CGFloat x = (win.bounds.size.width - bw) / 2.0;
    CGFloat y = (win.bounds.size.height - bh) / 2.0;
    
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(x, y, bw, bh)];
    box.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.18 alpha:0.96];
    box.layer.cornerRadius = 14.0;
    box.layer.borderWidth = 1.0;
    box.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.18] CGColor];
    
    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    spin.center = CGPointMake(bw/2.0, bh/2.0 - 10);
    [spin startAnimating];
    [box addSubview:spin];
    
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(8, bh - 40, bw - 16, 24)];
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont systemFontOfSize:14];
    lbl.text = msg ?: @"Loading...";
    [box addSubview:lbl];
    
    [ov addSubview:box];
    [win addSubview:ov];
    self.loadingOverlay = ov;
}

- (void)hideLoading {
    if (self.loadingOverlay.superview) {
        [self.loadingOverlay removeFromSuperview];
    }
    self.loadingOverlay = nil;
}

#pragma mark - Overlay + tabs

- (UIView *)createOverlayWithTitle:(NSString *)title withTabs:(BOOL)withTabs {
    UIWindow *win = firstWindow();
    if (!win) return nil;
    
    if (self.currentOverlay.superview) {
        [self.currentOverlay removeFromSuperview];
    }
    
    UIView *overlay = [[UIView alloc] initWithFrame:win.bounds];
    overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    
    CGFloat w = MIN(win.bounds.size.width - 40.0, 360.0);
    CGFloat h = MIN(win.bounds.size.height - 140.0, 460.0);
    CGFloat x = (win.bounds.size.width - w) / 2.0;
    CGFloat y = (win.bounds.size.height - h) / 2.0;
    
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(x, y, w, h)];
    panel.layer.cornerRadius = 12.0;
    panel.clipsToBounds = YES;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.18] CGColor];
    
    if (self.backgroundImage) {
        UIImageView *bgView = [[UIImageView alloc] initWithFrame:panel.bounds];
        bgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        bgView.image = self.backgroundImage;
        bgView.contentMode = UIViewContentModeScaleAspectFill;
        [panel addSubview:bgView];
        
        UIView *blurOverlay = [[UIView alloc] initWithFrame:panel.bounds];
        blurOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        blurOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
        [panel addSubview:blurOverlay];
    } else {
        CAGradientLayer *grad = [CAGradientLayer layer];
        grad.frame = panel.bounds;
        grad.colors = @[
            (id)[UIColor colorWithRed:0.16 green:0.20 blue:0.35 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.12 green:0.10 blue:0.22 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.20 green:0.08 blue:0.25 alpha:1.0].CGColor
        ];
        grad.startPoint = CGPointMake(0, 0);
        grad.endPoint   = CGPointMake(1, 1);
        [panel.layer insertSublayer:grad atIndex:0];
        panel.backgroundColor = [UIColor clearColor];
    }
    
    CGFloat headerH = 42.0;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, headerH)];
    CAGradientLayer *hgrad = [CAGradientLayer layer];
    hgrad.frame = header.bounds;
    hgrad.colors = @[
        (id)[UIColor colorWithRed:0.30 green:0.65 blue:1.0 alpha:0.95].CGColor,
        (id)[UIColor colorWithRed:0.75 green:0.35 blue:1.0 alpha:0.95].CGColor
    ];
    hgrad.startPoint = CGPointMake(0, 0.5);
    hgrad.endPoint   = CGPointMake(1, 0.5);
    [header.layer insertSublayer:hgrad atIndex:0];
    header.backgroundColor = [UIColor clearColor];
    [panel addSubview:header];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 7, w - 80, 28)];
    titleLabel.text = title;
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [header addSubview:titleLabel];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w - 40, 7, 28, 28);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
    closeBtn.layer.cornerRadius = 6.0;
    [closeBtn addTarget:self action:@selector(closeOverlay) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:closeBtn];
    
    if (withTabs) {
        CGFloat sidebarW = 92.0;
        UIView *side = [[UIView alloc] initWithFrame:CGRectMake(0, headerH, sidebarW, h - headerH)];
        CAGradientLayer *sgrad = [CAGradientLayer layer];
        sgrad.frame = side.bounds;
        sgrad.colors = @[
            (id)[UIColor colorWithRed:0.10 green:0.15 blue:0.30 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.08 green:0.10 blue:0.22 alpha:1.0].CGColor
        ];
        sgrad.startPoint = CGPointMake(0, 0);
        sgrad.endPoint   = CGPointMake(0, 1);
        [side.layer insertSublayer:sgrad atIndex:0];
        side.backgroundColor = [UIColor clearColor];
        [panel addSubview:side];
        self.sidebarView = side;
        
        UIView *content = [[UIView alloc] initWithFrame:CGRectMake(sidebarW, headerH, w - sidebarW, h - headerH)];
        content.backgroundColor = [UIColor colorWithRed:0.06 green:0.07 blue:0.14 alpha:0.96];
        content.layer.borderWidth = 1.0;
        content.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.08] CGColor];
        [panel addSubview:content];
        self.contentView = content;
        
        CGFloat yTabs = 8.0;
        NSArray *tabs = @[
            @{@"title": @"Main",   @"key": @"Main"},
            @{@"title": @"Player", @"key": @"Player"},
            @{@"title": @"Data",   @"key": @"Data"},
            @{@"title": @"Full",   @"key": @"Full"},
            @{@"title": @"Settings", @"key": @"Settings"},
            @{@"title": @"Credit", @"key": @"Credit"}
        ];
        for (NSDictionary *info in tabs) {
            UIButton *tb = [UIButton buttonWithType:UIButtonTypeSystem];
            tb.frame = CGRectMake(6, yTabs, sidebarW - 12, 32);
            [tb setTitle:info[@"title"] forState:UIControlStateNormal];
            [tb setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            tb.titleLabel.font = [UIFont boldSystemFontOfSize:13];
            tb.layer.cornerRadius = 7.0;
            tb.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.06];
            objc_setAssociatedObject(tb, &kSidebarTabKey, info[@"key"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [tb addTarget:self action:@selector(sideTabButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [side addSubview:tb];
            yTabs += 36.0;
        }
    } else {
        self.sidebarView = nil;
        self.contentView = nil;
    }
    
    overlay.alpha = 0.0;
    panel.transform = CGAffineTransformMakeScale(0.86, 0.86);
    
    [overlay addSubview:panel];
    [win addSubview:overlay];
    self.currentOverlay = overlay;
    
    [UIView animateWithDuration:0.22
                          delay:0
         usingSpringWithDamping:0.80
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        overlay.alpha = 1.0;
        panel.transform = CGAffineTransformIdentity;
    } completion:nil];
    
    return panel;
}

- (UIView *)createOverlayWithTitle:(NSString *)title {
    return [self createOverlayWithTitle:title withTabs:YES];
}

- (void)closeOverlay {
    if (self.currentOverlay.superview) {
        [UIView animateWithDuration:0.18 animations:^{
            self.currentOverlay.alpha = 0.0;
        } completion:^(BOOL finished) {
            [self.currentOverlay removeFromSuperview];
        }];
    }
    self.currentOverlay = nil;
    self.contentView = nil;
    self.sidebarView = nil;
}

#pragma mark - Sidebar tabs

- (void)updateSidebarSelection {
    for (UIView *v in self.sidebarView.subviews) {
        if (![v isKindOfClass:[UIButton class]]) continue;
        UIButton *b = (UIButton *)v;
        NSString *tab = objc_getAssociatedObject(b, &kSidebarTabKey);
        BOOL active = (tab && [tab isEqualToString:self.activeTab]);
        if (active) {
            CAGradientLayer *grad = [CAGradientLayer layer];
            grad.frame = b.bounds;
            grad.colors = @[
                (id)[UIColor colorWithRed:0.35 green:0.75 blue:1.0 alpha:1.0].CGColor,
                (id)[UIColor colorWithRed:0.80 green:0.45 blue:1.0 alpha:1.0].CGColor
            ];
            grad.startPoint = CGPointMake(0, 0.5);
            grad.endPoint   = CGPointMake(1, 0.5);
            b.backgroundColor = [UIColor clearColor];
            NSArray *sublayers = [b.layer.sublayers copy];
            for (CALayer *l in sublayers) {
                if ([l isKindOfClass:[CAGradientLayer class]]) {
                    [l removeFromSuperlayer];
                }
            }
            [b.layer insertSublayer:grad atIndex:0];
            b.layer.borderWidth = 1.0;
            b.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.5] CGColor];
            b.transform = CGAffineTransformMakeScale(1.03, 1.03);
        } else {
            NSArray *sublayers = [b.layer.sublayers copy];
            for (CALayer *l in sublayers) {
                if ([l isKindOfClass:[CAGradientLayer class]]) {
                    [l removeFromSuperlayer];
                }
            }
            b.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.06];
            b.layer.borderWidth = 0.0;
            b.transform = CGAffineTransformIdentity;
        }
    }
}

- (void)sideTabButtonTapped:(UIButton *)btn {
    NSString *tab = objc_getAssociatedObject(btn, &kSidebarTabKey);
    if (!tab) return;
    if ([tab isEqualToString:self.activeTab]) return;
    [self showTab:tab];
}

#pragma mark - Common helpers

- (UIScrollView *)createScrollInContent {
    if (!self.contentView) return nil;
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.contentView.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = YES;
    scroll.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:scroll];
    return scroll;
}

- (UIButton *)addMenuButtonWithTitle:(NSString *)title
                              toView:(UIView *)view
                                  y:(CGFloat *)yPtr
                              action:(SEL)sel {
    CGFloat y = *yPtr;
    CGFloat margin = 14.0;
    CGFloat w = view.bounds.size.width - margin * 2.0;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(margin, y, w, 40);
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = btn.bounds;
    grad.colors = @[
        (id)[UIColor colorWithRed:0.30 green:0.60 blue:1.0 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.65 green:0.40 blue:1.0 alpha:1.0].CGColor
    ];
    grad.startPoint = CGPointMake(0, 0.5);
    grad.endPoint   = CGPointMake(1, 0.5);
    [btn.layer insertSublayer:grad atIndex:0];
    btn.layer.cornerRadius = 8.0;
    btn.layer.masksToBounds = YES;
    btn.layer.borderWidth = 1.0;
    btn.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.14] CGColor];
    
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [btn addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    
    [view addSubview:btn];
    *yPtr = y + 46.0;
    
    return btn;
}

- (void)hideKeyboardTapped {
    if (self.currentOverlay) {
        [self.currentOverlay endEditing:YES];
    }
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return NO;
}

#pragma mark - Tab renderers

- (void)renderMainTab {
    UIScrollView *scroll = [self createScrollInContent];
    if (!scroll) return;
    CGFloat y = 12.0;
    
    [self addMenuButtonWithTitle:@"Player"   toView:scroll y:&y action:@selector(mainPlayerTapped)];
    [self addMenuButtonWithTitle:@"Data"     toView:scroll y:&y action:@selector(mainDataTapped)];
    [self addMenuButtonWithTitle:@"Settings" toView:scroll y:&y action:@selector(mainSettingsTapped)];
    [self addMenuButtonWithTitle:@"Full"     toView:scroll y:&y action:@selector(mainFullTapped)];
    [self addMenuButtonWithTitle:@"Credit"   toView:scroll y:&y action:@selector(mainCreditTapped)];
    
    scroll.contentSize = CGSizeMake(scroll.bounds.size.width, y + 12.0);
}

- (void)renderPlayerTab {
    UIScrollView *scroll = [self createScrollInContent];
    if (!scroll) return;
    CGFloat y = 12.0;
    
    [self addMenuButtonWithTitle:@"Characters" toView:scroll y:&y action:@selector(playerCharactersTapped)];
    [self addMenuButtonWithTitle:@"Skins"      toView:scroll y:&y action:@selector(playerSkinsTapped)];
    [self addMenuButtonWithTitle:@"Skills"     toView:scroll y:&y action:@selector(playerSkillsTapped)];
    [self addMenuButtonWithTitle:@"Pets"       toView:scroll y:&y action:@selector(playerPetsTapped)];
    [self addMenuButtonWithTitle:@"Level"      toView:scroll y:&y action:@selector(playerLevelTapped)];
    [self addMenuButtonWithTitle:@"Furniture"  toView:scroll y:&y action:@selector(playerFurnitureTapped)];
    [self addMenuButtonWithTitle:@"Gems"       toView:scroll y:&y action:@selector(playerGemsTapped)];
    [self addMenuButtonWithTitle:@"Reborn"     toView:scroll y:&y action:@selector(playerRebornTapped)];
    [self addMenuButtonWithTitle:@"Patch All"  toView:scroll y:&y action:@selector(playerPatchAllTapped)];
    
    scroll.contentSize = CGSizeMake(scroll.bounds.size.width, y + 12.0);
}

- (void)renderDataRootTab {
    UIScrollView *scroll = [self createScrollInContent];
    if (!scroll) return;
    CGFloat y = 12.0;
    
    [self addMenuButtonWithTitle:@"Statistic" toView:scroll y:&y action:@selector(dataStatisticTapped)];
    [self addMenuButtonWithTitle:@"Item"      toView:scroll y:&y action:@selector(dataItemTapped)];
    [self addMenuButtonWithTitle:@"Season"    toView:scroll y:&y action:@selector(dataSeasonTapped)];
    [self addMenuButtonWithTitle:@"Weapon"    toView:scroll y:&y action:@selector(dataWeaponTapped)];
    [self addMenuButtonWithTitle:@"All Files" toView:scroll y:&y action:@selector(dataAllTapped)];
    
    scroll.contentSize = CGSizeMake(scroll.bounds.size.width, y + 12.0);
}

- (void)renderFullTab {
    if (!self.contentView) return;
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    UIView *panel = self.contentView;
    
    CGFloat margin = 14.0;
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(margin, 16, panel.bounds.size.width - margin*2, 18)];
    lbl.text = @"Full import by ID";
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont boldSystemFontOfSize:14];
    [panel addSubview:lbl];
    
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(margin, 42, panel.bounds.size.width - margin*2, 36)];
    box.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.3];
    box.layer.cornerRadius = 8.0;
    box.layer.borderWidth = 1.0;
    box.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.18] CGColor];
    [panel addSubview:box];
    
    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(8, 3, box.bounds.size.width - 76, 30)];
    tf.placeholder = @"ID";
    tf.textColor = [UIColor whiteColor];
    tf.backgroundColor = [UIColor clearColor];
    tf.borderStyle = UITextBorderStyleNone;
    tf.keyboardType = UIKeyboardTypeDefault;
    tf.returnKeyType = UIReturnKeyDone;
    tf.delegate = [LMUIHelper shared];
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.spellCheckingType = UITextSpellCheckingTypeNo;
    [box addSubview:tf];
    
    UIButton *importBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    importBtn.frame = CGRectMake(box.bounds.size.width - 68, 3, 60, 30);
    importBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = importBtn.bounds;
    grad.colors = @[
        (id)[UIColor colorWithRed:0.25 green:0.65 blue:0.35 alpha:0.95].CGColor,
        (id)[UIColor colorWithRed:0.15 green:0.80 blue:0.55 alpha:0.95].CGColor
    ];
    grad.startPoint = CGPointMake(0, 0.5);
    grad.endPoint   = CGPointMake(1, 0.5);
    [importBtn.layer insertSublayer:grad atIndex:0];
    importBtn.layer.cornerRadius = 7.0;
    importBtn.layer.masksToBounds = YES;
    [importBtn setTitle:@"Import" forState:UIControlStateNormal];
    [importBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    importBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    objc_setAssociatedObject(importBtn, &kFullIDFieldKey, tf, OBJC_ASSOCIATION_ASSIGN);
    [importBtn addTarget:self action:@selector(fullImportButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:importBtn];
    
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(margin, 84, panel.bounds.size.width - margin*2, 34)];
    hint.text = @"Will fetch item/stat/season/weapon files for this ID,\nreplace and auto Patch All.";
    hint.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    hint.font = [UIFont systemFontOfSize:11];
    hint.numberOfLines = 2;
    [panel addSubview:hint];
}

- (void)renderSettingsTabContentInCurrentContentView {
    if (!self.contentView) return;
    UIView *panel = self.contentView;
    [panel.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    CGFloat margin = 16.0;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(margin, 18, panel.bounds.size.width - margin*2, 18)];
    label.text = @"Background image URL";
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:13];
    [panel addSubview:label];
    
    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(margin, 40, panel.bounds.size.width - margin*2, 32)];
    tf.borderStyle = UITextBorderStyleRoundedRect;
    tf.backgroundColor = [UIColor colorWithWhite:1 alpha:0.9];
    tf.keyboardType = UIKeyboardTypeURL;
    tf.returnKeyType = UIReturnKeyDone;
    tf.delegate = [LMUIHelper shared];
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.spellCheckingType = UITextSpellCheckingTypeNo;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    NSString *savedURL = [[NSUserDefaults standardUserDefaults] stringForKey:kBGImageURLDefaultsKey];
    if (savedURL.length) tf.text = savedURL;
    [panel addSubview:tf];
    
    UIButton *hideKB = [UIButton buttonWithType:UIButtonTypeSystem];
    hideKB.frame = CGRectMake(margin, 76, panel.bounds.size.width - margin*2, 26);
    [hideKB setTitle:@"Hide Keyboard" forState:UIControlStateNormal];
    [hideKB setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    hideKB.titleLabel.font = [UIFont systemFontOfSize:13];
    hideKB.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
    hideKB.layer.cornerRadius = 6.0;
    [hideKB addTarget:self action:@selector(hideKeyboardTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:hideKB];
    
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.frame = CGRectMake(margin, 108, panel.bounds.size.width - margin*2, 38);
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = saveBtn.bounds;
    grad.colors = @[
        (id)[UIColor colorWithRed:0.25 green:0.55 blue:0.95 alpha:0.95].CGColor,
        (id)[UIColor colorWithRed:0.50 green:0.35 blue:1.0 alpha:0.95].CGColor
    ];
    grad.startPoint = CGPointMake(0, 0.5);
    grad.endPoint   = CGPointMake(1, 0.5);
    [saveBtn.layer insertSublayer:grad atIndex:0];
    saveBtn.layer.cornerRadius = 10.0;
    saveBtn.layer.masksToBounds = YES;
    [saveBtn setTitle:@"Save Background" forState:UIControlStateNormal];
    [saveBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    saveBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [saveBtn addTarget:self action:@selector(bgSaveTapped:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:saveBtn];
    
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.frame = CGRectMake(margin, 152, panel.bounds.size.width - margin*2, 34);
    clearBtn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
    clearBtn.layer.cornerRadius = 10.0;
    [clearBtn setTitle:@"Clear Background" forState:UIControlStateNormal];
    [clearBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    clearBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    [clearBtn addTarget:self action:@selector(bgClearTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:clearBtn];
}

- (void)renderCreditTab {
    if (!self.contentView) return;
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    UIView *panel = self.contentView;
    
    CGFloat w = panel.bounds.size.width;
    
    UIView *circle = [[UIView alloc] initWithFrame:CGRectMake((w - 80)/2.0, 40, 80, 80)];
    circle.backgroundColor = [UIColor colorWithRed:0.33 green:0.55 blue:0.98 alpha:1.0];
    circle.layer.cornerRadius = 40.0;
    circle.layer.masksToBounds = YES;
    
    // simple "Discord-like" face
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(12, 38, 56, 16)];
    bar.backgroundColor = [UIColor whiteColor];
    bar.layer.cornerRadius = 8.0;
    [circle addSubview:bar];
    
    UIView *eye1 = [[UIView alloc] initWithFrame:CGRectMake(18, 42, 6, 6)];
    eye1.backgroundColor = [UIColor colorWithRed:0.33 green:0.55 blue:0.98 alpha:1.0];
    eye1.layer.cornerRadius = 3.0;
    [circle addSubview:eye1];
    
    UIView *eye2 = [[UIView alloc] initWithFrame:CGRectMake(80-18-6, 42, 6, 6)];
    eye2.backgroundColor = [UIColor colorWithRed:0.33 green:0.55 blue:0.98 alpha:1.0];
    eye2.layer.cornerRadius = 3.0;
    [circle addSubview:eye2];
    
    [panel addSubview:circle];
    
    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(10, CGRectGetMaxY(circle.frame) + 12, w - 20, 24)];
    name.textAlignment = NSTextAlignmentCenter;
    name.textColor = [UIColor whiteColor];
    name.font = [UIFont boldSystemFontOfSize:18];
    name.text = @"mochiteyvat";
    [panel addSubview:name];
    
    UILabel *disc = [[UILabel alloc] initWithFrame:CGRectMake(10, CGRectGetMaxY(name.frame) + 4, w - 20, 18)];
    disc.textAlignment = NSTextAlignmentCenter;
    disc.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    disc.font = [UIFont systemFontOfSize:13];
    disc.text = @"Discord";
    [panel addSubview:disc];
}

- (void)renderActiveTab {
    if (!self.contentView) return;
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [self updateSidebarSelection];
    
    if ([self.activeTab isEqualToString:@"Main"]) {
        [self renderMainTab];
    } else if ([self.activeTab isEqualToString:@"Player"]) {
        [self renderPlayerTab];
    } else if ([self.activeTab isEqualToString:@"Data"]) {
        [self renderDataRootTab];
    } else if ([self.activeTab isEqualToString:@"Full"]) {
        [self renderFullTab];
    } else if ([self.activeTab isEqualToString:@"Settings"]) {
        [self renderSettingsTabContentInCurrentContentView];
    } else if ([self.activeTab isEqualToString:@"Credit"]) {
        [self renderCreditTab];
    }
}

#pragma mark - Public tab entry

- (void)showTab:(NSString *)tabName {
    self.activeTab = tabName;
    NSString *title = [NSString stringWithFormat:@"Menu - %@", tabName];
    [self createOverlayWithTitle:title];
    [self renderActiveTab];
}

#pragma mark - Simple message (no tabs)

- (void)showSimpleMessageWithTitle:(NSString *)title message:(NSString *)message {
    UIView *panel = [self createOverlayWithTitle:title withTabs:NO];
    if (!panel) return;
    CGFloat margin = 18.0;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(margin, 60, panel.bounds.size.width - margin*2, panel.bounds.size.height - 110)];
    label.text = message;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:15];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:label];
}

#pragma mark - Main menu facade

- (void)showMainMenu {
    [self showTab:@"Main"];
}
- (void)showPlayerMenu {
    [self showTab:@"Player"];
}
- (void)showDataCategoryMenu {
    [self showTab:@"Data"];
}
- (void)showSettings {
    [self showTab:@"Settings"];
}

- (void)mainPlayerTapped { [self showTab:@"Player"]; }
- (void)mainDataTapped   { [self showTab:@"Data"]; }
- (void)mainSettingsTapped { [self showTab:@"Settings"]; }
- (void)mainFullTapped   { [self showTab:@"Full"]; }
- (void)mainCreditTapped { [self showTab:@"Credit"]; }

#pragma mark - Player actions

- (void)playerCharactersTapped {
    [self closeOverlay];
    applyPatchWithAlert(@"Characters", @"(<key>\\d+_c\\d+_unlock.*\\n.*)false", @"$1True");
}
- (void)playerSkinsTapped {
    [self closeOverlay];
    applyPatchWithAlert(@"Skins", @"(<key>\\d+_c\\d+_skin\\d+.*\\n.*>)[+-]?\\d+", @"$11");
}
- (void)playerSkillsTapped {
    [self closeOverlay];
    applyPatchWithAlert(@"Skills", @"(<key>\\d+_c_.*_skill_\\d_unlock.*\\n.*<integer>)\\d", @"$11");
}
- (void)playerPetsTapped {
    [self closeOverlay];
    applyPatchWithAlert(@"Pets", @"(<key>\\d+_p\\d+_unlock.*\\n.*)false", @"$1True");
}
- (void)playerLevelTapped {
    [self closeOverlay];
    applyPatchWithAlert(@"Level", @"(<key>\\d+_c\\d+_level+.*\\n.*>)[+-]?\\d+", @"$18");
}
- (void)playerFurnitureTapped {
    [self closeOverlay];
    applyPatchWithAlert(@"Furniture", @"(<key>\\d+_furniture+_+.*\\n.*>)[+-]?\\d+", @"$15");
}
- (void)playerGemsTapped {
    [self showGemsInput];
}
- (void)playerRebornTapped {
    [self closeOverlay];
    patchRebornWithAlert();
}
- (void)playerPatchAllTapped {
    [self closeOverlay];
    patchAllExcludingGems();
}

#pragma mark - Gems input (no tabs)

- (void)showGemsInput {
    UIView *panel = [self createOverlayWithTitle:@"Set Gems" withTabs:NO];
    if (!panel) return;
    
    CGFloat margin = 18.0;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(margin, 60, panel.bounds.size.width - margin*2, 20)];
    label.text = @"Enter value";
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:14];
    [panel addSubview:label];
    
    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(margin, 86, panel.bounds.size.width - margin*2, 32)];
    tf.borderStyle = UITextBorderStyleRoundedRect;
    tf.keyboardType = UIKeyboardTypeNumberPad;
    tf.placeholder = @"0";
    tf.backgroundColor = [UIColor colorWithWhite:1 alpha:0.9];
    tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    tf.returnKeyType = UIReturnKeyDone;
    tf.delegate = [LMUIHelper shared];
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.spellCheckingType = UITextSpellCheckingTypeNo;
    [panel addSubview:tf];
    
    UIButton *hideKB = [UIButton buttonWithType:UIButtonTypeSystem];
    hideKB.frame = CGRectMake(margin, 124, panel.bounds.size.width - margin*2, 26);
    [hideKB setTitle:@"Hide Keyboard" forState:UIControlStateNormal];
    [hideKB setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    hideKB.titleLabel.font = [UIFont systemFontOfSize:13];
    hideKB.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
    hideKB.layer.cornerRadius = 6.0;
    [hideKB addTarget:self action:@selector(hideKeyboardTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:hideKB];
    
    UIButton *okBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    okBtn.frame = CGRectMake(margin, 158, panel.bounds.size.width - margin*2, 40);
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = okBtn.bounds;
    grad.colors = @[
        (id)[UIColor colorWithRed:0.25 green:0.65 blue:0.35 alpha:0.95].CGColor,
        (id)[UIColor colorWithRed:0.15 green:0.80 blue:0.50 alpha:0.95].CGColor
    ];
    grad.startPoint = CGPointMake(0, 0.5);
    grad.endPoint   = CGPointMake(1, 0.5);
    [okBtn.layer insertSublayer:grad atIndex:0];
    okBtn.layer.cornerRadius = 10.0;
    okBtn.layer.masksToBounds = YES;
    [okBtn setTitle:@"OK" forState:UIControlStateNormal];
    [okBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    okBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [okBtn addTarget:self action:@selector(gemsOkPressed:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:okBtn];
}

- (void)gemsOkPressed:(UIButton *)sender {
    UIView *panel = sender.superview;
    UITextField *tf = nil;
    for (UIView *v in panel.subviews) {
        if ([v isKindOfClass:[UITextField class]]) {
            tf = (UITextField *)v;
            break;
        }
    }
    NSInteger v = [tf.text integerValue];
    NSString *re1 = @"(<key>\\d+_gems</key>\\s*<integer>)\\d+";
    NSString *re2 = @"(<key>\\d+_last_gems</key>\\s*<integer>)\\d+";
    silentApplyRegexToDomain(re1, [NSString stringWithFormat:@"$1%ld", (long)v]);
    silentApplyRegexToDomain(re2, [NSString stringWithFormat:@"$1%ld", (long)v]);
    
    [self closeOverlay];
    [self showSimpleMessageWithTitle:@"Gems Updated" message:[NSString stringWithFormat:@"%ld", (long)v]];
}

#pragma mark - Full import

- (void)fullImportButtonTapped:(UIButton *)sender {
    UITextField *tf = objc_getAssociatedObject(sender, &kFullIDFieldKey);
    NSString *idStr = [tf.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (idStr.length == 0) {
        [self showSimpleMessageWithTitle:@"Full Import" message:@"ID is empty"];
        return;
    }
    [self runFullImportWithID:idStr];
}

- (void)runFullImportWithID:(NSString *)idStr {

    [self showLoadingWithMessage:@"Importing..."];

    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];

    // Templates stay the same, we will replace the "id" part with the actual idStr
    NSArray *configs = @[
        @{@"template": @"item_data_id_.data",           @"param": @"item"},
        @{@"template": @"statistic_id_.data",           @"param": @"stat"},
        @{@"template": @"season_data_id_.data",         @"param": @"season"},
        @{@"template": @"weapon_evolution_id_.data",    @"param": @"weapon"}
    ];

    __block NSString *errorMessage = nil;
    dispatch_group_t group = dispatch_group_create();

    for (NSDictionary *cfg in configs) {
        NSString *templ = cfg[@"template"];
        NSString *param = cfg[@"param"];

        // Convert "item_data_id_.data" -> "item_data_{idStr}_.data"
        NSString *fileName = templ;
        NSRange r = [templ rangeOfString:@"id"];
        if (r.location != NSNotFound) {
            NSString *prefix = [templ substringToIndex:r.location];
            NSString *suffix = [templ substringFromIndex:r.location + r.length];
            fileName = [NSString stringWithFormat:@"%@%@%@", prefix, idStr, suffix];
        }

        NSString *path = [docs stringByAppendingPathComponent:fileName];

        NSString *urlStr = [NSString stringWithFormat:@"https://chillysilly.frfrnocap.men/datafile.php?data=%@", param];
        NSURL *url = [NSURL URLWithString:urlStr];
        if (!url) continue;

        dispatch_group_enter(group);
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
            if (error || !data) {
                @synchronized (self) {
                    if (!errorMessage) {
                        errorMessage = [NSString stringWithFormat:@"Network error (%@)", param];
                    }
                }
                dispatch_group_leave(group);
                return;
            }

            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!str) {
                @synchronized (self) {
                    if (!errorMessage) errorMessage = @"Invalid server response";
                }
                dispatch_group_leave(group);
                return;
            }

            NSError *werr = nil;
            BOOL ok = [str writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&werr];
            if (!ok) {
                @synchronized (self) {
                    if (!errorMessage) errorMessage = [NSString stringWithFormat:@"Write failed (%@)", param];
                }
            }

            dispatch_group_leave(group);
        }];
        [task resume];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [self hideLoading];
        if (errorMessage) {
            [self showSimpleMessageWithTitle:@"Full Import" message:errorMessage];
        } else {
            // After all 4 files done, run Patch All (excluding gems)
            patchAllExcludingGems();
        }
    });
}

#pragma mark - Data menus / files

- (void)dataStatisticTapped { [self showDataFilesForCategory:@"Statistic"]; }
- (void)dataItemTapped      { [self showDataFilesForCategory:@"Item"]; }
- (void)dataSeasonTapped    { [self showDataFilesForCategory:@"Season"]; }
- (void)dataWeaponTapped    { [self showDataFilesForCategory:@"Weapon"]; }
- (void)dataAllTapped       { [self showDataFilesForCategory:nil]; }

- (void)showDataFilesForCategory:(NSString *)category {
    if (!self.contentView) {
        [self showTab:@"Data"];
    }
    if (!self.contentView) return;
    
    NSArray *files = listDocumentsFiles();
    NSMutableArray *filtered = [NSMutableArray array];
    if (category.length == 0) {
        [filtered addObjectsFromArray:files];
    } else {
        for (NSString *f in files) {
            if ([f rangeOfString:category options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [filtered addObject:f];
            }
        }
    }
    
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    if (filtered.count == 0) {
        NSString *msg = category.length ? [NSString stringWithFormat:@"No files match '%@'", category] : @"Documents is empty";
        UILabel *label = [[UILabel alloc] initWithFrame:self.contentView.bounds];
        label.text = msg;
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont systemFontOfSize:14];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        [self.contentView addSubview:label];
        return;
    }
    
    CGFloat margin = 10.0;
    CGFloat top = 8.0;
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(margin, top, self.contentView.bounds.size.width - margin*2, self.contentView.bounds.size.height - top - 8.0)];
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = YES;
    [self.contentView addSubview:scroll];
    
    CGFloat y = 0.0;
    for (NSString *name in filtered) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(0, y, scroll.bounds.size.width, 36);
        btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
        [btn setTitle:name forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:13];
        btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        btn.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
        objc_setAssociatedObject(btn, &kFileNameAssocKey, name, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [btn addTarget:self action:@selector(fileButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:btn];
        y += 38.0;
    }
    scroll.contentSize = CGSizeMake(scroll.bounds.size.width, y);
}

- (void)fileButtonTapped:(UIButton *)sender {
    NSString *name = objc_getAssociatedObject(sender, &kFileNameAssocKey);
    if (!name) return;
    self.currentFileName = name;
    [self showFileActionMenuWithName:name];
}

- (void)showFileActionMenuWithName:(NSString *)fileName {
    if (!self.contentView) {
        self.activeTab = @"Data";
        [self createOverlayWithTitle:@"Menu - Data"];
    }
    if (!self.contentView) return;
    
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    UIScrollView *scroll = [self createScrollInContent];
    if (!scroll) return;
    CGFloat y = 12.0;
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, y, scroll.bounds.size.width - 24, 18)];
    titleLabel.text = fileName;
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [scroll addSubview:titleLabel];
    y += 26.0;
    
    [self addMenuButtonWithTitle:@"Export" toView:scroll y:&y action:@selector(fileExportTapped)];
    [self addMenuButtonWithTitle:@"Import" toView:scroll y:&y action:@selector(fileImportTapped)];
    [self addMenuButtonWithTitle:@"Delete" toView:scroll y:&y action:@selector(fileDeleteTapped)];
    
    scroll.contentSize = CGSizeMake(scroll.bounds.size.width, y + 12.0);
}

- (NSString *)currentFilePath {
    if (!self.currentFileName) return nil;
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [docs stringByAppendingPathComponent:self.currentFileName];
}

- (void)fileExportTapped {
    NSString *path = [self currentFilePath];
    if (!path) return;
    NSError *err = nil;
    NSString *txt = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
    [self closeOverlay];
    if (txt) {
        UIPasteboard.generalPasteboard.string = txt;
        [self showSimpleMessageWithTitle:@"Exported" message:@"Copied to clipboard"];
    } else {
        [self showSimpleMessageWithTitle:@"Error" message:err.localizedDescription ?: @"Unknown error"];
    }
}

- (void)fileImportTapped {
    UIView *panel = [self createOverlayWithTitle:@"Import" withTabs:NO];
    if (!panel) return;
    
    CGFloat margin = 12.0;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(margin, 54, panel.bounds.size.width - margin*2, 18)];
    label.text = @"Paste text to import";
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:14];
    [panel addSubview:label];
    
    // Base Y for text view (we may shift it down if we show clipboard bar)
    CGFloat tvBaseY = 76.0;
    CGFloat tvHeight = panel.bounds.size.height - tvBaseY - 80.0;
    
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(margin, tvBaseY, panel.bounds.size.width - margin*2, tvHeight)];
    tv.backgroundColor = [UIColor colorWithWhite:1 alpha:0.9];
    tv.font = [UIFont systemFontOfSize:13];
    tv.textColor = [UIColor blackColor];
    tv.layer.cornerRadius = 8.0;
    [panel addSubview:tv];
    
    // If clipboard has text, show a "Paste from clipboard?" bar and auto-fill on accept
    NSString *clip = UIPasteboard.generalPasteboard.string;
    if (clip.length > 0) {
        CGFloat barHeight = 26.0;
        
        // Move text view down a bit and reduce its height
        CGRect tvFrame = tv.frame;
        tvFrame.origin.y += barHeight + 4.0;
        tvFrame.size.height -= (barHeight + 4.0);
        tv.frame = tvFrame;
        
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(margin, tvBaseY, panel.bounds.size.width - margin*2, barHeight)];
        bar.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
        bar.layer.cornerRadius = 6.0;
        
        UILabel *barLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 4, bar.bounds.size.width - 90, barHeight - 8)];
        barLabel.text = @"Paste from clipboard?";
        barLabel.textColor = [UIColor whiteColor];
        barLabel.font = [UIFont systemFontOfSize:12];
        [bar addSubview:barLabel];
        
        UIButton *pasteBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        pasteBtn.frame = CGRectMake(bar.bounds.size.width - 70, 3, 62, barHeight - 6);
        [pasteBtn setTitle:@"Paste" forState:UIControlStateNormal];
        [pasteBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        pasteBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        pasteBtn.backgroundColor = [[UIColor colorWithRed:0.25 green:0.65 blue:0.35 alpha:0.95] colorWithAlphaComponent:0.9];
        pasteBtn.layer.cornerRadius = 6.0;
        
        // Link the text view to this button so we can fill it when tapped
        objc_setAssociatedObject(pasteBtn, &kImportTextViewKey, tv, OBJC_ASSOCIATION_ASSIGN);
        [pasteBtn addTarget:self action:@selector(pasteClipboardIntoImportTextView:) forControlEvents:UIControlEventTouchUpInside];
        
        [bar addSubview:pasteBtn];
        [panel addSubview:bar];
    }
    
    UIButton *hideKB = [UIButton buttonWithType:UIButtonTypeSystem];
    hideKB.frame = CGRectMake(margin, CGRectGetMaxY(tv.frame) + 4, panel.bounds.size.width - margin*2, 26);
    [hideKB setTitle:@"Hide Keyboard" forState:UIControlStateNormal];
    [hideKB setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    hideKB.titleLabel.font = [UIFont systemFontOfSize:13];
    hideKB.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
    hideKB.layer.cornerRadius = 6.0;
    [hideKB addTarget:self action:@selector(hideKeyboardTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:hideKB];
    
    UIButton *okBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    okBtn.frame = CGRectMake(margin, CGRectGetMaxY(hideKB.frame) + 4, panel.bounds.size.width - margin*2, 34);
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = okBtn.bounds;
    grad.colors = @[
        (id)[UIColor colorWithRed:0.25 green:0.65 blue:0.35 alpha:0.95].CGColor,
        (id)[UIColor colorWithRed:0.15 green:0.80 blue:0.50 alpha:0.95].CGColor
    ];
    grad.startPoint = CGPointMake(0, 0.5);
    grad.endPoint   = CGPointMake(1, 0.5);
    [okBtn.layer insertSublayer:grad atIndex:0];
    okBtn.layer.cornerRadius = 10.0;
    okBtn.layer.masksToBounds = YES;
    [okBtn setTitle:@"OK" forState:UIControlStateNormal];
    [okBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    okBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [okBtn addTarget:self action:@selector(fileImportOkPressed:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:okBtn];
}

- (void)fileImportOkPressed:(UIButton *)sender {
    UIView *panel = sender.superview;
    UITextView *tv = nil;
    for (UIView *v in panel.subviews) {
        if ([v isKindOfClass:[UITextView class]]) {
            tv = (UITextView *)v;
            break;
        }
    }
    NSString *txt = tv.text ?: @"";
    NSString *path = [self currentFilePath];
    [self closeOverlay];
    if (!path) {
        [self showSimpleMessageWithTitle:@"Import Failed" message:@"No file selected"];
        return;
    }
    NSError *err = nil;
    BOOL ok = [txt writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (ok) {
        [self showSimpleMessageWithTitle:@"Imported" message:@"Edit Applied\nLeave game to load new data\nThoát game để load data mới"];
    } else {
        [self showSimpleMessageWithTitle:@"Import Failed" message:err.localizedDescription ?: @"Unknown error"];
    }
}

- (void)pasteClipboardIntoImportTextView:(UIButton *)sender {
    NSString *clip = UIPasteboard.generalPasteboard.string;
    if (clip.length == 0) return;
    
    UITextView *tv = objc_getAssociatedObject(sender, &kImportTextViewKey);
    if (!tv) return;
    
    tv.text = clip;
}

- (void)fileDeleteTapped {
    NSString *path = [self currentFilePath];
    if (!path) return;
    NSError *err = nil;
    BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:path error:&err];
    [self closeOverlay];
    if (ok) {
        [self showSimpleMessageWithTitle:@"Deleted" message:@"File removed"];
    } else {
        [self showSimpleMessageWithTitle:@"Delete failed" message:err.localizedDescription ?: @"Unknown error"];
    }
}

#pragma mark - Settings / Background result

- (void)bgSaveTapped:(UIButton *)sender {
    UIView *panel = sender.superview;
    UITextField *tf = nil;
    for (UIView *v in panel.subviews) {
        if ([v isKindOfClass:[UITextField class]]) {
            tf = (UITextField *)v;
            break;
        }
    }
    NSString *urlStr = [tf.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (urlStr.length == 0) {
        [self backgroundUpdatedFailed:@"URL is empty"];
        return;
    }
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        [self backgroundUpdatedFailed:@"Invalid URL"];
        return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:urlStr forKey:kBGImageURLDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [self showLoadingWithMessage:@"Downloading..."];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self backgroundUpdatedFailed:@"Download failed"];
            });
            return;
        }
        UIImage *img = [UIImage imageWithData:data];
        if (!img) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self backgroundUpdatedFailed:@"Not an image"];
            });
            return;
        }
        NSString *path = [self bgImagePath];
        [data writeToFile:path atomically:YES];
        self.backgroundImage = img;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self backgroundUpdatedSuccess];
        });
    }];
    [task resume];
}

- (void)bgClearTapped {
    NSString *path = [self bgImagePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    self.backgroundImage = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kBGImageURLDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self backgroundUpdatedSuccess];
}

- (void)backgroundUpdatedSuccess {
    [self hideLoading];
    [self closeOverlay];
    [self showSimpleMessageWithTitle:@"Background" message:@"Background image updated"];
}

- (void)backgroundUpdatedFailed:(NSString *)msg {
    [self hideLoading];
    [self closeOverlay];
    [self showSimpleMessageWithTitle:@"Background" message:msg ?: @"Error"];
}

#pragma mark - Credit UI (no tabs)

- (void)showCreditWithCompletion:(void(^)(void))completion {
    self.creditCompletion = completion;
    UIView *panel = [self createOverlayWithTitle:@"Info" withTabs:NO];
    if (!panel) return;
    NSString *message = @"Thank you for using!\n"
                        @"Cảm ơn vì đã sử dụng!\n";
    CGFloat margin = 18.0;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(margin, 60, panel.bounds.size.width - margin*2, panel.bounds.size.height - 110)];
    label.text = message;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:15];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    [panel addSubview:label];
    
    UIButton *okBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    okBtn.frame = CGRectMake(margin, CGRectGetMaxY(label.frame) + 6, panel.bounds.size.width - margin*2, 36);
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = okBtn.bounds;
    grad.colors = @[
        (id)[UIColor colorWithRed:0.25 green:0.65 blue:0.35 alpha:0.95].CGColor,
        (id)[UIColor colorWithRed:0.15 green:0.80 blue:0.50 alpha:0.95].CGColor
    ];
    grad.startPoint = CGPointMake(0, 0.5);
    grad.endPoint   = CGPointMake(1, 0.5);
    [okBtn.layer insertSublayer:grad atIndex:0];
    okBtn.layer.cornerRadius = 10.0;
    okBtn.layer.masksToBounds = YES;
    [okBtn setTitle:@"OK" forState:UIControlStateNormal];
    [okBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    okBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [okBtn addTarget:self action:@selector(creditOkTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:okBtn];
}

- (void)creditOkTapped {
    void (^completion)(void) = self.creditCompletion;
    self.creditCompletion = nil;
    [self closeOverlay];
    if (completion) completion();
}

@end

#pragma mark - Floating draggable button + AUTO CLEANUP & BYPASS
static CGPoint g_startPoint;
static CGPoint g_btnStart;
static UIButton *floatingButton = nil;

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // === AUTO DELETE ALL .new FILES ONCE WHEN DYLIB LOADS ===
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSArray *allFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil];
        for (NSString *file in allFiles) {
            if ([file hasSuffix:@".new"]) {
                NSString *fullPath = [docs stringByAppendingPathComponent:file];
                [[NSFileManager defaultManager] removeItemAtPath:fullPath error:nil];
            }
        }
        // === AUTO APPLY BYPASS ONCE WHEN DYLIB LOADS ===
        silentPatchBypass();
        // === CREATE FLOATING BUTTON ===
        UIWindow *win = firstWindow();
        floatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
        floatingButton.frame = CGRectMake(10, 50, 64, 40);
        floatingButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
        floatingButton.layer.cornerRadius = 10;
        floatingButton.layer.borderWidth = 1.0;
        floatingButton.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.25] CGColor];
        floatingButton.tintColor = UIColor.whiteColor;
        [floatingButton setTitle:@"Menu" forState:UIControlStateNormal];
        floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [floatingButton addTarget:UIApplication.sharedApplication action:@selector(showMenuPressed) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:UIApplication.sharedApplication action:@selector(handlePan:)];
        [floatingButton addGestureRecognizer:pan];
        [win addSubview:floatingButton];
    });
}

%hook UIApplication
%new
- (void)showMenuPressed {
    // Auto bypass every time menu is opened
    silentPatchBypass();
    
    if (!g_hasShownCreditAlert) {
        g_hasShownCreditAlert = YES;
        [[LMUIHelper shared] showCreditWithCompletion:^{
            verifyAccessAndOpenMenu();
        }];
    } else {
        verifyAccessAndOpenMenu();
    }
}
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIButton *btn = (UIButton*)pan.view;
    if (pan.state == UIGestureRecognizerStateBegan) {
        g_startPoint = [pan locationInView:btn.superview];
        g_btnStart = btn.center;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint pt = [pan locationInView:btn.superview];
        CGFloat dx = pt.x - g_startPoint.x;
        CGFloat dy = pt.y - g_startPoint.y;
        btn.center = CGPointMake(g_btnStart.x + dx, g_btnStart.y + dy);
    }
}
%end
