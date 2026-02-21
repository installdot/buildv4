// tweak.xm — Soul Knight Save Manager v8
// iOS 14+ | Theos/Logos | ARC
// Upload: sequential per-file POSTs with live progress bar + log
// Load: download + apply all files, delete cloud session

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ── Config ────────────────────────────────────────────────────────────────────
#define API_BASE @"https://yourserver.com/skapi.php"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Session UUID  (survives NSUserDefaults wipe)
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
    [uuid writeToFile:sessionFilePath() atomically:YES
             encoding:NSUTF8StringEncoding error:nil];
}
static void clearSessionUUID(void) {
    [[NSFileManager defaultManager] removeItemAtPath:sessionFilePath() error:nil];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Device UUID
// ─────────────────────────────────────────────────────────────────────────────
static NSString *deviceUUID(void) {
    NSString *v = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    return v ?: [[NSUUID UUID] UUIDString];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NSURLSession helper  (120-second timeout, no cache)
// ─────────────────────────────────────────────────────────────────────────────
static NSURLSession *makeSession(void) {
    NSURLSessionConfiguration *cfg =
        [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest  = 120;
    cfg.timeoutIntervalForResource = 300;
    cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    return [NSURLSession sessionWithConfiguration:cfg];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Multipart builder
// ─────────────────────────────────────────────────────────────────────────────
static NSMutableURLRequest *buildRequest(NSString *boundary) {
    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:API_BASE]
           cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
       timeoutInterval:120];
    req.HTTPMethod = @"POST";
    [req setValue:[NSString stringWithFormat:
        @"multipart/form-data; boundary=%@", boundary]
       forHTTPHeaderField:@"Content-Type"];
    return req;
}

static NSData *mpField(NSString *boundary, NSString *name, NSString *value) {
    NSString *s = [NSString stringWithFormat:
        @"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n",
        boundary, name, value];
    return [s dataUsingEncoding:NSUTF8StringEncoding];
}

static NSData *mpFile(NSString *boundary, NSString *name,
                      NSString *filename, NSData *data) {
    NSMutableData *m = [NSMutableData new];
    NSString *hdr = [NSString stringWithFormat:
        @"--%@\r\nContent-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n"
        @"Content-Type: application/octet-stream\r\n\r\n", boundary, name, filename];
    [m appendData:[hdr dataUsingEncoding:NSUTF8StringEncoding]];
    [m appendData:data];
    [m appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    return m;
}

static NSData *mpEnd(NSString *boundary) {
    return [[NSString stringWithFormat:@"--%@--\r\n", boundary]
            dataUsingEncoding:NSUTF8StringEncoding];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKProgressOverlay
// ─────────────────────────────────────────────────────────────────────────────
@interface SKProgressOverlay : UIView
@property (nonatomic, strong) UILabel      *titleLabel;
@property (nonatomic, strong) UIProgressView *bar;
@property (nonatomic, strong) UILabel      *percentLabel;
@property (nonatomic, strong) UITextView   *logView;
@property (nonatomic, strong) UIButton     *closeBtn;
@property (nonatomic, assign) BOOL         finished;
+ (instancetype)showInView:(UIView *)parent title:(NSString *)title;
- (void)setProgress:(float)p;
- (void)log:(NSString *)msg;
- (void)finish:(BOOL)success message:(NSString *)msg;
@end

@implementation SKProgressOverlay

+ (instancetype)showInView:(UIView *)parent title:(NSString *)title {
    SKProgressOverlay *o = [[SKProgressOverlay alloc] initWithFrame:parent.bounds];
    o.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [parent addSubview:o];
    [o setupWithTitle:title];
    o.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ o.alpha = 1; }];
    return o;
}

- (void)setupWithTitle:(NSString *)title {
    // Dim background
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];

    // Card
    UIView *card = [[UIView alloc] init];
    card.backgroundColor     = [UIColor colorWithRed:0.09 green:0.09 blue:0.13 alpha:1];
    card.layer.cornerRadius  = 16;
    card.layer.shadowColor   = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.80;
    card.layer.shadowRadius  = 16;
    card.layer.shadowOffset  = CGSizeMake(0, 5);
    card.clipsToBounds       = NO;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:card];

    // Title
    self.titleLabel = [UILabel new];
    self.titleLabel.text          = title;
    self.titleLabel.textColor     = [UIColor whiteColor];
    self.titleLabel.font          = [UIFont boldSystemFontOfSize:14];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.titleLabel];

    // Progress bar
    self.bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.bar.trackTintColor    = [UIColor colorWithWhite:0.25 alpha:1];
    self.bar.progressTintColor = [UIColor colorWithRed:0.20 green:0.75 blue:0.42 alpha:1];
    self.bar.layer.cornerRadius = 3;
    self.bar.clipsToBounds      = YES;
    self.bar.progress           = 0;
    self.bar.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.bar];

    // Percent label
    self.percentLabel = [UILabel new];
    self.percentLabel.text          = @"0%";
    self.percentLabel.textColor     = [UIColor colorWithWhite:0.60 alpha:1];
    self.percentLabel.font          = [UIFont boldSystemFontOfSize:11];
    self.percentLabel.textAlignment = NSTextAlignmentCenter;
    self.percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.percentLabel];

    // Log view
    self.logView = [[UITextView alloc] init];
    self.logView.backgroundColor   = [UIColor colorWithWhite:0.05 alpha:1];
    self.logView.textColor         = [UIColor colorWithRed:0.45 green:1.0 blue:0.60 alpha:1];
    self.logView.font              = [UIFont fontWithName:@"Courier" size:10.5]
                                     ?: [UIFont systemFontOfSize:10.5];
    self.logView.editable          = NO;
    self.logView.selectable        = NO;
    self.logView.layer.cornerRadius = 8;
    self.logView.text              = @"";
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.logView];

    // Close button (hidden until finished)
    self.closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.closeBtn setTitle:@"Close" forState:UIControlStateNormal];
    [self.closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeBtn.titleLabel.font  = [UIFont boldSystemFontOfSize:13];
    self.closeBtn.backgroundColor  = [UIColor colorWithWhite:0.22 alpha:1];
    self.closeBtn.layer.cornerRadius = 9;
    self.closeBtn.hidden           = YES;
    self.closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.closeBtn addTarget:self action:@selector(dismiss)
             forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.closeBtn];

    // Constraints
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:296],

        [self.titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        [self.bar.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:14],
        [self.bar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.bar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [self.bar.heightAnchor constraintEqualToConstant:6],

        [self.percentLabel.topAnchor constraintEqualToAnchor:self.bar.bottomAnchor constant:5],
        [self.percentLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.percentLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        [self.logView.topAnchor constraintEqualToAnchor:self.percentLabel.bottomAnchor constant:10],
        [self.logView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [self.logView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [self.logView.heightAnchor constraintEqualToConstant:160],

        [self.closeBtn.topAnchor constraintEqualToAnchor:self.logView.bottomAnchor constant:12],
        [self.closeBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.closeBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [self.closeBtn.heightAnchor constraintEqualToConstant:40],
        [card.bottomAnchor constraintEqualToAnchor:self.closeBtn.bottomAnchor constant:16],
    ]];
}

- (void)setProgress:(float)p {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.bar setProgress:p animated:YES];
        self.percentLabel.text = [NSString stringWithFormat:@"%.0f%%", p * 100];
    });
}

