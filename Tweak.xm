// tweak.xm — Soul Knight Save Manager v10
// iOS 14+ | Theos/Logos | ARC
// Changes: .data files are plain text — no base64 encode/decode anywhere.
//          Parallel file uploads, All/specific-UID selection, Open Link button.
//          v10.1: Batched NSUserDefaults restore (100 keys/tick) to prevent
//                 memory leak / crash when restoring large saves (~5000 keys).
//          v10.2: Fixed crash on Load — dispatch_after 1s delay replaced with
//                 dispatch_async (no artificial wait), nil-guarded ov calls,
//                 full error output instead of silent crash.
//          v10.3: Settings menu — Auto Rij, Auto Detect UID, Auto Close.
//                 Hide Menu. Footer credit label.
//          v10.4: UID shown in main panel below session label;
//                 draggable settings card; fixed UISwitch clipping/sizing.
//          v10.5: UISwitch scaled via fixed container view (no AL breakage).
//                 CRASH FIX: Load now uses smart-diff apply — only changed/
//                 new/deleted keys are touched. If plist is identical to the
//                 current NSUserDefaults snapshot the game's runtime keys are
//                 never disturbed, preventing the "unmodified plist" crash.

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
// MARK: - Settings  (persistent per-install, separate from session)
// ─────────────────────────────────────────────────────────────────────────────
static NSString *settingsFilePath(void) {
    return [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Preferences/SKToolsSettings.plist"];
}
static NSMutableDictionary *loadSettingsDict(void) {
    NSMutableDictionary *d = [NSMutableDictionary
        dictionaryWithContentsOfFile:settingsFilePath()];
    return d ?: [NSMutableDictionary dictionary];
}
static void persistSettingsDict(NSMutableDictionary *d) {
    [d writeToFile:settingsFilePath() atomically:YES];
}
static BOOL getSetting(NSString *key) {
    return [loadSettingsDict()[key] boolValue];
}
static void setSetting(NSString *key, BOOL val) {
    NSMutableDictionary *d = loadSettingsDict();
    d[key] = @(val);
    persistSettingsDict(d);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Device UUID
// ─────────────────────────────────────────────────────────────────────────────
static NSString *deviceUUID(void) {
    NSString *v = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    return v ?: [[NSUUID UUID] UUIDString];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Auto Detect UID — reads PlayerId from SdkStateCache#1
// ─────────────────────────────────────────────────────────────────────────────
static NSString *detectPlayerUID(void) {
    NSString *raw = [[NSUserDefaults standardUserDefaults]
        stringForKey:@"SdkStateCache#1"];
    if (!raw.length) return nil;
    NSData *jdata = [raw dataUsingEncoding:NSUTF8StringEncoding];
    if (!jdata) return nil;
    NSDictionary *root = [NSJSONSerialization
        JSONObjectWithData:jdata options:0 error:nil];
    if (![root isKindOfClass:[NSDictionary class]]) return nil;
    id user = root[@"User"];
    if (![user isKindOfClass:[NSDictionary class]]) return nil;
    id pid = ((NSDictionary *)user)[@"PlayerId"];
    if (!pid) return nil;
    return [NSString stringWithFormat:@"%@", pid];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Auto Rij — zero out OpenRijTest_ flags before upload
// ─────────────────────────────────────────────────────────────────────────────
static NSString *applyAutoRij(NSString *plistXML) {
    if (!plistXML.length) return plistXML;
    NSError *re = nil;
    NSRegularExpression *rx = [NSRegularExpression
        regularExpressionWithPattern:
            @"(<key>OpenRijTest_\\d+</key>\\s*<integer>)1(</integer>)"
        options:0 error:&re];
    if (!rx || re) return plistXML;
    return [rx stringByReplacingMatchesInString:plistXML
                                        options:0
                                          range:NSMakeRange(0, plistXML.length)
                                   withTemplate:@"${1}0${2}"];
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

    if (getSetting(@"autoRij")) {
        NSString *patched = applyAutoRij(plistXML);
        NSUInteger before = plistXML.length;
        NSUInteger after  = patched.length;
        plistXML = patched;
        [ov appendLog:[NSString stringWithFormat:
            @"Auto Rij applied (Δ%ld chars).",
            (long)((NSInteger)after - (NSInteger)before)]];
    }

    [ov appendLog:[NSString stringWithFormat:@"PlayerPrefs: %lu keys",
                   (unsigned long)snap.count]];
    [ov appendLog:[NSString stringWithFormat:@"Will upload %lu .data file(s)",
                   (unsigned long)fileNames.count]];

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
// MARK: - Smart-diff batched NSUserDefaults writer  (v10.5 crash fix)
//
// OLD behaviour: wipe ALL keys → rewrite ALL keys from downloaded plist.
//   Problem: runtime keys the game writes after launch (session tokens, device
//   IDs, cache entries) get destroyed then restored with stale snapshot values.
//   The game detects the inconsistency and crashes — especially when the plist
//   was not edited at all, so every key comes back bit-for-bit identical yet
//   the wipe still happens.
//
// NEW behaviour: diff downloaded dict against live NSUserDefaults.
//   • Keys whose value CHANGED  → setObject
//   • Keys that are NEW         → setObject
//   • Keys that were DELETED    → removeObjectForKey
//   • Keys that are IDENTICAL   → untouched  ← the key fix
//   If the diff is empty (plist identical to live state) NSUserDefaults is
//   never touched at all and the game never notices anything happened.
// ─────────────────────────────────────────────────────────────────────────────
static const NSUInteger kUDWriteBatchSize = 100;

// Deep-equality helper for plist values (NSString, NSNumber, NSData,
// NSArray, NSDictionary, NSDate).  Falls back to isEqual: for anything else.
static BOOL plistValuesEqual(id a, id b) {
    if (a == b) return YES;
    if (!a || !b) return NO;
    if ([a isKindOfClass:[NSDictionary class]] && [b isKindOfClass:[NSDictionary class]]) {
        NSDictionary *da = a, *db = b;
        if (da.count != db.count) return NO;
        for (NSString *k in da) {
            if (!plistValuesEqual(da[k], db[k])) return NO;
        }
        return YES;
    }
    if ([a isKindOfClass:[NSArray class]] && [b isKindOfClass:[NSArray class]]) {
        NSArray *aa = a, *ab = b;
        if (aa.count != ab.count) return NO;
        for (NSUInteger i = 0; i < aa.count; i++) {
            if (!plistValuesEqual(aa[i], ab[i])) return NO;
        }
        return YES;
    }
    return [a isEqual:b];
}

// Compute diff: returns dict with keys to set (value = new value) and keys to
// remove (value = [NSNull null]).
static NSDictionary *udDiff(NSDictionary *live, NSDictionary *incoming) {
    NSMutableDictionary *diff = [NSMutableDictionary dictionary];

    // Changed or new keys
    [incoming enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *_) {
        id current = live[k];
        if (!plistValuesEqual(current, v)) diff[k] = v;
    }];

    // Deleted keys
    [live enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *_) {
        if (!incoming[k]) diff[k] = [NSNull null];
    }];

    return diff;
}

static void _applyDiffBatch(NSUserDefaults *ud,
                             NSArray<NSString *> *keys,
                             NSDictionary *diff,
                             NSUInteger start,
                             NSUInteger total,
                             SKProgressOverlay *ov,
                             void (^completion)(NSUInteger changed)) {
    if (start >= total) {
        @try { [ud synchronize]; }
        @catch (NSException *ex) {
            NSLog(@"[SKTools] ud synchronize exception: %@", ex.reason);
        }
        completion(total);
        return;
    }

    @autoreleasepool {
        NSUInteger end = MIN(start + kUDWriteBatchSize, total);
        for (NSUInteger i = start; i < end; i++) {
            NSString *k = keys[i];
            id v = diff[k];
            if (!k || !v) continue;
            @try {
                if ([v isKindOfClass:[NSNull class]]) {
                    [ud removeObjectForKey:k];
                } else {
                    [ud setObject:v forKey:k];
                }
            } @catch (NSException *ex) {
                NSLog(@"[SKTools] ud apply exception for key %@: %@", k, ex.reason);
            }
        }

        if (ov && (start == 0 || (end % 500 == 0) || end == total)) {
            [ov appendLog:[NSString stringWithFormat:
                @"  PlayerPrefs diff %lu/%lu…",
                (unsigned long)end, (unsigned long)total]];
            [ov setProgress:0.10f + 0.28f * ((float)end / (float)total)
                      label:[NSString stringWithFormat:
                @"%lu/%lu", (unsigned long)end, (unsigned long)total]];
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        _applyDiffBatch(ud, keys, diff, start + kUDWriteBatchSize, total, ov, completion);
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Helper: write .data files from server response
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

    NSUInteger fileTotal       = dataMap.count;
    __block NSUInteger fi      = 0;
    __block NSUInteger applied = 0;

    for (NSString *fname in dataMap) {
        id rawValue = dataMap[fname];

        if (![rawValue isKindOfClass:[NSString class]] || !((NSString *)rawValue).length) {
            [ov appendLog:[NSString stringWithFormat:@"⚠ %@ — empty or invalid, skipped", fname]];
            fi++;
            continue;
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
// MARK: - Load  (v10.5: smart-diff apply, never wipes live UD state)
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
                      err.localizedDescription]);
            return;
        }

        if ([j[@"changed"] isEqual:@NO] || [j[@"changed"] isEqual:@0]) {
            clearSessionUUID();
            done(YES, @"ℹ Server reports no changes were made. Nothing applied.");
            return;
        }

        [ov setProgress:0.10 label:@"10%"];

        NSString *ppXML       = j[@"playerpref"];
        NSDictionary *dataMap = j[@"data"];

        if (!ppXML.length) {
            [ov appendLog:@"No PlayerPrefs in response — writing .data files only."];
            writeDataFiles(dataMap, ov, ^(NSUInteger applied) {
                clearSessionUUID();
                done(YES, [NSString stringWithFormat:
                    @"✓ Loaded %lu file(s). Restart the game.", (unsigned long)applied]);
            });
            return;
        }

        // ── Parse downloaded plist ────────────────────────────────────────────
        [ov appendLog:@"Parsing PlayerPrefs…"];
        NSError *pe      = nil;
        NSDictionary *incoming = nil;

        @try {
            incoming = [NSPropertyListSerialization
                propertyListWithData:[ppXML dataUsingEncoding:NSUTF8StringEncoding]
                             options:NSPropertyListMutableContainersAndLeaves
                              format:nil error:&pe];
        } @catch (NSException *ex) {
            [ov appendLog:[NSString stringWithFormat:
                @"⚠ PlayerPrefs plist exception: %@", ex.reason]];
            incoming = nil;
        }

        if (pe || ![incoming isKindOfClass:[NSDictionary class]]) {
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

        // ── Smart diff against live NSUserDefaults ────────────────────────────
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud synchronize];
        NSDictionary *live = [ud dictionaryRepresentation];

        NSDictionary *diff = udDiff(live, incoming);

        if (!diff.count) {
            // Plist is identical to live state — skip UD entirely, no crash risk
            [ov appendLog:@"PlayerPrefs unchanged — skipping (0 diff keys)."];
            [ov setProgress:0.40 label:@"40%"];
            writeDataFiles(dataMap, ov, ^(NSUInteger filesApplied) {
                clearSessionUUID();
                done(YES, [NSString stringWithFormat:
                    @"✓ PlayerPrefs identical (skipped), %lu file(s) applied. "
                    @"Restart the game.", (unsigned long)filesApplied]);
            });
            return;
        }

        NSArray<NSString *> *diffKeys = [diff allKeys];
        NSUInteger total   = diffKeys.count;
        NSUInteger removes = 0;
        for (id v in [diff allValues])
            if ([v isKindOfClass:[NSNull class]]) removes++;
        NSUInteger sets = total - removes;

        [ov appendLog:[NSString stringWithFormat:
            @"PlayerPrefs diff: %lu set, %lu remove (of %lu total keys)",
            (unsigned long)sets, (unsigned long)removes, (unsigned long)live.count]];

        // ── Apply only changed keys in batches ────────────────────────────────
        _applyDiffBatch(ud, diffKeys, diff, 0, total, ov, ^(NSUInteger changed) {
            [ov appendLog:[NSString stringWithFormat:
                @"PlayerPrefs ✓ (%lu keys changed)", (unsigned long)changed]];

            writeDataFiles(dataMap, ov, ^(NSUInteger filesApplied) {
                clearSessionUUID();
                NSUInteger totalApplied = (changed > 0 ? 1 : 0) + filesApplied;
                done(YES, [NSString stringWithFormat:
                    @"✓ Loaded %lu item(s). Restart the game.",
                    (unsigned long)totalApplied]);
            });
        });
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKSettingsMenu
//
//  v10.5: UISwitch placed inside a fixed-size container view so the scale
//  transform doesn't affect Auto Layout measurements.  The container has the
//  scaled visual size (51*kSWScale × 31*kSWScale); Auto Layout pins the
//  container, not the switch.  Adjust kSWScale to taste (0.70–0.85).
// ─────────────────────────────────────────────────────────────────────────────
static const CGFloat kSWScale = 0.75f;   // ← change scale here

@interface SKSettingsMenu : UIView
@end

@implementation SKSettingsMenu {
    UIView   *_card;
    UISwitch *_rijSwitch;
    UISwitch *_uidSwitch;
    UISwitch *_closeSwitch;
}

+ (instancetype)showInView:(UIView *)parent {
    SKSettingsMenu *m = [[SKSettingsMenu alloc] initWithFrame:parent.bounds];
    m.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [parent addSubview:m];
    m.alpha = 0;
    [UIView animateWithDuration:0.22 animations:^{ m.alpha = 1; }];
    return m;
}

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.68];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(bgTap:)];
    tap.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tap];
    [self buildUI];
    return self;
}

- (void)bgTap:(UITapGestureRecognizer *)g {
    CGPoint pt = [g locationInView:self];
    if (_card && !CGRectContainsPoint(_card.frame, pt)) [self dismiss];
}

// ── Row factory ───────────────────────────────────────────────────────────────
// UISwitch lives inside a fixed-size container so its transform never escapes
// into Auto Layout.  Container width = 51*kSWScale, height = 31*kSWScale.
- (UIView *)rowWithTitle:(NSString *)title
             description:(NSString *)desc
                  swRef:(__strong UISwitch **)swRef
                     tag:(NSInteger)tag {

    UIView *row = [UIView new];
    row.backgroundColor    = [UIColor colorWithRed:0.12 green:0.12 blue:0.18 alpha:1];
    row.layer.cornerRadius = 10;
    row.clipsToBounds      = YES;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    // ── Switch container (sized to the SCALED visual footprint) ──────────────
    CGFloat swNativeW = 51.0f, swNativeH = 31.0f;
    CGFloat swContW   = swNativeW * kSWScale;
    CGFloat swContH   = swNativeH * kSWScale;

    UIView *swCont = [UIView new];
    swCont.clipsToBounds = NO;   // let the switch render; clip is on row
    swCont.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:swCont];

    UISwitch *sw = [UISwitch new];
    sw.onTintColor = [UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];
    sw.tag         = tag;
    // Scale transform — applied AFTER adding to container so transform origin
    // is the switch's own centre, not the container's.
    sw.transform   = CGAffineTransformMakeScale(kSWScale, kSWScale);
    // Position: centre the (native-sized) switch inside the small container.
    sw.frame = CGRectMake((swContW - swNativeW) * 0.5f,
                          (swContH - swNativeH) * 0.5f,
                          swNativeW, swNativeH);
    [sw addTarget:self action:@selector(switchChanged:)
 forControlEvents:UIControlEventValueChanged];
    [swCont addSubview:sw];
    *swRef = sw;

    // ── Text labels ───────────────────────────────────────────────────────────
    UILabel *nameL = [UILabel new];
    nameL.text          = title;
    nameL.textColor     = [UIColor whiteColor];
    nameL.font          = [UIFont boldSystemFontOfSize:12];
    nameL.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:nameL];

    UILabel *descL = [UILabel new];
    descL.text          = desc;
    descL.textColor     = [UIColor colorWithWhite:0.45 alpha:1];
    descL.font          = [UIFont systemFontOfSize:9.5];
    descL.numberOfLines = 0;
    descL.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:descL];

    // ── Constraints ───────────────────────────────────────────────────────────
    [NSLayoutConstraint activateConstraints:@[
        // Container: pinned to trailing, vertically centred, FIXED to scaled size
        [swCont.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [swCont.centerYAnchor  constraintEqualToAnchor:row.centerYAnchor],
        [swCont.widthAnchor    constraintEqualToConstant:swContW],
        [swCont.heightAnchor   constraintEqualToConstant:swContH],

        // Name label
        [nameL.leadingAnchor  constraintEqualToAnchor:row.leadingAnchor constant:12],
        [nameL.topAnchor      constraintEqualToAnchor:row.topAnchor constant:10],
        [nameL.trailingAnchor constraintLessThanOrEqualToAnchor:swCont.leadingAnchor constant:-8],

        // Description label
        [descL.leadingAnchor  constraintEqualToAnchor:row.leadingAnchor constant:12],
        [descL.topAnchor      constraintEqualToAnchor:nameL.bottomAnchor constant:3],
        [descL.trailingAnchor constraintLessThanOrEqualToAnchor:swCont.leadingAnchor constant:-8],
        [row.bottomAnchor     constraintEqualToAnchor:descL.bottomAnchor constant:10],
    ]];
    return row;
}

