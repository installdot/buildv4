#import <UIKit/UIKit.h>
#import <signal.h>
#import <unistd.h>
#import <objc/runtime.h>

static NSString *HOME() { return NSHomeDirectory(); }
static NSString *DOCS() { return [HOME() stringByAppendingPathComponent:@"Documents"]; }
static NSString *PREFS(){ return [HOME() stringByAppendingPathComponent:@"Library/Preferences"]; }

static UIButton *globalButton = nil;
static NSMutableString *debugLog = nil;

// Initialize debug log
static void initDebugLog() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        debugLog = [NSMutableString string];
    });
}

// Add to debug log
static void addLog(NSString *message) {
    initDebugLog();
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                         dateStyle:NSDateFormatterNoStyle
                                                         timeStyle:NSDateFormatterMediumStyle];
    [debugLog appendFormat:@"[%@] %@\n", timestamp, message];
}

// Helper function to show alerts
static void showAlert(NSString *title, NSString *message) {
    addLog([NSString stringWithFormat:@"Alert: %@ - %@", title, message]);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                          style:UIAlertActionStyleDefault
                                                        handler:nil];
        [alert addAction:okAction];
        
        // Add "Show Log" button for errors
        if ([title isEqualToString:@"Error"] || [title isEqualToString:@"Debug"]) {
            UIAlertAction *logAction = [UIAlertAction actionWithTitle:@"Show Full Log"
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction * _Nonnull action) {
                showAlert(@"Debug Log", debugLog);
            }];
            [alert addAction:logAction];
        }
        
        // Find top view controller
        UIViewController *topVC = nil;
        UIWindow *keyWindow = nil;
        
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        
        if (!keyWindow) {
            keyWindow = [UIApplication sharedApplication].windows.firstObject;
        }
        
        topVC = keyWindow.rootViewController;
        while (topVC.presentedViewController) {
            topVC = topVC.presentedViewController;
        }
        
        if (topVC) {
            [topVC presentViewController:alert animated:YES completion:nil];
        }
    });
}

// Show confirmation dialog
static void showConfirmation(NSString *title, NSString *message, void (^onConfirm)(void)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                             style:UIAlertActionStyleCancel
                                                           handler:nil];
        
        UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"Continue"
                                                               style:UIAlertActionStyleDestructive
                                                             handler:^(UIAlertAction * _Nonnull action) {
            if (onConfirm) onConfirm();
        }];
        
        [alert addAction:cancelAction];
        [alert addAction:confirmAction];
        
        UIViewController *topVC = nil;
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) keyWindow = [UIApplication sharedApplication].windows.firstObject;
        
        topVC = keyWindow.rootViewController;
        while (topVC.presentedViewController) {
            topVC = topVC.presentedViewController;
        }
        
        if (topVC) {
            [topVC presentViewController:alert animated:YES completion:nil];
        }
    });
}

static void saveAndCloseApp() {
    addLog(@"Initiating app closure");
    showAlert(@"M1 Complete", @"All operations successful!\n\nApp will close in 3 seconds...");
    
    UIApplication *app = [UIApplication sharedApplication];
    id delegate = app.delegate;
    if ([delegate respondsToSelector:@selector(applicationWillResignActive:)])
        [delegate applicationWillResignActive:app];
    if ([delegate respondsToSelector:@selector(applicationDidEnterBackground:)])
        [delegate applicationDidEnterBackground:app];
    sync();
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3000 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        addLog(@"Sending SIGTERM");
        kill(getpid(), SIGTERM);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{ 
            addLog(@"Sending SIGKILL");
            kill(getpid(), SIGKILL); 
        });
    });
}

