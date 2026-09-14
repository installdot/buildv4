// TNMD Audition Auto Perfect - Unified Single Source Tweak.xm

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <math.h>
#include <unistd.h>
#include <fcntl.h>
#include <dlfcn.h>
#include <errno.h>
#include <sys/stat.h>
#include <mach-o/dyld.h>

#pragma mark - UIKit Compatibility Helpers
// Source: UI/F4CUIKitCompat.h



/*
 * UIKit compatibility helpers for the menu presentation layer.
 *
 * The project is built with deprecation warnings promoted to errors.  Avoid
 * direct references to deprecated application-window accessors and legacy UIButton inset
 * properties while preserving the existing UI behavior.
 */
static inline UIWindow *F4CActiveWindow(void) {
    UIApplication *application = UIApplication.sharedApplication;
    UIWindow *fallback = nil;

    /* iOS 13+ scene-aware lookup. Keep the project safe for an iOS 12 deployment target. */
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;

            UIWindowScene *windowScene = (UIWindowScene *)scene;
            BOOL foreground = (scene.activationState == UISceneActivationStateForegroundActive ||
                               scene.activationState == UISceneActivationStateForegroundInactive);

            for (UIWindow *window in windowScene.windows) {
                if (!window) continue;
                if (foreground && window.isKeyWindow) return window;

                if (!fallback && foreground && !window.hidden && window.alpha > 0.0 &&
                    window.windowLevel == UIWindowLevelNormal) {
                    fallback = window;
                }
            }
        }

        if (fallback) return fallback;

        /* Second pass: useful during scene transitions before activation settles. */
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (!window) continue;
                if (window.isKeyWindow) return window;
                if (!fallback && !window.hidden && window.alpha > 0.0 &&
                    window.windowLevel == UIWindowLevelNormal) {
                    fallback = window;
                }
            }
        }

        if (fallback) return fallback;
    }

    /* Compatibility fallback for apps that do not opt into UIScene lifecycle. */
    id<UIApplicationDelegate> delegate = application.delegate;
    SEL windowSelector = NSSelectorFromString(@"window");
    if (delegate && [delegate respondsToSelector:windowSelector]) {
        typedef UIWindow *(*F4CWindowGetter)(id, SEL);
        UIWindow *delegateWindow = ((F4CWindowGetter)objc_msgSend)(delegate, windowSelector);
        if (delegateWindow) return delegateWindow;
    }

    return nil;
}

static inline void F4CSetButtonInsets(UIButton *button,
                                      NSString *selectorName,
                                      UIEdgeInsets insets) {
    if (!button || selectorName.length == 0) return;
    SEL selector = NSSelectorFromString(selectorName);
    if (![button respondsToSelector:selector]) return;
    typedef void (*F4CSetInsetsFn)(id, SEL, UIEdgeInsets);
    ((F4CSetInsetsFn)objc_msgSend)(button, selector, insets);
}

static inline void F4CSetButtonContentInsets(UIButton *button, UIEdgeInsets insets) {
    F4CSetButtonInsets(button, @"setContentEdgeInsets:", insets);
}

static inline void F4CSetButtonImageInsets(UIButton *button, UIEdgeInsets insets) {
    F4CSetButtonInsets(button, @"setImageEdgeInsets:", insets);
}

static inline void F4CSetButtonTitleInsets(UIButton *button, UIEdgeInsets insets) {
    F4CSetButtonInsets(button, @"setTitleEdgeInsets:", insets);
}


#pragma mark - Embedded Logo Assets & Helper
// Source: UI/EmbeddedLogo.h


#ifdef __cplusplus
extern "C" {
#endif
extern const unsigned char F4CMenuLogoPNGStart[];
extern const unsigned char F4CMenuLogoPNGEnd[];
#ifdef __cplusplus
}
#endif

static UIImage *F4CMenuEmbeddedLogoImage(void) {
    static UIImage *image = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        @try {
            ptrdiff_t byteCount = (ptrdiff_t)(F4CMenuLogoPNGEnd - F4CMenuLogoPNGStart);
            if (byteCount > 0) {
                NSData *data = [[NSData alloc] initWithBytesNoCopy:(void *)F4CMenuLogoPNGStart
                                                             length:(NSUInteger)byteCount
                                                       freeWhenDone:NO];
                image = data ? [UIImage imageWithData:data] : nil;
            }
        } @catch (id ex) {}
    });
    return image;
}


#pragma mark - Gameplay / AutoPerfect Declarations
// Source: Gameplay/AuditionAutoPerfect.h


typedef void (^TNMDAutoPerfectUILogSink)(NSString *feature, NSString *state, NSString *reason);

FOUNDATION_EXPORT void TNMDAutoPerfectInitialize(void);
FOUNDATION_EXPORT void TNMDAutoPerfectSetUILogSink(TNMDAutoPerfectUILogSink sink);
FOUNDATION_EXPORT void TNMDAutoPerfectSetEnabled(BOOL enabled);
FOUNDATION_EXPORT void TNMDAutoPerfectSetArrowPacingEnabled(BOOL enabled);
FOUNDATION_EXPORT void TNMDAutoPerfectSetBeatJitterEnabled(BOOL enabled);
FOUNDATION_EXPORT void TNMDAutoPerfectSetBeatOneShotEnabled(BOOL enabled);
FOUNDATION_EXPORT void TNMDAutoPerfectSetArrowAckGateEnabled(BOOL enabled);
FOUNDATION_EXPORT BOOL TNMDAutoPerfectIsEnabled(void);
FOUNDATION_EXPORT NSString *TNMDAutoPerfectStatusText(void);
FOUNDATION_EXPORT NSString *TNMDAutoPerfectModeText(void);
FOUNDATION_EXPORT NSString *TNMDAutoPerfectBuildText(void);
FOUNDATION_EXPORT NSString *TNMDAutoPerfectLogDirectory(void);
FOUNDATION_EXPORT NSString *TNMDAutoPerfectDiagnosticText(void);
FOUNDATION_EXPORT void TNMDAutoPerfectSnapshotNow(void);
// Compatibility API: clears only CURRENT session logs. Previous/crash evidence is preserved.
FOUNDATION_EXPORT void TNMDAutoPerfectClearLogs(void);

// V10.22 Check Log / Diagnostic Center.
FOUNDATION_EXPORT NSArray<NSString *> *TNMDDiagnosticFeatureOptions(void);
FOUNDATION_EXPORT NSArray<NSString *> *TNMDDiagnosticSessionOptions(void);
FOUNDATION_EXPORT NSString *TNMDDiagnosticTopStatusText(void);
FOUNDATION_EXPORT NSString *TNMDDiagnosticFailureSummary(void);
FOUNDATION_EXPORT NSString *TNMDDiagnosticStageMapText(void);
FOUNDATION_EXPORT NSString *TNMDDiagnosticLoggerHealthText(void);
FOUNDATION_EXPORT NSString *TNMDDiagnosticTextForSelection(NSString *feature, NSString *session);
FOUNDATION_EXPORT NSString *TNMDDiagnosticRunSelfTest(void);
FOUNDATION_EXPORT NSString *TNMDDiagnosticExportFixPack(void);
FOUNDATION_EXPORT NSString *TNMDDiagnosticMarkBaselineGood(void);
FOUNDATION_EXPORT NSString *TNMDDiagnosticCompareBaseline(void);
FOUNDATION_EXPORT void TNMDDiagnosticRotateSession(void);

// V10.15 local-only cosmetic skin changer with per-slot pickers. No inventory/server ownership mutation.
FOUNDATION_EXPORT NSArray<NSDictionary *> *TNMDSkinSearchItems(NSInteger category, NSString *query, NSUInteger limit);
FOUNDATION_EXPORT BOOL TNMDSkinPreviewItem(uint32_t itemID, NSInteger category);
FOUNDATION_EXPORT BOOL TNMDSkinApplyItem(uint32_t itemID, NSInteger category);
FOUNDATION_EXPORT BOOL TNMDSkinRestoreOriginal(void);
FOUNDATION_EXPORT NSString *TNMDSkinStatusText(void);

// V10.19 local-only VIP visual. UI_VIPIcon/self billboard only; no ClientVIP/server entitlement mutation.
FOUNDATION_EXPORT NSArray<NSString *> *TNMDVIPVisualLevelOptions(void);
FOUNDATION_EXPORT BOOL TNMDVIPVisualSetLevel(NSInteger level);
FOUNDATION_EXPORT BOOL TNMDVIPVisualRestore(void);
FOUNDATION_EXPORT NSString *TNMDVIPVisualStatusText(void);

// V10.26 local-only head effects/title/ring preview. Self CharacterTop only; no ownership/server mutation.
FOUNDATION_EXPORT NSArray<NSString *> *TNMDHeadNameEffectOptions(void);
FOUNDATION_EXPORT NSArray<NSString *> *TNMDHeadTitleOptions(void);
FOUNDATION_EXPORT NSArray<NSString *> *TNMDHeadRingOptions(void);
FOUNDATION_EXPORT BOOL TNMDHeadReloadCatalogs(void);
FOUNDATION_EXPORT BOOL TNMDHeadNameEffectSet(NSInteger selectedIndex);
FOUNDATION_EXPORT BOOL TNMDHeadTitleSet(NSInteger selectedIndex);
FOUNDATION_EXPORT BOOL TNMDHeadTitleSetDynamic(BOOL enabled);
FOUNDATION_EXPORT BOOL TNMDHeadTitleClear(void);
FOUNDATION_EXPORT BOOL TNMDHeadRingSet(NSInteger selectedIndex);
FOUNDATION_EXPORT BOOL TNMDHeadRingClear(void);
FOUNDATION_EXPORT NSString *TNMDHeadOverlayStatusText(void);


#pragma mark - Floating Grabber View
// Source: UI/FloatingButton.h


/*
 * PullOver-style edge grabber.
 *
 * The class name stays unchanged so existing cleanup/integration code keeps
 * working, the edge grabber uses the embedded TNxMD avatar while preserving drawer gestures.
 * It reports two-axis drag progress to UIManager instead of moving itself.
 * UIManager locks each gesture to horizontal drawer motion or vertical
 * repositioning, so diagonal input never moves both at once.
 */
@interface FloatingButton : UIView <UIGestureRecognizerDelegate>

@property (nonatomic, strong) UIButton *mainButton;
@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic, copy) void (^onPanBegan)(void);
@property (nonatomic, copy) void (^onPanChanged)(CGPoint translation);
@property (nonatomic, copy) void (^onPanEnded)(CGPoint translation,
                                                   CGPoint velocity,
                                                   BOOL cancelled);
@property (nonatomic, assign, getter=isMenuPresented) BOOL menuPresented;

@property (nonatomic, assign, getter=isRightAnchored) BOOL rightAnchored;

+ (CGSize)preferredSize;
+ (instancetype)buttonWithFrame:(CGRect)frame;
- (void)makeDraggable;
- (void)cancelActivePan;
- (void)setMenuPresented:(BOOL)presented animated:(BOOL)animated;

@end

@implementation FloatingButton {
    UIPanGestureRecognizer *_horizontalPanGesture;
    UITapGestureRecognizer *_tapGesture;
    CAGradientLayer *_backgroundGradient;
    CAShapeLayer *_contentMask;
    CAShapeLayer *_borderLayer;
}

@synthesize menuPresented = _menuPresented;
@synthesize rightAnchored = _rightAnchored;

+ (CGSize)preferredSize {
    /* 34 pt visible tab inside a 44 pt minimum touch target. */
    return CGSizeMake(50.0, 44.0);
}

+ (instancetype)buttonWithFrame:(CGRect)frame {
    CGSize preferred = [self preferredSize];
    CGFloat width = frame.size.width > 0.0 ? frame.size.width : preferred.width;
    CGFloat height = frame.size.height > 0.0 ? frame.size.height : preferred.height;
    FloatingButton *grabber = [[FloatingButton alloc]
        initWithFrame:CGRectMake(frame.origin.x, frame.origin.y, width, height)];
    [grabber setup];
    return grabber;
}

- (void)setup {
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.clipsToBounds = NO;
    self.userInteractionEnabled = YES;
    self.layer.shadowColor =
        [UIColor colorWithRed:0.08 green:0.12 blue:0.24 alpha:0.35].CGColor;
    self.layer.shadowOffset = CGSizeMake(0.0, 4.0);
    self.layer.shadowOpacity = 1.0;
    self.layer.shadowRadius = 8.0;

    self.mainButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.mainButton.userInteractionEnabled = NO;
    self.mainButton.backgroundColor = UIColor.clearColor;
    UIImage *brandImage = F4CMenuEmbeddedLogoImage();
    if (brandImage) {
        [self.mainButton setImage:[brandImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]
                         forState:UIControlStateNormal];
        self.mainButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
        self.mainButton.imageEdgeInsets = UIEdgeInsetsMake(0.0, 8.0, 0.0, 8.0);
        [self.mainButton setTitle:nil forState:UIControlStateNormal];
        self.mainButton.accessibilityLabel = @"TNxMD menu";
    } else {
        [self.mainButton setTitle:@"TN" forState:UIControlStateNormal];
        self.mainButton.titleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightHeavy];
    }
    [self.mainButton addTarget:self
                        action:@selector(f4c_buttonTapped)
              forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.mainButton];

    _backgroundGradient = [CAGradientLayer layer];
    _backgroundGradient.startPoint = CGPointMake(0.0, 0.0);
    _backgroundGradient.endPoint = CGPointMake(1.0, 1.0);
    [self.mainButton.layer insertSublayer:_backgroundGradient atIndex:0];

    _contentMask = [CAShapeLayer layer];
    self.mainButton.layer.mask = _contentMask;

    _borderLayer = [CAShapeLayer layer];
    _borderLayer.fillColor = UIColor.clearColor.CGColor;
    _borderLayer.lineWidth = 1.2;
    [self.mainButton.layer addSublayer:_borderLayer];

    [self makeDraggable];
    [self f4c_updateAppearanceAnimated:NO];
    [self setNeedsLayout];
}

- (void)setRightAnchored:(BOOL)rightAnchored {
    if (_rightAnchored == rightAnchored) return;
    _rightAnchored = rightAnchored;
    [self f4c_updateAppearanceAnimated:NO];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat visibleHeight = MIN(34.0, self.bounds.size.height);
    CGFloat y = floor((self.bounds.size.height - visibleHeight) * 0.5);
    self.mainButton.frame = CGRectMake(0.0, y, self.bounds.size.width, visibleHeight);
    _backgroundGradient.frame = self.mainButton.bounds;

    CGFloat radius = visibleHeight * 0.5;
    UIRectCorner corners = _rightAnchored
        ? (UIRectCornerTopLeft | UIRectCornerBottomLeft)
        : (UIRectCornerTopRight | UIRectCornerBottomRight);

    UIBezierPath *path = [UIBezierPath
        bezierPathWithRoundedRect:self.mainButton.bounds
        byRoundingCorners:corners
        cornerRadii:CGSizeMake(radius, radius)];
    _contentMask.frame = self.mainButton.bounds;
    _contentMask.path = path.CGPath;
    _borderLayer.frame = self.mainButton.bounds;
    _borderLayer.path = path.CGPath;

    UIBezierPath *shadowPath = [path copy];
    [shadowPath applyTransform:CGAffineTransformMakeTranslation(0.0, y)];
    self.layer.shadowPath = shadowPath.CGPath;
}

- (void)f4c_updateAppearanceAnimated:(BOOL)animated {
    void (^changes)(void) = ^{
        if (self.isMenuPresented) {
            if ([self.mainButton imageForState:UIControlStateNormal]) {
                [self.mainButton setTitle:nil forState:UIControlStateNormal];
            }
            self->_backgroundGradient.colors = @[
                (id)[UIColor colorWithWhite:1.0 alpha:0.96].CGColor,
                (id)[UIColor colorWithRed:0.88 green:0.93 blue:0.98 alpha:0.94].CGColor
            ];
            self->_borderLayer.strokeColor =
                [UIColor colorWithRed:37.0/255.0 green:99.0/255.0 blue:235.0/255.0 alpha:0.65].CGColor;
        } else {
            if ([self.mainButton imageForState:UIControlStateNormal]) {
                [self.mainButton setTitle:nil forState:UIControlStateNormal];
            }
            self->_backgroundGradient.colors = @[
                (id)[UIColor colorWithWhite:1.0 alpha:0.95].CGColor,
                (id)[UIColor colorWithRed:0.90 green:0.94 blue:0.98 alpha:0.90].CGColor
            ];
            self->_borderLayer.strokeColor =
                [UIColor colorWithWhite:1.0 alpha:0.90].CGColor;
        }
    };

    if (animated) {
        [UIView transitionWithView:self.mainButton
                          duration:0.16
                           options:UIViewAnimationOptionTransitionCrossDissolve |
                                   UIViewAnimationOptionAllowUserInteraction
                        animations:changes
                        completion:nil];
    } else {
        changes();
    }
}

- (void)setMenuPresented:(BOOL)menuPresented {
    [self setMenuPresented:menuPresented animated:NO];
}

- (void)setMenuPresented:(BOOL)presented animated:(BOOL)animated {
    if (_menuPresented == presented) return;
    _menuPresented = presented;
    self.accessibilityValue = presented ? @"Open" : @"Closed";
    [self f4c_updateAppearanceAnimated:animated];
}

- (void)makeDraggable {
    if (_horizontalPanGesture || _tapGesture) return;

    _horizontalPanGesture = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(f4c_handlePan:)];
    _horizontalPanGesture.delegate = self;
    _horizontalPanGesture.maximumNumberOfTouches = 1;
    _horizontalPanGesture.cancelsTouchesInView = YES;

    _tapGesture = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(f4c_handleTap:)];
    [_tapGesture requireGestureRecognizerToFail:_horizontalPanGesture];

    [self addGestureRecognizer:_horizontalPanGesture];
    [self addGestureRecognizer:_tapGesture];
}

- (void)cancelActivePan {
    if (!_horizontalPanGesture || !_horizontalPanGesture.enabled) return;
    _horizontalPanGesture.enabled = NO;
    _horizontalPanGesture.enabled = YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    /* UIKit's pan threshold separates taps; UIManager performs axis locking. */
    return YES;
}

- (void)f4c_buttonTapped {
    if (self.onTap) {
        self.onTap();
    }
}

- (void)f4c_handleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized && self.onTap) {
        self.onTap();
    }
}

- (void)f4c_handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *host = self.superview ?: self;
    CGPoint translation = [gesture translationInView:host];

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            if (self.onPanBegan) self.onPanBegan();
            break;
        case UIGestureRecognizerStateChanged:
            if (self.onPanChanged) self.onPanChanged(translation);
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            CGPoint velocity = [gesture velocityInView:host];
            BOOL cancelled = gesture.state != UIGestureRecognizerStateEnded;
            if (self.onPanEnded) {
                self.onPanEnded(translation, velocity, cancelled);
            }
            break;
        }
        default:
            break;
    }
}

@end


#pragma mark - Menu View Component
// Source: UI/MenuView.h


@interface MenuView : UIView <UITextFieldDelegate, UIGestureRecognizerDelegate, UIScrollViewDelegate>

@property (nonatomic, assign) CGPoint lastLocation;
@property (nonatomic, strong) NSMutableDictionary *switches;
@property (nonatomic, strong) NSMutableDictionary *checkboxes;
@property (nonatomic, strong) NSMutableDictionary *sliders;
@property (nonatomic, strong) NSMutableDictionary *sliderLabels;
@property (nonatomic, strong) NSMutableDictionary *buttons;
@property (nonatomic, strong) NSMutableDictionary *textFields;
@property (nonatomic, strong) UIColor *accentColor;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIVisualEffectView *blurEffectView;
/* Clips blur + chrome to rounded shell; MenuView itself keeps shadow (no masksToBounds). */
@property (nonatomic, strong) UIView *shellClipView;
@property (nonatomic, strong) UISegmentedControl *tabBar;
@property (nonatomic, strong) UIView *tabSidebar;
@property (nonatomic, strong) UIScrollView *tabScrollView;
@property (nonatomic, strong) UIView *tabContainerView;
@property (nonatomic, strong) NSMutableArray *tabButtons;
@property (nonatomic, assign) NSInteger selectedTabIndex;
@property (nonatomic, assign) NSInteger currentCategoryCounter;
@property (nonatomic, strong) UIButton *telegramButton;

@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, assign) BOOL canMove;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property (nonatomic, strong) UITapGestureRecognizer *keyboardDismissTapGesture;
@property (nonatomic, strong) UIView *currentSectionCard;
@property (nonatomic, strong) UIView *sectionCardInner;
@property (nonatomic, strong) UILabel *sidebarFooterLabel;
@property (nonatomic, strong) UIView *sidebarLogoBox;
@property (nonatomic, strong) UILabel *sidebarLogoChar;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIView *headerSeparator;
@property (nonatomic, strong) UIView *footerSeparator;
@property (nonatomic, strong) UIView *bodySeparator;
@property (nonatomic, strong) UIView *contentPanel;
@property (nonatomic, assign) CGFloat cachedSidebarContentWidth;

+ (instancetype)menuWithFrame:(CGRect)frame;
- (void)makeDraggable;
- (void)canMove:(BOOL)enabled;
- (void)addFeatureSwitch:(NSString *)title handler:(void (^)(BOOL isOn))handler;
- (void)addCheckbox:(NSString *)title handler:(void (^)(BOOL isOn))handler;
- (BOOL)switchOnForTitle:(NSString *)title;
- (void)setSwitch:(BOOL)on forTitle:(NSString *)title animated:(BOOL)animated;
- (BOOL)checkboxOnForTitle:(NSString *)title;
- (void)setCheckbox:(BOOL)on forTitle:(NSString *)title animated:(BOOL)animated;
- (void)f4c_checkboxTapped:(UIButton *)sender;
- (void)addSlider:(NSString *)title max:(CGFloat)max min:(CGFloat)min value:(CGFloat)value handler:(void (^)(CGFloat value))handler;
- (void)addSliderWithButton:(NSString *)title
                        max:(CGFloat)max
                        min:(CGFloat)min
                      value:(CGFloat)value
                buttonTitle:(NSString *)buttonTitle
              buttonHandler:(void (^)(void))buttonHandler
                    handler:(void (^)(CGFloat value))handler;
- (void)addSliderWithButton:(NSString *)title
                        max:(CGFloat)max
                        min:(CGFloat)min
                      value:(CGFloat)value
               defaultValue:(CGFloat)defaultValue
                buttonTitle:(NSString *)buttonTitle
              buttonHandler:(void (^)(void))buttonHandler
                    handler:(void (^)(CGFloat value))handler;
- (void)addButton:(NSString *)title withHandler:(void (^)(void))handler;
- (void)addButton:(NSString *)title
        badgeText:(NSString *)badgeText
    badgeDuration:(NSTimeInterval)badgeDuration
       withHandler:(void (^)(void))handler;
- (void)addComboSelector:(NSString *)title options:(NSArray *)options selectedIndex:(NSInteger)index handler:(void (^)(NSInteger selectedIndex))handler;
- (void)updateComboSelector:(NSString *)title options:(NSArray *)options selectedIndex:(NSInteger)index;
- (UILabel *)addStatusLabel:(NSString *)text;
- (void)addTextField:(NSString *)title placeholder:(NSString *)placeholder handler:(void (^)(NSString *text))handler;
- (void)addFilteredComboCheckbox:(NSArray<NSString *> *)options ids:(NSArray<NSString *> *)ids selectedIndex:(NSInteger)index selectionHandler:(void (^)(NSInteger selectedIndex))selectionHandler toggleHandler:(void (^)(BOOL isOn))toggleHandler;
- (void)f4c_filteredComboFilterChanged:(UITextField *)field;
- (void)addIntegerInputCheckbox:(NSString *)title
                            min:(NSInteger)minValue
                            max:(NSInteger)maxValue
                          value:(NSInteger)value
                   valueHandler:(void (^)(NSInteger value))valueHandler
                  toggleHandler:(void (^)(BOOL isOn))toggleHandler;
- (void)f4c_integerInputEditingDidEnd:(UITextField *)textField;
- (void)f4c_integerCheckboxTapped:(UIButton *)sender;
- (void)f4c_finishIntegerInput:(id)sender;
@property (nonatomic, strong) NSString *telegramURL;


- (void)addSectionTitle:(NSString *)title;
- (void)setTabIndex:(NSInteger)index;
- (void)selectTabAtIndex:(NSInteger)index;
- (void)addTab:(NSArray<NSString *> *)tabNames;
- (void)addTabSection:(NSString *)sectionTitle
                 tabs:(NSArray<NSString *> *)tabNames;
- (void)updateLayout;
- (void)setMenuAccentColor:(UIColor *)color;


- (void)setMenuGlassEffect:(BOOL)enabled;
- (void)setMenuCornerRadius:(CGFloat)radius;
- (void)setMenuBorderWidth:(CGFloat)width;
- (void)setMenuTitle:(NSString *)title;
- (void)setMenuSubtitle:(NSString *)subtitle;
- (void)setFooterText:(NSString *)text;
- (void)setMenuLogoCharacter:(NSString *)character;
- (void)setSidebarFooterText:(NSString *)text;
- (void)addIntegerInput:(NSString *)title
                    min:(NSInteger)minValue
                    max:(NSInteger)maxValue
                  value:(NSInteger)value
           valueHandler:(void (^)(NSInteger value))valueHandler;
- (void)addCheckboxCombo:(NSString *)title
                 options:(NSArray<NSString *> *)options
           selectedIndex:(NSInteger)index
                    isOn:(BOOL)isOn
       selectionHandler:(void (^)(NSInteger selectedIndex))selectionHandler
          toggleHandler:(void (^)(BOOL isOn))toggleHandler;
- (void)addInlineCombo:(NSString *)title
               options:(NSArray<NSString *> *)options
         selectedIndex:(NSInteger)index
               handler:(void (^)(NSInteger selectedIndex))handler;
- (void)addInlineComboWithButton:(NSString *)title
                          options:(NSArray<NSString *> *)options
                    selectedIndex:(NSInteger)index
                 selectionHandler:(void (^)(NSInteger selectedIndex))selectionHandler
                      buttonTitle:(NSString *)buttonTitle
                    buttonHandler:(void (^)(void))buttonHandler;
- (void)addInputWithButton:(NSString *)title
               placeholder:(NSString *)placeholder
               buttonTitle:(NSString *)buttonTitle
                   handler:(void (^)(NSString *text))handler;
- (void)addComboWithInput:(NSString *)title
                  options:(NSArray<NSString *> *)options
            selectedIndex:(NSInteger)index
             defaultValue:(NSInteger)defaultValue
         selectionHandler:(void (^)(NSInteger selectedIndex))selectionHandler
             valueHandler:(void (^)(NSInteger value))valueHandler;
@end

@implementation MenuView

#pragma mark - Appearance Theme Helpers

/*
 * Liquid Glass look via DEPTH (rim + soft shadow), not by making UI
 * ultra-transparent. Cards stay frosted/readable; elevation comes from shadow.
 */

/* Glass switch fixed geometry — slim & sleek layout */
static const CGFloat kF4CGlassSW = 48.0;
static const CGFloat kF4CGlassSH = 24.0;
static const CGFloat kF4CGlassThumb = 18.0;
static const CGFloat kF4CGlassPad = 3.0;


- (UIColor *)f4c_primaryTextColor {
    return [UIColor colorWithRed:18.0/255.0 green:28.0/255.0 blue:44.0/255.0 alpha:0.94];
}

- (UIColor *)f4c_secondaryTextColor {
    return [UIColor colorWithRed:55.0/255.0 green:72.0/255.0 blue:98.0/255.0 alpha:0.80];
}

/* Soft cool glass tint — used with higher alpha for solid frosted panels */
- (UIColor *)f4c_glassTintColorWithAlpha:(CGFloat)alpha {
    return [UIColor colorWithRed:0.90 green:0.94 blue:0.98 alpha:alpha];
}

- (UIColor *)f4c_sidebarBackgroundColor {
    return [self f4c_glassTintColorWithAlpha:0.42];
}

- (UIColor *)f4c_contentBackgroundColor {
    return [self f4c_glassTintColorWithAlpha:0.28];
}

- (UIColor *)f4c_headerBackgroundColor {
    return [self f4c_glassTintColorWithAlpha:0.50];
}

- (UIColor *)f4c_cardBackgroundColor {
    /* Dense frosted card — readable, not see-through */
    return [self f4c_glassTintColorWithAlpha:0.78];
}

- (UIColor *)f4c_cardBorderColor {
    return [UIColor colorWithWhite:1.0 alpha:0.88];
}

- (UIColor *)f4c_inputBackgroundColor {
    return [UIColor colorWithWhite:1.0 alpha:0.62];
}

- (UIColor *)f4c_glassHighlightColor {
    return [UIColor colorWithWhite:1.0 alpha:0.95];
}

- (UIColor *)f4c_glassRimColor {
    return [UIColor colorWithWhite:1.0 alpha:0.90];
}

- (UIColor *)f4c_glassShadowColor {
    return [UIColor colorWithRed:0.10 green:0.14 blue:0.28 alpha:1.0];
}

- (CGFloat)f4c_glassCardCornerRadius {
    return 16.0;
}

- (CGFloat)f4c_glassControlCornerRadius {
    return 12.0;
}

- (CGFloat)f4c_glassShellCornerRadius {
    /* Use real menu radius — do NOT force min 20 (was mismatching border vs blur). */
    CGFloat r = self.layer.cornerRadius;
    return (r > 0.5) ? r : 14.0;
}

/* Soft continuous corners when available (no @available / isOSVersionAtLeast). */
- (void)f4c_applyContinuousCornerOnLayer:(CALayer *)layer {
    if (!layer) return;
    /* iOS 13+ CALayer.cornerCurve; KVC avoids availability / linker helpers */
    if ([layer respondsToSelector:NSSelectorFromString(@"setCornerCurve:")]) {
        @try {
            [layer setValue:@"continuous" forKey:@"cornerCurve"];
        } @catch (__unused NSException *e) {
        }
    }
}

/*
 * Sync rounded shell so blur/chrome never paint square corners outside the border.
 * Shadow stays on MenuView (masksToBounds NO); clipping lives on shellClipView + blur.
 */
- (void)f4c_syncShellCornerClip {
    CGFloat r = [self f4c_glassShellCornerRadius];
    self.layer.cornerRadius = r;
    [self f4c_applyContinuousCornerOnLayer:self.layer];

    if (self.bounds.size.width > 0.5 && self.bounds.size.height > 0.5) {
        self.layer.shadowPath =
            [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:r].CGPath;
    }

    if (self.shellClipView) {
        self.shellClipView.frame = self.bounds;
        self.shellClipView.layer.cornerRadius = r;
        self.shellClipView.layer.masksToBounds = YES;
        self.shellClipView.clipsToBounds = YES;
        [self f4c_applyContinuousCornerOnLayer:self.shellClipView.layer];
    }

    if (self.blurEffectView) {
        self.blurEffectView.frame = self.shellClipView ? self.shellClipView.bounds : self.bounds;
        self.blurEffectView.layer.cornerRadius = r;
        self.blurEffectView.layer.masksToBounds = YES;
        self.blurEffectView.clipsToBounds = YES;
        [self f4c_applyContinuousCornerOnLayer:self.blurEffectView.layer];
        /* UIVisualEffectView contentView can leak square blur without this */
        self.blurEffectView.contentView.layer.cornerRadius = r;
        self.blurEffectView.contentView.layer.masksToBounds = YES;
        self.blurEffectView.contentView.clipsToBounds = YES;
        [self f4c_applyContinuousCornerOnLayer:self.blurEffectView.contentView.layer];
        [self f4c_syncGlassSheenOnView:self.blurEffectView cornerRadius:r intensity:0.40];
    }
}

- (CGFloat)f4c_cardShadowRadius {
    return 12.0;
}

- (CGFloat)f4c_cardShadowOffsetY {
    return 6.0;
}

- (CGFloat)f4c_cardShadowExtraSpacing {
    /* Clearance so next card never sits under previous drop-shadow */
    return [self f4c_cardShadowOffsetY] + ([self f4c_cardShadowRadius] * 0.45);
}

/* Mild top sheen only — does not wash out solid frosted fill */
- (void)f4c_syncGlassSheenOnView:(UIView *)view
                    cornerRadius:(CGFloat)radius
                       intensity:(CGFloat)intensity {
    if (!view) return;
    static NSString * const kSheen = @"f4cLiquidGlassSheen";
    CAGradientLayer *sheen = nil;
    for (CALayer *sub in view.layer.sublayers.copy) {
        if ([sub.name isEqualToString:kSheen]) {
            sheen = (CAGradientLayer *)sub;
            break;
        }
    }
    if (!sheen) {
        sheen = [CAGradientLayer layer];
        sheen.name = kSheen;
        sheen.startPoint = CGPointMake(0.5, 0.0);
        sheen.endPoint = CGPointMake(0.5, 1.0);
        /* Keep under content layers but above solid fill */
        [view.layer insertSublayer:sheen atIndex:0];
    }
    sheen.frame = view.bounds;
    sheen.cornerRadius = radius;
    sheen.masksToBounds = YES;
    CGFloat i = MAX(0.0, MIN(intensity, 1.0));
    sheen.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.28 * i].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.08 * i].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
    ];
    sheen.locations = @[@0.0, @0.35, @1.0];
}

- (void)f4c_applyLiquidGlassToView:(UIView *)view
                      cornerRadius:(CGFloat)radius
                         fillAlpha:(CGFloat)fillAlpha
                         elevated:(BOOL)elevated
                     sheenIntensity:(CGFloat)sheenIntensity
                         clipBody:(BOOL)clipBody {
    if (!view) return;
    view.backgroundColor = [self f4c_glassTintColorWithAlpha:fillAlpha];
    view.layer.cornerRadius = radius;
    view.layer.borderWidth = elevated ? 1.35 : 1.2;
    view.layer.borderColor = [self f4c_glassRimColor].CGColor;

    if (elevated) {
        /* Shadow only when not clipping — never combine clip + shadow on same view */
        view.clipsToBounds = NO;
        view.layer.masksToBounds = NO;
        view.layer.shadowColor = [self f4c_glassShadowColor].CGColor;
        view.layer.shadowOpacity = 0.28;
        view.layer.shadowRadius = [self f4c_cardShadowRadius];
        view.layer.shadowOffset = CGSizeMake(0, [self f4c_cardShadowOffsetY]);
    } else {
        view.layer.shadowOpacity = 0.0;
        view.layer.shadowPath = nil;
        view.layer.masksToBounds = clipBody;
        if (clipBody) view.clipsToBounds = YES;
    }
    [self f4c_syncGlassSheenOnView:view cornerRadius:radius intensity:sheenIntensity];
}

- (void)f4c_applyCardElevationShadow:(UIView *)card body:(UIView *)inner {
    if (!card || !inner) return;
    CGFloat r = [self f4c_glassCardCornerRadius];
    card.clipsToBounds = NO;
    card.layer.masksToBounds = NO;
    card.layer.shadowColor = [self f4c_glassShadowColor].CGColor;
    card.layer.shadowOpacity = 0.30;
    card.layer.shadowRadius = [self f4c_cardShadowRadius];
    card.layer.shadowOffset = CGSizeMake(0, [self f4c_cardShadowOffsetY]);
    /* Shadow follows glass body only (not full wrapper incl. title overhang) */
    if (inner.bounds.size.width > 0.0 && inner.bounds.size.height > 0.0) {
        card.layer.shadowPath =
            [UIBezierPath bezierPathWithRoundedRect:inner.frame
                                       cornerRadius:r].CGPath;
    }
}

- (void)f4c_applyGlassChromeToView:(UIView *)view
                      cornerRadius:(CGFloat)radius
                       borderAlpha:(CGFloat)borderAlpha
                        fillAlpha:(CGFloat)fillAlpha {
    [self f4c_applyLiquidGlassToView:view
                        cornerRadius:radius
                           fillAlpha:MAX(fillAlpha, 0.55)
                           elevated:YES
                     sheenIntensity:0.55
                           clipBody:NO];
    if (borderAlpha > 0.0) {
        view.layer.borderColor =
            [UIColor colorWithWhite:1.0 alpha:borderAlpha].CGColor;
    }
}

- (CGFloat)f4c_headerChipSize {
    return 30.0;
}

- (CGFloat)f4c_headerChipGap {
    return 8.0;
}

- (CGFloat)f4c_headerChipCornerRadius {
    /* Perfect circle chips — same for telegram + close */
    return [self f4c_headerChipSize] * 0.5;
}

/*
 * Shared raised glass-chip chrome for Telegram / Close:
 * same size, corner, border, sheen, drop-shadow; only fill differs.
 * masksToBounds MUST stay NO so elevation shadow is visible.
 */
- (void)f4c_styleHeaderChipButton:(UIButton *)button
                    fillColor:(UIColor *)fillColor
                  glyphColor:(UIColor *)glyphColor
                 shadowColor:(UIColor *)shadowColor {
    if (!button) return;
    CGFloat size = [self f4c_headerChipSize];
    CGFloat radius = [self f4c_headerChipCornerRadius];

    button.backgroundColor = fillColor;
    button.layer.cornerRadius = radius;
    /* No clip — circular shadow needs masksToBounds = NO */
    button.layer.masksToBounds = NO;
    button.clipsToBounds = NO;
    button.layer.borderWidth = 1.25;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.88].CGColor;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    button.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    F4CSetButtonContentInsets(button, UIEdgeInsetsZero);
    F4CSetButtonImageInsets(button, UIEdgeInsetsMake(6.0, 6.0, 6.0, 6.0));
    F4CSetButtonTitleInsets(button, UIEdgeInsetsZero);
    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    button.tintColor = glyphColor;
    [button setTitleColor:glyphColor forState:UIControlStateNormal];
    [button setTitleColor:glyphColor forState:UIControlStateHighlighted];

    /* Lifted chip: soft colored glow + depth offset */
    UIColor *shade = shadowColor ?: [self f4c_glassShadowColor];
    button.layer.shadowColor = shade.CGColor;
    button.layer.shadowOpacity = 0.42;
    button.layer.shadowRadius = 7.0;
    button.layer.shadowOffset = CGSizeMake(0, 3.5);

    /* Keep frame square if already laid out */
    if (button.frame.size.width > 0.0 || button.frame.size.height > 0.0) {
        CGRect f = button.frame;
        f.size.width = size;
        f.size.height = size;
        button.frame = f;
    }

    button.layer.shadowPath =
        [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size, size)].CGPath;

    [self f4c_syncGlassSheenOnView:button cornerRadius:radius intensity:0.55];
}

- (void)f4c_styleCloseButton {
    if (!self.closeButton) return;
    UIColor *fill =
        [UIColor colorWithRed:1.0 green:0.34 blue:0.36 alpha:0.92];
    UIColor *shadow =
        [UIColor colorWithRed:0.85 green:0.12 blue:0.16 alpha:1.0];
    [self f4c_styleHeaderChipButton:self.closeButton
                          fillColor:fill
                         glyphColor:[UIColor whiteColor]
                        shadowColor:shadow];
}

- (void)f4c_styleTelegramButton {
    if (!self.telegramButton) return;
    /* Telegram brand blue — solid raised chip */
    UIColor *fill =
        [UIColor colorWithRed:37.0/255.0 green:150.0/255.0 blue:230.0/255.0 alpha:0.95];
    UIColor *shadow =
        [UIColor colorWithRed:0.08 green:0.35 blue:0.70 alpha:1.0];
    [self f4c_styleHeaderChipButton:self.telegramButton
                          fillColor:fill
                         glyphColor:[UIColor whiteColor]
                        shadowColor:shadow];
}

- (void)f4c_styleHeaderActionButtons {
    [self f4c_styleTelegramButton];
    [self f4c_styleCloseButton];
}

- (void)f4c_styleMenuLogo {
    if (!self.sidebarLogoBox) return;
    CGFloat r = 11.0;
    CGRect bounds = self.sidebarLogoBox.bounds;

    self.sidebarLogoBox.backgroundColor = [UIColor clearColor];
    self.sidebarLogoBox.layer.cornerRadius = r;
    self.sidebarLogoBox.clipsToBounds = NO;
    self.sidebarLogoBox.layer.masksToBounds = NO;
    self.sidebarLogoBox.layer.borderWidth = 1.25;
    self.sidebarLogoBox.layer.borderColor =
        [UIColor colorWithWhite:1.0 alpha:0.88].CGColor;
    self.sidebarLogoBox.layer.shadowColor =
        [UIColor colorWithRed:0.02 green:0.08 blue:0.22 alpha:1.0].CGColor;
    self.sidebarLogoBox.layer.shadowOpacity = 0.45;
    self.sidebarLogoBox.layer.shadowRadius = 7.0;
    self.sidebarLogoBox.layer.shadowOffset = CGSizeMake(0, 3.5);
    if (bounds.size.width > 0.0 && bounds.size.height > 0.0) {
        self.sidebarLogoBox.layer.shadowPath =
            [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:r].CGPath;
    }

    // Remove old gradient layers
    static NSString * const kLogoGrad = @"f4cLogoGradient";
    for (CALayer *sub in self.sidebarLogoBox.layer.sublayers.copy) {
        if ([sub.name isEqualToString:kLogoGrad]) {
            [sub removeFromSuperlayer];
        }
    }

    // Remove old image view if exists
    static NSInteger const kLogoImageTag = 9898;
    UIView *oldImg = [self.sidebarLogoBox viewWithTag:kLogoImageTag];
    if (oldImg) [oldImg removeFromSuperview];

    // Prefer the installed asset across libroot, conventional rootless, and rootful paths.
    NSArray<NSString *> *logoPaths = @[
        @"/var/jb/Library/Application Support/NativeMenuObjC/logo.png",
        @"/Library/Application Support/NativeMenuObjC/logo.png"
    ];

    UIImage *logoImg = nil;
    for (NSString *candidatePath in logoPaths) {
        if (candidatePath.length == 0) continue;
        logoImg = [UIImage imageWithContentsOfFile:candidatePath];
        if (logoImg) break;
    }

    // A standalone injected dylib has no layout payload, so use the exact same PNG embedded in the binary.
    if (!logoImg) {
        logoImg = F4CMenuEmbeddedLogoImage();
    }

    if (logoImg) {
        UIImageView *imgView = [[UIImageView alloc] initWithFrame:bounds];
        imgView.tag = kLogoImageTag;
        imgView.image = logoImg;
        imgView.contentMode = UIViewContentModeScaleAspectFill;
        imgView.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        imgView.clipsToBounds = YES;
        imgView.layer.cornerRadius = r;
        [self.sidebarLogoBox addSubview:imgView];
    }

    // Never leave the logo box blank when the external asset is unavailable.
    if (self.sidebarLogoChar) {
        self.sidebarLogoChar.hidden = (logoImg != nil);
    }
}

- (void)f4c_refreshContentAppearance {
    for (UIView *container in self.contentView.subviews) {
        if (container.tag < 1000) continue;

        if ([container viewWithTag:9996]) {
            container.backgroundColor = [UIColor clearColor];
            container.layer.borderWidth = 0.0;
            container.layer.borderColor = [UIColor clearColor].CGColor;

            UILabel *sectionTitle = [container viewWithTag:9998];
            if (sectionTitle) {
                [self f4c_styleSectionTitleBadge:sectionTitle];
            }

            UIView *divider = [container viewWithTag:9995];
            if (divider) {
                divider.hidden = YES;
                divider.backgroundColor = [UIColor clearColor];
            }

            UIView *inner = [container viewWithTag:9996];
            CGFloat cardR = [self f4c_glassCardCornerRadius];
            [self f4c_applyLiquidGlassToView:inner
                               cornerRadius:cardR
                                  fillAlpha:0.78
                                  elevated:NO
                            sheenIntensity:0.45
                                  clipBody:YES];
            [self f4c_applyCardElevationShadow:container body:inner];
            for (UIView *row in inner.subviews) {
                for (UIView *subview in row.subviews) {
                    if ([subview isKindOfClass:[UILabel class]]) {
                        UILabel *label = (UILabel *)subview;
                        if (label.tag == 9192) continue;
                        CGFloat fontSize = label.font.pointSize;
                        label.textColor = fontSize <= 10.5
                            ? [self f4c_secondaryTextColor]
                            : [self f4c_primaryTextColor];
                    } else if ([subview isKindOfClass:[UITextField class]]) {
                        UITextField *field = (UITextField *)subview;
                        field.backgroundColor = [self f4c_inputBackgroundColor];
                        field.textColor = [self f4c_primaryTextColor];
                        field.layer.cornerRadius = [self f4c_glassControlCornerRadius];
                        field.layer.borderWidth = 1.1;
                        field.layer.borderColor = [self f4c_glassRimColor].CGColor;
                        field.clipsToBounds = YES;
                    } else if ([subview isKindOfClass:[UIButton class]]) {
                        UIButton *btn = (UIButton *)subview;
                        if (btn.tag == 9191) {
                            if (!btn.selected) {
                                btn.backgroundColor =
                                    [UIColor colorWithWhite:1.0 alpha:0.55];
                            }
                            btn.layer.borderColor = [self f4c_glassRimColor].CGColor;
                            btn.layer.borderWidth = 1.1;
                        } else if (objc_getAssociatedObject(btn, "comboOptions")) {
                            btn.backgroundColor = [self f4c_inputBackgroundColor];
                            btn.layer.cornerRadius = [self f4c_glassControlCornerRadius];
                            btn.layer.borderWidth = 1.1;
                            btn.layer.borderColor = [self f4c_glassRimColor].CGColor;
                            btn.clipsToBounds = YES;
                        } else if (btn.tag != 8888 && btn.tag != 8889) {
                            [btn setTitleColor:[self f4c_secondaryTextColor]
                                      forState:UIControlStateNormal];
                        }
                    }
                }
            }
            continue;
        }

        for (UIView *subview in container.subviews) {
            if ([subview isKindOfClass:[UILabel class]]) {
                ((UILabel *)subview).textColor = [self f4c_primaryTextColor];
            } else if ([subview isKindOfClass:[UITextField class]]) {
                UITextField *field = (UITextField *)subview;
                field.backgroundColor = [self f4c_inputBackgroundColor];
                field.textColor = [self f4c_primaryTextColor];
            } else if ([subview isKindOfClass:[UIButton class]]) {
                UIButton *btn = (UIButton *)subview;
                if (btn.tag == 8888 || btn.tag == 8889) {
                    [btn setTitleColor:[self f4c_secondaryTextColor]
                              forState:UIControlStateNormal];
                }
            }
        }
    }
}

- (void)f4c_applyAppearanceTheme {
    /* Outer shell: frosted panel + rim + drop shadow (depth, not ultra-clear) */
    CGFloat shellR = [self f4c_glassShellCornerRadius];
    /* Tint lives on clip shell so rounded corners don't show square fill */
    self.backgroundColor = [UIColor clearColor];
    if (self.shellClipView) {
        self.shellClipView.backgroundColor = [self f4c_glassTintColorWithAlpha:0.35];
    }
    self.layer.cornerRadius = shellR;
    self.layer.borderColor = [self f4c_glassHighlightColor].CGColor;
    self.layer.borderWidth = MAX(self.layer.borderWidth, 1.0);
    self.layer.shadowColor = [self f4c_glassShadowColor].CGColor;
    self.layer.shadowOpacity = 0.32;
    self.layer.shadowRadius = 22.0;
    self.layer.shadowOffset = CGSizeMake(0, 10);
    self.layer.masksToBounds = NO; /* shadow; clip is on shellClipView */

    if (self.blurEffectView) {
        UIBlurEffect *fx =
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
        self.blurEffectView.effect = fx;
        self.blurEffectView.alpha = 1.0;
    }
    [self f4c_syncShellCornerClip];

    if (self.headerView) {
        self.headerView.backgroundColor = [self f4c_headerBackgroundColor];
    }
    if (self.tabSidebar) {
        self.tabSidebar.backgroundColor = [self f4c_sidebarBackgroundColor];
    }
    if (self.contentPanel) {
        self.contentPanel.backgroundColor = [self f4c_contentBackgroundColor];
    }
    UIColor *hairline = [UIColor colorWithWhite:1.0 alpha:0.50];
    if (self.headerSeparator) {
        self.headerSeparator.backgroundColor = hairline;
    }
    if (self.footerSeparator) {
        self.footerSeparator.backgroundColor = hairline;
    }
    if (self.bodySeparator) {
        self.bodySeparator.backgroundColor =
            [UIColor colorWithWhite:1.0 alpha:0.40];
    }

    self.titleLabel.textColor = [self f4c_primaryTextColor];
    self.subtitleLabel.textColor = [self f4c_secondaryTextColor];
    self.sidebarFooterLabel.textColor = [self f4c_secondaryTextColor];
    self.sidebarFooterLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self f4c_styleHeaderActionButtons];
    [self f4c_styleMenuLogo];

    self.tabScrollView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    self.scrollView.indicatorStyle = UIScrollViewIndicatorStyleWhite;

    for (UIView *subview in self.tabContainerView.subviews) {
        if ([self f4c_isTabSectionHeaderView:subview]) {
            [self f4c_styleTabSectionHeader:subview];
            continue;
        }
        if ([subview isKindOfClass:[UILabel class]] &&
            subview.tag >= 8001 && subview.tag < 9000) {
            [self f4c_styleTabSectionHeader:subview];
        }
    }

    for (NSInteger i = 0; i < (NSInteger)self.tabButtons.count; i++) {
        [self f4c_styleTabButton:self.tabButtons[i] selected:(i == self.selectedTabIndex)];
    }

    [self f4c_refreshContentAppearance];
    [self updateTheme];
}

- (CGFloat)f4c_headerHeight {
    return 52.0;
}

- (CGFloat)f4c_sidebarMinWidth {
    return 52.0;
}

- (CGFloat)f4c_sidebarMaxWidth {
    CGFloat menuW = self.bounds.size.width;
    if (menuW <= 1.0) menuW = 368.0;
    BOOL isLandscape = (menuW > self.bounds.size.height);
    CGFloat maxRatio = isLandscape ? 0.28 : 0.26;
    return MIN(isLandscape ? 136.0 : 96.0, MAX(menuW * maxRatio, 66.0));
}

- (CGFloat)f4c_tabTitleLeadingInset {
    return 8.0; /* padding only — no side indicator glyph */
}

- (CGFloat)f4c_tabTitleTrailingInset {
    return 6.0;
}

- (CGFloat)f4c_tabSideInset {
    return 4.0;
}

- (CGFloat)f4c_measureTextWidth:(NSString *)text font:(UIFont *)font {
    if (text.length == 0 || !font) return 0.0;
    CGRect rect =
        [text boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, 40.0)
                           options:(NSStringDrawingUsesLineFragmentOrigin |
                                    NSStringDrawingUsesFontLeading)
                        attributes:@{NSFontAttributeName: font}
                           context:nil];
    return ceil(rect.size.width);
}

/*
 * Auto-size vertical sidebar to the widest tab / section title text.
 * Footer credit is NOT included (it scales/truncates inside the rail).
 */
- (CGFloat)f4c_measureSidebarContentWidth {
    if (!self.tabButtons || self.tabButtons.count == 0) return 0.0;
    if (self.cachedSidebarContentWidth > 0.0) {
        return self.cachedSidebarContentWidth;
    }

    CGFloat maxText = 0.0;
    UIFont *fallbackTabFont =
        [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    UIFont *fallbackHeaderFont =
        [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];

    for (UIButton *tabBtn in self.tabButtons) {
        if (![tabBtn isKindOfClass:[UIButton class]]) continue;
        NSString *title = [tabBtn titleForState:UIControlStateNormal] ?: @"";
        UIFont *font = tabBtn.titleLabel.font ?: fallbackTabFont;
        maxText = MAX(maxText, [self f4c_measureTextWidth:title font:font]);
        /* selected state may use heavier weight */
        maxText = MAX(maxText, [self f4c_measureTextWidth:title font:fallbackTabFont]);
    }

    if (self.tabContainerView) {
        UIFont *headerFont = [self f4c_tabSectionHeaderFont] ?: fallbackHeaderFont;
        for (UIView *subview in self.tabContainerView.subviews) {
            if ([self f4c_isTabSectionHeaderView:subview]) {
                UILabel *titleLabel = (UILabel *)[subview viewWithTag:8100];
                NSString *raw = titleLabel.text.length
                    ? titleLabel.text
                    : @"";
                NSString *text = [self f4c_tabSectionDisplayTitle:raw];
                /* Header needs side hairlines (~8+8) + gaps — inflate measure */
                CGFloat headerTextW = [self f4c_measureTextWidth:text font:headerFont];
                maxText = MAX(maxText, headerTextW + 16.0 + 12.0);
                continue;
            }
            if (![subview isKindOfClass:[UILabel class]]) continue;
            if (subview.tag < 8001 || subview.tag >= 9000) continue;
            UILabel *header = (UILabel *)subview;
            UIFont *font = header.font ?: headerFont;
            NSString *text = [self f4c_tabSectionDisplayTitle:header.text ?: @""];
            maxText = MAX(maxText, [self f4c_measureTextWidth:text font:font] + 16.0 + 12.0);
        }
    }

    CGFloat sideInset = [self f4c_tabSideInset];
    /* Tab labels are centered now — padding both sides, not old left-glyph inset */
    CGFloat chrome = (sideInset * 2.0) + 8.0 + 8.0;
    self.cachedSidebarContentWidth = maxText + chrome;
    return self.cachedSidebarContentWidth;
}

- (CGFloat)f4c_sidebarWidth {
    if (!self.tabButtons || self.tabButtons.count == 0) return 0.0;
    CGFloat needed = [self f4c_measureSidebarContentWidth];
    if (needed <= 0.0) return 0.0;
    CGFloat minW = [self f4c_sidebarMinWidth];
    CGFloat maxW = [self f4c_sidebarMaxWidth];
    return MIN(MAX(needed, minW), maxW);
}

- (CGFloat)f4c_effectiveSidebarWidth {
    if (!self.tabSidebar) return 0.0;
    if (!self.tabButtons || self.tabButtons.count == 0) return 0.0;
    return [self f4c_sidebarWidth];
}

- (CGFloat)f4c_sidebarFooterHeight {
    /* Full-width bottom credit bar (not limited to sidebar) */
    NSString *text = self.sidebarFooterLabel.text ?: @"";
    if (text.length == 0) return 0.0;
    return 30.0;
}

- (CGFloat)f4c_chromeHorizontalInset {
    BOOL isLandscape = (self.bounds.size.width > self.bounds.size.height);
    return isLandscape ? 14.0 : 10.0;
}

- (CGFloat)f4c_contentInsetValue {
    return [self f4c_chromeHorizontalInset];
}

- (UIEdgeInsets)f4c_contentInsets {
    CGFloat inset = [self f4c_contentInsetValue];
    return UIEdgeInsetsMake(inset, inset, inset, inset);
}

- (CGFloat)f4c_contentHorizontalInset {
    return [self f4c_contentInsetValue];
}

- (CGFloat)f4c_contentPanelWidth {
    return MAX(self.bounds.size.width - [self f4c_effectiveSidebarWidth], 0.0);
}

- (CGFloat)f4c_contentLayoutWidth {
    CGFloat panelWidth = [self f4c_contentPanelWidth];
    return MAX(panelWidth - (2.0 * [self f4c_contentInsetValue]), 40.0);
}

- (void)f4c_applyScrollContentInsets {
    if (!self.scrollView) return;

    CGFloat inset = [self f4c_contentInsetValue];
    UIEdgeInsets scrollInsets = UIEdgeInsetsMake(inset, 0.0, inset, 0.0);
    self.scrollView.contentInset = scrollInsets;
    self.scrollView.scrollIndicatorInsets = scrollInsets;

    if (self.contentView) {
        CGRect contentFrame = self.contentView.frame;
        contentFrame.origin.x = inset;
        contentFrame.origin.y = 0.0;
        contentFrame.size.width = [self f4c_contentLayoutWidth];
        self.contentView.frame = contentFrame;
    }

    // Preserve the reader's offset; clamp only after content/bounds change.
    [self f4c_clampContentScrollOffset];
}

- (void)f4c_configureContentScrollView {
    if (!self.scrollView) return;

    self.scrollView.delegate = self;
    self.scrollView.bounces = YES;
    self.scrollView.alwaysBounceVertical = NO;
    self.scrollView.alwaysBounceHorizontal = NO;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    self.scrollView.directionalLockEnabled = YES;
    self.scrollView.scrollsToTop = NO;
}

- (void)f4c_clampContentScrollOffset {
    UIScrollView *scrollView = self.scrollView;
    if (!scrollView) return;

    CGFloat minY = -scrollView.contentInset.top;
    CGFloat maxY = scrollView.contentSize.height -
                   scrollView.bounds.size.height +
                   scrollView.contentInset.bottom;
    if (maxY < minY) maxY = minY;

    CGPoint offset = scrollView.contentOffset;
    offset.x = 0.0;
    if (offset.y < minY) offset.y = minY;
    if (offset.y > maxY) offset.y = maxY;

    if (!CGPointEqualToPoint(offset, scrollView.contentOffset)) {
        scrollView.contentOffset = offset;
    }
}

- (void)f4c_layoutChrome {
    /* Keep rounded clip + blur in sync before laying out chrome frames */
    [self f4c_syncShellCornerClip];

    CGFloat menuWidth = self.bounds.size.width;
    CGFloat menuHeight = self.bounds.size.height;
    CGFloat headerHeight = [self f4c_headerHeight];
    CGFloat sidebarWidth = [self f4c_effectiveSidebarWidth];
    CGFloat footerHeight = [self f4c_sidebarFooterHeight];
    CGFloat panelWidth = [self f4c_contentPanelWidth];
    /* Body sits between header and full-width credit footer */
    CGFloat bodyHeight = MAX(menuHeight - headerHeight - footerHeight, 0.0);
    CGFloat headerInset = [self f4c_chromeHorizontalInset];
    CGFloat headerButtonSize = [self f4c_headerChipSize];
    CGFloat headerButtonGap = [self f4c_headerChipGap];
    CGFloat logoSize = 40.0;
    CGFloat midGap = 10.0;
    CGFloat chipY = MAX((headerHeight - headerButtonSize) * 0.5, 0.0);
    CGFloat logoY = MAX((headerHeight - logoSize) * 0.5, 0.0);
    BOOL isLandscape = (menuWidth > menuHeight);

    CGFloat logoX, closeX, telegramX, titleX, titleRight;
    if (isLandscape) {
        /*
         * MIRRORED (Landscape):
         * [Close (Left)] [Telegram] ---- [Title] ---- [Logo (Right)]
         */
        closeX = headerInset;
        telegramX = closeX + headerButtonSize + headerButtonGap;
        logoX = menuWidth - headerInset - logoSize;
        titleX = telegramX + headerButtonSize + midGap;
        titleRight = logoX - midGap;
    } else {
        /*
         * DEFAULT (Portrait):
         * [Logo (Left)] ---- [Title] ---- [Telegram] [Close (Right)]
         */
        logoX = headerInset;
        closeX = menuWidth - headerInset - headerButtonSize;
        telegramX = closeX - headerButtonGap - headerButtonSize;
        titleX = logoX + logoSize + midGap;
        titleRight = telegramX - midGap;
    }
    CGFloat titleWidth = MAX(titleRight - titleX, 0.0);

    if (self.headerView) {
        self.headerView.frame = CGRectMake(0, 0, menuWidth, headerHeight);
        /* Allow chip drop-shadows to paint outside header bounds */
        self.headerView.clipsToBounds = NO;
        self.headerView.layer.masksToBounds = NO;
    }

    if (self.sidebarLogoBox) {
        self.sidebarLogoBox.frame = CGRectMake(logoX, logoY, logoSize, logoSize);
        if (self.sidebarLogoChar) {
            self.sidebarLogoChar.frame = self.sidebarLogoBox.bounds;
        }
        [self f4c_styleMenuLogo];
    }

    if (self.titleLabel) {
        BOOL hasSubtitle = (self.subtitleLabel &&
                            !self.subtitleLabel.hidden &&
                            self.subtitleLabel.text.length > 0);
        if (hasSubtitle) {
            /*
             * Title/subtitle sit in the true middle band between logo and chips.
             */
            CGFloat titleBlockH = 34.0;
            CGFloat titleBlockY = MAX((headerHeight - titleBlockH) * 0.5, 0.0);
            self.titleLabel.frame = CGRectMake(titleX, titleBlockY, titleWidth, 16);
            self.subtitleLabel.frame = CGRectMake(titleX, titleBlockY + 17.0, titleWidth, 14);
            self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
            self.subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        } else {
            self.titleLabel.frame = CGRectMake(titleX, 0.0, titleWidth, headerHeight);
        }
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    }

    /* Telegram + Close: same size, Y, gap — visually even pair */
    if (self.telegramButton) {
        self.telegramButton.frame =
            CGRectMake(telegramX, chipY, headerButtonSize, headerButtonSize);
    }

    if (self.closeButton) {
        self.closeButton.frame =
            CGRectMake(closeX, chipY, headerButtonSize, headerButtonSize);
    }

    [self f4c_styleHeaderActionButtons];

    if (self.headerSeparator) {
        self.headerSeparator.frame = CGRectMake(0, headerHeight - 1, menuWidth, 1);
    }

    /* Body Layout: Sidebar vs Content Panel */
    CGFloat sidebarX = isLandscape ? (menuWidth - sidebarWidth) : 0.0;
    CGFloat panelX   = isLandscape ? 0.0 : sidebarWidth;

    if (self.tabSidebar) {
        self.tabSidebar.frame = CGRectMake(sidebarX, headerHeight, sidebarWidth, bodyHeight);
        self.tabSidebar.hidden = (sidebarWidth <= 0.0);
    }

    if (self.tabScrollView && self.tabSidebar && sidebarWidth > 0.0) {
        self.tabScrollView.frame = CGRectMake(0, 0, sidebarWidth, bodyHeight);
    }

    /* Full-width bottom credit bar */
    BOOL showFooter = (footerHeight > 0.0 && self.sidebarFooterLabel);
    if (self.sidebarFooterLabel) {
        self.sidebarFooterLabel.hidden = !showFooter;
        if (showFooter) {
            self.sidebarFooterLabel.frame =
                CGRectMake(12.0, menuHeight - footerHeight, menuWidth - 24.0, footerHeight);
            self.sidebarFooterLabel.textAlignment = NSTextAlignmentCenter;
            self.sidebarFooterLabel.adjustsFontSizeToFitWidth = YES;
            self.sidebarFooterLabel.minimumScaleFactor = 0.72;
            self.sidebarFooterLabel.numberOfLines = 1;
            self.sidebarFooterLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        }
    }
    if (self.footerSeparator) {
        self.footerSeparator.hidden = !showFooter;
        if (showFooter) {
            self.footerSeparator.frame =
                CGRectMake(0, menuHeight - footerHeight, menuWidth, 1);
        }
    }

    if (self.tabSidebar && sidebarWidth > 0.0) {
        self.tabSidebar.clipsToBounds = NO;
        self.tabSidebar.layer.masksToBounds = NO;
    }
    if (self.tabScrollView && sidebarWidth > 0.0) {
        /* Keep scroll clipping horizontally soft so selected tab shadow shows */
        self.tabScrollView.clipsToBounds = YES;
    }
    if (self.tabContainerView && sidebarWidth > 0.0) {
        self.tabContainerView.clipsToBounds = NO;
        self.tabContainerView.layer.masksToBounds = NO;
        [self f4c_relayoutTabSidebarContent];
    }

    if (self.bodySeparator) {
        if (sidebarWidth > 0.0) {
            self.bodySeparator.hidden = NO;
            CGFloat sepX = isLandscape ? (menuWidth - sidebarWidth) : (sidebarWidth - 1);
            self.bodySeparator.frame =
                CGRectMake(sepX, headerHeight, 1, bodyHeight);
        } else {
            self.bodySeparator.hidden = YES;
        }
    }

    if (self.contentPanel) {
        self.contentPanel.frame =
            CGRectMake(panelX, headerHeight, panelWidth, bodyHeight);
    }

    if (self.scrollView && self.contentPanel) {
        self.scrollView.frame = CGRectMake(0, 0, panelWidth, bodyHeight);
    }

    [self f4c_applyScrollContentInsets];
}

- (UIView *)f4c_activeContentContainer {
    return self.sectionCardInner ?: self.contentView;
}

- (CGFloat)f4c_sectionCardInnerInset {
    BOOL isLandscape = (self.bounds.size.width > self.bounds.size.height);
    return isLandscape ? 12.0 : 8.0;
}

- (CGFloat)f4c_rowControlHeight {
    return 34.0;
}

/* UI/DESIGN.md Điều 4 — một chiều cao hàng, một cỡ nút, không số tự chế. */
- (CGFloat)f4c_rowHeight {
    return 46.0;
}

- (CGFloat)f4c_rowButtonWidth {
    return 84.0;
}

- (CGFloat)f4c_rowControlCornerRadius {
    return [self f4c_glassControlCornerRadius];
}

- (CGFloat)f4c_rowStandardComboWidth {
    return 120.0;
}

- (CGFloat)f4c_rowIntegerInputWidth {
    return 120.0;
}

- (CGFloat)f4c_buttonCornerRadius {
    return [self f4c_glassControlCornerRadius];
}

- (CGFloat)f4c_effectiveRowWidthForParent:(UIView *)parent {
    if (self.sectionCardInner && parent == self.sectionCardInner) {
        CGFloat contentWidth = [self f4c_contentLayoutWidth];
        return MAX(contentWidth - (2.0 * [self f4c_sectionCardInnerInset]), 40.0);
    }

    if (parent.frame.size.width > 0.0) {
        return parent.frame.size.width;
    }

    return [self f4c_contentLayoutWidth];
}

- (CGFloat)f4c_rowControlYForRowHeight:(CGFloat)rowHeight {
    return MAX((rowHeight - [self f4c_rowControlHeight]) * 0.5, 4.0);
}

- (void)f4c_configureInlineComboChrome:(UIButton *)combo width:(CGFloat)width {
    UIButton *arrow = [combo viewWithTag:8888];
    UIButton *close = [combo viewWithTag:8889];
    CGRect arrowFrame =
        CGRectMake(width - 22.0, 0.0, 20.0, combo.frame.size.height);
    if (arrow) arrow.frame = arrowFrame;
    if (close) close.frame = arrowFrame;
}

- (void)f4c_layoutStandardRowSubviewsInContainer:(UIView *)container {
    CGFloat rowWidth = container.frame.size.width;
    CGFloat controlH = [self f4c_rowControlHeight];
    CGFloat comboW = [self f4c_rowStandardComboWidth];
    CGFloat integerW = [self f4c_rowIntegerInputWidth];
    CGFloat gap = 12.0;
    CGFloat verticalPadding = 6.0;

    UILabel *label = nil;
    UIButton *checkbox = nil;
    UIButton *combo = nil;
    UIButton *confirm = nil;
    UITextField *integerField = nil;

    for (UIView *subview in container.subviews) {
        if ([subview isKindOfClass:[UILabel class]]) {
            label = (UILabel *)subview;
        } else if ([subview isKindOfClass:[UITextField class]] && subview.tag == 9193) {
            integerField = (UITextField *)subview;
        } else if ([subview isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)subview;
            if (btn.tag == 9191) checkbox = btn;
            else if (btn.tag == 9194) confirm = btn;
            else if (objc_getAssociatedObject(btn, "comboOptions")) combo = btn;
        }
    }

    CGFloat labelX = checkbox ? 30.0 : 0.0;
    CGFloat trailingWidth = 0.0;
    if (combo) trailingWidth = comboW;
    else if (integerField) trailingWidth = integerW;

    if (combo && confirm) {
        NSArray<NSString *> *options = objc_getAssociatedObject(combo, "comboOptions");
        CGFloat buttonWidth = [self f4c_rowButtonWidth];
        CGFloat labelWidth = 68.0;
        CGFloat buttonGap = 6.0;
        trailingWidth = [self f4c_preferredInlineComboWidthForOptions:options
                                                         contentWidth:rowWidth
                                                           labelWidth:labelWidth
                                                          buttonWidth:buttonWidth
                                                                  gap:buttonGap] + buttonWidth + buttonGap;
    }

    CGFloat labelWidth = MAX(rowWidth - labelX - trailingWidth - gap, 20.0);
    CGFloat labelHeight = 20.0;
    if (label) {
        label.numberOfLines = 2;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        CGSize fit = [label sizeThatFits:CGSizeMake(labelWidth, CGFLOAT_MAX)];
        CGFloat maxTwoLines = ceil(label.font.lineHeight * 2.0);
        labelHeight = MIN(MAX(ceil(fit.height), label.font.lineHeight), maxTwoLines);
    }

    CGFloat rowHeight = MAX(46.0, MAX(labelHeight + verticalPadding * 2.0,
                                     controlH + verticalPadding * 2.0));
    CGRect containerFrame = container.frame;
    containerFrame.size.height = rowHeight;
    container.frame = containerFrame;
    CGFloat controlY = (rowHeight - controlH) * 0.5;

    if (integerField) {
        integerField.frame = CGRectMake(rowWidth - integerW, controlY, integerW, controlH);
        integerField.layer.cornerRadius = [self f4c_rowControlCornerRadius];
    }

    if (combo) {
        CGFloat comboWidth = comboW;
        if (confirm) {
            NSArray<NSString *> *options = objc_getAssociatedObject(combo, "comboOptions");
            CGFloat buttonWidth = 72.0;
            CGFloat labelFixedWidth = 68.0;
            CGFloat buttonGap = 6.0;
            comboWidth = [self f4c_preferredInlineComboWidthForOptions:options
                                                           contentWidth:rowWidth
                                                             labelWidth:labelFixedWidth
                                                            buttonWidth:buttonWidth
                                                                    gap:buttonGap];
            CGFloat comboX = [self f4c_inlineComboOriginXForWidth:comboWidth
                                                     contentWidth:rowWidth
                                                      buttonWidth:buttonWidth
                                                              gap:buttonGap];
            combo.frame = CGRectMake(comboX, controlY, comboWidth, controlH);
            confirm.frame = CGRectMake(rowWidth - buttonWidth, controlY, buttonWidth, controlH);
            confirm.layer.cornerRadius = [self f4c_rowControlCornerRadius];
            if (label) {
                labelWidth = MAX(comboX - gap, 20.0);
                CGSize fit = [label sizeThatFits:CGSizeMake(labelWidth, CGFLOAT_MAX)];
                labelHeight = MIN(MAX(ceil(fit.height), label.font.lineHeight),
                                  ceil(label.font.lineHeight * 2.0));
                label.frame = CGRectMake(0.0, (rowHeight - labelHeight) * 0.5,
                                         labelWidth, labelHeight);
            }
        } else if (confirm) {
            NSArray<NSString *> *options = objc_getAssociatedObject(combo, "comboOptions");
            CGFloat buttonWidth = [self f4c_rowButtonWidth];
            CGFloat labelFixedWidth = 68.0;
            CGFloat buttonGap = 6.0;
            comboWidth = [self f4c_preferredInlineComboWidthForOptions:options
                                                          contentWidth:rowWidth
                                                            labelWidth:labelFixedWidth
                                                           buttonWidth:buttonWidth
                                                                   gap:buttonGap];
            CGFloat comboX = [self f4c_inlineComboOriginXForWidth:comboWidth
                                                     contentWidth:rowWidth
                                                      buttonWidth:buttonWidth
                                                              gap:buttonGap];
            combo.frame = CGRectMake(comboX, controlY, comboWidth, controlH);
            confirm.frame = CGRectMake(rowWidth - buttonWidth, controlY, buttonWidth, controlH);
            confirm.layer.cornerRadius = [self f4c_rowControlCornerRadius];
            if (label) {
                labelWidth = MAX(comboX - gap, 20.0);
                CGSize fit = [label sizeThatFits:CGSizeMake(labelWidth, CGFLOAT_MAX)];
                labelHeight = MIN(MAX(ceil(fit.height), label.font.lineHeight),
                                  ceil(label.font.lineHeight * 2.0));
                label.frame = CGRectMake(0.0, (rowHeight - labelHeight) * 0.5,
                                         labelWidth, labelHeight);
            }
        } else {
            combo.frame = CGRectMake(rowWidth - comboWidth, controlY, comboWidth, controlH);
            if (label) {
                label.frame = CGRectMake(labelX, (rowHeight - labelHeight) * 0.5,
                                         labelWidth, labelHeight);
            }
        }
        [self f4c_configureInlineComboChrome:combo width:combo.frame.size.width];
    } else if (label) {
        label.frame = CGRectMake(labelX, (rowHeight - labelHeight) * 0.5,
                                 labelWidth, labelHeight);
    }

    if (checkbox) {
        checkbox.frame = CGRectMake(0.0, (rowHeight - 22.0) * 0.5, 22.0, 22.0);
    }
}

- (void)f4c_relayoutRowContainer:(UIView *)container {
    if (!container || container.frame.size.width <= 0.0) return;

    CGFloat rowWidth = container.frame.size.width;
    UILabel *statusText = [container viewWithTag:9398];
    if (statusText) {
        CGFloat textWidth = MAX(rowWidth - 20.0, 20.0);
        CGSize fit = [statusText sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)];
        CGFloat textHeight = MIN(MAX(ceil(fit.height), 20.0), 96.0);
        CGRect frame = container.frame;
        frame.size.height = textHeight + 16.0;
        container.frame = frame;
        statusText.frame = CGRectMake(10.0, 8.0, textWidth, textHeight);
        return;
    }
    UISlider *slider = nil;
    UISwitch *toggle = nil;
    UIView *glassToggle = nil; /* tag 9288 — liquid glass switch */
    UILabel *firstLabel = nil;
    UILabel *secondLabel = nil;

    for (UIView *subview in container.subviews) {
        if ([subview isKindOfClass:[UISlider class]]) {
            slider = (UISlider *)subview;
        } else if ([subview isKindOfClass:[UISwitch class]]) {
            toggle = (UISwitch *)subview;
        } else if (subview.tag == 9288) {
            glassToggle = subview;
        } else if ([subview isKindOfClass:[UILabel class]]) {
            if (!firstLabel) firstLabel = (UILabel *)subview;
            else secondLabel = (UILabel *)subview;
        }
    }
    /* Prefer glass toggle layout metrics when present */
    if (glassToggle && !toggle) {
        toggle = (UISwitch *)glassToggle;
    }

    UIButton *trailingButton = nil;
    for (UIView *subview in container.subviews) {
        if ([subview isKindOfClass:[UIButton class]] && subview.tag == 9195) {
            trailingButton = (UIButton *)subview;
            break;
        }
    }

    if (trailingButton) {
        CGFloat buttonWidth = [self f4c_rowButtonWidth];
        CGFloat buttonHeight = [self f4c_rowControlHeight];
        CGFloat labelWidth = MAX(rowWidth - buttonWidth - 12.0, 20.0);
        CGFloat labelHeight = 20.0;
        if (firstLabel) {
            firstLabel.numberOfLines = 2;
            firstLabel.lineBreakMode = NSLineBreakByWordWrapping;
            CGSize fit = [firstLabel sizeThatFits:CGSizeMake(labelWidth, CGFLOAT_MAX)];
            labelHeight = MIN(MAX(ceil(fit.height), firstLabel.font.lineHeight),
                              ceil(firstLabel.font.lineHeight * 2.0));
        }
        CGFloat rowHeight = MAX([self f4c_rowHeight],
                                MAX(labelHeight + 12.0, buttonHeight + 10.0));
        CGRect cf = container.frame;
        cf.size.height = rowHeight;
        container.frame = cf;
        trailingButton.frame = CGRectMake(rowWidth - buttonWidth,
                                          (rowHeight - buttonHeight) * 0.5,
                                          buttonWidth,
                                          buttonHeight);
        if (firstLabel) {
            firstLabel.frame = CGRectMake(0.0,
                                          (rowHeight - labelHeight) * 0.5,
                                          labelWidth,
                                          labelHeight);
        }
        UILabel *badge = [trailingButton viewWithTag:9090];
        if (badge) {
            badge.frame = CGRectMake((buttonWidth - 58.0) * 0.5,
                                     (buttonHeight - 18.0) * 0.5,
                                     58.0,
                                     18.0);
        }
        return;
    }

    if (slider) {
        UIButton *sliderBtn = nil;
        for (UIView *subview in container.subviews) {
            if ([subview isKindOfClass:[UIButton class]]) {
                sliderBtn = (UIButton *)subview;
                break;
            }
        }

        CGFloat gap = 6.0;
        CGFloat rowHeight = [self f4c_rowHeight];
        CGFloat controlH = [self f4c_rowControlHeight];
        CGRect cf = container.frame;
        cf.size.height = rowHeight;
        container.frame = cf;

        if (sliderBtn) {
            CGFloat labelWidth = MIN(62.0, rowWidth * 0.28);
            CGFloat buttonWidth = [self f4c_rowButtonWidth];
            CGFloat valueWidth = MIN(28.0, rowWidth * 0.12);
            CGFloat sliderX = labelWidth + gap;
            CGFloat sliderWidth = MAX(rowWidth - sliderX - valueWidth - buttonWidth - (gap * 3), 30.0);

            if (firstLabel) {
                firstLabel.frame = CGRectMake(0.0, (rowHeight - 18.0) * 0.5, labelWidth, 18.0);
                firstLabel.adjustsFontSizeToFitWidth = YES;
                firstLabel.minimumScaleFactor = 0.8;
            }
            slider.frame = CGRectMake(sliderX, (rowHeight - 24.0) * 0.5, sliderWidth, 24.0);
            if (secondLabel) {
                secondLabel.frame = CGRectMake(sliderX + sliderWidth + gap, (rowHeight - 18.0) * 0.5, valueWidth, 18.0);
            }
            sliderBtn.frame = CGRectMake(rowWidth - buttonWidth, (rowHeight - controlH) * 0.5, buttonWidth, controlH);
            [self f4c_applyPremiumButtonStyle:sliderBtn];
        } else {
            CGFloat labelWidth = MIN(44.0, rowWidth * 0.20);
            CGFloat valueWidth = MIN(40.0, rowWidth * 0.18);
            CGFloat sliderX = labelWidth + gap;
            CGFloat sliderWidth = MAX(rowWidth - sliderX - valueWidth - gap, 30.0);

            if (firstLabel) {
                firstLabel.frame = CGRectMake(0.0, (rowHeight - 18.0) * 0.5, labelWidth, 18.0);
            }
            if (secondLabel) {
                secondLabel.frame = CGRectMake(rowWidth - valueWidth, (rowHeight - 18.0) * 0.5, valueWidth, 18.0);
            }
            slider.frame = CGRectMake(sliderX, (rowHeight - 24.0) * 0.5, sliderWidth, 24.0);
        }
        return;
    }


    if (toggle) {
        /* description removed from the API — switch rows are title + toggle only */
        CGFloat labelMaxW = MAX(rowWidth - 58.0, 20.0);
        CGFloat toggleH = 31.0;
        CGFloat titleH = 18.0;

        UILabel *titleLabel = firstLabel;

        if (titleLabel) {
            titleLabel.numberOfLines = 2;
            titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
            CGSize fit = [titleLabel sizeThatFits:CGSizeMake(labelMaxW, CGFLOAT_MAX)];
            CGFloat maxTwo = ceil(titleLabel.font.lineHeight * 2.0);
            titleH = MIN(MAX(ceil(fit.height), titleLabel.font.lineHeight), maxTwo);
        }

        CGFloat rowHeight = MAX([self f4c_rowHeight], titleH + 12.0);
        CGRect cf = container.frame;
        cf.size.height = rowHeight;
        container.frame = cf;

        /* Glass switch (tag 9288) or legacy UISwitch */
        if (toggle.tag == 9288) {
            CGFloat gw = kF4CGlassSW, gh = kF4CGlassSH;
            toggle.transform = CGAffineTransformIdentity;
            CGFloat yToggle = MAX((rowHeight - gh) * 0.5, 4.0);
            toggle.frame = CGRectMake(rowWidth - gw, yToggle, gw, gh);
            [self f4c_resetGlassSwitchGeometry:toggle];
            CGRect tf = toggle.frame;
            tf.origin = CGPointMake(rowWidth - gw, yToggle);
            toggle.frame = tf;
        } else {
            CGAffineTransform saved = toggle.transform;
            toggle.transform = CGAffineTransformIdentity;
            toggle.frame = CGRectMake(rowWidth - 51.0,
                                      MAX((rowHeight - toggleH) * 0.5, 4.0),
                                      51.0,
                                      toggleH);
            toggle.transform = saved;
        }

        if (titleLabel) {
            titleLabel.frame = CGRectMake(0.0, (rowHeight - titleH) * 0.5, labelMaxW, titleH);
        }
        return;
    }

    if ([container viewWithTag:9997]) {
        CGFloat boxX = rowWidth - 34.0;
        CGFloat fieldWidth = 58.0;
        CGFloat fieldX = boxX - fieldWidth - 10.0;
        CGFloat labelMaxW = MAX(fieldX - 19.0, 40.0);
        CGFloat titleH = 20.0;
        UILabel *titleLabel = nil;
        for (UIView *subview in container.subviews) {
            if ([subview isKindOfClass:[UILabel class]] && subview.tag != 9192) {
                titleLabel = (UILabel *)subview;
                break;
            }
        }
        if (titleLabel) {
            titleLabel.numberOfLines = 2;
            titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
            titleLabel.adjustsFontSizeToFitWidth = NO;
            CGSize fit = [titleLabel sizeThatFits:CGSizeMake(labelMaxW, CGFLOAT_MAX)];
            CGFloat maxTwo = ceil(titleLabel.font.lineHeight * 2.0);
            titleH = MIN(MAX(ceil(fit.height), titleLabel.font.lineHeight), maxTwo);
        }
        CGFloat controlH = [self f4c_rowControlHeight];
        CGFloat rowHeight = MAX([self f4c_rowHeight], titleH + 20.0);
        CGFloat controlCenterY = rowHeight * 0.5 + 2.0;
        CGRect cf = container.frame;
        cf.size.height = rowHeight;
        container.frame = cf;

        for (UIView *subview in container.subviews) {
            if ([subview isKindOfClass:[UILabel class]] && subview.tag != 9192) {
                subview.frame =
                    CGRectMake(11.0,
                               controlCenterY - titleH * 0.5,
                               labelMaxW,
                               titleH);
            } else if ([subview isKindOfClass:[UITextField class]] && subview.tag == 9193) {
                subview.frame = CGRectMake(fieldX, controlCenterY - controlH * 0.5, fieldWidth, controlH);
            } else if ([subview isKindOfClass:[UIButton class]] && subview.tag == 9191) {
                subview.frame = CGRectMake(boxX, controlCenterY - 11.0, 22.0, 22.0);
            } else if ([subview isKindOfClass:[UILabel class]] && subview.tag == 9192) {
                subview.frame = CGRectMake(rowWidth - 48.0, 1.0, 42.0, 14.0);
            } else if (subview.tag == 9997) {
                CGFloat barH = MIN(24.0, rowHeight - 12.0);
                subview.frame = CGRectMake(0.0, controlCenterY - barH * 0.5, 3.0, barH);
            }
        }
        return;
    }

    UIButton *plainCheckbox = nil;
    BOOL hasInlineCombo = NO;
    for (UIView *subview in container.subviews) {
        if (![subview isKindOfClass:[UIButton class]]) continue;
        UIButton *btn = (UIButton *)subview;
        if (objc_getAssociatedObject(btn, "comboOptions")) {
            hasInlineCombo = YES;
        }
        if (btn.tag == 9191 &&
            !objc_getAssociatedObject(btn, "comboOptions") &&
            !objc_getAssociatedObject(btn, "integerTextField")) {
            plainCheckbox = btn;
        }
    }

    /* Plain checkbox only — skip when row also has combo/confirm (standard layout). */
    if (plainCheckbox && !hasInlineCombo) {
        UILabel *valueLabel = nil;
        UILabel *titleLabel = nil;
        for (UIView *subview in container.subviews) {
            if (![subview isKindOfClass:[UILabel class]]) continue;
            UILabel *label = (UILabel *)subview;
            if (label.textAlignment == NSTextAlignmentRight) valueLabel = label;
            else titleLabel = label;
        }

        CGFloat valueW = valueLabel ? 72.0 : 0.0;
        CGFloat titleMaxW = MAX(rowWidth - 28.0 - (valueLabel ? (valueW + 8.0) : 0.0), 20.0);
        CGFloat titleH = 20.0;
        if (titleLabel) {
            titleLabel.numberOfLines = 2;
            titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
            CGSize fit = [titleLabel sizeThatFits:CGSizeMake(titleMaxW, CGFLOAT_MAX)];
            CGFloat maxTwo = ceil(titleLabel.font.lineHeight * 2.0);
            titleH = MIN(MAX(ceil(fit.height), titleLabel.font.lineHeight), maxTwo);
        }
        CGFloat rowHeight = MAX([self f4c_rowHeight], titleH + 16.0);
        CGRect cf = container.frame;
        cf.size.height = rowHeight;
        container.frame = cf;

        plainCheckbox.frame = CGRectMake(0.0, (rowHeight - 22.0) * 0.5, 22.0, 22.0);
        if (titleLabel) {
            titleLabel.frame = CGRectMake(28.0, (rowHeight - titleH) * 0.5, titleMaxW, titleH);
        }
        if (valueLabel) {
            valueLabel.frame = CGRectMake(rowWidth - valueW,
                                          (rowHeight - 18.0) * 0.5,
                                          valueW,
                                          18.0);
        }
        return;
    }

    if (objc_getAssociatedObject(container, "f4cInputWithButton")) {
        CGFloat gap = 6.0;
        CGFloat controlH = [self f4c_rowControlHeight];
        CGFloat rowHeight = [self f4c_rowHeight];
        CGFloat controlY = (rowHeight - controlH) * 0.5;

        CGFloat labelWidth = MIN(44.0, rowWidth * 0.20);
        CGFloat buttonWidth = [self f4c_rowButtonWidth];
        CGFloat inputWidth = MAX(rowWidth - labelWidth - buttonWidth - (gap * 2), 30.0);

        UILabel *titleLabel = nil;
        UITextField *field = nil;
        UIButton *confirmBtn = nil;
        for (UIView *v in container.subviews) {
            if ([v isKindOfClass:[UILabel class]]) titleLabel = (UILabel *)v;
            else if ([v isKindOfClass:[UITextField class]]) field = (UITextField *)v;
            else if ([v isKindOfClass:[UIButton class]]) confirmBtn = (UIButton *)v;
        }
        if (titleLabel) titleLabel.frame = CGRectMake(0.0, (rowHeight - 18.0) * 0.5, labelWidth, 18.0);
        if (field) field.frame = CGRectMake(labelWidth + gap, controlY, inputWidth, controlH);
        if (confirmBtn) confirmBtn.frame = CGRectMake(rowWidth - buttonWidth, controlY, buttonWidth, controlH);
        CGRect cf = container.frame;
        cf.size.height = rowHeight;
        container.frame = cf;
        return;
    }

    if (objc_getAssociatedObject(container, "f4cComboWithInput")) {
        CGFloat gap = 6.0;
        CGFloat controlH = [self f4c_rowControlHeight];
        CGFloat rowHeight = [self f4c_rowHeight];
        CGFloat controlY = (rowHeight - controlH) * 0.5;

        UILabel *titleLabel = nil;
        UIButton *comboBtn = nil;
        UITextField *field = nil;
        for (UIView *v in container.subviews) {
            if ([v isKindOfClass:[UILabel class]]) {
                titleLabel = (UILabel *)v;
            } else if ([v isKindOfClass:[UIButton class]] && objc_getAssociatedObject(v, "comboOptions")) {
                comboBtn = (UIButton *)v;
            } else if ([v isKindOfClass:[UITextField class]]) {
                field = (UITextField *)v;
            }
        }

        CGFloat startX = 0.0;
        CGFloat remWidth = rowWidth;
        if (titleLabel) {
            CGFloat labelWidth = MIN(44.0, rowWidth * 0.20);
            titleLabel.frame = CGRectMake(0.0, (rowHeight - 18.0) * 0.5, labelWidth, 18.0);
            startX = labelWidth + gap;
            remWidth = MAX(rowWidth - startX, 40.0);
        }

        CGFloat comboWidth = floor((remWidth - gap) * 0.56);
        CGFloat inputWidth = MAX(remWidth - comboWidth - gap, 30.0);

        if (comboBtn) {
            comboBtn.frame = CGRectMake(startX, controlY, comboWidth, controlH);
            [self f4c_configureInlineComboChrome:comboBtn width:comboWidth];
        }
        if (field) {
            field.frame = CGRectMake(rowWidth - inputWidth, controlY, inputWidth, controlH);
        }
        CGRect cf = container.frame;
        cf.size.height = rowHeight;
        container.frame = cf;
        return;
    }


    UITextField *plainField = nil;
    for (UIView *subview in container.subviews) {
        if ([subview isKindOfClass:[UITextField class]] && subview.tag != 9193) {
            plainField = (UITextField *)subview;
            break;
        }
    }

    if (plainField) {
        UILabel *titleLabel = nil;
        for (UIView *subview in container.subviews) {
            if ([subview isKindOfClass:[UILabel class]]) {
                titleLabel = (UILabel *)subview;
                break;
            }
        }
        if (titleLabel) {
            titleLabel.frame = CGRectMake(0.0, 0.0, rowWidth, 16.0);
        }
        plainField.frame = CGRectMake(0.0, 20.0, rowWidth, 32.0);
        return;
    }


    [self f4c_layoutStandardRowSubviewsInContainer:container];
}

- (CGFloat)f4c_preferredInlineComboWidthForOptions:(NSArray<NSString *> *)options
                                      contentWidth:(CGFloat)contentWidth
                                        labelWidth:(CGFloat)labelWidth
                                       buttonWidth:(CGFloat)buttonWidth
                                               gap:(CGFloat)gap {
    UIFont *font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    CGFloat maxTextWidth = 0.0;

    for (NSString *option in options) {
        if (![option isKindOfClass:[NSString class]]) continue;
        CGRect textRect =
            [option boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, 28.0)
                                 options:(NSStringDrawingUsesLineFragmentOrigin |
                                          NSStringDrawingUsesFontLeading)
                              attributes:@{NSFontAttributeName: font}
                                 context:nil];
        maxTextWidth = MAX(maxTextWidth, ceil(textRect.size.width));
    }

    CGFloat paddedWidth = maxTextWidth + 8.0 + 22.0;
    CGFloat maxAllowed =
        contentWidth - labelWidth - buttonWidth - (gap * 2.0);
    if (maxAllowed < 72.0) maxAllowed = 72.0;

    return MIN(MAX(paddedWidth, 72.0), maxAllowed);
}

- (CGFloat)f4c_inlineComboOriginXForWidth:(CGFloat)comboWidth
                             contentWidth:(CGFloat)contentWidth
                              buttonWidth:(CGFloat)buttonWidth
                                      gap:(CGFloat)gap {
    return contentWidth - buttonWidth - gap - comboWidth;
}

- (CGFloat)f4c_sectionDividerHeaderHeight {
    return 26.0; /* room for title badge above card body */
}

// Card top border Y — title badge straddles this line (center of badge).
- (CGFloat)f4c_sectionDividerInnerTop {
    return 14.0;
}

- (CGFloat)f4c_sectionTitleBadgeHeight {
    return 20.0;
}

- (CGFloat)f4c_sectionCardTopPadding {
    /* badge overhang into glass is badgeH/2; keep clear gap under badge */
    return ceil([self f4c_sectionTitleBadgeHeight] * 0.5) + 12.0; /* 22 */
}

- (CGFloat)f4c_sectionCardBottomPadding {
    return 14.0;
}

- (CGFloat)f4c_sectionCardRowSpacing {
    return 8.0;
}

- (CGFloat)f4c_sectionCardSpacing {
    return 6.0;
}


/*
 * Section title — glass legend box on card top edge:
 *
 *     ╭───────╮
 * ───┤ Title ├───
 *     ╰───────╯
 */
- (void)f4c_styleSectionTitleBadge:(UILabel *)titleLabel {
    if (!titleLabel) return;
    UIColor *accent = self.accentColor
        ?: [UIColor colorWithRed:37.0/255.0 green:99.0/255.0 blue:235.0/255.0 alpha:1.0];
    titleLabel.textColor = accent;
    titleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightBold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    /* 100% solid opaque white background clipped cleanly to rounded corners */
    titleLabel.backgroundColor = [UIColor colorWithWhite:1.0 alpha:1.0];
    titleLabel.layer.cornerRadius = 10.0;
    titleLabel.layer.masksToBounds = YES;
    titleLabel.layer.borderWidth = 1.35;
    titleLabel.layer.borderColor = [accent colorWithAlphaComponent:0.40].CGColor;
    titleLabel.layer.zPosition = 30.0;
}

- (void)f4c_layoutSectionDividerHeader:(UIView *)card
                          contentWidth:(CGFloat)contentWidth {
    UILabel *titleLabel = [card viewWithTag:9998];
    UIView *divider = [card viewWithTag:9995];
    UIView *inner = [card viewWithTag:9996];
    if (!titleLabel) return;

    CGFloat horizontalTextPadding = 10.0;
    CGFloat legendLeading = 14.0;
    CGSize titleSize =
        [titleLabel.text sizeWithAttributes:@{NSFontAttributeName: titleLabel.font}];
    CGFloat titleWidth = MIN(ceil(titleSize.width) + (horizontalTextPadding * 2.0),
                             MAX(contentWidth - (legendLeading * 2.0), 48.0));

    CGFloat badgeH = [self f4c_sectionTitleBadgeHeight];
    CGFloat borderY = [self f4c_sectionDividerInnerTop];
    CGFloat legendY = borderY - badgeH * 0.5;
    if (legendY < 0.0) legendY = 0.0;

    CGRect badgeFrame = CGRectMake(legendLeading, legendY, titleWidth, badgeH);
    titleLabel.frame = badgeFrame;
    [self f4c_styleSectionTitleBadge:titleLabel];

    /* Shadow view behind title label to cast drop shadow while keeping label rounded */
    UIView *shadowView = [card viewWithTag:9994];
    if (!shadowView) {
        shadowView = [[UIView alloc] initWithFrame:badgeFrame];
        shadowView.tag = 9994;
        shadowView.backgroundColor = [UIColor whiteColor];
        shadowView.layer.cornerRadius = 10.0;
        shadowView.layer.masksToBounds = NO;
        [card addSubview:shadowView];
    }
    shadowView.frame = badgeFrame;
    shadowView.layer.cornerRadius = 10.0;
    shadowView.layer.shadowColor = [self f4c_glassShadowColor].CGColor;
    shadowView.layer.shadowOpacity = 0.30;
    shadowView.layer.shadowRadius = 4.5;
    shadowView.layer.shadowOffset = CGSizeMake(0, 2.5);
    shadowView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:shadowView.bounds cornerRadius:10.0].CGPath;
    shadowView.layer.zPosition = 29.0;

    if (divider) {
        divider.hidden = YES;
        divider.frame = CGRectZero;
        divider.layer.borderWidth = 0.0;
    }

    if (inner) {
        [card sendSubviewToBack:inner];
    }
    [card bringSubviewToFront:shadowView];
    [card bringSubviewToFront:titleLabel];
}


- (void)f4c_finalizeSectionCard {
    if (!self.currentSectionCard || !self.sectionCardInner) return;

    CGFloat contentWidth = [self f4c_contentLayoutWidth];
    [self f4c_layoutSectionCard:self.currentSectionCard
                            atY:self.currentSectionCard.frame.origin.y
                   contentWidth:contentWidth];

    self.currentSectionCard = nil;
    self.sectionCardInner = nil;
}

- (void)setMenuLogoCharacter:(NSString *)character {
    self.sidebarLogoChar.text = character.length > 0 ? character : @"F4";
}

- (void)setSidebarFooterText:(NSString *)text {
    self.sidebarFooterLabel.text = text ?: @"";
    self.sidebarFooterLabel.textAlignment = NSTextAlignmentCenter;
    [self f4c_layoutChrome];
    [self updateLayout];
}

- (void)setFooterText:(NSString *)text {
    [self setSidebarFooterText:text];
}

- (void)f4c_checkboxTapped:(UIButton *)sender {
    void (^handler)(BOOL) = objc_getAssociatedObject(sender, "checkboxHandler");
    if (!handler) return;

    sender.selected = !sender.selected;
    sender.backgroundColor = sender.selected ? self.accentColor : [UIColor whiteColor];
    [sender setTitle:(sender.selected ? @"✓" : @"") forState:UIControlStateNormal];
    [sender setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
    [sender setTitleColor:[UIColor clearColor] forState:UIControlStateNormal];

    UILabel *badge = objc_getAssociatedObject(sender, "checkboxBadge");
    if (badge) {
        [badge.layer removeAllAnimations];

        if (sender.selected) {
            badge.hidden = NO;
            badge.alpha = 0.0;
            badge.transform = CGAffineTransformMakeScale(0.82, 0.82);

            [UIView animateWithDuration:0.16
                                  delay:0
                                options:UIViewAnimationOptionCurveEaseOut |
                                        UIViewAnimationOptionAllowUserInteraction
                             animations:^{
                badge.alpha = 1.0;
                badge.transform = CGAffineTransformIdentity;
            } completion:nil];
        } else {
            [UIView animateWithDuration:0.14
                                  delay:0
                                options:UIViewAnimationOptionCurveEaseIn |
                                        UIViewAnimationOptionAllowUserInteraction
                             animations:^{
                badge.alpha = 0.0;
                badge.transform = CGAffineTransformMakeScale(0.82, 0.82);
            } completion:^(BOOL finished) {
                badge.hidden = YES;
                badge.transform = CGAffineTransformIdentity;
            }];
        }
    }

    handler(sender.selected);
}

- (void)f4c_checkboxProxyTapped:(UIButton *)sender {
    UIButton *box = objc_getAssociatedObject(sender, "checkboxProxy");
    if (box) [self f4c_checkboxTapped:box];
}

- (void)addCheckbox:(NSString *)title handler:(void (^)(BOOL isOn))handler {
    UIView *parent = [self f4c_activeContentContainer];
    CGFloat contentWidth = [self f4c_effectiveRowWidthForParent:parent];
    const CGFloat containerHeight = 46.0;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, contentWidth, containerHeight)];
    if (!self.sectionCardInner) {
        container.tag = self.currentCategoryCounter + 1000;
    }
    objc_setAssociatedObject(container, "f4cHasDescription", @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIButton *box = [UIButton buttonWithType:UIButtonTypeCustom];
    box.frame = CGRectMake(0, 12.0, 22.0, 22.0);
    box.layer.cornerRadius = 4.0;
    box.layer.borderWidth = 1.2;
    box.layer.borderColor = [self f4c_cardBorderColor].CGColor;
    box.backgroundColor = [UIColor whiteColor];
    box.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [box setTitle:@"" forState:UIControlStateNormal];
    [box setTitle:@"✓" forState:UIControlStateSelected];
    [box setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
    box.tag = 9191;
    objc_setAssociatedObject(box, "checkboxHandler", handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [box addTarget:self action:@selector(f4c_checkboxTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:box];
    self.checkboxes[title] = box;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(28.0, 12.0, contentWidth - 90.0, 20.0)];
    label.text = title;
    label.textColor = [self f4c_primaryTextColor];
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    label.numberOfLines = 2;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    [container addSubview:label];

    [parent addSubview:container];
    [self f4c_relayoutRowContainer:container];
    [self updateLayout];
}

- (void)f4c_commitIntegerTextField:(UITextField *)textField {
    if (!textField) return;

    NSInteger minValue =
        [objc_getAssociatedObject(textField, "integerMin") integerValue];
    NSInteger maxValue =
        [objc_getAssociatedObject(textField, "integerMax") integerValue];

    NSString *raw = textField.text ?: @"";
    NSCharacterSet *nonDigits =
        [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    NSString *digits =
        [[raw componentsSeparatedByCharactersInSet:nonDigits]
            componentsJoinedByString:@""];

    NSInteger value = digits.length > 0
        ? digits.integerValue
        : minValue;

    if (value < minValue) value = minValue;
    if (value > maxValue) value = maxValue;

    textField.text =
        [NSString stringWithFormat:@"%ld", (long)value];

    void (^handler)(NSInteger) =
        objc_getAssociatedObject(textField, "integerHandler");
    if (handler) handler(value);
}

- (void)f4c_integerInputEditingDidEnd:(UITextField *)textField {
    [self f4c_commitIntegerTextField:textField];
}

- (void)f4c_integerCheckboxTapped:(UIButton *)sender {
    UITextField *field =
        objc_getAssociatedObject(sender, "integerTextField");
    [self f4c_commitIntegerTextField:field];
    [self f4c_checkboxTapped:sender];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [self endEditing:YES];
}

- (void)f4c_dismissKeyboardOnBackgroundTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized) {
        [self endEditing:YES];
    }
}

- (void)f4c_finishIntegerInput:(id)sender {
    [self endEditing:YES];
}

- (void)f4c_attachDoneToolbarToTextField:(UITextField *)field {
    if (!field) return;
    field.inputAccessoryView = nil;
}




- (void)addFilteredComboCheckbox:(NSArray<NSString *> *)options ids:(NSArray<NSString *> *)ids selectedIndex:(NSInteger)index selectionHandler:(void (^)(NSInteger))selectionHandler toggleHandler:(void (^)(BOOL))toggleHandler {
    if (options.count == 0 || options.count != ids.count) return;
    if (index < 0 || index >= (NSInteger)options.count) index = 0;
    UIView *parent = [self f4c_activeContentContainer];
    CGFloat w = [self f4c_effectiveRowWidthForParent:parent];
    UIView *c = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 48)];
    if (!self.sectionCardInner) {
        c.tag = self.currentCategoryCounter + 1000;
    }
    CGFloat boxX = w - 34, filterW = 76, gap = 8;
    CGFloat comboW = MAX(boxX - filterW - gap - 8, 90);

    UIButton *combo = [UIButton buttonWithType:UIButtonTypeCustom];
    combo.frame = CGRectMake(0, 10, comboW, 30);
    combo.backgroundColor = [UIColor colorWithWhite:1 alpha:.055];
    combo.layer.cornerRadius = 5; combo.layer.borderWidth = 1;
    combo.layer.borderColor = [self.accentColor colorWithAlphaComponent:.45].CGColor;
    [combo setTitle:options[index] forState:UIControlStateNormal];
    [combo setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    combo.titleLabel.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightMedium];
    combo.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    F4CSetButtonTitleInsets(combo, UIEdgeInsetsMake(0,8,0,22));
    combo.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    UIButton *arrow = [UIButton buttonWithType:UIButtonTypeCustom];
    arrow.frame = CGRectMake(comboW-24,0,22,30); arrow.tag = 8888;
    [arrow setTitle:@"▶" forState:UIControlStateNormal];
    [arrow setTitleColor:[UIColor colorWithWhite:.62 alpha:1] forState:UIControlStateNormal];
    arrow.titleLabel.font = [UIFont systemFontOfSize:10];
    [arrow addTarget:self action:@selector(comboTapped:) forControlEvents:UIControlEventTouchUpInside];
    [combo addSubview:arrow];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = arrow.frame; close.tag = 8889; close.hidden = YES;
    [close setTitle:@"⤬" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor colorWithRed:1 green:.23 blue:.19 alpha:1] forState:UIControlStateNormal];
    [close addTarget:self action:@selector(comboCloseTapped:) forControlEvents:UIControlEventTouchUpInside];
    [combo addSubview:close];

    NSMutableArray *indices = [NSMutableArray arrayWithCapacity:options.count];
    for (NSInteger i=0;i<(NSInteger)options.count;i++) [indices addObject:@(i)];
    objc_setAssociatedObject(combo,"comboAllOptions",options,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo,"comboAllIds",ids,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo,"comboOptions",options,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo,"comboOriginalIndices",indices,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo,"comboHandler",selectionHandler,OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(combo,"comboSelectedIndex",@(index),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo,"comboArrow",arrow,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo,"comboCloseBtn",close,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    /* Whole combo body opens dropdown — not only the arrow */
    [combo addTarget:self action:@selector(comboTapped:) forControlEvents:UIControlEventTouchUpInside];

    UITextField *filter = [[UITextField alloc] initWithFrame:CGRectMake(comboW+gap,10,filterW,30)];
    filter.backgroundColor=[UIColor colorWithWhite:1 alpha:.055];
    filter.layer.cornerRadius=5; filter.layer.borderWidth=1;
    filter.layer.borderColor=[UIColor colorWithWhite:1 alpha:.12].CGColor;
    filter.textColor=[UIColor whiteColor]; filter.font=[UIFont systemFontOfSize:9.5];
    filter.attributedPlaceholder=[[NSAttributedString alloc] initWithString:@"Filter" attributes:@{NSForegroundColorAttributeName:[UIColor colorWithWhite:1 alpha:.4]}];
    filter.autocorrectionType=UITextAutocorrectionTypeNo; filter.autocapitalizationType=UITextAutocapitalizationTypeNone;
    filter.clearButtonMode=UITextFieldViewModeWhileEditing; filter.delegate=self;
    objc_setAssociatedObject(filter,"filteredComboButton",combo,OBJC_ASSOCIATION_ASSIGN);
    [filter addTarget:self action:@selector(f4c_filteredComboFilterChanged:) forControlEvents:UIControlEventEditingChanged];

    UIButton *check=[UIButton buttonWithType:UIButtonTypeCustom];
    check.frame=CGRectMake(boxX,15,24,24); check.layer.cornerRadius=5; check.layer.borderWidth=1.4;
    check.layer.borderColor=[self.accentColor colorWithAlphaComponent:.72].CGColor;
    check.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [check setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    objc_setAssociatedObject(check,"checkboxHandler",toggleHandler,OBJC_ASSOCIATION_COPY_NONATOMIC);
    [check addTarget:self action:@selector(f4c_checkboxTapped:) forControlEvents:UIControlEventTouchUpInside];

    [c addSubview:combo]; [c addSubview:filter]; [c addSubview:check];
    [parent addSubview:c];
    [self updateLayout];
}

- (void)f4c_filteredComboFilterChanged:(UITextField *)field {
    UIButton *combo=objc_getAssociatedObject(field,"filteredComboButton");
    NSArray *all=objc_getAssociatedObject(combo,"comboAllOptions");
    NSArray *ids=objc_getAssociatedObject(combo,"comboAllIds");
    if (!combo || all.count!=ids.count) return;
    NSString *q=[[[field.text ?: @"" stringByFoldingWithOptions:NSDiacriticInsensitiveSearch|NSCaseInsensitiveSearch locale:[NSLocale currentLocale]] lowercaseString] copy];
    NSMutableArray *filtered=[NSMutableArray array], *indices=[NSMutableArray array];
    for (NSInteger i=0;i<(NSInteger)all.count;i++) {
        NSString *n=[[all[i] stringByFoldingWithOptions:NSDiacriticInsensitiveSearch|NSCaseInsensitiveSearch locale:[NSLocale currentLocale]] lowercaseString];
        NSString *a=[[ids[i] stringByFoldingWithOptions:NSDiacriticInsensitiveSearch|NSCaseInsensitiveSearch locale:[NSLocale currentLocale]] lowercaseString];
        if (!q.length || [n containsString:q] || [a containsString:q]) { [filtered addObject:all[i]]; [indices addObject:@(i)]; }
    }
    [self closeComboDropdown:combo];
    if (!filtered.count) { filtered=[NSMutableArray arrayWithObject:@"Không tìm thấy"]; indices=[NSMutableArray arrayWithObject:@(-1)]; }
    objc_setAssociatedObject(combo,"comboOptions",filtered,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo,"comboOriginalIndices",indices,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)addIntegerInputCheckbox:(NSString *)title
                            min:(NSInteger)minValue
                            max:(NSInteger)maxValue
                          value:(NSInteger)value
                   valueHandler:(void (^)(NSInteger value))valueHandler
                  toggleHandler:(void (^)(BOOL isOn))toggleHandler {
    if (maxValue < minValue) {
        NSInteger temp = minValue;
        minValue = maxValue;
        maxValue = temp;
    }
    if (value < minValue) value = minValue;
    if (value > maxValue) value = maxValue;

    UIView *parent = [self f4c_activeContentContainer];
    CGFloat contentWidth = [self f4c_effectiveRowWidthForParent:parent];
    UIView *container =
        [[UIView alloc] initWithFrame:
            CGRectMake(0, 0, contentWidth, 48)];
    if (!self.sectionCardInner) {
        container.tag = self.currentCategoryCounter + 1000;
    }

    CGFloat barWidth = 3.0;
    CGFloat controlCenterY = 32.0;
    CGFloat barHeight = 24.0;
    CGFloat barY = controlCenterY - (barHeight * 0.5);

    UIView *verticalBar =
        [[UIView alloc] initWithFrame:
            CGRectMake(0, barY, barWidth, barHeight)];
    verticalBar.backgroundColor = self.accentColor;
    verticalBar.layer.cornerRadius =
        MAX(self.layer.cornerRadius * 0.5, 1.5);
    verticalBar.tag = 9997;
    [container addSubview:verticalBar];

    CGFloat boxX = container.frame.size.width - 34.0;
    CGFloat fieldWidth = 58.0;
    CGFloat fieldX = boxX - fieldWidth - 10.0;

    UILabel *label =
        [[UILabel alloc] initWithFrame:
            CGRectMake(
                11.0,
                controlCenterY - 10.0,
                MAX(fieldX - 19.0, 40.0),
                20.0
            )];
    label.text = title;
    label.textColor = [UIColor whiteColor];
    label.font =
        [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.68;
    label.numberOfLines = 1;
    label.textAlignment = NSTextAlignmentLeft;
    [container addSubview:label];

    UITextField *field =
        [[UITextField alloc] initWithFrame:
            CGRectMake(fieldX, 18.0, fieldWidth, 28.0)];
    field.backgroundColor =
        [UIColor colorWithWhite:1.0 alpha:0.055];
    field.layer.cornerRadius = 5.0;
    field.layer.borderWidth = 1.0;
    field.layer.borderColor =
        [self.accentColor colorWithAlphaComponent:0.55].CGColor;
    field.textColor = [UIColor whiteColor];
    field.font =
        [UIFont monospacedDigitSystemFontOfSize:11
                                         weight:UIFontWeightSemibold];
    field.textAlignment = NSTextAlignmentCenter;
    field.keyboardType = UIKeyboardTypeNumberPad;
    field.tag = 9193;
    field.text =
        [NSString stringWithFormat:@"%ld", (long)value];
    field.delegate = self;
    field.returnKeyType = UIReturnKeyDone;

    objc_setAssociatedObject(
        field,
        "integerMin",
        @(minValue),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    objc_setAssociatedObject(
        field,
        "integerMax",
        @(maxValue),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    objc_setAssociatedObject(
        field,
        "integerHandler",
        valueHandler,
        OBJC_ASSOCIATION_COPY_NONATOMIC
    );

    [field addTarget:self
              action:@selector(f4c_integerInputEditingDidEnd:)
    forControlEvents:UIControlEventEditingDidEnd];

    field.inputAccessoryView = nil;

    [container addSubview:field];
    self.textFields[title] = field;


    UIButton *box =
        [UIButton buttonWithType:UIButtonTypeCustom];
    box.frame = CGRectMake(boxX, 21.0, 22.0, 22.0);
    box.layer.cornerRadius = 5.0;
    box.layer.borderWidth = 1.7;
    box.layer.borderColor = self.accentColor.CGColor;
    box.backgroundColor = [UIColor clearColor];
    box.titleLabel.font =
        [UIFont systemFontOfSize:15 weight:UIFontWeightBlack];
    [box setTitleColor:[UIColor whiteColor]
              forState:UIControlStateNormal];
    [box setTitle:@"" forState:UIControlStateNormal];
    box.tag = 9191;

    UILabel *badge =
        [[UILabel alloc] initWithFrame:
            CGRectMake(
                container.frame.size.width - 48.0,
                1.0,
                42.0,
                14.0
            )];
    badge.text = @"ACTIVE";
    badge.textAlignment = NSTextAlignmentCenter;
    badge.textColor = [UIColor whiteColor];
    badge.backgroundColor =
        [[UIColor colorWithRed:16.0/255.0
                         green:185.0/255.0
                          blue:129.0/255.0
                         alpha:1.0]
            colorWithAlphaComponent:0.88];
    badge.font =
        [UIFont systemFontOfSize:8 weight:UIFontWeightBlack];
    badge.layer.cornerRadius = 4.0;
    badge.layer.borderWidth = 1.0;
    badge.layer.borderColor =
        [[UIColor whiteColor] colorWithAlphaComponent:0.18].CGColor;
    badge.layer.masksToBounds = YES;
    badge.userInteractionEnabled = NO;
    badge.alpha = 0.0;
    badge.hidden = YES;
    badge.tag = 9192;
    [container addSubview:badge];

    objc_setAssociatedObject(
        box,
        "checkboxHandler",
        toggleHandler,
        OBJC_ASSOCIATION_COPY_NONATOMIC
    );
    objc_setAssociatedObject(
        box,
        "checkboxBadge",
        badge,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    objc_setAssociatedObject(
        box,
        "integerTextField",
        field,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    [box addTarget:self
            action:@selector(f4c_integerCheckboxTapped:)
  forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:box];

    UIButton *boxHit =
        [UIButton buttonWithType:UIButtonTypeCustom];
    boxHit.frame =
        CGRectInset(box.frame, -8.0, -7.0);
    boxHit.backgroundColor = [UIColor clearColor];
    objc_setAssociatedObject(
        boxHit,
        "checkboxProxy",
        box,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    [boxHit addTarget:self
               action:@selector(f4c_checkboxProxyTapped:)
     forControlEvents:UIControlEventTouchUpInside];
    [container insertSubview:boxHit belowSubview:box];

    [parent addSubview:container];
    [self updateLayout];
}

- (void)addIntegerInput:(NSString *)title
                    min:(NSInteger)minValue
                    max:(NSInteger)maxValue
                  value:(NSInteger)value
           valueHandler:(void (^)(NSInteger value))valueHandler {
    UIView *parent = [self f4c_activeContentContainer];
    CGFloat rowWidth = [self f4c_effectiveRowWidthForParent:parent];
    CGFloat controlH = [self f4c_rowControlHeight];
    CGFloat integerW = [self f4c_rowIntegerInputWidth];
    CGFloat rowHeight = 46.0;
    CGFloat controlY = [self f4c_rowControlYForRowHeight:rowHeight];

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, rowWidth, rowHeight)];
    if (!self.sectionCardInner) {
        container.tag = self.currentCategoryCounter + 1000;
    }

    UILabel *label =
        [[UILabel alloc] initWithFrame:CGRectMake(0.0,
                                                  (rowHeight - 22.0) * 0.5,
                                                  MAX(rowWidth - integerW - 16.0, 20.0),
                                                  22.0)];
    label.text = title;
    label.textColor = [self f4c_primaryTextColor];
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    label.numberOfLines = 2;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    [container addSubview:label];

    UITextField *field =
        [[UITextField alloc] initWithFrame:CGRectMake(rowWidth - integerW,
                                                      controlY,
                                                      integerW,
                                                      controlH)];
    field.backgroundColor = [self f4c_inputBackgroundColor];
    field.layer.cornerRadius = [self f4c_rowControlCornerRadius];
    field.layer.borderWidth = 0.0;
    field.textColor = [self f4c_primaryTextColor];
    field.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    field.textAlignment = NSTextAlignmentCenter;
    field.keyboardType = UIKeyboardTypeNumberPad;
    field.text = [NSString stringWithFormat:@"%ld", (long)value];
    field.tag = 9193;
    field.delegate = self;

    objc_setAssociatedObject(field, "integerMin", @(minValue), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(field, "integerMax", @(maxValue), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(field, "integerHandler", valueHandler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [field addTarget:self action:@selector(f4c_integerInputEditingDidEnd:) forControlEvents:UIControlEventEditingDidEnd];

    field.inputAccessoryView = nil;

    [container addSubview:field];
    self.textFields[title] = field;
    [parent addSubview:container];
    [self f4c_relayoutRowContainer:container];
    [self updateLayout];
}


- (void)addInlineCombo:(NSString *)title
               options:(NSArray<NSString *> *)options
         selectedIndex:(NSInteger)index
               handler:(void (^)(NSInteger selectedIndex))handler {
    if (options.count == 0) return;
    if (index < 0 || index >= (NSInteger)options.count) index = 0;

    UIView *parent = [self f4c_activeContentContainer];
    CGFloat rowWidth = [self f4c_effectiveRowWidthForParent:parent];
    CGFloat controlH = [self f4c_rowControlHeight];
    CGFloat comboW = [self f4c_rowStandardComboWidth];
    CGFloat rowHeight = 46.0;
    CGFloat controlY = [self f4c_rowControlYForRowHeight:rowHeight];

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, rowWidth, rowHeight)];
    if (!self.sectionCardInner) {
        container.tag = self.currentCategoryCounter + 1000;
    }

    UILabel *label =
        [[UILabel alloc] initWithFrame:CGRectMake(0.0,
                                                  (rowHeight - 22.0) * 0.5,
                                                  MAX(rowWidth - comboW - 16.0, 20.0),
                                                  22.0)];
    label.text = title;
    label.textColor = [self f4c_primaryTextColor];
    label.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];
    label.numberOfLines = 2;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    [container addSubview:label];

    UIButton *combo = [UIButton buttonWithType:UIButtonTypeCustom];
    combo.frame = CGRectMake(rowWidth - comboW, controlY, comboW, controlH);
    combo.backgroundColor = [self f4c_inputBackgroundColor];
    combo.layer.cornerRadius = [self f4c_rowControlCornerRadius];
    combo.layer.borderWidth = 0.0;
    [combo setTitle:options[index] forState:UIControlStateNormal];
    [combo setTitleColor:[self f4c_primaryTextColor] forState:UIControlStateNormal];
    combo.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    combo.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    F4CSetButtonTitleInsets(combo, UIEdgeInsetsMake(0, 4, 0, 16));


    UIButton *arrow = [UIButton buttonWithType:UIButtonTypeCustom];
    arrow.frame = CGRectMake(comboW - 22.0, 0.0, 20.0, controlH);
    arrow.tag = 8888;
    [arrow setTitle:@"▾" forState:UIControlStateNormal];
    [arrow setTitleColor:[self f4c_secondaryTextColor] forState:UIControlStateNormal];
    arrow.titleLabel.font = [UIFont systemFontOfSize:10];
    [arrow addTarget:self action:@selector(comboTapped:) forControlEvents:UIControlEventTouchUpInside];
    [combo addSubview:arrow];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = arrow.frame;
    close.tag = 8889;
    close.hidden = YES;
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:[self f4c_secondaryTextColor] forState:UIControlStateNormal];
    [close addTarget:self action:@selector(comboCloseTapped:) forControlEvents:UIControlEventTouchUpInside];
    [combo addSubview:close];

    objc_setAssociatedObject(combo, "comboOptions", options, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo, "comboHandler", handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(combo, "comboSelectedIndex", @(index), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo, "comboArrow", arrow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo, "comboCloseBtn", close, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    /* Whole combo body opens dropdown — not only the arrow */
    [combo addTarget:self action:@selector(comboTapped:) forControlEvents:UIControlEventTouchUpInside];

    [container addSubview:combo];
    [parent addSubview:container];
    [self updateLayout];
}

- (void)addInlineComboWithButton:(NSString *)title
                         options:(NSArray<NSString *> *)options
                   selectedIndex:(NSInteger)index
                selectionHandler:(void (^)(NSInteger selectedIndex))selectionHandler
                     buttonTitle:(NSString *)buttonTitle
                   buttonHandler:(void (^)(void))buttonHandler {
    if (options.count == 0 || buttonTitle.length == 0) return;
    if (index < 0 || index >= (NSInteger)options.count) index = 0;

    UIView *parent = [self f4c_activeContentContainer];
    CGFloat rowWidth = [self f4c_effectiveRowWidthForParent:parent];
    CGFloat rowHeight = [self f4c_rowHeight];
    CGFloat buttonWidth = [self f4c_rowButtonWidth];
    CGFloat labelWidth = 72.0;
    CGFloat gap = 8.0;
    CGFloat controlH = [self f4c_rowControlHeight];
    CGFloat controlY = [self f4c_rowControlYForRowHeight:rowHeight];
    CGFloat comboWidth =
        [self f4c_preferredInlineComboWidthForOptions:options
                                         contentWidth:rowWidth
                                           labelWidth:labelWidth
                                          buttonWidth:buttonWidth
                                                  gap:gap];

    UIView *container =
        [[UIView alloc] initWithFrame:CGRectMake(0, 0, rowWidth, rowHeight)];
    if (!self.sectionCardInner) {
        container.tag = self.currentCategoryCounter + 1000;
    }

    UILabel *label =
        [[UILabel alloc] initWithFrame:CGRectMake(0.0, controlY + 2.0, labelWidth, 18.0)];
    label.text = title;
    label.textColor = [self f4c_primaryTextColor];
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    [container addSubview:label];

    CGFloat comboX =
        [self f4c_inlineComboOriginXForWidth:comboWidth
                                contentWidth:rowWidth
                                 buttonWidth:buttonWidth
                                         gap:gap];

    UIButton *combo = [UIButton buttonWithType:UIButtonTypeCustom];
    combo.frame = CGRectMake(comboX, controlY, comboWidth, controlH);
    combo.backgroundColor = [self f4c_inputBackgroundColor];
    combo.layer.cornerRadius = [self f4c_rowControlCornerRadius];
    combo.layer.borderWidth = 1.0;
    combo.layer.borderColor = [self f4c_cardBorderColor].CGColor;
    [combo setTitle:options[index] forState:UIControlStateNormal];
    [combo setTitleColor:[self f4c_primaryTextColor] forState:UIControlStateNormal];
    combo.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    combo.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    F4CSetButtonTitleInsets(combo, UIEdgeInsetsMake(0, 4, 0, 16));
    combo.titleLabel.lineBreakMode = NSLineBreakByClipping;

    UIButton *arrow = [UIButton buttonWithType:UIButtonTypeCustom];
    arrow.frame = CGRectMake(comboWidth - 22.0, 0, 20.0, 28.0);
    arrow.tag = 8888;
    [arrow setTitle:@"▾" forState:UIControlStateNormal];
    [arrow setTitleColor:[self f4c_secondaryTextColor] forState:UIControlStateNormal];
    arrow.titleLabel.font = [UIFont systemFontOfSize:10];
    [arrow addTarget:self action:@selector(comboTapped:) forControlEvents:UIControlEventTouchUpInside];
    [combo addSubview:arrow];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = arrow.frame;
    close.tag = 8889;
    close.hidden = YES;
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:[self f4c_secondaryTextColor] forState:UIControlStateNormal];
    [close addTarget:self action:@selector(comboCloseTapped:) forControlEvents:UIControlEventTouchUpInside];
    [combo addSubview:close];

    objc_setAssociatedObject(combo, "comboOptions", options, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo, "comboHandler", selectionHandler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(combo, "comboSelectedIndex", @(index), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo, "comboArrow", arrow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo, "comboCloseBtn", close, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [combo addTarget:self action:@selector(comboTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIButton *confirm = [UIButton buttonWithType:UIButtonTypeCustom];
    confirm.frame = CGRectMake(rowWidth - buttonWidth, controlY, buttonWidth, controlH);
    confirm.tag = 9194;
    [confirm setTitle:buttonTitle forState:UIControlStateNormal];
    [confirm setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    confirm.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    confirm.layer.cornerRadius = [self f4c_rowControlCornerRadius];
    confirm.layer.masksToBounds = YES;
    [self f4c_applyPremiumButtonStyle:confirm];
    objc_setAssociatedObject(confirm, "buttonHandler", buttonHandler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(confirm, "buttonRawTitle", buttonTitle, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [confirm addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];

    [container addSubview:combo];
    [container addSubview:confirm];
    [parent addSubview:container];
    self.buttons[buttonTitle] = confirm;
    [self updateLayout];
}

- (void)addInputWithButton:(NSString *)title
               placeholder:(NSString *)placeholder
               buttonTitle:(NSString *)buttonTitle
                   handler:(void (^)(NSString *text))handler {
    UIView *parent = [self f4c_activeContentContainer];
    CGFloat rowWidth = [self f4c_effectiveRowWidthForParent:parent];
    CGFloat rowHeight = [self f4c_rowHeight];
    CGFloat buttonWidth = [self f4c_rowButtonWidth];
    CGFloat labelWidth = 50.0;
    CGFloat gap = 8.0;
    CGFloat controlH = [self f4c_rowControlHeight];
    CGFloat controlY = [self f4c_rowControlYForRowHeight:rowHeight];
    CGFloat inputWidth = rowWidth - labelWidth - buttonWidth - (gap * 2);
    if (inputWidth < 60) inputWidth = 60;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, rowWidth, rowHeight)];
    if (!self.sectionCardInner) {
        container.tag = self.currentCategoryCounter + 1000;
    }
    objc_setAssociatedObject(container, "f4cInputWithButton", @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0.0, controlY + 2.0, labelWidth, 18.0)];
    label.text = title;
    label.textColor = [self f4c_primaryTextColor];
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    [container addSubview:label];

    UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(labelWidth + gap, controlY, inputWidth, controlH)];
    field.backgroundColor = [self f4c_inputBackgroundColor];
    field.layer.cornerRadius = [self f4c_rowControlCornerRadius];
    field.layer.borderWidth = 1.0;
    field.layer.borderColor = [self f4c_cardBorderColor].CGColor;
    field.textColor = [self f4c_primaryTextColor];
    field.font = [UIFont systemFontOfSize:11];
    field.textAlignment = NSTextAlignmentCenter;
    if (placeholder.length > 0) {
        field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder attributes:@{NSForegroundColorAttributeName: [self f4c_secondaryTextColor]}];
    }
    field.delegate = self;
    field.returnKeyType = UIReturnKeyDone;
    [self f4c_attachDoneToolbarToTextField:field];

    UIView *paddingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, controlH)];
    field.leftView = paddingView;
    field.leftViewMode = UITextFieldViewModeAlways;
    [container addSubview:field];

    UIButton *confirm = [UIButton buttonWithType:UIButtonTypeCustom];
    confirm.frame = CGRectMake(labelWidth + gap + inputWidth + gap, controlY, buttonWidth, controlH);
    [confirm setTitle:buttonTitle forState:UIControlStateNormal];
    [confirm setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    confirm.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    confirm.layer.cornerRadius = [self f4c_rowControlCornerRadius];
    confirm.layer.masksToBounds = YES;
    [self f4c_applyPremiumButtonStyle:confirm];

    objc_setAssociatedObject(confirm, "f4cInputRef", field, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(confirm, "f4cInputHandler", handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [confirm addTarget:self action:@selector(f4c_inputWithButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    [container addSubview:confirm];
    [parent addSubview:container];
    [self f4c_relayoutRowContainer:container];
    [self updateLayout];
}

- (void)f4c_inputWithButtonTapped:(UIButton *)sender {
    [self endEditing:YES];
    UITextField *field = objc_getAssociatedObject(sender, "f4cInputRef");
    void (^handler)(NSString *) = objc_getAssociatedObject(sender, "f4cInputHandler");
    if (field) [field resignFirstResponder];
    if (handler && field) {
        handler(field.text);
    }
}

- (void)addComboWithInput:(NSString *)title

                  options:(NSArray<NSString *> *)options
            selectedIndex:(NSInteger)index
             defaultValue:(NSInteger)defaultValue
         selectionHandler:(void (^)(NSInteger selectedIndex))selectionHandler
             valueHandler:(void (^)(NSInteger value))valueHandler {
    if (options.count == 0) return;
    if (index < 0 || index >= (NSInteger)options.count) index = 0;

    UIView *parent = [self f4c_activeContentContainer];
    CGFloat rowWidth = [self f4c_effectiveRowWidthForParent:parent];
    CGFloat rowHeight = [self f4c_rowHeight];
    CGFloat labelWidth = 50.0;
    CGFloat gap = 8.0;
    CGFloat controlH = [self f4c_rowControlHeight];
    CGFloat controlY = (rowHeight - controlH) * 0.5;

    CGFloat startX = 0.0;
    CGFloat remWidth = rowWidth;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, rowWidth, rowHeight)];
    if (!self.sectionCardInner) {
        container.tag = self.currentCategoryCounter + 1000;
    }
    objc_setAssociatedObject(container, "f4cComboWithInput", @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (title.length > 0) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0.0, (rowHeight - 18.0) * 0.5, labelWidth, 18.0)];
        label.text = title;
        label.textColor = [self f4c_primaryTextColor];
        label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        [container addSubview:label];

        startX = labelWidth + gap;
        remWidth = rowWidth - startX;
    }

    CGFloat comboWidth = (remWidth - gap) * 0.55;
    CGFloat inputWidth = remWidth - comboWidth - gap;

    UIButton *combo = [UIButton buttonWithType:UIButtonTypeCustom];
    combo.frame = CGRectMake(startX, controlY, comboWidth, controlH);
    combo.backgroundColor = [self f4c_inputBackgroundColor];
    combo.layer.cornerRadius = [self f4c_rowControlCornerRadius];
    combo.layer.borderWidth = 1.0;
    combo.layer.borderColor = [self f4c_cardBorderColor].CGColor;
    [combo setTitle:options[index] forState:UIControlStateNormal];
    [combo setTitleColor:[self f4c_primaryTextColor] forState:UIControlStateNormal];
    combo.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    combo.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    F4CSetButtonTitleInsets(combo, UIEdgeInsetsMake(0, 4, 0, 16));

    UIButton *arrow = [UIButton buttonWithType:UIButtonTypeCustom];
    arrow.frame = CGRectMake(comboWidth - 22.0, 0, 20.0, controlH);
    arrow.tag = 8888;
    [arrow setTitle:@"▾" forState:UIControlStateNormal];
    [arrow setTitleColor:[self f4c_secondaryTextColor] forState:UIControlStateNormal];
    arrow.titleLabel.font = [UIFont systemFontOfSize:10];
    [arrow addTarget:self action:@selector(comboTapped:) forControlEvents:UIControlEventTouchUpInside];
    [combo addSubview:arrow];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = arrow.frame;
    close.tag = 8889;
    close.hidden = YES;
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:[self f4c_secondaryTextColor] forState:UIControlStateNormal];
    [close addTarget:self action:@selector(comboCloseTapped:) forControlEvents:UIControlEventTouchUpInside];
    [combo addSubview:close];

    objc_setAssociatedObject(combo, "comboOptions", options, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo, "comboHandler", selectionHandler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(combo, "comboSelectedIndex", @(index), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo, "comboArrow", arrow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo, "comboCloseBtn", close, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [combo addTarget:self action:@selector(comboTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:combo];

    UITextField *input = [[UITextField alloc] initWithFrame:CGRectMake(startX + comboWidth + gap, controlY, inputWidth, controlH)];
    input.backgroundColor = [self f4c_inputBackgroundColor];
    input.layer.cornerRadius = [self f4c_rowControlCornerRadius];
    input.layer.borderWidth = 1.0;
    input.layer.borderColor = [self f4c_cardBorderColor].CGColor;
    input.textColor = [self f4c_primaryTextColor];
    input.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    input.textAlignment = NSTextAlignmentCenter;
    input.keyboardType = UIKeyboardTypeNumberPad;
    input.text = [NSString stringWithFormat:@"%ld", (long)defaultValue];
    input.delegate = self;
    input.returnKeyType = UIReturnKeyDone;
    [self f4c_attachDoneToolbarToTextField:input];


    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, controlH)];
    input.leftView = pad;
    input.leftViewMode = UITextFieldViewModeAlways;

    objc_setAssociatedObject(input, "comboValueHandler", valueHandler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [input addTarget:self action:@selector(f4c_comboInputValueChanged:) forControlEvents:UIControlEventEditingChanged | UIControlEventEditingDidEnd];

    [container addSubview:input];
    [parent addSubview:container];
    [self f4c_relayoutRowContainer:container];
}





- (void)f4c_comboInputValueChanged:(UITextField *)textField {
    void (^valueHandler)(NSInteger) = objc_getAssociatedObject(textField, "comboValueHandler");
    if (valueHandler) {
        NSInteger val = [textField.text integerValue];
        valueHandler(val);
    }
}

- (void)addCheckboxCombo:(NSString *)title

                 options:(NSArray<NSString *> *)options
           selectedIndex:(NSInteger)index
                    isOn:(BOOL)isOn
       selectionHandler:(void (^)(NSInteger selectedIndex))selectionHandler
          toggleHandler:(void (^)(BOOL isOn))toggleHandler {
    if (options.count == 0) return;
    if (index < 0 || index >= (NSInteger)options.count) index = 0;

    UIView *parent = [self f4c_activeContentContainer];
    CGFloat rowWidth = [self f4c_effectiveRowWidthForParent:parent];
    CGFloat controlH = [self f4c_rowControlHeight];
    CGFloat comboW = [self f4c_rowStandardComboWidth];
    CGFloat rowHeight = [self f4c_rowHeight];
    CGFloat controlY = [self f4c_rowControlYForRowHeight:rowHeight];

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, rowWidth, rowHeight)];
    if (!self.sectionCardInner) {
        container.tag = self.currentCategoryCounter + 1000;
    }

    UIButton *box = [UIButton buttonWithType:UIButtonTypeCustom];
    box.frame = CGRectMake(0.0, (rowHeight - 22.0) * 0.5, 22.0, 22.0);
    box.layer.cornerRadius = 4.0;
    box.layer.borderWidth = 1.2;
    box.layer.borderColor = [self f4c_cardBorderColor].CGColor;
    box.backgroundColor = isOn ? self.accentColor : [UIColor whiteColor];
    box.selected = isOn;
    box.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [box setTitle:(isOn ? @"✓" : @"") forState:UIControlStateNormal];
    [box setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
    box.tag = 9191;
    objc_setAssociatedObject(box, "checkboxHandler", toggleHandler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [box addTarget:self action:@selector(f4c_checkboxTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:box];
    self.checkboxes[title] = box;

    UILabel *label =
        [[UILabel alloc] initWithFrame:CGRectMake(32.0,
                                                  (rowHeight - 22.0) * 0.5,
                                                  MAX(rowWidth - 32.0 - comboW - 16.0, 20.0),
                                                  22.0)];
    label.text = title;
    label.textColor = [self f4c_primaryTextColor];
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    label.numberOfLines = 2;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    [container addSubview:label];

    UIButton *combo = [UIButton buttonWithType:UIButtonTypeCustom];
    combo.frame = CGRectMake(rowWidth - comboW, controlY, comboW, controlH);
    combo.backgroundColor = [self f4c_inputBackgroundColor];
    combo.layer.cornerRadius = [self f4c_rowControlCornerRadius];
    combo.layer.borderWidth = 0.0;
    [combo setTitle:options[index] forState:UIControlStateNormal];
    [combo setTitleColor:[self f4c_primaryTextColor] forState:UIControlStateNormal];
    combo.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    combo.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    F4CSetButtonTitleInsets(combo, UIEdgeInsetsMake(0, 8, 0, 22));

    UIButton *arrow = [UIButton buttonWithType:UIButtonTypeCustom];
    arrow.frame = CGRectMake(comboW - 22.0, 0.0, 20.0, controlH);
    arrow.tag = 8888;
    [arrow setTitle:@"▾" forState:UIControlStateNormal];
    [arrow setTitleColor:[self f4c_secondaryTextColor] forState:UIControlStateNormal];
    arrow.titleLabel.font = [UIFont systemFontOfSize:10];
    [arrow addTarget:self action:@selector(comboTapped:) forControlEvents:UIControlEventTouchUpInside];
    [combo addSubview:arrow];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = arrow.frame;
    close.tag = 8889;
    close.hidden = YES;
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:[self f4c_secondaryTextColor] forState:UIControlStateNormal];
    [close addTarget:self action:@selector(comboCloseTapped:) forControlEvents:UIControlEventTouchUpInside];
    [combo addSubview:close];

    objc_setAssociatedObject(combo, "comboOptions", options, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo, "comboHandler", selectionHandler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(combo, "comboSelectedIndex", @(index), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo, "comboArrow", arrow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(combo, "comboCloseBtn", close, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    /* Whole combo body opens dropdown — not only the arrow */
    [combo addTarget:self action:@selector(comboTapped:) forControlEvents:UIControlEventTouchUpInside];

    [container addSubview:combo];
    [parent addSubview:container];
    [self f4c_relayoutRowContainer:container];
    [self updateLayout];
}


+ (instancetype)menuWithFrame:(CGRect)frame {
    MenuView *menu = [[MenuView alloc] initWithFrame:frame];
    [menu setup];
    return menu;
}

- (void)setup {
    self.accentColor = [UIColor colorWithRed:59.0/255.0 green:130.0/255.0 blue:246.0/255.0 alpha:1.0];
    self.layer.cornerRadius = 14.0;
    /* masksToBounds NO so outer glass shadow can show; content clips in shellClipView */
    self.layer.masksToBounds = NO;
    self.layer.borderWidth = 1.45;
    self.layer.borderColor = [self f4c_glassHighlightColor].CGColor;
    self.layer.shadowColor = [self f4c_glassShadowColor].CGColor;
    self.layer.shadowOpacity = 0.28;
    self.layer.shadowRadius = 24.0;
    self.layer.shadowOffset = CGSizeMake(0, 12);
    self.alpha = 1.0;
    self.currentCategoryCounter = 0;
    self.selectedTabIndex = 0;

    self.backgroundColor = [UIColor clearColor];

    /* Clip host: rounds blur + panels so corners are not square/milky */
    self.shellClipView = [[UIView alloc] initWithFrame:self.bounds];
    self.shellClipView.backgroundColor = [self f4c_glassTintColorWithAlpha:0.35];
    self.shellClipView.userInteractionEnabled = YES;
    self.shellClipView.clipsToBounds = YES;
    self.shellClipView.layer.masksToBounds = YES;
    [self addSubview:self.shellClipView];

    UIBlurEffect *blurEffect =
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    self.blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    self.blurEffectView.frame = self.shellClipView.bounds;
    self.blurEffectView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.blurEffectView.layer.cornerRadius = 14.0;
    self.blurEffectView.layer.masksToBounds = YES;
    self.blurEffectView.clipsToBounds = YES;
    self.blurEffectView.alpha = 1.0;
    [self.shellClipView addSubview:self.blurEffectView];
    [self f4c_syncShellCornerClip];

    CGFloat headerHeight = [self f4c_headerHeight];
    CGFloat bodyHeight = self.frame.size.height - headerHeight;
    (void)bodyHeight;

    self.headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.frame.size.width, headerHeight)];
    self.headerView.backgroundColor = [self f4c_headerBackgroundColor];
    self.headerView.clipsToBounds = NO;
    self.headerView.layer.masksToBounds = NO;
    [self.shellClipView addSubview:self.headerView];

    self.sidebarLogoBox = [[UIView alloc] initWithFrame:CGRectMake(14, 9, 34, 34)];
    [self.headerView addSubview:self.sidebarLogoBox];

    self.sidebarLogoChar = [[UILabel alloc] initWithFrame:self.sidebarLogoBox.bounds];
    self.sidebarLogoChar.text = @"F4";
    [self.sidebarLogoBox addSubview:self.sidebarLogoChar];
    [self f4c_styleMenuLogo];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(54, 11, self.frame.size.width - 150, 18)];
    self.titleLabel.text = @"Menu";
    self.titleLabel.textColor = [self f4c_primaryTextColor];
    self.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.minimumScaleFactor = 0.70;
    self.titleLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.headerView addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(54, 29, self.frame.size.width - 150, 14)];
    self.subtitleLabel.text = @"";
    self.subtitleLabel.textColor = [self f4c_secondaryTextColor];
    self.subtitleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.subtitleLabel.hidden = YES;
    [self.headerView addSubview:self.subtitleLabel];

    CGFloat chipSize = [self f4c_headerChipSize];
    CGFloat chipGap = [self f4c_headerChipGap];
    CGFloat chipInset = [self f4c_chromeHorizontalInset];
    CGFloat chipY = MAX((headerHeight - chipSize) * 0.5, 0.0);
    CGFloat closeX0 = self.frame.size.width - chipInset - chipSize;
    CGFloat telegramX0 = closeX0 - chipGap - chipSize;

    self.telegramButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.telegramButton.frame = CGRectMake(telegramX0, chipY, chipSize, chipSize);
    self.telegramButton.tag = 5001;
    SEL systemImageSelector = NSSelectorFromString(@"systemImageNamed:");
    if ([UIImage respondsToSelector:systemImageSelector]) {
        typedef UIImage *(*F4CSystemImageFunction)(id, SEL, NSString *);
        F4CSystemImageFunction systemImageFunction =
            (F4CSystemImageFunction)[UIImage methodForSelector:systemImageSelector];
        UIImage *telegramImage =
            systemImageFunction([UIImage class], systemImageSelector, @"paperplane.fill");
        if (telegramImage) {
            [self.telegramButton setImage:telegramImage forState:UIControlStateNormal];
        } else {
            [self.telegramButton setTitle:@"✈" forState:UIControlStateNormal];
        }
    } else {
        [self.telegramButton setTitle:@"✈" forState:UIControlStateNormal];
    }
    [self.telegramButton addTarget:self
                            action:@selector(socialTapped:)
                  forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.telegramButton];




    self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.closeButton.frame = CGRectMake(closeX0, chipY, chipSize, chipSize);
    [self.closeButton setTitle:@"✕" forState:UIControlStateNormal];
    [self.closeButton addTarget:self action:@selector(closeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.closeButton];

    /* Same chip chrome for both — size/corner/border/sheen matched */
    [self f4c_styleHeaderActionButtons];

    self.headerSeparator = [[UIView alloc] initWithFrame:CGRectMake(0, headerHeight - 1, self.frame.size.width, 1)];
    self.headerSeparator.backgroundColor = [self f4c_cardBorderColor];
    [self.shellClipView addSubview:self.headerSeparator];

    self.tabSidebar = [[UIView alloc] initWithFrame:CGRectZero];
    self.tabSidebar.backgroundColor = [self f4c_sidebarBackgroundColor];
    [self.shellClipView addSubview:self.tabSidebar];

    self.tabScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.tabScrollView.showsVerticalScrollIndicator = YES;
    self.tabScrollView.indicatorStyle = UIScrollViewIndicatorStyleDefault;
    self.tabScrollView.delegate = self;
    [self.tabSidebar addSubview:self.tabScrollView];

    self.tabContainerView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.tabScrollView addSubview:self.tabContainerView];

    /* Full-width bottom credit (spans whole menu, not only sidebar) */
    self.footerSeparator = [[UIView alloc] initWithFrame:CGRectZero];
    self.footerSeparator.backgroundColor = [self f4c_cardBorderColor];
    self.footerSeparator.hidden = YES;
    [self.shellClipView addSubview:self.footerSeparator];

    self.sidebarFooterLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.sidebarFooterLabel.text = @"";
    self.sidebarFooterLabel.textAlignment = NSTextAlignmentCenter;
    self.sidebarFooterLabel.textColor = [self f4c_secondaryTextColor];
    self.sidebarFooterLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    self.sidebarFooterLabel.hidden = YES;
    [self.shellClipView addSubview:self.sidebarFooterLabel];

    self.bodySeparator = [[UIView alloc] initWithFrame:CGRectZero];
    self.bodySeparator.backgroundColor = [self f4c_cardBorderColor];
    [self.shellClipView addSubview:self.bodySeparator];

    self.tabButtons = [NSMutableArray array];

    self.contentPanel = [[UIView alloc] initWithFrame:CGRectZero];
    self.contentPanel.backgroundColor = [self f4c_contentBackgroundColor];
    /* NO clip — section title badges may sit near edges / shadows */
    self.contentPanel.clipsToBounds = NO;
    [self.shellClipView addSubview:self.contentPanel];

    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.scrollView.showsVerticalScrollIndicator = YES;
    self.scrollView.indicatorStyle = UIScrollViewIndicatorStyleDefault;
    self.scrollView.backgroundColor = [UIColor clearColor];
    [self f4c_configureContentScrollView];
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.contentPanel addSubview:self.scrollView];

    [self f4c_applyScrollContentInsets];
    self.contentView =
        [[UIView alloc] initWithFrame:
            CGRectMake([self f4c_contentHorizontalInset],
                       0.0,
                       [self f4c_contentLayoutWidth],
                       0.0)];
    [self.scrollView addSubview:self.contentView];

    [self f4c_layoutChrome];
    [self f4c_applyAppearanceTheme];

    self.switches = [NSMutableDictionary dictionary];
    self.checkboxes = [NSMutableDictionary dictionary];
    self.sliders = [NSMutableDictionary dictionary];
    self.sliderLabels = [NSMutableDictionary dictionary];
    self.buttons = [NSMutableDictionary dictionary];
    self.textFields = [NSMutableDictionary dictionary];

    /*
     * Keyboard dismissal must not depend on the optional menu-drag recognizer.
     * This recognizer sees taps in all nested cards/scroll views, but does not
     * cancel the underlying button, combo, or scrolling interaction.
     */
    self.keyboardDismissTapGesture = [[UITapGestureRecognizer alloc]
        initWithTarget:self
                action:@selector(f4c_dismissKeyboardOnBackgroundTap:)];
    self.keyboardDismissTapGesture.delegate = self;
    self.keyboardDismissTapGesture.cancelsTouchesInView = NO;
    self.keyboardDismissTapGesture.delaysTouchesBegan = NO;
    self.keyboardDismissTapGesture.delaysTouchesEnded = NO;
    [self addGestureRecognizer:self.keyboardDismissTapGesture];

    self.canMove = NO;
}

- (void)socialTapped:(UIButton *)sender {
    NSString *urlStr = self.telegramURL;
    if (urlStr) {
        NSURL *url = [NSURL URLWithString:urlStr];
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }
}

- (void)addThemeSlider:(NSString *)title property:(NSString *)prop max:(CGFloat)max min:(CGFloat)min value:(CGFloat)value handler:(void (^)(CGFloat value))handler {
    [self addSlider:title max:max min:min value:value handler:handler];
    UISlider *sl = self.sliders[title];
    objc_setAssociatedObject(sl, "themeProp", prop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setMenuAccentColor:(UIColor *)color {
    if (!color) return;
    self.accentColor = color;
    /* Single path: updateTheme walks tree + tabs + controls */
    [self updateTheme];
}



- (void)setMenuGlassEffect:(BOOL)enabled {
    self.blurEffectView.hidden = !enabled;
}

- (void)setMenuCornerRadius:(CGFloat)radius {
    self.layer.cornerRadius = MAX(radius, 0.0);
    [self f4c_syncShellCornerClip];

    /* Header chips keep their own equal circular radius (not menu shell radius) */
    [self f4c_styleHeaderActionButtons];




    CGFloat buttonCornerRadius = MAX(radius * 0.35, 8.0);
    CGFloat barCornerRadius = MAX(radius * 0.5, 1.5);
    for (UIView *container in self.contentView.subviews) {
        if (container.tag >= 1000) {
            UIView *verticalBar = [container viewWithTag:9997];
            if (verticalBar) {
                verticalBar.layer.cornerRadius = barCornerRadius;
            }
        }
    }

    CGFloat tabButtonCornerRadius = radius * 0.3;
    for (UIButton *tabBtn in self.tabButtons) {
        tabBtn.layer.cornerRadius = tabButtonCornerRadius;
        UIView *indicator = [tabBtn viewWithTag:9999];
        if (indicator) {
            indicator.layer.cornerRadius = radius * 0.1;
        }
    }

    for (UIButton *btn in self.buttons.allValues) {
        btn.layer.cornerRadius = [self f4c_buttonCornerRadius];
        UILabel *badge = [btn viewWithTag:9090];
        if (badge) badge.layer.cornerRadius = 4.0;
    }

    for (UITextField *field in self.textFields.allValues) {
        field.layer.cornerRadius = buttonCornerRadius;
    }

    for (UIView *container in self.contentView.subviews) {
        if (container.tag >= 1000) {
            for (UIView *subview in container.subviews) {
                if ([subview isKindOfClass:[UIButton class]]) {
                    UIButton *comboBtn = (UIButton *)subview;
                    if ([comboBtn.subviews count] > 0) {
                        BOOL isCombo = NO;
                        for (UIView *sv in comboBtn.subviews) {
                            if ([sv isKindOfClass:[UILabel class]] && [((UILabel *)sv).text isEqualToString:@"▼"]) {
                                isCombo = YES;
                                break;
                            }
                        }
                        if (isCombo) {
                            comboBtn.layer.cornerRadius = buttonCornerRadius;
                        }
                    }
                } else if ([subview isKindOfClass:[UITextField class]]) {
                    subview.layer.cornerRadius = buttonCornerRadius;
                }
            }
        }
    }

    [self f4c_updateGradientBorder];
}

- (void)setMenuBorderWidth:(CGFloat)width {
    self.layer.borderWidth = MAX(width, 1.0);
    self.layer.borderColor = [UIColor clearColor].CGColor;
    [self f4c_updateGradientBorder];
}
























- (void)setMenuTitle:(NSString *)title {
    self.titleLabel.text = title ?: @"";
    self.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.minimumScaleFactor = 0.70;
    self.titleLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self f4c_layoutChrome];
}

- (void)setMenuSubtitle:(NSString *)subtitle {
    if (self.subtitleLabel) {
        if (subtitle.length > 0) {
            self.subtitleLabel.text = subtitle;
            self.subtitleLabel.hidden = NO;
        } else {
            self.subtitleLabel.text = @"";
            self.subtitleLabel.hidden = YES;
        }
    }
    [self f4c_layoutChrome];
}

- (void)f4c_applyAccentToViewTree:(UIView *)root {
    if (!root || !self.accentColor) return;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        for (UIView *ch in v.subviews) [stack addObject:ch];

        if ([v isKindOfClass:[UISwitch class]]) {
            ((UISwitch *)v).onTintColor = self.accentColor;
        } else if (v.tag == 9288) {
            [self f4c_styleGlassSwitch:v];
        } else if ([v isKindOfClass:[UISlider class]]) {
            ((UISlider *)v).minimumTrackTintColor = self.accentColor;
        } else if ([v isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)v;
            if (btn.tag == 9194 ||
                objc_getAssociatedObject(btn, "buttonHandler") ||
                objc_getAssociatedObject(btn, "f4cInputHandler")) {
                if (![btn.currentTitle isEqualToString:@"⤬"]) {
                    [self f4c_applyPremiumButtonStyle:btn];
                }
            }
            if (btn.tag == 9191) {
                btn.layer.borderColor = self.accentColor.CGColor;
                if (btn.selected) btn.backgroundColor = self.accentColor;
            }
            if (objc_getAssociatedObject(btn, "comboOptions")) {
                btn.layer.borderWidth = MAX(btn.layer.borderWidth, 1.0);
                btn.layer.borderColor =
                    [self.accentColor colorWithAlphaComponent:0.45].CGColor;
            }
        } else if ([v isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)v;
            if (lbl.tag == 9192) {
                lbl.backgroundColor =
                    [self.accentColor colorWithAlphaComponent:0.88];
            } else if (lbl.tag == 9998) {
                [self f4c_styleSectionTitleBadge:lbl];
            }
        } else if ([v isKindOfClass:[UITextField class]]) {
            UITextField *tf = (UITextField *)v;
            tf.layer.borderWidth = 1.0;
            tf.layer.borderColor =
                [self.accentColor colorWithAlphaComponent:0.45].CGColor;
            tf.tintColor = self.accentColor;
        } else if (v.tag == 9997) {

            v.backgroundColor = self.accentColor;
        } else if (v.tag == 9995) {
            /* unused divider — keep hidden, never draw a second top line */
            v.hidden = YES;
            v.backgroundColor = [UIColor clearColor];
        } else if (v.tag == 9996) {
            /* Dense frosted card; elevation shadow lives on wrapper */
            [self f4c_applyLiquidGlassToView:v
                               cornerRadius:[self f4c_glassCardCornerRadius]
                                  fillAlpha:0.78
                                  elevated:NO
                            sheenIntensity:0.45
                                  clipBody:YES];
            if (v.superview) {
                [self f4c_applyCardElevationShadow:v.superview body:v];
            }
        }
    }
}

- (void)updateTheme {
    if (!self.accentColor) return;

    for (id s in self.switches.allValues) {
        if ([s isKindOfClass:[UISwitch class]]) {
            ((UISwitch *)s).onTintColor = self.accentColor;
        } else if ([s isKindOfClass:[UIView class]] && ((UIView *)s).tag == 9288) {
            [self f4c_styleGlassSwitch:(UIView *)s];
        }
    }
    for (UISlider *sl in self.sliders.allValues) {
        sl.minimumTrackTintColor = self.accentColor;
    }
    for (UILabel *lbl in self.sliderLabels.allValues) {
        lbl.textColor = self.accentColor;
    }
    for (UIButton *btn in self.buttons.allValues) {
        if (![btn.currentTitle isEqualToString:@"⤬"]) {
            [self f4c_applyPremiumButtonStyle:btn];

            NSNumber *pinned = objc_getAssociatedObject(btn, "f4cBadgePinned");
            if (pinned.boolValue) {
                [self f4c_updateBadgeForButton:btn];
            }
        }
    }

    /* Walk full content tree (section cards nest rows) so accent always hits */
    if (self.contentView) {
        [self f4c_applyAccentToViewTree:self.contentView];
    }
    if (self.tabContainerView) {
        [self f4c_applyAccentToViewTree:self.tabContainerView];
    }

    for (NSInteger i = 0; i < (NSInteger)self.tabButtons.count; i++) {
        [self f4c_styleTabButton:self.tabButtons[i]
                        selected:(i == self.selectedTabIndex)];
    }

    [self f4c_updateGradientBorder];
    for (UIButton *box in self.checkboxes.allValues) {
        box.backgroundColor = box.selected ? self.accentColor : [UIColor whiteColor];
    }
}

- (void)f4c_styleTabButton:(UIButton *)tabBtn selected:(BOOL)selected {
    tabBtn.selected = selected;
    CGFloat r = [self f4c_glassControlCornerRadius];
    tabBtn.layer.cornerRadius = r;
    /* Centered label for both states */
    tabBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    tabBtn.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    F4CSetButtonTitleInsets(tabBtn, UIEdgeInsetsMake(0, 4, 0, 4));
    tabBtn.titleLabel.textAlignment = NSTextAlignmentCenter;

    if (selected) {
        /* Raised selected pill — bolder punchy presence */
        tabBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.96];
        tabBtn.layer.borderWidth = 1.5;
        UIColor *highlightColor = self.accentColor ? [self.accentColor colorWithAlphaComponent:0.65] : [self f4c_glassHighlightColor];
        tabBtn.layer.borderColor = highlightColor.CGColor;
        [tabBtn setTitleColor:(self.accentColor ?: [self f4c_primaryTextColor])
                     forState:UIControlStateNormal];
        tabBtn.titleLabel.font =
            [UIFont systemFontOfSize:12 weight:UIFontWeightHeavy];
        tabBtn.layer.masksToBounds = NO;
        tabBtn.clipsToBounds = NO;
        tabBtn.layer.shadowColor = (self.accentColor ?: [self f4c_glassShadowColor]).CGColor;
        tabBtn.layer.shadowOpacity = 0.42;
        tabBtn.layer.shadowRadius = 7.5;
        tabBtn.layer.shadowOffset = CGSizeMake(0, 3.0);
        if (tabBtn.bounds.size.width > 0.0 && tabBtn.bounds.size.height > 0.0) {
            tabBtn.layer.shadowPath =
                [UIBezierPath bezierPathWithRoundedRect:tabBtn.bounds
                                           cornerRadius:r].CGPath;
        }
        [self f4c_syncGlassSheenOnView:tabBtn cornerRadius:r intensity:0.55];
    } else {
        tabBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.30];
        tabBtn.layer.borderWidth = 1.0;
        tabBtn.layer.borderColor =
            [UIColor colorWithWhite:1.0 alpha:0.38].CGColor;
        [tabBtn setTitleColor:[self f4c_secondaryTextColor]
                     forState:UIControlStateNormal];
        tabBtn.titleLabel.font =
            [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        tabBtn.layer.masksToBounds = NO;
        tabBtn.clipsToBounds = NO;
        tabBtn.layer.shadowOpacity = 0.0;
        tabBtn.layer.shadowPath = nil;
        [self f4c_syncGlassSheenOnView:tabBtn cornerRadius:r intensity:0.18];
    }

    /* Remove legacy ▶ indicator if still attached from older builds */
    UIView *legacy = [tabBtn viewWithTag:9999];
    if (legacy) [legacy removeFromSuperview];
}

/*
 * Section header style #1 — CAPS + glass hairlines:
 *   ─── TÍNH NĂNG ───
 * Tags: container 8001–8999, title 8100, left line 8101, right line 8102
 */
- (UIFont *)f4c_tabSectionHeaderFont {
    /* Same visual size as before (not shrunk) — rail auto-sizes instead */
    return [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
}

- (UIColor *)f4c_tabSectionHairlineColor {
    return [UIColor colorWithWhite:1.0 alpha:0.42];
}

- (CGFloat)f4c_tabSectionHeaderHeight {
    return 20.0;
}

- (BOOL)f4c_isTabSectionHeaderView:(UIView *)view {
    if (!view) return NO;
    if (view.tag < 8001 || view.tag >= 9000) return NO;
    return [view viewWithTag:8100] != nil;
}

- (NSString *)f4c_tabSectionDisplayTitle:(NSString *)title {
    if (title.length == 0) return @"";
    return [title localizedUppercaseString] ?: [title uppercaseString];
}

- (void)f4c_styleTabSectionHeader:(UIView *)headerView {
    if (![self f4c_isTabSectionHeaderView:headerView]) {
        /* legacy plain UILabel */
        if ([headerView isKindOfClass:[UILabel class]]) {
            UILabel *header = (UILabel *)headerView;
            header.text = [self f4c_tabSectionDisplayTitle:header.text];
            header.font = [self f4c_tabSectionHeaderFont];
            header.textColor = [self f4c_secondaryTextColor];
            header.textAlignment = NSTextAlignmentCenter;
            header.adjustsFontSizeToFitWidth = YES;
            header.minimumScaleFactor = 0.75;
            header.lineBreakMode = NSLineBreakByTruncatingTail;
        }
        return;
    }

    UILabel *titleLabel = (UILabel *)[headerView viewWithTag:8100];
    UIView *leftLine = [headerView viewWithTag:8101];
    UIView *rightLine = [headerView viewWithTag:8102];
    if ([titleLabel isKindOfClass:[UILabel class]]) {
        titleLabel.font = [self f4c_tabSectionHeaderFont];
        titleLabel.textColor = [self f4c_secondaryTextColor];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        /* Prefer full size; only shrink if rail already hit max width */
        titleLabel.adjustsFontSizeToFitWidth = NO;
        titleLabel.minimumScaleFactor = 1.0;
        titleLabel.lineBreakMode = NSLineBreakByClipping;
        titleLabel.backgroundColor = [UIColor clearColor];
        if (titleLabel.text.length > 0) {
            titleLabel.text = [self f4c_tabSectionDisplayTitle:titleLabel.text];
        }
    }
    UIColor *lineColor = [self f4c_tabSectionHairlineColor];
    if (leftLine) leftLine.backgroundColor = lineColor;
    if (rightLine) rightLine.backgroundColor = lineColor;
}

- (void)f4c_layoutTabSectionHeaderView:(UIView *)headerView width:(CGFloat)width {
    if (!headerView || width <= 0.0) return;
    CGFloat height = [self f4c_tabSectionHeaderHeight];
    headerView.frame = CGRectMake(headerView.frame.origin.x,
                                  headerView.frame.origin.y,
                                  width,
                                  height);

    UILabel *titleLabel = (UILabel *)[headerView viewWithTag:8100];
    UIView *leftLine = [headerView viewWithTag:8101];
    UIView *rightLine = [headerView viewWithTag:8102];
    if (![titleLabel isKindOfClass:[UILabel class]]) return;

    [self f4c_styleTabSectionHeader:headerView];

    CGFloat gap = 6.0;
    CGFloat lineH = 1.0;
    CGFloat minLineW = 8.0;
    /* Full natural text width at original font size */
    CGSize fit =
        [titleLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, height)];
    CGFloat naturalW = MAX(ceil(fit.width), 20.0);
    /* Leave room for short hairlines on both sides when possible */
    CGFloat maxTitleW = MAX(width - (minLineW * 2.0) - (gap * 2.0), 20.0);
    BOOL hitCap = naturalW > maxTitleW + 0.5;
    CGFloat titleW = hitCap ? maxTitleW : naturalW;
    if (hitCap) {
        titleLabel.adjustsFontSizeToFitWidth = YES;
        titleLabel.minimumScaleFactor = 0.85;
        titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    CGFloat titleX = (width - titleW) * 0.5;
    titleLabel.frame = CGRectMake(titleX, 0.0, titleW, height);

    CGFloat lineY = (height - lineH) * 0.5;
    CGFloat leftW = MAX(titleX - gap, 0.0);
    CGFloat rightX = CGRectGetMaxX(titleLabel.frame) + gap;
    CGFloat rightW = MAX(width - rightX, 0.0);

    if (leftLine) {
        leftLine.frame = CGRectMake(0.0, lineY, leftW, lineH);
        leftLine.layer.cornerRadius = 0.5;
        leftLine.hidden = (leftW < 4.0);
    }
    if (rightLine) {
        rightLine.frame = CGRectMake(rightX, lineY, rightW, lineH);
        rightLine.layer.cornerRadius = 0.5;
        rightLine.hidden = (rightW < 4.0);
    }
}

- (UIView *)f4c_createTabSectionHeaderWithTitle:(NSString *)title
                                          width:(CGFloat)width
                                            tag:(NSInteger)tag {
    CGFloat height = [self f4c_tabSectionHeaderHeight];
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    wrap.tag = tag;
    wrap.backgroundColor = [UIColor clearColor];
    wrap.userInteractionEnabled = NO;

    UIView *leftLine = [[UIView alloc] initWithFrame:CGRectZero];
    leftLine.tag = 8101;
    [wrap addSubview:leftLine];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.tag = 8100;
    titleLabel.text = [self f4c_tabSectionDisplayTitle:title];
    [wrap addSubview:titleLabel];

    UIView *rightLine = [[UIView alloc] initWithFrame:CGRectZero];
    rightLine.tag = 8102;
    [wrap addSubview:rightLine];

    [self f4c_layoutTabSectionHeaderView:wrap width:width];
    return wrap;
}

- (void)tabButtonTapped:(UIButton *)sender {
    NSInteger oldIndex = self.selectedTabIndex;
    NSInteger newIndex = sender.tag;
    if (newIndex == oldIndex) return;

    [self closeAllComboDropdowns];
    [self f4c_finalizeSectionCard];

    if (oldIndex >= 0 && oldIndex < (NSInteger)self.tabButtons.count) {
        [self f4c_styleTabButton:self.tabButtons[oldIndex] selected:NO];
    }
    [self f4c_styleTabButton:sender selected:YES];

    self.selectedTabIndex = newIndex;
    [self endEditing:YES];
    [self updateLayout];
}

- (void)tabChanged:(UISegmentedControl *)sender {
    [self closeAllComboDropdowns];
    [self endEditing:YES];
    self.selectedTabIndex = sender.selectedSegmentIndex;
    [self updateLayout];
}

- (void)addSectionTitle:(NSString *)title {
    [self f4c_finalizeSectionCard];

    CGFloat contentWidth = [self f4c_contentLayoutWidth];
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, contentWidth, 52)];
    card.tag = self.currentCategoryCounter + 1000;
    card.backgroundColor = [UIColor clearColor];
    card.layer.cornerRadius = 0.0;
    card.layer.borderWidth = 0.0;

    UILabel *label =
        [[UILabel alloc] initWithFrame:CGRectMake(0, 0, contentWidth,
                                                  [self f4c_sectionDividerHeaderHeight])];
    label.text = title;
    label.textColor = [self f4c_secondaryTextColor];
    label.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightBold];
    label.textAlignment = NSTextAlignmentLeft;
    label.tag = 9998;
    [card addSubview:label];

    UIView *divider = [[UIView alloc] initWithFrame:CGRectZero];
    divider.tag = 9995;
    divider.backgroundColor = [self f4c_cardBorderColor];
    [card addSubview:divider];
    [self f4c_layoutSectionDividerHeader:card contentWidth:contentWidth];

    UIView *inner =
        [[UIView alloc] initWithFrame:CGRectMake(0, [self f4c_sectionDividerInnerTop],
                                                 contentWidth, 0)];
    inner.tag = 9996;
    [self f4c_applyLiquidGlassToView:inner
                        cornerRadius:[self f4c_glassCardCornerRadius]
                           fillAlpha:0.78
                           elevated:NO
                     sheenIntensity:0.45
                           clipBody:YES];
    [card addSubview:inner];
    [card bringSubviewToFront:label];
    card.clipsToBounds = NO;
    card.layer.masksToBounds = NO;

    self.currentSectionCard = card;
    self.sectionCardInner = inner;
    [self.contentView addSubview:card];
    [self updateLayout];
}

- (void)setTabIndex:(NSInteger)index {
    [self f4c_finalizeSectionCard];
    self.currentCategoryCounter = index;
}

- (UIButton *)f4c_resolveComboFromSender:(UIButton *)sender {
    if (!sender) return nil;

    if (objc_getAssociatedObject(sender, "comboOptions")) {
        return sender;
    }

    if ((sender.tag == 8888 || sender.tag == 8889) &&
        [sender.superview isKindOfClass:[UIButton class]]) {
        UIButton *parentCombo = (UIButton *)sender.superview;
        if (objc_getAssociatedObject(parentCombo, "comboOptions")) {
            return parentCombo;
        }
    }

    return nil;
}

- (NSArray<UIButton *> *)f4c_allComboButtonsInContentView {
    NSMutableArray<UIButton *> *combos = [NSMutableArray array];
    NSMutableArray<UIView *> *queue =
        [NSMutableArray arrayWithArray:self.contentView.subviews];

    while (queue.count > 0) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];

        if ([view isKindOfClass:[UIButton class]] &&
            objc_getAssociatedObject(view, "comboOptions")) {
            [combos addObject:(UIButton *)view];
        }

        for (UIView *child in view.subviews) {
            [queue addObject:child];
        }
    }

    return combos;
}

- (void)selectTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabButtons.count) return;
    [self tabButtonTapped:self.tabButtons[index]];
}

/*
 * Liquid-glass toggle (replaces stock UISwitch) — ported from 8.Tieu Cuong 3Q.
 * Track + thumb with sheen; spring slide on/off.
 * tag 9288 = root, 9289 = track, 9290 = thumb.
 * Geometry ALWAYS fixed (50×30 / 24×24) — never size from mid-animation bounds.
 */
- (UIView *)f4c_makeGlassSwitchWithHandler:(void (^)(BOOL isOn))handler {
    const CGFloat W = kF4CGlassSW;
    const CGFloat H = kF4CGlassSH;
    const CGFloat thumb = kF4CGlassThumb;
    const CGFloat pad = kF4CGlassPad;

    UIControl *root = [[UIControl alloc] initWithFrame:CGRectMake(0, 0, W, H)];
    root.tag = 9288;
    root.backgroundColor = [UIColor clearColor];
    root.clipsToBounds = NO;
    root.isAccessibilityElement = YES;
    root.accessibilityTraits = UIAccessibilityTraitButton;
    objc_setAssociatedObject(root, "f4cGlassOn", @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(root, "switchHandler", handler, OBJC_ASSOCIATION_COPY_NONATOMIC);

    UIView *track = [[UIView alloc] initWithFrame:root.bounds];
    track.tag = 9289;
    track.userInteractionEnabled = NO;
    track.clipsToBounds = YES;
    [self f4c_applyLiquidGlassToView:track
                        cornerRadius:H * 0.5
                           fillAlpha:0.42
                           elevated:NO
                     sheenIntensity:0.55
                           clipBody:YES];
    track.layer.cornerRadius = H * 0.5;
    track.layer.masksToBounds = YES;
    [root addSubview:track];

    UIView *thumbV = [[UIView alloc] initWithFrame:CGRectMake(pad, (H - thumb) * 0.5, thumb, thumb)];
    thumbV.tag = 9290;
    thumbV.userInteractionEnabled = NO;
    thumbV.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.94];
    thumbV.layer.cornerRadius = thumb * 0.5;
    thumbV.layer.masksToBounds = NO;
    thumbV.layer.borderWidth = 1.0;
    thumbV.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.85].CGColor;
    thumbV.layer.shadowColor = [self f4c_glassShadowColor].CGColor;
    thumbV.layer.shadowOpacity = 0.35;
    thumbV.layer.shadowRadius = 4.0;
    thumbV.layer.shadowOffset = CGSizeMake(0, 2.0);
    thumbV.layer.shadowPath =
        [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, thumb, thumb)].CGPath;
    [self f4c_syncGlassSheenOnView:thumbV cornerRadius:thumb * 0.5 intensity:0.65];
    [root addSubview:thumbV];

    [root addTarget:self
                  action:@selector(f4c_glassSwitchTouchDown:)
        forControlEvents:UIControlEventTouchDown];
    [root addTarget:self
                  action:@selector(f4c_glassSwitchTouchUp:)
        forControlEvents:UIControlEventTouchUpInside];
    [root addTarget:self action:@selector(f4c_glassSwitchTouchCancel:)
        forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    return root;
}

- (void)f4c_resetGlassSwitchGeometry:(UIView *)root {
    if (!root || root.tag != 9288) return;
    UIView *track = [root viewWithTag:9289];
    UIView *thumb = [root viewWithTag:9290];
    if (!track || !thumb) return;

    const CGFloat W = kF4CGlassSW;
    const CGFloat H = kF4CGlassSH;
    const CGFloat thumbS = kF4CGlassThumb;
    const CGFloat pad = kF4CGlassPad;

    [root.layer removeAllAnimations];
    [track.layer removeAllAnimations];
    [thumb.layer removeAllAnimations];
    track.transform = CGAffineTransformIdentity;
    thumb.transform = CGAffineTransformIdentity;
    track.alpha = 1.0;

    CGRect rf = root.frame;
    rf.size = CGSizeMake(W, H);
    root.frame = rf;
    root.bounds = CGRectMake(0, 0, W, H);

    track.transform = CGAffineTransformIdentity;
    track.frame = CGRectMake(0, 0, W, H);
    track.layer.cornerRadius = H * 0.5;
    track.layer.masksToBounds = YES;

    BOOL on = [objc_getAssociatedObject(root, "f4cGlassOn") boolValue];
    CGFloat xOff = on ? (W - thumbS - pad) : pad;
    CGFloat yOff = (H - thumbS) * 0.5;
    thumb.transform = CGAffineTransformIdentity;
    thumb.bounds = CGRectMake(0, 0, thumbS, thumbS);
    thumb.frame = CGRectMake(xOff, yOff, thumbS, thumbS);
    thumb.layer.cornerRadius = thumbS * 0.5;
    thumb.layer.shadowPath =
        [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, thumbS, thumbS)].CGPath;
}

- (void)f4c_setGlassSwitch:(UIView *)root on:(BOOL)on animated:(BOOL)animated {
    if (!root || root.tag != 9288) return;
    UIView *track = [root viewWithTag:9289];
    UIView *thumb = [root viewWithTag:9290];
    if (!track || !thumb) return;

    objc_setAssociatedObject(root, "f4cGlassOn", @(on), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    root.accessibilityValue = on ? @"1" : @"0";

    const CGFloat W = kF4CGlassSW;
    const CGFloat H = kF4CGlassSH;
    const CGFloat thumbS = kF4CGlassThumb;
    const CGFloat pad = kF4CGlassPad;

    [root.layer removeAllAnimations];
    [track.layer removeAllAnimations];
    [thumb.layer removeAllAnimations];
    track.transform = CGAffineTransformIdentity;
    thumb.transform = CGAffineTransformIdentity;
    track.alpha = 1.0;

    CGRect rf = root.frame;
    rf.size = CGSizeMake(W, H);
    root.frame = rf;
    track.frame = CGRectMake(0, 0, W, H);
    track.layer.cornerRadius = H * 0.5;

    CGFloat xOff = on ? (W - thumbS - pad) : pad;
    CGFloat yOff = (H - thumbS) * 0.5;
    CGRect thumbFrame = CGRectMake(xOff, yOff, thumbS, thumbS);

    UIColor *onFill = self.accentColor
        ? [self.accentColor colorWithAlphaComponent:0.82]
        : [UIColor colorWithRed:0.15 green:0.45 blue:0.95 alpha:0.82];
    UIColor *offFill = [self f4c_inputBackgroundColor];
    UIColor *onBorder = [UIColor colorWithWhite:1.0 alpha:0.75];
    UIColor *offBorder = self.accentColor
        ? [self.accentColor colorWithAlphaComponent:0.45]
        : [UIColor colorWithWhite:1.0 alpha:0.35];

    void (^applyVisual)(void) = ^{
        track.backgroundColor = on ? onFill : offFill;
        track.layer.borderColor = (on ? onBorder : offBorder).CGColor;
        track.layer.borderWidth = 1.0;
        thumb.layer.shadowOpacity = on ? 0.42 : 0.28;
        thumb.layer.cornerRadius = thumbS * 0.5;
        thumb.layer.shadowPath =
            [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, thumbS, thumbS)].CGPath;
    };


    if (!animated) {
        thumb.frame = thumbFrame;
        applyVisual();
        return;
    }

    applyVisual();
    [UIView animateWithDuration:0.30
                          delay:0
         usingSpringWithDamping:0.72
          initialSpringVelocity:0.70
                        options:UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        thumb.frame = thumbFrame;
        track.backgroundColor = on ? onFill : offFill;
        track.layer.borderColor = (on ? onBorder : offBorder).CGColor;
    } completion:^(BOOL finished) {
        (void)finished;
        thumb.transform = CGAffineTransformIdentity;
        track.transform = CGAffineTransformIdentity;
        thumb.bounds = CGRectMake(0, 0, thumbS, thumbS);
        thumb.frame = thumbFrame;
        thumb.layer.cornerRadius = thumbS * 0.5;
        thumb.layer.shadowPath =
            [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, thumbS, thumbS)].CGPath;
    }];
}

- (void)f4c_glassSwitchTouchDown:(UIControl *)sender {
    UIView *thumb = [sender viewWithTag:9290];
    if (!thumb) return;
    [UIView animateWithDuration:0.08
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut |
                                UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        thumb.transform = CGAffineTransformMakeScale(0.92, 0.92);
    } completion:nil];
}

- (void)f4c_glassSwitchTouchCancel:(UIControl *)sender {
    BOOL on = [objc_getAssociatedObject(sender, "f4cGlassOn") boolValue];
    [self f4c_setGlassSwitch:sender on:on animated:YES];
}

- (void)f4c_glassSwitchTouchUp:(UIControl *)sender {
    BOOL wasOn = [objc_getAssociatedObject(sender, "f4cGlassOn") boolValue];
    BOOL nowOn = !wasOn;
    [self f4c_setGlassSwitch:sender on:nowOn animated:YES];

    void (^handler)(BOOL) = objc_getAssociatedObject(sender, "switchHandler");
    if (handler) {
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(nowOn);
        });
    }
}

- (void)f4c_styleGlassSwitch:(UIView *)root {
    if (!root || root.tag != 9288) return;
    BOOL on = [objc_getAssociatedObject(root, "f4cGlassOn") boolValue];
    [self f4c_setGlassSwitch:root on:on animated:NO];
}

- (void)addFeatureSwitch:(NSString *)title handler:(void (^)(BOOL isOn))handler {
    UIView *parent = [self f4c_activeContentContainer];
    CGFloat contentWidth = [self f4c_effectiveRowWidthForParent:parent];
    const CGFloat containerHeight = 46.0;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, contentWidth, containerHeight)];
    if (!self.sectionCardInner) {
        container.tag = self.currentCategoryCounter + 1000;
    }
    objc_setAssociatedObject(container, "f4cHasDescription", @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 12.0, contentWidth - 60.0, 22.0)];
    label.text = title;
    label.textColor = [self f4c_primaryTextColor];
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    label.numberOfLines = 2;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    [container addSubview:label];

    UIView *toggle = [self f4c_makeGlassSwitchWithHandler:handler];
    toggle.frame = CGRectMake(contentWidth - kF4CGlassSW, (containerHeight - kF4CGlassSH) / 2.0,
                              kF4CGlassSW, kF4CGlassSH);
    [container addSubview:toggle];

    [parent addSubview:container];
    self.switches[title] = (UISwitch *)toggle; /* glass UIControl stored in switches map */
    [self f4c_relayoutRowContainer:container];
    [self updateLayout];
}

- (BOOL)switchOnForTitle:(NSString *)title {
    UIView *toggle = self.switches[title];
    if (!toggle) return NO;
    return [objc_getAssociatedObject(toggle, "f4cGlassOn") boolValue];
}

- (void)setSwitch:(BOOL)on forTitle:(NSString *)title animated:(BOOL)animated {
    UIView *toggle = self.switches[title];
    if (!toggle) return;
    [self f4c_setGlassSwitch:toggle on:on animated:animated];
}

- (BOOL)checkboxOnForTitle:(NSString *)title {
    UIButton *box = self.checkboxes[title];
    return box.selected;
}

- (void)setCheckbox:(BOOL)on forTitle:(NSString *)title animated:(BOOL)animated {
    UIButton *box = self.checkboxes[title];
    if (!box) return;
    box.selected = on;
    UIColor *targetBackground = on ? self.accentColor : [UIColor whiteColor];
    if (animated) {
        [UIView animateWithDuration:0.15 animations:^{
            box.backgroundColor = targetBackground;
        }];
    } else {
        box.backgroundColor = targetBackground;
    }
    [box setTitle:(on ? @"✓" : @"") forState:UIControlStateNormal];
    [box setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
    [box setTitleColor:[UIColor clearColor] forState:UIControlStateNormal];
}

- (void)addSlider:(NSString *)title max:(CGFloat)max min:(CGFloat)min value:(CGFloat)value handler:(void (^)(CGFloat value))handler {
    UIView *parent = [self f4c_activeContentContainer];
    CGFloat contentWidth = [self f4c_effectiveRowWidthForParent:parent];
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, contentWidth, [self f4c_rowHeight])];
    if (!self.sectionCardInner) {
        container.tag = self.currentCategoryCounter + 1000;
    }

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 11.0, 50.0, 18.0)];
    titleLabel.text = title;
    titleLabel.textColor = [self f4c_primaryTextColor];
    titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    [container addSubview:titleLabel];

    UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(contentWidth - 46.0, 11.0, 46.0, 18.0)];
    valueLabel.textColor = self.accentColor;
    valueLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    valueLabel.textAlignment = NSTextAlignmentRight;
    valueLabel.text = [NSString stringWithFormat:@"%.1f", value];
    [container addSubview:valueLabel];

    CGFloat sliderX = 58.0;
    CGFloat sliderW = MAX(contentWidth - sliderX - 46.0 - 8.0, 40.0);
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(sliderX, 8.0, sliderW, 24.0)];
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = value;
    slider.minimumTrackTintColor = self.accentColor;

    UIImage *thumbImage = [self createSliderThumbImage];
    [slider setThumbImage:thumbImage forState:UIControlStateNormal];
    [slider setThumbImage:thumbImage forState:UIControlStateHighlighted];

    [slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [slider addTarget:self action:@selector(f4c_sliderTrackingBegan:) forControlEvents:UIControlEventTouchDown];
    [slider addTarget:self action:@selector(f4c_sliderTrackingEnded:) forControlEvents:(UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel)];
    objc_setAssociatedObject(slider, "sliderHandler", handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(slider, "f4cSliderTitle", title ?: @"", OBJC_ASSOCIATION_COPY_NONATOMIC);
    [container addSubview:slider];

    [parent addSubview:container];
    self.sliders[title] = slider;
    self.sliderLabels[title] = valueLabel;
    [self f4c_relayoutRowContainer:container];
    [self updateLayout];
}

- (void)addSliderWithButton:(NSString *)title
                        max:(CGFloat)max
                        min:(CGFloat)min
                      value:(CGFloat)value
                buttonTitle:(NSString *)buttonTitle
              buttonHandler:(void (^)(void))buttonHandler
                    handler:(void (^)(CGFloat value))handler {
    [self addSliderWithButton:title
                          max:max
                          min:min
                        value:value
                 defaultValue:100.0
                  buttonTitle:buttonTitle
                buttonHandler:buttonHandler
                      handler:handler];
}

- (void)addSliderWithButton:(NSString *)title
                        max:(CGFloat)max
                        min:(CGFloat)min
                      value:(CGFloat)value
               defaultValue:(CGFloat)defaultValue
                buttonTitle:(NSString *)buttonTitle
              buttonHandler:(void (^)(void))buttonHandler
                    handler:(void (^)(CGFloat value))handler {
    UIView *parent = [self f4c_activeContentContainer];
    CGFloat contentWidth = [self f4c_effectiveRowWidthForParent:parent];
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, contentWidth, [self f4c_rowHeight])];
    if (!self.sectionCardInner) {
        container.tag = self.currentCategoryCounter + 1000;
    }

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 11.0, 60.0, 18.0)];
    titleLabel.text = title;
    titleLabel.textColor = [self f4c_primaryTextColor];
    titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.8;
    [container addSubview:titleLabel];

    UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 11.0, 28.0, 18.0)];
    valueLabel.textColor = self.accentColor;
    valueLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    valueLabel.textAlignment = NSTextAlignmentCenter;
    valueLabel.text = [NSString stringWithFormat:@"%.0f", value];
    [container addSubview:valueLabel];

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 8.0, 40.0, 24.0)];
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = value;
    slider.minimumTrackTintColor = self.accentColor;

    UIImage *thumbImage = [self createSliderThumbImage];
    [slider setThumbImage:thumbImage forState:UIControlStateNormal];
    [slider setThumbImage:thumbImage forState:UIControlStateHighlighted];

    [slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [slider addTarget:self action:@selector(f4c_sliderTrackingBegan:) forControlEvents:UIControlEventTouchDown];
    [slider addTarget:self action:@selector(f4c_sliderTrackingEnded:) forControlEvents:(UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel)];
    objc_setAssociatedObject(slider, "sliderHandler", handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(slider, "f4cSliderTitle", title ?: @"", OBJC_ASSOCIATION_COPY_NONATOMIC);
    [container addSubview:slider];

    UIButton *actionBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    actionBtn.frame = CGRectMake(0, 4.0, 66.0, [self f4c_rowControlHeight]);
    [actionBtn setTitle:(buttonTitle ?: @"Mặc Định") forState:UIControlStateNormal];
    [actionBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    actionBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [self f4c_applyPremiumButtonStyle:actionBtn];

    __weak UISlider *weakSlider = slider;
    __weak UILabel *weakValueLabel = valueLabel;
    void (^combinedBtnHandler)(void) = ^{
        UISlider *strongSlider = weakSlider;
        UILabel *strongValueLabel = weakValueLabel;
        if (strongSlider) {
            [strongSlider setValue:defaultValue animated:YES];
        }
        if (strongValueLabel) {
            strongValueLabel.text = [NSString stringWithFormat:@"%.0f", defaultValue];
        }
        if (handler) {
            handler(defaultValue);
        }
        if (buttonHandler) {
            buttonHandler();
        }
    };
    objc_setAssociatedObject(actionBtn, "buttonHandler", combinedBtnHandler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [actionBtn addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:actionBtn];

    [parent addSubview:container];
    self.sliders[title] = slider;
    self.sliderLabels[title] = valueLabel;
    [self f4c_relayoutRowContainer:container];
    [self updateLayout];
}


- (void)addComboSelector:(NSString *)title options:(NSArray *)options selectedIndex:(NSInteger)index handler:(void (^)(NSInteger selectedIndex))handler {
    UIView *parent = [self f4c_activeContentContainer];
    CGFloat contentWidth = [self f4c_effectiveRowWidthForParent:parent];
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, contentWidth, 64)];
    if (!self.sectionCardInner) {
        container.tag = self.currentCategoryCounter + 1000;
    }
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, container.frame.size.width, 16)];
    titleLabel.text = title;
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [container addSubview:titleLabel];
    
    UIButton *comboBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    comboBtn.frame = CGRectMake(0, 20, container.frame.size.width, 40);
    comboBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];
    comboBtn.layer.cornerRadius = self.layer.cornerRadius * 0.3;
    comboBtn.layer.borderWidth = 1.0;
    comboBtn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.1].CGColor;
    NSArray *safeOptions = options ?: @[];
    NSInteger safeIndex = index;
    if (safeOptions.count == 0) safeIndex = 0;
    else if (safeIndex < 0) safeIndex = 0;
    else if (safeIndex >= (NSInteger)safeOptions.count) safeIndex = (NSInteger)safeOptions.count - 1;
    NSString *initialTitle = safeOptions.count > 0 ? [NSString stringWithFormat:@"%@", safeOptions[safeIndex]] : @"Không có dữ liệu";
    [comboBtn setTitle:initialTitle forState:UIControlStateNormal];
    [comboBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    comboBtn.titleLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightRegular];
    comboBtn.titleLabel.numberOfLines = 2;
    comboBtn.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    comboBtn.titleLabel.adjustsFontSizeToFitWidth = YES;
    comboBtn.titleLabel.minimumScaleFactor = 0.72;
    comboBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    comboBtn.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    F4CSetButtonTitleInsets(comboBtn, UIEdgeInsetsMake(0, 12, 0, 24));
    
    // Arrow icon (mặc định quay ngang ▶)
    UIButton *arrowBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    arrowBtn.frame = CGRectMake(comboBtn.frame.size.width - 24, 0, 20, 40);
    [arrowBtn setTitle:@"▶" forState:UIControlStateNormal];
    [arrowBtn setTitleColor:[UIColor colorWithWhite:0.5 alpha:1.0] forState:UIControlStateNormal];
    arrowBtn.titleLabel.font = [UIFont systemFontOfSize:11];
    arrowBtn.tag = 8888; // Tag để tìm arrow
    [arrowBtn addTarget:self action:@selector(comboTapped:) forControlEvents:UIControlEventTouchUpInside];
    [comboBtn addSubview:arrowBtn];
    
    // Close button với dấu ⤬ màu đỏ (ẩn mặc định)
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(comboBtn.frame.size.width - 24, 0, 20, 40);
    [closeBtn setTitle:@"⤬" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:15];
    closeBtn.hidden = YES;
    closeBtn.tag = 8889; // Tag để tìm close button
    [closeBtn addTarget:self action:@selector(comboCloseTapped:) forControlEvents:UIControlEventTouchUpInside];
    [comboBtn addSubview:closeBtn];
    objc_setAssociatedObject(comboBtn, "comboTitle", title ?: @"", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(comboBtn, "comboOptions", safeOptions, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(comboBtn, "comboHandler", handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(comboBtn, "comboSelectedIndex", @(safeIndex), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(comboBtn, "comboArrow", arrowBtn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(comboBtn, "comboCloseBtn", closeBtn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    /* Whole combo body opens dropdown — not only the arrow */
    [comboBtn addTarget:self action:@selector(comboTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    [container addSubview:comboBtn];
    [parent addSubview:container];
    [self updateLayout];
}


- (void)updateComboSelector:(NSString *)title options:(NSArray *)options selectedIndex:(NSInteger)index {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateComboSelector:title options:options selectedIndex:index];
        });
        return;
    }
    if (title.length == 0) return;

    UIButton *target = nil;
    for (UIButton *combo in [self f4c_allComboButtonsInContentView]) {
        NSString *storedTitle = objc_getAssociatedObject(combo, "comboTitle");
        if ([storedTitle isEqualToString:title]) {
            target = combo;
            break;
        }
    }
    if (!target) return;

    [self closeComboDropdown:target];
    NSArray *safeOptions = options ?: @[];
    NSInteger safeIndex = index;
    if (safeOptions.count == 0) safeIndex = 0;
    else if (safeIndex < 0) safeIndex = 0;
    else if (safeIndex >= (NSInteger)safeOptions.count) safeIndex = (NSInteger)safeOptions.count - 1;

    objc_setAssociatedObject(target, "comboOptions", safeOptions, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(target, "comboSelectedIndex", @(safeIndex), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSString *selectedTitle = safeOptions.count > 0
        ? [NSString stringWithFormat:@"%@", safeOptions[safeIndex]]
        : @"Không có dữ liệu";
    [target setTitle:selectedTitle forState:UIControlStateNormal];
}

- (UILabel *)addStatusLabel:(NSString *)text {
    UIView *parent = [self f4c_activeContentContainer];
    CGFloat width = [self f4c_effectiveRowWidthForParent:parent];
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 76.0)];
    container.tag = 9399;
    if (!self.sectionCardInner) {
        container.tag = self.currentCategoryCounter + 1000;
    }

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10.0, 8.0, MAX(width - 20.0, 20.0), 60.0)];
    label.tag = 9398;
    label.text = text ?: @"";
    label.textColor = [self f4c_secondaryTextColor];
    label.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium];
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.textAlignment = NSTextAlignmentLeft;
    [container addSubview:label];
    [parent addSubview:container];
    [self updateLayout];
    return label;
}

- (BOOL)f4c_comboIsOpen:(UIButton *)comboBtn {
    if (!comboBtn) return NO;
    UIView *dropdown = objc_getAssociatedObject(comboBtn, "comboDropdown");
    return (dropdown && dropdown.superview && dropdown.tag == 7777);
}

- (void)comboTapped:(UIButton *)sender {
    UIButton *comboBtn = [self f4c_resolveComboFromSender:sender];
    if (!comboBtn) return;
    
    NSArray *options = objc_getAssociatedObject(comboBtn, "comboOptions");
    UIButton *arrow = objc_getAssociatedObject(comboBtn, "comboArrow");
    
    /* Tap 1 = open, tap 2 on same list = close (toggle) */
    if ([self f4c_comboIsOpen:comboBtn]) {
        [self closeComboDropdown:comboBtn];
        return;
    }
    
    // Đóng tất cả dropdown khác
    [self closeAllComboDropdowns];
    
    // Ẩn arrow và hiện close button (dấu ⤬ màu đỏ)
    UIButton *closeBtn = objc_getAssociatedObject(comboBtn, "comboCloseBtn");
    [UIView animateWithDuration:0.055 animations:^{
        arrow.alpha = 0;
        closeBtn.alpha = 0;
    } completion:^(BOOL finished) {
        arrow.hidden = YES;
        closeBtn.hidden = NO;
        closeBtn.alpha = 1.0;
    }];
    
    // Tạo dropdown menu (ưu tiên mở xuống, neo theo vùng hiển thị contentPanel)
    CGRect comboRect = [comboBtn convertRect:comboBtn.bounds toView:self.contentPanel];
    CGFloat dropdownWidth = comboRect.size.width;
    CGFloat itemHeight = 44;
    CGFloat maxHeight = 220; // Max 5 items visible with 2-line labels
    CGFloat dropdownHeight = MIN(options.count * itemHeight, maxHeight);

    CGFloat spaceBelow =
        CGRectGetMaxY(self.contentPanel.bounds) - CGRectGetMaxY(comboRect);
    CGFloat spaceAbove =
        CGRectGetMinY(comboRect) - CGRectGetMinY(self.contentPanel.bounds);
    CGFloat dropdownY =
        (spaceBelow >= dropdownHeight || spaceBelow >= spaceAbove)
            ? CGRectGetMaxY(comboRect)
            : (CGRectGetMinY(comboRect) - dropdownHeight);

    UIView *dropdown = [[UIView alloc] initWithFrame:
        CGRectMake(comboRect.origin.x, dropdownY, dropdownWidth, dropdownHeight)];
    dropdown.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.98];
    dropdown.layer.cornerRadius = 8.0;
    dropdown.layer.borderWidth = 1.0;
    dropdown.layer.borderColor = [self f4c_cardBorderColor].CGColor;
    dropdown.layer.shadowColor = [UIColor blackColor].CGColor;
    dropdown.layer.shadowOffset = CGSizeMake(0, 4);
    dropdown.layer.shadowOpacity = 0.3;
    dropdown.layer.shadowRadius = 8;
    dropdown.tag = 7777; // Tag để identify dropdown
    
    // Scroll view nếu có nhiều options
    UIScrollView *scrollView = nil;
    if (options.count > 5) {
        scrollView = [[UIScrollView alloc] initWithFrame:dropdown.bounds];
        scrollView.contentSize = CGSizeMake(dropdownWidth, options.count * itemHeight);
        scrollView.showsVerticalScrollIndicator = YES;
        scrollView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
        [dropdown addSubview:scrollView];
    }
    
    UIView *itemsContainer = scrollView ? scrollView : dropdown;
    CGFloat containerY = scrollView ? 0 : 0;
    
    for (NSInteger i = 0; i < options.count; i++) {
        UIButton *optionBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        optionBtn.frame = CGRectMake(0, containerY + (i * itemHeight), dropdownWidth, itemHeight - 1);
        [optionBtn setTitle:options[i] forState:UIControlStateNormal];
        [optionBtn setTitleColor:[self f4c_primaryTextColor] forState:UIControlStateNormal];
        optionBtn.titleLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightRegular];
        optionBtn.titleLabel.numberOfLines = 2;
        optionBtn.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        optionBtn.titleLabel.adjustsFontSizeToFitWidth = YES;
        optionBtn.titleLabel.minimumScaleFactor = 0.70;
        optionBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        optionBtn.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        F4CSetButtonTitleInsets(optionBtn, UIEdgeInsetsMake(0, 12, 0, 10));
        optionBtn.tag = i;
        
        // Highlight selected option
        NSNumber *selectedIndex = objc_getAssociatedObject(comboBtn, "comboSelectedIndex");
        if (selectedIndex && selectedIndex.integerValue == i) {
            optionBtn.backgroundColor = [self.accentColor colorWithAlphaComponent:0.2];
        } else {
            optionBtn.backgroundColor = [UIColor clearColor];
        }
        
        [optionBtn addTarget:self action:@selector(comboOptionSelected:) forControlEvents:UIControlEventTouchUpInside];
        [itemsContainer addSubview:optionBtn];
        
        // Separator line (trừ item cuối)
        if (i < options.count - 1) {
            UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(12, itemHeight - 1, dropdownWidth - 24, 1)];
            separator.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
            [optionBtn addSubview:separator];
        }
    }
    
    [self.contentPanel addSubview:dropdown];
    [self.contentPanel bringSubviewToFront:dropdown];
    objc_setAssociatedObject(comboBtn, "comboDropdown", dropdown, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(dropdown, "comboOwner", comboBtn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // Animation fade in
    dropdown.alpha = 0;
    dropdown.transform = CGAffineTransformMakeScale(0.95, 0.95);
    [UIView animateWithDuration:0.055 animations:^{
        dropdown.alpha = 1.0;
        dropdown.transform = CGAffineTransformIdentity;
    }];
    
    // Tap outside để đóng
    UITapGestureRecognizer *tapOutside = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeComboDropdownsOnTap:)];
    tapOutside.cancelsTouchesInView = NO;
    [self.scrollView addGestureRecognizer:tapOutside];
    objc_setAssociatedObject(dropdown, "tapOutsideGesture", tapOutside, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)comboOptionSelected:(UIButton *)optionBtn {
    // Tìm combo button cha
    UIView *dropdown = optionBtn.superview;
    while (dropdown && dropdown.tag != 7777) {
        dropdown = dropdown.superview;
    }
    if (!dropdown) return;
    
    UIButton *comboBtn = objc_getAssociatedObject(dropdown, "comboOwner");

    if (comboBtn) {
        NSArray *options = objc_getAssociatedObject(comboBtn, "comboOptions");
        void (^handler)(NSInteger) = objc_getAssociatedObject(comboBtn, "comboHandler");
        NSInteger selectedIndex = optionBtn.tag;
        if (selectedIndex < 0 || selectedIndex >= (NSInteger)options.count) {
            [self closeComboDropdown:comboBtn];
            return;
        }

        NSArray *originalIndices =
            objc_getAssociatedObject(comboBtn, "comboOriginalIndices");
        NSInteger callbackIndex = selectedIndex;
        if (originalIndices &&
            selectedIndex < (NSInteger)originalIndices.count) {
            callbackIndex = [originalIndices[selectedIndex] integerValue];
        }

        if (callbackIndex < 0) {
            [self closeComboDropdown:comboBtn];
            return;
        }

        // Update button title
        [comboBtn setTitle:options[selectedIndex] forState:UIControlStateNormal];
        objc_setAssociatedObject(comboBtn,
                                 "comboSelectedIndex",
                                 @(callbackIndex),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        // Call handler
        if (handler) handler(callbackIndex);
        
        // Đóng dropdown
        [self closeComboDropdown:comboBtn];
    }
}

- (void)closeComboDropdown:(UIButton *)comboBtn {
    UIView *dropdown = objc_getAssociatedObject(comboBtn, "comboDropdown");
    UILabel *arrow = objc_getAssociatedObject(comboBtn, "comboArrow");
    UIButton *closeBtn = objc_getAssociatedObject(comboBtn, "comboCloseBtn");
    
    if (dropdown) {
        // Remove tap gesture
        UITapGestureRecognizer *tapGesture = objc_getAssociatedObject(dropdown, "tapOutsideGesture");
        if (tapGesture) {
            [self.scrollView removeGestureRecognizer:tapGesture];
        }
        
        // Animation fade out
        [UIView animateWithDuration:0.055 animations:^{
            dropdown.alpha = 0;
            dropdown.transform = CGAffineTransformMakeScale(0.95, 0.95);
        } completion:^(BOOL finished) {
            [dropdown removeFromSuperview];
        }];
        
        objc_setAssociatedObject(comboBtn, "comboDropdown", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    // Ẩn close button (dấu ⤬) và hiện lại arrow (▶)
    [UIView animateWithDuration:0.055 animations:^{
        closeBtn.alpha = 0;
        arrow.alpha = 0;
    } completion:^(BOOL finished) {
        closeBtn.hidden = YES;
        arrow.hidden = NO;
        arrow.alpha = 1.0;
    }];
}

- (void)comboCloseTapped:(UIButton *)sender {
    UIButton *comboBtn = [self f4c_resolveComboFromSender:sender];
    if (comboBtn) {
        [self closeComboDropdown:comboBtn];
    }
}

- (void)closeAllComboDropdowns {
    for (UIButton *comboBtn in [self f4c_allComboButtonsInContentView]) {
        UIView *dropdown = objc_getAssociatedObject(comboBtn, "comboDropdown");
        if (dropdown && dropdown.superview) {
            [self closeComboDropdown:comboBtn];
        }
    }

    for (UIView *subview in [self.contentPanel.subviews copy]) {
        if (subview.tag != 7777) continue;

        UIButton *comboOwner = objc_getAssociatedObject(subview, "comboOwner");
        if (comboOwner) {
            [self closeComboDropdown:comboOwner];
            continue;
        }

        UITapGestureRecognizer *tapGesture =
            objc_getAssociatedObject(subview, "tapOutsideGesture");
        if (tapGesture) {
            [self.scrollView removeGestureRecognizer:tapGesture];
        }
        [subview removeFromSuperview];
    }
}

- (void)closeComboDropdownsOnTap:(UITapGestureRecognizer *)gesture {
    if (!self.contentPanel) {
        [self closeAllComboDropdowns];
        return;
    }

    CGPoint locationInPanel = [gesture locationInView:self.contentPanel];

    for (UIView *subview in self.contentPanel.subviews) {
        if (subview.tag != 7777) continue;

        /* Tap inside open dropdown list — keep open (option buttons handle select) */
        CGRect dropdownRect =
            [subview convertRect:subview.bounds toView:self.contentPanel];
        if (CGRectContainsPoint(dropdownRect, locationInPanel)) {
            return;
        }

        /*
         * Tap on the combo that owns this dropdown must NOT be handled here.
         * cancelsTouchesInView=NO would close via gesture then reopen via comboTapped.
         * Let comboTapped perform the toggle close instead.
         */
        UIButton *owner = objc_getAssociatedObject(subview, "comboOwner");
        if (owner) {
            CGRect comboRect =
                [owner convertRect:owner.bounds toView:self.contentPanel];
            /* Slightly inflate so edge taps still count as toggle */
            comboRect = CGRectInset(comboRect, -4.0, -4.0);
            if (CGRectContainsPoint(comboRect, locationInPanel)) {
                return;
            }
        }
    }

    [self closeAllComboDropdowns];
}

- (void)addTextField:(NSString *)title placeholder:(NSString *)placeholder handler:(void (^)(NSString *text))handler {
    UIView *parent = [self f4c_activeContentContainer];
    CGFloat contentWidth = [self f4c_effectiveRowWidthForParent:parent];
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, contentWidth, 64)];
    if (!self.sectionCardInner) {
        container.tag = self.currentCategoryCounter + 1000;
    }
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, container.frame.size.width, 16)];
    titleLabel.text = title;
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [container addSubview:titleLabel];
    
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(0, 20, container.frame.size.width, 32)];
    field.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];
    field.layer.cornerRadius = self.layer.cornerRadius * 0.3;
    field.layer.borderWidth = 1.0;
    field.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.1].CGColor;
    field.textColor = [UIColor whiteColor];
    field.font = [UIFont systemFontOfSize:10];
    field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.4]}];
    field.delegate = self;
    field.returnKeyType = UIReturnKeyDone;
    [field addTarget:self
              action:@selector(f4c_textFieldEditingDidEnd:)
    forControlEvents:UIControlEventEditingDidEnd];
    
    // Padding
    UIView *paddingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 32)];
    field.leftView = paddingView;
    field.leftViewMode = UITextFieldViewModeAlways;
    
    objc_setAssociatedObject(field, "fieldHandler", handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [container addSubview:field];
    [parent addSubview:container];
    [self updateLayout];
}

- (void)f4c_textFieldEditingDidEnd:(UITextField *)textField {
    void (^handler)(NSString *) = objc_getAssociatedObject(textField, "fieldHandler");
    if (handler) handler(textField.text);
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)addButton:(NSString *)title withHandler:(void (^)(void))handler {
    [self addButton:title
          badgeText:nil
      badgeDuration:0.0
         withHandler:handler];
}

- (void)addButton:(NSString *)title
        badgeText:(NSString *)badgeText
    badgeDuration:(NSTimeInterval)badgeDuration
       withHandler:(void (^)(void))handler {
    UIView *parent = [self f4c_activeContentContainer];
    CGFloat rowWidth = [self f4c_effectiveRowWidthForParent:parent];
    CGFloat rowHeight = 46.0;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, rowWidth, rowHeight)];
    if (!self.sectionCardInner) {
        container.tag = self.currentCategoryCounter + 1000;
    }

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = title;
    label.textColor = [self f4c_primaryTextColor];
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    label.numberOfLines = 2;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    [container addSubview:label];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = 9195;
    [button setTitle:@"Chạy" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    button.layer.cornerRadius = [self f4c_buttonCornerRadius];
    button.layer.masksToBounds = NO;

    UILabel *badge = [[UILabel alloc] initWithFrame:CGRectZero];
    badge.tag = 9090;
    badge.textAlignment = NSTextAlignmentCenter;
    badge.font = [UIFont systemFontOfSize:9 weight:UIFontWeightBlack];
    badge.textColor = [UIColor whiteColor];
    badge.layer.cornerRadius = 4.0;
    badge.layer.masksToBounds = YES;
    badge.userInteractionEnabled = NO;
    badge.alpha = 0.0;
    badge.hidden = YES;
    [button addSubview:badge];

    objc_setAssociatedObject(button, "buttonHandler", handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(button, "buttonRawTitle", title, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, "f4cBadgePinned", @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, "f4cBadgeGeneration", @(0), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (badgeText.length > 0) {
        objc_setAssociatedObject(button, "f4cCustomBadgeText", badgeText, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    if (badgeDuration > 0.0) {
        objc_setAssociatedObject(button, "f4cCustomBadgeDuration", @(badgeDuration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:button];
    [parent addSubview:container];
    self.buttons[title] = button;

    [self f4c_applyPremiumButtonStyle:button];
    [self f4c_relayoutRowContainer:container];
    [self updateLayout];
}


/* ─── Auto row alignment (section card) ─────────────────────────────
 * Normalizes simple rows (checkbox / switch / trailing button) so mixed
 * sections share one label column, one baseline row height and one
 * trailing control size. Complex rows (slider / combo / text input)
 * get the same metrics from f4c_relayoutRowContainer. */
- (void)f4c_autoAlignRow:(UIView *)row
                rowWidth:(CGFloat)rowWidth
            labelColumn:(CGFloat)labelColumn {
    if (!row || rowWidth <= 0.0) return;

    UIView *checkbox = [row viewWithTag:9191];
    UIView *toggle = [row viewWithTag:9288];
    UIButton *trailingButton = nil;
    for (UIView *sub in row.subviews) {
        if ([sub isKindOfClass:[UIButton class]] && sub.tag == 9195) {
            trailingButton = (UIButton *)sub;
            break;
        }
    }

    BOOL simpleRow = (checkbox || toggle || trailingButton);
    if (!simpleRow) return; /* slider / combo / input rows follow relayout metrics */

    UILabel *titleLabel = nil;
    for (UIView *sub in row.subviews) {
        if (![sub isKindOfClass:[UILabel class]]) continue;
        UILabel *lbl = (UILabel *)sub;
        BOOL rightAligned = (lbl.textAlignment == NSTextAlignmentRight ||
                              CGRectGetMinX(lbl.frame) > rowWidth * 0.5);
        if (rightAligned) continue; /* trailing value labels stay untouched */
        if (!titleLabel) titleLabel = lbl;
    }

    /* Unified baseline height for simple rows */
    const CGFloat kBaseRowHeight = [self f4c_rowHeight];
    CGRect rf = row.frame;
    rf.size.height = kBaseRowHeight;
    row.frame = rf;

    /* Canonical layout first so controls match the new height */
    [self f4c_relayoutRowContainer:row];
    CGFloat rowH = row.frame.size.height;

    /* Shared label column + vertical centering */
    if (titleLabel) {
        CGRect f = titleLabel.frame;
        f.origin.x = labelColumn;
        f.size.width = MAX(f.size.width - labelColumn, 20.0);
        f.origin.y = (rowH - f.size.height) * 0.5;
        titleLabel.frame = f;
    }

    /* Checkbox sits in the 0-20pt gutter, vertically centered */
    if (checkbox) {
        CGRect f = checkbox.frame;
        f.origin.x = 0.0;
        f.origin.y = (rowH - f.size.height) * 0.5;
        checkbox.frame = f;
    }
    /* Trailing button & glass switch are already re-centered by relayout */
}

- (void)f4c_layoutSectionCard:(UIView *)card atY:(CGFloat)y contentWidth:(CGFloat)contentWidth {
    UIView *inner = [card viewWithTag:9996];
    if (!inner) return;

    UILabel *titleLabel = [card viewWithTag:9998];

    CGFloat innerInset = [self f4c_sectionCardInnerInset];
    CGFloat rowSpacing = [self f4c_sectionCardRowSpacing];
    CGFloat innerY = [self f4c_sectionCardTopPadding];
    CGFloat rowWidth = MAX(contentWidth - (innerInset * 2.0), 40.0);
    CGRect innerFrame = inner.frame;
    innerFrame.origin.x = 0.0;
    innerFrame.origin.y = [self f4c_sectionDividerInnerTop];
    innerFrame.size.width = contentWidth;
    inner.frame = innerFrame;

    NSArray<UIView *> *rows = [inner.subviews copy];

    /* Auto-align: one shared label column per section card */
    BOOL sectionHasCheckbox = NO;
    for (UIView *row in rows) {
        if ([row viewWithTag:9191]) { sectionHasCheckbox = YES; break; }
    }
    const CGFloat kSectionLabelColumn = sectionHasCheckbox ? 28.0 : 0.0;

    for (NSUInteger i = 0; i < rows.count; i++) {
        UIView *row = rows[i];
        CGRect frame = row.frame;
        frame.origin.x = innerInset;
        frame.origin.y = innerY;
        frame.size.width = rowWidth;
        row.frame = frame;
        [self f4c_relayoutRowContainer:row];
        [self f4c_autoAlignRow:row rowWidth:rowWidth labelColumn:kSectionLabelColumn];
        innerY += row.frame.size.height;
        if (i + 1 < rows.count) {
            innerY += rowSpacing;
        }
    }

    /* empty card still needs a minimum body so title badge has glass under it */
    if (rows.count == 0) {
        innerY = MAX(innerY, [self f4c_sectionCardTopPadding] + 8.0);
    }

    innerFrame.size.height = innerY + [self f4c_sectionCardBottomPadding];
    inner.frame = innerFrame;
    CGFloat cardR = [self f4c_glassCardCornerRadius];
    [self f4c_applyLiquidGlassToView:inner
                       cornerRadius:cardR
                          fillAlpha:0.78
                          elevated:NO
                    sheenIntensity:0.45
                          clipBody:YES];

    /* Title after body size so z-order/frame win over glass card */
    [self f4c_layoutSectionDividerHeader:card contentWidth:contentWidth];
    [card sendSubviewToBack:inner];
    if (titleLabel) {
        [card bringSubviewToFront:titleLabel];
        titleLabel.layer.zPosition = 30.0;
    }
    inner.layer.zPosition = 0.0;

    CGRect cardFrame = card.frame;
    cardFrame.origin.x = 0.0;
    cardFrame.origin.y = y;
    cardFrame.size.width = contentWidth;
    /* Height covers glass body + title badge (no clipping) */
    CGFloat bodyBottom = CGRectGetMaxY(inner.frame);
    CGFloat titleBottom = titleLabel ? CGRectGetMaxY(titleLabel.frame) : 0.0;
    cardFrame.size.height = MAX(bodyBottom, titleBottom) + 2.0;
    card.frame = cardFrame;
    card.clipsToBounds = NO; /* never clip title badge or drop-shadow */
    [self f4c_applyCardElevationShadow:card body:inner];
}

- (void)updateLayout {
    [self f4c_applyScrollContentInsets];

    NSInteger selectedTab = self.selectedTabIndex;
    CGFloat contentWidth = [self f4c_contentLayoutWidth];
    CGFloat sectionSpacing = [self f4c_sectionCardSpacing];
    __block CGFloat yOffset = 5.0; /* first card raised 3 pt toward separator */

    [self.contentView.subviews enumerateObjectsUsingBlock:^(__kindof UIView *obj, NSUInteger idx, BOOL *stop) {
        if (obj.tag < 1000) return;

        if (obj.tag - 1000 == selectedTab) {
            obj.hidden = NO;

            if ([obj viewWithTag:9996]) {
                [self f4c_layoutSectionCard:obj atY:yOffset contentWidth:contentWidth];
                yOffset += obj.frame.size.height + sectionSpacing;
            } else {
                CGRect frame = obj.frame;
                frame.origin.x = 0.0;
                frame.origin.y = yOffset;
                frame.size.width = contentWidth;
                obj.frame = frame;

                if ([obj isKindOfClass:[UIButton class]]) {
                    UIButton *btn = (UIButton *)obj;
                    UILabel *badge = [btn viewWithTag:9090];
                    if (badge) {
                        badge.frame = CGRectMake(btn.frame.size.width - 70, 9, 58, 18);
                    }
                } else {
                    [self f4c_relayoutRowContainer:obj];
                }

                yOffset += frame.size.height + sectionSpacing;
            }
        } else {
            obj.hidden = YES;
        }
    }];

    /* Room under last card for drop-shadow so it isn’t clipped */
    yOffset += [self f4c_cardShadowExtraSpacing] + 4.0;

    CGFloat horizontalInset = [self f4c_contentHorizontalInset];
    self.contentView.frame = CGRectMake(horizontalInset, 0.0, contentWidth, yOffset);
    self.scrollView.contentSize =
        CGSizeMake([self f4c_contentPanelWidth], yOffset);
    self.contentView.clipsToBounds = NO;
    self.scrollView.clipsToBounds = YES;
    [self f4c_clampContentScrollOffset];
}

- (void)switchChanged:(UISwitch *)sender {
    /* Legacy UISwitch path (feature rows use glass switch tag 9288) */
    void (^handler)(BOOL) = objc_getAssociatedObject(sender, "switchHandler");
    if (!handler) return;
    BOOL on = sender.isOn;
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(on);
    });
}

/*
 * The Size slider resizes MenuView itself. In portrait mode the content panel
 * lives to the right of the sidebar, so every size change also moves/reflows
 * the slider under the finger. Freeze only this slider's window-space geometry
 * while it is tracking; the rest of the menu still resizes in real time.
 */
- (BOOL)f4c_isSizeSlider:(UISlider *)slider {
    NSString *title = objc_getAssociatedObject(slider, "f4cSliderTitle");
    if (![title isKindOfClass:[NSString class]]) return NO;

    NSString *folded = [[title stringByFoldingWithOptions:NSDiacriticInsensitiveSearch
                                                   locale:[NSLocale currentLocale]] lowercaseString];
    return [folded isEqualToString:@"kich thuoc"] ||
           [folded isEqualToString:@"size"] ||
           [folded containsString:@"kich thuoc"];
}

- (void)f4c_sliderTrackingBegan:(UISlider *)slider {
    if (![self f4c_isSizeSlider:slider]) return;

    /* Horizontal menu is already stable; apply the lock only to vertical UI. */
    if (self.bounds.size.width > self.bounds.size.height) return;
    if (!self.window || !slider.superview) return;

    CGRect frozenRect = [slider convertRect:slider.bounds toView:self.window];
    objc_setAssociatedObject(slider,
                             "f4cFrozenWindowRect",
                             [NSValue valueWithCGRect:frozenRect],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slider,
                             "f4cFreezeGeometry",
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self,
                             "f4cActiveSizeSlider",
                             slider,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)f4c_restoreActiveSizeSliderGeometry {
    UISlider *slider = objc_getAssociatedObject(self, "f4cActiveSizeSlider");
    if (!slider || !slider.superview || !self.window) return;

    NSNumber *freeze = objc_getAssociatedObject(slider, "f4cFreezeGeometry");
    NSValue *rectValue = objc_getAssociatedObject(slider, "f4cFrozenWindowRect");
    if (!freeze.boolValue || !rectValue) return;

    /* Keep the same on-screen rect even if sidebar/panel/content widths changed. */
    CGRect frozenWindowRect = rectValue.CGRectValue;
    CGRect localRect = [slider.superview convertRect:frozenWindowRect fromView:self.window];
    slider.frame = CGRectIntegral(localRect);
}

- (void)f4c_sliderTrackingEnded:(UISlider *)slider {
    if (![self f4c_isSizeSlider:slider]) return;

    objc_setAssociatedObject(slider,
                             "f4cFreezeGeometry",
                             @NO,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slider,
                             "f4cFrozenWindowRect",
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UISlider *active = objc_getAssociatedObject(self, "f4cActiveSizeSlider");
    if (active == slider) {
        objc_setAssociatedObject(self,
                                 "f4cActiveSizeSlider",
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    /* One clean final layout after the finger is released. Forced: the last
     * tracking value may already match the cached size, but the frozen slider
     * geometry still needs the restore pass. */
    objc_setAssociatedObject(self, "f4cForceLayoutPass", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)sliderValueChanged:(UISlider *)slider {
    for (NSString *key in self.sliders) {
        if (self.sliders[key] == slider) {
            UILabel *label = (UILabel *)self.sliderLabels[key];
            if (label) {
                if (slider.maximumValue <= 1.0) {
                    label.text = [NSString stringWithFormat:@"%.2f", slider.value];
                } else if (slider.maximumValue >= 50.0) {
                    label.text = [NSString stringWithFormat:@"%.0f", slider.value];
                } else {
                    label.text = [NSString stringWithFormat:@"%.1f", slider.value];
                }
            }
            
            void (^handler)(CGFloat) = objc_getAssociatedObject(slider, "sliderHandler");
            if (handler) handler(slider.value);

            NSString *prop = objc_getAssociatedObject(slider, "themeProp");
            if ([prop isEqualToString:@"opacity"]) self.alpha = slider.value;
            if ([prop isEqualToString:@"corner"]) [self setMenuCornerRadius:slider.value];
            if ([prop isEqualToString:@"border"]) [self setMenuBorderWidth:slider.value];
            break;
        }
    }
}

- (void)buttonTapped:(UIButton *)sender {
    void (^handler)(void) = objc_getAssociatedObject(sender, "buttonHandler");
    if (handler) {
        handler();
        [self f4c_showBadgeForButton:sender];
    }
}


- (void)close {
    CGFloat targetAlpha = self.alpha > 0.05 ? self.alpha : 1.0;
    [UIView animateWithDuration:0.055
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.alpha = 0.0;
        self.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0, 2.0),
                                                 CGAffineTransformMakeScale(0.98, 0.98));
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        self.alpha = targetAlpha;
        self.transform = CGAffineTransformIdentity;
    }];
}

- (void)makeDraggable {
    if (self.panGesture) {
        [self removeGestureRecognizer:self.panGesture];
    }
    if (self.canMove) {
        self.panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        self.panGesture.delegate = self;
        self.panGesture.cancelsTouchesInView = NO;
        [self addGestureRecognizer:self.panGesture];
    }
}

- (void)canMove:(BOOL)enabled {
    self.canMove = enabled;
    [self makeDraggable];
    
    // Nếu canMove = false, đặt menu ở giữa màn hình
    if (!enabled) {
        UIWindow *window = F4CActiveWindow();
        if (window) {
            UIEdgeInsets safeInsets = UIEdgeInsetsZero;
            if ([window respondsToSelector:@selector(safeAreaInsets)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
                safeInsets = window.safeAreaInsets;
#pragma clang diagnostic pop
            }
            CGRect safeRect = CGRectMake(safeInsets.left,
                                         safeInsets.top,
                                         window.bounds.size.width - safeInsets.left - safeInsets.right,
                                         window.bounds.size.height - safeInsets.top - safeInsets.bottom);
            CGRect menuFrame = self.frame;
            menuFrame.origin.x = safeRect.origin.x + (safeRect.size.width - menuFrame.size.width) * 0.5;
            menuFrame.origin.y = safeRect.origin.y + (safeRect.size.height - menuFrame.size.height) * 0.5;
            self.frame = menuFrame;
            [self setNeedsLayout];
        }
    }
}

- (BOOL)f4c_viewIsInsideSectionCard:(UIView *)start {
    /*
     * Section card = wrapper that owns inner tag 9996 (glass body + title badge).
     * Drag menu ONLY outside these cards (padding between cards / sidebar / empty).
     */
    for (UIView *v = start; v && v != self; v = v.superview) {
        if (v.tag == 9996) return YES; /* card body */
        if (v == self.contentView || v == self.scrollView ||
            v == self.contentPanel || v == self.shellClipView ||
            v == self.tabSidebar || v == self.tabScrollView ||
            v == self.tabContainerView || v == self.headerView) {
            break;
        }
        /* Card wrapper: direct child is glass inner (9996) */
        for (UIView *ch in v.subviews) {
            if (ch.tag == 9996) return YES;
        }
    }
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer == self.keyboardDismissTapGesture) {
        /* Tapping an input (including its private UIKit subviews) changes/focuses
         * input normally; every location outside input dismisses the keyboard. */
        for (UIView *view = touch.view; view && view != self; view = view.superview) {
            if ([view isKindOfClass:[UITextField class]] ||
                [view isKindOfClass:[UITextView class]]) {
                return NO;
            }
        }
        return YES;
    }
    if (gestureRecognizer != self.panGesture) return YES;


    /*
     * Drag OK: sidebar empty, content padding OUTSIDE section cards, scroll bg.
     * Drag blocked: inside section card (any control/label/title on the card),
     *               interactive controls, Telegram/Close.
     */
    if ([self f4c_viewIsInsideSectionCard:touch.view]) {
        return NO;
    }

    for (UIView *v = touch.view; v && v != self; v = v.superview) {
        if (v.tag == 9288) return NO; /* glass toggle */
        if (v == self.telegramButton || v == self.closeButton) {
            return NO;
        }
        if ([v isKindOfClass:[UISlider class]] ||
            [v isKindOfClass:[UISwitch class]] ||
            [v isKindOfClass:[UITextField class]] ||
            [v isKindOfClass:[UIButton class]]) {
            return NO;
        }
        if ([v isKindOfClass:[UIControl class]]) return NO;
    }
    return YES;
}

/* Prefer scrolling content when user is panning inside a UIScrollView. */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.keyboardDismissTapGesture ||
        otherGestureRecognizer == self.keyboardDismissTapGesture) {
        return YES;
    }
    if (gestureRecognizer != self.panGesture) return NO;
    if ([otherGestureRecognizer.view isKindOfClass:[UIScrollView class]]) {
        return NO;
    }
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    /* Menu drag waits if scroll view is actively scrolling vertically */
    if (gestureRecognizer == self.panGesture &&
        [otherGestureRecognizer.view isKindOfClass:[UIScrollView class]] &&
        [otherGestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        return NO; /* do not require scroll failure — empty content still drags */
    }
    return NO;
}

/* Keep menu fully on-screen (safe area + margin). */
- (void)f4c_clampFrameToSuperviewSafeArea {
    UIView *host = self.superview;
    if (!host) return;

    UIEdgeInsets safe = UIEdgeInsetsZero;
    if ([host respondsToSelector:@selector(safeAreaInsets)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
        safe = host.safeAreaInsets;
#pragma clang diagnostic pop
    }

    CGFloat margin = 0.0; /* sát cận màn hình (safe area) */
    CGRect f = self.frame;
    CGFloat minX = safe.left + margin;
    CGFloat minY = safe.top + margin;
    CGFloat maxX = host.bounds.size.width - safe.right - margin - f.size.width;
    CGFloat maxY = host.bounds.size.height - safe.bottom - margin - f.size.height;
    if (maxX < minX) maxX = minX;
    if (maxY < minY) maxY = minY;
    f.origin.x = MIN(MAX(f.origin.x, minX), maxX);
    f.origin.y = MIN(MAX(f.origin.y, minY), maxY);
    self.frame = f;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    if (!self.canMove || !self.superview) return;

    CGPoint translation = [gesture translationInView:self.superview];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.lastLocation = self.center;
    }
    self.center = CGPointMake(self.lastLocation.x + translation.x,
                              self.lastLocation.y + translation.y);
    [self f4c_clampFrameToSuperviewSafeArea];
}

- (void)closeButtonTapped:(UIButton *)sender { [self close]; }
- (void)addFeatureSwitch:(NSString *)title { [self addFeatureSwitch:title handler:nil]; }

- (NSInteger)f4c_tabSectionHeaderCount {
    NSInteger count = 0;
    for (UIView *subview in self.tabContainerView.subviews) {
        if ([self f4c_isTabSectionHeaderView:subview]) {
            count++;
            continue;
        }
        if ([subview isKindOfClass:[UILabel class]] &&
            subview.tag >= 8001 && subview.tag < 9000) {
            count++;
        }
    }
    return count;
}

- (CGFloat)f4c_tabButtonHeight {
    return 32.0;
}

- (CGFloat)f4c_tabButtonSpacing {
    return 2.0;
}

- (void)f4c_relayoutTabSidebarContent {
    if (!self.tabContainerView) return;

    CGFloat sidebarWidth = [self f4c_sidebarWidth];
    if (sidebarWidth <= 0.0) {
        self.tabContainerView.frame = CGRectZero;
        if (self.tabScrollView) self.tabScrollView.contentSize = CGSizeZero;
        return;
    }

    CGFloat tabButtonHeight = [self f4c_tabButtonHeight];
    CGFloat tabSpacing = [self f4c_tabButtonSpacing];
    CGFloat sideInset = [self f4c_tabSideInset];
    CGFloat btnWidth = MAX(sidebarWidth - (sideInset * 2.0), 40.0);
    CGFloat nextY = 4.0;
    BOOL hitMaxWidth = (sidebarWidth >= [self f4c_sidebarMaxWidth] - 0.5);

    /* Preserve visual order of headers + tab buttons as currently stacked */
    NSMutableArray<UIView *> *ordered = [NSMutableArray array];
    for (UIView *subview in self.tabContainerView.subviews) {
        if ([self f4c_isTabSectionHeaderView:subview] ||
            ([subview isKindOfClass:[UILabel class]] &&
             subview.tag >= 8001 && subview.tag < 9000)) {
            [ordered addObject:subview];
        } else if ([subview isKindOfClass:[UIButton class]]) {
            [ordered addObject:subview];
        }
    }

    /* Sort by current Y so sections stay grouped */
    [ordered sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ya = a.frame.origin.y;
        CGFloat yb = b.frame.origin.y;
        if (ya < yb) return NSOrderedAscending;
        if (ya > yb) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    for (UIView *view in ordered) {
        if ([self f4c_isTabSectionHeaderView:view] ||
            ([view isKindOfClass:[UILabel class]] &&
             view.tag >= 8001 && view.tag < 9000)) {
            CGFloat headerH = [self f4c_tabSectionHeaderHeight];
            CGFloat topPad = (nextY < 6.0) ? 2.0 : 8.0; /* extra air between sections */
            view.frame = CGRectMake(sideInset, nextY + topPad, btnWidth, headerH);
            if ([self f4c_isTabSectionHeaderView:view]) {
                [self f4c_layoutTabSectionHeaderView:view width:btnWidth];
            } else {
                [self f4c_styleTabSectionHeader:view];
            }
            nextY += topPad + headerH + 6.0;
            continue;
        }

        UIButton *tabBtn = (UIButton *)view;
        tabBtn.frame = CGRectMake(sideInset, nextY, btnWidth, tabButtonHeight);
        tabBtn.titleLabel.adjustsFontSizeToFitWidth = hitMaxWidth;
        tabBtn.titleLabel.minimumScaleFactor = hitMaxWidth ? 0.75 : 1.0;
        tabBtn.titleLabel.lineBreakMode = hitMaxWidth
            ? NSLineBreakByTruncatingTail
            : NSLineBreakByClipping;
        /* Center tab titles; re-apply selected/raised chrome after frame set */
        BOOL isSelected = (tabBtn.tag == self.selectedTabIndex);
        [self f4c_styleTabButton:tabBtn selected:isSelected];

        UIView *legacy = [tabBtn viewWithTag:9999];
        if (legacy) [legacy removeFromSuperview];
        nextY += tabButtonHeight + tabSpacing;
    }

    CGFloat totalHeight = nextY + 6.0;
    self.tabContainerView.frame = CGRectMake(0, 0, sidebarWidth, totalHeight);
    if (self.tabScrollView) {
        self.tabScrollView.contentSize = CGSizeMake(sidebarWidth, totalHeight);
    }
}

- (void)addTabSection:(NSString *)sectionTitle
                 tabs:(NSArray<NSString *> *)tabNames {
    if (!tabNames || tabNames.count == 0) return;

    CGFloat tabButtonHeight = [self f4c_tabButtonHeight];
    CGFloat tabSpacing = [self f4c_tabButtonSpacing];
    CGFloat sideInset = [self f4c_tabSideInset];

    CGFloat nextY = CGRectGetMaxY(self.tabContainerView.frame);
    if (nextY < 4.0) nextY = 4.0;

    /* Provisional width; final width is auto-measured after buttons exist */
    CGFloat provisionalW = MAX([self f4c_sidebarWidth], [self f4c_sidebarMinWidth]);
    if (provisionalW <= 0.0) provisionalW = 80.0;

    if (sectionTitle.length > 0) {
        CGFloat headerW = MAX(provisionalW - (sideInset * 2.0), 28.0);
        CGFloat topPad = (nextY < 6.0) ? 2.0 : 8.0;
        NSInteger headerTag = 8001 + [self f4c_tabSectionHeaderCount];
        UIView *header =
            [self f4c_createTabSectionHeaderWithTitle:sectionTitle
                                                width:headerW
                                                  tag:headerTag];
        CGRect hf = header.frame;
        hf.origin.x = sideInset;
        hf.origin.y = nextY + topPad;
        header.frame = hf;
        [self.tabContainerView addSubview:header];
        nextY += topPad + [self f4c_tabSectionHeaderHeight] + 6.0;
    }

    NSInteger startIndex = self.tabButtons.count;
    BOOL isFirstTabBatch = (startIndex == 0);

    for (NSInteger i = 0; i < (NSInteger)tabNames.count; i++) {
        NSString *tabName = tabNames[i];
        NSInteger tabIndex = startIndex + i;

        UIButton *tabBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        tabBtn.frame = CGRectMake(sideInset, nextY,
                                  MAX(provisionalW - (sideInset * 2.0), 40.0),
                                  tabButtonHeight);
        [tabBtn setTitle:tabName forState:UIControlStateNormal];
        tabBtn.tag = tabIndex;
        tabBtn.layer.cornerRadius = [self f4c_glassControlCornerRadius];
        tabBtn.backgroundColor = [UIColor clearColor];

        if (isFirstTabBatch && i == 0) {
            self.selectedTabIndex = 0;
            [self f4c_styleTabButton:tabBtn selected:YES];
        } else {
            [self f4c_styleTabButton:tabBtn selected:NO];
        }

        [tabBtn addTarget:self
                   action:@selector(tabButtonTapped:)
         forControlEvents:UIControlEventTouchUpInside];
        [self.tabContainerView addSubview:tabBtn];
        [self.tabButtons addObject:tabBtn];

        nextY += tabButtonHeight + tabSpacing;
    }

    /* Auto-size rail to widest tab text, then reflow chrome + content */
    [self f4c_layoutChrome];
    [self updateLayout];
}

- (void)addTab:(NSArray<NSString *> *)tabNames {
    NSString *sectionTitle = (self.tabButtons.count == 0) ? @"Tính Năng" : @"";
    [self addTabSection:sectionTitle tabs:tabNames];
}














- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.scrollView) {
        [self f4c_clampContentScrollOffset];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView
                  willDecelerate:(BOOL)decelerate {
    if (scrollView == self.scrollView && !decelerate) {
        [self f4c_clampContentScrollOffset];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == self.scrollView) {
        [self f4c_clampContentScrollOffset];
    }
}

- (UIImage *)createSliderThumbImage {
    // Tạo thumb image nhỏ hơn một chút (kích thước mặc định ~23x23, giờ ~14x14)
    CGFloat thumbSize = 14.0;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(thumbSize, thumbSize), NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Vẽ hình tròn màu trắng
    CGRect thumbRect = CGRectMake(0, 0, thumbSize, thumbSize);
    CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextFillEllipseInRect(context, thumbRect);
    
    // Thêm border nhẹ
    CGContextSetStrokeColorWithColor(context, [UIColor colorWithWhite:0.3 alpha:1.0].CGColor);
    CGContextSetLineWidth(context, 0.5);
    CGContextStrokeEllipseInRect(context, thumbRect);
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}



#pragma mark - Premium UI Effects


























- (void)f4c_updateGradientBorder {
    CAGradientLayer *gradient = objc_getAssociatedObject(self, "f4cGradientBorderLayer");
    if (gradient) {
        gradient.opacity = 0.0;
    }
    /* Static specular glass rim (reference liquid-glass look) */
    self.layer.borderWidth = 1.45;
    self.layer.borderColor = [self f4c_glassHighlightColor].CGColor;
    if (self.blurEffectView) {
        [self f4c_syncGlassSheenOnView:self.blurEffectView
                          cornerRadius:[self f4c_glassShellCornerRadius]
                             intensity:0.75];
    }
}




- (UIColor *)f4c_statusColor:(NSString *)status {
    return [UIColor colorWithRed:16.0/255.0 green:185.0/255.0 blue:129.0/255.0 alpha:1.0];
}

- (NSString *)f4c_statusForButtonTitle:(NSString *)title {
    /* No default "DONE" badge — only explicit custom badgeText shows */
    (void)title;
    return nil;
}

- (void)f4c_attachSpringButtonFeedback:(UIButton *)button {
    if (!button) return;
    [button addTarget:self action:@selector(f4c_buttonTouchDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(f4c_buttonTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
}

- (void)f4c_buttonTouchDown:(UIButton *)button {
    UIColor *accent = self.accentColor ?: [UIColor colorWithRed:59.0/255.0 green:130.0/255.0 blue:246.0/255.0 alpha:1.0];
    [UIView animateWithDuration:0.06
                          delay:0.0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        button.transform = CGAffineTransformMakeScale(0.92, 0.92);
        button.alpha = 0.82;
        button.layer.borderColor = [UIColor whiteColor].CGColor;
        button.layer.borderWidth = 1.8;
        button.layer.shadowColor = accent.CGColor;
        button.layer.shadowOpacity = 0.65;
        button.layer.shadowRadius = 12.0;
    } completion:nil];
}

- (void)f4c_buttonTouchUp:(UIButton *)button {
    UIColor *accent = self.accentColor ?: [UIColor colorWithRed:59.0/255.0 green:130.0/255.0 blue:246.0/255.0 alpha:1.0];
    [UIView animateWithDuration:0.24
                          delay:0.0
         usingSpringWithDamping:0.55
          initialSpringVelocity:0.80
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        button.transform = CGAffineTransformIdentity;
        button.alpha = 1.0;
        button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.75].CGColor;
        button.layer.borderWidth = 1.2;
        button.layer.shadowColor = accent.CGColor;
        button.layer.shadowOpacity = 0.30;
        button.layer.shadowRadius = 8.0;
    } completion:nil];
}


- (void)f4c_applyPremiumButtonStyle:(UIButton *)button {
    UIColor *accent = self.accentColor ?: [UIColor colorWithRed:59.0/255.0 green:130.0/255.0 blue:246.0/255.0 alpha:1.0];
    CGFloat r = [self f4c_glassControlCornerRadius];
    /* Solid-enough accent with soft lift shadow — bolder punch */
    button.backgroundColor = [accent colorWithAlphaComponent:0.88];
    button.layer.cornerRadius = r;
    button.layer.masksToBounds = NO;
    button.layer.borderWidth = 1.35;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.85].CGColor;
    button.layer.shadowColor = accent.CGColor;
    button.layer.shadowOffset = CGSizeMake(0, 3);
    button.layer.shadowOpacity = 0.38;
    button.layer.shadowRadius = 6.5;
    button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setTitleColor:[[UIColor whiteColor] colorWithAlphaComponent:0.75] forState:UIControlStateHighlighted];
    [self f4c_syncGlassSheenOnView:button cornerRadius:r intensity:0.45];
    [self f4c_attachSpringButtonFeedback:button];
}


- (void)f4c_updateBadgeForButton:(UIButton *)button {
    UILabel *badge = [button viewWithTag:9090];
    if (!badge) return;

    NSString *status =
        objc_getAssociatedObject(button, "f4cCustomBadgeText");
    if (!status || status.length == 0) {
        NSString *rawTitle =
            objc_getAssociatedObject(button, "buttonRawTitle");
        if (!rawTitle || rawTitle.length == 0) {
            rawTitle = button.currentTitle ?: @"";
        }
        status = [self f4c_statusForButtonTitle:rawTitle];
    }

    badge.text = status;
    badge.backgroundColor =
        [[self f4c_statusColor:status] colorWithAlphaComponent:0.88];
    badge.layer.borderWidth = 1.0;
    badge.layer.borderColor =
        [[UIColor whiteColor] colorWithAlphaComponent:0.18].CGColor;
    badge.textColor = [UIColor whiteColor];
}

- (void)f4c_showBadgeForButton:(UIButton *)button {
    UILabel *badge = [button viewWithTag:9090];
    if (!badge) return;

    NSString *customStatus =
        objc_getAssociatedObject(button, "f4cCustomBadgeText");
    NSNumber *customDuration =
        objc_getAssociatedObject(button, "f4cCustomBadgeDuration");

    NSString *rawTitle =
        objc_getAssociatedObject(button, "buttonRawTitle");
    if (!rawTitle || rawTitle.length == 0) {
        rawTitle = button.currentTitle ?: @"";
    }

    NSString *status =
        customStatus.length > 0
            ? customStatus
            : [self f4c_statusForButtonTitle:rawTitle];

    /* Skip empty / default — never show automatic "DONE" */
    if (status.length == 0) {
        badge.hidden = YES;
        badge.alpha = 0.0;
        return;
    }

    [self f4c_updateBadgeForButton:button];

    BOOL hasCustomDuration =
        customDuration != nil && customDuration.doubleValue > 0.0;
    BOOL shouldPin =
        !hasCustomDuration && [status isEqualToString:@"ACTIVE"];
    NSTimeInterval displayDuration =
        hasCustomDuration ? customDuration.doubleValue : 1.0;

    NSNumber *oldGeneration =
        objc_getAssociatedObject(button, "f4cBadgeGeneration");
    NSInteger generation = oldGeneration.integerValue + 1;
    objc_setAssociatedObject(
        button,
        "f4cBadgeGeneration",
        @(generation),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    objc_setAssociatedObject(
        button,
        "f4cBadgePinned",
        @(shouldPin),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    [badge.layer removeAllAnimations];
    badge.hidden = NO;
    badge.alpha = 0.0;
    badge.transform = CGAffineTransformMakeScale(0.82, 0.82);

    [UIView animateWithDuration:0.16
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut |
                                UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        badge.alpha = 1.0;
        badge.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        if (shouldPin) return;

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(displayDuration * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(),
            ^{
                NSNumber *currentGeneration =
                    objc_getAssociatedObject(
                        button,
                        "f4cBadgeGeneration"
                    );
                NSNumber *pinned =
                    objc_getAssociatedObject(
                        button,
                        "f4cBadgePinned"
                    );
                if (pinned.boolValue ||
                    currentGeneration.integerValue != generation) {
                    return;
                }

                [UIView animateWithDuration:0.18
                                      delay:0
                                    options:UIViewAnimationOptionCurveEaseIn |
                                            UIViewAnimationOptionAllowUserInteraction
                                 animations:^{
                    badge.alpha = 0.0;
                    badge.transform =
                        CGAffineTransformMakeScale(0.82, 0.82);
                } completion:^(BOOL finished) {
                    NSNumber *latestGeneration =
                        objc_getAssociatedObject(
                            button,
                            "f4cBadgeGeneration"
                        );
                    if (latestGeneration.integerValue != generation) {
                        return;
                    }
                    badge.hidden = YES;
                    badge.transform = CGAffineTransformIdentity;
                }];
            }
        );
    }];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    NSNumber *layoutPass = objc_getAssociatedObject(self, "f4cLayoutPass");
    if (layoutPass.boolValue) return;
    objc_setAssociatedObject(self, "f4cLayoutPass", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    /*
     * Drawer pan/open/close and canMove centering only move frame.origin at
     * 60 Hz. Chrome, content layout, and the gradient border all derive from
     * bounds.size alone, so origin-only passes skip the heavy relayout and
     * dragging stays smooth. Paths that need a pass without a size change
     * (size-slider release) set f4cForceLayoutPass first.
     */
    CGSize size = self.bounds.size;
    NSValue *lastSize = objc_getAssociatedObject(self, "f4cLastLayoutSize");
    BOOL force = [objc_getAssociatedObject(self, "f4cForceLayoutPass") boolValue];
    objc_setAssociatedObject(self, "f4cForceLayoutPass", @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL sizeChanged = (lastSize == nil) ||
                       !CGSizeEqualToSize(lastSize.CGSizeValue, size);
    if (!sizeChanged && !force) {
        objc_setAssociatedObject(self, "f4cLayoutPass", @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    objc_setAssociatedObject(self, "f4cLastLayoutSize",
                             [NSValue valueWithCGSize:size],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [self f4c_layoutChrome];
    [self updateLayout];
    [self f4c_restoreActiveSizeSliderGeometry];
    [self f4c_updateGradientBorder];

    objc_setAssociatedObject(self, "f4cLayoutPass", @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end


#pragma mark - UI Manager Component
// Source: UI/UIManager.h


@interface UIManager : NSObject <UIGestureRecognizerDelegate>

@property (nonatomic, strong) FloatingButton *floatingButton;
@property (nonatomic, strong) MenuView *menu;
@property (nonatomic, assign) CGFloat menuScale;

+ (instancetype)shared;
- (void)setupUI;
- (void)teardownUI;
- (void)toggleMenu;
- (void)setMenuScale:(CGFloat)scale;

@end

static UIEdgeInsets F4CSafeAreaInsetsForWindow(UIWindow *window) {
    UIEdgeInsets insets = UIEdgeInsetsZero;
    if (!window || ![window respondsToSelector:@selector(safeAreaInsets)]) {
        return insets;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
    insets = window.safeAreaInsets;
#pragma clang diagnostic pop

    return insets;
}

static CGFloat F4CClampUnit(CGFloat value) {
    return MIN(MAX(value, 0.0), 1.0);
}

typedef NS_ENUM(NSInteger, F4CGrabberPanAxis) {
    F4CGrabberPanAxisUndecided = 0,
    F4CGrabberPanAxisHorizontal,
    F4CGrabberPanAxisVertical
};

@implementation UIManager {
    UIView *_backdropView;
    UITapGestureRecognizer *_backdropTapGesture;
    BOOL _drawerAnimating;
    BOOL _drawerPanning;
    BOOL _drawerOpen;
    BOOL _drawerTargetOpenAtPanBegan;
    BOOL _orientationObserverRegistered;
    CGFloat _drawerProgress;
    CGFloat _grabberVerticalFraction;
    CGFloat _menuRestingAlpha;
    CGPoint _grabberPanLastTranslation;
    F4CGrabberPanAxis _grabberPanAxis;
    NSUInteger _drawerAnimationGeneration;
}

+ (instancetype)shared {
    static UIManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[UIManager alloc] init];
        double savedScale = [[NSUserDefaults standardUserDefaults] doubleForKey:@"F4C_MenuScale"];
        sharedInstance.menuScale = (savedScale >= 0.70 && savedScale <= 1.25) ? savedScale : 1.0;
    });
    return sharedInstance;
}

- (void)f4c_persistMenuScale {
    [[NSUserDefaults standardUserDefaults] setDouble:_menuScale forKey:@"F4C_MenuScale"];
}

- (void)setMenuScale:(CGFloat)scale {
    scale = MIN(MAX(scale, 0.70), 1.25);
    _menuScale = scale;
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(f4c_persistMenuScale)
                                               object:nil];
    [self performSelector:@selector(f4c_persistMenuScale)
               withObject:nil
               afterDelay:0.35];
    
    UIWindow *window = F4CActiveWindow();
    if (!window || !self.menu) return;
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGRect openFrame = [self f4c_openMenuFrameForWindow:window];
    self.menu.frame = openFrame;
    [self.menu updateLayout];
    [self f4c_applyDrawerProgress:(_drawerOpen ? 1.0 : 0.0) inWindow:window];
    [CATransaction commit];
}

- (CGRect)f4c_safeRectForWindow:(UIWindow *)window {
    UIEdgeInsets safe = F4CSafeAreaInsetsForWindow(window);
    return CGRectMake(safe.left,
                      safe.top,
                      MAX(window.bounds.size.width - safe.left - safe.right, 1.0),
                      MAX(window.bounds.size.height - safe.top - safe.bottom, 1.0));
}

/* Keep a visible frame fully inside the safe area. Closed drawer frames bypass it. */
- (CGRect)f4c_clampFrame:(CGRect)frame
                inWindow:(UIWindow *)window
                  margin:(CGFloat)margin {
    if (!window) return frame;
    UIEdgeInsets safe = F4CSafeAreaInsetsForWindow(window);
    CGFloat minX = safe.left + margin;
    CGFloat minY = safe.top + margin;
    CGFloat maxX = window.bounds.size.width - safe.right - margin - frame.size.width;
    CGFloat maxY = window.bounds.size.height - safe.bottom - margin - frame.size.height;
    if (maxX < minX) maxX = minX;
    if (maxY < minY) maxY = minY;
    frame.origin.x = MIN(MAX(frame.origin.x, minX), maxX);
    frame.origin.y = MIN(MAX(frame.origin.y, minY), maxY);
    return frame;
}

/*
 * Open drawer:
 * - Portrait: flush to screen left edge (x = 0), vertically centered.
 * - Landscape: flush to screen right edge (x = screen.width - menuWidth), vertically centered.
 */
- (CGRect)f4c_openMenuFrameForWindow:(UIWindow *)window {
    CGRect bounds = window ? window.bounds : [UIScreen mainScreen].bounds;
    BOOL isLandscape = bounds.size.width > bounds.size.height;
    CGFloat scale = (_menuScale >= 0.70 && _menuScale <= 1.25) ? _menuScale : 1.0;
    
    CGFloat preferredWidth = (isLandscape ? 580.0 : 368.0) * scale;
    CGFloat preferredHeight = (isLandscape ? 400.0 : 580.0) * scale;
    CGFloat availableWidth = isLandscape
        ? MAX(bounds.size.width - 50.0, 300.0)
        : MAX(bounds.size.width - 20.0, 300.0);
    CGFloat menuWidth = MIN(preferredWidth, availableWidth);
    CGFloat menuHeight = MIN(preferredHeight, bounds.size.height - 24.0);
    
    CGFloat x = isLandscape ? (bounds.size.width - menuWidth) : 0.0;
    CGFloat y = (bounds.size.height - menuHeight) * 0.5;
    return CGRectMake(x, y, menuWidth, menuHeight);
}

/* Closed drawer: completely outside the visible screen bounds. */
- (CGRect)f4c_closedMenuFrameForWindow:(UIWindow *)window {
    CGRect frame = [self f4c_openMenuFrameForWindow:window];
    CGRect bounds = window ? window.bounds : [UIScreen mainScreen].bounds;
    BOOL isLandscape = bounds.size.width > bounds.size.height;
    if (isLandscape) {
        /* Mirrored (Landscape): closed menu sits offscreen to the right */
        frame.origin.x = bounds.size.width;
    } else {
        /* Default (Portrait): closed menu sits offscreen to the left */
        frame.origin.x = -frame.size.width;
    }
    return frame;
}

/*
 * The grabber follows the drawer edge horizontally.
 * - Portrait: When progress = 0 (closed), x = 0 (left edge); when progress = 1, x = menu.right.
 * - Landscape (Mirrored): When progress = 0 (closed), x = screen.width - grabber.width (right edge);
 *                         when progress = 1, x = menu.left - grabber.width.
 */
- (CGRect)f4c_grabberFrameForProgress:(CGFloat)progress
                              inWindow:(UIWindow *)window {
    CGRect openFrame = [self f4c_openMenuFrameForWindow:window];
    CGRect bounds = window ? window.bounds : [UIScreen mainScreen].bounds;
    BOOL isLandscape = bounds.size.width > bounds.size.height;
    CGSize size = [FloatingButton preferredSize];

    CGFloat targetClosedX, targetOpenX;
    if (isLandscape) {
        targetClosedX = bounds.size.width - size.width;
        targetOpenX = openFrame.origin.x - size.width;
    } else {
        targetClosedX = 0.0;
        targetOpenX = CGRectGetMaxX(openFrame);
    }
    CGFloat x = targetClosedX + F4CClampUnit(progress) * (targetOpenX - targetClosedX);
    
    CGFloat minY = openFrame.origin.y;
    CGFloat maxY = MAX(CGRectGetMaxY(openFrame) - size.height, minY);
    CGFloat y = minY + F4CClampUnit(_grabberVerticalFraction) * (maxY - minY);
    return CGRectMake(x, y, size.width, size.height);
}

- (void)f4c_applyGrabberVerticalDelta:(CGFloat)deltaY
                              inWindow:(UIWindow *)window {
    if (!window || !self.floatingButton) return;
    CGRect openFrame = [self f4c_openMenuFrameForWindow:window];
    CGSize size = [FloatingButton preferredSize];
    CGFloat minY = openFrame.origin.y;
    CGFloat maxY = MAX(CGRectGetMaxY(openFrame) - size.height, minY);
    CGFloat y = MIN(MAX(self.floatingButton.frame.origin.y + deltaY, minY), maxY);
    CGFloat travel = maxY - minY;
    _grabberVerticalFraction = travel > 0.0 ? (y - minY) / travel : 0.5;
    [self f4c_applyDrawerProgress:_drawerProgress inWindow:window];
}

- (void)f4c_captureMenuRestingAlpha {
    if (self.menu && self.menu.alpha > 0.05 && !_drawerAnimating) {
        _menuRestingAlpha = self.menu.alpha;
    }
    if (_menuRestingAlpha <= 0.05) _menuRestingAlpha = 1.0;
}

- (void)f4c_prepareMenuForDrawer {
    if (!self.menu) return;

    /* A side drawer has one stable endpoint; disable the old free-2D menu pan. */
    if (self.menu.canMove || self.menu.panGesture) {
        self.menu.canMove = NO;
        [self.menu makeDraggable];
    }
    self.menu.transform = CGAffineTransformIdentity;
    self.menu.alpha = _menuRestingAlpha > 0.05 ? _menuRestingAlpha : 1.0;
}

- (void)f4c_setupBackdropInWindow:(UIWindow *)window {
    if (!window) return;
    if (!_backdropView) {
        _backdropView = [[UIView alloc] initWithFrame:window.bounds];
        _backdropView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.18];
        _backdropView.opaque = NO;
        _backdropView.hidden = YES;
        _backdropView.userInteractionEnabled = NO;
        _backdropView.layer.zPosition = 900.0;
        
        _backdropTapGesture = [[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(f4c_backdropTapped:)];
        _backdropTapGesture.delegate = self;
        _backdropTapGesture.cancelsTouchesInView = NO;
        [_backdropView addGestureRecognizer:_backdropTapGesture];
    }
    if (_backdropView.superview != window) {
        [window addSubview:_backdropView];
    }
    if (self.menu && self.menu.superview == window) {
        [window bringSubviewToFront:self.menu];
    }
    if (self.floatingButton && self.floatingButton.superview == window) {
        [window bringSubviewToFront:self.floatingButton];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer == _backdropTapGesture) {
        UIWindow *window = F4CActiveWindow();
        CGPoint location = [touch locationInView:window];
        
        /* Chạm BÊN TRONG Menu -> KHÔNG BAO GIỜ đóng menu */
        if (self.menu && !self.menu.hidden && CGRectContainsPoint(self.menu.frame, location)) {
            return NO;
        }
        /* Chạm vào Nút F4 Grabber -> KHÔNG đóng menu qua backdrop */
        if (self.floatingButton && !self.floatingButton.hidden && CGRectContainsPoint(self.floatingButton.frame, location)) {
            return NO;
        }
    }
    return YES;
}

- (void)f4c_backdropTapped:(UITapGestureRecognizer *)gesture {
    if (_drawerOpen && !_drawerPanning) {
        [self f4c_setDrawerOpen:NO animated:YES initialVelocity:0.0];
    }
}

- (void)f4c_bringGrabberAboveMenuInWindow:(UIWindow *)window {
    if (!window || !self.floatingButton) return;
    [self f4c_setupBackdropInWindow:window];
    if (_backdropView) _backdropView.layer.zPosition = 900.0;
    if (self.menu) {
        self.menu.layer.zPosition = 1000.0;
        if (self.menu.superview != window) [window addSubview:self.menu];
        [window bringSubviewToFront:self.menu];
    }
    self.floatingButton.layer.zPosition = 99999.0;
    if (self.floatingButton.superview != window) {
        [window addSubview:self.floatingButton];
    }
    [window bringSubviewToFront:self.floatingButton];
}

- (void)f4c_applyDrawerProgress:(CGFloat)progress inWindow:(UIWindow *)window {
    if (!window || !self.menu || !self.floatingButton) return;
    progress = F4CClampUnit(progress);

    [self f4c_setupBackdropInWindow:window];
    if (_backdropView) {
        _backdropView.frame = window.bounds;
        _backdropView.alpha = progress;
        _backdropView.hidden = (progress <= 0.001);
        _backdropView.userInteractionEnabled = (progress >= 0.05);
    }

    CGRect openFrame = [self f4c_openMenuFrameForWindow:window];
    CGRect closedFrame = [self f4c_closedMenuFrameForWindow:window];
    CGRect bounds = window ? window.bounds : [UIScreen mainScreen].bounds;
    BOOL isLandscape = bounds.size.width > bounds.size.height;
    self.floatingButton.rightAnchored = isLandscape;

    CGRect menuFrame = openFrame;
    menuFrame.origin.x = closedFrame.origin.x +
                         (openFrame.origin.x - closedFrame.origin.x) * progress;
    self.menu.frame = menuFrame;
    self.floatingButton.frame = [self f4c_grabberFrameForProgress:progress
                                                         inWindow:window];
    _drawerProgress = progress;
    [self f4c_bringGrabberAboveMenuInWindow:window];
}

/* Freeze the visual position before reversing an animation or starting a drag. */
- (void)f4c_commitPresentationFramesInWindow:(UIWindow *)window {
    if (!window || !self.menu || !self.floatingButton) return;

    CALayer *menuPresentation = (CALayer *)self.menu.layer.presentationLayer;
    CALayer *grabberPresentation =
        (CALayer *)self.floatingButton.layer.presentationLayer;
    if (_drawerAnimating && menuPresentation) {
        self.menu.frame = menuPresentation.frame;
    }
    if (_drawerAnimating && grabberPresentation) {
        self.floatingButton.frame = grabberPresentation.frame;
    }
    [self.menu.layer removeAllAnimations];
    [self.floatingButton.layer removeAllAnimations];

    CGRect openFrame = [self f4c_openMenuFrameForWindow:window];
    CGRect closedFrame = [self f4c_closedMenuFrameForWindow:window];
    CGFloat distance = openFrame.origin.x - closedFrame.origin.x;
    if (fabs(distance) > 0.001) {
        _drawerProgress = F4CClampUnit((self.menu.frame.origin.x -
                                       closedFrame.origin.x) / distance);
    }
    _drawerAnimating = NO;
    _drawerAnimationGeneration++;
}

- (void)f4c_setDrawerOpen:(BOOL)open
                  animated:(BOOL)animated
           initialVelocity:(CGFloat)velocityX {
    UIWindow *window = F4CActiveWindow();
    if (!window || !self.menu || !self.floatingButton) return;

    if (_drawerAnimating) {
        [self f4c_commitPresentationFramesInWindow:window];
    }
    [self f4c_captureMenuRestingAlpha];
    [self f4c_prepareMenuForDrawer];
    if (!open) [self.menu endEditing:YES];

    if (self.menu.superview != window) {
        [window addSubview:self.menu];
        [self f4c_bringGrabberAboveMenuInWindow:window];
    }

    _drawerOpen = open;
    [self.floatingButton setMenuPresented:open animated:animated];
    CGFloat target = open ? 1.0 : 0.0;
    NSUInteger generation = ++_drawerAnimationGeneration;

    if (!animated || fabs(_drawerProgress - target) < 0.001) {
        _drawerAnimating = NO;
        [self f4c_applyDrawerProgress:target inWindow:window];
        return;
    }

    CGRect openFrame = [self f4c_openMenuFrameForWindow:window];
    CGFloat remainingDistance = MAX(fabs(target - _drawerProgress) *
                                    openFrame.size.width, 1.0);
    CGFloat normalizedVelocity = MIN(fabs(velocityX) / remainingDistance, 3.0);
    _drawerAnimating = YES;

    [UIView animateWithDuration:0.28
                          delay:0.0
         usingSpringWithDamping:0.88
          initialSpringVelocity:normalizedVelocity
                        options:UIViewAnimationOptionCurveEaseOut |
                                UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        [self f4c_applyDrawerProgress:target inWindow:window];
    } completion:^(BOOL finished) {
        if (generation != self->_drawerAnimationGeneration) return;
        self->_drawerAnimating = NO;
        [self f4c_applyDrawerProgress:target inWindow:window];
    }];
}

- (void)f4c_handleGrabberPanBegan {
    UIWindow *window = F4CActiveWindow();
    if (!window || !self.menu || !self.floatingButton) return;

    [self f4c_commitPresentationFramesInWindow:window];
    [self f4c_captureMenuRestingAlpha];
    [self f4c_prepareMenuForDrawer];
    if (self.menu.superview != window) {
        [window addSubview:self.menu];
    }
    [self f4c_bringGrabberAboveMenuInWindow:window];
    [self.menu endEditing:YES];
    _drawerTargetOpenAtPanBegan = _drawerOpen;
    _grabberPanLastTranslation = CGPointZero;
    _grabberPanAxis = F4CGrabberPanAxisUndecided;
    _drawerPanning = YES;
}

- (void)f4c_handleGrabberPanChanged:(CGPoint)translation {
    UIWindow *window = F4CActiveWindow();
    if (!window || !_drawerPanning) return;

    if (_grabberPanAxis == F4CGrabberPanAxisUndecided) {
        CGFloat dx = fabs(translation.x);
        CGFloat dy = fabs(translation.y);
        if (dx < 6.0 && dy < 6.0) return;
        _grabberPanAxis = (dx >= dy) ? F4CGrabberPanAxisHorizontal
                                     : F4CGrabberPanAxisVertical;
    }

    CGPoint delta = CGPointMake(translation.x - _grabberPanLastTranslation.x,
                                translation.y - _grabberPanLastTranslation.y);
    _grabberPanLastTranslation = translation;

    if (_grabberPanAxis == F4CGrabberPanAxisVertical) {
        [self f4c_applyGrabberVerticalDelta:delta.y inWindow:window];
        return;
    }

    CGRect openFrame = [self f4c_openMenuFrameForWindow:window];
    CGRect closedFrame = [self f4c_closedMenuFrameForWindow:window];
    CGFloat distance = openFrame.origin.x - closedFrame.origin.x;
    if (fabs(distance) <= 0.001) return;
    CGFloat progress = _drawerProgress + delta.x / distance;
    [self f4c_applyDrawerProgress:progress inWindow:window];
}

- (void)f4c_handleGrabberPanEnded:(CGPoint)translation
                         velocity:(CGPoint)velocity
                        cancelled:(BOOL)cancelled {
    UIWindow *window = F4CActiveWindow();
    if (!window || !_drawerPanning) return;
    if (!cancelled) {
        [self f4c_handleGrabberPanChanged:translation];
    }
    _drawerPanning = NO;

    if (_grabberPanAxis == F4CGrabberPanAxisVertical ||
        _grabberPanAxis == F4CGrabberPanAxisUndecided) {
        _grabberPanAxis = F4CGrabberPanAxisUndecided;
        [self f4c_setDrawerOpen:_drawerTargetOpenAtPanBegan
                        animated:YES
                 initialVelocity:0.0];
        return;
    }

    BOOL shouldOpen = _drawerTargetOpenAtPanBegan;
    if (!cancelled) {
        CGRect openFrame = [self f4c_openMenuFrameForWindow:window];
        CGRect closedFrame = [self f4c_closedMenuFrameForWindow:window];
        BOOL isLandscape = window.bounds.size.width > window.bounds.size.height;
        CGFloat distance = openFrame.origin.x - closedFrame.origin.x;
        CGFloat projected = _drawerProgress;
        if (fabs(distance) > 0.001) {
            projected += (velocity.x / distance) * 0.16;
        }

        if (isLandscape) {
            /* Landscape (Mirrored Right): dragging LEFT (negative velocity) opens */
            if (velocity.x < -420.0) {
                shouldOpen = YES;
            } else if (velocity.x > 420.0) {
                shouldOpen = NO;
            } else {
                shouldOpen = projected >= 0.48;
            }
        } else {
            /* Portrait (Left): dragging RIGHT (positive velocity) opens */
            if (velocity.x > 420.0) {
                shouldOpen = YES;
            } else if (velocity.x < -420.0) {
                shouldOpen = NO;
            } else {
                shouldOpen = projected >= 0.48;
            }
        }
    }
    _grabberPanAxis = F4CGrabberPanAxisUndecided;
    [self f4c_setDrawerOpen:shouldOpen
                    animated:YES
             initialVelocity:velocity.x];
}

- (void)f4c_installCloseButtonRoute {
    UIButton *closeButton = self.menu.closeButton;
    if (!closeButton) return;

    [closeButton removeTarget:self.menu
                       action:NSSelectorFromString(@"closeButtonTapped:")
             forControlEvents:UIControlEventTouchUpInside];
    [closeButton removeTarget:self
                       action:@selector(f4c_closeButtonTapped:)
             forControlEvents:UIControlEventTouchUpInside];
    [closeButton addTarget:self
                    action:@selector(f4c_closeButtonTapped:)
          forControlEvents:UIControlEventTouchUpInside];
}

- (void)f4c_closeButtonTapped:(UIButton *)sender {
    (void)sender;
    [self f4c_setDrawerOpen:NO animated:YES initialVelocity:0.0];
}

- (void)teardownUI {
    NSAssert([NSThread isMainThread], @"UI teardown must run on main thread");
    ++_drawerAnimationGeneration;
    [self.menu endEditing:YES];
    [self.menu.layer removeAllAnimations];
    [self.floatingButton.layer removeAllAnimations];
    [_backdropView.layer removeAllAnimations];
    [self.menu removeFromSuperview];
    [self.floatingButton removeFromSuperview];
    [_backdropView removeFromSuperview];
    self.menu = nil;
    self.floatingButton = nil;
    _backdropView = nil;
    _backdropTapGesture = nil;
    _drawerAnimating = NO;
    _drawerPanning = NO;
    _drawerOpen = NO;
    _drawerProgress = 0.0;
    _grabberPanAxis = F4CGrabberPanAxisUndecided;
}

- (void)setupUI {
    UIWindow *window = F4CActiveWindow();
    if (!window) return;

    BOOL startingFreshSession = (self.menu == nil);
    if (startingFreshSession) {
        _drawerOpen = NO;
        _drawerTargetOpenAtPanBegan = NO;
        _drawerPanning = NO;
        _drawerAnimating = NO;
        _drawerProgress = 0.0;
        _grabberVerticalFraction = 0.5;
        _grabberPanLastTranslation = CGPointZero;
        _grabberPanAxis = F4CGrabberPanAxisUndecided;
        _menuRestingAlpha = 1.0;
        _drawerAnimationGeneration++;
    }

    CGRect openMenuFrame = [self f4c_openMenuFrameForWindow:window];
    if (!self.menu) {
        self.menu = [MenuView menuWithFrame:openMenuFrame];
    } else {
        self.menu.frame = openMenuFrame;
        [self.menu updateLayout];
    }
    [self f4c_installCloseButtonRoute];

    if (!self.floatingButton) {
        CGRect grabberFrame = [self f4c_grabberFrameForProgress:0.0
                                                       inWindow:window];
        self.floatingButton = [FloatingButton buttonWithFrame:grabberFrame];
        self.floatingButton.onTap = ^{
            [[UIManager shared] toggleMenu];
        };
        self.floatingButton.onPanBegan = ^{
            [[UIManager shared] f4c_handleGrabberPanBegan];
        };
        self.floatingButton.onPanChanged = ^(CGPoint translation) {
            [[UIManager shared] f4c_handleGrabberPanChanged:translation];
        };
        self.floatingButton.onPanEnded = ^(CGPoint translation,
                                            CGPoint velocity,
                                            BOOL cancelled) {
            [[UIManager shared] f4c_handleGrabberPanEnded:translation
                                                velocity:velocity
                                               cancelled:cancelled];
        };
    }

    if (self.menu.superview != window) [window addSubview:self.menu];
    if (self.floatingButton.superview != window) [window addSubview:self.floatingButton];

    [self f4c_captureMenuRestingAlpha];
    [self f4c_prepareMenuForDrawer];
    CGFloat settledProgress = _drawerOpen ? 1.0 : 0.0;
    [self f4c_applyDrawerProgress:settledProgress inWindow:window];
    [self.floatingButton setMenuPresented:_drawerOpen animated:NO];

    if (!_orientationObserverRegistered) {
        _orientationObserverRegistered = YES;
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(f4c_orientationDidChange:)
                   name:UIDeviceOrientationDidChangeNotification
                 object:[UIDevice currentDevice]];
    }
}

- (void)f4c_applyRotationRecoveryInWindow:(UIWindow *)window {
    if (!window || !self.menu || !self.floatingButton) return;
    [self f4c_commitPresentationFramesInWindow:window];
    _drawerPanning = NO;
    _grabberPanAxis = F4CGrabberPanAxisUndecided;
    _grabberPanLastTranslation = CGPointZero;
    [self.floatingButton cancelActivePan];
    CGRect openFrame = [self f4c_openMenuFrameForWindow:window];
    if (_backdropView) {
        _backdropView.frame = window.bounds;
    }
    self.menu.frame = openFrame;
    [self.menu updateLayout];
    [self f4c_applyDrawerProgress:(_drawerOpen ? 1.0 : 0.0)
                         inWindow:window];
    [self.floatingButton setMenuPresented:_drawerOpen animated:NO];
}

/*
 * Device-orientation notifications may fire before the scene window actually
 * resizes, so a single fixed delay can race with slow rotations. Poll until
 * window.bounds really change (or the bounded attempts run out — also covers
 * same-size orientation flips where bounds never change), then recover once.
 */
- (void)f4c_awaitRotationFromSize:(CGSize)preRotation attempt:(NSInteger)attempt {
    UIWindow *window = F4CActiveWindow();
    if (!window) {
        if (attempt >= 6) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(0.05 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self f4c_awaitRotationFromSize:preRotation attempt:attempt + 1];
        });
        return;
    }
    if (!CGSizeEqualToSize(window.bounds.size, preRotation) || attempt >= 12) {
        [self f4c_applyRotationRecoveryInWindow:window];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(0.05 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self f4c_awaitRotationFromSize:preRotation attempt:attempt + 1];
    });
}

- (void)f4c_orientationDidChange:(NSNotification *)notification {
    (void)notification;
    UIWindow *window = F4CActiveWindow();
    CGSize preRotation = window ? window.bounds.size : CGSizeZero;
    [self f4c_awaitRotationFromSize:preRotation attempt:0];
}

- (void)toggleMenu {
    if (!self.menu || !self.floatingButton) [self setupUI];
    [self f4c_setDrawerOpen:!_drawerOpen animated:YES initialVelocity:0.0];
}

@end


#pragma mark - Gameplay / AutoPerfect Implementation
// Source: Gameplay/AuditionAutoPerfect.mm



// Opaque IL2CPP runtime types. The module intentionally uses exported metadata/runtime
// APIs and managed invocation; it does not patch bytes or hook shared HotFix trampolines.
struct Il2CppDomain;
struct Il2CppAssembly;
struct Il2CppImage;
struct Il2CppClass;
struct Il2CppObject;
struct Il2CppString;
struct Il2CppType;
struct Il2CppThread;
struct MethodInfo;
struct FieldInfo;

namespace TNMDAP {

static NSString * const kBuildTag = @"V10.29-FINAL-CLEAN-UI-20260912";

using domain_get_t = Il2CppDomain *(*)();
using domain_get_assemblies_t = const Il2CppAssembly **(*)(const Il2CppDomain *, size_t *);
using assembly_get_image_t = const Il2CppImage *(*)(const Il2CppAssembly *);
using image_get_name_t = const char *(*)(const Il2CppImage *);
using class_from_name_t = Il2CppClass *(*)(const Il2CppImage *, const char *, const char *);
using class_get_method_from_name_t = const MethodInfo *(*)(Il2CppClass *, const char *, int);
using class_get_methods_t = const MethodInfo *(*)(Il2CppClass *, void **);
using class_get_parent_t = Il2CppClass *(*)(Il2CppClass *);
using method_get_name_t = const char *(*)(const MethodInfo *);
using method_get_param_count_t = uint32_t (*)(const MethodInfo *);
using method_get_param_t = const Il2CppType *(*)(const MethodInfo *, uint32_t);
using method_get_return_type_t = const Il2CppType *(*)(const MethodInfo *);
using method_get_flags_t = uint32_t (*)(const MethodInfo *, uint32_t *);
using type_get_name_t = char *(*)(const Il2CppType *);
using il2cpp_free_t = void (*)(void *);
using class_get_field_from_name_t = FieldInfo *(*)(Il2CppClass *, const char *);
using field_get_value_t = void (*)(Il2CppObject *, FieldInfo *, void *);
using field_set_value_t = void (*)(Il2CppObject *, FieldInfo *, void *);
using field_static_get_value_t = void (*)(FieldInfo *, void *);
using field_get_type_t = const Il2CppType *(*)(FieldInfo *);
using class_from_type_t = Il2CppClass *(*)(const Il2CppType *);
using object_new_t = Il2CppObject *(*)(Il2CppClass *);
using object_get_class_t = Il2CppClass *(*)(Il2CppObject *);
using runtime_invoke_t = Il2CppObject *(*)(const MethodInfo *, void *, void **, Il2CppObject **);
using object_unbox_t = void *(*)(Il2CppObject *);
using class_get_type_t = const Il2CppType *(*)(Il2CppClass *);
using type_get_object_t = Il2CppObject *(*)(const Il2CppType *);
using string_chars_t = const uint16_t *(*)(Il2CppString *);
using string_length_t = int32_t (*)(Il2CppString *);
using thread_attach_t = Il2CppThread *(*)(Il2CppDomain *);
using gchandle_new_t = uint32_t (*)(Il2CppObject *, bool);
using gchandle_get_target_t = Il2CppObject *(*)(uint32_t);
using gchandle_free_t = void (*)(uint32_t);

struct API {
    domain_get_t domain_get = nullptr;
    domain_get_assemblies_t domain_get_assemblies = nullptr;
    assembly_get_image_t assembly_get_image = nullptr;
    image_get_name_t image_get_name = nullptr;
    class_from_name_t class_from_name = nullptr;
    class_get_method_from_name_t class_get_method_from_name = nullptr;
    class_get_methods_t class_get_methods = nullptr;
    class_get_parent_t class_get_parent = nullptr;
    method_get_name_t method_get_name = nullptr;
    method_get_param_count_t method_get_param_count = nullptr;
    method_get_param_t method_get_param = nullptr;
    method_get_return_type_t method_get_return_type = nullptr;
    method_get_flags_t method_get_flags = nullptr;
    type_get_name_t type_get_name = nullptr;
    il2cpp_free_t il2cpp_free = nullptr;
    class_get_field_from_name_t class_get_field_from_name = nullptr;
    field_get_value_t field_get_value = nullptr;
    field_set_value_t field_set_value = nullptr;
    field_static_get_value_t field_static_get_value = nullptr;
    field_get_type_t field_get_type = nullptr;
    class_from_type_t class_from_type = nullptr;
    object_new_t object_new = nullptr;
    object_get_class_t object_get_class = nullptr;
    runtime_invoke_t runtime_invoke = nullptr;
    object_unbox_t object_unbox = nullptr;
    class_get_type_t class_get_type = nullptr;
    type_get_object_t type_get_object = nullptr;
    string_chars_t string_chars = nullptr;
    string_length_t string_length = nullptr;
    thread_attach_t thread_attach = nullptr;
    gchandle_new_t gchandle_new = nullptr;
    gchandle_get_target_t gchandle_get_target = nullptr;
    gchandle_free_t gchandle_free = nullptr;
};

struct Bindings {
    Il2CppClass *uiClass = nullptr;
    Il2CppClass *groupClass = nullptr;
    Il2CppClass *arrowClass = nullptr;
    Il2CppClass *rangeClass = nullptr;
    Il2CppClass *unityObjectClass = nullptr;
    Il2CppClass *uiManagerClass = nullptr;
    Il2CppClass *drumBeatClass = nullptr;

    const MethodInfo *findObjectOfType = nullptr;
    const MethodInfo *findFirstObjectByTypeInactive = nullptr;
    const MethodInfo *getUIWnd = nullptr;
    const MethodInfo *isUIShowing = nullptr;
    const MethodInfo *isUICaching = nullptr;
    const MethodInfo *objectImplicit = nullptr;
    const MethodInfo *onDrumDown = nullptr;
    const MethodInfo *isAllHit = nullptr;
    const MethodInfo *rangeIsInRange = nullptr;
    const MethodInfo *drumBeatOnPress = nullptr;

    FieldInfo *uiCurGroup = nullptr;
    FieldInfo *uiAudioTime = nullptr;
    FieldInfo *uiCenterAudioTime = nullptr;
    FieldInfo *uiOpenClickBeatTime = nullptr;
    FieldInfo *uiMoveRate = nullptr;
    FieldInfo *uiDrumBeatArray = nullptr;

    FieldInfo *groupArrowsList = nullptr;
    FieldInfo *groupCurArrowIndex = nullptr;
    FieldInfo *groupGroupIndex = nullptr;
    FieldInfo *groupIsShow = nullptr;
    FieldInfo *groupIsHitBeat = nullptr;
    FieldInfo *groupRangeList = nullptr;
    FieldInfo *groupJudgeLevel = nullptr;

    FieldInfo *arrowDirection = nullptr;
    FieldInfo *drumBeatBeatType = nullptr;

    FieldInfo *rangeStartTime = nullptr;
    FieldInfo *rangeEndTime = nullptr;
    FieldInfo *rangeRank = nullptr;
};

// V10.18 local-only cosmetic skin changer. This path only asks the existing
// NewPlayer.Player costume loader to render config-backed assets on the local
// client. It does not mutate bag/inventory ownership or send equip messages.
struct SkinBindings {
    Il2CppClass *appInterfaceClass = nullptr;
    Il2CppClass *roomModuleClass = nullptr;
    Il2CppClass *roomBaseClass = nullptr;
    Il2CppClass *roomPlayerClass = nullptr;
    Il2CppClass *baseDanceClass = nullptr;
    Il2CppClass *dancerControllerClass = nullptr;
    Il2CppClass *guiModuleClass = nullptr;
    Il2CppClass *uiPlayerManagerClass = nullptr;
    Il2CppClass *uiPlayerClass = nullptr;
    Il2CppClass *playerClass = nullptr;
    Il2CppClass *configItemClass = nullptr;
    Il2CppClass *itemClass = nullptr;
    Il2CppClass *equipClass = nullptr;

    FieldInfo *appRoomModule = nullptr;
    FieldInfo *appGUIModule = nullptr;
    FieldInfo *roomPlayerPlayer = nullptr;
    FieldInfo *dancerControllerPlayer = nullptr;
    FieldInfo *uiPlayerManagerPlayersList = nullptr;
    FieldInfo *uiPlayerModel = nullptr;
    FieldInfo *playerGameObject = nullptr;
    FieldInfo *playerNeedPutOnItems = nullptr;
    FieldInfo *configItemArray = nullptr;
    FieldInfo *itemID = nullptr;
    FieldInfo *itemType1 = nullptr;
    FieldInfo *itemType2 = nullptr;
    FieldInfo *itemSexNeed = nullptr;
    FieldInfo *equipItemID = nullptr;

    const MethodInfo *roomGetRoomPlayer = nullptr;
    const MethodInfo *roomGetRoom = nullptr;
    const MethodInfo *roomBaseGetLocalPlayer = nullptr;
    const MethodInfo *baseDanceGetPlayer = nullptr;
    const MethodInfo *guiGetPlayerManager = nullptr;
    const MethodInfo *playerGetSex = nullptr;
    const MethodInfo *playerGetRoleId = nullptr;
    const MethodInfo *playerGetLoadComplete = nullptr;
    const MethodInfo *playerIsPuton = nullptr;
    const MethodInfo *unityObjectImplicit = nullptr;
    const MethodInfo *playerLoadAndPutOn = nullptr;
    const MethodInfo *playerChangeAll = nullptr;
    const MethodInfo *playerGetOriginEquip = nullptr;
    const MethodInfo *configGetSingleton = nullptr;
    const MethodInfo *configGetItem = nullptr;
    const MethodInfo *itemGetName = nullptr;
};

static SkinBindings gSkinB;
static BOOL gSkinBindingsReady = NO;
static NSMutableArray<NSDictionary *> *gSkinCatalog = nil;
static NSMutableDictionary<NSNumber *, NSNumber *> *gSkinPinnedByType = nil;
static NSString *gSkinStatus = @"IDLE • LOCAL_ONLY";
static Il2CppObject *gSkinLastPlayer = nullptr;
static uint32_t gSkinLastPlayerHandle = 0;
static uint32_t gSkinLastRoleId = 0;
static int32_t gSkinLastGUIListCount = -1;
static int32_t gSkinLastGUINonNullModels = 0;
static int32_t gSkinLastGUILoadedModels = 0;
static NSString *gSkinLastGUIListPath = @"none";
static NSString *gSkinLastGUIStage = @"none";
static BOOL gSkinPendingApply = NO;
static NSString *gSkinLastTargetSource = @"none";
static dispatch_source_t gSkinTimer = nullptr;
// V10.21: pin verification catches same-object costume refreshes. V10.18 only
// re-applied when the Player pointer changed, so an AllBody set could be
// overwritten by the game's normal costume refresh while the object stayed alive.
static CFTimeInterval gSkinLastPinnedApplyAt = 0.0;
static CFTimeInterval gSkinLastPinLostLogAt = 0.0;

// V10.20 local-only VIP visual overlay. This deliberately targets UI components
// (UI_VIPIcon / self CharacterTop) and never mutates ClientVIP, RoleInfoData,
// recharge, reward, inventory, or entitlement/server state.
struct VIPVisualBindings {
    Il2CppClass *unityObjectClass = nullptr;
    Il2CppClass *vipIconClass = nullptr;
    Il2CppClass *billboardClass = nullptr;
    Il2CppClass *playerHeadClass = nullptr;
    Il2CppClass *uiLabelClass = nullptr;
    Il2CppClass *islandPlayerInfoClass = nullptr;
    Il2CppClass *clientVIPClass = nullptr;
    Il2CppClass *monoBehaviourClass = nullptr;

    // V10.20: read-only identity source. This resolves the local role and original
    // VIP level from ClientPlayer.RoleInfo without writing account/VIP state.
    Il2CppClass *clientPlayerClass = nullptr;
    Il2CppClass *roleInfoClass = nullptr;
    Il2CppClass *commonPlayerInfoClass = nullptr;
    const MethodInfo *clientPlayerGetSingleton = nullptr;
    const MethodInfo *clientPlayerGetRoleInfo = nullptr;
    const MethodInfo *roleInfoGetVipLevel = nullptr;
    const MethodInfo *roleInfoGetRoleName = nullptr;
    FieldInfo *commonRoleId = nullptr;

    // Role-aware local UI targets. These are presentation widgets only.
    Il2CppClass *waitRoomCellClass = nullptr;
    Il2CppClass *roomPlayerInfoCellClass = nullptr;
    Il2CppClass *dgPlayerInfoCellClass = nullptr;
    Il2CppClass *rankPlayerCellClass = nullptr;
    Il2CppClass *roomPlayerDataClass = nullptr;

    const MethodInfo *findObjectsOfType = nullptr;
    const MethodInfo *vipSetLevel = nullptr;
    const MethodInfo *clientVIPGetMaxLevel = nullptr;
    const MethodInfo *billboardShowVip = nullptr;
    const MethodInfo *startCoroutine = nullptr;

    FieldInfo *vipCurrentLevel = nullptr;
    FieldInfo *billboardRoleId = nullptr;
    FieldInfo *billboardVipIcon = nullptr;
    FieldInfo *playerHeadVipIcon = nullptr;
    FieldInfo *playerHeadNameLabel = nullptr;
    FieldInfo *uiLabelText = nullptr;
    FieldInfo *islandPlayerData = nullptr;
    FieldInfo *islandPlayerVipIcon = nullptr;

    FieldInfo *waitRoomCellData = nullptr;
    FieldInfo *waitRoomCellVipIcon = nullptr;
    FieldInfo *roomPlayerDataRoleId = nullptr;
    FieldInfo *roomPlayerInfoRoleId = nullptr;
    FieldInfo *roomPlayerInfoVipIcon = nullptr;
    FieldInfo *dgPlayerInfoRoleId = nullptr;
    FieldInfo *dgPlayerInfoVipIcon = nullptr;
    FieldInfo *rankPlayerRoleId = nullptr;
    FieldInfo *rankPlayerVipIcon = nullptr;

    // V10.25: direct self presentation owners. This avoids depending on global UI scans
    // and lets a non-VIP local account ask the game to create its normal VIP icon.
    FieldInfo *roomPlayerCharacterTopUI = nullptr;
    FieldInfo *roomPlayerTopUI = nullptr;
    FieldInfo *dancerPlayerTopUI = nullptr;

    // V10.26 head-effects preview bindings.
    Il2CppClass *characterTopParamClass = nullptr;
    Il2CppClass *configTitleClass = nullptr;
    Il2CppClass *itemTitleClass = nullptr;
    Il2CppClass *configPersonalNameClass = nullptr;
    Il2CppClass *itemPersonalNameClass = nullptr;
    Il2CppClass *configMarryRingClass = nullptr;
    Il2CppClass *itemMarryRingClass = nullptr;

    const MethodInfo *billboardStartNameEffect = nullptr;
    const MethodInfo *billboardShowRing = nullptr;
    const MethodInfo *billboardShowTitle = nullptr;
    const MethodInfo *billboardSetEffectTitleState = nullptr;
    const MethodInfo *billboardClearEffectTitle = nullptr;
    const MethodInfo *configTitleGetSingleton = nullptr;
    const MethodInfo *titleGetName = nullptr;
    const MethodInfo *configPersonalNameGetSingleton = nullptr;
    const MethodInfo *configMarryRingGetSingleton = nullptr;
    const MethodInfo *marryRingGetName = nullptr;

    FieldInfo *billboardNameColorChange = nullptr;
    FieldInfo *configTitleArray = nullptr;
    FieldInfo *titleID = nullptr;
    FieldInfo *titleStaticEffect = nullptr;
    FieldInfo *titleDynamicEffect = nullptr;
    FieldInfo *configPersonalNameArray = nullptr;
    FieldInfo *personalNameItemID = nullptr;
    FieldInfo *personalNameNameID = nullptr;
    FieldInfo *configMarryRingArray = nullptr;
    FieldInfo *marryRingIndexID = nullptr;
    FieldInfo *paramTitleId = nullptr;
};

static VIPVisualBindings gVIPB;
static BOOL gVIPBindingsReady = NO;
static NSInteger gVIPRequestedLevel = -1;
static NSInteger gVIPOriginalLevel = -1;
static NSString *gVIPStatus = @"OFF • LOCAL_UI_ONLY";
static NSString *gVIPLastTarget = @"none";
static int32_t gVIPLastBillboardMatches = 0;
static int32_t gVIPLastPlayerHeadCount = 0;
static int32_t gVIPLastIconCount = 0;
static int32_t gVIPLastRoleAwareMatches = 0;
static int32_t gVIPLastHeadNameMatches = 0;
static int32_t gVIPLastIslandMatches = 0;
static int32_t gVIPLastDirectTopMatches = 0;
static int32_t gVIPLastSpawnQueued = 0;
static CFTimeInterval gVIPLastWaitEmitAt = 0.0;
static int32_t gVIPLastAppliedCount = 0;
static uint32_t gVIPLastLocalRole = 0;
static NSInteger gVIPLastTrueLevel = -1;
static dispatch_source_t gVIPTimer = nullptr;
static CFTimeInterval gVIPLastEmitAt = 0.0;
static NSInteger gVIPLastEmittedLevel = -999;
static NSString *gVIPLastEmittedTarget = @"none";

static NSMutableArray<NSDictionary *> *gHeadNameEffectCatalog = nil;
static NSMutableArray<NSDictionary *> *gHeadTitleCatalog = nil;
static NSMutableArray<NSDictionary *> *gHeadRingCatalog = nil;
static NSInteger gHeadNameEffectIndex = 0;
static NSInteger gHeadTitleIndex = 0;
static NSInteger gHeadRingIndex = 0;
static BOOL gHeadTitleDynamic = YES;
static NSString *gHeadStatus = @"OFF • LOCAL_UI_ONLY";
static dispatch_source_t gHeadTimer = nullptr;

struct ListCacheEntry {
    Il2CppClass *klass = nullptr;
    const MethodInfo *count = nullptr;
    const MethodInfo *item = nullptr;
};

static API gAPI;
static Bindings gB;              // currently selected runtime profile
static Bindings gClassicB;       // UI_DanceAudition / AuditionGroup
static Bindings gBurstB;         // UI_DanceBurstAu / BurstAuGroup
static ListCacheEntry gListCache[24];
static BOOL gInitialized = NO;
static BOOL gEnabled = NO;
static BOOL gBindingsReady = NO;
static BOOL gAPIsReady = NO;
static dispatch_source_t gTimer = nullptr;
static TNMDAutoPerfectUILogSink gUILogSink = nil;
static NSString *gStatus = @"OFF";
static uint64_t gSeq = 0;
static CFTimeInterval gLastResolveAttempt = 0.0;
static CFTimeInterval gLastDiscoveryAttempt = 0.0;
static CFTimeInterval gLastInstanceProbeLog = 0.0;
static CFTimeInterval gLastInputAttempt = 0.0;
static CFTimeInterval gLastHealth = 0.0;
static Il2CppObject *gUIInstance = nullptr;
static NSString *gActiveProfile = @"none";
static int32_t gActiveFlag = -1;
static FieldInfo *gAppDanceModuleField = nullptr;
static const MethodInfo *gDanceGetMode = nullptr;
static const MethodInfo *gDanceGetLogic = nullptr;
static Il2CppClass *gSystemArrayClass = nullptr;
static const MethodInfo *gArrayGetLength = nullptr;
static const MethodInfo *gArrayGetValue = nullptr;
static const MethodInfo *gUnityTimeGetTime = nullptr;
static Il2CppClass *gStarlightBubbleDanceClass = nullptr;
static Il2CppClass *gBubbleNoteControllerClass = nullptr;
static FieldInfo *gStarlightBubbleNoteCtrlField = nullptr;
static FieldInfo *gBubbleIsAutoPlayField = nullptr;
static FieldInfo *gBubbleComboNowField = nullptr;
static FieldInfo *gBubblePerfectCountField = nullptr;
static FieldInfo *gBubbleIsEndField = nullptr;
static Il2CppObject *gBubbleDanceLogic = nullptr;
static Il2CppObject *gBubbleNoteCtrl = nullptr;
static BOOL gBubbleAutoPlayOwned = NO;
static uint8_t gBubblePreviousAutoPlay = 0;
static uint32_t gBubbleLastCombo = 0;
static int32_t gBubbleLastPerfectCount = 0;
static CFTimeInterval gBubbleLastProgressLog = 0.0;
static Il2CppObject *gLastGroup = nullptr;
static int32_t gLastGroupIndex = -1;
static int32_t gLastArrowIndex = -1;
static int32_t gArrowAttempts = 0;
static int32_t gBeatAttempts = 0;
static BOOL gBeatAccepted = NO;
static CFTimeInterval gBeatFirstAttemptAt = 0.0;
static int32_t gLastJudgeLevel = -1;
static BOOL gGroupCompletionLogged = NO;

// V10.1: exact mode telemetry for every eDanceGameMode value present in the
// current 23.4 dump. Mode 9 is not defined by the enum and is kept as reserved.
struct ModeDescriptor {
    int32_t mode;
    const char *name;
    const char *family;
    int32_t primaryFlag;
    bool playable;
};

static const ModeDescriptor kModeDescriptors[] = {
    { 0,  "All",                       "Meta",       -1,  false },
    { 1,  "Bubble",                    "Bubble",      70, true  },
    { 2,  "Audition",                  "Audition",    71, true  },
    { 3,  "Dynamic",                   "Dynamic",     73, true  },
    { 4,  "Track",                     "Track",       74, true  },
    { 5,  "BurstAu",                   "BurstAu",    308, true  },
    { 6,  "VOS",                       "VOS",        364, true  },
    { 7,  "DanceBall",                 "DanceBall",  487, true  },
    { 8,  "MaxDanceMode",              "Meta",       -1,  false },
    { 10, "BubbleGuide",               "Bubble",     169, true  },
    { 11, "AuditionGuide",             "Audition",   170, true  },
    { 12, "DynamicGuide",              "Dynamic",    171, true  },
    { 13, "TrackGuide",                "Track",      172, true  },
    { 14, "StarlightTheatreBubble",    "Bubble",     180, true  },
    { 15, "StarlightTheatreAudition",  "Audition",   180, true  },
    { 16, "StarlightTheatreDynamic",   "Dynamic",    180, true  },
    { 17, "StarlightTheatreTrack",     "Track",      180, true  },
    { 18, "SpiritOrdeal",              "Bubble",      -1, true  },
    { 19, "SpiritChallengeWith",       "Witch",       72, true  },
    { 20, "IdolBubble",                "Bubble",      -1, true  },
    { 21, "IdolAudition",              "Audition",    -1, true  },
    { 22, "IdolDynamic",               "Dynamic",     -1, true  },
    { 23, "IdolTrack",                 "Track",       -1, true  },
    { 24, "PeakMatchBubble",           "Bubble",      -1, true  },
    { 25, "PeakMatchAudition",         "Audition",    -1, true  },
    { 26, "PeakMatchDynamic",          "Dynamic",     -1, true  },
    { 27, "PeakMatchTrack",            "Track",       -1, true  },
    { 28, "PeakMatchVOS",              "VOS",         -1, true  },
    { 29, "RoomDanceTaiko",            "Taiko",      282, true  },
};

static const ModeDescriptor *ModeDescriptorFor(int32_t mode) {
    for (const auto &entry : kModeDescriptors) {
        if (entry.mode == mode) return &entry;
    }
    return nullptr;
}

static NSString *ModeNameFor(int32_t mode) {
    const ModeDescriptor *d = ModeDescriptorFor(mode);
    if (d) return [NSString stringWithUTF8String:d->name];
    if (mode == 9) return @"Reserved9";
    if (mode < 0) return @"NotDetected";
    return [NSString stringWithFormat:@"Unknown(%d)", mode];
}

static NSString *ModeFamilyFor(int32_t mode) {
    const ModeDescriptor *d = ModeDescriptorFor(mode);
    if (d) return [NSString stringWithUTF8String:d->family];
    if (mode == 9) return @"Reserved";
    return @"Unknown";
}

static int32_t gDetectedMode = -1;
static int32_t gDetectedFallbackFlag = -1;
static NSString *gDetectedModeSource = @"NONE";
static CFTimeInterval gLastModeHeartbeat = 0.0;
static CFTimeInterval gLastFallbackModeProbe = 0.0;
static int32_t gFallbackModeCache = -1;
static int32_t gFallbackFlagCache = -1;

// V10 full-mode router: bind each gameplay family independently. All access is by
// current-build metadata (class/field/method names), never reused native RVAs.
struct FullModeBindings {
    Il2CppClass *bubbleCtrlClass = nullptr;
    FieldInfo *bubbleAuto = nullptr;
    FieldInfo *bubbleCombo = nullptr;
    FieldInfo *bubblePerfect = nullptr;
    FieldInfo *bubbleEnd = nullptr;

    Il2CppClass *vosCtrlClass = nullptr;
    FieldInfo *vosAuto = nullptr;
    FieldInfo *vosCombo = nullptr;
    FieldInfo *vosPerfect = nullptr;
    FieldInfo *vosEnd = nullptr;

    Il2CppClass *danceBallUIClass = nullptr;
    Il2CppClass *danceBallCtrlClass = nullptr;
    FieldInfo *danceBallUICtrl = nullptr;
    FieldInfo *danceBallAuto = nullptr;
    FieldInfo *danceBallCombo = nullptr;
    FieldInfo *danceBallPerfect = nullptr;
    FieldInfo *danceBallEnd = nullptr;

    Il2CppClass *dynamicUIClass = nullptr;
    Il2CppClass *dynamicCtrlClass = nullptr;
    Il2CppClass *dynamicGroupClass = nullptr;
    Il2CppClass *dynamicBeatKeysClass = nullptr;
    Il2CppClass *dynamicArrowClass = nullptr;
    const MethodInfo *dynamicOnDrumDown = nullptr;
    FieldInfo *dynamicCtrlGroup = nullptr;
    FieldInfo *dynamicCtrlSourceTime = nullptr;
    FieldInfo *dynamicCtrlMusicBeginTime = nullptr;
    FieldInfo *dynamicCtrlOffsetTime = nullptr;
    FieldInfo *dynamicUICurGroup = nullptr;
    FieldInfo *dynamicUIIsCanJudgeHit = nullptr;
    FieldInfo *dynamicUIIsInCrazy = nullptr;
    FieldInfo *dynamicGroupBeatKeys = nullptr;
    FieldInfo *dynamicGroupCurKeysIndex = nullptr;
    FieldInfo *dynamicGroupIndex = nullptr;
    FieldInfo *dynamicGroupIsShow = nullptr;
    FieldInfo *dynamicBeatArrows = nullptr;
    FieldInfo *dynamicBeatRanges = nullptr;
    FieldInfo *dynamicBeatCurArrow = nullptr;
    FieldInfo *dynamicBeatStartHitTime = nullptr;
    FieldInfo *dynamicBeatEndHitTime = nullptr;
    const MethodInfo *dynamicBeatIsInHitTime = nullptr;
    FieldInfo *dynamicArrowDir = nullptr;
    FieldInfo *dynamicArrowHit = nullptr;

    Il2CppClass *trackUIClass = nullptr;
    Il2CppClass *trackGuideUIClass = nullptr;
    Il2CppClass *trackCtrlClass = nullptr;
    Il2CppClass *trackNoteClass = nullptr;
    Il2CppClass *trackPoolsClass = nullptr;
    Il2CppClass *trackUINoteClass = nullptr;
    const MethodInfo *trackOnPress = nullptr;
    const MethodInfo *trackGuideOnPress = nullptr;
    const MethodInfo *trackPressLeft = nullptr;
    const MethodInfo *trackPressRight = nullptr;
    const MethodInfo *trackGuidePressLeft = nullptr;
    const MethodInfo *trackGuidePressRight = nullptr;
    const MethodInfo *trackJudgeDrag = nullptr;
    FieldInfo *trackUIBtnLeft = nullptr;
    FieldInfo *trackUIBtnRight = nullptr;
    FieldInfo *trackGuideBtnLeft = nullptr;
    FieldInfo *trackGuideBtnRight = nullptr;
    FieldInfo *trackUIPools = nullptr;
    FieldInfo *trackPoolsCurrentNoteUI = nullptr;
    FieldInfo *trackPoolsAudioTime = nullptr;
    FieldInfo *trackUINoteData = nullptr;
    FieldInfo *trackCtrlNote = nullptr;
    FieldInfo *trackCtrlAllNotes = nullptr;
    FieldInfo *trackCtrlAudioTime = nullptr;
    FieldInfo *trackNoteIndex = nullptr;
    FieldInfo *trackNoteDir = nullptr;
    FieldInfo *trackNoteChannel = nullptr;
    FieldInfo *trackNoteJudgeTime = nullptr;
    FieldInfo *trackNoteSecondJudgeTime = nullptr;
    FieldInfo *trackNoteRanges = nullptr;
    FieldInfo *trackNoteSecondRanges = nullptr;
    FieldInfo *trackNoteJudgeEnd = nullptr;
    FieldInfo *trackNoteJudgeSecond = nullptr;
    FieldInfo *trackNoteHitSecond = nullptr;
    FieldInfo *trackNoteJudgeLevel = nullptr;

    Il2CppClass *witchUIClass = nullptr;
    Il2CppClass *witchGroupClass = nullptr;
    Il2CppClass *auditionArrowClass = nullptr;
    const MethodInfo *witchOnDrumDown = nullptr;
    const MethodInfo *witchIsAllHitLane = nullptr;
    FieldInfo *witchUICurGroup = nullptr;
    FieldInfo *witchUIAudioTime = nullptr;
    FieldInfo *witchUICenterTime = nullptr;
    FieldInfo *witchUIOpenClickBeatTime = nullptr;
    FieldInfo *witchUIDrumArray = nullptr;
    FieldInfo *witchGroupArrowsArray = nullptr;
    FieldInfo *witchGroupIndexArray = nullptr;
    FieldInfo *witchGroupGroupIndex = nullptr;
    FieldInfo *witchGroupIsShow = nullptr;
    FieldInfo *witchGroupIsHitBeat = nullptr;
    FieldInfo *witchGroupRanges = nullptr;
    FieldInfo *witchGroupJudge = nullptr;
    FieldInfo *witchArrowDir = nullptr;

    Il2CppClass *taikoUIClass = nullptr;
    Il2CppClass *taikoCtrlClass = nullptr;
    Il2CppClass *taikoNoteClass = nullptr;
    const MethodInfo *taikoPressLeft = nullptr;
    const MethodInfo *taikoPressRight = nullptr;
    const MethodInfo *taikoDragLeft = nullptr;
    const MethodInfo *taikoDragRight = nullptr;
    FieldInfo *taikoUICtrl = nullptr;
    FieldInfo *taikoUIBtnLeft = nullptr;
    FieldInfo *taikoUIBtnRight = nullptr;
    FieldInfo *taikoCtrlNote = nullptr;
    FieldInfo *taikoCtrlTime = nullptr;
    FieldInfo *taikoCtrlLongInterval = nullptr;
    FieldInfo *taikoNoteDir = nullptr;
    FieldInfo *taikoNoteType = nullptr;
    FieldInfo *taikoNoteJudgeTime = nullptr;
    FieldInfo *taikoNoteEndTime = nullptr;
};
static FullModeBindings gF;

struct AutoOwnedSlot {
    Il2CppObject *ctrl = nullptr;
    FieldInfo *field = nullptr;
    uint8_t previous = 0;
    BOOL owned = NO;
    int32_t mode = -1;
};
static AutoOwnedSlot gAutoSlots[3]; // Bubble, VOS, DanceBall

static int32_t gLastMode = -999;
static Il2CppObject *gDynamicPendingArrow = nullptr;
static CFTimeInterval gDynamicPendingAt = 0.0;
static int32_t gDynamicPendingRetries = 0;
static Il2CppObject *gTrackHeldUI = nullptr;
static Il2CppObject *gTrackHeldPools = nullptr;
static const MethodInfo *gTrackHeldPressMethod = nullptr;
static Il2CppObject *gTrackHeldNote = nullptr;
static int32_t gTrackHeldDir = 0;
static uint8_t gTrackHeldBoth = 0;
static BOOL gTrackHeldPhysical = NO;
static Il2CppObject *gTrackHeldLeftGO = nullptr;
static Il2CppObject *gTrackHeldRightGO = nullptr;
static const MethodInfo *gTrackHeldLeftMethod = nullptr;
static const MethodInfo *gTrackHeldRightMethod = nullptr;
static BOOL gTrackHeldLeftDown = NO;
static BOOL gTrackHeldRightDown = NO;
static BOOL gTrackLongHold = NO;
static CFTimeInterval gTrackReleaseAt = 0.0;
// V10.11: TrackUIPools.curDispalyNote can advance before the previous note's
// JudgeTime. Lock the first unjudged note we acquire so an 8 ms scheduler tick
// cannot lose it merely because the presentation cursor moved to the next note.
static Il2CppObject *gTrackPendingNote = nullptr;
static float gTrackPendingJudgeTime = 0.0f;
static float gTrackPendingSecondJudgeTime = 0.0f;
static int32_t gTrackPendingDir = 0;
static uint8_t gTrackPendingChannel = 0;
static NSString *gTrackPendingSource = nil;
static CFTimeInterval gTrackPendingAt = 0.0;
static int32_t gTrackPendingAttempts = 0;
static CFTimeInterval gTrackRetryNotBefore = 0.0;
static Il2CppObject *gWitchGroup = nullptr;
static int32_t gWitchLane = 0;
static int32_t gWitchPendingIndex = -1;
static CFTimeInterval gWitchPendingAt = 0.0;
static int32_t gWitchPendingRetries = 0;
static BOOL gWitchBeatSent = NO;
static Il2CppObject *gTaikoLastNote = nullptr;
static Il2CppObject *gTaikoHeldUI = nullptr;
static Il2CppObject *gTaikoHeldGO = nullptr;
static const MethodInfo *gTaikoHeldPress = nullptr;
static const MethodInfo *gTaikoHeldDrag = nullptr;
static BOOL gTaikoLongHold = NO;
static int32_t gTaikoHeldDir = 0;
static CFTimeInterval gTaikoReleaseAt = 0.0;
static CFTimeInterval gTaikoLastDragAt = 0.0;

// Safe-input controls. These are stability controls, not judgement/score writes.
static BOOL gArrowPacingEnabled = YES;   // 75..110 ms between accepted arrow inputs.
static BOOL gBeatJitterEnabled = YES;    // Small target offset to avoid same-tick dispatch collisions.
static BOOL gBeatOneShotEnabled = YES;   // One Beat dispatch per group until state ACK.
static BOOL gArrowAckGateEnabled = YES;  // Never advance to next arrow before curArrowIndex/allHit changes.

static int32_t gPendingArrowIndex = -1;
static CFTimeInterval gPendingArrowSentAt = 0.0;
static int32_t gPendingArrowRetries = 0;
static CFTimeInterval gNextArrowAllowedAt = 0.0;

static BOOL gBeatDispatched = NO;
static CFTimeInterval gBeatDispatchedAt = 0.0;
static float gBeatJitterSeconds = 0.0f;
static Il2CppObject *gHeldBeatButton = nullptr;
static CFTimeInterval gBeatButtonReleaseAt = 0.0;

static Il2CppObject *CachedSkinPlayer(void);

static NSString *TimeString() {
    static NSDateFormatter *fmt = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ";
    });
    return [fmt stringFromDate:[NSDate date]];
}

static NSString *LogsDir() {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (docs.length == 0) docs = NSTemporaryDirectory();
    NSString *dir = [docs stringByAppendingPathComponent:@"AuditionTNMDModLogs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return dir;
}

static NSString *Path(NSString *name) {
    return [LogsDir() stringByAppendingPathComponent:name];
}

// -------------------------------------------------------------------------
// V10.22 Diagnostic Core
// -------------------------------------------------------------------------

static NSString *gDiagSessionId = nil;
static NSString *gDiagPreviousSessionId = nil;
static NSString *gDiagSessionWallStart = nil;
static NSString *gDiagPreviousEndReason = @"UNKNOWN";
static uint64_t gDiagTraceCounter = 0;
static CFTimeInterval gDiagSessionMonoStart = 0.0;
static NSMutableDictionary *gDiagFeatureState = nil;
static NSString *gDiagLastFailureFeature = @"NONE";
static NSString *gDiagLastFailureTrace = @"-";
static NSString *gDiagLastFailureStage = @"NONE";
static NSString *gDiagLastFailureReason = @"NONE";
static NSString *gDiagLastFailureState = @"NONE";
static NSString *gDiagLastFailureEvidence = @"-";
static NSString *gDiagLastFailureLastGood = @"NONE";
static NSString *gDiagLastFailureAction = @"-";
static uint64_t gDiagOpenFailures = 0;
static uint64_t gDiagWriteFailures = 0;
static uint64_t gDiagFlushFailures = 0;
static uint64_t gDiagBytesWritten = 0;
static uint64_t gDiagDroppedEvents = 0;
static CFTimeInterval gDiagLastSuccessfulWrite = 0.0;
static CFTimeInterval gDiagLastSuccessfulFlush = 0.0;
static uint64_t gDiagRotationCount = 0;
static NSString *gDiagLastExportPath = nil;

static NSObject *DiagLock() {
    static NSObject *lock = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}

static NSString *DiagArch() {
#if defined(__arm64e__)
    return @"arm64e";
#elif defined(__aarch64__) || defined(__arm64__)
    return @"arm64";
#elif defined(__x86_64__)
    return @"x86_64";
#else
    return @"unknown";
#endif
}

static NSString *DiagMakeSessionId() {
    static NSDateFormatter *fmt = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyyMMdd-HHmmss-SSS";
    });
    return [NSString stringWithFormat:@"S%@-%d", [fmt stringFromDate:[NSDate date]], getpid()];
}

static NSString *DiagNewTraceId(NSString *feature) {
    (void)feature;
    gDiagTraceCounter++;
    return [NSString stringWithFormat:@"T%06llu", (unsigned long long)gDiagTraceCounter];
}

static NSMutableDictionary *DiagStateForFeature(NSString *feature) {
    if (!gDiagFeatureState) gDiagFeatureState = [NSMutableDictionary dictionary];
    NSString *key = feature.length ? feature : @"Unknown";
    NSMutableDictionary *st = gDiagFeatureState[key];
    if (!st) {
        st = [@{
            @"state": @"OFF", @"stage": @"NOT_STARTED", @"reason": @"NO_DATA",
            @"lastGood": @"NONE", @"firstFail": @"NONE", @"firstFailReason": @"NONE",
            @"trace": @"-", @"action": @"Background", @"event": @"NONE",
            @"lastSeq": @0, @"lastMono": @0.0
        } mutableCopy];
        gDiagFeatureState[key] = st;
    }
    return st;
}

static NSInteger DiagStageRank(NSString *stage) {
    static NSArray *order = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        order = @[@"NOT_STARTED", @"CONFIG", @"PRECHECK", @"RUNTIME_READY", @"RESOLVE", @"INSTANCE",
                  @"SOURCE", @"SELECT", @"ARGS", @"INVOKE", @"CALLBACK", @"READBACK", @"SAVE",
                  @"SYNC", @"RECONCILE", @"VERIFY", @"COMPLETE", @"HEALTH"];
    });
    NSUInteger idx = [order indexOfObject:stage ?: @""];
    return idx == NSNotFound ? 0 : (NSInteger)idx;
}

static BOOL DiagContains(NSString *haystack, NSString *needle) {
    return haystack.length && needle.length && [haystack rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static NSString *DiagStageFor(NSString *feature, NSString *event, NSString *state, NSString *reason) {
    NSString *e = event.uppercaseString ?: @"";
    NSString *r = reason.uppercaseString ?: @"";
    (void)feature;
    if ([e isEqualToString:@"SESSION_HEADER"]) return @"RUNTIME_READY";
    if ([e isEqualToString:@"TOGGLE"]) return @"CONFIG";
    if ([e isEqualToString:@"MODE"]) return @"RUNTIME_READY";
    if ([e isEqualToString:@"RESOLVE"]) return @"RESOLVE";
    if ([e isEqualToString:@"TASK"]) return @"SELECT";
    if ([e isEqualToString:@"ACTION"]) return @"INVOKE";
    if ([e isEqualToString:@"ACK"]) return @"CALLBACK";
    if ([e isEqualToString:@"PROGRESS"]) return @"VERIFY";
    if ([e isEqualToString:@"COMPLETE"]) return @"COMPLETE";
    if ([e isEqualToString:@"HEALTH"]) return @"HEALTH";

    if (DiagContains(r, @"IL2CPP") || DiagContains(r, @"BIND") || DiagContains(r, @"DOMAIN") ||
        DiagContains(r, @"METHOD_MISSING") || DiagContains(r, @"CLASS_MISSING") || DiagContains(r, @"RESOLVE")) return @"RESOLVE";
    if (DiagContains(r, @"INSTANCE") || DiagContains(r, @"PLAYER_NOT_READY") || DiagContains(r, @"TARGET_WAIT") ||
        DiagContains(r, @"TARGET_GONE") || DiagContains(r, @"UI_TARGET") || DiagContains(r, @"UI_FLAG_CLASS")) return @"INSTANCE";
    if (DiagContains(r, @"SOURCE") || DiagContains(r, @"CATALOG") || DiagContains(r, @"SEARCH") ||
        DiagContains(r, @"CONFIG_ITEM") || DiagContains(r, @"PROFILE_EMPTY") || DiagContains(r, @"UI_NOT_READY") ||
        DiagContains(r, @"MODE_PROBE") || DiagContains(r, @"BUTTON_NOT_FOUND")) return @"SOURCE";
    if (DiagContains(r, @"OUT_OF_RANGE") || DiagContains(r, @"INVALID") || DiagContains(r, @"PRECONDITION")) return @"PRECHECK";
    if (DiagContains(r, @"ARG") || DiagContains(r, @"SIGNATURE") || DiagContains(r, @"ABI")) return @"ARGS";
    if (DiagContains(r, @"INVOKE") || DiagContains(r, @"WRITE_FAIL") || DiagContains(r, @"PRESS_EXCEPTION") ||
        DiagContains(r, @"INPUT_EXCEPTION") || DiagContains(r, @"CREATE_FAILED") || DiagContains(r, @"DISPATCH")) return @"INVOKE";
    if (DiagContains(r, @"READBACK")) return @"READBACK";
    if (DiagContains(r, @"SAVE")) return @"SAVE";
    if (DiagContains(r, @"SYNC") || DiagContains(r, @"SERVER_REJECT")) return @"SYNC";
    if (DiagContains(r, @"RECONCILE")) return @"RECONCILE";
    if (DiagContains(r, @"NO_EFFECT") || DiagContains(r, @"JUDGEMENT") || DiagContains(r, @"VERIFY") ||
        DiagContains(r, @"APPLIED") || DiagContains(r, @"PINNED") || DiagContains(r, @"RESTORED")) return @"VERIFY";
    if ([e isEqualToString:@"SOURCE"]) return @"SOURCE";
    if ([e isEqualToString:@"FAULT"] || [e isEqualToString:@"STALL"]) return @"VERIFY";
    return @"HEALTH";
}

static BOOL DurableWriteData(NSString *path, NSData *data, BOOL append, BOOL durableFlush) {
    if (path.length == 0 || data.length == 0) { gDiagDroppedEvents++; return NO; }
    @synchronized (DiagLock()) {
        int flags = O_WRONLY | O_CREAT | (append ? O_APPEND : O_TRUNC);
        int fd = open(path.fileSystemRepresentation, flags, 0644);
        if (fd < 0) { gDiagOpenFailures++; return NO; }
        const uint8_t *p = (const uint8_t *)data.bytes;
        size_t left = data.length;
        BOOL ok = YES;
        while (left > 0) {
            ssize_t n = write(fd, p, left);
            if (n <= 0) { gDiagWriteFailures++; ok = NO; break; }
            p += n;
            left -= (size_t)n;
            gDiagBytesWritten += (uint64_t)n;
            gDiagLastSuccessfulWrite = CACurrentMediaTime();
        }
        if (durableFlush) {
            if (fsync(fd) != 0) { gDiagFlushFailures++; ok = NO; }
            else gDiagLastSuccessfulFlush = CACurrentMediaTime();
        }
        close(fd);
        return ok;
    }
}

static BOOL DurableAppendMode(NSString *path, NSString *line, BOOL durableFlush) {
    if (line.length == 0) { gDiagDroppedEvents++; return NO; }
    NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    return DurableWriteData(path, data, YES, durableFlush);
}

static BOOL DurableAppend(NSString *path, NSString *line) {
    return DurableAppendMode(path, line, YES);
}

static BOOL DurableReplace(NSString *path, NSString *text) {
    NSData *data = [(text.length ? text : @"\n") dataUsingEncoding:NSUTF8StringEncoding];
    return DurableWriteData(path, data, NO, YES);
}

static NSString *ReadText(NSString *path) {
    NSError *err = nil;
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
    return text ?: @"";
}

static NSString *TailLines(NSString *text, NSUInteger count) {
    if (text.length == 0) return @"<empty>";
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    NSUInteger n = lines.count;
    NSUInteger start = n > count ? n - count : 0;
    return [[lines subarrayWithRange:NSMakeRange(start, n - start)] componentsJoinedByString:@"\n"];
}

static void CopyIfExists(NSString *src, NSString *dst) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:src]) return;
    [fm removeItemAtPath:dst error:NULL];
    [fm copyItemAtPath:src toPath:dst error:NULL];
}

static void RotateOne(NSString *base) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *cur = Path([base stringByAppendingString:@".current.log"]);
    NSString *prev = Path([base stringByAppendingString:@".previous.log"]);
    if ([fm fileExistsAtPath:prev]) [fm removeItemAtPath:prev error:NULL];
    if ([fm fileExistsAtPath:cur]) {
        if ([fm moveItemAtPath:cur toPath:prev error:NULL]) gDiagRotationCount++;
    }
}

static NSString *DiagMetaText() {
    NSBundle *b = NSBundle.mainBundle;
    NSString *appVersion = [b objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    NSString *appBuild = [b objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown";
    const char *mainImageC = _dyld_image_count() > 0 ? _dyld_get_image_name(0) : nullptr;
    NSString *mainImage = mainImageC ? [NSString stringWithUTF8String:mainImageC] : @"unknown";
    return [NSString stringWithFormat:
            @"DIAGNOSTIC_SCHEMA=2\nSESSION_ID=%@\nPREVIOUS_SESSION_ID=%@\nSESSION_START_WALL=%@\nSESSION_START_MONO=%.6f\nPREVIOUS_SESSION_END=%@\nPID=%d\nPROCESS=%@\nBUNDLE_ID=%@\nGAME_VERSION=%@\nGAME_BUILD=%@\nMOD_BUILD=%@\nPLATFORM=iOS\nOS_VERSION=%@\nDEVICE_MODEL=%@\nARCH=%@\nENGINE_MODE=Unity IL2CPP\nMAIN_IMAGE=%@\nLOG_DIR=%@\n",
            gDiagSessionId ?: @"-", gDiagPreviousSessionId ?: @"-", gDiagSessionWallStart ?: @"-", gDiagSessionMonoStart, gDiagPreviousEndReason ?: @"UNKNOWN",
            getpid(), NSProcessInfo.processInfo.processName ?: @"unknown", b.bundleIdentifier ?: @"unknown",
            appVersion, appBuild, kBuildTag, NSProcessInfo.processInfo.operatingSystemVersionString ?: @"unknown",
            UIDevice.currentDevice.model ?: @"unknown", DiagArch(), mainImage, LogsDir()];
}

static NSString *DiagLoggerHealthTextInternal() {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:Path(@"Feature.current.log") error:NULL];
    unsigned long long size = [attrs fileSize];
    NSString *state = (gDiagOpenFailures || gDiagWriteFailures || gDiagFlushFailures || gDiagDroppedEvents) ? @"LOGGER_DEGRADED" : @"OK";
    return [NSString stringWithFormat:
            @"LOGGER_STATE=%@\npersistentPathReady=%d\nopenFailures=%llu\nwriteFailures=%llu\nflushFailures=%llu\ndroppedEvents=%llu\nbytesWritten=%llu\ncurrentFileSize=%llu\nlastSuccessfulWriteMono=%.6f\nlastSuccessfulFlushMono=%.6f\nrotationCount=%llu\n",
            state, [[NSFileManager defaultManager] isWritableFileAtPath:LogsDir()] ? 1 : 0,
            (unsigned long long)gDiagOpenFailures, (unsigned long long)gDiagWriteFailures,
            (unsigned long long)gDiagFlushFailures, (unsigned long long)gDiagDroppedEvents,
            (unsigned long long)gDiagBytesWritten, size, gDiagLastSuccessfulWrite,
            gDiagLastSuccessfulFlush, (unsigned long long)gDiagRotationCount];
}

static NSString *DiagFailureSummaryInternal() {
    return [NSString stringWithFormat:
            @"GAME=AUDITION\nGAME_BUILD=%@\nSESSION=%@\nTRACE=%@\nFEATURE=%@\nACTION=%@\nSTATE=%@\nLAST_GOOD=%@\nFIRST_FAIL=%@\nREASON=%@\nEVIDENCE=%@\nNEXT_DIAGNOSTIC_STEP=%@\nLOG_DIR=%@\n",
            kBuildTag, gDiagSessionId ?: @"-", gDiagLastFailureTrace ?: @"-",
            gDiagLastFailureFeature ?: @"NONE", gDiagLastFailureAction ?: @"-", gDiagLastFailureState ?: @"NONE",
            gDiagLastFailureLastGood ?: @"NONE", gDiagLastFailureStage ?: @"NONE", gDiagLastFailureReason ?: @"NONE",
            gDiagLastFailureEvidence ?: @"-",
            [gDiagLastFailureStage isEqualToString:@"NONE"] ? @"Reproduce feature once, then Snapshot/Export Fix Pack" : [NSString stringWithFormat:@"Inspect %@ stage and selected feature trace", gDiagLastFailureStage],
            LogsDir()];
}

static void DiagWriteFailureArtifacts() {
    NSString *summary = DiagFailureSummaryInternal();
    DurableReplace(Path(@"LastFailure.txt"), summary);
    NSString *tail = TailLines(ReadText(Path(@"Feature.current.log")), 80);
    NSString *crash = [NSString stringWithFormat:@"%@\nLAST_EVENTS_TAIL:\n%@\n", summary, tail];
    DurableReplace(Path(@"CrashContext.txt"), crash);
}

static NSString *DiagTraceForFeature(NSString *feature) {
    NSMutableDictionary *st = DiagStateForFeature(feature);
    NSString *trace = st[@"trace"];
    if (trace.length == 0 || [trace isEqualToString:@"-"]) {
        trace = DiagNewTraceId(feature);
        st[@"trace"] = trace;
        st[@"action"] = @"Background";
    }
    return trace;
}

static NSString *DiagBeginTrace(NSString *feature, NSString *action) {
    @synchronized (DiagLock()) {
        NSMutableDictionary *st = DiagStateForFeature(feature);
        NSString *trace = DiagNewTraceId(feature);
        st[@"trace"] = trace;
        st[@"action"] = action.length ? action : @"Action";
        st[@"firstFail"] = @"NONE";
        st[@"firstFailReason"] = @"NONE";
        return trace;
    }
}

static void DiagUpdateFeatureState(NSString *feature, NSString *event, NSString *state, NSString *reason, NSString *stage, uint64_t seq, CFTimeInterval mono) {
    NSMutableDictionary *st = DiagStateForFeature(feature);
    st[@"state"] = state ?: @"UNKNOWN";
    st[@"stage"] = stage ?: @"UNKNOWN";
    st[@"reason"] = reason ?: @"UNKNOWN";
    st[@"event"] = event ?: @"STATE";
    st[@"lastSeq"] = @(seq);
    st[@"lastMono"] = @(mono);

    BOOL wait = [state isEqualToString:@"WAIT_PREREQ"] || [state isEqualToString:@"WAIT_COOLDOWN"];
    BOOL hardFail = [state isEqualToString:@"FAULT"] || [state isEqualToString:@"STALLED"] || [state isEqualToString:@"BLOCKED"] ||
                    [event isEqualToString:@"FAULT"] || [event isEqualToString:@"STALL"];
    BOOL success = [state isEqualToString:@"READY"] || [state isEqualToString:@"RUNNING"] || [state isEqualToString:@"COMPLETE"] || [state isEqualToString:@"OFF"];

    if (wait || hardFail) {
        if ([st[@"firstFail"] isEqualToString:@"NONE"]) {
            st[@"firstFail"] = stage ?: @"UNKNOWN";
            st[@"firstFailReason"] = reason ?: @"UNKNOWN";
        }
    } else if (success) {
        st[@"lastGood"] = stage ?: @"UNKNOWN";
        NSString *firstFail = st[@"firstFail"];
        if (![firstFail isEqualToString:@"NONE"] && DiagStageRank(stage) >= DiagStageRank(firstFail)) {
            st[@"firstFail"] = @"NONE";
            st[@"firstFailReason"] = @"NONE";
        }
    }

    if (hardFail) {
        gDiagLastFailureFeature = feature ?: @"Unknown";
        gDiagLastFailureTrace = st[@"trace"] ?: @"-";
        gDiagLastFailureStage = stage ?: @"UNKNOWN";
        gDiagLastFailureReason = reason ?: @"UNKNOWN";
        gDiagLastFailureState = state ?: @"UNKNOWN";
        gDiagLastFailureLastGood = st[@"lastGood"] ?: @"NONE";
        gDiagLastFailureAction = st[@"action"] ?: @"-";
        gDiagLastFailureEvidence = [NSString stringWithFormat:@"event=%@ seq=%llu mono=%.6f", event ?: @"STATE", (unsigned long long)seq, mono];
    }
}

static void DiagRecord(NSString *feature, NSString *event, NSString *state, NSString *reason, NSString *details) {
    if (!gDiagSessionId) gDiagSessionId = DiagMakeSessionId();
    NSString *f = feature.length ? feature : @"Unknown";
    NSString *e = event.length ? event : @"STATE";
    NSString *s = state.length ? state : @"UNKNOWN";
    NSString *r = reason.length ? reason : @"UNKNOWN";
    NSString *stage = DiagStageFor(f, e, s, r);
    CFTimeInterval mono = CACurrentMediaTime();
    NSString *trace = nil;
    uint64_t seq = 0;
    @synchronized (DiagLock()) {
        trace = DiagTraceForFeature(f);
        gSeq++;
        seq = gSeq;
        DiagUpdateFeatureState(f, e, s, r, stage, seq, mono);
    }
    NSString *line = [NSString stringWithFormat:
                      @"%@ [mono=%.6f] [sid=%@] [trace=%@] [seq=%llu] [F:%@] [STAGE=%@] [EVENT=%@] [STATUS=%@] [REASON=%@]%@",
                      TimeString(), mono, gDiagSessionId ?: @"-", trace ?: @"-", (unsigned long long)seq,
                      f, stage, e, s, r, details.length ? [@" " stringByAppendingString:details] : @""];
    BOOL hardFail = [s isEqualToString:@"FAULT"] || [s isEqualToString:@"STALLED"] || [s isEqualToString:@"BLOCKED"] ||
                    [e isEqualToString:@"FAULT"] || [e isEqualToString:@"STALL"];
    BOOL critical = hardFail || [e isEqualToString:@"ACTION"] || [e isEqualToString:@"TOGGLE"] || [e isEqualToString:@"SESSION_HEADER"];
    NSString *featurePath = Path(@"Feature.current.log");
    if ((seq & 0xFFu) == 0) {
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:featurePath error:NULL];
        if ([attrs fileSize] > (4ull * 1024ull * 1024ull)) {
            NSString *roll = Path(@"Feature.roll.log");
            [[NSFileManager defaultManager] removeItemAtPath:roll error:NULL];
            if ([[NSFileManager defaultManager] moveItemAtPath:featurePath toPath:roll error:NULL]) gDiagRotationCount++;
        }
    }
    DurableAppendMode(featurePath, line, critical);
    if (hardFail) DiagWriteFailureArtifacts();
}

static void Emit(NSString *event, NSString *state, NSString *reason, NSString *details = nil) {
    DiagRecord(@"AutoPerfect", event, state, reason, details);
    gStatus = [NSString stringWithFormat:@"%@ • %@", state ?: @"UNKNOWN", reason ?: @"UNKNOWN"];
    if (gUILogSink) {
        NSString *uiReason = details.length ? [NSString stringWithFormat:@"%@ • %@", reason ?: @"UNKNOWN", details] : (reason ?: @"UNKNOWN");
        gUILogSink(@"AutoPerfect", state ?: @"UNKNOWN", uiReason);
    }
}

static void Boot(NSString *event, NSString *reason) {
    CFTimeInterval mono = CACurrentMediaTime();
    NSString *line = [NSString stringWithFormat:
                      @"%@ [mono=%.6f] [sid=%@] [BOOT] [STAGE=BOOT] [EVENT=%@] [STATUS=INFO] [REASON=%@] pid=%d bundle=%@ build=%@",
                      TimeString(), mono, gDiagSessionId ?: @"-", event ?: @"STATE", reason ?: @"OK",
                      getpid(), NSBundle.mainBundle.bundleIdentifier ?: @"unknown", kBuildTag];
    DurableAppend(Path(@"Boot.current.log"), line);
}

static void DiagWriteMetaAndHealth() {
    DurableReplace(Path(@"Diagnostic.meta.txt"), DiagMetaText());
    DurableReplace(Path(@"LoggerHealth.txt"), DiagLoggerHealthTextInternal());
}

static NSString *DiagStageMapInternal() {
    NSMutableString *out = [NSMutableString stringWithFormat:@"SESSION=%@\n", gDiagSessionId ?: @"-"];
    NSArray *features = @[@"AutoPerfect", @"Skin", @"VIPVisual", @"HeadFX", @"CheckLog"];
    for (NSString *feature in features) {
        NSMutableDictionary *st = DiagStateForFeature(feature);
        [out appendFormat:@"%@  state=%@ stage=%@ reason=%@ lastGood=%@ firstFail=%@ trace=%@ action=%@\n",
         feature, st[@"state"] ?: @"-", st[@"stage"] ?: @"-", st[@"reason"] ?: @"-",
         st[@"lastGood"] ?: @"NONE", st[@"firstFail"] ?: @"NONE", st[@"trace"] ?: @"-", st[@"action"] ?: @"-"];
    }
    return out;
}

static NSString *DiagSemanticStageMapInternal() {
    NSMutableString *out = [NSMutableString string];
    NSArray *features = @[@"AutoPerfect", @"Skin", @"VIPVisual", @"HeadFX", @"CheckLog"];
    for (NSString *feature in features) {
        NSMutableDictionary *st = DiagStateForFeature(feature);
        [out appendFormat:@"%@|state=%@|stage=%@|reason=%@|lastGood=%@|firstFail=%@\n",
         feature, st[@"state"] ?: @"-", st[@"stage"] ?: @"-", st[@"reason"] ?: @"-",
         st[@"lastGood"] ?: @"NONE", st[@"firstFail"] ?: @"NONE"];
    }
    return out;
}

static NSString *DiagResolverSnapshot() {
    return [NSString stringWithFormat:
            @"build=%@\napisReady=%d\nbindingsReady=%d\nactiveProfile=%@\ndetectedMode=%d\nmodeName=%@\nmodeSource=%@\nskinBindingsReady=%d\nvipBindingsReady=%d\n",
            kBuildTag, gAPIsReady ? 1 : 0, gBindingsReady ? 1 : 0, gActiveProfile ?: @"none",
            gDetectedMode, ModeNameFor(gDetectedMode), gDetectedModeSource ?: @"NONE",
            gSkinBindingsReady ? 1 : 0, gVIPBindingsReady ? 1 : 0];
}

static NSString *DiagInstanceSnapshot() {
    return [NSString stringWithFormat:
            @"uiInstance=%p\nlastGroup=%p\ngroupIndex=%d\nskinPlayer=%p\nskinRole=%u\nskinTargetSource=%@\nvipLocalRole=%u\nvipTarget=%@\nsceneHint=%@\n",
            gUIInstance, gLastGroup, gLastGroupIndex, CachedSkinPlayer(), gSkinLastRoleId,
            gSkinLastTargetSource ?: @"none", gVIPLastLocalRole, gVIPLastTarget ?: @"none", gActiveProfile ?: @"none"];
}

static NSString *DiagConfigSnapshot() {
    return [NSString stringWithFormat:
            @"autoEnabled=%d\narrowPacing=%d\nbeatJitter=%d\nbeatOneShot=%d\narrowAckGate=%d\nskinPinnedCount=%lu\nvipRequested=%ld\n",
            gEnabled ? 1 : 0, gArrowPacingEnabled ? 1 : 0, gBeatJitterEnabled ? 1 : 0,
            gBeatOneShotEnabled ? 1 : 0, gArrowAckGateEnabled ? 1 : 0,
            (unsigned long)gSkinPinnedByType.count, (long)gVIPRequestedLevel];
}

static NSString *DiagDependencyHealth() {
    return [NSString stringWithFormat:
            @"RuntimeReady=%@\nResolver=%@\nAutoBindings=%@\nSkinBindings=%@\nVIPBindings=%@\nLogger=%@\n",
            gAPIsReady ? @"READY" : @"NOT_READY", gAPIsReady ? @"READY" : @"NOT_READY",
            gBindingsReady ? @"READY" : @"NOT_READY", gSkinBindingsReady ? @"READY" : @"NOT_READY",
            gVIPBindingsReady ? @"READY" : @"NOT_READY",
            (gDiagOpenFailures || gDiagWriteFailures || gDiagFlushFailures) ? @"FAULT" : @"READY"];
}

static void DiagWriteSessionMarker() {
    DurableReplace(Path(@"Session.active"), [NSString stringWithFormat:@"%@\n", gDiagSessionId ?: @"-"]);
}

static void DiagClearSessionMarker() {
    [[NSFileManager defaultManager] removeItemAtPath:Path(@"Session.active") error:NULL];
}

static void *ResolveSymbol(const char *name) {
    if (!name) return nullptr;
    void *p = dlsym(RTLD_DEFAULT, name);
    if (p) return p;

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *image = _dyld_get_image_name(i);
        if (!image) continue;
        if (!strstr(image, "UnityFramework") && !strstr(image, "libil2cpp")) continue;
        void *h = dlopen(image, RTLD_LAZY | RTLD_NOLOAD);
        if (!h) continue;
        p = dlsym(h, name);
        dlclose(h);
        if (p) return p;
    }
    return nullptr;
}

static bool ResolveAPIs() {
    if (gAPIsReady) return true;
#define RESOLVE_API(field, symbol) gAPI.field = reinterpret_cast<decltype(gAPI.field)>(ResolveSymbol(symbol))
    RESOLVE_API(domain_get, "il2cpp_domain_get");
    RESOLVE_API(domain_get_assemblies, "il2cpp_domain_get_assemblies");
    RESOLVE_API(assembly_get_image, "il2cpp_assembly_get_image");
    RESOLVE_API(image_get_name, "il2cpp_image_get_name");
    RESOLVE_API(class_from_name, "il2cpp_class_from_name");
    RESOLVE_API(class_get_method_from_name, "il2cpp_class_get_method_from_name");
    RESOLVE_API(class_get_methods, "il2cpp_class_get_methods");
    RESOLVE_API(class_get_parent, "il2cpp_class_get_parent");
    RESOLVE_API(method_get_name, "il2cpp_method_get_name");
    RESOLVE_API(method_get_param_count, "il2cpp_method_get_param_count");
    RESOLVE_API(method_get_param, "il2cpp_method_get_param");
    RESOLVE_API(method_get_return_type, "il2cpp_method_get_return_type");
    RESOLVE_API(method_get_flags, "il2cpp_method_get_flags");
    RESOLVE_API(type_get_name, "il2cpp_type_get_name");
    RESOLVE_API(il2cpp_free, "il2cpp_free");
    RESOLVE_API(class_get_field_from_name, "il2cpp_class_get_field_from_name");
    RESOLVE_API(field_get_value, "il2cpp_field_get_value");
    RESOLVE_API(field_set_value, "il2cpp_field_set_value");
    RESOLVE_API(field_static_get_value, "il2cpp_field_static_get_value");
    RESOLVE_API(field_get_type, "il2cpp_field_get_type");
    RESOLVE_API(class_from_type, "il2cpp_class_from_type");
    RESOLVE_API(object_new, "il2cpp_object_new");
    RESOLVE_API(object_get_class, "il2cpp_object_get_class");
    RESOLVE_API(runtime_invoke, "il2cpp_runtime_invoke");
    RESOLVE_API(object_unbox, "il2cpp_object_unbox");
    RESOLVE_API(class_get_type, "il2cpp_class_get_type");
    RESOLVE_API(type_get_object, "il2cpp_type_get_object");
    RESOLVE_API(string_chars, "il2cpp_string_chars");
    RESOLVE_API(string_length, "il2cpp_string_length");
    RESOLVE_API(thread_attach, "il2cpp_thread_attach");
    RESOLVE_API(gchandle_new, "il2cpp_gchandle_new");
    RESOLVE_API(gchandle_get_target, "il2cpp_gchandle_get_target");
    RESOLVE_API(gchandle_free, "il2cpp_gchandle_free");
#undef RESOLVE_API

    gAPIsReady = gAPI.domain_get && gAPI.domain_get_assemblies && gAPI.assembly_get_image &&
                 gAPI.image_get_name && gAPI.class_from_name && gAPI.class_get_method_from_name &&
                 gAPI.class_get_methods && gAPI.method_get_name && gAPI.method_get_param_count &&
                 gAPI.method_get_param && gAPI.method_get_return_type && gAPI.method_get_flags &&
                 gAPI.type_get_name && gAPI.il2cpp_free &&
                 gAPI.class_get_field_from_name && gAPI.field_get_value && gAPI.field_set_value && gAPI.object_get_class &&
                 gAPI.runtime_invoke && gAPI.object_unbox && gAPI.class_get_type &&
                 gAPI.type_get_object && gAPI.thread_attach;
    return gAPIsReady;
}

static bool ImageNameMatches(const char *actual, const char *wanted) {
    if (!actual || !wanted) return false;
    if (strcasecmp(actual, wanted) == 0) return true;
    char a[192] = {0};
    char w[192] = {0};
    snprintf(a, sizeof(a), "%s", actual);
    snprintf(w, sizeof(w), "%s", wanted);
    char *adot = strrchr(a, '.');
    char *wdot = strrchr(w, '.');
    if (adot && strcasecmp(adot, ".dll") == 0) *adot = '\0';
    if (wdot && strcasecmp(wdot, ".dll") == 0) *wdot = '\0';
    return strcasecmp(a, w) == 0;
}

static const Il2CppImage *FindImage(const char *name) {
    Il2CppDomain *domain = gAPI.domain_get();
    if (!domain) return nullptr;
    size_t count = 0;
    const Il2CppAssembly **assemblies = gAPI.domain_get_assemblies(domain, &count);
    if (!assemblies || count == 0) return nullptr;
    for (size_t i = 0; i < count; i++) {
        const Il2CppImage *img = gAPI.assembly_get_image(assemblies[i]);
        if (!img) continue;
        const char *imgName = gAPI.image_get_name(img);
        if (ImageNameMatches(imgName, name)) return img;
    }
    return nullptr;
}


static bool TypeNameMatches(const Il2CppType *type, const char *expected) {
    if (!type || !expected || !gAPI.type_get_name) return false;
    char *name = gAPI.type_get_name(type);
    if (!name) return false;
    bool match = strcmp(name, expected) == 0;
    gAPI.il2cpp_free(name);
    return match;
}

static const MethodInfo *FindMethodExact(Il2CppClass *klass, const char *name,
                                         uint32_t paramCount, const char *param0 = nullptr,
                                         int expectedStatic = -1, const char *returnType = nullptr) {
    if (!klass || !name || !gAPI.class_get_methods || !gAPI.method_get_name ||
        !gAPI.method_get_param_count || !gAPI.method_get_param ||
        !gAPI.method_get_return_type || !gAPI.method_get_flags) return nullptr;
    constexpr uint32_t kMethodAttributeStatic = 0x0010;
    void *iter = nullptr;
    while (const MethodInfo *method = gAPI.class_get_methods(klass, &iter)) {
        const char *methodName = gAPI.method_get_name(method);
        if (!methodName || strcmp(methodName, name) != 0) continue;
        if (gAPI.method_get_param_count(method) != paramCount) continue;
        if (paramCount > 0 && param0) {
            const Il2CppType *p0 = gAPI.method_get_param(method, 0);
            if (!TypeNameMatches(p0, param0)) continue;
        }
        if (expectedStatic >= 0) {
            uint32_t iflags = 0;
            uint32_t flags = gAPI.method_get_flags(method, &iflags);
            bool isStatic = (flags & kMethodAttributeStatic) != 0;
            if (isStatic != (expectedStatic != 0)) continue;
        }
        if (returnType && !TypeNameMatches(gAPI.method_get_return_type(method), returnType)) continue;
        return method;
    }
    return nullptr;
}

static const MethodInfo *FindMethodParamContains(Il2CppClass *klass, const char *name,
                                                     uint32_t paramCount, const char *needle,
                                                     int expectedStatic = -1, const char *returnType = nullptr) {
    if (!klass || !name || !gAPI.class_get_methods || !gAPI.method_get_name ||
        !gAPI.method_get_param_count || !gAPI.method_get_param || !gAPI.method_get_flags) return nullptr;
    constexpr uint32_t kMethodAttributeStatic = 0x0010;
    void *iter = nullptr;
    while (const MethodInfo *method = gAPI.class_get_methods(klass, &iter)) {
        const char *methodName = gAPI.method_get_name(method);
        if (!methodName || strcmp(methodName, name) != 0) continue;
        if (gAPI.method_get_param_count(method) != paramCount) continue;
        if (paramCount > 0 && needle) {
            const Il2CppType *p0 = gAPI.method_get_param(method, 0);
            char *pname = p0 && gAPI.type_get_name ? gAPI.type_get_name(p0) : nullptr;
            bool match = pname && strstr(pname, needle);
            if (pname) gAPI.il2cpp_free(pname);
            if (!match) continue;
        }
        if (expectedStatic >= 0) {
            uint32_t iflags = 0;
            uint32_t flags = gAPI.method_get_flags(method, &iflags);
            bool isStatic = (flags & kMethodAttributeStatic) != 0;
            if (isStatic != (expectedStatic != 0)) continue;
        }
        if (returnType && !TypeNameMatches(gAPI.method_get_return_type(method), returnType)) continue;
        return method;
    }
    return nullptr;
}

static bool BindProfile(Bindings &b,
                        const Il2CppImage *hotfix,
                        const Il2CppImage *core,
                        const char *uiClassName,
                        const char *groupClassName,
                        const char *arrowClassName) {
    memset(&b, 0, sizeof(Bindings));
    b.uiClass = gAPI.class_from_name(hotfix, "Modules.UI", uiClassName);
    b.groupClass = gAPI.class_from_name(hotfix, "Dance", groupClassName);
    b.arrowClass = gAPI.class_from_name(hotfix, "Dance", arrowClassName);
    b.rangeClass = gAPI.class_from_name(hotfix, "Dance.MusicTool", "NoteJudgeRange");
    b.unityObjectClass = gAPI.class_from_name(core, "UnityEngine", "Object");
    b.uiManagerClass = gAPI.class_from_name(hotfix, "Modules.UI", "UIManager");
    b.drumBeatClass = gAPI.class_from_name(hotfix, "Modules.UI", "UI_AuditionDrumBeat");
    if (!b.uiClass || !b.groupClass || !b.arrowClass || !b.rangeClass || !b.unityObjectClass || !b.uiManagerClass || !b.drumBeatClass) {
        return false;
    }

    b.findObjectOfType = FindMethodExact(b.unityObjectClass, "FindObjectOfType", 1, "System.Type", 1, "UnityEngine.Object");
    b.findFirstObjectByTypeInactive = FindMethodExact(b.unityObjectClass, "FindFirstObjectByType", 2, "System.Type", 1, "UnityEngine.Object");
    b.getUIWnd = FindMethodExact(b.uiManagerClass, "GetUIWnd", 1, "Modules.UI.UIFlag", 1, "Modules.UI.UIWndBase");
    b.isUIShowing = FindMethodExact(b.uiManagerClass, "IsUIShowing", 1, "Modules.UI.UIFlag", 1, "System.Boolean");
    b.isUICaching = FindMethodExact(b.uiManagerClass, "IsUICaching", 1, "Modules.UI.UIFlag", 1, "System.Boolean");
    b.objectImplicit = FindMethodExact(b.unityObjectClass, "op_Implicit", 1, "UnityEngine.Object", 1, "System.Boolean");
    b.onDrumDown = FindMethodExact(b.uiClass, "OnDrumDown", 1, "Dance.AuditionBeatType", 0, "System.Void");
    b.isAllHit = FindMethodExact(b.groupClass, "IsAllHit", 0, nullptr, 0, "System.Boolean");
    b.rangeIsInRange = FindMethodExact(b.rangeClass, "IsInRange", 1, "System.Single", 0, "System.Boolean");
    b.drumBeatOnPress = FindMethodExact(b.drumBeatClass, "OnPress", 1, "System.Boolean", 0, "System.Void");

    b.uiCurGroup = gAPI.class_get_field_from_name(b.uiClass, "curGroup");
    b.uiAudioTime = gAPI.class_get_field_from_name(b.uiClass, "audioTime");
    b.uiCenterAudioTime = gAPI.class_get_field_from_name(b.uiClass, "centerAudioTime");
    b.uiOpenClickBeatTime = gAPI.class_get_field_from_name(b.uiClass, "openClickBeatTime");
    b.uiMoveRate = gAPI.class_get_field_from_name(b.uiClass, "moveRate");
    b.uiDrumBeatArray = gAPI.class_get_field_from_name(b.uiClass, "arryDrumBeat");

    b.groupArrowsList = gAPI.class_get_field_from_name(b.groupClass, "arrowsList");
    b.groupCurArrowIndex = gAPI.class_get_field_from_name(b.groupClass, "curArrowIndex");
    b.groupGroupIndex = gAPI.class_get_field_from_name(b.groupClass, "groupIndex");
    b.groupIsShow = gAPI.class_get_field_from_name(b.groupClass, "isShow");
    b.groupIsHitBeat = gAPI.class_get_field_from_name(b.groupClass, "isHitBeat");
    b.groupRangeList = gAPI.class_get_field_from_name(b.groupClass, "rangeList");
    b.groupJudgeLevel = gAPI.class_get_field_from_name(b.groupClass, "judgeLevel");

    b.arrowDirection = gAPI.class_get_field_from_name(b.arrowClass, "arrowsDir");
    b.drumBeatBeatType = gAPI.class_get_field_from_name(b.drumBeatClass, "beatType");
    b.rangeStartTime = gAPI.class_get_field_from_name(b.rangeClass, "StartTime");
    b.rangeEndTime = gAPI.class_get_field_from_name(b.rangeClass, "EndTime");
    b.rangeRank = gAPI.class_get_field_from_name(b.rangeClass, "RangeRank");

    const bool methodsOK = b.getUIWnd && b.objectImplicit && b.onDrumDown && b.isAllHit && b.rangeIsInRange && b.drumBeatOnPress;
    const bool fieldsOK = b.uiCurGroup && b.uiAudioTime && b.uiCenterAudioTime && b.uiOpenClickBeatTime && b.uiMoveRate && b.uiDrumBeatArray && b.groupArrowsList &&
                          b.groupCurArrowIndex && b.groupGroupIndex && b.groupIsShow && b.groupIsHitBeat &&
                          b.groupRangeList && b.groupJudgeLevel && b.arrowDirection && b.drumBeatBeatType && b.rangeStartTime &&
                          b.rangeEndTime && b.rangeRank;
    return methodsOK && fieldsOK;
}

static bool BindGame() {
    if (gBindingsReady) return true;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gLastResolveAttempt < 0.8) return false;
    gLastResolveAttempt = now;

    if (!ResolveAPIs()) {
        Emit(@"RESOLVE", @"WAIT_PREREQ", @"IL2CPP_EXPORTS_NOT_READY");
        return false;
    }

    Il2CppDomain *domain = gAPI.domain_get();
    if (!domain) {
        Emit(@"RESOLVE", @"WAIT_PREREQ", @"DOMAIN_NOT_READY");
        return false;
    }
    gAPI.thread_attach(domain);

    const Il2CppImage *hotfix = FindImage("HotFix.dll");
    const Il2CppImage *core = FindImage("UnityEngine.CoreModule.dll");
    const Il2CppImage *mscorlib = FindImage("mscorlib.dll");
    const Il2CppImage *ngui = FindImage("NGUI.dll");
    if (!hotfix || !core || !mscorlib) {
        NSString *missing = !hotfix ? @"HOTFIX_IMAGE_MISSING" : (!core ? @"UNITY_CORE_IMAGE_MISSING" : @"MSCORLIB_IMAGE_MISSING");
        Emit(@"RESOLVE", @"WAIT_PREREQ", missing);
        return false;
    }

    // System.Array is used to walk UI_DanceAudition/UI_DanceBurstAu.arryDrumBeat
    // without relying on raw IL2CPP array layout.
    gSystemArrayClass = gAPI.class_from_name(mscorlib, "System", "Array");
    gArrayGetLength = gSystemArrayClass ? FindMethodExact(gSystemArrayClass, "get_Length", 0, nullptr, 0, "System.Int32") : nullptr;
    gArrayGetValue = gSystemArrayClass ? FindMethodExact(gSystemArrayClass, "GetValue", 1, "System.Int32", 0, "System.Object") : nullptr;

    // DynamicOneBeatKeys.startHitTime/endHitTime are in UnityEngine.Time.time domain
    // in the current 23.4 runtime (confirmed by V10.6 trace). Bind the engine clock
    // directly instead of trying to reconstruct it from song-relative sourceTime.
    Il2CppClass *unityTimeClass = gAPI.class_from_name(core, "UnityEngine", "Time");
    gUnityTimeGetTime = unityTimeClass ? FindMethodExact(unityTimeClass, "get_time", 0, nullptr, 1, "System.Single") : nullptr;

    // Optional read-only mode diagnostic from Common.AppInterface.DanceModule.
    // Failure to resolve this path never blocks Auto Perfect.
    Il2CppClass *appInterfaceClass = gAPI.class_from_name(hotfix, "Common", "AppInterface");
    Il2CppClass *danceModuleClass = gAPI.class_from_name(hotfix, "Dance", "DanceModule");
    gAppDanceModuleField = appInterfaceClass ? gAPI.class_get_field_from_name(appInterfaceClass, "DanceModule") : nullptr;
    gDanceGetMode = danceModuleClass ? FindMethodExact(danceModuleClass, "GetMode", 0, nullptr, 0, "Dance.eDanceGameMode") : nullptr;
    gDanceGetLogic = danceModuleClass ? FindMethodExact(danceModuleClass, "get_DanceLogic", 0, nullptr, 0, "Dance.BaseDance") : nullptr;

    // V10.15 skin changer bindings. All are current-build metadata discoveries.
    gSkinB.appInterfaceClass = appInterfaceClass;
    gSkinB.roomModuleClass = gAPI.class_from_name(hotfix, "Room", "RoomModule");
    gSkinB.roomBaseClass = gAPI.class_from_name(hotfix, "Room", "RoomBase");
    gSkinB.roomPlayerClass = gAPI.class_from_name(hotfix, "Room", "RoomPlayer");
    gSkinB.baseDanceClass = gAPI.class_from_name(hotfix, "Dance", "BaseDance");
    gSkinB.dancerControllerClass = gAPI.class_from_name(hotfix, "Dance", "DancerController");
    gSkinB.guiModuleClass = gAPI.class_from_name(hotfix, "Modules.UI", "GUIModule");
    gSkinB.uiPlayerManagerClass = gAPI.class_from_name(hotfix, "NewPlayer", "UIPlayerManager");
    gSkinB.uiPlayerClass = gAPI.class_from_name(hotfix, "NewPlayer", "UIPlayer");
    gSkinB.playerClass = gAPI.class_from_name(hotfix, "NewPlayer", "Player");
    Il2CppClass *skinUnityObjectClass = gAPI.class_from_name(core, "UnityEngine", "Object");
    gSkinB.configItemClass = gAPI.class_from_name(hotfix, "", "Config_t_item");
    gSkinB.itemClass = gAPI.class_from_name(hotfix, "", "Item_t_item");
    gSkinB.equipClass = gAPI.class_from_name(hotfix, "", "Item_t_equip");
    gSkinB.appRoomModule = gSkinB.appInterfaceClass ? gAPI.class_get_field_from_name(gSkinB.appInterfaceClass, "RoomModule") : nullptr;
    gSkinB.appGUIModule = gSkinB.appInterfaceClass ? gAPI.class_get_field_from_name(gSkinB.appInterfaceClass, "GUIModule") : nullptr;
    gSkinB.roomPlayerPlayer = gSkinB.roomPlayerClass ? gAPI.class_get_field_from_name(gSkinB.roomPlayerClass, "player") : nullptr;
    gSkinB.dancerControllerPlayer = gSkinB.dancerControllerClass ? gAPI.class_get_field_from_name(gSkinB.dancerControllerClass, "player") : nullptr;
    gSkinB.uiPlayerManagerPlayersList = gSkinB.uiPlayerManagerClass ? gAPI.class_get_field_from_name(gSkinB.uiPlayerManagerClass, "playersList") : nullptr;
    gSkinB.uiPlayerModel = gSkinB.uiPlayerClass ? gAPI.class_get_field_from_name(gSkinB.uiPlayerClass, "model") : nullptr;
    gSkinB.playerGameObject = gSkinB.playerClass ? gAPI.class_get_field_from_name(gSkinB.playerClass, "<gameObject>k__BackingField") : nullptr;
    gSkinB.playerNeedPutOnItems = gSkinB.playerClass ? gAPI.class_get_field_from_name(gSkinB.playerClass, "mNeedPutOnItems") : nullptr;
    gSkinB.configItemArray = gSkinB.configItemClass ? gAPI.class_get_field_from_name(gSkinB.configItemClass, "Array") : nullptr;
    gSkinB.itemID = gSkinB.itemClass ? gAPI.class_get_field_from_name(gSkinB.itemClass, "f_ItemID") : nullptr;
    gSkinB.itemType1 = gSkinB.itemClass ? gAPI.class_get_field_from_name(gSkinB.itemClass, "f_Type1") : nullptr;
    gSkinB.itemType2 = gSkinB.itemClass ? gAPI.class_get_field_from_name(gSkinB.itemClass, "f_Type2") : nullptr;
    gSkinB.itemSexNeed = gSkinB.itemClass ? gAPI.class_get_field_from_name(gSkinB.itemClass, "f_SexNeed") : nullptr;
    gSkinB.equipItemID = gSkinB.equipClass ? gAPI.class_get_field_from_name(gSkinB.equipClass, "f_ItemID") : nullptr;
    gSkinB.roomGetRoomPlayer = gSkinB.roomModuleClass ? FindMethodExact(gSkinB.roomModuleClass, "get_RoomPlayer", 0, nullptr, 0, "Room.RoomPlayer") : nullptr;
    gSkinB.roomGetRoom = gSkinB.roomModuleClass ? FindMethodExact(gSkinB.roomModuleClass, "GetRoom", 0, nullptr, 0, "Room.RoomBase") : nullptr;
    gSkinB.roomBaseGetLocalPlayer = gSkinB.roomBaseClass ? FindMethodExact(gSkinB.roomBaseClass, "get_LocalPlayer", 0, nullptr, 0, "Room.RoomPlayer") : nullptr;
    gSkinB.baseDanceGetPlayer = gSkinB.baseDanceClass ? FindMethodExact(gSkinB.baseDanceClass, "get_Player", 0, nullptr, 0, "Dance.DancerController") : nullptr;
    gSkinB.guiGetPlayerManager = gSkinB.guiModuleClass ? FindMethodExact(gSkinB.guiModuleClass, "get_PlayerManager", 0, nullptr, 0, "NewPlayer.UIPlayerManager") : nullptr;
    gSkinB.playerGetSex = gSkinB.playerClass ? FindMethodExact(gSkinB.playerClass, "get_PlayerSex", 0, nullptr, 0, "ClientData.Sex_Type") : nullptr;
    gSkinB.playerGetRoleId = gSkinB.playerClass ? FindMethodExact(gSkinB.playerClass, "get_RoleId", 0, nullptr, 0, "System.UInt32") : nullptr;
    gSkinB.playerGetLoadComplete = gSkinB.playerClass ? FindMethodExact(gSkinB.playerClass, "get_IsLoadComplete", 0, nullptr, 0, "System.Boolean") : nullptr;
    gSkinB.playerIsPuton = gSkinB.playerClass ? FindMethodExact(gSkinB.playerClass, "IsPuton", 2, "ClientData.ItemCloth_3rdType", 0, "System.Boolean") : nullptr;
    gSkinB.unityObjectImplicit = skinUnityObjectClass ? FindMethodExact(skinUnityObjectClass, "op_Implicit", 1, "UnityEngine.Object", 1, "System.Boolean") : nullptr;
    gSkinB.playerLoadAndPutOn = gSkinB.playerClass ? FindMethodParamContains(gSkinB.playerClass, "LoadAndPutOnCostume", 1, "System.UInt32", 0, "System.Void") : nullptr;
    gSkinB.playerChangeAll = gSkinB.playerClass ? FindMethodParamContains(gSkinB.playerClass, "ChangeAllCostume", 1, "System.UInt32", 0, "System.Void") : nullptr;
    gSkinB.playerGetOriginEquip = gSkinB.playerClass ? FindMethodExact(gSkinB.playerClass, "GetOriginCostumeTEquip", 1, "ClientData.ItemCloth_3rdType", 0, "Item_t_equip") : nullptr;
    gSkinB.configGetSingleton = gSkinB.configItemClass ? FindMethodExact(gSkinB.configItemClass, "get_Singleton", 0, nullptr, 1, "Config_t_item") : nullptr;
    gSkinB.configGetItem = gSkinB.configItemClass ? FindMethodExact(gSkinB.configItemClass, "GetConfig", 1, "System.UInt32", 0, "Item_t_item") : nullptr;
    gSkinB.itemGetName = gSkinB.itemClass ? FindMethodExact(gSkinB.itemClass, "get_f_Name", 0, nullptr, 0, "System.String") : nullptr;
    gSkinBindingsReady = gSkinB.appRoomModule && gSkinB.roomPlayerPlayer && gSkinB.playerNeedPutOnItems &&
                         gSkinB.configItemArray && gSkinB.itemID && gSkinB.itemType1 && gSkinB.itemType2 && gSkinB.itemSexNeed &&
                         gSkinB.roomGetRoomPlayer && gSkinB.playerGetSex && gSkinB.playerLoadAndPutOn &&
                         gSkinB.playerChangeAll && gSkinB.playerGetOriginEquip && gSkinB.configGetSingleton && gSkinB.configGetItem && gSkinB.itemGetName &&
                         gAPI.field_static_get_value && gAPI.field_get_type && gAPI.class_from_type && gAPI.object_new &&
                         gAPI.string_chars && gAPI.string_length;

    // V10.20 VIP visual bindings. Still UI-only for writes: the ClientPlayer/RoleInfo
    // path below is read-only and exists only to identify the self role + original VIP.
    gVIPB.unityObjectClass = skinUnityObjectClass;
    gVIPB.vipIconClass = gAPI.class_from_name(hotfix, "Modules.UI", "UI_VIPIcon");
    gVIPB.billboardClass = gAPI.class_from_name(hotfix, "Modules.UI", "UI_Billboard_CharacterTop");
    gVIPB.playerHeadClass = gAPI.class_from_name(hotfix, "", "UI_PlayerHead");
    gVIPB.uiLabelClass = ngui ? gAPI.class_from_name(ngui, "", "UILabel") : nullptr;
    gVIPB.islandPlayerInfoClass = gAPI.class_from_name(hotfix, "Modules.UI", "UI_Cell_IslandPlayerInfo");
    gVIPB.clientVIPClass = gAPI.class_from_name(hotfix, "ClientData", "ClientVIP");
    gVIPB.monoBehaviourClass = gAPI.class_from_name(core, "UnityEngine", "MonoBehaviour");
    gVIPB.clientPlayerClass = gAPI.class_from_name(hotfix, "ClientData", "ClientPlayer");
    gVIPB.roleInfoClass = gAPI.class_from_name(hotfix, "ClientData", "RoleInfoData");
    gVIPB.commonPlayerInfoClass = gAPI.class_from_name(hotfix, "ClientData", "CommonPlayerInfo");
    gVIPB.waitRoomCellClass = gAPI.class_from_name(hotfix, "Modules.UI", "Cell_PlayerListItem");
    gVIPB.roomPlayerInfoCellClass = gAPI.class_from_name(hotfix, "Modules.UI", "UI_Cell_RoomPlayerInfo");
    gVIPB.dgPlayerInfoCellClass = gAPI.class_from_name(hotfix, "Modules.UI", "UI_Cell_DGPlayerInfo");
    gVIPB.rankPlayerCellClass = gAPI.class_from_name(hotfix, "", "UI_Cell_PlayerRankItem");
    gVIPB.roomPlayerDataClass = gAPI.class_from_name(hotfix, "ClientData", "RoomPlayerData");
    gVIPB.characterTopParamClass = gAPI.class_from_name(hotfix, "Modules.UI", "CharacterTopParam");
    gVIPB.configTitleClass = gAPI.class_from_name(hotfix, "", "Config_t_title");
    gVIPB.itemTitleClass = gAPI.class_from_name(hotfix, "", "Item_t_title");
    gVIPB.configPersonalNameClass = gAPI.class_from_name(hotfix, "", "Config_t_personal_name");
    gVIPB.itemPersonalNameClass = gAPI.class_from_name(hotfix, "", "Item_t_personal_name");
    gVIPB.configMarryRingClass = gAPI.class_from_name(hotfix, "", "Config_t_marry_ring");
    gVIPB.itemMarryRingClass = gAPI.class_from_name(hotfix, "", "Item_t_marry_ring");

    gVIPB.findObjectsOfType = gVIPB.unityObjectClass ? FindMethodExact(gVIPB.unityObjectClass, "FindObjectsOfType", 2, "System.Type", 1, "UnityEngine.Object[]") : nullptr;
    gVIPB.vipSetLevel = gVIPB.vipIconClass ? FindMethodExact(gVIPB.vipIconClass, "SetVipLevel", 1, "System.Int32", 0, "System.Void") : nullptr;
    gVIPB.clientVIPGetMaxLevel = gVIPB.clientVIPClass ? FindMethodExact(gVIPB.clientVIPClass, "get_MaxVIPLevel", 0, nullptr, 1, "System.UInt32") : nullptr;
    gVIPB.billboardShowVip = gVIPB.billboardClass ? FindMethodExact(gVIPB.billboardClass, "ShowVip", 2, "System.Int32", 0, "System.Collections.IEnumerator") : nullptr;
    gVIPB.billboardStartNameEffect = gVIPB.billboardClass ? FindMethodExact(gVIPB.billboardClass, "StartNameEffect", 1, "System.UInt32", 0, "System.Void") : nullptr;
    gVIPB.billboardShowRing = gVIPB.billboardClass ? FindMethodExact(gVIPB.billboardClass, "ShowRing", 2, "System.Boolean", 0, "System.Void") : nullptr;
    gVIPB.billboardShowTitle = gVIPB.billboardClass ? FindMethodExact(gVIPB.billboardClass, "ShowTitle", 1, "Modules.UI.CharacterTopParam", 0, "System.Void") : nullptr;
    gVIPB.billboardSetEffectTitleState = gVIPB.billboardClass ? FindMethodExact(gVIPB.billboardClass, "SetEffectTitleState", 1, "System.Boolean", 0, "System.Void") : nullptr;
    gVIPB.billboardClearEffectTitle = gVIPB.billboardClass ? FindMethodExact(gVIPB.billboardClass, "ClearEffectTitle", 0, nullptr, 0, "System.Void") : nullptr;
    gVIPB.configTitleGetSingleton = gVIPB.configTitleClass ? FindMethodExact(gVIPB.configTitleClass, "get_Singleton", 0, nullptr, 1, "Config_t_title") : nullptr;
    gVIPB.titleGetName = gVIPB.itemTitleClass ? FindMethodExact(gVIPB.itemTitleClass, "get_f_TitleName", 0, nullptr, 0, "System.String") : nullptr;
    gVIPB.configPersonalNameGetSingleton = gVIPB.configPersonalNameClass ? FindMethodExact(gVIPB.configPersonalNameClass, "get_Singleton", 0, nullptr, 1, "Config_t_personal_name") : nullptr;
    gVIPB.configMarryRingGetSingleton = gVIPB.configMarryRingClass ? FindMethodExact(gVIPB.configMarryRingClass, "get_Singleton", 0, nullptr, 1, "Config_t_marry_ring") : nullptr;
    gVIPB.marryRingGetName = gVIPB.itemMarryRingClass ? FindMethodExact(gVIPB.itemMarryRingClass, "get_f_RingName", 0, nullptr, 0, "System.String") : nullptr;
    gVIPB.startCoroutine = gVIPB.monoBehaviourClass ? FindMethodExact(gVIPB.monoBehaviourClass, "StartCoroutine", 1, "System.Collections.IEnumerator", 0, "UnityEngine.Coroutine") : nullptr;
    Il2CppClass *clientPlayerSingletonBase = (gVIPB.clientPlayerClass && gAPI.class_get_parent) ? gAPI.class_get_parent(gVIPB.clientPlayerClass) : nullptr;
    gVIPB.clientPlayerGetSingleton = clientPlayerSingletonBase ? FindMethodExact(clientPlayerSingletonBase, "get_Singleton", 0, nullptr, 1, nullptr) : nullptr;
    gVIPB.clientPlayerGetRoleInfo = gVIPB.clientPlayerClass ? FindMethodExact(gVIPB.clientPlayerClass, "get_RoleInfo", 0, nullptr, 0, "ClientData.RoleInfoData") : nullptr;
    gVIPB.roleInfoGetVipLevel = gVIPB.roleInfoClass ? FindMethodExact(gVIPB.roleInfoClass, "get_VipLevel", 0, nullptr, 0, "System.UInt16") : nullptr;
    gVIPB.roleInfoGetRoleName = gVIPB.roleInfoClass ? FindMethodExact(gVIPB.roleInfoClass, "get_RoleName", 0, nullptr, 0, "System.String") : nullptr;

    gVIPB.vipCurrentLevel = gVIPB.vipIconClass ? gAPI.class_get_field_from_name(gVIPB.vipIconClass, "m_vipLevel") : nullptr;
    gVIPB.billboardRoleId = gVIPB.billboardClass ? gAPI.class_get_field_from_name(gVIPB.billboardClass, "role_ID") : nullptr;
    gVIPB.billboardVipIcon = gVIPB.billboardClass ? gAPI.class_get_field_from_name(gVIPB.billboardClass, "m_vipIcon") : nullptr;
    gVIPB.billboardNameColorChange = gVIPB.billboardClass ? gAPI.class_get_field_from_name(gVIPB.billboardClass, "nameColorChange") : nullptr;
    gVIPB.playerHeadVipIcon = gVIPB.playerHeadClass ? gAPI.class_get_field_from_name(gVIPB.playerHeadClass, "m_vipIcon") : nullptr;
    gVIPB.playerHeadNameLabel = gVIPB.playerHeadClass ? gAPI.class_get_field_from_name(gVIPB.playerHeadClass, "m_labelName") : nullptr;
    gVIPB.uiLabelText = gVIPB.uiLabelClass ? gAPI.class_get_field_from_name(gVIPB.uiLabelClass, "mText") : nullptr;
    gVIPB.islandPlayerData = gVIPB.islandPlayerInfoClass ? gAPI.class_get_field_from_name(gVIPB.islandPlayerInfoClass, "playerData") : nullptr;
    gVIPB.islandPlayerVipIcon = gVIPB.islandPlayerInfoClass ? gAPI.class_get_field_from_name(gVIPB.islandPlayerInfoClass, "m_vipIcon") : nullptr;
    gVIPB.commonRoleId = gVIPB.commonPlayerInfoClass ? gAPI.class_get_field_from_name(gVIPB.commonPlayerInfoClass, "m_RoleID") : nullptr;

    gVIPB.waitRoomCellData = gVIPB.waitRoomCellClass ? gAPI.class_get_field_from_name(gVIPB.waitRoomCellClass, "m_CurRoomPlayerData") : nullptr;
    gVIPB.waitRoomCellVipIcon = gVIPB.waitRoomCellClass ? gAPI.class_get_field_from_name(gVIPB.waitRoomCellClass, "m_vipIcon") : nullptr;
    gVIPB.roomPlayerDataRoleId = gVIPB.roomPlayerDataClass ? gAPI.class_get_field_from_name(gVIPB.roomPlayerDataClass, "roleId") : nullptr;
    gVIPB.roomPlayerInfoRoleId = gVIPB.roomPlayerInfoCellClass ? gAPI.class_get_field_from_name(gVIPB.roomPlayerInfoCellClass, "roleID") : nullptr;
    gVIPB.roomPlayerInfoVipIcon = gVIPB.roomPlayerInfoCellClass ? gAPI.class_get_field_from_name(gVIPB.roomPlayerInfoCellClass, "m_vipIcon") : nullptr;
    gVIPB.dgPlayerInfoRoleId = gVIPB.dgPlayerInfoCellClass ? gAPI.class_get_field_from_name(gVIPB.dgPlayerInfoCellClass, "roleID") : nullptr;
    gVIPB.dgPlayerInfoVipIcon = gVIPB.dgPlayerInfoCellClass ? gAPI.class_get_field_from_name(gVIPB.dgPlayerInfoCellClass, "m_vipIcon") : nullptr;
    gVIPB.rankPlayerRoleId = gVIPB.rankPlayerCellClass ? gAPI.class_get_field_from_name(gVIPB.rankPlayerCellClass, "m_RoleID") : nullptr;
    gVIPB.rankPlayerVipIcon = gVIPB.rankPlayerCellClass ? gAPI.class_get_field_from_name(gVIPB.rankPlayerCellClass, "m_vipIcon") : nullptr;
    gVIPB.configTitleArray = gVIPB.configTitleClass ? gAPI.class_get_field_from_name(gVIPB.configTitleClass, "Array") : nullptr;
    gVIPB.titleID = gVIPB.itemTitleClass ? gAPI.class_get_field_from_name(gVIPB.itemTitleClass, "f_TitleID") : nullptr;
    gVIPB.titleStaticEffect = gVIPB.itemTitleClass ? gAPI.class_get_field_from_name(gVIPB.itemTitleClass, "f_StaticPicOfSpecialEffects") : nullptr;
    gVIPB.titleDynamicEffect = gVIPB.itemTitleClass ? gAPI.class_get_field_from_name(gVIPB.itemTitleClass, "f_SpecialEffects") : nullptr;
    gVIPB.configPersonalNameArray = gVIPB.configPersonalNameClass ? gAPI.class_get_field_from_name(gVIPB.configPersonalNameClass, "Array") : nullptr;
    gVIPB.personalNameItemID = gVIPB.itemPersonalNameClass ? gAPI.class_get_field_from_name(gVIPB.itemPersonalNameClass, "f_ItemID") : nullptr;
    gVIPB.personalNameNameID = gVIPB.itemPersonalNameClass ? gAPI.class_get_field_from_name(gVIPB.itemPersonalNameClass, "f_NameID") : nullptr;
    gVIPB.configMarryRingArray = gVIPB.configMarryRingClass ? gAPI.class_get_field_from_name(gVIPB.configMarryRingClass, "Array") : nullptr;
    gVIPB.marryRingIndexID = gVIPB.itemMarryRingClass ? gAPI.class_get_field_from_name(gVIPB.itemMarryRingClass, "f_IndexID") : nullptr;
    gVIPB.paramTitleId = gVIPB.characterTopParamClass ? gAPI.class_get_field_from_name(gVIPB.characterTopParamClass, "titleId") : nullptr;
    gVIPB.roomPlayerCharacterTopUI = gSkinB.roomPlayerClass ? gAPI.class_get_field_from_name(gSkinB.roomPlayerClass, "characterTopUI") : nullptr;
    gVIPB.roomPlayerTopUI = gSkinB.roomPlayerClass ? gAPI.class_get_field_from_name(gSkinB.roomPlayerClass, "topUI") : nullptr;
    gVIPB.dancerPlayerTopUI = gSkinB.dancerControllerClass ? gAPI.class_get_field_from_name(gSkinB.dancerControllerClass, "playerTopUI") : nullptr;

    gVIPBindingsReady = gVIPB.vipIconClass && gVIPB.billboardClass && gVIPB.playerHeadClass &&
                        gVIPB.findObjectsOfType && gVIPB.vipSetLevel && gVIPB.vipCurrentLevel &&
                        gVIPB.billboardRoleId && gVIPB.billboardVipIcon && gVIPB.playerHeadVipIcon &&
                        gAPI.class_get_type && gAPI.type_get_object;

    // Mode 14 (StarlightTheatreBubble) has its own native autoplay path.
    // It does not use UI_DanceAudition/flag 71. The game's BubbleNoteController already
    // owns isAutoPlay and dispatches each concrete note's AutoPlay() implementation.
    gStarlightBubbleDanceClass = gAPI.class_from_name(hotfix, "Dance", "StarlightTheatreBubbleDance");
    gBubbleNoteControllerClass = gAPI.class_from_name(hotfix, "Dance.MusicTool", "BubbleNoteController");
    gStarlightBubbleNoteCtrlField = gStarlightBubbleDanceClass ? gAPI.class_get_field_from_name(gStarlightBubbleDanceClass, "m_noteCtrl") : nullptr;
    gBubbleIsAutoPlayField = gBubbleNoteControllerClass ? gAPI.class_get_field_from_name(gBubbleNoteControllerClass, "isAutoPlay") : nullptr;
    gBubbleComboNowField = gBubbleNoteControllerClass ? gAPI.class_get_field_from_name(gBubbleNoteControllerClass, "combo_now") : nullptr;
    gBubblePerfectCountField = gBubbleNoteControllerClass ? gAPI.class_get_field_from_name(gBubbleNoteControllerClass, "clickPerfectCount") : nullptr;
    gBubbleIsEndField = gBubbleNoteControllerClass ? gAPI.class_get_field_from_name(gBubbleNoteControllerClass, "IsEnd") : nullptr;
    const bool nativeBubble14OK = gAppDanceModuleField && gDanceGetMode && gDanceGetLogic &&
                                  gStarlightBubbleDanceClass && gBubbleNoteControllerClass &&
                                  gStarlightBubbleNoteCtrlField && gBubbleIsAutoPlayField;


    // Full-mode family bindings (all optional individually; router reports unsupported
    // only for the exact family whose metadata is absent).
    gF.bubbleCtrlClass = gAPI.class_from_name(hotfix, "Dance.MusicTool", "BubbleNoteController");
    gF.bubbleAuto = gF.bubbleCtrlClass ? gAPI.class_get_field_from_name(gF.bubbleCtrlClass, "isAutoPlay") : nullptr;
    gF.bubbleCombo = gF.bubbleCtrlClass ? gAPI.class_get_field_from_name(gF.bubbleCtrlClass, "combo_now") : nullptr;
    gF.bubblePerfect = gF.bubbleCtrlClass ? gAPI.class_get_field_from_name(gF.bubbleCtrlClass, "clickPerfectCount") : nullptr;
    gF.bubbleEnd = gF.bubbleCtrlClass ? gAPI.class_get_field_from_name(gF.bubbleCtrlClass, "IsEnd") : nullptr;

    gF.vosCtrlClass = gAPI.class_from_name(hotfix, "Dance.MusicTool", "VOSNoteController");
    gF.vosAuto = gF.vosCtrlClass ? gAPI.class_get_field_from_name(gF.vosCtrlClass, "isAutoPlay") : nullptr;
    gF.vosCombo = gF.vosCtrlClass ? gAPI.class_get_field_from_name(gF.vosCtrlClass, "combo_now") : nullptr;
    gF.vosPerfect = gF.vosCtrlClass ? gAPI.class_get_field_from_name(gF.vosCtrlClass, "clickPerfectCount") : nullptr;
    gF.vosEnd = gF.vosCtrlClass ? gAPI.class_get_field_from_name(gF.vosCtrlClass, "IsEnd") : nullptr;

    gF.danceBallUIClass = gAPI.class_from_name(hotfix, "Modules.UI", "UI_DanceBall_DanceWnd");
    gF.danceBallCtrlClass = gAPI.class_from_name(hotfix, "Dance.MusicTool", "DanceBallNoteController");
    gF.danceBallUICtrl = gF.danceBallUIClass ? gAPI.class_get_field_from_name(gF.danceBallUIClass, "danceBallCtrl") : nullptr;
    gF.danceBallAuto = gF.danceBallCtrlClass ? gAPI.class_get_field_from_name(gF.danceBallCtrlClass, "isAutoPlay") : nullptr;
    gF.danceBallCombo = gF.danceBallCtrlClass ? gAPI.class_get_field_from_name(gF.danceBallCtrlClass, "combo_now") : nullptr;
    gF.danceBallPerfect = gF.danceBallCtrlClass ? gAPI.class_get_field_from_name(gF.danceBallCtrlClass, "clickPerfectCount") : nullptr;
    gF.danceBallEnd = gF.danceBallCtrlClass ? gAPI.class_get_field_from_name(gF.danceBallCtrlClass, "IsEnd") : nullptr;

    gF.dynamicUIClass = gAPI.class_from_name(hotfix, "Modules.UI", "UI_DanceDynamic");
    gF.dynamicCtrlClass = gAPI.class_from_name(hotfix, "Dance", "DynamicArrowsController");
    gF.dynamicGroupClass = gAPI.class_from_name(hotfix, "Dance", "DynamicGroup");
    gF.dynamicBeatKeysClass = gAPI.class_from_name(hotfix, "Dance", "DynamicOneBeatKeys");
    gF.dynamicArrowClass = gAPI.class_from_name(hotfix, "Dance", "DynamicArrows");
    gF.dynamicOnDrumDown = gF.dynamicUIClass ? FindMethodExact(gF.dynamicUIClass, "OnDrumDown", 1, "Dance.eDynamicArrowDir", 0, "System.Void") : nullptr;
    gF.dynamicCtrlGroup = gF.dynamicCtrlClass ? gAPI.class_get_field_from_name(gF.dynamicCtrlClass, "curGroup") : nullptr;
    gF.dynamicCtrlSourceTime = gF.dynamicCtrlClass ? gAPI.class_get_field_from_name(gF.dynamicCtrlClass, "sourceTime") : nullptr;
    gF.dynamicCtrlMusicBeginTime = gF.dynamicCtrlClass ? gAPI.class_get_field_from_name(gF.dynamicCtrlClass, "musicBeginTime") : nullptr;
    gF.dynamicCtrlOffsetTime = gF.dynamicCtrlClass ? gAPI.class_get_field_from_name(gF.dynamicCtrlClass, "offsetTime") : nullptr;
    gF.dynamicUICurGroup = gF.dynamicUIClass ? gAPI.class_get_field_from_name(gF.dynamicUIClass, "curGroup") : nullptr;
    gF.dynamicUIIsCanJudgeHit = gF.dynamicUIClass ? gAPI.class_get_field_from_name(gF.dynamicUIClass, "isCanJudgeHit") : nullptr;
    gF.dynamicUIIsInCrazy = gF.dynamicUIClass ? gAPI.class_get_field_from_name(gF.dynamicUIClass, "isInCrazy") : nullptr;
    gF.dynamicGroupBeatKeys = gF.dynamicGroupClass ? gAPI.class_get_field_from_name(gF.dynamicGroupClass, "beatKeys") : nullptr;
    gF.dynamicGroupCurKeysIndex = gF.dynamicGroupClass ? gAPI.class_get_field_from_name(gF.dynamicGroupClass, "curKeysIndex") : nullptr;
    gF.dynamicGroupIndex = gF.dynamicGroupClass ? gAPI.class_get_field_from_name(gF.dynamicGroupClass, "groupIndex") : nullptr;
    gF.dynamicGroupIsShow = gF.dynamicGroupClass ? gAPI.class_get_field_from_name(gF.dynamicGroupClass, "isShow") : nullptr;
    gF.dynamicBeatArrows = gF.dynamicBeatKeysClass ? gAPI.class_get_field_from_name(gF.dynamicBeatKeysClass, "arrows") : nullptr;
    gF.dynamicBeatRanges = gF.dynamicBeatKeysClass ? gAPI.class_get_field_from_name(gF.dynamicBeatKeysClass, "rangeList") : nullptr;
    gF.dynamicBeatCurArrow = gF.dynamicBeatKeysClass ? gAPI.class_get_field_from_name(gF.dynamicBeatKeysClass, "curArrowsIndex") : nullptr;
    gF.dynamicBeatStartHitTime = gF.dynamicBeatKeysClass ? gAPI.class_get_field_from_name(gF.dynamicBeatKeysClass, "startHitTime") : nullptr;
    gF.dynamicBeatEndHitTime = gF.dynamicBeatKeysClass ? gAPI.class_get_field_from_name(gF.dynamicBeatKeysClass, "endHitTime") : nullptr;
    gF.dynamicBeatIsInHitTime = gF.dynamicBeatKeysClass ? FindMethodExact(gF.dynamicBeatKeysClass, "IsInHitTime", 1, "System.Single", 0, "System.Boolean") : nullptr;
    gF.dynamicArrowDir = gF.dynamicArrowClass ? gAPI.class_get_field_from_name(gF.dynamicArrowClass, "ArrowDir") : nullptr;
    gF.dynamicArrowHit = gF.dynamicArrowClass ? gAPI.class_get_field_from_name(gF.dynamicArrowClass, "IsHit") : nullptr;

    gF.trackUIClass = gAPI.class_from_name(hotfix, "Modules.UI", "UI_DanceTrack");
    gF.trackGuideUIClass = gAPI.class_from_name(hotfix, "Modules.UI", "UI_DanceTrackGuide");
    gF.trackCtrlClass = gAPI.class_from_name(hotfix, "Dance.MusicTool", "TrackNoteController");
    gF.trackNoteClass = gAPI.class_from_name(hotfix, "Dance.MusicTool", "TrackNote");
    gF.trackPoolsClass = gAPI.class_from_name(hotfix, "", "TrackUIPools");
    gF.trackUINoteClass = gAPI.class_from_name(hotfix, "Modules.UI", "UI_TrackNoteBase");
    gF.trackOnPress = gF.trackUIClass ? FindMethodExact(gF.trackUIClass, "OnPressBtn", 3, "Dance.MusicTool.eTrackDirection", 0, "System.Void") : nullptr;
    gF.trackGuideOnPress = gF.trackGuideUIClass ? FindMethodExact(gF.trackGuideUIClass, "OnPressBtn", 3, "Dance.MusicTool.eTrackDirection", 0, "System.Void") : nullptr;
    // V10.12: use the public/outer button handlers as the primary Track input path.
    // V10.11 called private OnPressBtn(dir,press,isBoth) directly, bypassing the
    // wrapper-maintained isPress/isClickLeft/isClickRight/debounce state.
    gF.trackPressLeft = gF.trackUIClass ? FindMethodExact(gF.trackUIClass, "OnPressBtnLeft", 2, "UnityEngine.GameObject", 0, "System.Void") : nullptr;
    gF.trackPressRight = gF.trackUIClass ? FindMethodExact(gF.trackUIClass, "OnPressBtnRight", 2, "UnityEngine.GameObject", 0, "System.Void") : nullptr;
    gF.trackGuidePressLeft = gF.trackGuideUIClass ? FindMethodExact(gF.trackGuideUIClass, "OnPressBtnLeft", 2, "UnityEngine.GameObject", 0, "System.Void") : nullptr;
    gF.trackGuidePressRight = gF.trackGuideUIClass ? FindMethodExact(gF.trackGuideUIClass, "OnPressBtnRight", 2, "UnityEngine.GameObject", 0, "System.Void") : nullptr;
    gF.trackJudgeDrag = gF.trackPoolsClass ? FindMethodExact(gF.trackPoolsClass, "JudgeNoteDrag", 1, "Dance.MusicTool.eTrackDirection", 0, "System.Void") : nullptr;
    gF.trackUIBtnLeft = gF.trackUIClass ? gAPI.class_get_field_from_name(gF.trackUIClass, "btnLeft") : nullptr;
    gF.trackUIBtnRight = gF.trackUIClass ? gAPI.class_get_field_from_name(gF.trackUIClass, "btnRight") : nullptr;
    gF.trackGuideBtnLeft = gF.trackGuideUIClass ? gAPI.class_get_field_from_name(gF.trackGuideUIClass, "btnLeft") : nullptr;
    gF.trackGuideBtnRight = gF.trackGuideUIClass ? gAPI.class_get_field_from_name(gF.trackGuideUIClass, "btnRight") : nullptr;
    gF.trackUIPools = gF.trackUIClass ? gAPI.class_get_field_from_name(gF.trackUIClass, "uiPools") : nullptr;
    gF.trackPoolsCurrentNoteUI = gF.trackPoolsClass ? gAPI.class_get_field_from_name(gF.trackPoolsClass, "curDispalyNote") : nullptr;
    gF.trackPoolsAudioTime = gF.trackPoolsClass ? gAPI.class_get_field_from_name(gF.trackPoolsClass, "audioTime") : nullptr;
    gF.trackUINoteData = gF.trackUINoteClass ? gAPI.class_get_field_from_name(gF.trackUINoteClass, "noteData") : nullptr;
    gF.trackCtrlNote = gF.trackCtrlClass ? gAPI.class_get_field_from_name(gF.trackCtrlClass, "curDisplayNote") : nullptr;
    // V10.13: scan the controller's full chart list instead of trusting the single
    // presentation cursor. V10.12 runtime proved every dispatched note was Perfect,
    // while the user still saw misses, so the missing stage is acquisition of notes
    // that never become our locked curDispalyNote target.
    gF.trackCtrlAllNotes = gF.trackCtrlClass ? gAPI.class_get_field_from_name(gF.trackCtrlClass, "noteAllList") : nullptr;
    gF.trackCtrlAudioTime = gF.trackCtrlClass ? gAPI.class_get_field_from_name(gF.trackCtrlClass, "audioTime") : nullptr;
    gF.trackNoteIndex = gF.trackNoteClass ? gAPI.class_get_field_from_name(gF.trackNoteClass, "NoteIndex") : nullptr;
    gF.trackNoteDir = gF.trackNoteClass ? gAPI.class_get_field_from_name(gF.trackNoteClass, "Direction") : nullptr;
    gF.trackNoteChannel = gF.trackNoteClass ? gAPI.class_get_field_from_name(gF.trackNoteClass, "Channel") : nullptr;
    gF.trackNoteJudgeTime = gF.trackNoteClass ? gAPI.class_get_field_from_name(gF.trackNoteClass, "JudgeTime") : nullptr;
    gF.trackNoteSecondJudgeTime = gF.trackNoteClass ? gAPI.class_get_field_from_name(gF.trackNoteClass, "secondJudgeTime") : nullptr;
    gF.trackNoteRanges = gF.trackNoteClass ? gAPI.class_get_field_from_name(gF.trackNoteClass, "RangeList") : nullptr;
    gF.trackNoteSecondRanges = gF.trackNoteClass ? gAPI.class_get_field_from_name(gF.trackNoteClass, "SecondRangeList") : nullptr;
    gF.trackNoteJudgeEnd = gF.trackNoteClass ? gAPI.class_get_field_from_name(gF.trackNoteClass, "isJudgeEnd") : nullptr;
    gF.trackNoteJudgeSecond = gF.trackNoteClass ? gAPI.class_get_field_from_name(gF.trackNoteClass, "isJudgeSecond") : nullptr;
    gF.trackNoteHitSecond = gF.trackNoteClass ? gAPI.class_get_field_from_name(gF.trackNoteClass, "isHitSecond") : nullptr;
    gF.trackNoteJudgeLevel = gF.trackNoteClass ? gAPI.class_get_field_from_name(gF.trackNoteClass, "judgeLevel") : nullptr;

    gF.witchUIClass = gAPI.class_from_name(hotfix, "Modules.UI", "UI_DanceAuditionChallengeWitch");
    gF.witchGroupClass = gAPI.class_from_name(hotfix, "Dance", "AuditionWitchGroup");
    gF.auditionArrowClass = gAPI.class_from_name(hotfix, "Dance", "AuditionArrows");
    gF.witchOnDrumDown = gF.witchUIClass ? FindMethodExact(gF.witchUIClass, "OnDrumDown", 1, "Dance.AuditionBeatType", 0, "System.Void") : nullptr;
    gF.witchIsAllHitLane = gF.witchGroupClass ? FindMethodExact(gF.witchGroupClass, "IsAllHit", 1, "System.Int32", 0, "System.Boolean") : nullptr;
    gF.witchUICurGroup = gF.witchUIClass ? gAPI.class_get_field_from_name(gF.witchUIClass, "curGroup") : nullptr;
    gF.witchUIAudioTime = gF.witchUIClass ? gAPI.class_get_field_from_name(gF.witchUIClass, "audioTime") : nullptr;
    gF.witchUICenterTime = gF.witchUIClass ? gAPI.class_get_field_from_name(gF.witchUIClass, "centerAudioTime") : nullptr;
    gF.witchUIOpenClickBeatTime = gF.witchUIClass ? gAPI.class_get_field_from_name(gF.witchUIClass, "openClickBeatTime") : nullptr;
    gF.witchUIDrumArray = gF.witchUIClass ? gAPI.class_get_field_from_name(gF.witchUIClass, "arryDrumBeat") : nullptr;
    gF.witchGroupArrowsArray = gF.witchGroupClass ? gAPI.class_get_field_from_name(gF.witchGroupClass, "arrowsList") : nullptr;
    gF.witchGroupIndexArray = gF.witchGroupClass ? gAPI.class_get_field_from_name(gF.witchGroupClass, "curArrowIndex") : nullptr;
    gF.witchGroupGroupIndex = gF.witchGroupClass ? gAPI.class_get_field_from_name(gF.witchGroupClass, "groupIndex") : nullptr;
    gF.witchGroupIsShow = gF.witchGroupClass ? gAPI.class_get_field_from_name(gF.witchGroupClass, "isShow") : nullptr;
    gF.witchGroupIsHitBeat = gF.witchGroupClass ? gAPI.class_get_field_from_name(gF.witchGroupClass, "isHitBeat") : nullptr;
    gF.witchGroupRanges = gF.witchGroupClass ? gAPI.class_get_field_from_name(gF.witchGroupClass, "rangeList") : nullptr;
    gF.witchGroupJudge = gF.witchGroupClass ? gAPI.class_get_field_from_name(gF.witchGroupClass, "judgeLevel") : nullptr;
    gF.witchArrowDir = gF.auditionArrowClass ? gAPI.class_get_field_from_name(gF.auditionArrowClass, "arrowsDir") : nullptr;

    gF.taikoUIClass = gAPI.class_from_name(hotfix, "Modules.UI", "UI_DanceTaiko");
    gF.taikoCtrlClass = gAPI.class_from_name(hotfix, "", "DanceTaikoController");
    gF.taikoNoteClass = gAPI.class_from_name(hotfix, "Dance.MusicTool", "TaikoNote");
    gF.taikoPressLeft = gF.taikoUIClass ? FindMethodExact(gF.taikoUIClass, "OnPressLeft", 2, "UnityEngine.GameObject", 0, "System.Void") : nullptr;
    gF.taikoPressRight = gF.taikoUIClass ? FindMethodExact(gF.taikoUIClass, "OnPressRight", 2, "UnityEngine.GameObject", 0, "System.Void") : nullptr;
    gF.taikoDragLeft = gF.taikoUIClass ? FindMethodExact(gF.taikoUIClass, "OnDragLeft", 2, "UnityEngine.GameObject", 0, "System.Void") : nullptr;
    gF.taikoDragRight = gF.taikoUIClass ? FindMethodExact(gF.taikoUIClass, "OnDragRight", 2, "UnityEngine.GameObject", 0, "System.Void") : nullptr;
    gF.taikoUICtrl = gF.taikoUIClass ? gAPI.class_get_field_from_name(gF.taikoUIClass, "taikoCtrl") : nullptr;
    gF.taikoUIBtnLeft = gF.taikoUIClass ? gAPI.class_get_field_from_name(gF.taikoUIClass, "btnLeft") : nullptr;
    gF.taikoUIBtnRight = gF.taikoUIClass ? gAPI.class_get_field_from_name(gF.taikoUIClass, "btnRight") : nullptr;
    gF.taikoCtrlNote = gF.taikoCtrlClass ? gAPI.class_get_field_from_name(gF.taikoCtrlClass, "nowNoteData") : nullptr;
    gF.taikoCtrlTime = gF.taikoCtrlClass ? gAPI.class_get_field_from_name(gF.taikoCtrlClass, "nowMusicTime") : nullptr;
    gF.taikoCtrlLongInterval = gF.taikoCtrlClass ? gAPI.class_get_field_from_name(gF.taikoCtrlClass, "longHitInterval") : nullptr;
    gF.taikoNoteDir = gF.taikoNoteClass ? gAPI.class_get_field_from_name(gF.taikoNoteClass, "direction") : nullptr;
    gF.taikoNoteType = gF.taikoNoteClass ? gAPI.class_get_field_from_name(gF.taikoNoteClass, "noteType") : nullptr;
    gF.taikoNoteJudgeTime = gF.taikoNoteClass ? gAPI.class_get_field_from_name(gF.taikoNoteClass, "judgeTime") : nullptr;
    gF.taikoNoteEndTime = gF.taikoNoteClass ? gAPI.class_get_field_from_name(gF.taikoNoteClass, "endJudgeTime") : nullptr;

    const bool classicOK = BindProfile(gClassicB, hotfix, core,
                                       "UI_DanceAudition", "AuditionGroup", "AuditionArrows");
    const bool burstOK = BindProfile(gBurstB, hotfix, core,
                                     "UI_DanceBurstAu", "BurstAuGroup", "BurstAuArrows");
    if (!classicOK && !burstOK) {
        Emit(@"RESOLVE", @"FAULT", @"SUPPORTED_PROFILE_BIND_FAILED",
             [NSString stringWithFormat:@"classic=%d burst=%d", classicOK ? 1 : 0, burstOK ? 1 : 0]);
        return false;
    }

    // Keep a valid common binding selected before runtime discovery. It will be replaced
    // with the exact profile as soon as a live UI instance is found.
    gB = classicOK ? gClassicB : gBurstB;
    gBindingsReady = YES;
    Emit(@"RESOLVE", @"READY", @"BINDINGS_READY",
         [NSString stringWithFormat:@"build=%@ profiles=classic:%d,burst:%d,nativeBubble14:%d beatButtonPath=%d unityTimeStatic=%d trackVisibleNote=%d trackPhysicalButtons=%d trackChartScanner=%d trackJudgeTimePrimary=1 skinLocal=%d skinTargetResolver=6 skinSticky=1 skinGCHandle=%d skinListFields=1 skinPinVerify=%d skinAllBodySticky=1 vipVisual=%d vipSelfBillboard=%d vipLocalIdentity=%d vipRoleAwareCells=%d vipHeadNameMatch=%d vipQueuedUI=1 vipUniqueUI=0 vipServerState=0 skinTargets=roomBase:%d,roomCompat:%d,dance:%d,gui:%d fullRouter=1 modes=1-7,10-29 invoke=runtime metadata=fresh self_input=1",
          kBuildTag, classicOK ? 1 : 0, burstOK ? 1 : 0, nativeBubble14OK ? 1 : 0,
          (gArrayGetLength && gArrayGetValue) ? 1 : 0, gUnityTimeGetTime ? 1 : 0,
          (gF.trackUIPools && gF.trackPoolsCurrentNoteUI && gF.trackPoolsAudioTime && gF.trackUINoteData) ? 1 : 0,
          (gF.trackPressLeft && gF.trackPressRight && gF.trackUIBtnLeft && gF.trackUIBtnRight) ? 1 : 0,
          (gF.trackCtrlAllNotes && gF.trackNoteIndex && gF.trackNoteJudgeTime && gF.trackNoteJudgeEnd) ? 1 : 0,
          gSkinBindingsReady ? 1 : 0,
          (gAPI.gchandle_new && gAPI.gchandle_get_target && gAPI.gchandle_free) ? 1 : 0,
          gSkinB.playerIsPuton ? 1 : 0,
          gVIPBindingsReady ? 1 : 0,
          (gVIPB.billboardRoleId && gVIPB.billboardVipIcon) ? 1 : 0,
          (gVIPB.clientPlayerGetSingleton && gVIPB.clientPlayerGetRoleInfo && gVIPB.commonRoleId && gVIPB.roleInfoGetVipLevel) ? 1 : 0,
          ((gVIPB.waitRoomCellData && gVIPB.waitRoomCellVipIcon && gVIPB.roomPlayerDataRoleId) ? 1 : 0) +
          ((gVIPB.islandPlayerData && gVIPB.islandPlayerVipIcon && gVIPB.roomPlayerDataRoleId) ? 1 : 0) +
          ((gVIPB.roomPlayerInfoRoleId && gVIPB.roomPlayerInfoVipIcon) ? 1 : 0) +
          ((gVIPB.dgPlayerInfoRoleId && gVIPB.dgPlayerInfoVipIcon) ? 1 : 0) +
          ((gVIPB.rankPlayerRoleId && gVIPB.rankPlayerVipIcon) ? 1 : 0),
          (gVIPB.playerHeadNameLabel && gVIPB.playerHeadVipIcon && gVIPB.uiLabelText && gVIPB.roleInfoGetRoleName) ? 1 : 0,
          (gSkinB.roomGetRoom && gSkinB.roomBaseGetLocalPlayer && gSkinB.roomPlayerPlayer) ? 1 : 0,
          (gSkinB.roomGetRoomPlayer && gSkinB.roomPlayerPlayer) ? 1 : 0,
          (gDanceGetLogic && gSkinB.baseDanceGetPlayer && gSkinB.dancerControllerPlayer) ? 1 : 0,
          (gSkinB.appGUIModule && gSkinB.guiGetPlayerManager && gSkinB.uiPlayerManagerPlayersList && gSkinB.uiPlayerModel) ? 1 : 0]);
    return true;
}

static bool InvokeRaw(const MethodInfo *method, void *instance, void **args, Il2CppObject **retOut = nullptr) {
    if (!method || !gAPI.runtime_invoke) return false;
    Il2CppObject *exc = nullptr;
    Il2CppObject *ret = gAPI.runtime_invoke(method, instance, args, &exc);
    if (retOut) *retOut = ret;
    return exc == nullptr;
}

static bool InvokeBool(const MethodInfo *method, void *instance, void **args, bool &out) {
    Il2CppObject *ret = nullptr;
    if (!InvokeRaw(method, instance, args, &ret) || !ret) return false;
    void *p = gAPI.object_unbox(ret);
    if (!p) return false;
    out = *reinterpret_cast<uint8_t *>(p) != 0;
    return true;
}

static bool InvokeInt32(const MethodInfo *method, void *instance, void **args, int32_t &out) {
    Il2CppObject *ret = nullptr;
    if (!InvokeRaw(method, instance, args, &ret) || !ret) return false;
    void *p = gAPI.object_unbox(ret);
    if (!p) return false;
    out = *reinterpret_cast<int32_t *>(p);
    return true;
}

static bool InvokeUInt8(const MethodInfo *method, void *instance, void **args, uint8_t &out) {
    Il2CppObject *ret = nullptr;
    if (!InvokeRaw(method, instance, args, &ret) || !ret) return false;
    void *p = gAPI.object_unbox(ret);
    if (!p) return false;
    out = *reinterpret_cast<uint8_t *>(p);
    return true;
}

static bool InvokeUInt16(const MethodInfo *method, void *instance, void **args, uint16_t &out) {
    Il2CppObject *ret = nullptr;
    if (!InvokeRaw(method, instance, args, &ret) || !ret) return false;
    void *p = gAPI.object_unbox(ret);
    if (!p) return false;
    out = *reinterpret_cast<uint16_t *>(p);
    return true;
}

static bool InvokeUInt32(const MethodInfo *method, void *instance, void **args, uint32_t &out) {
    Il2CppObject *ret = nullptr;
    if (!InvokeRaw(method, instance, args, &ret) || !ret) return false;
    void *p = gAPI.object_unbox(ret);
    if (!p) return false;
    out = *reinterpret_cast<uint32_t *>(p);
    return true;
}

static NSString *ManagedString(Il2CppObject *obj) {
    if (!obj || !gAPI.string_chars || !gAPI.string_length) return nil;
    Il2CppString *str = reinterpret_cast<Il2CppString *>(obj);
    int32_t len = gAPI.string_length(str);
    const uint16_t *chars = gAPI.string_chars(str);
    if (!chars || len <= 0) return @"";
    return [NSString stringWithCharacters:reinterpret_cast<const unichar *>(chars) length:(NSUInteger)len];
}

static bool InvokeFloat(const MethodInfo *method, void *instance, void **args, float &out) {
    Il2CppObject *ret = nullptr;
    if (!InvokeRaw(method, instance, args, &ret) || !ret) return false;
    void *p = gAPI.object_unbox(ret);
    if (!p) return false;
    out = *reinterpret_cast<float *>(p);
    return isfinite(out);
}

static int32_t ManagedArrayLength(Il2CppObject *array) {
    if (!array || !gArrayGetLength) return -1;
    int32_t length = -1;
    if (!InvokeInt32(gArrayGetLength, array, nullptr, length)) return -1;
    return length;
}

static Il2CppObject *ManagedArrayItem(Il2CppObject *array, int32_t index) {
    if (!array || !gArrayGetValue || index < 0) return nullptr;
    void *args[1] = { &index };
    Il2CppObject *ret = nullptr;
    if (!InvokeRaw(gArrayGetValue, array, args, &ret)) return nullptr;
    return ret;
}

static int32_t ProbeDanceMode(Il2CppObject **moduleOut = nullptr) {
    if (moduleOut) *moduleOut = nullptr;
    if (!gAPI.field_static_get_value || !gAppDanceModuleField || !gDanceGetMode) return -1;
    Il2CppObject *module = nullptr;
    gAPI.field_static_get_value(gAppDanceModuleField, &module);
    if (moduleOut) *moduleOut = module;
    if (!module) return -1;
    int32_t mode = -1;
    if (!InvokeInt32(gDanceGetMode, module, nullptr, mode)) return -1;
    return mode;
}

static void Health(NSString *state, NSString *reason, NSString *details);

template <typename T>
static bool ReadField(Il2CppObject *obj, FieldInfo *field, T &out) {
    if (!obj || !field || !gAPI.field_get_value) return false;
    memset(&out, 0, sizeof(T));
    gAPI.field_get_value(obj, field, &out);
    return true;
}

template <typename T>
static bool WriteField(Il2CppObject *obj, FieldInfo *field, const T &value) {
    if (!obj || !field || !gAPI.field_set_value) return false;
    T copy = value;
    gAPI.field_set_value(obj, field, &copy);
    return true;
}

static Il2CppObject *GetDanceLogic(Il2CppObject *module) {
    if (!module || !gDanceGetLogic) return nullptr;
    Il2CppObject *logic = nullptr;
    if (!InvokeRaw(gDanceGetLogic, module, nullptr, &logic)) return nullptr;
    return logic;
}

__attribute__((unused)) static bool HandleStarlightBubbleNativeAutoPlay(int32_t danceMode, Il2CppObject *danceModule) {
    if (danceMode != 14) return false;

    if (!danceModule || !gDanceGetLogic || !gStarlightBubbleDanceClass || !gBubbleNoteControllerClass ||
        !gStarlightBubbleNoteCtrlField || !gBubbleIsAutoPlayField) {
        Health(@"BLOCKED", @"MODE14_BINDINGS_NOT_READY", @"expected=StarlightTheatreBubbleDance/BubbleNoteController");
        return true;
    }

    Il2CppObject *logic = GetDanceLogic(danceModule);
    if (!logic) {
        Health(@"WAIT_PREREQ", @"DANCE_LOGIC_NOT_READY", @"danceMode=14");
        return true;
    }

    Il2CppClass *actualLogicClass = gAPI.object_get_class ? gAPI.object_get_class(logic) : nullptr;
    if (actualLogicClass != gStarlightBubbleDanceClass) {
        Health(@"BLOCKED", @"MODE14_LOGIC_CLASS_MISMATCH",
               [NSString stringWithFormat:@"logic=%p actualClass=%p expectedClass=%p", logic, actualLogicClass, gStarlightBubbleDanceClass]);
        return true;
    }

    Il2CppObject *noteCtrl = nullptr;
    if (!ReadField(logic, gStarlightBubbleNoteCtrlField, noteCtrl) || !noteCtrl) {
        Health(@"WAIT_PREREQ", @"NOTE_CONTROLLER_NOT_READY", [NSString stringWithFormat:@"danceLogic=%p", logic]);
        return true;
    }

    Il2CppClass *actualCtrlClass = gAPI.object_get_class ? gAPI.object_get_class(noteCtrl) : nullptr;
    if (actualCtrlClass != gBubbleNoteControllerClass) {
        Health(@"BLOCKED", @"NOTE_CONTROLLER_CLASS_MISMATCH",
               [NSString stringWithFormat:@"ctrl=%p actualClass=%p expectedClass=%p", noteCtrl, actualCtrlClass, gBubbleNoteControllerClass]);
        return true;
    }

    if (noteCtrl != gBubbleNoteCtrl || logic != gBubbleDanceLogic) {
        gBubbleDanceLogic = logic;
        gBubbleNoteCtrl = noteCtrl;
        gBubbleAutoPlayOwned = NO;
        gBubblePreviousAutoPlay = 0;
        gBubbleLastCombo = 0;
        gBubbleLastPerfectCount = 0;
        Emit(@"SOURCE", @"READY", @"NATIVE_AUTOPLAY_CONTROLLER_FOUND",
             [NSString stringWithFormat:@"mode=14 danceLogic=%p noteCtrl=%p", logic, noteCtrl]);
    }

    uint8_t autoPlay = 0;
    uint32_t combo = 0;
    int32_t perfectCount = 0;
    uint8_t isEnd = 0;
    ReadField(noteCtrl, gBubbleIsAutoPlayField, autoPlay);
    if (gBubbleComboNowField) ReadField(noteCtrl, gBubbleComboNowField, combo);
    if (gBubblePerfectCountField) ReadField(noteCtrl, gBubblePerfectCountField, perfectCount);
    if (gBubbleIsEndField) ReadField(noteCtrl, gBubbleIsEndField, isEnd);

    if (!autoPlay) {
        gBubblePreviousAutoPlay = autoPlay;
        uint8_t requested = 1;
        Emit(@"ACTION", @"RUNNING", @"NATIVE_AUTOPLAY_ENABLE_BEGIN",
             [NSString stringWithFormat:@"mode=14 ctrl=%p before=%u", noteCtrl, autoPlay]);
        if (!WriteField(noteCtrl, gBubbleIsAutoPlayField, requested)) {
            Emit(@"FAULT", @"FAULT", @"NATIVE_AUTOPLAY_WRITE_FAIL", [NSString stringWithFormat:@"ctrl=%p", noteCtrl]);
            return true;
        }
        uint8_t after = 0;
        ReadField(noteCtrl, gBubbleIsAutoPlayField, after);
        if (!after) {
            Emit(@"FAULT", @"FAULT", @"NATIVE_AUTOPLAY_READBACK_FAIL", [NSString stringWithFormat:@"ctrl=%p", noteCtrl]);
            return true;
        }
        gBubbleAutoPlayOwned = YES;
        autoPlay = after;
        Emit(@"ACK", @"RUNNING", @"NATIVE_AUTOPLAY_ENABLED",
             [NSString stringWithFormat:@"mode=14 ctrl=%p after=%u mechanism=BubbleNoteController.isAutoPlay", noteCtrl, after]);
    }

    if (combo != gBubbleLastCombo || perfectCount != gBubbleLastPerfectCount) {
        Emit(@"PROGRESS", @"RUNNING", @"NATIVE_AUTOPLAY_PROGRESS",
             [NSString stringWithFormat:@"mode=14 combo=%u->%u perfectCount=%d->%d",
              gBubbleLastCombo, combo, gBubbleLastPerfectCount, perfectCount]);
        gBubbleLastCombo = combo;
        gBubbleLastPerfectCount = perfectCount;
        gBubbleLastProgressLog = CACurrentMediaTime();
    }

    Health(isEnd ? @"COMPLETE" : @"RUNNING",
           isEnd ? @"NATIVE_AUTOPLAY_DANCE_END" : @"NATIVE_AUTOPLAY_ACTIVE",
           [NSString stringWithFormat:@"mode=14 ctrl=%p auto=%u combo=%u perfectCount=%d", noteCtrl, autoPlay, combo, perfectCount]);
    return true;
}

static void RestoreStarlightBubbleAutoPlayIfOwned() {
    if (!gBubbleAutoPlayOwned || !gBubbleNoteCtrl) {
        gBubbleDanceLogic = nullptr;
        gBubbleNoteCtrl = nullptr;
        gBubbleAutoPlayOwned = NO;
        return;
    }

    Il2CppObject *module = nullptr;
    int32_t mode = ProbeDanceMode(&module);
    Il2CppObject *logic = (mode == 14 && module) ? GetDanceLogic(module) : nullptr;
    if (logic && logic == gBubbleDanceLogic) {
        Il2CppObject *ctrl = nullptr;
        if (ReadField(logic, gStarlightBubbleNoteCtrlField, ctrl) && ctrl == gBubbleNoteCtrl) {
            uint8_t requested = gBubblePreviousAutoPlay;
            WriteField(ctrl, gBubbleIsAutoPlayField, requested);
            uint8_t after = 1;
            ReadField(ctrl, gBubbleIsAutoPlayField, after);
            Emit(@"ACK", @"OFF", @"NATIVE_AUTOPLAY_RESTORED",
                 [NSString stringWithFormat:@"mode=14 ctrl=%p restored=%u", ctrl, after]);
        }
    }
    gBubbleDanceLogic = nullptr;
    gBubbleNoteCtrl = nullptr;
    gBubbleAutoPlayOwned = NO;
}

static ListCacheEntry *ListCacheFor(Il2CppObject *list) {
    if (!list || !gAPI.object_get_class) return nullptr;
    Il2CppClass *klass = gAPI.object_get_class(list);
    if (!klass) return nullptr;
    for (auto &entry : gListCache) {
        if (entry.klass == klass) return &entry;
    }
    for (auto &entry : gListCache) {
        if (!entry.klass) {
            entry.klass = klass;
            entry.count = FindMethodExact(klass, "get_Count", 0, nullptr, 0, "System.Int32");
            entry.item = FindMethodExact(klass, "get_Item", 1, "System.Int32", 0, nullptr);
            return &entry;
        }
    }
    return nullptr;
}

static int32_t ListCount(Il2CppObject *list) {
    ListCacheEntry *cache = ListCacheFor(list);
    if (!cache || !cache->count) return -1;
    int32_t count = -1;
    if (!InvokeInt32(cache->count, list, nullptr, count)) return -1;
    return count;
}

static Il2CppObject *ListItem(Il2CppObject *list, int32_t index) {
    ListCacheEntry *cache = ListCacheFor(list);
    if (!cache || !cache->item || index < 0) return nullptr;
    void *args[1] = { &index };
    Il2CppObject *ret = nullptr;
    if (!InvokeRaw(cache->item, list, args, &ret)) return nullptr;
    return ret;
}

// V10.18 skin-only fallback. V10.17 runtime showed playersList != null while
// invoking generic List<UIPlayer>.get_Count returned no value (guiCount=-1).
// Resolve the runtime generic class' own metadata fields `_size` and `_items`
// instead. This is current-build metadata discovery, not a hard-coded object layout.
static bool SkinListBackingFields(Il2CppObject *list, FieldInfo **sizeOut, FieldInfo **itemsOut) {
    if (sizeOut) *sizeOut = nullptr;
    if (itemsOut) *itemsOut = nullptr;
    if (!list || !gAPI.object_get_class || !gAPI.class_get_field_from_name) return false;
    Il2CppClass *klass = gAPI.object_get_class(list);
    if (!klass) return false;
    FieldInfo *sizeField = gAPI.class_get_field_from_name(klass, "_size");
    FieldInfo *itemsField = gAPI.class_get_field_from_name(klass, "_items");
    if (sizeOut) *sizeOut = sizeField;
    if (itemsOut) *itemsOut = itemsField;
    return sizeField && itemsField;
}

static int32_t SkinListCount(Il2CppObject *list) {
    int32_t count = ListCount(list);
    if (count >= 0) {
        gSkinLastGUIListPath = @"method";
        return count;
    }
    FieldInfo *sizeField = nullptr;
    FieldInfo *itemsField = nullptr;
    if (!SkinListBackingFields(list, &sizeField, &itemsField)) {
        gSkinLastGUIListPath = @"unresolved";
        return -1;
    }
    count = -1;
    if (!ReadField(list, sizeField, count) || count < 0 || count > 4096) {
        gSkinLastGUIListPath = @"field-invalid";
        return -1;
    }
    Il2CppObject *items = nullptr;
    if (!ReadField(list, itemsField, items) || !items) {
        if (count == 0) {
            gSkinLastGUIListPath = @"fields-empty";
            return 0;
        }
        gSkinLastGUIListPath = @"items-null";
        return -1;
    }
    int32_t capacity = ManagedArrayLength(items);
    if (capacity >= 0 && count > capacity) {
        gSkinLastGUIListPath = @"field-capacity-mismatch";
        return -1;
    }
    gSkinLastGUIListPath = @"fields";
    return count;
}

static Il2CppObject *SkinListItem(Il2CppObject *list, int32_t index) {
    if (!list || index < 0) return nullptr;
    // Keep the normal managed getter first when it works.
    Il2CppObject *viaMethod = ListItem(list, index);
    if (viaMethod) return viaMethod;

    FieldInfo *sizeField = nullptr;
    FieldInfo *itemsField = nullptr;
    if (!SkinListBackingFields(list, &sizeField, &itemsField)) return nullptr;
    int32_t count = -1;
    if (!ReadField(list, sizeField, count) || index >= count) return nullptr;
    Il2CppObject *items = nullptr;
    if (!ReadField(list, itemsField, items) || !items) return nullptr;
    return ManagedArrayItem(items, index);
}

static void SkinEmit(NSString *state, NSString *reason, NSString *details = nil) {
    DiagRecord(@"Skin", @"STATE", state, reason, details);
    gSkinStatus = [NSString stringWithFormat:@"%@ • %@", state ?: @"UNKNOWN", reason ?: @"UNKNOWN"];
    if (gUILogSink) {
        NSString *uiReason = details.length ? [NSString stringWithFormat:@"%@ • %@", reason ?: @"UNKNOWN", details] : (reason ?: @"UNKNOWN");
        gUILogSink(@"Skin", state ?: @"UNKNOWN", uiReason);
    }
}

__attribute__((unused)) static NSString *SkinTypeName(int32_t type) {
    switch (type) {
        case 0: return @"Hair"; case 1: return @"Coat"; case 2: return @"Pants"; case 3: return @"Shoes";
        case 5: return @"UpBody"; case 6: return @"AllBody"; case 7: return @"Top";
        case 8: return @"LeftShoulder"; case 9: return @"RightShoulder"; case 10: return @"Wing";
        case 11: return @"Face"; case 12: return @"Necklace"; case 13: return @"Tail";
        case 14: return @"LeftBangle"; case 15: return @"RightBangle"; case 16: return @"LeftHand";
        case 17: return @"RightHand"; case 18: return @"Gloves"; case 19: return @"Ring";
        case 20: return @"Leglet"; case 21: return @"Badge"; case 23: return @"Skin"; case 24: return @"Socks";
        case 25: return @"Vehicle"; case 26: return @"Sp_LeftHand"; case 27: return @"Sp_RightHand";
        case 28: return @"ColorCloth"; case 29: return @"Track"; case 30: return @"Motion_Walk";
        case 31: return @"Motion_Run"; case 32: return @"Motion_Fly";
        default: return [NSString stringWithFormat:@"Type%d", type];
    }
}

static Il2CppObject *FinalizeSkinPlayer(Il2CppObject *player, NSString *source, uint8_t *sexOut) {
    if (!player) return nullptr;
    if (sexOut && gSkinB.playerGetSex) {
        uint8_t sex = 2;
        if (InvokeUInt8(gSkinB.playerGetSex, player, nullptr, sex)) *sexOut = sex;
    }
    gSkinLastTargetSource = source ?: @"unknown";
    return player;
}

static bool SkinPlayerNativeAlive(Il2CppObject *player) {
    if (!player) return false;
    if (gSkinB.playerGameObject && gSkinB.unityObjectImplicit) {
        Il2CppObject *go = nullptr;
        if (ReadField(player, gSkinB.playerGameObject, go) && go) {
            void *args[1] = { go };
            bool alive = false;
            if (InvokeBool(gSkinB.unityObjectImplicit, nullptr, args, alive)) return alive;
        }
    }
    // Fallback when Unity Object validation is unavailable. A successfully loaded
    // Player is still a stronger signal than a raw cached pointer.
    if (gSkinB.playerGetLoadComplete) {
        bool loaded = false;
        if (InvokeBool(gSkinB.playerGetLoadComplete, player, nullptr, loaded)) return loaded;
    }
    return false;
}

static Il2CppObject *CachedSkinPlayer(void) {
    if (gSkinLastPlayerHandle && gAPI.gchandle_get_target) {
        Il2CppObject *target = gAPI.gchandle_get_target(gSkinLastPlayerHandle);
        if (target) return target;
    }
    return gSkinLastPlayer;
}

static void RememberSkinPlayer(Il2CppObject *player) {
    if (!player) return;
    Il2CppObject *old = CachedSkinPlayer();
    if (old != player) {
        if (gSkinLastPlayerHandle && gAPI.gchandle_free) {
            gAPI.gchandle_free(gSkinLastPlayerHandle);
            gSkinLastPlayerHandle = 0;
        }
        if (gAPI.gchandle_new && gAPI.gchandle_get_target && gAPI.gchandle_free) gSkinLastPlayerHandle = gAPI.gchandle_new(player, false);
    }
    gSkinLastPlayer = player;
    if (gSkinB.playerGetRoleId) {
        uint32_t role = 0;
        if (InvokeUInt32(gSkinB.playerGetRoleId, player, nullptr, role) && role) gSkinLastRoleId = role;
    }
}

static Il2CppObject *ActiveSkinPlayer(uint8_t *sexOut = nullptr) {
    if (sexOut) *sexOut = 2;
    if (!gSkinBindingsReady || !gAPI.field_static_get_value) return nullptr;

    gSkinLastGUIListCount = -1;
    gSkinLastGUINonNullModels = 0;
    gSkinLastGUILoadedModels = 0;
    gSkinLastGUIListPath = @"none";
    gSkinLastGUIStage = @"not-entered";
    Il2CppObject *cached = CachedSkinPlayer();

    // 1) Preferred room path: RoomModule.GetRoom() -> RoomBase.LocalPlayer -> RoomPlayer.player.
    Il2CppObject *roomModule = nullptr;
    gAPI.field_static_get_value(gSkinB.appRoomModule, &roomModule);
    if (roomModule) {
        if (gSkinB.roomGetRoom && gSkinB.roomBaseGetLocalPlayer) {
            Il2CppObject *room = nullptr;
            if (InvokeRaw(gSkinB.roomGetRoom, roomModule, nullptr, &room) && room) {
                Il2CppObject *roomPlayer = nullptr;
                if (InvokeRaw(gSkinB.roomBaseGetLocalPlayer, room, nullptr, &roomPlayer) && roomPlayer) {
                    Il2CppObject *player = nullptr;
                    if (ReadField(roomPlayer, gSkinB.roomPlayerPlayer, player) && player)
                        return FinalizeSkinPlayer(player, @"RoomBase.LocalPlayer", sexOut);
                }
            }
        }
        // 2) Compatibility path.
        if (gSkinB.roomGetRoomPlayer) {
            Il2CppObject *roomPlayer = nullptr;
            if (InvokeRaw(gSkinB.roomGetRoomPlayer, roomModule, nullptr, &roomPlayer) && roomPlayer) {
                Il2CppObject *player = nullptr;
                if (ReadField(roomPlayer, gSkinB.roomPlayerPlayer, player) && player)
                    return FinalizeSkinPlayer(player, @"RoomModule.RoomPlayer", sexOut);
            }
        }
    }

    // 3) Dance path: during an active match BaseDance owns the self DancerController.
    if (gAppDanceModuleField && gDanceGetLogic && gSkinB.baseDanceGetPlayer && gSkinB.dancerControllerPlayer) {
        Il2CppObject *danceModule = nullptr;
        gAPI.field_static_get_value(gAppDanceModuleField, &danceModule);
        if (danceModule) {
            Il2CppObject *dance = nullptr;
            if (InvokeRaw(gDanceGetLogic, danceModule, nullptr, &dance) && dance) {
                Il2CppObject *dancer = nullptr;
                if (InvokeRaw(gSkinB.baseDanceGetPlayer, dance, nullptr, &dancer) && dancer) {
                    Il2CppObject *player = nullptr;
                    if (ReadField(dancer, gSkinB.dancerControllerPlayer, player) && player)
                        return FinalizeSkinPlayer(player, @"BaseDance.Player", sexOut);
                }
            }
        }
    }

    // 4) UI preview/lobby path. V10.16 required count == 1. Runtime proved that
    // after the first costume application the UI manager can stop being unambiguous,
    // even though the already-selected local model is still valid. Preserve target
    // continuity by matching the last successful Player pointer/RoleId, then fall
    // back to a unique loaded model.
    if (gSkinB.appGUIModule && gSkinB.guiGetPlayerManager &&
        gSkinB.uiPlayerManagerPlayersList && gSkinB.uiPlayerModel) {
        gSkinLastGUIStage = @"gui-module";
        Il2CppObject *guiModule = nullptr;
        gAPI.field_static_get_value(gSkinB.appGUIModule, &guiModule);
        if (guiModule) {
            gSkinLastGUIStage = @"manager";
            Il2CppObject *mgr = nullptr;
            if (InvokeRaw(gSkinB.guiGetPlayerManager, guiModule, nullptr, &mgr) && mgr) {
                gSkinLastGUIStage = @"players-list";
                Il2CppObject *players = nullptr;
                if (ReadField(mgr, gSkinB.uiPlayerManagerPlayersList, players) && players) {
                    gSkinLastGUIStage = @"list-count";
                    int32_t count = SkinListCount(players);
                    gSkinLastGUIListCount = count;
                    if (count < 0) gSkinLastGUIStage = @"list-count-failed";
                    else gSkinLastGUIStage = @"scan";
                    Il2CppObject *uniqueLoaded = nullptr;
                    Il2CppObject *uniqueNonNull = nullptr;
                    int32_t loadedCount = 0;
                    int32_t nonNullCount = 0;
                    for (int32_t i = 0; i < count; i++) {
                        Il2CppObject *uiPlayer = SkinListItem(players, i);
                        Il2CppObject *player = nullptr;
                        if (!uiPlayer || !ReadField(uiPlayer, gSkinB.uiPlayerModel, player) || !player) continue;
                        nonNullCount++;
                        uniqueNonNull = player;

                        if (cached && player == cached && SkinPlayerNativeAlive(player)) {
                            gSkinLastGUINonNullModels = nonNullCount;
                            return FinalizeSkinPlayer(player, @"GUI.UIPlayer.cached-member", sexOut);
                        }

                        if (gSkinLastRoleId && gSkinB.playerGetRoleId) {
                            uint32_t role = 0;
                            if (InvokeUInt32(gSkinB.playerGetRoleId, player, nullptr, role) && role == gSkinLastRoleId && SkinPlayerNativeAlive(player)) {
                                gSkinLastGUINonNullModels = nonNullCount;
                                return FinalizeSkinPlayer(player, @"GUI.UIPlayer.role-match", sexOut);
                            }
                        }

                        bool loaded = false;
                        if (!gSkinB.playerGetLoadComplete || (InvokeBool(gSkinB.playerGetLoadComplete, player, nullptr, loaded) && loaded)) {
                            if (SkinPlayerNativeAlive(player)) {
                                loadedCount++;
                                uniqueLoaded = player;
                            }
                        }
                    }
                    gSkinLastGUINonNullModels = nonNullCount;
                    gSkinLastGUILoadedModels = loadedCount;
                    if (loadedCount == 1 && uniqueLoaded)
                        return FinalizeSkinPlayer(uniqueLoaded, @"GUI.UIPlayer.unique-loaded", sexOut);
                    if (count == 1 && nonNullCount == 1 && uniqueNonNull && SkinPlayerNativeAlive(uniqueNonNull))
                        return FinalizeSkinPlayer(uniqueNonNull, @"GUI.UIPlayer.single", sexOut);
                }
            }
        }
    }

    // 5) Sticky local target: a strong IL2CPP GC handle keeps the last successfully
    // applied NewPlayer.Player managed object alive. We only reuse it while its Unity
    // GameObject is still natively alive, so a destroyed preview is not blindly called.
    if (gSkinLastPlayerHandle && gAPI.gchandle_get_target && cached && SkinPlayerNativeAlive(cached))
        return FinalizeSkinPlayer(cached, @"CachedLastPlayer.alive", sexOut);

    gSkinLastTargetSource = @"none";
    return nullptr;
}

static Il2CppObject *CreateUIntList(NSArray<NSNumber *> *ids) {
    if (!gSkinBindingsReady || !gSkinB.playerNeedPutOnItems || !gAPI.field_get_type || !gAPI.class_from_type || !gAPI.object_new) return nullptr;
    const Il2CppType *listType = gAPI.field_get_type(gSkinB.playerNeedPutOnItems);
    Il2CppClass *listClass = listType ? gAPI.class_from_type(listType) : nullptr;
    if (!listClass) return nullptr;
    const MethodInfo *ctor = FindMethodExact(listClass, ".ctor", 0, nullptr, 0, "System.Void");
    const MethodInfo *add = FindMethodExact(listClass, "Add", 1, "System.UInt32", 0, "System.Void");
    if (!ctor || !add) return nullptr;
    Il2CppObject *list = gAPI.object_new(listClass);
    if (!list || !InvokeRaw(ctor, list, nullptr, nullptr)) return nullptr;
    for (NSNumber *n in ids) {
        uint32_t itemID = n.unsignedIntValue;
        if (!itemID) continue;
        void *args[1] = { &itemID };
        if (!InvokeRaw(add, list, args, nullptr)) return nullptr;
    }
    return list;
}

static void VIPEmit(NSString *state, NSString *reason, NSString *details = nil) {
    DiagRecord(@"VIPVisual", @"STATE", state, reason, details);
    gVIPStatus = [NSString stringWithFormat:@"%@ • %@", state ?: @"UNKNOWN", reason ?: @"UNKNOWN"];
    if (gUILogSink) {
        NSString *uiReason = details.length ? [NSString stringWithFormat:@"%@ • %@", reason ?: @"UNKNOWN", details] : (reason ?: @"UNKNOWN");
        gUILogSink(@"VIPVisual", state ?: @"UNKNOWN", uiReason);
    }
}

static Il2CppObject *FindObjectsForClass(Il2CppClass *klass) {
    if (!gVIPBindingsReady || !klass || !gVIPB.findObjectsOfType || !gAPI.class_get_type || !gAPI.type_get_object) return nullptr;
    const Il2CppType *type = gAPI.class_get_type(klass);
    Il2CppObject *typeObj = type ? gAPI.type_get_object(type) : nullptr;
    if (!typeObj) return nullptr;
    int32_t includeInactive = 1;
    void *args[2] = { typeObj, &includeInactive };
    Il2CppObject *ret = nullptr;
    if (!InvokeRaw(gVIPB.findObjectsOfType, nullptr, args, &ret)) return nullptr;
    return ret;
}

static bool SetVIPIconVisual(Il2CppObject *icon, int32_t level, bool captureOriginal) {
    if (!icon || !gVIPB.vipSetLevel) return false;
    if (captureOriginal && gVIPOriginalLevel < 0 && gVIPB.vipCurrentLevel) {
        int32_t old = -1;
        if (ReadField(icon, gVIPB.vipCurrentLevel, old) && old >= 0 && old <= 255) gVIPOriginalLevel = old;
    }
    int32_t value = level;
    void *args[1] = { &value };
    if (!InvokeRaw(gVIPB.vipSetLevel, icon, args, nullptr)) return false;
    if (gVIPB.vipCurrentLevel) {
        int32_t after = -1;
        if (ReadField(icon, gVIPB.vipCurrentLevel, after) && after != value) return false;
    }
    return true;
}

static uint32_t VIPMaxLevel() {
    // Build 23.4 exposes VIP through 18. Keep 18 as the safe presentation fallback
    // when ClientVIP/config is not initialized yet, while still honoring a future
    // runtime max above 18 without another menu update.
    uint32_t maxLevel = 18;
    if (gVIPB.clientVIPGetMaxLevel) {
        uint32_t runtimeMax = 0;
        if (InvokeUInt32(gVIPB.clientVIPGetMaxLevel, nullptr, nullptr, runtimeMax) && runtimeMax > maxLevel && runtimeMax <= 100)
            maxLevel = runtimeMax;
    }
    return maxLevel;
}

static bool ReadLocalVIPIdentity(uint32_t &roleOut, int32_t &vipOut, NSString **nameOut = nullptr) {
    roleOut = 0;
    vipOut = -1;
    if (nameOut) *nameOut = nil;
    if (!gVIPB.clientPlayerGetSingleton || !gVIPB.clientPlayerGetRoleInfo || !gVIPB.commonRoleId) return false;

    Il2CppObject *clientPlayer = nullptr;
    if (!InvokeRaw(gVIPB.clientPlayerGetSingleton, nullptr, nullptr, &clientPlayer) || !clientPlayer) return false;

    Il2CppObject *roleInfo = nullptr;
    if (!InvokeRaw(gVIPB.clientPlayerGetRoleInfo, clientPlayer, nullptr, &roleInfo) || !roleInfo) return false;

    uint32_t role = 0;
    if (ReadField(roleInfo, gVIPB.commonRoleId, role) && role) roleOut = role;

    if (gVIPB.roleInfoGetVipLevel) {
        uint16_t vip = 0;
        if (InvokeUInt16(gVIPB.roleInfoGetVipLevel, roleInfo, nullptr, vip)) vipOut = (int32_t)vip;
    }
    if (nameOut && gVIPB.roleInfoGetRoleName) {
        Il2CppObject *nameObj = nullptr;
        if (InvokeRaw(gVIPB.roleInfoGetRoleName, roleInfo, nullptr, &nameObj) && nameObj) {
            NSString *name = ManagedString(nameObj);
            if (name.length) *nameOut = name;
        }
    }
    return roleOut != 0 || vipOut >= 0 || (nameOut && (*nameOut).length > 0);
}

static NSString *NormalizeVIPLabelName(NSString *text) {
    if (!text.length) return @"";
    NSMutableString *out = [NSMutableString string];
    BOOL inTag = NO;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '[') { inTag = YES; continue; }
        if (inTag) {
            if (c == ']') inTag = NO;
            continue;
        }
        [out appendString:[NSString stringWithCharacters:&c length:1]];
    }
    return [out stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static int ApplyNamedPlayerHeadIcons(NSString *localName, int32_t level, bool captureOriginal, int32_t &matched, int32_t &headCount) {
    matched = 0;
    headCount = 0;
    if (!localName.length || !gVIPB.playerHeadClass || !gVIPB.playerHeadNameLabel || !gVIPB.playerHeadVipIcon || !gVIPB.uiLabelText) return 0;
    Il2CppObject *heads = FindObjectsForClass(gVIPB.playerHeadClass);
    int32_t count = ManagedArrayLength(heads);
    headCount = count > 0 ? count : 0;
    int applied = 0;
    NSString *expected = NormalizeVIPLabelName(localName);
    for (int32_t i = 0; i < count; i++) {
        Il2CppObject *head = ManagedArrayItem(heads, i);
        if (!head) continue;
        Il2CppObject *label = nullptr;
        if (!ReadField(head, gVIPB.playerHeadNameLabel, label) || !label) continue;
        Il2CppObject *nameObj = nullptr;
        if (!ReadField(label, gVIPB.uiLabelText, nameObj) || !nameObj) continue;
        NSString *visibleName = NormalizeVIPLabelName(ManagedString(nameObj));
        if (!visibleName.length || ![visibleName isEqualToString:expected]) continue;
        matched++;
        Il2CppObject *icon = nullptr;
        if (!ReadField(head, gVIPB.playerHeadVipIcon, icon) || !icon) continue;
        if (SetVIPIconVisual(icon, level, captureOriginal)) applied++;
    }
    return applied;
}

static int ApplyNestedRoleIconClass(Il2CppClass *klass, FieldInfo *dataField, FieldInfo *roleField, FieldInfo *iconField,
                                    uint32_t localRole, int32_t level, bool captureOriginal, int32_t &matched) {
    if (!klass || !dataField || !roleField || !iconField || !localRole) return 0;
    Il2CppObject *objects = FindObjectsForClass(klass);
    int32_t count = ManagedArrayLength(objects);
    int applied = 0;
    for (int32_t i = 0; i < count; i++) {
        Il2CppObject *obj = ManagedArrayItem(objects, i);
        if (!obj) continue;
        Il2CppObject *data = nullptr;
        if (!ReadField(obj, dataField, data) || !data) continue;
        uint32_t role = 0;
        if (!ReadField(data, roleField, role) || role != localRole) continue;
        matched++;
        Il2CppObject *icon = nullptr;
        if (!ReadField(obj, iconField, icon) || !icon) continue;
        if (SetVIPIconVisual(icon, level, captureOriginal)) applied++;
    }
    return applied;
}

static int ApplyDirectRoleIconClass(Il2CppClass *klass, FieldInfo *roleField, FieldInfo *iconField,
                                    uint32_t localRole, int32_t level, bool captureOriginal,
                                    NSString *tag, int32_t &matched) {
    if (!klass || !roleField || !iconField || !localRole) return 0;
    Il2CppObject *objects = FindObjectsForClass(klass);
    int32_t count = ManagedArrayLength(objects);
    int applied = 0;
    for (int32_t i = 0; i < count; i++) {
        Il2CppObject *obj = ManagedArrayItem(objects, i);
        if (!obj) continue;
        uint32_t role = 0;
        if (!ReadField(obj, roleField, role) || role != localRole) continue;
        Il2CppObject *icon = nullptr;
        if (!ReadField(obj, iconField, icon) || !icon) continue;
        matched++;
        if (SetVIPIconVisual(icon, level, captureOriginal)) {
            applied++;
            if (gVIPLastTarget.length && ![gVIPLastTarget isEqualToString:@"none"]) {
                // target aggregation happens in ApplyVIPVisualSweep; this helper only applies.
            }
        }
    }
    (void)tag;
    return applied;
}

static int ApplyWaitRoomRoleIcons(uint32_t localRole, int32_t level, bool captureOriginal, int32_t &matched) {
    return ApplyNestedRoleIconClass(gVIPB.waitRoomCellClass, gVIPB.waitRoomCellData, gVIPB.roomPlayerDataRoleId,
                                    gVIPB.waitRoomCellVipIcon, localRole, level, captureOriginal, matched);
}

static int ApplyIslandRoleIcons(uint32_t localRole, int32_t level, bool captureOriginal, int32_t &matched) {
    return ApplyNestedRoleIconClass(gVIPB.islandPlayerInfoClass, gVIPB.islandPlayerData, gVIPB.roomPlayerDataRoleId,
                                    gVIPB.islandPlayerVipIcon, localRole, level, captureOriginal, matched);
}

static Il2CppObject *LocalRoomPlayerObject() {
    if (!gSkinBindingsReady || !gAPI.field_static_get_value || !gSkinB.appRoomModule) return nullptr;
    Il2CppObject *roomModule = nullptr;
    gAPI.field_static_get_value(gSkinB.appRoomModule, &roomModule);
    if (!roomModule) return nullptr;
    if (gSkinB.roomGetRoom && gSkinB.roomBaseGetLocalPlayer) {
        Il2CppObject *room = nullptr;
        if (InvokeRaw(gSkinB.roomGetRoom, roomModule, nullptr, &room) && room) {
            Il2CppObject *roomPlayer = nullptr;
            if (InvokeRaw(gSkinB.roomBaseGetLocalPlayer, room, nullptr, &roomPlayer) && roomPlayer) return roomPlayer;
        }
    }
    if (gSkinB.roomGetRoomPlayer) {
        Il2CppObject *roomPlayer = nullptr;
        if (InvokeRaw(gSkinB.roomGetRoomPlayer, roomModule, nullptr, &roomPlayer) && roomPlayer) return roomPlayer;
    }
    return nullptr;
}

static Il2CppObject *LocalDancerObject() {
    if (!gAppDanceModuleField || !gDanceGetLogic || !gSkinB.baseDanceGetPlayer || !gAPI.field_static_get_value) return nullptr;
    Il2CppObject *danceModule = nullptr;
    gAPI.field_static_get_value(gAppDanceModuleField, &danceModule);
    if (!danceModule) return nullptr;
    Il2CppObject *dance = nullptr;
    if (!InvokeRaw(gDanceGetLogic, danceModule, nullptr, &dance) || !dance) return nullptr;
    Il2CppObject *dancer = nullptr;
    if (!InvokeRaw(gSkinB.baseDanceGetPlayer, dance, nullptr, &dancer) || !dancer) return nullptr;
    return dancer;
}

static bool StartLocalBillboardVip(Il2CppObject *top, int32_t level) {
    if (!top || !gVIPB.billboardShowVip || !gVIPB.startCoroutine) return false;
    int32_t requested = level;
    uint8_t hideVIP = 0;
    void *showArgs[2] = { &requested, &hideVIP };
    Il2CppObject *routine = nullptr;
    if (!InvokeRaw(gVIPB.billboardShowVip, top, showArgs, &routine) || !routine) return false;
    void *startArgs[1] = { routine };
    return InvokeRaw(gVIPB.startCoroutine, top, startArgs, nullptr);
}

static int ApplyLocalTop(Il2CppObject *top, int32_t level, bool captureOriginal,
                         NSString *source, NSMutableString *targets,
                         int32_t &directMatches, int32_t &spawnQueued) {
    if (!top) return 0;
    directMatches++;
    Il2CppObject *icon = nullptr;
    if (ReadField(top, gVIPB.billboardVipIcon, icon) && icon) {
        if (SetVIPIconVisual(icon, level, captureOriginal)) {
            if (targets.length) [targets appendString:@","];
            [targets appendString:source ?: @"local-top"];
            return 1;
        }
        return 0;
    }

    // A true VIP 0 account normally has no UI_VIPIcon at all. Ask the game's own
    // CharacterTop presentation coroutine to construct it locally, then re-read in
    // case StartCoroutine executed the creation before its first yield.
    if (StartLocalBillboardVip(top, level)) {
        spawnQueued++;
        icon = nullptr;
        if (ReadField(top, gVIPB.billboardVipIcon, icon) && icon && SetVIPIconVisual(icon, level, captureOriginal)) {
            if (targets.length) [targets appendString:@","];
            [targets appendFormat:@"%@-spawned", source ?: @"local-top"];
            return 1;
        }
    }
    return 0;
}

static int ApplyDirectLocalTopIcons(int32_t level, bool captureOriginal, NSMutableString *targets,
                                    int32_t &directMatches, int32_t &spawnQueued) {
    int applied = 0;
    Il2CppObject *seen[3] = { nullptr, nullptr, nullptr };
    int seenCount = 0;
    auto applyUnique = [&](Il2CppObject *top, NSString *source) {
        if (!top) return;
        for (int i = 0; i < seenCount; i++) if (seen[i] == top) return;
        if (seenCount < 3) seen[seenCount++] = top;
        applied += ApplyLocalTop(top, level, captureOriginal, source, targets, directMatches, spawnQueued);
    };

    Il2CppObject *roomPlayer = LocalRoomPlayerObject();
    if (roomPlayer) {
        Il2CppObject *top = nullptr;
        if (gVIPB.roomPlayerCharacterTopUI && ReadField(roomPlayer, gVIPB.roomPlayerCharacterTopUI, top))
            applyUnique(top, @"room-local-top");
        top = nullptr;
        if (gVIPB.roomPlayerTopUI && ReadField(roomPlayer, gVIPB.roomPlayerTopUI, top))
            applyUnique(top, @"room-local-top2");
    }

    Il2CppObject *dancer = LocalDancerObject();
    if (dancer && gVIPB.dancerPlayerTopUI) {
        Il2CppObject *top = nullptr;
        if (ReadField(dancer, gVIPB.dancerPlayerTopUI, top)) applyUnique(top, @"dance-local-top");
    }
    return applied;
}

static int ApplyVIPVisualSweep(int32_t level, bool captureOriginal, NSString *reason) {
    if (!BindGame() || !gVIPBindingsReady) return 0;
    if (level < 0 || level > 100) return 0;

    uint32_t localRole = 0;
    int32_t trueVipLevel = -1;
    NSString *localName = nil;
    ReadLocalVIPIdentity(localRole, trueVipLevel, &localName);
    if (captureOriginal && gVIPOriginalLevel < 0 && trueVipLevel >= 0 && trueVipLevel <= 100)
        gVIPOriginalLevel = trueVipLevel;

    // Fallback identity only if the account-level RoleInfo is not ready yet.
    if (!localRole) localRole = gSkinLastRoleId;
    if (!localRole && gSkinBindingsReady && gSkinB.playerGetRoleId) {
        Il2CppObject *player = ActiveSkinPlayer(nullptr);
        if (player) InvokeUInt32(gSkinB.playerGetRoleId, player, nullptr, localRole);
    }
    gVIPLastLocalRole = localRole;
    gVIPLastTrueLevel = trueVipLevel;

    int applied = 0;
    int billboardMatches = 0;
    int playerHeadCount = 0;
    int playerHeadNameMatches = 0;
    int islandMatches = 0;
    int vipIconCount = 0;
    int directTopMatches = 0;
    int spawnQueued = 0;
    NSMutableString *targets = [NSMutableString string];

    // V10.25 preferred path: local RoomPlayer/DancerController owns its CharacterTop
    // directly. For trueVip=0, this path can create the normal local VIP icon via
    // ShowVip coroutine instead of waiting for an icon that never existed.
    applied += ApplyDirectLocalTopIcons(level, captureOriginal, targets, directTopMatches, spawnQueued);

    Il2CppObject *billboards = FindObjectsForClass(gVIPB.billboardClass);
    int32_t billboardCount = ManagedArrayLength(billboards);
    if (billboardCount > 0 && localRole) {
        for (int32_t i = 0; i < billboardCount; i++) {
            Il2CppObject *top = ManagedArrayItem(billboards, i);
            if (!top) continue;
            uint32_t role = 0;
            if (!ReadField(top, gVIPB.billboardRoleId, role) || role != localRole) continue;
            Il2CppObject *icon = nullptr;
            if (!ReadField(top, gVIPB.billboardVipIcon, icon) || !icon) continue;
            billboardMatches++;
            if (SetVIPIconVisual(icon, level, captureOriginal)) {
                applied++;
                if (targets.length) [targets appendString:@","];
                [targets appendString:@"self-billboard"];
            }
        }
    }

    // V10.20 role-aware room/rank cells. These widgets already own a UI_VIPIcon and
    // a role identifier, so matching the current ClientPlayer role is unambiguous.
    int32_t roleAwareMatches = 0;
    int waitApplied = ApplyWaitRoomRoleIcons(localRole, level, captureOriginal, roleAwareMatches);
    if (waitApplied > 0) {
        applied += waitApplied;
        if (targets.length) [targets appendString:@","];
        [targets appendString:@"wait-room-self"];
    }
    int islandApplied = ApplyIslandRoleIcons(localRole, level, captureOriginal, islandMatches);
    if (islandApplied > 0) {
        applied += islandApplied;
        roleAwareMatches += islandMatches;
        if (targets.length) [targets appendString:@","];
        [targets appendString:@"dream-island-self"];
    }
    int roomApplied = ApplyDirectRoleIconClass(gVIPB.roomPlayerInfoCellClass, gVIPB.roomPlayerInfoRoleId,
                                               gVIPB.roomPlayerInfoVipIcon, localRole, level, captureOriginal,
                                               @"room-player-info", roleAwareMatches);
    if (roomApplied > 0) {
        applied += roomApplied;
        if (targets.length) [targets appendString:@","];
        [targets appendString:@"room-player-self"];
    }
    int dgApplied = ApplyDirectRoleIconClass(gVIPB.dgPlayerInfoCellClass, gVIPB.dgPlayerInfoRoleId,
                                             gVIPB.dgPlayerInfoVipIcon, localRole, level, captureOriginal,
                                             @"dg-player-info", roleAwareMatches);
    if (dgApplied > 0) {
        applied += dgApplied;
        if (targets.length) [targets appendString:@","];
        [targets appendString:@"dance-group-self"];
    }
    int rankApplied = ApplyDirectRoleIconClass(gVIPB.rankPlayerCellClass, gVIPB.rankPlayerRoleId,
                                               gVIPB.rankPlayerVipIcon, localRole, level, captureOriginal,
                                               @"rank-player", roleAwareMatches);
    if (rankApplied > 0) {
        applied += rankApplied;
        if (targets.length) [targets appendString:@","];
        [targets appendString:@"rank-self"];
    }
    gVIPLastRoleAwareMatches = roleAwareMatches;

    // V10.24: UI_PlayerHead has no roleId field, so bind it to the local account by
    // the rendered role name instead of relying on "exactly one head exists". Runtime
    // logs showed three heads at once; the old unique-head/unique-icon fallback could
    // therefore either skip the local head or report RUNNING for an unrelated icon.
    int headApplied = ApplyNamedPlayerHeadIcons(localName, level, captureOriginal, playerHeadNameMatches, playerHeadCount);
    if (headApplied > 0) {
        applied += headApplied;
        if (targets.length) [targets appendString:@","];
        [targets appendString:@"self-player-head-name"];
    }

    // Count global VIP icons for diagnostics only. V10.24 deliberately never treats a
    // scene-wide unique icon as a safe self target because the V10.23 device trace proved
    // that this heuristic can produce a false success while no role-aware target matches.
    Il2CppObject *icons = FindObjectsForClass(gVIPB.vipIconClass);
    int32_t iconCount = ManagedArrayLength(icons);
    vipIconCount = iconCount > 0 ? iconCount : 0;

    gVIPLastBillboardMatches = billboardMatches;
    gVIPLastPlayerHeadCount = playerHeadCount;
    gVIPLastHeadNameMatches = playerHeadNameMatches;
    gVIPLastIslandMatches = islandMatches;
    gVIPLastDirectTopMatches = directTopMatches;
    gVIPLastSpawnQueued = spawnQueued;
    gVIPLastIconCount = vipIconCount;
    gVIPLastAppliedCount = applied;
    gVIPLastTarget = targets.length ? [targets copy] : @"none";
    if (applied > 0) {
        CFTimeInterval now = CACurrentMediaTime();
        BOOL important = ![reason isEqualToString:@"VIP_VISUAL_REFRESH"] || gVIPLastEmittedLevel != level ||
                         ![gVIPLastEmittedTarget isEqualToString:gVIPLastTarget] || (now - gVIPLastEmitAt) >= 6.0;
        if (important) {
            gVIPLastEmitAt = now;
            gVIPLastEmittedLevel = level;
            gVIPLastEmittedTarget = [gVIPLastTarget copy];
            VIPEmit(@"RUNNING", reason ?: @"VIP_VISUAL_APPLIED",
                    [NSString stringWithFormat:@"level=%d original=%ld trueVip=%ld localRole=%u localName=%@ targets=%@ applied=%d directTop=%d spawnQueued=%d billboardMatches=%d roleAwareMatches=%d islandMatches=%d playerHeads=%d headNameMatches=%d vipIcons=%d localOnly=1 serverState=0",
                     level, (long)gVIPOriginalLevel, (long)gVIPLastTrueLevel, localRole, localName ?: @"-", gVIPLastTarget, applied, directTopMatches, spawnQueued, billboardMatches, gVIPLastRoleAwareMatches, islandMatches, playerHeadCount, playerHeadNameMatches, vipIconCount]);
        } else {
            gVIPStatus = [NSString stringWithFormat:@"RUNNING • VIP %d • %@", level, gVIPLastTarget ?: @"none"];
        }
    }
    return applied;
}

static void StartVIPTimer() {
    if (gVIPTimer) return;
    gVIPTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gVIPTimer, dispatch_time(DISPATCH_TIME_NOW, 0), (uint64_t)1000000000ULL, (uint64_t)100000000ULL);
    dispatch_source_set_event_handler(gVIPTimer, ^{
        if (gVIPRequestedLevel < 0) return;
        int applied = ApplyVIPVisualSweep((int32_t)gVIPRequestedLevel, true, @"VIP_VISUAL_REFRESH");
        if (applied == 0) {
            gVIPStatus = gVIPLastSpawnQueued > 0 ? @"WAIT_PREREQ • VIP_ICON_SPAWN_QUEUED" : @"WAIT_PREREQ • VIP_UI_TARGET_QUEUED";
            CFTimeInterval now = CACurrentMediaTime();
            if ((now - gVIPLastWaitEmitAt) >= 4.0) {
                gVIPLastWaitEmitAt = now;
                VIPEmit(@"WAIT_PREREQ", gVIPLastSpawnQueued > 0 ? @"VIP_ICON_SPAWN_QUEUED" : @"VIP_UI_TARGET_STILL_WAITING",
                        [NSString stringWithFormat:@"level=%ld localRole=%u trueVip=%ld directTop=%d spawnQueued=%d billboards=%d roleAware=%d island=%d playerHeads=%d headNameMatches=%d vipIcons=%d localOnly=1 serverState=0",
                         (long)gVIPRequestedLevel, gVIPLastLocalRole, (long)gVIPLastTrueLevel, gVIPLastDirectTopMatches, gVIPLastSpawnQueued,
                         gVIPLastBillboardMatches, gVIPLastRoleAwareMatches, gVIPLastIslandMatches, gVIPLastPlayerHeadCount, gVIPLastHeadNameMatches, gVIPLastIconCount]);
            }
        }
    });
    dispatch_resume(gVIPTimer);
}

static NSString *HeadCatalogNameAt(NSArray<NSDictionary *> *catalog, NSInteger index, NSString *fallback) {
    if (index >= 0 && index < (NSInteger)catalog.count) {
        NSString *name = catalog[(NSUInteger)index][@"name"];
        if (name.length) return name;
    }
    return fallback ?: @"-";
}

static NSArray<NSDictionary *> *BuildHeadNameEffectCatalog() {
    if (gHeadNameEffectCatalog) return gHeadNameEffectCatalog;
    gHeadNameEffectCatalog = [NSMutableArray arrayWithObject:@{ @"id": @(0), @"name": @"Bình thường" }];
    if (!BindGame() || !gVIPB.configPersonalNameGetSingleton || !gVIPB.configPersonalNameArray ||
        !gVIPB.personalNameItemID || !gVIPB.personalNameNameID || !gSkinB.configGetSingleton ||
        !gSkinB.configGetItem || !gSkinB.itemGetName) {
        return gHeadNameEffectCatalog;
    }

    Il2CppObject *personalCfg = nullptr;
    if (!InvokeRaw(gVIPB.configPersonalNameGetSingleton, nullptr, nullptr, &personalCfg) || !personalCfg) return gHeadNameEffectCatalog;
    Il2CppObject *personalArray = nullptr;
    if (!ReadField(personalCfg, gVIPB.configPersonalNameArray, personalArray) || !personalArray) return gHeadNameEffectCatalog;

    Il2CppObject *itemCfg = nullptr;
    InvokeRaw(gSkinB.configGetSingleton, nullptr, nullptr, &itemCfg);
    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
    [seen addObject:[NSNumber numberWithUnsignedInt:0]];
    int32_t count = ManagedArrayLength(personalArray);
    for (int32_t i = 0; i < count; i++) {
        Il2CppObject *entry = ManagedArrayItem(personalArray, i);
        if (!entry) continue;
        uint32_t itemID = 0;
        uint32_t nameID = 0;
        if (!ReadField(entry, gVIPB.personalNameItemID, itemID) || !ReadField(entry, gVIPB.personalNameNameID, nameID) || !nameID) continue;
        NSNumber *dedupe = @(nameID);
        if ([seen containsObject:dedupe]) continue;
        [seen addObject:dedupe];
        NSString *name = nil;
        if (itemCfg) {
            void *args[1] = { &itemID };
            Il2CppObject *item = nullptr;
            if (InvokeRaw(gSkinB.configGetItem, itemCfg, args, &item) && item) {
                Il2CppObject *nameObj = nullptr;
                if (InvokeRaw(gSkinB.itemGetName, item, nullptr, &nameObj) && nameObj) name = ManagedString(nameObj);
            }
        }
        if (name.length == 0) name = [NSString stringWithFormat:@"Hiệu ứng %u", nameID];
        [gHeadNameEffectCatalog addObject:@{ @"id": @(nameID), @"name": name }];
    }
    return gHeadNameEffectCatalog;
}

static NSArray<NSDictionary *> *BuildHeadTitleCatalog() {
    if (gHeadTitleCatalog) return gHeadTitleCatalog;
    gHeadTitleCatalog = [NSMutableArray arrayWithObject:@{ @"id": @(0), @"name": @"Không chọn" }];
    if (!BindGame() || !gVIPB.configTitleGetSingleton || !gVIPB.configTitleArray || !gVIPB.titleID || !gVIPB.titleGetName)
        return gHeadTitleCatalog;

    Il2CppObject *cfg = nullptr;
    if (!InvokeRaw(gVIPB.configTitleGetSingleton, nullptr, nullptr, &cfg) || !cfg) return gHeadTitleCatalog;
    Il2CppObject *array = nullptr;
    if (!ReadField(cfg, gVIPB.configTitleArray, array) || !array) return gHeadTitleCatalog;

    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
    [seen addObject:[NSNumber numberWithUnsignedInt:0]];
    int32_t count = ManagedArrayLength(array);
    for (int32_t i = 0; i < count; i++) {
        Il2CppObject *entry = ManagedArrayItem(array, i);
        if (!entry) continue;
        uint32_t titleID = 0;
        if (!ReadField(entry, gVIPB.titleID, titleID) || !titleID) continue;
        NSNumber *dedupe = @(titleID);
        if ([seen containsObject:dedupe]) continue;
        [seen addObject:dedupe];
        NSString *name = nil;
        Il2CppObject *nameObj = nullptr;
        if (InvokeRaw(gVIPB.titleGetName, entry, nullptr, &nameObj) && nameObj) name = ManagedString(nameObj);
        if (name.length == 0) name = [NSString stringWithFormat:@"Danh hiệu %u", titleID];
        BOOL hasStaticFx = NO;
        BOOL hasDynamicFx = NO;
        Il2CppObject *strObj = nullptr;
        if (ReadField(entry, gVIPB.titleStaticEffect, strObj) && strObj) hasStaticFx = ManagedString(strObj).length > 0;
        strObj = nullptr;
        if (ReadField(entry, gVIPB.titleDynamicEffect, strObj) && strObj) hasDynamicFx = ManagedString(strObj).length > 0;
        NSString *label = name;
        if (hasStaticFx || hasDynamicFx) {
            NSMutableArray *parts = [NSMutableArray array];
            if (hasDynamicFx) [parts addObject:@"động"];
            if (hasStaticFx) [parts addObject:@"tĩnh"];
            label = [NSString stringWithFormat:@"%@ (%@)", name, [parts componentsJoinedByString:@"/"]];
        }
        [gHeadTitleCatalog addObject:@{ @"id": @(titleID), @"name": label }];
    }
    return gHeadTitleCatalog;
}

static NSArray<NSDictionary *> *BuildHeadRingCatalog() {
    if (gHeadRingCatalog) return gHeadRingCatalog;
    gHeadRingCatalog = [NSMutableArray arrayWithObject:@{ @"id": @(0), @"name": @"Không chọn" }];
    if (!BindGame() || !gVIPB.configMarryRingGetSingleton || !gVIPB.configMarryRingArray || !gVIPB.marryRingIndexID || !gVIPB.marryRingGetName)
        return gHeadRingCatalog;

    Il2CppObject *cfg = nullptr;
    if (!InvokeRaw(gVIPB.configMarryRingGetSingleton, nullptr, nullptr, &cfg) || !cfg) return gHeadRingCatalog;
    Il2CppObject *array = nullptr;
    if (!ReadField(cfg, gVIPB.configMarryRingArray, array) || !array) return gHeadRingCatalog;

    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
    [seen addObject:[NSNumber numberWithUnsignedInt:0]];
    int32_t count = ManagedArrayLength(array);
    for (int32_t i = 0; i < count; i++) {
        Il2CppObject *entry = ManagedArrayItem(array, i);
        if (!entry) continue;
        uint16_t ringIndex = 0;
        if (!ReadField(entry, gVIPB.marryRingIndexID, ringIndex) || !ringIndex) continue;
        NSNumber *dedupe = [NSNumber numberWithUnsignedInt:(unsigned int)ringIndex];
        if ([seen containsObject:dedupe]) continue;
        [seen addObject:dedupe];
        NSString *name = nil;
        Il2CppObject *nameObj = nullptr;
        if (InvokeRaw(gVIPB.marryRingGetName, entry, nullptr, &nameObj) && nameObj) name = ManagedString(nameObj);
        if (name.length == 0) name = [NSString stringWithFormat:@"Vòng %u", ringIndex];
        [gHeadRingCatalog addObject:@{ @"id": [NSNumber numberWithUnsignedInt:(unsigned int)ringIndex], @"name": name }];
    }
    return gHeadRingCatalog;
}

static void UpdateHeadStatusText() {
    NSArray<NSDictionary *> *nameCatalog = BuildHeadNameEffectCatalog();
    NSArray<NSDictionary *> *titleCatalog = BuildHeadTitleCatalog();
    NSArray<NSDictionary *> *ringCatalog = BuildHeadRingCatalog();
    if (gHeadNameEffectIndex <= 0 && gHeadTitleIndex <= 0 && gHeadRingIndex <= 0) {
        gHeadStatus = @"OFF • LOCAL_UI_ONLY";
        return;
    }
    gHeadStatus = [NSString stringWithFormat:@"RUNNING • Tên:%@ • Danh hiệu:%@ (%@) • Vòng:%@",
                   HeadCatalogNameAt(nameCatalog, gHeadNameEffectIndex, @"Bình thường"),
                   HeadCatalogNameAt(titleCatalog, gHeadTitleIndex, @"Không chọn"),
                   gHeadTitleDynamic ? @"Động" : @"Tĩnh",
                   HeadCatalogNameAt(ringCatalog, gHeadRingIndex, @"Không chọn")];
}

static bool ApplyHeadNameEffectToTop(Il2CppObject *top, uint32_t effectID) {
    if (!top || !gVIPB.billboardStartNameEffect) return false;
    if (gVIPB.billboardNameColorChange) WriteField(top, gVIPB.billboardNameColorChange, effectID);
    void *args[1] = { &effectID };
    return InvokeRaw(gVIPB.billboardStartNameEffect, top, args, nullptr);
}

static bool ApplyHeadTitleToTop(Il2CppObject *top, uint32_t titleID, BOOL dynamicEffect) {
    if (!top) return false;
    bool ok = false;
    if (titleID == 0) {
        if (gVIPB.billboardClearEffectTitle) InvokeRaw(gVIPB.billboardClearEffectTitle, top, nullptr, nullptr);
        if (gVIPB.billboardSetEffectTitleState) {
            BOOL off = NO;
            void *toggleArgs[1] = { &off };
            InvokeRaw(gVIPB.billboardSetEffectTitleState, top, toggleArgs, nullptr);
        }
        return true;
    }
    if (gVIPB.billboardShowTitle && gVIPB.characterTopParamClass && gVIPB.paramTitleId && gAPI.object_new) {
        Il2CppObject *param = gAPI.object_new(gVIPB.characterTopParamClass);
        if (param) {
            WriteField(param, gVIPB.paramTitleId, titleID);
            void *showArgs[1] = { param };
            ok = InvokeRaw(gVIPB.billboardShowTitle, top, showArgs, nullptr);
        }
    }
    if (gVIPB.billboardSetEffectTitleState) {
        BOOL on = dynamicEffect ? YES : NO;
        void *toggleArgs[1] = { &on };
        InvokeRaw(gVIPB.billboardSetEffectTitleState, top, toggleArgs, nullptr);
        ok = true;
    }
    return ok;
}

static bool ApplyHeadRingToTop(Il2CppObject *top, BOOL isWaitRoom, uint16_t ringID) {
    if (!top || !gVIPB.billboardShowRing) return false;
    BOOL room = isWaitRoom ? YES : NO;
    void *args[2] = { &room, &ringID };
    return InvokeRaw(gVIPB.billboardShowRing, top, args, nullptr);
}

static int ApplyHeadOverlaySweep(NSString *reason) {
    if (!BindGame() || !gVIPBindingsReady) return 0;
    NSArray<NSDictionary *> *nameCatalog = BuildHeadNameEffectCatalog();
    NSArray<NSDictionary *> *titleCatalog = BuildHeadTitleCatalog();
    NSArray<NSDictionary *> *ringCatalog = BuildHeadRingCatalog();

    uint32_t effectID = 0;
    if (gHeadNameEffectIndex > 0 && gHeadNameEffectIndex < (NSInteger)nameCatalog.count)
        effectID = [nameCatalog[(NSUInteger)gHeadNameEffectIndex][@"id"] unsignedIntValue];
    uint32_t titleID = 0;
    if (gHeadTitleIndex > 0 && gHeadTitleIndex < (NSInteger)titleCatalog.count)
        titleID = [titleCatalog[(NSUInteger)gHeadTitleIndex][@"id"] unsignedIntValue];
    uint16_t ringID = 0;
    if (gHeadRingIndex > 0 && gHeadRingIndex < (NSInteger)ringCatalog.count)
        ringID = (uint16_t)[ringCatalog[(NSUInteger)gHeadRingIndex][@"id"] unsignedIntValue];

    int applied = 0;
    Il2CppObject *seen[3] = { nullptr, nullptr, nullptr };
    int seenCount = 0;
    auto applyUnique = [&](Il2CppObject *top, BOOL isWaitRoom) {
        if (!top) return;
        for (int i = 0; i < seenCount; i++) if (seen[i] == top) return;
        if (seenCount < 3) seen[seenCount++] = top;
        bool touched = false;
        if (gHeadNameEffectIndex >= 0) touched = ApplyHeadNameEffectToTop(top, effectID) || touched;
        if (gHeadTitleIndex >= 0) touched = ApplyHeadTitleToTop(top, titleID, gHeadTitleDynamic) || touched;
        if (gHeadRingIndex >= 0) touched = ApplyHeadRingToTop(top, isWaitRoom, ringID) || touched;
        if (touched) applied++;
    };

    Il2CppObject *roomPlayer = LocalRoomPlayerObject();
    if (roomPlayer) {
        Il2CppObject *top = nullptr;
        if (gVIPB.roomPlayerCharacterTopUI && ReadField(roomPlayer, gVIPB.roomPlayerCharacterTopUI, top)) applyUnique(top, YES);
        top = nullptr;
        if (gVIPB.roomPlayerTopUI && ReadField(roomPlayer, gVIPB.roomPlayerTopUI, top)) applyUnique(top, YES);
    }
    Il2CppObject *dancer = LocalDancerObject();
    if (dancer && gVIPB.dancerPlayerTopUI) {
        Il2CppObject *top = nullptr;
        if (ReadField(dancer, gVIPB.dancerPlayerTopUI, top)) applyUnique(top, NO);
    }

    UpdateHeadStatusText();
    if (applied > 0 && reason.length) {
        DiagRecord(@"HeadFX", @"ACTION", @"RUNNING", reason,
                   [NSString stringWithFormat:@"effect=%u title=%u dynamic=%d ring=%u targets=%d localOnly=1", effectID, titleID, gHeadTitleDynamic ? 1 : 0, ringID, applied]);
    } else if (applied == 0) {
        gHeadStatus = @"WAIT_PREREQ • SELF_TOP_NOT_READY";
    }
    return applied;
}

static void StartHeadTimer() {
    if (gHeadTimer) return;
    gHeadTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gHeadTimer, dispatch_time(DISPATCH_TIME_NOW, 0), (uint64_t)1000000000ULL, (uint64_t)100000000ULL);
    dispatch_source_set_event_handler(gHeadTimer, ^{
        if (gHeadNameEffectIndex <= 0 && gHeadTitleIndex <= 0 && gHeadRingIndex <= 0) return;
        ApplyHeadOverlaySweep(@"HEADFX_REFRESH");
    });
    dispatch_resume(gHeadTimer);
}

static bool ApplySkinIDs(Il2CppObject *player, NSArray<NSNumber *> *ids, bool replaceAll, NSString *reason) {
    if (!player || ids.count == 0) return false;
    Il2CppObject *list = CreateUIntList(ids);
    if (!list) {
        SkinEmit(@"FAULT", @"UINT_LIST_CREATE_FAILED");
        return false;
    }
    const MethodInfo *method = replaceAll ? gSkinB.playerChangeAll : gSkinB.playerLoadAndPutOn;
    if (!method) return false;
    void *args[1] = { list };
    bool ok = InvokeRaw(method, player, args, nullptr);
    SkinEmit(ok ? @"RUNNING" : @"FAULT", ok ? reason : @"COSTUME_INVOKE_FAILED",
             [NSString stringWithFormat:@"player=%p target=%@ replaceAll=%d ids=%@ localOnly=1", player, gSkinLastTargetSource ?: @"unknown", replaceAll ? 1 : 0, ids]);
    return ok;
}

static NSArray<NSDictionary *> *BuildSkinCatalog() {
    if (gSkinCatalog) return gSkinCatalog;
    gSkinCatalog = [NSMutableArray array];
    if (!BindGame() || !gSkinBindingsReady) {
        SkinEmit(@"WAIT_PREREQ", @"SKIN_BINDINGS_NOT_READY");
        gSkinCatalog = nil;
        return @[];
    }
    Il2CppObject *config = nullptr;
    if (!InvokeRaw(gSkinB.configGetSingleton, nullptr, nullptr, &config) || !config) {
        SkinEmit(@"WAIT_PREREQ", @"CONFIG_T_ITEM_NOT_READY");
        gSkinCatalog = nil;
        return @[];
    }
    Il2CppObject *array = nullptr;
    if (!ReadField(config, gSkinB.configItemArray, array) || !array) {
        SkinEmit(@"WAIT_PREREQ", @"CONFIG_ITEM_ARRAY_NOT_READY");
        gSkinCatalog = nil;
        return @[];
    }
    int32_t count = ManagedArrayLength(array);
    if (count <= 0) return gSkinCatalog;
    for (int32_t i = 0; i < count; i++) {
        Il2CppObject *item = ManagedArrayItem(array, i);
        if (!item) continue;
        uint32_t itemID = 0;
        uint16_t type1 = 0xffff, type2 = 0xffff, sexNeed = 2;
        if (!ReadField(item, gSkinB.itemID, itemID) || itemID == 0) continue;
        if (!ReadField(item, gSkinB.itemType1, type1) || type1 != 0) continue; // Equip only.
        if (!ReadField(item, gSkinB.itemType2, type2) || type2 > 32 || type2 == 4 || type2 == 22) continue;
        ReadField(item, gSkinB.itemSexNeed, sexNeed);
        Il2CppObject *nameObj = nullptr;
        NSString *name = nil;
        if (InvokeRaw(gSkinB.itemGetName, item, nullptr, &nameObj)) name = ManagedString(nameObj);
        if (name.length == 0) name = [NSString stringWithFormat:@"Item #%u", itemID];
        [gSkinCatalog addObject:@{@"id": @(itemID), @"name": name, @"type": @((int32_t)type2), @"sex": @((int32_t)sexNeed)}];
    }
    SkinEmit(@"READY", @"CATALOG_READY", [NSString stringWithFormat:@"count=%lu", (unsigned long)gSkinCatalog.count]);
    return gSkinCatalog;
}

static NSArray<NSDictionary *> *SearchSkinCatalog(int32_t type, NSString *query, NSUInteger limit) {
    NSArray<NSDictionary *> *catalog = BuildSkinCatalog();
    if (!catalog.count) return @[];
    uint8_t playerSex = 2;
    ActiveSkinPlayer(&playerSex);
    NSString *q = [[query ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (NSDictionary *entry in catalog) {
        int32_t itemType = [entry[@"type"] intValue];
        int32_t sex = [entry[@"sex"] intValue];
        if (type >= 0 && itemType != type) continue;
        if (playerSex <= 1 && sex != 2 && sex != playerSex) continue;
        NSString *name = entry[@"name"] ?: @"";
        if (q.length && [[name lowercaseString] rangeOfString:q].location == NSNotFound) continue;
        [out addObject:entry];
        if (out.count >= MAX((NSUInteger)1, limit)) break;
    }
    SkinEmit(@"READY", @"SEARCH_COMPLETE", [NSString stringWithFormat:@"type=%d query=%@ results=%lu sex=%u", type, q, (unsigned long)out.count, playerSex]);
    return out;
}

static NSArray<NSNumber *> *OriginSkinIDs(Il2CppObject *player) {
    if (!player || !gSkinB.playerGetOriginEquip || !gSkinB.equipItemID) return @[];
    NSMutableArray<NSNumber *> *ids = [NSMutableArray array];
    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
    for (int32_t type = 0; type <= 32; type++) {
        if (type == 4 || type == 22) continue;
        uint8_t t = (uint8_t)type;
        void *args[1] = { &t };
        Il2CppObject *equip = nullptr;
        if (!InvokeRaw(gSkinB.playerGetOriginEquip, player, args, &equip) || !equip) continue;
        uint32_t itemID = 0;
        if (!ReadField(equip, gSkinB.equipItemID, itemID) || !itemID) continue;
        NSNumber *boxed = @(itemID);
        if ([seen containsObject:boxed]) continue;
        [seen addObject:boxed];
        [ids addObject:boxed];
    }
    return ids;
}

static NSArray<NSNumber *> *PinnedSkinIDs() {
    NSMutableArray<NSNumber *> *ids = [NSMutableArray array];
    if (!gSkinPinnedByType.count) return ids;
    // Dictionary allValues order is not stable. Apply in slot order so the same
    // selection always reaches Player.LoadAndPutOnCostume in the same order.
    for (int32_t type = 0; type <= 32; type++) {
        NSNumber *item = gSkinPinnedByType[@(type)];
        if (item && item.unsignedIntValue != 0) [ids addObject:item];
    }
    return ids;
}

static void SetPinnedSkinSelection(int32_t category, uint32_t itemID) {
    if (!gSkinPinnedByType) gSkinPinnedByType = [NSMutableDictionary dictionary];

    // AllBody(6) is mutually exclusive with Coat(1), Pants(2) and UpBody(5).
    // Keeping both families pinned makes later re-apply order fight itself and is
    // the main reason a full-body set can appear and then disappear.
    bool choosingAllBody = category == 6;
    bool choosingSplitBody = category == 1 || category == 2 || category == 5;
    if (choosingAllBody || choosingSplitBody) {
        NSMutableDictionary<NSNumber *, NSNumber *> *normalized = [NSMutableDictionary dictionary];
        for (int32_t type = 0; type <= 32; type++) {
            NSNumber *existing = gSkinPinnedByType[@(type)];
            if (!existing) continue;
            if (choosingAllBody && (type == 1 || type == 2 || type == 5 || type == 6)) continue;
            if (choosingSplitBody && type == 6) continue;
            normalized[@(type)] = existing;
        }
        gSkinPinnedByType = normalized;
    }
    gSkinPinnedByType[@(category)] = @(itemID);
}

static bool PinnedSkinStateMatches(Il2CppObject *player, int32_t &missingType, uint32_t &missingItem) {
    missingType = -1;
    missingItem = 0;
    if (!player || !gSkinB.playerIsPuton || !gSkinPinnedByType.count) return false;
    for (int32_t type = 0; type <= 32; type++) {
        NSNumber *boxed = gSkinPinnedByType[@(type)];
        if (!boxed) continue;
        uint32_t itemID = boxed.unsignedIntValue;
        if (!itemID) continue;
        uint8_t clothType = (uint8_t)type;
        void *args[2] = { &clothType, &itemID };
        bool active = false;
        if (!InvokeBool(gSkinB.playerIsPuton, player, args, active) || !active) {
            missingType = type;
            missingItem = itemID;
            return false;
        }
    }
    return true;
}

static void SkinPinnedTick() {
    if (!gSkinPinnedByType.count || !gSkinBindingsReady) return;
    Il2CppObject *player = ActiveSkinPlayer(nullptr);
    if (!player) return;

    bool loaded = true;
    if (gSkinB.playerGetLoadComplete) InvokeBool(gSkinB.playerGetLoadComplete, player, nullptr, loaded);
    if (!loaded) return;

    bool sameTarget = player == CachedSkinPlayer();
    if (!gSkinPendingApply && sameTarget) {
        if (gSkinB.playerIsPuton) {
            int32_t missingType = -1;
            uint32_t missingItem = 0;
            if (PinnedSkinStateMatches(player, missingType, missingItem)) return;

            CFTimeInterval now = CACurrentMediaTime();
            if ((now - gSkinLastPinLostLogAt) >= 1.5) {
                gSkinLastPinLostLogAt = now;
                SkinEmit(@"WAIT_PREREQ", @"SKIN_PIN_LOST_REAPPLY",
                         [NSString stringWithFormat:@"type=%d item=%u allBody=%d player=%p target=%@",
                          missingType, missingItem, gSkinPinnedByType[@6] ? 1 : 0, player,
                          gSkinLastTargetSource ?: @"unknown"]);
            }
        } else {
            // Safe fallback for builds where IsPuton cannot be resolved: only keep
            // AllBody sticky, at a low cadence, rather than constantly reloading
            // every cosmetic slot.
            if (!gSkinPinnedByType[@6]) return;
            CFTimeInterval now = CACurrentMediaTime();
            if ((now - gSkinLastPinnedApplyAt) < 2.2) return;
        }
    }

    NSArray<NSNumber *> *ids = PinnedSkinIDs();
    NSString *reason = gSkinPendingApply ? @"QUEUED_SKIN_APPLIED" :
                       (sameTarget ? @"PIN_LOST_REAPPLIED" : @"PINNED_REAPPLIED");
    if (ApplySkinIDs(player, ids, false, reason)) {
        RememberSkinPlayer(player);
        gSkinPendingApply = NO;
        gSkinLastPinnedApplyAt = CACurrentMediaTime();
    }
}

static void StartSkinTimer() {
    if (gSkinTimer) return;
    gSkinTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gSkinTimer, dispatch_time(DISPATCH_TIME_NOW, 0), 700ull * NSEC_PER_MSEC, 80ull * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(gSkinTimer, ^{ SkinPinnedTick(); });
    dispatch_resume(gSkinTimer);
}

static bool ObjectAlive(Il2CppObject *obj) {
    if (!obj || !gB.objectImplicit) return false;
    void *args[1] = { obj };
    bool alive = false;
    return InvokeBool(gB.objectImplicit, nullptr, args, alive) && alive;
}

static void ProbeFlagState(Bindings &b, int32_t flag, bool &showing, bool &caching) {
    showing = false;
    caching = false;
    if (b.isUIShowing) {
        int32_t value = flag;
        void *args[1] = { &value };
        InvokeBool(b.isUIShowing, nullptr, args, showing);
    }
    if (b.isUICaching) {
        int32_t value = flag;
        void *args[1] = { &value };
        InvokeBool(b.isUICaching, nullptr, args, caching);
    }
}

struct UIFallbackMode {
    int32_t flag;
    int32_t mode;
};

// Fallback only when DanceModule.GetMode() is unavailable. Showing windows win
// over cached windows so stale UI cache cannot silently select an old dance mode.
static int32_t ProbeModeFromUIFlags(int32_t *flagOut) {
    if (flagOut) *flagOut = -1;
    const CFTimeInterval now = CACurrentMediaTime();
    if (now - gLastFallbackModeProbe < 0.45) {
        if (flagOut) *flagOut = gFallbackFlagCache;
        return gFallbackModeCache;
    }
    gLastFallbackModeProbe = now;

    static const UIFallbackMode candidates[] = {
        {487, 7},   // DanceBall dance window
        {364, 6},   // VOS
        {308, 5},   // Burst AU
        {282, 29},  // Taiko
        {172, 13},  // Track guide (newer guide flag)
        {171, 12},  // Dynamic guide
        {170, 11},  // Audition guide
        {169, 10},  // Bubble guide
        {75,  13},  // Track guide gameplay UI
        {74,  4},
        {73,  3},
        {72,  19},  // Challenge Witch / Spirit challenge UI family
        {71,  2},
        {70,  1},
    };

    int32_t cachedMode = -1;
    int32_t cachedFlag = -1;
    for (const auto &candidate : candidates) {
        bool showing = false, caching = false;
        ProbeFlagState(gClassicB, candidate.flag, showing, caching);
        if (showing) {
            gFallbackModeCache = candidate.mode;
            gFallbackFlagCache = candidate.flag;
            if (flagOut) *flagOut = candidate.flag;
            return candidate.mode;
        }
        if (cachedMode < 0 && caching) {
            cachedMode = candidate.mode;
            cachedFlag = candidate.flag;
        }
    }
    gFallbackModeCache = cachedMode;
    gFallbackFlagCache = cachedFlag;
    if (flagOut) *flagOut = cachedFlag;
    return cachedMode;
}

static int32_t ProbeResolvedMode(Il2CppObject **moduleOut, NSString **sourceOut, int32_t *flagOut) {
    if (sourceOut) *sourceOut = @"NONE";
    if (flagOut) *flagOut = -1;
    Il2CppObject *module = nullptr;
    int32_t mode = ProbeDanceMode(&module);
    if (moduleOut) *moduleOut = module;
    if (mode >= 0) {
        if (sourceOut) *sourceOut = @"DanceModule.GetMode";
        return mode;
    }

    int32_t fallbackFlag = -1;
    mode = ProbeModeFromUIFlags(&fallbackFlag);
    if (flagOut) *flagOut = fallbackFlag;
    if (mode >= 0 && sourceOut) *sourceOut = @"UIFlagFallback";
    return mode;
}

static void PublishModeDetection(int32_t mode, NSString *source, int32_t fallbackFlag, bool force = false) {
    NSString *safeSource = source.length ? source : @"NONE";
    const bool changed = (mode != gDetectedMode) || (fallbackFlag != gDetectedFallbackFlag) ||
                         ![safeSource isEqualToString:gDetectedModeSource ?: @""];
    const CFTimeInterval now = CACurrentMediaTime();
    if (!changed && !force && now - gLastModeHeartbeat < 3.0) return;

    gDetectedMode = mode;
    gDetectedFallbackFlag = fallbackFlag;
    gDetectedModeSource = [safeSource copy];
    gLastModeHeartbeat = now;

    const ModeDescriptor *d = ModeDescriptorFor(mode);
    NSString *state = (mode >= 0 && d && d->playable) ? @"READY" : (mode >= 0 ? @"WAIT_PREREQ" : @"WAIT_PREREQ");
    NSString *reason = changed ? @"MODE_DETECTED" : @"MODE_HEARTBEAT";
    Emit(@"MODE", state, reason,
         [NSString stringWithFormat:@"mode=%d name=%@ family=%@ source=%@ fallbackFlag=%d playable=%d",
          mode, ModeNameFor(mode), ModeFamilyFor(mode), safeSource, fallbackFlag,
          (d && d->playable) ? 1 : 0]);
}

static Il2CppObject *FindUIInstanceFor(Bindings &b, int32_t flag, NSString *profile, bool shouldDiag) {
    if (!b.uiClass) return nullptr;

    bool showing = false;
    bool caching = false;
    if (shouldDiag) ProbeFlagState(b, flag, showing, caching);

    if (b.getUIWnd) {
        if (shouldDiag) Emit(@"SOURCE", @"WAIT_PREREQ", @"GETUIWND_BEGIN",
                             [NSString stringWithFormat:@"profile=%@ flag=%d showing=%d caching=%d",
                              profile, flag, showing ? 1 : 0, caching ? 1 : 0]);
        int32_t value = flag;
        void *args[1] = { &value };
        Il2CppObject *ret = nullptr;
        bool ok = InvokeRaw(b.getUIWnd, nullptr, args, &ret);
        if (shouldDiag) Emit(@"SOURCE", @"WAIT_PREREQ", @"GETUIWND_RETURN",
                             [NSString stringWithFormat:@"profile=%@ flag=%d invoke=%d ptr=%p",
                              profile, flag, ok ? 1 : 0, ret]);
        if (ok && ret) {
            Il2CppClass *actual = gAPI.object_get_class ? gAPI.object_get_class(ret) : nullptr;
            if (actual == b.uiClass) return ret;
            if (shouldDiag) Emit(@"SOURCE", @"WAIT_PREREQ", @"UI_FLAG_CLASS_MISMATCH",
                                 [NSString stringWithFormat:@"profile=%@ flag=%d ptr=%p actual=%p expected=%p",
                                  profile, flag, ret, actual, b.uiClass]);
        }
    }

    if (b.findFirstObjectByTypeInactive) {
        const Il2CppType *type = gAPI.class_get_type(b.uiClass);
        Il2CppObject *typeObj = type ? gAPI.type_get_object(type) : nullptr;
        if (typeObj) {
            int32_t includeInactive = 1;
            void *args[2] = { typeObj, &includeInactive };
            Il2CppObject *ret = nullptr;
            if (shouldDiag) Emit(@"SOURCE", @"WAIT_PREREQ", @"FIND_FIRST_INACTIVE_BEGIN",
                                 [NSString stringWithFormat:@"profile=%@ flag=%d typeObj=%p include=%d",
                                  profile, flag, typeObj, includeInactive]);
            bool ok = InvokeRaw(b.findFirstObjectByTypeInactive, nullptr, args, &ret);
            if (shouldDiag) Emit(@"SOURCE", @"WAIT_PREREQ", @"FIND_FIRST_INACTIVE_RETURN",
                                 [NSString stringWithFormat:@"profile=%@ flag=%d invoke=%d ptr=%p",
                                  profile, flag, ok ? 1 : 0, ret]);
            if (ok && ret) {
                Il2CppClass *actual = gAPI.object_get_class ? gAPI.object_get_class(ret) : nullptr;
                if (actual == b.uiClass) return ret;
            }
        }
    }

    if (b.findObjectOfType) {
        const Il2CppType *type = gAPI.class_get_type(b.uiClass);
        Il2CppObject *typeObj = type ? gAPI.type_get_object(type) : nullptr;
        if (typeObj) {
            void *args[1] = { typeObj };
            Il2CppObject *ret = nullptr;
            if (shouldDiag) Emit(@"SOURCE", @"WAIT_PREREQ", @"FIND_ACTIVE_BEGIN",
                                 [NSString stringWithFormat:@"profile=%@ flag=%d typeObj=%p", profile, flag, typeObj]);
            bool ok = InvokeRaw(b.findObjectOfType, nullptr, args, &ret);
            if (shouldDiag) Emit(@"SOURCE", @"WAIT_PREREQ", @"FIND_ACTIVE_RETURN",
                                 [NSString stringWithFormat:@"profile=%@ flag=%d invoke=%d ptr=%p",
                                  profile, flag, ok ? 1 : 0, ret]);
            if (ok && ret) {
                Il2CppClass *actual = gAPI.object_get_class ? gAPI.object_get_class(ret) : nullptr;
                if (actual == b.uiClass) return ret;
            }
        }
    }

    if (shouldDiag) {
        Emit(@"SOURCE", @"WAIT_PREREQ", @"PROFILE_EMPTY",
             [NSString stringWithFormat:@"profile=%@ flag=%d showing=%d caching=%d",
              profile, flag, showing ? 1 : 0, caching ? 1 : 0]);
    }
    return nullptr;
}


static Il2CppObject *FindUIByClass(Il2CppClass *klass, int32_t flag, NSString *profile, bool diag = false) {
    if (!klass) return nullptr;
    Bindings &base = gClassicB.uiClass ? gClassicB : gBurstB;
    if (base.getUIWnd) {
        int32_t value = flag;
        void *args[1] = { &value };
        Il2CppObject *ret = nullptr;
        if (InvokeRaw(base.getUIWnd, nullptr, args, &ret) && ret) {
            Il2CppClass *actual = gAPI.object_get_class ? gAPI.object_get_class(ret) : nullptr;
            if (actual == klass) return ret;
        }
    }
    const Il2CppType *type = gAPI.class_get_type ? gAPI.class_get_type(klass) : nullptr;
    Il2CppObject *typeObj = (type && gAPI.type_get_object) ? gAPI.type_get_object(type) : nullptr;
    // V10.4: prefer the live active gameplay UI. Inactive-first could select a cached
    // Starlight/Idol/Peak instance whose curGroup is null, which made Dynamic/Crazy
    // look detected but never receive input.
    if (typeObj && base.findObjectOfType) {
        void *args[1] = { typeObj };
        Il2CppObject *ret = nullptr;
        if (InvokeRaw(base.findObjectOfType, nullptr, args, &ret) && ret) {
            Il2CppClass *actual = gAPI.object_get_class ? gAPI.object_get_class(ret) : nullptr;
            if (actual == klass) return ret;
        }
    }
    if (typeObj && base.findFirstObjectByTypeInactive) {
        int32_t includeInactive = 1;
        void *args[2] = { typeObj, &includeInactive };
        Il2CppObject *ret = nullptr;
        if (InvokeRaw(base.findFirstObjectByTypeInactive, nullptr, args, &ret) && ret) {
            Il2CppClass *actual = gAPI.object_get_class ? gAPI.object_get_class(ret) : nullptr;
            if (actual == klass) return ret;
        }
    }
    if (diag) Emit(@"SOURCE", @"WAIT_PREREQ", @"FULLMODE_UI_NOT_READY",
                   [NSString stringWithFormat:@"family=%@ flag=%d class=%p", profile ?: @"unknown", flag, klass]);
    return nullptr;
}

static FieldInfo *FieldFromObject(Il2CppObject *obj, const char *a, const char *b = nullptr) {
    if (!obj || !gAPI.object_get_class || !gAPI.class_get_field_from_name) return nullptr;
    Il2CppClass *klass = gAPI.object_get_class(obj);
    if (!klass) return nullptr;
    FieldInfo *f = a ? gAPI.class_get_field_from_name(klass, a) : nullptr;
    if (!f && b) f = gAPI.class_get_field_from_name(klass, b);
    return f;
}

static bool IsBubbleMode(int32_t mode) {
    return mode == 1 || mode == 10 || mode == 14 || mode == 18 || mode == 20 || mode == 24;
}
static bool IsAuditionMode(int32_t mode) {
    return mode == 2 || mode == 11 || mode == 15 || mode == 21 || mode == 25;
}
static bool IsDynamicMode(int32_t mode) {
    return mode == 3 || mode == 12 || mode == 16 || mode == 22 || mode == 26;
}
static bool IsTrackMode(int32_t mode) {
    return mode == 4 || mode == 13 || mode == 17 || mode == 23 || mode == 27;
}
static bool IsVOSMode(int32_t mode) { return mode == 6 || mode == 28; }

static bool RangePerfectReady(Il2CppObject *ranges, float time, float &startOut, float &endOut, float &targetOut) {
    if (!ranges || !gB.rangeRank || !gB.rangeStartTime || !gB.rangeEndTime || !gB.rangeIsInRange) return false;
    int32_t count = ListCount(ranges);
    if (count <= 0 || count > 64) return false;
    for (int32_t i = 0; i < count; i++) {
        Il2CppObject *range = ListItem(ranges, i);
        if (!range) continue;
        int32_t rank = -1;
        if (!ReadField(range, gB.rangeRank, rank) || rank != 4) continue;
        float start = 0.0f, end = 0.0f;
        if (!ReadField(range, gB.rangeStartTime, start) || !ReadField(range, gB.rangeEndTime, end)) continue;
        if (end < start) { float x = start; start = end; end = x; }
        float target = start + (end - start) * 0.5f;
        void *args[1] = { &time };
        bool inside = false;
        if (!InvokeBool(gB.rangeIsInRange, range, args, inside) || !inside) continue;
        startOut = start; endOut = end; targetOut = target;
        return time >= target;
    }
    return false;
}

// V10.2: some NoteJudgeRange.StartTime/EndTime values are local to a note/window,
// while controller/UI clocks are absolute song times. The runtime log proved that
// Audition was comparing ~6.99s directly with [0.725..0.775]. These helpers keep
// judgement in the game's own NoteJudgeRange but convert to the correct local domain.
static bool RangePerfectReadyWithBaseline(Il2CppObject *ranges, float rawTime, float baseline,
                                          float &startOut, float &endOut, float &targetOut,
                                          float &localOut) {
    if (!ranges || !gB.rangeRank || !gB.rangeStartTime || !gB.rangeEndTime || !gB.rangeIsInRange) return false;
    int32_t count = ListCount(ranges);
    if (count <= 0 || count > 64) return false;
    for (int32_t i = 0; i < count; i++) {
        Il2CppObject *range = ListItem(ranges, i);
        if (!range) continue;
        int32_t rank = -1;
        if (!ReadField(range, gB.rangeRank, rank) || rank != 4) continue;
        float start = 0.0f, end = 0.0f;
        if (!ReadField(range, gB.rangeStartTime, start) || !ReadField(range, gB.rangeEndTime, end)) continue;
        if (end < start) { float x = start; start = end; end = x; }
        float target = start + (end - start) * 0.5f;
        float local = rawTime - baseline;
        void *args[1] = { &local };
        bool inside = false;
        if (!InvokeBool(gB.rangeIsInRange, range, args, inside) || !inside) continue;
        startOut = start; endOut = end; targetOut = target; localOut = local;
        return local >= target;
    }
    return false;
}

static bool RangePerfectReadyCentered(Il2CppObject *ranges, float rawTime, float absoluteCenter,
                                      float &startOut, float &endOut, float &targetOut,
                                      float &localOut) {
    if (!ranges || !gB.rangeRank || !gB.rangeStartTime || !gB.rangeEndTime || !gB.rangeIsInRange) return false;
    int32_t count = ListCount(ranges);
    if (count <= 0 || count > 64) return false;
    for (int32_t i = 0; i < count; i++) {
        Il2CppObject *range = ListItem(ranges, i);
        if (!range) continue;
        int32_t rank = -1;
        if (!ReadField(range, gB.rangeRank, rank) || rank != 4) continue;
        float start = 0.0f, end = 0.0f;
        if (!ReadField(range, gB.rangeStartTime, start) || !ReadField(range, gB.rangeEndTime, end)) continue;
        if (end < start) { float x = start; start = end; end = x; }
        float target = start + (end - start) * 0.5f;
        float local = rawTime - absoluteCenter + target;
        void *args[1] = { &local };
        bool inside = false;
        if (!InvokeBool(gB.rangeIsInRange, range, args, inside) || !inside) continue;
        startOut = start; endOut = end; targetOut = target; localOut = local;
        return local >= target;
    }
    return false;
}

static bool ArrayInt32(Il2CppObject *array, int32_t index, int32_t &out) {
    Il2CppObject *boxed = ManagedArrayItem(array, index);
    if (!boxed || !gAPI.object_unbox) return false;
    void *p = gAPI.object_unbox(boxed);
    if (!p) return false;
    out = *reinterpret_cast<int32_t *>(p);
    return true;
}

static bool EnsureNativeAutoPlay(int slotIndex, int32_t mode, NSString *family,
                                 Il2CppObject *ctrl, Il2CppClass *expectedClass,
                                 FieldInfo *autoField, FieldInfo *comboField,
                                 FieldInfo *perfectField, FieldInfo *endField) {
    if (!ctrl || !autoField || slotIndex < 0 || slotIndex >= 3) return false;
    if (expectedClass && gAPI.object_get_class && gAPI.object_get_class(ctrl) != expectedClass) {
        Health(@"BLOCKED", @"AUTOPLAY_CONTROLLER_CLASS_MISMATCH",
               [NSString stringWithFormat:@"family=%@ mode=%d ctrl=%p", family, mode, ctrl]);
        return true;
    }
    AutoOwnedSlot &slot = gAutoSlots[slotIndex];
    uint8_t autoPlay = 0;
    ReadField(ctrl, autoField, autoPlay);
    if (slot.ctrl != ctrl || slot.field != autoField) {
        slot.ctrl = ctrl; slot.field = autoField; slot.previous = autoPlay; slot.owned = NO; slot.mode = mode;
        Emit(@"SOURCE", @"READY", @"FULLMODE_CONTROLLER_FOUND",
             [NSString stringWithFormat:@"family=%@ mode=%d ctrl=%p auto=%u", family, mode, ctrl, autoPlay]);
    }
    if (!autoPlay) {
        uint8_t one = 1;
        if (!WriteField(ctrl, autoField, one)) {
            Emit(@"FAULT", @"FAULT", @"AUTOPLAY_WRITE_FAIL",
                 [NSString stringWithFormat:@"family=%@ mode=%d ctrl=%p", family, mode, ctrl]);
            return true;
        }
        uint8_t after = 0; ReadField(ctrl, autoField, after);
        if (!after) {
            Emit(@"FAULT", @"FAULT", @"AUTOPLAY_READBACK_FAIL",
                 [NSString stringWithFormat:@"family=%@ mode=%d ctrl=%p", family, mode, ctrl]);
            return true;
        }
        slot.owned = YES;
        autoPlay = after;
        Emit(@"ACK", @"RUNNING", @"NATIVE_AUTOPLAY_ENABLED",
             [NSString stringWithFormat:@"family=%@ mode=%d ctrl=%p", family, mode, ctrl]);
    }
    uint32_t combo = 0; int32_t perfect = 0; uint8_t ended = 0;
    if (comboField) ReadField(ctrl, comboField, combo);
    if (perfectField) ReadField(ctrl, perfectField, perfect);
    if (endField) ReadField(ctrl, endField, ended);
    Health(ended ? @"COMPLETE" : @"RUNNING", ended ? @"FULLMODE_DANCE_END" : @"FULLMODE_NATIVE_ACTIVE",
           [NSString stringWithFormat:@"family=%@ mode=%d auto=%u combo=%u perfect=%d", family, mode, autoPlay, combo, perfect]);
    return true;
}

static bool HandleBubbleFamily(int32_t mode, Il2CppObject *module) {
    if (!IsBubbleMode(mode)) return false;
    Il2CppObject *logic = GetDanceLogic(module);
    if (!logic) { Health(@"WAIT_PREREQ", @"DANCE_LOGIC_NOT_READY", [NSString stringWithFormat:@"family=bubble mode=%d", mode]); return true; }
    FieldInfo *f = FieldFromObject(logic, "m_noteCtrl", "NoteCtrl");
    Il2CppObject *ctrl = nullptr;
    if (!f || !ReadField(logic, f, ctrl) || !ctrl) { Health(@"WAIT_PREREQ", @"NOTE_CONTROLLER_NOT_READY", [NSString stringWithFormat:@"family=bubble mode=%d", mode]); return true; }
    return EnsureNativeAutoPlay(0, mode, @"bubble", ctrl, gF.bubbleCtrlClass, gF.bubbleAuto, gF.bubbleCombo, gF.bubblePerfect, gF.bubbleEnd);
}

static bool HandleVOSFamily(int32_t mode, Il2CppObject *module) {
    if (!IsVOSMode(mode)) return false;
    Il2CppObject *logic = GetDanceLogic(module);
    if (!logic) { Health(@"WAIT_PREREQ", @"DANCE_LOGIC_NOT_READY", [NSString stringWithFormat:@"family=vos mode=%d", mode]); return true; }
    FieldInfo *f = FieldFromObject(logic, "m_noteCtrl");
    Il2CppObject *ctrl = nullptr;
    if (!f || !ReadField(logic, f, ctrl) || !ctrl) { Health(@"WAIT_PREREQ", @"NOTE_CONTROLLER_NOT_READY", [NSString stringWithFormat:@"family=vos mode=%d", mode]); return true; }
    return EnsureNativeAutoPlay(1, mode, @"vos", ctrl, gF.vosCtrlClass, gF.vosAuto, gF.vosCombo, gF.vosPerfect, gF.vosEnd);
}

static bool HandleDanceBall(int32_t mode) {
    if (mode != 7) return false;
    Il2CppObject *ui = FindUIByClass(gF.danceBallUIClass, 487, @"danceball", false);
    if (!ui) { Health(@"WAIT_PREREQ", @"DANCEBALL_UI_NOT_READY", @"flag=487"); return true; }
    Il2CppObject *ctrl = nullptr;
    if (!gF.danceBallUICtrl || !ReadField(ui, gF.danceBallUICtrl, ctrl) || !ctrl) { Health(@"WAIT_PREREQ", @"DANCEBALL_CONTROLLER_NOT_READY", @"UI_DanceBall_DanceWnd.danceBallCtrl"); return true; }
    return EnsureNativeAutoPlay(2, mode, @"danceball", ctrl, gF.danceBallCtrlClass, gF.danceBallAuto, gF.danceBallCombo, gF.danceBallPerfect, gF.danceBallEnd);
}

static Il2CppObject *GetLogicController(Il2CppObject *module, const char *a, const char *b, Il2CppClass *expected, NSString *family, int32_t mode) {
    Il2CppObject *logic = GetDanceLogic(module);
    if (!logic) { Health(@"WAIT_PREREQ", @"DANCE_LOGIC_NOT_READY", [NSString stringWithFormat:@"family=%@ mode=%d", family, mode]); return nullptr; }
    FieldInfo *f = FieldFromObject(logic, a, b);
    Il2CppObject *ctrl = nullptr;
    if (!f || !ReadField(logic, f, ctrl) || !ctrl) { Health(@"WAIT_PREREQ", @"FAMILY_CONTROLLER_NOT_READY", [NSString stringWithFormat:@"family=%@ mode=%d fields=%s/%s", family, mode, a ?: "", b ?: ""]); return nullptr; }
    if (expected && gAPI.object_get_class && gAPI.object_get_class(ctrl) != expected) {
        Health(@"BLOCKED", @"FAMILY_CONTROLLER_CLASS_MISMATCH", [NSString stringWithFormat:@"family=%@ mode=%d ctrl=%p", family, mode, ctrl]);
        return nullptr;
    }
    return ctrl;
}

static bool HandleDynamicFamily(int32_t mode, Il2CppObject *module) {
    if (!IsDynamicMode(mode)) return false;
    if (!gF.dynamicOnDrumDown) { Health(@"BLOCKED", @"DYNAMIC_BINDINGS_MISSING", [NSString stringWithFormat:@"mode=%d", mode]); return true; }
    Il2CppObject *ctrl = GetLogicController(module, "ArrowsCtrl", "m_arrowsCtrl", gF.dynamicCtrlClass, @"dynamic", mode);
    if (!ctrl) return true;
    float sourceTime = 0.0f;
    if (!ReadField(ctrl, gF.dynamicCtrlSourceTime, sourceTime)) {
        Health(@"WAIT_PREREQ", @"DYNAMIC_TIME_NOT_READY", [NSString stringWithFormat:@"mode=%d", mode]); return true;
    }

    // The V10.1 log proved controller.curGroup can lag behind the actually displayed
    // Starlight/Idol/Peak Dynamic UI group. Prefer UI_DanceDynamic.curGroup, then
    // fall back to the controller group.
    Il2CppObject *ui = FindUIByClass(gF.dynamicUIClass, 73, @"dynamic", false);
    Il2CppObject *group = nullptr;
    NSString *groupSource = @"controller.curGroup";
    if (ui && gF.dynamicUICurGroup && ReadField(ui, gF.dynamicUICurGroup, group) && group) {
        groupSource = @"UI_DanceDynamic.curGroup";
    } else {
        group = nullptr;
        ReadField(ctrl, gF.dynamicCtrlGroup, group);
    }
    if (!group) { Health(@"WAIT_PREREQ", @"DYNAMIC_GROUP_NOT_READY", [NSString stringWithFormat:@"mode=%d source=%@", mode, groupSource]); return true; }
    uint8_t show = 0, canJudge = 0, inCrazy = 0;
    ReadField(group, gF.dynamicGroupIsShow, show);
    if (ui && gF.dynamicUIIsCanJudgeHit) ReadField(ui, gF.dynamicUIIsCanJudgeHit, canJudge);
    if (ui && gF.dynamicUIIsInCrazy) ReadField(ui, gF.dynamicUIIsInCrazy, inCrazy);
    // V10.5: V10.4 runtime proved show=0/canJudge=0 can persist for the entire
    // StarlightTheatreDynamic session even while controller.curGroup is populated.
    // Those UI flags are not portable across Dynamic variants. Keep them as telemetry
    // only and let DynamicOneBeatKeys.IsInHitTime(sourceTime) be the authoritative
    // input-window gate, because that is the gameplay object's own timing predicate.
    Il2CppObject *beatKeys = nullptr; int32_t keyIdx = -1;
    if (!ReadField(group, gF.dynamicGroupBeatKeys, beatKeys) || !beatKeys || !ReadField(group, gF.dynamicGroupCurKeysIndex, keyIdx)) return true;
    int32_t keyCount = ManagedArrayLength(beatKeys);
    if (keyIdx < 0 || keyIdx >= keyCount) { Health(@"WAIT_PREREQ", @"DYNAMIC_KEY_INDEX_WAIT", [NSString stringWithFormat:@"idx=%d count=%d", keyIdx, keyCount]); return true; }
    Il2CppObject *beat = ManagedArrayItem(beatKeys, keyIdx);
    if (!beat) return true;
    Il2CppObject *arrows = nullptr; Il2CppObject *ranges = nullptr; int32_t arrowIdx = -1;
    if (!ReadField(beat, gF.dynamicBeatArrows, arrows) || !arrows || !ReadField(beat, gF.dynamicBeatRanges, ranges) || !ReadField(beat, gF.dynamicBeatCurArrow, arrowIdx)) return true;
    int32_t arrowCount = ManagedArrayLength(arrows);
    if (arrowIdx < 0 || arrowIdx >= arrowCount) return true;
    Il2CppObject *arrow = ManagedArrayItem(arrows, arrowIdx);
    if (!arrow) return true;
    uint8_t hit = 0, dir = 0; ReadField(arrow, gF.dynamicArrowHit, hit); ReadField(arrow, gF.dynamicArrowDir, dir);
    if (hit) { if (gDynamicPendingArrow == arrow) { gDynamicPendingArrow = nullptr; gDynamicPendingRetries = 0; Emit(@"ACK", @"RUNNING", @"DYNAMIC_ARROW_ACCEPTED", [NSString stringWithFormat:@"mode=%d key=%d arrow=%d", mode, keyIdx, arrowIdx]); } return true; }
    if (dir < 1 || dir > 4) return true;
    if (gDynamicPendingArrow && gDynamicPendingArrow != arrow) { gDynamicPendingArrow = nullptr; gDynamicPendingRetries = 0; }
    CFTimeInterval now = CACurrentMediaTime();
    if (gDynamicPendingArrow == arrow) {
        if (now - gDynamicPendingAt < 0.180) return true;
        if (gDynamicPendingRetries >= 2) { Health(@"STALLED", @"DYNAMIC_ACK_TIMEOUT", [NSString stringWithFormat:@"mode=%d key=%d arrow=%d", mode, keyIdx, arrowIdx]); return true; }
    }
    float rs=0,re=0,target=0,localTime=sourceTime;
    float startHit=0.0f,endHit=0.0f;
    float musicBegin=0.0f, offsetTime=0.0f;
    if (gF.dynamicBeatStartHitTime) ReadField(beat, gF.dynamicBeatStartHitTime, startHit);
    if (gF.dynamicBeatEndHitTime) ReadField(beat, gF.dynamicBeatEndHitTime, endHit);
    if (gF.dynamicCtrlMusicBeginTime) ReadField(ctrl, gF.dynamicCtrlMusicBeginTime, musicBegin);
    if (gF.dynamicCtrlOffsetTime) ReadField(ctrl, gF.dynamicCtrlOffsetTime, offsetTime);

    // V10.7: V10.6 runtime trace proved startHitTime/endHitTime are not in the
    // song-relative sourceTime domain. Their values track the app's absolute Unity
    // clock (for example startHit ~80.84 while sourceTime ~9.50). Use the engine's
    // own UnityEngine.Time.time as the primary and authoritative hit-window clock.
    float unityTime = NAN;
    bool unityTimeReady = InvokeFloat(gUnityTimeGetTime, nullptr, nullptr, unityTime);
    float hitTime = unityTimeReady ? unityTime : sourceTime;
    NSString *hitDomain = unityTimeReady ? @"UnityEngine.Time.time" : @"source-fallback";
    bool inHit = false;
    if (gF.dynamicBeatIsInHitTime) {
        if (unityTimeReady) {
            void *hitArgs[1] = { &unityTime };
            bool candidateInHit = false;
            if (InvokeBool(gF.dynamicBeatIsInHitTime, beat, hitArgs, candidateInHit) && candidateInHit) {
                inHit = true;
                hitTime = unityTime;
            }
        }

        // Keep controller-derived clocks only as a compatibility fallback if the
        // Unity Time binding is temporarily unavailable on an unusual build.
        if (!inHit && !unityTimeReady) {
            struct Candidate { float t; const char *name; } candidates[] = {
                { sourceTime,                           "source" },
                { sourceTime + musicBegin,              "source+musicBegin" },
                { sourceTime + offsetTime,              "source+offset" },
                { sourceTime + musicBegin + offsetTime, "source+musicBegin+offset" },
                { sourceTime - offsetTime,              "source-offset" },
            };
            const int candidateCount = (int)(sizeof(candidates) / sizeof(candidates[0]));
            for (int ci = 0; ci < candidateCount; ++ci) {
                float candidate = candidates[ci].t;
                if (!isfinite(candidate) || fabsf(candidate) > 100000.0f) continue;
                bool duplicate = false;
                for (int pj = 0; pj < ci; ++pj) {
                    if (fabsf(candidate - candidates[pj].t) < 0.0001f) { duplicate = true; break; }
                }
                if (duplicate) continue;
                void *hitArgs[1] = { &candidate };
                bool candidateInHit = false;
                if (InvokeBool(gF.dynamicBeatIsInHitTime, beat, hitArgs, candidateInHit) && candidateInHit) {
                    hitTime = candidate;
                    hitDomain = [NSString stringWithUTF8String:candidates[ci].name];
                    inHit = true;
                    break;
                }
            }
        }
        if (!inHit) {
            Health(@"WAIT_COOLDOWN", @"DYNAMIC_WAIT_HIT_WINDOW",
                   [NSString stringWithFormat:@"mode=%d unityTime=%@ source=%.4f musicBegin=%.4f offset=%.4f startHit=%.4f endHit=%.4f key=%d arrow=%d groupSource=%@ show=%u canJudge=%u crazy=%u",
                    mode, unityTimeReady ? [NSString stringWithFormat:@"%.4f", unityTime] : @"UNAVAILABLE",
                    sourceTime, musicBegin, offsetTime, startHit, endHit, keyIdx, arrowIdx, groupSource, show, canJudge, inCrazy]);
            return true;
        }
    }

    bool ready = false;
    NSString *timeDomain = hitDomain;
    if (startHit != 0.0f && gF.dynamicBeatStartHitTime) {
        ready = RangePerfectReadyWithBaseline(ranges, hitTime, startHit, rs, re, target, localTime);
        if (ready) timeDomain = [hitDomain stringByAppendingString:@"-startHit"];
    }
    if (!ready) { localTime = hitTime; ready = RangePerfectReady(ranges, hitTime, rs, re, target); }
    if (!ready) {
        Health(@"WAIT_COOLDOWN", @"DYNAMIC_WAIT_PERFECT",
               [NSString stringWithFormat:@"mode=%d source=%.4f hitTime=%.4f hitDomain=%@ musicBegin=%.4f offset=%.4f local=%.4f startHit=%.4f endHit=%.4f perfect=[%.4f..%.4f] target=%.4f key=%d arrow=%d groupSource=%@ show=%u canJudge=%u crazy=%u",
                mode, sourceTime, hitTime, hitDomain, musicBegin, offsetTime, localTime, startHit, endHit, rs, re, target, keyIdx, arrowIdx, groupSource, show, canJudge, inCrazy]);
        return true;
    }
    if (!ui) { Health(@"WAIT_PREREQ", @"DYNAMIC_UI_NOT_READY", [NSString stringWithFormat:@"mode=%d flags=73/171", mode]); return true; }
    void *args[1] = { &dir };
    if (!InvokeRaw(gF.dynamicOnDrumDown, ui, args, nullptr)) { Emit(@"FAULT", @"FAULT", @"DYNAMIC_INPUT_EXCEPTION"); return true; }
    gDynamicPendingArrow = arrow; gDynamicPendingAt = now; gDynamicPendingRetries++;
    Emit(@"ACTION", @"RUNNING", @"DYNAMIC_ARROW", [NSString stringWithFormat:@"mode=%d key=%d arrow=%d dir=%u unityTime=%@ source=%.4f hitTime=%.4f local=%.4f target=%.4f domain=%@ musicBegin=%.4f offset=%.4f gate=DynamicOneBeatKeys.IsInHitTime groupSource=%@ show=%u canJudge=%u crazy=%u attempt=%d", mode, keyIdx, arrowIdx, dir, unityTimeReady ? [NSString stringWithFormat:@"%.4f", unityTime] : @"UNAVAILABLE", sourceTime, hitTime, localTime, target, timeDomain, musicBegin, offsetTime, groupSource, show, canJudge, inCrazy, gDynamicPendingRetries]);
    return true;
}

static void ReleaseTrackHold() {
    if (!gTrackHeldUI) return;
    uint8_t press = 0;
    if (gTrackHeldPhysical) {
        // Release the same outer UI button handlers used for the press. This mirrors
        // the normal NGUI path and lets UI_DanceTrack maintain isPress/isClick*/time_Click*.
        if (gTrackHeldRightDown && gTrackHeldRightGO && gTrackHeldRightMethod) {
            void *rargs[2] = { gTrackHeldRightGO, &press };
            InvokeRaw(gTrackHeldRightMethod, gTrackHeldUI, rargs, nullptr);
        }
        if (gTrackHeldLeftDown && gTrackHeldLeftGO && gTrackHeldLeftMethod) {
            void *largs[2] = { gTrackHeldLeftGO, &press };
            InvokeRaw(gTrackHeldLeftMethod, gTrackHeldUI, largs, nullptr);
        }
        Emit(@"ACTION", @"RUNNING", @"TRACK_RELEASE",
             [NSString stringWithFormat:@"dir=%d both=%u dispatch=physical left=%u right=%u",
              gTrackHeldDir, gTrackHeldBoth, gTrackHeldLeftDown ? 1 : 0, gTrackHeldRightDown ? 1 : 0]);
    } else if (gTrackHeldPressMethod) {
        int32_t dir = gTrackHeldDir; uint8_t both = gTrackHeldBoth;
        void *args[3] = { &dir, &press, &both };
        InvokeRaw(gTrackHeldPressMethod, gTrackHeldUI, args, nullptr);
        Emit(@"ACTION", @"RUNNING", @"TRACK_RELEASE",
             [NSString stringWithFormat:@"dir=%d both=%u dispatch=private-fallback", dir, both]);
    }
    gTrackHeldUI = nullptr; gTrackHeldPools = nullptr; gTrackHeldPressMethod = nullptr; gTrackHeldNote = nullptr;
    gTrackHeldDir = 0; gTrackHeldBoth = 0; gTrackHeldPhysical = NO;
    gTrackHeldLeftGO = nullptr; gTrackHeldRightGO = nullptr;
    gTrackHeldLeftMethod = nullptr; gTrackHeldRightMethod = nullptr;
    gTrackHeldLeftDown = NO; gTrackHeldRightDown = NO;
    gTrackLongHold = NO; gTrackReleaseAt = 0.0;
}

static void ClearTrackPending() {
    gTrackPendingNote = nullptr;
    gTrackPendingJudgeTime = 0.0f;
    gTrackPendingSecondJudgeTime = 0.0f;
    gTrackPendingDir = 0;
    gTrackPendingChannel = 0;
    gTrackPendingSource = nil;
    gTrackPendingAt = 0.0;
    gTrackPendingAttempts = 0;
    gTrackRetryNotBefore = 0.0;
}

static bool FindTrackPerfectRange(Il2CppObject *ranges, float &startOut, float &endOut, float &targetOut) {
    if (!ranges || !gB.rangeRank || !gB.rangeStartTime || !gB.rangeEndTime) return false;
    int32_t count = ListCount(ranges);
    if (count <= 0 || count > 64) return false;
    for (int32_t i = 0; i < count; i++) {
        Il2CppObject *range = ListItem(ranges, i);
        if (!range) continue;
        int32_t rank = -1;
        if (!ReadField(range, gB.rangeRank, rank) || rank != 4) continue;
        float a = 0.0f, b = 0.0f;
        if (!ReadField(range, gB.rangeStartTime, a) || !ReadField(range, gB.rangeEndTime, b)) continue;
        if (b < a) { float x = a; a = b; b = x; }
        startOut = a; endOut = b; targetOut = a + (b - a) * 0.5f;
        return true;
    }
    return false;
}

static Il2CppObject *FindTrackChartCandidate(Il2CppObject *ctrl, float audioTime,
                                                 int32_t &listIndexOut, int32_t &noteIndexOut,
                                                 float &judgeOut, int32_t &dirOut, uint8_t &channelOut,
                                                 int32_t &countOut) {
    listIndexOut = -1; noteIndexOut = -1; judgeOut = 0.0f; dirOut = 0; channelOut = 0; countOut = -1;
    if (!ctrl || !gF.trackCtrlAllNotes) return nullptr;
    Il2CppObject *allNotes = nullptr;
    if (!ReadField(ctrl, gF.trackCtrlAllNotes, allNotes) || !allNotes) return nullptr;
    const int32_t count = ListCount(allNotes);
    countOut = count;
    if (count <= 0 || count > 4096) return nullptr;

    // Keep the scan bounded around the live song clock. The chart list is sorted by
    // TrackNoteComparer in the current build, but selection is still by minimum
    // JudgeTime so correctness does not depend on that implementation detail.
    const float lateGrace = 0.115f;
    const float lookAhead = 2.50f;
    float bestJudge = 1.0e30f;
    int32_t bestNoteIndex = 0x7fffffff;
    Il2CppObject *best = nullptr;
    int32_t bestListIndex = -1, bestDir = 0;
    uint8_t bestChannel = 0;

    for (int32_t i = 0; i < count; i++) {
        Il2CppObject *candidate = ListItem(allNotes, i);
        if (!candidate) continue;
        uint8_t ended = 0, channel = 0;
        int32_t dir = 0, noteIndex = i;
        float judge = 0.0f;
        if (!ReadField(candidate, gF.trackNoteJudgeEnd, ended) || ended) continue;
        if (!ReadField(candidate, gF.trackNoteJudgeTime, judge) || judge <= 0.0f) continue;
        if (judge < audioTime - lateGrace || judge > audioTime + lookAhead) continue;
        if (!ReadField(candidate, gF.trackNoteDir, dir) || dir < 1 || dir > 4) continue;
        if (!ReadField(candidate, gF.trackNoteChannel, channel) || channel == 0) continue;
        if (gF.trackNoteIndex) ReadField(candidate, gF.trackNoteIndex, noteIndex);
        if (judge < bestJudge - 0.0001f || (fabsf(judge - bestJudge) <= 0.0001f && noteIndex < bestNoteIndex)) {
            best = candidate; bestJudge = judge; bestNoteIndex = noteIndex;
            bestListIndex = i; bestDir = dir; bestChannel = channel;
        }
    }
    if (!best) return nullptr;
    listIndexOut = bestListIndex; noteIndexOut = bestNoteIndex; judgeOut = bestJudge;
    dirOut = bestDir; channelOut = bestChannel;
    return best;
}

static bool HandleTrackFamily(int32_t mode, Il2CppObject *module) {
    if (!IsTrackMode(mode)) return false;

    // V10.9: the runtime Track log proved the router recognizes mode=4, but the old
    // adapter emitted no TRACK_* events for the entire song. The old source was
    // TrackNoteController.curDisplayNote, which can remain on an already-consumed
    // logical/display note. Prefer the note that the live UI pool is actually showing.
    Il2CppObject *ctrl = GetLogicController(module, "noteController", "m_noteController", gF.trackCtrlClass, @"track", mode);

    Il2CppClass *uiClass = (mode == 13 && gF.trackGuideUIClass) ? gF.trackGuideUIClass : gF.trackUIClass;
    int32_t flag = (mode == 13) ? 75 : 74;
    Il2CppObject *ui = FindUIByClass(uiClass, flag, @"track", false);
    if (!ui && mode == 13) ui = FindUIByClass(uiClass, 172, @"track_guide", false);

    Il2CppObject *pools = nullptr;
    Il2CppObject *uiNote = nullptr;
    Il2CppObject *note = nullptr;
    Il2CppObject *ctrlNote = nullptr;
    float ctrlAudioTime = 0.0f;
    float poolAudioTime = 0.0f;
    bool poolAudioReady = false;
    NSString *noteSource = @"none";
    int32_t chartListIndex = -1, chartNoteIndex = -1, chartCount = -1;
    float chartJudge = 0.0f;
    int32_t chartDir = 0; uint8_t chartChannel = 0;
    Il2CppObject *chartNote = nullptr;

    if (ctrl) {
        ReadField(ctrl, gF.trackCtrlNote, ctrlNote);
        ReadField(ctrl, gF.trackCtrlAudioTime, ctrlAudioTime);
    }

    // Normal / Starlight / Idol / Peak Track all use UI_DanceTrack + TrackUIPools.
    // TrackGuide has a different GuidTrackDanceNoteCtrl, so it keeps the controller fallback.
    if (ui && uiClass == gF.trackUIClass && gF.trackUIPools) {
        ReadField(ui, gF.trackUIPools, pools);
        if (pools) {
            poolAudioReady = ReadField(pools, gF.trackPoolsAudioTime, poolAudioTime);
            if (gF.trackPoolsCurrentNoteUI && ReadField(pools, gF.trackPoolsCurrentNoteUI, uiNote) && uiNote &&
                gF.trackUINoteData && ReadField(uiNote, gF.trackUINoteData, note) && note) {
                noteSource = @"UI_DanceTrack.uiPools.curDispalyNote.noteData";
            }
        }
    }

    if (!note && ctrlNote) {
        note = ctrlNote;
        noteSource = @"TrackNoteController.curDisplayNote";
    }

    const float audioTime = poolAudioReady ? poolAudioTime : ctrlAudioTime;

    // V10.13 primary source: the complete logical chart, not the one-note presentation
    // cursor. V10.12 trace had 24/24 dispatched notes acknowledged Perfect, proving
    // the remaining visible misses are notes that never entered TRACK_NOTE_LOCKED.
    // Scanning noteAllList lets overlapping/fast notes be acquired even when
    // curDispalyNote has already rolled to another UI object.
    if (ctrl && gF.trackCtrlAllNotes) {
        chartNote = FindTrackChartCandidate(ctrl, audioTime, chartListIndex, chartNoteIndex,
                                            chartJudge, chartDir, chartChannel, chartCount);
        if (chartNote) {
            note = chartNote;
            noteSource = @"TrackNoteController.noteAllList";
        }
    }

    CFTimeInterval now = CACurrentMediaTime();

    if (gTrackHeldUI) {
        // Do not release a held Track note just because the UI presentation cursor
        // advanced to another note. Short notes release on the 32 ms hold timer;
        // long notes release on their own secondJudgeTime.
        if (!gTrackLongHold && now >= gTrackReleaseAt) {
            ReleaseTrackHold();
        } else if (gTrackLongHold && gTrackHeldNote) {
            Il2CppObject *secondRanges = nullptr;
            ReadField(gTrackHeldNote, gF.trackNoteSecondRanges, secondRanges);
            float heldAudio = audioTime;
            if (gTrackHeldPools && gF.trackPoolsAudioTime) ReadField(gTrackHeldPools, gF.trackPoolsAudioTime, heldAudio);
            float a=0,b=0,t=0,localSecond=heldAudio,secondJudge=0.0f;
            if (gF.trackNoteSecondJudgeTime) ReadField(gTrackHeldNote, gF.trackNoteSecondJudgeTime, secondJudge);

            // V10.10: Track runtime proved RangeList is present but our generic
            // NoteJudgeRange walker never exposes a usable Perfect window (always
            // perfect=[0..0]). secondJudgeTime is the game's per-note canonical
            // release timestamp, so use it as the primary target. RangeList stays
            // diagnostic/fallback only.
            bool releaseReady = false;
            NSString *releaseDomain = @"none";
            if (secondJudge > 0.0f) {
                const float lead = 0.008f;
                releaseReady = heldAudio >= (secondJudge - lead);
                t = secondJudge;
                localSecond = heldAudio - secondJudge;
                if (releaseReady) releaseDomain = @"secondJudgeTime";
            }
            if (!releaseReady && secondRanges) {
                releaseReady = RangePerfectReady(secondRanges, heldAudio, a,b,t);
                if (releaseReady) releaseDomain = @"SecondRangeList";
            }
            if (!releaseReady && secondRanges && secondJudge > 0.0f) {
                releaseReady = RangePerfectReadyCentered(secondRanges, heldAudio, secondJudge, a,b,t,localSecond);
                if (releaseReady) releaseDomain = @"SecondRangeList-centered";
            }
            if (releaseReady) {
                Emit(@"ACTION", @"RUNNING", @"TRACK_LONG_RELEASE_READY",
                     [NSString stringWithFormat:@"audio=%.4f secondJudge=%.4f delta=%.4f perfect=[%.4f..%.4f] target=%.4f domain=%@ rangeCount=%d", heldAudio, secondJudge, localSecond, a, b, t, releaseDomain, ListCount(secondRanges)]);
                ReleaseTrackHold();
            }
        }
        if (gTrackHeldUI) return true;
    }

    if (!ui) {
        Health(@"WAIT_PREREQ", @"TRACK_UI_NOT_READY", [NSString stringWithFormat:@"mode=%d flags=74/75/172", mode]);
        return true;
    }
    if (!ctrl) {
        Health(@"WAIT_PREREQ", @"TRACK_CONTROLLER_NOT_READY", [NSString stringWithFormat:@"mode=%d noteSource=%@", mode, noteSource]);
        return true;
    }
    if (!note && !gTrackPendingNote) {
        Health(@"WAIT_PREREQ", @"TRACK_NOTE_NOT_READY",
               [NSString stringWithFormat:@"mode=%d source=%@ ui=%p pools=%p ctrlNote=%p chartCount=%d audio=%.4f", mode, noteSource, ui, pools, ctrlNote, chartCount, audioTime]);
        return true;
    }

    // Lock the first live, unjudged Track note until it is pressed or expires.
    // Runtime V10.10 showed the visible-note pointer hopping to the next note while
    // every sampled delta was still negative, so following curDispalyNote every
    // tick can permanently skip the previous note's JudgeTime.
    if (gTrackPendingNote) {
        uint8_t pendingEnd = 0;
        ReadField(gTrackPendingNote, gF.trackNoteJudgeEnd, pendingEnd);
        if (pendingEnd || (gTrackPendingJudgeTime > 0.0f && audioTime > gTrackPendingJudgeTime + 0.30f)) {
            Emit(@"ACK", @"RUNNING", pendingEnd ? @"TRACK_LOCK_ALREADY_JUDGED" : @"TRACK_LOCK_EXPIRED",
                 [NSString stringWithFormat:@"note=%p audio=%.4f judge=%.4f delta=%.4f",
                  gTrackPendingNote, audioTime, gTrackPendingJudgeTime, audioTime-gTrackPendingJudgeTime]);
            ClearTrackPending();
        }
    }
    if (!gTrackPendingNote && note) {
        uint8_t candEnd = 0, candChannel = 0;
        int32_t candDir = 0;
        float candJudge = 0.0f, candSecond = 0.0f;
        ReadField(note, gF.trackNoteJudgeEnd, candEnd);
        ReadField(note, gF.trackNoteDir, candDir);
        ReadField(note, gF.trackNoteChannel, candChannel);
        if (gF.trackNoteJudgeTime) ReadField(note, gF.trackNoteJudgeTime, candJudge);
        if (gF.trackNoteSecondJudgeTime) ReadField(note, gF.trackNoteSecondJudgeTime, candSecond);
        int32_t candNoteIndex = -1;
        if (gF.trackNoteIndex) ReadField(note, gF.trackNoteIndex, candNoteIndex);
        if (!candEnd && candJudge > 0.0f && candDir >= 1 && candDir <= 4 && candChannel != 0) {
            gTrackPendingNote = note;
            gTrackPendingJudgeTime = candJudge;
            gTrackPendingSecondJudgeTime = candSecond;
            gTrackPendingDir = candDir;
            gTrackPendingChannel = candChannel;
            gTrackPendingSource = noteSource;
            gTrackPendingAt = now;
            Emit(@"SOURCE", @"READY", @"TRACK_NOTE_LOCKED",
                 [NSString stringWithFormat:@"mode=%d source=%@ note=%p noteIndex=%d chartListIndex=%d chartCount=%d dir=%d channel=%u audio=%.4f judge=%.4f delta=%.4f",
                  mode, noteSource, note, candNoteIndex, chartListIndex, chartCount, candDir, candChannel, audioTime, candJudge, audioTime-candJudge]);
        }
    }
    if (gTrackPendingNote) {
        note = gTrackPendingNote;
        noteSource = gTrackPendingSource ?: @"TRACK_LOCK";
    }
    if (!note) return true;

    if (gTrackRetryNotBefore > 0.0 && now < gTrackRetryNotBefore) {
        return true;
    }

    uint8_t judgeEnd = 0;
    ReadField(note, gF.trackNoteJudgeEnd, judgeEnd);
    if (judgeEnd) {
        Health(@"WAIT_COOLDOWN", @"TRACK_VISIBLE_NOTE_ALREADY_JUDGED",
               [NSString stringWithFormat:@"mode=%d source=%@ note=%p audio=%.4f", mode, noteSource, note, audioTime]);
        return true;
    }

    Il2CppObject *ranges = nullptr;
    ReadField(note, gF.trackNoteRanges, ranges);
    float a=0,b=0,target=0,localTrack=audioTime,judgeTime=0.0f;
    if (gTrackPendingNote == note && gTrackPendingJudgeTime > 0.0f) judgeTime = gTrackPendingJudgeTime;
    else if (gF.trackNoteJudgeTime) ReadField(note, gF.trackNoteJudgeTime, judgeTime);

    // V10.11: two runtime facts are now established:
    // 1) Track's song audio clock is correct; 2) the presentation cursor can move
    // to the next note before our old 8 ms JudgeTime gate fires. Keep the note
    // locked and interpret its rank-4 NoteJudgeRange in a JudgeTime-centered local
    // domain. This uses the game's own Perfect window without writing judge/score.
    bool trackReady = false;
    NSString *trackDomain = @"none";
    const int32_t trackRangeCount = ranges ? ListCount(ranges) : -1;
    float diagTarget = 0.0f;
    const bool havePerfectRange = FindTrackPerfectRange(ranges, a, b, diagTarget);
    if (judgeTime > 0.0f && havePerfectRange && b > a) {
        // RangeList times are local to the note. Map the rank-4 window around
        // JudgeTime and fire 20% into that window, not at its exact center. That
        // stays inside Perfect while giving the main-thread 8 ms timer room before
        // the UI presentation cursor rolls to the next note at/near JudgeTime.
        const float width = b - a;
        const float localDispatch = a + width * 0.20f;
        const float absStart = judgeTime + (a - diagTarget);
        const float absEnd = judgeTime + (b - diagTarget);
        target = judgeTime + (localDispatch - diagTarget);
        localTrack = audioTime - judgeTime + diagTarget;
        trackReady = audioTime >= target && audioTime <= absEnd;
        trackDomain = @"RangeList-centered-20pct";
        if (audioTime > absEnd) {
            Health(@"WAIT_COOLDOWN", @"TRACK_LOCK_MISSED_PERFECT",
                   [NSString stringWithFormat:@"mode=%d source=%@ note=%p audio=%.4f judge=%.4f absPerfect=[%.4f..%.4f] dispatch=%.4f local=%.4f perfect=[%.4f..%.4f] ranges=%p",
                    mode, noteSource, note, audioTime, judgeTime, absStart, absEnd, target, localTrack, a, b, ranges]);
            ClearTrackPending();
            return true;
        }
    } else if (judgeTime > 0.0f) {
        // If the rank-4 range cannot be enumerated, retain a conservative pre-center
        // fallback. The note lock is the important part: it survives presentation
        // cursor rollover instead of silently switching to the next note.
        const float lead = 0.024f;
        const float lateLimit = 0.100f;
        localTrack = audioTime - judgeTime;
        target = judgeTime - lead;
        trackReady = audioTime >= target && audioTime <= (judgeTime + lateLimit);
        trackDomain = @"JudgeTime-24ms-fallback";
        if (audioTime > judgeTime + lateLimit) {
            Health(@"WAIT_COOLDOWN", @"TRACK_LOCK_MISSED_WINDOW",
                   [NSString stringWithFormat:@"mode=%d source=%@ note=%p audio=%.4f judge=%.4f delta=%.4f rangeCount=%d perfect=[%.4f..%.4f] localTarget=%.4f ranges=%p",
                    mode, noteSource, note, audioTime, judgeTime, localTrack, trackRangeCount, a, b, diagTarget, ranges]);
            ClearTrackPending();
            return true;
        }
    } else if (!trackReady) {
        trackReady = RangePerfectReady(ranges, audioTime, a,b,target);
        trackDomain = @"RangeList-absolute-fallback";
    }
    if (!trackReady) {
        Health(@"WAIT_COOLDOWN", @"TRACK_WAIT_LOCKED_NOTE",
               [NSString stringWithFormat:@"mode=%d source=%@ note=%p poolAudio=%.4f ctrlAudio=%.4f selected=%.4f judge=%.4f delta=%.4f target=%.4f domain=%@ rangeCount=%d perfect=[%.4f..%.4f] localTarget=%.4f lockAge=%.3f ranges=%p",
                mode, noteSource, note, poolAudioTime, ctrlAudioTime, audioTime, judgeTime, audioTime-judgeTime, target, trackDomain, trackRangeCount, a, b, diagTarget,
                gTrackPendingAt > 0.0 ? (now-gTrackPendingAt) : 0.0, ranges]);
        return true;
    }

    int32_t dir = 0;
    uint8_t channel = 0;
    if (gTrackPendingNote == note) {
        dir = gTrackPendingDir;
        channel = gTrackPendingChannel;
    } else {
        ReadField(note, gF.trackNoteDir, dir);
        ReadField(note, gF.trackNoteChannel, channel);
    }
    if (dir < 1 || dir > 4 || channel == 0) {
        Health(@"WAIT_PREREQ", @"TRACK_NOTE_INVALID",
               [NSString stringWithFormat:@"mode=%d source=%@ dir=%d channel=%u note=%p", mode, noteSource, dir, channel, note]);
        ClearTrackPending();
        return true;
    }

    const MethodInfo *pressMethod = (uiClass == gF.trackGuideUIClass) ? gF.trackGuideOnPress : gF.trackOnPress;

    // V10.12 runtime evidence: 34 V10.11 TRACK_PRESS attempts had essentially the
    // same timing whether accepted or ignored (16 Perfect ACK vs 18 no-ACK). That
    // rules out the current Perfect target as the primary failure. The direct call
    // to private OnPressBtn(dir,press,isBoth) bypasses UI_DanceTrack's outer button
    // handlers, which own isPress/isClickLeft/isClickRight/time_Click* state.
    // Prefer those real button handlers and keep the private method only as fallback.
    FieldInfo *leftField = (uiClass == gF.trackGuideUIClass) ? gF.trackGuideBtnLeft : gF.trackUIBtnLeft;
    FieldInfo *rightField = (uiClass == gF.trackGuideUIClass) ? gF.trackGuideBtnRight : gF.trackUIBtnRight;
    const MethodInfo *leftMethod = (uiClass == gF.trackGuideUIClass) ? gF.trackGuidePressLeft : gF.trackPressLeft;
    const MethodInfo *rightMethod = (uiClass == gF.trackGuideUIClass) ? gF.trackGuidePressRight : gF.trackPressRight;
    Il2CppObject *leftGO = nullptr, *rightGO = nullptr;
    if (leftField) ReadField(ui, leftField, leftGO);
    if (rightField) ReadField(ui, rightField, rightGO);

    uint8_t press = 1;
    uint8_t both = (channel == 2 || channel == 4) ? 1 : 0;
    bool usedPhysical = false;
    bool leftDown = false, rightDown = false;
    bool invokeOK = false;
    NSString *dispatchPath = @"private-fallback";

    const bool physicalBindings = leftMethod && rightMethod && leftGO && rightGO;
    if (physicalBindings && (dir == 3 || dir == 4)) {
        usedPhysical = true;
        if (both) {
            // Both-channel notes are produced by the normal two-button state machine:
            // first button down arms one side, second button down makes isClickBoth true.
            void *largs[2] = { leftGO, &press };
            void *rargs[2] = { rightGO, &press };
            bool lOK = InvokeRaw(leftMethod, ui, largs, nullptr);
            bool rOK = lOK ? InvokeRaw(rightMethod, ui, rargs, nullptr) : false;
            invokeOK = lOK && rOK;
            leftDown = lOK; rightDown = rOK;
            dispatchPath = @"physical-both";
        } else if (dir == 3) {
            void *args[2] = { leftGO, &press };
            invokeOK = InvokeRaw(leftMethod, ui, args, nullptr);
            leftDown = invokeOK;
            dispatchPath = @"physical-left";
        } else {
            void *args[2] = { rightGO, &press };
            invokeOK = InvokeRaw(rightMethod, ui, args, nullptr);
            rightDown = invokeOK;
            dispatchPath = @"physical-right";
        }
    } else if (pressMethod) {
        void *args[3] = { &dir, &press, &both };
        invokeOK = InvokeRaw(pressMethod, ui, args, nullptr);
    }

    if (!invokeOK) {
        Emit(@"FAULT", @"FAULT", @"TRACK_PRESS_EXCEPTION",
             [NSString stringWithFormat:@"mode=%d source=%@ dir=%d channel=%u dispatch=%@ physicalBindings=%d",
              mode, noteSource, dir, channel, dispatchPath, physicalBindings ? 1 : 0]);
        return true;
    }

    // Read the pool's live note again at dispatch time. This is diagnostic only; it
    // tells us whether presentation rollover ever races the locked logical note.
    Il2CppObject *liveUINote = nullptr, *liveNoteNow = nullptr;
    if (pools && gF.trackPoolsCurrentNoteUI && ReadField(pools, gF.trackPoolsCurrentNoteUI, liveUINote) && liveUINote && gF.trackUINoteData) {
        ReadField(liveUINote, gF.trackUINoteData, liveNoteNow);
    }
    const int liveMatch = (!liveNoteNow || liveNoteNow == note) ? 1 : 0;

    int32_t judgeAfterPress = -1;
    uint8_t judgeEndAfterPress = 0;
    if (gF.trackNoteJudgeLevel) ReadField(note, gF.trackNoteJudgeLevel, judgeAfterPress);
    if (gF.trackNoteJudgeEnd) ReadField(note, gF.trackNoteJudgeEnd, judgeEndAfterPress);
    const bool accepted = judgeEndAfterPress != 0;
    gTrackPendingAttempts++;

    int32_t actionNoteIndex = -1;
    if (gF.trackNoteIndex) ReadField(note, gF.trackNoteIndex, actionNoteIndex);
    Emit(@"ACTION", @"RUNNING", @"TRACK_PRESS",
         [NSString stringWithFormat:@"mode=%d source=%@ note=%p noteIndex=%d dir=%d channel=%u poolAudio=%.4f ctrlAudio=%.4f selected=%.4f judge=%.4f delta=%.4f target=%.4f domain=%@ dispatch=%@ attempt=%d liveNote=%p liveMatch=%d judgeAfterPress=%d judgeEndAfterPress=%u rangeCount=%d",
          mode, noteSource, note, actionNoteIndex, dir, channel, poolAudioTime, ctrlAudioTime, audioTime, judgeTime, localTrack, target, trackDomain,
          dispatchPath, gTrackPendingAttempts, liveNoteNow, liveMatch, judgeAfterPress, judgeEndAfterPress, trackRangeCount]);

    // Always remember how the button went down so release uses the exact same outer
    // handler. A rejected press is released quickly and retried once while the same
    // locked note is still inside its own Perfect window.
    gTrackHeldUI = ui;
    gTrackHeldPools = pools;
    gTrackHeldPressMethod = usedPhysical ? nullptr : pressMethod;
    gTrackHeldNote = note;
    gTrackHeldDir = dir;
    gTrackHeldBoth = both;
    gTrackHeldPhysical = usedPhysical;
    gTrackHeldLeftGO = leftGO; gTrackHeldRightGO = rightGO;
    gTrackHeldLeftMethod = leftMethod; gTrackHeldRightMethod = rightMethod;
    gTrackHeldLeftDown = leftDown; gTrackHeldRightDown = rightDown;
    gTrackLongHold = accepted && (channel == 3 || channel == 4);
    gTrackReleaseAt = now + (accepted ? 0.032 : 0.020);

    if (accepted) {
        ClearTrackPending();
    } else if (gTrackPendingAttempts < 2) {
        gTrackRetryNotBefore = now + 0.028;
        Emit(@"ACK", @"WAIT_COOLDOWN", @"TRACK_PRESS_REJECTED_RETRY",
             [NSString stringWithFormat:@"note=%p dispatch=%@ attempt=%d audio=%.4f judge=%.4f target=%.4f liveMatch=%d",
              note, dispatchPath, gTrackPendingAttempts, audioTime, judgeTime, target, liveMatch]);
    } else {
        Emit(@"ACK", @"WAIT_COOLDOWN", @"TRACK_PRESS_REJECTED_GIVEUP",
             [NSString stringWithFormat:@"note=%p dispatch=%@ attempts=%d audio=%.4f judge=%.4f liveMatch=%d",
              note, dispatchPath, gTrackPendingAttempts, audioTime, judgeTime, liveMatch]);
        ClearTrackPending();
    }

    if (accepted && channel == 5 && gF.trackJudgeDrag && pools && uiClass == gF.trackUIClass) {
        void *dargs[1] = { &dir };
        if (InvokeRaw(gF.trackJudgeDrag, pools, dargs, nullptr))
            Emit(@"ACTION", @"RUNNING", @"TRACK_SLIDER_DRAG", [NSString stringWithFormat:@"dir=%d dispatch=%@", dir, dispatchPath]);
    }

    return true;
}

static Il2CppObject *FindBeatButtonFor(Il2CppObject *ui, FieldInfo *arrayField) {
    if (!ui || !arrayField || !gB.drumBeatBeatType || !gB.drumBeatOnPress) return nullptr;
    Il2CppObject *array = nullptr; if (!ReadField(ui, arrayField, array) || !array) return nullptr;
    int32_t n = ManagedArrayLength(array); if (n <= 0 || n > 16) return nullptr;
    for (int32_t i=0;i<n;i++) { Il2CppObject *button = ManagedArrayItem(array,i); if (!button) continue; uint8_t bt=0; if (ReadField(button,gB.drumBeatBeatType,bt) && bt==5) return button; }
    return nullptr;
}

static bool PressBeatButtonFor(Il2CppObject *ui, FieldInfo *arrayField, NSString *family) {
    Il2CppObject *button = FindBeatButtonFor(ui, arrayField);
    if (!button) return false;
    uint8_t press = 1; void *args[1] = { &press };
    if (!InvokeRaw(gB.drumBeatOnPress, button, args, nullptr)) return false;
    // Reuse common delayed release state; drum button class/method is shared.
    gHeldBeatButton = button; gBeatButtonReleaseAt = CACurrentMediaTime() + 0.032;
    Emit(@"ACTION", @"RUNNING", @"FULLMODE_BEAT_BUTTON", [NSString stringWithFormat:@"family=%@ button=%p", family, button]);
    return true;
}

static bool HandleWitchFamily(int32_t mode) {
    if (mode != 19) return false;
    Il2CppObject *ui = FindUIByClass(gF.witchUIClass, 72, @"challenge_witch", false);
    if (!ui) { Health(@"WAIT_PREREQ", @"WITCH_UI_NOT_READY", @"flag=72"); return true; }
    Il2CppObject *group = nullptr; if (!ReadField(ui, gF.witchUICurGroup, group) || !group) return true;
    int32_t groupIndex=-1; ReadField(group,gF.witchGroupGroupIndex,groupIndex);
    if (group != gWitchGroup) { gWitchGroup=group; gWitchLane=0; gWitchPendingIndex=-1; gWitchPendingRetries=0; gWitchBeatSent=NO; Emit(@"TASK",@"READY",@"WITCH_GROUP_LOCKED",[NSString stringWithFormat:@"group=%d",groupIndex]); }
    uint8_t show=0, hitBeat=0; ReadField(group,gF.witchGroupIsShow,show); ReadField(group,gF.witchGroupIsHitBeat,hitBeat); if (!show) return true;
    Il2CppObject *arrowsArray=nullptr,*idxArray=nullptr; ReadField(group,gF.witchGroupArrowsArray,arrowsArray); ReadField(group,gF.witchGroupIndexArray,idxArray);
    int32_t lanes = ManagedArrayLength(arrowsArray); if (lanes <= 0 || !idxArray) return true; if (gWitchLane >= lanes) gWitchLane=0;
    bool laneAll=false; int32_t laneArg=gWitchLane; void *allArgs[1]={&laneArg}; InvokeBool(gF.witchIsAllHitLane,group,allArgs,laneAll);
    CFTimeInterval now=CACurrentMediaTime();
    if (!laneAll) {
        Il2CppObject *list=ManagedArrayItem(arrowsArray,gWitchLane); int32_t idx=-1; if(!list||!ArrayInt32(idxArray,gWitchLane,idx)) return true;
        int32_t count=ListCount(list); if(idx<0||idx>=count) return true;
        if (gWitchPendingIndex>=0) {
            if (idx>gWitchPendingIndex) { Emit(@"ACK",@"RUNNING",@"WITCH_ARROW_ACCEPTED",[NSString stringWithFormat:@"lane=%d idx=%d->%d",gWitchLane,gWitchPendingIndex,idx]); gWitchPendingIndex=-1; gWitchPendingRetries=0; return true; }
            if (now-gWitchPendingAt<0.260) return true;
            if (gWitchPendingRetries>=2 && lanes>1) { gWitchLane=(gWitchLane+1)%lanes; gWitchPendingIndex=-1; gWitchPendingRetries=0; Emit(@"TASK",@"READY",@"WITCH_LANE_SWITCH",[NSString stringWithFormat:@"lane=%d",gWitchLane]); return true; }
        }
        Il2CppObject *arrow=ListItem(list,idx); uint8_t dir=0; if(!arrow||!ReadField(arrow,gF.witchArrowDir,dir)||dir<1||dir>4) return true;
        void *args[1]={&dir}; if(!InvokeRaw(gF.witchOnDrumDown,ui,args,nullptr)) return true;
        gWitchPendingIndex=idx; gWitchPendingAt=now; gWitchPendingRetries++;
        Emit(@"ACTION",@"RUNNING",@"WITCH_ARROW",[NSString stringWithFormat:@"lane=%d idx=%d/%d dir=%u attempt=%d",gWitchLane,idx,count,dir,gWitchPendingRetries]);
        return true;
    }
    if (hitBeat) return true;
    float audio=0,center=0,openBeat=0,localBeat=0; ReadField(ui,gF.witchUIAudioTime,audio); ReadField(ui,gF.witchUICenterTime,center);
    if (gF.witchUIOpenClickBeatTime) ReadField(ui,gF.witchUIOpenClickBeatTime,openBeat);
    Il2CppObject *ranges=nullptr; ReadField(group,gF.witchGroupRanges,ranges); float a=0,b=0,t=0;
    bool ready=false;
    if (openBeat > 0.0f) ready=RangePerfectReadyWithBaseline(ranges,audio,openBeat,a,b,t,localBeat);
    if(!ready) ready=RangePerfectReady(ranges,audio,a,b,t);
    if(!ready && openBeat > 0.0f) ready=RangePerfectReadyWithBaseline(ranges,center,openBeat,a,b,t,localBeat);
    if(!ready) ready=RangePerfectReady(ranges,center,a,b,t);
    if(!ready) return true;
    if (!gWitchBeatSent || now-gWitchPendingAt>0.060) {
        if (PressBeatButtonFor(ui,gF.witchUIDrumArray,@"witch")) { gWitchBeatSent=YES; gWitchPendingAt=now; }
        else { uint8_t bt=5; void *args[1]={&bt}; InvokeRaw(gF.witchOnDrumDown,ui,args,nullptr); gWitchBeatSent=YES; gWitchPendingAt=now; }
    }
    return true;
}

struct Vec2Value { float x; float y; };
static void ReleaseTaikoHold() {
    if (!gTaikoHeldUI || !gTaikoHeldGO || !gTaikoHeldPress) return;
    uint8_t press=0; void *args[2]={gTaikoHeldGO,&press}; InvokeRaw(gTaikoHeldPress,gTaikoHeldUI,args,nullptr);
    Emit(@"ACTION",@"RUNNING",@"TAIKO_RELEASE",[NSString stringWithFormat:@"dir=%d",gTaikoHeldDir]);
    gTaikoHeldUI=nullptr; gTaikoHeldGO=nullptr; gTaikoHeldPress=nullptr; gTaikoHeldDrag=nullptr; gTaikoLongHold=NO; gTaikoReleaseAt=0; gTaikoLastDragAt=0;
}

static bool HandleTaiko(int32_t mode) {
    if (mode != 29) return false;
    Il2CppObject *ui=FindUIByClass(gF.taikoUIClass,282,@"taiko",false); if(!ui){Health(@"WAIT_PREREQ",@"TAIKO_UI_NOT_READY",@"flag=282");return true;}
    Il2CppObject *ctrl=nullptr; if(!ReadField(ui,gF.taikoUICtrl,ctrl)||!ctrl)return true;
    Il2CppObject *note=nullptr; float musicTime=0; ReadField(ctrl,gF.taikoCtrlNote,note); ReadField(ctrl,gF.taikoCtrlTime,musicTime);
    CFTimeInterval now=CACurrentMediaTime();
    if (gTaikoHeldUI) {
        float endT=0; if(gTaikoLastNote) ReadField(gTaikoLastNote,gF.taikoNoteEndTime,endT);
        if (!gTaikoLongHold && now>=gTaikoReleaseAt) ReleaseTaikoHold();
        else if (gTaikoLongHold && endT>0 && musicTime>=endT) ReleaseTaikoHold();
        else if (gTaikoLongHold && gTaikoHeldDrag && now-gTaikoLastDragAt>=0.024) {
            Vec2Value v = gTaikoHeldDir==0 ? Vec2Value{-3.0f,0.0f} : Vec2Value{3.0f,0.0f};
            void *dargs[2]={gTaikoHeldGO,&v}; InvokeRaw(gTaikoHeldDrag,gTaikoHeldUI,dargs,nullptr); gTaikoLastDragAt=now;
        }
        if(gTaikoHeldUI)return true;
    }
    if(!note)return true;
    if(note!=gTaikoLastNote){gTaikoLastNote=note;}
    int32_t dir=0,noteType=0; float judge=0,endT=0; ReadField(note,gF.taikoNoteDir,dir); ReadField(note,gF.taikoNoteType,noteType); ReadField(note,gF.taikoNoteJudgeTime,judge); ReadField(note,gF.taikoNoteEndTime,endT);
    if(dir<0||dir>1)return true; if(musicTime < judge-0.004f || musicTime > judge+0.060f)return true;
    Il2CppObject *go=nullptr; FieldInfo *goField=dir==0?gF.taikoUIBtnLeft:gF.taikoUIBtnRight; ReadField(ui,goField,go); if(!go)return true;
    const MethodInfo *pressMethod=dir==0?gF.taikoPressLeft:gF.taikoPressRight; const MethodInfo *dragMethod=dir==0?gF.taikoDragLeft:gF.taikoDragRight; if(!pressMethod)return true;
    uint8_t press=1; void *args[2]={go,&press}; if(!InvokeRaw(pressMethod,ui,args,nullptr))return true;
    gTaikoHeldUI=ui;gTaikoHeldGO=go;gTaikoHeldPress=pressMethod;gTaikoHeldDrag=dragMethod;gTaikoHeldDir=dir;
    gTaikoLongHold=(noteType==1||noteType==2);gTaikoReleaseAt=now+0.032;gTaikoLastDragAt=now;
    Emit(@"ACTION",@"RUNNING",@"TAIKO_PRESS",[NSString stringWithFormat:@"dir=%d type=%d music=%.4f judge=%.4f end=%.4f",dir,noteType,musicTime,judge,endT]);
    return true;
}

static void ResetFullModeTransientOnModeChange(int32_t mode) {
    if (mode == gLastMode) return;
    if (gTrackHeldUI) ReleaseTrackHold();
    ClearTrackPending();
    if (gTaikoHeldUI) ReleaseTaikoHold();
    gDynamicPendingArrow=nullptr; gDynamicPendingAt=0; gDynamicPendingRetries=0;
    gWitchGroup=nullptr; gWitchLane=0; gWitchPendingIndex=-1; gWitchPendingRetries=0; gWitchBeatSent=NO;
    gUIInstance=nullptr; gActiveProfile=@"none"; gActiveFlag=-1;
    Emit(@"MODE",@"READY",@"FULLMODE_ROUTE",[NSString stringWithFormat:@"from=%d to=%d",gLastMode,mode]);
    gLastMode=mode;
}

static bool RouteFullMode(int32_t mode, Il2CppObject *module) {
    if (mode < 0) return false;
    if (HandleBubbleFamily(mode,module)) return true;
    if (HandleVOSFamily(mode,module)) return true;
    if (HandleDanceBall(mode)) return true;
    if (HandleDynamicFamily(mode,module)) return true;
    if (HandleTrackFamily(mode,module)) return true;
    if (HandleWitchFamily(mode)) return true;
    if (HandleTaiko(mode)) return true;
    // Audition family and BurstAu continue through the mature V9.5 state machine below.
    return false;
}

static Il2CppObject *DiscoverUIInstance() {
    const CFTimeInterval now = CACurrentMediaTime();
    const bool shouldDiag = (now - gLastInstanceProbeLog >= 2.5);

    // Probe the generic dance window and Challenge Witch as diagnostics only. Challenge Witch
    // is intentionally not forced through the classic state machine because its arrows/indexes
    // are arrays and need a separate lane model.
    if (shouldDiag) {
        bool danceShow = false, danceCache = false;
        bool witchShow = false, witchCache = false;
        ProbeFlagState(gClassicB, 69, danceShow, danceCache);   // ui_dance
        ProbeFlagState(gClassicB, 72, witchShow, witchCache);   // ui_dance_audition_witch
        Il2CppObject *danceModule = nullptr;
        NSString *modeSource = nil;
        int32_t fallbackFlag = -1;
        int32_t danceMode = ProbeResolvedMode(&danceModule, &modeSource, &fallbackFlag);
        Emit(@"SOURCE", @"WAIT_PREREQ", @"MODE_PROBE",
             [NSString stringWithFormat:@"danceMode=%d name=%@ family=%@ source=%@ danceModule=%p ui_dance69=%d/%d witch72=%d/%d fallbackFlag=%d",
              danceMode, ModeNameFor(danceMode), ModeFamilyFor(danceMode), modeSource ?: @"NONE", danceModule,
              danceShow ? 1 : 0, danceCache ? 1 : 0, witchShow ? 1 : 0, witchCache ? 1 : 0, fallbackFlag]);
        if (witchShow || witchCache) {
            Emit(@"SOURCE", @"READY", @"WITCH_UI_VISIBLE_DEDICATED_ADAPTER",
                 @"flag=72 routed by Witch adapter when DanceMode=19");
        }
    }

    Il2CppObject *ret = FindUIInstanceFor(gClassicB, 71, @"classic_audition", shouldDiag);
    if (ret) {
        gB = gClassicB;
        gActiveProfile = @"classic_audition";
        gActiveFlag = 71;
        if (shouldDiag) gLastInstanceProbeLog = now;
        return ret;
    }

    ret = FindUIInstanceFor(gBurstB, 308, @"burst_au", shouldDiag);
    if (ret) {
        gB = gBurstB;
        gActiveProfile = @"burst_au";
        gActiveFlag = 308;
        if (shouldDiag) gLastInstanceProbeLog = now;
        return ret;
    }

    if (shouldDiag) {
        gLastInstanceProbeLog = now;
        Emit(@"SOURCE", @"WAIT_PREREQ", @"INSTANCE_PROBE_EMPTY",
             @"profiles=classic_audition:71,burst_au:308");
    }
    return nullptr;
}


static CFTimeInterval RandomArrowPacingDelay(void) {
    // Inclusive 75..110 ms. Randomization here is only a scheduler/pacing aid so
    // sequential inputs are not collapsed into the same frame/tick.
    uint32_t ms = 75u + arc4random_uniform(36u);
    return (CFTimeInterval)ms / 1000.0;
}

static float RandomBeatJitterSeconds(void) {
    // V10.4: keep Beat centered. Only ±2 ms is retained as a scheduler collision aid.
    int32_t ms = (int32_t)arc4random_uniform(5u) - 2;
    return (float)ms / 1000.0f;
}

static void ResetGroupState(Il2CppObject *group, int32_t groupIndex) {
    gLastGroup = group;
    gLastGroupIndex = groupIndex;
    gLastArrowIndex = -1;
    gArrowAttempts = 0;
    gBeatAttempts = 0;
    gBeatAccepted = NO;
    gBeatFirstAttemptAt = 0.0;
    gLastJudgeLevel = -1;
    gGroupCompletionLogged = NO;

    gPendingArrowIndex = -1;
    gPendingArrowSentAt = 0.0;
    gPendingArrowRetries = 0;
    gNextArrowAllowedAt = 0.0;

    gBeatDispatched = NO;
    gBeatDispatchedAt = 0.0;
    gBeatJitterSeconds = gBeatJitterEnabled ? RandomBeatJitterSeconds() : 0.0f;

    Emit(@"TASK", @"READY", @"GROUP_LOCKED",
         [NSString stringWithFormat:@"profile=%@ flag=%d group=%d ptr=%p pacing=%d ackGate=%d beatOneShot=%d beatJitterMs=%.1f",
          gActiveProfile ?: @"unknown", gActiveFlag, groupIndex, group,
          gArrowPacingEnabled ? 1 : 0, gArrowAckGateEnabled ? 1 : 0,
          gBeatOneShotEnabled ? 1 : 0, gBeatJitterSeconds * 1000.0f]);
}

static bool SendBeatType(uint8_t beatType, NSString *kind, NSString *details) {
    if (!gUIInstance || !gB.onDrumDown) return false;
    void *args[1] = { &beatType };
    Emit(@"ACTION", @"RUNNING", @"DISPATCH_BEGIN",
         [NSString stringWithFormat:@"kind=%@ beat=%u%@", kind ?: @"INPUT", beatType,
          details.length ? [@" " stringByAppendingString:details] : @""]);
    bool ok = InvokeRaw(gB.onDrumDown, gUIInstance, args, nullptr);
    if (!ok) {
        Emit(@"FAULT", @"FAULT", @"INVOKE_EXCEPTION",
             [NSString stringWithFormat:@"kind=%@ beat=%u", kind ?: @"INPUT", beatType]);
    }
    return ok;
}

static Il2CppObject *FindPhysicalBeatButton(uint8_t wantedBeatType) {
    if (!gUIInstance || !gB.uiDrumBeatArray || !gB.drumBeatBeatType ||
        !gB.drumBeatOnPress || !gArrayGetLength || !gArrayGetValue) return nullptr;

    Il2CppObject *array = nullptr;
    if (!ReadField(gUIInstance, gB.uiDrumBeatArray, array) || !array) return nullptr;
    int32_t length = ManagedArrayLength(array);
    if (length <= 0 || length > 16) return nullptr;

    for (int32_t i = 0; i < length; i++) {
        Il2CppObject *button = ManagedArrayItem(array, i);
        if (!button) continue;
        uint8_t beatType = 0;
        if (!ReadField(button, gB.drumBeatBeatType, beatType)) continue;
        if (beatType == wantedBeatType) return button;
    }
    return nullptr;
}

static bool ReleaseHeldBeatButtonIfDue(CFTimeInterval now) {
    if (!gHeldBeatButton || now < gBeatButtonReleaseAt || !gB.drumBeatOnPress) return false;
    uint8_t press = 0;
    void *args[1] = { &press };
    bool ok = InvokeRaw(gB.drumBeatOnPress, gHeldBeatButton, args, nullptr);
    Emit(ok ? @"ACTION" : @"FAULT", ok ? @"RUNNING" : @"FAULT",
         ok ? @"BEAT_BUTTON_RELEASE" : @"BEAT_BUTTON_RELEASE_FAIL",
         [NSString stringWithFormat:@"button=%p", gHeldBeatButton]);
    gHeldBeatButton = nullptr;
    gBeatButtonReleaseAt = 0.0;
    return ok;
}

static bool SendPhysicalBeatButton(NSString *details) {
    Il2CppObject *button = FindPhysicalBeatButton(5);
    if (!button) {
        Emit(@"FAULT", @"STALLED", @"BEAT_BUTTON_NOT_FOUND",
             @"arryDrumBeat has no live beatType=5 button; direct OnDrumDown fallback will be used");
        return SendBeatType(5, @"BEAT_FALLBACK", details);
    }

    uint8_t press = 1;
    void *args[1] = { &press };
    Emit(@"ACTION", @"RUNNING", @"BEAT_BUTTON_PRESS_BEGIN",
         [NSString stringWithFormat:@"path=UI_AuditionDrumBeat.OnPress beat=5 button=%p%@",
          button, details.length ? [@" " stringByAppendingString:details] : @""]);
    bool ok = InvokeRaw(gB.drumBeatOnPress, button, args, nullptr);
    if (!ok) {
        Emit(@"FAULT", @"FAULT", @"BEAT_BUTTON_PRESS_EXCEPTION",
             [NSString stringWithFormat:@"button=%p", button]);
        return false;
    }

    // NGUI OnPress receives both down/up states. Hold briefly so the game's real button
    // state/visual path is exercised, then release on a later scheduler tick.
    gHeldBeatButton = button;
    gBeatButtonReleaseAt = CACurrentMediaTime() + 0.032;
    return true;
}

static bool PerfectTargetReady(Il2CppObject *group,
                               float audioTime,
                               float centerAudioTime,
                               float openClickBeatTime,
                               bool hasMoveRate,
                               float moveRate,
                               float &startOut, float &endOut, float &centerTargetOut,
                               float &adjustedTargetOut, float &selectedTimeOut,
                               NSString **sourceOut) {
    Il2CppObject *ranges = nullptr;
    if (!ReadField(group, gB.groupRangeList, ranges) || !ranges) return false;
    int32_t count = ListCount(ranges);
    if (count <= 0 || count > 64) return false;

    for (int32_t i = 0; i < count; i++) {
        Il2CppObject *range = ListItem(ranges, i);
        if (!range) continue;
        int32_t rank = -1;
        if (!ReadField(range, gB.rangeRank, rank) || rank != 4) continue;

        float start = 0.0f, end = 0.0f;
        if (!ReadField(range, gB.rangeStartTime, start) ||
            !ReadField(range, gB.rangeEndTime, end)) continue;
        if (end < start) { float tmp = start; start = end; end = tmp; }

        const float centerTarget = start + (end - start) * 0.5f;
        startOut = start;
        endOut = end;
        centerTargetOut = centerTarget;

        // V10.5: runtime V10.4 proved that the physical Beat is accepted but
        // judgeAfterPress remains Miss even when (audio-openClick) is 0.754..0.766
        // inside the nominal [0.725..0.775] Perfect range. UI_DanceAudition and
        // UI_DanceBurstAu both expose moveRate immediately next to UpdateCursor(),
        // and JudgeBeatRound takes a single float judgeTime. Treat moveRate as the
        // authoritative judge coordinate whenever it is available.
        //
        // Do not apply the old "seconds" jitter to moveRate: the units are not seconds.
        if (hasMoveRate) {
            float t = moveRate;
            void *a1[1] = { &t };
            bool inside = false;
            if (!InvokeBool(gB.rangeIsInRange, range, a1, inside) || !inside) {
                adjustedTargetOut = centerTarget;
                selectedTimeOut = t;
                if (sourceOut) *sourceOut = @"ui.moveRate";
                return false;
            }
            adjustedTargetOut = centerTarget;
            selectedTimeOut = t;
            if (sourceOut) *sourceOut = @"ui.moveRate";
            return t >= centerTarget;
        }

        // Compatibility fallback only for variants where moveRate cannot be read.
        // Keep this deterministic at the range center; V10.4 showed that edge bias
        // and extra jitter made diagnosis harder and did not improve judgement.
        const float adjustedTarget = centerTarget;
        adjustedTargetOut = adjustedTarget;

        float localAudio = audioTime - openClickBeatTime;
        float localCenter = centerAudioTime - openClickBeatTime;
        float candidates[4] = { localAudio, localCenter, audioTime, centerAudioTime };
        NSString *names[4] = { @"audio-openClick", @"center-openClick", @"audioTime(raw)", @"centerAudioTime(raw)" };
        int candidateCount = openClickBeatTime > 0.0f ? 4 : 2;
        int candidateOffset = openClickBeatTime > 0.0f ? 0 : 2;
        int best = -1;
        float bestDistance = 999999.0f;

        for (int k = 0; k < candidateCount; k++) {
            int c = k + candidateOffset;
            float t = candidates[c];
            void *a1[1] = { &t };
            bool inside = false;
            if (!InvokeBool(gB.rangeIsInRange, range, a1, inside) || !inside) continue;

            float d = fabsf(t - adjustedTarget);
            if (d < bestDistance) {
                bestDistance = d;
                best = c;
            }
        }

        if (best < 0) return false;
        selectedTimeOut = candidates[best];
        if (sourceOut) *sourceOut = names[best];
        return candidates[best] >= adjustedTarget;
    }
    return false;
}

static void Health(NSString *state, NSString *reason, NSString *details) {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gLastHealth < 2.5) return;
    gLastHealth = now;
    Emit(@"HEALTH", state, reason, details);
}


static void RestoreFullNativeAutoPlayIfCurrent() {
    Il2CppObject *module = nullptr;
    int32_t mode = ProbeDanceMode(&module);
    if (IsBubbleMode(mode) && gAutoSlots[0].owned && module) {
        Il2CppObject *logic = GetDanceLogic(module);
        FieldInfo *f = FieldFromObject(logic, "m_noteCtrl", "NoteCtrl");
        Il2CppObject *ctrl = nullptr;
        if (f && ReadField(logic, f, ctrl) && ctrl == gAutoSlots[0].ctrl) {
            WriteField(ctrl, gAutoSlots[0].field, gAutoSlots[0].previous);
            Emit(@"ACK", @"OFF", @"AUTOPLAY_RESTORED", [NSString stringWithFormat:@"family=bubble mode=%d", mode]);
        }
    }
    if (IsVOSMode(mode) && gAutoSlots[1].owned && module) {
        Il2CppObject *logic = GetDanceLogic(module);
        FieldInfo *f = FieldFromObject(logic, "m_noteCtrl");
        Il2CppObject *ctrl = nullptr;
        if (f && ReadField(logic, f, ctrl) && ctrl == gAutoSlots[1].ctrl) {
            WriteField(ctrl, gAutoSlots[1].field, gAutoSlots[1].previous);
            Emit(@"ACK", @"OFF", @"AUTOPLAY_RESTORED", [NSString stringWithFormat:@"family=vos mode=%d", mode]);
        }
    }
    if (mode == 7 && gAutoSlots[2].owned) {
        Il2CppObject *ui = FindUIByClass(gF.danceBallUIClass, 487, @"danceball", false);
        Il2CppObject *ctrl = nullptr;
        if (ui && ReadField(ui, gF.danceBallUICtrl, ctrl) && ctrl == gAutoSlots[2].ctrl) {
            WriteField(ctrl, gAutoSlots[2].field, gAutoSlots[2].previous);
            Emit(@"ACK", @"OFF", @"AUTOPLAY_RESTORED", @"family=danceball mode=7");
        }
    }
    for (auto &slot : gAutoSlots) { slot.ctrl=nullptr; slot.field=nullptr; slot.owned=NO; slot.mode=-1; slot.previous=0; }
}

static void Tick() {
    if (!gEnabled) return;
    if (!BindGame()) return;

    CFTimeInterval tickNow = CACurrentMediaTime();
    ReleaseHeldBeatButtonIfDue(tickNow);

    // Runtime-first full-mode routing. Families with native or dedicated controllers
    // are handled before the mature Audition/Burst state machine.
    Il2CppObject *danceModule = nullptr;
    NSString *modeSource = nil;
    int32_t fallbackFlag = -1;
    int32_t danceMode = ProbeResolvedMode(&danceModule, &modeSource, &fallbackFlag);
    PublishModeDetection(danceMode, modeSource, fallbackFlag);
    ResetFullModeTransientOnModeChange(danceMode);
    if (RouteFullMode(danceMode, danceModule)) return;
    if (danceMode >= 0 && !IsAuditionMode(danceMode) && danceMode != 5) {
        const ModeDescriptor *d = ModeDescriptorFor(danceMode);
        Health(@"WAIT_PREREQ", d ? @"MODE_RECOGNIZED_BUT_NO_ACTIVE_ADAPTER" : @"MODE_UNKNOWN_OR_RESERVED",
               [NSString stringWithFormat:@"danceMode=%d name=%@ family=%@ source=%@",
                danceMode, ModeNameFor(danceMode), ModeFamilyFor(danceMode), modeSource ?: @"NONE"]);
        return;
    }

    CFTimeInterval now = CACurrentMediaTime();
    if (!gUIInstance || !ObjectAlive(gUIInstance)) {
        gUIInstance = nullptr;
        if (now - gLastDiscoveryAttempt >= 0.20) {
            gLastDiscoveryAttempt = now;
            Il2CppObject *found = DiscoverUIInstance();
            if (found && ObjectAlive(found)) {
                gUIInstance = found;
                Emit(@"SOURCE", @"READY", @"UI_INSTANCE_FOUND",
                     [NSString stringWithFormat:@"profile=%@ flag=%d ptr=%p", gActiveProfile ?: @"unknown", gActiveFlag, found]);
            }
        }
        if (!gUIInstance) {
            Health(@"WAIT_PREREQ", @"INSTANCE_NOT_READY", @"profiles=classic_audition:71,burst_au:308 sources=GetUIWnd+FindFirstIncludeInactive+FindObjectOfType");
            return;
        }
    }

    Il2CppObject *group = nullptr;
    if (!ReadField(gUIInstance, gB.uiCurGroup, group) || !group) {
        Health(@"WAIT_PREREQ", @"SOURCE_EMPTY", @"curGroup=null");
        return;
    }

    int32_t groupIndex = -1;
    ReadField(group, gB.groupGroupIndex, groupIndex);
    if (group != gLastGroup || groupIndex != gLastGroupIndex) ResetGroupState(group, groupIndex);

    uint8_t isShow = 0;
    uint8_t isHitBeat = 0;
    int32_t judgeLevel = -1;
    ReadField(group, gB.groupIsShow, isShow);
    ReadField(group, gB.groupIsHitBeat, isHitBeat);
    ReadField(group, gB.groupJudgeLevel, judgeLevel);
    gLastJudgeLevel = judgeLevel;

    if (isHitBeat && gBeatDispatched && !gBeatAccepted) {
        gBeatAccepted = YES;
        Emit(@"ACK", @"RUNNING", @"BEAT_ACCEPTED",
             [NSString stringWithFormat:@"group=%d attempts=%d delayed=1", groupIndex, gBeatAttempts]);
    }

    if (!isShow) {
        Health(@"WAIT_PREREQ", @"GROUP_NOT_VISIBLE",
               [NSString stringWithFormat:@"group=%d", groupIndex]);
        return;
    }

    bool allHit = false;
    if (!InvokeBool(gB.isAllHit, group, nullptr, allHit)) {
        Emit(@"FAULT", @"FAULT", @"IS_ALL_HIT_INVOKE_FAIL");
        return;
    }

    if (!allHit) {
        Il2CppObject *arrows = nullptr;
        int32_t idx = -1;
        if (!ReadField(group, gB.groupArrowsList, arrows) || !arrows ||
            !ReadField(group, gB.groupCurArrowIndex, idx)) {
            Health(@"WAIT_PREREQ", @"SOURCE_NOT_READY", @"arrowsList/curArrowIndex");
            return;
        }
        int32_t count = ListCount(arrows);
        if (count <= 0 || idx < 0 || idx >= count) {
            Health(@"STALLED", @"ARROW_INDEX_INVALID",
                   [NSString stringWithFormat:@"idx=%d count=%d", idx, count]);
            return;
        }

        // ACK gate: once an arrow was sent, do not advance to any next arrow until
        // curArrowIndex/allHit proves that the game consumed the previous input.
        if (gArrowAckGateEnabled && gPendingArrowIndex >= 0) {
            if (idx > gPendingArrowIndex) {
                CFTimeInterval pace = gArrowPacingEnabled ? RandomArrowPacingDelay() : 0.014;
                Emit(@"ACK", @"RUNNING", @"ARROW_ACCEPTED",
                     [NSString stringWithFormat:@"group=%d idx=%d->%d paceMs=%.0f retries=%d",
                      groupIndex, gPendingArrowIndex, idx, pace * 1000.0, gPendingArrowRetries]);
                gLastArrowIndex = idx;
                gPendingArrowIndex = -1;
                gPendingArrowSentAt = 0.0;
                gPendingArrowRetries = 0;
                gNextArrowAllowedAt = now + pace;
                return;
            }

            // If state moved backwards, treat this as a new lifecycle and release
            // the stale pending gate instead of injecting against the wrong arrow.
            if (idx < gPendingArrowIndex) {
                Emit(@"TASK", @"READY", @"ARROW_GATE_RESET",
                     [NSString stringWithFormat:@"group=%d pending=%d current=%d",
                      groupIndex, gPendingArrowIndex, idx]);
                gPendingArrowIndex = -1;
                gPendingArrowSentAt = 0.0;
                gPendingArrowRetries = 0;
            } else {
                // Same arrow still pending. Give the game plenty of time to ACK before
                // a controlled retry of the SAME arrow. Never jump ahead.
                if (now - gPendingArrowSentAt < 0.320) return;
                if (gPendingArrowRetries >= 2) {
                    Health(@"STALLED", @"ARROW_ACK_TIMEOUT",
                           [NSString stringWithFormat:@"group=%d idx=%d attempts=%d",
                            groupIndex, idx, gArrowAttempts]);
                    return;
                }

                Il2CppObject *retryArrow = ListItem(arrows, idx);
                if (!retryArrow) {
                    Health(@"STALLED", @"ARROW_ITEM_NULL",
                           [NSString stringWithFormat:@"idx=%d retry=1", idx]);
                    return;
                }
                uint8_t retryDir = 0;
                if (!ReadField(retryArrow, gB.arrowDirection, retryDir) ||
                    retryDir < 1 || retryDir > 4) {
                    Emit(@"FAULT", @"FAULT", @"ARROW_DIRECTION_INVALID",
                         [NSString stringWithFormat:@"idx=%d dir=%u retry=1", idx, retryDir]);
                    return;
                }

                gPendingArrowRetries++;
                gPendingArrowSentAt = now;
                gLastInputAttempt = now;
                gArrowAttempts++;
                SendBeatType(retryDir, @"ARROW_RETRY",
                             [NSString stringWithFormat:@"group=%d idx=%d/%d retry=%d",
                              groupIndex, idx, count, gPendingArrowRetries]);
                return;
            }
        }

        if (now < gNextArrowAllowedAt) return;
        if (!gArrowPacingEnabled && now - gLastInputAttempt < 0.014) return;

        Il2CppObject *arrow = ListItem(arrows, idx);
        if (!arrow) {
            Health(@"STALLED", @"ARROW_ITEM_NULL",
                   [NSString stringWithFormat:@"idx=%d", idx]);
            return;
        }
        uint8_t dir = 0;
        if (!ReadField(arrow, gB.arrowDirection, dir) || dir < 1 || dir > 4) {
            Emit(@"FAULT", @"FAULT", @"ARROW_DIRECTION_INVALID",
                 [NSString stringWithFormat:@"idx=%d dir=%u", idx, dir]);
            return;
        }

        gLastInputAttempt = now;
        gArrowAttempts++;
        int32_t before = idx;
        if (!SendBeatType(dir, @"ARROW",
                          [NSString stringWithFormat:@"group=%d idx=%d/%d ackGate=%d",
                           groupIndex, idx, count, gArrowAckGateEnabled ? 1 : 0])) return;

        if (gArrowAckGateEnabled) {
            gPendingArrowIndex = before;
            gPendingArrowSentAt = now;
            gPendingArrowRetries = 0;
        }

        // Accept an immediate synchronous state change if the managed handler updates
        // curArrowIndex during the same invocation; otherwise the next Tick waits for it.
        int32_t after = before;
        ReadField(group, gB.groupCurArrowIndex, after);
        bool nowAllHit = false;
        InvokeBool(gB.isAllHit, group, nullptr, nowAllHit);
        if (after > before || nowAllHit) {
            CFTimeInterval pace = gArrowPacingEnabled ? RandomArrowPacingDelay() : 0.014;
            gLastArrowIndex = after;
            if (gArrowAckGateEnabled) {
                gPendingArrowIndex = -1;
                gPendingArrowSentAt = 0.0;
                gPendingArrowRetries = 0;
            }
            gNextArrowAllowedAt = now + pace;
            Emit(@"ACK", @"RUNNING", @"ARROW_ACCEPTED",
                 [NSString stringWithFormat:@"group=%d idx=%d->%d allHit=%d paceMs=%.0f",
                  groupIndex, before, after, nowAllHit ? 1 : 0, pace * 1000.0]);
        } else if (!gArrowAckGateEnabled && (gArrowAttempts % 6) == 0) {
            Emit(@"STALL", @"STALLED", @"ACTION_SENT_NO_EFFECT",
                 [NSString stringWithFormat:@"kind=ARROW idx=%d attempts=%d", idx, gArrowAttempts]);
        }
        return;
    }

    // The last arrow may transition directly to allHit before the pending gate is
    // observed on the next tick. allHit itself is a valid ACK for that final arrow.
    if (gArrowAckGateEnabled && gPendingArrowIndex >= 0) {
        Emit(@"ACK", @"RUNNING", @"ARROW_ACCEPTED",
             [NSString stringWithFormat:@"group=%d idx=%d->ALL_HIT retries=%d",
              groupIndex, gPendingArrowIndex, gPendingArrowRetries]);
        gPendingArrowIndex = -1;
        gPendingArrowSentAt = 0.0;
        gPendingArrowRetries = 0;
    }

    // Arrows are complete. Beat is sent only while the game's own Perfect range says
    // the current UI timing source is inside that range. No judgement field is forced.
    if (!isHitBeat) {
        // ACK-gated Beat: one ACCEPTED Beat per group, not one blind dispatch.
        // If the first managed input does not flip group.isHitBeat, allow a small
        // number of controlled retries while the game's Perfect window is still live.
        // This avoids the V9 regression where one missed dispatch locked Beat forever.
        if (gBeatOneShotEnabled && gBeatDispatched) {
            CFTimeInterval waited = now - gBeatDispatchedAt;
            const CFTimeInterval retryDelay = 0.024; // ~3 ticks at the 8 ms scheduler.
            const int32_t maxBeatAttempts = 3;

            if (waited < retryDelay) return;
            if (gBeatAttempts >= maxBeatAttempts) {
                Health(@"STALLED", @"BEAT_ACK_TIMEOUT",
                       [NSString stringWithFormat:@"group=%d waitedMs=%.0f attempts=%d max=%d",
                        groupIndex, waited * 1000.0, gBeatAttempts, maxBeatAttempts]);
                return;
            }

            // Release only the dispatch latch. gBeatAccepted remains false and the
            // Perfect-range gate below must pass again before another Beat is sent.
            gBeatDispatched = NO;
        }

        float audioTime = 0.0f;
        float centerAudioTime = 0.0f;
        float openClickBeatTime = 0.0f;
        float moveRate = 0.0f;
        ReadField(gUIInstance, gB.uiAudioTime, audioTime);
        ReadField(gUIInstance, gB.uiCenterAudioTime, centerAudioTime);
        ReadField(gUIInstance, gB.uiOpenClickBeatTime, openClickBeatTime);
        bool hasMoveRate = gB.uiMoveRate && ReadField(gUIInstance, gB.uiMoveRate, moveRate);
        float perfectStart = 0.0f;
        float perfectEnd = 0.0f;
        float perfectCenterTarget = 0.0f;
        float perfectAdjustedTarget = 0.0f;
        float selectedBeatTime = 0.0f;
        NSString *source = nil;
        bool targetReady = PerfectTargetReady(group, audioTime, centerAudioTime, openClickBeatTime,
                                              hasMoveRate, moveRate,
                                              perfectStart, perfectEnd,
                                              perfectCenterTarget, perfectAdjustedTarget,
                                              selectedBeatTime, &source);
        if (!targetReady) {
            Health(@"WAIT_COOLDOWN", @"WAIT_PERFECT_WINDOW_READY",
                   [NSString stringWithFormat:@"group=%d audio=%.4f center=%.4f openClick=%.4f localAudio=%.4f moveRate=%.4f hasMoveRate=%d perfect=[%.4f..%.4f] centerTarget=%.4f adjustedTarget=%.4f source=%@ selected=%.4f",
                    groupIndex, audioTime, centerAudioTime, openClickBeatTime, audioTime-openClickBeatTime, moveRate, hasMoveRate ? 1 : 0, perfectStart, perfectEnd,
                    perfectCenterTarget, perfectAdjustedTarget,
                    source ?: @"none", selectedBeatTime]);
            return;
        }

        // Debounce against the final arrow / another Beat dispatch landing in the same
        // scheduler tick. PerfectTargetReady still controls the musical timing.
        if (now - gLastInputAttempt < 0.008) return;

        if (!gBeatOneShotEnabled) {
            if (gBeatAttempts >= 4 && now - gBeatFirstAttemptAt < 0.080) return;
        } else if (gBeatAttempts >= 3) {
            return;
        }

        if (gBeatFirstAttemptAt <= 0.0) gBeatFirstAttemptAt = now;
        gLastInputAttempt = now;
        gBeatAttempts++;

        if (!SendPhysicalBeatButton(
                          [NSString stringWithFormat:@"group=%d source=%@ selected=%.4f centerTarget=%.4f adjustedTarget=%.4f delta=%.4f audio=%.4f center=%.4f openClick=%.4f localAudio=%.4f moveRate=%.4f hasMoveRate=%d window=[%.4f..%.4f] attempt=%d oneShot=%d",
                           groupIndex, source ?: @"unknown", selectedBeatTime,
                           perfectCenterTarget, perfectAdjustedTarget,
                           (selectedBeatTime - perfectAdjustedTarget),
                           audioTime, centerAudioTime, openClickBeatTime, audioTime-openClickBeatTime, moveRate, hasMoveRate ? 1 : 0, perfectStart, perfectEnd,
                           gBeatAttempts, gBeatOneShotEnabled ? 1 : 0])) return;

        gBeatDispatched = YES;
        gBeatDispatchedAt = now;

        uint8_t accepted = 0;
        ReadField(group, gB.groupIsHitBeat, accepted);
        if (accepted) {
            gBeatAccepted = YES;
            int32_t judgeAfterPress = -1;
            ReadField(group, gB.groupJudgeLevel, judgeAfterPress);
            Emit(@"ACK", @"RUNNING", @"BEAT_ACCEPTED",
                 [NSString stringWithFormat:@"group=%d attempts=%d delayed=0 judgeAfterPress=%d", groupIndex, gBeatAttempts, judgeAfterPress]);
        }
        return;
    }

    if (!gGroupCompletionLogged) {
        if (judgeLevel == 4) {
            gGroupCompletionLogged = YES;
            Emit(@"COMPLETE", @"COMPLETE", @"PERFECT_CONFIRMED",
                 [NSString stringWithFormat:@"group=%d judge=%d arrows=%d beatAttempts=%d", groupIndex, judgeLevel, gArrowAttempts, gBeatAttempts]);
        } else if (gBeatAccepted && gBeatFirstAttemptAt > 0.0 && now - gBeatFirstAttemptAt > 0.20) {
            gGroupCompletionLogged = YES;
            Emit(@"FAULT", @"FAULT", @"JUDGEMENT_NOT_PERFECT",
                 [NSString stringWithFormat:@"group=%d judge=%d beatAttempts=%d", groupIndex, judgeLevel, gBeatAttempts]);
        } else {
            Health(@"RUNNING", @"WAIT_JUDGEMENT",
                   [NSString stringWithFormat:@"group=%d judge=%d hitBeat=%d", groupIndex, judgeLevel, isHitBeat ? 1 : 0]);
        }
    }
}

static void StartTimer() {
    if (gTimer) return;
    gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gTimer, dispatch_time(DISPATCH_TIME_NOW, 0), 8ull * NSEC_PER_MSEC, 1ull * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(gTimer, ^{
        Tick();
    });
    dispatch_resume(gTimer);
}

static void StopTimer() {
    if (!gTimer) return;
    dispatch_source_cancel(gTimer);
    gTimer = nullptr;
}

static NSString *DiagFilterLines(NSString *text, NSString *feature) {
    if (text.length == 0) return @"";
    if (feature.length == 0 || [feature isEqualToString:@"ALL"]) return text;
    NSString *needle = [NSString stringWithFormat:@"[F:%@]", feature];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if ([line rangeOfString:needle].location != NSNotFound) [out addObject:line];
    }
    return [out componentsJoinedByString:@"\n"];
}

static NSString *DiagLogForSelection(NSString *feature, NSString *session) {
    NSString *suffix = @"current";
    if ([session isEqualToString:@"Previous"]) suffix = @"previous";
    else if ([session isEqualToString:@"Last Crash/Unclean"]) suffix = @"crash";

    if ([feature isEqualToString:@"Boot"]) {
        NSString *boot = ReadText(Path([NSString stringWithFormat:@"Boot.%@.log", suffix]));
        return boot.length ? boot : @"<empty>";
    }
    NSString *text = ReadText(Path([NSString stringWithFormat:@"Feature.%@.log", suffix]));
    if ([suffix isEqualToString:@"current"]) {
        NSString *roll = ReadText(Path(@"Feature.roll.log"));
        if (roll.length) text = [NSString stringWithFormat:@"%@\n%@", roll, text ?: @""];
    }
    NSString *filtered = DiagFilterLines(text, feature ?: @"ALL");
    return filtered.length ? filtered : @"<empty>";
}

static NSString *DiagRunSelfTestInternal() {
    BOOL dirExists = [[NSFileManager defaultManager] fileExistsAtPath:LogsDir()];
    NSString *probe = Path(@".logger-selftest.tmp");
    BOOL writePass = DurableReplace(probe, @"TNMD_CHECK_LOG_SELF_TEST\n");
    [[NSFileManager defaultManager] removeItemAtPath:probe error:NULL];
    BOOL apiPass = ResolveAPIs();
    BOOL bindPass = gBindingsReady;
    if ([NSThread isMainThread]) bindPass = BindGame();
    NSString *result = [NSString stringWithFormat:
                        @"CHECK LOG SELF-TEST\n"
                        @"Build             PASS %@\n"
                        @"LogDirectory      %@ path=%@\n"
                        @"LoggerWrite       %@\n"
                        @"RuntimeExports    %@\n"
                        @"AutoBindings      %@\n"
                        @"SkinBindings      %@\n"
                        @"VIPBindings       %@\n"
                        @"Session           PASS %@\n"
                        @"TraceCorrelation  PASS seq=%llu\n"
                        @"SELF_TEST_RESULT=%@\n"
                        @"FIRST_BLOCKER=%@\n",
                        kBuildTag,
                        dirExists ? @"PASS" : @"FAIL", LogsDir(),
                        writePass ? @"PASS" : @"FAIL",
                        apiPass ? @"PASS" : @"FAIL",
                        bindPass ? @"PASS" : @"UNKNOWN/NOT_READY",
                        gSkinBindingsReady ? @"PASS" : @"UNKNOWN/NOT_READY",
                        gVIPBindingsReady ? @"PASS" : @"UNKNOWN/NOT_READY",
                        gDiagSessionId ?: @"-", (unsigned long long)gSeq,
                        (dirExists && writePass && apiPass) ? @"PASS" : @"FAIL",
                        !dirExists ? @"LogDirectory" : (!writePass ? @"LoggerWrite" : (!apiPass ? @"RuntimeExports" : @"NONE"))];
    DurableReplace(Path(@"SelfTest.txt"), result);
    return result;
}

static NSString *DiagCompareBaselineInternal() {
    NSString *dir = Path(@"BaselineGood");
    NSString *baseMeta = ReadText([dir stringByAppendingPathComponent:@"Diagnostic.meta.txt"]);
    NSString *baseStage = ReadText([dir stringByAppendingPathComponent:@"SemanticStageMap.txt"]);
    if (baseMeta.length == 0) return @"BASELINE_AVAILABLE=NO\nMark Baseline Good trước khi compare.\n";
    BOOL buildMatch = [baseMeta rangeOfString:[NSString stringWithFormat:@"MOD_BUILD=%@", kBuildTag]].location != NSNotFound;
    NSString *nowStage = DiagSemanticStageMapInternal();
    BOOL stageSame = [baseStage isEqualToString:nowStage];
    NSString *result = [NSString stringWithFormat:
                        @"BASELINE_AVAILABLE=YES\nBUILD_MATCH=%@\nSTAGE_MAP_IDENTICAL=%@\n\n--- BASELINE STAGE MAP ---\n%@\n--- CURRENT STAGE MAP ---\n%@\n",
                        buildMatch ? @"YES" : @"NO", stageSame ? @"YES" : @"NO",
                        baseStage.length ? baseStage : @"<empty>", nowStage];
    DurableReplace(Path(@"BaselineDiff.txt"), result);
    return result;
}

static NSString *DiagMarkBaselineGoodInternal() {
    NSString *dir = Path(@"BaselineGood");
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:dir error:NULL];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    DurableReplace([dir stringByAppendingPathComponent:@"Diagnostic.meta.txt"], DiagMetaText());
    DurableReplace([dir stringByAppendingPathComponent:@"StageMap.txt"], DiagStageMapInternal());
    DurableReplace([dir stringByAppendingPathComponent:@"SemanticStageMap.txt"], DiagSemanticStageMapInternal());
    CopyIfExists(Path(@"Feature.current.log"), [dir stringByAppendingPathComponent:@"Feature.current.log"]);
    NSString *result = [NSString stringWithFormat:@"BASELINE_MARKED=YES\nSESSION=%@\nPATH=%@\n", gDiagSessionId ?: @"-", dir];
    DurableReplace([dir stringByAppendingPathComponent:@"Baseline.txt"], result);
    return result;
}

static NSString *DiagExportFixPackInternal() {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *cur = Path(@"FixPack.current");
    NSString *prev = Path(@"FixPack.previous");
    [fm removeItemAtPath:prev error:NULL];
    if ([fm fileExistsAtPath:cur]) [fm moveItemAtPath:cur toPath:prev error:NULL];
    [fm createDirectoryAtPath:cur withIntermediateDirectories:YES attributes:nil error:NULL];

    DiagWriteMetaAndHealth();
    DurableReplace(Path(@"StageMap.txt"), DiagStageMapInternal());
    DurableReplace(Path(@"ResolverSnapshot.txt"), DiagResolverSnapshot());
    DurableReplace(Path(@"InstanceSnapshot.txt"), DiagInstanceSnapshot());
    DurableReplace(Path(@"FeatureConfigSnapshot.txt"), DiagConfigSnapshot());
    DurableReplace(Path(@"DependencyHealth.txt"), DiagDependencyHealth());
    DurableReplace(Path(@"ReproTimeline.txt"), TailLines(ReadText(Path(@"Feature.current.log")), 140));
    DurableReplace(Path(@"FAILURE_SUMMARY.txt"), DiagFailureSummaryInternal());

    NSArray *files = @[@"FAILURE_SUMMARY.txt", @"Diagnostic.meta.txt", @"Feature.current.log", @"Feature.roll.log", @"Feature.previous.log",
                       @"Feature.crash.log", @"Boot.current.log", @"Boot.previous.log", @"Boot.crash.log",
                       @"ResolverSnapshot.txt", @"InstanceSnapshot.txt", @"FeatureConfigSnapshot.txt",
                       @"DependencyHealth.txt", @"ReproTimeline.txt", @"CrashContext.txt", @"LastFailure.txt",
                       @"BaselineDiff.txt", @"LoggerHealth.txt", @"SelfTest.txt"];
    NSMutableArray *included = [NSMutableArray array];
    NSMutableArray *missing = [NSMutableArray array];
    for (NSString *name in files) {
        NSString *src = Path(name);
        if ([fm fileExistsAtPath:src]) {
            CopyIfExists(src, [cur stringByAppendingPathComponent:name]);
            [included addObject:name];
        } else if ([name isEqualToString:@"Feature.current.log"] || [name isEqualToString:@"Diagnostic.meta.txt"] ||
                   [name isEqualToString:@"LoggerHealth.txt"] || [name isEqualToString:@"FAILURE_SUMMARY.txt"]) {
            [missing addObject:name];
        }
    }
    BOOL ready = missing.count == 0;
    NSString *manifest = [NSString stringWithFormat:
                          @"FIX_PACK_SCHEMA=2\nCREATED_AT=%@\nSESSION_ID=%@\nTRACE_ID=%@\nGAME_BUILD=%@\nMENU_BUILD=%@\nFILES_INCLUDED=%@\nFILES_MISSING=%@\nREDACTIONS_APPLIED=YES(no raw auth/session/receipt secrets logged)\nFIX_PACK_READY=%@\n",
                          TimeString(), gDiagSessionId ?: @"-", DiagStateForFeature(gDiagLastFailureFeature ?: @"AutoPerfect")[@"trace"] ?: @"-",
                          kBuildTag, kBuildTag, [included componentsJoinedByString:@","],
                          missing.count ? [missing componentsJoinedByString:@","] : @"NONE", ready ? @"YES" : @"NO"];
    DurableReplace([cur stringByAppendingPathComponent:@"FIX_PACK_MANIFEST.txt"], manifest);
    gDiagLastExportPath = cur;
    return [NSString stringWithFormat:@"FIX_PACK_READY=%@\nPATH=%@\nMISSING=%@\n", ready ? @"YES" : @"NO", cur,
            missing.count ? [missing componentsJoinedByString:@","] : @"NONE"];
}

static void DiagRotateSessionInternal(BOOL manual) {
    DiagClearSessionMarker();
    RotateOne(@"Boot");
    RotateOne(@"AutoPerfect");
    RotateOne(@"Feature");
    gDiagPreviousSessionId = gDiagSessionId;
    gDiagSessionId = DiagMakeSessionId();
    gDiagSessionWallStart = TimeString();
    gDiagSessionMonoStart = CACurrentMediaTime();
    gDiagPreviousEndReason = manual ? @"MANUAL_ROTATE" : @"INIT";
    gDiagLastFailureFeature = @"NONE";
    gDiagLastFailureTrace = @"-";
    gDiagLastFailureStage = @"NONE";
    gDiagLastFailureReason = @"NONE";
    gDiagLastFailureState = @"NONE";
    gDiagLastFailureEvidence = @"-";
    gDiagLastFailureLastGood = @"NONE";
    gDiagLastFailureAction = @"-";
    gDiagTraceCounter = 0;
    gDiagFeatureState = [NSMutableDictionary dictionary];
    gSeq = 0;
    DiagWriteSessionMarker();
    DiagWriteMetaAndHealth();
    Boot(@"SESSION_START", manual ? @"MANUAL_ROTATE" : @"INIT");
    DiagBeginTrace(@"CheckLog", manual ? @"RotateSession" : @"Startup");
    DiagRecord(@"CheckLog", @"SESSION_HEADER", @"READY", manual ? @"SESSION_ROTATED" : @"SESSION_STARTED", [NSString stringWithFormat:@"build=%@ arch=%@", kBuildTag, DiagArch()]);
}

static void Initialize() {
    if (gInitialized) return;
    gInitialized = YES;
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:LogsDir() withIntermediateDirectories:YES attributes:nil error:NULL];

    NSString *oldMarker = ReadText(Path(@"Session.active"));
    BOOL previousUnclean = oldMarker.length > 0;
    gDiagPreviousSessionId = [[oldMarker componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] firstObject];

    RotateOne(@"Boot");
    RotateOne(@"AutoPerfect");
    RotateOne(@"Feature");
    if (previousUnclean) {
        CopyIfExists(Path(@"Boot.previous.log"), Path(@"Boot.crash.log"));
        CopyIfExists(Path(@"Feature.previous.log"), Path(@"Feature.crash.log"));
        CopyIfExists(Path(@"LastFailure.txt"), Path(@"LastFailure.crash.txt"));
        CopyIfExists(Path(@"CrashContext.txt"), Path(@"CrashContext.previous.txt"));
    }

    gDiagSessionId = DiagMakeSessionId();
    gDiagSessionWallStart = TimeString();
    gDiagSessionMonoStart = CACurrentMediaTime();
    gDiagPreviousEndReason = previousUnclean ? @"UNCLEAN_OR_CRASH_CANDIDATE" : @"CLEAN_OR_BACKGROUND_TERMINATION";
    gDiagTraceCounter = 0;
    gDiagFeatureState = [NSMutableDictionary dictionary];
    gSeq = 0;
    DiagWriteSessionMarker();
    DiagWriteMetaAndHealth();

    static dispatch_once_t lifecycleOnce;
    dispatch_once(&lifecycleOnce, ^{
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(__unused NSNotification *n) {
            if (gInitialized) DiagWriteSessionMarker();
        }];
        [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(__unused NSNotification *n) {
            DiagClearSessionMarker();
            DiagWriteMetaAndHealth();
        }];
        [nc addObserverForName:UIApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(__unused NSNotification *n) {
            DiagClearSessionMarker();
            DiagWriteMetaAndHealth();
        }];
    });

    Boot(@"INIT", previousUnclean ? @"MODULE_LOADED_PREVIOUS_UNCLEAN" : @"MODULE_LOADED");
    DiagBeginTrace(@"CheckLog", @"Startup");
    DiagRecord(@"CheckLog", @"SESSION_HEADER", @"READY", previousUnclean ? @"SESSION_STARTED_PREVIOUS_UNCLEAN" : @"SESSION_STARTED",
               [NSString stringWithFormat:@"build=%@ previous=%@ arch=%@", kBuildTag, gDiagPreviousSessionId ?: @"-", DiagArch()]);
    gStatus = @"OFF • READY_TO_ENABLE";
    if (!gSkinPinnedByType) gSkinPinnedByType = [NSMutableDictionary dictionary];
    gSkinStatus = @"IDLE • LOCAL_ONLY";
}

} // namespace TNMDAP

void TNMDAutoPerfectInitialize(void) {
    TNMDAP::Initialize();
}

void TNMDAutoPerfectSetUILogSink(TNMDAutoPerfectUILogSink sink) {
    TNMDAP::Initialize();
    TNMDAP::gUILogSink = [sink copy];
}

void TNMDAutoPerfectSetEnabled(BOOL enabled) {
    TNMDAP::Initialize();
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ TNMDAutoPerfectSetEnabled(enabled); });
        return;
    }
    if (TNMDAP::gEnabled == enabled) return;
    TNMDAP::DiagBeginTrace(@"AutoPerfect", enabled ? @"ToggleOn" : @"ToggleOff");
    TNMDAP::gEnabled = enabled;
    if (enabled) {
        TNMDAP::Emit(@"TOGGLE", @"ARMED", @"USER_ENABLED", [NSString stringWithFormat:@"build=%@ mode=SELF_INPUT no_patch no_raw_hook", TNMDAP::kBuildTag]);
        TNMDAP::StartTimer();
    } else {
        TNMDAP::Emit(@"TOGGLE", @"OFF", @"USER_DISABLED");
        TNMDAP::RestoreFullNativeAutoPlayIfCurrent();
        TNMDAP::RestoreStarlightBubbleAutoPlayIfOwned();
        TNMDAP::StopTimer();
        TNMDAP::gUIInstance = nullptr;
        TNMDAP::gLastGroup = nullptr;
        TNMDAP::gLastGroupIndex = -1;
        TNMDAP::gPendingArrowIndex = -1;
        TNMDAP::gPendingArrowSentAt = 0.0;
        TNMDAP::gPendingArrowRetries = 0;
        TNMDAP::gNextArrowAllowedAt = 0.0;
        TNMDAP::gBeatDispatched = NO;
        TNMDAP::gBeatDispatchedAt = 0.0;
        TNMDAP::gHeldBeatButton = nullptr;
        TNMDAP::gBeatButtonReleaseAt = 0.0;
        TNMDAP::gActiveProfile = @"none";
        TNMDAP::gActiveFlag = -1;
        TNMDAP::gStatus = @"OFF • USER_DISABLED";
    }
}


void TNMDAutoPerfectSetArrowPacingEnabled(BOOL enabled) {
    TNMDAP::Initialize();
    TNMDAP::gArrowPacingEnabled = enabled;
    TNMDAP::gNextArrowAllowedAt = 0.0;
}

void TNMDAutoPerfectSetBeatJitterEnabled(BOOL enabled) {
    TNMDAP::Initialize();
    TNMDAP::gBeatJitterEnabled = enabled;
    if (!enabled) TNMDAP::gBeatJitterSeconds = 0.0f;
}

void TNMDAutoPerfectSetBeatOneShotEnabled(BOOL enabled) {
    TNMDAP::Initialize();
    TNMDAP::gBeatOneShotEnabled = enabled;
}

void TNMDAutoPerfectSetArrowAckGateEnabled(BOOL enabled) {
    TNMDAP::Initialize();
    TNMDAP::gArrowAckGateEnabled = enabled;
    if (!enabled) {
        TNMDAP::gPendingArrowIndex = -1;
        TNMDAP::gPendingArrowSentAt = 0.0;
        TNMDAP::gPendingArrowRetries = 0;
    }
}

BOOL TNMDAutoPerfectIsEnabled(void) {
    return TNMDAP::gEnabled;
}

NSString *TNMDAutoPerfectStatusText(void) {
    TNMDAP::Initialize();
    return TNMDAP::gStatus ?: @"UNKNOWN";
}

NSString *TNMDAutoPerfectModeText(void) {
    TNMDAP::Initialize();
    return [NSString stringWithFormat:@"mode=%d • %@ • family=%@ • source=%@%@",
            TNMDAP::gDetectedMode, TNMDAP::ModeNameFor(TNMDAP::gDetectedMode),
            TNMDAP::ModeFamilyFor(TNMDAP::gDetectedMode), TNMDAP::gDetectedModeSource ?: @"NONE",
            TNMDAP::gDetectedFallbackFlag >= 0 ? [NSString stringWithFormat:@" • flag=%d", TNMDAP::gDetectedFallbackFlag] : @""];
}

NSString *TNMDAutoPerfectBuildText(void) {
    TNMDAP::Initialize();
    return TNMDAP::kBuildTag;
}

NSString *TNMDAutoPerfectLogDirectory(void) {
    TNMDAP::Initialize();
    return TNMDAP::LogsDir();
}

NSString *TNMDAutoPerfectDiagnosticText(void) {
    TNMDAP::Initialize();
    TNMDAP::DiagWriteMetaAndHealth();
    NSMutableString *s = [NSMutableString string];
    [s appendString:@"===== FAILURE SUMMARY =====\n"];
    [s appendString:TNMDAP::DiagFailureSummaryInternal()];
    [s appendString:@"\n===== STAGE MAP =====\n"];
    [s appendString:TNMDAP::DiagStageMapInternal()];
    [s appendString:@"\n===== DIAGNOSTIC META =====\n"];
    [s appendString:TNMDAP::DiagMetaText()];
    [s appendString:@"\n===== LOGGER HEALTH =====\n"];
    [s appendString:TNMDAP::DiagLoggerHealthTextInternal()];
    [s appendFormat:@"\nAuto Perfect status: %@\nDetected mode: %@\nSkin status: %@\nVIP Visual status: %@\nLog directory: %@\n\n",
     TNMDAutoPerfectStatusText(), TNMDAutoPerfectModeText(), TNMDSkinStatusText(), TNMDVIPVisualStatusText(), TNMDAP::LogsDir()];
    NSArray<NSString *> *files = @[@"Feature.current.log", @"Feature.roll.log", @"Feature.previous.log", @"Feature.crash.log",
                                   @"Boot.current.log", @"Boot.previous.log", @"Boot.crash.log",
                                   @"LastFailure.txt", @"CrashContext.txt", @"ResolverSnapshot.txt",
                                   @"InstanceSnapshot.txt", @"DependencyHealth.txt", @"SelfTest.txt"];
    for (NSString *name in files) {
        [s appendFormat:@"===== %@ =====\n", name];
        NSString *text = TNMDAP::ReadText(TNMDAP::Path(name));
        [s appendString:text.length ? text : @"<empty>\n"];
        if (![s hasSuffix:@"\n"]) [s appendString:@"\n"];
        [s appendString:@"\n"];
    }
    return s;
}

void TNMDAutoPerfectSnapshotNow(void) {
    TNMDAP::Initialize();
    TNMDAP::DiagRecord(@"CheckLog", @"ACTION", @"RUNNING", @"SNAPSHOT_REQUESTED", nil);
    if (TNMDAP::BindGame()) {
        Il2CppObject *module = nullptr;
        NSString *source = nil;
        int32_t fallbackFlag = -1;
        int32_t mode = TNMDAP::ProbeResolvedMode(&module, &source, &fallbackFlag);
        TNMDAP::PublishModeDetection(mode, source, fallbackFlag, true);
    }
    NSString *details = [NSString stringWithFormat:@"build=%@ enabled=%d bindings=%d detectedMode=%d modeName=%@ family=%@ modeSource=%@ fallbackFlag=%d profile=%@ flag=%d ui=%p group=%p groupIndex=%d judge=%d arrows=%d beatAttempts=%d bubbleLogic=%p bubbleCtrl=%p bubbleOwned=%d bubbleCombo=%u bubblePerfect=%d skinBindings=%d skinPinned=%lu skinLastPlayer=%p skinLastRole=%u skinGUI=stage:%@/count:%d/models:%d/loaded:%d/list:%@ skinPending=%d skinTarget=%@ skinAllBody=%u skinPinVerify=%d vipBindings=%d vipRequested=%ld vipOriginal=%ld vipTrue=%ld vipLocalRole=%u vipTarget=%@ vipApplied=%d vipDirectTop=%d vipSpawnQueued=%d vipBillboard=%d vipRoleAware=%d vipIsland=%d vipPlayerHeads=%d vipHeadName=%d vipIcons=%d",
                         TNMDAP::kBuildTag, TNMDAP::gEnabled ? 1 : 0, TNMDAP::gBindingsReady ? 1 : 0,
                         TNMDAP::gDetectedMode, TNMDAP::ModeNameFor(TNMDAP::gDetectedMode), TNMDAP::ModeFamilyFor(TNMDAP::gDetectedMode),
                         TNMDAP::gDetectedModeSource ?: @"NONE", TNMDAP::gDetectedFallbackFlag,
                         TNMDAP::gActiveProfile ?: @"none", TNMDAP::gActiveFlag,
                         TNMDAP::gUIInstance, TNMDAP::gLastGroup, TNMDAP::gLastGroupIndex,
                         TNMDAP::gLastJudgeLevel, TNMDAP::gArrowAttempts, TNMDAP::gBeatAttempts,
                         TNMDAP::gBubbleDanceLogic, TNMDAP::gBubbleNoteCtrl, TNMDAP::gBubbleAutoPlayOwned ? 1 : 0,
                         TNMDAP::gBubbleLastCombo, TNMDAP::gBubbleLastPerfectCount,
                         TNMDAP::gSkinBindingsReady ? 1 : 0, (unsigned long)TNMDAP::gSkinPinnedByType.count, TNMDAP::CachedSkinPlayer(), TNMDAP::gSkinLastRoleId, TNMDAP::gSkinLastGUIStage ?: @"none", TNMDAP::gSkinLastGUIListCount, TNMDAP::gSkinLastGUINonNullModels, TNMDAP::gSkinLastGUILoadedModels, TNMDAP::gSkinLastGUIListPath ?: @"none", TNMDAP::gSkinPendingApply ? 1 : 0, TNMDAP::gSkinLastTargetSource ?: @"none",
                         [TNMDAP::gSkinPinnedByType[@6] unsignedIntValue], TNMDAP::gSkinB.playerIsPuton ? 1 : 0,
                         TNMDAP::gVIPBindingsReady ? 1 : 0, (long)TNMDAP::gVIPRequestedLevel, (long)TNMDAP::gVIPOriginalLevel,
                         (long)TNMDAP::gVIPLastTrueLevel, TNMDAP::gVIPLastLocalRole, TNMDAP::gVIPLastTarget ?: @"none",
                         TNMDAP::gVIPLastAppliedCount, TNMDAP::gVIPLastDirectTopMatches, TNMDAP::gVIPLastSpawnQueued,
                         TNMDAP::gVIPLastBillboardMatches, TNMDAP::gVIPLastRoleAwareMatches, TNMDAP::gVIPLastIslandMatches,
                         TNMDAP::gVIPLastPlayerHeadCount, TNMDAP::gVIPLastHeadNameMatches, TNMDAP::gVIPLastIconCount];
    TNMDAP::Emit(@"HEALTH", TNMDAP::gEnabled ? @"RUNNING" : @"OFF", @"MANUAL_SNAPSHOT", details);
    TNMDAP::DurableReplace(TNMDAP::Path(@"ResolverSnapshot.txt"), TNMDAP::DiagResolverSnapshot());
    TNMDAP::DurableReplace(TNMDAP::Path(@"InstanceSnapshot.txt"), TNMDAP::DiagInstanceSnapshot());
    TNMDAP::DurableReplace(TNMDAP::Path(@"FeatureConfigSnapshot.txt"), TNMDAP::DiagConfigSnapshot());
    TNMDAP::DurableReplace(TNMDAP::Path(@"DependencyHealth.txt"), TNMDAP::DiagDependencyHealth());
    TNMDAP::DurableReplace(TNMDAP::Path(@"StageMap.txt"), TNMDAP::DiagStageMapInternal());
    TNMDAP::DiagWriteMetaAndHealth();
    TNMDAP::DiagRecord(@"CheckLog", @"COMPLETE", @"COMPLETE", @"SNAPSHOT_COMPLETE", nil);
}

void TNMDAutoPerfectClearLogs(void) {
    TNMDAP::Initialize();
    // Compatibility behavior is intentionally safe in V10.22: only current-session logs are cleared.
    // Previous/crash evidence, baseline, and FixPack are preserved.
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in @[@"AutoPerfect.current.log", @"Feature.current.log", @"Boot.current.log"]) {
        [fm removeItemAtPath:TNMDAP::Path(name) error:NULL];
    }
    TNMDAP::DiagBeginTrace(@"CheckLog", @"ClearCurrentSessionLogs");
    TNMDAP::Boot(@"LOG_CLEAR_CURRENT", @"USER_REQUEST_PRESERVE_PREVIOUS_CRASH");
    TNMDAP::DiagRecord(@"CheckLog", @"COMPLETE", @"COMPLETE", @"CURRENT_LOGS_CLEARED_PREVIOUS_PRESERVED", nil);
}

NSArray<NSString *> *TNMDDiagnosticFeatureOptions(void) {
    return @[@"ALL", @"AutoPerfect", @"Skin", @"VIPVisual", @"HeadFX", @"CheckLog", @"Boot"];
}

NSArray<NSString *> *TNMDDiagnosticSessionOptions(void) {
    return @[@"Current", @"Previous", @"Last Crash/Unclean"];
}

NSString *TNMDDiagnosticTopStatusText(void) {
    TNMDAP::Initialize();
    NSString *logger = (TNMDAP::gDiagOpenFailures || TNMDAP::gDiagWriteFailures || TNMDAP::gDiagFlushFailures || TNMDAP::gDiagDroppedEvents) ? @"DEGRADED" : @"OK";
    return [NSString stringWithFormat:@"SID %@ • Logger %@ • LastFail %@/%@ • %@",
            TNMDAP::gDiagSessionId ?: @"-", logger, TNMDAP::gDiagLastFailureFeature ?: @"NONE",
            TNMDAP::gDiagLastFailureStage ?: @"NONE", TNMDAP::gDiagLastFailureReason ?: @"NONE"];
}

NSString *TNMDDiagnosticFailureSummary(void) {
    TNMDAP::Initialize();
    return TNMDAP::DiagFailureSummaryInternal();
}

NSString *TNMDDiagnosticStageMapText(void) {
    TNMDAP::Initialize();
    return TNMDAP::DiagStageMapInternal();
}

NSString *TNMDDiagnosticLoggerHealthText(void) {
    TNMDAP::Initialize();
    return TNMDAP::DiagLoggerHealthTextInternal();
}

NSString *TNMDDiagnosticTextForSelection(NSString *feature, NSString *session) {
    TNMDAP::Initialize();
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"SELECTED_FEATURE=%@\nSELECTED_SESSION=%@\n\n", feature ?: @"ALL", session ?: @"Current"];
    [out appendString:@"===== FAILURE SUMMARY =====\n"];
    [out appendString:TNMDAP::DiagFailureSummaryInternal()];
    [out appendString:@"\n===== STAGE MAP =====\n"];
    [out appendString:TNMDAP::DiagStageMapInternal()];
    [out appendString:@"\n===== SELECTED LOG =====\n"];
    [out appendString:TNMDAP::DiagLogForSelection(feature ?: @"ALL", session ?: @"Current")];
    return out;
}

NSString *TNMDDiagnosticRunSelfTest(void) {
    TNMDAP::Initialize();
    TNMDAP::DiagBeginTrace(@"CheckLog", @"RunSelfTest");
    TNMDAP::DiagRecord(@"CheckLog", @"ACTION", @"RUNNING", @"SELF_TEST_BEGIN", nil);
    NSString *result = TNMDAP::DiagRunSelfTestInternal();
    TNMDAP::DiagRecord(@"CheckLog", @"COMPLETE", @"COMPLETE", [result rangeOfString:@"SELF_TEST_RESULT=PASS"].location != NSNotFound ? @"SELF_TEST_PASS" : @"SELF_TEST_FAIL", nil);
    return result;
}

NSString *TNMDDiagnosticExportFixPack(void) {
    TNMDAP::Initialize();
    TNMDAP::DiagBeginTrace(@"CheckLog", @"ExportFixPack");
    TNMDAP::DiagRecord(@"CheckLog", @"ACTION", @"RUNNING", @"FIX_PACK_EXPORT_BEGIN", nil);
    NSString *result = TNMDAP::DiagExportFixPackInternal();
    TNMDAP::DiagRecord(@"CheckLog", @"COMPLETE", @"COMPLETE", [result rangeOfString:@"FIX_PACK_READY=YES"].location != NSNotFound ? @"FIX_PACK_READY" : @"FIX_PACK_INCOMPLETE", result);
    return result;
}

NSString *TNMDDiagnosticMarkBaselineGood(void) {
    TNMDAP::Initialize();
    TNMDAP::DiagBeginTrace(@"CheckLog", @"MarkBaselineGood");
    NSString *result = TNMDAP::DiagMarkBaselineGoodInternal();
    TNMDAP::DiagRecord(@"CheckLog", @"COMPLETE", @"COMPLETE", @"BASELINE_MARKED_GOOD", result);
    return result;
}

NSString *TNMDDiagnosticCompareBaseline(void) {
    TNMDAP::Initialize();
    TNMDAP::DiagBeginTrace(@"CheckLog", @"CompareBaseline");
    NSString *result = TNMDAP::DiagCompareBaselineInternal();
    TNMDAP::DiagRecord(@"CheckLog", @"COMPLETE", @"COMPLETE", @"BASELINE_COMPARE_COMPLETE", nil);
    return result;
}

void TNMDDiagnosticRotateSession(void) {
    TNMDAP::Initialize();
    TNMDAP::DiagRotateSessionInternal(YES);
}


NSArray<NSString *> *TNMDVIPVisualLevelOptions(void) {
    TNMDAP::Initialize();
    if ([NSThread isMainThread]) TNMDAP::BindGame();
    uint32_t maxLevel = TNMDAP::gVIPBindingsReady ? TNMDAP::VIPMaxLevel() : 18;
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    for (uint32_t i = 0; i <= maxLevel; i++) [items addObject:[NSString stringWithFormat:@"VIP %u", i]];
    return [items copy];
}

BOOL TNMDVIPVisualSetLevel(NSInteger level) {
    TNMDAP::Initialize();
    TNMDAP::DiagBeginTrace(@"VIPVisual", @"SetLevel");
    if (![NSThread isMainThread]) return NO;
    if (!TNMDAP::BindGame() || !TNMDAP::gVIPBindingsReady) {
        TNMDAP::VIPEmit(@"WAIT_PREREQ", @"VIP_VISUAL_BINDINGS_NOT_READY");
        return NO;
    }
    uint32_t maxLevel = TNMDAP::VIPMaxLevel();
    if (level < 0 || (uint32_t)level > maxLevel) {
        TNMDAP::VIPEmit(@"BLOCKED", @"VIP_LEVEL_OUT_OF_RANGE", [NSString stringWithFormat:@"requested=%ld max=%u", (long)level, maxLevel]);
        return NO;
    }
    TNMDAP::gVIPRequestedLevel = level;
    int applied = TNMDAP::ApplyVIPVisualSweep((int32_t)level, true, @"VIP_VISUAL_APPLIED");
    TNMDAP::StartVIPTimer();
    if (applied == 0) {
        TNMDAP::VIPEmit(@"WAIT_PREREQ", @"VIP_UI_TARGET_QUEUED",
                        [NSString stringWithFormat:@"level=%ld localRole=%u trueVip=%ld original=%ld directTop=%d spawnQueued=%d billboards=%d roleAware=%d island=%d playerHeads=%d headNameMatches=%d vipIcons=%d applied=%d queued=1 localOnly=1 serverState=0",
                         (long)level, TNMDAP::gVIPLastLocalRole, (long)TNMDAP::gVIPLastTrueLevel, (long)TNMDAP::gVIPOriginalLevel,
                         TNMDAP::gVIPLastDirectTopMatches, TNMDAP::gVIPLastSpawnQueued, TNMDAP::gVIPLastBillboardMatches, TNMDAP::gVIPLastRoleAwareMatches, TNMDAP::gVIPLastIslandMatches, TNMDAP::gVIPLastPlayerHeadCount, TNMDAP::gVIPLastHeadNameMatches, TNMDAP::gVIPLastIconCount, TNMDAP::gVIPLastAppliedCount]);
        return NO;
    }
    return YES;
}

BOOL TNMDVIPVisualRestore(void) {
    TNMDAP::Initialize();
    TNMDAP::DiagBeginTrace(@"VIPVisual", @"Restore");
    if (![NSThread isMainThread]) return NO;
    NSInteger original = TNMDAP::gVIPOriginalLevel;
    TNMDAP::gVIPRequestedLevel = -1;
    if (original < 0) {
        // Attempt one read-only identity refresh before declaring original unavailable.
        uint32_t role = 0;
        int32_t trueVip = -1;
        if (TNMDAP::ReadLocalVIPIdentity(role, trueVip) && trueVip >= 0) {
            TNMDAP::gVIPOriginalLevel = trueVip;
            original = trueVip;
            TNMDAP::gVIPLastLocalRole = role;
            TNMDAP::gVIPLastTrueLevel = trueVip;
        }
    }
    if (original < 0) {
        TNMDAP::gVIPStatus = @"OFF • ORIGINAL_NOT_CAPTURED";
        TNMDAP::VIPEmit(@"OFF", @"VIP_VISUAL_DISABLED_NO_ORIGINAL");
        return YES;
    }
    int applied = TNMDAP::ApplyVIPVisualSweep((int32_t)original, false, @"VIP_VISUAL_RESTORED");
    TNMDAP::gVIPStatus = @"OFF • ORIGINAL_RESTORED";
    TNMDAP::VIPEmit(@"OFF", applied > 0 ? @"VIP_VISUAL_RESTORED" : @"VIP_VISUAL_DISABLED_TARGET_GONE",
                    [NSString stringWithFormat:@"original=%ld targets=%@ localOnly=1 serverState=0", (long)original, TNMDAP::gVIPLastTarget ?: @"none"]);
    return YES;
}

NSString *TNMDVIPVisualStatusText(void) {
    TNMDAP::Initialize();
    return TNMDAP::gVIPStatus ?: @"UNKNOWN";
}

BOOL TNMDHeadReloadCatalogs(void) {
    TNMDAP::Initialize();
    TNMDAP::DiagBeginTrace(@"HeadFX", @"ReloadCatalogs");
    if (![NSThread isMainThread]) return NO;
    TNMDAP::gHeadNameEffectCatalog = nil;
    TNMDAP::gHeadTitleCatalog = nil;
    TNMDAP::gHeadRingCatalog = nil;
    if (!TNMDAP::BindGame()) {
        TNMDAP::gHeadStatus = @"WAIT_PREREQ • GAME_CONFIG_NOT_READY";
        TNMDAP::DiagRecord(@"HeadFX", @"SOURCE", @"WAIT_PREREQ", @"HEADFX_CONFIG_NOT_READY", nil);
        return NO;
    }
    NSArray *nameFx = TNMDAP::BuildHeadNameEffectCatalog();
    NSArray *titles = TNMDAP::BuildHeadTitleCatalog();
    NSArray *rings = TNMDAP::BuildHeadRingCatalog();
    BOOL ready = (nameFx.count > 1 || titles.count > 1 || rings.count > 1);
    TNMDAP::gHeadStatus = ready
        ? [NSString stringWithFormat:@"READY • Tên:%lu • Danh hiệu:%lu • Vòng:%lu",
           (unsigned long)(nameFx.count > 0 ? nameFx.count - 1 : 0),
           (unsigned long)(titles.count > 0 ? titles.count - 1 : 0),
           (unsigned long)(rings.count > 0 ? rings.count - 1 : 0)]
        : @"WAIT_PREREQ • CONFIG_ARRAYS_EMPTY";
    TNMDAP::DiagRecord(@"HeadFX", @"SOURCE", ready ? @"READY" : @"WAIT_PREREQ",
                       ready ? @"HEADFX_CATALOG_RELOADED" : @"HEADFX_CATALOG_EMPTY",
                       [NSString stringWithFormat:@"nameFx=%lu titles=%lu rings=%lu",
                        (unsigned long)nameFx.count, (unsigned long)titles.count, (unsigned long)rings.count]);
    return ready;
}

NSArray<NSString *> *TNMDHeadNameEffectOptions(void) {
    TNMDAP::Initialize();
    if ([NSThread isMainThread]) TNMDAP::BindGame();
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    for (NSDictionary *entry in TNMDAP::BuildHeadNameEffectCatalog()) {
        NSString *name = entry[@"name"] ?: @"-";
        [items addObject:name];
    }
    return [items copy];
}

NSArray<NSString *> *TNMDHeadTitleOptions(void) {
    TNMDAP::Initialize();
    if ([NSThread isMainThread]) TNMDAP::BindGame();
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    for (NSDictionary *entry in TNMDAP::BuildHeadTitleCatalog()) {
        NSString *name = entry[@"name"] ?: @"-";
        [items addObject:name];
    }
    return [items copy];
}

NSArray<NSString *> *TNMDHeadRingOptions(void) {
    TNMDAP::Initialize();
    if ([NSThread isMainThread]) TNMDAP::BindGame();
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    for (NSDictionary *entry in TNMDAP::BuildHeadRingCatalog()) {
        NSString *name = entry[@"name"] ?: @"-";
        [items addObject:name];
    }
    return [items copy];
}

BOOL TNMDHeadNameEffectSet(NSInteger selectedIndex) {
    TNMDAP::Initialize();
    TNMDAP::DiagBeginTrace(@"HeadFX", @"SetNameEffect");
    if (![NSThread isMainThread]) return NO;
    NSArray *catalog = TNMDAP::BuildHeadNameEffectCatalog();
    if (selectedIndex < 0 || selectedIndex >= (NSInteger)catalog.count) return NO;
    TNMDAP::gHeadNameEffectIndex = selectedIndex;
    TNMDAP::UpdateHeadStatusText();
    TNMDAP::StartHeadTimer();
    return TNMDAP::ApplyHeadOverlaySweep(@"HEAD_NAME_EFFECT_APPLIED") > 0 || selectedIndex == 0;
}

BOOL TNMDHeadTitleSet(NSInteger selectedIndex) {
    TNMDAP::Initialize();
    TNMDAP::DiagBeginTrace(@"HeadFX", @"SetTitle");
    if (![NSThread isMainThread]) return NO;
    NSArray *catalog = TNMDAP::BuildHeadTitleCatalog();
    if (selectedIndex < 0 || selectedIndex >= (NSInteger)catalog.count) return NO;
    TNMDAP::gHeadTitleIndex = selectedIndex;
    TNMDAP::UpdateHeadStatusText();
    TNMDAP::StartHeadTimer();
    return TNMDAP::ApplyHeadOverlaySweep(@"HEAD_TITLE_APPLIED") > 0 || selectedIndex == 0;
}

BOOL TNMDHeadTitleSetDynamic(BOOL enabled) {
    TNMDAP::Initialize();
    TNMDAP::DiagBeginTrace(@"HeadFX", @"SetTitleStyle");
    if (![NSThread isMainThread]) return NO;
    TNMDAP::gHeadTitleDynamic = enabled;
    TNMDAP::UpdateHeadStatusText();
    TNMDAP::StartHeadTimer();
    return TNMDAP::ApplyHeadOverlaySweep(enabled ? @"HEAD_TITLE_DYNAMIC" : @"HEAD_TITLE_STATIC") > 0 || TNMDAP::gHeadTitleIndex == 0;
}

BOOL TNMDHeadTitleClear(void) {
    TNMDAP::Initialize();
    if (![NSThread isMainThread]) return NO;
    TNMDAP::gHeadTitleIndex = 0;
    TNMDAP::UpdateHeadStatusText();
    TNMDAP::StartHeadTimer();
    return TNMDAP::ApplyHeadOverlaySweep(@"HEAD_TITLE_CLEARED") >= 0;
}

BOOL TNMDHeadRingSet(NSInteger selectedIndex) {
    TNMDAP::Initialize();
    TNMDAP::DiagBeginTrace(@"HeadFX", @"SetRing");
    if (![NSThread isMainThread]) return NO;
    NSArray *catalog = TNMDAP::BuildHeadRingCatalog();
    if (selectedIndex < 0 || selectedIndex >= (NSInteger)catalog.count) return NO;
    TNMDAP::gHeadRingIndex = selectedIndex;
    TNMDAP::UpdateHeadStatusText();
    TNMDAP::StartHeadTimer();
    return TNMDAP::ApplyHeadOverlaySweep(@"HEAD_RING_APPLIED") > 0 || selectedIndex == 0;
}

BOOL TNMDHeadRingClear(void) {
    TNMDAP::Initialize();
    if (![NSThread isMainThread]) return NO;
    TNMDAP::gHeadRingIndex = 0;
    TNMDAP::UpdateHeadStatusText();
    TNMDAP::StartHeadTimer();
    return TNMDAP::ApplyHeadOverlaySweep(@"HEAD_RING_CLEARED") >= 0;
}

NSString *TNMDHeadOverlayStatusText(void) {
    TNMDAP::Initialize();
    TNMDAP::UpdateHeadStatusText();
    return TNMDAP::gHeadStatus ?: @"UNKNOWN";
}

NSArray<NSDictionary *> *TNMDSkinSearchItems(NSInteger category, NSString *query, NSUInteger limit) {
    TNMDAP::Initialize();
    if (![NSThread isMainThread]) return @[];
    return [TNMDAP::SearchSkinCatalog((int32_t)category, query, limit) copy];
}

BOOL TNMDSkinPreviewItem(uint32_t itemID, NSInteger category) {
    TNMDAP::Initialize();
    TNMDAP::DiagBeginTrace(@"Skin", @"PreviewItem");
    if (![NSThread isMainThread]) return NO;
    if (!TNMDAP::BindGame() || !TNMDAP::gSkinBindingsReady) {
        TNMDAP::SkinEmit(@"WAIT_PREREQ", @"SKIN_BINDINGS_NOT_READY");
        return NO;
    }
    Il2CppObject *player = TNMDAP::ActiveSkinPlayer(nullptr);
    if (!player) {
        TNMDAP::SkinEmit(@"WAIT_PREREQ", @"LOCAL_PLAYER_NOT_READY", [NSString stringWithFormat:@"item=%u type=%ld guiStage=%@ guiCount=%d guiModels=%d guiLoaded=%d guiList=%@ cached=%p cachedRole=%u", itemID, (long)category, TNMDAP::gSkinLastGUIStage ?: @"none", TNMDAP::gSkinLastGUIListCount, TNMDAP::gSkinLastGUINonNullModels, TNMDAP::gSkinLastGUILoadedModels, TNMDAP::gSkinLastGUIListPath ?: @"none", TNMDAP::CachedSkinPlayer(), TNMDAP::gSkinLastRoleId]);
        return NO;
    }
    BOOL ok = TNMDAP::ApplySkinIDs(player, @[@(itemID)], false, @"PREVIEW_APPLIED") ? YES : NO;
    if (ok) TNMDAP::RememberSkinPlayer(player);
    return ok;
}

BOOL TNMDSkinApplyItem(uint32_t itemID, NSInteger category) {
    TNMDAP::Initialize();
    TNMDAP::DiagBeginTrace(@"Skin", @"ApplyItem");
    if (![NSThread isMainThread]) return NO;
    if (!TNMDAP::BindGame() || !TNMDAP::gSkinBindingsReady) {
        TNMDAP::SkinEmit(@"WAIT_PREREQ", @"SKIN_BINDINGS_NOT_READY");
        return NO;
    }
    Il2CppObject *player = TNMDAP::ActiveSkinPlayer(nullptr);
    if (!player) {
        TNMDAP::SetPinnedSkinSelection((int32_t)category, itemID);
        TNMDAP::gSkinPendingApply = YES;
        TNMDAP::StartSkinTimer();
        TNMDAP::SkinEmit(@"WAIT_PREREQ", @"SKIN_QUEUED_TARGET_WAIT", [NSString stringWithFormat:@"item=%u type=%ld guiStage=%@ guiCount=%d guiModels=%d guiLoaded=%d guiList=%@ cached=%p cachedRole=%u", itemID, (long)category, TNMDAP::gSkinLastGUIStage ?: @"none", TNMDAP::gSkinLastGUIListCount, TNMDAP::gSkinLastGUINonNullModels, TNMDAP::gSkinLastGUILoadedModels, TNMDAP::gSkinLastGUIListPath ?: @"none", TNMDAP::CachedSkinPlayer(), TNMDAP::gSkinLastRoleId]);
        return NO;
    }
    BOOL ok = TNMDAP::ApplySkinIDs(player, @[@(itemID)], false, @"SKIN_APPLIED") ? YES : NO;
    if (ok) {
        TNMDAP::SetPinnedSkinSelection((int32_t)category, itemID);
        TNMDAP::gSkinPendingApply = NO;
        TNMDAP::gSkinLastPinnedApplyAt = CACurrentMediaTime();
        TNMDAP::RememberSkinPlayer(player);
        TNMDAP::StartSkinTimer();
        TNMDAP::SkinEmit(@"RUNNING", category == 6 ? @"SKIN_ALLBODY_PINNED" : @"SKIN_PINNED_LOCAL",
                         [NSString stringWithFormat:@"item=%u type=%ld pinned=%lu allBody=%u pinVerify=%d",
                          itemID, (long)category, (unsigned long)TNMDAP::gSkinPinnedByType.count,
                          [TNMDAP::gSkinPinnedByType[@6] unsignedIntValue], TNMDAP::gSkinB.playerIsPuton ? 1 : 0]);
    }
    return ok;
}

BOOL TNMDSkinRestoreOriginal(void) {
    TNMDAP::Initialize();
    TNMDAP::DiagBeginTrace(@"Skin", @"RestoreOriginal");
    if (![NSThread isMainThread]) return NO;
    if (!TNMDAP::BindGame() || !TNMDAP::gSkinBindingsReady) {
        TNMDAP::SkinEmit(@"WAIT_PREREQ", @"SKIN_BINDINGS_NOT_READY");
        return NO;
    }
    Il2CppObject *player = TNMDAP::ActiveSkinPlayer(nullptr);
    if (!player) {
        TNMDAP::SkinEmit(@"WAIT_PREREQ", @"LOCAL_PLAYER_NOT_READY", [NSString stringWithFormat:@"guiStage=%@ guiCount=%d guiModels=%d guiLoaded=%d guiList=%@ cached=%p cachedRole=%u", TNMDAP::gSkinLastGUIStage ?: @"none", TNMDAP::gSkinLastGUIListCount, TNMDAP::gSkinLastGUINonNullModels, TNMDAP::gSkinLastGUILoadedModels, TNMDAP::gSkinLastGUIListPath ?: @"none", TNMDAP::CachedSkinPlayer(), TNMDAP::gSkinLastRoleId]);
        return NO;
    }
    NSArray<NSNumber *> *ids = TNMDAP::OriginSkinIDs(player);
    if (!ids.count) {
        TNMDAP::SkinEmit(@"FAULT", @"ORIGIN_OUTFIT_EMPTY", [NSString stringWithFormat:@"player=%p", player]);
        return NO;
    }
    [TNMDAP::gSkinPinnedByType removeAllObjects];
    TNMDAP::gSkinPendingApply = NO;
    TNMDAP::gSkinLastPinnedApplyAt = 0.0;
    BOOL ok = TNMDAP::ApplySkinIDs(player, ids, true, @"ORIGINAL_OUTFIT_RESTORED") ? YES : NO;
    TNMDAP::RememberSkinPlayer(player);
    return ok;
}

NSString *TNMDSkinStatusText(void) {
    TNMDAP::Initialize();
    return TNMDAP::gSkinStatus ?: @"UNKNOWN";
}


#pragma mark - Tweak Entrypoint & Setup
// Source: Tweak.mm



#pragma mark - Compatibility

extern "C" __attribute__((visibility("hidden")))
int32_t __isOSVersionAtLeast(int32_t major, int32_t minor, int32_t subminor) {
    NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
    if (v.majorVersion < major) return 0;
    if (v.majorVersion > major) return 1;
    if (v.minorVersion < minor) return 0;
    if (v.minorVersion > minor) return 1;
    return v.patchVersion >= subminor ? 1 : 0;
}

extern "C" __attribute__((visibility("hidden")))
int32_t __isPlatformVersionAtLeast(uint32_t platform,
                                   uint32_t major,
                                   uint32_t minor,
                                   uint32_t subminor) {
    (void)platform;
    return __isOSVersionAtLeast((int32_t)major, (int32_t)minor, (int32_t)subminor);
}

#pragma mark - Branding

static NSString * const kF4GameName = @"AUDITION";
static NSString * const kF4TelegramURL = @"https://t.me/F4CKMOD";
static NSString * const kF4Credit = @"Ma Đế x F4 TEAM";

static NSString * const kF4ArrowPacingKey = @"F4_Audition_ArrowPacing";
static NSString * const kF4BeatJitterKey = @"F4_Audition_BeatJitter";
static NSString * const kF4BeatOneShotKey = @"F4_Audition_BeatOneShot";
static NSString * const kF4ArrowAckKey = @"F4_Audition_ArrowAckGate";
static NSString * const kF4AccentPreferenceKey = @"F4_Audition_AHTL_Accent";
static NSString * const kF4HeadNameEffectIndexKey = @"TNMD.HeadFX.NameEffectIndex";
static NSString * const kF4HeadTitleIndexKey = @"TNMD.HeadFX.TitleIndex";
static NSString * const kF4HeadTitleDynamicKey = @"TNMD.HeadFX.TitleDynamic";
static NSString * const kF4HeadRingIndexKey = @"TNMD.HeadFX.RingIndex";

static BOOL gF4MenuConfigured = NO;
static BOOL gF4AuthorizedUIStarted = NO;
static UILabel *gF4ModeStatusLabel = nil;
static UILabel *gF4LastEventLabel = nil;
static UILabel *gF4AutoStatusLabel = nil;
static UILabel *gF4VIPStatusLabel = nil;
static UILabel *gF4HeadStatusLabel = nil;
static UILabel *gF4HeadCatalogLabel = nil;
static UILabel *gF4DiagTopStatusLabel = nil;
static UILabel *gF4DiagStageMapLabel = nil;
static UILabel *gF4DiagLoggerLabel = nil;
static NSInteger gF4DiagFeatureIndex = 0;
static NSInteger gF4DiagSessionIndex = 0;
static NSMutableDictionary<NSNumber *, NSArray<NSDictionary *> *> *gF4SkinItemsByType = nil;
static NSMutableDictionary<NSNumber *, NSNumber *> *gF4SkinIndexByType = nil;
static uint32_t gF4SkinSelectedID = 0;
static NSInteger gF4SkinSelectedType = -1;
static NSString *gF4SkinSelectedName = nil;
static NSString * const kF4VIPVisualLevelKey = @"TNMD.VIPVisual.Level";
static NSString * const kF4VIPVisualEnabledKey = @"TNMD.VIPVisual.Enabled";
static NSString *gF4LastRuntimeEvent = @"Chưa có runtime event.";

static UIViewController *F4TopViewController(void) {
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    if (!window) {
        for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
            if (!candidate.hidden && candidate.alpha > 0.01) { window = candidate; break; }
        }
    }
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) vc = ((UINavigationController *)vc).visibleViewController;
    if ([vc isKindOfClass:UITabBarController.class]) vc = ((UITabBarController *)vc).selectedViewController;
    return vc;
}

static void F4RefreshRuntimeLabels(void) {
    if (gF4ModeStatusLabel) {
        gF4ModeStatusLabel.text = [NSString stringWithFormat:@"MODE: %@", TNMDAutoPerfectModeText() ?: @"NotDetected"];
    }
    if (gF4AutoStatusLabel) {
        gF4AutoStatusLabel.text = [NSString stringWithFormat:@"AUTO: %@", TNMDAutoPerfectStatusText() ?: @"UNKNOWN"];
    }
    if (gF4VIPStatusLabel) {
        gF4VIPStatusLabel.text = [NSString stringWithFormat:@"VIP: %@", TNMDVIPVisualStatusText() ?: @"UNKNOWN"];
    }
    if (gF4HeadStatusLabel) {
        gF4HeadStatusLabel.text = [NSString stringWithFormat:@"HEAD FX: %@", TNMDHeadOverlayStatusText() ?: @"UNKNOWN"];
    }
    if (gF4LastEventLabel) {
        gF4LastEventLabel.text = [NSString stringWithFormat:@"LAST: %@", gF4LastRuntimeEvent ?: @"-"];
    }
    if (gF4DiagTopStatusLabel) {
        gF4DiagTopStatusLabel.text = [NSString stringWithFormat:@"STATUS: %@", TNMDDiagnosticTopStatusText() ?: @"UNKNOWN"];
    }
    if (gF4DiagStageMapLabel) {
        gF4DiagStageMapLabel.text = TNMDDiagnosticStageMapText() ?: @"<no stage data>";
    }
    if (gF4DiagLoggerLabel) {
        NSString *health = TNMDDiagnosticLoggerHealthText() ?: @"LOGGER_STATE=UNKNOWN";
        NSRange lineEnd = [health rangeOfString:@"\n"];
        NSString *first = lineEnd.location == NSNotFound ? health : [health substringToIndex:lineEnd.location];
        gF4DiagLoggerLabel.text = [NSString stringWithFormat:@"LOGGER: %@", first];
    }
}

__attribute__((unused)) static void F4InstallRuntimeLogSink(void) {
    TNMDAutoPerfectSetUILogSink(^(NSString *feature, NSString *state, NSString *reason) {
        dispatch_async(dispatch_get_main_queue(), ^{
            gF4LastRuntimeEvent = [NSString stringWithFormat:@"[%@] %@ • %@",
                                   feature ?: @"AutoPerfect", state ?: @"UNKNOWN", reason ?: @"-"];
            F4RefreshRuntimeLabels();
        });
    });
}

static NSArray<NSString *> *F4DiagnosticFeatures(void) {
    NSArray<NSString *> *items = TNMDDiagnosticFeatureOptions();
    return items.count ? items : @[@"ALL", @"AutoPerfect", @"Skin", @"VIPVisual", @"CheckLog", @"Boot"];
}

static NSArray<NSString *> *F4DiagnosticSessions(void) {
    NSArray<NSString *> *items = TNMDDiagnosticSessionOptions();
    return items.count ? items : @[@"Current", @"Previous", @"Last Crash/Unclean"];
}

static NSString *F4SelectedDiagnosticFeature(void) {
    NSArray<NSString *> *items = F4DiagnosticFeatures();
    NSInteger idx = gF4DiagFeatureIndex;
    if (idx < 0 || idx >= (NSInteger)items.count) idx = 0;
    return items[(NSUInteger)idx];
}

static NSString *F4SelectedDiagnosticSession(void) {
    NSArray<NSString *> *items = F4DiagnosticSessions();
    NSInteger idx = gF4DiagSessionIndex;
    if (idx < 0 || idx >= (NSInteger)items.count) idx = 0;
    return items[(NSUInteger)idx];
}

static void F4ShowDiagnosticText(NSString *title, NSString *fullText) {
    NSString *full = fullText.length ? fullText : @"<empty>";
    NSString *preview = full;
    const NSUInteger maxPreview = 9000;
    if (full.length > maxPreview) {
        NSUInteger side = maxPreview / 2;
        NSString *head = [full substringToIndex:side];
        NSString *tail = [full substringFromIndex:full.length - side];
        preview = [NSString stringWithFormat:@"[PREVIEW ONLY — Copy Full để lấy toàn bộ]\n\n%@\n\n… <middle omitted in preview> …\n\n%@", head, tail];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title ?: @"CHECK LOG"
                                                                   message:preview
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copy Full" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIPasteboard.generalPasteboard.string = full;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *vc = F4TopViewController();
    if (vc) [vc presentViewController:alert animated:YES completion:nil];
}

__attribute__((unused)) static void F4ShowSelectedDiagnostic(void) {
    NSString *feature = F4SelectedDiagnosticFeature();
    NSString *session = F4SelectedDiagnosticSession();
    NSString *text = TNMDDiagnosticTextForSelection(feature, session);
    F4ShowDiagnosticText([NSString stringWithFormat:@"%@ • %@", feature, session], text);
}


static void F4OpenTelegram(void) {
    NSURL *url = [NSURL URLWithString:kF4TelegramURL];
    if (!url) return;
    UIApplication *app = UIApplication.sharedApplication;
    if (!app) return;
    if (@available(iOS 10.0, *)) {
        [app openURL:url options:@{} completionHandler:nil];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [app openURL:url];
#pragma clang diagnostic pop
    }
}

#pragma mark - Local skin changer

static NSArray<NSDictionary *> *F4SkinSlots(void) {
    return @[
        @{ @"name": @"Tóc", @"type": @0, @"group": @"TRANG PHỤC" },
        @{ @"name": @"Áo", @"type": @1, @"group": @"TRANG PHỤC" },
        @{ @"name": @"Quần", @"type": @2, @"group": @"TRANG PHỤC" },
        @{ @"name": @"Giày", @"type": @3, @"group": @"TRANG PHỤC" },
        @{ @"name": @"Set toàn thân", @"type": @6, @"group": @"TRANG PHỤC" },
        @{ @"name": @"Mặt", @"type": @11, @"group": @"TRANG PHỤC" },
        @{ @"name": @"Skin", @"type": @23, @"group": @"TRANG PHỤC" },
        @{ @"name": @"Tất", @"type": @24, @"group": @"TRANG PHỤC" },
        @{ @"name": @"Cánh", @"type": @10, @"group": @"PHỤ KIỆN / EFFECT" },
        @{ @"name": @"Dây chuyền", @"type": @12, @"group": @"PHỤ KIỆN / EFFECT" },
        @{ @"name": @"Đuôi", @"type": @13, @"group": @"PHỤ KIỆN / EFFECT" },
        @{ @"name": @"Găng", @"type": @18, @"group": @"PHỤ KIỆN / EFFECT" },
        @{ @"name": @"Nhẫn", @"type": @19, @"group": @"PHỤ KIỆN / EFFECT" },
        @{ @"name": @"Vehicle", @"type": @25, @"group": @"PHỤ KIỆN / EFFECT" },
        @{ @"name": @"Trail", @"type": @29, @"group": @"PHỤ KIỆN / EFFECT" },
        @{ @"name": @"Walk Motion", @"type": @30, @"group": @"PHỤ KIỆN / EFFECT" },
        @{ @"name": @"Run Motion", @"type": @31, @"group": @"PHỤ KIỆN / EFFECT" },
        @{ @"name": @"Fly Motion", @"type": @32, @"group": @"PHỤ KIỆN / EFFECT" }
    ];
}

static NSArray<NSString *> *F4SkinOptionNames(NSArray<NSDictionary *> *items) {
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithObject:@"— Giữ nguyên —"];
    NSMutableDictionary<NSString *, NSNumber *> *seen = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in items ?: @[]) {
        NSString *base = entry[@"name"] ?: @"Item";
        NSInteger n = [seen[base] integerValue] + 1;
        seen[base] = @(n);
        NSString *display = n > 1 ? [NSString stringWithFormat:@"%@ • Mẫu %ld", base, (long)n] : base;
        [names addObject:display];
    }
    return names;
}

static void F4RefreshSkinLabels(void) {
    // FINAL CLEAN UI: no persistent skin status/debug rows.
}

static void F4SkinSelectType(NSInteger type, NSInteger selectedIndex) {
    if (selectedIndex <= 0) return; // index 0 = keep current/original for this slot.
    NSArray<NSDictionary *> *items = gF4SkinItemsByType[@(type)];
    NSInteger itemIndex = selectedIndex - 1;
    if (itemIndex < 0 || itemIndex >= (NSInteger)items.count) return;
    NSDictionary *entry = items[(NSUInteger)itemIndex];
    uint32_t itemID = [entry[@"id"] unsignedIntValue];
    NSString *name = entry[@"name"] ?: @"Item";
    if (!itemID) return;
    gF4SkinSelectedID = itemID;
    gF4SkinSelectedType = type;
    gF4SkinSelectedName = name;
    if (!gF4SkinIndexByType) gF4SkinIndexByType = [NSMutableDictionary dictionary];
    gF4SkinIndexByType[@(type)] = @(selectedIndex);
    TNMDSkinApplyItem(itemID, type); // local visual + pin through local respawn.
    F4RefreshSkinLabels();
}

static void F4ReloadSkinSelectors(MenuView *menu) {
    if (!menu) return;
    if (!gF4SkinItemsByType) gF4SkinItemsByType = [NSMutableDictionary dictionary];
    if (!gF4SkinIndexByType) gF4SkinIndexByType = [NSMutableDictionary dictionary];
    NSUInteger total = 0;
    for (NSDictionary *slot in F4SkinSlots()) {
        NSInteger type = [slot[@"type"] integerValue];
        NSString *title = slot[@"name"] ?: @"Skin";
        NSArray<NSDictionary *> *items = TNMDSkinSearchItems(type, @"", 5000) ?: @[];
        gF4SkinItemsByType[@(type)] = items;
        total += items.count;
        NSInteger selected = [gF4SkinIndexByType[@(type)] integerValue];
        NSArray<NSString *> *options = F4SkinOptionNames(items);
        if (selected < 0 || selected >= (NSInteger)options.count) selected = 0;
        [menu updateComboSelector:title options:options selectedIndex:selected];
    }
    F4RefreshSkinLabels();
}


static void F4ReloadHeadSelectors(MenuView *menu) {
    if (!menu) return;
    BOOL reloaded = TNMDHeadReloadCatalogs();
    NSArray<NSString *> *nameOptions = TNMDHeadNameEffectOptions() ?: @[];
    NSArray<NSString *> *titleOptions = TNMDHeadTitleOptions() ?: @[];
    NSArray<NSString *> *ringOptions = TNMDHeadRingOptions() ?: @[];

    NSInteger nameIndex = [NSUserDefaults.standardUserDefaults integerForKey:kF4HeadNameEffectIndexKey];
    NSInteger titleIndex = [NSUserDefaults.standardUserDefaults integerForKey:kF4HeadTitleIndexKey];
    NSInteger ringIndex = [NSUserDefaults.standardUserDefaults integerForKey:kF4HeadRingIndexKey];
    if (nameIndex < 0 || nameIndex >= (NSInteger)nameOptions.count) nameIndex = 0;
    if (titleIndex < 0 || titleIndex >= (NSInteger)titleOptions.count) titleIndex = 0;
    if (ringIndex < 0 || ringIndex >= (NSInteger)ringOptions.count) ringIndex = 0;
    [NSUserDefaults.standardUserDefaults setInteger:nameIndex forKey:kF4HeadNameEffectIndexKey];
    [NSUserDefaults.standardUserDefaults setInteger:titleIndex forKey:kF4HeadTitleIndexKey];
    [NSUserDefaults.standardUserDefaults setInteger:ringIndex forKey:kF4HeadRingIndexKey];

    [menu updateComboSelector:@"Chọn hiệu ứng tên" options:(nameOptions.count ? nameOptions : @[@"Bình thường"]) selectedIndex:nameIndex];
    [menu updateComboSelector:@"Chọn danh hiệu" options:(titleOptions.count ? titleOptions : @[@"Không chọn"]) selectedIndex:titleIndex];
    [menu updateComboSelector:@"Chọn vòng" options:(ringOptions.count ? ringOptions : @[@"Không chọn"]) selectedIndex:ringIndex];

    if (gF4HeadCatalogLabel) {
        NSUInteger nc = nameOptions.count > 0 ? nameOptions.count - 1 : 0;
        NSUInteger tc = titleOptions.count > 0 ? titleOptions.count - 1 : 0;
        NSUInteger rc = ringOptions.count > 0 ? ringOptions.count - 1 : 0;
        gF4HeadCatalogLabel.text = reloaded
            ? [NSString stringWithFormat:@"Đã nạp: %lu hiệu ứng tên • %lu danh hiệu • %lu vòng.", (unsigned long)nc, (unsigned long)tc, (unsigned long)rc]
            : @"Chưa nạp được danh sách. Vào lobby/room rồi bấm Nạp / làm mới hiệu ứng.";
    }
    F4RefreshRuntimeLabels();
}

#pragma mark - AHTL menu appearance

static UIColor *F4UIColorFromHex(NSString *hex) {
    NSString *clean = [[[hex ?: @"" stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet]
        stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    if (clean.length != 6) {
        return [UIColor colorWithRed:37.0/255.0 green:99.0/255.0 blue:235.0/255.0 alpha:1.0];
    }
    unsigned int rgb = 0;
    if (![[NSScanner scannerWithString:clean] scanHexInt:&rgb]) {
        return [UIColor colorWithRed:37.0/255.0 green:99.0/255.0 blue:235.0/255.0 alpha:1.0];
    }
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

static NSArray<NSDictionary<NSString *, NSString *> *> *F4AccentStyles(void) {
    return @[
        @{@"name": @"Neon Blue",       @"hex": @"#2563EB"},
        @{@"name": @"Electric Purple", @"hex": @"#7C3AED"},
        @{@"name": @"Emerald",         @"hex": @"#10B981"},
        @{@"name": @"Rose",            @"hex": @"#E11D48"},
        @{@"name": @"Amber",           @"hex": @"#F59E0B"},
        @{@"name": @"Indigo",          @"hex": @"#4F46E5"}
    ];
}

static NSArray<NSString *> *F4AccentNames(void) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSDictionary<NSString *, NSString *> *entry in F4AccentStyles()) {
        [names addObject:entry[@"name"] ?: @"Theme"];
    }
    return names;
}

static NSInteger F4SavedAccentIndex(void) {
    NSInteger index = [NSUserDefaults.standardUserDefaults integerForKey:kF4AccentPreferenceKey];
    return (index >= 0 && index < (NSInteger)F4AccentStyles().count) ? index : 0;
}

static void F4ApplyAccent(MenuView *menu, NSInteger index) {
    if (!menu) return;
    if (index < 0 || index >= (NSInteger)F4AccentStyles().count) index = 0;
    [menu setMenuAccentColor:F4UIColorFromHex(F4AccentStyles()[(NSUInteger)index][@"hex"])];
    [NSUserDefaults.standardUserDefaults setInteger:index forKey:kF4AccentPreferenceKey];
}

#pragma mark - Feature preferences

static void F4RegisterDefaults(void) {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        kF4ArrowPacingKey: @YES,
        kF4BeatJitterKey: @YES,
        kF4BeatOneShotKey: @YES,
        kF4ArrowAckKey: @YES,
        kF4AccentPreferenceKey: @0
    }];
}

static void F4ApplySavedGameplaySettings(MenuView *menu) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    BOOL pacing = [d boolForKey:kF4ArrowPacingKey];
    BOOL jitter = [d boolForKey:kF4BeatJitterKey];
    BOOL oneShot = [d boolForKey:kF4BeatOneShotKey];
    BOOL ack = [d boolForKey:kF4ArrowAckKey];

    TNMDAutoPerfectSetArrowPacingEnabled(pacing);
    TNMDAutoPerfectSetBeatJitterEnabled(jitter);
    TNMDAutoPerfectSetBeatOneShotEnabled(oneShot);
    TNMDAutoPerfectSetArrowAckGateEnabled(ack);


    // Never auto-arm gameplay automation from a previous launch.
    TNMDAutoPerfectSetEnabled(NO);
    [menu setSwitch:NO forTitle:@"Auto Perfect" animated:NO];
}

#pragma mark - Requested AHTL menu integration

static void F4SetupMenu(void) {
    if (!gF4AuthorizedUIStarted) return;

    UIManager *ui = UIManager.shared;
    [ui setupUI];

    MenuView *menu = ui.menu;
    if (!menu || !ui.floatingButton) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            F4SetupMenu();
        });
        return;
    }

    if (gF4MenuConfigured) {
        [menu updateLayout];
        return;
    }
    gF4MenuConfigured = YES;

    [menu setMenuTitle:kF4GameName];
    [menu setMenuSubtitle:@"SẢN PHẨM MIỄN PHÍ TỪ F4 TEAM"];
    [menu setMenuLogoCharacter:@"F4"];
    [menu setSidebarFooterText:kF4Credit];
    [menu setFooterText:kF4Credit];
    [menu setMenuCornerRadius:14.0];
    [menu setMenuBorderWidth:1.0];
    [menu setMenuGlassEffect:YES];
    menu.telegramURL = kF4TelegramURL;
    menu.alpha = 0.98;

    [menu addTabSection:@"GAMEPLAY" tabs:@[@"AUTO"]];
    [menu addTabSection:@"COSMETIC" tabs:@[@"SKIN", @"HIỆU ỨNG TRÊN ĐẦU", @"VIP"]];
    [menu addTabSection:@"F4 TEAM" tabs:@[@"TELEGRAM", @"GIAO DIỆN"]];

    [menu setTabIndex:0];
    [menu addSectionTitle:@"AUTO PERFECT"];
    [menu addFeatureSwitch:@"Auto Perfect" handler:^(BOOL on) {
        TNMDAutoPerfectSetEnabled(on);
        F4RefreshRuntimeLabels();
    }];

    [menu setTabIndex:1];
    [menu addSectionTitle:@"SKIN CHANGER — CHỌN THEO TỪNG Ô"];
    __weak MenuView *weakSkinMenu = menu;
    [menu addButton:@"Nạp / làm mới danh sách đồ" withHandler:^{
        MenuView *strongMenu = weakSkinMenu;
        F4ReloadSkinSelectors(strongMenu);
    }];

    NSString *lastGroup = nil;
    for (NSDictionary *slot in F4SkinSlots()) {
        NSString *group = slot[@"group"] ?: @"SKIN";
        if (!lastGroup || ![lastGroup isEqualToString:group]) {
            [menu addSectionTitle:group];
            lastGroup = group;
        }
        NSString *title = slot[@"name"] ?: @"Skin";
        NSInteger type = [slot[@"type"] integerValue];
        [menu addComboSelector:title
                       options:@[@"Đang nạp..."]
                 selectedIndex:0
                       handler:^(NSInteger selectedIndex) {
            F4SkinSelectType(type, selectedIndex);
        }];
    }

    [menu addButton:@"Restore toàn bộ outfit gốc" withHandler:^{
        TNMDSkinRestoreOriginal();
        [gF4SkinIndexByType removeAllObjects];
        MenuView *strongMenu = weakSkinMenu;
        for (NSDictionary *slot in F4SkinSlots()) {
            NSString *title = slot[@"name"] ?: @"Skin";
            NSInteger type = [slot[@"type"] integerValue];
            NSArray<NSDictionary *> *items = gF4SkinItemsByType[@(type)] ?: @[];
            [strongMenu updateComboSelector:title options:F4SkinOptionNames(items) selectedIndex:0];
        }
        gF4SkinSelectedID = 0;
        gF4SkinSelectedType = -1;
        gF4SkinSelectedName = nil;
        F4RefreshSkinLabels();
    }];

    // Try once immediately; if config/player is not ready yet, the reload button above retries later.
    F4ReloadSkinSelectors(menu);

    [menu setTabIndex:2];
    [menu addSectionTitle:@"HIỆU ỨNG TRÊN ĐẦU"];
    gF4HeadCatalogLabel = [menu addStatusLabel:@"Bấm nút bên dưới để nạp danh sách hiệu ứng."];
    __weak MenuView *weakHeadMenu = menu;
    [menu addButton:@"Nạp / làm mới hiệu ứng" withHandler:^{
        F4ReloadHeadSelectors(weakHeadMenu);
    }];

    NSArray<NSString *> *headNameOptions = TNMDHeadNameEffectOptions() ?: @[];
    NSInteger savedHeadName = [NSUserDefaults.standardUserDefaults integerForKey:kF4HeadNameEffectIndexKey];
    if (savedHeadName < 0 || savedHeadName >= (NSInteger)headNameOptions.count) savedHeadName = 0;
    [menu addSectionTitle:@"HIỆU ỨNG TÊN"];
    [menu addComboSelector:@"Chọn hiệu ứng tên"
                   options:headNameOptions.count ? headNameOptions : @[@"Bình thường"]
             selectedIndex:savedHeadName
                   handler:^(NSInteger selectedIndex) {
        [NSUserDefaults.standardUserDefaults setInteger:selectedIndex forKey:kF4HeadNameEffectIndexKey];
        TNMDHeadNameEffectSet(selectedIndex);
        F4RefreshRuntimeLabels();
    }];

    NSArray<NSString *> *headTitleOptions = TNMDHeadTitleOptions() ?: @[];
    NSInteger savedHeadTitle = [NSUserDefaults.standardUserDefaults integerForKey:kF4HeadTitleIndexKey];
    if (savedHeadTitle < 0 || savedHeadTitle >= (NSInteger)headTitleOptions.count) savedHeadTitle = 0;
    BOOL savedHeadTitleDynamic = [NSUserDefaults.standardUserDefaults objectForKey:kF4HeadTitleDynamicKey] ? [NSUserDefaults.standardUserDefaults boolForKey:kF4HeadTitleDynamicKey] : YES;
    [menu addSectionTitle:@"DANH HIỆU"];
    [menu addComboSelector:@"Chọn danh hiệu"
                   options:headTitleOptions.count ? headTitleOptions : @[@"Không chọn"]
             selectedIndex:savedHeadTitle
                   handler:^(NSInteger selectedIndex) {
        [NSUserDefaults.standardUserDefaults setInteger:selectedIndex forKey:kF4HeadTitleIndexKey];
        TNMDHeadTitleSet(selectedIndex);
        F4RefreshRuntimeLabels();
    }];
    [menu addComboSelector:@"Danh hiệu động / tĩnh"
                   options:@[@"Động", @"Tĩnh"]
             selectedIndex:(savedHeadTitleDynamic ? 0 : 1)
                   handler:^(NSInteger selectedIndex) {
        BOOL dynamic = (selectedIndex == 0);
        [NSUserDefaults.standardUserDefaults setBool:dynamic forKey:kF4HeadTitleDynamicKey];
        TNMDHeadTitleSetDynamic(dynamic);
        F4RefreshRuntimeLabels();
    }];
    [menu addButton:@"Xóa danh hiệu" withHandler:^{
        [NSUserDefaults.standardUserDefaults setInteger:0 forKey:kF4HeadTitleIndexKey];
        TNMDHeadTitleClear();
        F4RefreshRuntimeLabels();
    }];

    NSArray<NSString *> *headRingOptions = TNMDHeadRingOptions() ?: @[];
    NSInteger savedHeadRing = [NSUserDefaults.standardUserDefaults integerForKey:kF4HeadRingIndexKey];
    if (savedHeadRing < 0 || savedHeadRing >= (NSInteger)headRingOptions.count) savedHeadRing = 0;
    [menu addSectionTitle:@"VÒNG HIỆU ỨNG"];
    [menu addComboSelector:@"Chọn vòng"
                   options:headRingOptions.count ? headRingOptions : @[@"Không chọn"]
             selectedIndex:savedHeadRing
                   handler:^(NSInteger selectedIndex) {
        [NSUserDefaults.standardUserDefaults setInteger:selectedIndex forKey:kF4HeadRingIndexKey];
        TNMDHeadRingSet(selectedIndex);
        F4RefreshRuntimeLabels();
    }];
    [menu addButton:@"Xóa vòng" withHandler:^{
        [NSUserDefaults.standardUserDefaults setInteger:0 forKey:kF4HeadRingIndexKey];
        TNMDHeadRingClear();
        F4RefreshRuntimeLabels();
    }];
    if (savedHeadName > 0) TNMDHeadNameEffectSet(savedHeadName);
    if (savedHeadTitle > 0) TNMDHeadTitleSet(savedHeadTitle);
    TNMDHeadTitleSetDynamic(savedHeadTitleDynamic);
    if (savedHeadRing > 0) TNMDHeadRingSet(savedHeadRing);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        F4ReloadHeadSelectors(weakHeadMenu);
    });

    [menu setTabIndex:3];
    [menu addSectionTitle:@"VIP"];
    NSArray<NSString *> *vipOptions = TNMDVIPVisualLevelOptions() ?: @[];
    NSInteger savedVIP = [NSUserDefaults.standardUserDefaults integerForKey:kF4VIPVisualLevelKey];
    if (savedVIP < 0 || savedVIP >= (NSInteger)vipOptions.count) savedVIP = 0;
    [menu addComboSelector:@"VIP hiển thị"
                   options:vipOptions.count ? vipOptions : @[@"VIP 0", @"VIP 1", @"VIP 2", @"VIP 3", @"VIP 4", @"VIP 5", @"VIP 6", @"VIP 7", @"VIP 8", @"VIP 9", @"VIP 10", @"VIP 11", @"VIP 12", @"VIP 13", @"VIP 14", @"VIP 15", @"VIP 16", @"VIP 17", @"VIP 18"]
             selectedIndex:savedVIP
                   handler:^(NSInteger selectedIndex) {
        [NSUserDefaults.standardUserDefaults setInteger:selectedIndex forKey:kF4VIPVisualLevelKey];
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:kF4VIPVisualEnabledKey];
        TNMDVIPVisualSetLevel(selectedIndex);
        F4RefreshRuntimeLabels();
    }];
    [menu addButton:@"Áp lại VIP visual ngay" withHandler:^{
        NSInteger level = [NSUserDefaults.standardUserDefaults integerForKey:kF4VIPVisualLevelKey];
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:kF4VIPVisualEnabledKey];
        TNMDVIPVisualSetLevel(level);
        F4RefreshRuntimeLabels();
    }];
    [menu addButton:@"Restore VIP thật" withHandler:^{
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:kF4VIPVisualEnabledKey];
        TNMDVIPVisualRestore();
        F4RefreshRuntimeLabels();
    }];
    if ([NSUserDefaults.standardUserDefaults boolForKey:kF4VIPVisualEnabledKey]) {
        TNMDVIPVisualSetLevel(savedVIP);
    }

    [menu setTabIndex:4];
    [menu addSectionTitle:@"F4 TEAM"];
    [menu addStatusLabel:kF4Credit];
    [menu addStatusLabel:@"t.me/F4CKMOD"];
    [menu addButton:@"Mở Telegram F4CKMOD" withHandler:^{
        F4OpenTelegram();
    }];

    [menu setTabIndex:5];
    [menu addSectionTitle:@"GIAO DIỆN"];
    NSInteger accent = F4SavedAccentIndex();
    __weak MenuView *weakMenu = menu;
    [menu addComboSelector:@"Màu giao diện"
                   options:F4AccentNames()
             selectedIndex:accent
                   handler:^(NSInteger selectedIndex) {
        F4ApplyAccent(weakMenu, selectedIndex);
    }];
    [menu addSlider:@"Kích thước menu"
                max:1.25
                min:0.70
              value:ui.menuScale
            handler:^(CGFloat value) {
        [UIManager.shared setMenuScale:value];
    }];

    // V10.29 FINAL CLEAN UI: diagnostic backend stays compiled for feature safety,
    // but all diagnostic UI is intentionally hidden from the release menu.
    F4ApplyAccent(menu, accent);
    F4ApplySavedGameplaySettings(menu);
    [menu setTabIndex:0];
    [menu updateLayout];
}

#pragma mark - Menu & Lifecycle

static void F4StartUI(void) {
    if (gF4AuthorizedUIStarted) return;
    UIWindow *window = F4CActiveWindow();
    if (!window) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            F4StartUI();
        });
        return;
    }
    gF4AuthorizedUIStarted = YES;
    F4SetupMenu();
}

static void F4Initialize(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            F4RegisterDefaults();
            TNMDAutoPerfectInitialize();
        } @catch (id ex) {}

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            F4StartUI();
        });
    });
}

static void F4DidFinishLaunching(CFNotificationCenterRef center,
                                 void *observer,
                                 CFStringRef name,
                                 const void *object,
                                 CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        F4Initialize();
    });
}

__attribute__((constructor)) static void F4Constructor(void) {
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(),
                                     NULL,
                                     &F4DidFinishLaunching,
                                     (CFStringRef)UIApplicationDidFinishLaunchingNotification,
                                     NULL,
                                     CFNotificationSuspensionBehaviorDrop);
}


