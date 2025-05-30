#import <UIKit/UIKit.h>
#import <IOKit/hid/IOHIDEventSystem.h>
#import <dlfcn.h>

static UIWindow *overlayWindow;
static UIButton *startStopBtn;
static UIView *targetView;
static NSTimer *clickTimer;
static BOOL isClicking = NO;
static CGPoint clickPoint = {100, 300};

// Declare IOHID functions pointers
static void *(*IOHIDEventSystemCreate)(CFAllocatorRef allocator);
static IOHIDEventRef (*IOHIDEventCreateDigitizerEvent)(
    CFAllocatorRef allocator,
    AbsoluteTime timeStamp,
    uint32_t transducer,
    uint32_t index,
    uint32_t identity,
    uint32_t eventMask,
    uint32_t buttonMask,
    float x,
    float y,
    float z,
    float tipPressure,
    float twist,
    boolean_t range,
    boolean_t touch,
    IOOptionBits options
);
static void (*IOHIDEventSystemDispatchEvent)(void *eventSystem, IOHIDEventRef event);

void loadIOHIDSymbols() {
    void *ioKit = dlopen("/System/Library/PrivateFrameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (!ioKit) return;

    IOHIDEventSystemCreate = dlsym(ioKit, "IOHIDEventSystemCreate");
    IOHIDEventCreateDigitizerEvent = dlsym(ioKit, "IOHIDEventCreateDigitizerEvent");
    IOHIDEventSystemDispatchEvent = dlsym(ioKit, "IOHIDEventSystemDispatchEvent");
}

void simulateTouch(CGPoint point) {
    if (!IOHIDEventSystemCreate || !IOHIDEventCreateDigitizerEvent || !IOHIDEventSystemDispatchEvent) return;

    void *hidSystem = IOHIDEventSystemCreate(kCFAllocatorDefault);
    if (!hidSystem) return;

    AbsoluteTime now = mach_absolute_time();

    // Touch Down
    IOHIDEventRef downEvent = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault,
        now,
        0, 0, 0,
        kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventRange,
        1,
        point.x, point.y, 0,
        1.0, 0,
        true, true,
        0
    );

    // Touch Up
    IOHIDEventRef upEvent = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault,
        now,
        0, 0, 0,
        kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventRange,
        0,
        point.x, point.y, 0,
        0.0, 0,
        true, false,
        0
    );

    IOHIDEventSystemDispatchEvent(hidSystem, downEvent);
    IOHIDEventSystemDispatchEvent(hidSystem, upEvent);

    CFRelease(downEvent);
    CFRelease(upEvent);
    CFRelease(hidSystem);
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

    // Start/Stop Button
    startStopBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    startStopBtn.frame = CGRectMake(40, 100, 60, 60);
    startStopBtn.layer.cornerRadius = 30;
    startStopBtn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    [startStopBtn setTitle:@"▶️" forState:UIControlStateNormal];
    [startStopBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [startStopBtn addTarget:nil action:@selector(_toggleClicking) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:startStopBtn];

    // Target circle view
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
    loadIOHIDSymbols();
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
