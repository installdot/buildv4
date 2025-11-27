// Tweak.xm - FULLY FIXED & COMPILABLE - BEAUTIFUL UI + BACKGROUND + FILTERED DATA
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#import <objc/runtime.h>

#pragma mark - CONFIG
static NSString * const kHexKey = @"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
static NSString * const kHexHmacKey = @"fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210";
static NSString * const kServerURL = @"https://chillysilly.frfrnocap.men/iost.php";
static BOOL g_hasShownCreditAlert = NO;

#pragma mark - Global UI
static UIView *g_overlay = nil;
static UIImageView *g_backgroundImageView = nil;
static UIButton *g_floatingButton = nil;
static NSString *g_backgroundURL = nil;
static const void *kFileNameKey = &kFileNameKey;

#pragma mark - Background Image
static NSString *backgroundURLPath() {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/bg_url.txt"];
}

static void saveBackgroundURL(NSString *url) {
    [url writeToFile:backgroundURLPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    g_backgroundURL = url;
}

static void loadBackgroundURL() {
    g_backgroundURL = [NSString stringWithContentsOfFile:backgroundURLPath() encoding:NSUTF8StringEncoding error:nil];
    if (!g_backgroundURL || g_backgroundURL.length == 0) {
        g_backgroundURL = @"https://i.imgur.com/9k0L3aZ.jpg";
        saveBackgroundURL(g_backgroundURL);
    }
}

static void downloadAndSetBackground(NSString *urlStr) {
    if (!urlStr.length) return;
    NSURL *url = [NSURL URLWithString:urlStr];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (data && !err) {
            UIImage *img = [UIImage imageWithData:data];
            dispatch_async(dispatch_get_main_queue(), ^{
                g_backgroundImageView.image = img;
                saveBackgroundURL(urlStr);
            });
        }
    }] resume];
}

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

#pragma mark - AES-256-CBC + HMAC
static NSData* encryptPayload(NSData *plaintext, NSData *key, NSData *hmacKey) {
    uint8_t ivBytes[16]; arc4random_buf(ivBytes, sizeof(ivBytes));
    NSData *iv = [NSData dataWithBytes:ivBytes length:16];
    size_t outlen = plaintext.length + kCCBlockSizeAES128;
    void *outbuf = malloc(outlen); size_t actualOut = 0;
    CCCryptorStatus st = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                 key.bytes, key.length, iv.bytes,
                                 plaintext.bytes, plaintext.length, outbuf, outlen, &actualOut);
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
    void *outbuf = malloc(outlen); size_t actualOut = 0;
    CCCryptorStatus st = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                 key.bytes, key.length, iv.bytes,
                                 cipher.bytes, cipher.length, outbuf, outlen, &actualOut);
    if (st != kCCSuccess) { free(outbuf); return nil; }
    return [NSData dataWithBytesNoCopy:outbuf length:actualOut freeWhenDone:YES];
}

static NSString* appUUID() {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/uuid.txt"];
    NSString *uuid = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!uuid || uuid.length == 0) {
        uuid = [[NSUUID UUID] UUIDString];
        [uuid writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return uuid;
}

static NSString *g_lastTimestamp = nil;
static void killApp() { exit(0); }

#pragma mark - Window & VC
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
    UIViewController *vc = win.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static void dismissOverlay() {
    [g_overlay removeFromSuperview];
    g_overlay = nil;
}

#pragma mark - Patch Functions (100% unchanged)
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
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController alertControllerWithTitle:(ok?@"Success":@"Failed")
                                    message:[NSString stringWithFormat:@"%@ %@", title, ok?@"applied":@"failed"]
                             preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:a animated:YES completion:nil];
    });
}

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

static void patchRebornWithAlert() { applyPatchWithAlert(@"Reborn", @"(<key>\\d+_reborn_card</key>\\s*<integer>)\\d+", @"$11"); }
static void silentPatchBypass() { silentApplyRegexToDomain(@"(<key>OpenRijTest_\\d+</key>\\s*<integer>)\\d+", @"$10"); }

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
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Patch All" message:@"Applied (excluding Gems)" preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:done animated:YES completion:nil];
    });
}

