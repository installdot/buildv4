// Tweak.xm - FINAL FULL VERSION (No Crash + Small Button + Permanent Background)
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>

#pragma mark - CONFIG
static NSString * const kHexKey = @"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
static NSString * const kHexHmacKey = @"fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210";
static NSString * const kServerURL = @"https://chillysilly.frfrnocap.men/iost.php";
static BOOL g_hasShownCreditAlert = NO;

#pragma mark - Background Cache (Permanent)
static NSString *g_savedBackgroundURL = nil;
static NSString *g_cachedBackgroundPath = nil;

static NSString* backgroundCachePath() {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"__menu_bg.jpg"];
}

static void downloadAndCacheBackground(NSString *urlString, void(^completion)(BOOL success)) {
    if (!urlString || urlString.length == 0) {
        [[NSFileManager defaultManager] removeItemAtPath:g_cachedBackgroundPath error:nil];
        if (completion) completion(NO);
        return;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        BOOL ok = (data && !err && data.length > 1000 && [data writeToFile:g_cachedBackgroundPath atomically:YES]);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(ok);
        });
    }] resume];
}

static void loadBackgroundImage(void(^completion)(UIImage *img)) {
    g_cachedBackgroundPath = backgroundCachePath();
    UIImage *img = [UIImage imageWithContentsOfFile:g_cachedBackgroundPath];
    completion(img);
}

#pragma mark - Safe Top ViewController
static UIViewController *safeTopVC() {
    UIWindow *keyWindow = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *w in scene.windows) {
                if (w.isKeyWindow) { keyWindow = w; break; }
            }
        }
    }
    if (!keyWindow) keyWindow = [UIApplication sharedApplication].windows.firstObject;
    UIViewController *vc = keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

#pragma mark - Cool Menu (No Crash)
@interface CoolMenuViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIImageView *bgImageView;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, copy) void (^didSelect)(NSInteger index);
@end

@implementation CoolMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.modalPresentationStyle = UIModalPresentationOverCurrentContext;

    // Background Image
    self.bgImageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    self.bgImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.bgImageView.clipsToBounds = YES;
    [self.view addSubview:self.bgImageView];

    // Blur Overlay
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.blurView.frame = self.view.bounds;
    self.blurView.alpha = 0.93;
    [self.view addSubview:self.blurView];

    // Load Background
    loadBackgroundImage(^(UIImage *img) {
        self.bgImageView.image = img;
    });

    // Title
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 45, self.view.bounds.size.width, 50)];
    title.text = self.title ?: @"Menu";
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:28];
    title.textColor = [UIColor cyanColor];
    title.shadowColor = [UIColor blackColor];
    title.shadowOffset = CGSizeMake(0, 2);
    [self.view addSubview:title];

    // X Button
    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = CGRectMake(self.view.bounds.size.width - 80, 35, 60, 60);
    [close setTitle:@"X" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:38];
    [close addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    // Table
    CGFloat margin = 50;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(margin, 110, self.view.bounds.size.width - 2*margin, self.view.bounds.size.height - 190) style:UITableViewStylePlain];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.layer.cornerRadius = 20;
    self.tableView.clipsToBounds = YES;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 58;
    [self.view addSubview:self.tableView];
}

- (void)closeMenu {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.items.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"cell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];
    c.textLabel.text = self.items[ip.row];
    c.textLabel.textColor = [UIColor cyanColor];
    c.textLabel.font = [UIFont boldSystemFontOfSize:19];
    c.textLabel.textAlignment = NSTextAlignmentCenter;
    c.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.88];
    c.layer.cornerRadius = 14;
    c.layer.masksToBounds = YES;
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (self.didSelect) self.didSelect(ip.row);
}
@end

