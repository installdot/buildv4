// SKOverlays.h — Progress overlay, auth overlay, alert helpers
// Part of SKFramework · iOS 14+ · ARC
//
// Provides:
//   SKProgressOverlay  — animated progress card with scrollable log
//   SKAlert            — quick UIAlertController builder helpers

#pragma once
#import "SKTypes.h"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: SKProgressOverlay
//
// A full-screen semi-transparent overlay with a dark card containing:
//   • Title row  (SF Symbol + text)
//   • Progress bar + percentage
//   • Scrollable green-on-dark log view
//   • "Open Link in Browser" button  (shown only when a link is supplied)
//   • "Close" button                 (shown when operation finishes)
//
// ── Usage ────────────────────────────────────────────────────────────────────
//
//   SKProgressOverlay *ov = [SKProgressOverlay showInView:root
//                                                   title:@"Uploading save…"];
//   [ov setProgress:0.3 label:@"30%"];
//   [ov appendLog:@"Uploading game.data"];
//   [ov finish:YES message:@"Done!" link:@"https://…/view"];
// ─────────────────────────────────────────────────────────────────────────────

@interface SKProgressOverlay : UIView

/// Title text at the top of the card (set via showInView:title:).
@property (nonatomic, strong) UILabel        *titleLabel;
/// Horizontal progress bar. Range 0–1.
@property (nonatomic, strong) UIProgressView *bar;
/// Right-aligned percentage / status label.
@property (nonatomic, strong) UILabel        *percentLabel;
/// Monospaced green scrollable log.
@property (nonatomic, strong) UITextView     *logView;
/// Close button (hidden until -finish: is called).
@property (nonatomic, strong) UIButton       *closeBtn;
/// "Open Link in Browser" button (hidden unless link is non-empty in finish:).
@property (nonatomic, strong) UIButton       *openLinkBtn;
/// URL string last passed to finish:message:link:.
@property (nonatomic, copy)   NSString       *uploadedLink;

/// Creates and presents the overlay inside `parent`. Fades in over 0.2 s.
+ (instancetype)showInView:(UIView *)parent title:(NSString *)title;

/// Updates progress bar and label text.
/// @param p      0.0–1.0 (clamped).
/// @param label  Override string (nil = auto "XX%").
- (void)setProgress:(float)p label:(NSString *)label;

/// Appends a timestamped line to the log and scrolls to bottom.
- (void)appendLog:(NSString *)msg;

/// Marks operation complete.
/// @param success  Controls bar / label colour.
/// @param msg      Final log line (nil = skip).
/// @param link     If non-empty, shows "Open in Browser" button.
- (void)finish:(BOOL)success message:(NSString *)msg link:(NSString *)link;

@end

@implementation SKProgressOverlay

+ (instancetype)showInView:(UIView *)parent title:(NSString *)title {
    SKProgressOverlay *o = [[SKProgressOverlay alloc] initWithFrame:parent.bounds];
    o.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [parent addSubview:o];
    [o _setup:title];
    o.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ o.alpha = 1; }];
    return o;
}

