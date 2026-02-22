// tweak.xm — Soul Knight Save Manager v11
// iOS 14+ / iPadOS 26+ | Theos/Logos | ARC
//
// v11.1 CHANGES:
//   • Removed floating pill button and bottom sheet entirely
//   • NEW trigger: Press Volume UP then Volume DOWN within 3 seconds → opens menu
//   • Menu is now a UIAlertController (action sheet on iPhone, alert on iPad)
//   • Volume state is monitored via AVAudioSession outputVolume KVO
//   • All other behaviour (upload/load/settings/progress overlay) unchanged

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

// ── Config ──────────────────────────────────────────────────────────────────
#define API_BASE      @"https://chillysilly.frfrnocap.men/isk.php"
#define DYLIB_VERSION @"2.2"
#define DYLIB_BUILD   @"300.v11.1"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Error helper
// ─────────────────────────────────────────────────────────────────────────────
static void skError(NSString *context, NSString *detail);  // forward

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Session
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
// MARK: - Settings
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
    @try {
        NSString *v = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        return v ?: [[NSUUID UUID] UUIDString];
    } @catch (...) { return [[NSUUID UUID] UUIDString]; }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Auto Detect UID
// ─────────────────────────────────────────────────────────────────────────────
static NSString *detectPlayerUID(void) {
    @try {
        NSString *raw = [[NSUserDefaults standardUserDefaults]
            stringForKey:@"SdkStateCache#1"];
        if (!raw.length) return nil;
        NSData *jdata = [raw dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:jdata options:0 error:nil];
        if (![root isKindOfClass:[NSDictionary class]]) return nil;
        id user = root[@"User"];
        if (![user isKindOfClass:[NSDictionary class]]) return nil;
        id pid = ((NSDictionary *)user)[@"PlayerId"];
        return pid ? [NSString stringWithFormat:@"%@", pid] : nil;
    } @catch (...) { return nil; }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Auto Rij
// ─────────────────────────────────────────────────────────────────────────────
static NSString *applyAutoRij(NSString *plistXML) {
    if (!plistXML.length) return plistXML;
    @try {
        NSError *rxErr = nil;
        NSRegularExpression *rx = [NSRegularExpression
            regularExpressionWithPattern:
                @"<key>OpenRijTest_\\d+</key>\\s*<integer>1</integer>"
            options:0 error:&rxErr];
        if (!rx) return plistXML;
        NSMutableString *result = [plistXML mutableCopy];
        NSArray *matches = [rx matchesInString:plistXML options:0
                                         range:NSMakeRange(0, plistXML.length)];
        if (!matches.count) return plistXML;
        for (NSTextCheckingResult *m in matches.reverseObjectEnumerator) {
            NSString *orig    = [result substringWithRange:m.range];
            NSString *patched = [orig
                stringByReplacingOccurrencesOfString:@"<integer>1</integer>"
                                          withString:@"<integer>0</integer>"];
            [result replaceCharactersInRange:m.range withString:patched];
        }
        NSData *test = [result dataUsingEncoding:NSUTF8StringEncoding];
        if (!test) return plistXML;
        NSError *verr = nil;
        id parsed = [NSPropertyListSerialization
            propertyListWithData:test options:NSPropertyListImmutable format:nil error:&verr];
        return (verr || !parsed) ? plistXML : result;
    } @catch (...) { return plistXML; }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Scene helper
// ─────────────────────────────────────────────────────────────────────────────
static UIWindowScene *activeWindowScene(void) {
    if (@available(iOS 13.0, *)) {
        UIWindowScene *fallback = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (scene.activationState == UISceneActivationStateForegroundActive) return ws;
            if (!fallback) fallback = ws;
        }
        return fallback;
    }
    return nil;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Network
// ─────────────────────────────────────────────────────────────────────────────
static NSURLSession *makeSession(void) {
    NSURLSessionConfiguration *c = [NSURLSessionConfiguration defaultSessionConfiguration];
    c.timeoutIntervalForRequest  = 120;
    c.timeoutIntervalForResource = 600;
    c.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    return [NSURLSession sessionWithConfiguration:c];
}

typedef struct { NSMutableURLRequest *req; NSData *body; } MPRequest;

static MPRequest buildMP(NSDictionary<NSString*,NSString*> *fields,
                          NSString *fileField, NSString *filename, NSData *fileData) {
    NSString *boundary = [NSString stringWithFormat:@"----SKBound%08X%08X",
                          arc4random(), arc4random()];
    NSMutableData *body = [NSMutableData dataWithCapacity:fileData ? fileData.length+1024 : 1024];
    void(^add)(NSString*,NSString*) = ^(NSString *n, NSString *v){
        NSString *s = [NSString stringWithFormat:
            @"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n",boundary,n,v];
        [body appendData:[s dataUsingEncoding:NSUTF8StringEncoding]];
    };
    for (NSString *k in fields) add(k, fields[k]);
    if (fileField && filename && fileData) {
        NSString *hdr = [NSString stringWithFormat:
            @"--%@\r\nContent-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n"
            @"Content-Type: text/plain; charset=utf-8\r\n\r\n",boundary,fileField,filename];
        [body appendData:[hdr dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:fileData];
        [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n",boundary]
                      dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:API_BASE]
           cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
       timeoutInterval:120];
    req.HTTPMethod = @"POST";
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@",boundary]
       forHTTPHeaderField:@"Content-Type"];
    return (MPRequest){req,body};
}

static void skPost(NSURLSession *session, NSMutableURLRequest *req, NSData *body,
                   void (^cb)(NSDictionary *json, NSError *err)) {
    [[session uploadTaskWithRequest:req fromData:body
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err) { cb(nil,err); return; }
            if (!data.length) {
                cb(nil,[NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:@"Empty server response"}]); return;
            }
            NSError *je = nil;
            NSDictionary *j = [NSJSONSerialization JSONObjectWithData:data options:0 error:&je];
            if (je || !j) {
                NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                               ?: @"Non-JSON response";
                cb(nil,[NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:raw}]); return;
            }
            if (j[@"error"]) {
                cb(nil,[NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:j[@"error"]}]); return;
            }
            cb(j,nil);
        });
    }] resume];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Diff writer
// ─────────────────────────────────────────────────────────────────────────────
static const NSUInteger kBatch = 100;

