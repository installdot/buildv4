// tweak.xm — Thiên Ma Đạo | Dev Panel 
// Theos/Logos — iOS 14+  (arm64)
// UI: Solo Leveling "System" aesthetic
// Build: theos make package FINALPACKAGE=1

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ═══════════════════════════════════════════════════════════════
// MARK: — Global State
// ═══════════════════════════════════════════════════════════════
static NSString *const kTargetHost     = @"tmd-game.duckdns.org";
static NSString *const kFirebaseKey    = @"AIzaSyBMBKs0r821LGpLwc3lGN8CeoLbNi-dths";
static NSString *const kBundleId       = @"com.playmoon.thienmadao.ios";
static NSString *const kServer         = @"server001";

static NSString   *gToken      = nil;
static NSString   *gCharId     = nil;
static NSArray    *gCharacters = nil;
static UIWindow   *gOverlay    = nil;   // Overlay window that holds floating button

// ═══════════════════════════════════════════════════════════════
// MARK: — Solo Leveling Palette & Fonts
// ═══════════════════════════════════════════════════════════════
static inline UIColor *SLC(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r/255.f green:g/255.f blue:b/255.f alpha:a];
}
#define SL_BG        SLC(4,   4,   14,  1.00)
#define SL_PANEL     SLC(6,   8,   22,  0.97)
#define SL_CARD      SLC(10,  14,  38,  1.00)
#define SL_BORDER    SLC(0,   140, 255, 0.60)
#define SL_BLUE      SLC(0,   168, 255, 1.00)
#define SL_BLUE2     SLC(80,  60,  255, 1.00)
#define SL_TEXT      SLC(210, 228, 255, 1.00)
#define SL_MUTED     SLC(80,  100, 160, 1.00)
#define SL_GOLD      SLC(255, 198, 50,  1.00)
#define SL_GREEN     SLC(30,  220, 120, 1.00)
#define SL_RED       SLC(255, 60,  60,  1.00)
#define SL_ORANGE    SLC(255, 140, 30,  1.00)

static UIFont *SLFont(CGFloat size, BOOL bold) {
    NSString *name = bold ? @"AvenirNext-Heavy" : @"AvenirNext-Regular";
    UIFont *f = [UIFont fontWithName:name size:size];
    return f ?: (bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size]);
}
static UIFont *SLMono(CGFloat size) {
    return [UIFont fontWithName:@"Courier-Bold" size:size] ?: [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightBold];
}

// ═══════════════════════════════════════════════════════════════
// MARK: — Helpers: CALayer glow & gradient border
// ═══════════════════════════════════════════════════════════════
static void applyGlowBorder(UIView *v, UIColor *color, CGFloat radius, CGFloat width) {
    v.layer.borderColor  = color.CGColor;
    v.layer.borderWidth  = width;
    v.layer.cornerRadius = radius;
    v.layer.shadowColor  = color.CGColor;
    v.layer.shadowRadius = 8;
    v.layer.shadowOpacity = 0.9;
    v.layer.shadowOffset  = CGSizeZero;
}

// Diagonal lines pattern image (Solo Leveling UI motif)
static UIImage *diagonalPatternImage(void) {
    CGSize size = CGSizeMake(20, 20);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(ctx, [SLC(0, 140, 255, 0.06) CGColor]);
    CGContextSetLineWidth(ctx, 1);
    for (int i = -20; i < 40; i += 6) {
        CGContextMoveToPoint(ctx, i, 0);
        CGContextAddLineToPoint(ctx, i + 20, 20);
    }
    CGContextStrokePath(ctx);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

// ═══════════════════════════════════════════════════════════════
// MARK: — API Manager
// ═══════════════════════════════════════════════════════════════
@interface TMDApi : NSObject
+ (void)post:(NSString *)url
        body:(NSDictionary *)body
     headers:(NSDictionary *)headers
  completion:(void(^)(NSInteger code, NSDictionary *json))cb;
+ (void)gamePost:(NSString *)path
            body:(NSDictionary *)body
      completion:(void(^)(NSInteger code, NSDictionary *json))cb;
+ (NSDictionary *)gameHeaders;
@end

@implementation TMDApi

+ (NSDictionary *)gameHeaders {
    if (!gToken) return @{};
    return @{
        @"Host":             kTargetHost,
        @"Accept-Encoding":  @"gzip, deflate, br",
        @"Connection":       @"keep-alive",
        @"Accept":           @"*/*",
        @"User-Agent":       @"ThinMao/0 CFNetwork/1410.0.3 Darwin/22.6.0",
        @"Accept-Language":  @"vi-VN,vi;q=0.9",
        @"X-Unity-Version":  @"6000.2.8f1",
        @"Content-Type":     @"application/json",
        @"Authorization":    [NSString stringWithFormat:@"Bearer %@", gToken],
    };
}

+ (void)post:(NSString *)url
        body:(NSDictionary *)body
     headers:(NSDictionary *)headers
  completion:(void(^)(NSInteger code, NSDictionary *json))cb {

    NSURL *u = [NSURL URLWithString:url];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u];
    req.HTTPMethod = @"POST";
    [headers enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *s) {
        [req setValue:v forHTTPHeaderField:k];
    }];
    if (body) {
        req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    }

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        NSDictionary *json = nil;
        if (data) {
            json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ cb(code, json ?: @{}); });
    }] resume];
}

+ (void)gamePost:(NSString *)path body:(NSDictionary *)body completion:(void(^)(NSInteger,NSDictionary*))cb {
    NSString *url = [NSString stringWithFormat:@"https://%@%@", kTargetHost, path];
    [self post:url body:body headers:[self gameHeaders] completion:cb];
}

@end

// UILabel category for letter spacing
@interface UILabel (SLSpacing)
@property (nonatomic) CGFloat letterSpacing;
@end
@implementation UILabel (SLSpacing)
- (void)setLetterSpacing:(CGFloat)s {
    if (!self.text) return;
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:self.text];
    [as addAttribute:NSKernAttributeName value:@(s) range:NSMakeRange(0, as.length)];
    self.attributedText = as;
}
- (CGFloat)letterSpacing { return 0; }
@end

// ═══════════════════════════════════════════════════════════════
// MARK: — System Notification (Solo Leveling style)
// ═══════════════════════════════════════════════════════════════
@interface TMDSystemNotif : UIView
@property (nonatomic, strong) UILabel *titleLbl;
@property (nonatomic, strong) UILabel *msgLbl;
@property (nonatomic, strong) NSTimer *typeTimer;
@property (nonatomic, copy)   NSString *fullMsg;
@property (nonatomic) NSInteger charIndex;
+ (void)show:(NSString *)message;
+ (void)showTitle:(NSString *)title msg:(NSString *)msg;
@end

@implementation TMDSystemNotif

+ (void)show:(NSString *)message {
    [self showTitle:@"[ HỆ THỐNG ]" msg:message];
}

+ (void)showTitle:(NSString *)title msg:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                win = scene.windows.firstObject;
                break;
            }
        }
        if (!win) return;

        CGFloat sw = win.bounds.size.width;
        CGFloat padding = 16.f;
        CGFloat w = sw - padding * 2;

        TMDSystemNotif *n = [[TMDSystemNotif alloc] initWithFrame:CGRectMake(padding, -160, w, 140)];
        n.layer.cornerRadius = 4;
        n.layer.masksToBounds = NO;
        n.backgroundColor = SLC(4, 6, 20, 0.96);
        applyGlowBorder(n, SL_BLUE, 4, 1.5);

        // Top accent line
        UIView *accent = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 2)];
        accent.backgroundColor = SL_BLUE;
        accent.layer.cornerRadius = 1;
        [n addSubview:accent];

        // Corner ornaments
        for (NSValue *corner in @[
            [NSValue valueWithCGRect:CGRectMake(0, 0, 8, 1)],
            [NSValue valueWithCGRect:CGRectMake(0, 0, 1, 8)],
            [NSValue valueWithCGRect:CGRectMake(w - 8, 0, 8, 1)],
            [NSValue valueWithCGRect:CGRectMake(w - 1, 0, 1, 8)],
            [NSValue valueWithCGRect:CGRectMake(0, 138, 8, 1)],
            [NSValue valueWithCGRect:CGRectMake(0, 130, 1, 8)],
            [NSValue valueWithCGRect:CGRectMake(w - 8, 138, 8, 1)],
            [NSValue valueWithCGRect:CGRectMake(w - 1, 130, 1, 8)],
        ]) {
            UIView *c = [[UIView alloc] initWithFrame:corner.CGRectValue];
            c.backgroundColor = SL_BLUE;
            [n addSubview:c];
        }

        // Title
        UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(16, 14, w - 32, 18)];
        tl.text = title;
        tl.font = SLMono(11);
        tl.textColor = SL_BLUE;
        tl.letterSpacing = 2;
        [n addSubview:tl];

        // Separator
        UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(16, 36, w - 32, 0.5)];
        sep.backgroundColor = SLC(0, 140, 255, 0.35);
        [n addSubview:sep];

        // Message label
        UILabel *ml = [[UILabel alloc] initWithFrame:CGRectMake(16, 44, w - 32, 84)];
        ml.textColor = SL_TEXT;
        ml.font = SLFont(14, NO);
        ml.numberOfLines = 0;
        ml.lineBreakMode = NSLineBreakByWordWrapping;
        [n addSubview:ml];

        n.titleLbl = tl;
        n.msgLbl   = ml;
        n.fullMsg  = msg;
        n.charIndex = 0;

        [win addSubview:n];

        // Safe area top offset
        CGFloat safeTop = win.safeAreaInsets.top + 8;
        CGRect toFrame = CGRectMake(padding, safeTop, w, 140);

        [UIView animateWithDuration:0.4
                              delay:0
             usingSpringWithDamping:0.7
              initialSpringVelocity:0.5
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{ n.frame = toFrame; }
                         completion:^(BOOL _) {
            [n startTypewriter];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.35 animations:^{
                    n.alpha = 0;
                    n.transform = CGAffineTransformMakeTranslation(0, -30);
                } completion:^(BOOL _) { [n removeFromSuperview]; }];
            });
        }];
    });
}

