// Tweak.xm – Custom UI Version (No UIAlertController)
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#import <objc/runtime.h>

@interface UIButton (Blocks)
- (void)addBlockForControlEvents:(UIControlEvents)events block:(void(^)(void))block;
@end

@implementation UIButton (Blocks)
- (void)addBlockForControlEvents:(UIControlEvents)events block:(void(^)(void))block {
    objc_setAssociatedObject(self, _cmd, block, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self addTarget:self action:@selector(_invokeBlock: ) forControlEvents:events];
}
- (void)_invokeBlock:(id)sender {
    void(^block)(void) = objc_getAssociatedObject(self, @selector(_invokeBlock:));
    if (block) block();
}
@end
#pragma mark - CONFIG
static NSString * const kHexKey = @"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
static NSString * const kHexHmacKey = @"fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210";
static NSString * const kServerURL = @"https://chillysilly.frfrnocap.men/iost.php";
static BOOL g_hasShownCreditAlert = NO;

#pragma mark - Helpers (unchanged)
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
static NSString* base64Encode(NSData *d) { return [d base64EncodedStringWithOptions:0]; }
static NSData* base64Decode(NSString *s) { return [[NSData alloc] initWithBase64EncodedString:s options:0]; }

#pragma mark - AES-256-CBC + HMAC-SHA256 (unchanged)
static NSData* encryptPayload(NSData *plaintext, NSData *key, NSData *hmacKey) {
    uint8_t ivBytes[16]; arc4random_buf(ivBytes, sizeof(ivBytes));
    NSData *iv = [NSData dataWithBytes:ivBytes length:16];
    size_t outlen = plaintext.length + kCCBlockSizeAES128;
    void *outbuf = malloc(outlen);
    size_t actualOut = 0;
    CCCryptorStatus st = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                 key.bytes, key.length, iv.bytes,
                                 plaintext.bytes, plaintext.length,
                                 outbuf, outlen, &actualOut);
    if (st != kCCSuccess) { free(outbuf); return nil; }
    NSData *cipher = [NSData dataWithBytesNoCopy:outbuf length:actualOut freeWhenDone:YES];
    NSMutableData *forHmac = [NSMutableData data]; [forHmac appendData:iv]; [forHmac appendData:cipher];
    unsigned char hmac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, hmacKey.length, forHmac.bytes, forHmac.length, hmac);
    NSData *hmacData = [NSData dataWithBytes:hmac length:CC_SHA256_DIGEST_LENGTH];
    NSMutableData *box = [NSMutableData data]; [box appendData:iv]; [box appendData:cipher]; [box appendData:hmacData];
    return box;
}
static NSData* decryptAndVerify(NSData *box, NSData *key, NSData *hmacKey) {
    if (box.length < 16 + 32) return nil;
    NSData *iv = [box subdataWithRange:NSMakeRange(0,16)];
    NSData *hmac = [box subdataWithRange:NSMakeRange(box.length - 32, 32)];
    NSData *cipher = [box subdataWithRange:NSMakeRange(16, box.length - 16 - 32)];
    NSMutableData *forHmac = [NSMutableData data]; [forHmac appendData:iv]; [forHmac appendData:cipher];
    unsigned char calc[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, hmacKey.length, forHmac.bytes, forHmac.length, calc);
    NSData *calcData = [NSData dataWithBytes:calc length:CC_SHA256_DIGEST_LENGTH];
    if (![calcData isEqualToData:hmac]) return nil;
    size_t outlen = cipher.length + kCCBlockSizeAES128;
    void *outbuf = malloc(outlen);
    size_t actualOut = 0;
    CCCryptorStatus st = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                 key.bytes, key.length, iv.bytes,
                                 cipher.bytes, cipher.length, outbuf, outlen, &actualOut);
    if (st != kCCSuccess) { free(outbuf); return nil; }
    return [NSData dataWithBytesNoCopy:outbuf length:actualOut freeWhenDone:YES];
}

#pragma mark - UUID & Window helpers (unchanged)
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
static UIWindow* firstWindow() {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) return w;
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}
static void killApp() { exit(0); }
static NSString *g_lastTimestamp = nil;

#pragma mark - Custom UI Base
@interface CustomMenuView : UIView
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *container;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, copy) void(^dismissBlock)(void);
- (void)showInWindow:(UIWindow *)window;
- (void)dismiss;
@end

