#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>

// ── Keychain entries to wipe ──────────────────────────────────────────────────
static NSArray *keychainServices(void) {
    return @[@"SKToolsRealUDID", @"SKToolsEnrollToken", @"SKToolsAuthKey"];
}

static void deleteSKToolsKeychain(void) {
    NSString *account = @"sktools";
    NSUInteger deleted = 0;
    NSUInteger notFound = 0;

    for (NSString *service in keychainServices()) {
        NSDictionary *query = @{
            (__bridge id)kSecClass:              (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService:        service,
            (__bridge id)kSecAttrAccount:        account,
            (__bridge id)kSecAttrSynchronizable: @NO,
        };

        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);

        if (status == errSecSuccess) {
            NSLog(@"[SKCleaner] Deleted: %@", service);
            deleted++;
        } else if (status == errSecItemNotFound) {
            NSLog(@"[SKCleaner] Not found: %@", service);
            notFound++;
        } else {
            NSLog(@"[SKCleaner] Failed to delete %@ — OSStatus: %d", service, (int)status);
        }
    }

    NSLog(@"[SKCleaner] Done. Deleted: %lu, Not found: %lu", 
        (unsigned long)deleted, (unsigned long)notFound);

    // Show alert to confirm
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"SKCleaner"
                             message:[NSString stringWithFormat:
                                @"Keychain wiped.\n%lu deleted, %lu not found.",
                                (unsigned long)deleted,
                                (unsigned long)notFound]
                      preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];

        UIViewController *vc = nil;
        for (UIWindow *w in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
            if (!w.isHidden && w.alpha > 0 && w.rootViewController) {
                vc = w.rootViewController;
                break;
            }
        }
        while (vc.presentedViewController) vc = vc.presentedViewController;
        [vc presentViewController:alert animated:YES completion:nil];
    });
}

// ── Entry point — runs once on app launch ─────────────────────────────────────
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                deleteSKToolsKeychain();
            });
    });
}
%end