- (void)log:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *ts = ({
            NSDateFormatter *f = [NSDateFormatter new];
            f.dateFormat = @"HH:mm:ss";
            [f stringFromDate:[NSDate date]];
        });
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, msg];
        self.logView.text = [self.logView.text stringByAppendingString:line];
        // Scroll to bottom
        if (self.logView.text.length > 0) {
            NSRange bottom = NSMakeRange(self.logView.text.length - 1, 1);
            [self.logView scrollRangeToVisible:bottom];
        }
    });
}

- (void)finish:(BOOL)success message:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.finished = YES;
        [self setProgress:1.0];
        self.percentLabel.text = success ? @"✓ Done" : @"✗ Failed";
        self.percentLabel.textColor = success
            ? [UIColor colorWithRed:0.28 green:0.85 blue:0.45 alpha:1]
            : [UIColor colorWithRed:0.90 green:0.30 blue:0.30 alpha:1];
        if (msg.length) [self log:msg];
        self.closeBtn.hidden = NO;
        if (success) {
            self.closeBtn.backgroundColor =
                [UIColor colorWithRed:0.16 green:0.55 blue:0.90 alpha:1];
        } else {
            self.closeBtn.backgroundColor =
                [UIColor colorWithRed:0.60 green:0.18 blue:0.18 alpha:1];
        }
    });
}