@implementation CustomMenuView
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        _blurView.frame = self.bounds;
        _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_blurView];
        
        _container = [[UIView alloc] init];
        _container.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.95];
        _container.layer.cornerRadius = 16;
        _container.clipsToBounds = YES;
        [self addSubview:_container];
        
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.font = [UIFont boldSystemFontOfSize:22];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        [_container addSubview:_titleLabel];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
        [self addGestureRecognizer:tap];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = 300;
    CGFloat h = 400;
    _container.frame = CGRectMake((self.bounds.size.width-w)/2, (self.bounds.size.height-h)/2, w, h);
    _titleLabel.frame = CGRectMake(0, 20, w, 40);
}
- (void)showInWindow:(UIWindow *)window {
    self.frame = window.bounds;
    [window addSubview:self];
    self.alpha = 0;
    [UIView animateWithDuration:0.3 animations:^{ self.alpha = 1; }];
}
- (void)dismiss {
    [UIView animateWithDuration:0.25 animations:^{ self.alpha = 0; } completion:^(BOOL f){ [self removeFromSuperview]; if (self.dismissBlock) self.dismissBlock(); }];
}
@end

#pragma mark - Network Verification (unchanged logic)
static void verifyAccessAndOpenMenu();
static void showMainMenu();
static void verifyAccessAndOpenMenu() {
    NSData *key = dataFromHex(kHexKey);
    NSData *hmacKey = dataFromHex(kHexHmacKey);
    if (!key || key.length != 32 || !hmacKey || hmacKey.length != 32) { killApp(); return; }
    
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
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kServerURL]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 10.0;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = postData;
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || !data) { killApp(); return; }
        NSDictionary *outer = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *respB64 = outer[@"data"];
        NSData *respBox = base64Decode(respB64);
        NSData *plainResp = decryptAndVerify(respBox, key, hmacKey);
        NSDictionary *respJSON = [NSJSONSerialization JSONObjectWithData:plainResp options:0 error:nil];
        if (!respJSON || ![respJSON[@"uuid"] isEqualToString:uuid] || ![respJSON[@"timestamp"] isEqualToString:g_lastTimestamp] || ![respJSON[@"allow"] boolValue]) {
            killApp(); return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ showMainMenu(); });
    }] resume];
}

#pragma mark - Regex & Patch Helpers (unchanged)
static NSString* dictToPlist(NSDictionary *d) {
    NSError *e; NSData *dat = [NSPropertyListSerialization dataWithPropertyList:d format:NSPropertyListXMLFormat_v1_0 options:0 error:&e];
    return dat ? [[NSString alloc] initWithData:dat encoding:NSUTF8StringEncoding] : nil;
}
static NSDictionary* plistToDict(NSString *plist) {
    if (!plist) return nil;
    NSData *dat = [plist dataUsingEncoding:NSUTF8StringEncoding];
    NSError *e;
    id obj = [NSPropertyListSerialization propertyListWithData:dat options:NSPropertyListMutableContainersAndLeaves format:NULL error:&e];
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

static void applyPatchWithTitle(NSString *title, NSString *pattern, NSString *replacement) {
    BOOL ok = silentApplyRegexToDomain(pattern, replacement);
    dispatch_async(dispatch_get_main_queue(), ^{
        CustomMenuView *v = [[CustomMenuView alloc] init];
        v.titleLabel.text = ok ? @"Success" : @"Failed";
        UILabel *msg = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, 260, 60)];
        msg.text = [NSString stringWithFormat:@"%@ %@", title, ok ? @"applied" : @"failed"];
        msg.textColor = UIColor.lightGrayColor;
        msg.textAlignment = NSTextAlignmentCenter;
        msg.numberOfLines = 0;
        [v.container addSubview:msg];
        
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(80, 180, 140, 44);
        [btn setTitle:@"OK" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        btn.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1];
        btn.layer.cornerRadius = 10;
        [btn addTarget:v action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
        [v.container addSubview:btn];
        [v showInWindow:firstWindow()];
    });
}

