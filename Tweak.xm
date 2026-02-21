// tweak.xm — Soul Knight Save Manager v10
// iOS 14+ | Theos/Logos | ARC
// Changes: .data files are plain text — no base64 encode/decode anywhere.
//          Parallel file uploads, All/specific-UID selection, Open Link button.
//          v10.1: Batched NSUserDefaults restore (100 keys/tick) to prevent
//                 memory leak / crash when restoring large saves (~5000 keys).
//          v10.2: Fixed crash on Load — dispatch_after 1s delay replaced with
//                 dispatch_async (no artificial wait), nil-guarded ov calls,
//                 full error output instead of silent crash.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ── Config ────────────────────────────────────────────────────────────────────
#define API_BASE @"https://chillysilly.frfrnocap.men/isk.php"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Session file  (survives NSUserDefaults wipe)
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
// MARK: - URLSession  (generous timeouts)
// ─────────────────────────────────────────────────────────────────────────────
static NSURLSession *makeSession(void) {
    NSURLSessionConfiguration *c =
        [NSURLSessionConfiguration defaultSessionConfiguration];
    c.timeoutIntervalForRequest  = 120;
    c.timeoutIntervalForResource = 600;
    c.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    return [NSURLSession sessionWithConfiguration:c];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Multipart body builder
// ─────────────────────────────────────────────────────────────────────────────
typedef struct { NSMutableURLRequest *req; NSData *body; } MPRequest;

static MPRequest buildMP(NSDictionary<NSString*,NSString*> *fields,
                          NSString *fileField, NSString *filename, NSData *fileData) {
    NSString *boundary = [NSString stringWithFormat:@"----SKBound%08X%08X",
                          arc4random(), arc4random()];
    NSMutableData *body = [NSMutableData dataWithCapacity:
                           fileData ? fileData.length + 1024 : 1024];

    void (^addField)(NSString *, NSString *) = ^(NSString *n, NSString *v) {
        NSString *s = [NSString stringWithFormat:
            @"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n",
            boundary, n, v];
        [body appendData:[s dataUsingEncoding:NSUTF8StringEncoding]];
    };

    for (NSString *k in fields) addField(k, fields[k]);

    if (fileField && filename && fileData) {
        NSString *hdr = [NSString stringWithFormat:
            @"--%@\r\nContent-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n"
            @"Content-Type: text/plain; charset=utf-8\r\n\r\n",
            boundary, fileField, filename];
        [body appendData:[hdr dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:fileData];
        [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    }

    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary]
                      dataUsingEncoding:NSUTF8StringEncoding]];

    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:API_BASE]
           cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
       timeoutInterval:120];
    req.HTTPMethod = @"POST";
    [req setValue:[NSString stringWithFormat:
        @"multipart/form-data; boundary=%@", boundary]
       forHTTPHeaderField:@"Content-Type"];

    return (MPRequest){ req, body };
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - POST helper using uploadTask
// ─────────────────────────────────────────────────────────────────────────────
static void skPost(NSURLSession *session,
                   NSMutableURLRequest *req,
                   NSData *body,
                   void (^cb)(NSDictionary *json, NSError *err)) {
    [[session uploadTaskWithRequest:req
                           fromData:body
                  completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err) { cb(nil, err); return; }
            if (!data.length) {
                cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:@"Empty server response"}]);
                return;
            }
            NSError *je = nil;
            NSDictionary *j = [NSJSONSerialization
                JSONObjectWithData:data options:0 error:&je];
            if (je || !j) {
                NSString *raw = [[NSString alloc] initWithData:data
                    encoding:NSUTF8StringEncoding] ?: @"Non-JSON response";
                cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:raw}]);
                return;
            }
            if (j[@"error"]) {
                cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:j[@"error"]}]);
                return;
            }
            cb(j, nil);
        });
    }] resume];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKProgressOverlay
