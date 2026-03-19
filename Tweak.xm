// Tweak.xm  –  TrollFools compatible plain dylib
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ─── State ────────────────────────────────────────────────────────────────────
static NSString       *gMochiCode = nil;
static NSMutableArray *gItems     = nil;
static BOOL            gRunning   = NO;
static UIButton       *gFabButton = nil;

// ─── Helpers ──────────────────────────────────────────────────────────────────
static NSString *randomAlpha(NSUInteger len) {
    NSString *chars = @"abcdefghijklmnopqrstuvwxyz0123456789";
    NSMutableString *s = [NSMutableString stringWithCapacity:len];
    for (NSUInteger i = 0; i < len; i++)
        [s appendFormat:@"%C", [chars characterAtIndex:arc4random_uniform((uint32_t)chars.length)]];
    return s;
}

static NSString *targetURL() {
    return [NSString stringWithFormat:
        @"https://ashen-legacy-default-rtdb.asia-southeast1.firebasedatabase.app/Code//%@.json",
        gMochiCode];
}

static NSData *fakeResponse() {
    NSString *gift = @"0-0";
    if (gItems.count) {
        NSMutableArray *parts = [NSMutableArray array];
        for (NSDictionary *item in gItems)
            [parts addObject:[NSString stringWithFormat:@"%@-%@", item[@"id"], item[@"amount"]]];
        gift = [parts componentsJoinedByString:@","];
    }
    NSDictionary *d = @{@"CountCurrent":@1, @"CountMax":@10000, @"Gift":gift};
    return [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
}

// ─── NSURLSession swizzle ─────────────────────────────────────────────────────
typedef void (^CompletionBlock)(NSData *, NSURLResponse *, NSError *);
static NSURLSessionDataTask *(*orig_dataTaskWithRequest)(id, SEL, NSURLRequest *, CompletionBlock);

static NSURLSessionDataTask *swiz_dataTaskWithRequest(id self, SEL _cmd,
                                                       NSURLRequest *req,
                                                       CompletionBlock ch) {
    if (gRunning && gMochiCode.length &&
        [req.URL.absoluteString isEqualToString:targetURL()]) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSHTTPURLResponse *resp =
                [[NSHTTPURLResponse alloc] initWithURL:req.URL
                                            statusCode:200
                                           HTTPVersion:@"HTTP/1.1"
                                          headerFields:@{@"Content-Type":@"application/json"}];
            if (ch) ch(fakeResponse(), resp, nil);
        });
        NSURLSessionDataTask *dummy = orig_dataTaskWithRequest(self, _cmd, req, nil);
        [dummy cancel];
        return dummy;
    }
    return orig_dataTaskWithRequest(self, _cmd, req, ch);
}

static void installSwizzle() {
    Class cls = [NSURLSession class];
    SEL   sel = @selector(dataTaskWithRequest:completionHandler:);
    Method m  = class_getInstanceMethod(cls, sel);
    orig_dataTaskWithRequest =
        (NSURLSessionDataTask *(*)(id,SEL,NSURLRequest*,CompletionBlock))
        method_getImplementation(m);
    method_setImplementation(m, (IMP)swiz_dataTaskWithRequest);
}

// ─── Colors ───────────────────────────────────────────────────────────────────
#define COL_BG     [UIColor colorWithRed:0.07 green:0.07 blue:0.11 alpha:0.97]
#define COL_BAR    [UIColor colorWithRed:0.11 green:0.07 blue:0.20 alpha:1]
#define COL_PURPLE [UIColor colorWithRed:0.55 green:0.35 blue:0.90 alpha:1]
#define COL_GREEN  [UIColor colorWithRed:0.20 green:0.72 blue:0.44 alpha:1]
#define COL_RED    [UIColor colorWithRed:0.90 green:0.25 blue:0.25 alpha:1]
#define COL_FIELD  [UIColor colorWithWhite:0.18 alpha:1]
#define COL_DIM    [UIColor colorWithWhite:0.40 alpha:1]
#define COL_MONO   [UIColor colorWithRed:0.40 green:1.00 blue:0.62 alpha:1]

