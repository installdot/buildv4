// Tweak.xm - Unitoreios Offline Cache Session Tester
// Fix: dùng ObjC runtime, không forward-declare Unitoreios class

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ─── Runtime helpers (tránh linker tìm _OBJC_CLASS_$_Unitoreios) ──
static Class UnitoreiosClass(void) {
    return objc_getClass("Unitoreios");
}

static NSInteger getRemainingSecondsFromInstance(id inst) {
    if (!inst) return 0;
    Ivar ivar = class_getInstanceVariable(object_getClass(inst), "remainingSeconds");
    if (!ivar) {
        // Thử tên private _remainingSeconds
        ivar = class_getInstanceVariable(object_getClass(inst), "_remainingSeconds");
    }
    if (!ivar) return 0;
    // NSInteger là primitive, dùng ivar_getOffset
    NSInteger *ptr = (NSInteger *)((uint8_t *)(__bridge void *)inst + ivar_getOffset(ivar));
    return *ptr;
}

static void setRemainingSecondsOnInstance(id inst, NSInteger val) {
    if (!inst) return;
    Ivar ivar = class_getInstanceVariable(object_getClass(inst), "remainingSeconds");
    if (!ivar) ivar = class_getInstanceVariable(object_getClass(inst), "_remainingSeconds");
    if (!ivar) return;
    NSInteger *ptr = (NSInteger *)((uint8_t *)(__bridge void *)inst + ivar_getOffset(ivar));
    *ptr = val;
}

static NSString *callClassStringMethod(NSString *selName) {
    Class cls = UnitoreiosClass();
    if (!cls) return @"(class not found)";
    SEL sel = NSSelectorFromString(selName);
    if (![cls respondsToSelector:sel]) return @"(method not found)";
    return ((NSString *(*)(id, SEL))objc_msgSend)(cls, sel);
}

// ─── Key để lưu singleton instance ───────────────────────────────
static const void *kExtraInfoKey = &kExtraInfoKey;

static id getExtraInfoInstance(void) {
    return objc_getAssociatedObject(UnitoreiosClass(), kExtraInfoKey);
}

