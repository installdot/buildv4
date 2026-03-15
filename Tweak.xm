#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <SystemConfiguration/SystemConfiguration.h>

// ═════════════════════════════════════════════════════════════════════════════
//  UNITOREIOS DEV TOOL — Offline Auth Tester
//  • Force offline mode on/off (persistent across restarts)
//  • Live remainingSeconds counter from memory
//  • +7 days button
//  • Draggable, minimisable overlay
// ═════════════════════════════════════════════════════════════════════════════

#define SEVEN_DAYS        604800
#define kForceOfflineKey  @"com.yourname.devtool.forceOffline"

// ── singleton refs ────────────────────────────────────────────────────────────
@interface Unitoreios : NSObject
@property (nonatomic, assign) NSInteger remainingSeconds;
- (void)startUpdateTimer;
@end

static Unitoreios *gExtraInfo = nil;

// ── persistence helpers ───────────────────────────────────────────────────────
static BOOL forceOfflineEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kForceOfflineKey];
}
static void setForceOffline(BOOL on) {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:kForceOfflineKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSLog(@"[DevTool] ForceOffline → %@", on ? @"ON" : @"OFF");
}

// ── format helpers ────────────────────────────────────────────────────────────
static NSString *fmtSeconds(NSInteger s) {
    if (s <= 0) return @"EXPIRED";
    NSInteger d = s/86400; s %= 86400;
    NSInteger h = s/3600;  s %= 3600;
    NSInteger m = s/60;    s %= 60;
    return [NSString stringWithFormat:@"%02ldd %02ldh %02ldm %02lds",
            (long)d,(long)h,(long)m,(long)s];
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
@property (nonatomic, strong) NSTimer  *displayTimer;
@property (nonatomic, assign) BOOL      minimised;
@property (nonatomic, strong) UIView   *pillView;
@property (nonatomic, strong) UILabel  *pillLabel;
@end

static UIWindow    *gWindow  = nil;
static DevToolView *gOverlay = nil;

@implementation DevToolView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    CGFloat W = frame.size.width;

    self.backgroundColor    = [UIColor colorWithWhite:0.07 alpha:0.94];
    self.layer.cornerRadius = 18;
    self.layer.borderWidth  = 1;
    self.layer.borderColor  = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.55].CGColor;
    self.clipsToBounds      = YES;

    // ── header ────────────────────────────────────────────────────────────────
    UILabel *titleIcon      = [[UILabel alloc] initWithFrame:CGRectMake(14,12,24,20)];
    titleIcon.text          = @"🛠";
    titleIcon.font          = [UIFont systemFontOfSize:14];
    [self addSubview:titleIcon];

    UILabel *titleText      = [[UILabel alloc] initWithFrame:CGRectMake(40,12,W-80,18)];
    titleText.text          = @"Dev Tool";
    titleText.font          = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    titleText.textColor     = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    [self addSubview:titleText];

    UIButton *minBtn        = [UIButton buttonWithType:UIButtonTypeSystem];
    minBtn.frame            = CGRectMake(W-36, 8, 28, 28);
    [minBtn setTitle:@"—" forState:UIControlStateNormal];
    minBtn.tintColor        = [UIColor colorWithWhite:0.5 alpha:1.0];
    minBtn.titleLabel.font  = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [minBtn addTarget:self action:@selector(toggleMinimise) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:minBtn];

    // ── divider 1 ─────────────────────────────────────────────────────────────
    [self addDividerAt:38 width:W];

    // ── section: timer ────────────────────────────────────────────────────────
    UILabel *secTitle       = [[UILabel alloc] initWithFrame:CGRectMake(14,46,W-28,13)];
    secTitle.text           = @"MEMORY PATCH";
    secTitle.font           = [UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    secTitle.textColor      = [UIColor colorWithWhite:0.35 alpha:1.0];
    [self addSubview:secTitle];

    self.timeLabel          = [[UILabel alloc] initWithFrame:CGRectMake(0,62,W,32)];
    self.timeLabel.text     = @"-- no session --";
    self.timeLabel.font     = [UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightMedium];
    self.timeLabel.textColor= [UIColor colorWithWhite:0.90 alpha:1.0];
    self.timeLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.timeLabel];

    self.rawLabel           = [[UILabel alloc] initWithFrame:CGRectMake(0,94,W,14)];
    self.rawLabel.font      = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.rawLabel.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    self.rawLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.rawLabel];

    self.sessionLabel       = [[UILabel alloc] initWithFrame:CGRectMake(0,110,W,13)];
    self.sessionLabel.font  = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    self.sessionLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.sessionLabel];

    // ── +7 days button ────────────────────────────────────────────────────────
    self.addButton          = [UIButton buttonWithType:UIButtonTypeSystem];
    self.addButton.frame    = CGRectMake(14, 128, W-28, 36);
    [self.addButton setTitle:@"Patch Memory" forState:UIControlStateNormal];
    self.addButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.addButton.tintColor       = [UIColor colorWithRed:0.07 green:0.09 blue:0.12 alpha:1.0];
    self.addButton.backgroundColor = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    self.addButton.layer.cornerRadius = 10;
    self.addButton.clipsToBounds    = YES;
    [self.addButton addTarget:self action:@selector(didTapAdd) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.addButton];

    // ── divider 2 ─────────────────────────────────────────────────────────────
    [self addDividerAt:174 width:W];

    // ── section: force offline ────────────────────────────────────────────────
    UILabel *offTitle       = [[UILabel alloc] initWithFrame:CGRectMake(14,182,W-28,13)];
    offTitle.text           = @"FORCE AUTH";
    offTitle.font           = [UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    offTitle.textColor      = [UIColor colorWithWhite:0.35 alpha:1.0];
    [self addSubview:offTitle];

    // state label (ON / OFF)
    self.offlineStateLabel  = [[UILabel alloc] initWithFrame:CGRectMake(14,200,80,28)];
    self.offlineStateLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    [self addSubview:self.offlineStateLabel];

    // toggle track
    CGFloat trackW=52, trackH=30, trackX=W-trackW-14, trackY=198;
    self.toggleTrack        = [[UIView alloc] initWithFrame:CGRectMake(trackX,trackY,trackW,trackH)];
    self.toggleTrack.layer.cornerRadius = trackH/2;
    self.toggleTrack.clipsToBounds      = YES;
    [self addSubview:self.toggleTrack];

    self.toggleThumb        = [[UIView alloc] initWithFrame:CGRectMake(2,2,trackH-4,trackH-4)];
    self.toggleThumb.layer.cornerRadius = (trackH-4)/2;
    self.toggleThumb.backgroundColor    = [UIColor whiteColor];
    [self.toggleTrack addSubview:self.toggleThumb];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTapToggle)];
    [self.toggleTrack addGestureRecognizer:tap];

    UILabel *hint           = [[UILabel alloc] initWithFrame:CGRectMake(0,234,W,13)];
    hint.text               = @"Persists across app restarts";
    hint.font               = [UIFont systemFontOfSize:9 weight:UIFontWeightRegular];
    hint.textColor          = [UIColor colorWithWhite:0.28 alpha:1.0];
    hint.textAlignment      = NSTextAlignmentCenter;
    [self addSubview:hint];

    // ── pill (minimised) ──────────────────────────────────────────────────────
    self.pillView               = [[UIView alloc] initWithFrame:CGRectMake(0,0,W,36)];
    self.pillView.backgroundColor = [UIColor colorWithWhite:0.07 alpha:0.94];
    self.pillView.layer.cornerRadius = 18;
    self.pillView.layer.borderWidth  = 1;
    self.pillView.layer.borderColor  = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.5].CGColor;
    self.pillView.clipsToBounds      = YES;
    self.pillView.hidden             = YES;

    self.pillLabel          = [[UILabel alloc] initWithFrame:CGRectMake(10,0,W-20,36)];
    self.pillLabel.font     = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
    self.pillLabel.textColor= [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    self.pillLabel.text     = @"⏱ --";
    [self.pillView addSubview:self.pillLabel];

    UITapGestureRecognizer *pillTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMinimise)];
    [self.pillView addGestureRecognizer:pillTap];
    [self addSubview:self.pillView];

    // ── drag ──────────────────────────────────────────────────────────────────
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];

    // ── boot state ────────────────────────────────────────────────────────────
    [self applyToggleState:NO];

    // ── refresh timer ─────────────────────────────────────────────────────────
    self.displayTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                         target:self
                                                       selector:@selector(refresh)
                                                       userInfo:nil
                                                        repeats:YES];
    [self refresh];
    return self;
}

