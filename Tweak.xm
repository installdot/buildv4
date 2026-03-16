#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <dlfcn.h>

// ═════════════════════════════════════════════════════════════════════════════
//  UNITOREIOS DEV TOOL
//  • Priority 101 constructor — hooks armed before Unitoreios +load
//  • Force offline on/off (persistent)
//  • Live remainingSeconds counter
//  • +7 days button
//  • Inject fake cached session (all 5 guards)
//  • Dump all decrypted constants + session state
//
//  FIX: All Unitoreios globals resolved via dlsym(RTLD_DEFAULT) at runtime.
//       extern declarations cause linker errors because the symbols live in
//       the app binary, not a linked library.
// ═════════════════════════════════════════════════════════════════════════════

#define SEVEN_DAYS       604800
#define kForceOfflineKey @"com.yourname.devtool.forceOffline"
#define kFakeSessionKey  @"com.yourname.devtool.fakeSessionKey"

// ── Unitoreios interface ──────────────────────────────────────────────────────
@interface Unitoreios : NSObject
@property (nonatomic, assign) NSInteger remainingSeconds;
- (void)startUpdateTimer;
- (NSString *)effectiveDebHash;
- (NSString *)effectiveBaseURL;
- (NSString *)effectivePackageDisplayName;
@end

static Unitoreios *gExtraInfo      = nil;
static NSString   *gCapturedAESKey = nil;
static NSString   *gCapturedAESIV  = nil;

// ═════════════════════════════════════════════════════════════════════════════
//  RUNTIME SYMBOL RESOLUTION via dlsym
//
//  Every NSString* global in Unitoreios.mm is accessed through a cached
//  pointer-to-pointer so we never need extern / link-time resolution.
//
//  Naming convention:  _ptr_<symbolname>
//  Read:   GET(symbolname)          → NSString*  (nil if not resolved)
//  Write:  SET(symbolname, value)   → assigns through the pointer
// ═════════════════════════════════════════════════════════════════════════════
static NSString **_ptr_iskey                = NULL;
static NSString **_ptr_keyValidationStatus  = NULL;
static NSString **_ptr_encodedcode          = NULL;
static NSString **_ptr_encodestring         = NULL;
static NSString **_ptr___kHashDefaultValue  = NULL;
static NSString **_ptr___kBaseURL           = NULL;
static NSString **_ptr_kKeyEncoded          = NULL;
static NSString **_ptr_kIVEncoded           = NULL;

static void resolveSymbols(void) {
    // dlsym looks up by mangled C name.
    // ObjC file-scope NSString* vars are exported as _varname.
    // NSString * const vars with leading __ get ___varname (3 underscores).
    _ptr_iskey               = (NSString **)dlsym(RTLD_DEFAULT, "_iskey");
    _ptr_keyValidationStatus = (NSString **)dlsym(RTLD_DEFAULT, "_keyValidationStatus");
    _ptr_encodedcode         = (NSString **)dlsym(RTLD_DEFAULT, "_encodedcode");
    _ptr_encodestring        = (NSString **)dlsym(RTLD_DEFAULT, "_encodestring");
    _ptr___kHashDefaultValue = (NSString **)dlsym(RTLD_DEFAULT, "___kHashDefaultValue");
    _ptr___kBaseURL          = (NSString **)dlsym(RTLD_DEFAULT, "___kBaseURL");
    _ptr_kKeyEncoded         = (NSString **)dlsym(RTLD_DEFAULT, "_kKeyEncoded");
    _ptr_kIVEncoded          = (NSString **)dlsym(RTLD_DEFAULT, "_kIVEncoded");

    NSLog(@"[DevTool] symbol resolution:");
    NSLog(@"[DevTool]   iskey               %@", _ptr_iskey               ? @"OK" : @"MISSING");
    NSLog(@"[DevTool]   keyValidationStatus %@", _ptr_keyValidationStatus ? @"OK" : @"MISSING");
    NSLog(@"[DevTool]   encodedcode         %@", _ptr_encodedcode         ? @"OK" : @"MISSING");
    NSLog(@"[DevTool]   encodestring        %@", _ptr_encodestring        ? @"OK" : @"MISSING");
    NSLog(@"[DevTool]   __kHashDefaultValue %@", _ptr___kHashDefaultValue ? @"OK" : @"MISSING");
    NSLog(@"[DevTool]   __kBaseURL          %@", _ptr___kBaseURL          ? @"OK" : @"MISSING");
    NSLog(@"[DevTool]   kKeyEncoded         %@", _ptr_kKeyEncoded         ? @"OK" : @"MISSING");
    NSLog(@"[DevTool]   kIVEncoded          %@", _ptr_kIVEncoded          ? @"OK" : @"MISSING");
}

// safe read — returns nil if pointer not resolved
#define GET(sym)      (_ptr_##sym ? *_ptr_##sym : nil)
// safe write — no-op if pointer not resolved
#define SET(sym, val) do { if (_ptr_##sym) *_ptr_##sym = (val); } while(0)