- (void)startTypewriter {
    self.typeTimer = [NSTimer scheduledTimerWithTimeInterval:0.03
                                                     target:self
                                                   selector:@selector(typeNext)
                                                   userInfo:nil
                                                    repeats:YES];
}

- (void)typeNext {
    if (self.charIndex >= (NSInteger)self.fullMsg.length) {
        [self.typeTimer invalidate];
        return;
    }
    self.charIndex++;
    self.msgLbl.text = [self.fullMsg substringToIndex:self.charIndex];
}

- (void)dealloc { [self.typeTimer invalidate]; }

@end

// ═══════════════════════════════════════════════════════════════
// MARK: — Loading View
// ═══════════════════════════════════════════════════════════════
#define CLAMP(v,lo,hi) MAX((lo), MIN((hi), (v)))

@interface TMDLoadingView : UIView
@property (nonatomic, strong) UILabel *statusLbl;
@property (nonatomic, strong) UIView  *bar;
@property (nonatomic, strong) UIView  *barFill;
@property (nonatomic) CGFloat progress;
- (void)setProgress:(CGFloat)p animated:(BOOL)anim;
- (void)setStatus:(NSString *)s;
@end

@implementation TMDLoadingView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = SL_BG;

    // Background pattern
    UIColor *pat = [UIColor colorWithPatternImage:diagonalPatternImage()];
    UIView *patView = [[UIView alloc] initWithFrame:self.bounds];
    patView.backgroundColor = pat;
    patView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:patView];

    CGFloat w = frame.size.width;
    CGFloat h = frame.size.height;

    // Logo container
    UIView *logo = [[UIView alloc] initWithFrame:CGRectMake(w/2 - 140, h/2 - 100, 280, 80)];

    UILabel *sys = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 280, 40)];
    sys.text = @"H Ệ   T H Ố N G";
    sys.font = SLMono(22);
    sys.textColor = SL_BLUE;
    sys.textAlignment = NSTextAlignmentCenter;
    sys.layer.shadowColor = SL_BLUE.CGColor;
    sys.layer.shadowRadius = 12;
    sys.layer.shadowOpacity = 1;
    sys.layer.shadowOffset  = CGSizeZero;
    [logo addSubview:sys];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(0, 44, 280, 20)];
    sub.text = @"THIÊN MA ĐẠO — DEV CONSOLE";
    sub.font = SLFont(11, NO);
    sub.textColor = SL_MUTED;
    sub.textAlignment = NSTextAlignmentCenter;
    [logo addSubview:sub];

    [self addSubview:logo];

    // Progress bar bg
    UIView *barBg = [[UIView alloc] initWithFrame:CGRectMake(w/2 - 120, h/2 + 20, 240, 3)];
    barBg.backgroundColor = SLC(0, 60, 100, 0.5);
    barBg.layer.cornerRadius = 1.5;
    [self addSubview:barBg];

    // Progress bar fill
    _barFill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 3)];
    _barFill.backgroundColor = SL_BLUE;
    _barFill.layer.cornerRadius = 1.5;
    _barFill.layer.shadowColor = SL_BLUE.CGColor;
    _barFill.layer.shadowRadius = 4;
    _barFill.layer.shadowOpacity = 1;
    _barFill.layer.shadowOffset  = CGSizeZero;
    [barBg addSubview:_barFill];
    _bar = barBg;

    // Status label
    _statusLbl = [[UILabel alloc] initWithFrame:CGRectMake(w/2 - 150, h/2 + 36, 300, 24)];
    _statusLbl.text = @"Đang kết nối hệ thống...";
    _statusLbl.font = SLMono(11);
    _statusLbl.textColor = SL_MUTED;
    _statusLbl.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_statusLbl];

    // Pulsing dots
    UILabel *dots = [[UILabel alloc] initWithFrame:CGRectMake(w/2 - 30, h/2 + 60, 60, 20)];
    dots.text = @"● ● ●";
    dots.font = [UIFont systemFontOfSize:8];
    dots.textColor = SL_BLUE;
    dots.textAlignment = NSTextAlignmentCenter;
    [self addSubview:dots];

    // Pulse animation
    [UIView animateWithDuration:0.8
                          delay:0
                        options:UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse
                     animations:^{ dots.alpha = 0.2; }
                     completion:nil];

    return self;
}

- (void)setProgress:(CGFloat)p animated:(BOOL)anim {
    _progress = CLAMP(p, 0, 1);
    CGFloat fullW = _bar.bounds.size.width;
    void(^update)(void) = ^{ self.barFill.frame = CGRectMake(0, 0, fullW * self->_progress, 3); };
    if (anim) [UIView animateWithDuration:0.3 animations:update];
    else update();
}

- (void)setStatus:(NSString *)s { _statusLbl.text = s; }

#define CLAMP(v,lo,hi) MAX((lo), MIN((hi), (v)))
@end

// ═══════════════════════════════════════════════════════════════
// MARK: — Styled Button
// ═══════════════════════════════════════════════════════════════
@interface SLButton : UIButton
+ (instancetype)buttonWithTitle:(NSString *)t color:(UIColor *)c;
@end
@implementation SLButton
+ (instancetype)buttonWithTitle:(NSString *)t color:(UIColor *)c {
    SLButton *b = [SLButton buttonWithType:UIButtonTypeCustom];
    b.backgroundColor = [c colorWithAlphaComponent:0.12];
    b.layer.borderColor = [c colorWithAlphaComponent:0.6].CGColor;
    b.layer.borderWidth = 1;
    b.layer.cornerRadius = 4;
    b.layer.shadowColor  = c.CGColor;
    b.layer.shadowRadius = 6;
    b.layer.shadowOpacity = 0.5;
    b.layer.shadowOffset  = CGSizeZero;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:c forState:UIControlStateNormal];
    b.titleLabel.font = SLMono(13);
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    [b addTarget:b action:@selector(slTouchDown) forControlEvents:UIControlEventTouchDown];
    [b addTarget:b action:@selector(slTouchUp)   forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return b;
}
- (void)slTouchDown {
    [UIView animateWithDuration:0.1 animations:^{ self.transform = CGAffineTransformMakeScale(0.96, 0.96); self.alpha = 0.8; }];
}
- (void)slTouchUp {
    [UIView animateWithDuration:0.15 animations:^{ self.transform = CGAffineTransformIdentity; self.alpha = 1; }];
}
@end

// ═══════════════════════════════════════════════════════════════
// MARK: — Styled Text Field
// ═══════════════════════════════════════════════════════════════
@interface SLTextField : UITextField @end
@implementation SLTextField
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor = SLC(4, 8, 25, 1);
    self.textColor = SL_TEXT;
    self.font = SLFont(14, NO);
    self.tintColor = SL_BLUE;
    applyGlowBorder(self, SL_BORDER, 4, 1);
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0,0,12,0)];
    self.leftView = pad;
    self.leftViewMode = UITextFieldViewModeAlways;
    return self;
}
- (CGRect)textRect:(CGRect)bounds            { return CGRectInset(bounds, 12, 0); }
- (CGRect)editingRect:(CGRect)bounds         { return CGRectInset(bounds, 12, 0); }
- (CGRect)placeholderRectForBounds:(CGRect)b { return CGRectInset(b, 12, 0); }
- (void)setPlaceholder:(NSString *)s {
    self.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:s attributes:@{ NSForegroundColorAttributeName: SL_MUTED }];
}
@end

// ═══════════════════════════════════════════════════════════════
// MARK: — Main Panel Controller
// ═══════════════════════════════════════════════════════════════
@interface TMDPanelVC : UIViewController
<UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>

@property (nonatomic, strong) UIView         *container;
@property (nonatomic, strong) TMDLoadingView *loadingView;
@property (nonatomic, strong) UIScrollView   *contentScroll;
@property (nonatomic, strong) UIView         *contentView;

// — Character info
@property (nonatomic, strong) UILabel *charNameLbl;
@property (nonatomic, strong) UILabel *charRealmLbl;
@property (nonatomic, strong) UILabel *charExpLbl;

// — Tabs
@property (nonatomic, strong) UIView        *tabBar;
@property (nonatomic, strong) NSArray<UIButton*> *tabBtns;
@property (nonatomic) NSInteger              activeTab;
@property (nonatomic, strong) UIView        *tabIndicator;

// — Panels (one UIView per tab)
@property (nonatomic, strong) UIView *tabEXP;
@property (nonatomic, strong) UIView *tabItem;
@property (nonatomic, strong) UIView *tabBreak;
@property (nonatomic, strong) UIView *tabTiemNang;
@property (nonatomic, strong) UIView *tabAuto;

// — EXP
@property (nonatomic, strong) SLTextField *expField;

// — Item
@property (nonatomic, strong) SLTextField *itemSearchField;
@property (nonatomic, strong) UITableView *itemTable;
@property (nonatomic, strong) SLTextField *itemCountField;
@property (nonatomic, strong) SLTextField *manualItemField;
@property (nonatomic, strong) NSArray     *allItems;
@property (nonatomic, strong) NSArray     *filteredItems;