#pragma mark - Patch Functions (unchanged logic, custom UI only)
static void patchGems() {
    CustomMenuView *v = [[CustomMenuView alloc] init];
    v.titleLabel.text = @"Set Gems";
    
    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(40, 100, 220, 44)];
    tf.placeholder = @"Enter value";
    tf.keyboardType = UIKeyboardTypeNumberPad;
    tf.borderStyle = UITextBorderStyleRoundedRect;
    tf.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    [v.container addSubview:tf];
    
    UIButton *ok = [UIButton buttonWithType:UIButtonTypeSystem];
    ok.frame = CGRectMake(40, 170, 100, 44);
    [ok setTitle:@"OK" forState:UIControlStateNormal];
    ok.backgroundColor = UIColor.systemBlueColor;
    ok.layer.cornerRadius = 10;
    [ok addTarget:v action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [ok addTarget:nil action:nil forControlEvents:UIControlEventTouchUpInside]; // dummy
    [v.container addSubview:ok];
    
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    cancel.frame = CGRectMake(160, 170, 100, 44);
    [cancel setTitle:@"Cancel" forState:UIControlStateNormal];
    cancel.backgroundColor = UIColor.systemRedColor;
    cancel.layer.cornerRadius = 10;
    [cancel addTarget:v action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [v.container addSubview:cancel];
    
    [ok addBlockForControlEvents:UIControlEventTouchUpInside block:^{
        NSInteger val = [tf.text integerValue];
        silentApplyRegexToDomain(@"(?<=<key>\\d+_gems</key>\\s*<integer>)\\d+", [NSString stringWithFormat:@"%ld", (long)val]);
        silentApplyRegexToDomain(@"(?<=<key>\\d+_last_gems</key>\\s*<integer>)\\d+", [NSString stringWithFormat:@"%ld", (long)val]);
        [v dismiss];
        CustomMenuView *done = [[CustomMenuView alloc] init];
        done.titleLabel.text = @"Gems Updated";
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, 260, 60)];
        l.text = [NSString stringWithFormat:@"%ld gems set", (long)val];
        l.textColor = UIColor.cyanColor;
        l.textAlignment = NSTextAlignmentCenter;
        [done.container addSubview:l];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(80, 160, 140, 44);
        [b setTitle:@"OK" forState:UIControlStateNormal];
        b.backgroundColor = UIColor.systemGreenColor;
        b.layer.cornerRadius = 10;
        [b addTarget:done action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
        [done.container addSubview:b];
        [done showInWindow:firstWindow()];
    }];
    
    [v showInWindow:firstWindow()];
}

static void patchReborn() { applyPatchWithTitle(@"Reborn", @"(<key>\\d+_reborn_card</key>\\s*<integer>)\\d+", @"$11"); }
static void silentPatchBypass() { silentApplyRegexToDomain(@"(<key>OpenRijTest_\\d+</key>\\s*<integer>)\\d+", @"$10"); }

static void patchAllExcludingGems() {
    // same as original
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
        NSString *rep = ([k isEqualToString:@"Characters"] || [k isEqualToString:@"Pets"]) ? @"$1True" :
                        ([k isEqualToString:@"Skins"] || [k isEqualToString:@"Skills"]) ? @"$11" :
                        ([k isEqualToString:@"Level"]) ? @"$18" : @"$15";
        silentApplyRegexToDomain(pattern, rep);
    }
    silentApplyRegexToDomain(@"(<key>\\d+_reborn_card</key>\\s*<integer>)\\d+", @"$11");
    silentPatchBypass();
    
    CustomMenuView *v = [[CustomMenuView alloc] init];
    v.titleLabel.text = @"Patch All";
    UILabel *msg = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, 260, 80)];
    msg.text = @"All patches applied\n(excluding Gems)";
    msg.textAlignment = NSTextAlignmentCenter;
    msg.textColor = UIColor.cyanColor;
    msg.numberOfLines = 0;
    [v.container addSubview:msg];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(80, 180, 140, 44);
    [b setTitle:@"OK" forState:UIControlStateNormal];
    b.backgroundColor = UIColor.systemGreenColor;
    b.layer.cornerRadius = 10;
    [b addTarget:v action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [v.container addSubview:b];
    [v showInWindow:firstWindow()];
}

