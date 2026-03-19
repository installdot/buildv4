// Tweak.xm
#import <UIKit/UIKit.h>
#import <substrate.h>

// ─── State ───────────────────────────────────────────────────────────────────
static NSString *gMochiCode   = nil;   // current mochi code
static NSMutableArray<NSDictionary*> *gItems = nil; // [{id, amount}]
static BOOL      gRunning     = NO;

// ─── Helpers ─────────────────────────────────────────────────────────────────
static NSString *randomString(NSUInteger len) {
    NSString *chars = @"abcdefghijklmnopqrstuvwxyz0123456789";
    NSMutableString *s = [NSMutableString stringWithCapacity:len];
    for (NSUInteger i = 0; i < len; i++)
        [s appendFormat:@"%C", [chars characterAtIndex:arc4random_uniform((uint32_t)chars.length)]];
    return s;
}

static NSString *buildTargetURL() {
    return [NSString stringWithFormat:@"https://ashen-legacy-default-rtdb.asia-southeast1.firebasedatabase.app/Code//%@.json", gMochiCode];
}

/** Build the fake JSON response from gItems */
static NSData *buildFakeResponse() {
    if (!gItems.count) {
        // fallback
        NSDictionary *d = @{@"CountCurrent":@1,
                            @"CountMax":@10000,
                            @"Gift":@"32-1000000"};
        return [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
    }
    // Build gift string: "itemid-howmuch,itemid2-howmuch2,…"
    NSMutableArray<NSString*> *parts = [NSMutableArray array];
    for (NSDictionary *item in gItems)
        [parts addObject:[NSString stringWithFormat:@"%@-%@", item[@"id"], item[@"amount"]]];
    NSString *gift = [parts componentsJoinedByString:@","];
    NSDictionary *d = @{@"CountCurrent":@1,
                        @"CountMax":@10000,
                        @"Gift":gift};
    return [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
}

// ─── NSURLSession hook ────────────────────────────────────────────────────────
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))ch {
    if (gRunning && gMochiCode.length) {
        NSString *target = buildTargetURL();
        if ([request.URL.absoluteString isEqualToString:target]) {
            // Block real request – return fake response immediately
            dispatch_async(dispatch_get_global_queue(0,0), ^{
                NSHTTPURLResponse *fakeResp =
                    [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                               statusCode:200
                                              HTTPVersion:@"HTTP/1.1"
                                             headerFields:@{@"Content-Type":@"application/json"}];
                if (ch) ch(buildFakeResponse(), fakeResp, nil);
            });
            // Return a dummy (cancelled) task so callers hold a valid object
            NSURLSessionDataTask *dummy = %orig(request, nil);
            [dummy cancel];
            return dummy;
        }
    }
    return %orig;
}

%end

// ─── UI Window ───────────────────────────────────────────────────────────────
@interface MochiMenuView : UIView
@end

