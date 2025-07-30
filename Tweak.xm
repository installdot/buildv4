#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <substrate.h>

// Define paths (same as in your bash script)
#define APP_DIR @"/var/mobile/Containers/Data/Application/07B538A4-7A52-4A01-A5F7-C869EDB09A87"
#define DOCS_DIR APP_DIR @"/Documents"
#define PREF_DIR APP_DIR @"/Library/Preferences"
#define OLD_PLIST PREF_DIR @"/com.ChillyRoom.DungeonShooter.plist"
#define TXT_FILE PREF_DIR @"/com.ChillyRoom.DungeonShooter.txt"
#define ACC_FILE APP_DIR @"/acc.txt"
#define DONE_FILE APP_DIR @"/done.txt"
#define TMP_FILE APP_DIR @"/.acc_tmp.txt"

// Floating button and menu window
static UIWindow *menuWindow = nil;
static UIButton *floatingButton = nil;

@interface TweakMenuController : UIViewController
+ (void)executeMode:(NSInteger)mode;
@end

@implementation TweakMenuController

+ (void)showMenu {
    // Create a new window for the menu
    if (!menuWindow) {
        menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake(100, 100, 250, 300)];
        menuWindow.windowLevel = UIWindowLevelAlert + 1;
        menuWindow.backgroundColor = [UIColor whiteColor];
        menuWindow.layer.cornerRadius = 10;
        menuWindow.layer.masksToBounds = YES;

        TweakMenuController *menuController = [[TweakMenuController alloc] init];
        menuWindow.rootViewController = menuController;
    }
    [menuWindow makeKeyAndVisible];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];

    // Add title label
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, 210, 30)];
    titleLabel.text = @"Select Mode";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.view addSubview:titleLabel];

    // Add buttons for each mode
    NSArray *modeTitles = @[@"Mode 1: Full All", @"Mode 2: Full All (Less Material)", @"Mode 3: Full Char/Skin/Pet", @"Mode 4: Full Material/Weapon"];
    for (int i = 0; i < 4; i++) {
        UIButton *modeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        modeButton.frame = CGRectMake(20, 60 + i * 50, 210, 40);
        [modeButton setTitle:modeTitles[i] forState:UIControlStateNormal];
        modeButton.titleLabel.font = [UIFont systemFontOfSize:16];
        modeButton.tag = i + 1; // Mode 1 to 4
        [modeButton addTarget:self action:@selector(modeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:modeButton];
    }

    // Add close button
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(20, 260, 210, 30);
    [closeButton setTitle:@"Close" forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeButton];
}

- (void)modeButtonTapped:(UIButton *)sender {
    [self closeMenu];
    [TweakMenuController executeMode:sender.tag];
}

- (void)closeMenu {
    menuWindow.hidden = YES;
    [menuWindow resignKeyWindow];
}

