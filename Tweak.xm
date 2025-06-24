#import <UIKit/UIKit.h>

void performTokenTask(void) {
    NSLog(@"[+] Manual task started");

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

        NSString *token = parts[0];
        NSString *uid = parts[1];

        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];

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

        NSString *prefsPath = @"/Library/Preferences/";
        NSString *plistPath = [prefsPath stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
        NSString *txtPath   = [prefsPath stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.txt"];

        if ([fm fileExistsAtPath:plistPath]) {
            NSError *deleteError = nil;
            if ([fm removeItemAtPath:plistPath error:&deleteError]) {
                NSLog(@"[+] Deleted existing plist");
            } else {
                NSLog(@"[!] Could not delete plist: %@", deleteError);
            }
        }

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

        NSLog(@"[+] Manual task complete.");
    }];

    [task resume];
}

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
            NSLog(@"[!] No keyWindow found.");
            return;
        }

        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:@"Start Task" forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.backgroundColor = [UIColor systemBlueColor];
        button.frame = CGRectMake(40, 100, 150, 50);
        button.layer.cornerRadius = 10;
        [button addTarget:nil action:@selector(runManualTask) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:button];

        NSLog(@"[+] Manual trigger button added to UI");
    });
}

%new
- (void)runManualTask {
    performTokenTask();
}

%end