// — Auto run
@property (nonatomic) BOOL autoRunning;
@property (nonatomic) BOOL autoStop;
@property (nonatomic) NSInteger autoLoops;
@property (nonatomic) NSInteger autoSuccess;
@property (nonatomic) NSInteger autoFail;
@property (nonatomic, strong) UILabel *autoLoopLbl;
@property (nonatomic, strong) UILabel *autoSuccessLbl;
@property (nonatomic, strong) UILabel *autoFailLbl;
@property (nonatomic, strong) UILabel *autoStatusLbl;
@property (nonatomic, strong) UIView  *autoStatusDot;
@property (nonatomic, strong) UITextView *autoLogView;
@property (nonatomic, strong) SLButton   *autoStartBtn;
@property (nonatomic, strong) SLButton   *autoStopBtn;

// — Tiềm Năng
@property (nonatomic, strong) NSMutableDictionary *tnOrig;
@property (nonatomic, strong) NSMutableDictionary *tnFields;

// — current char data
@property (nonatomic, strong) NSDictionary *charData;

@end

@implementation TMDPanelVC

static NSArray *kTNKeys(void) {
    return @[@"CamNhan", @"SucManh", @"LinhHoat", @"TheLuc", @"TriLuc"];
}
static NSDictionary *kTNLabels(void) {
    return @{@"CamNhan":@"Cảm Nhận", @"SucManh":@"Sức Mạnh",
             @"LinhHoat":@"Linh Hoạt", @"TheLuc":@"Thể Lực", @"TriLuc":@"Trí Lực"};
}

// ─────────────────────────────────────────────
// MARK: viewDidLoad
// ─────────────────────────────────────────────
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    CGFloat sh = UIScreen.mainScreen.bounds.size.height;
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;

    // Dimmed backdrop
    UIView *dim = [[UIView alloc] initWithFrame:self.view.bounds];
    dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeSelf)];
    [dim addGestureRecognizer:tap];
    [self.view addSubview:dim];

    // Container (85% height, full width)
    CGFloat panelH = sh * 0.88;
    _container = [[UIView alloc] initWithFrame:CGRectMake(0, sh, sw, panelH)];
    _container.backgroundColor = SL_PANEL;
    _container.layer.cornerRadius = 16;
    _container.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    _container.layer.borderColor  = [SL_BORDER colorWithAlphaComponent:0.5].CGColor;
    _container.layer.borderWidth  = 1;
    _container.layer.shadowColor  = SL_BLUE.CGColor;
    _container.layer.shadowRadius = 20;
    _container.layer.shadowOpacity = 0.3;
    _container.layer.shadowOffset  = CGSizeZero;
    _container.clipsToBounds = YES;

    // Background pattern
    UIView *pat = [[UIView alloc] initWithFrame:_container.bounds];
    pat.backgroundColor = [UIColor colorWithPatternImage:diagonalPatternImage()];
    pat.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_container addSubview:pat];

    [self.view addSubview:_container];

    // Drag handle
    UIView *handle = [[UIView alloc] initWithFrame:CGRectMake(sw/2 - 24, 10, 48, 4)];
    handle.backgroundColor = SL_BORDER;
    handle.layer.cornerRadius = 2;
    [_container addSubview:handle];

    // Header
    [self buildHeader:sw];

    // Tab bar
    [self buildTabBar:sw];

    // Content scroll view (below header 44 + tabs 44 = ~120)
    CGFloat topOffset = 100;
    _contentScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, topOffset, sw, panelH - topOffset)];
    _contentScroll.showsVerticalScrollIndicator = NO;
    _contentScroll.backgroundColor = [UIColor clearColor];
    [_container addSubview:_contentScroll];

    // Build all tab content views
    [self buildTabViews:sw];
    [self switchTab:0 animated:NO];

    // Loading overlay
    _loadingView = [[TMDLoadingView alloc] initWithFrame:_container.bounds];
    [_container addSubview:_loadingView];

    // Slide up animation
    [UIView animateWithDuration:0.45 delay:0
         usingSpringWithDamping:0.82 initialSpringVelocity:0.6
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{ self.container.frame = CGRectMake(0, sh - panelH, sw, panelH); }
                     completion:nil];

    // Start login flow
    [self startLogin];
}

// ─────────────────────────────────────────────
// MARK: Header
// ─────────────────────────────────────────────
- (void)buildHeader:(CGFloat)sw {
    // Top accent line
    UIView *topLine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, sw, 2)];
    topLine.backgroundColor = SL_BLUE;
    topLine.layer.shadowColor  = SL_BLUE.CGColor;
    topLine.layer.shadowRadius = 8;
    topLine.layer.shadowOpacity = 1;
    topLine.layer.shadowOffset  = CGSizeZero;
    [_container addSubview:topLine];

    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 20, sw - 100, 22)];
    titleLbl.text = @"⚔  HỆ THỐNG — THIÊN MA ĐẠO";
    titleLbl.font = SLMono(12);
    titleLbl.textColor = SL_BLUE;
    titleLbl.letterSpacing = 1.5;
    [_container addSubview:titleLbl];

    // Char info pill
    _charNameLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 44, sw - 32, 18)];
    _charNameLbl.text = @"Đang tải...";
    _charNameLbl.font = SLFont(13, YES);
    _charNameLbl.textColor = SL_GOLD;
    [_container addSubview:_charNameLbl];

    _charRealmLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 60, (sw - 32)/2, 16)];
    _charRealmLbl.font = SLFont(12, NO);
    _charRealmLbl.textColor = SL_MUTED;
    [_container addSubview:_charRealmLbl];

    _charExpLbl = [[UILabel alloc] initWithFrame:CGRectMake(sw/2, 60, sw/2 - 16, 16)];
    _charExpLbl.font = SLFont(12, NO);
    _charExpLbl.textColor = SL_MUTED;
    _charExpLbl.textAlignment = NSTextAlignmentRight;
    [_container addSubview:_charExpLbl];

    // Close button
    SLButton *closeBtn = [SLButton buttonWithTitle:@"✕" color:SL_RED];
    closeBtn.frame = CGRectMake(sw - 48, 14, 36, 36);
    [closeBtn addTarget:self action:@selector(closeSelf) forControlEvents:UIControlEventTouchUpInside];
    [_container addSubview:closeBtn];

    // Separator
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 82, sw, 0.5)];
    sep.backgroundColor = [SL_BLUE colorWithAlphaComponent:0.2];
    [_container addSubview:sep];
}

// ─────────────────────────────────────────────
// MARK: Tab Bar
// ─────────────────────────────────────────────
- (void)buildTabBar:(CGFloat)sw {
    _tabBar = [[UIView alloc] initWithFrame:CGRectMake(0, 83, sw, 44)];
    _tabBar.backgroundColor = SLC(4, 6, 20, 1);

    NSArray *titles = @[@"EXP", @"VẬT PHẨM", @"ĐỘT PHÁ", @"TIỀM NĂNG", @"TỰ ĐỘNG"];
    NSMutableArray *btns = [NSMutableArray array];
    CGFloat bw = sw / titles.count;

    for (NSInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(i * bw, 0, bw, 44);
        b.tag = i;
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b setTitleColor:SL_MUTED forState:UIControlStateNormal];
        [b setTitleColor:SL_BLUE  forState:UIControlStateSelected];
        b.titleLabel.font = SLFont(10, YES);
        b.titleLabel.adjustsFontSizeToFitWidth = YES;
        b.titleLabel.minimumScaleFactor = 0.6;
        [b addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_tabBar addSubview:b];
        [btns addObject:b];
    }
    _tabBtns = [btns copy];

    // Active indicator
    _tabIndicator = [[UIView alloc] initWithFrame:CGRectMake(0, 42, bw, 2)];
    _tabIndicator.backgroundColor = SL_BLUE;
    _tabIndicator.layer.shadowColor   = SL_BLUE.CGColor;
    _tabIndicator.layer.shadowRadius  = 4;
    _tabIndicator.layer.shadowOpacity = 1;
    _tabIndicator.layer.shadowOffset  = CGSizeZero;
    [_tabBar addSubview:_tabIndicator];

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 43.5, sw, 0.5)];
    sep.backgroundColor = [SL_BLUE colorWithAlphaComponent:0.2];
    [_tabBar addSubview:sep];

    [_container addSubview:_tabBar];
}

- (void)tabTapped:(UIButton *)sender {
    [self switchTab:sender.tag animated:YES];
}

- (void)switchTab:(NSInteger)idx animated:(BOOL)anim {
    _activeTab = idx;
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    CGFloat bw = sw / _tabBtns.count;

    for (NSInteger i = 0; i < (NSInteger)_tabBtns.count; i++) {
        _tabBtns[i].selected = (i == idx);
    }

    CGRect indFrame = CGRectMake(idx * bw, 42, bw, 2);
    if (anim) {
        [UIView animateWithDuration:0.25 animations:^{ self.tabIndicator.frame = indFrame; }];
    } else {
        _tabIndicator.frame = indFrame;
    }

    NSArray *panels = @[_tabEXP, _tabItem, _tabBreak, _tabTiemNang, _tabAuto];
    for (NSInteger i = 0; i < (NSInteger)panels.count; i++) {
        UIView *p = panels[i];
        if (!p) continue;
        p.hidden = (i != idx);
    }
    _contentScroll.contentOffset = CGPointZero;
}

// ─────────────────────────────────────────────
// MARK: Tab Views Builder
// ─────────────────────────────────────────────
- (void)buildTabViews:(CGFloat)sw {
    CGFloat cw = sw - 32;

    _tabEXP       = [self buildTabEXP:cw];
    _tabItem      = [self buildTabItem:cw];
    _tabBreak     = [self buildTabBreak:cw];
    _tabTiemNang  = [self buildTabTiemNang:cw];
    _tabAuto      = [self buildTabAuto:cw];

    NSArray *views = @[_tabEXP, _tabItem, _tabBreak, _tabTiemNang, _tabAuto];
    CGFloat totalH = 0;
    for (UIView *v in views) {
        v.frame = CGRectMake(16, 16, cw, v.frame.size.height);
        [_contentScroll addSubview:v];
        totalH = MAX(totalH, CGRectGetMaxY(v.frame) + 32);
    }
    _contentScroll.contentSize = CGSizeMake(sw, totalH);
}

