// Tweak.xm - Unitoreios Offline Cache Session Tester
// Debug tool - chủ sở hữu sử dụng

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@interface Unitoreios : NSObject
@property (nonatomic, assign) NSInteger remainingSeconds;
+ (NSString *)getRemainingTime;
+ (NSString *)getCurrentKey;
@end

// ─── Debug Menu ───────────────────────────────────────────────────
@interface UnitoreiosDebugMenu : NSObject
+ (instancetype)sharedMenu;
- (void)show;
- (void)hide;
- (void)toggle;
@end

@implementation UnitoreiosDebugMenu {
    UIWindow    *_menuWindow;
    UIView      *_overlay;
    UIView      *_panel;
    UILabel     *_statusLabel;
    UITextField *_inputField;
    BOOL         _visible;
}

+ (instancetype)sharedMenu {
    static UnitoreiosDebugMenu *s = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (Unitoreios *)extraInfoInstance {
    return objc_getAssociatedObject([Unitoreios class], "extraInfo_debug_ptr");
}

- (NSInteger)currentRemaining {
    Unitoreios *inst = [self extraInfoInstance];
    return inst ? inst.remainingSeconds : 0;
}

- (void)setRemaining:(NSInteger)seconds {
    Unitoreios *inst = [self extraInfoInstance];
    if (inst) inst.remainingSeconds = seconds;
}

- (void)refreshStatus {
    NSString *key     = [Unitoreios getCurrentKey]    ?: @"(chưa có)";
    NSString *timeStr = [Unitoreios getRemainingTime] ?: @"(chưa có)";
    NSInteger rawSec  = [self currentRemaining];
    _statusLabel.text = [NSString stringWithFormat:
        @"🔑 Key: %@\n⏱ Còn lại: %@\n📦 Raw seconds: %ld",
        key, timeStr, (long)rawSec];
}

- (void)buildWindowIfNeeded {
    if (_menuWindow) return;

    CGRect screen = [UIScreen mainScreen].bounds;

    // Overlay mờ phía sau
    _menuWindow = [[UIWindow alloc] initWithFrame:screen];
    _menuWindow.windowLevel = UIWindowLevelAlert + 100;
    _menuWindow.backgroundColor = [UIColor clearColor];

    _overlay = [[UIView alloc] initWithFrame:screen];
    _overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    UITapGestureRecognizer *tapDismiss = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(hide)];
    [_overlay addGestureRecognizer:tapDismiss];
    [_menuWindow addSubview:_overlay];

    // Panel
    CGFloat pw = 318, ph = 340;
    _panel = [[UIView alloc] initWithFrame:CGRectMake(
        (screen.size.width  - pw) / 2,
        (screen.size.height - ph) / 2,
        pw, ph)];
    _panel.backgroundColor    = [UIColor colorWithWhite:0.09 alpha:0.97];
    _panel.layer.cornerRadius = 22;
    _panel.layer.borderWidth  = 1;
    _panel.layer.borderColor  = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.5].CGColor;
    _panel.layer.shadowColor  = UIColor.blackColor.CGColor;
    _panel.layer.shadowOpacity = 0.4;
    _panel.layer.shadowRadius  = 20;
    _panel.layer.shadowOffset  = CGSizeMake(0, 8);
    // Chặn tap xuyên qua panel xuống overlay
    UITapGestureRecognizer *tapBlock = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(noop)];
    [_panel addGestureRecognizer:tapBlock];
    [_menuWindow addSubview:_panel];

    CGFloat y = 0;

    // ── Header bar ──────────────────────────────────────────────
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, pw, 48)];
    header.backgroundColor = [UIColor colorWithRed:0.08 green:0.68 blue:0.46 alpha:0.18];
    header.layer.cornerRadius = 22;
    // chỉ bo góc trên
    CAShapeLayer *headerMask = [CAShapeLayer layer];
    UIBezierPath *hp = [UIBezierPath bezierPathWithRoundedRect:header.bounds
        byRoundingCorners:UIRectCornerTopLeft|UIRectCornerTopRight
              cornerRadii:CGSizeMake(22,22)];
    headerMask.path = hp.CGPath;
    header.layer.mask = headerMask;
    [_panel addSubview:header];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, pw - 50, 48)];
    title.text          = @"🛠  Cache Session Debug";
    title.textAlignment = NSTextAlignmentCenter;
    title.font          = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    title.textColor     = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1];
    title.frame = CGRectMake(25, 0, pw - 50, 48);
    [header addSubview:title];

    // ── Nút X đóng góc trên phải ────────────────────────────────
    UIButton *xBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    xBtn.frame = CGRectMake(pw - 42, 8, 34, 34);
    [xBtn setTitle:@"✕" forState:UIControlStateNormal];
    xBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [xBtn setTitleColor:[UIColor colorWithWhite:0.55 alpha:1] forState:UIControlStateNormal];
    [xBtn setTitleColor:[UIColor colorWithWhite:0.85 alpha:1] forState:UIControlStateHighlighted];
    xBtn.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
    xBtn.layer.cornerRadius = 17;
    [xBtn addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:xBtn];

    y = 56;

    // ── Status box ──────────────────────────────────────────────
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, y, pw - 28, 88)];
    _statusLabel.numberOfLines  = 4;
    _statusLabel.font           = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _statusLabel.textColor      = [UIColor colorWithWhite:0.85 alpha:1];
    _statusLabel.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.85];
    _statusLabel.layer.cornerRadius = 10;
    _statusLabel.clipsToBounds  = YES;
    // padding dùng inset layer
    _statusLabel.layer.borderWidth = 0.5;
    _statusLabel.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1].CGColor;
    [_panel addSubview:_statusLabel];
    y += 96;

    // ── Hint ────────────────────────────────────────────────────
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(14, y, pw - 28, 16)];
    hint.text      = @"Nhập số giây muốn set  (86400 = 1 ngày)";
    hint.font      = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    hint.textColor = [UIColor colorWithWhite:0.50 alpha:1];
    [_panel addSubview:hint];
    y += 22;

    // ── Input ───────────────────────────────────────────────────
    _inputField = [[UITextField alloc] initWithFrame:CGRectMake(14, y, pw - 28, 42)];
    _inputField.placeholder         = @"Số giây  (vd: 86400)";
    _inputField.keyboardType        = UIKeyboardTypeNumberPad;
    _inputField.textAlignment       = NSTextAlignmentCenter;
    _inputField.backgroundColor     = UIColor.whiteColor;
    _inputField.layer.cornerRadius  = 11;
    _inputField.layer.masksToBounds = YES;
    _inputField.font                = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _inputField.clearButtonMode     = UITextFieldViewModeWhileEditing;
    _inputField.tintColor           = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1];
    [_panel addSubview:_inputField];
    y += 50;

    // ── Nút Save + Refresh ──────────────────────────────────────
    CGFloat bw = (pw - 42) / 2;

    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    saveBtn.frame = CGRectMake(14, y, bw, 44);
    saveBtn.backgroundColor   = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1];
    saveBtn.layer.cornerRadius = 12;
    [saveBtn setTitle:@"💾  Lưu" forState:UIControlStateNormal];
    saveBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [saveBtn addTarget:self action:@selector(onSave) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:saveBtn];

    UIButton *refreshBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    refreshBtn.frame = CGRectMake(14 + bw + 14, y, bw, 44);
    refreshBtn.backgroundColor   = [UIColor colorWithRed:0.22 green:0.42 blue:0.85 alpha:1];
    refreshBtn.layer.cornerRadius = 12;
    [refreshBtn setTitle:@"🔄  Refresh" forState:UIControlStateNormal];
    refreshBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [refreshBtn addTarget:self action:@selector(onRefresh) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:refreshBtn];
    y += 52;

    // ── Nút Hide (ẩn menu, float button vẫn còn) ────────────────
    UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    hideBtn.frame = CGRectMake(14, y, pw - 28, 36);
    hideBtn.backgroundColor   = [UIColor colorWithWhite:0.18 alpha:1];
    hideBtn.layer.cornerRadius = 12;
    [hideBtn setTitle:@"👁  Ẩn menu  (nút 🛠 vẫn còn)" forState:UIControlStateNormal];
    [hideBtn setTitleColor:[UIColor colorWithWhite:0.60 alpha:1] forState:UIControlStateNormal];
    hideBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [hideBtn addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:hideBtn];
}

