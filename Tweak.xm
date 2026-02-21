// tweak.xm — Soul Knight Save Manager v10
// iOS 14+ | Theos/Logos | MRC
// v10.2: Fixed crash on Load, nil-guarded ov calls, error output.
// v10.3: Settings menu — Auto Rij, Auto Detect UID, Auto Close.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ── Config ────────────────────────────────────────────────────────────────────
#define API_BASE @"https://chillysilly.frfrnocap.men/isk.php"

// ── Settings keys ─────────────────────────────────────────────────────────────
#define kSettingsPath [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/SKToolsSettings.plist"]
#define kKeyAutoRij       @"AutoRij"
#define kKeyAutoDetectUID @"AutoDetectUID"
#define kKeyAutoClose     @"AutoClose"

static NSMutableDictionary *gSettings = nil;

static void loadSettings(void) {
    if (!gSettings) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kSettingsPath];
        gSettings = d ? [d mutableCopy] : [NSMutableDictionary new];
    }
}
static void saveSettings(void) {
    [gSettings writeToFile:kSettingsPath atomically:YES];
}
static BOOL getSetting(NSString *key) {
    loadSettings();
    return [gSettings[key] boolValue];
}
static void setSetting(NSString *key, BOOL val) {
    loadSettings();
    gSettings[key] = @(val);
    saveSettings();
}

