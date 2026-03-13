// SKSettingsMenu.h — Dynamic settings menu builder
// Part of SKFramework · iOS 14+ · ARC
//
// Build a settings card by adding toggle rows and button rows one at a time.
// Every row is identified by a unique key string.
//
// ── Minimal example ──────────────────────────────────────────────────────────
//
//   SKSettingsMenu *menu = [SKSettingsMenu new];
//
//   [menu addToggle:@"autoClose"
//             title:@"Auto Close"
//       description:@"Exit the app after loading from cloud."
//            symbol:@"power"
//          onChange:^(BOOL on) { NSLog(@"autoClose → %d", on); }];
//
//   [menu addToggle:@"autoRij"
//             title:@"Auto Rij"
//       description:@"Patches OpenRijTest_ flags to 0 before upload."
//            symbol:@"wand.and.stars"
//          onChange:nil];   // nil = just persist to NSUserDefaults
//
//   [menu addButtonRow:@"clearCache"
//               title:@"Clear Cache"
//              symbol:@"trash"
//               color:SKColorRed()
//              action:^{ /* … */ }];
//
//   [menu showInView:self.view];
//
// ── Accessing current value of a toggle ──────────────────────────────────────
//
//   BOOL on = [menu boolForKey:@"autoClose"];
//   [menu setBool:YES forKey:@"autoClose"];   // also flips the UISwitch live
//
// ── Sections ─────────────────────────────────────────────────────────────────
//
//   [menu addSectionHeader:@"Advanced"];
//   [menu addToggle: … ];

#pragma once
#import "SKTypes.h"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: SKSettingToggleRow  (internal model — you don't create these directly)
// ─────────────────────────────────────────────────────────────────────────────

/// Describes one toggle row in the settings menu.
@interface SKSettingToggleRow : NSObject
@property (nonatomic, copy)   NSString      *key;         ///< NSUserDefaults key
@property (nonatomic, copy)   NSString      *title;       ///< Row label
@property (nonatomic, copy)   NSString      *descText;    ///< Sub-label (2 lines max)
@property (nonatomic, copy)   NSString      *symbolName;  ///< SF Symbol for the icon
@property (nonatomic, copy)   SKToggleBlock  onChange;    ///< Called after value changes (may be nil)
@property (nonatomic, assign) BOOL           defaultValue;///< Used when no persisted value exists
@end

@implementation SKSettingToggleRow
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: SKSettingButtonRow  (internal model)
// ─────────────────────────────────────────────────────────────────────────────

/// Describes one button row in the settings menu.
@interface SKSettingButtonRow : NSObject
@property (nonatomic, copy)   NSString      *key;
@property (nonatomic, copy)   NSString      *title;
@property (nonatomic, copy)   NSString      *symbolName;
@property (nonatomic, strong) UIColor       *color;
@property (nonatomic, copy)   SKActionBlock  action;
@end

@implementation SKSettingButtonRow
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: SKSettingsMenu
// ─────────────────────────────────────────────────────────────────────────────

@interface SKSettingsMenu : UIView

// ─── Title (optional — default: "Settings") ──────────────────────────────────

/// Header title shown at the top of the card. Default: @"Settings".
@property (nonatomic, copy) NSString *menuTitle;

/// Footer note shown at the bottom (version info etc.). Default: nil (hidden).
@property (nonatomic, copy) NSString *footerText;

// ─── Builder API ─────────────────────────────────────────────────────────────

/// Adds a section header label (non-interactive divider with text).
/// Sections are rendered in the order they are added.
- (void)addSectionHeader:(NSString *)title;

/// Adds a toggle row.
///
/// @param key          NSUserDefaults key. Value is auto-loaded and auto-saved.
/// @param title        Bold row label.
/// @param description  Smaller sub-label (pass nil to hide).
/// @param symbolName   SF Symbol name (pass nil to hide icon).
/// @param defaultValue Used if no value is persisted yet.
/// @param onChange     Called on main queue after the user flips the switch.
///                     Pass nil to only persist without a callback.
- (void)addToggle:(NSString *)key
            title:(NSString *)title
      description:(NSString *)description
           symbol:(NSString *)symbolName
     defaultValue:(BOOL)defaultValue
         onChange:(SKToggleBlock)onChange;

/// Convenience — default value is NO.
- (void)addToggle:(NSString *)key
            title:(NSString *)title
      description:(NSString *)description
           symbol:(NSString *)symbolName
         onChange:(SKToggleBlock)onChange;

