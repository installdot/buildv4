#import <UIKit/UIKit.h>
#import <signal.h>
#import <unistd.h>
#import <objc/runtime.h>

static UIButton *globalButton = nil;

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

// Search for a file ANYWHERE in sandbox
static NSString *findFileAnywhere(NSString *filename) {
    NSFileManager *fm = [NSFileManager defaultManager];
    
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
        // Check directly in this folder
        NSString *directPath = [basePath stringByAppendingPathComponent:filename];
        if ([fm fileExistsAtPath:directPath]) {
            return directPath;
        }
        
        // Recursively search subdirectories
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:basePath];
        for (NSString *file in enumerator) {
            if ([[file lastPathComponent] isEqualToString:filename]) {
                return [basePath stringByAppendingPathComponent:file];
            }
        }
    }
    
    return nil;
}

// Find all data files matching pattern
static NSArray *findAllDataFiles(NSString *pattern) {
    NSMutableArray *found = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSArray *searchPaths = @[
        getDocumentsDirectory(),
        getLibraryDirectory(),
        getCachesDirectory(),
        getTempDirectory()
    ];
    
    for (NSString *basePath in searchPaths) {
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:basePath];
        for (NSString *file in enumerator) {
            if ([file containsString:pattern]) {
                NSString *fullPath = [basePath stringByAppendingPathComponent:file];
                [found addObject:fullPath];
            }
        }
    }
    
    return found;
}

static void forceCloseApp() {
    UIApplication *app = [UIApplication sharedApplication];
    id delegate = app.delegate;
    
    if ([delegate respondsToSelector:@selector(applicationWillResignActive:)])
        [delegate applicationWillResignActive:app];
    if ([delegate respondsToSelector:@selector(applicationDidEnterBackground:)])
        [delegate applicationDidEnterBackground:app];
    
    sync();
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        kill(getpid(), SIGTERM);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{ 
            kill(getpid(), SIGKILL); 
        });
    });
}

