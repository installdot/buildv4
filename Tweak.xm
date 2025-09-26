#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCryptor.h>

static NSString * const kServerURL = @"https://chillysilly.frfrnocap.men/tverify.php"; // replace if needed
static NSString * const kAESKeyHex = @"0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567";
static NSString * const kAESIvHex  = @"0123456789ABCDEF0123456789ABCDEF";

@interface UIWindow (Overlay)
@end

@implementation UIWindow (Overlay)

- (void)layoutSubviews {
    [super layoutSubviews];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIButton *prefsButton = [UIButton buttonWithType:UIButtonTypeSystem];
        prefsButton.frame = CGRectMake(50, 100, 120, 40);
        [prefsButton setTitle:@"Menu" forState:UIControlStateNormal];
        prefsButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        [prefsButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        prefsButton.layer.cornerRadius = 8.0;
        prefsButton.clipsToBounds = YES;
        [prefsButton addTarget:self action:@selector(showMainMenu) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:prefsButton];
    });
}

#pragma mark - Main Menu

- (void)showMainMenu {
    // Use the existing verifyWithServerThen you provided
    [self verifyWithServerThen:^(BOOL allowed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!allowed) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Access Denied"
                                                                               message:@"Server rejected request."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    exit(0);
                }]];
                UIViewController *root = self.rootViewController;
                if (root) [root presentViewController:alert animated:YES completion:nil];
                return;
            }

            UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Options"
                                                                          message:nil
                                                                   preferredStyle:UIAlertControllerStyleActionSheet];

            [menu addAction:[UIAlertAction actionWithTitle:@"Search" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
                [self promptSearchKey];
            }]];
            [menu addAction:[UIAlertAction actionWithTitle:@"Unlock Char" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
                // keys like xxxxx_cx_unlock (use regex to match _c<number>_unlock)
                [self massEditWithPattern:@"_c[0-9]+_unlock" newValue:@"true"];
            }]];
            [menu addAction:[UIAlertAction actionWithTitle:@"Unlock Skin" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
                // keys like xxxxx_cx_skinxx
                [self massEditWithPattern:@"_c[0-9]+_skin[0-9]+" newValue:@"1"];
            }]];
            [menu addAction:[UIAlertAction actionWithTitle:@"Unlock Skill" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
                // keys like xxxxx_c_xxxxxx_skill_x_unlock (use a permissive pattern)
                [self massEditWithPattern:@"c.*_skill.*_unlock" newValue:@"1"];
            }]];
            [menu addAction:[UIAlertAction actionWithTitle:@"Unlock Pet" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
                // keys like xxxxx_p12_unlock
                [self massEditWithPattern:@"_p[0-9]+_unlock" newValue:@"true"];
            }]];
            [menu addAction:[UIAlertAction actionWithTitle:@"Gems" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
                [self promptSetGems];
            }]];
            [menu addAction:[UIAlertAction actionWithTitle:@"Reborn" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
                // keys like xxxxx_reborn_card
                [self massEditWithPattern:@"_reborn_card" newValue:@"1"];
            }]];
            [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

            UIViewController *root = self.rootViewController;
            if (root) [root presentViewController:menu animated:YES completion:nil];
        });
    }];
}

#pragma mark - Search Flow (unchanged behavior)

- (void)promptSearchKey {
    UIAlertController *searchAlert = [UIAlertController alertControllerWithTitle:@"Search Key"
                                                                         message:@"Enter part of a key name"
                                                                  preferredStyle:UIAlertControllerStyleAlert];
    [searchAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"example_key";
    }];

    [searchAlert addAction:[UIAlertAction actionWithTitle:@"Search"
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction * _Nonnull act) {
        NSString *query = searchAlert.textFields.firstObject.text;
        if (query.length > 0) {
            [self showMatchingKeys:query];
        }
    }]];

    [searchAlert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                    style:UIAlertActionStyleCancel
                                                  handler:nil]];

    UIViewController *rootVC = self.rootViewController;
    if (rootVC) [rootVC presentViewController:searchAlert animated:YES completion:nil];
}

