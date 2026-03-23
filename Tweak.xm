// Tweak.xm - Unitoreios Cache Session Debug
// Fix offline: dùng %hook Unitoreios (Logos tự dùng runtime, không cần linker)
//              + hook -init để capture instance ngay khi Unitoreios new

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ─── Instance storage ─────────────────────────────────────────────
static id sInst = nil; // extraInfo singleton

// ─── Ivar reader/writer ───────────────────────────────────────────
static Ivar findRemainingIvar(void) {
    if (!sInst) return NULL;
    Class cls = object_getClass(sInst);

    // Tên property tạo ra _remainingSeconds, + tên static trong file .mm
    const char *names[] = {
        "_remainingSeconds",
        "remainingSeconds",
        "_remainingSeconds1",
        "remainingSeconds1",
        NULL
    };
    for (int i = 0; names[i]; i++) {
        Ivar iv = class_getInstanceVariable(cls, names[i]);
        if (iv) return iv;
    }

    // Fallback: scan ivar NSInteger chứa "remaining" hoặc "second"
    unsigned int n = 0;
    Ivar *list = class_copyIvarList(cls, &n);
    Ivar found = NULL;
    for (unsigned int i = 0; i < n && !found; i++) {
        const char *enc = ivar_getTypeEncoding(list[i]);
        const char *nm  = ivar_getName(list[i]);
        if (!enc || !nm) continue;
        if (enc[0] != 'q' && enc[0] != 'i') continue;
        NSString *s = [[NSString stringWithUTF8String:nm] lowercaseString];
        if ([s containsString:@"remaining"] || [s containsString:@"second"])
            found = list[i];
    }
    if (list) free(list);
    return found;
}

static NSInteger getRaw(void) {
    if (!sInst) return -1;
    Ivar iv = findRemainingIvar();
    if (!iv) return -2;
    uint8_t *base = (uint8_t *)(__bridge void *)sInst;
    return *(NSInteger *)(base + ivar_getOffset(iv));
}

static void setRaw(NSInteger val) {
    if (!sInst) return;
    Ivar iv = findRemainingIvar();
    if (!iv) return;
    uint8_t *base = (uint8_t *)(__bridge void *)sInst;
    *(NSInteger *)(base + ivar_getOffset(iv)) = val;
}

// Class methods - dùng objc_msgSend để tránh linker dependency
static NSString *callCls(const char *sel) {
    Class cls = objc_getClass("Unitoreios");
    if (!cls) return @"class not found";
    SEL s = sel_registerName(sel);
    if (![cls respondsToSelector:s]) return @"method not found";
    return ((NSString *(*)(id,SEL))objc_msgSend)(cls, s);
}

// Dump tất cả NSInteger ivar để debug
static NSString *dumpIvars(void) {
    if (!sInst) return @"no instance";
    Class cls = object_getClass(sInst);
    unsigned int n = 0;
    Ivar *list = class_copyIvarList(cls, &n);
    NSMutableString *out = [NSMutableString string];
    for (unsigned int i = 0; i < n; i++) {
        const char *enc = ivar_getTypeEncoding(list[i]);
        const char *nm  = ivar_getName(list[i]);
        if (!enc || !nm) continue;
        if (enc[0] != 'q' && enc[0] != 'i') continue;
        uint8_t *base = (uint8_t *)(__bridge void *)sInst;
        NSInteger v = *(NSInteger *)(base + ivar_getOffset(list[i]));
        [out appendFormat:@"%s=%ld  ", nm, (long)v];
    }
    if (list) free(list);
    return out.length ? out : @"(none)";
}

// ─── Debug Menu ───────────────────────────────────────────────────
@interface UDMenu : NSObject
+ (instancetype)shared;
- (void)toggle;
@end

@implementation UDMenu {
    UIWindow    *_win;
    UIView      *_panel;
    UILabel     *_statusLabel;
    UILabel     *_ivarLabel;
    UITextField *_inputField;
    BOOL         _visible;
}

