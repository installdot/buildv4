#import <UIKit/UIKit.h>
#import <signal.h>
#import <unistd.h>

static NSString *HOME() { return NSHomeDirectory(); }
static NSString *DOCS() { return [HOME() stringByAppendingPathComponent:@"Documents"]; }
static NSString *PREFS(){ return [HOME() stringByAppendingPathComponent:@"Library/Preferences"]; }

static UIWindow *getMainWindow() {
    UIApplication *app = [UIApplication sharedApplication];
    
    // Try delegate window first (fastest)
    if ([app.delegate respondsToSelector:@selector(window)]) {
        UIWindow *delegateWindow = [(id)app.delegate window];
        if (delegateWindow && delegateWindow.isKeyWindow) return delegateWindow;
    }
    
    // Fallback to scene-based lookup
    for (UIScene *scene in app.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *w in windowScene.windows) {
                if (w.isKeyWindow) return w;
            }
            // Return first window if no key window found
            if (windowScene.windows.count > 0) return windowScene.windows[0];
        }
    }
    
    // Last resort: deprecated keyWindow
    return app.keyWindow;
}

static void saveAndCloseApp() {
    UIApplication *app = [UIApplication sharedApplication];
    id delegate = app.delegate;

    if ([delegate respondsToSelector:@selector(applicationWillResignActive:)])
        [delegate applicationWillResignActive:app];

    if ([delegate respondsToSelector:@selector(applicationDidEnterBackground:)])
        [delegate applicationDidEnterBackground:app];

    sync();

    // Reduced delay for faster termination
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        kill(getpid(), SIGTERM);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            kill(getpid(), SIGKILL);
        });
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

        if (![fm fileExistsAtPath:accFile]) return;

        // Read and parse accounts (optimized)
        NSError *error = nil;
        NSString *content = [NSString stringWithContentsOfFile:accFile 
                                                      encoding:NSUTF8StringEncoding 
                                                         error:&error];
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

        // Select random account
        NSString *line = valid[arc4random_uniform((uint32_t)valid.count)];
        NSArray *p = [line componentsSeparatedByString:@"|"];

        NSString *email = p[0];
        NSString *pass  = p[1];
        NSString *uid   = p[2];
        NSString *token = p[3];

        // ===== Copy data files (optimized) =====
        NSArray *files = @[
            @"item_data_1_.data",
            @"season_data_1_.data",
            @"statistic_1_.data",
            @"weapon_evolution_data_1_.data",
            @"bp_data_1_.data",
            @"misc_data_1_.data"
        ];

        NSError *copyError = nil;
        for (NSString *f in files) {
            NSString *oldPath = [DOCS() stringByAppendingPathComponent:f];
            if (![fm fileExistsAtPath:oldPath]) continue;
            
            NSString *newName = [f stringByReplacingOccurrencesOfString:@"1" withString:uid];
            NSString *newPath = [DOCS() stringByAppendingPathComponent:newName];

            [fm removeItemAtPath:newPath error:nil];
            [fm copyItemAtPath:oldPath toPath:newPath error:&copyError];
        }

        // ===== Delete plist (single operation) =====
        [fm removeItemAtPath:plist error:nil];

        // ===== Write plist (optimized) =====
        if ([fm fileExistsAtPath:txt]) {
            NSString *tpl = [NSString stringWithContentsOfFile:txt 
                                                      encoding:NSUTF8StringEncoding 
                                                         error:nil];
            if (tpl) {
                NSString *mod = [[tpl stringByReplacingOccurrencesOfString:@"98989898" withString:uid]
                                        stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];

                // Single write operation
                [mod writeToFile:plist atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }

        // ===== Save used account (optimized) =====
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

        // ===== Update account list (optimized) =====
        NSMutableArray *remain = [valid mutableCopy];
        [remain removeObject:line];
        
        NSString *newContent = [remain componentsJoinedByString:@"\n"];
        [newContent writeToFile:tmpFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        [fm removeItemAtPath:accFile error:nil];
        [fm moveItemAtPath:tmpFile toPath:accFile error:nil];

        saveAndCloseApp();
    }
}

static void addButtonToWindow() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = getMainWindow();
        if (!win) {
            // Retry after a short delay if window not ready
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                           dispatch_get_main_queue(), ^{
                addButtonToWindow();
            });
            return;
        }

        // Check if button already exists
        for (UIView *subview in win.subviews) {
            if ([subview isKindOfClass:[UIButton class]] && subview.tag == 99999) {
                return; // Button already added
            }
        }

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(20, 120, 52, 52);
        btn.layer.cornerRadius = 26;
        btn.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.85];
        btn.tag = 99999; // Unique tag to identify button
        
        [btn setTitle:@"M1" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        
        // Add shadow for better visibility
        btn.layer.shadowColor = [UIColor blackColor].CGColor;
        btn.layer.shadowOffset = CGSizeMake(0, 2);
        btn.layer.shadowRadius = 4;
        btn.layer.shadowOpacity = 0.3;

        [btn addTarget:nil action:@selector(runM1) forControlEvents:UIControlEventTouchUpInside];

        [win addSubview:btn];
        [win bringSubviewToFront:btn];
    });
}

%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    
    // Add button when app becomes active (window guaranteed to be ready)
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            addButtonToWindow();
        });
    });
}
%end

%hook UIWindowScene
- (void)_performActionsForUIScene:(id)arg1 
              withUpdatedFBSScene:(id)arg2 
                  settingsDiff:(id)arg3 
                  fromSettings:(id)arg4 
            transitionContext:(id)arg5 
                  lifecycleActionType:(unsigned int)arg6 {
    %orig;
    
    // Also try adding button when scene updates
    addButtonToWindow();
}
%end

@interface UIResponder (M1)
- (void)runM1;
@end

@implementation UIResponder (M1)
- (void)runM1 {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        runMode1_SaveModifyClose();
    });
}
@end