/// Adds a standalone action button inside the settings card.
/// Useful for "Clear Cache", "Log Out", "Reset", etc.
- (void)addButtonRow:(NSString *)key
               title:(NSString *)title
              symbol:(NSString *)symbolName
               color:(UIColor *)color
              action:(SKActionBlock)action;

// ─── Runtime value access ─────────────────────────────────────────────────────

/// Returns the current persisted BOOL value for `key`.
- (BOOL)boolForKey:(NSString *)key;

/// Sets the persisted BOOL value for `key` and updates the live UISwitch if visible.
- (void)setBool:(BOOL)value forKey:(NSString *)key;

// ─── Presentation ─────────────────────────────────────────────────────────────

/// Builds the card UI and presents it as a subview of `parent`.
/// The card is positioned at center and can be panned freely.
/// Tapping outside the card dismisses it.
/// Returns self so you can chain: [[SKSettingsMenu new] showInView:v]
- (instancetype)showInView:(UIView *)parent;

/// Animates the card out and removes it from its superview.
- (void)dismiss;

// ─── Reference views for tutorial / spotlight ─────────────────────────────────

/// Returns the row UIView for `key` (nil if not found).
/// Use this to spotlight a specific row in SKTutorialOverlay or similar.
- (UIView *)rowViewForKey:(NSString *)key;

@end


// ─────────────────────────────────────────────────────────────────────────────
// MARK: Implementation
// ─────────────────────────────────────────────────────────────────────────────

@implementation SKSettingsMenu {
    // Ordered item list: items are NSDictionary with @"type" → @"toggle"/@"button"/@"header"
    NSMutableArray  *_items;       // holds SKSettingToggleRow / SKSettingButtonRow / NSString
    NSMutableDictionary<NSString *, UIView *> *_rowViews;    // key → row UIView
    NSMutableDictionary<NSString *, UISwitch *> *_switches;  // key → UISwitch
    UIView          *_card;
}

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _items     = [NSMutableArray new];
    _rowViews  = [NSMutableDictionary new];
    _switches  = [NSMutableDictionary new];
    _menuTitle = @"Settings";
    return self;
}

// ── Builder ──

- (void)addSectionHeader:(NSString *)title {
    [_items addObject:@{ @"type": @"header", @"title": title ?: @"" }];
}

- (void)addToggle:(NSString *)key title:(NSString *)title
      description:(NSString *)description symbol:(NSString *)symbolName
     defaultValue:(BOOL)defaultValue onChange:(SKToggleBlock)onChange {
    SKSettingToggleRow *row = [SKSettingToggleRow new];
    row.key          = key;
    row.title        = title;
    row.descText     = description;
    row.symbolName   = symbolName;
    row.defaultValue = defaultValue;
    row.onChange     = onChange;
    [_items addObject:@{ @"type": @"toggle", @"row": row }];
}

- (void)addToggle:(NSString *)key title:(NSString *)title
      description:(NSString *)description symbol:(NSString *)symbolName
         onChange:(SKToggleBlock)onChange {
    [self addToggle:key title:title description:description
             symbol:symbolName defaultValue:NO onChange:onChange];
}

- (void)addButtonRow:(NSString *)key title:(NSString *)title
              symbol:(NSString *)symbolName color:(UIColor *)color action:(SKActionBlock)action {
    SKSettingButtonRow *row = [SKSettingButtonRow new];
    row.key        = key;
    row.title      = title;
    row.symbolName = symbolName;
    row.color      = color ?: SKColorGray();
    row.action     = action;
    [_items addObject:@{ @"type": @"button", @"row": row }];
}

// ── Value access ──

- (BOOL)boolForKey:(NSString *)key {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
    UISwitch *sw = _switches[key];
    if (sw) sw.on = value;
}

// ── rowViewForKey ──

- (UIView *)rowViewForKey:(NSString *)key {
    return _rowViews[key];
}

// ── Presentation ──

- (instancetype)showInView:(UIView *)parent {
    self.frame = parent.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundColor  = [UIColor colorWithWhite:0 alpha:0.68];
    [parent addSubview:self];
    [self _buildCard];
    self.alpha = 0;
    [UIView animateWithDuration:0.22 animations:^{ self.alpha = 1; }];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(_bgTap:)];
    tap.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tap];
    return self;
}

- (void)dismiss {
    [UIView animateWithDuration:0.18 animations:^{ self.alpha = 0; }
                     completion:^(BOOL _){ [self removeFromSuperview]; }];
}

// ── Internal build ──

