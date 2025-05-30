#import <UIKit/UIKit.h>
#include <IOKit/hid/IOHIDEvent.h>
#include <IOKit/hid/IOHIDEventQueue.h>

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;

    // Create the main window for UI elements
    UIWindow *window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    window.windowLevel = UIWindowLevelAlert + 1;
    window.hidden = NO;

    // Create the on/off button
    UIButton *toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    toggleButton.frame = CGRectMake(50, 50, 60, 60);
    toggleButton.backgroundColor = [UIColor blueColor];
    toggleButton.layer.cornerRadius = 30;
    [toggleButton setTitle:@"OFF" forState:UIControlStateNormal];
    [toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    toggleButton.tag = 1; // Tag to identify button
    [window addSubview:toggleButton];

    // Create the dot view
    UIView *dotView = [[UIView alloc] initWithFrame:CGRectMake(100, 100, 20, 20)];
    dotView.backgroundColor = [UIColor redColor];
    dotView.layer.cornerRadius = 10;
    dotView.tag = 2; // Tag to identify dot
    [window addSubview:dotView];

    // Make button and dot draggable
    UIPanGestureRecognizer *buttonPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [toggleButton addGestureRecognizer:buttonPan];
    toggleButton.userInteractionEnabled = YES;

    UIPanGestureRecognizer *dotPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [dotView addGestureRecognizer:dotPan];
    dotView.userInteractionEnabled = YES;

    // Handle button tap
    [toggleButton addTarget:self action:@selector(toggleButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    // Store window and timer in instance variables
    objc_setAssociatedObject(self, "TweakWindow", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "TweakTimer", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "ToggleButton", toggleButton, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "DotView", dotView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Handle dragging of button and dot
%new
- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *view = gesture.view;
    CGPoint translation = [gesture translationInView:view.superview];
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:view.superview];
}

// Handle button tap to start/stop timer
%new
- (void)toggleButtonTapped:(UIButton *)button {
    NSTimer *timer = objc_getAssociatedObject(self, "TweakTimer");
    if (timer && [timer isValid]) {
        [timer invalidate];
        objc_setAssociatedObject(self, "TweakTimer", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button setTitle:@"OFF" forState:UIControlStateNormal];
        button.backgroundColor = [UIColor blueColor];
    } else {
        timer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(simulateTap) userInfo:nil repeats:YES];
        objc_setAssociatedObject(self, "TweakTimer", timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button setTitle:@"ON" forState:UIControlStateNormal];
        button.backgroundColor = [UIColor greenColor];
    }
}

// Simulate tap at dot's location using IOHIDEvent
%new
- (void)simulateTap {
    UIView *dotView = objc_getAssociatedObject(self, "DotView");
    CGPoint tapPoint = dotView.center;

    // Create touch down event
    IOHIDEventRef touchDown = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, mach_absolute_time(),
                                                             kIOHIDEventTypeDigitizer, 0, 0);
    IOHIDEventSetPosition(touchDown, (IOHIDFloat)tapPoint.x, (IOHIDFloat)tapPoint.y);
    IOHIDEventSetIntegerValue(touchDown, kIOHIDEventFieldDigitizerTouch, 1);

    // Create touch up event
    IOHIDEventRef touchUp = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, mach_absolute_time(),
                                                           kIOHIDEventTypeDigitizer, 0, 0);
    IOHIDEventSetPosition(touchUp, (IOHIDFloat)tapPoint.x, (IOHIDFloat)tapPoint.y);
    IOHIDEventSetIntegerValue(touchUp, kIOHIDEventFieldDigitizerTouch, 0);

    // Send events to SpringBoard
    Class SBApplicationController = NSClassFromString(@"SBApplicationController");
    id appController = [SBApplicationController sharedInstance];
    if (appController) {
        [appController performSelector:@selector(_handleHIDEvent:) withObject:(__bridge id)touchDown];
        [appController performSelector:@selector(_handleHIDEvent:) withObject:(__bridge id)touchUp];
    }

    // Clean up
    CFRelease(touchDown);
    CFRelease(touchUp);
}
%end