- (void)buildUI {
    _card = [UIView new];
    _card.backgroundColor    = [UIColor colorWithRed:0.07 green:0.07 blue:0.11 alpha:1];
    _card.layer.cornerRadius = 18;
    _card.clipsToBounds      = YES;
    _card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_card];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(cardPan:)];
    [_card addGestureRecognizer:pan];

    UIView *handle = [UIView new];
    handle.backgroundColor    = [UIColor colorWithWhite:0.32 alpha:0.7];
    handle.layer.cornerRadius = 2;
    handle.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:handle];

    UILabel *titleL = [UILabel new];
    titleL.text          = @"⚙  Settings";
    titleL.textColor     = [UIColor whiteColor];
    titleL.font          = [UIFont boldSystemFontOfSize:15];
    titleL.textAlignment = NSTextAlignmentCenter;
    titleL.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:titleL];

    UIView *div = [UIView new];
    div.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
    div.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:div];

    UIView *rijRow = [self rowWithTitle:@"Auto Rij"
        description:@"Before uploading, sets all OpenRijTest_ flags from 1 → 0 in PlayerPrefs using regex."
        swRef:&_rijSwitch tag:1];
    [_card addSubview:rijRow];

    UIView *uidRow = [self rowWithTitle:@"Auto Detect UID"
        description:@"Reads PlayerId from SdkStateCache#1 — no manual UID entry needed when using Specific UID."
        swRef:&_uidSwitch tag:2];
    [_card addSubview:uidRow];

    UIView *closeRow = [self rowWithTitle:@"Auto Close"
        description:@"Terminates the app automatically once save data has finished loading from cloud."
        swRef:&_closeSwitch tag:3];
    [_card addSubview:closeRow];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [closeBtn setTitle:@"Close" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font    = [UIFont boldSystemFontOfSize:13];
    closeBtn.backgroundColor    = [UIColor colorWithWhite:0.20 alpha:1];
    closeBtn.layer.cornerRadius = 9;
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [closeBtn addTarget:self action:@selector(dismiss)
       forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:closeBtn];

    UILabel *footer = [UILabel new];
    footer.text          = @"Dylib By Mochi - Version: 2.1 - Build: 271.ef2ca7";
    footer.textColor     = [UIColor colorWithWhite:0.28 alpha:1];
    footer.font          = [UIFont systemFontOfSize:8.5];
    footer.textAlignment = NSTextAlignmentCenter;
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:footer];

    [NSLayoutConstraint activateConstraints:@[
        [_card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_card.widthAnchor   constraintEqualToConstant:320],

        [handle.topAnchor     constraintEqualToAnchor:_card.topAnchor constant:8],
        [handle.centerXAnchor constraintEqualToAnchor:_card.centerXAnchor],
        [handle.widthAnchor   constraintEqualToConstant:36],
        [handle.heightAnchor  constraintEqualToConstant:4],

        [titleL.topAnchor      constraintEqualToAnchor:handle.bottomAnchor constant:8],
        [titleL.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:16],
        [titleL.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-16],

        [div.topAnchor      constraintEqualToAnchor:titleL.bottomAnchor constant:10],
        [div.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:12],
        [div.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-12],
        [div.heightAnchor   constraintEqualToConstant:1],

        [rijRow.topAnchor      constraintEqualToAnchor:div.bottomAnchor constant:10],
        [rijRow.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:10],
        [rijRow.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],

        [uidRow.topAnchor      constraintEqualToAnchor:rijRow.bottomAnchor constant:8],
        [uidRow.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:10],
        [uidRow.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],

        [closeRow.topAnchor      constraintEqualToAnchor:uidRow.bottomAnchor constant:8],
        [closeRow.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:10],
        [closeRow.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],

        [closeBtn.topAnchor      constraintEqualToAnchor:closeRow.bottomAnchor constant:14],
        [closeBtn.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:14],
        [closeBtn.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-14],
        [closeBtn.heightAnchor   constraintEqualToConstant:38],

        [footer.topAnchor      constraintEqualToAnchor:closeBtn.bottomAnchor constant:10],
        [footer.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:8],
        [footer.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-8],
        [_card.bottomAnchor    constraintEqualToAnchor:footer.bottomAnchor constant:14],
    ]];

    [self refreshSwitches];
}