- (void)_bgTap:(UITapGestureRecognizer *)g {
    CGPoint pt = [g locationInView:self];
    if (_card && !CGRectContainsPoint(_card.frame, pt)) [self dismiss];
}

- (void)_buildCard {
    _card = [UIView new];
    _card.backgroundColor    = SKColorBackground();
    _card.layer.cornerRadius = 18;
    _card.clipsToBounds      = YES;
    _card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_card];

    // Drag handle
    UIView *handle = [UIView new];
    handle.backgroundColor    = [UIColor colorWithWhite:0.32 alpha:0.7];
    handle.layer.cornerRadius = 2;
    handle.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:handle];

    // Title row
    UIImageView *icon = SKSymView(@"gearshape.fill", 15, [UIColor colorWithWhite:0.70 alpha:1]);
    UILabel *titleL = [UILabel new];
    titleL.text      = _menuTitle;
    titleL.textColor = [UIColor whiteColor];
    titleL.font      = [UIFont boldSystemFontOfSize:15];
    titleL.textAlignment = NSTextAlignmentCenter;
    titleL.translatesAutoresizingMaskIntoConstraints = NO;
    UIStackView *titleRow = [[UIStackView alloc] initWithArrangedSubviews:@[icon, titleL]];
    titleRow.axis      = UILayoutConstraintAxisHorizontal;
    titleRow.spacing   = 6;
    titleRow.alignment = UIStackViewAlignmentCenter;
    titleRow.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:titleRow];

    // Divider
    UIView *div = [UIView new];
    div.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
    div.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:div];

    // Scroll wrapper
    UIScrollView *scroll = [UIScrollView new];
    scroll.showsVerticalScrollIndicator = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:scroll];

    UIView *content = [UIView new];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:content];

    // Build rows
    UIView *lastRow = nil;
    for (NSDictionary *item in _items) {
        NSString *type = item[@"type"];
        UIView *rowView = nil;

        if ([type isEqualToString:@"header"]) {
            rowView = [self _buildSectionHeader:item[@"title"]];
        } else if ([type isEqualToString:@"toggle"]) {
            SKSettingToggleRow *row = item[@"row"];
            rowView = [self _buildToggleRow:row];
            _rowViews[row.key] = rowView;
        } else if ([type isEqualToString:@"button"]) {
            SKSettingButtonRow *row = item[@"row"];
            rowView = [self _buildButtonRow:row];
            _rowViews[row.key] = rowView;
        }

        if (!rowView) continue;
        [content addSubview:rowView];

        NSLayoutConstraint *top = lastRow
            ? [rowView.topAnchor constraintEqualToAnchor:lastRow.bottomAnchor constant:7]
            : [rowView.topAnchor constraintEqualToAnchor:content.topAnchor constant:4];
        [NSLayoutConstraint activateConstraints:@[
            top,
            [rowView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [rowView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        ]];
        lastRow = rowView;
    }

    // Close button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.backgroundColor    = [UIColor colorWithWhite:0.20 alpha:1];
    closeBtn.layer.cornerRadius = 9;
    UIImage *xIcon = [[UIImage systemImageNamed:@"xmark"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12
        weight:UIImageSymbolWeightMedium]] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [closeBtn setImage:xIcon forState:UIControlStateNormal];
    closeBtn.tintColor = [UIColor whiteColor];
    [closeBtn setTitle:@"  Close" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [closeBtn addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:closeBtn];

    // Footer label
    UILabel *footer = nil;
    if (_footerText.length) {
        footer = [UILabel new];
        footer.text          = _footerText;
        footer.textColor     = [UIColor colorWithWhite:0.28 alpha:1];
        footer.font          = [UIFont systemFontOfSize:8.5];
        footer.textAlignment = NSTextAlignmentCenter;
        footer.numberOfLines = 1;
        footer.translatesAutoresizingMaskIntoConstraints = NO;
        [_card addSubview:footer];
    }

    // ── Constraints ──
    if (lastRow)
        [content.bottomAnchor constraintEqualToAnchor:lastRow.bottomAnchor constant:4].active = YES;
    else
        [content.bottomAnchor constraintEqualToAnchor:content.topAnchor].active = YES;

    NSMutableArray *cs = [NSMutableArray array];
    [cs addObjectsFromArray:@[
        [_card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_card.widthAnchor constraintEqualToConstant:320],
        [handle.topAnchor constraintEqualToAnchor:_card.topAnchor constant:8],
        [handle.centerXAnchor constraintEqualToAnchor:_card.centerXAnchor],
        [handle.widthAnchor constraintEqualToConstant:36],
        [handle.heightAnchor constraintEqualToConstant:4],
        [titleRow.topAnchor constraintEqualToAnchor:handle.bottomAnchor constant:8],
        [titleRow.centerXAnchor constraintEqualToAnchor:_card.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:18],
        [icon.heightAnchor constraintEqualToConstant:18],
        [div.topAnchor constraintEqualToAnchor:titleRow.bottomAnchor constant:10],
        [div.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:12],
        [div.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-12],
        [div.heightAnchor constraintEqualToConstant:1],
        [scroll.topAnchor constraintEqualToAnchor:div.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:10],
        [scroll.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],
        [scroll.heightAnchor constraintLessThanOrEqualToConstant:350],
        [content.topAnchor constraintEqualToAnchor:scroll.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:scroll.widthAnchor],
        [closeBtn.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:10],
        [closeBtn.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:14],
        [closeBtn.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-14],
        [closeBtn.heightAnchor constraintEqualToConstant:38],
    ]];

    if (footer) {
        [cs addObjectsFromArray:@[
            [footer.topAnchor constraintEqualToAnchor:closeBtn.bottomAnchor constant:10],
            [footer.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:8],
            [footer.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-8],
            [_card.bottomAnchor constraintEqualToAnchor:footer.bottomAnchor constant:14],
        ]];
    } else {
        [cs addObject:[_card.bottomAnchor constraintEqualToAnchor:closeBtn.bottomAnchor constant:18]];
    }
    [NSLayoutConstraint activateConstraints:cs];

    // Pan to reposition card
    [_card addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(_cardPan:)]];
}

- (UIView *)_buildSectionHeader:(NSString *)text {
    UILabel *label = [UILabel new];
    label.text          = text.uppercaseString;
    label.textColor     = [UIColor colorWithWhite:0.40 alpha:1];
    label.font          = [UIFont boldSystemFontOfSize:9.5];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *wrap = [UIView new];
    wrap.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:10],
        [label.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:6],
        [label.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor],
        [wrap.bottomAnchor constraintEqualToAnchor:label.bottomAnchor constant:2],
    ]];
    return wrap;
}