// ── helpers ───────────────────────────────────────────────────────────────────
- (void)addDividerAt:(CGFloat)y width:(CGFloat)w {
    UIView *d       = [[UIView alloc] initWithFrame:CGRectMake(0,y,w,0.5)];
    d.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.09];
    [self addSubview:d];
}

// ── refresh (every second) ────────────────────────────────────────────────────
- (void)refresh {
    NSInteger sec = gExtraInfo ? gExtraInfo.remainingSeconds : 0;
    BOOL hasSession = gExtraInfo != nil;

    // time label
    self.timeLabel.text = hasSession ? fmtSeconds(sec) : @"-- no session --";
    self.timeLabel.textColor = (hasSession && sec > 0)
        ? [UIColor colorWithWhite:0.90 alpha:1.0]
        : [UIColor colorWithRed:0.85 green:0.30 blue:0.30 alpha:1.0];

    // raw seconds
    self.rawLabel.text = hasSession
        ? [NSString stringWithFormat:@"%ld seconds raw", (long)sec]
        : @"waiting for session…";

    // session status
    if (hasSession) {
        self.sessionLabel.text      = @"● live memory";
        self.sessionLabel.textColor = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.9];
    } else {
        self.sessionLabel.text      = @"○ no session yet";
        self.sessionLabel.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    }

    // pill
    BOOL fOff = forceOfflineEnabled();
    NSString *indicator = fOff ? @"🐱" : @"😹";
    self.pillLabel.text = hasSession
        ? [NSString stringWithFormat:@"%@ %@", indicator, fmtSeconds(sec)]
        : [NSString stringWithFormat:@"%@ --", indicator];
}

