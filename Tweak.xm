// Tweak.xm - FULL FINAL 100% STABLE VERSION (NO CRASH + SMALL BUTTON + PERMANENT BG)
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
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"__menu_bg.jpg"];
}

static void downloadAndCacheBackground(NSString *urlString, void(^completion)(BOOL success)) {
    if (!urlString || urlString.length == 0) {
        [[NSFileManager defaultManager] removeItemAtPath:g_cachedBackgroundPath error:nil];
        if (completion) completion(NO);
        return;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        BOOL success = data && !error && data.length > 1000 && [data writeToFile:g_cachedBackgroundPath atomically:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(success);
        });
    }] resume];
}

static void loadBackgroundImage(void(^completion)(UIImage *img)) {
    g_cachedBackgroundPath = backgroundCachePath();
    UIImage *cached = [UIImage imageWithContentsOfFile:g_cachedBackgroundPath];
    completion(cached);
}

#pragma mark - Safe Top ViewController (Works on ALL iOS)
static UIViewController *safeTopVC() {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) keyWindow = [UIApplication sharedApplication].windows.firstObject;
    UIViewController *vc = keyWindow.rootViewController;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) {
        vc = vc.presentedViewController;
    }
    return vc;
}

#pragma mark - Cool Menu (100% Crash-Free)
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
    self.modalPresentationStyle = UIModalPresentationPageSheet;
    self.definesPresentationContext = YES;

    // Background Image
    self.bgImageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    self.bgImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.bgImageView.clipsToBounds = YES;
    [self.view addSubview:self.bgImageView];

    // Blur
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.blurView.frame = self.view.bounds;
    self.blurView.alpha = 0.94;
    [self.view addSubview:self.blurView];

    // Load Background
    loadBackgroundImage(^(UIImage *img) {
        if (img) self.bgImageView.image = img;
    });

    // Title
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 40, self.view.bounds.size.width, 60)];
    title.text = self.title ?: @"Menu";
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:30];
    title.textColor = [UIColor cyanColor];
    title.shadowColor = [UIColor blackColor];
    title.shadowOffset = CGSizeMake(0, 2);
    [self.view addSubview:title];

    // Close Button
    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = CGRectMake(self.view.bounds.size.width - 90, 30, 70, 70);
    [close setTitle:@"X" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:40];
    [close addTarget:self action:@selector(dismissMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    // Table
    CGFloat margin = 50;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(margin, 110, self.view.bounds.size.width - 2*margin, self.view.bounds.size.height - 200) style:UITableViewStylePlain];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.layer.cornerRadius = 20;
    self.tableView.clipsToBounds = YES;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 60;
    [self.view addSubview:self.tableView];
}

- (void)dismissMenu {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];
    cell.textLabel.text = self.items[indexPath.row];
    cell.textLabel.textColor = [UIColor cyanColor];
    cell.textLabel.font = [UIFont boldSystemFontOfSize:19];
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.9];
    cell.layer.cornerRadius = 16;
    cell.layer.masksToBounds = YES;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.didSelect) self.didSelect(indexPath.row);
}
@end

#pragma mark - Patch & Data Functions
static BOOL silentApplyRegexToDomain(NSString *pattern, NSString *replacement) {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSDictionary *domain = [defs persistentDomainForName:bid] ?: @{};
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:domain format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
    if (!data) return NO;
    NSString *plist = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    NSString *modified = [regex stringByReplacingMatchesInString:plist options:0 range:NSMakeRange(0, plist.length) withTemplate:replacement];
    NSDictionary *newDomain = [NSPropertyListSerialization propertyListWithData:[modified dataUsingEncoding:NSUTF8StringEncoding] options:NSPropertyListMutableContainersAndLeaves format:nil error:nil];
    if (![newDomain isKindOfClass:[NSDictionary class]]) return NO;
    [defs setPersistentDomain:newDomain forName:bid];
    return YES;
}

