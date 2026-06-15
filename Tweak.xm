// Tweak.xm - RAM Text Dumper
// Hooks into UIKit to collect all visible text and dump to file

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Foundation/Foundation.h>

// ─────────────────────────────────────────────
//  Helper: recursively harvest text from a view
// ─────────────────────────────────────────────
static void collectTextFromView(UIView *view, NSMutableArray<NSString *> *results, NSUInteger depth) {
    if (!view) return;

    NSString *indent = [@"" stringByPaddingToLength:depth * 2
                                         withString:@"  "
                                    startingAtIndex:0];

    // UILabel
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        if (label.text.length > 0) {
            [results addObject:[NSString stringWithFormat:@"%@[UILabel] %@", indent, label.text]];
        }
    }

    // UITextView
    if ([view isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)view;
        if (tv.text.length > 0) {
            [results addObject:[NSString stringWithFormat:@"%@[UITextView] %@", indent, tv.text]];
        }
        if (tv.placeholder.length > 0) {
            [results addObject:[NSString stringWithFormat:@"%@[UITextView placeholder] %@", indent, tv.placeholder]];
        }
    }

    // UITextField
    if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        if (tf.text.length > 0) {
            [results addObject:[NSString stringWithFormat:@"%@[UITextField] %@", indent, tf.text]];
        }
        if (tf.placeholder.length > 0) {
            [results addObject:[NSString stringWithFormat:@"%@[UITextField placeholder] %@", indent, tf.placeholder]];
        }
    }

    // UIButton title
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)view;
        NSString *title = [btn titleForState:UIControlStateNormal];
        if (title.length > 0) {
            [results addObject:[NSString stringWithFormat:@"%@[UIButton] %@", indent, title]];
        }
    }

    // WKWebView / UIWebView page title (best-effort via accessibility)
    NSString *accessLabel = view.accessibilityLabel;
    NSString *accessValue = view.accessibilityValue;
    NSString *accessHint  = view.accessibilityHint;
    if (accessLabel.length > 0) {
        [results addObject:[NSString stringWithFormat:@"%@[Accessibility label] %@", indent, accessLabel]];
    }
    if (accessValue.length > 0) {
        [results addObject:[NSString stringWithFormat:@"%@[Accessibility value] %@", indent, accessValue]];
    }
    if (accessHint.length > 0) {
        [results addObject:[NSString stringWithFormat:@"%@[Accessibility hint] %@", indent, accessHint]];
    }

    // Recurse into subviews
    for (UIView *sub in view.subviews) {
        collectTextFromView(sub, results, depth + 1);
    }
}

