// tweak.xm — Soul Knight Save Manager
// iOS 14+ | Theos/Logos | ARC
// Floating panel: Upload (NSUserDefaults + .data files → API) & Load (API → device)

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Config  (change API_BASE to your server URL)
// ─────────────────────────────────────────────────────────────────────────────
#define API_BASE @"https://yourserver.com/skapi.php"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Session UUID (stored in a dedicated file, survives any UD wipe)
// ─────────────────────────────────────────────────────────────────────────────
static NSString *sessionFilePath(void) {
    return [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Preferences/SKToolsSession.txt"];
}
static NSString *loadSessionUUID(void) {
    return [NSString stringWithContentsOfFile:sessionFilePath()
                                     encoding:NSUTF8StringEncoding error:nil];
}
static void saveSessionUUID(NSString *uuid) {
    [uuid writeToFile:sessionFilePath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static void clearSessionUUID(void) {
    [[NSFileManager defaultManager] removeItemAtPath:sessionFilePath() error:nil];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Device UUID  (stable per-app identifier)
// ─────────────────────────────────────────────────────────────────────────────
static NSString *deviceUUID(void) {
    return [[[UIDevice currentDevice] identifierForVendor] UUIDString]
           ?: [[NSUUID UUID] UUIDString];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Multipart helper
// ─────────────────────────────────────────────────────────────────────────────
@interface SKMultipart : NSObject
@property (nonatomic, strong) NSString *boundary;
@property (nonatomic, strong) NSMutableData *body;
- (instancetype)init;
- (void)addField:(NSString *)name value:(NSString *)value;
- (void)addFile:(NSString *)name filename:(NSString *)filename data:(NSData *)data mime:(NSString *)mime;
- (NSData *)finish;
- (NSString *)contentType;
@end

@implementation SKMultipart
- (instancetype)init {
    self = [super init];
    _boundary = [NSString stringWithFormat:@"----SKBoundary%08X", arc4random()];
    _body = [NSMutableData new];
    return self;
}
- (void)addField:(NSString *)name value:(NSString *)value {
    NSString *s = [NSString stringWithFormat:
        @"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n",
        _boundary, name, value];
    [_body appendData:[s dataUsingEncoding:NSUTF8StringEncoding]];
}
- (void)addFile:(NSString *)name filename:(NSString *)filename data:(NSData *)data mime:(NSString *)mime {
    NSString *header = [NSString stringWithFormat:
        @"--%@\r\nContent-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\nContent-Type: %@\r\n\r\n",
        _boundary, name, filename, mime];
    [_body appendData:[header dataUsingEncoding:NSUTF8StringEncoding]];
    [_body appendData:data];
    [_body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
}
- (NSData *)finish {
    NSString *tail = [NSString stringWithFormat:@"--%@--\r\n", _boundary];
    [_body appendData:[tail dataUsingEncoding:NSUTF8StringEncoding]];
    return _body;
}
- (NSString *)contentType {
    return [NSString stringWithFormat:@"multipart/form-data; boundary=%@", _boundary];
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Upload
// ─────────────────────────────────────────────────────────────────────────────
static void performUpload(void (^completion)(NSString *link, NSString *err)) {
    // 1. Serialize NSUserDefaults → plist XML
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud synchronize];
    NSDictionary *snapshot = [ud dictionaryRepresentation];

    NSError *plistErr = nil;
    NSData *plistData = [NSPropertyListSerialization
        dataWithPropertyList:snapshot
        format:NSPropertyListXMLFormat_v1_0
        options:0 error:&plistErr];

    if (plistErr || !plistData) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, [NSString stringWithFormat:@"Plist serialize error: %@",
                             plistErr.localizedDescription]);
        });
        return;
    }
    NSString *plistXML = [[NSString alloc] initWithData:plistData encoding:NSUTF8StringEncoding];

    // 2. Collect .data files from Documents
    NSString *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *allFiles = [fm contentsOfDirectoryAtPath:docs error:nil] ?: @[];
    NSMutableArray *dataFiles = [NSMutableArray new];
    for (NSString *f in allFiles)
        if ([f.pathExtension isEqualToString:@"data"])
            [dataFiles addObject:f];

    // 3. Build multipart body
    SKMultipart *mp = [SKMultipart new];
    [mp addField:@"uuid"        value:deviceUUID()];
    [mp addField:@"action"      value:@"upload"];
    [mp addField:@"playerpref"  value:plistXML];

    for (NSString *fname in dataFiles) {
        NSString *path = [docs stringByAppendingPathComponent:fname];
        NSData *fdata  = [NSData dataWithContentsOfFile:path];
        if (fdata)
            [mp addFile:@"datafiles[]" filename:fname data:fdata mime:@"application/octet-stream"];
    }

    NSData *body = [mp finish];

    // 4. POST
    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:API_BASE]
           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
       timeoutInterval:30];
    req.HTTPMethod = @"POST";
    [req setValue:[mp contentType] forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = body;

    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err || !data) {
                completion(nil, err.localizedDescription ?: @"Network error");
                return;
            }
            NSError *je = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                options:0 error:&je];
            if (je || !json) {
                completion(nil, @"Invalid API response");
                return;
            }
            if (json[@"error"]) { completion(nil, json[@"error"]); return; }
            NSString *link = json[@"link"];
            NSString *uuid = json[@"uuid"];
            if (link && uuid) {
                saveSessionUUID(uuid);
                completion(link, nil);
            } else {
                completion(nil, @"Missing link/uuid in response");
            }
        });
    }] resume];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Load
