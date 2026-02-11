#import <UIKit/UIKit.h>
#import <signal.h>
#import <unistd.h>
#import <objc/runtime.h>

static UIButton *globalButton = nil;
static NSMutableString *debugLog = nil;

// Get proper directories for non-jailbroken app sandbox
static NSString *getDocumentsDirectory() {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths firstObject];
}

static NSString *getLibraryDirectory() {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    return [paths firstObject];
}

static NSString *getPreferencesDirectory() {
    return [getLibraryDirectory() stringByAppendingPathComponent:@"Preferences"];
}

static NSString *getCachesDirectory() {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [paths firstObject];
}

static NSString *getTempDirectory() {
    return NSTemporaryDirectory();
}

// Search for a file in multiple locations
static NSString *findFile(NSString *filename) {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Search locations in order of priority
    NSArray *searchPaths = @[
        getDocumentsDirectory(),
        getLibraryDirectory(),
        getCachesDirectory(),
        getTempDirectory(),
        [getLibraryDirectory() stringByAppendingPathComponent:@"Application Support"],
        [[NSBundle mainBundle] bundlePath],
        [[NSBundle mainBundle] resourcePath]
    ];
    
    for (NSString *basePath in searchPaths) {
        NSString *fullPath = [basePath stringByAppendingPathComponent:filename];
        if ([fm fileExistsAtPath:fullPath]) {
            return fullPath;
        }
        
        // Also search subdirectories
        NSError *error = nil;
        NSArray *contents = [fm contentsOfDirectoryAtPath:basePath error:&error];
        for (NSString *item in contents) {
            NSString *itemPath = [basePath stringByAppendingPathComponent:item];
            BOOL isDir;
            if ([fm fileExistsAtPath:itemPath isDirectory:&isDir] && isDir) {
                NSString *subPath = [itemPath stringByAppendingPathComponent:filename];
                if ([fm fileExistsAtPath:subPath]) {
                    return subPath;
                }
            }
        }
    }
    
    return nil;
}

// Recursively search for data files
static NSArray *findDataFiles(NSString *pattern) {
    NSMutableArray *found = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSArray *searchPaths = @[
        getDocumentsDirectory(),
        getLibraryDirectory(),
        getCachesDirectory()
    ];
    
    for (NSString *basePath in searchPaths) {
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:basePath];
        for (NSString *file in enumerator) {
            if ([file hasSuffix:pattern] || [file containsString:pattern]) {
                NSString *fullPath = [basePath stringByAppendingPathComponent:file];
                [found addObject:fullPath];
            }
        }
    }
    
    return found;
}

// Initialize debug log
static void initDebugLog() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        debugLog = [NSMutableString string];
    });
}