// ─────────────────────────────────────────────
//  Core dump function
// ─────────────────────────────────────────────
static NSString *performTextDump(void) {
    NSMutableArray<NSString *> *allText = [NSMutableArray array];

    // Walk every window (including floating ones)
    NSArray<UIWindow *> *windows = [UIApplication sharedApplication].windows;
    [allText addObject:[NSString stringWithFormat:@"=== RAM Text Dump — %@ ===", [NSDate date]]];
    [allText addObject:[NSString stringWithFormat:@"Windows found: %lu", (unsigned long)windows.count]];
    [allText addObject:@""];

    NSUInteger winIdx = 0;
    for (UIWindow *window in windows) {
        [allText addObject:[NSString stringWithFormat:@"── Window %lu (%@) ──", (unsigned long)winIdx++, NSStringFromCGRect(window.frame)]];
        collectTextFromView(window, allText, 1);
        [allText addObject:@""];
    }

    // Build the output string
    NSString *output = [allText componentsJoinedByString:@"\n"];

    // Save to Documents/RamDumps/
    NSString *docsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dumpDir  = [docsPath stringByAppendingPathComponent:@"RamDumps"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dumpDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Timestamped filename
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyyMMdd_HHmmss";
    NSString *stamp    = [fmt stringFromDate:[NSDate date]];
    NSString *fileName = [NSString stringWithFormat:@"ramdump_%@.txt", stamp];
    NSString *filePath = [dumpDir stringByAppendingPathComponent:fileName];

    [output writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    return filePath;
}

// ─────────────────────────────────────────────
//  Floating overlay button (DumpOverlayWindow)
// ─────────────────────────────────────────────
@interface DumpOverlayWindow : UIWindow
@property (nonatomic, strong) UIButton *dumpButton;
@property (nonatomic, strong) UILabel  *statusLabel;
- (void)setupUI;
@end

@implementation DumpOverlayWindow

- (instancetype)init {
    // Cover the whole screen but pass touches through except on the button
    self = [super initWithFrame:[UIScreen mainScreen].bounds];
    if (self) {
        self.windowLevel          = UIWindowLevelAlert + 100;
        self.backgroundColor      = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.hidden               = NO;

        // Ensure this window doesn't interfere with the app's own windows
        self.rootViewController   = [[UIViewController alloc] init];
        self.rootViewController.view.backgroundColor = [UIColor clearColor];

        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    // ── Floating button ──────────────────────────────────────────────
    CGFloat size = 58.0;
    CGFloat margin = 20.0;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;

    self.dumpButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.dumpButton.frame = CGRectMake(margin,
                                       screenH / 2 - size / 2,
                                       size, size);
    self.dumpButton.layer.cornerRadius  = size / 2;
    self.dumpButton.layer.masksToBounds = YES;
    self.dumpButton.backgroundColor     = [UIColor colorWithRed:0.10 green:0.60 blue:1.00 alpha:0.92];
    self.dumpButton.tintColor           = [UIColor whiteColor];

    // Icon + text
    [self.dumpButton setTitle:@"💾" forState:UIControlStateNormal];
    self.dumpButton.titleLabel.font = [UIFont systemFontOfSize:26];

    // Shadow
    self.dumpButton.layer.shadowColor   = [UIColor blackColor].CGColor;
    self.dumpButton.layer.shadowOpacity = 0.35;
    self.dumpButton.layer.shadowOffset  = CGSizeMake(0, 3);
    self.dumpButton.layer.shadowRadius  = 6;
    self.dumpButton.layer.masksToBounds = NO;

    [self.dumpButton addTarget:self
                        action:@selector(dumpButtonTapped)
              forControlEvents:UIControlEventTouchUpInside];

    // Make it draggable
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
                                    initWithTarget:self
                                            action:@selector(handlePan:)];
    [self.dumpButton addGestureRecognizer:pan];

    [self.rootViewController.view addSubview:self.dumpButton];

    // ── Status label (toast) ─────────────────────────────────────────
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 260, 54)];
    self.statusLabel.center          = CGPointMake([UIScreen mainScreen].bounds.size.width / 2,
                                                    screenH - 120);
    self.statusLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.78];
    self.statusLabel.textColor        = [UIColor whiteColor];
    self.statusLabel.font             = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.statusLabel.textAlignment    = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines    = 2;
    self.statusLabel.layer.cornerRadius  = 10;
    self.statusLabel.layer.masksToBounds = YES;
    self.statusLabel.alpha            = 0.0;

    [self.rootViewController.view addSubview:self.statusLabel];
}

// ── Drag support ─────────────────────────────────────────────────────
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.rootViewController.view];
    CGPoint center      = self.dumpButton.center;
    center.x += translation.x;
    center.y += translation.y;

    // Keep inside screen bounds
    CGFloat hw = self.dumpButton.bounds.size.width  / 2;
    CGFloat hh = self.dumpButton.bounds.size.height / 2;
    CGSize  screen = [UIScreen mainScreen].bounds.size;
    center.x = MAX(hw,  MIN(screen.width  - hw, center.x));
    center.y = MAX(hh,  MIN(screen.height - hh, center.y));

    self.dumpButton.center = center;
    [pan setTranslation:CGPointZero inView:self.rootViewController.view];
}

// ── Dump action ──────────────────────────────────────────────────────
- (void)dumpButtonTapped {
    // Brief scale animation
    [UIView animateWithDuration:0.10 animations:^{
        self.dumpButton.transform = CGAffineTransformMakeScale(0.88, 0.88);
    } completion:^(BOOL _) {
        [UIView animateWithDuration:0.12 animations:^{
            self.dumpButton.transform = CGAffineTransformIdentity;
        }];
    }];

    // Run dump on background thread
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *path = performTextDump();
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showToast:[NSString stringWithFormat:@"✅ Saved!\n%@", path.lastPathComponent]];
        });
    });
}

// ── Toast notification ───────────────────────────────────────────────
- (void)showToast:(NSString *)message {
    self.statusLabel.text  = message;
    self.statusLabel.alpha = 0.0;
    [UIView animateWithDuration:0.25 animations:^{
        self.statusLabel.alpha = 1.0;
    } completion:^(BOOL _) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.35 animations:^{
                self.statusLabel.alpha = 0.0;
            }];
        });
    }];
}

// Pass touch events through the transparent areas
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // Only consume touches on our own subviews
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}

@end

// ─────────────────────────────────────────────
//  Inject the overlay into every app at launch
// ─────────────────────────────────────────────
static DumpOverlayWindow *overlayWindow = nil;

%hook UIApplication

- (void)_run {
    %orig;
}

%end

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    // Only create once, after the host app's first window is shown
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            overlayWindow = [[DumpOverlayWindow alloc] init];
        });
    });
}

%end