- (UIView *)_buildToggleRow:(SKSettingToggleRow *)row {
    UIView *wrap = [UIView new];
    wrap.backgroundColor    = SKColorRowBg();
    wrap.layer.cornerRadius = 10;
    wrap.clipsToBounds      = YES;
    wrap.translatesAutoresizingMaskIntoConstraints = NO;

    // Switch (scaled down)
    static const CGFloat kScale = 0.75f;
    UISwitch *sw = [UISwitch new];
    sw.onTintColor = SKColorAccent();
    sw.transform   = CGAffineTransformMakeScale(kScale, kScale);
    NSNumber *stored = [[NSUserDefaults standardUserDefaults] objectForKey:row.key];
    sw.on = stored ? stored.boolValue : row.defaultValue;
    if (!stored) [[NSUserDefaults standardUserDefaults] setBool:row.defaultValue forKey:row.key];
    sw.translatesAutoresizingMaskIntoConstraints = NO;
    _switches[row.key] = sw;

    // Container so scaled switch has correct hit target
    UIView *swCont = [UIView new];
    swCont.clipsToBounds = NO;
    swCont.translatesAutoresizingMaskIntoConstraints = NO;
    [swCont addSubview:sw];
    CGFloat sw_w = 51.0f * kScale, sw_h = 31.0f * kScale;
    sw.frame = CGRectMake((sw_w-51)*0.5f, (sw_h-31)*0.5f, 51, 31);
    [wrap addSubview:swCont];

    UIView *icon = row.symbolName
        ? SKSymView(row.symbolName, 13, [UIColor colorWithWhite:0.55 alpha:1])
        : nil;
    if (icon) [wrap addSubview:icon];

    UILabel *nameL = [UILabel new];
    nameL.text      = row.title;
    nameL.textColor = [UIColor whiteColor];
    nameL.font      = [UIFont boldSystemFontOfSize:12];
    nameL.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:nameL];

    UILabel *descL = nil;
    if (row.descText.length) {
        descL = [UILabel new];
        descL.text      = row.descText;
        descL.textColor = [UIColor colorWithWhite:0.45 alpha:1];
        descL.font      = [UIFont systemFontOfSize:9.5];
        descL.numberOfLines = 0;
        descL.translatesAutoresizingMaskIntoConstraints = NO;
        [wrap addSubview:descL];
    }

    CGFloat leadX = icon ? 36.0f : 12.0f;
    NSMutableArray *cs = [NSMutableArray array];
    [cs addObjectsFromArray:@[
        [swCont.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-12],
        [swCont.centerYAnchor constraintEqualToAnchor:wrap.centerYAnchor],
        [swCont.widthAnchor constraintEqualToConstant:sw_w],
        [swCont.heightAnchor constraintEqualToConstant:sw_h],
        [nameL.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:leadX],
        [nameL.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:10],
        [nameL.trailingAnchor constraintLessThanOrEqualToAnchor:swCont.leadingAnchor constant:-8],
    ]];
    if (icon) {
        [cs addObjectsFromArray:@[
            [icon.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:12],
            [icon.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:12],
            [icon.widthAnchor constraintEqualToConstant:16],
            [icon.heightAnchor constraintEqualToConstant:16],
        ]];
    }
    if (descL) {
        [cs addObjectsFromArray:@[
            [descL.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:leadX],
            [descL.topAnchor constraintEqualToAnchor:nameL.bottomAnchor constant:3],
            [descL.trailingAnchor constraintLessThanOrEqualToAnchor:swCont.leadingAnchor constant:-8],
            [wrap.bottomAnchor constraintEqualToAnchor:descL.bottomAnchor constant:10],
        ]];
    } else {
        [cs addObject:[wrap.bottomAnchor constraintEqualToAnchor:nameL.bottomAnchor constant:10]];
    }
    [NSLayoutConstraint activateConstraints:cs];

    // Wire up switch
    NSString *capturedKey = row.key;
    SKToggleBlock capturedCB = row.onChange;
    __weak SKSettingsMenu *ws = self;
    [sw addTarget:ws action:@selector(_switchTapped:) forControlEvents:UIControlEventValueChanged];
    objc_setAssociatedObject(sw, (void *)@"sk_key", capturedKey, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(sw, (void *)@"sk_cb",  capturedCB,  OBJC_ASSOCIATION_COPY_NONATOMIC);
    return wrap;
}