@implementation MochiMenuView {
    UITextField   *_codeField;
    UILabel       *_codeLabel;
    UIScrollView  *_itemScroll;
    UIStackView   *_itemStack;
    UIButton      *_addBtn, *_runBtn, *_genBtn;
    UILabel       *_statusLabel;
    NSMutableArray<UIView*> *_itemRows;
}

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 80, 320, 460)];
    if (!self) return nil;
    gItems   = [NSMutableArray array];
    _itemRows = [NSMutableArray array];

    self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    self.layer.cornerRadius = 14;
    self.layer.borderColor  = [UIColor systemPurpleColor].CGColor;
    self.layer.borderWidth  = 1.5;

    // ── Title ──
    UILabel *title = [UILabel new];
    title.text = @"🍡 Mochi Menu";
    title.textColor = [UIColor systemPurpleColor];
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textAlignment = NSTextAlignmentCenter;
    title.frame = CGRectMake(0, 10, 320, 28);
    [self addSubview:title];

    // ── Drag handle ──
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    [title addGestureRecognizer:pan];
    title.userInteractionEnabled = YES;

    // ── Code row ──
    UILabel *cl = [UILabel new];
    cl.text = @"Code:";
    cl.textColor = UIColor.lightGrayColor;
    cl.font = [UIFont systemFontOfSize:13];
    cl.frame = CGRectMake(12, 46, 46, 26);
    [self addSubview:cl];

    _codeField = [[UITextField alloc] initWithFrame:CGRectMake(62, 46, 158, 26)];
    _codeField.borderStyle = UITextBorderStyleRoundedRect;
    _codeField.placeholder = @"mochi{randomtext12}";
    _codeField.font = [UIFont systemFontOfSize:12];
    _codeField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    _codeField.textColor = UIColor.whiteColor;
    [self addSubview:_codeField];

    _genBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _genBtn.frame = CGRectMake(226, 46, 82, 26);
    [_genBtn setTitle:@"Generate" forState:UIControlStateNormal];
    _genBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [_genBtn setTitleColor:UIColor.systemPurpleColor forState:UIControlStateNormal];
    _genBtn.layer.borderColor  = UIColor.systemPurpleColor.CGColor;
    _genBtn.layer.borderWidth  = 1;
    _genBtn.layer.cornerRadius = 6;
    [_genBtn addTarget:self action:@selector(onGenerate) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_genBtn];

    // ── Item list header ──
    UILabel *ih = [UILabel new];
    ih.text = @"Item ID           Amount";
    ih.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    ih.font = [UIFont systemFontOfSize:11];
    ih.frame = CGRectMake(12, 80, 296, 18);
    [self addSubview:ih];

    // ── Item scroll ──
    _itemScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(8, 100, 304, 230)];
    _itemScroll.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    _itemScroll.layer.cornerRadius = 8;
    [self addSubview:_itemScroll];

    _itemStack = [UIStackView new];
    _itemStack.axis = UILayoutConstraintAxisVertical;
    _itemStack.spacing = 6;
    _itemStack.frame = CGRectMake(0, 4, 304, 0);
    [_itemScroll addSubview:_itemStack];

    [self addItemRow]; // start with one row

    // ── Add Item button ──
    _addBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _addBtn.frame = CGRectMake(8, 338, 140, 32);
    [_addBtn setTitle:@"+ Add Item" forState:UIControlStateNormal];
    [_addBtn setTitleColor:UIColor.systemGreenColor forState:UIControlStateNormal];
    _addBtn.layer.borderColor  = UIColor.systemGreenColor.CGColor;
    _addBtn.layer.borderWidth  = 1;
    _addBtn.layer.cornerRadius = 8;
    [_addBtn addTarget:self action:@selector(onAddItem) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_addBtn];

    // ── Run / Stop button ──
    _runBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _runBtn.frame = CGRectMake(172, 338, 140, 32);
    [_runBtn setTitle:@"▶  Run" forState:UIControlStateNormal];
    [_runBtn setTitleColor:UIColor.systemGreenColor forState:UIControlStateNormal];
    _runBtn.layer.borderColor  = UIColor.systemGreenColor.CGColor;
    _runBtn.layer.borderWidth  = 1;
    _runBtn.layer.cornerRadius = 8;
    [_runBtn addTarget:self action:@selector(onRunStop) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_runBtn];

    // ── Status label ──
    _statusLabel = [UILabel new];
    _statusLabel.text = @"Status: Idle";
    _statusLabel.textColor = UIColor.lightGrayColor;
    _statusLabel.font = [UIFont systemFontOfSize:12];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.frame = CGRectMake(0, 380, 320, 22);
    [self addSubview:_statusLabel];

    // ── URL preview ──
    _codeLabel = [UILabel new];
    _codeLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1];
    _codeLabel.font = [UIFont systemFontOfSize:9];
    _codeLabel.textAlignment = NSTextAlignmentCenter;
    _codeLabel.numberOfLines = 2;
    _codeLabel.frame = CGRectMake(8, 406, 304, 40);
    [self addSubview:_codeLabel];

    // close button
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(290, 8, 24, 24);
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:UIColor.grayColor forState:UIControlStateNormal];
    [close addTarget:self action:@selector(onClose) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:close];

    return self;
}

// ── Add a new item row ──────────────────────────────────────────────────
- (void)addItemRow {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0,0,304,30)];

    UITextField *idField = [[UITextField alloc] initWithFrame:CGRectMake(4,2,158,26)];
    idField.placeholder = @"Item ID";
    idField.borderStyle = UITextBorderStyleRoundedRect;
    idField.font = [UIFont systemFontOfSize:12];
    idField.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1];
    idField.textColor = UIColor.whiteColor;
    idField.tag = 1;
    [row addSubview:idField];

    UITextField *amtField = [[UITextField alloc] initWithFrame:CGRectMake(168,2,90,26)];
    amtField.placeholder = @"Amount";
    amtField.borderStyle = UITextBorderStyleRoundedRect;
    amtField.font = [UIFont systemFontOfSize:12];
    amtField.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1];
    amtField.textColor = UIColor.whiteColor;
    amtField.keyboardType = UIKeyboardTypeNumberPad;
    amtField.tag = 2;
    [row addSubview:amtField];

    UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
    del.frame = CGRectMake(262,2,36,26);
    [del setTitle:@"✕" forState:UIControlStateNormal];
    [del setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    [del addTarget:self action:@selector(onDeleteRow:) forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:del];

    [_itemStack addArrangedSubview:row];
    [_itemRows addObject:row];
    [self relayout];
}