// ═════════════════════════════════════════════════════════════════════════════
//  SAFE TOP VIEW CONTROLLER
// ═════════════════════════════════════════════════════════════════════════════
static UIViewController *topVC(void) {
    UIWindow *win = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in [(UIWindowScene *)scene windows]) {
                    if (w.isKeyWindow) { win = w; break; }
                }
                if (win) break;
            }
        }
    }
    if (!win) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        win = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    }
    UIViewController *vc = win.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

// ═════════════════════════════════════════════════════════════════════════════
//  PERSISTENCE
// ═════════════════════════════════════════════════════════════════════════════
static BOOL forceOfflineEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kForceOfflineKey];
}
static void setForceOffline(BOOL on) {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:kForceOfflineKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSLog(@"[DevTool] ForceOffline → %@", on ? @"ON" : @"OFF");
}

// ═════════════════════════════════════════════════════════════════════════════
//  SESSION INJECTION — writes all 5 guards +paid: checks simultaneously
// ═════════════════════════════════════════════════════════════════════════════
static void injectFakeSession(NSInteger seconds) {
    // pick the best key string available
    NSString *keyToUse = GET(iskey);
    if (!keyToUse.length)
        keyToUse = [[NSUserDefaults standardUserDefaults] objectForKey:@"savedKey"];
    if (!keyToUse.length)
        keyToUse = [[NSUserDefaults standardUserDefaults] objectForKey:kFakeSessionKey];
    if (!keyToUse.length) {
        keyToUse = [NSString stringWithFormat:@"DEVTOOL-%@",
                    [[[NSUUID UUID] UUIDString] substringToIndex:8]];
        [[NSUserDefaults standardUserDefaults] setObject:keyToUse forKey:kFakeSessionKey];
    }

    // 1. disk  — savedKey
    [[NSUserDefaults standardUserDefaults] setObject:keyToUse forKey:@"savedKey"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // 2. RAM   — iskey
    SET(iskey, keyToUse);

    // 3. RAM   — keyValidationStatus
    SET(keyValidationStatus, @"validated");

    // 4. RAM   — encodedcode must equal encodestring
    NSString *es = GET(encodestring);
    SET(encodedcode, es ? [es copy] : @"odsugddhwxbc==");

    // 5. RAM   — remainingSeconds on extraInfo singleton
    if (gExtraInfo) gExtraInfo.remainingSeconds = seconds;

    NSLog(@"[DevTool] session injected → key=%@  secs=%ld  status=%@  encodedcode=%@",
          keyToUse, (long)seconds, GET(keyValidationStatus), GET(encodedcode));
}

// ═════════════════════════════════════════════════════════════════════════════
//  FORMAT HELPERS
// ═════════════════════════════════════════════════════════════════════════════
static NSString *fmtSec(NSInteger s) {
    if (s <= 0) return @"EXPIRED";
    NSInteger d=s/86400; s%=86400;
    NSInteger h=s/3600;  s%=3600;
    NSInteger m=s/60;    s%=60;
    return [NSString stringWithFormat:@"%02ldd %02ldh %02ldm %02lds",
            (long)d,(long)h,(long)m,(long)s];
}
static NSString *safe(NSString *s) {
    return (s.length > 0) ? s : @"(not set)";
}

// ═════════════════════════════════════════════════════════════════════════════
//  BLOCK CATEGORIES
// ═════════════════════════════════════════════════════════════════════════════
@interface UIButton (DT)
- (void)dt_onTap:(void(^)(void))b;
@end
@implementation UIButton (DT)
static char kBK;
- (void)dt_onTap:(void(^)(void))b {
    objc_setAssociatedObject(self,&kBK,b,OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self addTarget:self action:@selector(dt_f)
          forControlEvents:UIControlEventTouchUpInside];
}
- (void)dt_f { void(^b)(void)=objc_getAssociatedObject(self,&kBK); if(b)b(); }
@end

@interface UITapGestureRecognizer (DT)
- (void)dt_onTap:(void(^)(UITapGestureRecognizer*))b;
@end
@implementation UITapGestureRecognizer (DT)
static char kTK;
- (void)dt_onTap:(void(^)(UITapGestureRecognizer*))b {
    objc_setAssociatedObject(self,&kTK,b,OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self addTarget:self action:@selector(dt_tf)];
}
- (void)dt_tf {
    void(^b)(UITapGestureRecognizer*)=objc_getAssociatedObject(self,&kTK);
    if(b)b(self);
}
@end

// ═════════════════════════════════════════════════════════════════════════════
//  DUMP POPUP
// ═════════════════════════════════════════════════════════════════════════════
static void addSection(NSMutableArray *rows, NSString *title) {
    [rows addObject:@[@"S", title]];
}
static void addRow(NSMutableArray *rows, NSString *key, NSString *val) {
    [rows addObject:@[@"R", key, val ?: @"(null)"]];
}

static void showDumpPopup(void) {
    UIViewController *root = topVC();
    NSMutableArray<NSArray<NSString*>*> *rows = [NSMutableArray array];

    // read all syms once
    NSString *iskeyVal     = GET(iskey);
    NSString *kvStatus     = GET(keyValidationStatus);
    NSString *encCode      = GET(encodedcode);
    NSString *encStr       = GET(encodestring);
    NSString *hashVal      = GET(__kHashDefaultValue);
    NSString *baseURLVal   = GET(__kBaseURL);
    NSString *keyEncVal    = GET(kKeyEncoded);
    NSString *ivEncVal     = GET(kIVEncoded);
    BOOL match             = encCode && encStr && [encCode isEqualToString:encStr];
    NSInteger sec          = gExtraInfo ? gExtraInfo.remainingSeconds : 0;
    NSString *savedKey     = [[NSUserDefaults standardUserDefaults] objectForKey:@"savedKey"];
    NSString *savedUDID    = [[NSUserDefaults standardUserDefaults] objectForKey:@"savedUDID"];

    addSection(rows, @"Package & Hash");
    addRow(rows, @"__kHashDefaultValue",  safe(hashVal));
    addRow(rows, @"__kBaseURL",           safe(baseURLVal));
    addRow(rows, @"effectiveDebHash",     gExtraInfo ? safe([gExtraInfo effectiveDebHash])           : @"(no session)");
    addRow(rows, @"effectiveBaseURL",     gExtraInfo ? safe([gExtraInfo effectiveBaseURL])           : @"(no session)");
    addRow(rows, @"Package display name", gExtraInfo ? safe([gExtraInfo effectivePackageDisplayName]): @"(no session)");

    addSection(rows, @"AES Crypto");
    addRow(rows, @"UNITOREIOS_AES_KEY",    safe(gCapturedAESKey));
    addRow(rows, @"UNITOREIOS_AES_IV",     safe(gCapturedAESIV));
    addRow(rows, @"kKeyEncoded (raw b64)", safe(keyEncVal));
    addRow(rows, @"kIVEncoded  (raw b64)", safe(ivEncVal));

    addSection(rows, @"Integrity Tokens");
    addRow(rows, @"encodestring  (const)",  safe(encStr));
    addRow(rows, @"encodedcode   (runtime)", safe(encCode));
    addRow(rows, @"tokens match?",           match ? @"YES ✓" : @"NO ✗");

    addSection(rows, @"Session State");
    addRow(rows, @"keyValidationStatus", safe(kvStatus));
    addRow(rows, @"iskey (RAM)",         safe(iskeyVal));
    addRow(rows, @"savedKey (disk)",     safe(savedKey));
    NSString *secStr = [NSString stringWithFormat:@"%ld  (%@)", (long)sec, fmtSec(sec)];
    addRow(rows, @"remainingSeconds",    secStr);
    addRow(rows, @"savedUDID",           safe(savedUDID));

    addSection(rows, @"5-Guard Check (+paid:)");
    BOOL g1 = iskeyVal.length > 0;
    BOOL g2 = [kvStatus isEqualToString:@"validated"];
    BOOL g3 = match;
    BOOL g4 = iskeyVal.length > 0 && savedKey.length > 0 && [iskeyVal isEqualToString:savedKey];
    BOOL g5 = sec > 0;
    addRow(rows, @"1  iskey != nil",        g1 ? @"PASS ✓" : @"FAIL ✗");
    addRow(rows, @"2  keyValidationStatus", g2 ? @"PASS ✓" : @"FAIL ✗");
    addRow(rows, @"3  encodedcode==const",  g3 ? @"PASS ✓" : @"FAIL ✗");
    addRow(rows, @"4  iskey==savedKey",     g4 ? @"PASS ✓" : @"FAIL ✗");
    addRow(rows, @"5  remainingSeconds>0",  g5 ? @"PASS ✓" : @"FAIL ✗");
    addRow(rows, @"→  +paid: result",       (g1&&g2&&g3&&g4&&g5) ? @"EXECUTE ✓" : @"BLOCK ✗");

    addSection(rows, @"Symbol Resolution");
    addRow(rows, @"iskey ptr",               _ptr_iskey               ? @"resolved ✓" : @"MISSING ✗");
    addRow(rows, @"keyValidationStatus ptr", _ptr_keyValidationStatus ? @"resolved ✓" : @"MISSING ✗");
    addRow(rows, @"encodedcode ptr",         _ptr_encodedcode         ? @"resolved ✓" : @"MISSING ✗");
    addRow(rows, @"encodestring ptr",        _ptr_encodestring        ? @"resolved ✓" : @"MISSING ✗");
    addRow(rows, @"__kHashDefaultValue ptr", _ptr___kHashDefaultValue ? @"resolved ✓" : @"MISSING ✗");
    addRow(rows, @"__kBaseURL ptr",          _ptr___kBaseURL          ? @"resolved ✓" : @"MISSING ✗");

    addSection(rows, @"Dev Tool State");
    addRow(rows, @"ForceOffline",       forceOfflineEnabled() ? @"ON" : @"OFF");
    addRow(rows, @"extraInfo captured", gExtraInfo ? @"YES" : @"NO");

    // plain text for clipboard
    NSMutableString *plain = [NSMutableString stringWithString:@"=== Unitoreios Dev Tool Dump ===\n\n"];
    for (NSArray<NSString*> *r in rows) {
        if ([r[0] isEqualToString:@"S"])
            [plain appendFormat:@"\n[%@]\n", r[1]];
        else
            [plain appendFormat:@"%@:\n  %@\n", r[1], r[2]];
    }

    // ── build popup ───────────────────────────────────────────────────────────
    UIView *bd = [[UIView alloc] initWithFrame:root.view.bounds];
    bd.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];

    CGFloat popW = MIN(root.view.bounds.size.width-40, 360);
    CGFloat popH = root.view.bounds.size.height * 0.75;
    UIView *pop  = [[UIView alloc] initWithFrame:CGRectMake(
        (root.view.bounds.size.width -popW)/2,
        (root.view.bounds.size.height-popH)/2, popW, popH)];
    pop.backgroundColor    = [UIColor colorWithWhite:0.07 alpha:0.98];
    pop.layer.cornerRadius = 18;
    pop.layer.borderWidth  = 1;
    pop.layer.borderColor  = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.6].CGColor;
    pop.clipsToBounds      = YES;

    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0,0,popW,44)];
    hdr.backgroundColor = [UIColor colorWithWhite:0.04 alpha:1.0];

    UILabel *hLbl = [[UILabel alloc] initWithFrame:CGRectMake(16,0,popW-120,44)];
    hLbl.text = @"Memory Dump";
    hLbl.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    hLbl.textColor = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    [hdr addSubview:hLbl];

    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(popW-106,9,60,26);
    [copyBtn setTitle:@"Copy" forState:UIControlStateNormal];
    copyBtn.tintColor = [UIColor colorWithWhite:0.70 alpha:1.0];
    copyBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    copyBtn.layer.borderWidth = 0.5;
    copyBtn.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:1.0].CGColor;
    copyBtn.layer.cornerRadius = 7; copyBtn.clipsToBounds = YES;
    NSString *plainCopy = [plain copy];
    [copyBtn dt_onTap:^{
        [UIPasteboard generalPasteboard].string = plainCopy;
        [copyBtn setTitle:@"Copied!" forState:UIControlStateNormal];
        copyBtn.tintColor = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),
            dispatch_get_main_queue(),^{
            [copyBtn setTitle:@"Copy" forState:UIControlStateNormal];
            copyBtn.tintColor = [UIColor colorWithWhite:0.70 alpha:1.0];
        });
    }];
    [hdr addSubview:copyBtn];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(popW-42,9,34,26);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.tintColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    [closeBtn dt_onTap:^{ [bd removeFromSuperview]; }];
    [hdr addSubview:closeBtn];

    UIView *hDiv = [[UIView alloc] initWithFrame:CGRectMake(0,44,popW,0.5)];
    hDiv.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.09];
    [hdr addSubview:hDiv];
    [pop addSubview:hdr];

    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:CGRectMake(0,45,popW,popH-45)];
    sv.alwaysBounceVertical = YES;
    [pop addSubview:sv];

    CGFloat y=12, pad=16;
    UIColor *sCol  = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.80];
    UIColor *kCol  = [UIColor colorWithWhite:0.50 alpha:1.0];
    UIColor *vCol  = [UIColor colorWithWhite:0.90 alpha:1.0];
    UIColor *okCol = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    UIColor *noCol = [UIColor colorWithRed:0.85 green:0.30 blue:0.30 alpha:1.0];

    for (NSArray<NSString*> *r in rows) {
        if ([r[0] isEqualToString:@"S"]) {
            y+=8;
            UILabel *sl=[[UILabel alloc] initWithFrame:CGRectMake(pad,y,popW-pad*2,13)];
            sl.text=r[1].uppercaseString;
            sl.font=[UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
            sl.textColor=sCol; [sv addSubview:sl]; y+=18;
            UIView *sd=[[UIView alloc] initWithFrame:CGRectMake(pad,y,popW-pad*2,0.5)];
            sd.backgroundColor=[UIColor colorWithWhite:1.0 alpha:0.08];
            [sv addSubview:sd]; y+=8;
        } else {
            UILabel *kl=[[UILabel alloc] initWithFrame:CGRectMake(pad,y,popW-pad*2,13)];
            kl.text=r[1];
            kl.font=[UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
            kl.textColor=kCol; [sv addSubview:kl]; y+=15;
            UILabel *vl=[[UILabel alloc] init];
            vl.text=r[2];
            vl.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
            vl.numberOfLines=0;
            NSString *v=r[2];
            if ([v hasPrefix:@"PASS"]||[v hasPrefix:@"YES"]||[v hasPrefix:@"EXECUTE"]||[v hasPrefix:@"resolved"])
                vl.textColor=okCol;
            else if ([v hasPrefix:@"FAIL"]||[v hasPrefix:@"NO ✗"]||[v hasPrefix:@"BLOCK"]||[v hasPrefix:@"MISSING"])
                vl.textColor=noCol;
            else
                vl.textColor=vCol;
            CGSize sz=[vl sizeThatFits:CGSizeMake(popW-pad*2-6,CGFLOAT_MAX)];
            vl.frame=CGRectMake(pad+6,y,popW-pad*2-6,sz.height);
            [sv addSubview:vl]; y+=sz.height+9;
        }
    }
    sv.contentSize=CGSizeMake(popW,y+24);
    [bd addSubview:pop];

    UITapGestureRecognizer *bdTap=[[UITapGestureRecognizer alloc] init];
    [bdTap dt_onTap:^(UITapGestureRecognizer *g){
        if (!CGRectContainsPoint(pop.frame,[g locationInView:bd]))
            [bd removeFromSuperview];
    }];
    [bd addGestureRecognizer:bdTap];
    [root.view addSubview:bd];

    pop.transform=CGAffineTransformMakeScale(0.88,0.88); pop.alpha=0;
    [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.75
          initialSpringVelocity:0.4 options:0 animations:^{
        pop.transform=CGAffineTransformIdentity; pop.alpha=1;
    } completion:nil];
}

// ═════════════════════════════════════════════════════════════════════════════
//  OVERLAY VIEW
// ═════════════════════════════════════════════════════════════════════════════
@interface DevToolView : UIView
@property (nonatomic, strong) UILabel  *timeLabel;
@property (nonatomic, strong) UILabel  *rawLabel;
@property (nonatomic, strong) UILabel  *sessionLabel;
@property (nonatomic, strong) UILabel  *offlineStateLabel;
@property (nonatomic, strong) UIView   *toggleTrack;
@property (nonatomic, strong) UIView   *toggleThumb;
@property (nonatomic, strong) UIButton *addButton;
@property (nonatomic, strong) UIButton *injectButton;
@property (nonatomic, strong) UIButton *dumpButton;
@property (nonatomic, strong) NSTimer  *displayTimer;
@property (nonatomic, assign) BOOL      minimised;
@property (nonatomic, strong) UIView   *pillView;
@property (nonatomic, strong) UILabel  *pillLabel;
@end

static UIWindow    *gWindow  = nil;
static DevToolView *gOverlay = nil;

@implementation DevToolView

- (instancetype)initWithFrame:(CGRect)frame {
    self=[super initWithFrame:frame];
    if (!self) return nil;
    CGFloat W=frame.size.width;

    self.backgroundColor    =[UIColor colorWithWhite:0.07 alpha:0.94];
    self.layer.cornerRadius =18;
    self.layer.borderWidth  =1;
    self.layer.borderColor  =[UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.55].CGColor;
    self.clipsToBounds      =YES;

    UILabel *ico=[[UILabel alloc] initWithFrame:CGRectMake(14,12,24,20)];
    ico.text=@"🛠"; ico.font=[UIFont systemFontOfSize:14];
    [self addSubview:ico];

    UILabel *ttl=[[UILabel alloc] initWithFrame:CGRectMake(40,12,W-78,18)];
    ttl.text=@"Unitoreios Dev Tool";
    ttl.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    ttl.textColor=[UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    [self addSubview:ttl];

    UIButton *minBtn=[UIButton buttonWithType:UIButtonTypeSystem];
    minBtn.frame=CGRectMake(W-36,8,28,28);
    [minBtn setTitle:@"—" forState:UIControlStateNormal];
    minBtn.tintColor=[UIColor colorWithWhite:0.50 alpha:1.0];
    minBtn.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [minBtn dt_onTap:^{ [self toggleMinimise]; }];
    [self addSubview:minBtn];

    [self hr:38];
    [self secLabel:@"MEMORY TIMER" y:46];

    self.timeLabel=[[UILabel alloc] initWithFrame:CGRectMake(0,62,W,32)];
    self.timeLabel.text=@"-- no session --";
    self.timeLabel.font=[UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightMedium];
    self.timeLabel.textColor=[UIColor colorWithWhite:0.90 alpha:1.0];
    self.timeLabel.textAlignment=NSTextAlignmentCenter;
    [self addSubview:self.timeLabel];

    self.rawLabel=[[UILabel alloc] initWithFrame:CGRectMake(0,94,W,14)];
    self.rawLabel.font=[UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.rawLabel.textColor=[UIColor colorWithWhite:0.35 alpha:1.0];
    self.rawLabel.textAlignment=NSTextAlignmentCenter;
    [self addSubview:self.rawLabel];

    self.sessionLabel=[[UILabel alloc] initWithFrame:CGRectMake(0,110,W,13)];
    self.sessionLabel.font=[UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    self.sessionLabel.textAlignment=NSTextAlignmentCenter;
    [self addSubview:self.sessionLabel];

    self.addButton=[self mkBtn:@"+ Add 7 Days to Memory"
                         frame:CGRectMake(14,128,W-28,34)
                            bg:[UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0]
                          tint:[UIColor colorWithRed:0.06 green:0.08 blue:0.10 alpha:1.0]
                        border:nil];
    [self.addButton dt_onTap:^{ [self didTapAdd]; }];
    [self addSubview:self.addButton];

    self.injectButton=[self mkBtn:@"⚡ Inject Cached Session (7d)"
                            frame:CGRectMake(14,168,W-28,34)
                               bg:[UIColor colorWithRed:0.85 green:0.60 blue:0.10 alpha:1.0]
                             tint:[UIColor colorWithRed:0.08 green:0.06 blue:0.02 alpha:1.0]
                           border:nil];
    [self.injectButton dt_onTap:^{ [self didTapInject]; }];
    [self addSubview:self.injectButton];

    self.dumpButton=[self mkBtn:@"⬇ Dump Memory Values"
                          frame:CGRectMake(14,208,W-28,34)
                             bg:[UIColor clearColor]
                           tint:[UIColor colorWithRed:0.63 green:0.47 blue:1.00 alpha:1.0]
                         border:[UIColor colorWithRed:0.63 green:0.47 blue:1.00 alpha:0.5]];
    [self.dumpButton dt_onTap:^{ [self didTapDump]; }];
    [self addSubview:self.dumpButton];

    [self hr:252];
    [self secLabel:@"FORCE OFFLINE AUTH" y:260];

    self.offlineStateLabel=[[UILabel alloc] initWithFrame:CGRectMake(14,278,80,28)];
    self.offlineStateLabel.font=[UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    [self addSubview:self.offlineStateLabel];

    CGFloat tW=52,tH=30,tX=W-tW-14,tY=276;
    self.toggleTrack=[[UIView alloc] initWithFrame:CGRectMake(tX,tY,tW,tH)];
    self.toggleTrack.layer.cornerRadius=tH/2;
    self.toggleTrack.clipsToBounds=YES;
    [self addSubview:self.toggleTrack];

    self.toggleThumb=[[UIView alloc] initWithFrame:CGRectMake(2,2,tH-4,tH-4)];
    self.toggleThumb.layer.cornerRadius=(tH-4)/2;
    self.toggleThumb.backgroundColor=[UIColor whiteColor];
    [self.toggleTrack addSubview:self.toggleThumb];

    UITapGestureRecognizer *tt=[[UITapGestureRecognizer alloc] init];
    [tt dt_onTap:^(id _){ [self didTapToggle]; }];
    [self.toggleTrack addGestureRecognizer:tt];

    UILabel *hint=[[UILabel alloc] initWithFrame:CGRectMake(0,314,W,13)];
    hint.text=@"Persists across app restarts";
    hint.font=[UIFont systemFontOfSize:9 weight:UIFontWeightRegular];
    hint.textColor=[UIColor colorWithWhite:0.28 alpha:1.0];
    hint.textAlignment=NSTextAlignmentCenter;
    [self addSubview:hint];

    self.pillView=[[UIView alloc] initWithFrame:CGRectMake(0,0,W,36)];
    self.pillView.backgroundColor=[UIColor colorWithWhite:0.07 alpha:0.94];
    self.pillView.layer.cornerRadius=18;
    self.pillView.layer.borderWidth=1;
    self.pillView.layer.borderColor=[UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.5].CGColor;
    self.pillView.clipsToBounds=YES;
    self.pillView.hidden=YES;

    self.pillLabel=[[UILabel alloc] initWithFrame:CGRectMake(10,0,W-20,36)];
    self.pillLabel.font=[UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
    self.pillLabel.textColor=[UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    self.pillLabel.text=@"⏱ --";
    [self.pillView addSubview:self.pillLabel];

    UITapGestureRecognizer *pt=[[UITapGestureRecognizer alloc] init];
    [pt dt_onTap:^(id _){ [self toggleMinimise]; }];
    [self.pillView addGestureRecognizer:pt];
    [self addSubview:self.pillView];

    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];

    [self applyToggleState:NO];
    self.displayTimer=[NSTimer scheduledTimerWithTimeInterval:1.0 target:self
                                                     selector:@selector(refresh)
                                                     userInfo:nil repeats:YES];
    [self refresh];
    return self;
}

- (UIButton *)mkBtn:(NSString *)t frame:(CGRect)f bg:(UIColor *)bg
               tint:(UIColor *)tint border:(UIColor *)border {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    b.frame=f; [b setTitle:t forState:UIControlStateNormal];
    b.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    b.tintColor=tint; b.backgroundColor=bg;
    b.layer.cornerRadius=10; b.clipsToBounds=YES;
    if (border){b.layer.borderWidth=1; b.layer.borderColor=border.CGColor;}
    return b;
}

- (void)hr:(CGFloat)y {
    UIView *d=[[UIView alloc] initWithFrame:CGRectMake(0,y,self.frame.size.width,0.5)];
    d.backgroundColor=[UIColor colorWithWhite:1.0 alpha:0.09];
    [self addSubview:d];
}
- (void)secLabel:(NSString *)t y:(CGFloat)y {
    UILabel *l=[[UILabel alloc] initWithFrame:CGRectMake(14,y,self.frame.size.width-28,13)];
    l.text=t; l.font=[UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    l.textColor=[UIColor colorWithWhite:0.35 alpha:1.0];
    [self addSubview:l];
}

- (void)refresh {
    NSInteger sec=gExtraInfo ? gExtraInfo.remainingSeconds : 0;
    BOOL hasSession=gExtraInfo!=nil;
    BOOL fOff=forceOfflineEnabled();

    self.timeLabel.text=hasSession ? fmtSec(sec) : @"-- no session --";
    self.timeLabel.textColor=(hasSession&&sec>0)
        ? [UIColor colorWithWhite:0.90 alpha:1.0]
        : [UIColor colorWithRed:0.85 green:0.30 blue:0.30 alpha:1.0];

    self.rawLabel.text=hasSession
        ? [NSString stringWithFormat:@"%ld seconds raw",(long)sec]
        : @"waiting for session…";

    self.sessionLabel.text=hasSession ? @"● live memory" : @"○ no session yet";
    self.sessionLabel.textColor=hasSession
        ? [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.9]
        : [UIColor colorWithWhite:0.35 alpha:1.0];

    NSString *ik=GET(iskey);
    NSString *kvs=GET(keyValidationStatus);
    NSString *ec=GET(encodedcode);
    NSString *es=GET(encodestring);
    BOOL allOk=ik.length>0
             &&[kvs isEqualToString:@"validated"]
             &&ec&&es&&[ec isEqualToString:es]
             &&sec>0;
    self.injectButton.alpha=allOk ? 0.45 : 1.0;

    NSString *ind=fOff ? @"📵" : @"📶";
    self.pillLabel.text=hasSession
        ? [NSString stringWithFormat:@"%@ %@",ind,fmtSec(sec)]
        : [NSString stringWithFormat:@"%@ --",ind];
}

- (void)didTapAdd {
    if (!gExtraInfo) return;
    gExtraInfo.remainingSeconds+=SEVEN_DAYS;
    [self flash:self.addButton
            col:[UIColor colorWithRed:0.05 green:0.50 blue:0.32 alpha:1.0]
       original:[UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0]];
    [self refresh];
}

- (void)didTapInject {
    injectFakeSession(SEVEN_DAYS);
    [self flash:self.injectButton
            col:[UIColor colorWithRed:0.85 green:0.60 blue:0.10 alpha:0.5]
       original:[UIColor clearColor]];
    [self toast:@"Session injected ✓"
          color:[UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0]];
    [self refresh];
}

- (void)didTapDump {
    [self flash:self.dumpButton
            col:[UIColor colorWithRed:0.63 green:0.47 blue:1.00 alpha:0.20]
       original:[UIColor clearColor]];
    showDumpPopup();
}

- (void)didTapToggle {
    setForceOffline(!forceOfflineEnabled());
    [self applyToggleState:YES];
    [self refresh];
}

- (void)applyToggleState:(BOOL)animated {
    BOOL on=forceOfflineEnabled();
    CGFloat tW=self.toggleTrack.frame.size.width;
    CGFloat tH=self.toggleThumb.frame.size.width;
    void(^upd)(void)=^{
        self.toggleTrack.backgroundColor=on
            ? [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0]
            : [UIColor colorWithWhite:0.24 alpha:1.0];
        CGRect tf=self.toggleThumb.frame;
        tf.origin.x=on?(tW-tH-2):2;
        self.toggleThumb.frame=tf;
        self.offlineStateLabel.text=on?@"ON":@"OFF";
        self.offlineStateLabel.textColor=on
            ? [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0]
            : [UIColor colorWithWhite:0.38 alpha:1.0];
        self.layer.borderColor=on
            ? [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.8].CGColor
            : [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.35].CGColor;
    };
    animated
        ? [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.7
               initialSpringVelocity:0.5 options:0 animations:upd completion:nil]
        : upd();
}

- (void)toggleMinimise {
    self.minimised=!self.minimised;
    if (self.minimised) {
        [UIView animateWithDuration:0.20 animations:^{
            CGRect f=gWindow.frame; f.size.height=36; gWindow.frame=f;
            self.frame=CGRectMake(0,0,f.size.width,36);
        } completion:^(BOOL _){
            for (UIView *v in self.subviews) v.hidden=(v!=self.pillView);
            self.pillView.hidden=NO; self.layer.cornerRadius=18;
        }];
    } else {
        for (UIView *v in self.subviews) v.hidden=NO;
        self.pillView.hidden=YES;
        [UIView animateWithDuration:0.20 animations:^{
            CGRect f=gWindow.frame; f.size.height=332; gWindow.frame=f;
            self.frame=CGRectMake(0,0,f.size.width,332);
        }];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint d=[pan translationInView:self.superview];
    CGRect f=gWindow.frame;
    f.origin.x+=d.x; f.origin.y+=d.y;
    CGRect sc=[UIScreen mainScreen].bounds;
    f.origin.x=MAX(0,MIN(f.origin.x,sc.size.width -f.size.width));
    f.origin.y=MAX(20,MIN(f.origin.y,sc.size.height-f.size.height-20));
    gWindow.frame=f;
    [pan setTranslation:CGPointZero inView:self.superview];
}

- (void)flash:(UIButton *)btn col:(UIColor *)col original:(UIColor *)orig {
    [UIView animateWithDuration:0.10 animations:^{ btn.backgroundColor=col; }
                     completion:^(BOOL _){
        [UIView animateWithDuration:0.35 animations:^{ btn.backgroundColor=orig; }];
    }];
}

- (void)toast:(NSString *)msg color:(UIColor *)col {
    UILabel *t=[[UILabel alloc] init];
    t.text=msg;
    t.font=[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    t.textColor=col; t.textAlignment=NSTextAlignmentCenter;
    t.backgroundColor=[UIColor colorWithWhite:0.05 alpha:0.9];
    t.layer.cornerRadius=8; t.clipsToBounds=YES;
    CGSize sz=[t sizeThatFits:CGSizeMake(self.frame.size.width-28,24)];
    t.frame=CGRectMake((self.frame.size.width-sz.width-20)/2,204,sz.width+20,24);
    t.alpha=0; [self addSubview:t];
    [UIView animateWithDuration:0.20 animations:^{ t.alpha=1; } completion:^(BOOL _){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.4*NSEC_PER_SEC)),
            dispatch_get_main_queue(),^{
            [UIView animateWithDuration:0.25 animations:^{ t.alpha=0; }
                             completion:^(BOOL _){ [t removeFromSuperview]; }];
        });
    }];
}

@end

// ═════════════════════════════════════════════════════════════════════════════
//  PASS-THROUGH WINDOW
// ═════════════════════════════════════════════════════════════════════════════
@interface DevToolWindow : UIWindow
@end
@implementation DevToolWindow
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {
    for (UIView *v in self.subviews)
        if (!v.hidden&&[v pointInside:[self convertPoint:p toView:v] withEvent:e])
            return YES;
    return NO;
}
@end

// ═════════════════════════════════════════════════════════════════════════════
//  SPAWN
// ═════════════════════════════════════════════════════════════════════════════
static void spawnOverlay(void) {
    if (gWindow) return;
    CGFloat w=234,h=332;
    CGRect sc=[UIScreen mainScreen].bounds;
    gWindow=[[DevToolWindow alloc] initWithFrame:
        CGRectMake(sc.size.width-w-12,sc.size.height*0.22,w,h)];
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState==UISceneActivationStateForegroundActive) {
                gWindow.windowScene=(UIWindowScene *)scene; break;
            }
        }
    }
    gWindow.windowLevel=UIWindowLevelAlert+100;
    gWindow.backgroundColor=[UIColor clearColor];
    gOverlay=[[DevToolView alloc] initWithFrame:CGRectMake(0,0,w,h)];
    [gWindow addSubview:gOverlay];
    gWindow.hidden=NO;
    [gWindow makeKeyAndVisible];
    NSLog(@"[DevTool] overlay ready");
}

// ═════════════════════════════════════════════════════════════════════════════
//  HOOKS
// ═════════════════════════════════════════════════════════════════════════════
%hook Unitoreios

- (void)startUpdateTimer {
    %orig;
    if (!gExtraInfo) {
        gExtraInfo=self;
        NSString *sk=[[NSUserDefaults standardUserDefaults] objectForKey:@"savedKey"];
        NSString *ec=GET(encodedcode);
        NSString *es=GET(encodestring);
        if (sk&&GET(iskey)&&ec&&es&&[ec isEqualToString:es]&&self.remainingSeconds<=0) {
            self.remainingSeconds=SEVEN_DAYS;
            NSLog(@"[DevTool] retroactively applied remainingSeconds");
        }
        dispatch_async(dispatch_get_main_queue(),^{ spawnOverlay(); });
    }
}

- (BOOL)isNetworkAvailable {
    if (forceOfflineEnabled()) return NO;
    return %orig;
}

- (NSString *)decryptAESData:(NSData *)data key:(NSString *)key iv:(NSString *)iv {
    if (!gCapturedAESKey&&key.length>0) gCapturedAESKey=[key copy];
    if (!gCapturedAESIV &&iv.length >0) gCapturedAESIV =[iv copy];
    return %orig;
}

%end

// ═════════════════════════════════════════════════════════════════════════════
//  CONSTRUCTOR — priority 101, before Unitoreios +load (65535)
// ═════════════════════════════════════════════════════════════════════════════
__attribute__((constructor(101)))
static void DevToolEarlyInit(void) {
    // Resolve all symbols now — app binary is loaded, dlsym works
    resolveSymbols();
    NSLog(@"[DevTool] early init priority 101 — hooks armed");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),
                   dispatch_get_main_queue(),^{ spawnOverlay(); });
}
