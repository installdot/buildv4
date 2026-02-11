#import <UIKit/UIKit.h>
#import <signal.h>
#import <unistd.h>

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

        if (![fm fileExistsAtPath:accFile]) return;

        NSString *content = [NSString stringWithContentsOfFile:accFile encoding:NSUTF8StringEncoding error:nil];
        if (!content) return;

        NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSMutableArray *valid = [NSMutableArray arrayWithCapacity:lines.count];
        for (NSString *l in lines) {
            NSString *trimmed = [l stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0 && [[trimmed componentsSeparatedByString:@"|"] count] == 4)
                [valid addObject:trimmed];
        }
        if (valid.count == 0) return;

        NSString *line = valid[arc4random_uniform((uint32_t)valid.count)];
        NSArray *p = [line componentsSeparatedByString:@"|"];
        NSString *email = p[0], *pass = p[1], *uid = p[2], *token = p[3];

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

        saveAndCloseApp();
    }
}

// METHOD 1: Hook UIViewController viewDidAppear
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            if (globalButton) return;
            
            UIWindow *keyWindow = self.view.window;
            if (!keyWindow) {
                for (UIWindow *window in [UIApplication sharedApplication].windows) {
                    if (window.isKeyWindow || window.windowLevel == UIWindowLevelNormal) {
                        keyWindow = window;
                        break;
                    }
                }
            }
            
            if (keyWindow) {
                globalButton = [UIButton buttonWithType:UIButtonTypeCustom];
                globalButton.frame = CGRectMake(20, 120, 52, 52);
                globalButton.layer.cornerRadius = 26;
                globalButton.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.85];
                globalButton.tag = 99999;
                
                [globalButton setTitle:@"M1" forState:UIControlStateNormal];
                globalButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
                
                globalButton.layer.shadowColor = [UIColor blackColor].CGColor;
                globalButton.layer.shadowOffset = CGSizeMake(0, 2);
                globalButton.layer.shadowRadius = 4;
                globalButton.layer.shadowOpacity = 0.3;
                
                [globalButton addTarget:nil action:@selector(runM1) forControlEvents:UIControlEventTouchUpInside];
                
                [keyWindow addSubview:globalButton];
                [keyWindow bringSubviewToFront:globalButton];
            }
        });
    });
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