static const CGFloat kMenuW      = 290;
static const CGFloat kBarH       = 34;
static const CGFloat kRowH       = 28;
static const CGFloat kRowSpacing = 32;
static const CGFloat kFieldH     = 24;
static const CGFloat kBtnH       = 28;
static const CGFloat kScrollH    = 130;
static const CGFloat kPad        = 10;

// ─── Pass-through overlay window ──────────────────────────────────────────────
// CRITICAL FIX: return nil for any touch that doesn't land on a visible
// overlay subview so the underlying app window gets the event normally.
@interface MochiPassthroughWindow : UIWindow @end
@implementation MochiPassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // If hit is our own root view (the transparent background) return nil
    // so the touch falls through to the app.
    if (hit == self.rootViewController.view) return nil;
    if (hit == self) return nil;
    return hit;
}

@end

// ─── Item Row ─────────────────────────────────────────────────────────────────
@interface ItemRow : UIView
@property (nonatomic, strong) UITextField *idField;
@property (nonatomic, strong) UITextField *amtField;
@end

@implementation ItemRow

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, 274, kRowH)];

    _idField  = [self field:@"Item ID" frame:CGRectMake(0,   0, 140, kFieldH) num:NO];
    _amtField = [self field:@"Amount"  frame:CGRectMake(146, 0,  82, kFieldH) num:YES];

    UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
    del.frame = CGRectMake(232, 0, 38, kFieldH);
    [del setTitle:@"X" forState:UIControlStateNormal];
    del.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [del setTitleColor:COL_RED forState:UIControlStateNormal];
    [del addTarget:self action:@selector(removeSelf)
  forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:del];
    return self;
}

- (UITextField *)field:(NSString *)ph frame:(CGRect)f num:(BOOL)num {
    UITextField *t = [[UITextField alloc] initWithFrame:f];
    t.borderStyle  = UITextBorderStyleRoundedRect;
    t.font         = [UIFont systemFontOfSize:11];
    t.backgroundColor = COL_FIELD;
    t.textColor    = UIColor.whiteColor;
    t.keyboardType = num ? UIKeyboardTypeNumberPad : UIKeyboardTypeDefault;
    t.returnKeyType = UIReturnKeyDone;
    t.attributedPlaceholder =
        [[NSAttributedString alloc] initWithString:ph
             attributes:@{NSForegroundColorAttributeName:COL_DIM}];
    [self addSubview:t];
    return t;
}

- (void)removeSelf {
    UIView *container    = self.superview;
    UIScrollView *scroll = (UIScrollView *)container.superview;
    [self removeFromSuperview];
    CGFloat y = 2;
    for (UIView *v in container.subviews) {
        CGRect fr = v.frame; fr.origin.y = y; v.frame = fr;
        y += kRowSpacing;
    }
    CGFloat h = MAX(y, kRowH + 4);
    container.frame = CGRectMake(2, 2, 274, h);
    scroll.contentSize = CGSizeMake(274, h + 4);
}

@end

// ─── Menu View ────────────────────────────────────────────────────────────────
@interface MochiMenuView : UIView <UITextFieldDelegate>
- (void)relayout;
@end

