// tweak.xm — Soul Knight Save Manager v11
// iOS 14+ | Theos/Logos | ARC
//
// v11.0 — COMPLETE REWRITE for iPad stability
//
// ROOT CAUSE of all previous crashes:
//   Injecting into the game's view hierarchy requires finding a valid
//   rootViewController and its view at exactly the right moment. On iPad
//   this is fragile: wrong timing = nil view, wrong window = wrong scene,
//   UIAlertController without popover anchor = NSInternalInconsistencyException.
//
// NEW APPROACH — dedicated UIWindow overlay:
//   • Create our own UIWindow at UIWindowLevelAlert+100 so it floats above everything.
//   • On iOS 13+ attach it to the foreground UIWindowScene.
//   • The window owns a minimal transparent UIViewController.
//   • All UIAlertControllers are presented on THAT controller — we always have
//     a valid presenter, popover anchoring is trivial, scene doesn't matter.
//   • hitTest: passes through touches that land on the transparent background,
//     so the game receives all input normally.
//   • Hook applicationDidBecomeActive: instead of viewDidAppear: — fires after
//     the window hierarchy is fully stable on every device and OS version.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ── Config ────────────────────────────────────────────────────────────────────
#define API_BASE @"https://chillysilly.frfrnocap.men/isk.php"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Helpers (session / settings / uid)
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
    NSString *raw = [[NSUserDefaults standardUserDefaults]
                     stringForKey:@"SdkStateCache#1"];
    if (!raw.length) return nil;
    NSDictionary *root = [NSJSONSerialization
        JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding]
        options:0 error:nil];
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
    NSArray *matches = [rx matchesInString:xml options:0
                                     range:NSMakeRange(0, xml.length)];
    if (!matches.count) return xml;
    NSMutableString *r = [xml mutableCopy];
    for (NSTextCheckingResult *m in matches.reverseObjectEnumerator) {
        NSString *orig = [r substringWithRange:m.range];
        [r replaceCharactersInRange:m.range
                         withString:[orig
            stringByReplacingOccurrencesOfString:@"<integer>1</integer>"
                                      withString:@"<integer>0</integer>"]];
    }
    NSData *td = [r dataUsingEncoding:NSUTF8StringEncoding];
    if (!td) return xml;
    NSError *ve = nil;
    id parsed = nil;
    @try { parsed = [NSPropertyListSerialization
        propertyListWithData:td options:NSPropertyListImmutable
        format:nil error:&ve]; }
    @catch (...) { return xml; }
    return (ve || !parsed) ? xml : r;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Networking
// ─────────────────────────────────────────────────────────────────────────────
static NSURLSession *makeSession(void) {
    NSURLSessionConfiguration *c =
        [NSURLSessionConfiguration defaultSessionConfiguration];
    c.timeoutIntervalForRequest  = 120;
    c.timeoutIntervalForResource = 600;
    c.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    return [NSURLSession sessionWithConfiguration:c];
}

typedef struct { NSMutableURLRequest *req; NSData *body; } MPRequest;
static MPRequest buildMP(NSDictionary *fields,
                          NSString *fileField, NSString *filename, NSData *fileData) {
    NSString *b = [NSString stringWithFormat:@"----SKB%08X%08X",
                   arc4random(), arc4random()];
    NSMutableData *body = [NSMutableData data];
    void (^af)(NSString *, NSString *) = ^(NSString *n, NSString *v) {
        [body appendData:[[NSString stringWithFormat:
            @"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n",
            b, n, v] dataUsingEncoding:NSUTF8StringEncoding]];
    };
    for (NSString *k in fields) af(k, fields[k]);
    if (fileField && filename && fileData) {
        [body appendData:[[NSString stringWithFormat:
            @"--%@\r\nContent-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n"
            @"Content-Type: text/plain; charset=utf-8\r\n\r\n", b, fileField, filename]
            dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:fileData];
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
                NSString *raw = [[NSString alloc] initWithData:d
                    encoding:NSUTF8StringEncoding] ?: @"Non-JSON";
                cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:raw}]); return;
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
// MARK: - SKOverlayViewController  (owns the floating button and all alerts)
// ─────────────────────────────────────────────────────────────────────────────
@interface SKOverlayViewController : UIViewController
@end