// ─────────────────────────────────────────────────────────────────────────────
static void performLoad(void (^completion)(BOOL success, NSString *msg)) {
    NSString *uuid = loadSessionUUID();
    if (!uuid.length) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, @"No upload session found.\nUpload first.");
        });
        return;
    }

    SKMultipart *mp = [SKMultipart new];
    [mp addField:@"action" value:@"load"];
    [mp addField:@"uuid"   value:uuid];
    NSData *body = [mp finish];

    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:API_BASE]
           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
       timeoutInterval:30];
    req.HTTPMethod = @"POST";
    [req setValue:[mp contentType] forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = body;

    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err || !data) {
                completion(NO, err.localizedDescription ?: @"Network error");
                return;
            }
            NSError *je = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                options:0 error:&je];
            if (je || !json) { completion(NO, @"Invalid API response"); return; }
            if (json[@"error"]) { completion(NO, json[@"error"]); return; }

            NSUInteger applied = 0;

            // ── Apply PlayerPrefs ────────────────────────────────────────────
            NSString *ppXML = json[@"playerpref"];
            if (ppXML.length) {
                NSError *ppErr = nil;
                NSDictionary *newSnap = [NSPropertyListSerialization
                    propertyListWithData:[ppXML dataUsingEncoding:NSUTF8StringEncoding]
                    options:NSPropertyListMutableContainersAndLeaves
                    format:nil error:&ppErr];
                if (!ppErr && [newSnap isKindOfClass:[NSDictionary class]]) {
                    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
                    NSDictionary *cur  = [ud dictionaryRepresentation];
                    for (NSString *k in cur) [ud removeObjectForKey:k];
                    for (NSString *k in newSnap) [ud setObject:newSnap[k] forKey:k];
                    [ud synchronize];
                    applied++;
                }
            }

            // ── Write .data files ───────────────────────────────────────────
            NSDictionary *dataMap = json[@"data"];
            NSString *docs = NSSearchPathForDirectoriesInDomains(
                NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
            NSFileManager *fm = NSFileManager.defaultManager;
            for (NSString *fname in dataMap) {
                NSString *b64 = dataMap[fname];
                NSData *raw   = [[NSData alloc]
                    initWithBase64EncodedString:b64
                    options:NSDataBase64DecodingIgnoreUnknownCharacters];
                if (raw) {
                    NSString *dst = [docs stringByAppendingPathComponent:fname];
                    [fm removeItemAtPath:dst error:nil];
                    [raw writeToFile:dst atomically:YES];
                    applied++;
                }
            }

            clearSessionUUID();
            NSString *msg = [NSString stringWithFormat:
                @"Loaded %lu item(s).\nSession cleared.\nRestart app to apply.",
                (unsigned long)applied];
            completion(YES, msg);
        });
    }] resume];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKPanel
// ─────────────────────────────────────────────────────────────────────────────
static const CGFloat kPW = 260;
static const CGFloat kBH = 46;
static const CGFloat kCH = 124;

@interface SKPanel : UIView
@property (nonatomic, strong) UIView   *content;
@property (nonatomic, strong) UILabel  *statusLabel;
@property (nonatomic, strong) UIButton *uploadBtn;
@property (nonatomic, strong) UIButton *loadBtn;
@property (nonatomic, assign) BOOL     expanded;
@end

@implementation SKPanel

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0,0,kPW,kBH)];
    if (!self) return nil;
    self.clipsToBounds      = NO;
    self.layer.cornerRadius = 12;
    self.backgroundColor    = [UIColor colorWithRed:0.06 green:0.06 blue:0.09 alpha:0.96];
    self.layer.shadowColor   = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.80;
    self.layer.shadowRadius  = 9;
    self.layer.shadowOffset  = CGSizeMake(0, 3);
    self.layer.zPosition     = 9999;
    [self buildBar];
    [self buildContent];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(onPan:)];
    [self addGestureRecognizer:pan];
    return self;
}

