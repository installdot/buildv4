// Tweak.xm
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#import <objc/runtime.h>

#pragma mark - CONFIG: set these to match server hex keys
static NSString * const kHexKey = @"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"; // CHANGE
static NSString * const kHexHmacKey = @"fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"; // CHANGE
static NSString * const kServerURL = @"https://chillysilly.frfrnocap.men/iost.php";
static BOOL g_hasShownCreditAlert = NO;
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

#pragma mark - Custom scrollable menu overlay
@interface MenuOverlay : UIView <UIScrollViewDelegate>
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, copy) void (^onDismiss)(void);
@property (nonatomic, strong) UIScrollView *scroll;
@end

@implementation MenuOverlay
- (instancetype)initWithTitle:(NSString*)title message:(NSString*)message actions:(NSArray<NSDictionary*>*)actions {
    self = [super initWithFrame:UIScreen.mainScreen.bounds];
    if (!self) return nil;
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];

    CGFloat panelW = 280;
    CGFloat panelH = MIN(400, 80 + actions.count * 46);
    _panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, panelW, panelH)];
    _panel.center = self.center;
    _panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    _panel.layer.cornerRadius = 14;
    _panel.layer.shadowColor = [UIColor blackColor].CGColor;
    _panel.layer.shadowOpacity = 0.3;
    _panel.layer.shadowRadius = 8;
    [self addSubview:_panel];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 12, panelW-24, 24)];
    titleLabel.text = title;
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    titleLabel.textColor = [UIColor whiteColor];
    [_panel addSubview:titleLabel];

    UILabel *msgLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 38, panelW-24, 36)];
    msgLabel.text = message;
    msgLabel.numberOfLines = 0;
    msgLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    msgLabel.font = [UIFont systemFontOfSize:14];
    [_panel addSubview:msgLabel];

    CGFloat y = CGRectGetMaxY(msgLabel.frame) + 8;
    _scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, y, panelW, panelH - y - 12)];
    _scroll.showsVerticalScrollIndicator = YES;
    [_panel addSubview:_scroll];

    CGFloat btnY = 0;
    for (NSDictionary *act in actions) {
        NSString *title = act[@"title"];
        void (^handler)(void) = act[@"handler"];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(12, btnY, panelW-24, 38);
        b.layer.cornerRadius = 8;
        b.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
        [b setTitle:title forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        [b addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(b, "handler", handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [_scroll addSubview:b];
        btnY += 46;
    }
    _scroll.contentSize = CGSizeMake(panelW, btnY);

    // X button
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(panelW-36, 8, 28, 28);
    [close setTitle:@"✕" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:close];

    return self;
}
- (void)buttonTapped:(UIButton*)b {
    void (^handler)(void) = objc_getAssociatedObject(b, "handler");
    [self dismissWithCompletion:^{ if (handler) handler(); }];
}
- (void)closeTapped {
    [self dismissWithCompletion:nil];
}
- (void)show {
    UIWindow *w = firstWindow();
    [w addSubview:self];
    self.alpha = 0.0;
    self.panel.transform = CGAffineTransformMakeScale(0.95, 0.95);
    [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.6 options:0 animations:^{
        self.alpha = 1.0;
        self.panel.transform = CGAffineTransformIdentity;
    } completion:nil];
}
- (void)dismissWithCompletion:(void(^)(void))cb {
    [UIView animateWithDuration:0.16 animations:^{
        self.alpha = 0.0;
        self.panel.transform = CGAffineTransformMakeScale(0.95, 0.95);
    } completion:^(BOOL finished){
        [self removeFromSuperview];
        if (cb) cb();
        if (self.onDismiss) self.onDismiss();
    }];
}
@end

#pragma mark - Input overlay with keyboard handling
@interface InputOverlay : UIView <UITextFieldDelegate>
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextField *textField;
@property (nonatomic, copy) void (^onOK)(NSString*);
@property (nonatomic, strong) UIButton *okButton;
@end

@implementation InputOverlay

- (instancetype)initWithTitle:(NSString*)title placeholder:(NSString*)ph okTitle:(NSString*)okTitle {
    self = [super initWithFrame:UIScreen.mainScreen.bounds];
    if (!self) return nil;
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];

    _panel = [[UIView alloc] initWithFrame:CGRectMake(20, 0, CGRectGetWidth(self.bounds)-40, 160)];
    _panel.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    _panel.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1.0];
    _panel.layer.cornerRadius = 12;
    [self addSubview:_panel];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(12, 12, _panel.bounds.size.width-24, 22)];
    label.text = title;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont boldSystemFontOfSize:17];
    [_panel addSubview:label];

    _textField = [[UITextField alloc] initWithFrame:CGRectMake(12, 44, _panel.bounds.size.width-24, 40)];
    _textField.placeholder = ph;
    _textField.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    _textField.textColor = [UIColor whiteColor];
    _textField.layer.cornerRadius = 8;
    _textField.keyboardAppearance = UIKeyboardAppearanceDark;
    _textField.keyboardType = UIKeyboardTypeNumberPad;
    _textField.returnKeyType = UIReturnKeyDone;
    _textField.delegate = (id<UITextFieldDelegate>)self;
    [_panel addSubview:_textField];

    UIButton *ok = [UIButton buttonWithType:UIButtonTypeSystem];
    ok.frame = CGRectMake(12, 96, (_panel.bounds.size.width-36)/2, 40);
    ok.layer.cornerRadius = 8;
    ok.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    [ok setTitle:okTitle forState:UIControlStateNormal];
    [ok setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [ok addTarget:self action:@selector(okTapped) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:ok];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    cancel.frame = CGRectMake(CGRectGetMaxX(ok.frame)+12, 96, (_panel.bounds.size.width-36)/2, 40);
    cancel.layer.cornerRadius = 8;
    cancel.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    [cancel setTitle:@"Cancel" forState:UIControlStateNormal];
    [cancel setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:cancel];

    // Listen to keyboard
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];

    return self;
}