+ (instancetype)shared {
    static UDMenu *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (void)refreshStatus {
    NSString *key     = callCls("getCurrentKey");
    NSString *timeStr = callCls("getRemainingTime");
    NSInteger raw     = getRaw();

    NSString *instLine;
    if (!sInst) {
        instLine = @"❌ Instance: chưa capture";
    } else {
        Ivar iv = findRemainingIvar();
        instLine = [NSString stringWithFormat:@"✅ %s | ivar: %s",
            class_getName(object_getClass(sInst)),
            iv ? ivar_getName(iv) : "NOT FOUND"];
    }

    NSString *rawStr = (raw == -1) ? @"no instance"
                     : (raw == -2) ? @"ivar not found"
                     : [NSString stringWithFormat:@"%ld giây", (long)raw];

    _statusLabel.text = [NSString stringWithFormat:
        @"🔑 %@\n⏱ %@\n📦 raw: %@\n%@",
        key ?: @"(none)", timeStr ?: @"(none)", rawStr, instLine];

    _ivarLabel.text = [NSString stringWithFormat:@"ivars: %@", dumpIvars()];
}

- (void)buildIfNeeded {
    if (_win) return;
    CGRect sc = [UIScreen mainScreen].bounds;
    CGFloat pw = 310, ph = 400;

    _win = [[UIWindow alloc] initWithFrame:sc];
    _win.windowLevel = UIWindowLevelAlert + 100;
    _win.backgroundColor = [UIColor clearColor];

    UIControl *dim = [[UIControl alloc] initWithFrame:sc];
    dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    [dim addTarget:self action:@selector(hide)
  forControlEvents:UIControlEventTouchUpInside];
    [_win addSubview:dim];

    _panel = [[UIView alloc] initWithFrame:CGRectMake(
        (sc.size.width-pw)/2, (sc.size.height-ph)/2, pw, ph)];
    _panel.backgroundColor    = [UIColor colorWithWhite:0.10 alpha:0.97];
    _panel.layer.cornerRadius  = 20;
    _panel.layer.borderWidth   = 1;
    _panel.layer.borderColor   = [UIColor colorWithRed:.10 green:.78 blue:.55 alpha:.5].CGColor;
    _panel.userInteractionEnabled = YES;
    [_win addSubview:_panel];

    // Title
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0,14,pw,26)];
    title.text = @"🛠  Cache Session Debug";
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    title.textColor = [UIColor colorWithRed:.10 green:.78 blue:.55 alpha:1];
    [_panel addSubview:title];

    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(14,44,pw-28,.5)];
    div.backgroundColor = [UIColor colorWithWhite:.3 alpha:.6];
    [_panel addSubview:div];

    // Status box
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(14,52,pw-28,106)];
    _statusLabel.numberOfLines = 5;
    _statusLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _statusLabel.textColor = [UIColor colorWithWhite:.85 alpha:1];
    _statusLabel.backgroundColor = [UIColor colorWithWhite:.06 alpha:.9];
    _statusLabel.layer.cornerRadius = 8;
    _statusLabel.clipsToBounds = YES;
    [_panel addSubview:_statusLabel];

    // Ivar dump
    _ivarLabel = [[UILabel alloc] initWithFrame:CGRectMake(14,164,pw-28,48)];
    _ivarLabel.numberOfLines = 3;
    _ivarLabel.font = [UIFont monospacedSystemFontOfSize:9.5 weight:UIFontWeightRegular];
    _ivarLabel.textColor = [UIColor colorWithWhite:.55 alpha:1];
    _ivarLabel.backgroundColor = [UIColor colorWithWhite:.04 alpha:.8];
    _ivarLabel.layer.cornerRadius = 6;
    _ivarLabel.clipsToBounds = YES;
    [_panel addSubview:_ivarLabel];

    // Hint
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(14,220,pw-28,16)];
    hint.text = @"Nhập số giây muốn set  (86400 = 1 ngày)";
    hint.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    hint.textColor = [UIColor colorWithWhite:.50 alpha:1];
    [_panel addSubview:hint];

    // Input + ⌨️ nút ẩn keyboard
    CGFloat kbW = 44;
    CGFloat tfW = pw - 28 - kbW - 8;
    _inputField = [[UITextField alloc] initWithFrame:CGRectMake(14,240,tfW,42)];
    _inputField.placeholder = @"vd: 86400";
    _inputField.keyboardType = UIKeyboardTypeNumberPad;
    _inputField.textAlignment = NSTextAlignmentCenter;
    _inputField.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.96];
    _inputField.layer.cornerRadius = 10;
    _inputField.layer.masksToBounds = YES;
    _inputField.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _inputField.clearButtonMode = UITextFieldViewModeWhileEditing;
    [_panel addSubview:_inputField];

    UIButton *kbBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    kbBtn.frame = CGRectMake(14+tfW+8, 240, kbW, 42);
    kbBtn.backgroundColor = [UIColor colorWithWhite:.22 alpha:1];
    kbBtn.layer.cornerRadius = 10;
    [kbBtn setTitle:@"⌨️" forState:UIControlStateNormal];
    kbBtn.titleLabel.font = [UIFont systemFontOfSize:18];
    [kbBtn addTarget:self action:@selector(hideKB)
    forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:kbBtn];

    // Save + Refresh
    CGFloat bw = (pw-42)/2.0;

    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    saveBtn.frame = CGRectMake(14,296,bw,44);
    saveBtn.backgroundColor = [UIColor colorWithRed:.10 green:.78 blue:.55 alpha:1];
    saveBtn.layer.cornerRadius = 12;
    [saveBtn setTitle:@"💾  Lưu" forState:UIControlStateNormal];
    saveBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [saveBtn addTarget:self action:@selector(onSave)
      forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:saveBtn];

    UIButton *refBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    refBtn.frame = CGRectMake(14+bw+14,296,bw,44);
    refBtn.backgroundColor = [UIColor colorWithRed:.20 green:.45 blue:.85 alpha:1];
    refBtn.layer.cornerRadius = 12;
    [refBtn setTitle:@"🔄  Refresh" forState:UIControlStateNormal];
    refBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [refBtn addTarget:self action:@selector(onRefresh)
      forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:refBtn];

    // Close
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(14,350,pw-28,38);
    [closeBtn setTitle:@"✕  Đóng" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [closeBtn setTitleColor:[UIColor colorWithWhite:.40 alpha:1] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(hide)
      forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:closeBtn];
}

