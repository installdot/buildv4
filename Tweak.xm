// tweak.xm — Soul Knight Save Manager v12
// iOS 14+ | Theos/Logos | ARC
//
// Trigger : 4-finger simultaneous tap anywhere on screen
// UI      : 100% UIAlertController — no custom views, no buttons, no overlays

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#define API_BASE @"https://chillysilly.frfrnocap.men/isk.php"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Helpers
// ─────────────────────────────────────────────────────────────────────────────
static NSString *sessionFilePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Preferences/SKToolsSession.txt"];
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
static NSString *settingsFilePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Preferences/SKToolsSettings.plist"];
}
static NSMutableDictionary *loadSettings(void) {
    return [NSMutableDictionary dictionaryWithContentsOfFile:settingsFilePath()]
           ?: [NSMutableDictionary dictionary];
}
static BOOL getSetting(NSString *key) { return [loadSettings()[key] boolValue]; }
static void setSetting(NSString *key, BOOL val) {
    NSMutableDictionary *d = loadSettings();
    d[key] = @(val);
    [d writeToFile:settingsFilePath() atomically:YES];
}
static NSString *deviceUUID(void) {
    return [[[UIDevice currentDevice] identifierForVendor] UUIDString]
           ?: [[NSUUID UUID] UUIDString];
}
static NSString *detectPlayerUID(void) {
    NSString *raw = [[NSUserDefaults standardUserDefaults] stringForKey:@"SdkStateCache#1"];
    if (!raw.length) return nil;
    NSDictionary *root = [NSJSONSerialization
        JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![root isKindOfClass:[NSDictionary class]]) return nil;
    id pid = ((NSDictionary *)root[@"User"])[@"PlayerId"];
    return pid ? [NSString stringWithFormat:@"%@", pid] : nil;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Auto Rij
// ─────────────────────────────────────────────────────────────────────────────
static NSString *applyAutoRij(NSString *xml) {
    if (!xml.length) return xml;
    NSRegularExpression *rx = [NSRegularExpression
        regularExpressionWithPattern:
            @"<key>OpenRijTest_\\d+</key>\\s*<integer>1</integer>"
        options:0 error:nil];
    if (!rx) return xml;
    NSArray *ms = [rx matchesInString:xml options:0 range:NSMakeRange(0, xml.length)];
    if (!ms.count) return xml;
    NSMutableString *r = [xml mutableCopy];
    for (NSTextCheckingResult *m in ms.reverseObjectEnumerator)
        [r replaceCharactersInRange:m.range
            withString:[[r substringWithRange:m.range]
                stringByReplacingOccurrencesOfString:@"<integer>1</integer>"
                                          withString:@"<integer>0</integer>"]];
    NSData *td = [r dataUsingEncoding:NSUTF8StringEncoding];
    if (!td) return xml;
    NSError *ve = nil; id p = nil;
    @try { p = [NSPropertyListSerialization propertyListWithData:td
                    options:NSPropertyListImmutable format:nil error:&ve]; }
    @catch (...) { return xml; }
    return (ve || !p) ? xml : r;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Networking
// ─────────────────────────────────────────────────────────────────────────────
static NSURLSession *makeSession(void) {
    NSURLSessionConfiguration *c = [NSURLSessionConfiguration defaultSessionConfiguration];
    c.timeoutIntervalForRequest  = 120;
    c.timeoutIntervalForResource = 600;
    c.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    return [NSURLSession sessionWithConfiguration:c];
}
typedef struct { NSMutableURLRequest *req; NSData *body; } MPRequest;
static MPRequest buildMP(NSDictionary *fields, NSString *ff, NSString *fn, NSData *fd) {
    NSString *b = [NSString stringWithFormat:@"----SKB%08X%08X", arc4random(), arc4random()];
    NSMutableData *body = [NSMutableData data];
    void (^af)(NSString *, NSString *) = ^(NSString *n, NSString *v) {
        [body appendData:[[NSString stringWithFormat:
            @"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", b, n, v]
            dataUsingEncoding:NSUTF8StringEncoding]];
    };
    for (NSString *k in fields) af(k, fields[k]);
    if (ff && fn && fd) {
        [body appendData:[[NSString stringWithFormat:
            @"--%@\r\nContent-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n"
            @"Content-Type: text/plain; charset=utf-8\r\n\r\n", b, ff, fn]
            dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:fd];
        [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", b]
        dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:API_BASE]
           cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
       timeoutInterval:120];
    req.HTTPMethod = @"POST";
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", b]
       forHTTPHeaderField:@"Content-Type"];
    return (MPRequest){ req, body };
}
static void skPost(NSURLSession *ses, NSMutableURLRequest *req, NSData *body,
                   void (^cb)(NSDictionary *, NSError *)) {
    [[ses uploadTaskWithRequest:req fromData:body
        completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (e) { cb(nil, e); return; }
            if (!d.length) {
                cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:@"Empty response"}]); return;
            }
            NSError *je = nil;
            NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:&je];
            if (je || !j) {
                cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:
                        [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]?:@"?"}]);
                return;
            }
            if (j[@"error"]) {
                cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:j[@"error"]}]); return;
            }
            cb(j, nil);
        });
    }] resume];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKMenuController  (pure UIAlertController UI)
