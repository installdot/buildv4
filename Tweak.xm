#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCryptor.h>

static NSString * const kServerURL = @"https://yourserver.example/verify.php"; // replace
static NSString * const kAESKeyHex = @"0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567";
static NSString * const kAESIvHex  = @"0123456789ABCDEF0123456789ABCDEF";

@interface UIWindow (Overlay)
@end

@implementation UIWindow (Overlay)

- (void)layoutSubviews {
    [super layoutSubviews];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIButton *menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
        menuButton.frame = CGRectMake(50, 100, 120, 40);
        [menuButton setTitle:@"Menu" forState:UIControlStateNormal];
        menuButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        [menuButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        menuButton.layer.cornerRadius = 8.0;
        menuButton.clipsToBounds = YES;
        [menuButton addTarget:self action:@selector(showMainMenu) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:menuButton];
    });
}

#pragma mark - Main Menu

- (void)showMainMenu {
    [self verifyWithServerThen:^(BOOL allowed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!allowed) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Access Denied"
                                                                               message:@"Server rejected request."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    exit(0);
                }]];
                [self.rootViewController presentViewController:alert animated:YES completion:nil];
                return;
            }

            UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Options"
                                                                          message:nil
                                                                   preferredStyle:UIAlertControllerStyleActionSheet];

            [menu addAction:[UIAlertAction actionWithTitle:@"Search" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
                [self promptSearchKey];
            }]];
            [menu addAction:[UIAlertAction actionWithTitle:@"Unlock Char" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
                [self massEditWithPattern:@"_c[0-9]+_unlock" newValue:@"true"];
            }]];
            [menu addAction:[UIAlertAction actionWithTitle:@"Unlock Skin" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
                [self massEditWithPattern:@"_c[0-9]+_skin[0-9]+" newValue:@"1"];
            }]];
            [menu addAction:[UIAlertAction actionWithTitle:@"Unlock Skill" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
                [self massEditWithPattern:@"_c_.*_skill_.*_unlock" newValue:@"1"];
            }]];
            [menu addAction:[UIAlertAction actionWithTitle:@"Unlock Pet" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
                [self massEditWithPattern:@"_p[0-9]+_unlock" newValue:@"true"];
            }]];
            [menu addAction:[UIAlertAction actionWithTitle:@"Gems" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
                [self promptSetGems];
            }]];
            [menu addAction:[UIAlertAction actionWithTitle:@"Reborn" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
                [self massEditWithPattern:@"_reborn_card" newValue:@"1"];
            }]];
            [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

            [self.rootViewController presentViewController:menu animated:YES completion:nil];
        });
    }];
}

#pragma mark - Search Flow

- (void)promptSearchKey {
    UIAlertController *input = [UIAlertController alertControllerWithTitle:@"Search Key"
                                                                   message:@"Enter part of the key to search"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [input addTextFieldWithConfigurationHandler:nil];

    [input addAction:[UIAlertAction actionWithTitle:@"Search" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
        NSString *term = input.textFields.firstObject.text;
        if (term.length > 0) {
            [self showMatchingKeys:term];
        }
    }]];
    [input addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self.rootViewController presentViewController:input animated:YES completion:nil];
}

- (void)showMatchingKeys:(NSString *)term {
    NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSMutableArray *matches = [NSMutableArray array];
    for (NSString *key in defaults.allKeys) {
        if ([key localizedCaseInsensitiveContainsString:term]) {
            [matches addObject:key];
        }
    }

    if (matches.count == 0) {
        UIAlertController *none = [UIAlertController alertControllerWithTitle:@"No Match"
                                                                      message:@"No keys found."
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [none addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self.rootViewController presentViewController:none animated:YES completion:nil];
        return;
    }

    UIAlertController *list = [UIAlertController alertControllerWithTitle:@"Matches"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *key in matches) {
        [list addAction:[UIAlertAction actionWithTitle:key style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
            [self promptEditKey:key];
        }]];
    }
    [list addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.rootViewController presentViewController:list animated:YES completion:nil];
}