- (void)_setup:(NSString *)title {
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];

    UIView *card = [UIView new];
    card.backgroundColor     = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1];
    card.layer.cornerRadius  = 18;
    card.layer.shadowColor   = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.85;
    card.layer.shadowRadius  = 18;
    card.layer.shadowOffset  = CGSizeMake(0, 6);
    card.clipsToBounds       = NO;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:card];

    UIColor *green = [UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];

    UIImageView *titleIcon = SKSymView(@"icloud.and.arrow.up", 13, green);

    self.titleLabel = [UILabel new];
    self.titleLabel.text          = title;
    self.titleLabel.textColor     = [UIColor whiteColor];
    self.titleLabel.font          = [UIFont boldSystemFontOfSize:14];
    self.titleLabel.textAlignment = NSTextAlignmentLeft;
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *titleRow = [[UIStackView alloc] initWithArrangedSubviews:@[titleIcon, self.titleLabel]];
    titleRow.axis    = UILayoutConstraintAxisHorizontal;
    titleRow.spacing = 7;
    titleRow.alignment = UIStackViewAlignmentCenter;
    titleRow.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:titleRow];

    self.bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.bar.trackTintColor    = [UIColor colorWithWhite:0.22 alpha:1];
    self.bar.progressTintColor = green;
    self.bar.layer.cornerRadius = 3; self.bar.clipsToBounds = YES; self.bar.progress = 0;
    self.bar.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.bar];

    self.percentLabel = [UILabel new];
    self.percentLabel.text          = @"0%";
    self.percentLabel.textColor     = [UIColor colorWithWhite:0.55 alpha:1];
    self.percentLabel.font          = [UIFont boldSystemFontOfSize:11];
    self.percentLabel.textAlignment = NSTextAlignmentRight;
    self.percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.percentLabel];

    self.logView = [UITextView new];
    self.logView.backgroundColor    = [UIColor colorWithWhite:0.04 alpha:1];
    self.logView.textColor          = [UIColor colorWithRed:0.42 green:0.98 blue:0.58 alpha:1];
    self.logView.font               = [UIFont fontWithName:@"Courier" size:10] ?: [UIFont systemFontOfSize:10];
    self.logView.editable           = NO; self.logView.selectable = NO;
    self.logView.layer.cornerRadius = 8; self.logView.text = @"";
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.logView];

    // Open-link button
    UIButton *linkBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    linkBtn.backgroundColor    = [UIColor colorWithRed:0.16 green:0.52 blue:0.92 alpha:1];
    linkBtn.layer.cornerRadius = 9;
    UIImage *safariImg = [[UIImage systemImageNamed:@"safari"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14
        weight:UIImageSymbolWeightMedium]] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [linkBtn setImage:safariImg forState:UIControlStateNormal];
    linkBtn.tintColor = [UIColor whiteColor];
    [linkBtn setTitle:@"  Open Link in Browser" forState:UIControlStateNormal];
    [linkBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    linkBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    linkBtn.translatesAutoresizingMaskIntoConstraints = NO;
    linkBtn.hidden = YES;
    [linkBtn addTarget:self action:@selector(_openLink) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:linkBtn];
    self.openLinkBtn = linkBtn;

    // Close button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.backgroundColor    = [UIColor colorWithWhite:0.20 alpha:1];
    closeBtn.layer.cornerRadius = 9;
    UIImage *xImg = [[UIImage systemImageNamed:@"xmark"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14
        weight:UIImageSymbolWeightMedium]] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [closeBtn setImage:xImg forState:UIControlStateNormal];
    closeBtn.tintColor = [UIColor whiteColor];
    [closeBtn setTitle:@"  Close" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    closeBtn.hidden = YES;
    [closeBtn addTarget:self action:@selector(_dismiss) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:closeBtn];
    self.closeBtn = closeBtn;

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:310],
        [titleRow.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
        [titleRow.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [titleIcon.widthAnchor constraintEqualToConstant:18],
        [titleIcon.heightAnchor constraintEqualToConstant:18],
        [self.bar.topAnchor constraintEqualToAnchor:titleRow.bottomAnchor constant:14],
        [self.bar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.bar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-72],
        [self.bar.heightAnchor constraintEqualToConstant:6],
        [self.percentLabel.centerYAnchor constraintEqualToAnchor:self.bar.centerYAnchor],
        [self.percentLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [self.percentLabel.widthAnchor constraintEqualToConstant:54],
        [self.logView.topAnchor constraintEqualToAnchor:self.bar.bottomAnchor constant:10],
        [self.logView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [self.logView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [self.logView.heightAnchor constraintEqualToConstant:170],
        [self.openLinkBtn.topAnchor constraintEqualToAnchor:self.logView.bottomAnchor constant:10],
        [self.openLinkBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [self.openLinkBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [self.openLinkBtn.heightAnchor constraintEqualToConstant:42],
        [self.closeBtn.topAnchor constraintEqualToAnchor:self.openLinkBtn.bottomAnchor constant:8],
        [self.closeBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [self.closeBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [self.closeBtn.heightAnchor constraintEqualToConstant:38],
        [card.bottomAnchor constraintEqualToAnchor:self.closeBtn.bottomAnchor constant:18],
    ]];
}

- (void)setProgress:(float)p label:(NSString *)label {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.bar setProgress:MAX(0, MIN(1, p)) animated:YES];
        self.percentLabel.text = label ?: [NSString stringWithFormat:@"%.0f%%", p * 100];
    });
}

- (void)appendLog:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"HH:mm:ss";
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                          [f stringFromDate:[NSDate date]], msg];
        self.logView.text = [self.logView.text stringByAppendingString:line];
        if (self.logView.text.length)
            [self.logView scrollRangeToVisible:
                NSMakeRange(self.logView.text.length - 1, 1)];
    });
}

- (void)finish:(BOOL)ok message:(NSString *)msg link:(NSString *)link {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setProgress:1.0 label:ok ? @"Done" : @"Failed"];
        self.percentLabel.textColor = ok
            ? [UIColor colorWithRed:0.25 green:0.88 blue:0.45 alpha:1]
            : [UIColor colorWithRed:0.90 green:0.28 blue:0.28 alpha:1];
        if (msg.length) [self appendLog:msg];
        self.uploadedLink = link;
        if (link.length) self.openLinkBtn.hidden = NO;
        self.closeBtn.hidden = NO;
        self.closeBtn.backgroundColor = ok
            ? [UIColor colorWithWhite:0.22 alpha:1]
            : [UIColor colorWithRed:0.55 green:0.14 blue:0.14 alpha:1];
    });
}

- (void)_openLink {
    NSURL *url = [NSURL URLWithString:self.uploadedLink];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)_dismiss {
    [UIView animateWithDuration:0.18 animations:^{ self.alpha = 0; }
                     completion:^(BOOL _){ [self removeFromSuperview]; }];
}

@end


// ─────────────────────────────────────────────────────────────────────────────
// MARK: SKAlert  (convenience helpers — no subclass needed)
// ─────────────────────────────────────────────────────────────────────────────

@interface SKAlert : NSObject

/// Shows a simple OK alert from the top-most view controller.
+ (void)showTitle:(NSString *)title message:(NSString *)msg;

/// Shows a destructive confirmation dialog.
/// @param confirmTitle  Label of the confirm button.
/// @param onConfirm     Called if user taps confirm (main queue).
+ (void)showConfirmTitle:(NSString *)title
                 message:(NSString *)msg
            confirmTitle:(NSString *)confirmTitle
               onConfirm:(SKActionBlock)onConfirm;

@end

@implementation SKAlert

+ (UIViewController *)_topVC {
    UIViewController *vc = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows.reverseObjectEnumerator)
        if (!w.isHidden && w.alpha > 0 && w.rootViewController) { vc = w.rootViewController; break; }
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

+ (void)showTitle:(NSString *)title message:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [[self _topVC] presentViewController:a animated:YES completion:nil];
}

+ (void)showConfirmTitle:(NSString *)title message:(NSString *)msg
            confirmTitle:(NSString *)confirmTitle onConfirm:(SKActionBlock)onConfirm {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:confirmTitle
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) { if (onConfirm) onConfirm(); }]];
    [[self _topVC] presentViewController:a animated:YES completion:nil];
}

@end
