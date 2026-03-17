#import <UIKit/UIKit.h>
#import <Security/Security.h>

static NSString *service = @"com.tnnguy.auth";
static NSString *account = @"device_udid";

void deleteKeychainItem() {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: service,
        (__bridge id)kSecAttrAccount: account
    };

    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    NSLog(@"[TWEAK] Delete status: %d", (int)status);
}

void setUDID(NSString *udid) {
    NSData *data = [udid dataUsingEncoding:NSUTF8StringEncoding];

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: service,
        (__bridge id)kSecAttrAccount: account
    };

    // delete old first
    SecItemDelete((__bridge CFDictionaryRef)query);

    NSDictionary *add = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: service,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecValueData: data,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlocked
    };

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    NSLog(@"[TWEAK] Set UDID status: %d", (int)status);
}

void showMenu() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        UIViewController *root = window.rootViewController;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Keychain Tool"
                                                                       message:@"Choose action"
                                                                preferredStyle:UIAlertControllerStyleAlert];

        // Button 1: Clear
        [alert addAction:[UIAlertAction actionWithTitle:@"Clear UDID"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction * _Nonnull action) {
            deleteKeychainItem();
        }]];

        // Button 2: Set
        [alert addAction:[UIAlertAction actionWithTitle:@"Set UDID"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {

            UIAlertController *input = [UIAlertController alertControllerWithTitle:@"Set UDID"
                                                                           message:@"Enter new UDID"
                                                                    preferredStyle:UIAlertControllerStyleAlert];

            [input addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
                textField.placeholder = @"00008020-XXXXXXXXXXXX";
            }];

            [input addAction:[UIAlertAction actionWithTitle:@"Save"
                                                     style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction * _Nonnull action) {
                NSString *udid = input.textFields.firstObject.text;
                if (udid.length > 0) {
                    setUDID(udid);
                }
            }]];

            [input addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                     style:UIAlertActionStyleCancel
                                                   handler:nil]];

            [root presentViewController:input animated:YES completion:nil];
        }]];

        // Cancel
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];

        [root presentViewController:alert animated:YES completion:nil];
    });
}

%hook UIApplication

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;

    // Show once (you can add condition if needed)
    showMenu();
}

%end