- (void)onDeleteRow:(UIButton *)btn {
    UIView *row = btn.superview;
    [_itemStack removeArrangedSubview:row];
    [row removeFromSuperview];
    [_itemRows removeObject:row];
    [self relayout];
}

- (void)relayout {
    CGFloat h = (CGFloat)_itemRows.count * 36 + 8;
    _itemStack.frame = CGRectMake(0, 4, 304, h);
    _itemScroll.contentSize = CGSizeMake(304, h + 8);
}

// ── Generate code ───────────────────────────────────────────────────────
- (void)onGenerate {
    NSString *rnd  = randomString(12);
    NSString *code = [NSString stringWithFormat:@"mochi{%@}", rnd];
    _codeField.text = code;
    gMochiCode = code;
    _codeLabel.text = buildTargetURL();
}

// ── Run / Stop ──────────────────────────────────────────────────────────
- (void)onRunStop {
    if (gRunning) {
        gRunning = NO;
        [_runBtn setTitle:@"▶  Run" forState:UIControlStateNormal];
        [_runBtn setTitleColor:UIColor.systemGreenColor forState:UIControlStateNormal];
        _runBtn.layer.borderColor = UIColor.systemGreenColor.CGColor;
        _statusLabel.text = @"Status: Stopped";
        return;
    }

    // Collect code
    NSString *code = _codeField.text;
    if (!code.length) {
        _statusLabel.text = @"⚠ Enter or generate a code first";
        return;
    }
    gMochiCode = code;

    // Collect items
    [gItems removeAllObjects];
    for (UIView *row in _itemRows) {
        UITextField *idF  = [row viewWithTag:1];
        UITextField *amtF = [row viewWithTag:2];
        NSString *itemId  = idF.text;
        NSString *amount  = amtF.text;
        if (itemId.length && amount.length)
            [gItems addObject:@{@"id":itemId, @"amount":amount}];
    }

    gRunning = YES;
    [_runBtn setTitle:@"⏹  Stop" forState:UIControlStateNormal];
    [_runBtn setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    _runBtn.layer.borderColor = UIColor.systemRedColor.CGColor;
    _codeLabel.text = buildTargetURL();
    _statusLabel.text = [NSString stringWithFormat:@"✅ Intercepting — %lu item(s)",
                         (unsigned long)gItems.count];
}

- (void)onAddItem { [self addItemRow]; }

- (void)onClose   { [self removeFromSuperview]; }

// ── Drag ───────────────────────────────────────────────────────────────
- (void)handlePan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}

@end

// ─── Floating trigger button ───────────────────────────────────────────────
static MochiMenuView *gMenu = nil;

static void showMenu() {
    UIWindow *win = [UIApplication sharedApplication].keyWindow;
    if (gMenu && gMenu.superview) { [gMenu removeFromSuperview]; gMenu = nil; return; }
    gMenu = [MochiMenuView new];
    [win addSubview:gMenu];
}

%hook UIApplication

- (void)applicationDidBecomeActive:(UIApplication *)app {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *win = app.keyWindow;
        // Floating pill button
        UIButton *fab = [UIButton buttonWithType:UIButtonTypeSystem];
        fab.frame = CGRectMake(win.bounds.size.width - 66, 120, 58, 28);
        fab.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
        fab.layer.cornerRadius = 14;
        fab.layer.borderColor  = UIColor.systemPurpleColor.CGColor;
        fab.layer.borderWidth  = 1.2;
        [fab setTitle:@"🍡" forState:UIControlStateNormal];
        fab.titleLabel.font = [UIFont systemFontOfSize:18];
        [fab addTarget:[UIApplication sharedApplication]
                action:@selector(mochiToggle)
      forControlEvents:UIControlEventTouchUpInside];
        [win addSubview:fab];
    });
}

%new
- (void)mochiToggle { showMenu(); }

%end