static BOOL pvEqual(id a, id b) {
    if (a == b) return YES;
    if (!a || !b) return NO;
    if ([a isKindOfClass:[NSDictionary class]] && [b isKindOfClass:[NSDictionary class]]) {
        NSDictionary *da=a,*db=b;
        if (da.count!=db.count) return NO;
        for (id k in da) if (!pvEqual(da[k],db[k])) return NO;
        return YES;
    }
    if ([a isKindOfClass:[NSArray class]] && [b isKindOfClass:[NSArray class]]) {
        NSArray *aa=a,*ab=b;
        if (aa.count!=ab.count) return NO;
        for (NSUInteger i=0;i<aa.count;i++) if (!pvEqual(aa[i],ab[i])) return NO;
        return YES;
    }
    return [a isEqual:b];
}

static NSDictionary *udDiff(NSDictionary *live, NSDictionary *incoming) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    [incoming enumerateKeysAndObjectsUsingBlock:^(id k,id v,BOOL *_){
        if (!pvEqual(live[k],v)) d[k]=v;
    }];
    [live enumerateKeysAndObjectsUsingBlock:^(id k,id v,BOOL *_){
        if (!incoming[k]) d[k]=[NSNull null];
    }];
    return d;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKProgressOverlay
// ─────────────────────────────────────────────────────────────────────────────
@interface SKProgressOverlay : UIView
@property (nonatomic,strong) UIProgressView *bar;
@property (nonatomic,strong) UILabel        *percentLabel;
@property (nonatomic,strong) UITextView     *logView;
@property (nonatomic,strong) UIButton       *closeBtn;
@property (nonatomic,strong) UIButton       *openLinkBtn;
@property (nonatomic,copy)   NSString       *uploadedLink;
+(instancetype)showInView:(UIView*)parent title:(NSString*)title;
-(void)setProgress:(float)p label:(NSString*)label;
-(void)appendLog:(NSString*)msg;
-(void)finish:(BOOL)ok message:(NSString*)msg link:(NSString*)link;
@end

@implementation SKProgressOverlay

+(instancetype)showInView:(UIView*)parent title:(NSString*)title {
    SKProgressOverlay *o=[[SKProgressOverlay alloc] initWithFrame:parent.bounds];
    o.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [parent addSubview:o];
    [o setup:title];
    o.alpha=0;
    [UIView animateWithDuration:0.2 animations:^{o.alpha=1;}];
    return o;
}

