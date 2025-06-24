#import <UIKit/UIKit.h>

%hook UIApplication

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }

        if (!keyWindow) {
            NSLog(@"[!] Could not find key window");
            return;
        }

        UIButton *startButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [startButton setTitle:@"Start" forState:UIControlStateNormal];
        startButton.frame = CGRectMake(100, 100, 80, 40);
        startButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        [startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        startButton.layer.cornerRadius = 10;
        startButton.clipsToBounds = YES;

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
        [startButton addGestureRecognizer:pan];

        [startButton addTarget:self action:@selector(startButtonTapped) forControlEvents:UIControlEventTouchUpInside];

        [keyWindow addSubview:startButton];
        NSLog(@"[+] Start button added");
    });
}

%new
- (void)handleDrag:(UIPanGestureRecognizer *)gesture {
    UIView *v = gesture.view;
    CGPoint t = [gesture translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [gesture setTranslation:CGPointZero inView:v.superview];
}

%new
- (void)startButtonTapped {
    NSLog(@"[+] Start button tapped");

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

        NSString *token = parts[0]; // 28410720410e46cba6f616752b2914ef
        NSString *uid = parts[1];   // 191106925

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

        // Step 5: Restart app
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"[+] Restarting app...");
            exit(0);
        });
    }];

    [task resume];
}

%end
