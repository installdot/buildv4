// Tweak.xm
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>

#pragma mark - CONFIG
static NSString * const kHexKey       = @"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
static NSString * const kHexHmacKey   = @"fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210";
static NSString * const kServerURL    = @"https://chillysilly.frfrnocap.men/iost2.php";
static BOOL g_hasShownCreditAlert = NO;

#pragma mark - Helpers
static NSData* dataFromHex(NSString *hex) {
    NSMutableData *d = [NSMutableData data];
    for (NSUInteger i = 0; i + 2 <= hex.length; i += 2) {
        NSRange r = NSMakeRange(i, 2);
        unsigned int byte = 0;
        [[NSScanner scannerWithString:[hex substringWithRange:r]] scanHexInt:&byte];
        [d appendBytes:&byte length:1];
    }
    return d;
}

static NSString* base64Encode(NSData *d) { return [d base64EncodedStringWithOptions:0]; }
static NSData*   base64Decode(NSString *s) { return [[NSData alloc] initWithBase64EncodedString:s options:0]; }

#pragma mark - AES-256-CBC + HMAC-SHA256
static NSData* encryptPayload(NSData *plain, NSData *key, NSData *hmacKey) {
    uint8_t iv[16]; arc4random_buf(iv, 16);
    NSData *ivData = [NSData dataWithBytes:iv length:16];

    size_t bufSize = plain.length + kCCBlockSizeAES128;
    void *buffer = malloc(bufSize);
    size_t numBytesEncrypted = 0;
    CCCryptorStatus status = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                     key.bytes, key.length, ivData.bytes,
                                     plain.bytes, plain.length,
                                     buffer, bufSize, &numBytesEncrypted);
    if (status != kCCSuccess) { free(buffer); return nil; }
    NSData *cipher = [NSData dataWithBytesNoCopy:buffer length:numBytesEncrypted freeWhenDone:YES];

    NSMutableData *forHmac = [NSMutableData dataWithData:ivData];
    [forHmac appendData:cipher];
    unsigned char hmac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, hmacKey.length, forHmac.bytes, forHmac.length, hmac);
    NSData *hmacData = [NSData dataWithBytes:hmac length:CC_SHA256_DIGEST_LENGTH];

    NSMutableData *box = [NSMutableData data];
    [box appendData:ivData];
    [box appendData:cipher];
    [box appendData:hmacData];
    return box;
}

static NSData* decryptAndVerify(NSData *box, NSData *key, NSData *hmacKey) {
    if (box.length < 48) return nil;
    NSData *iv = [box subdataWithRange:NSMakeRange(0, 16)];
    NSData *hmacReceived = [box subdataWithRange:NSMakeRange(box.length - 32, 32)];
    NSData *cipher = [box subdataWithRange:NSMakeRange(16, box.length - 48)];

    NSMutableData *forHmac = [NSMutableData dataWithData:iv];
    [forHmac appendData:cipher];
    unsigned char hmacCalc[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, hmacKey.length, forHmac.bytes, forHmac.length, hmacCalc);
    if (memcmp(hmacCalc, hmacReceived.bytes, 32) != 0) return nil;

    size_t bufSize = cipher.length + kCCBlockSizeAES128;
    void *buffer = malloc(bufSize);
    size_t numBytesDecrypted = 0;
    CCCryptorStatus status = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                     key.bytes, key.length, iv.bytes,
                                     cipher.bytes, cipher.length,
                                     buffer, bufSize, &numBytesDecrypted);
    if (status != kCCSuccess) { free(buffer); return nil; }
    return [NSData dataWithBytesNoCopy:buffer length:numBytesDecrypted freeWhenDone:YES];
}

