// SKPanel.h — Dynamic floating panel builder
// Part of SKFramework · iOS 14+ · ARC
//
// Build a floating draggable panel by adding buttons, labels, and dividers
// one at a time. The panel grows vertically to fit all content.
//
// ── Minimal example ──────────────────────────────────────────────────────────
//
//   SKPanel *panel = [SKPanel new];
//   panel.panelTitle = @"My Tool";
//
//   [panel addButton:@"Upload"
//             symbol:@"icloud.and.arrow.up"
//              color:SKColorBlue()
//             action:^{ NSLog(@"upload tapped"); }];
//
//   [panel addButton:@"Load"
//             symbol:@"icloud.and.arrow.down"
//              color:SKColorGreen()
//             action:^{ NSLog(@"load tapped"); }];
//
//   [panel addDivider];
//
//   [panel addSmallButtonsRow:@[
//       [SKButton buttonWithTitle:@"Settings" symbol:@"gearshape"
//                          color:SKColorGray() action:^{ [settingsMenu showInView:root]; }],
//       [SKButton buttonWithTitle:@"Hide"     symbol:@"eye.slash"
//                          color:SKColorRed() action:^{ [panel hide]; }],
//   ]];
//
//   [panel showInView:rootView];
//
// ── Info labels ───────────────────────────────────────────────────────────────
//
//   SKPanelLabel *lbl = [panel addLabel:@"statusLabel" text:@"No session"];
//   // later:
//   [panel setLabelText:@"Session: abc123…" forKey:@"statusLabel"];
//
// ── Custom view ───────────────────────────────────────────────────────────────
//
//   [panel addCustomView:myProgressBar height:8];

#pragma once
#import "SKTypes.h"
#import "SKButton.h"
#import "SKSettingsMenu.h"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: SKPanelLabel  (returned by addLabel:text: so you can update it later)
// ─────────────────────────────────────────────────────────────────────────────

@interface SKPanelLabel : NSObject
/// The underlying UILabel. Do not re-parent it.
@property (nonatomic, readonly, strong) UILabel *view;
/// Current text. Setting this updates the UILabel on the main queue.
@property (nonatomic, copy) NSString *text;
/// Text color. Default: dim white (0.44 alpha).
@property (nonatomic, strong) UIColor *color;
/// Font. Default: system 9.5.
@property (nonatomic, strong) UIFont  *font;
@end

@implementation SKPanelLabel
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    UILabel *l = [UILabel new];
    l.font          = [UIFont systemFontOfSize:9.5];
    l.textColor     = [UIColor colorWithWhite:0.44 alpha:1];
    l.textAlignment = NSTextAlignmentCenter;
    l.numberOfLines = 2;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    _view  = l;
    _color = l.textColor;
    _font  = l.font;
    return self;
}
- (void)setText:(NSString *)text {
    _text = [text copy];
    dispatch_async(dispatch_get_main_queue(), ^{ self.view.text = text; });
}
- (void)setColor:(UIColor *)color {
    _color = color;
    dispatch_async(dispatch_get_main_queue(), ^{ self.view.textColor = color; });
}
- (void)setFont:(UIFont *)font {
    _font = font;
    dispatch_async(dispatch_get_main_queue(), ^{ self.view.font = font; });
}
@end


// ─────────────────────────────────────────────────────────────────────────────
// MARK: SKPanel
// ─────────────────────────────────────────────────────────────────────────────

@interface SKPanel : UIView

// ─── Appearance ──────────────────────────────────────────────────────────────

/// Text shown in the panel's drag bar. Default: @"Panel".
@property (nonatomic, copy)   NSString  *panelTitle;

/// SF Symbol shown left of panelTitle in the bar. Default: @"square.stack.3d.up.fill".
@property (nonatomic, copy)   NSString  *panelTitleSymbol;

/// Background color of the panel card. Default: SKColorBackground().
@property (nonatomic, strong) UIColor   *backgroundColor;

/// Corner radius. Default: 12.
@property (nonatomic, assign) CGFloat    cornerRadius;

// ─── Sizing ──────────────────────────────────────────────────────────────────

/// Panel width. Default: kSKPanelWidth (258).
@property (nonatomic, assign) CGFloat    panelWidth;

// ─── Builder API ─────────────────────────────────────────────────────────────

/// Adds a full-width button to the panel body.
///
/// @param title      Label text.
/// @param symbolName SF Symbol name (nil = text only).
/// @param color      Background fill.
/// @param action     Tap callback (main queue).
/// @return  The SKButton so you can keep a reference for later (e.g. disable it).
- (SKButton *)addButton:(NSString *)title
                 symbol:(NSString *)symbolName
                  color:(UIColor *)color
                 action:(SKActionBlock)action;