@implementation MochiMenuView {
    UITextField  *_codeField;
    UILabel      *_urlLabel;
    UIScrollView *_scroll;
    UIView       *_rowContainer;
    UILabel      *_statusLabel;
    UIButton     *_runBtn;
    CGFloat       _menuH;
}

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    gItems = [NSMutableArray array];

    self.backgroundColor = COL_BG;
    self.layer.cornerRadius  = 12;
    self.layer.borderColor   = COL_PURPLE.CGColor;
    self.layer.borderWidth   = 1.4;
    self.layer.shadowColor   = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.65;
    self.layer.shadowRadius  = 10;

    // Tap anywhere on the menu card to dismiss keyboard
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tap];

    // ── Title bar ──────────────────────────────────────────────────────────
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kMenuW, kBarH)];
    bar.backgroundColor = COL_BAR;
    bar.layer.cornerRadius = 12;
    bar.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [self addSubview:bar];

    UILabel *title = [UILabel new];
    title.text      = @"Mochi Interceptor";
    title.textColor = COL_PURPLE;
    title.font      = [UIFont boldSystemFontOfSize:13];
    title.frame     = CGRectMake(10, 0, 210, kBarH);
    [bar addSubview:title];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    [bar addGestureRecognizer:pan];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(kMenuW - 34, 0, 30, kBarH);
    [closeBtn setTitle:@"X" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [closeBtn setTitleColor:COL_DIM forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(close)
       forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:closeBtn];

    CGFloat y = kBarH + kPad;

    // ── Step 1 ─────────────────────────────────────────────────────────────
    y = [self sectionLabel:@"STEP 1 — GIFT ITEMS" y:y];

    UILabel *hdr = [UILabel new];
    hdr.text      = @"Item ID                    Amount";
    hdr.font      = [UIFont systemFontOfSize:9];
    hdr.textColor = COL_DIM;
    hdr.frame     = CGRectMake(kPad, y, kMenuW - kPad*2, 12);
    [self addSubview:hdr];
    y += 14;

    _scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(7, y, kMenuW-14, kScrollH)];
    _scroll.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    _scroll.layer.cornerRadius = 6;
    _scroll.showsVerticalScrollIndicator = YES;
    [self addSubview:_scroll];
    y += kScrollH + 6;

    _rowContainer = [[UIView alloc] initWithFrame:CGRectMake(2, 2, 274, 0)];
    [_scroll addSubview:_rowContainer];
    [self addRow];

    UIButton *addBtn = [self btn:@"+ Add Item"
                           frame:CGRectMake(kPad, y, 120, kBtnH)
                             col:COL_GREEN];
    [addBtn addTarget:self action:@selector(onAddItem)
     forControlEvents:UIControlEventTouchUpInside];
    y += kBtnH + kPad;

    [self divider:y]; y += 8;

    // ── Step 2 ─────────────────────────────────────────────────────────────
    y = [self sectionLabel:@"STEP 2 — CREATE CODE" y:y];

    _codeField = [[UITextField alloc] initWithFrame:CGRectMake(kPad, y, 155, kFieldH)];
    _codeField.borderStyle  = UITextBorderStyleRoundedRect;
    _codeField.font         = [UIFont fontWithName:@"Courier" size:11];
    _codeField.backgroundColor = COL_FIELD;
    _codeField.textColor    = COL_MONO;
    _codeField.returnKeyType = UIReturnKeyDone;
    _codeField.delegate     = self;
    _codeField.attributedPlaceholder =
        [[NSAttributedString alloc] initWithString:@"mochi..."
             attributes:@{NSForegroundColorAttributeName:COL_DIM}];
    [self addSubview:_codeField];

    UIButton *genBtn  = [self btn:@"Gen"  frame:CGRectMake(171, y,  52, kFieldH) col:COL_PURPLE];
    UIButton *copyBtn = [self btn:@"Copy" frame:CGRectMake(228, y,  52, kFieldH) col:COL_DIM];
    [genBtn  addTarget:self action:@selector(onGenerate)
      forControlEvents:UIControlEventTouchUpInside];
    [copyBtn addTarget:self action:@selector(onCopyCode)
      forControlEvents:UIControlEventTouchUpInside];
    genBtn.titleLabel.font  = [UIFont boldSystemFontOfSize:11];
    copyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    y += kFieldH + 4;

    _urlLabel = [UILabel new];
    _urlLabel.font          = [UIFont fontWithName:@"Courier" size:8];
    _urlLabel.textColor     = [UIColor colorWithWhite:0.32 alpha:1];
    _urlLabel.numberOfLines = 2;
    _urlLabel.frame         = CGRectMake(kPad, y, kMenuW - kPad*2, 22);
    [self addSubview:_urlLabel];
    y += 24;

    [self divider:y]; y += 8;

    _runBtn = [self btn:@"Run"
                  frame:CGRectMake(kPad, y, kMenuW - kPad*2, kBtnH + 2)
                    col:COL_GREEN];
    _runBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [_runBtn addTarget:self action:@selector(onRunStop)
      forControlEvents:UIControlEventTouchUpInside];
    y += kBtnH + 2 + 6;

    _statusLabel = [UILabel new];
    _statusLabel.text          = @"Idle";
    _statusLabel.font          = [UIFont systemFontOfSize:10];
    _statusLabel.textColor     = COL_DIM;
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.frame         = CGRectMake(0, y, kMenuW, 16);
    [self addSubview:_statusLabel];
    y += 18;

    _menuH     = y;
    self.frame = CGRectMake(20, 60, kMenuW, _menuH);
    return self;
}