// ──────────── EXP Tab ────────────
- (UIView *)buildTabEXP:(CGFloat)w {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0,0,w,200)];

    UILabel *h = [self sectionHeader:@"✦ THÊM LINH KHÍ" width:w];
    [v addSubview:h];

    UILabel *hint = [self hintLabel:@"Thêm EXP tu luyện vào nhân vật đang chọn." width:w y:32];
    [v addSubview:hint];

    _expField = [[SLTextField alloc] initWithFrame:CGRectMake(0, 58, w, 44)];
    _expField.placeholder = @"Số Linh Khí (mặc định: 1,000,000,000)";
    _expField.text = @"1000000000";
    _expField.keyboardType = UIKeyboardTypeNumberPad;
    _expField.returnKeyType = UIReturnKeyDone;
    _expField.delegate = self;
    [v addSubview:_expField];

    SLButton *btn = [SLButton buttonWithTitle:@"[ THÊM LINH KHÍ ]" color:SL_GOLD];
    btn.frame = CGRectMake(0, 114, w, 48);
    [btn addTarget:self action:@selector(doAddEXP) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:btn];

    v.frame = CGRectMake(0, 0, w, 180);
    return v;
}

// ──────────── Item Tab ────────────
- (UIView *)buildTabItem:(CGFloat)w {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0,0,w,520)];

    UILabel *h = [self sectionHeader:@"✦ TẶNG VẬT PHẨM" width:w];
    [v addSubview:h];

    _itemSearchField = [[SLTextField alloc] initWithFrame:CGRectMake(0, 32, w, 38)];
    _itemSearchField.placeholder = @"Tìm kiếm (DanDuoc, CongPhap, Pet…)";
    _itemSearchField.delegate = self;
    [_itemSearchField addTarget:self action:@selector(itemSearchChanged:) forControlEvents:UIControlEventEditingChanged];
    [v addSubview:_itemSearchField];

    _itemTable = [[UITableView alloc] initWithFrame:CGRectMake(0, 78, w, 200) style:UITableViewStylePlain];
    _itemTable.backgroundColor = SLC(4, 8, 25, 1);
    _itemTable.layer.borderColor  = [SL_BORDER colorWithAlphaComponent:0.4].CGColor;
    _itemTable.layer.borderWidth  = 1;
    _itemTable.layer.cornerRadius = 4;
    _itemTable.separatorColor = [SL_BORDER colorWithAlphaComponent:0.2];
    _itemTable.delegate   = self;
    _itemTable.dataSource = self;
    _itemTable.rowHeight  = 34;
    [_itemTable registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    [v addSubview:_itemTable];

    UILabel *cntLbl = [self hintLabel:@"Số lượng:" width:60 y:286];
    [v addSubview:cntLbl];

    _itemCountField = [[SLTextField alloc] initWithFrame:CGRectMake(0, 284, w, 38)];
    _itemCountField.placeholder = @"Số lượng (mặc định: 10000)";
    _itemCountField.text = @"10000";
    _itemCountField.keyboardType = UIKeyboardTypeNumberPad;
    _itemCountField.delegate = self;
    [v addSubview:_itemCountField];

    SLButton *grantBtn = [SLButton buttonWithTitle:@"[ TẶNG VẬT PHẨM CHỌN ]" color:SL_BLUE2];
    grantBtn.frame = CGRectMake(0, 334, w, 44);
    [grantBtn addTarget:self action:@selector(doGrantSelected) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:grantBtn];

    UILabel *manLbl = [self sectionHeader:@"— NHẬP THỦ CÔNG —" width:w];
    manLbl.frame = CGRectMake(0, 392, w, 20);
    [v addSubview:manLbl];

    _manualItemField = [[SLTextField alloc] initWithFrame:CGRectMake(0, 418, w, 38)];
    _manualItemField.placeholder = @"VD: CongPhap_3_AmDuongHop, Pet_1_DaNhan";
    _manualItemField.autocorrectionType = UITextAutocorrectionTypeNo;
    _manualItemField.delegate = self;
    [v addSubview:_manualItemField];

    SLButton *manBtn = [SLButton buttonWithTitle:@"[ TẶNG THỦ CÔNG ]" color:SL_GOLD];
    manBtn.frame = CGRectMake(0, 466, w, 44);
    [manBtn addTarget:self action:@selector(doGrantManual) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:manBtn];

    v.frame = CGRectMake(0, 0, w, 520);
    return v;
}

// ──────────── Breakthrough Tab ────────────
- (UIView *)buildTabBreak:(CGFloat)w {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0,0,w,360)];

    UILabel *h = [self sectionHeader:@"⚡ ĐỘT PHÁ CẢNH GIỚI" width:w];
    [v addSubview:h];

    UILabel *desc = [[UILabel alloc] initWithFrame:CGRectMake(0, 32, w, 60)];
    desc.text = @"Tự động đột phá một lần. Nếu thiếu đan dược sẽ tự cấp rồi thử lại. Nếu thất bại RNG sẽ tiếp tục cho đến khi thành công (tối đa 30 lần).";
    desc.font = SLFont(12, NO);
    desc.textColor = SL_MUTED;
    desc.numberOfLines = 0;
    [v addSubview:desc];

    SLButton *btn = [SLButton buttonWithTitle:@"[ THỰC HIỆN ĐỘT PHÁ ]" color:SL_RED];
    btn.frame = CGRectMake(0, 100, w, 48);
    [btn addTarget:self action:@selector(doManualBreakthrough) forControlEvents:UIControlEventTouchUpInside];
    btn.tag = 801;
    [v addSubview:btn];

    UITextView *log = [[UITextView alloc] initWithFrame:CGRectMake(0, 162, w, 180)];
    log.backgroundColor = SLC(4, 8, 25, 1);
    log.textColor = SL_TEXT;
    log.font = [UIFont fontWithName:@"Courier" size:11];
    log.editable = NO;
    log.layer.borderColor  = [SL_BORDER colorWithAlphaComponent:0.3].CGColor;
    log.layer.borderWidth  = 1;
    log.layer.cornerRadius = 4;
    log.tag = 802;
    [v addSubview:log];

    v.frame = CGRectMake(0, 0, w, 356);
    return v;
}

// ──────────── Tiềm Năng Tab ────────────
- (UIView *)buildTabTiemNang:(CGFloat)w {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0,0,w,500)];

    UILabel *h = [self sectionHeader:@"✧ PHÂN BỔ TIỀM NĂNG" width:w];
    [v addSubview:h];

    UILabel *desc = [[UILabel alloc] initWithFrame:CGRectMake(0, 32, w, 40)];
    desc.text = @"Nhập giá trị mong muốn. Hệ thống tự thêm Điểm Cộng rồi phân bổ stat.";
    desc.font = SLFont(12, NO);
    desc.textColor = SL_MUTED;
    desc.numberOfLines = 0;
    [v addSubview:desc];

    _tnOrig   = [NSMutableDictionary dictionary];
    _tnFields = [NSMutableDictionary dictionary];

    NSArray *keys = kTNKeys();
    NSDictionary *labels = kTNLabels();
    CGFloat fw = (w - 10) / 2;

    for (NSInteger i = 0; i < (NSInteger)keys.count; i++) {
        NSString *k = keys[i];
        CGFloat col = (i % 2) * (fw + 10);
        CGFloat row = 80 + (i / 2) * 66;

        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(col, row, fw, 18)];
        lbl.text = labels[k];
        lbl.font = SLFont(11, YES);
        lbl.textColor = SL_TEXT;
        [v addSubview:lbl];

        SLTextField *tf = [[SLTextField alloc] initWithFrame:CGRectMake(col, row + 20, fw, 38)];
        tf.placeholder = @"0";
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.delegate = self;
        tf.tag = 900 + i;
        [v addSubview:tf];
        _tnFields[k] = tf;
    }

    CGFloat btnY = 80 + (CGFloat)(((keys.count + 1) / 2)) * 66 + 10;

    SLButton *btn = [SLButton buttonWithTitle:@"[ PHÂN BỔ TIỀM NĂNG ]" color:SLC(20, 210, 140, 1)];
    btn.frame = CGRectMake(0, btnY, w, 48);
    [btn addTarget:self action:@selector(doAllocatePotential) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:btn];

    v.frame = CGRectMake(0, 0, w, btnY + 56);
    return v;
}