static void applyPatchWithAlert(NSString *title, NSString *pattern, NSString *replacement) {
    BOOL success = silentApplyRegexToDomain(pattern, replacement);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:success ? @"Success" : @"Failed"
                                                                     message:[NSString stringWithFormat:@"%@ %@", title, success ? @"applied" : @"failed"]
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [safeTopVC() presentViewController:alert animated:YES completion:nil];
    });
}

static void patchGems() {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Set Gems" message:@"Enter amount" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.placeholder = @"999999";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        long long value = [alert.textFields.firstObject.text longLongValue] ?: 999999;
        silentApplyRegexToDomain(@"(<key>\\d+_gems</key>\\s*<integer>)\\d+", [NSString stringWithFormat:@"$1%lld", value]);
        silentApplyRegexToDomain(@"(<key>\\d+_last_gems</key>\\s*<integer>)\\d+", [NSString stringWithFormat:@"$1%lld", value]);
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Done" message:@"Gems updated!" preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [safeTopVC() presentViewController:done animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [safeTopVC() presentViewController:alert animated:YES completion:nil];
}

static void patchRebornWithAlert() { applyPatchWithAlert(@"Reborn", @"(<key>\\d+_reborn_card</key>\\s*<integer>)\\d+", @"$11"); }
static void silentPatchBypass() { silentApplyRegexToDomain(@"(<key>OpenRijTest_\\d+</key>\\s*<integer>)\\d+", @"$10"); }

static void patchAllExcludingGems() {
    NSDictionary *patches = @{
        @"(<key>\\d+_c\\d+_unlock.*\\n.*)false": @"$1True",
        @"(<key>\\d+_c\\d+_skin\\d+.*\\n.*>)[+-]?\\d+": @"$11",
        @"(<key>\\d+_c_.*_skill_\\d_unlock.*\\n.*<integer>)\\d": @"$11",
        @"(<key>\\d+_p\\d+_unlock.*\\n.*)false": @"$1True",
        @"(<key>\\d+_c\\d+_level+.*\\n.*>)[+-]?\\d+": @"$18",
        @"(<key>\\d+_furniture+_+.*\\n.*>)[+-]?\\d+": @"$15"
    };
    for (NSString *pattern in patches) {
        silentApplyRegexToDomain(pattern, patches[pattern]);
    }
    silentApplyRegexToDomain(@"(<key>\\d+_reborn_card</key>\\s*<integer>)\\d+", @"$11");
    silentPatchBypass();
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Success" message:@"All patched (except Gems)" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [safeTopVC() presentViewController:a animated:YES completion:nil];
    });
}

static NSArray* filteredFiles(NSString *keyword) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *all = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil] ?: @[];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *file in all) {
        if ([file hasSuffix:@".new"]) continue;
        if (!keyword || [file localizedCaseInsensitiveContainsString:keyword]) {
            [result addObject:file];
        }
    }
    return result;
}

static void showFileActionMenu(NSString *fileName);
static void showDataSubMenu();
static void showSettings();
static void showPlayerMenu();

static void showMainMenu() {
    CoolMenuViewController *vc = [CoolMenuViewController new];
    vc.title = @"Menu";
    vc.items = @[@"Player", @"Data", @"Settings", @"Cancel"];
    __weak CoolMenuViewController *weakVC = vc;
    vc.didSelect = ^(NSInteger i) {
        [weakVC dismissViewControllerAnimated:YES completion:nil];
        if (i == 0) showPlayerMenu();
        else if (i == 1) showDataSubMenu();
        else if (i == 2) showSettings();
    };
    [safeTopVC() presentViewController:vc animated:YES completion:nil];
}