// ─────────────────────────────────────────────────────────────────────────────
@interface SKMenuController : NSObject
+ (instancetype)shared;
- (void)presentMainMenu;
@end

@implementation SKMenuController

+ (instancetype)shared {
    static SKMenuController *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SKMenuController new]; });
    return s;
}

// ── Top-most VC ───────────────────────────────────────────────────────────────
- (UIViewController *)topVC {
    UIWindow *win = nil;
    if (@available(iOS 13, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in ws.windows)
                if (!w.isHidden && w.alpha > 0 && w.isKeyWindow) { win = w; break; }
            if (!win) win = ws.windows.firstObject;
            if (win) break;
        }
    }
    if (!win)
        for (UIWindow *w in UIApplication.sharedApplication.windows)
            if (!w.isHidden && w.alpha > 0) { win = w; break; }

    UIViewController *vc = win.rootViewController;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed)
        vc = vc.presentedViewController;
    return vc;
}

- (void)present:(UIAlertController *)ac {
    UIViewController *vc = [self topVC];
    if (!vc) return;
    // iPad: anchor to centre of screen — never crashes, no arrow
    if (ac.popoverPresentationController) {
        UIView *v = vc.view;
        ac.popoverPresentationController.sourceView = v;
        ac.popoverPresentationController.sourceRect =
            CGRectMake(CGRectGetMidX(v.bounds), CGRectGetMidY(v.bounds), 1, 1);
        ac.popoverPresentationController.permittedArrowDirections = 0;
    }
    [vc presentViewController:ac animated:YES completion:nil];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Main menu
// ─────────────────────────────────────────────────────────────────────────────
- (void)presentMainMenu {
    NSString *sess = loadSessionUUID();
    UIAlertController *m = [UIAlertController
        alertControllerWithTitle:@"SK Save Manager"
                         message:sess
            ? [NSString stringWithFormat:@"Session: %@…",
               [sess substringToIndex:MIN(8u, (unsigned)sess.length)]]
            : @"No active session"
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [m addAction:[UIAlertAction actionWithTitle:@"⬆  Upload to Cloud"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_) { [self uploadMenu]; }]];
    [m addAction:[UIAlertAction actionWithTitle:@"⬇  Load from Cloud"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_) { [self loadConfirm]; }]];
    [m addAction:[UIAlertAction actionWithTitle:@"⚙  Settings"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_) { [self settingsMenu]; }]];
    [m addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [self present:m];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Settings
// ─────────────────────────────────────────────────────────────────────────────
- (void)settingsMenu {
    BOOL rij = getSetting(@"autoRij");
    BOOL uid = getSetting(@"autoDetectUID");
    BOOL cls = getSetting(@"autoClose");

    UIAlertController *s = [UIAlertController
        alertControllerWithTitle:@"Settings"
                         message:[NSString stringWithFormat:
            @"Auto Rij: %@\nAuto Detect UID: %@\nAuto Close: %@",
            rij?@"ON":@"OFF", uid?@"ON":@"OFF", cls?@"ON":@"OFF"]
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [s addAction:[UIAlertAction
        actionWithTitle:[NSString stringWithFormat:@"Auto Rij: %@ → Toggle", rij?@"ON":@"OFF"]
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_) { setSetting(@"autoRij", !rij); }]];
    [s addAction:[UIAlertAction
        actionWithTitle:[NSString stringWithFormat:@"Auto Detect UID: %@ → Toggle", uid?@"ON":@"OFF"]
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_) { setSetting(@"autoDetectUID", !uid); }]];
    [s addAction:[UIAlertAction
        actionWithTitle:[NSString stringWithFormat:@"Auto Close: %@ → Toggle", cls?@"ON":@"OFF"]
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_) { setSetting(@"autoClose", !cls); }]];
    [s addAction:[UIAlertAction actionWithTitle:@"← Back"
        style:UIAlertActionStyleCancel
        handler:^(UIAlertAction *_) { [self presentMainMenu]; }]];
    [self present:s];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Upload