#pragma mark - Player Menu (Custom UI)
static void showPlayerMenu() {
    CustomMenuView *menu = [[CustomMenuView alloc] init];
    menu.titleLabel.text = @"Player Menu";
    
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(20, 70, 260, 300)];
    [menu.container addSubview:scroll];
    
    NSArray *items = @[
        @{@"title":@"Characters", @"pat":@"(<key>\\d+_c\\d+_unlock.*\\n.*)false", @"rep":@"$1True"},
        @{@"title":@"Skins",      @"pat":@"(<key>\\d+_c\\d+_skin\\d+.*\\n.*>)[+-]?\\d+", @"rep":@"$11"},
        @{@"title":@"Skills",     @"pat":@"(<key>\\d+_c_.*_skill_\\d_unlock.*\\n.*<integer>)\\d", @"rep":@"$11"},
        @{@"title":@"Pets",       @"pat":@"(<key>\\d+_p\\d+_unlock.*\\n.*)false", @"rep":@"$1True"},
        @{@"title":@"Level",      @"pat":@"(<key>\\d+_c\\d+_level+.*\\n.*>)[+-]?\\d+", @"rep":@"$18"},
        @{@"title":@"Furniture",  @"pat":@"(<key>\\d+_furniture+_+.*\\n.*>)[+-]?\\d+", @"rep":@"$15"},
        @{@"title":@"Gems",       @"action":@"gems"},
        @{@"title":@"Reborn",     @"action":@"reborn"},
        @{@"title":@"Patch All",  @"action":@"all"}
    ];
    
    CGFloat y = 10;
    for (NSDictionary *it in items) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(0, y, 240, 50);
        [btn setTitle:it[@"title"] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
        btn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1];
        btn.layer.cornerRadius = 12;
        [btn addTarget:menu action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
        
        if (it[@"pat"]) {
            [btn addBlockForControlEvents:UIControlEventTouchUpInside block:^{
                applyPatchWithTitle(it[@"title"], it[@"pat"], it[@"rep"]);
            }];
        } else if ([it[@"action"] isEqualToString:@"gems"]) {
            [btn addBlockForControlEvents:UIControlEventTouchUpInside block:^{ patchGems(); }];
        } else if ([it[@"action"] isEqualToString:@"reborn"]) {
            [btn addBlockForControlEvents:UIControlEventTouchUpInside block:^{ patchReborn(); }];
        } else if ([it[@"action"] isEqualToString:@"all"]) {
            [btn addBlockForControlEvents:UIControlEventTouchUpInside block:^{ patchAllExcludingGems(); }];
        }
        
        [scroll addSubview:btn];
        y += 60;
    }
    scroll.contentSize = CGSizeMake(260, y);
    [menu showInWindow:firstWindow()];
}

#pragma mark - Data Menu & Document Actions (Custom UI)
static NSArray* listDocumentsFiles() {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *all = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil] ?: @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *f in all) if (![f hasSuffix:@".new"]) [out addObject:f];
    return out;
}