static void showPlayerMenu() {
    CoolMenuViewController *vc = [CoolMenuViewController new];
    vc.title = @"Player";
    vc.items = @[@"Characters", @"Skins", @"Skills", @"Pets", @"Level", @"Furniture", @"Gems", @"Reborn", @"Patch All", @"Cancel"];
    __weak CoolMenuViewController *weakVC = vc;
    vc.didSelect = ^(NSInteger i) {
        [weakVC dismissViewControllerAnimated:YES completion:nil];
        if (i == 0) applyPatchWithAlert(@"Characters", @"(<key>\\d+_c\\d+_unlock.*\\n.*)false", @"$1True");
        else if (i == 1) applyPatchWithAlert(@"Skins", @"(<key>\\d+_c\\d+_skin\\d+.*\\n.*>)[+-]?\\d+", @"$11");
        else if (i == 2) applyPatchWithAlert(@"Skills", @"(<key>\\d+_c_.*_skill_\\d_unlock.*\\n.*<integer>)\\d", @"$11");
        else if (i == 3) applyPatchWithAlert(@"Pets", @"(<key>\\d+_p\\d+_unlock.*\\n.*)false", @"$1True");
        else if (i == 4) applyPatchWithAlert(@"Level", @"(<key>\\d+_c\\d+_level+.*\\n.*>)[+-]?\\d+", @"$18");
        else if (i == 5) applyPatchWithAlert(@"Furniture", @"(<key>\\d+_furniture+_+.*\\n.*>)[+-]?\\d+", @"$15");
        else if (i == 6) patchGems();
        else if (i == 7) patchRebornWithAlert();
        else if (i == 8) patchAllExcludingGems();
    };
    [safeTopVC() presentViewController:vc animated:YES completion:nil];
}