- (void)noop {}

- (void)onSave {
    [_inputField resignFirstResponder];
    NSString *text = [_inputField.text stringByTrimmingCharactersInSet:
                      NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length) return;
    NSInteger newSec = [text integerValue];
    if (newSec <= 0) { [self toast:@"⚠️ Giá trị không hợp lệ"]; return; }
    [self setRemaining:newSec];
    [self refreshStatus];
    [self toast:[NSString stringWithFormat:@"✅ Đã set %ld giây", (long)newSec]];
}

- (void)onRefresh {
    [self refreshStatus];
    [self toast:@"🔄 Đã refresh"];
}

- (void)toast:(NSString *)msg {
    UILabel *t = [[UILabel alloc] initWithFrame:CGRectZero];
    t.text            = msg;
    t.textAlignment   = NSTextAlignmentCenter;
    t.font            = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    t.textColor       = UIColor.whiteColor;
    t.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.95];
    t.layer.cornerRadius = 10;
    t.clipsToBounds   = YES;
    [t sizeToFit];
    CGFloat tw = t.frame.size.width + 28;
    t.frame = CGRectMake((_panel.bounds.size.width - tw) / 2,
                         _panel.bounds.size.height - 48, tw, 32);
    t.alpha = 0;
    [_panel addSubview:t];
    [UIView animateWithDuration:0.2 animations:^{ t.alpha = 1; } completion:^(BOOL f){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.2 animations:^{ t.alpha = 0; }
                             completion:^(BOOL ff){ [t removeFromSuperview]; }];
        });
    }];
}

