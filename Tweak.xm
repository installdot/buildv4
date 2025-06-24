#import <UIKit/UIKit.h>

// Define a new category for UIApplication to add our button and task method
@interface UIApplication (MovableButtonTask)
- (void)showMovableButton;
- (void)performAutoTask; // This will hold your existing task logic
@end

%hook UIApplication

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;

    // Call the method to show the movable button
    [self performSelector:@selector(showMovableButton) withObject:nil afterDelay:1.0];
}

%end

// Implement the methods in the category
@implementation UIApplication (MovableButtonTask)

- (void)showMovableButton {
    // Create a new window to host the button, ensuring it floats above other content
    UIWindow *overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    overlayWindow.windowLevel = UIWindowLevelStatusBar + 1; // Make it appear on top
    overlayWindow.backgroundColor = [UIColor clearColor];
    overlayWindow.hidden = NO;

    // Create the button
    UIButton *movableButton = [UIButton buttonWithType:UIButtonTypeCustom];
    movableButton.frame = CGRectMake(20, 100, 150, 50); // Initial position and size
    movableButton.backgroundColor = [UIColor systemBlueColor]; // A nice blue color
    [movableButton setTitle:@"Start Task" forState:UIControlStateNormal];
    [movableButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    movableButton.layer.cornerRadius = 10; // Rounded corners
    movableButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];

    // Add a pan gesture recognizer for moving the button
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [movableButton addGestureRecognizer:panGesture];

    // Add a target for the button press
    [movableButton addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];

    [overlayWindow addSubview:movableButton];
    
    // Retain the window to prevent it from being deallocated
    // This is a simple way for a quick hack. For a more robust solution,
    // you might want to store this window in an accessible property.
    objc_setAssociatedObject(self, @selector(showMovableButton), overlayWindow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Handles the pan gesture to move the button
- (void)handlePan:(UIPanGestureRecognizer *)sender {
    UIButton *button = (UIButton *)sender.view;
    CGPoint translation = [sender translationInView:button.superview];
    button.center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
    [sender setTranslation:CGPointZero inView:button.superview];
}

// Method called when the button is tapped
- (void)buttonTapped:(UIButton *)sender {
    NSLog(@"[+] Movable button tapped! Starting task...");
    [self performAutoTask]; // Call the method containing the task logic
    // You might want to disable the button or change its title after it's tapped
    [sender setTitle:@"Task Started" forState:UIControlStateNormal];
    sender.enabled = NO;
    sender.alpha = 0.6; // Make it look disabled
}

// This method encapsulates your original auto task logic
- (void)performAutoTask {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"[+] Auto task started");

        NSURL *url = [NSURL URLWithString:@"https://chillysilly.frfrnocap.men/token.php?gen"];
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) {
                NSLog(@"[!] Network request failed: %@", error);
                return;
            }

            NSString *respStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[+] Response: %@", respStr);

            NSArray *parts = [respStr componentsSeparatedByString:@"|"];
            if (parts.count != 2) {
                NSLog(@"[!] Invalid response format");
                return;
            }

            NSString *token = parts[0]; // e.g. 28410720410e46cba6f616752b2914ef
            NSString *uid = parts[1];   // e.g. 191106925

            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];

            // Step 1: Copy and rename data files in Documents
            NSArray *filenames = @[
                @"item_data_1_.data",
                @"season_data_1_.data",
                @"statistic_1_.data",
                @"weapon_evolution_data_1_.data"
            ];

            for (NSString *name in filenames) {
                NSString *originalPath = [docsDir stringByAppendingPathComponent:name];
                if (![fm fileExistsAtPath:originalPath]) {
                    NSLog(@"[!] Missing: %@", name);
                    continue;
                }

                NSString *newName = [name stringByReplacingOccurrencesOfString:@"1" withString:uid];
                NSString *newPath = [docsDir stringByAppendingPathComponent:newName];

                NSError *copyError = nil;
                if ([fm copyItemAtPath:originalPath toPath:newPath error:&copyError]) {
                    NSLog(@"[+] Copied %@ to %@", name, newName);
                } else {
                    NSLog(@"[!] Copy error: %@", copyError);
                }
            }

            // Step 2: Preferences path
            NSString *prefsPath = @"/Library/Preferences/";
            NSString *plistPath = [prefsPath stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
            NSString *txtPath   = [prefsPath stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.txt"];

            // Step 3: Delete old plist
            if ([fm fileExistsAtPath:plistPath]) {
                NSError *deleteError = nil;
                if ([fm removeItemAtPath:plistPath error:&deleteError]) {
                    NSLog(@"[+] Deleted existing plist");
                } else {
                    NSLog(@"[!] Could not delete plist: %@", deleteError);
                }
            }

            // Step 4: Modify .txt and write to .plist
            if ([fm fileExistsAtPath:txtPath]) {
                NSError *readError = nil;
                NSString *txtContent = [NSString stringWithContentsOfFile:txtPath encoding:NSUTF8StringEncoding error:&readError];

                if (txtContent && !readError) {
                    NSString *modified = [txtContent stringByReplacingOccurrencesOfString:@"98989898" withString:uid];
                    modified = [modified stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];

                    NSError *writeError = nil;
                    [modified writeToFile:plistPath atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
                    if (!writeError) {
                        NSLog(@"[+] Wrote new plist file");
                    } else {
                        NSLog(@"[!] Plist write error: %@", writeError);
                    }
                } else {
                    NSLog(@"[!] Failed to read txt: %@", readError);
                }
            } else {
                NSLog(@"[!] .txt file not found");
            }

            NSLog(@"[+] Task complete — no restart performed.");
        }];

        [task resume];
    });
}

@end
