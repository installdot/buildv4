#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <SSZipArchive/SSZipArchive.h>

@interface CustomMenu : NSObject

+ (void)addButtonsToAppAndShowInputDialog;

@end

@implementation CustomMenu

+ (void)addButtonsToAppAndShowInputDialog {
    // Create the "Enter ID" button
    UIButton *inputButton = [UIButton buttonWithType:UIButtonTypeSystem];
    inputButton.frame = CGRectMake(10, 40, 100, 40);  // Position the button at the top-left
    [inputButton setTitle:@"Enter ID" forState:UIControlStateNormal];
    
    // Add the button to the app's window
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
    [mainWindow addSubview:inputButton];
    
    // Set up the action for the "Enter ID" button
    [inputButton addTarget:self action:@selector(showInputDialogAndProcessFiles) forControlEvents:UIControlEventTouchUpInside];
    
    // Create the "Refresh" button below the "Enter ID" button
    UIButton *refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
    refreshButton.frame = CGRectMake(10, 90, 100, 40);  // Position the button below the "Enter ID" button
    [refreshButton setTitle:@"Refresh" forState:UIControlStateNormal];
    
    // Add the "Refresh" button to the app's window
    [mainWindow addSubview:refreshButton];
    
    // Set up the action for the "Refresh" button
    [refreshButton addTarget:self action:@selector(refreshApp) forControlEvents:UIControlEventTouchUpInside];
}

+ (void)showInputDialogAndProcessFiles {
    // Display an input alert to get the ID
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Input ID"
                                                                   message:@"Enter the ID"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Enter ID here";
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
        // Get the input ID
        NSString *inputID = alert.textFields.firstObject.text;
        
        if (inputID.length > 0) {
            // Delete existing .data files before unzipping
            [self deleteExistingDataFiles];
            
            // Delete com.ChillyRoom.DungeonShooter.plist file
            [self deletePlistFile];
            
            // Read, modify XML, and convert it into a binary plist file
            [self modifyXmlAndConvertToPlistWithID:inputID];
            
            // Unzip and process the files
            [self unzipAndRenameFilesWithInputID:inputID];
        }
    }];
    
    [alert addAction:cancelAction];
    [alert addAction:okAction];
    
    // Present the alert
    UIViewController *rootViewController = [[UIApplication sharedApplication].keyWindow rootViewController];
    [rootViewController presentViewController:alert animated:YES completion:nil];
}