#pragma mark - Patch Functions
static BOOL silentApplyRegexToDomain(NSString *pattern, NSString *replacement) {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSDictionary *domain = [defs persistentDomainForName:bid] ?: @{};
    NSError *err = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:domain format:NSPropertyListXMLFormat_v1_0 options:0 error:&err];
    if (!data) return NO;
    NSString *plist = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    NSString *modified = [re stringByReplacingMatchesInString:plist options:0 range:NSMakeRange(0, plist.length) withTemplate:replacement];
    NSDictionary *newDomain = [NSPropertyListSerialization propertyListWithData:[modified dataUsingEncoding:NSUTF8StringEncoding] options:NSPropertyListMutableContainersAndLeaves format:nil error:nil];
    if (![newDomain isKindOfClass:[NSDictionary class]]) return NO;
    [defs setPersistentDomain:newDomain forName:bid];
    return YES;
}

static void applyPatchWithAlert(NSString *title, NSString *p, NSString *r) {
    BOOL ok = silentApplyRegexToDomain(p, r);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController alertControllerWithTitle:ok?@"Success":@"Failed" message:[NSString stringWithFormat:@"%@ %@", title, ok?@"applied":@"failed"] preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [safeTopVC() presentViewController:a animated:YES completion:nil];
    });
}

static void patchGems() {
    UIAlertController *input = [UIAlertController alertControllerWithTitle:@"Set Gems" message:@"Enter value" preferredStyle:UIAlertControllerStyleAlert];
    [input addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.keyboardType = UIKeyboardTypeNumberPad; tf.placeholder = @"999999"; }];
    [input addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSInteger v = [input.textFields.firstObject.text integerValue] ?: 999999;
        silentApplyRegexToDomain(@"(<key>\\d+_gems</key>\\s*<integer>)\\d+", [NSString stringWithFormat:@"$1%ld", (long)v]);
        silentApplyRegexToDomain(@"(<key>\\d+_last_gems</key>\\s*<integer>)\\d+", [NSString stringWithFormat:@"$1%ld", (long)v]);
        UIAlertController *d = [UIAlertController alertControllerWithTitle:@"Gems Updated" message:[NSString stringWithFormat:@"%ld", (long)v] preferredStyle:UIAlertControllerStyleAlert];
        [d addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [safeTopVC() presentViewController:d animated:YES completion:nil];
    }]];
    [input addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [safeTopVC() presentViewController:input animated:YES completion:nil];
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
        NSString *p = map[k];
        NSString *r = [k isEqual:@"Characters"]||[k isEqual:@"Pets"] ? @"$1True" : [k isEqual:@"Level"] ? @"$18" : [k isEqual:@"Furniture"] ? @"$15" : @"$11";
        silentApplyRegexToDomain(p, r);
    }
    silentApplyRegexToDomain(@"(<key>\\d+_reborn_card</key>\\s*<integer>)\\d+", @"$11");
    silentPatchBypass();
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Patch All" message:@"Applied (excluding Gems)" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [safeTopVC() presentViewController:a animated:YES completion:nil];
    });
}

#pragma mark - File Filters
static NSArray* filteredFiles(NSString *keyword) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *all = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil] ?: @[];
    NSMutableArray *res = [NSMutableArray array];
    for (NSString *f in all)
        if (![f hasSuffix:@".new"] && (!keyword || [f localizedCaseInsensitiveContainsString:keyword]))
            [res addObject:f];
    return res;
}

static void showFileActionMenu(NSString *fileName);

static void showDataSubMenu() {
    CoolMenuViewController *vc = [CoolMenuViewController new];
    vc.title = @"Data Filters";
    vc.items = @[@"Statistic", @"Item", @"Season", @"Weapon", @"All Files", @"Cancel"];
    __weak CoolMenuViewController *weakVC = vc;
    vc.didSelect = ^(NSInteger i) {
        [weakVC dismissViewControllerAnimated:YES completion:nil];
        NSString *key = @[@"Statistic", @"Item", @"Season", @"Weapon", @"", @""][i];
        NSArray *files = filteredFiles(i < 4 ? key : nil);
        if (files.count == 0) {
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"No files" message:@"No matching files" preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [safeTopVC() presentViewController:a animated:YES completion:nil];
            return;
        }
        CoolMenuViewController *list = [CoolMenuViewController new];
        list.title = key.length ? key : @"Documents";
        NSMutableArray *items = [files mutableCopy];
        [items addObject:@"Cancel"];
        list.items = items;
        __weak CoolMenuViewController *weakList = list;
        list.didSelect = ^(NSInteger idx) {
            if (idx == items.count - 1) { [weakList dismissViewControllerAnimated:YES completion:nil]; return; }
            [weakList dismissViewControllerAnimated:YES completion:^{ showFileActionMenu(files[idx]); }];
        };
        [safeTopVC() presentViewController:list animated:YES completion:nil];
    };
    [safeTopVC() presentViewController:vc animated:YES completion:nil];
}

