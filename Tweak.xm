#import <UIKit/UIKit.h>

// iOS 8+ UIAlertController
%hook UIAlertController

- (void)viewDidAppear:(BOOL)animated {
    // Block alert from appearing
    return;
}

%end


// Also block presentation via UIViewController
%hook UIViewController

- (void)presentViewController:(UIViewController *)viewControllerToPresent
                     animated:(BOOL)flag
                   completion:(void (^)(void))completion {

    if ([viewControllerToPresent isKindOfClass:[UIAlertController class]]) {
        // Block alert
        NSLog(@"[Tweak] Blocked UIAlertController");
        return;
    }

    %orig;
}

%end


// iOS < 8 (legacy UIAlertView)
%hook UIAlertView

- (void)show {
    NSLog(@"[Tweak] Blocked UIAlertView");
    return;
}

%end