static void showFileActionMenu(NSString *fileName) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *path = [docs stringByAppendingPathComponent:fileName];
    
    CustomMenuView *menu = [[CustomMenuView alloc] init];
    menu.titleLabel.text = fileName;
    
    NSArray *actions = @[
        @{@"title":@"Export",   @"color":UIColor.systemBlueColor},
        @{@"title":@"Import",   @"color":UIColor.systemGreenColor},
        @{@"title":@"Delete",   @"color":UIColor.systemRedColor}
    ];
    
    CGFloat y = 80;
    for (NSDictionary *a in actions) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(40, y, 220, 50);
        [btn setTitle:a[@"title"] forState:UIControlStateNormal];
        btn.backgroundColor = a[@"color"];
        btn.layer.cornerRadius = 12;
        [btn addTarget:menu action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
        
        if ([a[@"title"] isEqualToString:@"Export"]) {
            [btn addBlockForControlEvents:UIControlEventTouchUpInside block:^{
                NSString *txt = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
                if (txt) UIPasteboard.generalPasteboard.string = txt;
                [menu dismiss];
                CustomMenuView *c = [[CustomMenuView alloc] init];
                c.titleLabel.text = txt ? @"Exported" : @"Error";
                UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, 260, 60)];
                l.text = txt ? @"Copied to clipboard" : @"Failed to read file";
                l.textAlignment = NSTextAlignmentCenter;
                l.textColor = UIColor.cyanColor;
                [c.container addSubview:l];
                UIButton *ok = [UIButton buttonWithType:UIButtonTypeSystem];
                ok.frame = CGRectMake(80, 160, 140, 44);
                [ok setTitle:@"OK" forState:UIControlStateNormal];
                ok.backgroundColor = UIColor.systemGrayColor;
                ok.layer.cornerRadius = 10;
                [ok addTarget:c action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
                [c.container addSubview:ok];
                [c showInWindow:firstWindow()];
            }];
        } else if ([a[@"title"] isEqualToString:@"Import"]) {
            [btn addBlockForControlEvents:UIControlEventTouchUpInside block:^{
                [menu dismiss];
                CustomMenuView *imp = [[CustomMenuView alloc] init];
                imp.titleLabel.text = @"Import";
                UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(20, 70, 260, 200)];
                tv.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
                tv.layer.cornerRadius = 10;
                tv.font = [UIFont systemFontOfSize:16];
                [imp.container addSubview:tv];
                UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
                save.frame = CGRectMake(40, 290, 100, 44);
                [save setTitle:@"Save" forState:UIControlStateNormal];
                save.backgroundColor = UIColor.systemGreenColor;
                save.layer.cornerRadius = 10;
                [imp.container addSubview:save];
                UIButton *can = [UIButton buttonWithType:UIButtonTypeSystem];
                can.frame = CGRectMake(160, 290, 100, 44);
                [can setTitle:@"Cancel" forState:UIControlStateNormal];
                can.backgroundColor = UIColor.systemRedColor;
                can.layer.cornerRadius = 10;
                [can addTarget:imp action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
                [imp.container addSubview:can];
                [save addBlockForControlEvents:UIControlEventTouchUpInside block:^{
                    BOOL ok = [tv.text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
                    [imp dismiss];
                    CustomMenuView *res = [[CustomMenuView alloc] init];
                    res.titleLabel.text = ok ? @"Imported" : @"Failed";
                    UILabel *m = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, 260, 100)];
                    m.text = ok ? @"Edit Applied\nLeave game to load new data\nThoát game để load data mới" : @"Write failed";
                    m.textAlignment = NSTextAlignmentCenter;
                    m.numberOfLines = 0;
                    [res.container addSubview:m];
                    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
                    b.frame = CGRectMake(80, 200, 140, 44);
                    [b setTitle:@"OK" forState:UIControlStateNormal];
                    b.backgroundColor = UIColor.systemGrayColor;
                    b.layer.cornerRadius = 10;
                    [b addTarget:res action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
                    [res.container addSubview:b];
                    [res showInWindow:firstWindow()];
                }];
                [imp showInWindow:firstWindow()];
            }];
        } else if ([a[@"title"] isEqualToString:@"Delete"]) {
            [btn addBlockForControlEvents:UIControlEventTouchUpInside block:^{
                BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
                [menu dismiss];
                CustomMenuView *c = [[CustomMenuView alloc] init];
                c.titleLabel.text = ok ? @"Deleted" : @"Delete failed";
                UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
                b.frame = CGRectMake(80, 120, 140, 44);
                [b setTitle:@"OK" forState:UIControlStateNormal];
                b.backgroundColor = UIColor.systemGrayColor;
                b.layer.cornerRadius = 10;
                [b addTarget:c action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
                [c.container addSubview:b];
                [c showInWindow:firstWindow()];
            }];
        }
        [menu.container addSubview:btn];
        y += 65;
    }
    [menu showInWindow:firstWindow()];
}

static void showDataMenu() {
    NSArray *files = listDocumentsFiles();
    if (files.count == 0) {
        CustomMenuView *v = [[CustomMenuView alloc] init];
        v.titleLabel.text = @"No files";
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, 260, 60)];
        l.text = @"Documents is empty";
        l.textAlignment = NSTextAlignmentCenter;
        [v.container addSubview:l];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(80, 160, 140, 44);
        [b setTitle:@"OK" forState:UIControlStateNormal];
        [b addTarget:v action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
        [v.container addSubview:b];
        [v showInWindow:firstWindow()];
        return;
    }
    
    CustomMenuView *menu = [[CustomMenuView alloc] init];
    menu.titleLabel.text = @"Documents";
    UIScrollView *sc = [[UIScrollView alloc] initWithFrame:CGRectMake(20, 70, 260, 300)];
    [menu.container addSubview:sc];
    
    CGFloat y = 10;
    for (NSString *f in files) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(0, y, 240, 50);
        [btn setTitle:f forState:UIControlStateNormal];
        btn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1];
        btn.layer.cornerRadius = 12;
        [btn addTarget:menu action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
        [btn addBlockForControlEvents:UIControlEventTouchUpInside block:^{ showFileActionMenu(f); }];
        [sc addSubview:btn];
        y += 60;
    }
    sc.contentSize = CGSizeMake(260, y);
    [menu showInWindow:firstWindow()];
}