static void setExtraInfoInstance(id inst) {
    objc_setAssociatedObject(UnitoreiosClass(), kExtraInfoKey,
                             inst, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// ─── Debug Menu ───────────────────────────────────────────────────
@interface UnitoreiosDebugMenu : NSObject
+ (instancetype)sharedMenu;
- (void)toggle;
@end

@implementation UnitoreiosDebugMenu {
    UIWindow    *_menuWindow;
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

- (void)refreshStatus {
    id inst        = getExtraInfoInstance();
    NSInteger raw  = getRemainingSecondsFromInstance(inst);
    NSString *key  = callClassStringMethod(@"getCurrentKey");
    NSString *time = callClassStringMethod(@"getRemainingTime");

    _statusLabel.text = [NSString stringWithFormat:
        @"🔑 Key: %@\n⏱ Còn lại: %@\n📦 Raw seconds: %ld\n%@",
        key ?: @"(none)",
        time ?: @"(none)",
        (long)raw,
        inst ? @"✅ Instance found" : @"⚠️ Instance chưa được cache (cần mở app trước)"];
}

- (void)buildWindowIfNeeded {
    if (_menuWindow) return;

    CGRect  screen = [UIScreen mainScreen].bounds;
    CGFloat pw = 310, ph = 320;

    _menuWindow = [[UIWindow alloc] initWithFrame:screen];
    _menuWindow.windowLevel       = UIWindowLevelAlert + 100;
    _menuWindow.backgroundColor   = [UIColor clearColor];
    _menuWindow.userInteractionEnabled = YES;

    // Tap ngoài để đóng
    UIControl *bg = [[UIControl alloc] initWithFrame:screen];
    bg.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    [bg addTarget:self action:@selector(hide)
 forControlEvents:UIControlEventTouchUpInside];
    [_menuWindow addSubview:bg];

    _panel = [[UIView alloc] initWithFrame:CGRectMake(
        (screen.size.width  - pw) / 2,
        (screen.size.height - ph) / 2,
        pw, ph)];
    _panel.backgroundColor    = [UIColor colorWithWhite:0.10 alpha:0.97];
    _panel.layer.cornerRadius  = 20;
    _panel.layer.borderWidth   = 1;
    _panel.layer.borderColor   = [UIColor colorWithRed:0.10 green:0.78
                                                  blue:0.55 alpha:0.5].CGColor;
    _panel.userInteractionEnabled = YES;
    [_menuWindow addSubview:_panel];

    // Title
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 14, pw, 26)];
    title.text          = @"🛠 Cache Session Debug";
    title.textAlignment = NSTextAlignmentCenter;
    title.font          = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    title.textColor     = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1];
    [_panel addSubview:title];

    // Divider
    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(14, 44, pw-28, 0.5)];
    div.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.6];
    [_panel addSubview:div];

    // Status box
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 52, pw-28, 100)];
    _statusLabel.numberOfLines    = 5;
    _statusLabel.font             = [UIFont monospacedSystemFontOfSize:11
                                                               weight:UIFontWeightRegular];
    _statusLabel.textColor        = [UIColor colorWithWhite:0.85 alpha:1];
    _statusLabel.backgroundColor  = [UIColor colorWithWhite:0.06 alpha:0.8];
    _statusLabel.layer.cornerRadius = 8;
    _statusLabel.clipsToBounds    = YES;
    // padding bằng inset trick
    _statusLabel.text = @"";
    [_panel addSubview:_statusLabel];

    // Hint
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(14, 160, pw-28, 16)];
    hint.text      = @"Nhập số giây muốn set (86400 = 1 ngày)";
    hint.font      = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    hint.textColor = [UIColor colorWithWhite:0.50 alpha:1];
    [_panel addSubview:hint];

    // Input
    _inputField = [[UITextField alloc] initWithFrame:CGRectMake(14, 180, pw-28, 42)];
    _inputField.placeholder         = @"vd: 86400";
    _inputField.keyboardType        = UIKeyboardTypeNumberPad;
    _inputField.textAlignment       = NSTextAlignmentCenter;
    _inputField.backgroundColor     = [UIColor colorWithWhite:1.0 alpha:0.96];
    _inputField.layer.cornerRadius  = 10;
    _inputField.layer.masksToBounds = YES;
    _inputField.font                = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _inputField.clearButtonMode     = UITextFieldViewModeWhileEditing;
    [_panel addSubview:_inputField];

    // Row buttons
    CGFloat bw = (pw - 42) / 2.0;
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    saveBtn.frame = CGRectMake(14, 232, bw, 44);
    saveBtn.backgroundColor     = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1];
    saveBtn.layer.cornerRadius  = 12;
    [saveBtn setTitle:@"💾 Lưu" forState:UIControlStateNormal];
    saveBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [saveBtn addTarget:self action:@selector(onSave)
      forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:saveBtn];

    UIButton *refreshBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    refreshBtn.frame = CGRectMake(14 + bw + 14, 232, bw, 44);
    refreshBtn.backgroundColor     = [UIColor colorWithRed:0.20 green:0.45 blue:0.85 alpha:1];
    refreshBtn.layer.cornerRadius  = 12;
    [refreshBtn setTitle:@"🔄 Refresh" forState:UIControlStateNormal];
    refreshBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [refreshBtn addTarget:self action:@selector(onRefresh)
         forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:refreshBtn];

    // Close
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(14, 284, pw-28, 28);
    [closeBtn setTitle:@"✕ Đóng" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [closeBtn setTitleColor:[UIColor colorWithWhite:0.40 alpha:1]
                  forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(hide)
       forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:closeBtn];
}

- (void)onSave {
    [_inputField resignFirstResponder];
    NSString *text = [_inputField.text
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length) return;
    NSInteger newSec = [text integerValue];
    if (newSec <= 0) { [self toast:@"⚠️ Giá trị phải > 0"]; return; }

    id inst = getExtraInfoInstance();
    if (!inst) { [self toast:@"⚠️ Chưa capture instance"]; return; }

    setRemainingSecondsOnInstance(inst, newSec);
    [self refreshStatus];
    [self toast:[NSString stringWithFormat:@"✅ Set %ld giây", (long)newSec]];
}

- (void)onRefresh { [self refreshStatus]; [self toast:@"🔄 Refreshed"]; }

