#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define SEVEN_DAYS 604800

// ── forward-declare the private ivar ──────────────────────────────────────────
@interface Unitoreios : NSObject
@property (nonatomic, assign) NSInteger remainingSeconds;
- (void)startUpdateTimer;
@end

// ── floating overlay window ───────────────────────────────────────────────────
@interface OTOverlayWindow : UIWindow
@end

@interface OTOverlayView : UIView
@property (nonatomic, strong) UILabel      *timeLabel;
@property (nonatomic, strong) UILabel      *titleLabel;
@property (nonatomic, strong) UIButton     *addButton;
@property (nonatomic, strong) UIButton     *closeButton;
@property (nonatomic, strong) NSTimer      *displayTimer;
@property (nonatomic, assign) BOOL          minimised;
@property (nonatomic, strong) UIView       *pill;   // minimised pill
- (void)refresh;
@end

static OTOverlayWindow *gWindow      = nil;
static OTOverlayView   *gOverlay     = nil;
static Unitoreios      *gExtraInfo   = nil;   // grabbed from hook

// ── helpers ───────────────────────────────────────────────────────────────────
static NSString *formatSeconds(NSInteger s) {
    if (s <= 0) return @"00d 00h 00m 00s  EXPIRED";
    NSInteger d  = s / 86400; s %= 86400;
    NSInteger h  = s / 3600;  s %= 3600;
    NSInteger m  = s / 60;    s %= 60;
    return [NSString stringWithFormat:@"%02ldd %02ldh %02ldm %02lds",
            (long)d,(long)h,(long)m,(long)s];
}

static void addSevenDays(void) {
    if (!gExtraInfo) return;
    gExtraInfo.remainingSeconds += SEVEN_DAYS;
    NSLog(@"[OT] +7d → remainingSeconds = %ld", (long)gExtraInfo.remainingSeconds);
}