/// Adds a row of equally-spaced small buttons.
/// Pass an NSArray of SKButton instances.  They will share the row width.
///
/// Example:
///   [panel addSmallButtonsRow:@[
///       [SKButton buttonWithTitle:@"A" symbol:@"star"  color:SKColorBlue()  action:^{…}],
///       [SKButton buttonWithTitle:@"B" symbol:@"trash" color:SKColorRed()   action:^{…}],
///   ]];
- (void)addSmallButtonsRow:(NSArray<SKButton *> *)buttons;

/// Adds a 1 pt horizontal divider line.
- (void)addDivider;

/// Adds an info label identified by `key`.
///
/// @param key   Unique string so you can retrieve/update later.
/// @param text  Initial text.
/// @return  SKPanelLabel you can mutate at runtime.
- (SKPanelLabel *)addLabel:(NSString *)key text:(NSString *)text;

/// Updates the text of the label added with `key`. No-op if key not found.
- (void)setLabelText:(NSString *)text forKey:(NSString *)key;

/// Returns the SKPanelLabel for `key` (nil if not found).
- (SKPanelLabel *)labelForKey:(NSString *)key;

/// Adds any arbitrary UIView at a fixed `height`. Use for custom widgets.
- (void)addCustomView:(UIView *)view height:(CGFloat)height;

/// Adds a SKSettingsMenu — tapping the provided `title` button shows the menu.
/// A convenience so you don't have to wire up a button manually.
///
/// @param title   Button label (e.g. @"Settings").
/// @param menu    Pre-configured SKSettingsMenu instance.
/// @return  The trigger SKButton.
- (SKButton *)addSettingsButton:(NSString *)title menu:(SKSettingsMenu *)menu;

// ─── Lifecycle ───────────────────────────────────────────────────────────────

/// Adds the panel to `parent`, animated in.
/// Default position: top-right, 10 pt from edge, y = 88.
- (void)showInView:(UIView *)parent;

/// Adds the panel to `parent` at a specific center point.
- (void)showInView:(UIView *)parent center:(CGPoint)center;

/// Fades + scales out, then removes from superview.
/// Prompts with a UIAlertController first if `confirm` is YES.
- (void)hideWithConfirm:(BOOL)confirm;

/// Alias for hideWithConfirm:YES.
- (void)hide;

// ─── Expand / collapse ────────────────────────────────────────────────────────

/// Programmatically expand or collapse the body.
- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated;

@end


// ─────────────────────────────────────────────────────────────────────────────
// MARK: Implementation
// ─────────────────────────────────────────────────────────────────────────────

@implementation SKPanel {
    // Item list — each entry: NSDictionary with @"type" key
    NSMutableArray *_items;
    NSMutableDictionary<NSString *, SKPanelLabel *> *_labels;
    NSMutableDictionary<NSString *, SKButton *>     *_buttons;

    UIView   *_body;       // expandable content container
    BOOL      _expanded;
    NSTimer  *_expTimer;
    CGFloat   _computedBodyHeight;
}

// ── Init ──

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, kSKPanelWidth, kSKPanelBarHeight)];
    if (!self) return nil;
    _items             = [NSMutableArray new];
    _labels            = [NSMutableDictionary new];
    _buttons           = [NSMutableDictionary new];
    _panelTitle        = @"Panel";
    _panelTitleSymbol  = @"square.stack.3d.up.fill";
    _backgroundColor   = SKColorBackground();
    _cornerRadius      = 12;
    _panelWidth        = kSKPanelWidth;
    _expanded          = NO;
    return self;
}

// ── Builder ──

- (SKButton *)addButton:(NSString *)title
                 symbol:(NSString *)symbolName
                  color:(UIColor *)color
                 action:(SKActionBlock)action {
    SKButton *btn = [SKButton buttonWithTitle:title symbol:symbolName
                                        color:color action:action];
    NSString *key = [NSString stringWithFormat:@"btn_%lu", (unsigned long)_items.count];
    _buttons[key] = btn;
    [_items addObject:@{ @"type": @"button", @"key": key }];
    return btn;
}

- (void)addSmallButtonsRow:(NSArray<SKButton *> *)buttons {
    if (!buttons.count) return;
    NSMutableArray *keys = [NSMutableArray new];
    for (SKButton *btn in buttons) {
        NSString *key = [NSString stringWithFormat:@"sbtn_%lu_%lu",
                         (unsigned long)_items.count, (unsigned long)keys.count];
        _buttons[key] = btn;
        [keys addObject:key];
    }
    [_items addObject:@{ @"type": @"smallrow", @"keys": keys }];
}