- (void)hideKB { [_inputField resignFirstResponder]; }

- (void)onSave {
    [self hideKB];
    NSString *t = [_inputField.text stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!t.length) { [self toast:@"⚠️ Chưa nhập"]; return; }
    NSInteger v = [t integerValue];
    if (v <= 0) { [self toast:@"⚠️ Phải > 0"]; return; }
    if (!sInst) { [self toast:@"⚠️ Chưa có instance"]; return; }
    setRaw(v);
    [self refreshStatus];
    [self toast:[NSString stringWithFormat:@"✅ Set %ld giây", (long)v]];
}

- (void)onRefresh { [self refreshStatus]; [self toast:@"🔄 Refreshed"]; }

- (void)toast:(NSString *)msg {
    UILabel *t = [[UILabel alloc] init];
    t.text = msg;
    t.textAlignment = NSTextAlignmentCenter;
    t.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    t.textColor = UIColor.whiteColor;
    t.backgroundColor = [UIColor colorWithWhite:.18 alpha:.95];
    t.layer.cornerRadius = 10;
    t.clipsToBounds = YES;
    [t sizeToFit];
    CGFloat tw = t.frame.size.width + 28;
    t.frame = CGRectMake((_panel.bounds.size.width-tw)/2,
                         _panel.bounds.size.height-42, tw, 28);
    t.alpha = 0;
    [_panel addSubview:t];
    [UIView animateWithDuration:.2 animations:^{ t.alpha = 1; }
                     completion:^(BOOL f){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2*NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:.2 animations:^{ t.alpha = 0; }
                completion:^(BOOL ff){ [t removeFromSuperview]; }];
        });
    }];
}

