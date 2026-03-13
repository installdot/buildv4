// SKButton.h — Standalone button builder
// Part of SKFramework · iOS 14+ · ARC
//
// SKButton wraps UIButton and exposes a fluent builder API.
// Used internally by SKPanel, but can also be created standalone and added
// to any UIView.
//
// Example — standalone:
//
//   SKButton *btn = [SKButton buttonWithTitle:@"Upload"
//                                      symbol:@"icloud.and.arrow.up"
//                                       color:SKColorBlue()
//                                      action:^{ NSLog(@"tapped"); }];
//   btn.frame = CGRectMake(20, 100, 220, 44);
//   [self.view addSubview:btn.view];

#pragma once
#import "SKTypes.h"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: SKButton
// ─────────────────────────────────────────────────────────────────────────────

@interface SKButton : NSObject

/// The underlying UIButton. Add this to your view hierarchy.
@property (nonatomic, readonly, strong) UIButton *view;

/// Label shown on the button.
@property (nonatomic, copy)   NSString      *title;
/// SF Symbol name shown left of the title.
@property (nonatomic, copy)   NSString      *symbolName;
/// Background fill color.
@property (nonatomic, strong) UIColor       *color;
/// Called on the main queue when the button is tapped.
@property (nonatomic, copy)   SKActionBlock  action;
/// Corner radius. Default: 9.
@property (nonatomic, assign) CGFloat        cornerRadius;
/// Font size for the title. Default: 13 (bold).
@property (nonatomic, assign) CGFloat        fontSize;
/// When YES the button cannot be tapped (dimmed to 50% alpha). Default: NO.
@property (nonatomic, assign, getter=isDisabled) BOOL disabled;

// ─────────────────────────────────────────────────────────────────────────────
// Factory
// ─────────────────────────────────────────────────────────────────────────────

/// Creates a fully configured button.
/// @param title      Label text (leading spaces added automatically).
/// @param symbolName SF Symbol name (e.g. @"icloud.and.arrow.up"). Pass nil for text-only.
/// @param color      Background fill.
/// @param action     Tap callback (main queue).
+ (instancetype)buttonWithTitle:(NSString *)title
                         symbol:(NSString *)symbolName
                          color:(UIColor *)color
                         action:(SKActionBlock)action;

/// Creates a button with the default grey color and no symbol.
+ (instancetype)buttonWithTitle:(NSString *)title action:(SKActionBlock)action;

// ─────────────────────────────────────────────────────────────────────────────
// Mutators (call before adding .view to hierarchy, or call -refresh after)
// ─────────────────────────────────────────────────────────────────────────────

/// Re-applies all properties to the underlying UIButton.
/// Call after changing title / color / disabled state at runtime.
- (void)refresh;

@end


// ─────────────────────────────────────────────────────────────────────────────
// MARK: SKButton — Implementation (header-only, static)
// ─────────────────────────────────────────────────────────────────────────────

@implementation SKButton {
    UIButton     *_btn;
    SKActionBlock _action;
}

+ (instancetype)buttonWithTitle:(NSString *)title
                         symbol:(NSString *)sym
                          color:(UIColor *)color
                         action:(SKActionBlock)action {
    SKButton *b    = [SKButton new];
    b.title        = title;
    b.symbolName   = sym;
    b.color        = color ?: SKColorGray();
    b.action       = action;
    b.cornerRadius = 9;
    b.fontSize     = 13;
    [b _buildView];
    return b;
}

+ (instancetype)buttonWithTitle:(NSString *)title action:(SKActionBlock)action {
    return [self buttonWithTitle:title symbol:nil color:SKColorGray() action:action];
}

- (void)_buildView {
    _btn = [UIButton buttonWithType:UIButtonTypeCustom];
    _btn.backgroundColor    = _color;
    _btn.layer.cornerRadius = _cornerRadius;
    _btn.clipsToBounds      = YES;
    _btn.translatesAutoresizingMaskIntoConstraints = NO;

    if (_symbolName) {
        UIImageSymbolConfiguration *cfg =
            [UIImageSymbolConfiguration configurationWithPointSize:12
                                                            weight:UIImageSymbolWeightMedium];
        UIImage *img = [[UIImage systemImageNamed:_symbolName withConfiguration:cfg]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [_btn setImage:img forState:UIControlStateNormal];
        _btn.tintColor = [UIColor whiteColor];
    }

    NSString *label = _symbolName ? [NSString stringWithFormat:@"  %@", _title] : _title;
    [_btn setTitle:label forState:UIControlStateNormal];
    [_btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_btn setTitleColor:[UIColor colorWithWhite:0.70 alpha:1] forState:UIControlStateHighlighted];
    _btn.titleLabel.font = [UIFont boldSystemFontOfSize:_fontSize];

    // UIButton does not retain its target, so passing self directly is safe here.
    [_btn addTarget:self action:@selector(_tapped) forControlEvents:UIControlEventTouchUpInside];
}

- (UIButton *)view { return _btn; }

- (void)setAction:(SKActionBlock)action { _action = [action copy]; }
- (SKActionBlock)action { return _action; }

- (void)_tapped { if (_action) _action(); }

- (void)refresh {
    _btn.backgroundColor    = _color;
    _btn.layer.cornerRadius = _cornerRadius;
    _btn.alpha              = _disabled ? 0.50f : 1.0f;
    _btn.userInteractionEnabled = !_disabled;

    if (_symbolName) {
        UIImageSymbolConfiguration *cfg =
            [UIImageSymbolConfiguration configurationWithPointSize:12
                                                            weight:UIImageSymbolWeightMedium];
        UIImage *img = [[UIImage systemImageNamed:_symbolName withConfiguration:cfg]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [_btn setImage:img forState:UIControlStateNormal];
    } else {
        [_btn setImage:nil forState:UIControlStateNormal];
    }

    NSString *label = _symbolName ? [NSString stringWithFormat:@"  %@", _title] : _title;
    [_btn setTitle:label forState:UIControlStateNormal];
    _btn.titleLabel.font = [UIFont boldSystemFontOfSize:_fontSize];
}

- (void)setDisabled:(BOOL)disabled {
    _disabled = disabled;
    _btn.alpha               = disabled ? 0.50f : 1.0f;
    _btn.userInteractionEnabled = !disabled;
}

@end