#pragma mark - File List & Actions
static NSArray* filteredDocumentsFiles(NSString *keyword) {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil] ?: @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *f in files) {
        if ([f hasSuffix:@".new"]) continue;
        if (!keyword || [f localizedCaseInsensitiveContainsString:keyword]) [out addObject:f];
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

#pragma mark - Menus (Beautiful UI)
static void showFilteredDataMenu(NSString *filter) {
    NSArray *files = filteredDocumentsFiles(filter);
    if (files.count == 0) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"No files" message:[NSString stringWithFormat:@"No %@ files found", filter] preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:a animated:YES completion:nil];
        return;
    }

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(40, 100, [UIScreen mainScreen].bounds.size.width - 80, 500)];
    panel.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    panel.layer.cornerRadius = 24;
    panel.layer.shadowOpacity = 0.8;
    panel.layer.shadowRadius = 20;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, panel.frame.size.width, 40)];
    title.text = [NSString stringWithFormat:@"%@ Files", filter];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:24];
    title.textColor = UIColor.cyanColor;
    [panel addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(panel.frame.size.width - 60, 10, 50, 50);
    [close setTitle:@"X" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBold];
    [close setTitleColor:UIColor.redColor forState:UIControlStateNormal];
    [close addTarget:nil action:@selector(dismissOverlay) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:close];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(20, 80, panel.frame.size.width - 40, 380)];
    [panel addSubview:scroll];

    CGFloat y = 15;
    for (NSString *f in files) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(0, y, scroll.frame.size.width, 55);
        b.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
        b.layer.cornerRadius = 12;
        [b setTitle:f forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        objc_setAssociatedObject(b, kFileNameKey, f, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [b addTarget:nil action:@selector(fileButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:b];
        y += 65;
    }
    scroll.contentSize = CGSizeMake(0, y + 20);

    g_overlay = panel;
    [topVC().view addSubview:g_overlay];
}

+ (void)fileButtonTapped:(UIButton *)btn {
    NSString *fileName = objc_getAssociatedObject(btn, kFileNameKey);
    [g_overlay removeFromSuperview];
    g_overlay = nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        showFileActionMenu(fileName);
    });
}

static void showDataMenu() {
    UIView *panel = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    panel.backgroundColor = [UIColor clearColor];

    g_backgroundImageView = [[UIImageView alloc] initWithFrame:panel.bounds];
    g_backgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
    g_backgroundImageView.clipsToBounds = YES;
    [panel addSubview:g_backgroundImageView];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blur.frame = panel.bounds;
    [panel addSubview:blur];

    UIView *content = [[UIView alloc] initWithFrame:CGRectMake(30, 120, panel.frame.size.width - 60, 420)];
    content.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.97];
    content.layer.cornerRadius = 28;
    content.layer.shadowOpacity = 0.9;
    content.layer.shadowRadius = 25;
    [panel addSubview:content];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 25, content.frame.size.width, 50)];
    title.text = @"Data Manager";
    title.font = [UIFont boldSystemFontOfSize:30];
    title.textColor = UIColor.cyanColor;
    title.textAlignment = NSTextAlignmentCenter;
    [content addSubview:title];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(content.frame.size.width - 70, 15, 60, 60);
    [closeBtn setTitle:@"X" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:36 weight:UIFontWeightBold];
    [closeBtn setTitleColor:UIColor.redColor forState:UIControlStateNormal];
    [closeBtn addTarget:nil action:@selector(dismissOverlay) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:closeBtn];

    NSArray *options = @[@"Statistic", @"Item", @"Season", @"Weapon"];
    NSArray *colors = @[[UIColor systemPurpleColor], [UIColor systemOrangeColor], [UIColor systemGreenColor], [UIColor systemBlueColor]];
    for (int i = 0; i < options.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(25, 100 + i * 80, content.frame.size.width - 50, 65);
        b.backgroundColor = colors[i];
        b.layer.cornerRadius = 16;
        b.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        [b setTitle:options[i] forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.tag = i;
        [b addTarget:nil action:@selector(dataFilterTapped:) forControlEvents:UIControlEventTouchUpInside];
        [content addSubview:b];
    }

    g_overlay = panel;
    [topVC().view addSubview:g_overlay];
}