// ─────────────────────────────────────────────────────────────────────────────
- (void)uploadMenu {
    NSString *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSMutableArray *df = [NSMutableArray new];
    for (NSString *f in ([[NSFileManager defaultManager]
                          contentsOfDirectoryAtPath:docs error:nil] ?: @[]))
        if ([f.pathExtension.lowercaseString isEqualToString:@"data"]) [df addObject:f];

    UIAlertController *u = [UIAlertController
        alertControllerWithTitle:@"Upload"
                         message:[NSString stringWithFormat:
            @"%lu .data file(s) found.", (unsigned long)df.count]
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [u addAction:[UIAlertAction
        actionWithTitle:[NSString stringWithFormat:@"Upload All (%lu files)", (unsigned long)df.count]
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_) { [self confirmUpload:[df copy]]; }]];
    [u addAction:[UIAlertAction actionWithTitle:@"Specific UID…"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_) {
            if (getSetting(@"autoDetectUID")) {
                NSString *uid = detectPlayerUID();
                if (!uid.length) {
                    [self alert:@"UID Not Found"
                            msg:@"PlayerId not found. Enter manually."
                           then:^{ [self askUID:[df copy]]; }];
                    return;
                }
                NSMutableArray *f = [NSMutableArray new];
                for (NSString *n in df) if ([n containsString:uid]) [f addObject:n];
                if (!f.count) {
                    [self alert:@"No Files"
                            msg:[NSString stringWithFormat:
                                @"UID \"%@\" matched no .data files.", uid]
                           then:nil];
                    return;
                }
                [self confirmUpload:f];
            } else {
                [self askUID:[df copy]];
            }
        }]];
    [u addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [self present:u];
}

