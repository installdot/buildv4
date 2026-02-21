// tweak.xm — Soul Knight Save Manager v11
// iOS 14+ | Theos/Logos | ARC
// Changes from v10:
//   - 200 keys written per second (dispatch_after 1.0s between batches)
//   - Diff-merge NSUserDefaults: only add/update/delete changed keys, never blind overwrite
//   - Detailed per-operation error logging — no silent crashes

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ── Config ────────────────────────────────────────────────────────────────────
#define API_BASE          @"https://chillysilly.frfrnocap.men/isk.php"
#define kUDBatchSize      200u          // keys written per batch
#define kUDBatchInterval  1.0           // seconds between batches

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
                    encoding:NSUTF8StringEncoding] ?: @"Non-UTF8 server response";
                cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:
                        @"JSON parse error: %@ | Raw: %.200@", je.localizedDescription, raw]}]);
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
- (void)appendError:(NSString *)msg;   // red tint in log
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
    self.bar.trackTintColor     = [UIColor colorWithWhite:0.22 alpha:1];
    self.bar.progressTintColor  = [UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];
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

// Append a normal (green) log line
- (void)appendLog:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _appendLine:msg color:[UIColor colorWithRed:0.42 green:0.98 blue:0.58 alpha:1]];
    });
}

// Append a red error line so failures are visually distinct
- (void)appendError:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _appendLine:[NSString stringWithFormat:@"❌ %@", msg]
                    color:[UIColor colorWithRed:1.0 green:0.38 blue:0.38 alpha:1]];
    });
}

- (void)_appendLine:(NSString *)msg color:(UIColor *)color {
    // Must be called on main thread
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                      [f stringFromDate:[NSDate date]], msg];

    NSMutableAttributedString *attr =
        [[NSMutableAttributedString alloc] initWithAttributedString:
         self.logView.attributedText ?: [[NSAttributedString alloc] initWithString:@""]];
    [attr appendAttributedString:
     [[NSAttributedString alloc] initWithString:line
                                     attributes:@{
        NSFontAttributeName:            self.logView.font,
        NSForegroundColorAttributeName: color
     }]];
    self.logView.attributedText = attr;

    if (attr.length)
        [self.logView scrollRangeToVisible:NSMakeRange(attr.length - 1, 1)];
}

- (void)finish:(BOOL)ok message:(NSString *)msg link:(NSString *)link {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setProgress:1.0 label:ok ? @"✓ Done" : @"✗ Failed"];
        self.percentLabel.textColor = ok
            ? [UIColor colorWithRed:0.25 green:0.88 blue:0.45 alpha:1]
            : [UIColor colorWithRed:0.90 green:0.28 blue:0.28 alpha:1];
        if (msg.length) {
            ok ? [self appendLog:msg] : [self appendError:msg];
        }
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
// MARK: - Diff-merge NSUserDefaults (200 keys/sec, no blind overwrite)
//
//  Compares serverDict (from cloud) against the live device NSUserDefaults:
//    • Key in server but NOT on device  → add it
//    • Key in both but value differs    → update it
//    • Key on device but NOT in server  → delete it
//
//  Changes are grouped into a flat operations array:
//    @{@"op": @"set"/@"del", @"key": k, @"val": v (for set)}
//  Then applied 200 at a time with a 1-second pause between batches.
//  Each batch runs in @autoreleasepool to keep heap flat.
// ─────────────────────────────────────────────────────────────────────────────

typedef NS_ENUM(NSUInteger, SKUDOp) { SKUDOpSet, SKUDOpDel };

@interface SKUDOperation : NSObject
@property SKUDOp  op;
@property NSString *key;
@property id       val;   // nil for delete
@end
@implementation SKUDOperation @end

static NSArray<SKUDOperation *> *buildDiff(NSDictionary *serverDict,
                                            NSDictionary *deviceDict) {
    NSMutableArray<SKUDOperation *> *ops = [NSMutableArray new];

    // Pass 1: iterate server keys → add or update
    for (NSString *k in serverDict) {
        id sv = serverDict[k];
        id dv = deviceDict[k];
        BOOL changed;
        if (!dv) {
            changed = YES; // key missing on device
        } else {
            // Use isEqual for value comparison; works for NSString/NSNumber/NSData/NSArray/NSDictionary
            changed = ![sv isEqual:dv];
        }
        if (changed) {
            SKUDOperation *o = [SKUDOperation new];
            o.op  = SKUDOpSet;
            o.key = k;
            o.val = sv;
            [ops addObject:o];
        }
    }

    // Pass 2: iterate device keys → delete any that server no longer has
    for (NSString *k in deviceDict) {
        if (!serverDict[k]) {
            SKUDOperation *o = [SKUDOperation new];
            o.op  = SKUDOpDel;
            o.key = k;
            [ops addObject:o];
        }
    }

    return [ops copy];
}

