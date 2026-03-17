#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ─────────────────────────────────────────
// APIClient interface redeclaration
// ─────────────────────────────────────────
@interface APIClient : NSObject
- (void)paid:(void (^)(void))execute;
- (void)start:(void (^)(void))onStart init:(void (^)(void))init;
- (void)setToken:(NSString *)token;
- (void)setUDID:(NSString *)uid;
- (void)setLanguage:(NSString *)language;
- (void)hideUI:(bool)isHide;
- (void)strictMode:(bool)_isStrictMode;
- (void)silentMode:(bool)_isSilentMode;
- (NSString *)getKey;
- (NSString *)getExpiryDate;
- (NSString *)getExpiredAt;
- (NSString *)getUDID;
- (NSString *)getDeviceModel;
- (NSString *)getLoginIP;
- (NSString *)getPackageName;
- (void)onCheckPackage:(void (^)(NSDictionary *))success onFailure:(void (^)(NSDictionary *))failure;
- (void)onCheckDevice:(void (^)(NSDictionary *))success onFailure:(void (^)(NSDictionary *))failure;
- (void)onLogin:(NSString *)inputKey onSuccess:(void (^)(NSDictionary *))success onFailure:(void (^)(NSDictionary *))failure;
+ (instancetype)sharedAPIClient;
@end

// ─────────────────────────────────────────
// Shared tracker state
// ─────────────────────────────────────────
static NSMutableArray<NSString *> *_hookLog;
static APIClient *_lastInstance = nil;
static BOOL _apiClientExists = NO;

static void hookLog(NSString *msg) {
    if (!_hookLog) _hookLog = [NSMutableArray new];
    NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                 dateStyle:NSDateFormatterNoStyle
                                                 timeStyle:NSDateFormatterMediumStyle];
    [_hookLog addObject:[NSString stringWithFormat:@"[%@] %@", ts, msg]];
    NSLog(@"[HookInspector] %@", msg);
}

// ─────────────────────────────────────────
// Debug Panel UI
// ─────────────────────────────────────────
@interface HookInspectorPanel : UIView
+ (void)showFromView:(UIView *)parent;
@end

@implementation HookInspectorPanel

