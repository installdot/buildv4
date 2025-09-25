#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCryptor.h>

static NSString * const kServerURL = @"https://chillysilly.frfrnocap.men/tverify.php"; // replace
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
        [prefsButton setTitle:@"Find Key" forState:UIControlStateNormal];
        prefsButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        [prefsButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        prefsButton.layer.cornerRadius = 8.0;
        prefsButton.clipsToBounds = YES;
        [prefsButton addTarget:self action:@selector(findKeyStart) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:prefsButton];
    });
}

#pragma mark - Entry point

- (void)findKeyStart {
    [self verifyWithServerThen:^(BOOL allowed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (allowed) {
                [self promptSearchKey];
            } else {
                // show denied + close app
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Access Denied"
                                                                               message:@"Editing disabled by server."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    exit(0);
                }]];
                UIViewController *rootVC = self.rootViewController;
                if (rootVC) {
                    [rootVC presentViewController:alert animated:YES completion:nil];
                }
            }
        });
    }];
}

#pragma mark - Key search/edit

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

    UIAlertController *list = [UIAlertController alertControllerWithTitle:@"Select Key"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];

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
        [[NSUserDefaults standardUserDefaults] setObject:newVal forKey:key];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }]];

    [edit addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *rootVC = self.rootViewController;
    if (rootVC) [rootVC presentViewController:edit animated:YES completion:nil];
}

#pragma mark - Server verification

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

#pragma mark - AES

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