-(void)setup:(NSString*)title {
    self.backgroundColor=[UIColor colorWithWhite:0 alpha:0.78];
    UIView *card=[UIView new];
    card.backgroundColor=[UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1];
    card.layer.cornerRadius=18;
    card.layer.shadowColor=[UIColor blackColor].CGColor;
    card.layer.shadowOpacity=0.85; card.layer.shadowRadius=18;
    card.layer.shadowOffset=CGSizeMake(0,6); card.clipsToBounds=NO;
    card.translatesAutoresizingMaskIntoConstraints=NO;
    [self addSubview:card];

    UILabel *tl=[UILabel new];
    tl.text=title; tl.textColor=[UIColor whiteColor];
    tl.font=[UIFont boldSystemFontOfSize:14]; tl.textAlignment=NSTextAlignmentCenter;
    tl.translatesAutoresizingMaskIntoConstraints=NO;
    [card addSubview:tl];

    self.bar=[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.bar.trackTintColor=[UIColor colorWithWhite:0.22 alpha:1];
    self.bar.progressTintColor=[UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];
    self.bar.layer.cornerRadius=3; self.bar.clipsToBounds=YES;
    self.bar.translatesAutoresizingMaskIntoConstraints=NO;
    [card addSubview:self.bar];

    self.percentLabel=[UILabel new];
    self.percentLabel.text=@"0%";
    self.percentLabel.textColor=[UIColor colorWithWhite:0.55 alpha:1];
    self.percentLabel.font=[UIFont boldSystemFontOfSize:11];
    self.percentLabel.textAlignment=NSTextAlignmentRight;
    self.percentLabel.translatesAutoresizingMaskIntoConstraints=NO;
    [card addSubview:self.percentLabel];

    self.logView=[UITextView new];
    self.logView.backgroundColor=[UIColor colorWithWhite:0.04 alpha:1];
    self.logView.textColor=[UIColor colorWithRed:0.42 green:0.98 blue:0.58 alpha:1];
    self.logView.font=[UIFont fontWithName:@"Courier" size:10]?:[UIFont systemFontOfSize:10];
    self.logView.editable=NO; self.logView.selectable=NO;
    self.logView.layer.cornerRadius=8; self.logView.text=@"";
    self.logView.translatesAutoresizingMaskIntoConstraints=NO;
    [card addSubview:self.logView];

    self.openLinkBtn=[UIButton buttonWithType:UIButtonTypeCustom];
    [self.openLinkBtn setTitle:@"🌐  Open Link" forState:UIControlStateNormal];
    [self.openLinkBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.openLinkBtn.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    self.openLinkBtn.backgroundColor=[UIColor colorWithRed:0.16 green:0.52 blue:0.92 alpha:1];
    self.openLinkBtn.layer.cornerRadius=9; self.openLinkBtn.hidden=YES;
    self.openLinkBtn.translatesAutoresizingMaskIntoConstraints=NO;
    [self.openLinkBtn addTarget:self action:@selector(openLink) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.openLinkBtn];

    self.closeBtn=[UIButton buttonWithType:UIButtonTypeCustom];
    [self.closeBtn setTitle:@"Close" forState:UIControlStateNormal];
    [self.closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeBtn.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    self.closeBtn.backgroundColor=[UIColor colorWithWhite:0.20 alpha:1];
    self.closeBtn.layer.cornerRadius=9; self.closeBtn.hidden=YES;
    self.closeBtn.translatesAutoresizingMaskIntoConstraints=NO;
    [self.closeBtn addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.closeBtn];

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:310],
        [tl.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
        [tl.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [tl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [self.bar.topAnchor constraintEqualToAnchor:tl.bottomAnchor constant:14],
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

-(void)setProgress:(float)p label:(NSString*)label {
    dispatch_async(dispatch_get_main_queue(),^{
        [self.bar setProgress:MAX(0,MIN(1,p)) animated:YES];
        self.percentLabel.text=label?:[NSString stringWithFormat:@"%.0f%%",p*100];
    });
}
-(void)appendLog:(NSString*)msg {
    dispatch_async(dispatch_get_main_queue(),^{
        NSDateFormatter *f=[NSDateFormatter new]; f.dateFormat=@"HH:mm:ss";
        NSString *line=[NSString stringWithFormat:@"[%@] %@\n",
                        [f stringFromDate:[NSDate date]],msg];
        self.logView.text=[self.logView.text stringByAppendingString:line];
        if (self.logView.text.length)
            [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length-1,1)];
    });
}
-(void)finish:(BOOL)ok message:(NSString*)msg link:(NSString*)link {
    dispatch_async(dispatch_get_main_queue(),^{
        [self setProgress:1.0 label:ok?@"✓ Done":@"✗ Failed"];
        self.percentLabel.textColor=ok
            ?[UIColor colorWithRed:0.25 green:0.88 blue:0.45 alpha:1]
            :[UIColor colorWithRed:0.90 green:0.28 blue:0.28 alpha:1];
        if (msg.length) [self appendLog:msg];
        self.uploadedLink=link;
        if (link.length) self.openLinkBtn.hidden=NO;
        self.closeBtn.hidden=NO;
        self.closeBtn.backgroundColor=ok
            ?[UIColor colorWithWhite:0.22 alpha:1]
            :[UIColor colorWithRed:0.55 green:0.14 blue:0.14 alpha:1];
    });
}
-(void)openLink {
    NSURL *url=[NSURL URLWithString:self.uploadedLink];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}
-(void)dismiss {
    [UIView animateWithDuration:0.18 animations:^{self.alpha=0;}
                     completion:^(BOOL _){[self removeFromSuperview];}];
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Upload / Load helpers
// ─────────────────────────────────────────────────────────────────────────────
static void writeDataFiles(NSDictionary *dataMap, SKProgressOverlay *ov,
                            void (^done)(NSUInteger)) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    if (![dataMap isKindOfClass:[NSDictionary class]] || !dataMap.count) {
        [ov appendLog:@"No .data files to write."]; done(0); return;
    }
    NSUInteger total=dataMap.count; __block NSUInteger fi=0,applied=0;
    for (NSString *fname in dataMap) {
        id raw=dataMap[fname];
        if (![raw isKindOfClass:[NSString class]] || !((NSString*)raw).length) {
            [ov appendLog:[NSString stringWithFormat:@"⚠ %@ — skipped",[fname lastPathComponent]]];
            fi++; continue;
        }
        NSString *text=(NSString*)raw;
        NSString *dst=[docs stringByAppendingPathComponent:[fname lastPathComponent]];
        [[NSFileManager defaultManager] removeItemAtPath:dst error:nil];
        NSError *we=nil;
        if ([text writeToFile:dst atomically:YES encoding:NSUTF8StringEncoding error:&we]) {
            applied++;
            [ov appendLog:[NSString stringWithFormat:@"✓ %@",[fname lastPathComponent]]];
        } else {
            [ov appendLog:[NSString stringWithFormat:@"✗ %@ write failed: %@",
                           [fname lastPathComponent],we.localizedDescription?:@"?"]];
        }
        fi++;
        [ov setProgress:0.40f+0.58f*((float)fi/MAX(1.0f,(float)total))
                  label:[NSString stringWithFormat:@"%lu/%lu",(unsigned long)fi,(unsigned long)total]];
    }
    done(applied);
}

static void applyDiffBatch(NSUserDefaults *ud, NSArray *keys, NSDictionary *diff,
                            NSUInteger start, NSUInteger total,
                            SKProgressOverlay *ov, void (^done)(NSUInteger)) {
    if (start >= total) {
        @try { [ud synchronize]; } @catch (...) {}
        done(total); return;
    }
    @autoreleasepool {
        NSUInteger end=MIN(start+kBatch,total);
        for (NSUInteger i=start;i<end;i++) {
            NSString *k=keys[i]; id v=diff[k]; if (!k||!v) continue;
            @try {
                if ([v isKindOfClass:[NSNull class]]) [ud removeObjectForKey:k];
                else [ud setObject:v forKey:k];
            } @catch (...) {}
        }
        if (ov && (start==0 || end==total || end%500==0))
            [ov appendLog:[NSString stringWithFormat:@"  Prefs %lu/%lu…",
                           (unsigned long)end,(unsigned long)total]];
    }
    dispatch_async(dispatch_get_main_queue(),^{
        applyDiffBatch(ud,keys,diff,start+kBatch,total,ov,done);
    });
}

static void performUpload(NSArray<NSString*> *fileNames, SKProgressOverlay *ov,
                           void (^done)(NSString *link, NSString *err)) {
    NSString *uuid=deviceUUID();
    NSURLSession *ses=makeSession();
    NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    [ov appendLog:@"Serialising NSUserDefaults…"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSDictionary *snap=[[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSError *pe=nil; NSData *pData=nil;
    @try {
        pData=[NSPropertyListSerialization dataWithPropertyList:snap
            format:NSPropertyListXMLFormat_v1_0 options:0 error:&pe];
    } @catch (NSException *ex) { done(nil,ex.reason); return; }
    if (pe||!pData) { done(nil,pe.localizedDescription?:@"Plist error"); return; }
    NSString *plistXML=[[NSString alloc] initWithData:pData encoding:NSUTF8StringEncoding];
    if (!plistXML) { done(nil,@"Plist UTF-8 failed"); return; }
    if (getSetting(@"autoRij")) {
        NSString *patched=applyAutoRij(plistXML);
        if (patched!=plistXML) {
            [ov appendLog:@"Auto Rij applied."]; plistXML=patched;
        } else { [ov appendLog:@"Auto Rij: no changes."]; }
    }
    [ov appendLog:[NSString stringWithFormat:@"Prefs: %lu keys",(unsigned long)snap.count]];
    [ov setProgress:0.05 label:@"5%"];
    MPRequest initMP=buildMP(@{@"action":@"upload",@"uuid":uuid,@"playerpref":plistXML},nil,nil,nil);
    skPost(ses,initMP.req,initMP.body,^(NSDictionary *j, NSError *err){
        if (err) { done(nil,err.localizedDescription); return; }
        NSString *link=j[@"link"]?:[NSString stringWithFormat:
            @"https://chillysilly.frfrnocap.men/isk.php?view=%@",uuid];
        [ov appendLog:@"Session created ✓"];
        saveSessionUUID(uuid);
        if (!fileNames.count) { done(link,nil); return; }
        NSUInteger total=fileNames.count;
        __block NSUInteger doneN=0,failN=0;
        dispatch_group_t group=dispatch_group_create();
        for (NSString *fname in fileNames) {
            NSString *path=[docs stringByAppendingPathComponent:fname];
            NSString *text=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            if (!text) {
                [ov appendLog:[NSString stringWithFormat:@"⚠ Skip %@",fname]];
                @synchronized(fileNames){doneN++;failN++;}
                [ov setProgress:0.1f+0.88f*((float)doneN/(float)total)
                          label:[NSString stringWithFormat:@"%lu/%lu",(unsigned long)doneN,(unsigned long)total]];
                continue;
            }
            dispatch_group_enter(group);
            MPRequest fmp=buildMP(@{@"action":@"upload_file",@"uuid":uuid},@"datafile",fname,
                                  [text dataUsingEncoding:NSUTF8StringEncoding]);
            skPost(ses,fmp.req,fmp.body,^(NSDictionary *fj, NSError *ferr){
                @synchronized(fileNames){doneN++;}
                if (ferr) { @synchronized(fileNames){failN++;}
                    [ov appendLog:[NSString stringWithFormat:@"✗ %@: %@",fname,ferr.localizedDescription]];
                } else { [ov appendLog:[NSString stringWithFormat:@"✓ %@",fname]]; }
                [ov setProgress:0.10f+0.88f*((float)doneN/(float)total)
                          label:[NSString stringWithFormat:@"%lu/%lu",(unsigned long)doneN,(unsigned long)total]];
                dispatch_group_leave(group);
            });
        }
        dispatch_group_notify(group,dispatch_get_main_queue(),^{
            if (failN) [ov appendLog:[NSString stringWithFormat:@"⚠ %lu failed",
                                      (unsigned long)failN]];
            done(link,nil);
        });
    });
}

static void performLoad(SKProgressOverlay *ov, void (^done)(BOOL,NSString*)) {
    NSString *uuid=loadSessionUUID();
    if (!uuid.length) { done(NO,@"No session found. Upload first."); return; }
    NSURLSession *ses=makeSession();
    [ov appendLog:[NSString stringWithFormat:@"Session: %@…",
                   [uuid substringToIndex:MIN(8u,(unsigned)uuid.length)]]];
    [ov setProgress:0.08 label:@"8%"];
    MPRequest mp=buildMP(@{@"action":@"load",@"uuid":uuid},nil,nil,nil);
    skPost(ses,mp.req,mp.body,^(NSDictionary *j, NSError *err){
        if (err) { done(NO,err.localizedDescription); return; }
        if ([j[@"changed"] isEqual:@NO]||[j[@"changed"] isEqual:@0]) {
            clearSessionUUID(); done(YES,@"ℹ No changes. Nothing applied."); return;
        }
        [ov setProgress:0.10 label:@"10%"];
        NSString *ppXML=j[@"playerpref"];
        NSDictionary *dataMap=j[@"data"];
        if (!ppXML.length) {
            writeDataFiles(dataMap,ov,^(NSUInteger a){
                clearSessionUUID();
                done(YES,[NSString stringWithFormat:@"✓ Loaded %lu file(s). Restart.",(unsigned long)a]);
            }); return;
        }
        [ov appendLog:@"Parsing Prefs…"];
        NSError *pe=nil; NSDictionary *incoming=nil;
        @try {
            incoming=[NSPropertyListSerialization
                propertyListWithData:[ppXML dataUsingEncoding:NSUTF8StringEncoding]
                             options:NSPropertyListMutableContainersAndLeaves
                              format:nil error:&pe];
        } @catch (...) { incoming=nil; }
        if (pe||![incoming isKindOfClass:[NSDictionary class]]) {
            [ov appendLog:@"⚠ Prefs parse failed — files only…"];
            writeDataFiles(dataMap,ov,^(NSUInteger a){
                clearSessionUUID();
                done(a>0,a>0
                    ?[NSString stringWithFormat:@"⚠ Prefs failed, %lu file(s) applied. Restart.",(unsigned long)a]
                    :@"✗ Prefs parse failed, no files written.");
            }); return;
        }
        NSUserDefaults *ud=[NSUserDefaults standardUserDefaults];
        [ud synchronize];
        NSDictionary *diff=udDiff([ud dictionaryRepresentation],incoming);
        if (!diff.count) {
            [ov appendLog:@"Prefs unchanged."]; [ov setProgress:0.40 label:@"40%"];
            writeDataFiles(dataMap,ov,^(NSUInteger fa){
                clearSessionUUID();
                done(YES,[NSString stringWithFormat:@"✓ Prefs identical, %lu file(s) applied. Restart.",(unsigned long)fa]);
            }); return;
        }
        NSArray *diffKeys=[diff allKeys]; NSUInteger total=diffKeys.count;
        NSUInteger removes=0;
        for (id v in [diff allValues]) if ([v isKindOfClass:[NSNull class]]) removes++;
        [ov appendLog:[NSString stringWithFormat:@"Prefs diff: %lu set, %lu remove",
                       (unsigned long)(total-removes),(unsigned long)removes]];
        applyDiffBatch(ud,diffKeys,diff,0,total,ov,^(NSUInteger changed){
            [ov appendLog:[NSString stringWithFormat:@"Prefs ✓ (%lu changed)",(unsigned long)changed]];
            writeDataFiles(dataMap,ov,^(NSUInteger fa){
                clearSessionUUID();
                done(YES,[NSString stringWithFormat:@"✓ Loaded %lu item(s). Restart.",
                          (unsigned long)((changed>0?1:0)+fa)]);
            });
        });
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKSettingsView
// ─────────────────────────────────────────────────────────────────────────────
@interface SKSettingsView : UIView
+(instancetype)showInView:(UIView*)parent;
@end

@implementation SKSettingsView {
    UIView *_card;
    UISwitch *_rijSw, *_uidSw, *_closeSw;
}

+(instancetype)showInView:(UIView*)parent {
    SKSettingsView *v=[[SKSettingsView alloc] initWithFrame:parent.bounds];
    v.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [parent addSubview:v];
    v.alpha=0;
    [UIView animateWithDuration:0.22 animations:^{v.alpha=1;}];
    return v;
}

-(instancetype)initWithFrame:(CGRect)f {
    self=[super initWithFrame:f];
    if (!self) return nil;
    self.backgroundColor=[UIColor colorWithWhite:0 alpha:0.6];
    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(bgTap:)];
    tap.cancelsTouchesInView=NO;
    [self addGestureRecognizer:tap];
    [self buildCard];
    return self;
}

-(void)bgTap:(UITapGestureRecognizer*)g {
    if (_card&&!CGRectContainsPoint(_card.frame,[g locationInView:self])) [self dismiss];
}

-(UIView*)makeRow:(NSString*)title desc:(NSString*)desc tag:(NSInteger)tag sw:(__strong UISwitch**)outSw {
    UIView *row=[UIView new];
    row.backgroundColor=[UIColor colorWithRed:0.11 green:0.11 blue:0.17 alpha:1];
    row.layer.cornerRadius=10; row.clipsToBounds=YES;
    row.translatesAutoresizingMaskIntoConstraints=NO;

    UISwitch *sw=[UISwitch new];
    sw.onTintColor=[UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];
    sw.tag=tag; sw.translatesAutoresizingMaskIntoConstraints=NO;
    [sw addTarget:self action:@selector(swChanged:) forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];
    if (outSw) *outSw=sw;

    UILabel *tl=[UILabel new];
    tl.text=title; tl.textColor=[UIColor whiteColor];
    tl.font=[UIFont boldSystemFontOfSize:12];
    tl.translatesAutoresizingMaskIntoConstraints=NO;
    [row addSubview:tl];

    UILabel *dl=[UILabel new];
    dl.text=desc; dl.textColor=[UIColor colorWithWhite:0.45 alpha:1];
    dl.font=[UIFont systemFontOfSize:9.5]; dl.numberOfLines=0;
    dl.translatesAutoresizingMaskIntoConstraints=NO;
    [row addSubview:dl];

    [NSLayoutConstraint activateConstraints:@[
        [sw.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [sw.centerYAnchor  constraintEqualToAnchor:row.centerYAnchor],
        [tl.leadingAnchor  constraintEqualToAnchor:row.leadingAnchor constant:12],
        [tl.topAnchor      constraintEqualToAnchor:row.topAnchor constant:10],
        [tl.trailingAnchor constraintLessThanOrEqualToAnchor:sw.leadingAnchor constant:-8],
        [dl.leadingAnchor  constraintEqualToAnchor:row.leadingAnchor constant:12],
        [dl.topAnchor      constraintEqualToAnchor:tl.bottomAnchor constant:3],
        [dl.trailingAnchor constraintLessThanOrEqualToAnchor:sw.leadingAnchor constant:-8],
        [row.bottomAnchor  constraintEqualToAnchor:dl.bottomAnchor constant:10],
    ]];
    return row;
}

-(void)buildCard {
    _card=[UIView new];
    _card.backgroundColor=[UIColor colorWithRed:0.07 green:0.07 blue:0.11 alpha:1];
    _card.layer.cornerRadius=18; _card.clipsToBounds=YES;
    _card.translatesAutoresizingMaskIntoConstraints=NO;
    [self addSubview:_card];

    UILabel *title=[UILabel new];
    title.text=@"⚙  Settings"; title.textColor=[UIColor whiteColor];
    title.font=[UIFont boldSystemFontOfSize:15]; title.textAlignment=NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints=NO;
    [_card addSubview:title];

    UIView *div=[UIView new];
    div.backgroundColor=[UIColor colorWithWhite:0.18 alpha:1];
    div.translatesAutoresizingMaskIntoConstraints=NO;
    [_card addSubview:div];

    UIView *r1=[self makeRow:@"Auto Rij"
        desc:@"Sets OpenRijTest_ flags from 1→0 before uploading."
        tag:1 sw:&_rijSw];
    UIView *r2=[self makeRow:@"Auto Detect UID"
        desc:@"Reads PlayerId from SdkStateCache#1 automatically."
        tag:2 sw:&_uidSw];
    UIView *r3=[self makeRow:@"Auto Close"
        desc:@"Exits app after loading save data."
        tag:3 sw:&_closeSw];
    [_card addSubview:r1]; [_card addSubview:r2]; [_card addSubview:r3];

    UIButton *closeBtn=[UIButton buttonWithType:UIButtonTypeCustom];
    [closeBtn setTitle:@"Close" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    closeBtn.backgroundColor=[UIColor colorWithWhite:0.20 alpha:1];
    closeBtn.layer.cornerRadius=9;
    closeBtn.translatesAutoresizingMaskIntoConstraints=NO;
    [closeBtn addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:closeBtn];

    UILabel *footer=[UILabel new];
    footer.text=[NSString stringWithFormat:@"SK Save Manager v%@ build %@",DYLIB_VERSION,DYLIB_BUILD];
    footer.textColor=[UIColor colorWithWhite:0.28 alpha:1];
    footer.font=[UIFont systemFontOfSize:8.5]; footer.textAlignment=NSTextAlignmentCenter;
    footer.translatesAutoresizingMaskIntoConstraints=NO;
    [_card addSubview:footer];

    [NSLayoutConstraint activateConstraints:@[
        [_card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_card.widthAnchor   constraintEqualToConstant:320],
        [title.topAnchor      constraintEqualToAnchor:_card.topAnchor constant:18],
        [title.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:16],
        [title.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-16],
        [div.topAnchor      constraintEqualToAnchor:title.bottomAnchor constant:10],
        [div.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:12],
        [div.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-12],
        [div.heightAnchor   constraintEqualToConstant:1],
        [r1.topAnchor      constraintEqualToAnchor:div.bottomAnchor constant:10],
        [r1.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:10],
        [r1.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],
        [r2.topAnchor      constraintEqualToAnchor:r1.bottomAnchor constant:8],
        [r2.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:10],
        [r2.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],
        [r3.topAnchor      constraintEqualToAnchor:r2.bottomAnchor constant:8],
        [r3.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:10],
        [r3.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],
        [closeBtn.topAnchor      constraintEqualToAnchor:r3.bottomAnchor constant:14],
        [closeBtn.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:14],
        [closeBtn.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-14],
        [closeBtn.heightAnchor   constraintEqualToConstant:38],
        [footer.topAnchor      constraintEqualToAnchor:closeBtn.bottomAnchor constant:10],
        [footer.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:8],
        [footer.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-8],
        [_card.bottomAnchor    constraintEqualToAnchor:footer.bottomAnchor constant:14],
    ]];

    _rijSw.on=getSetting(@"autoRij");
    _uidSw.on=getSetting(@"autoDetectUID");
    _closeSw.on=getSetting(@"autoClose");
}

-(void)swChanged:(UISwitch*)sw {
    NSString *key;
    switch (sw.tag) {
        case 1: key=@"autoRij"; break;
        case 2: key=@"autoDetectUID"; break;
        case 3: key=@"autoClose"; break;
        default: return;
    }
    setSetting(key,sw.isOn);
}

-(void)dismiss {
    [UIView animateWithDuration:0.18 animations:^{self.alpha=0;}
                     completion:^(BOOL _){[self removeFromSuperview];}];
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKRootViewController (passthrough)
// ─────────────────────────────────────────────────────────────────────────────
@interface SKRootViewController : UIViewController
@end
@implementation SKRootViewController
-(BOOL)prefersStatusBarHidden { return NO; }
-(UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKOverlayWindow
//
//  Dedicated UIWindow at UIWindowLevelAlert+1. No visible UI at rest.
//  TRIGGER: Volume UP then Volume DOWN within 3 seconds → UIAlertController menu.
// ─────────────────────────────────────────────────────────────────────────────
@interface SKOverlayWindow : UIWindow
@property (nonatomic,strong) SKRootViewController *skRoot;
// Volume trigger state
@property (nonatomic,assign) NSTimeInterval volUpTimestamp;  // 0 = not armed
@property (nonatomic,assign) float          lastVolume;
// Error banner
@property (nonatomic,strong) UIView  *bannerView;
@property (nonatomic,strong) UILabel *bannerLbl;
+(instancetype)makeForScene:(UIWindowScene*)scene;
-(void)showError:(NSString*)msg;
-(void)presentAlert:(UIAlertController*)alert;
-(void)openMenu;
@end

static SKOverlayWindow *gOverlay = nil;

static void skError(NSString *context, NSString *detail) {
    if (!context) context=@"?";
    if (!detail)  detail=@"(nil)";
    NSString *msg=[NSString stringWithFormat:@"[SKTools] %@: %@",context,detail];
    NSLog(@"%@",msg);
    dispatch_async(dispatch_get_main_queue(),^{
        @try { [UIPasteboard generalPasteboard].string=msg; } @catch (...) {}
        if (gOverlay) [gOverlay showError:msg];
    });
}

@implementation SKOverlayWindow

+(instancetype)makeForScene:(UIWindowScene*)scene {
    SKOverlayWindow *w;
    if (@available(iOS 13.0,*)) {
        if (scene) w=[[SKOverlayWindow alloc] initWithWindowScene:scene];
        else       w=[[SKOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    } else {
        w=[[SKOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    return w;
}

-(instancetype)initWithWindowScene:(UIWindowScene*)scene {
    if (@available(iOS 13.0,*)) { self=[super initWithWindowScene:scene]; }
    else                        { self=[super initWithFrame:[UIScreen mainScreen].bounds]; }
    if (!self) return nil;
    [self setup];
    return self;
}

-(instancetype)initWithFrame:(CGRect)f {
    self=[super initWithFrame:f];
    if (!self) return nil;
    [self setup];
    return self;
}

-(void)setup {
    self.windowLevel=UIWindowLevelAlert+1;
    self.backgroundColor=[UIColor clearColor];
    self.opaque=NO;

    _skRoot=[SKRootViewController new];
    _skRoot.view.backgroundColor=[UIColor clearColor];
    _skRoot.view.opaque=NO;
    self.rootViewController=_skRoot;

    [self buildBanner];
    [self startVolumeMonitor];
    [self makeKeyAndVisible];
}

// ── Banner ─────────────────────────────────────────────────────────────────
-(void)buildBanner {
    _bannerView=[UIView new];
    _bannerView.backgroundColor=[UIColor colorWithRed:0.75 green:0.10 blue:0.10 alpha:0.95];
    _bannerView.layer.cornerRadius=10; _bannerView.alpha=0;
    _bannerView.translatesAutoresizingMaskIntoConstraints=NO;
    [_skRoot.view addSubview:_bannerView];

    _bannerLbl=[UILabel new];
    _bannerLbl.textColor=[UIColor whiteColor];
    _bannerLbl.font=[UIFont systemFontOfSize:11]; _bannerLbl.numberOfLines=0;
    _bannerLbl.translatesAutoresizingMaskIntoConstraints=NO;
    [_bannerView addSubview:_bannerLbl];

    [NSLayoutConstraint activateConstraints:@[
        [_bannerView.leadingAnchor  constraintEqualToAnchor:_skRoot.view.safeAreaLayoutGuide.leadingAnchor  constant:12],
        [_bannerView.trailingAnchor constraintEqualToAnchor:_skRoot.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [_bannerView.topAnchor      constraintEqualToAnchor:_skRoot.view.safeAreaLayoutGuide.topAnchor constant:8],
        [_bannerLbl.topAnchor       constraintEqualToAnchor:_bannerView.topAnchor constant:8],
        [_bannerLbl.bottomAnchor    constraintEqualToAnchor:_bannerView.bottomAnchor constant:-8],
        [_bannerLbl.leadingAnchor   constraintEqualToAnchor:_bannerView.leadingAnchor constant:10],
        [_bannerLbl.trailingAnchor  constraintEqualToAnchor:_bannerView.trailingAnchor constant:-10],
    ]];
}

-(void)showError:(NSString*)msg {
    dispatch_async(dispatch_get_main_queue(),^{
        @try {
            [UIPasteboard generalPasteboard].string=msg;
            _bannerLbl.text=[NSString stringWithFormat:@"⚠ %@\n(copied to clipboard)",msg];
            [_skRoot.view bringSubviewToFront:_bannerView];
            _bannerView.alpha=0;
            [UIView animateWithDuration:0.2 animations:^{_bannerView.alpha=1;}
                             completion:^(BOOL _){
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(4*NSEC_PER_SEC)),
                               dispatch_get_main_queue(),^{
                    [UIView animateWithDuration:0.4 animations:^{_bannerView.alpha=0;}];
                });
            }];
        } @catch (...) {}
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Volume Monitor
//   Press Vol UP → arms trigger.
//   Press Vol DOWN within 3 s → opens menu.
//   Any other order or timeout → resets state silently.
// ─────────────────────────────────────────────────────────────────────────────
-(void)startVolumeMonitor {
    @try {
        AVAudioSession *session=[AVAudioSession sharedInstance];
        NSError *err=nil;
        [session setActive:YES error:&err];
        _lastVolume=session.outputVolume;
        _volUpTimestamp=0;
        [session addObserver:self
                  forKeyPath:@"outputVolume"
                     options:NSKeyValueObservingOptionNew
                     context:nil];
        NSLog(@"[SKTools] Volume monitor ready — Vol UP then Vol DOWN within 3s opens menu");
    } @catch (NSException *ex) {
        NSLog(@"[SKTools] startVolumeMonitor failed: %@", ex.reason);
    }
}

-(void)observeValueForKeyPath:(NSString*)keyPath
                     ofObject:(id)object
                       change:(NSDictionary*)change
                      context:(void*)context {
    if (![keyPath isEqualToString:@"outputVolume"]) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    @try {
        float newVol = [[change objectForKey:NSKeyValueChangeNewKey] floatValue];
        float prev   = _lastVolume;
        _lastVolume  = newVol;

        // Use a threshold of 0.01 to ignore tiny floating-point noise
        if (newVol > prev + 0.01f) {
            // ── Volume UP pressed ──────────────────────────────────────────
            _volUpTimestamp = [NSDate date].timeIntervalSinceReferenceDate;
            NSLog(@"[SKTools] Vol UP (%.2f→%.2f) armed, waiting for Vol DOWN…", prev, newVol);

        } else if (newVol < prev - 0.01f) {
            // ── Volume DOWN pressed ────────────────────────────────────────
            NSTimeInterval now = [NSDate date].timeIntervalSinceReferenceDate;
            if (_volUpTimestamp > 0 && (now - _volUpTimestamp) <= 3.0) {
                _volUpTimestamp = 0;
                NSLog(@"[SKTools] Sequence matched — opening menu");
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self openMenu];
                });
            } else {
                // No prior UP within window — reset
                _volUpTimestamp = 0;
            }
        }
    } @catch (...) {}
}

-(void)dealloc {
    @try {
        [[AVAudioSession sharedInstance] removeObserver:self forKeyPath:@"outputVolume"];
    } @catch (...) {}
}

// ── Touch passthrough for transparent root view ────────────────────────────
-(UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    UIView *hit=[super hitTest:point withEvent:event];
    // Return nil for our own transparent root so touches pass to the game
    if (hit==_skRoot.view) return nil;
    return hit;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Main Menu (UIAlertController)
// ─────────────────────────────────────────────────────────────────────────────
-(void)openMenu {
    @try {
        if (_skRoot.presentedViewController) {
            [_skRoot dismissViewControllerAnimated:NO completion:^{ [self showMainMenu]; }];
        } else {
            [self showMainMenu];
        }
    } @catch (NSException *ex) {
        skError(@"openMenu", ex.reason);
    }
}

-(void)showMainMenu {
    NSString *session = loadSessionUUID();
    NSString *sessionNote = session
        ? [NSString stringWithFormat:@"Session: %@…",
           [session substringToIndex:MIN(8u,(unsigned)session.length)]]
        : @"No active session";

    NSString *uidNote = @"";
    if (getSetting(@"autoDetectUID")) {
        NSString *uid = detectPlayerUID();
        uidNote = uid
            ? [NSString stringWithFormat:@"\nUID: %@", uid]
            : @"\nUID: not found";
    }

    NSString *msg = [NSString stringWithFormat:@"%@%@\n\nv%@ build %@",
                     sessionNote, uidNote, DYLIB_VERSION, DYLIB_BUILD];

    // Action sheet on iPhone; plain alert on iPad (action sheet without popover crashes on iPad)
    UIAlertControllerStyle style = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        ? UIAlertControllerStyleAlert
        : UIAlertControllerStyleActionSheet;

    UIAlertController *menu = [UIAlertController
        alertControllerWithTitle:@"💾 SK Save Manager"
                         message:msg
                  preferredStyle:style];

    [menu addAction:[UIAlertAction
        actionWithTitle:@"⬆  Upload to Cloud"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){ [self tapUpload]; }]];

    [menu addAction:[UIAlertAction
        actionWithTitle:@"⬇  Load from Cloud"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){ [self tapLoad]; }]];

    [menu addAction:[UIAlertAction
        actionWithTitle:@"⚙  Settings"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.15*NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [SKSettingsView showInView:_skRoot.view];
            });
        }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];

    [self presentAlert:menu];
}

// ── Alert presenter ─────────────────────────────────────────────────────────
-(void)presentAlert:(UIAlertController*)alert {
    @try {
        if (!alert) return;
        // iPad requires a source for popovers — anchor to screen centre
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = _skRoot.view;
            alert.popoverPresentationController.sourceRect =
                CGRectMake(CGRectGetMidX(_skRoot.view.bounds),
                           CGRectGetMidY(_skRoot.view.bounds), 1, 1);
            alert.popoverPresentationController.permittedArrowDirections = 0;
        }
        if (_skRoot.presentedViewController) {
            [_skRoot dismissViewControllerAnimated:NO completion:^{
                [_skRoot presentViewController:alert animated:YES completion:nil];
            }];
        } else {
            [_skRoot presentViewController:alert animated:YES completion:nil];
        }
    } @catch (NSException *ex) {
        skError(@"presentAlert", ex.reason);
        [self showError:ex.reason?:@"Alert failed"];
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Upload action
// ─────────────────────────────────────────────────────────────────────────────
-(void)tapUpload {
    @try {
        NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        NSArray *all=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil]?:@[];
        NSMutableArray *dataFiles=[NSMutableArray new];
        for (NSString *f in all)
            if ([f.pathExtension.lowercaseString isEqualToString:@"data"]) [dataFiles addObject:f];

        UIAlertController *choice=[UIAlertController
            alertControllerWithTitle:@"Upload Save"
                             message:[NSString stringWithFormat:@"Found %lu .data file(s)%@",
                                      (unsigned long)dataFiles.count,
                                      loadSessionUUID()?@"\n⚠ Existing session overwritten.":@""]
                      preferredStyle:UIAlertControllerStyleAlert];

        [choice addAction:[UIAlertAction
            actionWithTitle:[NSString stringWithFormat:@"Upload All (%lu)",(unsigned long)dataFiles.count]
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *a){ [self confirmAndUpload:dataFiles]; }]];

        [choice addAction:[UIAlertAction actionWithTitle:@"Specific UID…"
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *a){
                if (getSetting(@"autoDetectUID")) {
                    NSString *uid=detectPlayerUID();
                    if (!uid.length) {
                        [self alert:@"UID Not Found" msg:@"Enter UID manually." then:^{[self askUID:dataFiles];}];
                        return;
                    }
                    NSMutableArray *f=[NSMutableArray new];
                    for (NSString *fn in dataFiles) if ([fn containsString:uid]) [f addObject:fn];
                    if (!f.count) { [self alert:@"No Files" msg:[NSString stringWithFormat:@"UID \"%@\" matched nothing.",uid] then:nil]; return; }
                    [self confirmAndUpload:f];
                } else { [self askUID:dataFiles]; }
            }]];

        [choice addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentAlert:choice];
    } @catch (NSException *ex) {
        skError(@"tapUpload",ex.reason);
        [self showError:ex.reason?:@"Upload init failed"];
    }
}

-(void)askUID:(NSArray*)files {
    UIAlertController *a=[UIAlertController
        alertControllerWithTitle:@"Enter UID"
                         message:@"Only .data files whose filename contains this UID will be uploaded."
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.placeholder=@"e.g. 211062956"; tf.keyboardType=UIKeyboardTypeNumberPad;
        tf.clearButtonMode=UITextFieldViewModeWhileEditing;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Upload" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){
            NSString *uid=[a.textFields.firstObject.text
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!uid.length) { [self alert:@"No UID" msg:@"Please enter a UID." then:nil]; return; }
            NSMutableArray *f=[NSMutableArray new];
            for (NSString *fn in files) if ([fn containsString:uid]) [f addObject:fn];
            if (!f.count) { [self alert:@"No Files" msg:[NSString stringWithFormat:@"No file contains \"%@\".",uid] then:nil]; return; }
            [self confirmAndUpload:f];
        }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:a];
}

-(void)confirmAndUpload:(NSArray*)files {
    NSString *rij=getSetting(@"autoRij")?@"\n• Auto Rij ON":@"";
    NSString *flist=files.count<=5?[files componentsJoinedByString:@"\n"]
        :[[files subarrayWithRange:NSMakeRange(0,5)] componentsJoinedByString:@"\n"];
    UIAlertController *c=[UIAlertController
        alertControllerWithTitle:@"Confirm Upload"
                         message:[NSString stringWithFormat:
            @"Will upload:\n• PlayerPrefs%@\n• %lu .data file(s):\n%@",
            rij,(unsigned long)files.count,flist]
                  preferredStyle:UIAlertControllerStyleAlert];
    [c addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [c addAction:[UIAlertAction actionWithTitle:@"Yes, Upload" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){
            @try {
                SKProgressOverlay *ov=[SKProgressOverlay showInView:_skRoot.view title:@"Uploading…"];
                performUpload(files,ov,^(NSString *link, NSString *err){
                    if (err) {
                        [ov finish:NO message:[NSString stringWithFormat:@"✗ %@",err] link:nil];
                        skError(@"upload",err); [self showError:err];
                    } else {
                        [UIPasteboard generalPasteboard].string=link;
                        [ov appendLog:@"Link copied to clipboard."];
                        [ov finish:YES message:@"Upload complete ✓" link:link];
                    }
                });
            } @catch (NSException *ex) {
                skError(@"confirmUpload",ex.reason);
                [self showError:ex.reason?:@"Upload crashed"];
            }
        }]];
    [self presentAlert:c];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Load action
// ─────────────────────────────────────────────────────────────────────────────
-(void)tapLoad {
    @try {
        if (!loadSessionUUID().length) {
            [self alert:@"No Session" msg:@"No upload session found. Upload first." then:nil];
            return;
        }
        NSString *closeNote=getSetting(@"autoClose")?@"\n\n⚠ Auto Close ON — app exits after loading.":@"";
        UIAlertController *a=[UIAlertController
            alertControllerWithTitle:@"Load Save"
                             message:[NSString stringWithFormat:
                @"Download edited save and apply?\nSession deleted after loading.%@",closeNote]
                      preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Yes, Load" style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *_){
                @try {
                    SKProgressOverlay *ov=[SKProgressOverlay showInView:_skRoot.view title:@"Loading…"];
                    performLoad(ov,^(BOOL ok, NSString *msg){
                        [ov finish:ok message:msg link:nil];
                        if (!ok) { skError(@"load",msg); [self showError:msg?:@"Load failed"]; }
                        if (ok&&getSetting(@"autoClose"))
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.6*NSEC_PER_SEC)),
                                           dispatch_get_main_queue(),^{ exit(0); });
                    });
                } @catch (NSException *ex) {
                    skError(@"tapLoad",ex.reason);
                    [self showError:ex.reason?:@"Load crashed"];
                }
            }]];
        [self presentAlert:a];
    } @catch (NSException *ex) {
        skError(@"tapLoad",ex.reason);
        [self showError:ex.reason?:@"Load init failed"];
    }
}

-(void)alert:(NSString*)title msg:(NSString*)msg then:(void(^)(void))then {
    UIAlertController *a=[UIAlertController
        alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){ if (then) then(); }]];
    [self presentAlert:a];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Injection
// ─────────────────────────────────────────────────────────────────────────────
static void tryInject(void) {
    @try {
        if (gOverlay) return;
        UIWindowScene *scene = nil;
        if (@available(iOS 13.0,*)) scene = activeWindowScene();
        gOverlay = [SKOverlayWindow makeForScene:scene];
        if (!gOverlay) {
            skError(@"inject",@"SKOverlayWindow returned nil");
        } else {
            NSLog(@"[SKTools] v11.1 injected ✓ — trigger: Vol UP → Vol DOWN within 3s");
        }
    } @catch (NSException *ex) {
        NSString *msg=ex.reason?:@"Unknown injection exception";
        NSLog(@"[SKTools] inject exception: %@",msg);
        dispatch_async(dispatch_get_main_queue(),^{
            @try { [UIPasteboard generalPasteboard].string=
                [NSString stringWithFormat:@"[SKTools] inject failed: %@",msg]; } @catch (...) {}
        });
    }
}

%hook UIViewController
-(void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (@available(iOS 13.0,*)) {
            [[NSNotificationCenter defaultCenter]
                addObserverForName:UISceneDidActivateNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *n){
                    if (!gOverlay) tryInject();
                }];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.8*NSEC_PER_SEC)),
                       dispatch_get_main_queue(),^{ if (!gOverlay) tryInject(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2.0*NSEC_PER_SEC)),
                       dispatch_get_main_queue(),^{ if (!gOverlay) tryInject(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(4.0*NSEC_PER_SEC)),
                       dispatch_get_main_queue(),^{
            if (!gOverlay) {
                tryInject();
                if (!gOverlay) {
                    @try {
                        [UIPasteboard generalPasteboard].string=
                            @"[SKTools] FATAL: All 4 injection attempts failed.";
                    } @catch (...) {}
                }
            }
        });
    });
}
%end