@implementation SKOverlayViewController {
    UIButton     *_fab;
    UITextView   *_log;
    UIProgressView *_prog;
    UILabel      *_progLabel;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.view.userInteractionEnabled = YES;
    [self buildFAB];
}

// ── Floating Action Button ────────────────────────────────────────────────────
- (void)buildFAB {
    _fab = [UIButton buttonWithType:UIButtonTypeCustom];
    _fab.frame = CGRectMake(0, 0, 52, 52);
    _fab.backgroundColor =
        [UIColor colorWithRed:0.06 green:0.12 blue:0.26 alpha:0.92];
    _fab.layer.cornerRadius  = 26;
    _fab.layer.borderWidth   = 1.5;
    _fab.layer.borderColor   =
        [UIColor colorWithRed:0.18 green:0.52 blue:0.92 alpha:0.8].CGColor;
    _fab.layer.shadowColor   = [UIColor blackColor].CGColor;
    _fab.layer.shadowOpacity = 0.7;
    _fab.layer.shadowRadius  = 6;
    _fab.layer.shadowOffset  = CGSizeMake(0, 3);
    [_fab setTitle:@"SK" forState:UIControlStateNormal];
    [_fab setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _fab.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    _fab.translatesAutoresizingMaskIntoConstraints = NO;

    [_fab addTarget:self action:@selector(fabTapped)
   forControlEvents:UIControlEventTouchUpInside];
    [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(fabPan:)];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(fabPan:)];
    [_fab addGestureRecognizer:pan];

    [self.view addSubview:_fab];
    [NSLayoutConstraint activateConstraints:@[
        [_fab.widthAnchor  constraintEqualToConstant:52],
        [_fab.heightAnchor constraintEqualToConstant:52],
        [_fab.trailingAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor
                           constant:-14],
        [_fab.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
                           constant:80],
    ]];
}

- (void)fabPan:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        CGPoint cur = _fab.center;
        [NSLayoutConstraint deactivateConstraints:_fab.constraints];
        for (NSLayoutConstraint *c in self.view.constraints)
            if (c.firstItem == _fab || c.secondItem == _fab) c.active = NO;
        _fab.translatesAutoresizingMaskIntoConstraints = YES;
        _fab.center = cur;
    }
    CGPoint d = [g translationInView:self.view];
    CGFloat r = _fab.bounds.size.width / 2;
    _fab.center = CGPointMake(
        MAX(r, MIN(self.view.bounds.size.width  - r, _fab.center.x + d.x)),
        MAX(r, MIN(self.view.bounds.size.height - r, _fab.center.y + d.y)));
    [g setTranslation:CGPointZero inView:self.view];
}

- (void)fabTapped { [self showMainMenu]; }

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Menus (all ActionSheet so iPad gets a proper popover automatically)
// ─────────────────────────────────────────────────────────────────────────────
- (void)showMainMenu {
    NSString *sess = loadSessionUUID();
    UIAlertController *m = [UIAlertController
        alertControllerWithTitle:@"SK Save Manager"
                         message:sess
            ? [NSString stringWithFormat:@"Session: %@…",
               [sess substringToIndex:MIN(8u,(unsigned)sess.length)]]
            : @"No active session"
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [m addAction:[UIAlertAction actionWithTitle:@"⬆  Upload to Cloud"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){ [self uploadFlow]; }]];

    [m addAction:[UIAlertAction actionWithTitle:@"⬇  Load from Cloud"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){ [self loadFlow]; }]];

    [m addAction:[UIAlertAction actionWithTitle:@"⚙  Settings"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){ [self settingsMenu]; }]];

    [m addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];

    [self anchorAndPresent:m];
}

