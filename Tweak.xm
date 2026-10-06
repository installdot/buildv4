// Tweak.xm

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Security/Security.h>

static void DumpKeychainMetadataForClass(CFTypeRef itemClass,
                                         NSString *className,
                                         NSMutableString *output)
{
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)itemClass,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,

        // Return attributes ONLY.
        // Intentionally does NOT request kSecReturnData.
        (__bridge id)kSecReturnAttributes: @YES
    };

    CFTypeRef result = NULL;

    OSStatus status = SecItemCopyMatching(
        (__bridge CFDictionaryRef)query,
        &result
    );

    [output appendFormat:@"\n========== %@ ==========\n", className];

    if (status == errSecItemNotFound) {
        [output appendString:@"No items found.\n"];
        return;
    }

    if (status != errSecSuccess) {
        [output appendFormat:@"SecItemCopyMatching error: %d\n", (int)status];
        return;
    }

    NSArray *items = CFBridgingRelease(result);

    if (![items isKindOfClass:[NSArray class]]) {
        items = @[items];
    }

    NSInteger index = 0;

    for (NSDictionary *item in items) {
        index++;

        NSString *service = item[(__bridge id)kSecAttrService];
        NSString *account = item[(__bridge id)kSecAttrAccount];
        NSString *accessGroup = item[(__bridge id)kSecAttrAccessGroup];
        NSString *label = item[(__bridge id)kSecAttrLabel];

        [output appendFormat:@"\nItem #%ld\n", (long)index];

        if (service)
            [output appendFormat:@"Service: %@\n", service];

        if (account)
            [output appendFormat:@"Account: %@\n", account];

        if (label)
            [output appendFormat:@"Label: %@\n", label];

        if (accessGroup)
            [output appendFormat:@"Access Group: %@\n", accessGroup];
    }
}

static void ExportKeychainMetadata(void)
{
    NSMutableString *output = [NSMutableString string];

    [output appendFormat:@"Keychain Metadata Audit\n"];
    [output appendFormat:@"Bundle ID: %@\n",
        [[NSBundle mainBundle] bundleIdentifier]];

    [output appendFormat:@"Date: %@\n", [NSDate date]];

    DumpKeychainMetadataForClass(
        kSecClassGenericPassword,
        @"Generic Password",
        output
    );

    DumpKeychainMetadataForClass(
        kSecClassInternetPassword,
        @"Internet Password",
        output
    );

    DumpKeychainMetadataForClass(
        kSecClassCertificate,
        @"Certificate",
        output
    );

    DumpKeychainMetadataForClass(
        kSecClassKey,
        @"Key",
        output
    );

    DumpKeychainMetadataForClass(
        kSecClassIdentity,
        @"Identity",
        output
    );

    NSString *documents =
        NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory,
            NSUserDomainMask,
            YES
        ).firstObject;

    NSString *path =
        [documents stringByAppendingPathComponent:@"keychain_metadata.txt"];

    NSError *error = nil;

    [output writeToFile:path
             atomically:YES
               encoding:NSUTF8StringEncoding
                  error:&error];

    if (error) {
        NSLog(@"[KeychainAudit] Write error: %@", error);
    } else {
        NSLog(@"[KeychainAudit] Saved to %@", path);
    }
}

%hook UIApplication

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    BOOL result = %orig;

    dispatch_async(dispatch_get_main_queue(), ^{
        ExportKeychainMetadata();
    });

    return result;
}

%end