- (void)showMatchingKeys:(NSString *)query {
    NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSMutableArray *matches = [NSMutableArray array];
    for (NSString *key in defaults.allKeys) {
        if ([[key lowercaseString] containsString:[query lowercaseString]]) {
            [matches addObject:key];
        }
    }

    if (matches.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Matches"
                                                                       message:@"No keys found."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *rootVC = self.rootViewController;
        if (rootVC) [rootVC presentViewController:alert animated:YES completion:nil];
        return;
    }

    // If many matches, use ActionSheet for scrolling; UIAlertControllerActionSheet will present scrollable list
    UIAlertController *list = [UIAlertController alertControllerWithTitle:@"Select Key"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSString *key in matches) {
        [list addAction:[UIAlertAction actionWithTitle:key style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            id val = defaults[key];
            [self promptEditKey:key currentValue:val];
        }]];
    }

    [list addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *rootVC = self.rootViewController;
    if (rootVC) [rootVC presentViewController:list animated:YES completion:nil];
}

- (void)promptEditKey:(NSString *)key currentValue:(id)value {
    NSString *valStr = value ? [value description] : @"(nil)";
    UIAlertController *edit = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Edit %@", key]
                                                                  message:[NSString stringWithFormat:@"Current value: %@", valStr]
                                                           preferredStyle:UIAlertControllerStyleAlert];

    [edit addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = valStr;
    }];

    [edit addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
        NSString *newVal = edit.textFields.firstObject.text;
        if (newVal) {
            [[NSUserDefaults standardUserDefaults] setObject:newVal forKey:key];
            [[NSUserDefaults standardUserDefaults] synchronize];
        } else {
            // if empty, remove key
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }]];

    [edit addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *rootVC = self.rootViewController;
    if (rootVC) [rootVC presentViewController:edit animated:YES completion:nil];
}

#pragma mark - Gems Setter

- (void)promptSetGems {
    UIAlertController *input = [UIAlertController alertControllerWithTitle:@"Set Gems"
                                                                   message:@"Enter new gems value"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [input addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"12345";
        tf.keyboardType = UIKeyboardTypeNumberPad;
    }];

    [input addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
        NSString *val = input.textFields.firstObject.text;
        if (val.length > 0) {
            NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
            for (NSString *key in defaults.allKeys) {
                if ([key containsString:@"_gems"] || [key containsString:@"_last_gems"]) {
                    [[NSUserDefaults standardUserDefaults] setObject:val forKey:key];
                }
            }
            [[NSUserDefaults standardUserDefaults] synchronize];

            UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Done"
                                                                          message:@"Gems values updated."
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            UIViewController *root = self.rootViewController;
            if (root) [root presentViewController:done animated:YES completion:nil];
        }
    }]];
    [input addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *root = self.rootViewController;
    if (root) [root presentViewController:input animated:YES completion:nil];
}

#pragma mark - Mass edit helper (regex)

- (void)massEditWithPattern:(NSString *)regexPattern newValue:(NSString *)val {
    NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSError *err = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexPattern options:0 error:&err];
    if (err) {
        // invalid regex
        UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                          message:@"Invalid pattern"
                                                                   preferredStyle:UIAlertControllerStyleAlert];
        [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *r = self.rootViewController;
        if (r) [r presentViewController:errAlert animated:YES completion:nil];
        return;
    }

    NSMutableArray *changedKeys = [NSMutableArray array];

    for (NSString *key in defaults.allKeys) {
        NSTextCheckingResult *m = [regex firstMatchInString:key options:0 range:NSMakeRange(0, key.length)];
        if (m) {
            // write appropriate type: try to preserve numeric if val looks numeric, bool if "true"/"false"
            id outVal = val;
            NSString *lower = [val lowercaseString];
            if ([lower isEqualToString:@"true"] || [lower isEqualToString:@"false"]) {
                outVal = @([lower isEqualToString:@"true"]);
            } else {
                // check if integer
                NSScanner *scanner = [NSScanner scannerWithString:val];
                int intVal;
                if ([scanner scanInt:&intVal] && scanner.isAtEnd) {
                    outVal = @(intVal);
                } else {
                    // keep as string
                    outVal = val;
                }
            }

            [[NSUserDefaults standardUserDefaults] setObject:outVal forKey:key];
            [changedKeys addObject:key];
        }
    }
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSString *msg = [NSString stringWithFormat:@"Applied %@ to %lu keys", val, (unsigned long)changedKeys.count];
    UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Done"
                                                                  message:msg
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *root = self.rootViewController;
    if (root) [root presentViewController:done animated:YES completion:nil];
}