- (void)show {
    [self buildIfNeeded];
    [self refreshStatus];
    _visible = YES;
    _win.hidden = NO;
    [_win makeKeyAndVisible];
    _panel.alpha = 0;
    _panel.transform = CGAffineTransformMakeScale(.85,.85);
    [UIView animateWithDuration:.28 delay:0 usingSpringWithDamping:.72
             initialSpringVelocity:.5 options:0 animations:^{
        self->_panel.alpha = 1;
        self->_panel.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)hide {
    [self hideKB];
    [UIView animateWithDuration:.2 animations:^{
        self->_panel.alpha = 0;
        self->_panel.transform = CGAffineTransformMakeScale(.88,.88);
    } completion:^(BOOL f){
        self->_win.hidden = YES;
        self->_visible = NO;
    }];
}

- (void)toggle { _visible ? [self hide] : [self show]; }

@end

// ─── Floating button ──────────────────────────────────────────────
static UIWindow *sFloatWin = nil;

static void installFloatBtn(void) {
    CGRect sc = [UIScreen mainScreen].bounds;
    sFloatWin = [[UIWindow alloc] initWithFrame:
        CGRectMake(sc.size.width-62, sc.size.height*.38, 50, 50)];
    sFloatWin.windowLevel = UIWindowLevelAlert + 50;
    sFloatWin.backgroundColor = [UIColor clearColor];
    sFloatWin.userInteractionEnabled = YES;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0,0,50,50);
    [btn setTitle:@"🛠" forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithRed:.10 green:.78 blue:.55 alpha:.90];
    btn.layer.cornerRadius = 25;
    btn.layer.shadowColor  = UIColor.blackColor.CGColor;
    btn.layer.shadowOpacity = .30;
    btn.layer.shadowRadius  = 6;
    btn.layer.shadowOffset  = CGSizeMake(0,3);
    btn.titleLabel.font = [UIFont systemFontOfSize:20];
    [btn addTarget:[UDMenu shared] action:@selector(toggle)
  forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:btn action:@selector(ud_pan:)];
    [btn addGestureRecognizer:pan];
    [sFloatWin addSubview:btn];
    sFloatWin.hidden = NO;
    [sFloatWin makeKeyAndVisible];
}

@interface UIButton (UDPan)
- (void)ud_pan:(UIPanGestureRecognizer *)g;
@end
@implementation UIButton (UDPan)
- (void)ud_pan:(UIPanGestureRecognizer *)g {
    if (!sFloatWin) return;
    CGPoint d = [g translationInView:sFloatWin];
    CGRect f  = sFloatWin.frame;
    f.origin.x += d.x; f.origin.y += d.y;
    CGRect sc = [UIScreen mainScreen].bounds;
    f.origin.x = MAX(0, MIN(f.origin.x, sc.size.width  - f.size.width));
    f.origin.y = MAX(20,MIN(f.origin.y, sc.size.height - f.size.height - 20));
    sFloatWin.frame = f;
    [g setTranslation:CGPointZero inView:sFloatWin];
}
@end

// ─── Hook Unitoreios trực tiếp (Logos dùng runtime → không cần linker) ──
// Capture sInst ngay tại -init: gọi khi extraInfo = [Unitoreios new] trong +load
%hook Unitoreios

- (id)init {
    id result = %orig;
    if (result) sInst = result;
    return result;
}

// Backup: bắt thêm ở các method instance khác
- (BOOL)canUseCachedSession {
    if (!sInst) sInst = self;
    return %orig;
}

- (void)checkKey {
    if (!sInst) sInst = self;
    %orig;
}

- (void)updateTime {
    if (!sInst) sInst = self;
    %orig;
}

- (void)showOfflineNoticeIfNeeded {
    // Method này chắc chắn được gọi trong offline mode
    if (!sInst) sInst = self;
    %orig;
}

- (void)checkAndRequestUDIDIfNeeded {
    if (!sInst) sInst = self;
    %orig;
}

%end

// ─── Constructor ──────────────────────────────────────────────────
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2.0*NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
        installFloatBtn();
    });
}
