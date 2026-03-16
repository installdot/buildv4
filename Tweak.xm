// KeychainDumpTweak.xm

#import <UIKit/UIKit.h>
#import <Security/Security.h>

static NSString *describeValue(id value) {
    if (!value) return @"(null)";
    
    if ([value isKindOfClass:[NSData class]]) {
        NSData *data = (NSData *)value;
        
        NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (str) return str;
        
        NSMutableString *hex = [NSMutableString string];
        const unsigned char *bytes = data.bytes;
        for (NSUInteger i=0;i<data.length;i++) {
            [hex appendFormat:@"%02X",bytes[i]];
        }
        return hex;
    }
    
    return [NSString stringWithFormat:@"%@",value];
}

static void dumpKeychain() {

    NSMutableString *dump = [NSMutableString string];

    NSArray *classes = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];

    NSArray *names = @[
        @"GenericPassword",
        @"InternetPassword",
        @"Certificate",
        @"Key",
        @"Identity"
    ];

    [dump appendString:@"=== KEYCHAIN DUMP START ===\n"];

    for (int i=0;i<classes.count;i++) {

        NSDictionary *query = @{
            (__bridge id)kSecClass:classes[i],
            (__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitAll,
            (__bridge id)kSecReturnAttributes:@YES,
            (__bridge id)kSecReturnData:@YES
        };

        CFTypeRef result = NULL;

        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query,&result);

        if (status == errSecSuccess && result) {

            NSArray *items = (__bridge_transfer NSArray*)result;

            for (NSDictionary *item in items) {

                [dump appendFormat:@"\n----- %@ -----\n",names[i]];

                for (id key in item) {

                    NSString *value = describeValue(item[key]);

                    [dump appendFormat:@"%@ : %@\n",key,value];
                }

                [dump appendString:@"----------------------\n"];
            }
        }
    }

    [dump appendString:@"\n=== KEYCHAIN DUMP END ===\n"];

    // Save to Documents folder

    NSString *docPath = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory,
        NSUserDomainMask,
        YES
    )[0];

    NSString *file = [docPath stringByAppendingPathComponent:@"keychain_dump.txt"];

    [dump writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSLog(@"[KeychainDump] Saved to %@",file);
}

@interface KeychainDumpButton : NSObject
@end

@implementation KeychainDumpButton

+(void)dumpPressed {

    dumpKeychain();

    UIAlertController *alert =
    [UIAlertController alertControllerWithTitle:@"Keychain"
                                        message:@"Dump saved to Documents"
                                 preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *ok =
    [UIAlertAction actionWithTitle:@"OK"
                             style:UIAlertActionStyleDefault
                           handler:nil];

    [alert addAction:ok];

    UIWindow *key = [UIApplication sharedApplication].keyWindow;
    [key.rootViewController presentViewController:alert animated:YES completion:nil];
}

@end


%hook UIApplication

-(void)applicationDidFinishLaunching:(id)application {

    %orig;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),
                   dispatch_get_main_queue(),^{

        UIWindow *window = [UIApplication sharedApplication].keyWindow;

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];

        btn.frame = CGRectMake(20,120,120,40);
        btn.backgroundColor = [UIColor redColor];

        [btn setTitle:@"Dump Keychain" forState:UIControlStateNormal];

        [btn addTarget:[KeychainDumpButton class]
                action:@selector(dumpPressed)
      forControlEvents:UIControlEventTouchUpInside];

        [window addSubview:btn];
    });
}

%end
