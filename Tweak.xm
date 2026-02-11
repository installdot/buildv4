#import <UIKit/UIKit.h>
#import <signal.h>
#import <unistd.h>
#import <objc/runtime.h>

static NSString *HOME() { return NSHomeDirectory(); }
static NSString *DOCS() { return [HOME() stringByAppendingPathComponent:@"Documents"]; }
static NSString *PREFS(){ return [HOME() stringByAppendingPathComponent:@"Library/Preferences"]; }

static UIButton *globalButton = nil;

static void saveAndCloseApp() {
    UIApplication *app = [UIApplication sharedApplication];
    id delegate = app.delegate;
    if ([delegate respondsToSelector:@selector(applicationWillResignActive:)])
        [delegate applicationWillResignActive:app];
    if ([delegate respondsToSelector:@selector(applicationDidEnterBackground:)])
        [delegate applicationDidEnterBackground:app];
    sync();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        kill(getpid(), SIGTERM);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{ kill(getpid(), SIGKILL); });
    });
}

static void runMode1_SaveModifyClose() {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *accFile  = [HOME() stringByAppendingPathComponent:@"acc.txt"];
        NSString *doneFile = [HOME() stringByAppendingPathComponent:@"suc.txt"];
        NSString *tmpFile  = [HOME() stringByAppendingPathComponent:@".acc_tmp.txt"];
        NSString *plist = [PREFS() stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
        NSString *txt   = [PREFS() stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.txt"];

        if (![fm fileExistsAtPath:accFile]) {
            NSLog(@"[M1] ERROR: acc.txt not found!");
            return;
        }

        NSString *content = [NSString stringWithContentsOfFile:accFile encoding:NSUTF8StringEncoding error:nil];
        if (!content) {
            NSLog(@"[M1] ERROR: Could not read acc.txt!");
            return;
        }

        NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSMutableArray *valid = [NSMutableArray arrayWithCapacity:lines.count];
        for (NSString *l in lines) {
            NSString *trimmed = [l stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0 && [[trimmed componentsSeparatedByString:@"|"] count] == 4)
                [valid addObject:trimmed];
        }
        
        if (valid.count == 0) {
            NSLog(@"[M1] ERROR: No valid accounts found!");
            return;
        }

        NSLog(@"[M1] Found %lu valid accounts", (unsigned long)valid.count);

        NSString *line = valid[arc4random_uniform((uint32_t)valid.count)];
        NSArray *p = [line componentsSeparatedByString:@"|"];
        NSString *email = p[0], *pass = p[1], *uid = p[2], *token = p[3];

        NSLog(@"[M1] Processing account: %@", email);

        NSArray *files = @[@"item_data_1_.data", @"season_data_1_.data", @"statistic_1_.data",
                          @"weapon_evolution_data_1_.data", @"bp_data_1_.data", @"misc_data_1_.data"];
        for (NSString *f in files) {
            NSString *oldPath = [DOCS() stringByAppendingPathComponent:f];
            if (![fm fileExistsAtPath:oldPath]) continue;
            NSString *newPath = [DOCS() stringByAppendingPathComponent:[f stringByReplacingOccurrencesOfString:@"1" withString:uid]];
            [fm removeItemAtPath:newPath error:nil];
            [fm copyItemAtPath:oldPath toPath:newPath error:nil];
        }

        [fm removeItemAtPath:plist error:nil];
        if ([fm fileExistsAtPath:txt]) {
            NSString *tpl = [NSString stringWithContentsOfFile:txt encoding:NSUTF8StringEncoding error:nil];
            if (tpl) {
                NSString *mod = [[tpl stringByReplacingOccurrencesOfString:@"98989898" withString:uid]
                                stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];
                [mod writeToFile:plist atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }

        NSString *doneLine = [NSString stringWithFormat:@"%@|%@\n", email, pass];
        if ([fm fileExistsAtPath:doneFile]) {
            NSFileHandle *d = [NSFileHandle fileHandleForWritingAtPath:doneFile];
            if (d) { [d seekToEndOfFile]; [d writeData:[doneLine dataUsingEncoding:NSUTF8StringEncoding]]; [d closeFile]; }
        } else {
            [doneLine writeToFile:doneFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }

        NSMutableArray *remain = [valid mutableCopy];
        [remain removeObject:line];
        [[remain componentsJoinedByString:@"\n"] writeToFile:tmpFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [fm removeItemAtPath:accFile error:nil];
        [fm moveItemAtPath:tmpFile toPath:accFile error:nil];

        NSLog(@"[M1] Processing complete, closing app...");
        saveAndCloseApp();
    }
}

// Block-based action helper
@interface UIControl (BlockAction)
- (void)addActionForControlEvents:(UIControlEvents)controlEvents withBlock:(void (^)(void))block;
@end

@implementation UIControl (BlockAction)

- (void)addActionForControlEvents:(UIControlEvents)controlEvents withBlock:(void (^)(void))block {
    // Store the block
    objc_setAssociatedObject(self, @selector(handleActionBlock:), [block copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
    
    // Add target-action
    [self addTarget:self action:@selector(handleActionBlock:) forControlEvents:controlEvents];
}

- (void)handleActionBlock:(id)sender {
    void (^block)(void) = objc_getAssociatedObject(self, _cmd);
    if (block) {
        block();
    }
}

@end

// METHOD: MOST RELIABLE - Block-based action
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 800 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            if (globalButton) {
                NSLog(@"[M1] Button already exists, skipping...");
                return;
            }
            
            UIWindow *keyWindow = self.view.window;
            if (!keyWindow) {
                for (UIWindow *window in [UIApplication sharedApplication].windows) {
                    if (window.rootViewController != nil) {
                        keyWindow = window;
                        break;
                    }
                }
            }
            
            if (!keyWindow) {
                keyWindow = [UIApplication sharedApplication].keyWindow;
            }
            
            if (keyWindow) {
                NSLog(@"[M1] Creating button on window: %@", keyWindow);
                
                globalButton = [UIButton buttonWithType:UIButtonTypeCustom];
                globalButton.frame = CGRectMake(20, 120, 56, 56);
                globalButton.layer.cornerRadius = 28;
                globalButton.backgroundColor = [[UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0] colorWithAlphaComponent:0.9];
                globalButton.tag = 99999;
                
                [globalButton setTitle:@"M1" forState:UIControlStateNormal];
                globalButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
                [globalButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                
                globalButton.layer.shadowColor = [UIColor blackColor].CGColor;
                globalButton.layer.shadowOffset = CGSizeMake(0, 3);
                globalButton.layer.shadowRadius = 5;
                globalButton.layer.shadowOpacity = 0.4;
                globalButton.layer.borderWidth = 2.5;
                globalButton.layer.borderColor = [UIColor whiteColor].CGColor;
                
                // CRITICAL FIX: Use block-based action (most reliable)
                [globalButton addActionForControlEvents:UIControlEventTouchUpInside withBlock:^{
                    NSLog(@"[M1] ===== BUTTON CLICKED! =====");
                    
                    // Visual feedback
                    globalButton.transform = CGAffineTransformMakeScale(0.9, 0.9);
                    globalButton.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.9];
                    
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC),
                                   dispatch_get_main_queue(), ^{
                        globalButton.transform = CGAffineTransformIdentity;
                        globalButton.backgroundColor = [[UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0] colorWithAlphaComponent:0.9];
                    });
                    
                    // Run the main function
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                        NSLog(@"[M1] Starting Mode1 process...");
                        runMode1_SaveModifyClose();
                    });
                }];
                
                // Additional touch handlers for debugging
                [globalButton addTarget:globalButton 
                                action:@selector(touchDown:) 
                      forControlEvents:UIControlEventTouchDown];
                
                // Ensure button is fully interactive
                globalButton.userInteractionEnabled = YES;
                globalButton.exclusiveTouch = NO;
                keyWindow.userInteractionEnabled = YES;
                
                [keyWindow addSubview:globalButton];
                [keyWindow bringSubviewToFront:globalButton];
                
                NSLog(@"[M1] ===== BUTTON ADDED SUCCESSFULLY! =====");
                NSLog(@"[M1] Button frame: %@", NSStringFromCGRect(globalButton.frame));
                NSLog(@"[M1] Button superview: %@", globalButton.superview);
                NSLog(@"[M1] Button userInteractionEnabled: %d", globalButton.userInteractionEnabled);
            } else {
                NSLog(@"[M1] ERROR: No window found!");
            }
        });
    });
}

%end

// Debug method
%hook UIButton

- (void)touchDown:(id)sender {
    if (self.tag == 99999) {
        NSLog(@"[M1] TouchDown detected on button!");
    }
}

%end
