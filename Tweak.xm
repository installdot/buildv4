#import <UIKit/UIKit.h>
#import <signal.h>
#import <unistd.h>
#import <objc/runtime.h>

static UIButton *globalButton = nil;
static NSMutableString *debugLog = nil;

// ────────────────────────────────────────────────
// Directory helpers (unchanged)
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
// File search helpers (unchanged)
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

    exit(0);           // cleanest

    // fallback (rarely reached)
    kill(getpid(), SIGTERM);
    kill(getpid(), SIGKILL);
}

// ────────────────────────────────────────────────
// suc.txt path = same folder as acc.txt + fallback
// ────────────────────────────────────────────────
static NSString *getSucFilePath(NSString *accPath) {
    NSString *targetFolder = getDocumentsDirectory(); // default fallback

    if (accPath) {
        targetFolder = [accPath stringByDeletingLastPathComponent];
    }

    NSString *sucPath = [targetFolder stringByAppendingPathComponent:@"suc.txt"];
    addLog([NSString stringWithFormat:@"Target suc.txt location: %@", sucPath]);

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

        NSString *accPath   = findFile(@"acc.txt") ?: [docs stringByAppendingPathComponent:@"acc.txt"];
        NSString *plistPath = findFile(@"com.ChillyRoom.DungeonShooter.plist") ?:
                              [getPreferencesDirectory() stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
        NSString *tplPath   = findFile(@"com.ChillyRoom.DungeonShooter.txt") ?:
                              [docs stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.txt"];

        // Read accounts
        NSError *err = nil;
        NSString *accContent = [NSString stringWithContentsOfFile:accPath encoding:NSUTF8StringEncoding error:&err];
        if (!accContent || err) {
            showAlert(@"Error", [NSString stringWithFormat:@"Cannot read acc.txt\n%@", err.localizedDescription ?: @"Unknown"], nil);
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
            showAlert(@"Error", @"No valid accounts in acc.txt (email|pass|uid|token)", nil);
            return;
        }

        // Pick random
        NSString *chosen = valid[arc4random_uniform((uint32_t)valid.count)];
        NSArray *parts = [chosen componentsSeparatedByString:@"|"];
        NSString *email = parts[0], *pass = parts[1], *uid = parts[2], *token = parts[3];

        addLog([NSString stringWithFormat:@"Using: %@ (UID: %@)", email, uid]);

        // Copy data files to Documents
        NSMutableSet *sources = [NSMutableSet setWithArray:findDataFiles(@"_data_1_.data")];
        NSArray *extra = @[@"item_data", @"season_data", @"statistic", @"weapon_evolution", @"bp_data", @"misc_data"];
        for (NSString *pat in extra) [sources addObjectsFromArray:findDataFiles(pat)];

        int copied = 0;
        for (NSString *oldPath in sources) {
            NSString *name = oldPath.lastPathComponent;
            if (![name containsString:@"_1_"] && ![extra containsObject:name]) continue;

            NSString *newName = [name stringByReplacingOccurrencesOfString:@"_1_" withString:[NSString stringWithFormat:@"_%@_", uid]];
            NSString *newPath = [docs stringByAppendingPathComponent:newName];

            [fm removeItemAtPath:newPath error:nil];

            if ([fm copyItemAtPath:oldPath toPath:newPath error:&err]) {
                copied++;
                addLog([NSString stringWithFormat:@"Copied → %@", newName]);
            } else if (err) {
                addLog([NSString stringWithFormat:@"Copy failed: %@ → %@", name, err.localizedDescription]);
            }
        }

        // Update plist
        if ([fm fileExistsAtPath:tplPath]) {
            NSString *tpl = [NSString stringWithContentsOfFile:tplPath encoding:NSUTF8StringEncoding error:nil];
            if (tpl) {
                NSString *updated = [[tpl stringByReplacingOccurrencesOfString:@"98989898" withString:uid]
                                     stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];
                [fm removeItemAtPath:plistPath error:nil];
                if ([updated writeToFile:plistPath atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
                    addLog(@"Plist updated");
                } else {
                    addLog([NSString stringWithFormat:@"Plist write failed: %@", err.localizedDescription]);
                }
            }
        }

        // ─── Save to suc.txt ───────────────────────────────────────
        NSString *sucPath = getSucFilePath(accPath);
        NSString *entry = [NSString stringWithFormat:@"%@|%@\n", email, pass];
        BOOL writeSuccess = NO;

        if ([fm fileExistsAtPath:sucPath]) {
            NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:sucPath];
            if (h) {
                [h seekToEndOfFile];
                NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];
                @try {
                    [h writeData:data];
                    writeSuccess = YES;
                    addLog(@"Appended to suc.txt");
                } @catch (NSException *e) {
                    addLog([NSString stringWithFormat:@"Append exception: %@", e.reason]);
                }
                [h closeFile];
            } else {
                addLog(@"Cannot open suc.txt for append");
            }
        } else {
            if ([entry writeToFile:sucPath atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
                writeSuccess = YES;
                addLog(@"Created suc.txt");
            } else {
                addLog([NSString stringWithFormat:@"Create suc.txt failed: %@", err.localizedDescription]);
            }
        }

        // Fallback write if failed
        if (!writeSuccess) {
            NSString *fallbackPath = [docs stringByAppendingPathComponent:@"suc.txt"];
            if ([entry writeToFile:fallbackPath atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
                addLog([NSString stringWithFormat:@"Fallback save to Documents/suc.txt"]);
                sucPath = fallbackPath;
            } else {
                addLog([NSString stringWithFormat:@"Even fallback save failed: %@", err.localizedDescription]);
            }
        }

        // Remove used account
        [valid removeObject:chosen];
        [[valid componentsJoinedByString:@"\n"] writeToFile:accPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

        // Final message
        NSString *msg = [NSString stringWithFormat:
            @"Done!\n\n"
            @"Email: %@\n"
            @"UID:   %@\n"
            @"Files copied: %d\n"
            @"Remaining: %lu\n\n"
            @"Saving & closing...",
            email, uid, copied, (unsigned long)valid.count];

        showAlert(@"Auto-Mod Done", msg, ^{
            forceSaveAndTerminate();
        });
    }
}

// Floating button (your last version)
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

            addLog(@"M button created");

            showAlert(@"Auto-Mod Hook", @"Hooking...\nHooked App Data!\nLoading Mod Data...\nDone!", nil);
        });
    });
}

%end