#pragma mark - Main Menu (Custom UI)
static void showMainMenu() {
    CustomMenuView *menu = [[CustomMenuView alloc] init];
    menu.titleLabel.text = @"Menu";
    
    UIButton *player = [UIButton buttonWithType:UIButtonTypeSystem];
    player.frame = CGRectMake(40, 100, 220, 60);
    [player setTitle:@"Player" forState:UIControlStateNormal];
    player.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    player.backgroundColor = UIColor.systemIndigoColor;
    player.layer.cornerRadius = 15;
    [player addTarget:menu action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [player addBlockForControlEvents:UIControlEventTouchUpInside block:^{ showPlayerMenu(); }];
    [menu.container addSubview:player];
    
    UIButton *data = [UIButton buttonWithType:UIButtonTypeSystem];
    data.frame = CGRectMake(40, 180, 220, 60);
    [data setTitle:@"Data" forState:UIControlStateNormal];
    data.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    data.backgroundColor = UIColor.systemTealColor;
    data.layer.cornerRadius = 15;
    [data addTarget:menu action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [data addBlockForControlEvents:UIControlEventTouchUpInside block:^{ showDataMenu(); }];
    [menu.container addSubview:data];
    
    [menu showInWindow:firstWindow()];
}

#pragma mark - Floating Button & Pan Gesture (FINAL FIXES)
static UIButton *floatingButton = nil;

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // clean .new files + bypass
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil])
            if ([f hasSuffix:@".new"])
                [[NSFileManager defaultManager] removeItemAtPath:[docs stringByAppendingPathComponent:f] error:nil];

        // silent bypass patch
        [[NSUserDefaults standardUserDefaults] setPersistentDomain:@{} forName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];

        UIWindow *win = keyWindow();
        floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        floatingButton.frame = CGRectMake(20, 120, 64, 64);
        floatingButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.7 blue:1.0 alpha:0.92];
        floatingButton.layer.cornerRadius = 32;
        floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        [floatingButton setTitle:@"Menu" forState:UIControlStateNormal];
        [floatingButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [floatingButton addTarget:[UIApplication sharedApplication]
                           action:@selector(showMenuPressed)
                 forControlEvents:UIControlEventTouchUpInside];

        // Pan gesture – target is the button itself
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
            initWithTarget:floatingButton
                    action:@selector(handlePan:)];
        [floatingButton addGestureRecognizer:pan];

        [win addSubview:floatingButton];
    });
}

%hook UIApplication

%new
- (void)showMenuPressed {
    if (!g_hasShownCreditAlert) {
        g_hasShownCreditAlert = YES;
        CustomMenuView *v = [CustomMenuView new];
        v.titleLabel.text = @"Welcome";
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, 260, 100)];
        l.text = @"Thank you for using!\nCảm ơn vì đã sử dụng!";
        l.textColor = UIColor.cyanColor;
        l.textAlignment = NSTextAlignmentCenter;
        l.numberOfLines = 0;
        [v.container addSubview:l];

        UIButton *ok = [UIButton buttonWithType:UIButtonTypeSystem];
        ok.frame = CGRectMake(80, 220, 140, 50);
        [ok setTitle:@"Continue" forState:UIControlStateNormal];
        ok.backgroundColor = UIColor.systemGreenColor;
        ok.layer.cornerRadius = 12;
        [ok addTarget:v action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
        [ok addBlockForControlEvents:UIControlEventTouchUpInside block:^{ verifyAccessAndOpenMenu(); }];
        [v.container addSubview:ok];
        [v showInWindow:keyWindow()];
    } else {
        verifyAccessAndOpenMenu();
    }
}

// Pan handler – now correctly inside the button instance
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    static CGPoint start;
    if (pan.state == UIGestureRecognizerStateBegan) {
        start = pan.view.center;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [pan translationInView:pan.view.superview];
        pan.view.center = CGPointMake(start.x + t.x, start.y + t.y);
    }
}
%end
