#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// Prevent the compiler from complaining about UIAlertView (deprecated)
@interface UIAlertView : UIView
- (void)show;
@end

%hook UIAlertView
- (void)show {
    // Suppress legacy UIAlertView
    NSLog(@"[tweak] Suppressed UIAlertView show");
    // Do nothing
}
%end

%hook UIViewController

// Intercept all presentations
- (void)presentViewController:(UIViewController *)viewControllerToPresent
                     animated:(BOOL)flag
                   completion:(void (^ __nullable)(void))completion
{
    // If it's an UIAlertController, don't present it
    if ([viewControllerToPresent isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)viewControllerToPresent;

        // Optional: add extra checks if you want to allow some alerts through,
        // e.g. by title, message, or actions. Example (commented out):
        //
        // NSString *title = alert.title ?: @"";
        // if ([title containsString:@"Allow"] || [title containsString:@"Important"]) {
        //     %orig(viewControllerToPresent, flag, completion); // allow specific ones
        //     return;
        // }

        NSLog(@"[tweak] Suppressed UIAlertController: title='%@' message='%@'",
              alert.title, alert.message);

        // Call completion handler so calling code doesn't hang waiting for it
        if (completion) completion();
        return; // do NOT call original -> alert is blocked
    }

    // Otherwise call original behavior
    %orig(viewControllerToPresent, flag, completion);
}

%end
