#import <UIKit/UIKit.h>

// Declare the function that returns the key window
UIWindow *getKeyWindow(void);

// Declare the function that will handle the button tap
void handleStartButton(void);

%hook UIApplication

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;

    // Call this function to show the "Start Task" button
    showStartButton();
}

%end

// This function finds and returns the key window
UIWindow *getKeyWindow(void) {
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *window in scene.windows) {
                if (window.isKeyWindow) {
                    return window;
                }
            }
        }
    }
    // Fallback for older iOS versions or if scene-based approach fails
    return [UIApplication sharedApplication].keyWindow;
}

// This function displays the "Start Task" button
void showStartButton() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = getKeyWindow();
        if (!keyWindow) {
            NSLog(@"[!] Could not find key window to show button.");
            return;
        }

        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:@"Start Task" forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.backgroundColor = [UIColor systemBlueColor];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        button.frame = CGRectMake(0, 0, 160, 60);
        button.center = keyWindow.center;
        button.layer.cornerRadius = 12;
        button.clipsToBounds = YES;

        // Use @selector(handleStartButton) as the action
        [button addTarget:(id)[UIApplication sharedApplication] action:@selector(handleStartButton) forControlEvents:UIControlEventTouchUpInside];

        [keyWindow addSubview:button];
        [keyWindow bringSubviewToFront:button];
        NSLog(@"[+] 'Start Task' button shown.");
    });
}

// This is the function that will execute the task when the button is tapped
void handleStartButton() {
    NSLog(@"[+] Auto task started by user button tap");

    // All the original task logic goes here
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
}
