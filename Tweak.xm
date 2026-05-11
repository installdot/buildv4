// Tweak.xm
#import <UIKit/UIKit.h>
#import <Security/Security.h>

static void ExportKeychainToFile() {

    NSMutableString *output = [NSMutableString string];

    NSArray *classes = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];

    for (id secClass in classes) {

        NSDictionary *query = @{
            (__bridge id)kSecClass: secClass,
            (__bridge id)kSecReturnAttributes: @YES,
            (__bridge id)kSecReturnData: @YES,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll
        };

        CFTypeRef result = NULL;

        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

        [output appendFormat:@"\n============================\n"];
        [output appendFormat:@"CLASS: %@\n", secClass];
        [output appendFormat:@"STATUS: %d\n", (int)status];
        [output appendFormat:@"============================\n"];

        if (status == errSecSuccess && result) {

            NSArray *items = (__bridge_transfer NSArray *)result;

            for (NSDictionary *item in items) {

                [output appendString:@"\n--- ITEM ---\n"];

                for (id key in item) {

                    id value = item[key];

                    if ([value isKindOfClass:[NSData class]]) {

                        NSString *str = [[NSString alloc] initWithData:value
                                                              encoding:NSUTF8StringEncoding];

                        if (str) {
                            [output appendFormat:@"%@ = %@\n", key, str];
                        } else {
                            [output appendFormat:@"%@ = <binary %lu bytes>\n",
                             key,
                             (unsigned long)[(NSData *)value length]];
                        }

                    } else {
                        [output appendFormat:@"%@ = %@\n", key, value];
                    }
                }
            }

        } else {

            [output appendString:@"No items or failed.\n"];
        }
    }

    NSString *docPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                            NSUserDomainMask,
                                                            YES).firstObject;

    NSString *filePath = [docPath stringByAppendingPathComponent:@"keychain_dump.txt"];

    NSError *err = nil;

    [output writeToFile:filePath
             atomically:YES
               encoding:NSUTF8StringEncoding
                  error:&err];

    if (!err) {
        NSLog(@"[Tweak] Exported keychain -> %@", filePath);
    } else {
        NSLog(@"[Tweak] Write error: %@", err);
    }
}

%hook UIApplication

- (void)applicationDidBecomeActive:(UIApplication *)application {

    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        ExportKeychainToFile();
    });

    %orig;
}

%end
