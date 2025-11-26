// Tweak.xm
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>

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
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:(ok?@"Success":@"Failed")
                                                                       message:[NSString stringWithFormat:@"%@ %@", title, ok?@"applied":@"failed"]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - Gems/Reborn/Bypass/PatchAll

static void patchGems() {
    UIAlertController *input = [UIAlertController alertControllerWithTitle:@"Set Gems" message:@"Enter value" preferredStyle:UIAlertControllerStyleAlert];
    [input addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.keyboardType = UIKeyboardTypeNumberPad; tf.placeholder = @"0"; }];
    [input addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSInteger v = [input.textFields.firstObject.text integerValue];
        NSString *re1 = @"(<key>\\d+_gems</key>\\s*<integer>)\\d+";
        NSString *re2 = @"(<key>\\d+_last_gems</key>\\s*<integer>)\\d+";
        silentApplyRegexToDomain(re1, [NSString stringWithFormat:@"$1%ld", (long)v]);
        silentApplyRegexToDomain(re2, [NSString stringWithFormat:@"$1%ld", (long)v]);
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Gems Updated" message:[NSString stringWithFormat:@"%ld", (long)v] preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:done animated:YES completion:nil];
    }]];
    [input addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:input animated:YES completion:nil];
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

    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Patch All" message:@"Applied (excluding Gems)" preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:done animated:YES completion:nil];
    });
}

#pragma mark - Player menu

static void showPlayerMenu() {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Player" message:@"Choose patch" preferredStyle:UIAlertControllerStyleAlert];

    [menu addAction:[UIAlertAction actionWithTitle:@"Characters" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        applyPatchWithAlert(@"Characters", @"(<key>\\d+_c\\d+_unlock.*\\n.*)false", @"$1True");
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Skins" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        applyPatchWithAlert(@"Skins", @"(<key>\\d+_c\\d+_skin\\d+.*\\n.*>)[+-]?\\d+", @"$11");
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Skills" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        applyPatchWithAlert(@"Skills", @"(<key>\\d+_c_.*_skill_\\d_unlock.*\\n.*<integer>)\\d", @"$11");
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Pets" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        applyPatchWithAlert(@"Pets", @"(<key>\\d+_p\\d+_unlock.*\\n.*)false", @"$1True");
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Level" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        applyPatchWithAlert(@"Level", @"(<key>\\d+_c\\d+_level+.*\\n.*>)[+-]?\\d+", @"$18");
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Furniture" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        applyPatchWithAlert(@"Furniture", @"(<key>\\d+_furniture+_+.*\\n.*>)[+-]?\\d+", @"$15");
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Gems" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        patchGems();
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Reborn" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        patchRebornWithAlert();
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Patch All" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        patchAllExcludingGems();
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:menu animated:YES completion:nil];
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

    UIAlertController *menu = [UIAlertController alertControllerWithTitle:fileName message:@"Action" preferredStyle:UIAlertControllerStyleAlert];

    [menu addAction:[UIAlertAction actionWithTitle:@"Export" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSError *err = nil;
        NSString *txt = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
        if (txt) UIPasteboard.generalPasteboard.string = txt;
        UIAlertController *done = [UIAlertController alertControllerWithTitle:(txt?@"Exported":@"Error") message:(txt?@"Copied to clipboard":err.localizedDescription) preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:done animated:YES completion:nil];
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Import" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        UIAlertController *input = [UIAlertController alertControllerWithTitle:@"Import" message:@"Paste text to import" preferredStyle:UIAlertControllerStyleAlert];
        [input addTextFieldWithConfigurationHandler:nil];
        [input addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *ok){
            NSString *txt = input.textFields.firstObject.text ?: @"";
            NSError *err = nil;
            BOOL okw = [txt writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
            UIAlertController *done = [UIAlertController alertControllerWithTitle:(okw?@"Imported":@"Import Failed") message:(okw?@"Edit Applied\nLeave game to load new data\nThoát game để load data mới":err.localizedDescription) preferredStyle:UIAlertControllerStyleAlert];
            [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [topVC() presentViewController:done animated:YES completion:nil];
        }]];
        [input addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [topVC() presentViewController:input animated:YES completion:nil];
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
        NSError *err = nil;
        BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:path error:&err];
        UIAlertController *done = [UIAlertController alertControllerWithTitle:(ok?@"Deleted":@"Delete failed") message:(ok?@"File removed":err.localizedDescription) preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:done animated:YES completion:nil];
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:menu animated:YES completion:nil];
}

static void showDataMenu() {
    NSArray *files = listDocumentsFiles();
    if (files.count == 0) {
        UIAlertController *e = [UIAlertController alertControllerWithTitle:@"No files" message:@"Documents is empty" preferredStyle:UIAlertControllerStyleAlert];
        [e addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:e animated:YES completion:nil];
        return;
    }
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Documents" message:@"Select file" preferredStyle:UIAlertControllerStyleAlert];
    for (NSString *f in files) {
        [menu addAction:[UIAlertAction actionWithTitle:f style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            showFileActionMenu(f);
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:menu animated:YES completion:nil];
}

#pragma mark - Main Menu

static void showMainMenu() {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Menu" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [menu addAction:[UIAlertAction actionWithTitle:@"Player" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ showPlayerMenu(); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Data" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ showDataMenu(); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:menu animated:YES completion:nil];
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
            NSString *message = @"Thank you for using!\n"
                                @"Cảm ơn vì đã sử dụng!\n";

            UIAlertController *credit = [UIAlertController alertControllerWithTitle:@"Info"
                                                                            message:message
                                                                     preferredStyle:UIAlertControllerStyleAlert];

            [credit addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                verifyAccessAndOpenMenu();
            }]];

            [topVC() presentViewController:credit animated:YES completion:nil];
        });
    } else {
        verifyAccessAndOpenMenu();
    }
}

%new
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *piece = pan.view;
    CGPoint translation = [pan translationInView:piece.superview];

    if (pan.state == UIGestureRecognizerStateBegan) {
        g_startPoint = piece.center;
        g_btnStart = [pan locationInView:piece.superview];
    }

    if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint location = [pan locationInView:piece.superview];
        CGFloat dx = location.x - g_btnStart.x;
        CGFloat dy = location.y - g_btnStart.y;
        piece.center = CGPointMake(g_startPoint.x + dx, g_startPoint.y + dy);
    }

    if (pan.state == UIGestureRecognizerStateEnded ||
        pan.state == UIGestureRecognizerStateCancelled) {

        // Giới hạn nút trong màn hình
        CGFloat W = piece.superview.bounds.size.width;
        CGFloat H = piece.superview.bounds.size.height;
        CGFloat halfW = piece.frame.size.width / 2;
        CGFloat halfH = piece.frame.size.height / 2;

        CGFloat finalX = MIN(MAX(piece.center.x, halfW), W - halfW);
        CGFloat finalY = MIN(MAX(piece.center.y, halfH), H - halfH);

        [UIView animateWithDuration:0.25 animations:^{
            piece.center = CGPointMake(finalX, finalY);
        }];
    }
}
%end
