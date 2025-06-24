#import <UIKit/UIKit.h>

@interface FloatingButton : UIButton
@end

@implementation FloatingButton {
    CGPoint startLocation;
}
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(100, 200, 60, 60)];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.1 green:0.6 blue:1 alpha:0.8];
        [self setTitle:@"Run" forState:UIControlStateNormal];
        self.layer.cornerRadius = 30;
        self.clipsToBounds = YES;
        [self addTarget:self action:@selector(runTask) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)runTask {
    NSLog(@"[+] Task manually started");

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

// Movable
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    startLocation = [[touches anyObject] locationInView:self.superview];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    CGPoint location = [[touches anyObject] locationInView:self.superview];
    CGPoint delta = CGPointMake(location.x - startLocation.x, location.y - startLocation.y);
    self.center = CGPointMake(self.center.x + delta.x, self.center.y + delta.y);
    startLocation = location;
}
@end

%hook UIApplication

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (keyWindow) {
            FloatingButton *button = [[FloatingButton alloc] init];
            [keyWindow addSubview:button];
            NSLog(@"[+] Floating button added");
        } else {
            NSLog(@"[!] Could not find keyWindow");
        }
    });
}

%end
