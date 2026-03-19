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
#define COL_BG      [UIColor colorWithRed:0.07 green:0.07 blue:0.11 alpha:0.97]
#define COL_BAR     [UIColor colorWithRed:0.11 green:0.07 blue:0.20 alpha:1]
#define COL_PURPLE  [UIColor colorWithRed:0.55 green:0.35 blue:0.90 alpha:1]
#define COL_GREEN   [UIColor colorWithRed:0.20 green:0.72 blue:0.44 alpha:1]
#define COL_RED     [UIColor colorWithRed:0.90 green:0.25 blue:0.25 alpha:1]
#define COL_FIELD   [UIColor colorWithWhite:0.18 alpha:1]
#define COL_DIM     [UIColor colorWithWhite:0.40 alpha:1]
#define COL_MONO    [UIColor colorWithRed:0.40 green:1.00 blue:0.62 alpha:1]

// ─── Item Row ─────────────────────────────────────────────────────────────────
@interface ItemRow : UIView
@property (nonatomic, strong) UITextField *idField;
@property (nonatomic, strong) UITextField *amtField;
@end

@implementation ItemRow
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0,0,288,30)];

    _idField = [self makeField:@"Item ID" frame:CGRectMake(0,2,150,26) numeric:NO];
    _amtField = [self makeField:@"Amount"  frame:CGRectMake(156,2,90,26) numeric:YES];

    UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
    del.frame = CGRectMake(250,2,36,26);
    [del setTitle:@"X" forState:UIControlStateNormal];
    del.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [del setTitleColor:COL_RED forState:UIControlStateNormal];
    [del addTarget:self action:@selector(removeSelf)
  forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:del];
    return self;
}

- (UITextField *)makeField:(NSString *)ph frame:(CGRect)f numeric:(BOOL)num {
    UITextField *t = [[UITextField alloc] initWithFrame:f];
    t.borderStyle = UITextBorderStyleRoundedRect;
    t.font = [UIFont systemFontOfSize:12];
    t.backgroundColor = COL_FIELD;
    t.textColor = UIColor.whiteColor;
    t.keyboardType = num ? UIKeyboardTypeNumberPad : UIKeyboardTypeDefault;
    t.attributedPlaceholder =
        [[NSAttributedString alloc] initWithString:ph
             attributes:@{NSForegroundColorAttributeName:COL_DIM}];
    [self addSubview:t];
    return t;
}

- (void)removeSelf {
    UIScrollView *scroll = (UIScrollView *)self.superview.superview;
    UIView *container    = self.superview;
    [self removeFromSuperview];
    // restack
    CGFloat y = 2;
    for (UIView *v in container.subviews) {
        v.frame = CGRectMake(0, y, 288, 30);
        y += 34;
    }
    CGFloat h = MAX((CGFloat)container.subviews.count * 34 + 4, 34);
    container.frame = CGRectMake(2,2,288,h);
    scroll.contentSize = CGSizeMake(288, h+4);
}
@end

// ─── Menu View ────────────────────────────────────────────────────────────────
@interface MochiMenuView : UIView
@end

