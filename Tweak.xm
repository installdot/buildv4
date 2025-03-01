#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCryptor.h>
#import <sys/types.h>
#import <signal.h>

// ---------------------------
// Constants & Macros
// ---------------------------
#define AES_KEY @"tqhai2008tqhai20"   // 16 bytes key (as needed for AES-128)
#define AES_IV  @"tqhai2008tqhai20"    // 16 bytes IV
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
    NSURL *url = [NSURL URLWithString:@"https://raw.githubusercontent.com/installdot/verify/refs/heads/main/keys.txt?token=GHSAT0AAAAAAC6USNUTOJDLQNDPOW3SRTK4Z6CY5QQ"];
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

// Send UUID and key to the API for verification
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
    
    NSURLSession *session = [NSURLSession sharedSession];
    __block BOOL success = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
        if (err) {
            NSLog(@"[Tweak] API request error: %@", err.localizedDescription);
        } else {
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([responseDict[@"status"] isEqualToString:@"error"]) {
                NSLog(@"[Tweak] API verification failed: %@", responseDict[@"message"]);
            } else {
                success = YES;
            }
        }
        dispatch_semaphore_signal(semaphore);
    }] resume];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return success;
}

// ---------------------------
// UI Functions
// ---------------------------

// Prompt the user for a key; verify it and call the API.
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
            
            if (!([validKeys containsObject:enteredKey] && verifyKeyWithAPI(enteredKey))) {
                killApp();
            }
        }];
        
        [alert addAction:submitAction];
        
        // Fix for iOS 13+ (keyWindow deprecated)
        UIWindow *window = [[UIApplication sharedApplication].connectedScenes allObjects].firstObject;
        if ([window isKindOfClass:[UIWindowScene class]]) {
            UIWindow *keyWindow = [(UIWindowScene *)window keyWindow];
            UIViewController *rootVC = keyWindow.rootViewController;
            [rootVC presentViewController:alert animated:YES completion:nil];
        }
        
        // Terminate the app after 30 seconds if no correct input is received.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            killApp();
        });
    });
}

// Show menu for file operations (called on gesture)
void showFileMenu() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"File Options"
                                                                       message:@"Choose an action."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *copyAction = [UIAlertAction actionWithTitle:@"Copy to Document"
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(UIAlertAction *action) {
            NSString *destPath = [getDocumentsPath() stringByAppendingPathComponent:@"com.ChillyRoom.DungeonShooter.plist"];
            NSError *error = nil;
            if ([[NSFileManager defaultManager] copyItemAtPath:PREFS_PATH toPath:destPath error:&error]) {
                NSLog(@"[Tweak] Plist copied to Documents.");
            } else {
                NSLog(@"[Tweak] Copy failed: %@", error.localizedDescription);
            }
            killApp();
        }];
        
        UIAlertAction *replaceAction = [UIAlertAction actionWithTitle:@"Replace in Library"
                                                                style:UIAlertActionStyleDefault
                                                              handler:^(UIAlertAction *action) {
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
            killApp();
        }];
        
        UIAlertAction *closeAction = [UIAlertAction actionWithTitle:@"Close"
                                                              style:UIAlertActionStyleCancel
                                                            handler:nil];
        
        [alert addAction:copyAction];
        [alert addAction:replaceAction];
        [alert addAction:closeAction];
        
        // Fix for iOS 13+ (keyWindow deprecated)
        UIWindow *window = [[UIApplication sharedApplication].connectedScenes allObjects].firstObject;
        if ([window isKindOfClass:[UIWindowScene class]]) {
            UIWindow *keyWindow = [(UIWindowScene *)window keyWindow];
            UIViewController *rootVC = keyWindow.rootViewController;
            [rootVC presentViewController:alert animated:YES completion:nil];
        }
    });
}

// ---------------------------
// Gesture Handler Class
// ---------------------------
@interface GestureHandler : NSObject
- (void)handleGesture:(UITapGestureRecognizer *)gesture;
@end

@implementation GestureHandler
- (void)handleGesture:(UITapGestureRecognizer *)gesture {
    showFileMenu();
}
@end

// ---------------------------
// Hook UIApplication to install behavior
// ---------------------------
%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Show key prompt on app launch (only once)
        showKeyPrompt();
        
        // Add the gesture recognizer to the key window.
        UIWindow *window = [[UIApplication sharedApplication].connectedScenes allObjects].firstObject;
        if ([window isKindOfClass:[UIWindowScene class]]) {
            UIWindow *keyWindow = [(UIWindowScene *)window keyWindow];
            GestureHandler *gestureHandler = [[GestureHandler alloc] init];
            UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:gestureHandler action:@selector(handleGesture:)];
            gestureRecognizer.numberOfTapsRequired = 2;
            gestureRecognizer.numberOfTouchesRequired = 3;
            [keyWindow addGestureRecognizer:gestureRecognizer];
        }
    });
}
%end