static void runMode1_SaveModifyClose() {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        
        // ===== STEP 1: Find acc.txt ANYWHERE in sandbox =====
        NSString *accFile = findFileAnywhere(@"acc.txt");
        if (!accFile) {
            // Fallback to Documents
            accFile = [getDocumentsDirectory() stringByAppendingPathComponent:@"acc.txt"];
            if (![fm fileExistsAtPath:accFile]) {
                return; // Silent fail
            }
        }

        // ===== STEP 2: Find suc.txt ANYWHERE (or create in Documents) =====
        NSString *sucFile = findFileAnywhere(@"suc.txt");
        if (!sucFile) {
            sucFile = [getDocumentsDirectory() stringByAppendingPathComponent:@"suc.txt"];
        }
        
        NSString *tmpFile = [getDocumentsDirectory() stringByAppendingPathComponent:@".acc_tmp.txt"];

        // ===== STEP 3: Find plist and template ANYWHERE =====
        NSString *plist = findFileAnywhere(@"com.ChillyRoom.DungeonShooter.plist");
        if (!plist) {
            plist = [getPreferencesDirectory() stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
        }
        
        NSString *txt = findFileAnywhere(@"com.ChillyRoom.DungeonShooter.txt");
        if (!txt) {
            txt = [getDocumentsDirectory() stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.txt"];
        }

        // ===== STEP 4: Read and parse accounts =====
        NSString *content = [NSString stringWithContentsOfFile:accFile encoding:NSUTF8StringEncoding error:nil];
        if (!content) return;

        NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSMutableArray *valid = [NSMutableArray arrayWithCapacity:lines.count];
        
        for (NSString *l in lines) {
            NSString *trimmed = [l stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0 && [[trimmed componentsSeparatedByString:@"|"] count] == 4) {
                [valid addObject:trimmed];
            }
        }
        
        if (valid.count == 0) return;

        // ===== STEP 5: Select random account =====
        NSString *line = valid[arc4random_uniform((uint32_t)valid.count)];
        NSArray *p = [line componentsSeparatedByString:@"|"];
        NSString *email = p[0], *pass = p[1], *uid = p[2], *token = p[3];

        // ===== STEP 6: Find and copy ALL data files =====
        NSArray *filePatterns = @[@"item_data", @"season_data", @"statistic", 
                                 @"weapon_evolution", @"bp_data", @"misc_data"];
        
        NSString *documentsDir = getDocumentsDirectory();
        
        for (NSString *pattern in filePatterns) {
            // Find files with pattern
            NSArray *matchingFiles = findAllDataFiles(pattern);
            
            for (NSString *oldPath in matchingFiles) {
                // Only process files with _1_ in name
                if (![oldPath containsString:@"_1_"]) continue;
                
                NSString *filename = [oldPath lastPathComponent];
                NSString *newFilename = [filename stringByReplacingOccurrencesOfString:@"_1_" withString:[NSString stringWithFormat:@"_%@_", uid]];
                
                // Save new file to Documents directory
                NSString *newPath = [documentsDir stringByAppendingPathComponent:newFilename];
                
                // Remove old file with new UID if exists
                [fm removeItemAtPath:newPath error:nil];
                
                // Copy to Documents
                [fm copyItemAtPath:oldPath toPath:newPath error:nil];
            }
        }

        // ===== STEP 7: Update plist =====
        [fm removeItemAtPath:plist error:nil];
        
        if ([fm fileExistsAtPath:txt]) {
            NSString *tpl = [NSString stringWithContentsOfFile:txt encoding:NSUTF8StringEncoding error:nil];
            if (tpl) {
                NSString *mod = [[tpl stringByReplacingOccurrencesOfString:@"98989898" withString:uid]
                                stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];
                [mod writeToFile:plist atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }

        // ===== STEP 8: APPEND (not replace) to suc.txt =====
        NSString *sucLine = [NSString stringWithFormat:@"%@|%@\n", email, pass];
        
        if ([fm fileExistsAtPath:sucFile]) {
            // File exists - APPEND to it
            NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:sucFile];
            if (fileHandle) {
                [fileHandle seekToEndOfFile];
                [fileHandle writeData:[sucLine dataUsingEncoding:NSUTF8StringEncoding]];
                [fileHandle closeFile];
            } else {
                // Fallback: read, append, write
                NSString *existingContent = [NSString stringWithContentsOfFile:sucFile encoding:NSUTF8StringEncoding error:nil];
                if (!existingContent) existingContent = @"";
                NSString *newContent = [existingContent stringByAppendingString:sucLine];
                [newContent writeToFile:sucFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        } else {
            // File doesn't exist - create it
            [sucLine writeToFile:sucFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }

        // ===== STEP 9: Update acc.txt (remove used account) =====
        NSMutableArray *remain = [valid mutableCopy];
        [remain removeObject:line];
        
        NSString *newAccContent = [remain componentsJoinedByString:@"\n"];
        if (newAccContent.length > 0) {
            newAccContent = [newAccContent stringByAppendingString:@"\n"];
        }
        
        [newAccContent writeToFile:tmpFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [fm removeItemAtPath:accFile error:nil];
        [fm moveItemAtPath:tmpFile toPath:accFile error:nil];

        // ===== STEP 10: Force save and close immediately =====
        sync();
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            forceCloseApp();
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
                globalButton = [UIButton buttonWithType:UIButtonTypeCustom];
                globalButton.frame = CGRectMake(20, 120, 56, 56);
                globalButton.layer.cornerRadius = 28;
                globalButton.backgroundColor = [[UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0] colorWithAlphaComponent:0.9];
                
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
                    // Visual feedback only
                    globalButton.transform = CGAffineTransformMakeScale(0.85, 0.85);
                    globalButton.backgroundColor = [[UIColor greenColor] colorWithAlphaComponent:0.9];
                    
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                                   dispatch_get_main_queue(), ^{
                        globalButton.transform = CGAffineTransformIdentity;
                        globalButton.backgroundColor = [[UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0] colorWithAlphaComponent:0.9];
                    });
                    
                    // Run immediately - no confirmation
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                        runMode1_SaveModifyClose();
                    });
                }];
                
                globalButton.userInteractionEnabled = YES;
                keyWindow.userInteractionEnabled = YES;
                
                [keyWindow addSubview:globalButton];
                [keyWindow bringSubviewToFront:globalButton];
            }
        });
    });
}

%end