// ── overlay view ──────────────────────────────────────────────────────────────
@implementation OTOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor    = [UIColor colorWithWhite:0.08 alpha:0.92];
    self.layer.cornerRadius = 18;
    self.layer.borderWidth  = 1;
    self.layer.borderColor  = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.6].CGColor;
    self.clipsToBounds      = YES;

    // ── title bar ─────────────────────────────────────────────────────────────
    self.titleLabel                 = [[UILabel alloc] initWithFrame:CGRectMake(14,12,frame.size.width-60,20)];
    self.titleLabel.text            = @"⏱ Offline Time Test";
    self.titleLabel.font            = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.titleLabel.textColor       = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    [self addSubview:self.titleLabel];

    // ── close / minimise button ───────────────────────────────────────────────
    self.closeButton                = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.frame          = CGRectMake(frame.size.width-40, 8, 30, 28);
    [self.closeButton setTitle:@"—" forState:UIControlStateNormal];
    self.closeButton.tintColor      = [UIColor colorWithWhite:0.6 alpha:1.0];
    self.closeButton.titleLabel.font= [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [self.closeButton addTarget:self action:@selector(toggleMinimise) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.closeButton];

    // ── divider ───────────────────────────────────────────────────────────────
    UIView *div         = [[UIView alloc] initWithFrame:CGRectMake(0,40,frame.size.width,0.5)];
    div.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    [self addSubview:div];

    // ── time label ────────────────────────────────────────────────────────────
    self.timeLabel                  = [[UILabel alloc] initWithFrame:CGRectMake(0,50,frame.size.width,36)];
    self.timeLabel.text             = @"-- waiting --";
    self.timeLabel.font             = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightMedium];
    self.timeLabel.textColor        = [UIColor colorWithWhite:0.92 alpha:1.0];
    self.timeLabel.textAlignment    = NSTextAlignmentCenter;
    [self addSubview:self.timeLabel];

    // ── sub label (raw seconds) ───────────────────────────────────────────────
    UILabel *sub        = [[UILabel alloc] initWithFrame:CGRectMake(0,84,frame.size.width,16)];
    sub.tag             = 99;
    sub.font            = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    sub.textColor       = [UIColor colorWithWhite:0.45 alpha:1.0];
    sub.textAlignment   = NSTextAlignmentCenter;
    [self addSubview:sub];

    // ── +7 days button ────────────────────────────────────────────────────────
    self.addButton                  = [UIButton buttonWithType:UIButtonTypeSystem];
    self.addButton.frame            = CGRectMake(14, 110, frame.size.width-28, 40);
    [self.addButton setTitle:@"+ Add 7 Days" forState:UIControlStateNormal];
    self.addButton.titleLabel.font  = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.addButton.tintColor        = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:1.0];
    self.addButton.backgroundColor  = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    self.addButton.layer.cornerRadius = 10;
    self.addButton.clipsToBounds    = YES;
    [self.addButton addTarget:self action:@selector(didTapAdd) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.addButton];

    // ── status strip ──────────────────────────────────────────────────────────
    UILabel *status     = [[UILabel alloc] initWithFrame:CGRectMake(0,158,frame.size.width,14)];
    status.tag          = 98;
    status.font         = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    status.textColor    = [UIColor colorWithWhite:0.35 alpha:1.0];
    status.textAlignment= NSTextAlignmentCenter;
    status.text         = @"no session yet";
    [self addSubview:status];

    // ── pill (minimised state) ─────────────────────────────────────────────────
    self.pill               = [[UIView alloc] initWithFrame:CGRectMake(0,0,frame.size.width,36)];
    self.pill.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
    self.pill.layer.cornerRadius = 18;
    self.pill.layer.borderWidth = 1;
    self.pill.layer.borderColor = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.5].CGColor;
    self.pill.clipsToBounds = YES;
    self.pill.hidden        = YES;

    UILabel *pillLabel      = [[UILabel alloc] initWithFrame:CGRectMake(12,0,frame.size.width-24,36)];
    pillLabel.tag           = 97;
    pillLabel.font          = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
    pillLabel.textColor     = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    pillLabel.text          = @"⏱ --";
    [self.pill addSubview:pillLabel];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMinimise)];
    [self.pill addGestureRecognizer:tap];
    [self addSubview:self.pill];

    // ── drag gesture ─────────────────────────────────────────────────────────
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];

    // ── display refresh timer ─────────────────────────────────────────────────
    self.displayTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                         target:self
                                                       selector:@selector(refresh)
                                                       userInfo:nil
                                                        repeats:YES];
    return self;
}

- (void)refresh {
    NSInteger sec = gExtraInfo ? gExtraInfo.remainingSeconds : 0;

    self.timeLabel.text = formatSeconds(sec);
    self.timeLabel.textColor = sec > 0
        ? [UIColor colorWithWhite:0.92 alpha:1.0]
        : [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1.0];

    UILabel *sub    = (UILabel *)[self viewWithTag:99];
    sub.text        = [NSString stringWithFormat:@"%ld raw seconds in memory", (long)sec];

    UILabel *status = (UILabel *)[self viewWithTag:98];
    UILabel *pill   = (UILabel *)[self viewWithTag:97];

    if (gExtraInfo) {
        status.text  = @"session active — live memory";
        status.textColor = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.8];
        pill.text    = [NSString stringWithFormat:@"⏱ %@", formatSeconds(sec)];
    } else {
        status.text  = @"no session yet";
        status.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
        pill.text    = @"⏱ no session";
    }
}

- (void)didTapAdd {
    addSevenDays();

    // flash button green briefly
    UIColor *orig = self.addButton.backgroundColor;
    [UIView animateWithDuration:0.1 animations:^{
        self.addButton.backgroundColor = [UIColor colorWithRed:0.05 green:0.55 blue:0.35 alpha:1.0];
    } completion:^(BOOL _) {
        [UIView animateWithDuration:0.4 animations:^{
            self.addButton.backgroundColor = orig;
        }];
    }];

    [self refresh];
}