- (void)dismiss {
    [UIView animateWithDuration:0.18 animations:^{ self.alpha = 0; }
                     completion:^(BOOL _){ [self removeFromSuperview]; }];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Upload logic  (sequential: init → one file at a time)
// ─────────────────────────────────────────────────────────────────────────────

// Single POST helper. Calls back on main queue.
static void postRequest(NSMutableURLRequest *req,
                        NSURLSession *session,
                        void (^cb)(NSDictionary *json, NSError *err)) {
    [[session dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) { dispatch_async(dispatch_get_main_queue(), ^{ cb(nil, err); }); return; }
        NSError *je = nil;
        NSDictionary *j = data
            ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&je]
            : nil;
        NSError *outErr = je
            ? je
            : (j[@"error"]
               ? [NSError errorWithDomain:@"SKApi" code:0
                                 userInfo:@{NSLocalizedDescriptionKey: j[@"error"]}]
               : nil);
        dispatch_async(dispatch_get_main_queue(), ^{ cb(j, outErr); });
    }] resume];
}

// Main upload sequence
static void performUpload(SKProgressOverlay *overlay,
                          void (^done)(NSString *link, NSString *err)) {
    NSString *uuid = deviceUUID();
    NSURLSession *session = makeSession();

    // ── Step 1: serialize NSUserDefaults ─────────────────────────────────────
    [overlay log:@"Reading NSUserDefaults…"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSDictionary *snap = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSError *pErr = nil;
    NSData *plistData = [NSPropertyListSerialization
        dataWithPropertyList:snap
        format:NSPropertyListXMLFormat_v1_0
        options:0 error:&pErr];
    if (pErr || !plistData) {
        done(nil, [NSString stringWithFormat:@"Plist error: %@",
                   pErr.localizedDescription]); return;
    }
    NSString *plistXML = [[NSString alloc] initWithData:plistData
                                               encoding:NSUTF8StringEncoding];
    [overlay log:[NSString stringWithFormat:@"PlayerPrefs: %lu keys",
                  (unsigned long)snap.count]];

    // ── Step 2: collect .data files ───────────────────────────────────────────
    NSString *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *all = [[NSFileManager defaultManager]
                    contentsOfDirectoryAtPath:docs error:nil] ?: @[];
    NSMutableArray<NSString *> *dataFiles = [NSMutableArray new];
    for (NSString *f in all)
        if ([f.pathExtension.lowercaseString isEqualToString:@"data"])
            [dataFiles addObject:f];

    [overlay log:[NSString stringWithFormat:@"Found %lu .data file(s)",
                  (unsigned long)dataFiles.count]];

    // Total steps: 1 init + N data files  (+ 1 final confirm = N+2 ticks)
    NSUInteger total = 1 + dataFiles.count;   // init + files
    __block NSUInteger done_steps = 0;
    void (^tick)(void) = ^{
        done_steps++;
        [overlay setProgress:(float)done_steps / (float)(total + 1)];
    };

    // ── Step 3: POST init (PlayerPrefs only) ──────────────────────────────────
    [overlay log:@"Uploading PlayerPrefs…"];
    NSString *boundary = [NSString stringWithFormat:@"----SKBound%08X", arc4random()];
    NSMutableData *initBody = [NSMutableData new];
    [initBody appendData:mpField(boundary, @"action",     @"upload")];
    [initBody appendData:mpField(boundary, @"uuid",       uuid)];
    [initBody appendData:mpField(boundary, @"playerpref", plistXML)];
    [initBody appendData:mpEnd(boundary)];

    NSMutableURLRequest *initReq = buildRequest(boundary);
    initReq.HTTPBody = initBody;

    postRequest(initReq, session, ^(NSDictionary *json, NSError *err) {
        if (err) { done(nil, [NSString stringWithFormat:@"Init failed: %@",
                               err.localizedDescription]); return; }
        tick();
        [overlay log:@"PlayerPrefs uploaded ✓"];

        // ── Step 4: upload each .data file sequentially ───────────────────────
        __block NSUInteger idx = 0;

        void (^uploadNext)(void);
        // Declare via __block to allow recursion inside block
        __block void (^uploadNextRef)(void) = nil;
        uploadNext = ^{
            if (idx >= dataFiles.count) {
                // All done — get the link
                NSString *link = json[@"link"]
                    ?: [NSString stringWithFormat:@"%@?view=%@", API_BASE, uuid];
                // Re-fetch link from server if missing (shouldn't be, but safe)
                [overlay log:@"All files uploaded ✓"];
                [overlay setProgress:1.0];
                saveSessionUUID(uuid);
                done(link, nil);
                return;
            }

            NSString *fname = dataFiles[idx];
            idx++;
            NSString *path  = [docs stringByAppendingPathComponent:fname];
            NSData   *fdata = [NSData dataWithContentsOfFile:path];

            if (!fdata) {
                [overlay log:[NSString stringWithFormat:@"⚠ Skip %@ (unreadable)", fname]];
                tick();
                uploadNextRef();
                return;
            }

            [overlay log:[NSString stringWithFormat:@"Uploading %@ (%.1f KB)…",
                          fname, fdata.length / 1024.0]];

            NSString *b2 = [NSString stringWithFormat:@"----SKBound%08X", arc4random()];
            NSMutableData *fb = [NSMutableData new];
            [fb appendData:mpField(b2, @"action", @"upload_file")];
            [fb appendData:mpField(b2, @"uuid",   uuid)];
            [fb appendData:mpFile(b2,  @"datafile", fname, fdata)];
            [fb appendData:mpEnd(b2)];

            NSMutableURLRequest *fr = buildRequest(b2);
            fr.HTTPBody = fb;

            postRequest(fr, session, ^(NSDictionary *fj, NSError *ferr) {
                if (ferr)
                    [overlay log:[NSString stringWithFormat:@"⚠ %@ failed: %@",
                                  fname, ferr.localizedDescription]];
                else
                    [overlay log:[NSString stringWithFormat:@"%@ ✓", fname]];
                tick();
                uploadNextRef();
            });
        };
        uploadNextRef = uploadNext;
        uploadNext();
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Load logic
// ─────────────────────────────────────────────────────────────────────────────
static void performLoad(SKProgressOverlay *overlay,
                        void (^done)(BOOL ok, NSString *msg)) {
    NSString *uuid = loadSessionUUID();
    if (!uuid.length) {
        done(NO, @"No upload session found.\nUpload first."); return;
    }

    NSURLSession *session = makeSession();
    [overlay log:[NSString stringWithFormat:@"Session: %@…", [uuid substringToIndex:8]]];
    [overlay log:@"Requesting files from server…"];

    NSString *boundary = [NSString stringWithFormat:@"----SKBound%08X", arc4random()];
    NSMutableData *body = [NSMutableData new];
    [body appendData:mpField(boundary, @"action", @"load")];
    [body appendData:mpField(boundary, @"uuid",   uuid)];
    [body appendData:mpEnd(boundary)];

    NSMutableURLRequest *req = buildRequest(boundary);
    req.HTTPBody = body;
    [overlay setProgress:0.1];

    postRequest(req, session, ^(NSDictionary *json, NSError *err) {
        if (err) { done(NO, [NSString stringWithFormat:@"Load failed: %@",
                             err.localizedDescription]); return; }

        [overlay setProgress:0.4];
        NSUInteger applied = 0;

        // Apply PlayerPrefs
        NSString *ppXML = json[@"playerpref"];
        if (ppXML.length) {
            [overlay log:@"Applying PlayerPrefs…"];
            NSError *pe = nil;
            NSDictionary *newSnap = [NSPropertyListSerialization
                propertyListWithData:[ppXML dataUsingEncoding:NSUTF8StringEncoding]
                options:NSPropertyListMutableContainersAndLeaves
                format:nil error:&pe];
            if (!pe && [newSnap isKindOfClass:[NSDictionary class]]) {
                NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
                NSDictionary *cur  = [ud dictionaryRepresentation];
                for (NSString *k in cur) [ud removeObjectForKey:k];
                for (NSString *k in newSnap) [ud setObject:newSnap[k] forKey:k];
                [ud synchronize];
                [overlay log:[NSString stringWithFormat:@"PlayerPrefs applied ✓ (%lu keys)",
                              (unsigned long)newSnap.count]];
                applied++;
            } else {
                [overlay log:@"⚠ PlayerPrefs parse failed"];
            }
        }

        // Write .data files
        NSDictionary *dataMap = json[@"data"];
        NSString *docs = NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSFileManager *fm = NSFileManager.defaultManager;
        NSUInteger fileCount = dataMap.count;
        __block NSUInteger fi = 0;

        for (NSString *fname in dataMap) {
            NSString *b64  = dataMap[fname];
            NSData   *raw  = [[NSData alloc]
                initWithBase64EncodedString:b64
                options:NSDataBase64DecodingIgnoreUnknownCharacters];
            if (raw) {
                NSString *dst = [docs stringByAppendingPathComponent:fname];
                [fm removeItemAtPath:dst error:nil];
                [raw writeToFile:dst atomically:YES];
                [overlay log:[NSString stringWithFormat:@"%@ ✓ (%.1f KB)",
                              fname, raw.length / 1024.0]];
                applied++;
            } else {
                [overlay log:[NSString stringWithFormat:@"⚠ %@ (bad base64)", fname]];
            }
            fi++;
            [overlay setProgress:0.4f + 0.55f * ((float)fi / MAX(1, (float)fileCount))];
        }

        clearSessionUUID();
        NSString *msg = [NSString stringWithFormat:
            @"✓ Loaded %lu item(s).\nSession deleted.\nRestart the game to apply.",
            (unsigned long)applied];
        done(YES, msg);
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKPanel
// ─────────────────────────────────────────────────────────────────────────────
static const CGFloat kPW = 258;
static const CGFloat kBH = 46;
static const CGFloat kCH = 122;

@interface SKPanel : UIView
@property (nonatomic, strong) UIView   *content;
@property (nonatomic, strong) UILabel  *statusLabel;
@property (nonatomic, strong) UIButton *uploadBtn;
@property (nonatomic, strong) UIButton *loadBtn;
@property (nonatomic, assign) BOOL     expanded;
@end

@implementation SKPanel

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, kPW, kBH)];
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
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(kPW/2-20, 8, 40, 3)];
    h.backgroundColor    = [UIColor colorWithWhite:0.45 alpha:0.5];
    h.layer.cornerRadius = 1.5;
    [self addSubview:h];

    UILabel *t = [UILabel new];
    t.text          = @"⚙  SK Save Manager";
    t.textColor     = [UIColor colorWithWhite:0.82 alpha:1];
    t.font          = [UIFont boldSystemFontOfSize:12];
    t.textAlignment = NSTextAlignmentCenter;
    t.frame         = CGRectMake(0, 14, kPW, 22);
    t.userInteractionEnabled = NO;
    [self addSubview:t];

    UIView *tz = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPW, kBH)];
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

    self.statusLabel = [UILabel new];
    self.statusLabel.frame         = CGRectMake(pad, 6, w, 12);
    self.statusLabel.font          = [UIFont systemFontOfSize:9.5];
    self.statusLabel.textColor     = [UIColor colorWithWhite:0.45 alpha:1];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.content addSubview:self.statusLabel];
    [self refreshStatus];

    self.uploadBtn = [self btn:@"⬆  Upload to Cloud"
                         color:[UIColor colorWithRed:0.16 green:0.58 blue:0.92 alpha:1]
                         frame:CGRectMake(pad, 22, w, 42)
                        action:@selector(tapUpload)];
    [self.content addSubview:self.uploadBtn];

    self.loadBtn = [self btn:@"⬇  Load from Cloud"
                       color:[UIColor colorWithRed:0.20 green:0.72 blue:0.44 alpha:1]
                       frame:CGRectMake(pad, 70, w, 42)
                      action:@selector(tapLoad)];
    [self.content addSubview:self.loadBtn];
}

