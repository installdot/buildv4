#import <UIKit/UIKit.h>
#import <signal.h>
#import <unistd.h>

static NSString *HOME() { return NSHomeDirectory(); }
static NSString *DOCS() { return [HOME() stringByAppendingPathComponent:@"Documents"]; }
static NSString *PREFS(){ return [HOME() stringByAppendingPathComponent:@"Library/Preferences"]; }

static void saveAndCloseApp() {
    UIApplication *app = [UIApplication sharedApplication];
    id delegate = app.delegate;

    if ([delegate respondsToSelector:@selector(applicationWillResignActive:)])
        [delegate applicationWillResignActive:app];

    if ([delegate respondsToSelector:@selector(applicationDidEnterBackground:)])
        [delegate applicationDidEnterBackground:app];

    sync();

    // Give app time to flush internal saves
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        kill(getpid(), SIGTERM);

        // absolute fallback
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            kill(getpid(), SIGKILL);
        });
    });
}

static void runMode1_SaveModifyClose() {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *accFile  = [HOME() stringByAppendingPathComponent:@"acc.txt"];
    NSString *doneFile = [HOME() stringByAppendingPathComponent:@"suc.txt"];
    NSString *tmpFile  = [HOME() stringByAppendingPathComponent:@".acc_tmp.txt"];

    NSString *plist = [PREFS() stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
    NSString *txt   = [PREFS() stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.txt"];

    if (![fm fileExistsAtPath:accFile]) return;

    NSString *content = [NSString stringWithContentsOfFile:accFile encoding:NSUTF8StringEncoding error:nil];
    NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    NSMutableArray *valid = [NSMutableArray array];
    for (NSString *l in lines)
        if ([[l componentsSeparatedByString:@"|"] count] == 4)
            [valid addObject:l];

    if (!valid.count) return;

    NSString *line = valid[arc4random_uniform((uint32_t)valid.count)];
    NSArray *p = [line componentsSeparatedByString:@"|"];

    NSString *email = p[0];
    NSString *pass  = p[1];
    NSString *uid   = p[2];
    NSString *token = p[3];

    // ===== Copy game data =====
    NSArray *files = @[
        @"item_data_1_.data",
        @"season_data_1_.data",
        @"statistic_1_.data",
        @"weapon_evolution_data_1_.data",
        @"bp_data_1_.data",
        @"misc_data_1_.data"
    ];

    for (NSString *f in files) {
        NSString *old = [DOCS() stringByAppendingPathComponent:f];
        NSString *newName = [f stringByReplacingOccurrencesOfString:@"1" withString:uid];
        NSString *new = [DOCS() stringByAppendingPathComponent:newName];

        if ([fm fileExistsAtPath:old]) {
            [fm removeItemAtPath:new error:nil];
            [fm copyItemAtPath:old toPath:new error:nil];
        }
    }

    // ===== Delete plist 5x =====
    for (int i = 0; i < 5; i++) {
        [fm removeItemAtPath:plist error:nil];
        usleep(100000);
    }

    // ===== Write plist 5x =====
    if ([fm fileExistsAtPath:txt]) {
        NSString *tpl = [NSString stringWithContentsOfFile:txt encoding:NSUTF8StringEncoding error:nil];
        NSString *mod = [[tpl stringByReplacingOccurrencesOfString:@"98989898" withString:uid]
                                stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];

        for (int i = 0; i < 5; i++) {
            [mod writeToFile:plist atomically:YES encoding:NSUTF8StringEncoding error:nil];
            usleep(100000);
        }
    }

    // ===== Save used account =====
    NSString *doneLine = [NSString stringWithFormat:@"%@|%@\n", email, pass];
    NSFileHandle *d = [NSFileHandle fileHandleForWritingAtPath:doneFile];
    if (!d)
        [doneLine writeToFile:doneFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    else {
        [d seekToEndOfFile];
        [d writeData:[doneLine dataUsingEncoding:NSUTF8StringEncoding]];
        [d closeFile];
    }

    NSMutableArray *remain = [valid mutableCopy];
    [remain removeObject:line];
    [[remain componentsJoinedByString:@"\n"]
        writeToFile:tmpFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [fm moveItemAtPath:tmpFile toPath:accFile error:nil];

    // ===== SAVE & CLOSE =====
    saveAndCloseApp();
}

%hook UIApplication
- (void)applicationDidFinishLaunching:(UIApplication *)app {
    %orig;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(20, 120, 52, 52);
    btn.layer.cornerRadius = 26;
    btn.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.85];
    [btn setTitle:@"M1" forState:UIControlStateNormal];

    [btn addTarget:nil action:@selector(runM1) forControlEvents:UIControlEventTouchUpInside];
    [[UIApplication sharedApplication].keyWindow addSubview:btn];
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