static void addLog(NSString *message) {
    initDebugLog();
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                         dateStyle:NSDateFormatterNoStyle
                                                         timeStyle:NSDateFormatterMediumStyle];
    [debugLog appendFormat:@"[%@] %@\n", timestamp, message];
}

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
        
        if ([title isEqualToString:@"Error"] || [title isEqualToString:@"Debug"]) {
            UIAlertAction *logAction = [UIAlertAction actionWithTitle:@"Show Log"
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction * _Nonnull action) {
                showAlert(@"Debug Log", debugLog);
            }];
            [alert addAction:logAction];
        }
        
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
        addLog([NSString stringWithFormat:@"Documents: %@", getDocumentsDirectory()]);
        addLog([NSString stringWithFormat:@"Library: %@", getLibraryDirectory()]);
        addLog([NSString stringWithFormat:@"Preferences: %@", getPreferencesDirectory()]);
        
        NSFileManager *fm = [NSFileManager defaultManager];
        
        // Search for acc.txt in app sandbox
        addLog(@"Searching for acc.txt...");
        NSString *accFile = findFile(@"acc.txt");
        
        if (!accFile) {
            // If not found, create in Documents
            accFile = [getDocumentsDirectory() stringByAppendingPathComponent:@"acc.txt"];
            addLog([NSString stringWithFormat:@"acc.txt not found, will use: %@", accFile]);
        } else {
            addLog([NSString stringWithFormat:@"✓ Found acc.txt at: %@", accFile]);
        }
        
        NSString *doneFile = [getDocumentsDirectory() stringByAppendingPathComponent:@"suc.txt"];
        NSString *tmpFile  = [getDocumentsDirectory() stringByAppendingPathComponent:@".acc_tmp.txt"];

        // Search for plist and template
        addLog(@"Searching for plist files...");
        NSString *plist = findFile(@"com.ChillyRoom.DungeonShooter.plist");
        NSString *txt   = findFile(@"com.ChillyRoom.DungeonShooter.txt");
        
        if (!plist) {
            plist = [getPreferencesDirectory() stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
            addLog([NSString stringWithFormat:@"plist not found, will use: %@", plist]);
        } else {
            addLog([NSString stringWithFormat:@"✓ Found plist at: %@", plist]);
        }
        
        if (!txt) {
            txt = [getDocumentsDirectory() stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.txt"];
            addLog([NSString stringWithFormat:@"template not found, will use: %@", txt]);
        } else {
            addLog([NSString stringWithFormat:@"✓ Found template at: %@", txt]);
        }

        // Check if acc.txt exists
        if (![fm fileExistsAtPath:accFile]) {
            NSString *errorMsg = [NSString stringWithFormat:@"acc.txt not found!\n\nSearched in:\n• Documents\n• Library\n• Caches\n• Temp\n\nPlease create:\n%@\n\nFormat: email|pass|uid|token", accFile];
            showAlert(@"Error - File Missing", errorMsg);
            addLog(@"ERROR: acc.txt not found in any location");
            return;
        }

        // Read accounts
        NSError *readError = nil;
        NSString *content = [NSString stringWithContentsOfFile:accFile 
                                                      encoding:NSUTF8StringEncoding 
                                                         error:&readError];
        if (!content) {
            NSString *errorMsg = [NSString stringWithFormat:@"Cannot read acc.txt\n\nPath: %@\n\nError: %@", 
                                 accFile, readError.localizedDescription];
            showAlert(@"Error - Read Failed", errorMsg);
            addLog([NSString stringWithFormat:@"ERROR: Cannot read acc.txt - %@", readError]);
            return;
        }
        addLog([NSString stringWithFormat:@"✓ Read acc.txt (%lu bytes)", (unsigned long)content.length]);

        // Parse accounts
        NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSMutableArray *valid = [NSMutableArray arrayWithCapacity:lines.count];
        
        for (NSString *l in lines) {
            NSString *trimmed = [l stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                NSArray *parts = [trimmed componentsSeparatedByString:@"|"];
                if (parts.count == 4) {
                    [valid addObject:trimmed];
                }
            }
        }
        
        if (valid.count == 0) {
            NSString *errorMsg = [NSString stringWithFormat:@"No valid accounts!\n\nFile: %@\n\nFormat: email|pass|uid|token", accFile];
            showAlert(@"Error - No Valid Accounts", errorMsg);
            addLog(@"ERROR: No valid accounts found");
            return;
        }
        
        addLog([NSString stringWithFormat:@"✓ Found %lu valid accounts", (unsigned long)valid.count]);

        // Select random account
        NSString *line = valid[arc4random_uniform((uint32_t)valid.count)];
        NSArray *p = [line componentsSeparatedByString:@"|"];
        NSString *email = p[0], *pass = p[1], *uid = p[2], *token = p[3];
        
        addLog([NSString stringWithFormat:@"Selected: %@ (UID: %@)", email, uid]);

        // Search for data files
        addLog(@"Searching for data files...");
        NSArray *dataFiles = findDataFiles(@"_data_1_.data");
        addLog([NSString stringWithFormat:@"Found %lu data files", (unsigned long)dataFiles.count]);
        
        // Also search for specific patterns
        NSArray *filePatterns = @[@"item_data", @"season_data", @"statistic", 
                                 @"weapon_evolution", @"bp_data", @"misc_data"];
        
        int copiedCount = 0;
        NSMutableArray *foundFiles = [NSMutableArray array];
        
        for (NSString *pattern in filePatterns) {
            NSArray *matches = findDataFiles(pattern);
            [foundFiles addObjectsFromArray:matches];
        }
        
        // Remove duplicates
        NSSet *uniqueFiles = [NSSet setWithArray:foundFiles];
        addLog([NSString stringWithFormat:@"Found %lu unique data files", (unsigned long)uniqueFiles.count]);
        
        for (NSString *oldPath in uniqueFiles) {
            if (![oldPath containsString:@"_1_"]) continue;
            
            NSString *filename = [oldPath lastPathComponent];
            NSString *newFilename = [filename stringByReplacingOccurrencesOfString:@"_1_" withString:[NSString stringWithFormat:@"_%@_", uid]];
            NSString *directory = [oldPath stringByDeletingLastPathComponent];
            NSString *newPath = [directory stringByAppendingPathComponent:newFilename];
            
            [fm removeItemAtPath:newPath error:nil];
            
            NSError *copyError = nil;
            BOOL success = [fm copyItemAtPath:oldPath toPath:newPath error:&copyError];
            if (success) {
                copiedCount++;
                addLog([NSString stringWithFormat:@"✓ Copied: %@ → %@", filename, newFilename]);
            } else {
                addLog([NSString stringWithFormat:@"✗ Failed: %@ (%@)", filename, copyError.localizedDescription]);
            }
        }

        // Update plist
        addLog([NSString stringWithFormat:@"Updating plist: %@", plist]);
        [fm removeItemAtPath:plist error:nil];
        
        if ([fm fileExistsAtPath:txt]) {
            NSString *tpl = [NSString stringWithContentsOfFile:txt encoding:NSUTF8StringEncoding error:nil];
            if (tpl) {
                NSString *mod = [[tpl stringByReplacingOccurrencesOfString:@"98989898" withString:uid]
                                stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];
                
                NSError *writeError = nil;
                BOOL success = [mod writeToFile:plist atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
                
                if (success) {
                    addLog(@"✓ Plist updated");
                } else {
                    addLog([NSString stringWithFormat:@"✗ Plist write failed: %@", writeError]);
                }
            }
        } else {
            addLog(@"✗ Template file not found");
        }

        // Save used account
        NSString *doneLine = [NSString stringWithFormat:@"%@|%@\n", email, pass];
        if ([fm fileExistsAtPath:doneFile]) {
            NSFileHandle *d = [NSFileHandle fileHandleForWritingAtPath:doneFile];
            if (d) { 
                [d seekToEndOfFile]; 
                [d writeData:[doneLine dataUsingEncoding:NSUTF8StringEncoding]]; 
                [d closeFile];
            }
        } else {
            [doneLine writeToFile:doneFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }

        // Update account list
        NSMutableArray *remain = [valid mutableCopy];
        [remain removeObject:line];
        [[remain componentsJoinedByString:@"\n"] writeToFile:tmpFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [fm removeItemAtPath:accFile error:nil];
        [fm moveItemAtPath:tmpFile toPath:accFile error:nil];

        addLog(@"========== COMPLETED ==========");

        // Show success
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *msg = [NSString stringWithFormat:@"✓ Account: %@\n✓ UID: %@\n✓ Files copied: %d/%lu\n✓ Remaining: %lu\n\nPaths:\n• acc.txt: %@\n• plist: %@",
                           email, uid, copiedCount, (unsigned long)uniqueFiles.count, (unsigned long)remain.count,
                           [accFile lastPathComponent], [plist lastPathComponent]];
            
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✓ Success!"
                                                                           message:msg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *logAction = [UIAlertAction actionWithTitle:@"Show Log"
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction * _Nonnull action) {
                showAlert(@"Debug Log", debugLog);
            }];
            
            UIAlertAction *continueAction = [UIAlertAction actionWithTitle:@"Close App"
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
    if (block) block();
}

@end

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 800 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            if (globalButton) return;
            
            addLog(@"Creating button...");
            
            UIWindow *keyWindow = self.view.window;
            if (!keyWindow) {
                for (UIWindow *window in [UIApplication sharedApplication].windows) {
                    if (window.rootViewController != nil) {
                        keyWindow = window;
                        break;
                    }
                }
            }
            
            if (keyWindow) {
                globalButton = [UIButton buttonWithType:UIButtonTypeCustom];
                globalButton.frame = CGRectMake(20, 120, 56, 56);
                globalButton.layer.cornerRadius = 28;
                globalButton.backgroundColor = [[UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0] colorWithAlphaComponent:0.9];
                
                [globalButton setTitle:@"M1" forState:UIControlStateNormal];
                globalButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
                
                globalButton.layer.shadowColor = [UIColor blackColor].CGColor;
                globalButton.layer.shadowOffset = CGSizeMake(0, 3);
                globalButton.layer.shadowRadius = 5;
                globalButton.layer.shadowOpacity = 0.4;
                globalButton.layer.borderWidth = 2.5;
                globalButton.layer.borderColor = [UIColor whiteColor].CGColor;
                
                [globalButton addActionForControlEvents:UIControlEventTouchUpInside withBlock:^{
                    addLog(@"===== BUTTON CLICKED =====");
                    
                    showConfirmation(@"M1 Mode", 
                                   @"Start account switch?\n\nSearches app sandbox for:\n• acc.txt\n• Data files\n• Plist files", ^{
                        globalButton.transform = CGAffineTransformMakeScale(0.9, 0.9);
                        globalButton.backgroundColor = [[UIColor greenColor] colorWithAlphaComponent:0.9];
                        
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC),
                                       dispatch_get_main_queue(), ^{
                            globalButton.transform = CGAffineTransformIdentity;
                            globalButton.backgroundColor = [[UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0] colorWithAlphaComponent:0.9];
                        });
                        
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                            runMode1_SaveModifyClose();
                        });
                    });
                }];
                
                globalButton.userInteractionEnabled = YES;
                keyWindow.userInteractionEnabled = YES;
                
                [keyWindow addSubview:globalButton];
                [keyWindow bringSubviewToFront:globalButton];
                
                addLog(@"✓ Button added");
                
                NSString *paths = [NSString stringWithFormat:@"App Sandbox Paths:\n\nDocuments:\n%@\n\nLibrary:\n%@\n\nPreferences:\n%@\n\nPlace acc.txt in Documents folder.",
                                  getDocumentsDirectory(), getLibraryDirectory(), getPreferencesDirectory()];
                
                showAlert(@"M1 Ready", paths);
            }
        });
    });
}

%end
