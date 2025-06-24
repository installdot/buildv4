#import <UIKit/UIKit.h>

%hook UIApplication

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].windows.firstObject;
        if (!window) return;

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

        [window addSubview:startButton];
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
            NSLog(@"[!] Request failed: %@", error);
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
                NSLog(@"[!] File not found: %@", name);
                continue;
            }

            NSString *newName = [name stringByReplacingOccurrencesOfString:@"1" withString:uid];
            NSString *newPath = [docsDir stringByAppendingPathComponent:newName];

            NSError *copyError = nil;
            if ([fm copyItemAtPath:originalPath toPath:newPath error:&copyError]) {
                NSLog(@"[+] Copied %@ → %@", name, newName);
            } else {
                NSLog(@"[!] Copy failed: %@", copyError);
            }
        }

        // Step 2: Handle preferences in /Library/Preferences
        NSString *prefsPath = @"/Library/Preferences/";
        NSString *plistPath = [prefsPath stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
        NSString *txtPath   = [prefsPath stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.txt"];

        // Delete old plist
        if ([fm fileExistsAtPath:plistPath]) {
            NSError *deleteError = nil;
            if ([fm removeItemAtPath:plistPath error:&deleteError]) {
                NSLog(@"[+] Deleted old plist");
            } else {
                NSLog(@"[!] Failed to delete plist: %@", deleteError);
            }
        }

        // Copy and modify txt
        if ([fm fileExistsAtPath:txtPath]) {
            NSError *readError = nil;
            NSString *txtContent = [NSString stringWithContentsOfFile:txtPath encoding:NSUTF8StringEncoding error:&readError];

            if (txtContent && !readError) {
                NSString *modified = [txtContent stringByReplacingOccurrencesOfString:@"98989898" withString:uid];
                modified = [modified stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];

                NSError *writeError = nil;
                [modified writeToFile:plistPath atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
                if (!writeError) {
                    NSLog(@"[+] Wrote modified plist");
                } else {
                    NSLog(@"[!] Failed to write plist: %@", writeError);
                }
            } else {
                NSLog(@"[!] Failed to read txt: %@", readError);
            }
        } else {
            NSLog(@"[!] .txt file does not exist");
        }

    }];
    [task resume];
}

%end