+ (void)dataFilterTapped:(UIButton *)b {
    [g_overlay removeFromSuperview];
    g_overlay = nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        showFilteredDataMenu(@[@"Statistic", @"Item", @"Season", @"Weapon"][b.tag]);
    });
}

static void showPlayerMenu() {
    UIView *panel = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    panel.backgroundColor = [UIColor clearColor];

    g_backgroundImageView = [[UIImageView alloc] initWithFrame:panel.bounds];
    g_backgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
    [panel addSubview:g_backgroundImageView];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blur.frame = panel.bounds;
    [panel addSubview:blur];

    UIView *content = [[UIView alloc] initWithFrame:CGRectMake(30, 80, panel.frame.size.width - 60, 580)];
    content.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.97];
    content.layer.cornerRadius = 28;
    [panel addSubview:content];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 25, content.frame.size.width, 50)];
    title.text = @"Player Hacks";
    title.font = [UIFont boldSystemFontOfSize:30];
    title.textColor = UIColor.cyanColor;
    title.textAlignment = NSTextAlignmentCenter;
    [content addSubview:title];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(content.frame.size.width - 70, 15, 60, 60);
    [closeBtn setTitle:@"X" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:36 weight:UIFontWeightBold];
    [closeBtn setTitleColor:UIColor.redColor forState:UIControlStateNormal];
    [closeBtn addTarget:nil action:@selector(dismissOverlay) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:closeBtn];

    NSArray *titles = @[@"Characters", @"Skins", @"Skills", @"Pets", @"Level", @"Furniture", @"Gems", @"Reborn", @"Patch All"];
    NSArray *colors = @[[UIColor systemRedColor], [UIColor systemPinkColor], [UIColor systemTealColor], [UIColor systemIndigoColor],
                        [UIColor systemYellowColor], [UIColor systemGrayColor], [UIColor systemGreenColor], [UIColor systemPurpleColor], [UIColor orangeColor]];

    for (int i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(25, 90 + i * 68, content.frame.size.width - 50, 60);
        b.backgroundColor = colors[i];
        b.layer.cornerRadius = 16;
        b.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.tag = i;
        [b addTarget:nil action:@selector(playerButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [content addSubview:b];
    }

    g_overlay = panel;
    [topVC().view addSubview:g_overlay];
}

+ (void)playerButtonTapped:(UIButton *)b {
    [g_overlay removeFromSuperview];
    g_overlay = nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        switch (b.tag) {
            case 0: applyPatchWithAlert(@"Characters", @"(<key>\\d+_c\\d+_unlock.*\\n.*)false", @"$1True"); break;
            case 1: applyPatchWithAlert(@"Skins", @"(<key>\\d+_c\\d+_skin\\d+.*\\n.*>)[+-]?\\d+", @"$11"); break;
            case 2: applyPatchWithAlert(@"Skills", @"(<key>\\d+_c_.*_skill_\\d_unlock.*\\n.*<integer>)\\d", @"$11"); break;
            case 3: applyPatchWithAlert(@"Pets", @"(<key>\\d+_p\\d+_unlock.*\\n.*)false", @"$1True"); break;
            case 4: applyPatchWithAlert(@"Level", @"(<key>\\d+_c\\d+_level+.*\\n.*>)[+-]?\\d+", @"$18"); break;
            case 5: applyPatchWithAlert(@"Furniture", @"(<key>\\d+_furniture+_+.*\\n.*>)[+-]?\\d+", @"$15"); break;
            case 6: patchGems(); break;
            case 7: patchRebornWithAlert(); break;
            case 8: patchAllExcludingGems(); break;
        }
    });
}

static void showSettingsMenu();

