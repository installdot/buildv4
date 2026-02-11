#import <UIKit/UIKit.h>
#import <signal.h>
#import <unistd.h>
#import <objc/runtime.h>

static UIButton *globalButton = nil;
static NSMutableString *debugLog = nil;

// ────────────────────────────────────────────────
// Directory helpers
// ────────────────────────────────────────────────
static NSString *getDocumentsDirectory() {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

static NSString *getLibraryDirectory() {
    return NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
}

static NSString *getPreferencesDirectory() {
    return [getLibraryDirectory() stringByAppendingPathComponent:@"Preferences"];
}

static NSString *getCachesDirectory() {
    return NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
}

// ────────────────────────────────────────────────
// File search helpers
// ────────────────────────────────────────────────
static NSString *findFile(NSString *filename) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *bases = @[
        getDocumentsDirectory(),
        getLibraryDirectory(),
        getCachesDirectory(),
        NSTemporaryDirectory(),
        [getLibraryDirectory() stringByAppendingPathComponent:@"Application Support"],
        [[NSBundle mainBundle] bundlePath],
        [[NSBundle mainBundle] resourcePath]
    ];

    for (NSString *base in bases) {
        NSString *path = [base stringByAppendingPathComponent:filename];
        if ([fm fileExistsAtPath:path]) return path;

        NSDirectoryEnumerator *e = [fm enumeratorAtPath:base];
        for (NSString *sub in e) {
            if ([sub.lastPathComponent isEqualToString:filename]) {
                return [base stringByAppendingPathComponent:sub];
            }
        }
    }
    return nil;
}

static NSArray<NSString *> *findDataFiles(NSString *pattern) {
    NSMutableArray *found = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *roots = @[getDocumentsDirectory(), getLibraryDirectory(), getCachesDirectory()];

    for (NSString *root in roots) {
        NSDirectoryEnumerator *e = [fm enumeratorAtPath:root];
        for (NSString *path in e) {
            if ([path containsString:pattern]) {
                [found addObject:[root stringByAppendingPathComponent:path]];
            }
        }
    }
    return found;
}

// ────────────────────────────────────────────────
// Logging & UI
// ────────────────────────────────────────────────
static void initDebugLog() {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ debugLog = [NSMutableString string]; });
}

static void addLog(NSString *msg) {
    initDebugLog();
    NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                   dateStyle:NSDateFormatterNoStyle
                                                   timeStyle:NSDateFormatterMediumStyle];
    [debugLog appendFormat:@"[%@] %@\n", ts, msg];
}

static void showAlert(NSString *title, NSString *message, void (^completion)(void)) {
    addLog([NSString stringWithFormat:@"Alert: %@ — %@", title, message]);

    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            if (completion) completion();
        }]];

        UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;

        if (top) [top presentViewController:alert animated:YES completion:nil];
    });
}

// ────────────────────────────────────────────────
// FORCE save + close — no delays
// ────────────────────────────────────────────────
static void forceSaveAndTerminate() {
    addLog(@"Force saving → immediate terminate");

    UIApplication *app = [UIApplication sharedApplication];
    id delegate = app.delegate;

    if ([delegate respondsToSelector:@selector(applicationWillResignActive:)])
        [delegate applicationWillResignActive:app];
    if ([delegate respondsToSelector:@selector(applicationDidEnterBackground:)])
        [delegate applicationDidEnterBackground:app];
    if ([delegate respondsToSelector:@selector(applicationWillTerminate:)])
        [delegate applicationWillTerminate:app];

    sync();

    // Try cleanest exit first
    exit(0);

    // Fallback (almost never reached)
    kill(getpid(), SIGTERM);
    kill(getpid(), SIGKILL);
}