#pragma mark - Server verification (kept from your code)

- (void)verifyWithServerThen:(void(^)(BOOL allowed))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSString *uuid = [[NSUUID UUID] UUIDString];
        NSMutableArray *usedUUIDs = [[[NSUserDefaults standardUserDefaults] objectForKey:@"usedUUIDs"] mutableCopy];
        if (!usedUUIDs) usedUUIDs = [NSMutableArray array];
        [usedUUIDs addObject:uuid];
        [[NSUserDefaults standardUserDefaults] setObject:usedUUIDs forKey:@"usedUUIDs"];
        [[NSUserDefaults standardUserDefaults] synchronize];

        long long ts = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
        NSString *tsStr = [NSString stringWithFormat:@"%lld", ts];
        NSString *bundle = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";

        NSDictionary *payloadDict = @{@"timestamp": tsStr, @"bundle": bundle, @"uuid": uuid};
        NSData *json = [NSJSONSerialization dataWithJSONObject:payloadDict options:0 error:nil];
        NSData *enc = [self aes256EncryptData:json];
        NSString *b64 = [enc base64EncodedStringWithOptions:0];

        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kServerURL]];
        req.HTTPMethod = @"POST";
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        req.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"data": b64} options:0 error:nil];

        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (err || !data) { dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); }); return; }
            NSDictionary *respJson = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *b64Resp = respJson[@"data"];
            if (!b64Resp) { dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); }); return; }
            NSData *encResp = [[NSData alloc] initWithBase64EncodedString:b64Resp options:0];
            NSData *dec = [self aes256DecryptData:encResp];
            if (!dec) { dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); }); return; }
            NSDictionary *respDict = [NSJSONSerialization JSONObjectWithData:dec options:0 error:nil];
            BOOL allowed = [respDict[@"allow"] boolValue];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(allowed); });
        }];
        [task resume];
    });
}

#pragma mark - AES helpers (kept from your code)

- (NSData *)dataFromHexString:(NSString *)hex {
    NSMutableData *data = [NSMutableData data];
    for (NSUInteger i = 0; i+2 <= hex.length; i+=2) {
        unsigned int val;
        [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&val];
        uint8_t b = (uint8_t)val;
        [data appendBytes:&b length:1];
    }
    return data;
}

- (NSData *)aes256EncryptData:(NSData *)plain {
    NSData *keyData = [self dataFromHexString:kAESKeyHex];
    NSData *ivData  = [self dataFromHexString:kAESIvHex];
    size_t outLen;
    void *buf = malloc(plain.length + kCCBlockSizeAES128);
    CCCryptorStatus res = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                  keyData.bytes, kCCKeySizeAES256, ivData.bytes,
                                  plain.bytes, plain.length,
                                  buf, plain.length + kCCBlockSizeAES128, &outLen);
    if (res != kCCSuccess) { free(buf); return nil; }
    return [NSData dataWithBytesNoCopy:buf length:outLen freeWhenDone:YES];
}

- (NSData *)aes256DecryptData:(NSData *)enc {
    NSData *keyData = [self dataFromHexString:kAESKeyHex];
    NSData *ivData  = [self dataFromHexString:kAESIvHex];
    size_t outLen;
    void *buf = malloc(enc.length + kCCBlockSizeAES128);
    CCCryptorStatus res = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                  keyData.bytes, kCCKeySizeAES256, ivData.bytes,
                                  enc.bytes, enc.length,
                                  buf, enc.length + kCCBlockSizeAES128, &outLen);
    if (res != kCCSuccess) { free(buf); return nil; }
    return [NSData dataWithBytesNoCopy:buf length:outLen freeWhenDone:YES];
}

@end