- (void)settingsMenu {
    BOOL rij = getSetting(@"autoRij"), uid = getSetting(@"autoDetectUID"),
         cls = getSetting(@"autoClose");
    UIAlertController *s = [UIAlertController
        alertControllerWithTitle:@"Settings"
                         message:[NSString stringWithFormat:
            @"Auto Rij: %@  |  Auto UID: %@  |  Auto Close: %@",
            rij?@"ON":@"OFF", uid?@"ON":@"OFF", cls?@"ON":@"OFF"]
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [s addAction:[UIAlertAction actionWithTitle:
        [NSString stringWithFormat:@"Auto Rij: %@ → Toggle", rij?@"ON":@"OFF"]
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){ setSetting(@"autoRij",!rij); }]];

    [s addAction:[UIAlertAction actionWithTitle:
        [NSString stringWithFormat:@"Auto Detect UID: %@ → Toggle", uid?@"ON":@"OFF"]
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){ setSetting(@"autoDetectUID",!uid); }]];

    [s addAction:[UIAlertAction actionWithTitle:
        [NSString stringWithFormat:@"Auto Close: %@ → Toggle", cls?@"ON":@"OFF"]
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){ setSetting(@"autoClose",!cls); }]];

    [s addAction:[UIAlertAction actionWithTitle:@"Back"
        style:UIAlertActionStyleCancel handler:nil]];

    [self anchorAndPresent:s];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Upload flow
// ─────────────────────────────────────────────────────────────────────────────
- (void)uploadFlow {
    NSString *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSMutableArray *dataFiles = [NSMutableArray new];
    for (NSString *f in ([[NSFileManager defaultManager]
                          contentsOfDirectoryAtPath:docs error:nil] ?: @[]))
        if ([f.pathExtension.lowercaseString isEqualToString:@"data"])
            [dataFiles addObject:f];

    UIAlertController *pick = [UIAlertController
        alertControllerWithTitle:@"Upload"
                         message:[NSString stringWithFormat:
            @"%lu .data file(s) found in Documents.",
            (unsigned long)dataFiles.count]
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [pick addAction:[UIAlertAction
        actionWithTitle:[NSString stringWithFormat:@"Upload All  (%lu files)",
                         (unsigned long)dataFiles.count]
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){ [self confirmUpload:[dataFiles copy]]; }]];

    [pick addAction:[UIAlertAction actionWithTitle:@"Specific UID…"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){
            if (getSetting(@"autoDetectUID")) {
                NSString *uid = detectPlayerUID();
                if (!uid.length) {
                    [self simpleAlert:@"UID Not Found"
                                  msg:@"PlayerId not found. Enter manually."
                                 then:^{ [self askUIDUpload:[dataFiles copy]]; }];
                    return;
                }
                NSMutableArray *f=[NSMutableArray new];
                for (NSString *n in dataFiles) if ([n containsString:uid]) [f addObject:n];
                if (!f.count) {
                    [self simpleAlert:@"No Files"
                                  msg:[NSString stringWithFormat:
                        @"UID \"%@\" matched no .data files.",uid] then:nil]; return;
                }
                [self confirmUpload:f];
            } else {
                [self askUIDUpload:[dataFiles copy]];
            }
        }]];

    [pick addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [self anchorAndPresent:pick];
}