- (void)buildBar {
    // Drag handle
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(kPW/2-20, 8, 40, 3)];
    h.backgroundColor    = [UIColor colorWithWhite:0.45 alpha:0.5];
    h.layer.cornerRadius = 1.5;
    [self addSubview:h];
    // Title
    UILabel *t = [UILabel new];
    t.text          = @"⚙  SK Save Manager";
    t.textColor     = [UIColor colorWithWhite:0.82 alpha:1];
    t.font          = [UIFont boldSystemFontOfSize:12];
    t.textAlignment = NSTextAlignmentCenter;
    t.frame         = CGRectMake(0, 16, kPW, 22);
    t.userInteractionEnabled = NO;
    [self addSubview:t];
    // Tap zone
    UIView *tz = [[UIView alloc] initWithFrame:CGRectMake(0,0,kPW,kBH)];
    tz.backgroundColor = UIColor.clearColor;
    [tz addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(togglePanel)]];
    [self addSubview:tz];
}

- (void)buildContent {
    self.content = [[UIView alloc] initWithFrame:CGRectMake(0, kBH, kPW, kCH)];
    self.content.hidden        = YES;
    self.content.alpha         = 0;
    self.content.clipsToBounds = YES;
    [self addSubview:self.content];

    CGFloat pad = 9, w = kPW - pad*2;

    // Status label
    self.statusLabel = [UILabel new];
    self.statusLabel.frame         = CGRectMake(pad, 6, w, 12);
    self.statusLabel.font          = [UIFont systemFontOfSize:9.5];
    self.statusLabel.textColor     = [UIColor colorWithWhite:0.48 alpha:1];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 1;
    [self updateStatusLabel];
    [self.content addSubview:self.statusLabel];

    // Upload button
    self.uploadBtn = [self makeBtn:@"⬆  Upload to Cloud"
                             color:[UIColor colorWithRed:0.16 green:0.60 blue:0.92 alpha:1]
                             frame:CGRectMake(pad, 24, w, 42)
                            action:@selector(tapUpload)];
    [self.content addSubview:self.uploadBtn];

    // Load button
    self.loadBtn = [self makeBtn:@"⬇  Load from Cloud"
                           color:[UIColor colorWithRed:0.20 green:0.72 blue:0.44 alpha:1]
                           frame:CGRectMake(pad, 72, w, 42)
                          action:@selector(tapLoad)];
    [self.content addSubview:self.loadBtn];
}

- (UIButton *)makeBtn:(NSString *)title color:(UIColor *)color
                frame:(CGRect)frame action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = frame;
    b.backgroundColor   = color;
    b.layer.cornerRadius = 9;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:0.80 alpha:1] forState:UIControlStateHighlighted];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)updateStatusLabel {
    NSString *uuid = loadSessionUUID();
    self.statusLabel.text = uuid
        ? [NSString stringWithFormat:@"Session: %@…", [uuid substringToIndex:8]]
        : @"No active session";
}

// ── Toggle ────────────────────────────────────────────────────────────────────
- (void)togglePanel {
    self.expanded = !self.expanded;
    if (self.expanded) {
        [self updateStatusLabel];
        self.content.hidden = NO;
        self.content.frame  = CGRectMake(0, kBH, kPW, kCH);
        [UIView animateWithDuration:0.22 delay:0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            CGRect f = self.frame; f.size.height = kBH + kCH; self.frame = f;
            self.content.alpha = 1;
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.18 delay:0
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
            CGRect f = self.frame; f.size.height = kBH; self.frame = f;
            self.content.alpha = 0;
        } completion:^(BOOL _){ self.content.hidden = YES; }];
    }
}

// ── Upload ────────────────────────────────────────────────────────────────────
- (void)tapUpload {
    // Count .data files for the confirmation message
    NSString *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *all = [NSFileManager.defaultManager contentsOfDirectoryAtPath:docs error:nil] ?: @[];
    NSUInteger dataCount = 0;
    for (NSString *f in all)
        if ([f.pathExtension isEqualToString:@"data"]) dataCount++;

    NSString *existing = loadSessionUUID();
    NSString *msg = [NSString stringWithFormat:
        @"Are you sure?\n\nThis will upload:\n• PlayerPrefs (NSUserDefaults)\n• %lu .data file(s)\n%@\nto the cloud for editing.",
        (unsigned long)dataCount,
        existing ? @"\n⚠ This will overwrite your existing session.\n" : @""];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Upload Save Data"
                         message:msg
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Yes, Upload"
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self setBusy:YES button:self.uploadBtn title:@"Uploading…"];
        performUpload(^(NSString *link, NSString *err) {
            [self setBusy:NO button:self.uploadBtn title:@"⬆  Upload to Cloud"];
            [self updateStatusLabel];
            if (err) {
                [self toast:[NSString stringWithFormat:@"Upload failed:\n%@", err]
                    success:NO];
            } else {
                // Copy link to clipboard
                [UIPasteboard generalPasteboard].string = link;
                [self toast:[NSString stringWithFormat:
                    @"Uploaded!\n\nLink copied to clipboard:\n%@\n\nOpen in browser to edit.", link]
                    success:YES];
            }
        });
    }]];

    [[self topVC] presentViewController:alert animated:YES completion:nil];
}

