// Tweak.xm - FULL ImGui-Style Custom Menu (No UIAlertController)
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#import <objc/runtime.h>

#pragma mark - CONFIG
static NSString * const kHexKey = @"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
static NSString * const kHexHmacKey = @"fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210";
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

static NSString* base64Encode(NSData *d) { return [d base64EncodedStringWithOptions:0]; }
static NSData* base64Decode(NSString *s) { return [[NSData alloc] initWithBase64EncodedString:s options:0]; }

#pragma mark - AES-256-CBC + HMAC-SHA256
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

    NSMutableData *forHmac = [NSMutableData data];
    [forHmac appendData:iv]; [forHmac appendData:cipher];
    unsigned char hmac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, hmacKey.length, forHmac.bytes, forHmac.length, hmac);
    NSData *hmacData = [NSData dataWithBytes:hmac length:CC_SHA256_DIGEST_LENGTH];

    NSMutableData *box = [NSMutableData data];
    [box appendData:iv]; [box appendData:cipher]; [box appendData:hmacData];
    return box;
}

static NSData* decryptAndVerify(NSData *box, NSData *key, NSData *hmacKey) {
    if (box.length < 48) return nil;
    NSData *iv = [box subdataWithRange:NSMakeRange(0,16)];
    NSData *hmac = [box subdataWithRange:NSMakeRange(box.length - 32, 32)];
    NSData *cipher = [box subdataWithRange:NSMakeRange(16, box.length - 48)];

    NSMutableData *forHmac = [NSMutableData data];
    [forHmac appendData:iv]; [forHmac appendData:cipher];
    unsigned char calc[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, hmacKey.length, forHmac.bytes, forHmac.length, calc);
    if (memcmp(calc, hmac.bytes, 32) != 0) return nil;

    size_t outlen = cipher.length + kCCBlockSizeAES128;
    void *outbuf = malloc(outlen);
    size_t actualOut = 0;
    CCCryptorStatus st = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                 key.bytes, key.length, iv.bytes,
                                 cipher.bytes, cipher.length, outbuf, outlen, &actualOut);
    if (st != kCCSuccess) { free(outbuf); return nil; }
    return [NSData dataWithBytesNoCopy:outbuf length:actualOut freeWhenDone:YES];
}

#pragma mark - App UUID
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
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) return w;
            }
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static void killApp() { exit(0); }
static NSString *g_lastTimestamp = nil;

#pragma mark - IMGUI-STYLE MENU SYSTEM
static UIView *g_menuOverlay = nil;

static void dismissMenu() {
    [g_menuOverlay removeFromSuperview];
    g_menuOverlay = nil;
}

static void showMessage(NSString *title, NSString *message, void(^completion)(void)) {
    dismissMenu();
    UIWindow *win = firstWindow();
    g_menuOverlay = [[UIView alloc] initWithFrame:win.bounds];
    g_menuOverlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
    [win addSubview:g_menuOverlay];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blur.frame = g_menuOverlay.bounds;
    [g_menuOverlay addSubview:blur];

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0,0,300,200)];
    panel.center = g_menuOverlay.center;
    panel.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.98];
    panel.layer.cornerRadius = 18;
    panel.layer.borderWidth = 2;
    panel.layer.borderColor = [UIColor colorWithRed:0 green:0.8 blue:1 alpha:1].CGColor;
    [g_menuOverlay addSubview:panel];

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(20,25,260,40)];
    t.text = title; t.textColor = UIColor.cyanColor; t.font = [UIFont boldSystemFontOfSize:22]; t.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:t];

    UILabel *m = [[UILabel alloc] initWithFrame:CGRectMake(20,70,260,60)];
    m.text = message; m.textColor = UIColor.whiteColor; m.font = [UIFont systemFontOfSize:16]; m.numberOfLines = 0; m.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:m];

    UIButton *ok = [UIButton buttonWithType:UIButtonTypeSystem];
    ok.frame = CGRectMake(70,140,160,44);
    [ok setTitle:@"OK" forState:UIControlStateNormal];
    [ok setTitleColor:UIColor.cyanColor forState:UIControlStateNormal];
    ok.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    ok.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    ok.layer.cornerRadius = 12;
    [ok addTarget:nil action:@selector(dismissMenu) forControlEvents:UIControlEventTouchUpInside];
    [ok addBlockInvocationHandler:^(UIButton *) {
        if (completion) completion();
    } forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:ok];
}