// ── Auto Detect UID: parse PlayerId from SdkStateCache#1 ─────────────────────
static NSString *detectUIDFromPrefs(void) {
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSString *cache = [[NSUserDefaults standardUserDefaults]
                       stringForKey:@"SdkStateCache#1"];
    if (!cache.length) return nil;
    NSError *reErr = nil;
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"\"PlayerId\"\\s*:\\s*(\\d+)"
                             options:0 error:&reErr];
    if (reErr || !re) return nil;
    NSTextCheckingResult *m = [re firstMatchInString:cache options:0
                                               range:NSMakeRange(0, cache.length)];
    if (!m || m.numberOfRanges < 2) return nil;
    return [cache substringWithRange:[m rangeAtIndex:1]];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Session file
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
// MARK: - URLSession
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
// MARK: - POST helper
// ─────────────────────────────────────────────────────────────────────────────
static void skPost(NSURLSession *session,
                   NSMutableURLRequest *req,
                   NSData *body,
                   void (^cb)(NSDictionary *json, NSError *err)) {
    [[session uploadTaskWithRequest:req fromData:body
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
// MARK: - Auto Rij: regex replace OpenRijTest_{uid} integer 1 → 0
// ─────────────────────────────────────────────────────────────────────────────
static NSString *applyAutoRij(NSString *plistXML) {
    if (!plistXML.length) return plistXML;
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:
            @"(<key>OpenRijTest_\\d+</key>\\s*<integer>)1(</integer>)"
                             options:0 error:&err];
    if (err || !re) {
        NSLog(@"[SKTools] AutoRij regex error: %@", err.localizedDescription);
        return plistXML;
    }
    return [re stringByReplacingMatchesInString:plistXML
                                        options:0
                                          range:NSMakeRange(0, plistXML.length)
                                   withTemplate:@"$10$2"];
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
    o.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
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

    self.bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
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
    self.openLinkBtn.backgroundColor  = [UIColor colorWithRed:0.16 green:0.52 blue:0.92 alpha:1];
    self.openLinkBtn.layer.cornerRadius = 9;
    self.openLinkBtn.hidden             = YES;
    self.openLinkBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.openLinkBtn addTarget:self action:@selector(openLink)
               forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.openLinkBtn];

    self.closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.closeBtn setTitle:@"Close" forState:UIControlStateNormal];
    [self.closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeBtn.titleLabel.font    = [UIFont boldSystemFontOfSize:13];
    self.closeBtn.backgroundColor    = [UIColor colorWithWhite:0.20 alpha:1];
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
                     completion:^(BOOL f){ [self removeFromSuperview]; }];
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Upload
// ─────────────────────────────────────────────────────────────────────────────
static void performUpload(NSArray<NSString *> *fileNames,
                          SKProgressOverlay *ov,
                          void (^done)(NSString *link, NSString *err)) {
    NSString *uuid    = deviceUUID();
    NSURLSession *ses = makeSession();
    NSString *docs    = NSSearchPathForDirectoriesInDomains(
                            NSDocumentDirectory, NSUserDomainMask, YES).firstObject;

    [ov appendLog:@"Serialising NSUserDefaults…"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSDictionary *snap = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];

    NSError *pe = nil;
    NSData *pData = nil;
    @try {
        pData = [NSPropertyListSerialization
            dataWithPropertyList:snap format:NSPropertyListXMLFormat_v1_0
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
    if (!plistXML) { done(nil, @"Plist UTF-8 conversion failed"); return; }

    // Auto Rij
    if (getSetting(kKeyAutoRij)) {
        NSString *patched = applyAutoRij(plistXML);
        if (![patched isEqualToString:plistXML]) {
            [ov appendLog:@"Auto Rij: patched OpenRijTest entries → 0"];
            plistXML = patched;
        } else {
            [ov appendLog:@"Auto Rij: no OpenRijTest entries found"];
        }
    }

    [ov appendLog:[NSString stringWithFormat:@"PlayerPrefs: %lu keys", (unsigned long)snap.count]];
    [ov appendLog:[NSString stringWithFormat:@"Will upload %lu .data file(s)", (unsigned long)fileNames.count]];
    [ov appendLog:@"Creating cloud session…"];
    [ov setProgress:0.05 label:@"5%"];

    MPRequest initMP = buildMP(
        @{@"action":@"upload", @"uuid":uuid, @"playerpref":plistXML},
        nil, nil, nil);

    skPost(ses, initMP.req, initMP.body, ^(NSDictionary *j, NSError *err) {
        if (err) { done(nil, [NSString stringWithFormat:@"Init failed: %@",
                              err.localizedDescription]); return; }
        NSString *link = j[@"link"] ?: [NSString stringWithFormat:
            @"https://chillysilly.frfrnocap.men/isk.php?view=%@", uuid];
        [ov appendLog:@"Session created ✓"];
        [ov appendLog:[NSString stringWithFormat:@"Link: %@", link]];
        saveSessionUUID(uuid);
        if (!fileNames.count) { done(link, nil); return; }

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
                [ov setProgress:p label:[NSString stringWithFormat:@"%lu/%lu",
                    (unsigned long)doneN, (unsigned long)total]];
                continue;
            }
            NSData *fdata = [textContent dataUsingEncoding:NSUTF8StringEncoding];
            [ov appendLog:[NSString stringWithFormat:@"↑ %@  (%lu chars)",
                           fname, (unsigned long)textContent.length]];
            dispatch_group_enter(group);
            MPRequest fmp = buildMP(@{@"action":@"upload_file", @"uuid":uuid},
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
                [ov setProgress:p label:[NSString stringWithFormat:@"%lu/%lu",
                    (unsigned long)doneN, (unsigned long)total]];
                dispatch_group_leave(group);
            });
        }

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (failN > 0)
                [ov appendLog:[NSString stringWithFormat:@"⚠ %lu failed, %lu succeeded",
                               (unsigned long)failN, (unsigned long)(total - failN)]];
            done(link, nil);
        });
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Batched NSUserDefaults writer
// ─────────────────────────────────────────────────────────────────────────────
static const NSUInteger kUDWriteBatchSize = 100;

static void _applyUDBatch(NSUserDefaults *ud,
                           NSArray<NSString *> *keys,
                           NSDictionary *dict,
                           NSUInteger start,
                           NSUInteger total,
                           SKProgressOverlay *ov,
                           void (^completion)(NSUInteger writtenCount)) {
    if (start >= total) {
        @try { [ud synchronize]; } @catch (NSException *ex) {
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
            if (!k || !val) continue;
            @try { [ud setObject:val forKey:k]; } @catch (NSException *ex) {
                NSLog(@"[SKTools] ud setObject exception key %@: %@", k, ex.reason);
            }
        }
        if (ov && (start == 0 || (end % 500 == 0) || end == total)) {
            [ov appendLog:[NSString stringWithFormat:
                @"  PlayerPrefs %lu/%lu…", (unsigned long)end, (unsigned long)total]];
            [ov setProgress:0.10f + 0.28f * ((float)end / (float)total)
                      label:[NSString stringWithFormat:@"%lu/%lu",
                             (unsigned long)end, (unsigned long)total]];
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        _applyUDBatch(ud, keys, dict, start + kUDWriteBatchSize, total, ov, completion);
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Write .data files helper
// ─────────────────────────────────────────────────────────────────────────────
static void writeDataFiles(NSDictionary *dataMap,
                            SKProgressOverlay *ov,
                            void (^done)(NSUInteger appliedCount)) {
    NSString *docsPath = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![dataMap isKindOfClass:[NSDictionary class]] || !dataMap.count) {
        if (ov) [ov appendLog:@"No .data files to write."];
        done(0); return;
    }
    NSUInteger fileTotal       = dataMap.count;
    __block NSUInteger fi      = 0;
    __block NSUInteger applied = 0;
    for (NSString *fname in dataMap) {
        id rawValue = dataMap[fname];
        if (![rawValue isKindOfClass:[NSString class]] || !((NSString *)rawValue).length) {
            if (ov) [ov appendLog:[NSString stringWithFormat:
                @"⚠ %@ — empty or invalid, skipped", fname]];
            fi++; continue;
        }
        NSString *textContent = (NSString *)rawValue;
        NSString *safeName    = [fname lastPathComponent];
        NSString *dst         = [docsPath stringByAppendingPathComponent:safeName];
        [fm removeItemAtPath:dst error:nil];
        NSError *we = nil;
        BOOL ok = [textContent writeToFile:dst atomically:YES
                                  encoding:NSUTF8StringEncoding error:&we];
        if (ok) {
            applied++;
            if (ov) [ov appendLog:[NSString stringWithFormat:@"✓ %@  (%lu chars)",
                           safeName, (unsigned long)textContent.length]];
        } else {
            if (ov) [ov appendLog:[NSString stringWithFormat:@"✗ %@ write failed: %@",
                           safeName, we.localizedDescription ?: @"Unknown"]];
        }
        fi++;
        if (ov) [ov setProgress:0.40f + 0.58f * ((float)fi / MAX(1.0f, (float)fileTotal))
                  label:[NSString stringWithFormat:@"%lu/%lu",
                         (unsigned long)fi, (unsigned long)fileTotal]];
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
        if (err) {
            done(NO, [NSString stringWithFormat:@"✗ Load failed: %@",
                      err.localizedDescription]); return;
        }
        if ([j[@"changed"] isEqual:@NO] || [j[@"changed"] isEqual:@0]) {
            clearSessionUUID();
            done(YES, @"ℹ Server reports no changes. Nothing applied."); return;
        }
        [ov setProgress:0.10 label:@"10%"];

        NSString *ppXML       = j[@"playerpref"];
        NSDictionary *dataMap = j[@"data"];

        void (^afterLoad)(NSUInteger) = ^(NSUInteger filesApplied) {
            clearSessionUUID();
            if (getSetting(kKeyAutoClose)) {
                [ov appendLog:@"Auto Close: exiting app in 1s…"];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{ exit(0); });
            }
            done(YES, [NSString stringWithFormat:
                @"✓ Loaded %lu item(s). Restart the game.", (unsigned long)filesApplied]);
        };

        if (!ppXML.length) {
            [ov appendLog:@"No PlayerPrefs in response — writing .data files only."];
            writeDataFiles(dataMap, ov, ^(NSUInteger applied) { afterLoad(applied); });
            return;
        }

        [ov appendLog:@"Parsing PlayerPrefs…"];
        NSError *pe = nil;
        NSDictionary *ns = nil;
        @try {
            ns = [NSPropertyListSerialization
                propertyListWithData:[ppXML dataUsingEncoding:NSUTF8StringEncoding]
                             options:NSPropertyListMutableContainersAndLeaves
                              format:nil error:&pe];
        } @catch (NSException *ex) {
            [ov appendLog:[NSString stringWithFormat:
                @"⚠ PlayerPrefs plist exception: %@", ex.reason]];
            ns = nil;
        }

        if (pe || ![ns isKindOfClass:[NSDictionary class]]) {
            [ov appendLog:[NSString stringWithFormat:@"⚠ PlayerPrefs parse failed: %@",
                           pe.localizedDescription ?: @"Not a dictionary"]];
            [ov appendLog:@"Continuing with .data files only…"];
            writeDataFiles(dataMap, ov, ^(NSUInteger applied) {
                clearSessionUUID();
                if (getSetting(kKeyAutoClose)) {
                    [ov appendLog:@"Auto Close: exiting app in 1s…"];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{ exit(0); });
                }
                done(applied > 0,
                    applied > 0
                    ? [NSString stringWithFormat:
                        @"⚠ PlayerPrefs parse failed, %lu file(s) applied. Restart.",
                        (unsigned long)applied]
                    : @"✗ PlayerPrefs parse failed and no .data files were written.");
            });
            return;
        }

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        @autoreleasepool {
            NSArray *oldKeys = [[ud dictionaryRepresentation] allKeys];
            [ov appendLog:[NSString stringWithFormat:@"Clearing %lu existing keys…",
                           (unsigned long)oldKeys.count]];
            for (NSString *k in oldKeys) { if (k) [ud removeObjectForKey:k]; }
        }

        NSArray<NSString *> *newKeys = [ns allKeys];
        NSUInteger total = newKeys.count;
        [ov appendLog:[NSString stringWithFormat:
            @"Writing %lu PlayerPrefs keys (%lu per batch)…",
            (unsigned long)total, (unsigned long)kUDWriteBatchSize]];

        _applyUDBatch(ud, newKeys, ns, 0, total, ov, ^(NSUInteger written) {
            [ov appendLog:[NSString stringWithFormat:
                @"PlayerPrefs ✓ (%lu keys applied)", (unsigned long)written]];
            writeDataFiles(dataMap, ov, ^(NSUInteger filesApplied) {
                afterLoad(1 + filesApplied);
            });
        });
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKSettingsMenu
// ─────────────────────────────────────────────────────────────────────────────
@interface SKSettingsMenu : UIView
@property (nonatomic, strong) UILabel *uidLabel;
- (void)refreshUID;
@end

@implementation SKSettingsMenu

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    [self buildUI];
    return self;
}

- (void)buildUI {
    self.backgroundColor     = [UIColor colorWithRed:0.07 green:0.07 blue:0.11 alpha:0.98];
    self.layer.cornerRadius  = 16;
    self.layer.shadowColor   = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.9;
    self.layer.shadowRadius  = 16;
    self.layer.shadowOffset  = CGSizeMake(0, 4);
    self.clipsToBounds       = NO;
    self.translatesAutoresizingMaskIntoConstraints = NO;

    // Title
    UILabel *title = [UILabel new];
    title.text          = @"⚙  Settings";
    title.textColor     = [UIColor whiteColor];
    title.font          = [UIFont boldSystemFontOfSize:14];
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:title];

    // Divider
    UIView *div = [UIView new];
    div.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1];
    div.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:div];

    // Setting rows
    UIView *row1 = [self makeRowForKey:kKeyAutoRij
                                  icon:@"🔴"
                                 label:@"Auto Rij"
                                  desc:@"Sets all OpenRijTest entries to 0 before upload"];
    UIView *row2 = [self makeRowForKey:kKeyAutoDetectUID
                                  icon:@"🔍"
                                 label:@"Auto Detect UID"
                                  desc:@"Reads your Player ID from save data automatically"];
    UIView *row3 = [self makeRowForKey:kKeyAutoClose
                                  icon:@"🚪"
                                 label:@"Auto Close"
                                  desc:@"Closes the app after loading save from cloud"];

    // UID display label
    self.uidLabel = [UILabel new];
    self.uidLabel.font          = [UIFont fontWithName:@"Courier" size:10]
                                  ?: [UIFont systemFontOfSize:10];
    self.uidLabel.textColor     = [UIColor colorWithRed:0.35 green:0.80 blue:1.0 alpha:1];
    self.uidLabel.textAlignment = NSTextAlignmentCenter;
    self.uidLabel.numberOfLines = 1;
    self.uidLabel.hidden        = YES;
    self.uidLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.uidLabel];

    // Footer
    UILabel *footer = [UILabel new];
    footer.text          = @"Dylib By Mochi  ·  Version: 2.1  ·  Build: 271.ef2ca7";
    footer.textColor     = [UIColor colorWithWhite:0.26 alpha:1];
    footer.font          = [UIFont systemFontOfSize:9];
    footer.textAlignment = NSTextAlignmentCenter;
    footer.numberOfLines = 1;
    footer.adjustsFontSizeToFitWidth = YES;
    footer.minimumScaleFactor = 0.7;
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:footer];

    [NSLayoutConstraint activateConstraints:@[
        [self.widthAnchor constraintEqualToConstant:264],

        [title.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
        [title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],

        [div.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
        [div.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [div.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [div.heightAnchor constraintEqualToConstant:1],

        [row1.topAnchor constraintEqualToAnchor:div.bottomAnchor constant:4],
        [row1.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [row1.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [row2.topAnchor constraintEqualToAnchor:row1.bottomAnchor],
        [row2.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [row2.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [row3.topAnchor constraintEqualToAnchor:row2.bottomAnchor],
        [row3.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [row3.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [self.uidLabel.topAnchor constraintEqualToAnchor:row3.bottomAnchor constant:6],
        [self.uidLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [self.uidLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],

        [footer.topAnchor constraintEqualToAnchor:self.uidLabel.bottomAnchor constant:10],
        [footer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [footer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [self.bottomAnchor constraintEqualToAnchor:footer.bottomAnchor constant:12],
    ]];

    [self refreshUID];
}

- (UIView *)makeRowForKey:(NSString *)key icon:(NSString *)icon
                    label:(NSString *)labelText desc:(NSString *)descText {
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *iconLbl = [UILabel new];
    iconLbl.text = icon;
    iconLbl.font = [UIFont systemFontOfSize:17];
    iconLbl.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:iconLbl];

    UILabel *nameLbl = [UILabel new];
    nameLbl.text      = labelText;
    nameLbl.textColor = [UIColor colorWithWhite:0.90 alpha:1];
    nameLbl.font      = [UIFont boldSystemFontOfSize:12];
    nameLbl.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:nameLbl];

    UILabel *descLbl = [UILabel new];
    descLbl.text          = descText;
    descLbl.textColor     = [UIColor colorWithWhite:0.40 alpha:1];
    descLbl.font          = [UIFont systemFontOfSize:10];
    descLbl.numberOfLines = 2;
    descLbl.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:descLbl];

    // Toggle button — uses accessibilityIdentifier to store settings key
    UIButton *toggle = [UIButton buttonWithType:UIButtonTypeCustom];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    toggle.layer.cornerRadius = 12;
    toggle.layer.borderWidth  = 1.5;
    toggle.clipsToBounds      = YES;
    toggle.accessibilityIdentifier = key;
    [self applyToggleState:toggle on:getSetting(key) animated:NO];
    [toggle addTarget:self action:@selector(toggleTapped:)
     forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:toggle];

    // Row separator
    UIView *sep = [UIView new];
    sep.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:sep];

    [NSLayoutConstraint activateConstraints:@[
        [iconLbl.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14],
        [iconLbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [iconLbl.widthAnchor constraintEqualToConstant:22],

        [toggle.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14],
        [toggle.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [toggle.widthAnchor constraintEqualToConstant:44],
        [toggle.heightAnchor constraintEqualToConstant:24],

        [nameLbl.topAnchor constraintEqualToAnchor:row.topAnchor constant:10],
        [nameLbl.leadingAnchor constraintEqualToAnchor:iconLbl.trailingAnchor constant:10],
        [nameLbl.trailingAnchor constraintEqualToAnchor:toggle.leadingAnchor constant:-6],

        [descLbl.topAnchor constraintEqualToAnchor:nameLbl.bottomAnchor constant:2],
        [descLbl.leadingAnchor constraintEqualToAnchor:nameLbl.leadingAnchor],
        [descLbl.trailingAnchor constraintEqualToAnchor:toggle.leadingAnchor constant:-6],
        [descLbl.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-10],

        [sep.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [sep.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12],
        [sep.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [sep.heightAnchor constraintEqualToConstant:1],
    ]];

    [self addSubview:row];
    return row;
}

- (void)applyToggleState:(UIButton *)btn on:(BOOL)on animated:(BOOL)anim {
    UIColor *onBg    = [UIColor colorWithRed:0.12 green:0.76 blue:0.38 alpha:1];
    UIColor *offBg   = [UIColor colorWithWhite:0.20 alpha:1];
    UIColor *onBdr   = [UIColor colorWithRed:0.08 green:0.58 blue:0.28 alpha:1];
    UIColor *offBdr  = [UIColor colorWithWhite:0.30 alpha:1];
    UIColor *onTxt   = [UIColor whiteColor];
    UIColor *offTxt  = [UIColor colorWithWhite:0.42 alpha:1];

    void (^apply)(void) = ^{
        btn.backgroundColor = on ? onBg : offBg;
        btn.layer.borderColor = (on ? onBdr : offBdr).CGColor;
        [btn setTitle:on ? @"ON" : @"OFF" forState:UIControlStateNormal];
        [btn setTitleColor:on ? onTxt : offTxt forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:10];
    };
    anim ? [UIView animateWithDuration:0.18 animations:apply] : apply();
}

- (void)toggleTapped:(UIButton *)btn {
    NSString *key = btn.accessibilityIdentifier;
    BOOL newVal = !getSetting(key);
    setSetting(key, newVal);
    [self applyToggleState:btn on:newVal animated:YES];

    // Flicker
    btn.alpha = 0.45;
    [UIView animateWithDuration:0.15 animations:^{ btn.alpha = 1.0; }];

    if ([key isEqualToString:kKeyAutoDetectUID]) {
        [UIView animateWithDuration:0.2 animations:^{ [self refreshUID]; }];
    }
}

- (void)refreshUID {
    if (getSetting(kKeyAutoDetectUID)) {
        NSString *uid = detectUIDFromPrefs();
        self.uidLabel.text   = uid
            ? [NSString stringWithFormat:@"UID: %@", uid]
            : @"UID: not found";
        self.uidLabel.hidden = NO;
    } else {
        self.uidLabel.hidden = YES;
        self.uidLabel.text   = @"";
    }
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKPanel
// ─────────────────────────────────────────────────────────────────────────────
static const CGFloat kPW = 258;
static const CGFloat kBH = 46;
static const CGFloat kCH = 122;

@interface SKPanel : UIView
@property (nonatomic, strong) UIView         *content;
@property (nonatomic, strong) UILabel        *statusLabel;
@property (nonatomic, strong) UIButton       *uploadBtn;
@property (nonatomic, strong) UIButton       *loadBtn;
@property (nonatomic, assign) BOOL            expanded;
@property (nonatomic, strong) SKSettingsMenu *settingsMenu;
@property (nonatomic, assign) BOOL            settingsVisible;
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
    t.text      = @"⚙  SK Save Manager";
    t.textColor = [UIColor colorWithWhite:0.82 alpha:1];
    t.font      = [UIFont boldSystemFontOfSize:12];
    t.textAlignment = NSTextAlignmentCenter;
    t.frame = CGRectMake(0, 14, kPW - 38, 22);
    t.userInteractionEnabled = NO;
    [self addSubview:t];

    // Gear / settings button top-right
    UIButton *gear = [UIButton buttonWithType:UIButtonTypeCustom];
    gear.frame = CGRectMake(kPW - 36, 9, 28, 28);
    [gear setTitle:@"☰" forState:UIControlStateNormal];
    gear.titleLabel.font = [UIFont systemFontOfSize:16];
    [gear setTitleColor:[UIColor colorWithWhite:0.52 alpha:1] forState:UIControlStateNormal];
    [gear setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    [gear addTarget:self action:@selector(tapSettings)
   forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:gear];

    // Tap zone for expand/collapse (avoid gear button area)
    UIView *tz = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPW - 40, kBH)];
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
    [self hideSettings];
    if (self.expanded) {
        [self refreshStatus];
        self.content.hidden = NO;
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
        } completion:^(BOOL f){ self.content.hidden = YES; }];
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Settings menu show/hide
// ─────────────────────────────────────────────────────────────────────────────
- (void)tapSettings {
    self.settingsVisible ? [self hideSettings] : [self showSettings];
}

- (void)showSettings {
    if (self.settingsVisible) return;
    self.settingsVisible = YES;

    if (!self.settingsMenu) {
        self.settingsMenu = [SKSettingsMenu new];
        self.settingsMenu.layer.zPosition = 10000;
    }
    [self.settingsMenu refreshUID];

    UIView *parent = self.superview;
    [parent addSubview:self.settingsMenu];

    // Anchor left of panel, aligned to panel top
    [NSLayoutConstraint activateConstraints:@[
        [self.settingsMenu.trailingAnchor constraintEqualToAnchor:self.leadingAnchor constant:-8],
        [self.settingsMenu.topAnchor constraintEqualToAnchor:self.topAnchor],
    ]];

    self.settingsMenu.alpha     = 0;
    self.settingsMenu.transform = CGAffineTransformMakeScale(0.88, 0.88);
    [UIView animateWithDuration:0.22 delay:0
         usingSpringWithDamping:0.72 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.settingsMenu.alpha     = 1;
        self.settingsMenu.transform = CGAffineTransformIdentity;
    } completion:nil];

    // Dismiss on tap outside
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(hideSettings)];
    tap.cancelsTouchesInView = NO;
    [parent addGestureRecognizer:tap];
    objc_setAssociatedObject(self, "skDismissTap", tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)hideSettings {
    if (!self.settingsVisible) return;
    self.settingsVisible = NO;
    UITapGestureRecognizer *tap =
        objc_getAssociatedObject(self, "skDismissTap");
    if (tap) [tap.view removeGestureRecognizer:tap];
    objc_setAssociatedObject(self, "skDismissTap", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    SKSettingsMenu *menu = self.settingsMenu;
    [UIView animateWithDuration:0.16 animations:^{
        menu.alpha     = 0;
        menu.transform = CGAffineTransformMakeScale(0.88, 0.88);
    } completion:^(BOOL f) {
        [menu removeFromSuperview];
        menu.transform = CGAffineTransformIdentity;
    }];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Upload flow
// ─────────────────────────────────────────────────────────────────────────────
- (void)tapUpload {
    [self hideSettings];
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

    // Auto Detect UID option
    if (getSetting(kKeyAutoDetectUID)) {
        NSString *detectedUID = detectUIDFromPrefs();
        if (detectedUID.length) {
            NSMutableArray *filtered = [NSMutableArray new];
            for (NSString *f in dataFiles)
                if ([f containsString:detectedUID]) [filtered addObject:f];
            NSString *autoTitle = [NSString stringWithFormat:
                @"Auto UID: %@ (%lu files)", detectedUID, (unsigned long)filtered.count];
            NSArray *snap = [filtered copy];
            [choice addAction:[UIAlertAction
                actionWithTitle:autoTitle
                style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *a) {
                    snap.count
                        ? [self confirmAndUpload:snap]
                        : [self showAlert:@"No files found"
                                  message:[NSString stringWithFormat:
                              @"No .data file contains UID \"%@\".", detectedUID]];
                }]];
        }
    }

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
                         message:@"Only .data files containing this UID will be uploaded."
                  preferredStyle:UIAlertControllerStyleAlert];
    [input addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder     = @"e.g. 211062956";
        tf.keyboardType    = UIKeyboardTypeNumberPad;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [input addAction:[UIAlertAction actionWithTitle:@"Upload" style:UIAlertActionStyleDefault
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
                    @"No .data file contains UID \"%@\".", uid]]; return;
            }
            [self confirmAndUpload:filtered];
        }]];
    [input addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [[self topVC] presentViewController:input animated:YES completion:nil];
}

- (void)confirmAndUpload:(NSArray<NSString*> *)files {
    NSString *rijNote = getSetting(kKeyAutoRij) ? @"\n• Auto Rij ON (zeros OpenRijTest)" : @"";
    NSString *msg = [NSString stringWithFormat:
        @"Are you sure?\n\nWill upload:\n• PlayerPrefs%@\n• %lu .data file(s):\n%@",
        rijNote, (unsigned long)files.count,
        files.count <= 6
            ? [files componentsJoinedByString:@"\n"]
            : [[files subarrayWithRange:NSMakeRange(0, 6)] componentsJoinedByString:@"\n"]];

    UIAlertController *confirm = [UIAlertController
        alertControllerWithTitle:@"Confirm Upload" message:msg
        preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Yes, Upload"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIView *parent = [self topVC].view ?: self.superview;
        SKProgressOverlay *ov = [SKProgressOverlay showInView:parent title:@"Uploading save data…"];
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
    [self hideSettings];
    if (!loadSessionUUID().length) {
        [self showAlert:@"No Session" message:@"No upload session found. Upload first."];
        return;
    }
    NSString *extra = getSetting(kKeyAutoClose)
        ? @"\n\n⚠ Auto Close is ON — app will exit after load." : @"";
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Load Save"
                         message:[NSString stringWithFormat:
            @"Download edited save and apply it?\nSession is deleted after loading.%@", extra]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Yes, Load"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIView *parent = [self topVC].view ?: self.superview;
        SKProgressOverlay *ov = [SKProgressOverlay showInView:parent title:@"Loading save data…"];
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
    [self hideSettings];
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