+ (void)executeMode:(NSInteger)mode {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;

    // Log mode
    NSLog(@"[+] Running in mode: %ld", (long)mode);

    // Verify acc.txt exists
    if (![fileManager fileExistsAtPath:ACC_FILE]) {
        NSLog(@"[!] Account file not found: %@", ACC_FILE);
        [self showAlertWithMessage:@"Account file not found!"];
        return;
    }

    // Clean null bytes from acc.txt and txt file
    for (NSString *file in @[ACC_FILE, TXT_FILE]) {
        if ([fileManager fileExistsAtPath:file]) {
            NSData *data = [NSData dataWithContentsOfFile:file];
            if ([data rangeOfData:[NSData dataWithBytes:"\0" length:1] options:0 range:NSMakeRange(0, data.length)].location != NSNotFound) {
                NSLog(@"[+] Cleaning null bytes from: %@", file);
                NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                content = [content stringByReplacingOccurrencesOfString:@"\0" withString:@""];
                [content writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:&error];
                if (error) {
                    NSLog(@"[!] Error cleaning file %@: %@", file, error);
                }
            }
        }
    }

    // Read and pick random account from acc.txt
    NSString *accContent = [NSString stringWithContentsOfFile:ACC_FILE encoding:NSUTF8StringEncoding error:&error];
    if (error || !accContent) {
        NSLog(@"[!] Failed to read acc.txt: %@", error);
        [self showAlertWithMessage:@"Failed to read account file!"];
        return;
    }

    NSArray *accLines = [accContent componentsSeparatedByString:@"\n"];
    accLines = [accLines filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id line, NSDictionary *bindings) {
        return [line length] > 0;
    }]];
    if (accLines.count == 0) {
        NSLog(@"[!] No valid lines in acc.txt");
        [self showAlertWithMessage:@"No valid accounts found!"];
        return;
    }

    NSString *selectedLine = accLines[arc4random_uniform((u_int32_t)accLines.count)];
    NSArray *accParts = [selectedLine componentsSeparatedByString:@"|"];
    if (accParts.count != 4) {
        NSLog(@"[!] Invalid line in acc.txt: %@", selectedLine);
        [self showAlertWithMessage:@"Invalid account format!"];
        return;
    }

    NSString *email = accParts[0];
    NSString *pass = accParts[1];
    NSString *userID = accParts[2];
    NSString *token = accParts[3];

    NSLog(@"[+] Selected account: Email=%@, Pass=%@, ID=%@, Token=%@", email, pass, userID, token);

    // Copy and rename data files (skip for Mode 3)
    if (mode != 3) {
        NSArray *files;
        if (mode == 2 || mode == 4) {
            files = @[@"item_data_2_.data", @"season_data_1_.data", @"statistic_2_.data", @"weapon_evolution_data_1_.data"];
        } else {
            files = @[@"item_data_1_.data", @"season_data_1_.data", @"statistic_1_.data", @"weapon_evolution_data_1_.data"];
        }

        for (NSString *filename in files) {
            NSString *oldPath = [DOCS_DIR stringByAppendingPathComponent:filename];
            NSString *newFilename = [filename stringByReplacingOccurrencesOfString:@"[1-2]" withString:userID regex:YES];
            NSString *newPath = [DOCS_DIR stringByAppendingPathComponent:newFilename];

            if ([fileManager fileExistsAtPath:oldPath]) {
                [fileManager copyItemAtPath:oldPath toPath:newPath error:&error];
                if (error) {
                    NSLog(@"[!] Failed to copy %@: %@", filename, error);
                } else {
                    NSLog(@"[+] Copied %@ to %@", filename, newFilename);
                }
            } else {
                NSLog(@"[!] Missing file: %@", filename);
            }
        }
    } else {
        NSLog(@"[+] Mode 3: Skipping data file operations");
    }

    // Remove old plist
    if ([fileManager fileExistsAtPath:OLD_PLIST]) {
        [fileManager removeItemAtPath:OLD_PLIST error:&error];
        if (error) {
            NSLog(@"[!] Failed to remove plist: %@", error);
        } else {
            NSLog(@"[+] Removed old plist");
        }
    }

    // Replace and write new plist from TXT
    if ([fileManager fileExistsAtPath:TXT_FILE]) {
        NSString *txtContent = [NSString stringWithContentsOfFile:TXT_FILE encoding:NSUTF8StringEncoding error:&error];
        if (error || !txtContent) {
            NSLog(@"[!] Failed to read txt file: %@", error);
            [self showAlertWithMessage:@"TXT config not found!"];
            return;
        }

        NSString *modified;
        if (mode == 3) {
            modified = [txtContent stringByReplacingOccurrencesOfString:@"98989898" withString:userID];
            modified = [modified stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];
        } else if (mode == 4) {
            modified = [txtContent stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];
        } else {
            modified = [txtContent stringByReplacingOccurrencesOfString:@"98989898" withString:userID];
            modified = [modified stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];
        }

        [modified writeToFile:OLD_PLIST atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (error) {
            NSLog(@"[!] Failed to write plist: %@", error);
        } else {
            NSLog(@"[+] New plist written");
        }
    } else {
        NSLog(@"[!] TXT config not found at %@", TXT_FILE);
        [self showAlertWithMessage:@"TXT config not found!"];
        return;
    }

    // Save used account to done.txt and remove from acc.txt
    NSString *doneLine = [NSString stringWithFormat:@"%@|%@\n", email, pass];
    [doneLine appendToFile:DONE_FILE error:&error];
    if (error) {
        NSLog(@"[!] Failed to write to done.txt: %@", error);
    }

    NSMutableArray *newAccLines = [accLines mutableCopy];
    [newAccLines removeObject:selectedLine];
    NSString *newAccContent = [newAccLines componentsJoinedByString:@"\n"];
    [newAccContent writeToFile:ACC_FILE atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        NSLog(@"[!] Failed to update acc.txt: %@", error);
    } else {
        NSLog(@"[+] Updated acc.txt and done.txt");
    }

    // Launch app
    NSLog(@"[✓] Done – Launching App");
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"fb166745907472360://"] options:@{} completionHandler:nil];
}

+ (void)showAlertWithMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionDefault handler:nil];
    [alert addAction:ok];
    UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
    [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

@end

// Helper category for regex replacement
@interface NSString (Regex)
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)pattern withString:(NSString *)replacement regex:(BOOL)useRegex;
@end

@implementation NSString (Regex)
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)pattern withString:(NSString *)replacement regex:(BOOL)useRegex {
    if (!useRegex) {
        return [self stringByReplacingOccurrencesOfString:pattern withString:replacement];
    }
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    return [regex stringByReplacingMatchesInString:self options:0 range:NSMakeRange(0, self.length) withTemplate:replacement];
}
@end

// Helper category for file appending
@interface NSString (FileAppend)
- (BOOL)appendToFile:(NSString *)path error:(NSError **)error;
@end

@implementation NSString (FileAppend)
- (BOOL)appendToFile:(NSString *)path error:(NSError **)error {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fileHandle) {
        // File doesn't exist, create it
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    if (fileHandle) {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[self dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
        return YES;
    }
    return NO;
}
@end

// Hook to inject the floating button
%hook UIApplication
- (BOOL)becomeFirstResponder {
    BOOL result = %orig;

    // Add floating button to the key window
    dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
        floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        floatingButton.frame = CGRectMake(20, 100, 50, 50);
        floatingButton.backgroundColor = [UIColor blueColor];
        floatingButton.layer.cornerRadius = 25;
        [floatingButton setTitle:@"T" forState:UIControlStateNormal];
        [floatingButton addTarget:[TweakMenuController class] action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];

        // Make button draggable
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [floatingButton addGestureRecognizer:pan];

        [keyWindow addSubview:floatingButton];
    });

    return result;
}

%new
- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
    CGPoint translation = [gesture translationInView:keyWindow];
    CGPoint newCenter = CGPointMake(floatingButton.center.x + translation.x, floatingButton.center.y + translation.y);
    floatingButton.center = newCenter;
    [gesture setTranslation:CGPointZero inView:keyWindow];
}
%end

%ctor {
    %init;
    NSLog(@"Tweak loaded");
}
