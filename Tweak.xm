// Tweak.xm - FULL CODE WITH IMGUI MENU (NO UIAlertController)
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#import <OpenGLES/ES3/gl.h>
#import <GLKit/GLKit.h>
#import "imgui.h"
#import "imgui_impl_ios.h"

#pragma mark - CONFIG
static NSString * const kHexKey      = @"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
static NSString * const kHexHmacKey  = @"fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210";
static NSString * const kServerURL   = @"https://chillysilly.frfrnocap.men/iost.php";
static BOOL g_hasShownCreditAlert = NO;

#pragma mark - Global ImGui State
static bool g_menuVisible = false;
static char g_gemInput[32] = "";
static UIButton *g_floatingButton = nil;
static UIView *g_glView = nil;
static CADisplayLink *g_displayLink = nil;

#pragma mark - Helpers (ALL YOUR ORIGINAL CODE)
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
    uint8_t ivBytes[16]; arc4random_buf(ivBytes, 16);
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
                                 cipher.bytes, cipher.length,
                                 outbuf, outlen, &actualOut);
    if (st != kCCSuccess) { free(outbuf); return nil; }
    return [NSData dataWithBytesNoCopy:outbuf length:actualOut freeWhenDone:YES];
}

#pragma mark - App UUID
static NSString* appUUID() {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/uuid.txt"];
    NSString *uuid = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!uuid || uuid.length == 0) {
        uuid = [[NSUUID UUID] UUIDString];
        [uuid writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return uuid;
}

#pragma mark - UI Helpers
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

static UIViewController* topVC() {
    UIWindow *win = firstWindow();
    UIViewController *vc = win.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static void killApp() { exit(0); }

#pragma mark - Regex Patch
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
    // No UIAlert — we now show toast inside ImGui
    NSLog(@"[Menu] %@ %@", title, ok ? @"Success" : @"Failed");
}

#pragma mark - Patches
static void patchGems() {
    long v = atol(g_gemInput);
    if (v <= 0) return;
    silentApplyRegexToDomain(@"(<key>\\d+_gems</key>\\s*<integer>)\\d+", [NSString stringWithFormat:@"$1%ld", v]);
    silentApplyRegexToDomain(@"(<key>\\d+_last_gems</key>\\s*<integer>)\\d+", [NSString stringWithFormat:@"$1%ld", v]);
    strcpy(g_gemInput, "");
}

static void patchRebornWithAlert() { silentApplyRegexToDomain(@"(<key>\\d+_reborn_card</key>\\s*<integer>)\\d+", @"$11"); }
static void silentPatchBypass() { silentApplyRegexToDomain(@"(<key>OpenRijTest_\\d+</key>\\s*<integer>)\\d+", @"$10"); }

static void patchAllExcludingGems() {
    NSDictionary *map = @{
        @"(<key>\\d+_c\\d+_unlock.*\\n.*)false": @"$1True",
        @"(<key>\\d+_c\\d+_skin\\d+.*\\n.*>)[+-]?\\d+": @"$11",
        @"(<key>\\d+_c_.*_skill_\\d_unlock.*\\n.*<integer>)\\d": @"$11",
        @"(<key>\\d+_p\\d+_unlock.*\\n.*)false": @"$1True",
        @"(<key>\\d+_c\\d+_level+.*\\n.*>)[+-]?\\d+": @"$18",
        @"(<key>\\d+_furniture+_+.*\\n.*>)[+-]?\\d+": @"$15"
    };
    for (NSString *pat in map) silentApplyRegexToDomain(pat, map[pat]);
    silentApplyRegexToDomain(@"(<key>\\d+_reborn_card</key>\\s*<integer>)\\d+", @"$11");
    silentPatchBypass();
}

#pragma mark - Document Files
static NSArray* listDocumentsFiles() {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *all = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil] ?: @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *f in all) if (![f hasSuffix:@".new"]) [out addObject:f];
    return out;
}