- (void)askUIDUpload:(NSArray *)allFiles {
    UIAlertController *inp = [UIAlertController
        alertControllerWithTitle:@"Enter UID"
                         message:@"Only .data files whose name contains this UID will upload."
                  preferredStyle:UIAlertControllerStyleAlert];
    [inp addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.placeholder = @"e.g. 211062956";
        tf.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [inp addAction:[UIAlertAction actionWithTitle:@"Upload"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
            NSString *uid=[inp.textFields.firstObject.text
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if(!uid.length){[self simpleAlert:@"Error" msg:@"No UID entered." then:nil];return;}
            NSMutableArray *f=[NSMutableArray new];
            for(NSString *n in allFiles) if([n containsString:uid])[f addObject:n];
            if(!f.count){[self simpleAlert:@"No Files"
                msg:[NSString stringWithFormat:@"UID \"%@\" matched nothing.",uid] then:nil];return;}
            [self confirmUpload:f];
        }]];
    [inp addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    // Alert style — safe on iPad without popover anchor
    [self presentViewController:inp animated:YES completion:nil];
}

- (void)confirmUpload:(NSArray *)files {
    NSString *rij = getSetting(@"autoRij") ? @"\n• Auto Rij ON" : @"";
    UIAlertController *c = [UIAlertController
        alertControllerWithTitle:@"Confirm Upload"
                         message:[NSString stringWithFormat:
            @"Upload PlayerPrefs%@ + %lu file(s)?",rij,(unsigned long)files.count]
                  preferredStyle:UIAlertControllerStyleAlert];
    [c addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [c addAction:[UIAlertAction actionWithTitle:@"Upload"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){ [self runUpload:files]; }]];
    [self presentViewController:c animated:YES completion:nil];
}

- (void)runUpload:(NSArray *)files {
    [self showLog:@"Uploading…"];
    [self logLine:@"Serialising NSUserDefaults…"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSDictionary *snap = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSError *pe=nil;
    NSData *pData=[NSPropertyListSerialization dataWithPropertyList:snap
        format:NSPropertyListXMLFormat_v1_0 options:0 error:&pe];
    if(pe||!pData){[self logLine:[NSString stringWithFormat:@"✗ Plist: %@",
        pe.localizedDescription?:@"?"]];[self finishLog:NO];return;}
    NSString *xml=[[NSString alloc]initWithData:pData encoding:NSUTF8StringEncoding];
    if(!xml){[self logLine:@"✗ UTF-8 fail"];[self finishLog:NO];return;}
    if(getSetting(@"autoRij")){
        NSString *p=applyAutoRij(xml);
        xml=p;
        [self logLine:p==xml?@"Auto Rij: no change":@"Auto Rij ✓"];
    }
    [self logLine:[NSString stringWithFormat:@"Keys: %lu  Files: %lu",
        (unsigned long)snap.count,(unsigned long)files.count]];
    [self setProgress:0.05f];

    NSString *uuid=deviceUUID();
    NSURLSession *ses=makeSession();
    NSString *docs=NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory,NSUserDomainMask,YES).firstObject;

    MPRequest init=buildMP(
        @{@"action":@"upload",@"uuid":uuid,@"playerpref":xml},nil,nil,nil);
    skPost(ses,init.req,init.body,^(NSDictionary *j,NSError *err){
        if(err){[self logLine:[NSString stringWithFormat:@"✗ Init: %@",
            err.localizedDescription]];[self finishLog:NO];return;}
        NSString *link=j[@"link"]?:[NSString stringWithFormat:
            @"https://chillysilly.frfrnocap.men/isk.php?view=%@",uuid];
        saveSessionUUID(uuid);
        [self logLine:@"Session ✓"];
        [self logLine:[NSString stringWithFormat:@"Link: %@",link]];

        if(!files.count){
            [UIPasteboard generalPasteboard].string=link;
            [self logLine:@"Copied ✓"];[self finishLog:YES];return;
        }
        NSUInteger total=files.count;
        __block NSUInteger done=0,fail=0;
        dispatch_group_t g=dispatch_group_create();
        for(NSString *fname in files){
            NSString *text=[NSString stringWithContentsOfFile:
                [docs stringByAppendingPathComponent:fname]
                encoding:NSUTF8StringEncoding error:nil];
            if(!text){[self logLine:[NSString stringWithFormat:@"⚠ Skip %@",fname]];
                done++;fail++;continue;}
            dispatch_group_enter(g);
            MPRequest fm=buildMP(@{@"action":@"upload_file",@"uuid":uuid},
                @"datafile",fname,[text dataUsingEncoding:NSUTF8StringEncoding]);
            skPost(ses,fm.req,fm.body,^(NSDictionary *fj,NSError *fe){
                done++;
                if(fe){fail++;[self logLine:[NSString stringWithFormat:@"✗ %@",fname]];}
                else [self logLine:[NSString stringWithFormat:@"✓ %@",fname]];
                [self setProgress:0.1f+0.88f*((float)done/(float)total)];
                dispatch_group_leave(g);
            });
        }
        dispatch_group_notify(g,dispatch_get_main_queue(),^{
            [UIPasteboard generalPasteboard].string=link;
            [self logLine:@"Link copied ✓"];
            if(fail)[self logLine:[NSString stringWithFormat:
                @"⚠ %lu failed",(unsigned long)fail]];
            [self finishLog:fail==0];
        });
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Load flow
// ─────────────────────────────────────────────────────────────────────────────
- (void)loadFlow {
    if(!loadSessionUUID().length){
        [self simpleAlert:@"No Session" msg:@"Upload first." then:nil]; return;
    }
    NSString *note=getSetting(@"autoClose")?@"\n\n⚠ App exits after load.":@"";
    UIAlertController *c=[UIAlertController
        alertControllerWithTitle:@"Load Save"
                         message:[NSString stringWithFormat:
            @"Apply save from cloud? Session deleted after.%@",note]
                  preferredStyle:UIAlertControllerStyleAlert];
    [c addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [c addAction:[UIAlertAction actionWithTitle:@"Load"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){ [self runLoad]; }]];
    [self presentViewController:c animated:YES completion:nil];
}

- (void)runLoad {
    NSString *uuid=loadSessionUUID();
    [self showLog:@"Loading…"];
    [self logLine:[NSString stringWithFormat:@"Session: %@…",
        [uuid substringToIndex:MIN(8u,(unsigned)uuid.length)]]];
    [self setProgress:0.05f];

    NSURLSession *ses=makeSession();
    MPRequest mp=buildMP(@{@"action":@"load",@"uuid":uuid},nil,nil,nil);
    skPost(ses,mp.req,mp.body,^(NSDictionary *j,NSError *err){
        if(err){[self logLine:[NSString stringWithFormat:@"✗ %@",
            err.localizedDescription]];[self finishLog:NO];return;}
        if([j[@"changed"] isEqual:@NO]||[j[@"changed"] isEqual:@0]){
            clearSessionUUID();[self logLine:@"No changes."];[self finishLog:YES];return;
        }
        [self setProgress:0.12f];
        NSString *ppXML=j[@"playerpref"];
        NSDictionary *dataMap=j[@"data"];
        NSString *docs=NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        __block NSUInteger filesOK=0;
        if([dataMap isKindOfClass:[NSDictionary class]]){
            NSUInteger ft=dataMap.count,fi=0;
            for(NSString *fname in dataMap){
                id rv=dataMap[fname];
                if(![rv isKindOfClass:[NSString class]]){fi++;continue;}
                NSString *dst=[docs stringByAppendingPathComponent:[fname lastPathComponent]];
                [[NSFileManager defaultManager] removeItemAtPath:dst error:nil];
                BOOL ok=[(NSString*)rv writeToFile:dst atomically:YES
                    encoding:NSUTF8StringEncoding error:nil];
                if(ok)filesOK++;
                [self logLine:[NSString stringWithFormat:ok?@"✓ %@":@"✗ %@",
                    [fname lastPathComponent]]];
                fi++;
                [self setProgress:0.12f+0.28f*((float)fi/MAX(1.0f,(float)ft))];
            }
        }
        if(!ppXML.length){
            clearSessionUUID();
            [self logLine:[NSString stringWithFormat:@"%lu file(s) written.",(unsigned long)filesOK]];
            [self finishLog:YES];
            if(getSetting(@"autoClose"))
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.6*NSEC_PER_SEC)),
                    dispatch_get_main_queue(),^{exit(0);});
            return;
        }
        [self logLine:@"Applying PlayerPrefs…"];
        NSDictionary *incoming=nil;
        @try{incoming=[NSPropertyListSerialization
            propertyListWithData:[ppXML dataUsingEncoding:NSUTF8StringEncoding]
            options:NSPropertyListMutableContainersAndLeaves format:nil error:nil];}
        @catch(...){incoming=nil;}
        if(![incoming isKindOfClass:[NSDictionary class]]){
            [self logLine:@"⚠ Parse failed."];clearSessionUUID();[self finishLog:filesOK>0];return;
        }
        NSUserDefaults *ud=[NSUserDefaults standardUserDefaults];
        [ud synchronize];
        NSDictionary *live=[ud dictionaryRepresentation];
        NSMutableDictionary *diff=[NSMutableDictionary dictionary];
        [incoming enumerateKeysAndObjectsUsingBlock:^(id k,id v,BOOL *_){
            if(![live[k] isEqual:v])diff[k]=v;
        }];
        [live enumerateKeysAndObjectsUsingBlock:^(id k,id v,BOOL *_){
            if(!incoming[k])diff[k]=[NSNull null];
        }];
        [self logLine:[NSString stringWithFormat:@"Diff: %lu keys",(unsigned long)diff.count]];
        [self setProgress:0.42f];
        NSArray *keys=diff.allKeys;
        NSUInteger total=keys.count,i=0;
        while(i<total){
            NSUInteger end=MIN(i+100,total);
            for(NSUInteger x=i;x<end;x++){
                NSString *k=keys[x]; id v=diff[k];
                @try{
                    if([v isKindOfClass:[NSNull class]])[ud removeObjectForKey:k];
                    else [ud setObject:v forKey:k];
                }@catch(...){}
            }
            i=end;
        }
        [ud synchronize];
        clearSessionUUID();
        [self logLine:[NSString stringWithFormat:@"✓ %lu keys + %lu files",
            (unsigned long)diff.count,(unsigned long)filesOK]];
        [self finishLog:YES];
        if(getSetting(@"autoClose"))
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.6*NSEC_PER_SEC)),
                dispatch_get_main_queue(),^{exit(0);});
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Inline log
// ─────────────────────────────────────────────────────────────────────────────
- (void)showLog:(NSString *)title {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_log removeFromSuperview];
        [_prog removeFromSuperview];
        [_progLabel removeFromSuperview];

        CGFloat w = MIN(self.view.bounds.size.width - 28, 340);
        CGFloat x = (self.view.bounds.size.width - w) / 2;
        CGFloat fabY = _fab.frame.origin.y + _fab.frame.size.height + 8;
        if (fabY + 220 > self.view.bounds.size.height - 20)
            fabY = self.view.bounds.size.height - 240;

        _prog = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _prog.frame = CGRectMake(x, fabY, w, 6);
        _prog.progressTintColor = [UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];
        _prog.trackTintColor    = [UIColor colorWithWhite:0.25 alpha:1];
        _prog.layer.cornerRadius = 3;
        _prog.clipsToBounds = YES;
        _prog.progress = 0;
        [self.view addSubview:_prog];

        _progLabel = [UILabel new];
        _progLabel.frame = CGRectMake(x, fabY + 9, w, 14);
        _progLabel.text = title;
        _progLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1];
        _progLabel.font = [UIFont boldSystemFontOfSize:10];
        _progLabel.textAlignment = NSTextAlignmentCenter;
        _progLabel.backgroundColor =
            [UIColor colorWithRed:0.04 green:0.04 blue:0.07 alpha:0.88];
        [self.view addSubview:_progLabel];

        _log = [UITextView new];
        _log.frame = CGRectMake(x, fabY + 26, w, 190);
        _log.backgroundColor =
            [UIColor colorWithRed:0.04 green:0.05 blue:0.08 alpha:0.94];
        _log.textColor = [UIColor colorWithRed:0.35 green:0.92 blue:0.55 alpha:1];
        _log.font = [UIFont fontWithName:@"Courier" size:10]
                   ?: [UIFont systemFontOfSize:10];
        _log.editable = NO; _log.selectable = NO;
        _log.layer.cornerRadius = 10;
        _log.text = @"";
        [self.view addSubview:_log];
    });
}
- (void)logLine:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!_log) return;
        NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"HH:mm:ss";
        _log.text = [_log.text stringByAppendingFormat:@"[%@] %@\n",
                     [f stringFromDate:[NSDate date]], msg];
        if (_log.text.length)
            [_log scrollRangeToVisible:NSMakeRange(_log.text.length-1,1)];
    });
}
- (void)setProgress:(float)p {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_prog setProgress:MAX(0,MIN(1,p)) animated:YES];
        _progLabel.text = [NSString stringWithFormat:@"%.0f%%", p*100];
    });
}
- (void)finishLog:(BOOL)ok {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setProgress:1.0];
        _progLabel.text = ok ? @"✓ Done — tap SK to continue" : @"✗ Failed";
        _progLabel.textColor = ok
            ? [UIColor colorWithRed:0.25 green:0.88 blue:0.45 alpha:1]
            : [UIColor colorWithRed:0.90 green:0.28 blue:0.28 alpha:1];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(5.0*NSEC_PER_SEC)),
            dispatch_get_main_queue(),^{
                [UIView animateWithDuration:0.3 animations:^{
                    _log.alpha=0;_prog.alpha=0;_progLabel.alpha=0;
                } completion:^(BOOL _){
                    [_log removeFromSuperview];_log=nil;
                    [_prog removeFromSuperview];_prog=nil;
                    [_progLabel removeFromSuperview];_progLabel=nil;
                }];
            });
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Attach iPad popover anchor to _fab and present.
- (void)anchorAndPresent:(UIAlertController *)ac {
    if (ac.popoverPresentationController) {
        ac.popoverPresentationController.sourceView = _fab;
        ac.popoverPresentationController.sourceRect = _fab.bounds;
        ac.popoverPresentationController.permittedArrowDirections =
            UIPopoverArrowDirectionAny;
    }
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)simpleAlert:(NSString *)title msg:(NSString *)msg then:(void(^)(void))then {
    UIAlertController *a=[UIAlertController
        alertControllerWithTitle:title message:msg
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){if(then)then();}]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKOverlayWindow  — touch-passthrough dedicated window
// ─────────────────────────────────────────────────────────────────────────────
@interface SKOverlayWindow : UIWindow
@end
@implementation SKOverlayWindow
- (UIView *)hitTest:(CGPoint)pt withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:pt withEvent:event];
    // Transparent background → pass through to game
    if (hit == self.rootViewController.view) return nil;
    return hit;
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Injection
// ─────────────────────────────────────────────────────────────────────────────
static SKOverlayWindow *gOverlayWindow = nil;

static void createOverlayWindow(void) {
    if (gOverlayWindow) return;

    SKOverlayViewController *vc = [SKOverlayViewController new];
    SKOverlayWindow *win = nil;

    if (@available(iOS 13, *)) {
        UIWindowScene *scene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                if (s.activationState == UISceneActivationStateForegroundActive) {
                    scene = (UIWindowScene *)s; break;
                }
                if (!scene) scene = (UIWindowScene *)s; // fallback
            }
        }
        if (scene) win = [[SKOverlayWindow alloc] initWithWindowScene:scene];
    }
    if (!win)
        win = [[SKOverlayWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    win.windowLevel            = UIWindowLevelAlert + 100;
    win.backgroundColor        = UIColor.clearColor;
    win.rootViewController     = vc;
    win.userInteractionEnabled = YES;
    win.hidden                 = NO;

    gOverlayWindow = win;   // retain
}

// Hook on applicationDidBecomeActive — window hierarchy is guaranteed stable here
%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)app {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{ createOverlayWindow(); });
    });
}
%end
