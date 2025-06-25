#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@interface MyLogicButton : UIButton
@end

@implementation MyLogicButton
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(50, 150, 220, 60)];
    if (self) {
        [self setTitle:@"Run Token Patch" forState:UIControlStateNormal];
        [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 12.0;
        [self addTarget:self action:@selector(runLogic) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)runLogic {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *docsDir = @"/var/mobile/Containers/Data/Application/F1E40EDC-60EB-4CDE-B8B6-0D103BE21CB7/Documents";
        NSString *prefDir = @"/var/mobile/Containers/Data/Application/F1E40EDC-60EB-4CDE-B8B6-0D103BE21CB7/Library/Preferences";
        NSString *oldPlistPath = [prefDir stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
        NSString *txtFilePath = [prefDir stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.txt"];

        // 1. Download token
        NSURL *url = [NSURL URLWithString:@"https://chillysilly.frfrnocap.men/token.php?gen"];
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (!data || data.length == 0) {
            NSLog(@"[!] Failed to fetch token");
            return;
        }

        NSString *response = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSArray *parts = [response componentsSeparatedByString:@"|"];
        if (parts.count < 2) {
            NSLog(@"[!] Malformed token response: %@", response);
            return;
        }

        NSString *token = parts[0];
        NSString *userID = parts[1];

        NSLog(@"[+] Token: %@", token);
        NSLog(@"[+] User ID: %@", userID);

        // 2. Copy and rename data files
        NSArray *files = @[
            @"item_data_1_.data",
            @"season_data_1_.data",
            @"statistic_1_.data",
            @"weapon_evolution_data_1_.data"
        ];

        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *file in files) {
            NSString *oldPath = [docsDir stringByAppendingPathComponent:file];
            NSString *newFile = [file stringByReplacingOccurrencesOfString:@"1" withString:userID];
            NSString *newPath = [docsDir stringByAppendingPathComponent:newFile];
            if ([fm fileExistsAtPath:oldPath]) {
                NSError *copyError = nil;
                [fm copyItemAtPath:oldPath toPath:newPath error:&copyError];
                if (copyError) {
                    NSLog(@"[!] Copy failed: %@", copyError.localizedDescription);
                } else {
                    NSLog(@"[+] Copied %@ → %@", file, newFile);
                }
            } else {
                NSLog(@"[!] Missing file: %@", file);
            }
        }

        // 3. Delete old plist
        if ([fm fileExistsAtPath:oldPlistPath]) {
            NSError *removeError = nil;
            [fm removeItemAtPath:oldPlistPath error:&removeError];
            if (!removeError) {
                NSLog(@"[+] Deleted old plist");
            } else {
                NSLog(@"[!] Failed to delete plist: %@", removeError.localizedDescription);
            }
        }

        // 4. Write new plist
        if ([fm fileExistsAtPath:txtFilePath]) {
            NSError *readErr = nil;
            NSString *txt = [NSString stringWithContentsOfFile:txtFilePath encoding:NSUTF8StringEncoding error:&readErr];
            if (!readErr) {
                NSString *modified = [[txt stringByReplacingOccurrencesOfString:@"98989898" withString:userID]
                                        stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];
                NSError *writeErr = nil;
                [modified writeToFile:oldPlistPath atomically:YES encoding:NSUTF8StringEncoding error:&writeErr];
                if (!writeErr) {
                    NSLog(@"[+] New plist written");
                } else {
                    NSLog(@"[!] Failed to write plist: %@", writeErr.localizedDescription);
                }
            } else {
                NSLog(@"[!] Failed to read .txt: %@", readErr.localizedDescription);
            }
        } else {
            NSLog(@"[!] .txt config not found at %@", txtFilePath);
        }

        NSLog(@"[✓] Done");
    });
}
@end

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;

    UIWindow *win = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    win.windowLevel = UIWindowLevelAlert + 1;

    UIViewController *vc = [UIViewController new];
    win.rootViewController = vc;

    MyLogicButton *button = [[MyLogicButton alloc] init];
    [vc.view addSubview:button];

    win.hidden = NO;
    [win makeKeyAndVisible];
}

%end