// ─────────────────────────────────────────────────────────────────────────────
@interface SKProgressOverlay : UIView
@property (nonatomic, strong) UILabel        *titleLabel;
@property (nonatomic, strong) UIProgressView *bar;
@property (nonatomic, strong) UILabel        *percentLabel;
@property (nonatomic, strong) UITextView     *logView;
@property (nonatomic, strong) UIButton       *closeBtn;
@property (nonatomic, strong) UIButton       *openLinkBtn;
@property (nonatomic, copy)   NSString       *uploadedLink;
+ (instancetype)showInView:(UIView *)parent title:(NSString *)title;
- (void)setProgress:(float)p label:(NSString *)label;
- (void)appendLog:(NSString *)msg;
- (void)finish:(BOOL)success message:(NSString *)msg link:(NSString *)link;
@end

@implementation SKProgressOverlay

+ (instancetype)showInView:(UIView *)parent title:(NSString *)title {
    SKProgressOverlay *o = [[SKProgressOverlay alloc] initWithFrame:parent.bounds];
    o.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [parent addSubview:o];
    [o setup:title];
    o.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ o.alpha = 1; }];
    return o;
}

- (void)setup:(NSString *)title {
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];

    UIView *card = [UIView new];
    card.backgroundColor     = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1];
    card.layer.cornerRadius  = 18;
    card.layer.shadowColor   = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.85;
    card.layer.shadowRadius  = 18;
    card.layer.shadowOffset  = CGSizeMake(0, 6);
    card.clipsToBounds       = NO;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:card];

    self.titleLabel = [UILabel new];
    self.titleLabel.text          = title;
    self.titleLabel.textColor     = [UIColor whiteColor];
    self.titleLabel.font          = [UIFont boldSystemFontOfSize:14];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.titleLabel];

    self.bar = [[UIProgressView alloc]
        initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.bar.trackTintColor    = [UIColor colorWithWhite:0.22 alpha:1];
    self.bar.progressTintColor = [UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];
    self.bar.layer.cornerRadius = 3;
    self.bar.clipsToBounds      = YES;
    self.bar.progress           = 0;
    self.bar.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.bar];

    self.percentLabel = [UILabel new];
    self.percentLabel.text          = @"0%";
    self.percentLabel.textColor     = [UIColor colorWithWhite:0.55 alpha:1];
    self.percentLabel.font          = [UIFont boldSystemFontOfSize:11];
    self.percentLabel.textAlignment = NSTextAlignmentRight;
    self.percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.percentLabel];

    self.logView = [UITextView new];
    self.logView.backgroundColor    = [UIColor colorWithWhite:0.04 alpha:1];
    self.logView.textColor          = [UIColor colorWithRed:0.42 green:0.98 blue:0.58 alpha:1];
    self.logView.font               = [UIFont fontWithName:@"Courier" size:10]
                                     ?: [UIFont systemFontOfSize:10];
    self.logView.editable           = NO;
    self.logView.selectable         = NO;
    self.logView.layer.cornerRadius = 8;
    self.logView.text               = @"";
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.logView];

    self.openLinkBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.openLinkBtn setTitle:@"🌐  Open Link in Browser" forState:UIControlStateNormal];
    [self.openLinkBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.openLinkBtn.titleLabel.font  = [UIFont boldSystemFontOfSize:13];
    self.openLinkBtn.backgroundColor  =
        [UIColor colorWithRed:0.16 green:0.52 blue:0.92 alpha:1];
    self.openLinkBtn.layer.cornerRadius = 9;
    self.openLinkBtn.hidden             = YES;
    self.openLinkBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.openLinkBtn addTarget:self action:@selector(openLink)
               forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.openLinkBtn];

    self.closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.closeBtn setTitle:@"Close" forState:UIControlStateNormal];
    [self.closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeBtn.titleLabel.font  = [UIFont boldSystemFontOfSize:13];
    self.closeBtn.backgroundColor  = [UIColor colorWithWhite:0.20 alpha:1];
    self.closeBtn.layer.cornerRadius = 9;
    self.closeBtn.hidden             = YES;
    self.closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.closeBtn addTarget:self action:@selector(dismiss)
             forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.closeBtn];

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:310],

        [self.titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        [self.bar.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:14],
        [self.bar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.bar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-72],
        [self.bar.heightAnchor constraintEqualToConstant:6],

        [self.percentLabel.centerYAnchor constraintEqualToAnchor:self.bar.centerYAnchor],
        [self.percentLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [self.percentLabel.widthAnchor constraintEqualToConstant:54],

        [self.logView.topAnchor constraintEqualToAnchor:self.bar.bottomAnchor constant:10],
        [self.logView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [self.logView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [self.logView.heightAnchor constraintEqualToConstant:170],

        [self.openLinkBtn.topAnchor constraintEqualToAnchor:self.logView.bottomAnchor constant:10],
        [self.openLinkBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [self.openLinkBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [self.openLinkBtn.heightAnchor constraintEqualToConstant:42],

        [self.closeBtn.topAnchor constraintEqualToAnchor:self.openLinkBtn.bottomAnchor constant:8],
        [self.closeBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [self.closeBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [self.closeBtn.heightAnchor constraintEqualToConstant:38],
        [card.bottomAnchor constraintEqualToAnchor:self.closeBtn.bottomAnchor constant:18],
    ]];
}

- (void)setProgress:(float)p label:(NSString *)label {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.bar setProgress:MAX(0, MIN(1, p)) animated:YES];
        self.percentLabel.text = label ?: [NSString stringWithFormat:@"%.0f%%", p * 100];
    });
}

- (void)appendLog:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *f = [NSDateFormatter new];
        f.dateFormat = @"HH:mm:ss";
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                          [f stringFromDate:[NSDate date]], msg];
        self.logView.text = [self.logView.text stringByAppendingString:line];
        if (self.logView.text.length)
            [self.logView scrollRangeToVisible:
             NSMakeRange(self.logView.text.length - 1, 1)];
    });
}

