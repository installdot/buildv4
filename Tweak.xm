#import <UIKit/UIKit.h>
#import <objc/runtime.h>

%hook UIApplication

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;

        if (!keyWindow) return;

        UIButton *startButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [startButton setTitle:@"Start" forState:UIControlStateNormal];
        startButton.frame = CGRectMake(100, 100, 80, 40);
        startButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        [startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        startButton.layer.cornerRadius = 10;
        startButton.clipsToBounds = YES;
        startButton.layer.borderWidth = 1;
        startButton.layer.borderColor = [UIColor whiteColor].CGColor;

        // Add drag functionality
        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
        [startButton addGestureRecognizer:panGesture];

        // Add action on tap
        [startButton addTarget:self action:@selector(startButtonTapped) forControlEvents:UIControlEventTouchUpInside];

        [keyWindow addSubview:startButton];
    });
}

%new
- (void)startButtonTapped {
    NSLog(@"[+] Start button was tapped!");
    // Add your custom logic here
}

%new
- (void)handleDrag:(UIPanGestureRecognizer *)gesture {
    UIView *draggedView = gesture.view;
    CGPoint translation = [gesture translationInView:draggedView.superview];
    draggedView.center = CGPointMake(draggedView.center.x + translation.x, draggedView.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:draggedView.superview];
}

%end