// ── +7 days ───────────────────────────────────────────────────────────────────
- (void)didTapAdd {
    if (!gExtraInfo) return;
    gExtraInfo.remainingSeconds += SEVEN_DAYS;
    NSLog(@"[DevTool] +7d → remainingSeconds = %ld", (long)gExtraInfo.remainingSeconds);

    UIColor *orig = self.addButton.backgroundColor;
    [UIView animateWithDuration:0.10 animations:^{
        self.addButton.backgroundColor = [UIColor colorWithRed:0.05 green:0.50 blue:0.32 alpha:1.0];
    } completion:^(BOOL _){
        [UIView animateWithDuration:0.35 animations:^{
            self.addButton.backgroundColor = orig;
        }];
    }];
    [self refresh];
}

// ── toggle ────────────────────────────────────────────────────────────────────
- (void)didTapToggle {
    setForceOffline(!forceOfflineEnabled());
    [self applyToggleState:YES];
    [self refresh];
}

- (void)applyToggleState:(BOOL)animated {
    BOOL on           = forceOfflineEnabled();
    UIColor *trackOn  = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    UIColor *trackOff = [UIColor colorWithWhite:0.24 alpha:1.0];

    CGFloat tW = self.toggleTrack.frame.size.width;
    CGFloat tH = self.toggleThumb.frame.size.width;

    void (^upd)(void) = ^{
        self.toggleTrack.backgroundColor = on ? trackOn : trackOff;
        CGRect tf = self.toggleThumb.frame;
        tf.origin.x = on ? (tW - tH - 2) : 2;
        self.toggleThumb.frame = tf;

        self.offlineStateLabel.text      = on ? @"ON"  : @"OFF";
        self.offlineStateLabel.textColor = on
            ? [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0]
            : [UIColor colorWithWhite:0.38 alpha:1.0];

        self.layer.borderColor = on
            ? [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.8].CGColor
            : [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.35].CGColor;
    };

    animated
        ? [UIView animateWithDuration:0.22 delay:0
               usingSpringWithDamping:0.7 initialSpringVelocity:0.5
                              options:UIViewAnimationOptionCurveEaseInOut
                           animations:upd completion:nil]
        : upd();
}

