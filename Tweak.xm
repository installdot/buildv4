#import <UIKit/UIKit.h>
#include <objc/runtime.h>

@interface TweakWindow : UIWindow
@property (nonatomic, strong) UIView *circleView;
@property (nonatomic, strong) UIButton *clickButton;
@property (nonatomic, assign) CGPoint circleCenter;
@end

@implementation TweakWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.windowLevel = UIWindowLevelStatusBar + 100;
        self.backgroundColor = [UIColor clearColor];
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    // Create draggable circle
    self.circleView = [[UIView alloc] initWithFrame:CGRectMake(100, 100, 50, 50)];
    self.circleView.backgroundColor = [UIColor redColor];
    self.circleView.layer.cornerRadius = 25;
    self.circleView.userInteractionEnabled = YES;

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.circleView addGestureRecognizer:pan];

    // Create button
    self.clickButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.clickButton.frame = CGRectMake(20, 20, 100, 40);
    [self.clickButton setTitle:@"Click Here" forState:UIControlStateNormal];
    [self.clickButton addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.clickButton.backgroundColor = [UIColor whiteColor];
    self.clickButton.layer.cornerRadius = 5;

    [self addSubview:self.circleView];
    [self addSubview:self.clickButton];
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self];
    UIView *view = gesture.view;
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    self.circleCenter = view.center;
    [gesture setTranslation:CGPointZero inView:self];
}

- (void)buttonTapped {
    // Simulate tap at circle's center
    [self simulateTapAtPoint:self.circleCenter];
}

- (void)simulateTapAtPoint:(CGPoint)point {
    // Get the active window
    UIWindow *activeWindow = nil;
    for (UIWindowScene *windowScene in [UIApplication sharedApplication].connectedScenes) {
        if (windowScene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    activeWindow = window;
                    break;
                }
            }
        }
    }

    if (!activeWindow) {
        activeWindow = [UIApplication sharedApplication].windows.firstObject;
    }

    // Create and dispatch touch events
    UIEvent *event = [[UIEvent alloc] init];
    UITouch *touch = [[UITouch alloc] init];

    object_setInstanceVariable(touch, "_locationInWindow", &point);
    object_setInstanceVariable(touch, "_phase", (void *)UITouchPhaseBegan);
    object_setInstanceVariable(touch, "_window", (__bridge void *)activeWindow);

    [[UIApplication sharedApplication] sendEvent:event];

    object_setInstanceVariable(touch, "_phase", (void *)UITouchPhaseEnded);
    [[UIApplication sharedApplication] sendEvent:event];
}

@end

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;

    // Create tweak window
    TweakWindow *tweakWindow = [[TweakWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    tweakWindow.hidden = NO;
}

%end
