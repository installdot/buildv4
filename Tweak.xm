#import <UIKit/UIKit.h>
#import <unistd.h>
#import <Foundation/Foundation.h>

%hook UIViewController

- (void)viewDidLoad {
    %orig;

    // Create the Mod button
    UIButton *modButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [modButton setTitle:@"Mod" forState:UIControlStateNormal];
    modButton.frame = CGRectMake(20, 100, 100, 50); // Adjust position/size as needed
    [modButton addTarget:self action:@selector(modButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    // Style the button
    modButton.backgroundColor = [UIColor systemBlueColor];
    [modButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    modButton.layer.cornerRadius = 10;
    
    // Add button to the view
    [self.view addSubview:modButton];
}

%new
- (void)modButtonTapped {
    // Config paths
    NSString *appDir = @"/var/mobile/Containers/Data/Application/07B538A4-7A52-4A01-A5F7-C869EDB09A87";
    NSString *docsDir = [appDir stringByAppendingPathComponent:@"Documents"];
    NSString *prefDir = [appDir stringByAppendingPathComponent:@"Library/Preferences"];
    NSString *oldPlist = [prefDir stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
    NSString *txtFile = [prefDir stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.txt"];
    NSString *accFile = [appDir stringByAppendingPathComponent:@"acc.txt"];
    NSString *doneFile = [appDir stringByAppendingPathComponent:@"done.txt"];
    NSString *tmpFile = [appDir stringByAppendingPathComponent:@".acc_tmp.txt"];
    int mode = 1; // Hardcoded to Mode 1 (Full All); adjust as needed

    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];

    // Verify acc.txt exists
    if (![fileManager fileExistsAtPath:accFile]) {
        NSLog(@"[ModTweak] Error: Account file not found: %@", accFile);
        return;
    }

    // Clean null bytes from acc.txt and txtFile
    for (NSString *file in @[accFile, txtFile]) {
        if ([fileManager fileExistsAtPath:file]) {
            NSData *fileData = [NSData dataWithContentsOfFile:file];
            if ([fileData rangeOfData:[@"\0" dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(0, fileData.length)].location != NSNotFound) {
                NSLog(@"[ModTweak] Cleaning null bytes from: %@", file);
                NSString *content = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
                if (content) {
                    content = [content stringByReplacingOccurrencesOfString:@"\0" withString:@""];
                    [content writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:&error];
                    if (error) {
                        NSLog(@"[ModTweak] Error cleaning null bytes in %@: %@", file, error);
                    }
                }
            }
        }
    }

    // Pick random account from acc.txt
    NSString *accContent = [NSString stringWithContentsOfFile:accFile encoding:NSUTF8StringEncoding error:&error];
    if (!accContent) {
        NSLog(@"[ModTweak] Error reading acc.txt: %@", error);
        return;
    }
    NSArray *accLines = [accContent componentsSeparatedByString:@"\n"];
    accLines = [accLines filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF != ''"]];
    if (accLines.count == 0) {
        NSLog(@"[ModTweak] Error: acc.txt is empty");
        return;
    }
    NSString *selectedLine = accLines[arc4random_uniform((u_int32_t)accLines.count)];
    NSArray *components = [selectedLine componentsSeparatedByString:@"|"];
    if (components.count != 4) {
        NSLog(@"[ModTweak] Invalid line in acc.txt: %@", selectedLine);
        return;
    }
    NSString *email = components[0];
    NSString *pass = components[1];
    NSString *userId = components[2];
    NSString *token = components[3];

    NSLog(@"[ModTweak] Selected account: Email=%@, Pass=%@, ID=%@, Token=%@", email, pass, userId, token);

    // Copy and rename data files (skip for Mode 3)
    if (mode != 3) {
        NSArray *files;
        if (mode == 2 || mode == 4) {
            files = @[
                @"item_data_2_.data",
                @"season_data_1_.data",
                @"statistic_2_.data",
                @"weapon_evolution_data_1_.data"
            ];
        } else {
            files = @[
                @"item_data_1_.data",
                @"season_data_1_.data",
                @"statistic_1_.data",
                @"weapon_evolution_data_1_.data"
            ];
        }

        for (NSString *filename in files) {
            NSString *oldPath = [docsDir stringByAppendingPathComponent:filename];
            NSString *newFilename = [filename stringByReplacingOccurrencesOfString:@"[1-2]" withString:userId];
            NSString *newPath = [docsDir stringByAppendingPathComponent:newFilename];
            if ([fileManager fileExistsAtPath:oldPath]) {
                [fileManager copyItemAtPath:oldPath toPath:newPath error:&error];
                if (error) {
                    NSLog(@"[ModTweak] Error copying %@ to %@: %@", oldPath, newPath, error);
                } else {
                    NSLog(@"[ModTweak] Copied %@ to %@", filename, newFilename);
                }
            } else {
                NSLog(@"[ModTweak] Missing file: %@", filename);
            }
        }
    } else {
        NSLog(@"[ModTweak] Mode 3: Skipping data file operations");
    }

    // Remove old plist
    if ([fileManager fileExistsAtPath:oldPlist]) {
        [fileManager removeItemAtPath:oldPlist error:&error];
        if (error) {
            NSLog(@"[ModTweak] Error removing plist: %@", error);
        } else {
            NSLog(@"[ModTweak] Removed old plist");
        }
    } else {
        NSLog(@"[ModTweak] No plist to delete");
    }

    // Replace and write new plist from txt
    if ([fileManager fileExistsAtPath:txtFile]) {
        NSString *txtContent = [NSString stringWithContentsOfFile:txtFile encoding:NSUTF8StringEncoding error:&error];
        if (!txtContent) {
            NSLog(@"[ModTweak] Error reading txt file: %@", error);
            return;
        }
        NSString *modified;
        if (mode == 3) {
            modified = [txtContent stringByReplacingOccurrencesOfString:@"98989898" withString:userId];
            modified = [modified stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];
        } else if (mode == 4) {
            modified = [txtContent stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];
        } else {
            modified = [txtContent stringByReplacingOccurrencesOfString:@"98989898" withString:userId];
            modified = [modified stringByReplacingOccurrencesOfString:@"anhhaideptrai" withString:token];
        }
        [modified writeToFile:oldPlist atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (error) {
            NSLog(@"[ModTweak] Error writing plist: %@", error);
        } else {
            NSLog(@"[ModTweak] New plist written");
        }
    } else {
        NSLog(@"[ModTweak] Error: txt config not found at %@", txtFile);
        return;
    }

    // Append to done.txt
    NSString *doneEntry = [NSString stringWithFormat:@"%@|%@\n", email, pass];
    NSString *existingDoneContent = [NSString stringWithContentsOfFile:doneFile encoding:NSUTF8StringEncoding error:nil];
    NSString *newDoneContent = existingDoneContent ? [existingDoneContent stringByAppendingString:doneEntry] : doneEntry;
    if (![newDoneContent writeToFile:doneFile atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        NSLog(@"[ModTweak] Error appending to done.txt: %@", error);
    } else {
        NSLog(@"[ModTweak] Appended to done.txt");
    }

    // Remove used account from acc.txt using tmpFile
    accLines = [accLines filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF != %@", selectedLine]];
    NSString *newAccContent = [accLines componentsJoinedByString:@"\n"];
    if (newAccContent.length > 0) {
        newAccContent = [newAccContent stringByAppendingString:@"\n"];
    }
    if (![newAccContent writeToFile:tmpFile atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        NSLog(@"[ModTweak] Error writing to tmp file: %@", error);
        return;
    }
    if (![fileManager moveItemAtPath:tmpFile toPath:accFile error:&error]) {
        NSLog(@"[ModTweak] Error moving tmp file to acc.txt: %@", error);
    } else {
        NSLog(@"[ModTweak] Updated acc.txt");
    }

    // Launch app
    NSURL *url = [NSURL URLWithString:@"fb166745907472360://"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        NSLog(@"[ModTweak] Launched app");
    } else {
        NSLog(@"[ModTweak] Error: Cannot open URL scheme");
    }
}

%end