static void runMode1_SaveModifyClose() {
    @autoreleasepool {
        addLog(@"========== M1 MODE STARTED ==========");
        
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *accFile  = [HOME() stringByAppendingPathComponent:@"acc.txt"];
        NSString *doneFile = [HOME() stringByAppendingPathComponent:@"suc.txt"];
        NSString *tmpFile  = [HOME() stringByAppendingPathComponent:@".acc_tmp.txt"];
        NSString *plist = [PREFS() stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
        NSString *txt   = [PREFS() stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.txt"];

        addLog([NSString stringWithFormat:@"Checking acc.txt at: %@", accFile]);
        
        // Step 1: Check if acc.txt exists
        if (![fm fileExistsAtPath:accFile]) {
            NSString *errorMsg = [NSString stringWithFormat:@"File not found:\n%@\n\nPlease create this file with format:\nemail|pass|uid|token", accFile];
            showAlert(@"Error - File Missing", errorMsg);
            addLog(@"ERROR: acc.txt not found");
            return;
        }
        addLog(@"✓ acc.txt found");

        // Step 2: Read accounts
        NSError *readError = nil;
        NSString *content = [NSString stringWithContentsOfFile:accFile 
                                                      encoding:NSUTF8StringEncoding 
                                                         error:&readError];
        if (!content) {
            NSString *errorMsg = [NSString stringWithFormat:@"Cannot read acc.txt\n\nError: %@\n\nPath: %@", 
                                 readError.localizedDescription, accFile];
            showAlert(@"Error - Read Failed", errorMsg);
            addLog([NSString stringWithFormat:@"ERROR: Cannot read acc.txt - %@", readError]);
            return;
        }
        addLog([NSString stringWithFormat:@"✓ Read acc.txt (%lu bytes)", (unsigned long)content.length]);

        // Step 3: Parse accounts
        NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSMutableArray *valid = [NSMutableArray arrayWithCapacity:lines.count];
        
        for (NSString *l in lines) {
            NSString *trimmed = [l stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                NSArray *parts = [trimmed componentsSeparatedByString:@"|"];
                if (parts.count == 4) {
                    [valid addObject:trimmed];
                } else {
                    addLog([NSString stringWithFormat:@"Skipped invalid line: %@", trimmed]);
                }
            }
        }
        
        if (valid.count == 0) {
            NSString *errorMsg = [NSString stringWithFormat:@"No valid accounts!\n\nTotal lines: %lu\nValid accounts: 0\n\nFormat required:\nemail|pass|uid|token", 
                                 (unsigned long)lines.count];
            showAlert(@"Error - No Valid Accounts", errorMsg);
            addLog(@"ERROR: No valid accounts found");
            return;
        }
        
        addLog([NSString stringWithFormat:@"✓ Found %lu valid accounts", (unsigned long)valid.count]);

        // Step 4: Select random account
        NSString *line = valid[arc4random_uniform((uint32_t)valid.count)];
        NSArray *p = [line componentsSeparatedByString:@"|"];
        NSString *email = p[0], *pass = p[1], *uid = p[2], *token = p[3];
        
        addLog([NSString stringWithFormat:@"Selected account: %@", email]);
        addLog([NSString stringWithFormat:@"UID: %@", uid]);

        // Step 5: Copy data files
        NSArray *files = @[@"item_data_1_.data", @"season_data_1_.data", @"statistic_1_.data",
                          @"weapon_evolution_data_1_.data", @"bp_data_1_.data", @"misc_data_1_.data"];
        
        int copiedCount = 0;
        int skippedCount = 0;
        NSMutableString *fileStatus = [NSMutableString string];
        
        for (NSString *f in files) {
            NSString *oldPath = [DOCS() stringByAppendingPathComponent:f];
            if (![fm fileExistsAtPath:oldPath]) {
                skippedCount++;
                addLog([NSString stringWithFormat:@"Skip (not found): %@", f]);
                continue;
            }
            
            NSString *newPath = [DOCS() stringByAppendingPathComponent:[f stringByReplacingOccurrencesOfString:@"1" withString:uid]];
            [fm removeItemAtPath:newPath error:nil];
            
            NSError *copyError = nil;
            BOOL success = [fm copyItemAtPath:oldPath toPath:newPath error:&copyError];
            if (success) {
                copiedCount++;
                addLog([NSString stringWithFormat:@"✓ Copied: %@", f]);
            } else {
                addLog([NSString stringWithFormat:@"✗ Failed to copy %@: %@", f, copyError]);
            }
        }
        
        addLog([NSString stringWithFormat:@"Files: %d copied, %d skipped", copiedCount, skippedCount]);

        // Step 6: Update plist
        addLog([NSString stringWithFormat:@"Deleting old plist: %@", plist]);
        [fm removeItemAtPath:plist error:nil];
        
        BOOL plistSuccess = NO;
        if ([fm fileExistsAtPath:txt]) {
            NSString *tpl = [NSString stringWithContentsOfFile:txt encoding:NSUTF8StringEncoding error:nil];
            if (tpl) {
                NSString *mod = [[tpl stringByReplacingOccurrencesOfString:@"98989898" withString:uid]
                                stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];
                
                NSError *writeError = nil;
                plistSuccess = [mod writeToFile:plist atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
                
                if (plistSuccess) {
                    addLog(@"✓ Plist written successfully");
                } else {
                    addLog([NSString stringWithFormat:@"✗ Failed to write plist: %@", writeError]);
                }
            } else {
                addLog(@"✗ Cannot read template file");
                showAlert(@"Warning", [NSString stringWithFormat:@"Template file exists but cannot be read:\n%@", txt]);
            }
        } else {
            addLog([NSString stringWithFormat:@"✗ Template not found: %@", txt]);
            showAlert(@"Warning", [NSString stringWithFormat:@"Template file not found:\n%@\n\nPlist will not be updated.", txt]);
        }

        // Step 7: Save used account
        NSString *doneLine = [NSString stringWithFormat:@"%@|%@\n", email, pass];
        if ([fm fileExistsAtPath:doneFile]) {
            NSFileHandle *d = [NSFileHandle fileHandleForWritingAtPath:doneFile];
            if (d) { 
                [d seekToEndOfFile]; 
                [d writeData:[doneLine dataUsingEncoding:NSUTF8StringEncoding]]; 
                [d closeFile];
                addLog(@"✓ Appended to suc.txt");
            }
        } else {
            [doneLine writeToFile:doneFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
            addLog(@"✓ Created suc.txt");
        }

        // Step 8: Update account list
        NSMutableArray *remain = [valid mutableCopy];
        [remain removeObject:line];
        
        NSError *updateError = nil;
        [[remain componentsJoinedByString:@"\n"] writeToFile:tmpFile 
                                                   atomically:YES 
                                                     encoding:NSUTF8StringEncoding 
                                                        error:&updateError];
        
        if (updateError) {
            addLog([NSString stringWithFormat:@"✗ Error writing temp file: %@", updateError]);
        } else {
            [fm removeItemAtPath:accFile error:nil];
            [fm moveItemAtPath:tmpFile toPath:accFile error:nil];
            addLog(@"✓ Updated acc.txt");
        }

        addLog(@"========== M1 MODE COMPLETED ==========");

        // Show detailed success message
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *successMsg = [NSString stringWithFormat:@"✓ Account: %@\n✓ UID: %@\n✓ Files copied: %d\n✓ Remaining accounts: %lu\n\nTap 'Show Full Log' for details.",
                                   email, uid, copiedCount, (unsigned long)remain.count];
            
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✓ Success!"
                                                                           message:successMsg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *logAction = [UIAlertAction actionWithTitle:@"Show Full Log"
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction * _Nonnull action) {
                showAlert(@"Full Debug Log", debugLog);
            }];
            
            UIAlertAction *continueAction = [UIAlertAction actionWithTitle:@"OK - Close App"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^(UIAlertAction * _Nonnull action) {
                saveAndCloseApp();
            }];
            
            [alert addAction:logAction];
            [alert addAction:continueAction];
            
            UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
            while (topVC.presentedViewController) {
                topVC = topVC.presentedViewController;
            }
            
            if (topVC) {
                [topVC presentViewController:alert animated:YES completion:nil];
            }
        });
    }
}

// Block-based action helper
@interface UIControl (BlockAction)
- (void)addActionForControlEvents:(UIControlEvents)controlEvents withBlock:(void (^)(void))block;
@end

@implementation UIControl (BlockAction)

- (void)addActionForControlEvents:(UIControlEvents)controlEvents withBlock:(void (^)(void))block {
    objc_setAssociatedObject(self, @selector(handleActionBlock:), [block copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self addTarget:self action:@selector(handleActionBlock:) forControlEvents:controlEvents];
}

- (void)handleActionBlock:(id)sender {
    void (^block)(void) = objc_getAssociatedObject(self, _cmd);
    if (block) {
        block();
    }
}

@end

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 800 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            if (globalButton) {
                addLog(@"Button already exists, skipping creation");
                return;
            }
            
            addLog(@"Attempting to create button...");
            
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
                addLog([NSString stringWithFormat:@"Found window: %@", keyWindow]);
                
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
                
                [globalButton addActionForControlEvents:UIControlEventTouchUpInside withBlock:^{
                    addLog(@"===== BUTTON CLICKED =====");
                    
                    // Show confirmation dialog
                    showConfirmation(@"M1 Mode", 
                                   @"Start account switch?\n\nThis will:\n• Copy data files\n• Update plist\n• Close the app", ^{
                        // Visual feedback
                        globalButton.transform = CGAffineTransformMakeScale(0.9, 0.9);
                        globalButton.backgroundColor = [[UIColor greenColor] colorWithAlphaComponent:0.9];
                        
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC),
                                       dispatch_get_main_queue(), ^{
                            globalButton.transform = CGAffineTransformIdentity;
                            globalButton.backgroundColor = [[UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0] colorWithAlphaComponent:0.9];
                        });
                        
                        // Run the main function
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                            runMode1_SaveModifyClose();
                        });
                    });
                }];
                
                globalButton.userInteractionEnabled = YES;
                globalButton.exclusiveTouch = NO;
                keyWindow.userInteractionEnabled = YES;
                
                [keyWindow addSubview:globalButton];
                [keyWindow bringSubviewToFront:globalButton];
                
                addLog(@"✓ Button created and added to window");
                
                // Show welcome message
                showAlert(@"M1 Mode Ready", @"✓ Button loaded successfully!\n\nTap the red M1 button to start account switching.");
                
            } else {
                addLog(@"ERROR: No window found!");
                showAlert(@"Error", @"Could not find window to add button!\n\nPlease restart the app.");
            }
        });
    });
}

%end