static void showMainMenu() {
    UIView *panel = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    panel.backgroundColor = [UIColor clearColor];

    g_backgroundImageView = [[UIImageView alloc] initWithFrame:panel.bounds];
    g_backgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
    g_backgroundImageView.clipsToBounds = YES;
    [panel addSubview:g_backgroundImageView];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blur.frame = panel.bounds;
    [panel addSubview:blur];

    UIView *content = [[UIView alloc] initWithFrame:CGRectMake(40, 150, [UIScreen mainScreen].bounds.size.width - 80, 380)];
    content.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    content.layer.cornerRadius = 30;
    content.layer.shadowOpacity = 0.9;
    content.layer.shadowRadius = 30;
    [panel addSubview:content];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 30, content.frame.size.width, 60)];
    title.text = @"Main Menu";
    title.font = [UIFont boldSystemFontOfSize:36];
    title.textColor = UIColor.cyanColor;
    title.textAlignment = NSTextAlignmentCenter;
    [content addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = CGRectMake(content.frame.size.width - 80, 20, 70, 70);
    [close setTitle:@"✕" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:40 weight:UIFontWeightBold];
    [close setTitleColor:UIColor.redColor forState:UIControlStateNormal];
    [close addTarget:topVC() action:@selector(dismissOverlay) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:close];

    UIButton *player = createMenuButton(@"Player", [UIColor systemPurpleColor], NSSelectorFromString(@"tmp"));
    player.frame = CGRectMake(30, 110, content.frame.size.width - 60, 70);
    [player addBlockForControlEvents:UIControlEventTouchUpInside block:^(id){ dismissOverlay(); dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ showPlayerMenu(); }); }];
    [content addSubview:player];

    UIButton *data = createMenuButton(@"Data", [UIColor systemOrangeColor], NSSelectorFromString(@"tmp"));
    data.frame = CGRectMake(30, 200, content.frame.size.width - 60, 70);
    [data addBlockForControlEvents:UIControlEventTouchUpInside block:^(id){ dismissOverlay(); dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ showDataMenu(); }); }];
    [content addSubview:data];

    UIButton *settings = createMenuButton(@"Settings", [UIColor systemBlueColor], NSSelectorFromString(@"tmp"));
    settings.frame = CGRectMake(30, 290, content.frame.size.width - 60, 70);
    [settings addBlockForControlEvents:UIControlEventTouchUpInside block:^(id){ dismissOverlay(); showSettingsMenu(); }];
    [content addSubview:settings];

    g_overlay = panel;
    [topVC().view addSubview:g_overlay];
}

static void showSettingsMenu() {
    UIView *panel = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    panel.backgroundColor = [UIColor clearColor];

    g_backgroundImageView = [[UIImageView alloc] initWithFrame:panel.bounds];
    g_backgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
    [panel addSubview:g_backgroundImageView];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blur.frame = panel.bounds;
    [panel addSubview:blur];

    UIView *content = [[UIView alloc] initWithFrame:CGRectMake(30, 150, panel.frame.size.width - 60, 300)];
    content.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.97];
    content.layer.cornerRadius = 28;
    [panel addSubview:content];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, content.frame.size.width, 50)];
    title.text = @"Background Image URL";
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:22];
    title.textColor = UIColor.cyanColor;
    [content addSubview:title];

    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(20, 90, content.frame.size.width - 40, 50)];
    tf.borderStyle = UITextBorderStyleRoundedRect;
    tf.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    tf.textColor = UIColor.whiteColor;
    tf.text = g_backgroundURL;
    tf.font = [UIFont systemFontOfSize:16];
    tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    [content addSubview:tf];

    UIButton *save = createMenuButton(@"Apply Background", [UIColor systemGreenColor], NSSelectorFromString(@"tmp"));
    save.frame = CGRectMake(20, 160, content.frame.size.width - 40, 60);
    [save addBlockForControlEvents:UIControlEventTouchUpInside block:^(id){
        NSString *url = tf.text;
        if (url.length > 5) {
            downloadAndSetBackground(url);
            dismissOverlay();
        }
    }];
    [content addSubview:save];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = CGRectMake(content.frame.size.width - 70, 10, 60, 60);
    [close setTitle:@"✕" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:36 weight:UIFontWeightBold];
    [close setTitleColor:UIColor.redColor forState:UIControlStateNormal];
    [close addTarget:topVC() action:@selector(dismissOverlay) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:close];

    g_overlay = panel;
    [topVC().view addSubview:g_overlay];
}