// ─── UITextFieldDelegate ──────────────────────────────────────────────────────
- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    return YES;
}

- (void)dismissKeyboard { [self endEditing:YES]; }

// ─── Layout helpers ───────────────────────────────────────────────────────────
- (CGFloat)sectionLabel:(NSString *)t y:(CGFloat)y {
    UILabel *l = [UILabel new];
    l.text      = t;
    l.font      = [UIFont boldSystemFontOfSize:9];
    l.textColor = COL_PURPLE;
    l.frame     = CGRectMake(kPad, y, kMenuW - kPad*2, 12);
    [self addSubview:l];
    return y + 14;
}

- (UIButton *)btn:(NSString *)title frame:(CGRect)f col:(UIColor *)c {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = f;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [b setTitleColor:c forState:UIControlStateNormal];
    b.layer.borderColor  = c.CGColor;
    b.layer.borderWidth  = 1.1;
    b.layer.cornerRadius = 6;
    [self addSubview:b];
    return b;
}

- (void)divider:(CGFloat)y {
    UIView *d = [[UIView alloc] initWithFrame:CGRectMake(kPad, y, kMenuW - kPad*2, 1)];
    d.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1];
    [self addSubview:d];
}

- (void)addRow {
    ItemRow *row = [ItemRow new];
    row.frame = CGRectMake(0, (CGFloat)_rowContainer.subviews.count * kRowSpacing + 2, 274, kRowH);
    row.idField.delegate  = self;
    row.amtField.delegate = self;
    [_rowContainer addSubview:row];
    [self refreshScroll];
}

- (void)refreshScroll {
    NSUInteger cnt = _rowContainer.subviews.count;
    CGFloat h = MAX((CGFloat)cnt * kRowSpacing + 4, kRowH + 4);
    _rowContainer.frame    = CGRectMake(2, 2, 274, h);
    _scroll.contentSize    = CGSizeMake(274, h + 4);
}

- (void)relayout {
    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat maxX  = screen.size.width  - kMenuW - 10;
    CGFloat maxY  = screen.size.height - _menuH  - 10;
    CGRect f      = self.frame;
    f.origin.x    = MIN(MAX(f.origin.x, 10), MAX(maxX, 10));
    f.origin.y    = MIN(MAX(f.origin.y, 10), MAX(maxY, 10));
    self.frame    = f;

    if (gFabButton) {
        gFabButton.frame = CGRectMake(screen.size.width - 78, 60, 68, 26);
    }
}

// ─── Actions ──────────────────────────────────────────────────────────────────
- (void)onAddItem { [self addRow]; }

- (void)onGenerate {
    [self dismissKeyboard];
    [gItems removeAllObjects];
    BOOL ok = NO;
    for (ItemRow *row in _rowContainer.subviews) {
        if (![row isKindOfClass:[ItemRow class]]) continue;
        if (row.idField.text.length && row.amtField.text.length) {
            [gItems addObject:@{@"id":row.idField.text, @"amount":row.amtField.text}];
            ok = YES;
        }
    }
    if (!ok) { [self status:@"Fill at least one item first" col:COL_RED]; return; }

    NSString *code    = [NSString stringWithFormat:@"mochi%@", randomAlpha(12)];
    _codeField.text   = code;
    gMochiCode        = code;
    _urlLabel.text    = targetURL();
    [self status:@"Code generated — press Run" col:COL_DIM];
}

- (void)onCopyCode {
    if (!_codeField.text.length) { [self status:@"Nothing to copy" col:COL_RED]; return; }
    [UIPasteboard generalPasteboard].string = _codeField.text;
    [self status:@"Copied to clipboard" col:COL_GREEN];
}