static void showFileActionMenu(NSString *fileName) {
    CoolMenuViewController *vc = [CoolMenuViewController new];
    vc.title = fileName;
    vc.items = @[@"Export", @"Import", @"Delete", @"Cancel"];
    __weak CoolMenuViewController *weakVC = vc;
    vc.didSelect = ^(NSInteger i) {
        [weakVC dismissViewControllerAnimated:YES completion:nil];
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *path = [docs stringByAppendingPathComponent:fileName];
        if (i == 0) {
            NSString *txt = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            if (txt) UIPasteboard.generalPasteboard.string = txt;
            UIAlertController *a = [UIAlertController alertControllerWithTitle:txt?@"Exported":@"Error" message:txt?@"Copied to clipboard":@"Failed" preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [safeTopVC() presentViewController:a animated:YES completion:nil];
        } else if (i == 1) {
            UIAlertController *input = [UIAlertController alertControllerWithTitle:@"Import" message:@"Paste text" preferredStyle:UIAlertControllerStyleAlert];
            [input addTextFieldWithConfigurationHandler:nil];
            [input addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
                NSString *txt = input.textFields.firstObject.text ?: @"";
                BOOL ok = [txt writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
                UIAlertController *d = [UIAlertController alertControllerWithTitle:ok?@"Imported":@"Failed" message:ok?@"Restart game":@"Error" preferredStyle:UIAlertControllerStyleAlert];
                [d addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [safeTopVC() presentViewController:d animated:YES completion:nil];
            }]];
            [input addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [safeTopVC() presentViewController:input animated:YES completion:nil];
        } else if (i == 2) {
            BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            UIAlertController *a = [UIAlertController alertControllerWithTitle:ok?@"Deleted":@"Failed" message:ok?@"File removed":@"Error" preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [safeTopVC() presentViewController:a animated:YES completion:nil];
        }
    };
    [safeTopVC() presentViewController:vc animated:YES completion:nil];
}

static void showSettings() {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Background Image" message:@"Enter image URL" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.text = g_savedBackgroundURL;
        tf.placeholder = @"https://example.com/bg.jpg";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save & Apply" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSString *url = alert.textFields.firstObject.text;
        [[NSUserDefaults standardUserDefaults] setObject:url forKey:@"CoolMenuBGURL"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        g_savedBackgroundURL = url;

        UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"Downloading..." message:nil preferredStyle:UIAlertControllerStyleAlert];
        [safeTopVC() presentViewController:loading animated:YES completion:nil];

        downloadAndCacheBackground(url, ^(BOOL success) {
            [loading dismissViewControllerAnimated:YES completion:^{
                UIAlertController *done = [UIAlertController alertControllerWithTitle:success?@"Success":@"Failed" message:success?@"Background updated!":@"Download failed" preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [safeTopVC() presentViewController:done animated:YES completion:nil];
            }];
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"CoolMenuBGURL"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        g_savedBackgroundURL = nil;
        [[NSFileManager defaultManager] removeItemAtPath:g_cachedBackgroundPath error:nil];
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Cleared" message:@"Back to default" preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [safeTopVC() presentViewController:done animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [safeTopVC() presentViewController:alert animated:YES completion:nil];
}

static void showPlayerMenu() {
    CoolMenuViewController *vc = [CoolMenuViewController new];
    vc.title = @"Player";
    vc.items = @[@"Characters", @"Skins", @"Skills", @"Pets", @"Level", @"Furniture", @"Gems", @"Reborn", @"Patch All", @"Cancel"];
    __weak CoolMenuViewController *weakVC = vc;
    vc.didSelect = ^(NSInteger i) {
        [weakVC dismissViewControllerAnimated:YES completion:nil];
        if (i==0) applyPatchWithAlert(@"Characters", @"(<key>\\d+_c\\d+_unlock.*\\n.*)false", @"$1True");
        else if (i==1) applyPatchWithAlert(@"Skins", @"(<key>\\d+_c\\d+_skin\\d+.*\\n.*>)[+-]?\\d+", @"$11");
        else if (i==2) applyPatchWithAlert(@"Skills", @"(<key>\\d+_c_.*_skill_\\d_unlock.*\\n.*<integer>)\\d", @"$11");
        else if (i==3) applyPatchWithAlert(@"Pets", @"(<key>\\d+_p\\d+_unlock.*\\n.*)false", @"$1True");
        else if (i==4) applyPatchWithAlert(@"Level", @"(<key>\\d+_c\\d+_level+.*\\n.*>)[+-]?\\d+", @"$18");
        else if (i==5) applyPatchWithAlert(@"Furniture", @"(<key>\\d+_furniture+_+.*\\n.*>)[+-]?\\d+", @"$15");
        else if (i==6) patchGems();
        else if (i==7) patchRebornWithAlert();
        else if (i==8) patchAllExcludingGems();
    };
    [safeTopVC() presentViewController:vc animated:YES completion:nil];
}

static void showMainMenu() {
    CoolMenuViewController *vc = [CoolMenuViewController new];
    vc.title = @"Menu";
    vc.items = @[@"Player", @"Data", @"Settings", @"Cancel"];
    __weak CoolMenuViewController *weakVC = vc;
    vc.didSelect = ^(NSInteger i) {
        [weakVC dismissViewControllerAnimated:YES completion:nil];
        if (i==0) showPlayerMenu();
        else if (i==1) showDataSubMenu();
        else if (i==2) showSettings();
    };
    [safeTopVC() presentViewController:vc animated:YES completion:nil];
}

#pragma mark - Crypto & Verify
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
static NSData* base64Decode(NSString *s) { return [[NSData alloc] initWithBase64EncodedString:s options:0]; }

static NSData* encryptPayload(NSData *plain, NSData *key, NSData *hmacKey) {
    uint8_t iv[16]; arc4random_buf(iv, 16);
    NSData *ivData = [NSData dataWithBytes:iv length:16];
    void *buf = malloc(plain.length + kCCBlockSizeAES128);
    size_t out = 0;
    CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key.bytes, 32, ivData.bytes, plain.bytes, plain.length, buf, plain.length + kCCBlockSizeAES128, &out);
    NSData *cipher = [NSData dataWithBytesNoCopy:buf length:out freeWhenDone:YES];
    NSMutableData *hmacInput = [NSMutableData dataWithData:ivData]; [hmacInput appendData:cipher];
    unsigned char hmac[32];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, 32, hmacInput.bytes, hmacInput.length, hmac);
    NSMutableData *box = [NSMutableData dataWithData:ivData]; [box appendData:cipher]; [box appendData:[NSData dataWithBytes:hmac length:32]];
    return box;
}
static NSData* decryptAndVerify(NSData *box, NSData *key, NSData *hmacKey) {
    if (box.length < 48) return nil;
    NSData *iv = [box subdataWithRange:NSMakeRange(0,16)];
    NSData *hmac = [box subdataWithRange:NSMakeRange(box.length-32,32)];
    NSData *cipher = [box subdataWithRange:NSMakeRange(16, box.length-48)];
    NSMutableData *hmacInput = [NSMutableData dataWithData:iv]; [hmacInput appendData:cipher];
    unsigned char calc[32];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, 32, hmacInput.bytes, hmacInput.length, calc);
    if (![[NSData dataWithBytes:calc length:32] isEqualToData:hmac]) return nil;
    void *buf = malloc(cipher.length + kCCBlockSizeAES128);
    size_t out = 0;
    CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key.bytes, 32, iv.bytes, cipher.bytes, cipher.length, buf, cipher.length + kCCBlockSizeAES128, &out);
    return [NSData dataWithBytesNoCopy:buf length:out freeWhenDone:YES];
}

static void verifyAccessAndOpenMenu() {
    NSData *key = dataFromHex(kHexKey);
    NSData *hmacKey = dataFromHex(kHexHmacKey);
    if (!key || key.length != 32 || !hmacKey || hmacKey.length != 32) { exit(0); return; }
    NSString *uuid = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/uuid.txt"];
    NSString *savedUUID = [NSString stringWithContentsOfFile:uuid encoding:NSUTF8StringEncoding error:nil];
    if (!savedUUID || savedUUID.length == 0) {
        savedUUID = [[NSUUID UUID] UUIDString];
        [savedUUID writeToFile:uuid atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    NSString *ts = [NSString stringWithFormat:@"%lld", (long long)[[NSDate date] timeIntervalSince1970]];
    NSDictionary *payload = @{@"uuid": savedUUID, @"timestamp": ts, @"encrypted": @"yes"};
    NSData *box = encryptPayload([NSJSONSerialization dataWithJSONObject:payload options:0 error:nil], key, hmacKey);
    NSString *b64 = base64Encode(box);
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kServerURL]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 10.0;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"data": b64} options:0 error:nil];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err){
        if (err || !data) { exit(0); return; }
        NSDictionary *outer = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSData *respBox = base64Decode(outer[@"data"]);
        NSData *plain = decryptAndVerify(respBox, key, hmacKey);
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:plain options:0 error:nil];
        if (![json[@"uuid"] isEqual:savedUUID] || ![json[@"timestamp"] isEqual:ts] || ![json[@"allow"] boolValue]) {
            exit(0);
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            showMainMenu();
        });
    }] resume];
}