- (void)keyboardWillShow:(NSNotification*)notif {
    CGRect kbFrame = [notif.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat offset = kbFrame.size.height / 2;
    [UIView animateWithDuration:0.25 animations:^{
        self.panel.center = CGPointMake(self.panel.center.x, CGRectGetMidY(self.bounds) - offset);
    }];
}

- (void)keyboardWillHide:(NSNotification*)notif {
    [UIView animateWithDuration:0.25 animations:^{
        self.panel.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    }];
}

- (void)okTapped {
    [self.textField resignFirstResponder]; // hide keyboard
    if (self.onOK) self.onOK(self.textField.text ?: @"");
    [self removeFromSuperview];
}

- (void)cancelTapped {
    [self.textField resignFirstResponder];
    [self removeFromSuperview];
}

// allow hitting enter/return to trigger OK
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self okTapped];
    return YES;
}

- (void)show {
    UIWindow *w = firstWindow();
    [w addSubview:self];
    [self.textField becomeFirstResponder];
}

@end

#pragma mark - Data menu filtering
static NSArray* listDocumentsFilesFiltered() {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil] ?: @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *f in files) {
        if ([f rangeOfString:@"Item"].location != NSNotFound ||
            [f rangeOfString:@"Season"].location != NSNotFound ||
            [f rangeOfString:@"Statistic"].location != NSNotFound ||
            [f rangeOfString:@"Weapon"].location != NSNotFound) {
            [out addObject:f];
        }
    }
    return out;
}


#pragma mark - Network: verify then open menu
static void showMainMenu();
static void showPlayerMenu();
static void showDataMenu();
static void verifyAccessAndOpenMenu() {
    NSData *key = dataFromHex(kHexKey);
    NSData *hmacKey = dataFromHex(kHexHmacKey);
    if (!key || key.length != 32 || !hmacKey || hmacKey.length != 32) {
        killApp();
        return;
    }
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
            showMainMenu();
        });
    }];
    [task resume];
}

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
static void applyPatchWithAlert(NSString *title, NSString *pattern, NSString *replacement) {
    BOOL ok = silentApplyRegexToDomain(pattern, replacement);
    // show custom overlay with same text
    MenuOverlay *ov = [[MenuOverlay alloc] initWithTitle:(ok?@"Success":@"Failed") message:[NSString stringWithFormat:@"%@ %@", title, ok?@"applied":@"failed"] actions:@[@{@"title":@"OK", @"handler":^{}}]];
    [ov show];
}

#pragma mark - Gems/Reborn/Bypass/PatchAll
static void patchGems();
static void patchRebornWithAlert();
static void silentPatchBypass();
static void patchAllExcludingGems();