@implementation MochiMenuView {
    UITextField  *_codeField;
    UILabel      *_urlLabel;
    UIScrollView *_scroll;
    UIView       *_rowContainer;
    UILabel      *_statusLabel;
    UIButton     *_runBtn;
}

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 60, 316, 510)];
    if (!self) return nil;
    gItems = [NSMutableArray array];

    self.backgroundColor = COL_BG;
    self.layer.cornerRadius = 13;
    self.layer.borderColor  = COL_PURPLE.CGColor;
    self.layer.borderWidth  = 1.5;
    self.layer.shadowColor  = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.7;
    self.layer.shadowRadius  = 12;

    // ── Title bar ──
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0,0,316,38)];
    bar.backgroundColor = COL_BAR;
    bar.layer.cornerRadius = 13;
    bar.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [self addSubview:bar];

    UILabel *title = [UILabel new];
    title.text = @"Mochi Hooker";
    title.textColor = COL_PURPLE;
    title.font = [UIFont boldSystemFontOfSize:14];
    title.frame = CGRectMake(12,8,230,22);
    [bar addSubview:title];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    [bar addGestureRecognizer:pan];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(282,8,24,22);
    [closeBtn setTitle:@"X" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [closeBtn setTitleColor:COL_DIM forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:closeBtn];

    // ── Section 1: GIFT ITEMS (top) ──
    [self sectionLabel:@"Choose Item" y:46];

    UILabel *hdr = [UILabel new];
    hdr.text = @"Item ID                              Amount";
    hdr.font = [UIFont systemFontOfSize:10];
    hdr.textColor = COL_DIM;
    hdr.frame = CGRectMake(12,61,292,13);
    [self addSubview:hdr];

    _scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(8,76,300,190)];
    _scroll.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    _scroll.layer.cornerRadius = 7;
    _scroll.showsVerticalScrollIndicator = YES;
    [self addSubview:_scroll];

    _rowContainer = [[UIView alloc] initWithFrame:CGRectMake(2,2,288,0)];
    [_scroll addSubview:_rowContainer];
    [self addRow]; // first row

    UIButton *addBtn = [self styledBtn:@"+ Add Item"
                                 frame:CGRectMake(8,274,140,30)
                                 color:COL_GREEN];
    [addBtn addTarget:self action:@selector(onAddItem) forControlEvents:UIControlEventTouchUpInside];

    // ── Divider ──
    [self divider:312];

    // ── Section 2: CODE ──
    [self sectionLabel:@"Hook Code" y:318];

    _codeField = [[UITextField alloc] initWithFrame:CGRectMake(12,334,174,28)];
    _codeField.borderStyle = UITextBorderStyleRoundedRect;
    _codeField.font = [UIFont fontWithName:@"Courier" size:12];
    _codeField.backgroundColor = COL_FIELD;
    _codeField.textColor = COL_MONO;
    _codeField.attributedPlaceholder =
        [[NSAttributedString alloc] initWithString:@"mochi{...}"
             attributes:@{NSForegroundColorAttributeName:COL_DIM}];
    [self addSubview:_codeField];

    UIButton *genBtn = [self styledBtn:@"Generate"
                                 frame:CGRectMake(192,334,56,28)
                                 color:COL_PURPLE];
    [genBtn addTarget:self action:@selector(onGenerate) forControlEvents:UIControlEventTouchUpInside];
    genBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];

    UIButton *copyBtn = [self styledBtn:@"Copy"
                                  frame:CGRectMake(254,334,52,28)
                                  color:COL_DIM];
    [copyBtn addTarget:self action:@selector(onCopyCode) forControlEvents:UIControlEventTouchUpInside];
    copyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];

    _urlLabel = [UILabel new];
    _urlLabel.font = [UIFont fontWithName:@"Courier" size:8.5];
    _urlLabel.textColor = [UIColor colorWithWhite:0.35 alpha:1];
    _urlLabel.numberOfLines = 2;
    _urlLabel.frame = CGRectMake(12,366,292,26);
    [self addSubview:_urlLabel];

    // ── Run / Stop ──
    [self divider:398];

    _runBtn = [self styledBtn:@"Run"
                        frame:CGRectMake(8,406,300,34)
                        color:COL_GREEN];
    _runBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [_runBtn addTarget:self action:@selector(onRunStop) forControlEvents:UIControlEventTouchUpInside];

    // ── Status ──
    _statusLabel = [UILabel new];
    _statusLabel.text = @"Status: Idle";
    _statusLabel.font = [UIFont systemFontOfSize:11];
    _statusLabel.textColor = COL_DIM;
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.frame = CGRectMake(0,448,316,20);
    [self addSubview:_statusLabel];

    return self;
}

// ── helpers ───────────────────────────────────────────────────────────────────
- (UILabel *)sectionLabel:(NSString *)t y:(CGFloat)y {
    UILabel *l = [UILabel new];
    l.text = t;
    l.font = [UIFont boldSystemFontOfSize:10];
    l.textColor = COL_PURPLE;
    l.frame = CGRectMake(12, y, 292, 14);
    [self addSubview:l];
    return l;
}

- (UIButton *)styledBtn:(NSString *)title frame:(CGRect)f color:(UIColor *)c {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = f;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [b setTitleColor:c forState:UIControlStateNormal];
    b.layer.borderColor  = c.CGColor;
    b.layer.borderWidth  = 1.2;
    b.layer.cornerRadius = 7;
    [self addSubview:b];
    return b;
}

- (void)divider:(CGFloat)y {
    UIView *d = [[UIView alloc] initWithFrame:CGRectMake(12,y,292,1)];
    d.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1];
    [self addSubview:d];
}

- (void)addRow {
    ItemRow *row = [ItemRow new];
    row.frame = CGRectMake(0, (CGFloat)_rowContainer.subviews.count * 34 + 2, 288, 30);
    [_rowContainer addSubview:row];
    [self refreshScroll];
}

- (void)refreshScroll {
    CGFloat h = MAX((CGFloat)_rowContainer.subviews.count * 34 + 4, 34);
    _rowContainer.frame = CGRectMake(2,2,288,h);
    _scroll.contentSize = CGSizeMake(288, h+4);
}

// ── actions ───────────────────────────────────────────────────────────────────
- (void)onAddItem { [self addRow]; }