static void showCustomMenu(NSString *title, NSArray<NSDictionary *> *items) {
    dismissMenu();
    UIWindow *win = firstWindow();
    g_menuOverlay = [[UIView alloc] initWithFrame:win.bounds];
    g_menuOverlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
    [win addSubview:g_menuOverlay];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blur.frame = g_menuOverlay.bounds;
    [g_menuOverlay addSubview:blur];

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0,0,320,520)];
    panel.center = g_menuOverlay.center;
    panel.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.98];
    panel.layer.cornerRadius = 20;
    panel.layer.borderWidth = 2.5;
    panel.layer.borderColor = [UIColor colorWithRed:0 green:0.8 blue:1 alpha:1].CGColor;
    [g_menuOverlay addSubview:panel];

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(0,20,320,50)];
    t.text = title; t.textColor = UIColor.cyanColor; t.font = [UIFont boldSystemFontOfSize:24]; t.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:t];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = CGRectMake(280,15,40,40);
    [close setTitle:@"X" forState:UIControlStateNormal];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:28];
    [close addTarget:nil action:@selector(dismissMenu) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:close];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(25,80,270,420)];
    [panel addSubview:scroll];

    UIView *content = [[UIView alloc] initWithFrame:CGRectMake(0,0,270,items.count * 65 + 20)];
    [scroll addSubview:content];
    scroll.contentSize = content.frame.size;

    for (NSInteger i = 0; i < items.count; i++) {
        NSDictionary *item = items[i];
        NSString *text = item[@"title"];
        void(^action)(void) = item[@"action"];
        BOOL destructive = [item[@"destructive"] boolValue];
        BOOL cancel = [item[@"cancel"] boolValue];

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(0, i * 65, 270, 58);
        [btn setTitle:text forState:UIControlStateNormal];
        [btn setTitleColor:destructive ? UIColor.redColor : (cancel ? UIColor.grayColor : UIColor.cyanColor)
                  forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:19 weight:cancel ? UIFontWeightMedium : UIFontWeightBold];
        btn.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        btn.layer.cornerRadius = 14;
        btn.layer.borderWidth = 1.5;
        btn.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:1].CGColor;
        [btn addBlockInvocationHandler:^(UIButton *) {
            dismissMenu();
            if (action) action();
        } forControlEvents:UIControlEventTouchUpInside];
        [content addSubview:btn];
    }
}

static void showInputDialog(NSString *title, NSString *message, NSString *placeholder, void(^completion)(NSString *)) {
    dismissMenu();
    UIWindow *win = firstWindow();
    g_menuOverlay = [[UIView alloc] initWithFrame:win.bounds];
    g_menuOverlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
    [win addSubview:g_menuOverlay];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blur.frame = g_menuOverlay.bounds;
    [g_menuOverlay addSubview:blur];

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0,0,300,250)];
    panel.center = g_menuOverlay.center;
    panel.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.98];
    panel.layer.cornerRadius = 18;
    panel.layer.borderWidth = 2;
    panel.layer.borderColor = UIColor.cyanColor.CGColor;
    [g_menuOverlay addSubview:panel];

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(20,20,260,40)];
    t.text = title; t.textColor = UIColor.cyanColor; t.font = [UIFont boldSystemFontOfSize:22]; t.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:t];

    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(30,80,240,48)];
    tf.borderStyle = UITextBorderStyleRoundedRect;
    tf.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    tf.textColor = UIColor.whiteColor;
    tf.font = [UIFont systemFontOfSize:18];
    tf.keyboardType = UIKeyboardTypeNumberPad;
    tf.placeholder = placeholder;
    [panel addSubview:tf];

    UIButton *ok = [UIButton buttonWithType:UIButtonTypeSystem];
    ok.frame = CGRectMake(30,160,110,48);
    [ok setTitle:@"OK" forState:UIControlStateNormal];
    [ok setTitleColor:UIColor.cyanColor forState:UIControlStateNormal];
    ok.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    ok.layer.cornerRadius = 12;
    [ok addBlockInvocationHandler:^(UIButton *) {
        dismissMenu();
        if (completion) completion(tf.text.length ? tf.text : @"0");
    } forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:ok];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    cancel.frame = CGRectMake(160,160,110,48);
    [cancel setTitle:@"Cancel" forState:UIControlStateNormal];
    [cancel setTitleColor:UIColor.lightGrayColor forState:UIControlStateNormal];
    cancel.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    cancel.layer.cornerRadius = 12;
    [cancel addTarget:nil action:@selector(dismissMenu) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:cancel];

    [tf becomeFirstResponder];
}