+ (void)deleteExistingDataFiles {
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *unzippedDestination = [documentsPath stringByAppendingPathComponent:@"unzipped"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    
    // Get the list of files in the destination folder
    NSArray *unzippedFiles = [fileManager contentsOfDirectoryAtPath:unzippedDestination error:&error];
    
    if (error) {
        NSLog(@"Error reading contents of folder: %@", error.localizedDescription);
        return;
    }
    
    // Delete all .data files
    for (NSString *fileName in unzippedFiles) {
        if ([fileName hasSuffix:@".data"]) {
            NSString *filePath = [unzippedDestination stringByAppendingPathComponent:fileName];
            [fileManager removeItemAtPath:filePath error:&error];
            
            if (error) {
                NSLog(@"Error deleting file: %@", error.localizedDescription);
            } else {
                NSLog(@"Deleted file: %@", fileName);
            }
        }
    }
}

+ (void)deletePlistFile {
    // Delete the existing com.ChillyRoom.DungeonShooter.plist file
    NSString *preferencesPath = @"/Library/Preferences/com.ChillyRoom.DungeonShooter.plist";
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSError *error = nil;
    if ([fileManager fileExistsAtPath:preferencesPath]) {
        [fileManager removeItemAtPath:preferencesPath error:&error];
        
        if (error) {
            NSLog(@"Error deleting plist file: %@", error.localizedDescription);
        } else {
            NSLog(@"Deleted plist file: com.ChillyRoom.DungeonShooter.plist");
        }
    }
}

+ (void)modifyXmlAndConvertToPlistWithID:(NSString *)inputID {
    // Get the path to the XML file
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *xmlPath = [documentsPath stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.xml"];
    
    NSError *error = nil;
    
    // Read the XML file content
    NSString *xmlContent = [NSString stringWithContentsOfFile:xmlPath encoding:NSUTF8StringEncoding error:&error];
    
    if (error) {
        NSLog(@"Error reading XML file: %@", error.localizedDescription);
        return;
    }
    
    // Replace all occurrences of "123123123" with the input ID
    xmlContent = [xmlContent stringByReplacingOccurrencesOfString:@"123123123" withString:inputID];
    
    // Convert the modified XML content into a dictionary
    NSData *xmlData = [xmlContent dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *xmlDict = [NSPropertyListSerialization propertyListWithData:xmlData options:NSPropertyListMutableContainersAndLeaves format:nil error:&error];
    
    if (error) {
        NSLog(@"Error converting XML to dictionary: %@", error.localizedDescription);
        return;
    }
    
    // Convert the dictionary into a binary .plist format
    NSString *plistPath = [documentsPath stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
    [NSPropertyListSerialization writePropertyList:xmlDict toFile:plistPath format:NSPropertyListBinaryFormat_v1_0 error:&error];
    
    if (error) {
        NSLog(@"Error writing binary plist file: %@", error.localizedDescription);
    } else {
        NSLog(@"Converted XML to binary plist and saved as com.ChillyRoom.DungeonShooter.plist");
    }
}

+ (void)unzipAndRenameFilesWithInputID:(NSString *)inputID {
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *zipPath = [documentsPath stringByAppendingPathComponent:@"sample.zip"];
    
    // Step 1: Unzip the sample.zip
    NSString *unzipDestination = [documentsPath stringByAppendingPathComponent:@"unzipped"];
    [SSZipArchive unzipFileAtPath:zipPath toDestination:unzipDestination];
    
    // Step 2: Get the list of files and replace the random number in their names
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *unzippedFiles = [fileManager contentsOfDirectoryAtPath:unzipDestination error:nil];
    
    for (NSString *fileName in unzippedFiles) {
        if ([fileName hasSuffix:@".data"]) {
            // Check if the file matches the pattern something_something_something_randomNumber_.data
            NSArray *fileComponents = [fileName componentsSeparatedByString:@"_"];
            
            if (fileComponents.count >= 2) {
                // The second-to-last part should be the random number (before the last "_")
                NSString *randomNumberPart = fileComponents[fileComponents.count - 2]; // E.g., "123"
                
                if (randomNumberPart.length > 0) {
                    // Replace the random number with the input ID
                    NSMutableArray *modifiedComponents = [fileComponents mutableCopy];
                    modifiedComponents[fileComponents.count - 2] = inputID; // Replace the random number part
                    NSString *modifiedFileName = [modifiedComponents componentsJoinedByString:@"_"]; // Rebuild the file name
                    
                    // Ensure the filename ends with "_data" and not "_data_"
                    modifiedFileName = [modifiedFileName stringByAppendingString:@".data"];
                    
                    NSString *oldFilePath = [unzippedDestination stringByAppendingPathComponent:fileName];
                    NSString *newFilePath = [unzippedDestination stringByAppendingPathComponent:modifiedFileName];
                    
                    // Rename the file
                    [fileManager moveItemAtPath:oldFilePath toPath:newFilePath error:nil];
                }
            }
        }
    }
    
    NSLog(@"File names modified and moved successfully.");
}

+ (void)refreshApp {
    // Method to restart the app by simulating a crash and re-launch
    NSLog(@"App is refreshing...");

    // Forcing the app to terminate (this is one way to simulate a "restart")
    abort();  // This will crash the app and the system will automatically relaunch it

    // Alternatively, for a graceful restart, you would need to restart the app from the home screen, 
    // as iOS doesn’t allow apps to programmatically restart themselves. `abort()` is one way to force a crash.
}

@end