#pragma mark - UUID
static NSString* appUUID() {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/uuid.txt"];
    NSString *uuid = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!uuid.length) {
        uuid = [[NSUUID UUID] UUIDString];
        [uuid writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return uuid;
}

#pragma mark - UI Helpers
static UIWindow* keyWindow() {
    for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes)
        if (scene.activationState == UISceneActivationStateForegroundActive)
            for (UIWindow *w in scene.windows)
                if (w.isKeyWindow) return w;
    return UIApplication.sharedApplication.windows.firstObject;
}
static UIViewController* topVC() {
    UIViewController *vc = keyWindow().rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

#pragma mark - Regex Patch (NSUserDefaults)
static void applyRegex(NSString *pattern, NSString *replacement) {
    NSString *bid = NSBundle.mainBundle.bundleIdentifier;
    NSUserDefaults *defs = NSUserDefaults.standardUserDefaults;
    NSDictionary *domain = [defs persistentDomainForName:bid] ?: @{};
    NSString *xml = [[NSString alloc] initWithData:[NSPropertyListSerialization dataWithPropertyList:domain format:NSPropertyListXMLFormat_v1_0 options:0 error:nil] encoding:NSUTF8StringEncoding];
    if (!xml) return;

    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    NSString *modified = [re stringByReplacingMatchesInString:xml options:0 range:NSMakeRange(0, xml.length) withTemplate:replacement];

    NSData *newData = [modified dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *newDomain = [NSPropertyListSerialization propertyListWithData:newData options:NSPropertyListMutableContainersAndLeaves format:nil error:nil];
    if ([newDomain isKindOfClass:NSDictionary.class]) {
        [defs setPersistentDomain:newDomain forName:bid];
        [defs synchronize];
    }
}

#pragma mark - Patches
static void patchCharacters() { applyRegex(@"(<key>\\d+_c\\d+_unlock[^<]*</key>\\s*<[^>]*>)false", @"$1true"); }
static void patchSkins()      { applyRegex(@"(<key>\\d+_c\\d+_skin\\d+[^<]*</key>\\s*<[^>]*>)[-+]?\\d+", @"$11"); }
static void patchPets()       { applyRegex(@"(<key>\\d+_p\\d+_unlock[^<]*</key>\\s*<[^>]*>)false", @"$1true"); }

static void patchGems() {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Set Gems" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.placeholder = @"999999";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSInteger value = [alert.textFields.firstObject.text integerValue];
        if (value < 0) value = 999999;
        NSString *v = @(value).stringValue;
        applyRegex(@"(<key>\\d+_gems</key>\\s*<integer>)\\d+", [NSString stringWithFormat:@"$1%@", v]);
        applyRegex(@"(<key>\\d+_last_gems</key>\\s*<integer>)\\d+", [NSString stringWithFormat:@"$1%@", v]);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Menu
static void showMenu() {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Menu" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [menu addAction:[UIAlertAction actionWithTitle:@"Characters" style:UIAlertActionStyleDefault handler:^(id){ patchCharacters(); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Skins"       style:UIAlertActionStyleDefault handler:^(id){ patchSkins(); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Pets"        style:UIAlertActionStyleDefault handler:^(id){ patchPets(); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Gems"        style:UIAlertActionStyleDefault handler:^(id){ patchGems(); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel"      style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:menu animated:YES completion:nil];
}

#pragma mark - Access Check
static void checkAccessAndProceed() {
    NSString *uuid = appUUID();
    NSData *key = dataFromHex(kHexKey);
    NSData *hmacKey = dataFromHex(kHexHmacKey);

    NSDictionary *payload = @{@"uuid": uuid, @"timestamp": @((long long)[NSDate.date timeIntervalSince1970]), @"encrypted": @"yes"};
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSData *box = encryptPayload(json, key, hmacKey);
    NSString *b64 = base64Encode(box);

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kServerURL]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 10;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"data": b64} options:0 error:nil];

    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!data || err) {
            dispatch_async(dispatch_get_main_queue(), ^{ [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://chillysilly.frfrnocap.men/iost2.php?uuid=%@", uuid]] options:@{} completionHandler:nil]; });
            return;
        }

        NSDictionary *outer = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSData *respBox = base64Decode(outer[@"data"]);
        NSData *plain = decryptAndVerify(respBox, key, hmacKey);
        NSDictionary *resp = [NSJSONSerialization JSONObjectWithData:plain options:0 error:nil];

        BOOL allowed = [resp[@"allow"] boolValue];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (allowed) {
                showMenu();
            } else {
                NSString *link = [NSString stringWithFormat:@"https://chillysilly.frfrnocap.men/iost2.php?uuid=%@", uuid];
                [UIApplication.sharedApplication openURL:[NSURL URLWithString:link] options:@{} completionHandler:nil];
            }
        });
    }] resume];
}

#pragma mark - Floating Button
static UIButton *g_button = nil;

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_button = [UIButton buttonWithType:UIButtonTypeCustom];
        g_button.frame = CGRectMake(20, 80, 50, 50);
        g_button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        g_button.layer.cornerRadius = 25;
        [g_button setTitle:@"M" forState:UIControlStateNormal];
        g_button.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        [g_button addTarget:UIApplication.sharedApplication action:@selector(btnPressed) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:UIApplication.sharedApplication action:@selector(dragButton:)];
        [g_button addGestureRecognizer:pan];

        [keyWindow() addSubview:g_button];
    });
}

%hook UIApplication
%new
- (void)btnPressed {
    if (!g_hasShownCreditAlert) {
        g_hasShownCreditAlert = YES;
        UIAlertController *c = [UIAlertController alertControllerWithTitle:@"Info"
                                 message:@"This dylib is made by mochiteyvat(Discord).\nThis is free dylib, if you bought this then u likely got scammed.\nNếu bạn mua thì bạn đã bị dắt như bò!"
                                 preferredStyle:UIAlertControllerStyleAlert];
        [c addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(id){
            checkAccessAndProceed();
        }]];
        [topVC() presentViewController:c animated:YES completion:nil];
    } else {
        checkAccessAndProceed();
    }
}

%new
- (void)dragButton:(UIPanGestureRecognizer *)pan {
    UIView *v = pan.view;
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [pan translationInView:v.superview];
        v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
        [pan setTranslation:CGPointZero inView:v.superview];
    }
}
%end
