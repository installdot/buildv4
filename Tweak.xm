#import <UIKit/UIKit.h> // Import UIKit for UI elements

// Define a new interface for a view controller (or hook into an existing one)
// For simplicity, we'll just add the button to the key window.
%hook UIWindow

- (void)makeKeyAndVisible {
    %orig; // Call the original method

    // Create the button
    UIButton *startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [startButton setTitle:@"Start" forState:UIControlStateNormal];
    startButton.titleLabel.font = [UIFont boldSystemFontOfSize:30]; // Make text bold and larger

    // Set button colors for brightness
    [startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; // White text
    startButton.backgroundColor = [UIColor systemGreenColor]; // Bright green background
    startButton.layer.cornerRadius = 15; // Rounded corners for a softer look
    startButton.alpha = 0.9; // Slightly transparent to blend, but still prominent

    // Set frame for the button (centered)
    CGFloat buttonWidth = 200;
    CGFloat buttonHeight = 70;
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    startButton.frame = CGRectMake((screenSize.width - buttonWidth) / 2,
                                   (screenSize.height - buttonHeight) / 2,
                                   buttonWidth,
                                   buttonHeight);

    // Add a target-action for when the button is tapped (optional, but good practice)
    [startButton addTarget:self action:@selector(startButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    // Add the button to the key window
    [self addSubview:startButton];
}

// Action method for the button (this will be called when the button is tapped)
- (void)startButtonTapped {
    NSLog(@"Start Button Tapped!");
    // You can add your desired functionality here when the button is pressed.
    // For example, present a new view controller, trigger an action, etc.

    // Display an alert for demonstration
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Action"
                                                                   message:@"Start button was tapped!"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];
    [alert addAction:okAction];

    // Find the topmost view controller to present the alert
    UIViewController *rootViewController = self.rootViewController;
    while (rootViewController.presentedViewController) {
        rootViewController = rootViewController.presentedViewController;
    }
    [rootViewController presentViewController:alert animated:YES completion:nil];
}

%end