- (void)onRunStop {
    [self dismissKeyboard];
    if (gRunning) {
        gRunning = NO;
        [_runBtn setTitle:@"Run" forState:UIControlStateNormal];
        [_runBtn setTitleColor:COL_GREEN forState:UIControlStateNormal];
        _runBtn.layer.borderColor = COL_GREEN.CGColor;
        [self status:@"Stopped" col:COL_DIM];
        return;
    }
    [gItems removeAllObjects];
    for (ItemRow *row in _rowContainer.subviews) {
        if (![row isKindOfClass:[ItemRow class]]) continue;
        if (row.idField.text.length && row.amtField.text.length)
            [gItems addObject:@{@"id":row.idField.text, @"amount":row.amtField.text}];
    }
    if (!gItems.count)          { [self status:@"Add items first"       col:COL_RED]; return; }
    if (!_codeField.text.length){ [self status:@"Generate a code first" col:COL_RED]; return; }

    gMochiCode     = _codeField.text;
    _urlLabel.text = targetURL();
    gRunning       = YES;
    [_runBtn setTitle:@"Stop" forState:UIControlStateNormal];
    [_runBtn setTitleColor:COL_RED forState:UIControlStateNormal];
    _runBtn.layer.borderColor = COL_RED.CGColor;
    [self status:[NSString stringWithFormat:@"Active — %lu item(s)", (unsigned long)gItems.count]
             col:COL_MONO];
}

- (void)status:(NSString *)t col:(UIColor *)c {
    _statusLabel.text      = t;
    _statusLabel.textColor = c;
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}

- (void)close {
    [self dismissKeyboard];
    self.hidden       = YES;
    gFabButton.hidden = NO;
}

@end

// ─── Rotation-aware root VC ───────────────────────────────────────────────────
@interface MochiOverlayVC : UIViewController @end
@implementation MochiOverlayVC
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}
- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coord {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coord];
    [coord animateAlongsideTransition:nil completion:^(id ctx) {
        extern MochiMenuView *gMenuView;
        if (gMenuView) [gMenuView relayout];
    }];
}
@end

// ─── Globals ──────────────────────────────────────────────────────────────────
static MochiPassthroughWindow *gOverlayWindow = nil;
MochiMenuView                 *gMenuView      = nil;

static void buildOverlay() {
    gOverlayWindow = [[MochiPassthroughWindow alloc]
        initWithFrame:[UIScreen mainScreen].bounds];
    gOverlayWindow.windowLevel    = UIWindowLevelAlert + 200;
    gOverlayWindow.backgroundColor = UIColor.clearColor;

    MochiOverlayVC *vc = [MochiOverlayVC new];
    vc.view.backgroundColor = UIColor.clearColor;

    // The root view must also pass through untouched areas
    vc.view.userInteractionEnabled = YES;
    gOverlayWindow.rootViewController = vc;
    [gOverlayWindow makeKeyAndVisible];

    // Restore original key window so the app keeps working normally
    // The overlay window receives hits only on visible subviews (see hitTest above)
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w != gOverlayWindow) { [w makeKeyWindow]; break; }
    }

    gMenuView = [MochiMenuView new];
    [vc.view addSubview:gMenuView];

    CGFloat sw    = [UIScreen mainScreen].bounds.size.width;
    gFabButton    = [UIButton buttonWithType:UIButtonTypeSystem];
    gFabButton.frame = CGRectMake(sw - 78, 60, 68, 26);
    gFabButton.backgroundColor = [UIColor colorWithRed:0.11 green:0.07 blue:0.20 alpha:0.92];
    gFabButton.layer.cornerRadius = 7;
    gFabButton.layer.borderColor  = COL_PURPLE.CGColor;
    gFabButton.layer.borderWidth  = 1.1;
    [gFabButton setTitle:@"Mochi" forState:UIControlStateNormal];
    gFabButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [gFabButton setTitleColor:COL_PURPLE forState:UIControlStateNormal];
    gFabButton.hidden = YES;
    [gFabButton addTarget:[UIApplication sharedApplication]
                   action:@selector(mochiShow)
         forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:gFabButton];
}

@interface UIApplication (MochiShow)
- (void)mochiShow;
@end
@implementation UIApplication (MochiShow)
- (void)mochiShow {
    gMenuView.hidden  = NO;
    gFabButton.hidden = YES;
}
@end

// ─── Constructor ──────────────────────────────────────────────────────────────
__attribute__((constructor))
static void mochiInit() {
    installSwizzle();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        buildOverlay();
    });
}