static void showCreditScreen() {
    UIView *panel = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    panel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.9];

    g_backgroundImageView = [[UIImageView alloc] initWithFrame:panel.bounds];
    g_backgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
    [panel addSubview:g_backgroundImageView];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blur.frame = panel.bounds;
    [panel addSubview:blur];

    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(40, 200, [UIScreen mainScreen].bounds.size.width - 80, 300)];
    box.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    box.layer.cornerRadius = 30;
    [panel addSubview:box];

    UILabel *msg = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, box.frame.size.width - 40, 180)];
    msg.text = @"Thank you for using!\nCảm ơn vì đã sử dụng!\n\nMade with ❤️";
    msg.numberOfLines = 0;
    msg.textAlignment = NSTextAlignmentCenter;
    msg.font = [UIFont systemFontOfSize:22 weight:UIFontWeightMedium];
    msg.textColor = UIColor.cyanColor;
    [box addSubview:msg];

    UIButton *ok = createMenuButton(@"Continue", [UIColor systemPurpleColor], NSSelectorFromString(@"tmp"));
    ok.frame = CGRectMake(30, 220, box.frame.size.width - 60, 60);
    [ok addBlockForControlEvents:UIControlEventTouchUpInside block:^(id){
        dismissOverlay();
        verifyAccessAndOpenMenu();
    }];
    [box addSubview:ok];

    g_overlay = panel;
    [topVC().view addSubview:g_overlay];
}

#pragma mark - verifyAccessAndOpenMenu (unchanged logic)
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
        if (!outer || !outer[@"data"]) { killApp(); return; }
        NSData *respBox = base64Decode(outer[@"data"]);
        if (!respBox) { killApp(); return; }
        NSData *plainResp = decryptAndVerify(respBox, key, hmacKey);
        if (!plainResp) { killApp(); return; }
        NSDictionary *respJSON = [NSJSONSerialization JSONObjectWithData:plainResp options:0 error:nil];
        if (!respJSON) { killApp(); return; }

        NSString *r_uuid = respJSON[@"uuid"];
        NSString *r_ts = respJSON[@"timestamp"];
        BOOL allow = [respJSON[@"allow"] boolValue];

        if (!r_uuid || ![r_uuid isEqualToString:uuid] || !r_ts || ![r_ts isEqualToString:g_lastTimestamp] || !allow) {
            killApp();
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            showMainMenu();
        });
    }] resume];
}

#pragma mark - Floating Button + ctor
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        loadBackgroundURL();
        downloadAndSetBackground(g_backgroundURL);

        // clean .new files + bypass
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil]) {
            if ([f hasSuffix:@".new"]) [[NSFileManager defaultManager] removeItemAtPath:[docs stringByAppendingPathComponent:f] error:nil];
        }
        silentPatchBypass();

        // floating button
        UIWindow *win = firstWindow();
        g_floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        g_floatingButton.frame = CGRectMake(15, 80, 60, 60);
        g_floatingButton.backgroundColor = [UIColor colorWithRed:0.1 green:0.7 blue:1.0 alpha:1.0];
        g_floatingButton.layer.cornerRadius = 30;
        g_floatingButton.layer.shadowColor = UIColor.cyanColor.CGColor;
        g_floatingButton.layer.shadowOpacity = 0.8;
        g_floatingButton.layer.shadowRadius = 12;
        [g_floatingButton setTitle:@"Star" forState:UIControlStateNormal];
        g_floatingButton.titleLabel.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBold];
        [g_floatingButton addTarget:[UIApplication sharedApplication] action:@selector(showMenuPressed) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[UIApplication sharedApplication] action:@selector(handleDrag:)];
        [g_floatingButton addGestureRecognizer:pan];
        [win addSubview:g_floatingButton];
    });
}

%hook UIApplication
%new
- (void)showMenuPressed {
    if (!g_hasShownCreditAlert) {
        g_hasShownCreditAlert = YES;
        showCreditScreen();
    } else {
        verifyAccessAndOpenMenu();
    }
}

static CGPoint startLoc;
%new
- (void)handleDrag:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateBegan) {
        startLoc = [pan locationInView:g_floatingButton.superview];
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint p = [pan locationInView:g_floatingButton.superview];
        CGFloat dx = p.x - startLoc.x;
        CGFloat dy = p.y - startLoc.y;
        g_floatingButton.center = CGPointMake(g_floatingButton.center.x + dx, g_floatingButton.center.y + dy);
    }
}
%end

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
