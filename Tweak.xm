#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonDigest.h>

// === CONFIG ===
static NSString *kServerURL = @"https://chillysilly.frfrnocap.men/tverify.php";
static NSString *kKeyHex = @"0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567";
static NSString *kIVHex  = @"0123456789ABCDEF0123456789ABCDEF";

// === HEX → NSData ===
NSData *hex2data(NSString *hex) {
    NSMutableData *data = [NSMutableData data];
    for (NSUInteger i = 0; i < hex.length; i+=2) {
        NSString *byteStr = [hex substringWithRange:NSMakeRange(i, 2)];
        unsigned int num;
        [[NSScanner scannerWithString:byteStr] scanHexInt:&num];
        unsigned char c = (unsigned char)num;
        [data appendBytes:&c length:1];
    }
    return data;
}

// === AES Encrypt/Decrypt ===
NSData *aesEncrypt(NSData *data, NSData *key, NSData *iv) {
    size_t outLength;
    NSMutableData *cipher = [NSMutableData dataWithLength:data.length + kCCBlockSizeAES128];
    CCCryptorStatus result = CCCrypt(kCCEncrypt, kCCAlgorithmAES128,
        kCCOptionPKCS7Padding, key.bytes, key.length, iv.bytes,
        data.bytes, data.length, cipher.mutableBytes, cipher.length, &outLength);
    if (result == kCCSuccess) {
        cipher.length = outLength;
        return cipher;
    }
    return nil;
}

NSData *aesDecrypt(NSData *data, NSData *key, NSData *iv) {
    size_t outLength;
    NSMutableData *plain = [NSMutableData dataWithLength:data.length + kCCBlockSizeAES128];
    CCCryptorStatus result = CCCrypt(kCCDecrypt, kCCAlgorithmAES128,
        kCCOptionPKCS7Padding, key.bytes, key.length, iv.bytes,
        data.bytes, data.length, plain.mutableBytes, plain.length, &outLength);
    if (result == kCCSuccess) {
        plain.length = outLength;
        return plain;
    }
    return nil;
}

@interface UIWindow (Overlay)
@end

@implementation UIWindow (Overlay)

- (void)layoutSubviews {
    [super layoutSubviews];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIButton *menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
        menuButton.frame = CGRectMake(50, 200, 120, 40);
        [menuButton setTitle:@"Game Tools" forState:UIControlStateNormal];
        menuButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1 alpha:0.8];
        [menuButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        menuButton.layer.cornerRadius = 8;
        [menuButton addTarget:self action:@selector(requestServerCheck) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:menuButton];
    });
}

- (NSUserDefaults *)gameDefaults {
    return [NSUserDefaults standardUserDefaults];
}

#pragma mark - Server Check

- (void)requestServerCheck {
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSString *timestamp = [NSString stringWithFormat:@"%ld", time(NULL)];
    NSDictionary *payload = @{@"uuid": uuid, @"timestamp": timestamp};
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];

    NSData *key = hex2data(kKeyHex);
    NSData *iv  = hex2data(kIVHex);

    NSData *encrypted = aesEncrypt(json, key, iv);
    NSString *b64 = [encrypted base64EncodedStringWithOptions:0];
    NSDictionary *body = @{@"data": b64};
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kServerURL]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = bodyData;

    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *error) {
        if (error || !data) { exit(0); }
        NSDictionary *resp = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (!resp[@"data"]) { exit(0); }

        NSData *respCipher = [[NSData alloc] initWithBase64EncodedString:resp[@"data"] options:0];
        NSData *respPlain  = aesDecrypt(respCipher, key, iv);
        NSDictionary *respJson = [NSJSONSerialization JSONObjectWithData:respPlain options:0 error:nil];
        BOOL allow = [respJson[@"allow"] boolValue];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (allow) {
                [self showToolsMenu];
            } else {
                exit(0);
            }
        });
    }];
    [task resume];
}

#pragma mark - Menu

- (void)showToolsMenu {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Game Tools"
        message:@"Choose an option"
        preferredStyle:UIAlertControllerStyleAlert];

    NSArray *options = @[@"Search", @"Unlock Char", @"Unlock Skin", @"Unlock Skill", @"Unlock Pet", @"Gems", @"Reborn"];
    for (NSString *opt in options) {
        [menu addAction:[UIAlertAction actionWithTitle:opt style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if ([opt isEqualToString:@"Search"]) {
                [self handleSearch];
            } else if ([opt isEqualToString:@"Unlock Char"]) {
                [self massEditWithRegex:@".*_c\\d+_unlock" value:@(YES)];
            } else if ([opt isEqualToString:@"Unlock Skin"]) {
                [self massEditWithRegex:@".*_c\\d+_skin\\d+" value:@(1)];
            } else if ([opt isEqualToString:@"Unlock Skill"]) {
                [self massEditWithRegex:@".*_c_.*_skill_\\d+_unlock" value:@(1)];
            } else if ([opt isEqualToString:@"Unlock Pet"]) {
                [self massEditWithRegex:@".*_p\\d+_unlock" value:@(YES)];
            } else if ([opt isEqualToString:@"Gems"]) {
                [self handleGems];
            } else if ([opt isEqualToString:@"Reborn"]) {
                [self massEditWithRegex:@".*_reborn_card" value:@(1)];
            }
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:menu animated:YES completion:nil];
}

#pragma mark - Actions

- (void)handleSearch {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Search Key"
        message:@"Enter part of the key"
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:nil];
    [alert addAction:[UIAlertAction actionWithTitle:@"Search" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *query = alert.textFields.firstObject.text;
        if (query.length == 0) return;
        NSDictionary *all = [[self gameDefaults] dictionaryRepresentation];
        NSMutableArray *matches = [NSMutableArray array];
        for (NSString *k in all) {
            if ([k.lowercaseString containsString:query.lowercaseString]) {
                [matches addObject:k];
            }
        }
        NSString *result = matches.count > 0 ? [matches componentsJoinedByString:@"\n"] : @"No matches";
        UIAlertController *out = [UIAlertController alertControllerWithTitle:@"Results"
            message:result preferredStyle:UIAlertControllerStyleAlert];
        [out addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:out animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

- (void)handleGems {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Set Gems"
        message:@"Enter gem value"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSInteger gems = [alert.textFields.firstObject.text integerValue];
        NSDictionary *all = [[self gameDefaults] dictionaryRepresentation];
        for (NSString *k in all) {
            if ([k hasSuffix:@"_gems"] || [k hasSuffix:@"_last_gems"]) {
                [[self gameDefaults] setObject:@(gems) forKey:k];
            }
        }
        [[self gameDefaults] synchronize];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

- (void)massEditWithRegex:(NSString *)pattern value:(id)value {
    NSDictionary *all = [[self gameDefaults] dictionaryRepresentation];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    for (NSString *k in all) {
        if ([regex numberOfMatchesInString:k options:0 range:NSMakeRange(0, k.length)] > 0) {
            [[self gameDefaults] setObject:value forKey:k];
        }
    }
    [[self gameDefaults] synchronize];
    UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Done"
        message:[NSString stringWithFormat:@"Applied changes for %@", pattern]
        preferredStyle:UIAlertControllerStyleAlert];
    [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:done animated:YES completion:nil];
}

@end