static void patchGems() {
    // Use custom input overlay replicating alert with text field
    InputOverlay *input = [[InputOverlay alloc] initWithTitle:@"Set Gems" placeholder:@"0" okTitle:@"OK"];
    input.textField.keyboardType = UIKeyboardTypeNumberPad;
    input.onOK = ^(NSString *text){
        NSInteger v = [text integerValue];
        NSString *re1 = @"(<key>\\d+_gems</key>\s*<integer>)\\d+";
        NSString *re2 = @"(<key>\\d+_last_gems</key>\s*<integer>)\\d+";
        silentApplyRegexToDomain(re1, [NSString stringWithFormat:@"$1%ld", (long)v]);
        silentApplyRegexToDomain(re2, [NSString stringWithFormat:@"$1%ld", (long)v]);
        MenuOverlay *done = [[MenuOverlay alloc] initWithTitle:@"Gems Updated" message:[NSString stringWithFormat:@"%ld", (long)v] actions:@[@{@"title":@"OK", @"handler":^{}}]];
        [done show];
    };
    [input show];
}
static void patchRebornWithAlert() {
    applyPatchWithAlert(@"Reborn", @"(<key>\\d+_reborn_card</key>\s*<integer>)\\d+", @"$11");
}
static void silentPatchBypass() {
    silentApplyRegexToDomain(@"(<key>OpenRijTest_\\d+</key>\s*<integer>)\\d+", @"$10");
}
static void patchAllExcludingGems() {
    NSDictionary *map = @{
        @"Characters": @"(<key>\\d+_c\\d+_unlock.*\n.*)false",
        @"Skins": @"(<key>\\d+_c\\d+_skin\\d+.*\n.*>)[+-]?\\d+",
        @"Skills": @"(<key>\\d+_c_.*_skill_\\d_unlock.*\n.*<integer>)\\d",
        @"Pets": @"(<key>\\d+_p\\d+_unlock.*\n.*)false",
        @"Level": @"(<key>\\d+_c\\d+_level+.*\n.*>)[+-]?\\d+",
        @"Furniture": @"(<key>\\d+_furniture+_+.*\n.*>)[+-]?\\d+"
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
    silentApplyRegexToDomain(@"(<key>\\d+_reborn_card</key>\s*<integer>)\\d+", @"$11");
    silentPatchBypass();
    MenuOverlay *done = [[MenuOverlay alloc] initWithTitle:@"Patch All" message:@"Applied (excluding Gems)" actions:@[@{@"title":@"OK", @"handler":^{}}]];
    [done show];
}

#pragma mark - Player menu
static void showPlayerMenu() {
    NSArray *actions = @[
        @{@"title":@"Characters", @"handler":^{ applyPatchWithAlert(@"Characters", @"(<key>\\d+_c\\d+_unlock.*\n.*)false", @"$1True"); }},
        @{@"title":@"Skins", @"handler":^{ applyPatchWithAlert(@"Skins", @"(<key>\\d+_c\\d+_skin\\d+.*\n.*>)[+-]?\\d+", @"$11"); }},
        @{@"title":@"Skills", @"handler":^{ applyPatchWithAlert(@"Skills", @"(<key>\\d+_c_.*_skill_\\d_unlock.*\n.*<integer>)\\d", @"$11"); }},
        @{@"title":@"Pets", @"handler":^{ applyPatchWithAlert(@"Pets", @"(<key>\\d+_p\\d+_unlock.*\n.*)false", @"$1True"); }},
        @{@"title":@"Level", @"handler":^{ applyPatchWithAlert(@"Level", @"(<key>\\d+_c\\d+_level+.*\n.*>)[+-]?\\d+", @"$18"); }},
        @{@"title":@"Furniture", @"handler":^{ applyPatchWithAlert(@"Furniture", @"(<key>\\d+_furniture+_+.*\n.*>)[+-]?\\d+", @"$15"); }},
        @{@"title":@"Gems", @"handler":^{ patchGems(); }},
        @{@"title":@"Reborn", @"handler":^{ patchRebornWithAlert(); }},
        @{@"title":@"Patch All", @"handler":^{ patchAllExcludingGems(); }},
        @{@"title":@"Cancel", @"handler":^{ /* no-op */ }}
    ];
    // convert to overlay actions
    NSMutableArray *ovActs = [NSMutableArray array];
    for (NSDictionary *a in actions) {
        [ovActs addObject:@{@"title": a[@"title"], @"handler": a[@"handler"]}];
    }
    MenuOverlay *ov = [[MenuOverlay alloc] initWithTitle:@"Player" message:@"Choose patch" actions:ovActs];
    [ov show];
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
static void showFileActionMenu(NSString *fileName) {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *path = [docs stringByAppendingPathComponent:fileName];
    NSArray *actions = @[
        @{@"title":@"Export", @"handler":^{ NSError *err = nil; NSString *txt = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err]; if (txt) UIPasteboard.generalPasteboard.string = txt; MenuOverlay *done = [[MenuOverlay alloc] initWithTitle:(txt?@"Exported":@"Error") message:(txt?@"Copied to clipboard":err.localizedDescription) actions:@[@{@"title":@"OK", @"handler":^{}}]]; [done show]; }},
        @{@"title":@"Import", @"handler":^{ InputOverlay *input = [[InputOverlay alloc] initWithTitle:@"Import" placeholder:@"" okTitle:@"OK"]; input.onOK = ^(NSString *txt){ NSError *err = nil; BOOL okw = [txt writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err]; MenuOverlay *done = [[MenuOverlay alloc] initWithTitle:(okw?@"Imported":@"Import Failed") message:(okw?@"Edit Applied\nLeave game to load new data\nThoát game để load data mới":err.localizedDescription) actions:@[@{@"title":@"OK", @"handler":^{}}]]; [done show]; }; [input show]; }},
        @{@"title":@"Delete", @"handler":^{ NSError *err = nil; BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:path error:&err]; MenuOverlay *done = [[MenuOverlay alloc] initWithTitle:(ok?@"Deleted":@"Delete failed") message:(ok?@"File removed":err.localizedDescription) actions:@[@{@"title":@"OK", @"handler":^{}}]]; [done show]; }},
        @{@"title":@"Cancel", @"handler":^{}}
    ];
    NSMutableArray *ovActs = [NSMutableArray array];
    for (NSDictionary *a in actions) [ovActs addObject:@{@"title": a[@"title"], @"handler": a[@"handler"]}];
    MenuOverlay *menu = [[MenuOverlay alloc] initWithTitle:fileName message:@"Action" actions:ovActs];
    [menu show];
}