// ── Load ──────────────────────────────────────────────────────────────────────
- (void)tapLoad {
    NSString *uuid = loadSessionUUID();
    if (!uuid) {
        [self toast:@"No session found.\nUpload first." success:NO];
        return;
    }
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Load Save Data"
                         message:@"This will download your edited save data from the cloud and apply it to this device.\n\nThe cloud session will be deleted."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Yes, Load"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self setBusy:YES button:self.loadBtn title:@"Loading…"];
        performLoad(^(BOOL ok, NSString *msg) {
            [self setBusy:NO button:self.loadBtn title:@"⬇  Load from Cloud"];
            [self updateStatusLabel];
            [self toast:msg success:ok];
        });
    }]];
    [[self topVC] presentViewController:alert animated:YES completion:nil];
}

// ── Helpers ───────────────────────────────────────────────────────────────────
- (void)setBusy:(BOOL)busy button:(UIButton *)btn title:(NSString *)title {
    btn.enabled = !busy;
    [btn setTitle:title forState:UIControlStateNormal];
    btn.alpha = busy ? 0.60 : 1.0;
}

- (void)toast:(NSString *)msg success:(BOOL)ok {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *parent = self.superview ?: [self topVC].view;
        UILabel *t = [UILabel new];
        t.text               = msg;
        t.textColor          = UIColor.whiteColor;
        t.font               = [UIFont systemFontOfSize:12];
        t.backgroundColor    = ok
            ? [UIColor colorWithRed:0.07 green:0.20 blue:0.10 alpha:0.97]
            : [UIColor colorWithRed:0.22 green:0.07 blue:0.07 alpha:0.97];
        t.layer.cornerRadius = 10;
        t.layer.borderColor  = ok
            ? [UIColor colorWithRed:0.25 green:0.78 blue:0.40 alpha:0.6].CGColor
            : [UIColor colorWithRed:0.80 green:0.26 blue:0.26 alpha:0.6].CGColor;
        t.layer.borderWidth  = 1;
        t.clipsToBounds      = YES;
        t.numberOfLines      = 0;
        t.textAlignment      = NSTextAlignmentCenter;
        t.translatesAutoresizingMaskIntoConstraints = NO;
        [parent addSubview:t];
        [NSLayoutConstraint activateConstraints:@[
            [t.centerXAnchor constraintEqualToAnchor:parent.centerXAnchor],
            [t.centerYAnchor constraintEqualToAnchor:parent.centerYAnchor],
            [t.widthAnchor constraintLessThanOrEqualToAnchor:parent.widthAnchor constant:-32],
        ]];
        // Inner padding via insets label
        t.layer.sublayers = nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.30 animations:^{ t.alpha = 0; }
                completion:^(BOOL _){ [t removeFromSuperview]; }];
        });
    });
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint d  = [g translationInView:self.superview];
    CGRect  sb = self.superview.bounds;
    CGFloat nx = MAX(self.bounds.size.width/2,
                     MIN(sb.size.width  - self.bounds.size.width/2,  self.center.x + d.x));
    CGFloat ny = MAX(self.bounds.size.height/2,
                     MIN(sb.size.height - self.bounds.size.height/2, self.center.y + d.y));
    self.center = CGPointMake(nx, ny);
    [g setTranslation:CGPointZero inView:self.superview];
}

- (UIViewController *)topVC {
    UIViewController *vc = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows.reverseObjectEnumerator)
        if (!w.isHidden && w.alpha > 0 && w.rootViewController)
            { vc = w.rootViewController; break; }
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Injection
// ─────────────────────────────────────────────────────────────────────────────
static SKPanel *gPanel = nil;

static void injectPanel(void) {
    UIWindow *win = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows)
        if (!w.isHidden && w.alpha > 0) { win = w; break; }
    if (!win) return;
    UIView *root = win.rootViewController.view ?: win;
    gPanel = [SKPanel new];
    gPanel.center = CGPointMake(
        root.bounds.size.width - gPanel.bounds.size.width/2 - 10, 88);
    [root addSubview:gPanel];
    [root bringSubviewToFront:gPanel];
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ injectPanel(); });
    });
}
%end