+ (void)showFromView:(UIView *)parent {
    // Backdrop
    HookInspectorPanel *panel = [[HookInspectorPanel alloc] initWithFrame:parent.bounds];
    panel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    panel.alpha = 0;
    panel.tag = 9999;
    [parent addSubview:panel];

    // Card
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(20, 80, parent.bounds.size.width - 40, parent.bounds.size.height - 160)];
    card.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:1];
    card.layer.cornerRadius = 16;
    card.layer.borderColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:0.4].CGColor;
    card.layer.borderWidth = 1;
    card.clipsToBounds = YES;
    [panel addSubview:card];

    // Header bar
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, card.bounds.size.width, 52)];
    header.backgroundColor = [UIColor colorWithRed:0.05 green:0.15 blue:0.10 alpha:1];
    [card addSubview:header];

    // Title
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, card.bounds.size.width - 60, 52)];
    title.text = @"⚡ Hook Inspector";
    title.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightBold];
    title.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1];
    [header addSubview:title];

    // Close button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(card.bounds.size.width - 48, 8, 36, 36);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [closeBtn setTitleColor:[UIColor colorWithWhite:0.6 alpha:1] forState:UIControlStateNormal];
    [closeBtn addTarget:panel action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:closeBtn];

    // Status section
    CGFloat y = 64;

    // APIClient existence badge
    UIView *badge = [[UIView alloc] initWithFrame:CGRectMake(16, y, card.bounds.size.width - 32, 40)];
    badge.backgroundColor = _apiClientExists
        ? [UIColor colorWithRed:0.0 green:0.4 blue:0.15 alpha:1]
        : [UIColor colorWithRed:0.4 green:0.0 blue:0.0 alpha:1];
    badge.layer.cornerRadius = 8;
    [card addSubview:badge];

    UILabel *badgeLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, badge.bounds.size.width - 24, 40)];
    badgeLabel.text = _apiClientExists
        ? @"✅  APIClient — HOOKED & ACTIVE"
        : @"❌  APIClient — NOT DETECTED";
    badgeLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightSemibold];
    badgeLabel.textColor = [UIColor whiteColor];
    [badge addSubview:badgeLabel];

    y += 52;

    // Instance address
    if (_lastInstance) {
        UILabel *addr = [[UILabel alloc] initWithFrame:CGRectMake(16, y, card.bounds.size.width - 32, 24)];
        addr.text = [NSString stringWithFormat:@"📍 Instance: %p", (void *)_lastInstance];
        addr.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        addr.textColor = [UIColor colorWithWhite:0.55 alpha:1];
        [card addSubview:addr];
        y += 28;
    }

    // Divider
    UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(16, y, card.bounds.size.width - 32, 1)];
    divider.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    [card addSubview:divider];
    y += 12;

    // Log label
    UILabel *logHeader = [[UILabel alloc] initWithFrame:CGRectMake(16, y, 200, 20)];
    logHeader.text = @"METHOD CALL LOG";
    logHeader.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightBold];
    logHeader.textColor = [UIColor colorWithWhite:0.4 alpha:1];
    [card addSubview:logHeader];
    y += 24;

    // Scrollable log area
    CGFloat logHeight = card.bounds.size.height - y - 16;
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(16, y, card.bounds.size.width - 32, logHeight)];
    scroll.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.06 alpha:1];
    scroll.layer.cornerRadius = 8;
    scroll.showsVerticalScrollIndicator = YES;
    [card addSubview:scroll];

    NSArray<NSString *> *logs = _hookLog.count ? _hookLog : @[@"No hooks fired yet."];
    CGFloat lineY = 10;
    for (NSString *entry in logs.reverseObjectEnumerator) {
        UILabel *line = [[UILabel alloc] init];
        line.text = entry;
        line.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        line.numberOfLines = 0;

        // Color coding
        if ([entry containsString:@"paid"]) {
            line.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1];
        } else if ([entry containsString:@"setToken"] || [entry containsString:@"setUDID"]) {
            line.textColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1];
        } else if ([entry containsString:@"FAILURE"] || [entry containsString:@"nil"]) {
            line.textColor = [UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:1];
        } else {
            line.textColor = [UIColor colorWithWhite:0.7 alpha:1];
        }

        CGSize size = [entry boundingRectWithSize:CGSizeMake(scroll.frame.size.width - 20, CGFLOAT_MAX)
                                          options:NSStringDrawingUsesLineFragmentOrigin
                                       attributes:@{NSFontAttributeName: line.font}
                                          context:nil].size;
        line.frame = CGRectMake(10, lineY, scroll.frame.size.width - 20, size.height + 4);
        [scroll addSubview:line];
        lineY += size.height + 8;
    }
    scroll.contentSize = CGSizeMake(scroll.frame.size.width, MAX(lineY + 10, scroll.frame.size.height));

    // Animate in
    [UIView animateWithDuration:0.25 animations:^{
        panel.alpha = 1;
    }];
}

- (void)dismiss {
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0;
    } completion:^(BOOL done) {
        [self removeFromSuperview];
    }];
}

// Tap backdrop to dismiss
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject;
    if ([touch.view isEqual:self]) [self dismiss];
}

@end

// ─────────────────────────────────────────
// Floating Button
// ─────────────────────────────────────────
@interface HookFloatingButton : UIButton
+ (void)installInWindow:(UIWindow *)window;
@end

@implementation HookFloatingButton

+ (void)installInWindow:(UIWindow *)window {
    HookFloatingButton *btn = [HookFloatingButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(window.bounds.size.width - 68, 100, 52, 52);
    btn.backgroundColor = [UIColor colorWithRed:0.05 green:0.12 blue:0.08 alpha:0.92];
    btn.layer.cornerRadius = 26;
    btn.layer.borderColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:0.7].CGColor;
    btn.layer.borderWidth = 1.5;
    btn.layer.shadowColor = [UIColor colorWithRed:0.1 green:0.9 blue:0.4 alpha:1].CGColor;
    btn.layer.shadowOffset = CGSizeMake(0, 0);
    btn.layer.shadowRadius = 8;
    btn.layer.shadowOpacity = 0.6;

    UILabel *icon = [[UILabel alloc] initWithFrame:btn.bounds];
    icon.text = @"🪝";
    icon.font = [UIFont systemFontOfSize:22];
    icon.textAlignment = NSTextAlignmentCenter;
    icon.userInteractionEnabled = NO;
    [btn addSubview:icon];

    [btn addTarget:btn action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];

    // Drag to reposition
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:btn action:@selector(onPan:)];
    [btn addGestureRecognizer:pan];

    btn.alpha = 0;
    [window addSubview:btn];
    [UIView animateWithDuration:0.4 delay:0.5 options:0 animations:^{
        btn.alpha = 1;
    } completion:nil];
}