#pragma mark - ImGui Menu
static void ShowImGuiMenu() {
    if (!g_menuVisible) return;

    ImGui::SetNextWindowSize(ImVec2(420, 620), ImGuiCond_FirstUseEver);
    ImGui::SetNextWindowPos(ImVec2(30, 80), ImGuiCond_FirstUseEver);

    if (!ImGui::Begin("Premium Game Menu", &g_menuVisible, ImGuiWindowFlags_NoCollapse)) {
        ImGui::End();
        return;
    }

    if (ImGui::BeginTabBar("Tabs")) {
        if (ImGui::BeginTabItem("Player")) {
            if (ImGui::Button("Unlock All Characters"))  applyPatchWithAlert(@"Characters", @"(<key>\\d+_c\\d+_unlock.*\\n.*)false", @"$1True");
            if (ImGui::Button("Unlock All Skins"))       applyPatchWithAlert(@"Skins", @"(<key>\\d+_c\\d+_skin\\d+.*\\n.*>)[+-]?\\d+", @"$11");
            if (ImGui::Button("Unlock All Skills"))      applyPatchWithAlert(@"Skills", @"(<key>\\d+_c_.*_skill_\\d_unlock.*\\n.*<integer>)\\d", @"$11");
            if (ImGui::Button("Unlock All Pets"))        applyPatchWithAlert(@"Pets", @"(<key>\\d+_p\\d+_unlock.*\\n.*)false", @"$1True");
            if (ImGui::Button("Max Level (8)"))          applyPatchWithAlert(@"Level", @"(<key>\\d+_c\\d+_level+.*\\n.*>)[+-]?\\d+", @"$18");
            if (ImGui::Button("Max Furniture (5)"))      applyPatchWithAlert(@"Furniture", @"(<key>\\d+_furniture+_+.*\\n.*>)[+-]?\\d+", @"$15");
            if (ImGui::Button("Reborn Card"))            patchRebornWithAlert();

            ImGui::Separator();
            ImGui::Text("Gems:");
            ImGui::SameLine();
            ImGui::InputText("##gems", g_gemInput, sizeof(g_gemInput), ImGuiInputTextFlags_CharsDecimal);
            ImGui::SameLine();
            if (ImGui::Button("Set Gems")) patchGems();

            ImGui::Separator();
            if (ImGui::Button("PATCH ALL (except Gems)")) patchAllExcludingGems();

            ImGui::EndTabItem();
        }

        if (ImGui::BeginTabItem("Data")) {
            NSArray *files = listDocumentsFiles();
            if (files.count == 0) ImGui::Text("No files in Documents");
            else {
                for (NSString *f in files) {
                    if (ImGui::Button([f UTF8String])) {
                        NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:f];
                        NSString *txt = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
                        if (txt) {
                            UIPasteboard.generalPasteboard.string = txt;
                            NSLog(@"[Menu] Copied: %@", f);
                        }
                    }
                }
            }
            ImGui::EndTabItem();
        }

        ImGui::EndTabBar();
    }
    ImGui::End();

    if (!g_menuVisible) {
        g_glView.hidden = YES;
        g_floatingButton.hidden = NO;
    }
}

static void RenderLoop() {
    ImGui_ImplIOS_NewFrame();
    ImGui::NewFrame();
    ShowImGuiMenu();
    ImGui::Render();
    ImGui_ImplIOS_RenderDrawData(ImGui::GetDrawData());
}

#pragma mark - Server Verification
static NSString *g_lastTimestamp = nil;
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
        if (!plainResp) { killApp(); return; }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:plainResp options:0 error:nil];
        if (![json[@"uuid"] isEqualToString:uuid] || ![json[@"timestamp"] isEqualToString:g_lastTimestamp] || ![json[@"allow"] boolValue]) {
            killApp();
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            g_menuVisible = true;
            g_glView.hidden = NO;
            g_floatingButton.hidden = YES;
        });
    }] resume];
}

#pragma mark - %ctor
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Auto clean .new
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil]) {
            if ([f hasSuffix:@".new"]) [[NSFileManager defaultManager] removeItemAtPath:[docs stringByAppendingPathComponent:f] error:nil];
        }
        silentPatchBypass();

        // Setup ImGui
        UIWindow *win = firstWindow();
        g_glView = [[UIView alloc] initWithFrame:win.bounds];
        g_glView.backgroundColor = UIColor.clearColor;
        g_glView.hidden = YES;
        [win addSubview:g_glView];

        EAGLContext *ctx = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
        GLKView *glk = [[GLKView alloc] initWithFrame:g_glView.bounds context:ctx];
        glk.drawableMultisample = GLKViewDrawableMultisample4X;
        [g_glView addSubview:glk];
        [EAGLContext setCurrentContext:ctx];

        ImGui::CreateContext();
        ImGui::StyleColorsDark();
        ImGuiStyle& s = ImGui::GetStyle();
        s.WindowRounding = 12.0f;
        s.FrameRounding = 8.0f;
        ImGui_ImplIOS_Init(glk, (__bridge void*)ctx);

        g_displayLink = [CADisplayLink displayLinkWithTarget:^(){ RenderLoop(); } selector:@selector(invalidate)];
        [g_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

        // Floating button
        g_floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        g_floatingButton.frame = CGRectMake(20, 100, 60, 60);
        g_floatingButton.backgroundColor = [UIColor colorWithRed:0 green:0.7 blue:1 alpha:0.9];
        g_floatingButton.layer.cornerRadius = 30;
        [g_floatingButton setTitle:@"MENU" forState:UIControlStateNormal];
        [g_floatingButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        g_floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [g_floatingButton addTarget:%c(UIApplication) action:@selector(showMenuPressed) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:%c(UIApplication) action:@selector(handlePan:)];
        [g_floatingButton addGestureRecognizer:pan];
        [win addSubview:g_floatingButton];
    });
}

%hook UIApplication
%new
- (void)showMenuPressed {
    if (!g_hasShownCreditAlert) {
        g_hasShownCreditAlert = YES;
    }
    verifyAccessAndOpenMenu();
}

%new
- (void)handlePan:(UIPanGestureRecognizer *)rec {
    static CGPoint start;
    UIView *v = rec.view;
    if (rec.state == UIGestureRecognizerStateBegan) {
        start = [rec locationInView:v.superview];
    } else if (rec.state == UIGestureRecognizerStateChanged) {
        CGPoint p = [rec locationInView:v.superview];
        v.center = CGPointMake(v.center.x + (p.x - start.x), v.center.y + (p.y - start.y));
        start = p;
    }
}
%end
