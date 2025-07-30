// MainDylib.m
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h> // For iOS UI
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Define constants (from the bash script)
#define APP_DIR @"/var/mobile/Containers/Data/Application/07B538A4-7A52-4A01-A5F7-C869EDB09A87"
#define DOCS_DIR [APP_DIR stringByAppendingPathComponent:@"Documents"]
#define PREF_DIR [APP_DIR stringByAppendingPathComponent:@"Library/Preferences"]
#define OLD_PLIST [PREF_DIR stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"]
#define TXT_FILE [PREF_DIR stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.txt"]
#define ACC_FILE [APP_DIR stringByAppendingPathComponent:@"acc.txt"]
#define DONE_FILE [APP_DIR stringByAppendingPathComponent:@"done.txt"]
#define TMP_FILE [APP_DIR stringByAppendingPathComponent:@".acc_tmp.txt"]

@interface MainDylib : NSObject
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) UIButton *activeButton;
@end

@implementation MainDylib

+ (void)load {
    // Initialize the dylib when loaded
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        MainDylib *dylib = [[MainDylib alloc] init];
        [dylib setupUI];
    });
}

- (void)setupUI {
    // Create a floating window with the "Active" button
    self.overlayWindow = [[UIWindow alloc] initWithFrame:CGRectMake(50, 50, 100, 50)];
    self.overlayWindow.windowLevel = UIWindowLevelAlert + 1;
    self.overlayWindow.backgroundColor = [UIColor clearColor];
    
    self.activeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.activeButton.frame = CGRectMake(0, 0, 100, 50);
    [self.activeButton setTitle:@"Active" forState:UIControlStateNormal];
    [self.activeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.activeButton.backgroundColor = [UIColor blueColor];
    [self.activeButton addTarget:self action:@selector(activeButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    
    [self.overlayWindow addSubview:self.activeButton];
    [self.overlayWindow makeKeyAndVisible];
}

- (void)activeButtonPressed {
    // Execute the script logic (Mode 1, no app launch)
    [self runScriptLogic];
}

- (void)runScriptLogic {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    
    // Verify acc.txt exists
    if (![fileManager fileExistsAtPath:ACC_FILE]) {
        [self showAlert:@"Account file not found: acc.txt"];
        return;
    }
    
    // Clean null bytes from acc.txt and txt file
    for (NSString *file in @[ACC_FILE, TXT_FILE]) {
        if ([fileManager fileExistsAtPath:file]) {
            NSData *data = [NSData dataWithContentsOfFile:file];
            NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if ([content rangeOfString:@"\0"].location != NSNotFound) {
                content = [content stringByReplacingOccurrencesOfString:@"\0" withString:@""];
                [content writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:&error];
                if (error) {
                    [self showAlert:[NSString stringWithFormat:@"Error cleaning %@: %@", file, error.localizedDescription]];
                    return;
                }
            }
        }
    }
    
    // Read and select random line from acc.txt
    NSString *accContent = [NSString stringWithContentsOfFile:ACC_FILE encoding:NSUTF8StringEncoding error:&error];
    if (error || !accContent) {
        [self showAlert:@"Error reading acc.txt"];
        return;
    }
    
    NSArray *lines = [accContent componentsSeparatedByString:@"\n"];
    lines = [lines filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    if (lines.count == 0) {
        [self showAlert:@"No valid lines in acc.txt"];
        return;
    }
    
    NSString *selectedLine = lines[arc4random_uniform((u_int32_t)lines.count)];
    NSArray *components = [selectedLine componentsSeparatedByString:@"|"];
    if (components.count != 4) {
        [self showAlert:[NSString stringWithFormat:@"Invalid line format: %@", selectedLine]];
        return;
    }
    
    NSString *email = components[0];
    NSString *pass = components[1];
    NSString *userID = components[2];
    NSString *token = components[3];
    
    // Log selected account
    NSLog(@"[+] Selected account: Email: %@, Pass: %@, ID: %@, Token: %@", email, pass, userID, token);
    
    // Copy and rename data files (Mode 1)
    NSArray *files = @[
        @"item_data_1_.data",
        @"season_data_1_.data",
        @"statistic_1_.data",
        @"weapon_evolution_data_1_.data"
    ];
    
    for (NSString *filename in files) {
        NSString *oldPath = [DOCS_DIR stringByAppendingPathComponent:filename];
        NSString *newFilename = [filename stringByReplacingOccurrencesOfString:@"1" withString:userID];
        NSString *newPath = [DOCS_DIR stringByAppendingPathComponent:newFilename];
        
        if ([fileManager fileExistsAtPath:oldPath]) {
            [fileManager copyItemAtPath:oldPath toPath:newPath error:&error];
            if (error) {
                [self showAlert:[NSString stringWithFormat:@"Error copying %@: %@", filename, error.localizedDescription]];
                return;
            }
            NSLog(@"[+] Copied %@ to %@", filename, newFilename);
        } else {
            [self showAlert:[NSString stringWithFormat:@"Missing file: %@", filename]];
        }
    }
    
    // Remove old plist
    if ([fileManager fileExistsAtPath:OLD_PLIST]) {
        [fileManager removeItemAtPath:OLD_PLIST error:&error];
        if (error) {
            [self showAlert:[NSString stringWithFormat:@"Error removing plist: %@", error.localizedDescription]];
            return;
        }
        NSLog(@"[+] Removed old plist");
    }
    
    // Replace and write new plist
    if ([fileManager fileExistsAtPath:TXT_FILE]) {
        NSString *txtContent = [NSString stringWithContentsOfFile:TXT_FILE encoding:NSUTF8StringEncoding error:&error];
        if (error || !txtContent) {
            [self showAlert:@"Error reading txt config"];
            return;
        }
        
        NSString *modified = [txtContent stringByReplacingOccurrencesOfString:@"98989898" withString:userID];
        modified = [modified stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];
        
        [modified writeToFile:OLD_PLIST atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (error) {
            [self showAlert:[NSString stringWithFormat:@"Error writing plist: %@", error.localizedDescription]];
            return;
        }
        NSLog(@"[+] New plist written");
    } else {
        [self showAlert:@"txt config not found"];
        return;
    }
    
    // Save to done.txt and remove from acc.txt
    NSString *doneEntry = [NSString stringWithFormat:@"%@|%@\n", email, pass];
    [doneEntry writeToFile:DONE_FILE atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        [self showAlert:[NSString stringWithFormat:@"Error writing to done.txt: %@", error.localizedDescription]];
        return;
    }
    
    accContent = [accContent stringByReplacingOccurrencesOfString:[selectedLine stringByAppendingString:@"\n"] withString:@""];
    [accContent writeToFile:ACC_FILE atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        [self showAlert:[NSString stringWithFormat:@"Error updating acc.txt: %@", error.localizedDescription]];
        return;
    }
    
    [self showAlert:@"Done!"];
}

- (void)showAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Status" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    UIViewController *rootVC = keyWindow.rootViewController;
    [rootVC presentViewController:alert animated:YES completion:nil];
}

@end
