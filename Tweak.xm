#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCryptor.h>
#import <sys/types.h>
#import <signal.h>

// ---------------------------
// Constants & Macros
// ---------------------------
#define AES_KEY @"tqhai2008tqhai20"   // 16 bytes key (AES-128)
#define AES_IV  @"tqhai2008tqhai20"   // 16 bytes IV
#define PREFS_PATH @"/Library/Preferences/com.ChillyRoom.DungeonShooter.plist"
#define API_URL @"https://verify-ymx6.onrender.com/verify"  // <-- Replace with your API URL

// ---------------------------
// Utility Functions
// ---------------------------

// Terminate the app
void killApp() {
    pid_t pid = getpid();
    kill(pid, SIGKILL);
}

// Get the app’s Documents directory
NSString *getDocumentsPath() {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.firstObject;
}

// AES Decryption (AES-128-CBC with PKCS7 Padding)
NSData *aesDecrypt(NSData *cipherData, NSString *key, NSString *iv) {
    char keyPtr[kCCKeySizeAES128+1] = {0};
    char ivPtr[kCCBlockSizeAES128+1] = {0};
    
    [key getCString:keyPtr maxLength:sizeof(keyPtr) encoding:NSUTF8StringEncoding];
    [iv getCString:ivPtr maxLength:sizeof(ivPtr) encoding:NSUTF8StringEncoding];
    
    size_t decryptedSize = cipherData.length + kCCBlockSizeAES128;
    void *decryptedBuffer = malloc(decryptedSize);
    size_t numBytesDecrypted = 0;
    
    CCCryptorStatus status = CCCrypt(kCCDecrypt,
                                     kCCAlgorithmAES128,
                                     kCCOptionPKCS7Padding,
                                     keyPtr,
                                     kCCKeySizeAES128,
                                     ivPtr,
                                     cipherData.bytes,
                                     cipherData.length,
                                     decryptedBuffer,
                                     decryptedSize,
                                     &numBytesDecrypted);
    
    if (status == kCCSuccess) {
        return [NSData dataWithBytesNoCopy:decryptedBuffer length:numBytesDecrypted];
    }
    
    free(decryptedBuffer);
    return nil;
}

// Fetch and decrypt keys from remote URL
NSArray *fetchDecryptedKeys() {
    NSURL *url = [NSURL URLWithString:@"https://raw.githubusercontent.com/installdot/verify/refs/heads/main/keys.txt"];
    NSError *error = nil;
    
    // Fetch the encrypted key list as a string (each line is a Base64 string)
    NSString *encryptedDataString = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        NSLog(@"[Tweak] Error fetching keys: %@", error.localizedDescription);
        return nil;
    }
    
    NSArray *encryptedKeys = [encryptedDataString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray *decryptedKeys = [NSMutableArray array];
    
    for (NSString *encryptedKey in encryptedKeys) {
        if (encryptedKey.length == 0)
            continue;
        NSData *encryptedData = [[NSData alloc] initWithBase64EncodedString:encryptedKey options:0];
        NSData *decryptedData = aesDecrypt(encryptedData, AES_KEY, AES_IV);
        if (decryptedData) {
            NSString *decryptedKey = [[NSString alloc] initWithData:decryptedData encoding:NSUTF8StringEncoding];
            if (decryptedKey) {
                [decryptedKeys addObject:decryptedKey];
            }
        }
    }
    return decryptedKeys;
}

// Get device UUID
NSString *getDeviceUUID() {
    return [[[UIDevice currentDevice] identifierForVendor] UUIDString];
}

// Send UUID and key to the API for verification using NSURLSession
BOOL verifyKeyWithAPI(NSString *key) {
    NSString *uuid = getDeviceUUID();
    NSDictionary *jsonDict = @{@"uuid": uuid, @"key": key};
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:&error];
    if (!jsonData) {
        NSLog(@"[Tweak] JSON serialization error: %@", error.localizedDescription);
        return NO;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:API_URL]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:jsonData];
    
    __block BOOL isVerified = NO;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    NSURLSessionDataTask *dataTask = [[NSURLSession sharedSession]
       dataTaskWithRequest:request
         completionHandler:^(NSData * _Nullable responseData, NSURLResponse * _Nullable response, NSError * _Nullable err) {
        if (err) {
            NSLog(@"[Tweak] API request error: %@", err.localizedDescription);
            isVerified = NO;
        } else {
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
            if ([responseDict[@"status"] isEqualToString:@"error"]) {
                NSLog(@"[Tweak] API verification failed: %@", responseDict[@"message"]);
                isVerified = NO;
            } else {
                isVerified = YES;
            }
        }
        dispatch_semaphore_signal(sema);
    }];
    
    [dataTask resume];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return isVerified;
}

// ---------------------------
// UI Functions
// ---------------------------