- (void)cardPan:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        CGRect cur = _card.frame;
        for (NSLayoutConstraint *c in self.constraints) {
            if (c.firstItem == _card || c.secondItem == _card) c.active = NO;
        }
        _card.translatesAutoresizingMaskIntoConstraints = YES;
        _card.frame = cur;
    }
    CGPoint delta = [g translationInView:self];
    CGRect  f     = _card.frame;
    CGFloat nx    = MAX(0, MIN(self.bounds.size.width  - f.size.width,  f.origin.x + delta.x));
    CGFloat ny    = MAX(0, MIN(self.bounds.size.height - f.size.height, f.origin.y + delta.y));
    _card.frame   = CGRectMake(nx, ny, f.size.width, f.size.height);
    [g setTranslation:CGPointZero inView:self];
}

- (void)refreshSwitches {
    _rijSwitch.on   = getSetting(@"autoRij");
    _uidSwitch.on   = getSetting(@"autoDetectUID");
    _closeSwitch.on = getSetting(@"autoClose");
}

- (void)switchChanged:(UISwitch *)sw {
    NSString *key;
    switch (sw.tag) {
        case 1: key = @"autoRij";       break;
        case 2: key = @"autoDetectUID"; break;
        case 3: key = @"autoClose";     break;
        default: return;
    }
    setSetting(key, sw.isOn);
    [UIView animateWithDuration:0.07 animations:^{ sw.alpha = 0.25f; }
                     completion:^(BOOL _) {
        [UIView animateWithDuration:0.07 animations:^{ sw.alpha = 1.0f; }];
    }];
}