// ──────────── Auto Run Tab ────────────
- (UIView *)buildTabAuto:(CGFloat)w {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0,0,w,540)];

    UILabel *h = [self sectionHeader:@"🔄 TỰ ĐỘNG TU LUYỆN & ĐỘT PHÁ" width:w];
    [v addSubview:h];

    UILabel *desc = [[UILabel alloc] initWithFrame:CGRectMake(0, 32, w, 50)];
    desc.text = @"Tự động lặp: Thêm EXP → Đột Phá → lặp lại cho đến khi đạt cảnh giới tối đa hoặc bấm Dừng.";
    desc.font = SLFont(12, NO);
    desc.textColor = SL_MUTED;
    desc.numberOfLines = 0;
    [v addSubview:desc];

    // Status bar
    UIView *statusBar = [[UIView alloc] initWithFrame:CGRectMake(0, 90, w, 40)];
    statusBar.backgroundColor = SLC(4, 8, 25, 1);
    statusBar.layer.borderColor  = [SL_BORDER colorWithAlphaComponent:0.3].CGColor;
    statusBar.layer.borderWidth  = 1;
    statusBar.layer.cornerRadius = 4;
    [v addSubview:statusBar];

    _autoStatusDot = [[UIView alloc] initWithFrame:CGRectMake(12, 15, 10, 10)];
    _autoStatusDot.backgroundColor = SL_MUTED;
    _autoStatusDot.layer.cornerRadius = 5;
    [statusBar addSubview:_autoStatusDot];

    _autoStatusLbl = [[UILabel alloc] initWithFrame:CGRectMake(30, 10, w - 40, 20)];
    _autoStatusLbl.text = @"Chưa chạy";
    _autoStatusLbl.font = SLFont(12, NO);
    _autoStatusLbl.textColor = SL_TEXT;
    [statusBar addSubview:_autoStatusLbl];

    // Counters
    CGFloat cw2 = (w - 20) / 3;
    NSArray *counterTitles  = @[@"Vòng lặp", @"Đột phá OK", @"Thất bại"];
    NSArray *counterColors  = @[SL_ORANGE, SL_GREEN, SL_RED];
    NSMutableArray *labels  = [NSMutableArray array];
    for (NSInteger i = 0; i < 3; i++) {
        UIView *box = [[UIView alloc] initWithFrame:CGRectMake(i * (cw2 + 10), 140, cw2, 56)];
        box.backgroundColor = SLC(4, 8, 25, 1);
        box.layer.borderColor  = [SL_BORDER colorWithAlphaComponent:0.25].CGColor;
        box.layer.borderWidth  = 1;
        box.layer.cornerRadius = 4;
        [v addSubview:box];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 6, cw2, 16)];
        title.text = counterTitles[i];
        title.font = SLFont(9, YES);
        title.textColor = SL_MUTED;
        title.textAlignment = NSTextAlignmentCenter;
        [box addSubview:title];

        UILabel *val = [[UILabel alloc] initWithFrame:CGRectMake(0, 24, cw2, 28)];
        val.text = @"0";
        val.font = SLMono(20);
        val.textColor = counterColors[i];
        val.textAlignment = NSTextAlignmentCenter;
        [box addSubview:val];
        [labels addObject:val];
    }
    _autoLoopLbl    = labels[0];
    _autoSuccessLbl = labels[1];
    _autoFailLbl    = labels[2];

    // Start/Stop buttons
    _autoStartBtn = [SLButton buttonWithTitle:@"▶ BẮT ĐẦU TỰ ĐỘNG" color:SL_ORANGE];
    _autoStartBtn.frame = CGRectMake(0, 208, w * 0.6 - 6, 44);
    [_autoStartBtn addTarget:self action:@selector(startAutoRun) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:_autoStartBtn];

    _autoStopBtn = [SLButton buttonWithTitle:@"■ DỪNG" color:SL_MUTED];
    _autoStopBtn.frame = CGRectMake(w * 0.6 + 6, 208, w * 0.4 - 6, 44);
    _autoStopBtn.enabled = NO;
    [_autoStopBtn addTarget:self action:@selector(stopAutoRun) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:_autoStopBtn];

    // Log
    _autoLogView = [[UITextView alloc] initWithFrame:CGRectMake(0, 264, w, 260)];
    _autoLogView.backgroundColor = SLC(4, 8, 25, 1);
    _autoLogView.textColor = SL_TEXT;
    _autoLogView.font = [UIFont fontWithName:@"Courier" size:10];
    _autoLogView.editable = NO;
    _autoLogView.layer.borderColor  = [SL_BORDER colorWithAlphaComponent:0.3].CGColor;
    _autoLogView.layer.borderWidth  = 1;
    _autoLogView.layer.cornerRadius = 4;
    [v addSubview:_autoLogView];

    v.frame = CGRectMake(0, 0, w, 536);
    return v;
}

// ─────────────────────────────────────────────
// MARK: Helpers
// ─────────────────────────────────────────────
- (UILabel *)sectionHeader:(NSString *)t width:(CGFloat)w {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, w, 26)];
    l.text = t;
    l.font = SLMono(11);
    l.textColor = SL_BLUE;
    l.letterSpacing = 1.2;
    return l;
}
- (UILabel *)hintLabel:(NSString *)t width:(CGFloat)w y:(CGFloat)y {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, y, w, 18)];
    l.text = t;
    l.font = SLFont(12, NO);
    l.textColor = SL_MUTED;
    return l;
}

- (void)appendLog:(UITextView *)tv line:(NSString *)line color:(UIColor *)c {
    NSAttributedString *cur = tv.attributedText ?: [[NSAttributedString alloc] initWithString:@""];
    NSMutableAttributedString *next = [[NSMutableAttributedString alloc] initWithAttributedString:cur];
    NSDictionary *attrs = @{ NSForegroundColorAttributeName: c,
                             NSFontAttributeName: [UIFont fontWithName:@"Courier" size:10] };
    NSString *newLine = (cur.length > 0) ? [NSString stringWithFormat:@"\n%@", line] : line;
    [next appendAttributedString:[[NSAttributedString alloc] initWithString:newLine attributes:attrs]];
    tv.attributedText = next;
    [tv scrollRangeToVisible:NSMakeRange(tv.text.length, 0)];
}

// ─────────────────────────────────────────────
// MARK: Login Flow
// ─────────────────────────────────────────────
- (void)startLogin {
    [_loadingView setProgress:0.05 animated:NO];

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *email = [d stringForKey:@"CurrentAccount"];
    NSString *pass  = [d stringForKey:@"CurrentPassword"];

    if (!email.length || !pass.length) {
        [_loadingView setStatus:@"Không tìm thấy tài khoản trong NSUserDefaults"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self hideLoading];
            [TMDSystemNotif show:@"Không tìm thấy tài khoản. Vui lòng nhập thủ công."];
        });
        return;
    }

    [_loadingView setStatus:[NSString stringWithFormat:@"Đang đăng nhập: %@", email]];
    [_loadingView setProgress:0.2 animated:YES];

    NSDictionary *body = @{
        @"returnSecureToken": @YES,
        @"password":  pass,
        @"email":     email,
        @"clientType": @"CLIENT_TYPE_IOS",
    };
    NSDictionary *headers = @{
        @"x-client-version":       @"iOS/FirebaseSDK/11.14.0/FirebaseCore-iOS",
        @"content-type":           @"application/json",
        @"accept":                 @"*/*",
        @"x-ios-bundle-identifier": kBundleId,
        @"x-firebase-gmpid":       @"1:450058472283:ios:59f5c04277f277fc88a87e",
        @"user-agent":             @"FirebaseAuth.iOS/11.14.0 com.playmoon.thienmadao.ios/0.0.4 iPhone/16.6.1 hw/iPhone11_2",
        @"accept-language":        @"en",
        @"accept-encoding":        @"gzip, deflate, br",
    };

    NSString *url = [NSString stringWithFormat:@"https://www.googleapis.com/identitytoolkit/v3/relyingparty/verifyPassword?key=%@", kFirebaseKey];
    [TMDApi post:url body:body headers:headers completion:^(NSInteger code, NSDictionary *json) {
        NSString *tok = json[@"idToken"];
        if (code == 200 && tok.length) {
            gToken = tok;
            [self->_loadingView setStatus:@"Đăng nhập thành công — Đang tải nhân vật..."];
            [self->_loadingView setProgress:0.55 animated:YES];
            [self loadCharacters];
        } else {
            NSString *err = json[@"error"][@"message"] ?: @"Lỗi không xác định";
            [self->_loadingView setStatus:[NSString stringWithFormat:@"Đăng nhập thất bại: %@", err]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self hideLoading];
            });
        }
    }];
}

- (void)loadCharacters {
    NSString *path = [NSString stringWithFormat:@"/v1/servers/%@/characters", kServer];
    [TMDApi gamePost:path body:nil completion:^(NSInteger code, NSDictionary *json) {
        NSArray *chars = nil;
        if ([json isKindOfClass:[NSArray class]]) {
            chars = (NSArray *)json;
        } else if ([json[@"characters"] isKindOfClass:[NSArray class]]) {
            chars = json[@"characters"];
        } else {
            // Try raw data as array
            chars = [NSArray arrayWithObject:json];
        }
        gCharacters = chars;
        [self->_loadingView setProgress:0.8 animated:YES];
        [self->_loadingView setStatus:@"Đang tải vật phẩm từ server..."];
        [self loadItemConfig];
    }];
}

- (void)loadItemConfig {
    NSString *path = @"/api/cultivation/config";
    [TMDApi gamePost:path body:nil completion:^(NSInteger code, NSDictionary *json) {
        [self->_loadingView setProgress:1.0 animated:YES];
        [self->_loadingView setStatus:@"Hoàn tất — Kết nối hệ thống thành công!"];

        // Extract item IDs from config
        NSMutableSet *seen = [NSMutableSet set];
        NSMutableArray *items = [NSMutableArray array];
        [self collectIds:json seen:seen items:items];
        self.allItems = [items sortedArrayUsingSelector:@selector(compare:)];
        self.filteredItems = self.allItems;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self hideLoading];
            // Auto-select first character
            if (gCharacters.count > 0) {
                NSDictionary *c = gCharacters[0];
                if (!gCharId) gCharId = c[@"characterId"];
                self.charData = c;
                [self updateCharDisplay:c];
            }
            if (gCharacters.count > 1) {
                [self promptCharSelect];
            }
        });
    }];
}