- (void)onGenerate {
    // Collect items first
    [gItems removeAllObjects];
    BOOL hasItems = NO;
    for (ItemRow *row in _rowContainer.subviews) {
        if (![row isKindOfClass:[ItemRow class]]) continue;
        NSString *iid = row.idField.text;
        NSString *amt = row.amtField.text;
        if (iid.length && amt.length) {
            [gItems addObject:@{@"id":iid, @"amount":amt}];
            hasItems = YES;
        }
    }
    if (!hasItems) {
        [self setStatus:@"Fill in at least one item first" color:COL_RED];
        return;
    }
    NSString *code = [NSString stringWithFormat:@"mochi{%@}", randomAlpha(12)];
    _codeField.text = code;
    gMochiCode = code;
    _urlLabel.text = targetURL();
    [self setStatus:@"Code hooked — press Run to activate" color:COL_DIM];
}

- (void)onCopyCode {
    NSString *code = _codeField.text;
    if (!code.length) {
        [self setStatus:@"Nothing to copy" color:COL_RED];
        return;
    }
    [UIPasteboard generalPasteboard].string = code;
    [self setStatus:@"Code copied to clipboard" color:COL_GREEN];
}

- (void)onRunStop {
    if (gRunning) {
        gRunning = NO;
        [_runBtn setTitle:@"Run" forState:UIControlStateNormal];
        [_runBtn setTitleColor:COL_GREEN forState:UIControlStateNormal];
        _runBtn.layer.borderColor = COL_GREEN.CGColor;
        [self setStatus:@"Status: Stopped" color:COL_DIM];
        return;
    }

    // Validate items
    [gItems removeAllObjects];
    for (ItemRow *row in _rowContainer.subviews) {
        if (![row isKindOfClass:[ItemRow class]]) continue;
        NSString *iid = row.idField.text;
        NSString *amt = row.amtField.text;
        if (iid.length && amt.length)
            [gItems addObject:@{@"id":iid, @"amount":amt}];
    }
    if (!gItems.count) {
        [self setStatus:@"Add at least one item before running" color:COL_RED];
        return;
    }

    // Validate code
    NSString *code = _codeField.text;
    if (!code.length) {
        [self setStatus:@"Generate or enter a code first" color:COL_RED];
        return;
    }
    gMochiCode = code;
    _urlLabel.text = targetURL();

    gRunning = YES;
    [_runBtn setTitle:@"Stop" forState:UIControlStateNormal];
    [_runBtn setTitleColor:COL_RED forState:UIControlStateNormal];
    _runBtn.layer.borderColor = COL_RED.CGColor;
    [self setStatus:[NSString stringWithFormat:@"Active — hooking %lu item(s)",
                     (unsigned long)gItems.count]
              color:COL_MONO];
}

- (void)setStatus:(NSString *)text color:(UIColor *)c {
    _statusLabel.text  = text;
    _statusLabel.textColor = c;
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}

- (void)close {
    self.hidden = YES;
    gFabButton.hidden = NO;
}

@end

// ─── Overlay window ───────────────────────────────────────────────────────────
static UIWindow      *gOverlayWindow = nil;
static MochiMenuView *gMenuView      = nil;

static void buildOverlay() {
    gOverlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    gOverlayWindow.windowLevel = UIWindowLevelAlert + 200;
    gOverlayWindow.backgroundColor = UIColor.clearColor;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    gOverlayWindow.rootViewController = vc;
    [gOverlayWindow makeKeyAndVisible];

    // ── Menu ──
    gMenuView = [MochiMenuView new];
    [vc.view addSubview:gMenuView];

    // ── FAB toggle button (shown when menu is closed) ──
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    gFabButton = [UIButton buttonWithType:UIButtonTypeSystem];
    gFabButton.frame = CGRectMake(sw - 78, 110, 68, 28);
    gFabButton.backgroundColor = [UIColor colorWithRed:0.11 green:0.07 blue:0.20 alpha:0.92];
    gFabButton.layer.cornerRadius = 8;
    gFabButton.layer.borderColor  = COL_PURPLE.CGColor;
    gFabButton.layer.borderWidth  = 1.2;
    [gFabButton setTitle:@"Mochi" forState:UIControlStateNormal];
    gFabButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [gFabButton setTitleColor:COL_PURPLE forState:UIControlStateNormal];
    gFabButton.hidden = YES; // hidden while menu is visible
    [gFabButton addTarget:[UIApplication sharedApplication]
                   action:@selector(mochiShow)
         forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:gFabButton];
}

// ─── UIApplication category for FAB tap ──────────────────────────────────────
@interface UIApplication (Mochi)
- (void)mochiShow;
@end
@implementation UIApplication (Mochi)
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
