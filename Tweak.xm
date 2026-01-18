```objective-c
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

#pragma mark - Account manager constants

static NSString * const kSdkStateKey         = @"SdkStateCache#1";
static NSString * const kLMCurrentAccountKey = @"LM_Account_Current";
static NSString * const kLMAccountsListKey   = @"LM_Account_List";

#pragma mark - SdkState helpers

static NSString *currentSdkStateJSONString(void) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSDictionary *domain = [defs persistentDomainForName:bid];
    id val = domain[kSdkStateKey];
    if (![val isKindOfClass:[NSString class]]) return nil;
    return (NSString *)val;
}

static void setSdkStateJSONString(NSString *json) {
    if (!json) return;
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *domain = [[defs persistentDomainForName:bid] mutableCopy] ?: [NSMutableDictionary dictionary];
    domain[kSdkStateKey] = json;
    [defs setPersistentDomain:domain forName:bid];
    [defs synchronize];
}

/// Flatten the JSON in SdkStateCache#1 into a simple account dict we can store.
static NSDictionary *extractAccountFromSdkStateJSON(NSString *json) {
    if (json.length == 0) return nil;
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;
    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (!obj || ![obj isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *root = (NSDictionary *)obj;
    
    NSDictionary *user    = root[@"User"];
    NSDictionary *session = root[@"Session"];
    if (![user isKindOfClass:[NSDictionary class]] || ![session isKindOfClass:[NSDictionary class]]) return nil;
    
    NSString *email    = user[@"Email"];
    NSNumber *userId   = user[@"Id"];
    NSNumber *playerId = user[@"PlayerId"];
    NSString *token    = session[@"Token"];
    NSString *expire   = session[@"Expire"];
    
    if (token.length == 0) return nil;
    
    NSMutableDictionary *acc = [NSMutableDictionary dictionary];
    if (email)    acc[@"email"]    = email;
    if (userId)   acc[@"userId"]   = userId;
    if (playerId) acc[@"playerId"] = playerId;
    if (expire)   acc[@"expire"]   = expire;
    acc[@"token"] = token;
    acc[@"raw"]   = json; // original string, used for Quick Login
    return acc;
}

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

#pragma mark - DES-CBC encrypt/decrypt

static NSData *desKeyData = nil;
static NSData *desIVData = nil;

static void initDESKeyAndIV() {
    if (!desKeyData) {
        const char keyStr[8] = {'i', 'a', 'm', 'b', 'o', '\0', '\0', '\0'};
        desKeyData = [NSData dataWithBytes:keyStr length:8];
    }
    if (!desIVData) {
        const char ivStr[8] = {'A', 'h', 'b', 'o', 'o', 'l', '\0', '\0'};
        desIVData = [NSData dataWithBytes:ivStr length:8];
    }
}

static NSData* desEncrypt(NSData *plaintext) {
    initDESKeyAndIV();
    size_t outlen = plaintext.length + kCCBlockSizeDES;
    void *outbuf = malloc(outlen);
    size_t actual = 0;
    CCCryptorStatus st = CCCrypt(kCCEncrypt, kCCAlgorithmDES, kCCOptionPKCS7Padding,
                                 desKeyData.bytes, kCCKeySizeDES,
                                 desIVData.bytes,
                                 plaintext.bytes, plaintext.length,
                                 outbuf, outlen, &actual);
    if (st != kCCSuccess) { free(outbuf); return nil; }
    return [NSData dataWithBytesNoCopy:outbuf length:actual freeWhenDone:YES];
}

static NSData* desDecrypt(NSData *ciphertext) {
    initDESKeyAndIV();
    size_t outlen = ciphertext.length + kCCBlockSizeDES;
    void *outbuf = malloc(outlen);
    size_t actual = 0;
    CCCryptorStatus st = CCCrypt(kCCDecrypt, kCCAlgorithmDES, kCCOptionPKCS7Padding,
                                 desKeyData.bytes, kCCKeySizeDES,
                                 desIVData.bytes,
                                 ciphertext.bytes, ciphertext.length,
                                 outbuf, outlen, &actual);
    if (st != kCCSuccess) { free(outbuf); return nil; }
    return [NSData dataWithBytesNoCopy:outbuf length:actual freeWhenDone:YES];
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

static char kSidebarTabKey;
static char kTokenLabelKey;
static char kTokenVisibleKey;

@interface LMUIHelper : NSObject <UITextFieldDelegate>
@property (nonatomic, strong) UIView *currentOverlay;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIView *sidebarView;
@property (nonatomic, strong) UIImage *backgroundImage;
@property (nonatomic, copy) void (^creditCompletion)(void);
@property (nonatomic, strong) NSString *currentFileName;
@property (nonatomic, strong) NSString *activeTab;
@property (nonatomic, strong) UIView *loadingOverlay;
@property (nonatomic, strong) NSDictionary *currentAccount;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *savedAccounts;
@property (nonatomic, assign) BOOL shouldExitOnBypassOk;

+ (instancetype)shared;
- (void)showMainMenu;
- (void)showPlayerMenu;
- (void)showSettings;
- (void)showGemsInput;
- (void)showSimpleMessageWithTitle:(NSString *)title message:(NSString *)message;
- (void)showCreditWithCompletion:(void(^)(void))completion;
- (void)backgroundUpdatedSuccess;
- (void)backgroundUpdatedFailed:(NSString *)msg;
- (void)hideKeyboardTapped;
- (void)showTab:(NSString *)tabName;
- (void)showLoadingWithMessage:(NSString *)msg;
- (void)hideLoading;
- (void)refreshAccountsFromSdkState;
- (NSDictionary *)loadBPData;
- (NSString *)bpFilePath;
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

#pragma mark - Gems/Reborn/PatchAll

static void patchGems() {
    [[LMUIHelper shared] showGemsInput];
}

static void patchRebornWithAlert() {
    applyPatchWithAlert(@"Reborn", @"(<key>\\d+_reborn_card</key>\\s*<integer>)\\d+", @"$11");
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
    [[LMUIHelper shared] showSimpleMessageWithTitle:@"Patch All" message:@"Applied (excluding Gems)"];
}

#pragma mark - Forwarding menus to LMUIHelper

static void showPlayerMenu() {
    [[LMUIHelper shared] showPlayerMenu];
}
static void showMainMenu() {
    [[LMUIHelper shared] showMainMenu];
}

#pragma mark - LMUIHelper implementation

@implementation LMUIHelper

+ (instancetype)shared {
    static LMUIHelper *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[LMUIHelper alloc] init];
        [shared loadBackgroundImageFromDisk];
        
        // Load stored accounts once
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        
        id cur = [defs objectForKey:kLMCurrentAccountKey];
        if ([cur isKindOfClass:[NSDictionary class]]) {
            shared.currentAccount = (NSDictionary *)cur;
        }
        
        id arr = [defs objectForKey:kLMAccountsListKey];
        if ([arr isKindOfClass:[NSArray class]]) {
            shared.savedAccounts = [arr mutableCopy];
        } else {
            shared.savedAccounts = [NSMutableArray array];
        }
    });
    return shared;
}

- (NSString *)bgImagePath {
    NSString *lib = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    return [lib stringByAppendingPathComponent:kBGImageFileName];
}

- (NSString *)bpFilePath {
    id pid = self.currentAccount[@"playerId"] ?: self.currentAccount[@"userId"];
    if (!pid) return nil;
    NSString *fileName = [NSString stringWithFormat:@"bp_data_id_%@.data", pid];
    NSString *lib = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    return [lib stringByAppendingPathComponent:fileName];
}

- (NSDictionary *)loadBPData {
    NSString *path = [self bpFilePath];
    if (!path) return nil;
    NSData *enc = [NSData dataWithContentsOfFile:path];
    if (!enc) return nil;
    NSData *plain = desDecrypt(enc);
    if (!plain) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:plain options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    return obj;
}

- (BOOL)isAccountExpired:(NSDictionary *)acc {
    NSString *expireStr = acc[@"expire"];
    if (expireStr.length == 0) return NO;
    
    // Example format: "2025-12-03T12:34:37"
    static NSDateFormatter *fmt;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";
    });
    NSDate *date = [fmt dateFromString:expireStr];
    if (!date) return NO;
    
    return ([date timeIntervalSinceNow] < 0);
}

#pragma mark - Accounts tab

- (void)renderAccountsTab {
    UIScrollView *scroll = [self createScrollInContent];
    if (!scroll) return;
    
    CGFloat y = 12.0;
    
    // "<-" Back button to Main
    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    backBtn.frame = CGRectMake(12, y, 70, 26);
    [backBtn setTitle:@"←" forState:UIControlStateNormal];
    [backBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    backBtn.titleLabel.font = [UIFont systemFontOfSize:13];
    backBtn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
    backBtn.layer.cornerRadius = 6.0;
    [backBtn addTarget:self action:@selector(accountsBackTapped) forControlEvents:UIControlEventTouchUpInside];
    [scroll addSubview:backBtn];
    y += 34.0;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(12, y, scroll.bounds.size.width - 24, 20)];
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:15];
    title.text = @"You are logged!";
    [scroll addSubview:title];
    y += 24.0;
    
    NSDictionary *cur = self.currentAccount;
    if (!cur) {
        UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(12, y, scroll.bounds.size.width - 24, 40)];
        empty.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
        empty.font = [UIFont systemFontOfSize:13];
        empty.numberOfLines = 0;
        empty.text = @"No active account found in SdkStateCache#1.";
        [scroll addSubview:empty];
        scroll.contentSize = CGSizeMake(scroll.bounds.size.width, y + 60);
        return;
    }
    
    NSString *email  = cur[@"email"] ?: @"(null)";
    NSString *token  = cur[@"token"] ?: @"";
    NSString *expire = cur[@"expire"] ?: @"";
    id pid           = cur[@"playerId"] ?: cur[@"userId"] ?: @(0);
    NSString *pidStr = [NSString stringWithFormat:@"%@", pid];
    
    UILabel *curLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, y, scroll.bounds.size.width - 24, 18)];
    curLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    curLabel.font = [UIFont systemFontOfSize:13];
    curLabel.text = @"Current Account:";
    [scroll addSubview:curLabel];
    y += 22.0;
    
    // Email
    y = [self addKey:@"Email:" value:email toView:scroll y:y];
    // ID
    y = [self addKey:@"ID:" value:pidStr toView:scroll y:y];
    
    // Token with eye
    {
        CGFloat margin = 12.0;
        CGFloat rowH = 22.0;
        UILabel *keyLbl = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, 70, rowH)];
        keyLbl.text = @"Token:";
        keyLbl.textColor = [UIColor whiteColor];
        keyLbl.font = [UIFont systemFontOfSize:13];
        [scroll addSubview:keyLbl];
        
        CGFloat btnW = 34.0;
        CGFloat valueW = scroll.bounds.size.width - margin*2 - 70 - btnW - 6;
        UILabel *valLbl = [[UILabel alloc] initWithFrame:CGRectMake(margin + 70, y, valueW, rowH)];
        valLbl.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
        valLbl.font = [UIFont systemFontOfSize:13];
        valLbl.text = @"••••••••••";
        [scroll addSubview:valLbl];
        
        UIButton *eye = [UIButton buttonWithType:UIButtonTypeSystem];
        eye.frame = CGRectMake(CGRectGetMaxX(valLbl.frame) + 4, y - 1, btnW, rowH + 2);
        [eye setTitle:@"<~>" forState:UIControlStateNormal];
        [eye setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        eye.titleLabel.font = [UIFont systemFontOfSize:15];
        eye.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
        eye.layer.cornerRadius = 6.0;
        objc_setAssociatedObject(eye, &kTokenLabelKey, valLbl, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(eye, &kTokenVisibleKey, @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // store full token string in label's accessibilityValue
        valLbl.accessibilityValue = token;
        [eye addTarget:self action:@selector(toggleTokenVisibility:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:eye];
        
        y += rowH + 8.0;
    }
    
    // Expire
    y = [self addKey:@"Expire Token:" value:expire toView:scroll y:y];
    
    // Saved accounts section
    if (self.savedAccounts.count > 0) {
        y += 10.0;
        UILabel *savedTitle = [[UILabel alloc] initWithFrame:CGRectMake(12, y, scroll.bounds.size.width - 24, 18)];
        savedTitle.text = @"Saved Accounts:";
        savedTitle.textColor = [UIColor whiteColor];
        savedTitle.font = [UIFont boldSystemFontOfSize:14];
        [scroll addSubview:savedTitle];
        y += 22.0;
        
        NSInteger idx = 0;
        for (NSDictionary *acc in self.savedAccounts) {
            y = [self addSavedAccount:acc index:idx toView:scroll y:y];
            idx++;
        }
    }
    
    scroll.contentSize = CGSizeMake(scroll.bounds.size.width, y + 20.0);
}

- (CGFloat)addKey:(NSString *)key
            value:(NSString *)value
           toView:(UIView *)view
               y:(CGFloat)y {
    CGFloat margin = 12.0;
    CGFloat rowH = 20.0;
    
    UILabel *k = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, 110, rowH)];
    k.text = key;
    k.textColor = [UIColor whiteColor];
    k.font = [UIFont systemFontOfSize:13];
    [view addSubview:k];
    
    UILabel *v = [[UILabel alloc] initWithFrame:CGRectMake(margin + 110, y, view.bounds.size.width - margin*2 - 110, rowH)];
    v.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    v.font = [UIFont systemFontOfSize:13];
    v.text = value ?: @"";
    v.numberOfLines = 1;
    [view addSubview:v];
    
    return y + rowH + 6.0;
}

- (CGFloat)addSavedAccount:(NSDictionary *)acc
                     index:(NSInteger)index
                    toView:(UIView *)view
                         y:(CGFloat)y {
    CGFloat margin = 12.0;
    CGFloat width = view.bounds.size.width - margin*2;
    
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(margin, y, width, 80)];
    card.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
    card.layer.cornerRadius = 8.0;
    
    NSString *email  = acc[@"email"] ?: @"(null)";
    id pid           = acc[@"playerId"] ?: acc[@"userId"] ?: @(0);
    NSString *pidStr = [NSString stringWithFormat:@"%@", pid];
    NSString *expire = acc[@"expire"] ?: @"";
    
    UILabel *line1 = [[UILabel alloc] initWithFrame:CGRectMake(8, 6, width - 16, 18)];
    line1.textColor = [UIColor whiteColor];
    line1.font = [UIFont boldSystemFontOfSize:13];
    line1.text = [NSString stringWithFormat:@"%@", email];
    [card addSubview:line1];
    
    UILabel *line2 = [[UILabel alloc] initWithFrame:CGRectMake(8, 24, width - 16, 16)];
    line2.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    line2.font = [UIFont systemFontOfSize:12];
    line2.text = [NSString stringWithFormat:@"ID: %@ | Expire: %@", pidStr, expire];
    [card addSubview:line2];
    
    // Buttons
    CGFloat btnW = (width - 8*3) / 2.0;
    UIButton *quick = [UIButton buttonWithType:UIButtonTypeSystem];
    quick.frame = CGRectMake(8, 48, btnW, 24);
    [quick setTitle:@"Quick Login" forState:UIControlStateNormal];
    [quick setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    quick.titleLabel.font = [UIFont systemFontOfSize:12];
    quick.backgroundColor = [[UIColor colorWithRed:0.25 green:0.65 blue:0.35 alpha:0.95] colorWithAlphaComponent:0.9];
    quick.layer.cornerRadius = 6.0;
    quick.tag = index;
    [quick addTarget:self action:@selector(quickLoginTapped:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:quick];
    
    UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
    del.frame = CGRectMake(8 + btnW + 8, 48, btnW, 24);
    [del setTitle:@"Delete" forState:UIControlStateNormal];
    [del setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    del.titleLabel.font = [UIFont systemFontOfSize:12];
    del.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
    del.layer.cornerRadius = 6.0;
    del.tag = index;
    [del addTarget:self action:@selector(deleteAccountTapped:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:del];
    
    [view addSubview:card];
    
    return y + card.bounds.size.height + 8.0;
}

- (void)accountsBackTapped {
    [self showTab:@"Main"];
}

- (void)quickLoginTapped:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= self.savedAccounts.count) return;
    NSDictionary *acc = self.savedAccounts[idx];
    NSString *raw = acc[@"raw"];
    if (raw.length == 0) return;
    
    // Write new SdkStateCache#1
    setSdkStateJSONString(raw);
    
    // Move chosen account to current, remove from list
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [defs setObject:acc forKey:kLMCurrentAccountKey];
    NSMutableArray *list = [self.savedAccounts mutableCopy];
    [list removeObjectAtIndex:idx];
    [defs setObject:list forKey:kLMAccountsListKey];
    [defs synchronize];
    
    self.currentAccount = acc;
    self.savedAccounts = list;
    
    // Notify + auto close game
    [self closeOverlay];
    [self showSimpleMessageWithTitle:@"Account"
                             message:@"Account switched.\nGame will now close."];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        killApp();
    });
}

- (void)deleteAccountTapped:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= self.savedAccounts.count) return;
    NSMutableArray *list = [self.savedAccounts mutableCopy];
    [list removeObjectAtIndex:idx];
    self.savedAccounts = list;
    
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [defs setObject:list forKey:kLMAccountsListKey];
    [defs synchronize];
    
    // Refresh the tab UI
    if ([self.activeTab isEqualToString:@"Accounts"]) {
        [self renderAccountsTab];
    }
}

- (void)toggleTokenVisibility:(UIButton *)sender {
    UILabel *label = objc_getAssociatedObject(sender, &kTokenLabelKey);
    if (!label) return;
    NSNumber *visNum = objc_getAssociatedObject(sender, &kTokenVisibleKey);
    BOOL visible = visNum.boolValue;
    visible = !visible;
    objc_setAssociatedObject(sender, &kTokenVisibleKey, @(visible), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSString *token = label.accessibilityValue ?: @"";
    if (visible) {
        label.text = token;
    } else {
        label.text = @"••••••••••";
    }
}

- (void)refreshAccountsFromSdkState {
    NSString *json = currentSdkStateJSONString();
    NSDictionary *newAcc = extractAccountFromSdkStateJSON(json);
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    
    // Load stored
    NSDictionary *storedCurrent = [defs objectForKey:kLMCurrentAccountKey];
    NSMutableArray *storedList = [[defs objectForKey:kLMAccountsListKey] mutableCopy] ?: [NSMutableArray array];
    
    // Push old current into list if changed
    if (storedCurrent && newAcc) {
        BOOL changed = ![storedCurrent[@"token"] isEqual:newAcc[@"token"]] ||
                       ![storedCurrent[@"playerId"] ?: @0 isEqual:newAcc[@"playerId"] ?: @0];
        if (changed) {
            BOOL already = NO;
            for (NSDictionary *acc in storedList) {
                if ([acc[@"token"] isEqual:storedCurrent[@"token"]]) {
                    already = YES;
                    break;
                }
            }
            if (!already) {
                [storedList addObject:storedCurrent];
            }
        }
    }
    
    // Update current if we have a valid one
    if (newAcc) {
        [defs setObject:newAcc forKey:kLMCurrentAccountKey];
        self.currentAccount = newAcc;
    } else {
        self.currentAccount = storedCurrent;
    }
    
    // Remove expired accounts from list
    NSMutableArray *pruned = [NSMutableArray array];
    for (NSDictionary *acc in storedList) {
        if (![self isAccountExpired:acc]) {
            [pruned addObject:acc];
        }
    }
    [defs setObject:pruned forKey:kLMAccountsListKey];
    self.savedAccounts = pruned;
    
    // If current is expired, clear it
    NSDictionary *cur = self.currentAccount;
    if (cur && [self isAccountExpired:cur]) {
        [defs removeObjectForKey:kLMCurrentAccountKey];
        self.currentAccount = nil;
    }
    
    [defs synchronize];
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
    
    UIActivityIndicatorView *spin;
    if (@available(iOS 13.0, *)) {
        spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    } else {
        spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    }
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
            @{@"title": @"Main",     @"key": @"Main"},
            @{@"title": @"Player",   @"key": @"Player"},
            @{@"title": @"Accounts", @"key": @"Accounts"},
            @{@"title": @"BP",       @"key": @"BP"},
            @{@"title": @"Settings", @"key": @"Settings"},
            @{@"title": @"Credit",   @"key": @"Credit"}
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
    [self addMenuButtonWithTitle:@"Accounts" toView:scroll y:&y action:@selector(mainAccountsTapped)];
    [self addMenuButtonWithTitle:@"BP"       toView:scroll y:&y action:@selector(mainBPTapped)];
    [self addMenuButtonWithTitle:@"Settings" toView:scroll y:&y action:@selector(mainSettingsTapped)];
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
    [self addMenuButtonWithTitle:@"Bypass"     toView:scroll y:&y action:@selector(playerBypassTapped)];
    [self addMenuButtonWithTitle:@"Patch All"  toView:scroll y:&y action:@selector(playerPatchAllTapped)];
    
    scroll.contentSize = CGSizeMake(scroll.bounds.size.width, y + 12.0);
}

- (void)renderBPTab {
    UIScrollView *scroll = [self createScrollInContent];
    if (!scroll) return;
    CGFloat y = 12.0;
    
    NSDictionary *bpDict = [self loadBPData];
    if (!bpDict) {
        UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(12, y, scroll.bounds.size.width - 24, 40)];
        empty.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
        empty.font = [UIFont systemFontOfSize:13];
        empty.numberOfLines = 0;
        empty.text = @"No Battle Pass data found.";
        [scroll addSubview:empty];
        scroll.contentSize = CGSizeMake(scroll.bounds.size.width, y + 60);
        return;
    }
    NSArray *seasonData = bpDict[@"seasonData"];
    if (seasonData.count == 0) {
        UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(12, y, scroll.bounds.size.width - 24, 40)];
        empty.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
        empty.font = [UIFont systemFontOfSize:13];
        empty.numberOfLines = 0;
        empty.text = @"No Battle Pass data found.";
        [scroll addSubview:empty];
        scroll.contentSize = CGSizeMake(scroll.bounds.size.width, y + 60);
        return;
    }
    
    NSArray *seasons = seasonData;
    NSDictionary *season = seasons[0][@"Value"];
    
    NSString *curLevelStr = [NSString stringWithFormat:@"%@", season[@"curLevel"] ?: @"0"];
    NSString *hasBuyStr = [season[@"hasBuy"] boolValue] ? @"True" : @"False";
    
    y = [self addKey:@"Current Level:" value:curLevelStr toView:scroll y:y];
    y = [self addKey:@"Unlock:" value:hasBuyStr toView:scroll y:y];
    
    [self addMenuButtonWithTitle:@"Unlock BP" toView:scroll y:&y action:@selector(unlockBPTapped)];
    [self addMenuButtonWithTitle:@"Max Level" toView:scroll y:&y action:@selector(maxLevelBPTapped)];
    [self addMenuButtonWithTitle:@"Complete Quest" toView:scroll y:&y action:@selector(completeQuestBPTapped)];
    
    scroll.contentSize = CGSizeMake(scroll.bounds.size.width, y + 12.0);
}

- (void)unlockBPTapped {
    NSString *path = [self bpFilePath];
    if (!path) return;
    NSDictionary *bpDict = [self loadBPData];
    if (!bpDict) return;
    NSMutableArray *seasons = [bpDict[@"seasonData"] mutableCopy];
    if (seasons.count == 0) return;
    NSMutableDictionary *season = [seasons[0][@"Value"] mutableCopy];
    season[@"hasBuy"] = @YES;
    seasons[0][@"Value"] = season;
    NSMutableDictionary *newDict = [bpDict mutableCopy];
    newDict[@"seasonData"] = seasons;
    NSData *json = [NSJSONSerialization dataWithJSONObject:newDict options:0 error:nil];
    if (!json) return;
    NSData *enc = desEncrypt(json);
    if (!enc) return;
    [enc writeToFile:path atomically:YES];
    [self showSimpleMessageWithTitle:@"BattlePass" message:@"Unlocked BattlePass"];
    [self renderActiveTab];
}

- (void)maxLevelBPTapped {
    NSString *path = [self bpFilePath];
    if (!path) return;
    NSDictionary *bpDict = [self loadBPData];
    if (!bpDict) return;
    NSMutableArray *seasons = [bpDict[@"seasonData"] mutableCopy];
    if (seasons.count == 0) return;
    NSMutableDictionary *season = [seasons[0][@"Value"] mutableCopy];
    season[@"curLevel"] = @50;
    seasons[0][@"Value"] = season;
    NSMutableDictionary *newDict = [bpDict mutableCopy];
    newDict[@"seasonData"] = seasons;
    NSData *json = [NSJSONSerialization dataWithJSONObject:newDict options:0 error:nil];
    if (!json) return;
    NSData *enc = desEncrypt(json);
    if (!enc) return;
    [enc writeToFile:path atomically:YES];
    [self showSimpleMessageWithTitle:@"BattlePass" message:@"Max Level Applied"];
    [self renderActiveTab];
}

- (void)completeQuestBPTapped {
    NSString *path = [self bpFilePath];
    if (!path) return;
    NSDictionary *bpDict = [self loadBPData];
    if (!bpDict) return;
    NSMutableArray *seasons = [bpDict[@"seasonData"] mutableCopy];
    if (seasons.count == 0) return;
    NSMutableDictionary *season = [seasons[0][@"Value"] mutableCopy];
    NSMutableArray *tasks = [season[@"seasonTaskData"] mutableCopy];
    for (NSMutableDictionary *task in tasks) {
        if ([task[@"Status"] isEqualToString:@"Progress"]) {
            task[@"Status"] = @"Complete";
            task[@"CurrentProgress"] = task[@"TargetProgress"];
            task[@"CompleteTime"] = @((long long)[[NSDate date] timeIntervalSince1970] * 10000000LL); // Approximate ticks
        }
    }
    season[@"seasonTaskData"] = tasks;
    
    NSMutableArray *weeklyLists = [season[@"weeklyTaskDataList"] mutableCopy];
    for (NSMutableArray *week in weeklyLists) {
        for (NSMutableDictionary *task in week) {
            if ([task[@"Status"] isEqualToString:@"Progress"]) {
                task[@"Status"] = @"Complete";
                task[@"CurrentProgress"] = task[@"TargetProgress"];
                task[@"CompleteTime"] = @((long long)[[NSDate date] timeIntervalSince1970] * 10000000LL);
            }
        }
    }
    season[@"weeklyTaskDataList"] = weeklyLists;
    
    seasons[0][@"Value"] = season;
    NSMutableDictionary *newDict = [bpDict mutableCopy];
    newDict[@"seasonData"] = seasons;
    NSData *json = [NSJSONSerialization dataWithJSONObject:newDict options:0 error:nil];
    if (!json) return;
    NSData *enc = desEncrypt(json);
    if (!enc) return;
    [enc writeToFile:path atomically:YES];
    [self showSimpleMessageWithTitle:@"BattlePass" message:@"Quests Completed"];
    [self renderActiveTab];
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
    } else if ([self.activeTab isEqualToString:@"Accounts"]) {
        [self renderAccountsTab];
    } else if ([self.activeTab isEqualToString:@"BP"]) {
        [self renderBPTab];
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
- (void)showSettings {
    [self showTab:@"Settings"];
}

- (void)mainPlayerTapped { [self showTab:@"Player"]; }
- (void)mainAccountsTapped { [self showTab:@"Accounts"]; }
- (void)mainBPTapped { [self showTab:@"BP"]; }
- (void)mainSettingsTapped { [self showTab:@"Settings"]; }
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

- (void)playerBypassTapped {
    BOOL ok = silentApplyRegexToDomain(@"(<key>OpenRijTest_\\d+</key>\\s*<integer>)\\d+", @"$10");
    
    if (ok) {
        // Optional: close menu first so UI disappears cleanly
        [self closeOverlay];
        // Auto close game after successful bypass
        killApp();
    } else {
        [self closeOverlay];
        [self showSimpleMessageWithTitle:@"Bypass" message:@"Bypass failed"];
    }
}

#pragma mark - Bypass success UI

- (void)showBypassSuccessAndExit {
    self.shouldExitOnBypassOk = YES;
    UIView *panel = [self createOverlayWithTitle:@"Bypass" withTabs:NO];
    if (!panel) return;
    
    CGFloat margin = 18.0;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(margin, 60, panel.bounds.size.width - margin*2, panel.bounds.size.height - 110)];
    label.text = @"Bypass applied successfully.\nTap OK to close the game.";
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:15];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:label];
    
    UIButton *okBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    okBtn.frame = CGRectMake(margin, CGRectGetMaxY(label.frame) - 10, panel.bounds.size.width - margin*2, 36);
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
    [okBtn addTarget:self action:@selector(bypassOkTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:okBtn];
}

- (void)bypassOkTapped {
    [self closeOverlay];
    if (self.shouldExitOnBypassOk) {
        killApp();
    }
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

#pragma mark - Floating draggable button

static CGPoint g_startPoint;
static CGPoint g_btnStart;
static UIButton *floatingButton = nil;

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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
    // Refresh account cache from SdkStateCache#1 every time menu is shown
    [[LMUIHelper shared] refreshAccountsFromSdkState];
    
    if (!g_hasShownCreditAlert) {
        g_hasShownCreditAlert = YES;
        [[LMUIHelper shared] showCreditWithCompletion:^{
            verifyAccessAndOpenMenu();
        }];
    } else {
        verifyAccessAndOpenMenu();
    }
}

%new
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
```