- (void)show {
    [self buildWindowIfNeeded];
    [self refreshStatus];
    _visible = YES;
    _menuWindow.hidden = NO;
    [_menuWindow makeKeyAndVisible];
    _panel.transform = CGAffineTransformMakeScale(0.88, 0.88);
    _panel.alpha = 0;
    _overlay.alpha = 0;
    [UIView animateWithDuration:0.28 delay:0
         usingSpringWithDamping:0.72 initialSpringVelocity:0.5
                        options:0 animations:^{
        self->_panel.transform = CGAffineTransformIdentity;
        self->_panel.alpha = 1;
        self->_overlay.alpha = 1;
    } completion:nil];
}

- (void)hide {
    [_inputField resignFirstResponder];
    [UIView animateWithDuration:0.2 animations:^{
        self->_panel.transform = CGAffineTransformMakeScale(0.88, 0.88);
        self->_panel.alpha = 0;
        self->_overlay.alpha = 0;
    } completion:^(BOOL f){
        self->_menuWindow.hidden = YES;
        self->_visible = NO;
    }];
}

- (void)toggle { _visible ? [self hide] : [self show]; }

@end

// ─── Floating Button ──────────────────────────────────────────────
@interface UnitoreiosFloatBtn : NSObject
+ (void)install;
@end

@implementation UnitoreiosFloatBtn

+ (void)install {
    CGRect screen = [UIScreen mainScreen].bounds;
    UIWindow *win  = [[UIWindow alloc] initWithFrame:
        CGRectMake(screen.size.width - 62, screen.size.height * 0.38, 50, 50)];
    win.windowLevel           = UIWindowLevelAlert + 50;
    win.backgroundColor       = UIColor.clearColor;
    win.hidden                = NO;
    win.userInteractionEnabled = YES;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, 50, 50);
    [btn setTitle:@"🛠" forState:UIControlStateNormal];
    btn.titleLabel.font      = [UIFont systemFontOfSize:22];
    btn.backgroundColor      = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.92];
    btn.layer.cornerRadius   = 25;
    btn.layer.shadowColor    = UIColor.blackColor.CGColor;
    btn.layer.shadowOpacity  = 0.35;
    btn.layer.shadowRadius   = 8;
    btn.layer.shadowOffset   = CGSizeMake(0, 4);

    [btn addTarget:self action:@selector(onTap)
          forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(onPan:)];
    [btn addGestureRecognizer:pan];
    [win addSubview:btn];

    objc_setAssociatedObject([UnitoreiosFloatBtn class], "fw", win,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [win makeKeyAndVisible];
    win.hidden = NO;
}

+ (void)onTap {
    [[UnitoreiosDebugMenu sharedMenu] toggle];
}

+ (void)onPan:(UIPanGestureRecognizer *)pan {
    UIWindow *win = objc_getAssociatedObject([UnitoreiosFloatBtn class], "fw");
    if (!win) return;
    CGPoint d = [pan translationInView:win];
    CGRect  f = win.frame;
    f.origin.x += d.x;
    f.origin.y += d.y;
    CGRect sc = [UIScreen mainScreen].bounds;
    f.origin.x = MAX(0, MIN(f.origin.x, sc.size.width  - f.size.width));
    f.origin.y = MAX(24, MIN(f.origin.y, sc.size.height - f.size.height - 24));
    win.frame = f;
    [pan setTranslation:CGPointZero inView:win];
}

@end

// ─── Hook: bắt singleton extraInfo ───────────────────────────────
%hook Unitoreios

- (BOOL)canUseCachedSession {
    objc_setAssociatedObject([Unitoreios class], "extraInfo_debug_ptr",
                             self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return %orig;
}

%end

// ─── Constructor - priority cao ───────────────────────────────────
// __attribute__((constructor(101))) = load rất sớm sau dyld
static void __attribute__((constructor(101))) UnitoreiosDebugInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [UnitoreiosFloatBtn install];
    });
}