- (void)dismiss {
    [UIView animateWithDuration:0.18 animations:^{ self.alpha = 0; }
                     completion:^(BOOL _){ [self removeFromSuperview]; }];
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKPanel
// ─────────────────────────────────────────────────────────────────────────────
static const CGFloat kPW  = 258;
static const CGFloat kBH  = 46;
static const CGFloat kCH  = 168;

@interface SKPanel : UIView
@property (nonatomic, strong) UIView   *content;
@property (nonatomic, strong) UILabel  *statusLabel;
@property (nonatomic, strong) UILabel  *uidLabel;
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

    CGFloat pad = 9, w = kPW - pad * 2;

    self.statusLabel = [UILabel new];
    self.statusLabel.frame         = CGRectMake(pad, 6, w, 12);
    self.statusLabel.font          = [UIFont systemFontOfSize:9.5];
    self.statusLabel.textColor     = [UIColor colorWithWhite:0.44 alpha:1];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.content addSubview:self.statusLabel];

    self.uidLabel = [UILabel new];
    self.uidLabel.frame         = CGRectMake(pad, 20, w, 12);
    self.uidLabel.font          = [UIFont fontWithName:@"Courier" size:9]
                                 ?: [UIFont systemFontOfSize:9];
    self.uidLabel.textColor     = [UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:1];
    self.uidLabel.textAlignment = NSTextAlignmentCenter;
    self.uidLabel.text          = @"";
    [self.content addSubview:self.uidLabel];

    self.uploadBtn = [self btn:@"⬆  Upload to Cloud"
                         color:[UIColor colorWithRed:0.14 green:0.56 blue:0.92 alpha:1]
                         frame:CGRectMake(pad, 36, w, 42)
                        action:@selector(tapUpload)];
    [self.content addSubview:self.uploadBtn];

    self.loadBtn = [self btn:@"⬇  Load from Cloud"
                       color:[UIColor colorWithRed:0.18 green:0.70 blue:0.42 alpha:1]
                       frame:CGRectMake(pad, 84, w, 42)
                      action:@selector(tapLoad)];
    [self.content addSubview:self.loadBtn];

    CGFloat halfW = (w - 6) / 2;

    UIButton *settingsBtn = [self btn:@"⚙ Settings"
                                color:[UIColor colorWithRed:0.22 green:0.22 blue:0.30 alpha:1]
                                frame:CGRectMake(pad, 134, halfW, 30)
                               action:@selector(tapSettings)];
    settingsBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [self.content addSubview:settingsBtn];

    UIButton *hideBtn = [self btn:@"✕ Hide Menu"
                            color:[UIColor colorWithRed:0.30 green:0.12 blue:0.12 alpha:1]
                            frame:CGRectMake(pad + halfW + 6, 134, halfW, 30)
                           action:@selector(tapHide)];
    hideBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [self.content addSubview:hideBtn];

    [self refreshStatus];
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

    if (getSetting(@"autoDetectUID")) {
        NSString *uid = detectPlayerUID();
        self.uidLabel.text = uid
            ? [NSString stringWithFormat:@"UID: %@", uid]
            : @"UID: not found";
    } else {
        self.uidLabel.text = @"";
    }
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