- (void)toast:(NSString *)msg {
    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(20, 0, _panel.bounds.size.width - 40, 34)];
    t.center          = CGPointMake(_panel.bounds.size.width/2, _panel.bounds.size.height - 20);
    t.text            = msg;
    t.textAlignment   = NSTextAlignmentCenter;
    t.font            = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    t.textColor       = UIColor.whiteColor;
    t.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.95];
    t.layer.cornerRadius = 10;
    t.clipsToBounds   = YES;
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
    _panel.transform = CGAffineTransformMakeScale(0.85, 0.85);
    _panel.alpha = 0;
    [UIView animateWithDuration:0.28 delay:0
         usingSpringWithDamping:0.7 initialSpringVelocity:0.5
                        options:0 animations:^{
        self->_panel.transform = CGAffineTransformIdentity;
        self->_panel.alpha = 1;
    } completion:nil];
}

- (void)hide {
    [_inputField resignFirstResponder];
    [UIView animateWithDuration:0.2 animations:^{
        self->_panel.transform = CGAffineTransformMakeScale(0.88, 0.88);
        self->_panel.alpha = 0;
    } completion:^(BOOL f){
        self->_menuWindow.hidden = YES;
        self->_visible = NO;
    }];
}

- (void)toggle { _visible ? [self hide] : [self show]; }

@end

// ─── Floating drag button ─────────────────────────────────────────
static UIWindow *sFloatWin = nil;

static void installFloatButton(void) {
    CGRect screen = [UIScreen mainScreen].bounds;
    sFloatWin = [[UIWindow alloc] initWithFrame:CGRectMake(
        screen.size.width - 62, screen.size.height * 0.38, 50, 50)];
    sFloatWin.windowLevel          = UIWindowLevelAlert + 50;
    sFloatWin.backgroundColor      = [UIColor clearColor];
    sFloatWin.hidden               = NO;
    sFloatWin.userInteractionEnabled = YES;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, 50, 50);
    btn.tag   = 9981;
    [btn setTitle:@"🛠" forState:UIControlStateNormal];
    btn.backgroundColor    = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.90];
    btn.layer.cornerRadius = 25;
    btn.layer.shadowColor  = UIColor.blackColor.CGColor;
    btn.layer.shadowOpacity = 0.30;
    btn.layer.shadowRadius  = 6;
    btn.layer.shadowOffset  = CGSizeMake(0, 3);
    btn.titleLabel.font    = [UIFont systemFontOfSize:20];

    [btn addTarget:[UnitoreiosDebugMenu sharedMenu]
            action:@selector(toggle)
  forControlEvents:UIControlEventTouchUpInside];

    // Drag
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:btn action:@selector(handlePan:)];
    [btn addGestureRecognizer:pan];

    [sFloatWin addSubview:btn];
    [sFloatWin makeKeyAndVisible];
    sFloatWin.hidden = NO;
}

// Category trên UIButton để handle pan mà không cần class riêng
@interface UIButton (UnitoreiosPan)
- (void)handlePan:(UIPanGestureRecognizer *)pan;
@end
@implementation UIButton (UnitoreiosPan)
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (!sFloatWin) return;
    CGPoint delta = [pan translationInView:sFloatWin];
    CGRect  frame = sFloatWin.frame;
    frame.origin.x += delta.x;
    frame.origin.y += delta.y;
    CGRect screen  = [UIScreen mainScreen].bounds;
    frame.origin.x = MAX(0, MIN(frame.origin.x, screen.size.width  - frame.size.width));
    frame.origin.y = MAX(20, MIN(frame.origin.y, screen.size.height - frame.size.height - 20));
    sFloatWin.frame = frame;
    [pan setTranslation:CGPointZero inView:sFloatWin];
}
@end

// ─── Hook: bắt singleton extraInfo khi -canUseCachedSession được gọi ──
// Vì extraInfo là static local trong Unitoreios.mm, cách duy nhất không cần
// re-export symbol là hook một instance method để lấy `self`.
%hook NSObject

- (BOOL)canUseCachedSession {
    // Chỉ capture nếu đúng class Unitoreios
    if (object_getClass(self) == objc_getClass("Unitoreios")) {
        setExtraInfoInstance(self);
    }
    return %orig;
}

%end

// ─── Constructor ──────────────────────────────────────────────────
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        installFloatButton();
    });
}