- (void)addDivider {
    [_items addObject:@{ @"type": @"divider" }];
}

- (SKPanelLabel *)addLabel:(NSString *)key text:(NSString *)text {
    SKPanelLabel *lbl = [SKPanelLabel new];
    lbl.text = text;
    _labels[key] = lbl;
    [_items addObject:@{ @"type": @"label", @"key": key }];
    return lbl;
}

- (void)setLabelText:(NSString *)text forKey:(NSString *)key {
    _labels[key].text = text;
}

- (SKPanelLabel *)labelForKey:(NSString *)key {
    return _labels[key];
}

- (void)addCustomView:(UIView *)view height:(CGFloat)height {
    NSString *tag = [NSString stringWithFormat:@"custom_%lu", (unsigned long)_items.count];
    [_items addObject:@{ @"type": @"custom", @"view": view, @"height": @(height), @"tag": tag }];
}

- (SKButton *)addSettingsButton:(NSString *)title menu:(SKSettingsMenu *)menu {
    __unsafe_unretained SKPanel *ws   = self;
    __unsafe_unretained SKSettingsMenu *wm = menu;
    SKButton *btn = [self addButton:title
                             symbol:@"gearshape"
                              color:SKColorGray()
                             action:^{
        UIView *parent = [ws _topVC].view ?: ws.superview;
        if (parent) [wm showInView:parent];
    }];
    return btn;
}

// ── showInView ──

- (void)showInView:(UIView *)parent {
    [self showInView:parent
              center:CGPointMake(parent.bounds.size.width - _panelWidth/2 - 10, 88)];
}

- (void)showInView:(UIView *)parent center:(CGPoint)center {
    [self _buildUI];
    self.center = center;
    self.alpha  = 0;
    self.transform = CGAffineTransformMakeScale(0.88f, 0.88f);
    [parent addSubview:self];
    [parent bringSubviewToFront:self];
    [UIView animateWithDuration:0.25 delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.alpha = 1;
        self.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)hide { [self hideWithConfirm:YES]; }

- (void)hideWithConfirm:(BOOL)confirm {
    if (!confirm) {
        [_expTimer invalidate];
        [UIView animateWithDuration:0.2 animations:^{
            self.alpha = 0;
            self.transform = CGAffineTransformMakeScale(0.85f, 0.85f);
        } completion:^(BOOL __) { [self removeFromSuperview]; }];
        return;
    }
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Hide Panel"
                         message:@"The panel will be removed until the next app launch."
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Hide" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *_) { [self hideWithConfirm:NO]; }]];
    [[self _topVC] presentViewController:a animated:YES completion:nil];
}

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated {
    if (_expanded == expanded) return;
    _expanded = expanded;
    [self _animateExpansion:animated];
}

// ── Build UI ──

- (void)_buildUI {
    self.clipsToBounds      = NO;
    self.layer.cornerRadius = _cornerRadius;
    self.layer.shadowColor   = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.82;
    self.layer.shadowRadius  = 9;
    self.layer.shadowOffset  = CGSizeMake(0, 3);
    self.layer.zPosition     = 9999;
    // Explicitly set background on super's layer (self.backgroundColor is overridden by UIView)
    self.layer.backgroundColor = _backgroundColor.CGColor;

    [self _buildBar];
    [self _buildBody];
    [self addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(_onPan:)]];
}

- (void)_buildBar {
    // Drag handle
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(_panelWidth/2-20, 7, 40, 3)];
    h.backgroundColor    = [UIColor colorWithWhite:0.45 alpha:0.5];
    h.layer.cornerRadius = 1.5;
    [self addSubview:h];

    // Title icon
    if (_panelTitleSymbol) {
        UIImageView *icon = [[UIImageView alloc] initWithImage:SKSym(_panelTitleSymbol, 11)];
        icon.tintColor   = SKColorAccent();
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.frame       = CGRectMake(12, 14, 16, 16);
        [self addSubview:icon];
    }

    // Title label
    UILabel *t = [UILabel new];
    t.text          = _panelTitle;
    t.textColor     = [UIColor colorWithWhite:0.82 alpha:1];
    t.font          = [UIFont boldSystemFontOfSize:12];
    t.textAlignment = NSTextAlignmentCenter;
    t.frame         = CGRectMake(0, 14, _panelWidth, 18);
    t.userInteractionEnabled = NO;
    [self addSubview:t];

    // Transparent tap zone over the bar
    UIView *tz = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _panelWidth, kSKPanelBarHeight)];
    tz.backgroundColor = UIColor.clearColor;
    [tz addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(_toggleExpanded)]];
    [self addSubview:tz];
}