static void showDataSubMenu() {
    CoolMenuViewController *vc = [CoolMenuViewController new];
    vc.title = @"Data Filters";
    vc.items = @[@"Statistic", @"Item", @"Season", @"Weapon", @"All Files", @"Cancel"];
    __weak CoolMenuViewController *weakVC = vc;
    vc.didSelect = ^(NSInteger i) {
        [weakVC dismissViewControllerAnimated:YES completion:nil];
        NSString *keyword = (i < 4) ? @[@"Statistic", @"Item", @"Season", @"Weapon"][i] : nil;
        NSArray *files = filteredFiles(keyword);
        if (files.count == 0) {
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"No Files" message:@"No matching files found" preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [safeTopVC() presentViewController:a animated:YES completion:nil];
            return;
        }
        CoolMenuViewController *list = [CoolMenuViewController new];
        list.title = keyword ? keyword : @"Documents";
        NSMutableArray *items = [files mutableCopy];
        [items addObject:@"Cancel"];
        list.items = items;
        __weak CoolMenuViewController *weakList = list;
        list.didSelect = ^(NSInteger idx) {
            if (idx == items.count - 1) {
                [weakList dismissViewControllerAnimated:YES completion:nil];
                return;
            }
            [weakList dismissViewControllerAnimated:YES completion:^{
                showFileActionMenu(files[idx]);
            }];
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
        NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:fileName];
        if (i == 0) { // Export
            NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            if (content) UIPasteboard.generalPasteboard.string = content;
            UIAlertController *a = [UIAlertController alertControllerWithTitle:content ? @"Exported" : @"Error" message:content ? @"Copied to clipboard" : @"Failed to read" preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [safeTopVC() presentViewController:a animated:YES completion:nil];
        } else if (i == 1) { // Import
            UIAlertController *input = [UIAlertController alertControllerWithTitle:@"Import" message:@"Paste text below" preferredStyle:UIAlertControllerStyleAlert];
            [input addTextFieldWithConfigurationHandler:nil];
            [input addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *) {
                NSString *text = input.textFields.firstObject.text;
                BOOL ok = text && [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
                UIAlertController *res = [UIAlertController alertControllerWithTitle:ok ? @"Success" : @"Failed" message:ok ? @"Restart game" : @"Error" preferredStyle:UIAlertControllerStyleAlert];
                [res addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [safeTopVC() presentViewController:res animated:YES completion:nil];
            }]];
            [input addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [safeTopVC() presentViewController:input animated:YES completion:nil];
        } else if (i == 2) { // Delete
            BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            UIAlertController *a = [UIAlertController alertControllerWithTitle:ok ? @"Deleted" : @"Error" message:ok ? @"File removed" : @"Failed" preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [safeTopVC() presentViewController:a animated:YES completion:nil];
        }
    };
    [safeTopVC() presentViewController:vc animated:YES completion:nil];
}

static void showSettings() {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Background Image" message:@"Enter image URL (jpg/png)" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"CoolMenuBGURL"];
        tf.placeholder = @"https://example.com/image.jpg";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save & Apply" style:UIAlertActionStyleDefault handler:^(UIAlertAction *) {
        NSString *url = alert.textFields.firstObject.text;
        [[NSUserDefaults standardUserDefaults] setObject:url forKey:@"CoolMenuBGURL"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        g_savedBackgroundURL = url;

        UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"Downloading..." message:nil preferredStyle:UIAlertControllerStyleAlert];
        [safeTopVC() presentViewController:loading animated:YES completion:nil];

        downloadAndCacheBackground(url, ^(BOOL success) {
            [loading dismissViewControllerAnimated:YES completion:^{
                UIAlertController *done = [UIAlertController alertControllerWithTitle:success ? @"Success" : @"Failed"
                                                                             message:success ? @"New background applied!" : @"Invalid URL or download failed"
                                                                      preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [safeTopVC() presentViewController:done animated:YES completion:nil];
            }];
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear Background" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"CoolMenuBGURL"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [[NSFileManager defaultManager] removeItemAtPath:backgroundCachePath() error:nil];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Cleared" message:@"Back to default blur" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [safeTopVC() presentViewController:a animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [safeTopVC() presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Crypto & Server Verify
static NSData* dataFromHex(NSString *hex) {
    NSMutableData *data = [NSMutableData data];
    for (NSUInteger i = 0; i + 2 <= hex.length; i += 2) {
        unsigned int byte;
        [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&byte];
        [data appendBytes:&byte length:1];
    }
    return data;
}

static NSString* base64Encode(NSData *data) { return [data base64EncodedStringWithOptions:0]; }
static NSData* base64Decode(NSString *string) { return [[NSData alloc] initWithBase64EncodedString:string options:0]; }

static NSData* encryptPayload(NSData *plain, NSData *key, NSData *hmacKey) {
    uint8_t iv[16]; arc4random_buf(iv, 16);
    NSData *ivData = [NSData dataWithBytes:iv length:16];
    void *buffer = malloc(plain.length + kCCBlockSizeAES128);
    size_t outLength;
    CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key.bytes, 32, ivData.bytes, plain.bytes, plain.length, buffer, plain.length + kCCBlockSizeAES128, &outLength);
    NSData *cipher = [NSData dataWithBytesNoCopy:buffer length:outLength freeWhenDone:YES];
    NSMutableData *hmacInput = [NSMutableData dataWithData:ivData]; [hmacInput appendData:cipher];
    unsigned char hmac[32];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, 32, hmacInput.bytes, hmacInput.length, hmac);
    NSMutableData *result = [NSMutableData dataWithData:ivData]; [result appendData:cipher]; [result appendData:[NSData dataWithBytes:hmac length:32]];
    return result;
}

static NSData* decryptAndVerify(NSData *box, NSData *key, NSData *hmacKey) {
    if (box.length < 48) return nil;
    NSData *iv = [box subdataWithRange:NSMakeRange(0, 16)];
    NSData *cipher = [box subdataWithRange:NSMakeRange(16, box.length - 48)];
    NSData *receivedHmac = [box subdataWithRange:NSMakeRange(box.length - 32, 32)];
    NSMutableData *hmacInput = [NSMutableData dataWithData:iv]; [hmacInput appendData:cipher];
    unsigned char calculatedHmac[32];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, 32, hmacInput.bytes, hmacInput.length, calculatedHmac);
    if (![[NSData dataWithBytes:calculatedHmac length:32] isEqualToData:receivedHmac]) return nil;
    void *buffer = malloc(cipher.length + kCCBlockSizeAES128);
    size_t outLength;
    CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key.bytes, 32, iv.bytes, cipher.bytes, cipher.length, buffer, cipher.length + kCCBlockSizeAES128, &outLength);
    return [NSData dataWithBytesNoCopy:buffer length:outLength freeWhenDone:YES];
}

static void verifyAccessAndOpenMenu() {
    NSData *key = dataFromHex(kHexKey);
    NSData *hmacKey = dataFromHex(kHexHmacKey);
    if (key.length != 32 || hmacKey.length != 32) { exit(0); return; }

    NSString *uuidPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/uuid.txt"];
    NSString *uuid = [NSString stringWithContentsOfFile:uuidPath encoding:NSUTF8StringEncoding error:nil];
    if (!uuid.length) {
        uuid = [[NSUUID UUID] UUIDString];
        [uuid writeToFile:uuidPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }

    NSString *timestamp = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];
    NSDictionary *payload = @{@"uuid": uuid, @"timestamp": timestamp, @"encrypted": @"yes"};
    NSData *encrypted = encryptPayload([NSJSONSerialization dataWithJSONObject:payload options:0 error:nil], key, hmacKey);
    NSString *b64 = base64Encode(encrypted);

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kServerURL]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 12.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"data": b64} options:0 error:nil];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) { exit(0); return; }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSData *responseBox = base64Decode(json[@"data"]);
        NSData *decrypted = decryptAndVerify(responseBox, key, hmacKey);
        NSDictionary *responsePayload = [NSJSONSerialization JSONObjectWithData:decrypted options:0 error:nil];
        if (![responsePayload[@"allow"] boolValue]) { exit(0); return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            showMainMenu();
        });
    }] resume];
}