- (void)toggleMinimise {
    self.minimised = !self.minimised;

    if (self.minimised) {
        // shrink to pill
        [UIView animateWithDuration:0.22 animations:^{
            CGRect f = gWindow.frame;
            f.size.height = 36;
            gWindow.frame = f;
            self.frame = CGRectMake(0,0,f.size.width,36);
        } completion:^(BOOL _) {
            self.titleLabel.hidden = YES;
            self.closeButton.hidden = YES;
            self.timeLabel.hidden = YES;
            [self viewWithTag:99].hidden = YES;
            self.addButton.hidden = YES;
            [self viewWithTag:98].hidden = YES;
            self.pill.hidden = NO;
            self.layer.cornerRadius = 18;
        }];
    } else {
        // expand back
        self.titleLabel.hidden = NO;
        self.closeButton.hidden = NO;
        self.timeLabel.hidden = NO;
        [self viewWithTag:99].hidden = NO;
        self.addButton.hidden = NO;
        [self viewWithTag:98].hidden = NO;
        self.pill.hidden = YES;

        [UIView animateWithDuration:0.22 animations:^{
            CGRect f = gWindow.frame;
            f.size.height = 178;
            gWindow.frame = f;
            self.frame = CGRectMake(0,0,f.size.width,178);
        }];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint delta = [pan translationInView:self.superview];
    CGRect f = gWindow.frame;
    f.origin.x += delta.x;
    f.origin.y += delta.y;

    // keep on screen
    CGRect screen = [UIScreen mainScreen].bounds;
    f.origin.x = MAX(0, MIN(f.origin.x, screen.size.width  - f.size.width));
    f.origin.y = MAX(20, MIN(f.origin.y, screen.size.height - f.size.height - 20));
    gWindow.frame = f;
    [pan setTranslation:CGPointZero inView:self.superview];
}

@end

// ── overlay window (stays on top) ────────────────────────────────────────────
@implementation OTOverlayWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    // only intercept touches that land on our subviews
    for (UIView *sub in self.subviews) {
        if (!sub.hidden && [sub pointInside:[self convertPoint:point toView:sub] withEvent:event])
            return YES;
    }
    return NO;
}
@end

// ── spawn the overlay ─────────────────────────────────────────────────────────
static void spawnOverlay(void) {
    if (gWindow) return;

    CGFloat w = 220, h = 178;
    CGRect screen = [UIScreen mainScreen].bounds;
    gWindow = [[OTOverlayWindow alloc] initWithFrame:CGRectMake(screen.size.width - w - 12,
                                                                 screen.size.height * 0.30,
                                                                 w, h)];
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                gWindow.windowScene = (UIWindowScene *)scene;
                break;
            }
        }
    }
    gWindow.windowLevel   = UIWindowLevelAlert + 100;
    gWindow.backgroundColor = [UIColor clearColor];

    gOverlay = [[OTOverlayView alloc] initWithFrame:CGRectMake(0,0,w,h)];
    [gWindow addSubview:gOverlay];
    gWindow.hidden = NO;
    [gWindow makeKeyAndVisible];
    NSLog(@"[OT] overlay spawned");
}

// ── hooks ─────────────────────────────────────────────────────────────────────
%hook Unitoreios

// Called right after server sets remainingSeconds — grab self == extraInfo
- (void)startUpdateTimer {
    %orig;
    if (!gExtraInfo) {
        gExtraInfo = self;
        NSLog(@"[OT] grabbed extraInfo singleton: %@", self);
        dispatch_async(dispatch_get_main_queue(), ^{ spawnOverlay(); });
    }
}

// Also hook updateTime so remainingSeconds stays in sync with display
- (void)updateTime {
    %orig;
    // gOverlay refreshes itself via its own NSTimer — nothing needed here
}

%end

// ── constructor ───────────────────────────────────────────────────────────────
%ctor {
    NSLog(@"[OT] OfflineTimeTest loaded");
    // Spawn overlay early so it appears even before key validation
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        spawnOverlay();
    });
}