// ────────────────────────────────────────────────
// Get suc.txt path = same folder as acc.txt
// ────────────────────────────────────────────────
static NSString *getSucFilePath(NSString *accPath) {
    if (!accPath) {
        NSString *fallback = [getDocumentsDirectory() stringByAppendingPathComponent:@"suc.txt"];
        addLog(@"No acc.txt path → suc.txt in Documents");
        return fallback;
    }

    NSString *accFolder = [accPath stringByDeletingLastPathComponent];
    NSString *sucPath = [accFolder stringByAppendingPathComponent:@"suc.txt"];

    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:sucPath]) {
        addLog([NSString stringWithFormat:@"Using existing suc.txt → %@", sucPath]);
    } else {
        addLog([NSString stringWithFormat:@"Will create suc.txt in same folder as acc.txt → %@", sucPath]);
    }

    return sucPath;
}

// ────────────────────────────────────────────────
// Main logic — M1 mode
// ────────────────────────────────────────────────
static void runMode1() {
    @autoreleasepool {
        addLog(@"╔══════════════ M1 START ══════════════╗");

        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *docs = getDocumentsDirectory();

        // Files
        NSString *accPath   = findFile(@"acc.txt") ?: [docs stringByAppendingPathComponent:@"acc.txt"];
        NSString *plistPath = findFile(@"com.ChillyRoom.DungeonShooter.plist") ?:
                              [getPreferencesDirectory() stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
        NSString *tplPath   = findFile(@"com.ChillyRoom.DungeonShooter.txt") ?:
                              [docs stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.txt"];

        // Read accounts
        NSError *err = nil;
        NSString *accContent = [NSString stringWithContentsOfFile:accPath encoding:NSUTF8StringEncoding error:&err];
        if (!accContent || err) {
            showAlert(@"Error", [NSString stringWithFormat:@"Cannot read acc.txt\n%@", err.localizedDescription ?: @"Unknown error"], nil);
            return;
        }

        NSArray<NSString *> *lines = [accContent componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSMutableArray<NSString *> *valid = [NSMutableArray array];

        for (NSString *line in lines) {
            NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (t.length > 0 && [t componentsSeparatedByString:@"|"].count == 4) {
                [valid addObject:t];
            }
        }

        if (valid.count == 0) {
            showAlert(@"Error", @"No valid accounts found in acc.txt\nFormat: email|pass|uid|token", nil);
            return;
        }

        // Pick random account
        NSString *chosen = valid[arc4random_uniform((uint32_t)valid.count)];
        NSArray *parts = [chosen componentsSeparatedByString:@"|"];
        NSString *email = parts[0], *pass = parts[1], *uid = parts[2], *token = parts[3];

        addLog([NSString stringWithFormat:@"Selected → %@ (UID: %@)", email, uid]);

        // Find data files to duplicate
        NSMutableSet *sources = [NSMutableSet setWithArray:findDataFiles(@"_data_1_.data")];
        NSArray *extraPatterns = @[@"item_data", @"season_data", @"statistic", @"weapon_evolution", @"bp_data", @"misc_data"];
        for (NSString *pat in extraPatterns) {
            [sources addObjectsFromArray:findDataFiles(pat)];
        }

        // Copy → Documents with new UID
        int copied = 0;
        for (NSString *oldPath in sources) {
            NSString *name = oldPath.lastPathComponent;
            if (![name containsString:@"_1_"] && ![extraPatterns containsObject:name]) continue;

            NSString *newName = [name stringByReplacingOccurrencesOfString:@"_1_" withString:[NSString stringWithFormat:@"_%@_", uid]];
            NSString *newPath = [docs stringByAppendingPathComponent:newName];

            [fm removeItemAtPath:newPath error:nil];

            if ([fm copyItemAtPath:oldPath toPath:newPath error:&err]) {
                copied++;
                addLog([NSString stringWithFormat:@"→ %@", newName]);
            }
        }

        // Update plist from template
        if ([fm fileExistsAtPath:tplPath]) {
            NSString *tpl = [NSString stringWithContentsOfFile:tplPath encoding:NSUTF8StringEncoding error:nil];
            if (tpl) {
                NSString *updated = [[tpl stringByReplacingOccurrencesOfString:@"98989898" withString:uid]
                                     stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];

                [fm removeItemAtPath:plistPath error:nil];
                [updated writeToFile:plistPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                addLog(@"Plist updated");
            }
        }

        // suc.txt in same folder as acc.txt
        NSString *sucPath = getSucFilePath(accPath);

        // Append or create suc.txt
        NSString *entry = [NSString stringWithFormat:@"%@|%@\n", email, pass];
        if ([fm fileExistsAtPath:sucPath]) {
            NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:sucPath];
            [h seekToEndOfFile];
            [h writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
            [h closeFile];
            addLog(@"Appended to suc.txt");
        } else {
            [entry writeToFile:sucPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            addLog(@"Created suc.txt");
        }

        // Remove used line from acc.txt
        [valid removeObject:chosen];
        [[valid componentsJoinedByString:@"\n"] writeToFile:accPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

        // Show result & close immediately after alert is acknowledged
        NSString *msg = [NSString stringWithFormat:
            @"Account switched\n\n"
            @"• Email: %@\n"
            @"• UID:   %@\n"
            @"• Remaining accounts: %lu\n"
            @"• Good!\n\n"
            @"Saving & closing now...",
            email, uid, copied, (unsigned long)valid.count, [sucPath stringByDeletingLastPathComponent]];

        showAlert(@"Auto-Mod Done", msg, ^{
            forceSaveAndTerminate();
        });
    }
}

// ────────────────────────────────────────────────
// Floating button
// ────────────────────────────────────────────────
@interface UIControl (Block)
- (void)addActionForControlEvents:(UIControlEvents)ev withBlock:(void(^)(void))block;
@end

@implementation UIControl (Block)
- (void)addActionForControlEvents:(UIControlEvents)ev withBlock:(void(^)(void))block {
    objc_setAssociatedObject(self, @selector(blockAction:), [block copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self addTarget:self action:@selector(blockAction:) forControlEvents:ev];
}
- (void)blockAction:(id)sender {
    void (^b)(void) = objc_getAssociatedObject(self, _cmd);
    if (b) b();
}
@end

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    static dispatch_once_t token;
    dispatch_once(&token, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 700 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            if (globalButton) return;

            UIWindow *win = [UIApplication sharedApplication].keyWindow;
            if (!win || !win.rootViewController) {
                for (UIWindow *w in [UIApplication sharedApplication].windows) {
                    if (w.rootViewController) { win = w; break; }
                }
            }
            if (!win) return;

            globalButton = [UIButton buttonWithType:UIButtonTypeCustom];
            globalButton.frame = CGRectMake(20, 120, 56, 56);
            globalButton.layer.cornerRadius = 28;
            globalButton.backgroundColor = [UIColor colorWithRed:0.95 green:0.15 blue:0.15 alpha:0.94];
            [globalButton setTitle:@"M" forState:UIControlStateNormal];
            globalButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
            globalButton.layer.shadowColor = UIColor.blackColor.CGColor;
            globalButton.layer.shadowOffset = CGSizeMake(0, 3);
            globalButton.layer.shadowRadius = 5;
            globalButton.layer.shadowOpacity = 0.5;

            [globalButton addActionForControlEvents:UIControlEventTouchUpInside withBlock:^{
                globalButton.enabled = NO;
                globalButton.backgroundColor = UIColor.darkGrayColor;

                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    runMode1();
                });
            }];

            [win addSubview:globalButton];
            [win bringSubviewToFront:globalButton];

            addLog(@"M1 button created");

            showAlert(@"Auto-Mod Hook", [NSString stringWithFormat:
                @"Hooking...\n"
                @"Hooked App Data!\n"
                @"Loading Mod Data...\n"
                @"Done!");
        });
    });
}

%end