// Applies ops[start..start+kUDBatchSize), then schedules the next batch
// after kUDBatchInterval seconds. Calls completion(appliedCount, errorMessages)
// when done.
static void _applyOpBatch(NSUserDefaults *ud,
                           NSArray<SKUDOperation *> *ops,
                           NSUInteger start,
                           NSUInteger totalApplied,
                           NSMutableArray<NSString *> *errors,
                           SKProgressOverlay *ov,
                           void (^completion)(NSUInteger applied,
                                              NSArray<NSString *> *errors)) {

    NSUInteger total = ops.count;

    if (start >= total) {
        // All batches done
        [ud synchronize];
        completion(totalApplied, errors);
        return;
    }

    NSUInteger batchApplied = 0;

    @autoreleasepool {
        NSUInteger end = MIN(start + kUDBatchSize, total);

        for (NSUInteger i = start; i < end; i++) {
            SKUDOperation *op = ops[i];

            // Wrap each individual write in a guard so one bad key can't abort the batch
            @try {
                if (op.op == SKUDOpSet) {
                    if (!op.val) {
                        NSString *e = [NSString stringWithFormat:
                            @"SET skipped (nil value) key=%@", op.key];
                        [errors addObject:e];
                        [ov appendError:e];
                    } else {
                        [ud setObject:op.val forKey:op.key];
                        batchApplied++;
                    }
                } else {
                    [ud removeObjectForKey:op.key];
                    batchApplied++;
                }
            } @catch (NSException *ex) {
                NSString *e = [NSString stringWithFormat:
                    @"Exception on key '%@' (%@): %@ — %@",
                    op.key,
                    op.op == SKUDOpSet ? @"SET" : @"DEL",
                    ex.name, ex.reason];
                [errors addObject:e];
                [ov appendError:e];
            }
        }

        NSUInteger newApplied = totalApplied + batchApplied;
        float pct = (float)(start + (end - start)) / (float)total;
        [ov setProgress:0.10f + 0.28f * pct
                  label:[NSString stringWithFormat:@"%lu/%lu",
                    (unsigned long)(start + (end - start)), (unsigned long)total]];
        [ov appendLog:[NSString stringWithFormat:
            @"  Batch %lu–%lu applied (%lu ok, %lu total errors so far)",
            (unsigned long)start + 1, (unsigned long)(start + (end - start)),
            (unsigned long)batchApplied, (unsigned long)errors.count]];

        // Capture for block
        NSUInteger capturedApplied = newApplied;
        NSUInteger capturedNext    = end;

        // Pause kUDBatchInterval seconds before next batch, giving the run loop
        // (and autorelease pool) time to fully drain.
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)(kUDBatchInterval * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                _applyOpBatch(ud, ops, capturedNext, capturedApplied,
                              errors, ov, completion);
            });
    }
}

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
    @try {
        [[NSUserDefaults standardUserDefaults] synchronize];
    } @catch (NSException *ex) {
        [ov appendError:[NSString stringWithFormat:
            @"NSUserDefaults synchronize failed: %@ — %@", ex.name, ex.reason]];
    }

    NSDictionary *snap = nil;
    @try {
        snap = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    } @catch (NSException *ex) {
        done(nil, [NSString stringWithFormat:
            @"Cannot read NSUserDefaults: %@ — %@", ex.name, ex.reason]);
        return;
    }

    NSError *pe = nil;
    NSData *pData = [NSPropertyListSerialization
        dataWithPropertyList:snap
        format:NSPropertyListXMLFormat_v1_0
        options:0 error:&pe];
    if (pe || !pData) {
        done(nil, [NSString stringWithFormat:@"Plist serialisation error: %@",
                   pe.localizedDescription]); return;
    }

    NSString *plistXML = [[NSString alloc] initWithData:pData encoding:NSUTF8StringEncoding];
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
        if (err) {
            done(nil, [NSString stringWithFormat:@"Init POST failed: %@",
                       err.localizedDescription]); return;
        }

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
            NSError *readErr = nil;
            NSString *textContent = [NSString stringWithContentsOfFile:path
                                                              encoding:NSUTF8StringEncoding
                                                                 error:&readErr];
            if (!textContent) {
                NSString *reason = readErr
                    ? readErr.localizedDescription
                    : @"unreadable / not UTF-8";
                [ov appendError:[NSString stringWithFormat:
                    @"Skip %@ — %@", fname, reason]];
                @synchronized(fileNames) { doneN++; failN++; }
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
                @synchronized(fileNames) { doneN++; }
                if (ferr) {
                    @synchronized(fileNames) { failN++; }
                    [ov appendError:[NSString stringWithFormat:
                        @"%@: %@", fname, ferr.localizedDescription]];
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
                [ov appendError:[NSString stringWithFormat:
                    @"%lu file(s) failed, %lu succeeded",
                    (unsigned long)failN, (unsigned long)(total - failN)]];
            done(link, nil);
        });
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Load  (diff-merge PlayerPrefs, then write .data files)
// ─────────────────────────────────────────────────────────────────────────────
static void performLoad(SKProgressOverlay *ov,
                        void (^done)(BOOL ok, NSString *msg)) {
    NSString *uuid = loadSessionUUID();
    if (!uuid.length) { done(NO, @"No session. Upload first."); return; }

    NSURLSession *ses = makeSession();
    [ov appendLog:[NSString stringWithFormat:@"Session: %@…",
                   [uuid substringToIndex:MIN(8u, (unsigned)uuid.length)]]];
    [ov appendLog:@"Requesting save data from server…"];
    [ov setProgress:0.05 label:@"5%"];

    MPRequest mp = buildMP(@{@"action":@"load", @"uuid":uuid}, nil, nil, nil);

    skPost(ses, mp.req, mp.body, ^(NSDictionary *j, NSError *netErr) {
        if (netErr) {
            done(NO, [NSString stringWithFormat:@"Network error: %@",
                      netErr.localizedDescription]); return;
        }
        [ov setProgress:0.10 label:@"10%"];

        // ── Parse server plist ────────────────────────────────────────────────
        NSString *ppXML = j[@"playerpref"];
        if (!ppXML.length) {
            [ov appendError:@"Server returned no PlayerPrefs — skipping pref merge"];
        }

        NSDictionary *serverDict = nil;
        if (ppXML.length) {
            NSError *pe = nil;
            id parsed = [NSPropertyListSerialization
                propertyListWithData:[ppXML dataUsingEncoding:NSUTF8StringEncoding]
                options:NSPropertyListMutableContainersAndLeaves
                format:nil error:&pe];

            if (pe) {
                [ov appendError:[NSString stringWithFormat:
                    @"Server plist parse error: %@", pe.localizedDescription]];
            } else if (![parsed isKindOfClass:[NSDictionary class]]) {
                [ov appendError:[NSString stringWithFormat:
                    @"Server plist is unexpected type: %@",
                    NSStringFromClass([parsed class])]];
            } else {
                serverDict = (NSDictionary *)parsed;
                [ov appendLog:[NSString stringWithFormat:
                    @"Server plist: %lu keys", (unsigned long)serverDict.count]];
            }
        }

        // ── Read device NSUserDefaults ────────────────────────────────────────
        NSDictionary *deviceDict = nil;
        @try {
            deviceDict = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
            [ov appendLog:[NSString stringWithFormat:
                @"Device prefs: %lu keys", (unsigned long)deviceDict.count]];
        } @catch (NSException *ex) {
            [ov appendError:[NSString stringWithFormat:
                @"Cannot read device NSUserDefaults: %@ — %@", ex.name, ex.reason]];
            deviceDict = @{};
        }

        // ── Build diff ────────────────────────────────────────────────────────
        NSArray<SKUDOperation *> *ops = nil;
        if (serverDict) {
            ops = buildDiff(serverDict, deviceDict);

            NSUInteger setCount = 0, delCount = 0;
            for (SKUDOperation *o in ops) {
                if (o.op == SKUDOpSet) setCount++;
                else delCount++;
            }
            [ov appendLog:[NSString stringWithFormat:
                @"Diff: %lu add/update, %lu delete  (%lu total changes)",
                (unsigned long)setCount, (unsigned long)delCount,
                (unsigned long)ops.count]];

            if (!ops.count) {
                [ov appendLog:@"PlayerPrefs already up-to-date — nothing to change"];
            }
        }

        // ── Apply diff in batches of 200/sec ──────────────────────────────────
        void (^afterPrefs)(void) = ^{
            // Write .data files after PlayerPrefs is done
            NSDictionary *dataMap = j[@"data"];
            NSString *docsPath = NSSearchPathForDirectoriesInDomains(
                NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
            NSFileManager *fm   = NSFileManager.defaultManager;
            NSUInteger fileTotal = ((NSDictionary *)dataMap).count;
            __block NSUInteger fi = 0, fileOk = 0;

            for (NSString *fname in dataMap) {
                @autoreleasepool {
                    NSString *textContent = dataMap[fname];
                    if (![textContent isKindOfClass:[NSString class]] || !textContent.length) {
                        [ov appendError:[NSString stringWithFormat:
                            @"%@ — server value is empty or wrong type (%@)",
                            fname, NSStringFromClass([dataMap[fname] class])]];
                        fi++;
                        continue;
                    }

                    NSString *dst = [docsPath stringByAppendingPathComponent:fname];
                    // Remove old file first so atomicWrite creates a clean copy
                    NSError *rmErr = nil;
                    if ([fm fileExistsAtPath:dst]) {
                        [fm removeItemAtPath:dst error:&rmErr];
                        if (rmErr) {
                            [ov appendError:[NSString stringWithFormat:
                                @"%@ — could not remove old file: %@",
                                fname, rmErr.localizedDescription]];
                        }
                    }

                    NSError *we = nil;
                    BOOL wrote = [textContent writeToFile:dst atomically:YES
                                                 encoding:NSUTF8StringEncoding error:&we];
                    if (!wrote || we) {
                        [ov appendError:[NSString stringWithFormat:
                            @"%@ — write failed: %@ (POSIX %ld)",
                            fname,
                            we.localizedDescription ?: @"unknown",
                            (long)we.code]];
                    } else {
                        [ov appendLog:[NSString stringWithFormat:
                            @"✓ %@  (%lu chars)", fname,
                            (unsigned long)textContent.length]];
                        fileOk++;
                    }

                    fi++;
                    float p = 0.40f + 0.58f * ((float)fi / MAX(1.0f, (float)fileTotal));
                    [ov setProgress:p label:[NSString stringWithFormat:
                        @"%lu/%lu", (unsigned long)fi, (unsigned long)fileTotal]];
                }
            }

            clearSessionUUID();
            done(YES, [NSString stringWithFormat:
                @"✓ Done. %lu .data file(s) written. Restart game.", (unsigned long)fileOk]);
        };

        if (!ops || !ops.count) {
            afterPrefs();
            return;
        }

        [ov appendLog:[NSString stringWithFormat:
            @"Writing changes at %u keys/sec…", (unsigned)kUDBatchSize]];

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        NSMutableArray<NSString *> *errors = [NSMutableArray new];

        _applyOpBatch(ud, ops, 0, 0, errors, ov, ^(NSUInteger applied,
                                                     NSArray<NSString *> *errs) {
            [ov appendLog:[NSString stringWithFormat:
                @"PlayerPrefs ✓ %lu change(s) applied, %lu error(s)",
                (unsigned long)applied, (unsigned long)errs.count]];

            // Show a summary of any errors rather than silently ignoring
            if (errs.count) {
                [ov appendError:[NSString stringWithFormat:
                    @"%lu key(s) failed — see above for details", (unsigned long)errs.count]];
            }

            afterPrefs();
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
    self.clipsToBounds       = NO;
    self.layer.cornerRadius  = 12;
    self.backgroundColor     = [UIColor colorWithRed:0.06 green:0.06 blue:0.09 alpha:0.96];
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

    CGFloat pad = 9, w = kPW - pad * 2;

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
    [b setTitleColor:[UIColor colorWithWhite:0.80 alpha:1]
            forState:UIControlStateHighlighted];
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
    NSMutableArray<NSString *> *dataFiles = [NSMutableArray new];
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

- (void)askUIDThenUpload:(NSArray<NSString *> *)allFiles {
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
                stringByTrimmingCharactersInSet:
                    NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!uid.length) {
                [self showAlert:@"No UID entered" message:@"Please enter a UID."]; return;
            }
            NSMutableArray<NSString *> *filtered = [NSMutableArray new];
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

- (void)confirmAndUpload:(NSArray<NSString *> *)files {
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
                    [ov finish:NO message:err link:nil];
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
                         message:@"Download and apply changes?\n\nOnly keys that differ will be touched. Cloud session is deleted after loading."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction
        actionWithTitle:@"Yes, Load"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
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
        root.bounds.size.width - gPanel.bounds.size.width / 2 - 10, 88);
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