#pragma mark - Regex & Patch Helpers
static NSString* dictToPlist(NSDictionary *d) {
    NSError *err = nil;
    NSData *dat = [NSPropertyListSerialization dataWithPropertyList:d format:NSPropertyListXMLFormat_v1_0 options:0 error:&err];
    return dat ? [[NSString alloc] initWithData:dat encoding:NSUTF8StringEncoding] : nil;
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
    showMessage(ok ? @"Success" : @"Failed", [NSString stringWithFormat:@"%@ %@", title, ok ? @"applied" : @"failed"], nil);
}

#pragma mark - Patches
static void patchGems() {
    showInputDialog(@"Set Gems", @"Enter value", @"0", ^(NSString *text) {
        NSInteger v = [text integerValue];
        if (v <= 0) v = 999999;
        NSString *re1 = @"(<key>\\d+_gems</key>\\s*<integer>)\\d+";
        NSString *re2 = @"(<key>\\d+_last_gems</key>\\s*<integer>)\\d+";
        silentApplyRegexToDomain(re1, [NSString stringWithFormat:@"$1%ld", (long)v]);
        silentApplyRegexToDomain(re2, [NSString stringWithFormat:@"$1%ld", (long)v]);
        showMessage(@"Gems Updated", [NSString stringWithFormat:@"%ld", (long)v], nil);
    });
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
        @"Skins":      @"(<key>\\d+_c\\d+_skin\\d+.*\\n.*>)[+-]?\\d+",
        @"Skills":     @"(<key>\\d+_c_.*_skill_\\d_unlock.*\\n.*<integer>)\\d",
        @"Pets":       @"(<key>\\d+_p\\d+_unlock.*\\n.*)false",
        @"Level":      @"(<key>\\d+_c\\d+_level+.*\\n.*>)[+-]?\\d+",
        @"Furniture":  @"(<key>\\d+_furniture+_+.*\\n.*>)[+-]?\\d+"
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

    showMessage(@"Patch All", @"Applied (excluding Gems)", nil);
}

#pragma mark - Menus
static void showPlayerMenu() {
    showCustomMenu(@"Player", @[
        @{@"title": @"Characters", @"action": ^{ applyPatchWithAlert(@"Characters", @"(<key>\\d+_c\\d+_unlock.*\\n.*)false", @"$1True"); }},
        @{@"title": @"Skins",      @"action": ^{ applyPatchWithAlert(@"Skins", @"(<key>\\d+_c\\d+_skin\\d+.*\\n.*>)[+-]?\\d+", @"$11"); }},
        @{@"title": @"Skills",     @"action": ^{ applyPatchWithAlert(@"Skills", @"(<key>\\d+_c_.*_skill_\\d_unlock.*\\n.*<integer>)\\d", @"$11"); }},
        @{@"title": @"Pets",       @"action": ^{ applyPatchWithAlert(@"Pets", @"(<key>\\d+_p\\d+_unlock.*\\n.*)false", @"$1True"); }},
        @{@"title": @"Level",      @"action": ^{ applyPatchWithAlert(@"Level", @"(<key>\\d+_c\\d+_level+.*\\n.*>)[+-]?\\d+", @"$18"); }},
        @{@"title": @"Furniture",  @"action": ^{ applyPatchWithAlert(@"Furniture", @"(<key>\\d+_furniture+_+.*\\n.*>)[+-]?\\d+", @"$15"); }},
        @{@"title": @"Gems",       @"action": ^{ patchGems(); }},
        @{@"title": @"Reborn",     @"action": ^{ patchRebornWithAlert(); }},
        @{@"title": @"Patch All",  @"action": ^{ patchAllExcludingGems(); }},
        @{@"title": @"Cancel",     @"cancel": @YES}
    ]);
}

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

    showCustomMenu(fileName, @[
        @{@"title": @"Export", @"action": ^{
            NSString *txt = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            if (txt) UIPasteboard.generalPasteboard.string = txt;
            showMessage(txt ? @"Exported" : @"Error", txt ? @"Copied to clipboard" : @"Failed to read", nil);
        }},
        @{@"title": @"Import", @"action": ^{
            showInputDialog(@"Import", @"Paste text to import", @"", ^(NSString *txt) {
                BOOL ok = [txt writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
                showMessage(ok ? @"Imported" : @"Import Failed", ok ? @"Edit Applied\nLeave game to load new data\nThoát game để load data mới" : @"Write failed", nil);
            });
        }},
        @{@"title": @"Delete", @"destructive": @YES, @"action": ^{
            BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            showMessage(ok ? @"Deleted" : @"Delete failed", ok ? @"File removed" : @"Error", nil);
        }},
        @{@"title": @"Cancel", @"cancel": @YES}
    ]);
}