#pragma mark - Floating Button (Small & Clean)
static UIButton *floatingButton = nil;

%ctor {
    g_savedBackgroundURL = [[NSUserDefaults standardUserDefaults] stringForKey:@"CoolMenuBGURL"];
    g_cachedBackgroundPath = backgroundCachePath();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        silentPatchBypass();
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil])
            if ([f hasSuffix:@".new"])
                [[NSFileManager defaultManager] removeItemAtPath:[docs stringByAppendingPathComponent:f] error:nil];

        UIWindow *win = safeTopVC().view.window ?: [UIApplication sharedApplication].windows.firstObject;
        floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        floatingButton.frame = CGRectMake(15, 70, 44, 44);
        floatingButton.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.8];
        floatingButton.layer.cornerRadius = 22;
        floatingButton.layer.borderWidth = 1.5;
        floatingButton.layer.borderColor = [UIColor cyanColor].CGColor;
        [floatingButton setTitle:@"M" forState:UIControlStateNormal];
        floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
        [floatingButton addTarget:%c(UIApplication) action:@selector(showMenuPressed) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:%c(UIApplication) action:@selector(handlePan:)];
        [floatingButton addGestureRecognizer:pan];
        [win addSubview:floatingButton];
    });
}

%hook UIApplication
%new - (void)showMenuPressed {
    if (!g_hasShownCreditAlert) {
        g_hasShownCreditAlert = YES;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Info" message:@"Thank you for using!\nCảm ơn vì đã sử dụng!" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *){ verifyAccessAndOpenMenu(); }]];
        [safeTopVC() presentViewController:a animated:YES completion:nil];
    } else {
        verifyAccessAndOpenMenu();
    }
}
%new - (void)handlePan:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    if (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [g translationInView:v.superview];
        v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
        [g setTranslation:CGPointZero inView:v.superview];
    }
}
%end