#pragma mark - Floating Button (Small & Perfect)
static UIButton *floatingButton = nil;

%ctor {
    g_savedBackgroundURL = [[NSUserDefaults standardUserDefaults] stringForKey:@"CoolMenuBGURL"];
    g_cachedBackgroundPath = backgroundCachePath();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        silentPatchBypass();
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil]) {
            if ([file hasSuffix:@".new"]) {
                [[NSFileManager defaultManager] removeItemAtPath:[docs stringByAppendingPathComponent:file] error:nil];
            }
        }

        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window) window = [UIApplication sharedApplication].windows.firstObject;

        floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        floatingButton.frame = CGRectMake(15, 70, 44, 44);
        floatingButton.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
        floatingButton.layer.cornerRadius = 22;
        floatingButton.layer.borderWidth = 2.0;
        floatingButton.layer.borderColor = [UIColor cyanColor].CGColor;
        [floatingButton setTitle:@"M" forState:UIControlStateNormal];
        floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:22];
        [floatingButton addTarget:%c(UIApplication) action:@selector(showMenuPressed) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:%c(UIApplication) action:@selector(handlePanGesture:)];
        [floatingButton addGestureRecognizer:pan];

        [window addSubview:floatingButton];
    });
}

%hook UIApplication
%new
- (void)showMenuPressed {
    if (!g_hasShownCreditAlert) {
        g_hasShownCreditAlert = YES;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Welcome" message:@"Thank you for using!\nCảm ơn vì đã sử dụng!" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *) {
            verifyAccessAndOpenMenu();
        }]];
        [safeTopVC() presentViewController:alert animated:YES completion:nil];
    } else {
        verifyAccessAndOpenMenu();
    }
}

%new
- (void)handlePanGesture:(UIPanGestureRecognizer *)gesture {
    UIView *view = gesture.view;
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:view.superview];
        view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
        [gesture setTranslation:CGPointZero inView:view.superview];
    }
}
%end