- (UIView *)_buildButtonRow:(SKSettingButtonRow *)row {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.backgroundColor    = row.color;
    btn.layer.cornerRadius = 9;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    if (row.symbolName) {
        UIImage *img = [[UIImage systemImageNamed:row.symbolName
            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12
            weight:UIImageSymbolWeightMedium]] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [btn setImage:img forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
    }
    [btn setTitle:[NSString stringWithFormat:@"  %@", row.title] forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    SKActionBlock capturedAction = row.action;
    objc_setAssociatedObject(btn, (void *)@"sk_action", capturedAction, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [btn addTarget:self action:@selector(_btnRowTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIView *wrap = [UIView new];
    wrap.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:btn];
    [NSLayoutConstraint activateConstraints:@[
        [btn.topAnchor constraintEqualToAnchor:wrap.topAnchor],
        [btn.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor],
        [btn.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor],
        [btn.heightAnchor constraintEqualToConstant:40],
        [wrap.bottomAnchor constraintEqualToAnchor:btn.bottomAnchor],
    ]];
    return wrap;
}

- (void)_switchTapped:(UISwitch *)sw {
    NSString *key = objc_getAssociatedObject(sw, (void *)@"sk_key");
    SKToggleBlock cb = objc_getAssociatedObject(sw, (void *)@"sk_cb");
    if (key) [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:key];
    [UIView animateWithDuration:0.07 animations:^{ sw.alpha = 0.25f; }
                     completion:^(BOOL _) {
        [UIView animateWithDuration:0.07 animations:^{ sw.alpha = 1.0f; }];
    }];
    if (cb) cb(sw.isOn);
}

- (void)_btnRowTapped:(UIButton *)btn {
    SKActionBlock action = objc_getAssociatedObject(btn, (void *)@"sk_action");
    if (action) action();
}

- (void)_cardPan:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        CGRect cur = _card.frame;
        for (NSLayoutConstraint *c in self.constraints)
            if (c.firstItem == _card || c.secondItem == _card) c.active = NO;
        _card.translatesAutoresizingMaskIntoConstraints = YES;
        _card.frame = cur;
    }
    CGPoint d = [g translationInView:self];
    CGRect f  = _card.frame;
    _card.frame = CGRectMake(
        MAX(0, MIN(self.bounds.size.width  - f.size.width,  f.origin.x + d.x)),
        MAX(0, MIN(self.bounds.size.height - f.size.height, f.origin.y + d.y)),
        f.size.width, f.size.height);
    [g setTranslation:CGPointZero inView:self];
}

@end