static void showFilesForType(NSString *type);

static void showDataMenu() {
    NSArray *types = @[@"Item", @"Season", @"Statistic", @"Weapon"];
    NSMutableArray *typeActions = [NSMutableArray array];
    for (NSString *type in types) {
        NSString *t = [type copy];
        [typeActions addObject:@{@"title":t, @"handler":^{
            showFilesForType(t);
        }}];
    }
    [typeActions addObject:@{@"title":@"Cancel", @"handler":^{}}];
    
    MenuOverlay *menu = [[MenuOverlay alloc] initWithTitle:@"Choose Type" message:@"Select data file type" actions:typeActions];
    [menu show];
}

// Filter files by chosen type
static void showFilesForType(NSString *type) {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil] ?: @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *f in files) {
        if ([f rangeOfString:type options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [out addObject:f];
        }
    }
    
    if (out.count == 0) {
        MenuOverlay *e = [[MenuOverlay alloc] initWithTitle:@"No files" message:[NSString stringWithFormat:@"No %@ files found", type] actions:@[@{@"title":@"OK",@"handler":^{}}]];
        [e show];
        return;
    }
    
    NSMutableArray *fileActions = [NSMutableArray array];
    for (NSString *f in out) {
        NSString *ff = [f copy];
        [fileActions addObject:@{@"title": ff, @"handler":^{ showFileActionMenu(ff); }}];
    }
    [fileActions addObject:@{@"title":@"Cancel",@"handler":^{}}];
    
    MenuOverlay *menu = [[MenuOverlay alloc] initWithTitle:[NSString stringWithFormat:@"%@ Files", type] message:@"Select file" actions:fileActions];
    [menu show];
}

#pragma mark - Main Menu
static void showMainMenu() {
    NSArray *actions = @[
        @{@"title":@"Player", @"handler":^{ showPlayerMenu(); }},
        @{@"title":@"Data", @"handler":^{ showDataMenu(); }},
        @{@"title":@"Cancel", @"handler":^{}}
    ];
    NSMutableArray *ovActs = [NSMutableArray array];
    for (NSDictionary *a in actions) [ovActs addObject:@{@"title": a[@"title"], @"handler": a[@"handler"]}];
    MenuOverlay *menu = [[MenuOverlay alloc] initWithTitle:@"Menu" message:@"" actions:ovActs];
    [menu show];
}

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
        floatingButton.frame = CGRectMake(10, 50, 40, 40);
        floatingButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        floatingButton.layer.cornerRadius = 10;
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
    if (!g_hasShownCreditAlert) {
        g_hasShownCreditAlert = YES;

        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *message =
                @"Thank you for using!\n"
                @"Cảm ơn vì đã sử dụng!";

            // Custom overlay
            MenuOverlay *credit =
                [[MenuOverlay alloc] initWithTitle:@"Info"
                                            message:message
                                            actions:@[
                                                @{@"title":@"OK",
                                                  @"handler":^{ verifyAccessAndOpenMenu(); }}
                                            ]];

            [credit show];
        });

    } else {
        verifyAccessAndOpenMenu();
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIButton *btn = (UIButton*)pan.view;

    if (pan.state == UIGestureRecognizerStateBegan) {
        g_startPoint = [pan locationInView:btn.superview];
        g_btnStart   = btn.center;

    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint pt = [pan locationInView:btn.superview];
        CGFloat dx = pt.x - g_startPoint.x;
        CGFloat dy = pt.y - g_startPoint.y;

        btn.center = CGPointMake(g_btnStart.x + dx, g_btnStart.y + dy);
    }
}

%end

// End of file