- (UIButton *)btn:(NSString *)title color:(UIColor *)c
            frame:(CGRect)f action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f;
    b.backgroundColor    = c;
    b.layer.cornerRadius = 9;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:0.80 alpha:1]
            forState:UIControlStateHighlighted];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)refreshStatus {
    NSString *uuid = loadSessionUUID();
    self.statusLabel.text = uuid
        ? [NSString stringWithFormat:@"Session: %@…", [uuid substringToIndex:MIN(8, uuid.length)]]
        : @"No active session";
}

- (void)togglePanel {
    self.expanded = !self.expanded;
    if (self.expanded) {
        [self refreshStatus];
        self.content.hidden = NO;
        self.content.frame  = CGRectMake(0, kBH, kPW, kCH);
        [UIView animateWithDuration:0.22 delay:0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            CGRect fr = self.frame; fr.size.height = kBH + kCH; self.frame = fr;
            self.content.alpha = 1;
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.18 delay:0
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
            CGRect fr = self.frame; fr.size.height = kBH; self.frame = fr;
            self.content.alpha = 0;
        } completion:^(BOOL _){ self.content.hidden = YES; }];
    }
}

// ── Upload ────────────────────────────────────────────────────────────────────
- (void)tapUpload {
    NSString *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *all = [[NSFileManager defaultManager]
                    contentsOfDirectoryAtPath:docs error:nil] ?: @[];
    NSUInteger dc = 0;
    for (NSString *f in all)
        if ([f.pathExtension.lowercaseString isEqualToString:@"data"]) dc++;

    NSString *existing = loadSessionUUID();
    NSString *msg = [NSString stringWithFormat:
        @"Are you sure?\n\nWill upload:\n• PlayerPrefs (NSUserDefaults)\n• %lu .data file(s)\n%@",
        (unsigned long)dc,
        existing ? @"\n⚠ Overwrites existing session." : @""];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Upload Save"
                         message:msg
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Yes, Upload"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {

        UIView *parent = [self topVC].view ?: self.superview;
        SKProgressOverlay *overlay =
            [SKProgressOverlay showInView:parent title:@"Uploading save data…"];

        performUpload(overlay, ^(NSString *link, NSString *err) {
            [self refreshStatus];
            if (err) {
                [overlay finish:NO message:[NSString stringWithFormat:@"✗ %@", err]];
            } else {
                [UIPasteboard generalPasteboard].string = link;
                [overlay log:@"Link copied to clipboard!"];
                [overlay log:link];
                [overlay finish:YES message:@"Upload complete ✓"];
            }
        });
    }]];
    [[self topVC] presentViewController:alert animated:YES completion:nil];
}

// ── Load ──────────────────────────────────────────────────────────────────────
- (void)tapLoad {
    if (!loadSessionUUID().length) {
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:@"No Session"
                             message:@"No upload session found.\nPlease upload first."
                      preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK"
            style:UIAlertActionStyleDefault handler:nil]];
        [[self topVC] presentViewController:a animated:YES completion:nil];
        return;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Load Save"
                         message:@"Download your edited save data and apply it?\n\nThe cloud session will be deleted after loading."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Yes, Load"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {

        UIView *parent = [self topVC].view ?: self.superview;
        SKProgressOverlay *overlay =
            [SKProgressOverlay showInView:parent title:@"Loading save data…"];

        performLoad(overlay, ^(BOOL ok, NSString *msg) {
            [self refreshStatus];
            [overlay finish:ok message:msg];
        });
    }]];
    [[self topVC] presentViewController:alert animated:YES completion:nil];
}

// ── Drag ──────────────────────────────────────────────────────────────────────
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