static void showDataMenu() {
    NSArray *files = listDocumentsFiles();
    if (files.count == 0) {
        showMessage(@"No files", @"Documents is empty", nil);
        return;
    }
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *f in files) {
        [items addObject:@{@"title": f, @"action": ^{ showFileActionMenu(f); }}];
    }
    [items addObject:@{@"title": @"Cancel", @"cancel": @YES}];
    showCustomMenu(@"Documents", items);
}

static void showMainMenu() {
    showCustomMenu(@"Menu", @[
        @{@"title": @"Player", @"action": ^{ showPlayerMenu(); }},
        @{@"title": @"Data",   @"action": ^{ showDataMenu(); }},
        @{@"title": @"Cancel", @"cancel": @YES}
    ]);
}

#pragma mark - Network Verification
static void verifyAccessAndOpenMenu() {
    NSData *key = dataFromHex(kHexKey);
    NSData *hmacKey = dataFromHex(kHexHmacKey);
    if (!key || key.length != 32 || !hmacKey || hmacKey.length != 32) {
        killApp(); return;
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
        if (!respBox) { killApp(); return; }

        NSData *plainResp = decryptAndVerify(respBox, key, hmacKey);
        if (!plainResp) { killApp(); return; }

        NSDictionary *respJSON = [NSJSONSerialization JSONObjectWithData:plainResp options:0 error:nil];
        if (!respJSON) { killApp(); return; }

        NSString *r_uuid = respJSON[@"uuid"];
        NSString *r_ts = respJSON[@"timestamp"];
        BOOL allow = [respJSON[@"allow"] boolValue];

        if (!r_uuid || ![r_uuid isEqualToString:uuid] || !r_ts || ![r_ts isEqualToString:g_lastTimestamp] || !allow) {
            killApp(); return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            showMainMenu();
        });
    }] resume];
}

#pragma mark - Floating Button + ctor
static UIButton *floatingButton = nil;

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Auto clean .new files
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil]) {
            if ([f hasSuffix:@".new"]) {
                [[NSFileManager defaultManager] removeItemAtPath:[docs stringByAppendingPathComponent:f] error:nil];
            }
        }
        silentPatchBypass();

        // Floating Button
        UIWindow *win = firstWindow();
        floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        floatingButton.frame = CGRectMake(15, 80, 60, 60);
        floatingButton.backgroundColor = [UIColor colorWithRed:0 green:0.7 blue:1 alpha:0.9];
        floatingButton.layer.cornerRadius = 30;
        floatingButton.layer.shadowColor = [UIColor cyanColor].CGColor;
        floatingButton.layer.shadowOpacity = 0.8;
        floatingButton.layer.shadowRadius = 10;
        [floatingButton setTitle:@"M" forState:UIControlStateNormal];
        floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:28];
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
        showMessage(@"Info", @"Thank you for using!\nCảm ơn vì đã sử dụng!", ^{
            verifyAccessAndOpenMenu();
        });
    } else {
        verifyAccessAndOpenMenu();
    }
}

%new
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    static CGPoint start;
    if (pan.state == UIGestureRecognizerStateBegan) {
        start = [pan locationInView:pan.view.superview];
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint p = [pan locationInView:pan.view.superview];
        pan.view.center = CGPointMake(pan.view.center.x + (p.x - start.x), pan.view.center.y + (p.y - start.y));
        start = p;
    }
}
%end

// Helper for block invocation (add to UIButton)
@interface UIButton (Block)
- (void)addBlockInvocationHandler:(void(^)(UIButton *))block forControlEvents:(UIControlEvents)events;
@end

@implementation UIButton (Block)
- (void)addBlockInvocationHandler:(void(^)(UIButton *))block forControlEvents:(UIControlEvents)events {
    objc_setAssociatedObject(self, @selector(addBlockInvocationHandler:forControlEvents:), block, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self addTarget:self action:@selector(invokeBlock:) forControlEvents:events];
}
- (void)invokeBlock:(UIButton *)b {
    void(^block)(UIButton *) = objc_getAssociatedObject(self, @selector(addBlockInvocationHandler:forControlEvents:));
    if (block) block(b);
}
@end