- (void)collectIds:(id)data seen:(NSMutableSet *)seen items:(NSMutableArray *)items {
    if ([data isKindOfClass:[NSString class]]) {
        NSString *s = data;
        if ([s length] < 100 && [s length] > 4) {
            NSRegularExpression *rx = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z][A-Za-z0-9]+_\\d+_" options:0 error:nil];
            NSInteger m = [rx numberOfMatchesInString:s options:0 range:NSMakeRange(0, s.length)];
            if (m > 0 && ![seen containsObject:s]) {
                [seen addObject:s];
                [items addObject:s];
            }
        }
        return;
    }
    if ([data isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = data;
        NSArray *pkeys = @[@"itemId", @"congPhapId", @"client_ref", @"clientRefName",
                           @"petTargetClientRef", @"resultClientRef"];
        for (NSString *pk in pkeys) {
            NSString *v = dict[pk];
            if ([v isKindOfClass:[NSString class]] && v.length > 0 && ![seen containsObject:v]) {
                [seen addObject:v];
                [items addObject:v];
            }
        }
        for (id v in dict.allValues) [self collectIds:v seen:seen items:items];
        return;
    }
    if ([data isKindOfClass:[NSArray class]]) {
        for (id el in (NSArray *)data) [self collectIds:el seen:seen items:items];
    }
}

- (void)promptCharSelect {
    if (gCharacters.count <= 1) return;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Chọn Nhân Vật"
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *c in gCharacters) {
        NSString *name  = c[@"info"][@"name"] ?: @"Vô Danh";
        NSString *realm = c[@"cultivation"][@"realm"] ?: @"—";
        NSString *cid   = c[@"characterId"] ?: @"";
        [ac addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ (%@)", name, realm]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a) {
            gCharId = cid;
            self.charData = c;
            [self updateCharDisplay:c];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)updateCharDisplay:(NSDictionary *)c {
    NSString *name  = c[@"info"][@"name"] ?: @"Vô Danh";
    NSString *realm = c[@"cultivation"][@"realm"] ?: @"—";
    NSNumber *stage = c[@"cultivation"][@"stage"];
    NSNumber *etb   = c[@"cultivation"][@"expToBreak"];

    _charNameLbl.text  = [NSString stringWithFormat:@"⚔ %@", name];
    _charRealmLbl.text = [NSString stringWithFormat:@"%@ — Tầng %@", realm, stage ?: @"1"];
    _charExpLbl.text   = [NSString stringWithFormat:@"Cần: %@", etb ?: @"—"];

    // Fill tiemNang fields
    NSDictionary *tn = c[@"tiemNang"] ?: @{};
    for (NSString *k in kTNKeys()) {
        NSNumber *val = tn[k];
        _tnOrig[k] = val ?: @0;
        SLTextField *tf = _tnFields[k];
        tf.text = val ? val.stringValue : @"0";
    }

    [_itemTable reloadData];
}

- (void)hideLoading {
    [UIView animateWithDuration:0.4 animations:^{
        self.loadingView.alpha = 0;
    } completion:^(BOOL _) {
        [self.loadingView removeFromSuperview];
    }];
}

// ─────────────────────────────────────────────
// MARK: UITableView (Item List)
// ─────────────────────────────────────────────
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.filteredItems.count;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.text  = self.filteredItems[ip.row];
    cell.textLabel.textColor = SL_TEXT;
    cell.textLabel.font  = [UIFont fontWithName:@"Courier" size:11];
    cell.selectedBackgroundView = ({
        UIView *sv = [[UIView alloc] init];
        sv.backgroundColor = [SL_BLUE colorWithAlphaComponent:0.15];
        sv;
    });
    return cell;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {}

- (void)itemSearchChanged:(UITextField *)tf {
    NSString *q = tf.text.lowercaseString;
    if (!q.length) {
        self.filteredItems = self.allItems;
    } else {
        self.filteredItems = [self.allItems filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(NSString *s, id _) {
                return [s.lowercaseString containsString:q];
            }]];
    }
    [_itemTable reloadData];
}

// ─────────────────────────────────────────────
// MARK: UITextFieldDelegate
// ─────────────────────────────────────────────
- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    return YES;
}

// ─────────────────────────────────────────────
// MARK: Action Methods
// ─────────────────────────────────────────────
- (void)doAddEXP {
    if (!gCharId) { [TMDSystemNotif show:@"Chưa chọn nhân vật!"]; return; }
    NSInteger exp = [_expField.text integerValue] ?: 1000000000;
    NSString *path = [NSString stringWithFormat:@"/v1/servers/%@/characters/%@/cultivation/add-exp", kServer, gCharId];
    [TMDApi gamePost:path
                body:@{ @"expDelta": @(exp), @"source": @"offline_cultivation" }
          completion:^(NSInteger code, NSDictionary *json) {
        if (code == 200) {
            [TMDSystemNotif showTitle:@"[ THÀNH CÔNG ]" msg:[NSString stringWithFormat:@"Đã thêm %@ Linh Khí!", @(exp).stringValue]];
        } else {
            [TMDSystemNotif showTitle:@"[ THẤT BẠI ]" msg:[NSString stringWithFormat:@"HTTP %ld — %@", (long)code, json.description]];
        }
    }];
}

- (void)doGrantSelected {
    if (!gCharId) { [TMDSystemNotif show:@"Chưa chọn nhân vật!"]; return; }
    NSIndexPath *ip = _itemTable.indexPathForSelectedRow;
    if (!ip) { [TMDSystemNotif show:@"Hãy chọn một vật phẩm trong danh sách."]; return; }
    NSString *itemId = self.filteredItems[ip.row];
    [self grantItem:itemId];
}

- (void)doGrantManual {
    if (!gCharId) { [TMDSystemNotif show:@"Chưa chọn nhân vật!"]; return; }
    NSString *itemId = [_manualItemField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!itemId.length) { [TMDSystemNotif show:@"Nhập ClientRef hoặc ItemID trước."]; return; }
    [self grantItem:itemId];
}

- (void)grantItem:(NSString *)itemId {
    NSInteger count = [_itemCountField.text integerValue] ?: 10000;
    NSString *path = [NSString stringWithFormat:@"/v1/servers/%@/characters/%@/inventory/grant-or-stack", kServer, gCharId];
    [TMDApi gamePost:path
                body:@{ @"clientRefName": itemId, @"count": @(count), @"expiryDays": [NSNull null], @"isLocked": @NO }
          completion:^(NSInteger code, NSDictionary *json) {
        if (code == 200) {
            [TMDSystemNotif showTitle:@"[ TẶNG THÀNH CÔNG ]"
                                  msg:[NSString stringWithFormat:@"%@ × %@\nĐã thêm vào kho đồ.", @(count).stringValue, itemId]];
        } else {
            [TMDSystemNotif showTitle:@"[ THẤT BẠI ]"
                                  msg:[NSString stringWithFormat:@"HTTP %ld — Kiểm tra lại itemId.\n%@", (long)code, json[@"error"] ?: @""]];
        }
    }];
}

- (void)doManualBreakthrough {
    if (!gCharId) { [TMDSystemNotif show:@"Chưa chọn nhân vật!"]; return; }
    UIButton *btn   = (UIButton *)[_tabBreak viewWithTag:801];
    UITextView *log = (UITextView *)[_tabBreak viewWithTag:802];
    btn.enabled     = NO;
    log.text        = @"";

    [self performBreakthroughWithCharId:gCharId
                             pillRefs:@[]
                            maxTries:30
                               logTV:log
                          completion:^(BOOL ok, NSInteger attempts) {
        btn.enabled = YES;
        NSString *msg = ok
            ? [NSString stringWithFormat:@"⚡ Đột Phá thành công sau %ld lần thử!", (long)attempts]
            : [NSString stringWithFormat:@"Đột Phá thất bại sau %ld lần thử.", (long)attempts];
        [TMDSystemNotif showTitle:ok ? @"[ ĐỘT PHÁ THÀNH CÔNG ]" : @"[ ĐỘT PHÁ THẤT BẠI ]" msg:msg];
    }];
}

