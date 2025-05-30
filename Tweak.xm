#import <UIKit/UIKit.h>
#import <IOKit/hid/IOHIDEventSystem.h>
#import <mach/mach_time.h>

static UIWindow *overlayWindow;
static UIButton *startStopBtn;
static UIView *targetView;
static NSTimer *clickTimer;
static BOOL isClicking = NO;
static CGPoint clickPoint = {100, 300};

AbsoluteTime getAbsoluteTime() {
    uint64_t machTime = mach_absolute_time();
    AbsoluteTime absTime;
    absTime.lo = (uint32_t)(machTime & 0xFFFFFFFF);
    absTime.hi = (uint32_t)(machTime >> 32);
    return absTime;
}

void simulateTouch(CGPoint point) {
    IOHIDEventSystemRef system = IOHIDEventSystemCreate(kCFAllocatorDefault);
    if (!system) return;

    AbsoluteTime now = getAbsoluteTime();

    IOHIDEventRef downEvent = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault,
        now,
        kIOHIDDigitizerTransducerTypeFinger,
        0, 0,
        kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventRange,
        1,
        point.x, point.y, 0,
        1.0, 0,
        true, true,
        0
    );

    IOHIDEventRef upEvent = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault,
        now,
        kIOHIDDigitizerTransducerTypeFinger,
        0, 0,
        kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventRange,
        0,
        point.x, point.y, 0,
        0.0, 0,
        true, false,
        0
    );

    IOHIDEventSystemDispatchEvent(system, downEvent);
    IOHIDEventSystemDispatchEvent(system, upEvent);

    CFRelease(downEvent);
    CFRelease(upEvent);
    CFRelease(system);
}

void startClicking() {
    if (clickTimer) return;
    isClicking = YES;
    clickTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:YES block:^(NSTimer * _Nonnull timer) {
        simulateTouch(clickPoint);
    }];
}

void stopClicking() {
    isClicking = NO;
    [clickTimer invalidate];
    clickTimer = nil;
}

void toggleClicking() {
    if (isClicking) {
        stopClicking();
        [startStopBtn setTitle:@"▶️" forState:UIControlStateNormal];
    } else {
        startClicking();
        [startStopBtn setTitle:@"⏹️" forState:UIControlStateNormal];
    }
}

void setupUI() {
    if (overlayWindow) return;

    overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    overlayWindow.windowLevel = UIWindowLevelAlert + 100;
    overlayWindow.backgroundColor = [UIColor clearColor];
    overlayWindow.hidden = NO;

    UIViewController *vc = [UIViewController new];
    overlayWindow.rootViewController = vc;
    overlayWindow.hidden = NO;

    startStopBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    startStopBtn.frame = CGRectMake(40, 100, 60, 60);
    startStopBtn.layer.cornerRadius = 30;
    startStopBtn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    [startStopBtn setTitle:@"▶️" forState:UIControlStateNormal];
    [startStopBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [startStopBtn addTarget:nil action:@selector(_toggleClicking) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:startStopBtn];

    targetView = [[UIView alloc] initWithFrame:CGRectMake(clickPoint.x, clickPoint.y, 40, 40)];
    targetView.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.6];
    targetView.layer.cornerRadius = 20;
    targetView.userInteractionEnabled = YES;
    [vc.view addSubview:targetView];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(_dragTarget:)];
    [targetView addGestureRecognizer:pan];
}

%hook UIApplication

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        setupUI();
    });
}

%new
- (void)_toggleClicking {
    toggleClicking();
}

%new
- (void)_dragTarget:(UIPanGestureRecognizer *)gesture {
    UIView *view = gesture.view;
    CGPoint translation = [gesture translationInView:view.superview];
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:view.superview];
    clickPoint = view.center;
}

%end
