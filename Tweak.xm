#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <stdlib.h>

// =====================
// BLOCK ALERTS
// =====================

%hook UIViewController

- (void)presentViewController:(UIViewController *)vc
                     animated:(BOOL)animated
                   completion:(void (^)(void))completion {

    if ([vc isKindOfClass:[UIAlertController class]]) {
        NSLog(@"[Tweak] Blocked UIAlertController");
        return;
    }

    %orig;
}

%end


%hook UIAlertController
- (void)viewDidAppear:(BOOL)animated {
    return;
}
%end


%hook UIAlertView
- (void)show {
    NSLog(@"[Tweak] Blocked UIAlertView");
    return;
}
%end


// =====================
// BLOCK FORCE EXIT
// =====================

// exit()
%hookf(void, exit, int status) {
    NSLog(@"[Tweak] Prevented exit(%d)", status);
    return;
}

// abort()
%hookf(void, abort) {
    NSLog(@"[Tweak] Prevented abort()");
    return;
}

// UIApplication terminate
%hook UIApplication

- (void)terminateWithSuccess {
    NSLog(@"[Tweak] Blocked terminateWithSuccess");
    return;
}

%end


// =====================
// BLOCK SIGNAL CRASHES
// =====================

#include <signal.h>

%ctor {
    NSLog(@"[Tweak] Loaded - Anti Exit Enabled");

    // Ignore common crash signals
    signal(SIGABRT, SIG_IGN);
    signal(SIGTERM, SIG_IGN);
    signal(SIGINT,  SIG_IGN);
}
