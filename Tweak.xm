#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCryptor.h>

static NSString * const kServerURL = @"https://chillysilly.frfrnocap.men/tverify.php";
static NSString * const kAESKeyHex = @"0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567";
static NSString * const kAESIvHex  = @"0123456789ABCDEF0123456789ABCDEF";

static NSString *selectedID = nil;

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
        [menuButton addTarget:self action:@selector(openIDSelector) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:menuButton];
    });
}

#pragma mark - ID selector

- (void)openIDSelector {
    [self verifyWithServerThen:^(BOOL allowed) {
        if (!allowed) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Access Denied"
                                                                           message:@"Editing disabled by server."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                exit(0);
            }]];
            [self.rootViewController presentViewController:alert animated:YES completion:nil];
            return;
        }

        NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
        NSMutableSet *ids = [NSMutableSet set];
        for (NSString *key in defaults.allKeys) {
            NSArray *parts = [key componentsSeparatedByString:@"_c1"];
            if (parts.count > 1) [ids addObject:parts[0]];
        }

        UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Select ID"
                                                                        message:nil
                                                                 preferredStyle:UIAlertControllerStyleAlert];
        for (NSString *idPrefix in ids) {
            [picker addAction:[UIAlertAction actionWithTitle:idPrefix style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
                selectedID = idPrefix;
                [self showMainMenu];
            }]];
        }
        [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self.rootViewController presentViewController:picker animated:YES completion:nil];
    }];
}

#pragma mark - Main Menu

- (void)showMainMenu {
    if (!selectedID) return;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Options for %@", selectedID]
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    [menu addAction:[UIAlertAction actionWithTitle:@"Search" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
        [self promptSearchKey];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Unlock Char" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
        [self massEditPattern:[NSString stringWithFormat:@"%@_c[0-9]+_unlock", selectedID] newValue:@"true" useNumber:NO];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Unlock Skin" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
        [self massEditPattern:[NSString stringWithFormat:@"%@_c[0-9]+_skin[0-9]+", selectedID] newValue:@"1" useNumber:YES];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Unlock Skill" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
        [self massEditPattern:[NSString stringWithFormat:@"%@_c_.*_skill_.*_unlock", selectedID] newValue:@"1" useNumber:YES];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Unlock Pet" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
        [self massEditPattern:[NSString stringWithFormat:@"%@_p[0-9]+_unlock", selectedID] newValue:@"true" useNumber:NO];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Gems" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
        [self promptSetGems];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Reborn" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
        [self massEditPattern:[NSString stringWithFormat:@"%@_reborn_card", selectedID] newValue:@"1" useNumber:YES];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self.rootViewController presentViewController:menu animated:YES completion:nil];
}

#pragma mark - Gems

- (void)promptSetGems {
    UIAlertController *input = [UIAlertController alertControllerWithTitle:@"Set Gems"
                                                                   message:@"Enter new gems value"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [input addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"12345";
        tf.keyboardType = UIKeyboardTypeNumberPad;
    }];

    [input addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
        NSString *valStr = input.textFields.firstObject.text;
        if (valStr.length > 0) {
            NSNumber *numVal = @([valStr integerValue]);
            NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
            for (NSString *key in defaults.allKeys) {
                if ([key hasPrefix:selectedID]) {
                    if ([key hasSuffix:@"_gems"] || [key hasSuffix:@"_last_gems"]) {
                        [[NSUserDefaults standardUserDefaults] setObject:numVal forKey:key];
                    }
                }
            }
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }]];
    [input addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.rootViewController presentViewController:input animated:YES completion:nil];
}

#pragma mark - Mass edit

- (void)massEditPattern:(NSString *)regexPattern newValue:(NSString *)val useNumber:(BOOL)num {
    NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexPattern options:0 error:nil];
    for (NSString *key in defaults.allKeys) {
        if ([key hasPrefix:selectedID]) {
            if ([regex firstMatchInString:key options:0 range:NSMakeRange(0, key.length)]) {
                if (num) {
                    [[NSUserDefaults standardUserDefaults] setObject:@([val integerValue]) forKey:key];
                } else {
                    [[NSUserDefaults standardUserDefaults] setObject:val forKey:key];
                }
            }
        }
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
    UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Done"
                                                                  message:@"Applied changes"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self.rootViewController presentViewController:done animated:YES completion:nil];
}

#pragma mark - Search/Edit (unchanged)

- (void)promptSearchKey {
    UIAlertController *search = [UIAlertController alertControllerWithTitle:@"Search Key"
                                                                    message:@"Enter part of a key"
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [search addTextFieldWithConfigurationHandler:nil];
    [search addAction:[UIAlertAction actionWithTitle:@"Search" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
        NSString *query = search.textFields.firstObject.text;
        if (query.length > 0) {
            [self showMatchingKeys:query];
        }
    }]];
    [search addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.rootViewController presentViewController:search animated:YES completion:nil];
}

- (void)showMatchingKeys:(NSString *)query {
    NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSMutableArray *matches = [NSMutableArray array];
    for (NSString *key in defaults.allKeys) {
        if ([key hasPrefix:selectedID] && [[key lowercaseString] containsString:[query lowercaseString]]) {
            [matches addObject:key];
        }
    }
    if (matches.count == 0) return;
    UIAlertController *list = [UIAlertController alertControllerWithTitle:@"Select Key" message:nil preferredStyle:UIAlertControllerStyleAlert];
    for (NSString *key in matches) {
        [list addAction:[UIAlertAction actionWithTitle:key style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
            id val = defaults[key];
            [self promptEditKey:key currentValue:val];
        }]];
    }
    [list addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.rootViewController presentViewController:list animated:YES completion:nil];
}

- (void)promptEditKey:(NSString *)key currentValue:(id)value {
    NSString *valStr = value ? [value description] : @"(nil)";
    UIAlertController *edit = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Edit %@", key]
                                                                  message:[NSString stringWithFormat:@"Current: %@", valStr]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [edit addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = valStr; }];
    [edit addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
        NSString *newVal = edit.textFields.firstObject.text;
        [[NSUserDefaults standardUserDefaults] setObject:newVal forKey:key];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }]];
    [edit addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.rootViewController presentViewController:edit animated:YES completion:nil];
}

#pragma mark - Server verification (same as before)
// (verifyWithServerThen, AES helpers unchanged – keep them from your version)

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
