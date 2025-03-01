#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

%hook UIApplication

// Add a button to the app when it runs
- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;
    
    // Create the "Enter ID" button
    UIButton *enterIDButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [enterIDButton setTitle:@"Enter ID" forState:UIControlStateNormal];
    enterIDButton.frame = CGRectMake(10, 30, 100, 40); // Adjust the position as needed
    [enterIDButton addTarget:self action:@selector(enterID:) forControlEvents:UIControlEventTouchUpInside];
    
    // Add the "Enter ID" button to the window
    [[UIApplication sharedApplication].keyWindow addSubview:enterIDButton];
    
    // Create the "Refresh" button
    UIButton *refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [refreshButton setTitle:@"Refresh" forState:UIControlStateNormal];
    refreshButton.frame = CGRectMake(120, 30, 100, 40); // Adjust the position as needed
    [refreshButton addTarget:self action:@selector(refreshApp:) forControlEvents:UIControlEventTouchUpInside];
    
    // Add the "Refresh" button to the window
    [[UIApplication sharedApplication].keyWindow addSubview:refreshButton];
}

// Method to handle the Enter ID button click
- (void)enterID:(UIButton *)sender {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Enter ID" message:nil preferredStyle:UIAlertControllerStyleAlert];
    
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Enter ID";
        textField.keyboardType = UIKeyboardTypeNumberPad;
    }];
    
    UIAlertAction *submitAction = [UIAlertAction actionWithTitle:@"Submit" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *inputID = alertController.textFields.firstObject.text;
        
        if (inputID.length > 0) {
            // Process the ID, clear data, unzip, and modify files
            [self clearDataAndUnzip:inputID];
        }
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    
    [alertController addAction:submitAction];
    [alertController addAction:cancelAction];
    
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alertController animated:YES completion:nil];
}

// Method to handle the Refresh button click (relaunch the app)
- (void)refreshApp:(UIButton *)sender {
    // You can relaunch the app or trigger any desired refresh action here.
    exit(0);  // Exits the app (acts as a "refresh")
}

// Method to clear data, unzip the file, and replace data files with the input ID
- (void)clearDataAndUnzip:(NSString *)inputID {
    // Step 1: Delete all .data files in the Documents directory
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSError *error = nil;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:documentsPath error:&error];
    
    for (NSString *file in files) {
        if ([file hasSuffix:@".data"]) {
            NSString *filePath = [documentsPath stringByAppendingPathComponent:file];
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
        }
    }
    
    // Step 2: Delete the com.ChillyRoom.DungeonShooter.plist file in Preferences
    NSString *plistPath = [@"/Library/Preferences/com.ChillyRoom.DungeonShooter.plist" stringByExpandingTildeInPath];
    [[NSFileManager defaultManager] removeItemAtPath:plistPath error:&error];
    
    // Step 3: Unzip the sample.zip file
    NSString *zipPath = [documentsPath stringByAppendingPathComponent:@"sample.zip"];
    NSString *unzipPath = [documentsPath stringByAppendingPathComponent:@"unzipped"];
    
    // Create unzip directory if it doesn't exist
    if (![[NSFileManager defaultManager] fileExistsAtPath:unzipPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:unzipPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/unzip"];
    [task setArguments:@[zipPath, @"-d", unzipPath]];
    
    // Run the unzip task
    [task launch];
    [task waitUntilExit];
    
    // Step 4: Replace the random number in the .data files
    NSArray *unzippedFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:unzipPath error:nil];
    
    for (NSString *file in unzippedFiles) {
        if ([file hasSuffix:@".data"]) {
            // Construct the new file name
            NSString *newFileName = [file stringByReplacingOccurrencesOfString:@"62827" withString:inputID];
            NSString *oldFilePath = [unzipPath stringByAppendingPathComponent:file];
            NSString *newFilePath = [unzipPath stringByAppendingPathComponent:newFileName];
            
            [[NSFileManager defaultManager] moveItemAtPath:oldFilePath toPath:newFilePath error:nil];
        }
    }
    
    // Step 5: Read the XML file, replace text, and create the plist
    NSString *xmlPath = [documentsPath stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.xml"];
    NSString *xmlContent = [NSString stringWithContentsOfFile:xmlPath encoding:NSUTF8StringEncoding error:&error];
    
    xmlContent = [xmlContent stringByReplacingOccurrencesOfString:@"123123123" withString:inputID];
    
    // Convert XML to binary plist
    NSData *xmlData = [xmlContent dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *xmlDict = [NSPropertyListSerialization propertyListWithData:xmlData options:NSPropertyListMutableContainers format:nil error:&error];
    
    NSData *binaryPlist = [NSPropertyListSerialization dataWithPropertyList:xmlDict format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    
    if (binaryPlist) {
        NSString *plistOutputPath = [documentsPath stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
        [binaryPlist writeToFile:plistOutputPath atomically:YES];
    }
}

%end