// Recursive breakthrough with pill auto-grant
- (void)performBreakthroughWithCharId:(NSString *)charId
                             pillRefs:(NSArray *)pillRefs
                            maxTries:(NSInteger)maxTries
                               logTV:(UITextView *)log
                          completion:(void(^)(BOOL, NSInteger))cb {
    __block NSInteger attempt = 0;
    __block NSString *lastGranted = nil;
    __block NSMutableArray *pills = [pillRefs mutableCopy];
    __block BOOL finished = NO;

    __block void (^tryOnce)(void);
    tryOnce = ^{
        if (finished || attempt >= maxTries) {
            if (!finished) { finished = YES; cb(NO, attempt); }
            return;
        }
        attempt++;
        NSString *path = [NSString stringWithFormat:@"/v1/servers/%@/characters/%@/cultivation/breakthrough", kServer, charId];
        [TMDApi gamePost:path body:@{ @"selectedPillRefs": pills }
              completion:^(NSInteger code, NSDictionary *json) {
            if (code == 200 && [json[@"success"] boolValue]) {
                finished = YES;
                [self appendLog:log line:[NSString stringWithFormat:@"✓ Thành công lần #%ld", (long)attempt] color:SL_GREEN];
                cb(YES, attempt);
                return;
            }
            NSString *err = [json[@"error"] isKindOfClass:[NSString class]] ? json[@"error"] : @"";
            NSRange r = [err rangeOfString:@"MISSING_REQUIRED_MATERIAL_IN_FURNACE:"];
            if (r.location != NSNotFound) {
                NSString *after = [err substringFromIndex:r.location + r.length];
                NSString *needed = [[after componentsSeparatedByCharactersInSet:
                    [NSCharacterSet characterSetWithCharactersInString:@" ,\"\n"]] firstObject];
                if (needed.length) {
                    NSString *grantPath = [NSString stringWithFormat:@"/v1/servers/%@/characters/%@/inventory/grant-or-stack", kServer, charId];
                    [TMDApi gamePost:grantPath body:@{@"clientRefName":needed,@"count":@10,@"expiryDays":[NSNull null],@"isLocked":@NO}
                          completion:^(NSInteger gc, NSDictionary *_) {
                        lastGranted = needed;
                        pills = [[NSArray arrayWithObjects:needed, needed, needed, needed, needed,
                                  needed, needed, needed, needed, needed, nil] mutableCopy];
                        [self appendLog:log line:[NSString stringWithFormat:@"→ Thiếu %@ — đã cấp 10 (HTTP %ld)", needed, (long)gc] color:SL_BLUE];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
                        tryOnce();
#pragma clang diagnostic pop
                    }];
                    return;
                }
            }
            if ([json[@"success"] boolValue] == NO && [err isEqualToString:@"FAILED_RNG"]) {
                [self appendLog:log line:[NSString stringWithFormat:@"→ Lần #%ld: FAILED_RNG — thử lại", (long)attempt] color:SL_ORANGE];
                if (lastGranted) {
                    NSString *grantPath = [NSString stringWithFormat:@"/v1/servers/%@/characters/%@/inventory/grant-or-stack", kServer, charId];
                    [TMDApi gamePost:grantPath body:@{@"clientRefName":lastGranted,@"count":@10,@"expiryDays":[NSNull null],@"isLocked":@NO}
                          completion:^(NSInteger _, NSDictionary *__) { tryOnce(); }];
                } else { tryOnce(); }
                return;
            }
            [self appendLog:log line:[NSString stringWithFormat:@"✗ HTTP %ld: %@", (long)code, err] color:SL_RED];
            finished = YES;
            cb(NO, attempt);
        }];
    };
    tryOnce();
}

- (void)doAllocatePotential {
    if (!gCharId) { [TMDSystemNotif show:@"Chưa chọn nhân vật!"]; return; }
    NSMutableDictionary *newStats = [NSMutableDictionary dictionary];
    NSInteger totalDelta = 0;
    for (NSString *k in kTNKeys()) {
        SLTextField *tf = _tnFields[k];
        NSInteger newV = tf.text.integerValue;
        NSInteger oldV = [_tnOrig[k] integerValue];
        newStats[k] = @(newV);
        if (newV > oldV) totalDelta += (newV - oldV);
    }
    if (totalDelta > 0) {
        NSString *incPath = [NSString stringWithFormat:@"/v1/servers/%@/characters/%@/increment-field", kServer, gCharId];
        [TMDApi gamePost:incPath body:@{@"fieldPath":@"tiemNang.diemCong", @"delta":@(totalDelta)}
              completion:^(NSInteger code, NSDictionary *json) {
            if (code != 200) {
                [TMDSystemNotif showTitle:@"[ THẤT BẠI ]" msg:@"Bước 1: Thêm Điểm Cộng thất bại."];
                return;
            }
            [self sendAllocate:newStats];
        }];
    } else {
        [self sendAllocate:newStats];
    }
}

- (void)sendAllocate:(NSDictionary *)stats {
    NSString *path = [NSString stringWithFormat:@"/v1/servers/%@/characters/%@/allocate-potential", kServer, gCharId];
    [TMDApi gamePost:path body:stats completion:^(NSInteger code, NSDictionary *json) {
        if (code == 200) {
            for (NSString *k in kTNKeys()) { _tnOrig[k] = stats[k]; }
            [TMDSystemNotif showTitle:@"[ THÀNH CÔNG ]" msg:@"✧ Phân bổ Tiềm Năng thành công!"];
        } else {
            [TMDSystemNotif showTitle:@"[ THẤT BẠI ]"
                                  msg:[NSString stringWithFormat:@"Phân bổ thất bại. HTTP %ld", (long)code]];
        }
    }];
}

// ─────────────────────────────────────────────
// MARK: Auto Run
// ─────────────────────────────────────────────
- (void)startAutoRun {
    if (!gCharId) { [TMDSystemNotif show:@"Chưa chọn nhân vật!"]; return; }
    _autoRunning = YES;
    _autoStop    = NO;
    _autoLoops = _autoSuccess = _autoFail = 0;
    _autoStartBtn.enabled = NO;
    _autoStopBtn.enabled  = YES;
    _autoLogView.text = @"";
    [self autoUpdateDot:@"running"];
    [self appendLog:_autoLogView line:@"═══ BẮT ĐẦU TỰ ĐỘNG TU LUYỆN ═══" color:SL_ORANGE];
    [self autoLoop];
}

- (void)stopAutoRun {
    _autoStop = YES;
    [self appendLog:_autoLogView line:@"⏹ Yêu cầu dừng..." color:SL_MUTED];
}

- (void)autoLoop {
    if (_autoStop || !_autoRunning) {
        [self finishAuto:@"Đã dừng theo yêu cầu" success:NO];
        return;
    }
    _autoLoops++;
    [self updateAutoCounters];
    [self appendLog:_autoLogView line:[NSString stringWithFormat:@"\n[Vòng #%ld] Lấy thông tin nhân vật...", (long)_autoLoops] color:SL_BLUE];

    NSString *charPath = [NSString stringWithFormat:@"/v1/servers/%@/characters/%@", kServer, gCharId];
    [TMDApi gamePost:charPath body:nil completion:^(NSInteger code, NSDictionary *json) {
        if (code != 200) {
            self.autoFail++; [self updateAutoCounters];
            [self appendLog:self.autoLogView line:[NSString stringWithFormat:@"✗ Lấy char thất bại (HTTP %ld)", (long)code] color:SL_RED];
            [self finishAuto:@"Lỗi lấy thông tin nhân vật" success:NO];
            return;
        }
        NSDictionary *cult = json[@"cultivation"] ?: @{};
        NSInteger expToBreak = [cult[@"expToBreak"] integerValue];
        NSString *realm = cult[@"realm"] ?: @"—";
        NSNumber *stage = cult[@"stage"] ?: @1;

        [self appendLog:self.autoLogView
                   line:[NSString stringWithFormat:@"✦ %@ Tầng %@ | EXP cần: %@", realm, stage, @(expToBreak)]
                  color:SL_BLUE];
        self.autoStatusLbl.text = [NSString stringWithFormat:@"Vòng #%ld — %@ Tầng %@", (long)self.autoLoops, realm, stage];

        if (self.autoStop) { [self finishAuto:@"Đã dừng" success:NO]; return; }

        NSInteger addExp = expToBreak > 0 ? expToBreak + 1 : 1000000000;
        [self appendLog:self.autoLogView line:[NSString stringWithFormat:@"→ Thêm %@ Linh Khí...", @(addExp)] color:SL_ORANGE];

        NSString *expPath = [NSString stringWithFormat:@"/v1/servers/%@/characters/%@/cultivation/add-exp", kServer, gCharId];
        [TMDApi gamePost:expPath body:@{@"expDelta":@(addExp), @"source":@"offline_cultivation"}
              completion:^(NSInteger ec, NSDictionary *_) {
            if (ec != 200) {
                self.autoFail++; [self updateAutoCounters];
                [self appendLog:self.autoLogView line:[NSString stringWithFormat:@"✗ Thêm EXP thất bại (HTTP %ld)", (long)ec] color:SL_RED];
                [self finishAuto:@"Lỗi thêm EXP" success:NO];
                return;
            }
            [self appendLog:self.autoLogView line:@"✓ Đã thêm EXP" color:SL_GREEN];
            if (self.autoStop) { [self finishAuto:@"Đã dừng" success:NO]; return; }

            // Breakthrough
            [self appendLog:self.autoLogView line:@"→ Đang đột phá..." color:SL_ORANGE];
            [self performBreakthroughWithCharId:gCharId
                                      pillRefs:@[]
                                     maxTries:30
                                        logTV:self.autoLogView
                                   completion:^(BOOL ok, NSInteger attempts) {
                if (ok) {
                    self.autoSuccess++; [self updateAutoCounters];
                    [self appendLog:self.autoLogView
                               line:[NSString stringWithFormat:@"✓ Đột Phá THÀNH CÔNG (lần #%ld) → %@ Tầng %@", (long)attempts, realm, stage]
                              color:SL_GREEN];
                    if (expToBreak <= 0) {
                        [self finishAuto:@"Đạt cảnh giới tối đa!" success:YES];
                    } else {
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            [self autoLoop];
                        });
                    }
                } else {
                    self.autoFail++; [self updateAutoCounters];
                    [self appendLog:self.autoLogView line:@"✗ Đột phá thất bại — dừng tự động" color:SL_RED];
                    [self finishAuto:@"Đột phá thất bại" success:NO];
                }
            }];
        }];
    }];
}

- (void)finishAuto:(NSString *)reason success:(BOOL)ok {
    _autoRunning = NO;
    _autoStop    = NO;
    _autoStartBtn.enabled = YES;
    _autoStopBtn.enabled  = NO;
    [self autoUpdateDot:ok ? @"done" : @"stopped"];
    _autoStatusLbl.text = reason;
    [self appendLog:_autoLogView line:[NSString stringWithFormat:@"═══ KẾT THÚC: %@ ═══", reason] color:ok ? SL_GREEN : SL_MUTED];
    [TMDSystemNotif showTitle:ok ? @"[ HOÀN THÀNH ]" : @"[ DỪNG ]" msg:reason];
}

- (void)autoUpdateDot:(NSString *)state {
    UIColor *c = SL_MUTED;
    if ([state isEqualToString:@"running"]) c = SL_ORANGE;
    else if ([state isEqualToString:@"done"])    c = SL_GREEN;
    else if ([state isEqualToString:@"stopped"]) c = SL_RED;
    _autoStatusDot.backgroundColor = c;
}

