#import <UIKit/UIKit.h>

%hook UIViewController

- (void)viewDidLayoutSubviews {
    %orig;

    UIView *mainView = self.view;
    CGRect frame = mainView.frame;

    if (frame.size.width < 500) {
        frame.size.width = 500;
        mainView.frame = frame;
    }
}

%end
