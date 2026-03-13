// SKTypes.h — Shared types, color palette, layout constants
// Part of SKFramework · iOS 14+ · ARC
//
// Import this first. Every other SKFramework header imports it automatically
// via SKPanel.h / SKSettingsMenu.h.

#pragma once
#import <UIKit/UIKit.h>

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Block typedefs
// ─────────────────────────────────────────────────────────────────────────────

/// Simple tap action — used for panel buttons and settings rows.
typedef void (^SKActionBlock)(void);

/// Toggle-changed action — passed (newValue).
typedef void (^SKToggleBlock)(BOOL isOn);

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Layout constants
// ─────────────────────────────────────────────────────────────────────────────

/// Default panel width in points.
static const CGFloat kSKPanelWidth       = 258.0f;
/// Height of the always-visible drag bar at the top of the panel.
static const CGFloat kSKPanelBarHeight   =  46.0f;
/// Vertical padding between panel buttons.
static const CGFloat kSKPanelButtonGap   =   6.0f;
/// Horizontal inset for panel buttons.
static const CGFloat kSKPanelPad         =   9.0f;
/// Default height of a standard panel button.
static const CGFloat kSKButtonHeight     =  44.0f;
/// Default height of a small (half-width) panel button.
static const CGFloat kSKButtonHeightSm   =  32.0f;

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Built-in color palette  (UIColor factory helpers)
// ─────────────────────────────────────────────────────────────────────────────

/// Dark blue — default for action/upload buttons.
static inline UIColor *SKColorBlue(void) {
    return [UIColor colorWithRed:0.14 green:0.52 blue:0.92 alpha:1];
}
/// Green — default for confirm/load buttons.
static inline UIColor *SKColorGreen(void) {
    return [UIColor colorWithRed:0.18 green:0.70 blue:0.42 alpha:1];
}
/// Red — destructive / error states.
static inline UIColor *SKColorRed(void) {
    return [UIColor colorWithRed:0.75 green:0.18 blue:0.18 alpha:1];
}
/// Muted grey — secondary buttons (Settings, Hide, etc.).
static inline UIColor *SKColorGray(void) {
    return [UIColor colorWithRed:0.22 green:0.22 blue:0.30 alpha:1];
}
/// Amber — warnings, expiry timers.
static inline UIColor *SKColorAmber(void) {
    return [UIColor colorWithRed:0.85 green:0.70 blue:0.20 alpha:1];
}
/// Panel / card background.
static inline UIColor *SKColorBackground(void) {
    return [UIColor colorWithRed:0.06 green:0.06 blue:0.09 alpha:0.97];
}
/// Row background inside settings menu.
static inline UIColor *SKColorRowBg(void) {
    return [UIColor colorWithRed:0.12 green:0.12 blue:0.18 alpha:1];
}
/// Accent green used for status text and switch tint.
static inline UIColor *SKColorAccent(void) {
    return [UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:1];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: SF Symbol image helpers  (iOS 13+)
// ─────────────────────────────────────────────────────────────────────────────

/// Returns an SF Symbol UIImage at `ptSize` with medium weight.
static inline UIImage *SKSym(NSString *name, CGFloat ptSize) {
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:ptSize
                                                        weight:UIImageSymbolWeightMedium];
    return [UIImage systemImageNamed:name withConfiguration:cfg];
}

/// Returns a tinted UIImageView from an SF Symbol. Auto-layout ready.
static inline UIImageView *SKSymView(NSString *name, CGFloat ptSize, UIColor *tint) {
    UIImageView *v = [[UIImageView alloc] initWithImage:SKSym(name, ptSize)];
    v.tintColor   = tint;
    v.contentMode = UIViewContentModeScaleAspectFit;
    v.translatesAutoresizingMaskIntoConstraints = NO;
    return v;
}