- (void)updateAutoCounters {
    _autoLoopLbl.text    = @(_autoLoops).stringValue;
    _autoSuccessLbl.text = @(_autoSuccess).stringValue;
    _autoFailLbl.text    = @(_autoFail).stringValue;
}

// ─────────────────────────────────────────────
// MARK: Close
// ─────────────────────────────────────────────
- (void)closeSelf {
    if (_autoRunning) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Auto Đang Chạy"
                                                                    message:@"Dừng Auto Run và đóng bảng điều khiển?"
                                                             preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"Đóng & Dừng" style:UIAlertActionStyleDestructive handler:^(id _) {
            self.autoStop = YES; self.autoRunning = NO;
            [self dismissWithAnimation];
        }]];
        [ac addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }
    [self dismissWithAnimation];
}

- (void)dismissWithAnimation {
    CGFloat sh = UIScreen.mainScreen.bounds.size.height;
    [UIView animateWithDuration:0.35 animations:^{
        self.container.frame = CGRectMake(0, sh, self.container.bounds.size.width, self.container.bounds.size.height);
        self.view.alpha = 0;
    } completion:^(BOOL _) {
        [self dismissViewControllerAnimated:NO completion:nil];
    }];
}

@end

// ═══════════════════════════════════════════════════════════════
// MARK: — Floating Menu Button
// ═══════════════════════════════════════════════════════════════
@interface TMDMenuButton : UIView
@property (nonatomic, strong) UIButton *innerBtn;
@property (nonatomic) CGPoint panStart;
@property (nonatomic) BOOL wasDragging;
@end

@implementation TMDMenuButton

- (instancetype)init {
    CGFloat w = 90, h = 40;
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    self = [super initWithFrame:CGRectMake(sw - w - 12, 140, w, h)];
    if (!self) return nil;

    self.backgroundColor = SLC(4, 8, 25, 0.95);
    self.layer.cornerRadius = 20;
    self.layer.borderColor  = [SL_BLUE colorWithAlphaComponent:0.9].CGColor;
    self.layer.borderWidth  = 1.5;
    self.layer.shadowColor  = SL_BLUE.CGColor;
    self.layer.shadowRadius = 12;
    self.layer.shadowOpacity = 1.0;
    self.layer.shadowOffset  = CGSizeZero;
    self.clipsToBounds = NO;

    _innerBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _innerBtn.frame = CGRectMake(0, 0, w, h);
    [_innerBtn setTitle:@"⚔ MENU" forState:UIControlStateNormal];
    [_innerBtn setTitleColor:SL_BLUE forState:UIControlStateNormal];
    _innerBtn.titleLabel.font = SLMono(13);
    [_innerBtn addTarget:self action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_innerBtn];

    // Drag gesture
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];

    // Pulse animation
    [UIView animateWithDuration:2.0 delay:0
                        options:UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse
                     animations:^{
        self.layer.shadowOpacity = 0.3;
    } completion:nil];

    return self;
}

- (void)menuTapped {
    if (_wasDragging) return;
    UIImpactFeedbackGenerator *fg = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [fg impactOccurred];

    // Find the game's main window rootViewController (skip our overlay)
    UIViewController *root = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *win in scene.windows) {
            if (win == gOverlay) continue;
            if (win.rootViewController) { root = win.rootViewController; break; }
        }
        if (root) break;
    }
    if (!root) return;
    while (root.presentedViewController) root = root.presentedViewController;

    TMDPanelVC *panel = [[TMDPanelVC alloc] init];
    panel.modalPresentationStyle = UIModalPresentationOverFullScreen;
    panel.modalTransitionStyle   = UIModalTransitionStyleCrossDissolve;
    [root presentViewController:panel animated:NO completion:nil];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateBegan) {
        _panStart = self.frame.origin;
        _wasDragging = NO;
    }
    CGPoint t = [pan translationInView:self.superview];
    if (ABS(t.x) > 4 || ABS(t.y) > 4) _wasDragging = YES;

    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    CGFloat sh = UIScreen.mainScreen.bounds.size.height;
    CGFloat nx = CLAMP_F(_panStart.x + t.x, 0, sw - self.bounds.size.width);
    CGFloat ny = CLAMP_F(_panStart.y + t.y, 60, sh - self.bounds.size.height - 80);
    self.frame = CGRectMake(nx, ny, self.bounds.size.width, self.bounds.size.height);

    if (pan.state == UIGestureRecognizerStateEnded) {
        // Snap to nearest edge
        CGFloat midX = nx + self.bounds.size.width / 2;
        CGFloat snapX = (midX < sw/2) ? 12 : (sw - self.bounds.size.width - 12);
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5
                            options:0 animations:^{
            self.frame = CGRectMake(snapX, ny, self.bounds.size.width, self.bounds.size.height);
        } completion:nil];
    }
}

static inline CGFloat CLAMP_F(CGFloat v, CGFloat lo, CGFloat hi) { return MAX(lo, MIN(hi, v)); }
@end

// ═══════════════════════════════════════════════════════════════
// MARK: —  URL Protocol (fires EVERY launch, not just first)
// ═══════════════════════════════════════════════════════════════
@interface TMDHookProtocol : NSURLProtocol
@end

@implementation TMDHookProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSURL *url = request.URL;
    if (!url) return NO;
    if (![url.host isEqualToString:kTargetHost]) return NO;
    if ([NSURLProtocol propertyForKey:@"TMDHandled" inRequest:request]) return NO;

    NSString *path = url.path.lowercaseString;
    return ([path isEqualToString:@"/v1/auth/bootstrap"] ||
            [path isEqualToString:@"/v1/auth/ban-status"]);
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }

- (void)startLoading {
    NSMutableURLRequest *req = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"TMDHandled" inRequest:req];

    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { [self.client URLProtocol:self didFailWithError:error]; return; }

        NSData *finalData = data;
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;

        if (data) {
            NSError *je = nil;
            NSMutableDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                       options:NSJSONReadingMutableContainers
                                                                         error:&je];
            if (json && !je) {
                NSString *uid = json[@"uid"] ?: @"Unknown";

                if ([json[@"isBanned"] boolValue]) {
                    NSLog(@"[TMD Hook]  detected → Removing | UID: %@", uid);
                    json[@"isBanned"] = @NO;
                    json[@"banReason"] = @"";
                }

                // ── Show Solo Leveling "System" notification EVERY TIME ──
                dispatch_async(dispatch_get_main_queue(), ^{
                    [TMDSystemNotif showTitle:@"[ HỆ THỐNG KÍCH HOẠT ]"
                                         msg:[NSString stringWithFormat:
                                              @"Chào mừng tu sĩ trở lại.\nUID: %@\nBạn Đã Kích Hoạt Hệ Thống.", uid]];
                });

                NSError *we = nil;
                NSData *mod = [NSJSONSerialization dataWithJSONObject:json options:0 error:&we];
                if (!we && mod) finalData = mod;
            }
        }

        [self.client URLProtocol:self didReceiveResponse:httpResp cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        if (finalData) [self.client URLProtocol:self didLoadData:finalData];
        [self.client URLProtocolDidFinishLoading:self];
    }] resume];
}

- (void)stopLoading {}

@end

// ═══════════════════════════════════════════════════════════════
// MARK: — Overlay Window (hosts the floating button)
// ═══════════════════════════════════════════════════════════════
@interface TMDOverlayWindow : UIWindow
@end
@implementation TMDOverlayWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *sub in self.subviews) {
        if (!sub.hidden && sub.userInteractionEnabled &&
            [sub pointInside:[self convertPoint:point toView:sub] withEvent:event]) {
            return YES;
        }
    }
    return NO;
}
@end

// ═══════════════════════════════════════════════════════════════
// MARK: — Logos Hooks
// ═══════════════════════════════════════════════════════════════
static void registerProtocol(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ [NSURLProtocol registerClass:[TMDHookProtocol class]]; });
}

%hook NSURLSessionConfiguration

- (NSArray *)protocolClasses {
    NSMutableArray *arr = [NSMutableArray arrayWithObject:[TMDHookProtocol class]];
    NSArray *orig = %orig;
    if (orig) [arr addObjectsFromArray:orig];
    return arr;
}

%end

%hook NSURLSession

+ (NSURLSession *)sharedSession {
    registerProtocol();
    return %orig;
}

%end

static void spawnMenuButton(void) {
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
    }
    if (!scene) return;

    gOverlay = [[TMDOverlayWindow alloc] initWithWindowScene:scene];
    gOverlay.windowLevel = UIWindowLevelAlert + 100;
    gOverlay.backgroundColor = [UIColor clearColor];
    gOverlay.userInteractionEnabled = YES;

    // rootViewController required for touch delivery on iOS 13+
    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view.backgroundColor = [UIColor clearColor];
    rootVC.view.userInteractionEnabled = NO;
    gOverlay.rootViewController = rootVC;
    gOverlay.hidden = NO;

    TMDMenuButton *btn = [[TMDMenuButton alloc] init];
    [gOverlay addSubview:btn];
}

// ─────────────────────────────────────────────
%ctor {
    registerProtocol();
    NSLog(@"[TMD Dev Client] ✅ Loaded —  + System UI");

    // UIApplicationDidBecomeActiveNotification fires reliably every time the app
    // becomes active; we use dispatch_once so the button is only created once.
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *__unused n) {
        static dispatch_once_t menuOnce;
        dispatch_once(&menuOnce, ^{
            // Short delay so UIWindowScene is fully initialised
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                spawnMenuButton();
            });
        });
    }];
}