// Helper function to get the key window from connected scenes (iOS 13+)
UIWindow *getKeyWindow() {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            keyWindow = windowScene.keyWindow;
            if (keyWindow) {
                break;
            }
        }
    }
    return keyWindow;
}

// Create a button for file operation options (copy and replace)
UIButton *copyButton;
UIButton *replaceButton;

void showFileOperationOptions() {
    if (copyButton && replaceButton) {
        return; // Buttons already exist
    }

    // Copy to Document button
    copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    copyButton.frame = CGRectMake(100, 200, 200, 50);  // Position this button on screen
    [copyButton setTitle:@"Copy to Document" forState:UIControlStateNormal];
    [copyButton addTarget:nil action:@selector(copyToDocuments) forControlEvents:UIControlEventTouchUpInside];

    // Replace in Library button
    replaceButton = [UIButton buttonWithType:UIButtonTypeSystem];
    replaceButton.frame = CGRectMake(100, 260, 200, 50);  // Position this button on screen
    [replaceButton setTitle:@"Replace in Library" forState:UIControlStateNormal];
    [replaceButton addTarget:nil action:@selector(replaceInLibrary) forControlEvents:UIControlEventTouchUpInside];

    UIWindow *keyWindow = getKeyWindow();
    if (keyWindow) {
        UIViewController *rootVC = keyWindow.rootViewController;
        [rootVC.view addSubview:copyButton];
        [rootVC.view addSubview:replaceButton];
    }
}

// Copy to Documents
void copyToDocuments() {
    NSString *destPath = [getDocumentsPath() stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
    NSError *error = nil;
    if ([[NSFileManager defaultManager] copyItemAtPath:PREFS_PATH toPath:destPath error:&error]) {
        NSLog(@"[Tweak] Plist copied to Documents.");
    } else {
        NSLog(@"[Tweak] Copy failed: %@", error.localizedDescription);
    }
    showCountdownAndClose();  // Show countdown before closing app
}

// Replace in Library
void replaceInLibrary() {
    NSString *srcPath = [getDocumentsPath() stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
    NSError *error = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:srcPath]) {
        // Remove the original file, then copy from Documents
        if ([[NSFileManager defaultManager] removeItemAtPath:PREFS_PATH error:nil] &&
            [[NSFileManager defaultManager] copyItemAtPath:srcPath toPath:PREFS_PATH error:&error]) {
            NSLog(@"[Tweak] Plist replaced in Library.");
        } else {
            NSLog(@"[Tweak] Replace failed: %@", error.localizedDescription);
        }
    } else {
        NSLog(@"[Tweak] No plist found in Documents.");
    }
    showCountdownAndClose();  // Show countdown before closing app
}

// Show countdown alert before closing app
void showCountdownAndClose() {
    __block int countdown = 5;  // 5 seconds countdown
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Closing App"
                                                                   message:@"App will close in 5 seconds."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    UIWindow *keyWindow = getKeyWindow();
    if (keyWindow) {
        UIViewController *rootVC = keyWindow.rootViewController;
        
        // Timer to update the message with countdown
        dispatch_async(dispatch_get_main_queue(), ^{
            [rootVC presentViewController:alert animated:YES completion:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                countdown--;
                alert.message = [NSString stringWithFormat:@"App will close in %d seconds.", countdown];
                if (countdown > 0) {
                    showCountdownAndClose();  // Recursively update the alert
                } else {
                    killApp();  // Close the app when countdown reaches 0
                }
            });
        });
    }
}

// Show key input prompt to verify key
void showKeyPrompt() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Enter Key"
                                                                       message:@"Please enter the correct key to continue."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"Enter Key";
            textField.secureTextEntry = YES;
        }];
        
        UIAlertAction *submitAction = [UIAlertAction actionWithTitle:@"Submit"
                                                               style:UIAlertActionStyleDefault
                                                             handler:^(UIAlertAction *action) {
            UITextField *textField = alert.textFields.firstObject;
            NSString *enteredKey = textField.text;
            NSArray *validKeys = fetchDecryptedKeys();
            
            if ([validKeys containsObject:enteredKey] && verifyKeyWithAPI(enteredKey)) {
                showFileOperationOptions();  // Show the file operation options after correct key input
            } else {
                killApp();  // Terminate app if the key is incorrect
            }
        }];
        
        [alert addAction:submitAction];
        
        UIWindow *keyWindow = getKeyWindow();
        if (keyWindow) {
            UIViewController *rootVC = keyWindow.rootViewController;
            [rootVC presentViewController:alert animated:YES completion:nil];
        }
        
        // Terminate the app after 30 seconds if no correct input is received
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            killApp();
        });
    });
}

// ---------------------------
// Main Entry
// ---------------------------
__attribute__((constructor))
void entry() {
    // Show the key input prompt on launch
    showKeyPrompt();
}