- (void)onTap {
    // Pulse animation
    [UIView animateWithDuration:0.1 animations:^{
        self.transform = CGAffineTransformMakeScale(0.88, 0.88);
    } completion:^(BOOL _) {
        [UIView animateWithDuration:0.15 animations:^{
            self.transform = CGAffineTransformIdentity;
        }];
    }];

    UIWindow *window = self.window;
    if (window) [HookInspectorPanel showFromView:window];
}

- (void)onPan:(UIPanGestureRecognizer *)pan {
    CGPoint delta = [pan translationInView:self.superview];
    self.center = CGPointMake(self.center.x + delta.x, self.center.y + delta.y);
    [pan setTranslation:CGPointZero inView:self.superview];
}

@end

// ─────────────────────────────────────────
// Hook APIClient
// ─────────────────────────────────────────
%hook APIClient

- (void)setToken:(NSString *)token {
    _apiClientExists = YES;
    _lastInstance = self;
    hookLog([NSString stringWithFormat:@"🔑 setToken called → \"%@\"", token ?: @"nil"]);
    %orig;
}

- (void)setUDID:(NSString *)uid {
    hookLog([NSString stringWithFormat:@"📱 setUDID → \"%@\"", uid ?: @"nil"]);
    %orig;
}

- (void)setLanguage:(NSString *)language {
    hookLog([NSString stringWithFormat:@"🌐 setLanguage → \"%@\"", language ?: @"nil"]);
    %orig;
}

- (void)hideUI:(bool)isHide {
    hookLog([NSString stringWithFormat:@"👁 hideUI → %@", isHide ? @"YES" : @"NO"]);
    %orig;
}

- (void)strictMode:(bool)strict {
    hookLog([NSString stringWithFormat:@"🔒 strictMode → %@", strict ? @"ON" : @"OFF"]);
    %orig;
}

- (void)silentMode:(bool)silent {
    hookLog([NSString stringWithFormat:@"🔇 silentMode → %@", silent ? @"ON" : @"OFF"]);
    %orig;
}

- (void)start:(void (^)(void))onStart init:(void (^)(void))init {
    hookLog(@"🚀 start:init: called");
    %orig;
}

- (void)paid:(void (^)(void))execute {
    _apiClientExists = YES;
    _lastInstance = self;
    hookLog(@"💰 paid: INTERCEPTED — skipping server check");
    if (execute) {
        hookLog(@"▶️  paid block executing now...");
        execute();
        hookLog(@"✅  paid block finished");
    } else {
        hookLog(@"⚠️  paid block was nil — nothing to execute");
    }
    // NOTE: %orig intentionally NOT called — bypassed
}

- (void)onCheckPackage:(void (^)(NSDictionary *))success onFailure:(void (^)(NSDictionary *))failure {
    hookLog(@"📦 onCheckPackage: called");
    %orig;
}

- (void)onCheckDevice:(void (^)(NSDictionary *))success onFailure:(void (^)(NSDictionary *))failure {
    hookLog(@"🖥 onCheckDevice: called");
    %orig;
}

- (void)onLogin:(NSString *)inputKey onSuccess:(void (^)(NSDictionary *))success onFailure:(void (^)(NSDictionary *))failure {
    hookLog([NSString stringWithFormat:@"🔐 onLogin: key=\"%@\"", inputKey ?: @"nil"]);
    %orig;
}

%end

// ─────────────────────────────────────────
// Inject floating button when app is ready
// ─────────────────────────────────────────
%hook UIApplication

- (void)setDelegate:(id<UIApplicationDelegate>)delegate {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = UIApplication.sharedApplication.keyWindow;
        if (window) {
            hookLog(@"🪟 UI injected — Hook Inspector button ready");
            [HookFloatingButton installInWindow:window];
        }
    });
}

%end