- (void)_buildBody {
    CGFloat w = _panelWidth - kSKPanelPad * 2;
    CGFloat y = 4; // padding at top of body

    _body = [[UIView alloc] initWithFrame:CGRectMake(0, kSKPanelBarHeight, _panelWidth, 0)];
    _body.hidden = YES; _body.alpha = 0; _body.clipsToBounds = YES;
    [self addSubview:_body];

    for (NSDictionary *item in _items) {
        NSString *type = item[@"type"];

        if ([type isEqualToString:@"button"]) {
            SKButton *skb = _buttons[item[@"key"]];
            skb.view.frame = CGRectMake(kSKPanelPad, y, w, kSKButtonHeight);
            [_body addSubview:skb.view];
            y += kSKButtonHeight + kSKPanelButtonGap;

        } else if ([type isEqualToString:@"smallrow"]) {
            NSArray *keys = item[@"keys"];
            NSUInteger n = keys.count;
            CGFloat gap  = 6.0f;
            CGFloat bw   = (w - gap * (n - 1)) / (CGFloat)n;
            CGFloat x    = kSKPanelPad;
            for (NSString *k in keys) {
                SKButton *skb = _buttons[k];
                skb.view.frame = CGRectMake(x, y, bw, kSKButtonHeightSm);
                [_body addSubview:skb.view];
                x += bw + gap;
            }
            y += kSKButtonHeightSm + kSKPanelButtonGap;

        } else if ([type isEqualToString:@"divider"]) {
            UIView *div = [[UIView alloc] initWithFrame:CGRectMake(kSKPanelPad, y + 2, w, 1)];
            div.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1];
            [_body addSubview:div];
            y += 9;

        } else if ([type isEqualToString:@"label"]) {
            SKPanelLabel *sl = _labels[item[@"key"]];
            sl.view.frame = CGRectMake(kSKPanelPad, y, w, 14);
            [_body addSubview:sl.view];
            y += 14 + 4;

        } else if ([type isEqualToString:@"custom"]) {
            UIView *cv = item[@"view"];
            CGFloat h  = [item[@"height"] floatValue];
            cv.frame   = CGRectMake(kSKPanelPad, y, w, h);
            cv.translatesAutoresizingMaskIntoConstraints = YES;
            [_body addSubview:cv];
            y += h + kSKPanelButtonGap;
        }
    }

    y += 4; // padding at bottom of body
    _computedBodyHeight = y;
}

// ── Expand / collapse ──

- (void)_toggleExpanded {
    _expanded = !_expanded;
    [self _animateExpansion:YES];
}

- (void)_animateExpansion:(BOOL)animated {
    if (_expanded) {
        _body.hidden = NO;
        _body.frame  = CGRectMake(0, kSKPanelBarHeight, _panelWidth, _computedBodyHeight);
        void (^anim)(void) = ^{
            CGRect f = self.frame;
            f.size.height = kSKPanelBarHeight + self->_computedBodyHeight;
            self.frame = f;
            self->_body.alpha = 1;
        };
        if (animated) {
            [UIView animateWithDuration:0.22 delay:0
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:anim completion:nil];
        } else { anim(); }
    } else {
        void (^anim)(void) = ^{
            CGRect f = self.frame;
            f.size.height = kSKPanelBarHeight;
            self.frame = f;
            self->_body.alpha = 0;
        };
        void (^done)(BOOL) = ^(BOOL __) { self->_body.hidden = YES; };
        if (animated) {
            [UIView animateWithDuration:0.18 delay:0
                                options:UIViewAnimationOptionCurveEaseIn
                             animations:anim completion:done];
        } else { anim(); done(YES); }
    }
}

// ── Drag ──

- (void)_onPan:(UIPanGestureRecognizer *)g {
    CGPoint d  = [g translationInView:self.superview];
    CGRect  sb = self.superview.bounds;
    CGFloat nx = MAX(self.bounds.size.width/2,
                     MIN(sb.size.width  - self.bounds.size.width/2,  self.center.x + d.x));
    CGFloat ny = MAX(self.bounds.size.height/2,
                     MIN(sb.size.height - self.bounds.size.height/2, self.center.y + d.y));
    self.center = CGPointMake(nx, ny);
    [g setTranslation:CGPointZero inView:self.superview];
}

// ── Helpers ──

- (UIViewController *)_topVC {
    UIViewController *vc = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows.reverseObjectEnumerator)
        if (!w.isHidden && w.alpha > 0 && w.rootViewController) { vc = w.rootViewController; break; }
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

@end