- (void)tapSettings {
    UIView *parent = [self topVC].view ?: self.superview;
    [SKSettingsMenu showInView:parent];
}

- (void)tapHide {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Hide Menu"
                         message:@"The panel will be removed until the next app launch."
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Hide"
        style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *_) {
            [UIView animateWithDuration:0.2 animations:^{
                self.alpha     = 0;
                self.transform = CGAffineTransformMakeScale(0.85f, 0.85f);
            } completion:^(BOOL __) { [self removeFromSuperview]; }];
        }]];
    [[self topVC] presentViewController:a animated:YES completion:nil];
}

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
        handler:^(UIAlertAction *a) {
            if (getSetting(@"autoDetectUID")) {
                NSString *uid = detectPlayerUID();
                if (!uid.length) {
                    [self showAlert:@"Auto Detect UID"
                            message:@"PlayerId not found in SdkStateCache#1.\nPlease enter UID manually."];
                    [self askUIDThenUpload:dataFiles];
                    return;
                }
                NSMutableArray<NSString*> *filtered = [NSMutableArray new];
                for (NSString *f in dataFiles)
                    if ([f containsString:uid]) [filtered addObject:f];
                if (!filtered.count) {
                    [self showAlert:@"No files found"
                            message:[NSString stringWithFormat:
                        @"Auto-detected UID \"%@\" matched no .data files.", uid]];
                    return;
                }
                [self confirmAndUpload:filtered];
            } else {
                [self askUIDThenUpload:dataFiles];
            }
        }]];

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
    NSString *rijNote = getSetting(@"autoRij") ? @"\n• Auto Rij ON (OpenRijTest_ → 0)" : @"";
    NSString *msg = [NSString stringWithFormat:
        @"Are you sure?\n\nWill upload:\n• PlayerPrefs (NSUserDefaults)%@\n• %lu .data file(s):\n%@",
        rijNote,
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

- (void)tapLoad {
    if (!loadSessionUUID().length) {
        [self showAlert:@"No Session" message:@"No upload session found. Upload first."];
        return;
    }
    NSString *closeNote = getSetting(@"autoClose")
        ? @"\n\n⚠ Auto Close is ON — app will exit after loading."
        : @"";
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Load Save"
                         message:[NSString stringWithFormat:
            @"Download edited save data and apply it?\n\n"
            @"Cloud session is deleted after loading.%@", closeNote]
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
            if (ok && getSetting(@"autoClose")) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(1.6 * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{ exit(0); });
            }
        });
    }]];
    [[self topVC] presentViewController:alert animated:YES completion:nil];
}

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