- (void)promptEditKey:(NSString *)key {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    NSString *curVal = val ? [val description] : @"<nil>";

    UIAlertController *edit = [UIAlertController alertControllerWithTitle:key
                                                                  message:[NSString stringWithFormat:@"Current: %@", curVal]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [edit addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = curVal;
    }];
    [edit addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
        NSString *newVal = edit.textFields.firstObject.text;
        [[NSUserDefaults standardUserDefaults] setObject:newVal forKey:key];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }]];
    [edit addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.rootViewController presentViewController:edit animated:YES completion:nil];
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
                if ([key hasSuffix:@"_gems"] || [key hasSuffix:@"_last_gems"]) {
                    [[NSUserDefaults standardUserDefaults] setObject:val forKey:key];
                }
            }
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }]];
    [input addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.rootViewController presentViewController:input animated:YES completion:nil];
}

#pragma mark - Mass edit helper

- (void)massEditWithPattern:(NSString *)regexPattern newValue:(NSString *)val {
    NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexPattern options:0 error:nil];

    for (NSString *key in defaults.allKeys) {
        NSTextCheckingResult *m = [regex firstMatchInString:key options:0 range:NSMakeRange(0, key.length)];
        if (m) {
            [[NSUserDefaults standardUserDefaults] setObject:val forKey:key];
        }
    }
    [[NSUserDefaults standardUserDefaults] synchronize];

    UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Done"
                                                                  message:[NSString stringWithFormat:@"Applied %@ to matching keys", val]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self.rootViewController presentViewController:done animated:YES completion:nil];
}

#pragma mark - Verify (AES + UUID replay)

- (void)verifyWithServerThen:(void (^)(BOOL))callback {
    NSString *uuid = [[NSUserDefaults standardUserDefaults] stringForKey:@"verifyUUID"];
    if (!uuid) {
        uuid = [[NSUUID UUID] UUIDString];
        [[NSUserDefaults standardUserDefaults] setObject:uuid forKey:@"verifyUUID"];
    }

    NSString *timestamp = [NSString stringWithFormat:@"%f", [[NSDate date] timeIntervalSince1970]];
    NSString *payload = [NSString stringWithFormat:@"%@|%@", timestamp, uuid];

    NSData *enc = [self aesEncrypt:[payload dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *b64 = [enc base64EncodedStringWithOptions:0];

    NSURL *url = [NSURL URLWithString:kServerURL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = [b64 dataUsingEncoding:NSUTF8StringEncoding];

    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        if (!data || err) {
            callback(NO);
            return;
        }
        NSString *resp = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        BOOL allowed = [resp containsString:@"true"];
        callback(allowed);
    }] resume];
}

#pragma mark - AES

- (NSData *)aesEncrypt:(NSData *)data {
    NSMutableData *out = [NSMutableData dataWithLength:data.length + kCCBlockSizeAES128];
    size_t outLen;
    NSData *key = [self dataFromHex:kAESKeyHex];
    NSData *iv  = [self dataFromHex:kAESIvHex];

    CCCryptorStatus result = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                     key.bytes, key.length, iv.bytes,
                                     data.bytes, data.length,
                                     out.mutableBytes, out.length, &outLen);
    if (result == kCCSuccess) {
        out.length = outLen;
        return out;
    }
    return nil;
}

- (NSData *)dataFromHex:(NSString *)hex {
    NSMutableData *data = [NSMutableData data];
    for (int i = 0; i < hex.length; i += 2) {
        NSString *b = [hex substringWithRange:NSMakeRange(i, 2)];
        unsigned int v;
        [[NSScanner scannerWithString:b] scanHexInt:&v];
        unsigned char c = v;
        [data appendBytes:&c length:1];
    }
    return data;
}

@end