// ── minimise / expand ─────────────────────────────────────────────────────────
- (void)toggleMinimise {
    self.minimised = !self.minimised;
    if (self.minimised) {
        [UIView animateWithDuration:0.20 animations:^{
            CGRect f = gWindow.frame; f.size.height = 36; gWindow.frame = f;
            self.frame = CGRectMake(0,0,f.size.width,36);
        } completion:^(BOOL _){
            for (UIView *v in self.subviews) v.hidden = (v != self.pillView);
            self.pillView.hidden = NO;
            self.layer.cornerRadius = 18;
        }];
    } else {
        for (UIView *v in self.subviews) v.hidden = NO;
        self.pillView.hidden = YES;
        [UIView animateWithDuration:0.20 animations:^{
            CGRect f = gWindow.frame; f.size.height = 252; gWindow.frame = f;
            self.frame = CGRectMake(0,0,f.size.width,252);
        }];
    }
}

// ── drag ──────────────────────────────────────────────────────────────────────
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint delta  = [pan translationInView:self.superview];
    CGRect f       = gWindow.frame;
    f.origin.x    += delta.x;
    f.origin.y    += delta.y;
    CGRect screen  = [UIScreen mainScreen].bounds;
    f.origin.x     = MAX(0, MIN(f.origin.x, screen.size.width  - f.size.width));
    f.origin.y     = MAX(20, MIN(f.origin.y, screen.size.height - f.size.height - 20));
    gWindow.frame  = f;
    [pan setTranslation:CGPointZero inView:self.superview];
}

@end

// ═════════════════════════════════════════════════════════════════════════════
//  WINDOW (pass-through touches outside overlay)
// ═════════════════════════════════════════════════════════════════════════════
@interface DevToolWindow : UIWindow
@end
@implementation DevToolWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *sub in self.subviews) {
        if (!sub.hidden && [sub pointInside:[self convertPoint:point toView:sub] withEvent:event])
            return YES;
    }
    return NO;
}
@end

// ═════════════════════════════════════════════════════════════════════════════
//  SPAWN
// ═════════════════════════════════════════════════════════════════════════════
static void spawnOverlay(void) {
    if (gWindow) return;
    CGFloat w = 230, h = 252;
    CGRect screen = [UIScreen mainScreen].bounds;
    gWindow = [[DevToolWindow alloc] initWithFrame:CGRectMake(
        screen.size.width - w - 12,
        screen.size.height * 0.28,
        w, h)];

    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                gWindow.windowScene = (UIWindowScene *)scene;
                break;
            }
        }
    }

    gWindow.windowLevel     = UIWindowLevelAlert + 100;
    gWindow.backgroundColor = [UIColor clearColor];
    gOverlay = [[DevToolView alloc] initWithFrame:CGRectMake(0,0,w,h)];
    [gWindow addSubview:gOverlay];
    gWindow.hidden = NO;
    [gWindow makeKeyAndVisible];
    NSLog(@"[DevTool] overlay ready");
}

// ═════════════════════════════════════════════════════════════════════════════
//  HOOKS
// ═════════════════════════════════════════════════════════════════════════════
%hook Unitoreios

// ── grab extraInfo singleton + spawn overlay after first valid session ─────
- (void)startUpdateTimer {
    %orig;
    if (!gExtraInfo) {
        gExtraInfo = self;
        NSLog(@"[DevTool] extraInfo captured: %@", self);
        dispatch_async(dispatch_get_main_queue(), ^{ spawnOverlay(); });
    }
}

// ── force offline gate ────────────────────────────────────────────────────
- (BOOL)isNetworkAvailable {
    if (forceOfflineEnabled()) {
        return NO;
    }
    return %orig;
}

%end

// ═════════════════════════════════════════════════════════════════════════════
//  CONSTRUCTOR
// ═════════════════════════════════════════════════════════════════════════════
%ctor {
    NSLog(@"[DevTool] loaded — forceOffline=%@",
          forceOfflineEnabled() ? @"ON" : @"OFF");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        spawnOverlay();
    });
}