- (void)finish:(BOOL)ok message:(NSString *)msg link:(NSString *)link {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setProgress:1.0 label:ok ? @"✓ Done" : @"✗ Failed"];
        self.percentLabel.textColor = ok
            ? [UIColor colorWithRed:0.25 green:0.88 blue:0.45 alpha:1]
            : [UIColor colorWithRed:0.90 green:0.28 blue:0.28 alpha:1];
        if (msg.length) [self appendLog:msg];
        self.uploadedLink = link;
        if (link.length) self.openLinkBtn.hidden = NO;
        self.closeBtn.hidden = NO;
        self.closeBtn.backgroundColor = ok
            ? [UIColor colorWithWhite:0.22 alpha:1]
            : [UIColor colorWithRed:0.55 green:0.14 blue:0.14 alpha:1];
    });
}

- (void)openLink {
    if (!self.uploadedLink.length) return;
    NSURL *url = [NSURL URLWithString:self.uploadedLink];
    if (!url) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)dismiss {
    [UIView animateWithDuration:0.18 animations:^{ self.alpha = 0; }
                     completion:^(BOOL _){ [self removeFromSuperview]; }];
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Upload  (init session, then parallel file uploads)
// ─────────────────────────────────────────────────────────────────────────────
static void performUpload(NSArray<NSString *> *fileNames,
                          SKProgressOverlay *ov,
                          void (^done)(NSString *link, NSString *err)) {

    NSString *uuid    = deviceUUID();
    NSURLSession *ses = makeSession();
    NSString *docs    = NSSearchPathForDirectoriesInDomains(
                            NSDocumentDirectory, NSUserDomainMask, YES).firstObject;

    // ── Step 1: Serialize NSUserDefaults ─────────────────────────────────────
    [ov appendLog:@"Serialising NSUserDefaults…"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSDictionary *snap = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];

    NSError *pe = nil;
    NSData *pData = nil;

    @try {
        pData = [NSPropertyListSerialization
            dataWithPropertyList:snap
            format:NSPropertyListXMLFormat_v1_0
            options:0 error:&pe];
    } @catch (NSException *ex) {
        done(nil, [NSString stringWithFormat:@"Plist serialise exception: %@", ex.reason]);
        return;
    }

    if (pe || !pData) {
        done(nil, [NSString stringWithFormat:@"Plist serialise error: %@",
                   pe.localizedDescription ?: @"Unknown"]);
        return;
    }

    NSString *plistXML = [[NSString alloc] initWithData:pData encoding:NSUTF8StringEncoding];
    if (!plistXML) {
        done(nil, @"Plist UTF-8 conversion failed");
        return;
    }

    [ov appendLog:[NSString stringWithFormat:@"PlayerPrefs: %lu keys",
                   (unsigned long)snap.count]];
    [ov appendLog:[NSString stringWithFormat:@"Will upload %lu .data file(s)",
                   (unsigned long)fileNames.count]];

    // ── Step 2: POST init ─────────────────────────────────────────────────────
    [ov appendLog:@"Creating cloud session…"];
    MPRequest initMP = buildMP(
        @{@"action":@"upload", @"uuid":uuid, @"playerpref":plistXML},
        nil, nil, nil);
    [ov setProgress:0.05 label:@"5%"];

    skPost(ses, initMP.req, initMP.body, ^(NSDictionary *j, NSError *err) {
        if (err) { done(nil, [NSString stringWithFormat:@"Init failed: %@",
                              err.localizedDescription]); return; }

        NSString *link = j[@"link"] ?: [NSString stringWithFormat:
            @"https://chillysilly.frfrnocap.men/isk.php?view=%@", uuid];
        [ov appendLog:@"Session created ✓"];
        [ov appendLog:[NSString stringWithFormat:@"Link: %@", link]];
        saveSessionUUID(uuid);

        if (!fileNames.count) {
            done(link, nil);
            return;
        }

        // ── Step 3: Upload all .data files in parallel ────────────────────────
        [ov appendLog:@"Uploading .data files (parallel)…"];

        NSUInteger total         = fileNames.count;
        __block NSUInteger doneN = 0;
        __block NSUInteger failN = 0;
        dispatch_group_t group   = dispatch_group_create();

        for (NSString *fname in fileNames) {
            NSString *path = [docs stringByAppendingPathComponent:fname];
            NSString *textContent = [NSString stringWithContentsOfFile:path
                                                              encoding:NSUTF8StringEncoding
                                                                 error:nil];
            if (!textContent) {
                [ov appendLog:[NSString stringWithFormat:@"⚠ Skip %@ (unreadable)", fname]];
                @synchronized (fileNames) { doneN++; failN++; }
                float p = 0.1f + 0.88f * ((float)doneN / (float)total);
                [ov setProgress:p label:[NSString stringWithFormat:
                    @"%lu/%lu", (unsigned long)doneN, (unsigned long)total]];
                continue;
            }

            NSData *fdata = [textContent dataUsingEncoding:NSUTF8StringEncoding];
            [ov appendLog:[NSString stringWithFormat:@"↑ %@  (%lu chars)",
                           fname, (unsigned long)textContent.length]];

            dispatch_group_enter(group);

            MPRequest fmp = buildMP(
                @{@"action":@"upload_file", @"uuid":uuid},
                @"datafile", fname, fdata);

            skPost(ses, fmp.req, fmp.body, ^(NSDictionary *fj, NSError *ferr) {
                @synchronized (fileNames) { doneN++; }
                if (ferr) {
                    @synchronized (fileNames) { failN++; }
                    [ov appendLog:[NSString stringWithFormat:@"✗ %@: %@",
                                  fname, ferr.localizedDescription]];
                } else {
                    [ov appendLog:[NSString stringWithFormat:@"✓ %@", fname]];
                }
                float p = 0.10f + 0.88f * ((float)doneN / (float)total);
                [ov setProgress:p label:[NSString stringWithFormat:
                    @"%lu/%lu", (unsigned long)doneN, (unsigned long)total]];
                dispatch_group_leave(group);
            });
        }

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (failN > 0)
                [ov appendLog:[NSString stringWithFormat:
                    @"⚠ %lu file(s) failed, %lu succeeded",
                    (unsigned long)failN, (unsigned long)(total - failN)]];
            done(link, nil);
        });
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Batched NSUserDefaults writer
//
// FIX v10.2: Was using dispatch_after with 1.0s delay — with 5000 keys that
// meant ~50 seconds and the OS watchdog killed the app. Now uses dispatch_async
// (immediate next run-loop tick) which drains autorelease pools without waiting.
// Also nil-guards all ov calls so this can be used without a progress overlay.
// ─────────────────────────────────────────────────────────────────────────────
static const NSUInteger kUDWriteBatchSize = 100;

static void _applyUDBatch(NSUserDefaults *ud,
                           NSArray<NSString *> *keys,
                           NSDictionary *dict,
                           NSUInteger start,
                           NSUInteger total,
                           SKProgressOverlay * __weak ov,   // weak — overlay may be gone
                           void (^completion)(NSUInteger writtenCount)) {
    if (start >= total) {
        @try {
            [ud synchronize];
        } @catch (NSException *ex) {
            NSLog(@"[SKTools] ud synchronize exception: %@", ex.reason);
        }
        completion(total);
        return;
    }

    @autoreleasepool {
        NSUInteger end = MIN(start + kUDWriteBatchSize, total);
        for (NSUInteger i = start; i < end; i++) {
            NSString *k = keys[i];
            id val = dict[k];
            if (!k || !val) continue;   // guard nil keys/values → no crash
            @try {
                [ud setObject:val forKey:k];
            } @catch (NSException *ex) {
                NSLog(@"[SKTools] ud setObject exception for key %@: %@", k, ex.reason);
            }
        }

        // Log/progress every 500 keys (nil-guarded)
        if (ov && (start == 0 || (end % 500 == 0) || end == total)) {
            [ov appendLog:[NSString stringWithFormat:
                @"  PlayerPrefs %lu/%lu…", (unsigned long)end, (unsigned long)total]];
            [ov setProgress:0.10f + 0.28f * ((float)end / (float)total)
                      label:[NSString stringWithFormat:
                @"%lu/%lu", (unsigned long)end, (unsigned long)total]];
        }
    }

    // FIX: was dispatch_after 1.0s — replaced with dispatch_async so batches
    // run back-to-back on the next run-loop tick. No artificial delay, no watchdog kill.
    dispatch_async(dispatch_get_main_queue(), ^{
        _applyUDBatch(ud, keys, dict, start + kUDWriteBatchSize, total, ov, completion);
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Helper: write .data files from server response
//         Extracted to avoid duplicating the same block 3 times below.
// ─────────────────────────────────────────────────────────────────────────────
static void writeDataFiles(NSDictionary *dataMap,
                            SKProgressOverlay *ov,
                            void (^done)(NSUInteger appliedCount)) {
    NSString *docsPath = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSFileManager *fm = NSFileManager.defaultManager;

    if (![dataMap isKindOfClass:[NSDictionary class]] || !dataMap.count) {
        [ov appendLog:@"No .data files to write."];
        done(0);
        return;
    }

    NSUInteger fileTotal      = dataMap.count;
    __block NSUInteger fi     = 0;
    __block NSUInteger applied = 0;

    for (NSString *fname in dataMap) {
        id rawValue = dataMap[fname];

        if (![rawValue isKindOfClass:[NSString class]] || !((NSString *)rawValue).length) {
            [ov appendLog:[NSString stringWithFormat:@"⚠ %@ — empty or invalid, skipped", fname]];
            fi++;
            continue;
        }

        NSString *textContent = (NSString *)rawValue;
        NSString *safeName    = [fname lastPathComponent]; // no path traversal
        NSString *dst         = [docsPath stringByAppendingPathComponent:safeName];

        // Remove existing file (ignore error — it may not exist)
        [fm removeItemAtPath:dst error:nil];

        NSError *we = nil;
        BOOL ok = [textContent writeToFile:dst
                                atomically:YES
                                  encoding:NSUTF8StringEncoding
                                     error:&we];
        if (ok) {
            applied++;
            [ov appendLog:[NSString stringWithFormat:@"✓ %@  (%lu chars)",
                           safeName, (unsigned long)textContent.length]];
        } else {
            [ov appendLog:[NSString stringWithFormat:@"✗ %@ write failed: %@",
                           safeName, we.localizedDescription ?: @"Unknown error"]];
        }

        fi++;
        [ov setProgress:0.40f + 0.58f * ((float)fi / MAX(1.0f, (float)fileTotal))
                  label:[NSString stringWithFormat:
            @"%lu/%lu", (unsigned long)fi, (unsigned long)fileTotal]];
    }

    done(applied);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Load
// ─────────────────────────────────────────────────────────────────────────────
static void performLoad(SKProgressOverlay *ov,
                        void (^done)(BOOL ok, NSString *msg)) {
    NSString *uuid = loadSessionUUID();
    if (!uuid.length) { done(NO, @"No session found. Upload first."); return; }

    NSURLSession *ses = makeSession();
    [ov appendLog:[NSString stringWithFormat:@"Session: %@…",
                   [uuid substringToIndex:MIN(8u, (unsigned)uuid.length)]]];
    [ov appendLog:@"Requesting files from server…"];
    [ov setProgress:0.08 label:@"8%"];

    MPRequest mp = buildMP(@{@"action":@"load", @"uuid":uuid}, nil, nil, nil);
    skPost(ses, mp.req, mp.body, ^(NSDictionary *j, NSError *err) {

        // ── Network / server error ─────────────────────────────────────────
        if (err) {
            done(NO, [NSString stringWithFormat:@"✗ Load failed: %@",
                      err.localizedDescription]);
            return;
        }

        // ── Server says nothing was modified ──────────────────────────────
        if ([j[@"changed"] isEqual:@NO] || [j[@"changed"] isEqual:@0]) {
            clearSessionUUID();
            done(YES, @"ℹ Server reports no changes were made. Nothing applied.");
            return;
        }

        [ov setProgress:0.10 label:@"10%"];

        NSString *ppXML   = j[@"playerpref"];
        NSDictionary *dataMap = j[@"data"];

        // ── No PlayerPrefs → just write .data files ───────────────────────
        if (!ppXML.length) {
            [ov appendLog:@"No PlayerPrefs in response — writing .data files only."];
            writeDataFiles(dataMap, ov, ^(NSUInteger applied) {
                clearSessionUUID();
                done(YES, [NSString stringWithFormat:
                    @"✓ Loaded %lu file(s). Restart the game.", (unsigned long)applied]);
            });
            return;
        }

        // ── Parse PlayerPrefs plist ───────────────────────────────────────
        [ov appendLog:@"Parsing PlayerPrefs…"];
        NSError *pe    = nil;
        NSDictionary *ns = nil;

        @try {
            ns = [NSPropertyListSerialization
                propertyListWithData:[ppXML dataUsingEncoding:NSUTF8StringEncoding]
                             options:NSPropertyListMutableContainersAndLeaves
                              format:nil
                               error:&pe];
        } @catch (NSException *ex) {
            [ov appendLog:[NSString stringWithFormat:
                @"⚠ PlayerPrefs plist exception: %@", ex.reason]];
            ns = nil;
        }

        if (pe || ![ns isKindOfClass:[NSDictionary class]]) {
            // Log the exact error so the user can see what went wrong
            NSString *reason = pe.localizedDescription ?: @"Not a dictionary";
            [ov appendLog:[NSString stringWithFormat:
                @"⚠ PlayerPrefs parse failed: %@", reason]];
            [ov appendLog:@"Continuing with .data files only…"];

            writeDataFiles(dataMap, ov, ^(NSUInteger applied) {
                clearSessionUUID();
                done(applied > 0,
                    applied > 0
                    ? [NSString stringWithFormat:
                        @"⚠ PlayerPrefs failed (parse error), %lu file(s) applied. "
                        @"Restart the game.", (unsigned long)applied]
                    : @"✗ PlayerPrefs parse failed and no .data files were written.");
            });
            return;
        }

        // ── Apply PlayerPrefs in batches ──────────────────────────────────
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

        // Clear old keys inside an autorelease pool to avoid a spike
        @autoreleasepool {
            NSArray *oldKeys = [[ud dictionaryRepresentation] allKeys];
            [ov appendLog:[NSString stringWithFormat:
                @"Clearing %lu existing PlayerPrefs keys…", (unsigned long)oldKeys.count]];
            for (NSString *k in oldKeys) {
                if (k) [ud removeObjectForKey:k];
            }
        }

        NSArray<NSString *> *newKeys = [ns allKeys];
        NSUInteger total = newKeys.count;
        [ov appendLog:[NSString stringWithFormat:
            @"Writing %lu PlayerPrefs keys (%lu per batch)…",
            (unsigned long)total, (unsigned long)kUDWriteBatchSize]];

        // Batched write — dispatch_async between batches (no 1s delay → no watchdog kill)
        _applyUDBatch(ud, newKeys, ns, 0, total, ov, ^(NSUInteger written) {
            [ov appendLog:[NSString stringWithFormat:
                @"PlayerPrefs ✓ (%lu keys applied)", (unsigned long)written]];

            // Write .data files after PlayerPrefs completes
            writeDataFiles(dataMap, ov, ^(NSUInteger filesApplied) {
                clearSessionUUID();
                NSUInteger totalApplied = 1 /* PlayerPrefs */ + filesApplied;
                done(YES, [NSString stringWithFormat:
                    @"✓ Loaded %lu item(s). Restart the game.",
                    (unsigned long)totalApplied]);
            });
        });
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
    self.layer.shadowOpacity = 0.82;
    self.layer.shadowRadius  = 9;
    self.layer.shadowOffset  = CGSizeMake(0, 3);
    self.layer.zPosition     = 9999;
    [self buildBar];
    [self buildContent];
    [self addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(onPan:)]];
    return self;
}

- (void)buildBar {
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(kPW/2-20, 8, 40, 3)];
    h.backgroundColor    = [UIColor colorWithWhite:0.45 alpha:0.5];
    h.layer.cornerRadius = 1.5;
    [self addSubview:h];

    UILabel *t = [UILabel new];
    t.text = @"⚙  SK Save Manager";
    t.textColor = [UIColor colorWithWhite:0.82 alpha:1];
    t.font = [UIFont boldSystemFontOfSize:12];
    t.textAlignment = NSTextAlignmentCenter;
    t.frame = CGRectMake(0, 14, kPW, 22);
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
    self.statusLabel.textColor     = [UIColor colorWithWhite:0.44 alpha:1];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.content addSubview:self.statusLabel];
    [self refreshStatus];

    self.uploadBtn = [self btn:@"⬆  Upload to Cloud"
                         color:[UIColor colorWithRed:0.14 green:0.56 blue:0.92 alpha:1]
                         frame:CGRectMake(pad, 22, w, 42)
                        action:@selector(tapUpload)];
    [self.content addSubview:self.uploadBtn];

    self.loadBtn = [self btn:@"⬇  Load from Cloud"
                       color:[UIColor colorWithRed:0.18 green:0.70 blue:0.42 alpha:1]
                       frame:CGRectMake(pad, 70, w, 42)
                      action:@selector(tapLoad)];
    [self.content addSubview:self.loadBtn];
}

- (UIButton *)btn:(NSString *)t color:(UIColor *)c frame:(CGRect)f action:(SEL)s {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f; b.backgroundColor = c; b.layer.cornerRadius = 9;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:0.80 alpha:1] forState:UIControlStateHighlighted];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)refreshStatus {
    NSString *uuid = loadSessionUUID();
    self.statusLabel.text = uuid
        ? [NSString stringWithFormat:@"Session: %@…",
           [uuid substringToIndex:MIN(8u, (unsigned)uuid.length)]]
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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Upload flow
// ─────────────────────────────────────────────────────────────────────────────
- (void)tapUpload {
    NSString *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *all = [[NSFileManager defaultManager]
                    contentsOfDirectoryAtPath:docs error:nil] ?: @[];
    NSMutableArray<NSString*> *dataFiles = [NSMutableArray new];
    for (NSString *f in all)
        if ([f.pathExtension.lowercaseString isEqualToString:@"data"])
            [dataFiles addObject:f];

    NSString *existing = loadSessionUUID();

    UIAlertController *choice = [UIAlertController
        alertControllerWithTitle:@"Select files to upload"
                         message:[NSString stringWithFormat:
            @"Found %lu .data file(s)\n%@",
            (unsigned long)dataFiles.count,
            existing ? @"⚠ Existing session will be overwritten." : @""]
                  preferredStyle:UIAlertControllerStyleAlert];

    [choice addAction:[UIAlertAction
        actionWithTitle:[NSString stringWithFormat:@"Upload All (%lu files)",
                         (unsigned long)dataFiles.count]
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) { [self confirmAndUpload:dataFiles]; }]];

    [choice addAction:[UIAlertAction
        actionWithTitle:@"Specific UID…"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) { [self askUIDThenUpload:dataFiles]; }]];

    [choice addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];

    [[self topVC] presentViewController:choice animated:YES completion:nil];
}

- (void)askUIDThenUpload:(NSArray<NSString*> *)allFiles {
    UIAlertController *input = [UIAlertController
        alertControllerWithTitle:@"Enter UID"
                         message:@"Only .data files containing this UID in their filename will be uploaded."
                  preferredStyle:UIAlertControllerStyleAlert];

    [input addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder     = @"e.g. 211062956";
        tf.keyboardType    = UIKeyboardTypeNumberPad;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [input addAction:[UIAlertAction
        actionWithTitle:@"Upload"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            NSString *uid = [input.textFields.firstObject.text
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!uid.length) {
                [self showAlert:@"No UID entered" message:@"Please enter a UID."]; return;
            }
            NSMutableArray<NSString*> *filtered = [NSMutableArray new];
            for (NSString *f in allFiles)
                if ([f containsString:uid]) [filtered addObject:f];
            if (!filtered.count) {
                [self showAlert:@"No files found"
                        message:[NSString stringWithFormat:
                    @"No .data file contains UID \"%@\" in its name.", uid]]; return;
            }
            [self confirmAndUpload:filtered];
        }]];

    [input addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];

    [[self topVC] presentViewController:input animated:YES completion:nil];
}

- (void)confirmAndUpload:(NSArray<NSString*> *)files {
    NSString *msg = [NSString stringWithFormat:
        @"Are you sure?\n\nWill upload:\n• PlayerPrefs (NSUserDefaults)\n• %lu .data file(s):\n%@",
        (unsigned long)files.count,
        files.count <= 6
            ? [files componentsJoinedByString:@"\n"]
            : [[files subarrayWithRange:NSMakeRange(0, 6)] componentsJoinedByString:@"\n"]];

    UIAlertController *confirm = [UIAlertController
        alertControllerWithTitle:@"Confirm Upload"
                         message:msg
                  preferredStyle:UIAlertControllerStyleAlert];

    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];

    [confirm addAction:[UIAlertAction
        actionWithTitle:@"Yes, Upload"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            UIView *parent = [self topVC].view ?: self.superview;
            SKProgressOverlay *ov = [SKProgressOverlay
                showInView:parent title:@"Uploading save data…"];
            performUpload(files, ov, ^(NSString *link, NSString *err) {
                [self refreshStatus];
                if (err) {
                    [ov finish:NO message:[NSString stringWithFormat:@"✗ %@", err] link:nil];
                } else {
                    [UIPasteboard generalPasteboard].string = link;
                    [ov appendLog:@"Link copied to clipboard."];
                    [ov finish:YES message:@"Upload complete ✓" link:link];
                }
            });
        }]];

    [[self topVC] presentViewController:confirm animated:YES completion:nil];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Load
// ─────────────────────────────────────────────────────────────────────────────
- (void)tapLoad {
    if (!loadSessionUUID().length) {
        [self showAlert:@"No Session" message:@"No upload session found. Upload first."];
        return;
    }
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Load Save"
                         message:@"Download edited save data and apply it?\n\nCloud session is deleted after loading."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Yes, Load"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIView *parent = [self topVC].view ?: self.superview;
        SKProgressOverlay *ov = [SKProgressOverlay
            showInView:parent title:@"Loading save data…"];
        performLoad(ov, ^(BOOL ok, NSString *msg) {
            [self refreshStatus];
            [ov finish:ok message:msg link:nil];
        });
    }]];
    [[self topVC] presentViewController:alert animated:YES completion:nil];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Helpers
// ─────────────────────────────────────────────────────────────────────────────
- (void)showAlert:(NSString *)title message:(NSString *)msg {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:title message:msg
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK"
        style:UIAlertActionStyleDefault handler:nil]];
    [[self topVC] presentViewController:a animated:YES completion:nil];
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