- (void)askUID:(NSArray *)allFiles {
    UIAlertController *inp = [UIAlertController
        alertControllerWithTitle:@"Enter UID"
                         message:@"Only .data files whose name contains this UID will be uploaded."
                  preferredStyle:UIAlertControllerStyleAlert];
    [inp addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"e.g. 211062956";
        tf.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [inp addAction:[UIAlertAction actionWithTitle:@"Upload"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_) {
            NSString *uid = [inp.textFields.firstObject.text
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!uid.length) {
                [self alert:@"Error" msg:@"No UID entered." then:nil]; return;
            }
            NSMutableArray *f = [NSMutableArray new];
            for (NSString *n in allFiles) if ([n containsString:uid]) [f addObject:n];
            if (!f.count) {
                [self alert:@"No Files"
                        msg:[NSString stringWithFormat:@"UID \"%@\" matched nothing.", uid]
                       then:nil];
                return;
            }
            [self confirmUpload:f];
        }]];
    [inp addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [self present:inp];
}

- (void)confirmUpload:(NSArray *)files {
    UIAlertController *c = [UIAlertController
        alertControllerWithTitle:@"Confirm Upload"
                         message:[NSString stringWithFormat:
            @"Will upload:\n• PlayerPrefs (NSUserDefaults)%@\n• %lu .data file(s)",
            getSetting(@"autoRij") ? @"\n• Auto Rij ON" : @"",
            (unsigned long)files.count]
                  preferredStyle:UIAlertControllerStyleAlert];
    [c addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [c addAction:[UIAlertAction actionWithTitle:@"Upload"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_) { [self runUpload:files]; }]];
    [self present:c];
}

- (void)runUpload:(NSArray *)files {
    UIAlertController *working = [UIAlertController
        alertControllerWithTitle:@"Uploading…"
                         message:@"Please wait."
                  preferredStyle:UIAlertControllerStyleAlert];
    [self present:working];

    [[NSUserDefaults standardUserDefaults] synchronize];
    NSDictionary *snap = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSError *pe = nil;
    NSData *pData = [NSPropertyListSerialization dataWithPropertyList:snap
        format:NSPropertyListXMLFormat_v1_0 options:0 error:&pe];
    if (pe || !pData) {
        [working dismissViewControllerAnimated:YES completion:^{
            [self alert:@"Upload Failed"
                    msg:[NSString stringWithFormat:@"Plist error: %@",
                         pe.localizedDescription ?: @"Unknown"]
                   then:nil];
        }]; return;
    }
    NSString *xml = [[NSString alloc] initWithData:pData encoding:NSUTF8StringEncoding];
    if (!xml) {
        [working dismissViewControllerAnimated:YES completion:^{
            [self alert:@"Upload Failed" msg:@"UTF-8 conversion failed." then:nil];
        }]; return;
    }
    if (getSetting(@"autoRij")) xml = applyAutoRij(xml);

    NSString *uuid    = deviceUUID();
    NSURLSession *ses = makeSession();
    NSString *docs    = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;

    MPRequest init = buildMP(
        @{@"action":@"upload", @"uuid":uuid, @"playerpref":xml}, nil, nil, nil);
    skPost(ses, init.req, init.body, ^(NSDictionary *j, NSError *err) {
        if (err) {
            [working dismissViewControllerAnimated:YES completion:^{
                [self alert:@"Upload Failed" msg:err.localizedDescription then:nil];
            }]; return;
        }
        NSString *link = j[@"link"] ?: [NSString stringWithFormat:
            @"https://chillysilly.frfrnocap.men/isk.php?view=%@", uuid];
        saveSessionUUID(uuid);

        if (!files.count) {
            [UIPasteboard generalPasteboard].string = link;
            [working dismissViewControllerAnimated:YES completion:^{
                [self alert:@"Upload Complete ✓"
                        msg:[NSString stringWithFormat:@"Link copied to clipboard.\n\n%@", link]
                       then:nil];
            }]; return;
        }

        NSUInteger total = files.count;
        __block NSUInteger fail = 0;
        __block NSMutableArray *failNames = [NSMutableArray new];
        dispatch_group_t g = dispatch_group_create();

        for (NSString *fname in files) {
            NSString *text = [NSString stringWithContentsOfFile:
                [docs stringByAppendingPathComponent:fname]
                encoding:NSUTF8StringEncoding error:nil];
            if (!text) { fail++; [failNames addObject:fname]; continue; }
            dispatch_group_enter(g);
            MPRequest fm = buildMP(@{@"action":@"upload_file", @"uuid":uuid},
                @"datafile", fname, [text dataUsingEncoding:NSUTF8StringEncoding]);
            skPost(ses, fm.req, fm.body, ^(NSDictionary *fj, NSError *fe) {
                if (fe) { fail++; [failNames addObject:fname]; }
                dispatch_group_leave(g);
            });
        }

        dispatch_group_notify(g, dispatch_get_main_queue(), ^{
            [UIPasteboard generalPasteboard].string = link;
            [working dismissViewControllerAnimated:YES completion:^{
                if (fail == 0) {
                    [self alert:@"Upload Complete ✓"
                            msg:[NSString stringWithFormat:
                                @"%lu file(s) uploaded.\nLink copied.\n\n%@",
                                (unsigned long)total, link]
                           then:nil];
                } else {
                    [self alert:@"Upload Partial ⚠"
                            msg:[NSString stringWithFormat:
                                @"%lu/%lu succeeded.\nFailed: %@\n\nLink: %@",
                                (unsigned long)(total-fail), (unsigned long)total,
                                [failNames componentsJoinedByString:@", "], link]
                           then:nil];
                }
            }];
        });
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Load
// ─────────────────────────────────────────────────────────────────────────────
- (void)loadConfirm {
    if (!loadSessionUUID().length) {
        [self alert:@"No Session" msg:@"No upload session found. Upload first." then:nil];
        return;
    }
    UIAlertController *c = [UIAlertController
        alertControllerWithTitle:@"Load Save"
                         message:[NSString stringWithFormat:
            @"Download and apply edited save from cloud?\nSession deleted after loading.%@",
            getSetting(@"autoClose") ? @"\n\n⚠ App will exit after load." : @""]
                  preferredStyle:UIAlertControllerStyleAlert];
    [c addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [c addAction:[UIAlertAction actionWithTitle:@"Load"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_) { [self runLoad]; }]];
    [self present:c];
}

- (void)runLoad {
    NSString *uuid = loadSessionUUID();
    UIAlertController *working = [UIAlertController
        alertControllerWithTitle:@"Loading…"
                         message:@"Please wait."
                  preferredStyle:UIAlertControllerStyleAlert];
    [self present:working];

    NSURLSession *ses = makeSession();
    MPRequest mp = buildMP(@{@"action":@"load", @"uuid":uuid}, nil, nil, nil);
    skPost(ses, mp.req, mp.body, ^(NSDictionary *j, NSError *err) {
        if (err) {
            [working dismissViewControllerAnimated:YES completion:^{
                [self alert:@"Load Failed" msg:err.localizedDescription then:nil];
            }]; return;
        }
        if ([j[@"changed"] isEqual:@NO] || [j[@"changed"] isEqual:@0]) {
            clearSessionUUID();
            [working dismissViewControllerAnimated:YES completion:^{
                [self alert:@"No Changes" msg:@"Server reports no edits were made." then:nil];
            }]; return;
        }

        NSString *ppXML       = j[@"playerpref"];
        NSDictionary *dataMap = j[@"data"];
        NSString *docs        = NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        __block NSUInteger filesOK = 0, filesFail = 0;

        // Write .data files
        if ([dataMap isKindOfClass:[NSDictionary class]]) {
            for (NSString *fname in dataMap) {
                id rv = dataMap[fname];
                if (![rv isKindOfClass:[NSString class]]) { filesFail++; continue; }
                NSString *dst = [docs stringByAppendingPathComponent:[fname lastPathComponent]];
                [[NSFileManager defaultManager] removeItemAtPath:dst error:nil];
                [(NSString *)rv writeToFile:dst atomically:YES
                    encoding:NSUTF8StringEncoding error:nil] ? filesOK++ : filesFail++;
            }
        }

        // Apply PlayerPrefs
        __block NSUInteger keysChanged = 0;
        if (ppXML.length) {
            NSDictionary *incoming = nil;
            @try {
                incoming = [NSPropertyListSerialization
                    propertyListWithData:[ppXML dataUsingEncoding:NSUTF8StringEncoding]
                                 options:NSPropertyListMutableContainersAndLeaves
                                  format:nil error:nil];
            } @catch (...) { incoming = nil; }

            if ([incoming isKindOfClass:[NSDictionary class]]) {
                NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
                [ud synchronize];
                NSDictionary *live = [ud dictionaryRepresentation];
                NSMutableDictionary *diff = [NSMutableDictionary dictionary];
                [incoming enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *_) {
                    if (![live[k] isEqual:v]) diff[k] = v;
                }];
                [live enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *_) {
                    if (!incoming[k]) diff[k] = [NSNull null];
                }];
                keysChanged = diff.count;
                NSArray *keys = diff.allKeys;
                NSUInteger i = 0, total = keys.count;
                while (i < total) {
                    NSUInteger end = MIN(i + 100, total);
                    for (NSUInteger x = i; x < end; x++) {
                        NSString *k = keys[x]; id v = diff[k];
                        @try {
                            if ([v isKindOfClass:[NSNull class]]) [ud removeObjectForKey:k];
                            else [ud setObject:v forKey:k];
                        } @catch (...) {}
                    }
                    i = end;
                }
                [ud synchronize];
            }
        }

        clearSessionUUID();
        NSString *summary = [NSString stringWithFormat:
            @"PlayerPrefs: %lu key(s) changed\n.data files: %lu written, %lu failed\n\nRestart the game.",
            (unsigned long)keysChanged, (unsigned long)filesOK, (unsigned long)filesFail];

        [working dismissViewControllerAnimated:YES completion:^{
            [self alert:@"Load Complete ✓" msg:summary then:^{
                if (getSetting(@"autoClose"))
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                        (int64_t)(0.5 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{ exit(0); });
            }];
        }];
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Generic alert helper
// ─────────────────────────────────────────────────────────────────────────────
- (void)alert:(NSString *)title msg:(NSString *)msg then:(void (^)(void))then {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:title message:msg
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_) { if (then) then(); }]];
    [self present:a];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Transparent overlay window + 4-finger tap VC
// ─────────────────────────────────────────────────────────────────────────────
@interface SKOverlayWindow : UIWindow
@end
@implementation SKOverlayWindow
// Pass all touches through — the gesture recogniser will intercept 4-finger taps
- (UIView *)hitTest:(CGPoint)pt withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:pt withEvent:event];
    if (hit == self.rootViewController.view) return nil;
    return hit;
}
@end

@interface SKGestureViewController : UIViewController
@end
@implementation SKGestureViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(fourFingerTap)];
    tap.numberOfTapsRequired    = 1;
    tap.numberOfTouchesRequired = 4;
    tap.cancelsTouchesInView    = NO;   // game keeps receiving touches
    [self.view addGestureRecognizer:tap];
}
- (void)fourFingerTap {
    [[SKMenuController shared] presentMainMenu];
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Injection
// ─────────────────────────────────────────────────────────────────────────────
static SKOverlayWindow *gOverlayWindow = nil;

static void createOverlayWindow(void) {
    if (gOverlayWindow) return;

    SKGestureViewController *vc = [SKGestureViewController new];
    SKOverlayWindow *win = nil;

    if (@available(iOS 13, *)) {
        UIWindowScene *scene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            if (s.activationState == UISceneActivationStateForegroundActive)
                { scene = (UIWindowScene *)s; break; }
            if (!scene) scene = (UIWindowScene *)s;
        }
        if (scene) win = [[SKOverlayWindow alloc] initWithWindowScene:scene];
    }
    if (!win) win = [[SKOverlayWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    win.windowLevel            = UIWindowLevelStatusBar - 1;
    win.backgroundColor        = UIColor.clearColor;
    win.rootViewController     = vc;
    win.userInteractionEnabled = YES;
    win.hidden                 = NO;
    gOverlayWindow             = win;
}

%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)app {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{ createOverlayWindow(); });
    });
}
%end
