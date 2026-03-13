// tweak.xm — Soul Knight Save Manager v12
// iOS 14+ | Theos/Logos | ARC
// v12.0: Replaced identifierForVendor with real iOS UDID via .mobileconfig enrollment
//         UDID survives app delete/reinstall (stored in keychain).
//         If no UDID in keychain → show enrollment UI → open Safari → install profile
//         → app polls server until UDID received → stores in keychain → continues auth.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>
#import <sys/utsname.h>

// ── Config ────────────────────────────────────────────────────────────────────
#define API_BASE      @"https://chillysilly.frfrnocap.men/iske.php"
#define AUTH_BASE     @"https://chillysilly.frfrnocap.men/iskeauth.php"
#define UDID_BASE     @"https://chillysilly.frfrnocap.men/udid.php"

static NSString *authAESKeyHex(void) {
    return @"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"; // CHANGE
}
static NSString *authHMACKeyHex(void) {
    return @"fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"; // CHANGE
}

#define kMaxTsDrift  60

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SF Symbol helper
// ─────────────────────────────────────────────────────────────────────────────
static UIImage *sym(NSString *name, CGFloat ptSize) {
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:ptSize weight:UIImageSymbolWeightMedium];
    return [UIImage systemImageNamed:name withConfiguration:cfg];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Hex → NSData
// ─────────────────────────────────────────────────────────────────────────────
static NSData *dataFromHexString(NSString *hex) {
    NSMutableData *d = [NSMutableData dataWithCapacity:hex.length / 2];
    for (NSUInteger i = 0; i + 2 <= hex.length; i += 2) {
        NSRange r = NSMakeRange(i, 2);
        unsigned int byte = 0;
        [[NSScanner scannerWithString:[hex substringWithRange:r]] scanHexInt:&byte];
        uint8_t b = (uint8_t)byte;
        [d appendBytes:&b length:1];
    }
    return d;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AES-256-CBC + HMAC-SHA256
// ─────────────────────────────────────────────────────────────────────────────
static NSData *encryptBox(NSData *plainData, NSData *aesKey, NSData *hmacKey) {
    if (!plainData || !aesKey || aesKey.length != 32 || !hmacKey || hmacKey.length != 32) return nil;
    uint8_t iv[kCCBlockSizeAES128];
    (void)SecRandomCopyBytes(kSecRandomDefault, kCCBlockSizeAES128, iv);
    size_t outLen = plainData.length + kCCBlockSizeAES128;
    NSMutableData *cipher = [NSMutableData dataWithLength:outLen];
    size_t moved = 0;
    CCCryptorStatus st = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
        aesKey.bytes, kCCKeySizeAES256, iv,
        plainData.bytes, plainData.length, cipher.mutableBytes, outLen, &moved);
    if (st != kCCSuccess) return nil;
    [cipher setLength:moved];
    NSMutableData *forHmac = [NSMutableData dataWithBytes:iv length:kCCBlockSizeAES128];
    [forHmac appendData:cipher];
    uint8_t hmac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, hmacKey.length, forHmac.bytes, forHmac.length, hmac);
    NSMutableData *box = [NSMutableData dataWithBytes:iv length:kCCBlockSizeAES128];
    [box appendData:cipher];
    [box appendBytes:hmac length:CC_SHA256_DIGEST_LENGTH];
    return box;
}

static NSData *decryptBox(NSData *box, NSData *aesKey, NSData *hmacKey) {
    if (!box || box.length < (kCCBlockSizeAES128 + CC_SHA256_DIGEST_LENGTH + 1)) return nil;
    if (!aesKey || aesKey.length != 32 || !hmacKey || hmacKey.length != 32) return nil;
    NSData *iv     = [box subdataWithRange:NSMakeRange(0, kCCBlockSizeAES128)];
    NSData *hmac   = [box subdataWithRange:NSMakeRange(box.length - CC_SHA256_DIGEST_LENGTH, CC_SHA256_DIGEST_LENGTH)];
    NSData *cipher = [box subdataWithRange:NSMakeRange(kCCBlockSizeAES128, box.length - kCCBlockSizeAES128 - CC_SHA256_DIGEST_LENGTH)];
    NSMutableData *forHmac = [NSMutableData dataWithData:iv];
    [forHmac appendData:cipher];
    uint8_t calc[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, hmacKey.length, forHmac.bytes, forHmac.length, calc);
    if (![[NSData dataWithBytes:calc length:CC_SHA256_DIGEST_LENGTH] isEqualToData:hmac]) return nil;
    size_t outLen = cipher.length + kCCBlockSizeAES128;
    NSMutableData *plain = [NSMutableData dataWithLength:outLen];
    size_t moved = 0;
    CCCryptorStatus st = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
        aesKey.bytes, kCCKeySizeAES256, iv.bytes,
        cipher.bytes, cipher.length, plain.mutableBytes, outLen, &moved);
    if (st != kCCSuccess) return nil;
    [plain setLength:moved];
    return plain;
}

static NSString *encryptPayloadToBase64(NSDictionary *payload) {
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!jsonData) return nil;
    NSData *box = encryptBox(jsonData, dataFromHexString(authAESKeyHex()), dataFromHexString(authHMACKeyHex()));
    return box ? [box base64EncodedStringWithOptions:0] : nil;
}

static NSDictionary *decryptBase64ToDict(NSString *b64) {
    if (!b64.length) return nil;
    NSData *box = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    if (!box) return nil;
    NSData *plain = decryptBox(box, dataFromHexString(authAESKeyHex()), dataFromHexString(authHMACKeyHex()));
    return plain ? [NSJSONSerialization JSONObjectWithData:plain options:0 error:nil] : nil;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Keychain helpers
// ─────────────────────────────────────────────────────────────────────────────
static const NSString *kKCSvcUDID       = @"SKToolsRealUDID";
static const NSString *kKCSvcEnrollTok  = @"SKToolsEnrollToken";
static const NSString *kKCSvcKey        = @"SKToolsAuthKey";
static const NSString *kKCAccount       = @"sktools";

static NSDictionary *kcBaseQuery(NSString *service) {
    return @{
        (__bridge id)kSecClass:              (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:        service,
        (__bridge id)kSecAttrAccount:        kKCAccount,
        (__bridge id)kSecAttrAccessible:     (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        (__bridge id)kSecAttrSynchronizable: @NO,
    };
}

static NSString *kcRead(NSString *service) {
    NSMutableDictionary *q = [NSMutableDictionary dictionaryWithDictionary:kcBaseQuery(service)];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) != errSecSuccess || !result) return nil;
    NSString *str = [[NSString alloc] initWithData:(__bridge NSData *)result encoding:NSUTF8StringEncoding];
    CFRelease(result);
    return str;
}

static BOOL kcWrite(NSString *service, NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return NO;
    NSMutableDictionary *qFind = [NSMutableDictionary dictionaryWithDictionary:kcBaseQuery(service)];
    NSDictionary *update = @{ (__bridge id)kSecValueData: data };
    OSStatus st = SecItemUpdate((__bridge CFDictionaryRef)qFind, (__bridge CFDictionaryRef)update);
    if (st == errSecItemNotFound) {
        NSMutableDictionary *qAdd = [NSMutableDictionary dictionaryWithDictionary:kcBaseQuery(service)];
        qAdd[(__bridge id)kSecValueData] = data;
        st = SecItemAdd((__bridge CFDictionaryRef)qAdd, NULL);
    }
    return st == errSecSuccess;
}

static void kcDelete(NSString *service) {
    SecItemDelete((__bridge CFDictionaryRef)kcBaseQuery(service));
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Real UDID (profile-based, survives reinstall)
// ─────────────────────────────────────────────────────────────────────────────
static NSString *gRealUDID = nil;

static NSString *loadCachedUDID(void) {
    if (gRealUDID.length) return gRealUDID;
    NSString *kc = kcRead((NSString *)kKCSvcUDID);
    if (kc.length > 0) { gRealUDID = kc; return kc; }
    return nil;
}

static void saveRealUDID(NSString *udid) {
    if (!udid.length) return;
    gRealUDID = udid;
    kcWrite((NSString *)kKCSvcUDID, udid);
}

static NSString *loadEnrollToken(void) { return kcRead((NSString *)kKCSvcEnrollTok); }
static void saveEnrollToken(NSString *t) { kcWrite((NSString *)kKCSvcEnrollTok, t); }
static void clearEnrollToken(void)       { kcDelete((NSString *)kKCSvcEnrollTok); }

static NSString *newEnrollToken(void) {
    NSString *t = [[NSUUID UUID] UUIDString].lowercaseString;
    saveEnrollToken(t);
    return t;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Other keychain helpers
// ─────────────────────────────────────────────────────────────────────────────
static NSString *loadSavedKey(void)        { return kcRead((NSString *)kKCSvcKey); }
static void      saveSavedKey(NSString *k) { kcWrite((NSString *)kKCSvcKey, k); }
static void      clearSavedKey(void)       { kcDelete((NSString *)kKCSvcKey); }

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Timestamp replay guard
// ─────────────────────────────────────────────────────────────────────────────
static NSString *tsGuardFilePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/SKToolsLastTS.txt"];
}
static void saveLastSentTS(NSTimeInterval ts) {
    [[NSString stringWithFormat:@"%.0f", ts]
        writeToFile:tsGuardFilePath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static NSTimeInterval loadLastSentTS(void) {
    NSString *s = [NSString stringWithContentsOfFile:tsGuardFilePath() encoding:NSUTF8StringEncoding error:nil];
    return s.doubleValue;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Per-device expiry cache
// ─────────────────────────────────────────────────────────────────────────────
static NSTimeInterval gDeviceExpiry = 0;
static NSTimeInterval gKeyExpiry    = 0;
static BOOL           gWelcomeShownThisSession = NO;

static void saveDeviceExpiryLocally(NSTimeInterval exp) {
    [[NSUserDefaults standardUserDefaults] setDouble:exp forKey:@"SKToolsDeviceExpiry"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
static NSTimeInterval loadDeviceExpiryLocally(void) {
    return [[NSUserDefaults standardUserDefaults] doubleForKey:@"SKToolsDeviceExpiry"];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Session file
// ─────────────────────────────────────────────────────────────────────────────
static NSString *sessionFilePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/SKToolsSession.txt"];
}
static NSString *loadSessionUUID(void) {
    return [NSString stringWithContentsOfFile:sessionFilePath() encoding:NSUTF8StringEncoding error:nil];
}
static void saveSessionUUID(NSString *uuid) {
    [uuid writeToFile:sessionFilePath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static void clearSessionUUID(void) {
    [[NSFileManager defaultManager] removeItemAtPath:sessionFilePath() error:nil];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Settings
// ─────────────────────────────────────────────────────────────────────────────
static NSString *settingsFilePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/SKToolsSettings.plist"];
}
static NSMutableDictionary *loadSettingsDict(void) {
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:settingsFilePath()];
    return d ?: [NSMutableDictionary dictionary];
}
static void persistSettingsDict(NSMutableDictionary *d) { [d writeToFile:settingsFilePath() atomically:YES]; }
static BOOL getSetting(NSString *key) { return [loadSettingsDict()[key] boolValue]; }
static void setSetting(NSString *key, BOOL val) {
    NSMutableDictionary *d = loadSettingsDict(); d[key] = @(val); persistSettingsDict(d);
}
static void initDefaultSettings(void) {
    NSMutableDictionary *d = loadSettingsDict();
    BOOL changed = NO;
    if (!d[@"autoRij"]) { d[@"autoRij"] = @YES; changed = YES; }
    if (changed) persistSettingsDict(d);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Device info helpers
// ─────────────────────────────────────────────────────────────────────────────
static NSString *deviceModel(void) {
    struct utsname info; uname(&info);
    return [NSString stringWithCString:info.machine encoding:NSUTF8StringEncoding] ?: [UIDevice currentDevice].model;
}
static NSString *systemVersion(void) { return [UIDevice currentDevice].systemVersion ?: @"?"; }

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Auto Detect UID
// ─────────────────────────────────────────────────────────────────────────────
static NSString *detectPlayerUID(void) {
    NSString *raw = [[NSUserDefaults standardUserDefaults] stringForKey:@"SdkStateCache#1"];
    if (!raw.length) return nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![root isKindOfClass:[NSDictionary class]]) return nil;
    id user = root[@"User"];
    if (![user isKindOfClass:[NSDictionary class]]) return nil;
    id pid = ((NSDictionary *)user)[@"PlayerId"];
    return pid ? [NSString stringWithFormat:@"%@", pid] : nil;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Auto Rij
// ─────────────────────────────────────────────────────────────────────────────
static NSString *applyAutoRij(NSString *plistXML) {
    if (!plistXML.length) return plistXML;
    NSRegularExpression *rx = [NSRegularExpression
        regularExpressionWithPattern:@"<key>OpenRijTest_\\d+</key>\\s*<integer>1</integer>"
        options:0 error:nil];
    if (!rx) return plistXML;
    NSArray<NSTextCheckingResult *> *matches =
        [rx matchesInString:plistXML options:0 range:NSMakeRange(0, plistXML.length)];
    if (!matches.count) return plistXML;
    NSMutableString *result = [plistXML mutableCopy];
    for (NSTextCheckingResult *match in matches.reverseObjectEnumerator) {
        NSString *original = [result substringWithRange:match.range];
        NSString *patched  = [original stringByReplacingOccurrencesOfString:@"<integer>1</integer>"
                                                                 withString:@"<integer>0</integer>"];
        [result replaceCharactersInRange:match.range withString:patched];
    }
    NSData *testData = [result dataUsingEncoding:NSUTF8StringEncoding];
    if (!testData) return plistXML;
    NSError *verr = nil; id parsed = nil;
    @try { parsed = [NSPropertyListSerialization propertyListWithData:testData options:NSPropertyListImmutable format:nil error:&verr]; }
    @catch (NSException *ex) { return plistXML; }
    if (verr || !parsed) return plistXML;
    return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - URLSession
// ─────────────────────────────────────────────────────────────────────────────
static NSURLSession *makeSession(void) {
    NSURLSessionConfiguration *c = [NSURLSessionConfiguration defaultSessionConfiguration];
    c.timeoutIntervalForRequest  = 120;
    c.timeoutIntervalForResource = 600;
    c.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    return [NSURLSession sessionWithConfiguration:c];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Multipart body builder
// ─────────────────────────────────────────────────────────────────────────────
typedef struct { NSMutableURLRequest *req; NSData *body; } MPRequest;

static MPRequest buildMP(NSDictionary<NSString*,NSString*> *fields,
                          NSString *fileField, NSString *filename, NSData *fileData) {
    NSString *boundary = [NSString stringWithFormat:@"----SKBound%08X%08X", arc4random(), arc4random()];
    NSMutableData *body = [NSMutableData dataWithCapacity:fileData ? fileData.length + 1024 : 1024];
    void (^addField)(NSString *, NSString *) = ^(NSString *n, NSString *v) {
        NSString *s = [NSString stringWithFormat:
            @"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", boundary, n, v];
        [body appendData:[s dataUsingEncoding:NSUTF8StringEncoding]];
    };
    for (NSString *k in fields) addField(k, fields[k]);
    if (fileField && filename && fileData) {
        NSString *hdr = [NSString stringWithFormat:
            @"--%@\r\nContent-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n"
            @"Content-Type: text/plain; charset=utf-8\r\n\r\n", boundary, fileField, filename];
        [body appendData:[hdr dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:fileData];
        [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:API_BASE]
           cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
       timeoutInterval:120];
    req.HTTPMethod = @"POST";
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]
       forHTTPHeaderField:@"Content-Type"];
    return (MPRequest){ req, body };
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - POST helper
// ─────────────────────────────────────────────────────────────────────────────
static void skPost(NSURLSession *session,
                   NSMutableURLRequest *req, NSData *body,
                   void (^cb)(NSDictionary *json, NSError *err)) {
    [[session uploadTaskWithRequest:req fromData:body
                  completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err) { cb(nil, err); return; }
            if (!data.length) { cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                userInfo:@{NSLocalizedDescriptionKey:@"Empty server response"}]); return; }
            NSError *je = nil;
            NSDictionary *j = [NSJSONSerialization JSONObjectWithData:data options:0 error:&je];
            if (je || !j) {
                NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"Non-JSON response";
                cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:raw}]); return;
            }
            if (j[@"error"]) { cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                userInfo:@{NSLocalizedDescriptionKey:j[@"error"]}]); return; }
            cb(j, nil);
        });
    }] resume];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Auth Network Request
// ─────────────────────────────────────────────────────────────────────────────
static void performKeyAuth(NSString *keyValue,
                           void (^completion)(BOOL ok,
                                             NSTimeInterval keyExpiry,
                                             NSTimeInterval deviceExpiry,
                                             NSString *errorMsg)) {
    NSString *udid = loadCachedUDID();
    if (!udid.length) { completion(NO, 0, 0, @"Device not enrolled. UDID required."); return; }

    NSTimeInterval now    = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval sendTS = floor(now);
    saveLastSentTS(sendTS);

    NSDictionary *payload = @{
        @"key"       : keyValue ?: @"",
        @"timestamp" : @((long long)sendTS),
        @"device_id" : udid,
        @"model"     : deviceModel(),
        @"sys_ver"   : systemVersion(),
    };

    NSString *encPayload = encryptPayloadToBase64(payload);
    if (!encPayload) { completion(NO, 0, 0, @"Encryption failed."); return; }

    NSDictionary *bodyDict = @{ @"data" : encPayload };
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:nil];
    if (!bodyData) { completion(NO, 0, 0, @"JSON serialization failed."); return; }

    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:AUTH_BASE]
           cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
       timeoutInterval:20];
    req.HTTPMethod = @"POST";
    req.HTTPBody   = bodyData;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    [[makeSession() dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err) { completion(NO, 0, 0, [NSString stringWithFormat:@"Network error: %@", err.localizedDescription]); return; }
            if (!data.length) { completion(NO, 0, 0, @"Empty auth response."); return; }
            NSError *je = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&je];
            if (je || !json) { completion(NO, 0, 0, @"Auth server returned invalid JSON."); return; }
            if (json[@"error"]) { completion(NO, 0, 0, json[@"error"]); return; }
            NSString *encResp = json[@"data"];
            if (!encResp.length) { completion(NO, 0, 0, @"No data in auth response."); return; }
            NSDictionary *respDict = decryptBase64ToDict(encResp);
            if (!respDict) { completion(NO, 0, 0, @"Failed to decrypt auth response."); return; }

            NSTimeInterval echoedTS  = [respDict[@"timestamp"]     doubleValue];
            NSTimeInterval keyExpiry = [respDict[@"expiry"]        doubleValue];
            NSTimeInterval devExpiry = [respDict[@"device_expiry"] doubleValue];
            BOOL           success   = [respDict[@"success"]       boolValue];
            NSString      *message   = respDict[@"message"] ?: @"Unknown error";
            NSTimeInterval currentNow = [[NSDate date] timeIntervalSince1970];

            if (llabs((long long)echoedTS - (long long)sendTS) > 0) {
                clearSavedKey();
                completion(NO, 0, 0, @"Auth response timestamp mismatch."); return;
            }
            if (llabs((long long)loadLastSentTS() - (long long)sendTS) > 0) {
                clearSavedKey();
                completion(NO, 0, 0, @"Replay guard triggered."); return;
            }
            if (fabs(currentNow - echoedTS) > kMaxTsDrift) {
                clearSavedKey();
                completion(NO, 0, 0, @"Auth response too old."); return;
            }
            if (!success) { clearSavedKey(); completion(NO, 0, 0, message); return; }
            completion(YES, keyExpiry, devExpiry, message);
        });
    }] resume];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Poll server for UDID (after profile install)
// ─────────────────────────────────────────────────────────────────────────────
static void pollForUDID(NSString *token,
                         NSInteger attempt,
                         NSInteger maxAttempts,
                         void (^onFound)(NSString *udid),
                         void (^onTimeout)(void)) {
    if (attempt >= maxAttempts) {
        dispatch_async(dispatch_get_main_queue(), ^{ onTimeout(); });
        return;
    }

    NSString *urlStr = [NSString stringWithFormat:@"%@?action=check&token=%@",
        UDID_BASE, [token stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]];
    NSURL *url = [NSURL URLWithString:urlStr];

    // FIX: removed unused NSMutableURLRequest *req variable — use dataTaskWithURL directly
    [[makeSession() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!err && data.length) {
            NSDictionary *j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([j[@"found"] boolValue] && [j[@"udid"] length] > 0) {
                NSString *udid = j[@"udid"];
                saveRealUDID(udid);
                clearEnrollToken();
                dispatch_async(dispatch_get_main_queue(), ^{ onFound(udid); });
                return;
            }
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                pollForUDID(token, attempt + 1, maxAttempts, onFound, onTimeout);
            });
    }] resume];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SF Symbol tinted image view helper
// ─────────────────────────────────────────────────────────────────────────────
static UIImageView *symView(NSString *name, CGFloat ptSize, UIColor *tint) {
    UIImageView *v = [[UIImageView alloc] initWithImage:sym(name, ptSize)];
    v.tintColor = tint;
    v.contentMode = UIViewContentModeScaleAspectFit;
    v.translatesAutoresizingMaskIntoConstraints = NO;
    return v;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Button with SF Symbol + label
// ─────────────────────────────────────────────────────────────────────────────
static UIButton *makeSymBtn(NSString *title, NSString *symName, UIColor *bg, SEL action, id target) {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.backgroundColor    = bg;
    btn.layer.cornerRadius = 9;
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightMedium];
    UIImage *img = [[UIImage systemImageNamed:symName withConfiguration:cfg]
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [btn setImage:img forState:UIControlStateNormal];
    btn.tintColor = [UIColor whiteColor];
    [btn setTitle:[NSString stringWithFormat:@"  %@", title] forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor colorWithWhite:0.70 alpha:1] forState:UIControlStateHighlighted];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    if (action && target) [btn addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    return btn;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Spin animation key
// ─────────────────────────────────────────────────────────────────────────────
static NSString *kSpinKey = @"SKSpinRotation";
static void startSpinAnimation(CALayer *layer) {
    CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    anim.toValue      = @(M_PI * 2.0);
    anim.duration     = 5.0;
    anim.repeatCount  = HUGE_VALF;
    anim.cumulative   = YES;
    anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [layer addAnimation:anim forKey:kSpinKey];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKUDIDEnrollOverlay
// REWRITE: Compact frame-based panel, same architecture as SKPanel.
// ROOT CAUSE of old broken buttons: the full-screen UIView with dark
// backgroundColor intercepted ALL game-engine touch events before UIKit
// could route them to any subview. Fix: the view IS the card — no wrapper.
// Pure CGRect frame layout (zero Auto Layout), added directly to UIWindow.
// Key auth does NOT start until UDID confirmed in the completion block.
// ─────────────────────────────────────────────────────────────────────────────
static const CGFloat kEW = 258;   // enroll panel width (matches SKPanel kPW)

@interface SKUDIDEnrollOverlay : UIView
+ (instancetype)showInWindow:(UIWindow *)win completion:(void (^)(NSString *udid))completion;
@end

@implementation SKUDIDEnrollOverlay {
    NSString                 *_enrollToken;
    UILabel                  *_statusLabel;
    UIButton                 *_openSafariBtn;
    UIButton                 *_pollBtn;
    UIActivityIndicatorView  *_spinner;
    BOOL                      _polling;
    void (^_completion)(NSString *);
}

+ (instancetype)showInWindow:(UIWindow *)win completion:(void (^)(NSString *))completion {
    // Fixed height computed from content rows below
    CGFloat h  = 44+1+8+66+4+28+4+20+6+42+6+36+10;  // = 275
    CGFloat cx = win.bounds.size.width  / 2;
    CGFloat cy = win.bounds.size.height / 2;
    CGRect  f  = CGRectMake(cx - kEW/2, cy - h/2, kEW, h);
    SKUDIDEnrollOverlay *o = [[SKUDIDEnrollOverlay alloc] initWithFrame:f];
    o->_completion = [completion copy];
    o.layer.zPosition = 9999;
    [win addSubview:o];
    [win bringSubviewToFront:o];
    o.alpha = 0;
    [UIView animateWithDuration:0.25 animations:^{ o.alpha = 1; }];
    return o;
}

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;

    _enrollToken = loadEnrollToken();
    if (!_enrollToken.length) _enrollToken = newEnrollToken();

    // The view IS the panel card — no full-screen wrapper at all.
    self.backgroundColor    = [UIColor colorWithRed:0.06 green:0.06 blue:0.09 alpha:0.97];
    self.layer.cornerRadius = 13;
    self.layer.shadowColor  = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.86;
    self.layer.shadowRadius  = 12;
    self.layer.shadowOffset  = CGSizeMake(0, 4);
    self.clipsToBounds       = NO;

    [self buildUI];
    return self;
}

// Frame-based button builder — identical pattern to SKPanel -btn:symName:color:frame:action:
- (UIButton *)enrollBtn:(NSString *)title symName:(NSString *)sName
                  color:(UIColor *)c frame:(CGRect)fr action:(SEL)s {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame              = fr;
    b.backgroundColor    = c;
    b.layer.cornerRadius = 9;
    b.clipsToBounds      = YES;
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightMedium];
    UIImage *img = [[UIImage systemImageNamed:sName withConfiguration:cfg]
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [b setImage:img forState:UIControlStateNormal];
    b.tintColor = [UIColor whiteColor];
    [b setTitle:[NSString stringWithFormat:@"  %@", title] forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor]                  forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:0.70 alpha:1] forState:UIControlStateHighlighted];
    [b setTitleColor:[UIColor colorWithWhite:0.35 alpha:1] forState:UIControlStateDisabled];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)buildUI {
    CGFloat W   = kEW;
    CGFloat pad = 10;
    CGFloat bw  = W - pad * 2;
    CGFloat y   = 0;

    // ── Header bar (mirrors SKPanel buildBar) ─────────────────────────────────
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 44)];
    bar.backgroundColor    = [UIColor colorWithRed:0.08 green:0.08 blue:0.13 alpha:1];
    bar.userInteractionEnabled = NO;
    [self addSubview:bar];

    UIImageView *icon = [[UIImageView alloc] initWithImage:sym(@"iphone.badge.play", 11)];
    icon.tintColor    = [UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:1];
    icon.contentMode  = UIViewContentModeScaleAspectFit;
    icon.frame        = CGRectMake(12, 14, 16, 16);
    [bar addSubview:icon];

    UILabel *titleL      = [UILabel new];
    titleL.text          = @"iSKE - Device Registration";
    titleL.textColor     = [UIColor colorWithWhite:0.82 alpha:1];
    titleL.font          = [UIFont boldSystemFontOfSize:12];
    titleL.textAlignment = NSTextAlignmentCenter;
    titleL.frame         = CGRectMake(0, 14, W, 18);
    titleL.userInteractionEnabled = NO;
    [bar addSubview:titleL];
    y = 44;

    // ── Divider ───────────────────────────────────────────────────────────────
    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(0, y, W, 1)];
    div.backgroundColor        = [UIColor colorWithWhite:0.16 alpha:1];
    div.userInteractionEnabled = NO;
    [self addSubview:div];
    y += 1;

    // ── Step instructions ─────────────────────────────────────────────────────
    UILabel *steps      = [[UILabel alloc] initWithFrame:CGRectMake(pad, y+8, bw, 66)];
    steps.numberOfLines = 0;
    steps.textColor     = [UIColor colorWithWhite:0.54 alpha:1];
    steps.font          = [UIFont systemFontOfSize:11];
    steps.text          =
        @"① Tap \"Get UDID\" below\n"
        @"② Safari opens — tap Allow / Install\n"
        @"③ Settings → Profile → Install\n"
        @"④ Return here — auto detected";
    steps.userInteractionEnabled = NO;
    [self addSubview:steps];
    y += 8 + 66;

    // ── Status label ──────────────────────────────────────────────────────────
    _statusLabel               = [[UILabel alloc] initWithFrame:CGRectMake(pad, y+4, bw, 28)];
    _statusLabel.textColor     = [UIColor colorWithRed:0.90 green:0.35 blue:0.35 alpha:1];
    _statusLabel.font          = [UIFont systemFontOfSize:10.5];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.numberOfLines = 2;
    _statusLabel.text          = @"";
    _statusLabel.userInteractionEnabled = NO;
    [self addSubview:_statusLabel];
    y += 4 + 28;

    // ── Spinner ───────────────────────────────────────────────────────────────
    _spinner       = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color  = [UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];
    _spinner.hidden = YES;
    _spinner.frame  = CGRectMake(W/2 - 10, y+4, 20, 20);
    _spinner.userInteractionEnabled = NO;
    [self addSubview:_spinner];
    y += 4 + 20 + 6;

    // ── Get UDID button ───────────────────────────────────────────────────────
    _openSafariBtn = [self enrollBtn:@"Get UDID (opens Safari)"
                             symName:@"safari"
                               color:[UIColor colorWithRed:0.14 green:0.52 blue:0.28 alpha:1]
                               frame:CGRectMake(pad, y, bw, 42)
                              action:@selector(tapGetUDID)];
    [self addSubview:_openSafariBtn];
    y += 42 + 6;

    // ── Already installed button ──────────────────────────────────────────────
    _pollBtn = [self enrollBtn:@"Already Installed Profile"
                       symName:@"checkmark.circle"
                         color:[UIColor colorWithRed:0.18 green:0.35 blue:0.55 alpha:1]
                         frame:CGRectMake(pad, y, bw, 36)
                        action:@selector(tapAlreadyDone)];
    [self addSubview:_pollBtn];
}


- (void)tapGetUDID {
    NSString *profileURL = [NSString stringWithFormat:@"%@?action=profile&token=%@",
        UDID_BASE, _enrollToken];
    NSURL *url = [NSURL URLWithString:profileURL];
    if (!url) return;

    _statusLabel.text      = @"Safari opened — install the profile,\nthen return to this app.";
    _statusLabel.textColor = [UIColor colorWithRed:0.85 green:0.70 blue:0.20 alpha:1];

    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        if (success) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{ [self startPolling]; });
        } else {
            _statusLabel.text      = @"Could not open Safari. Check your URL.";
            _statusLabel.textColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1];
        }
    }];
}

- (void)tapAlreadyDone {
    [self startPolling];
}

- (void)startPolling {
    if (_polling) return;
    _polling = YES;

    _statusLabel.text      = @"Waiting for profile installation…";
    _statusLabel.textColor = [UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:0.80];
    _spinner.hidden = NO;
    [_spinner startAnimating];
    _openSafariBtn.enabled = NO;
    _pollBtn.enabled       = NO;

    pollForUDID(_enrollToken, 0, 60,
        ^(NSString *udid) {
            [self->_spinner stopAnimating];
            self->_spinner.hidden = YES;
            self->_statusLabel.text      = [NSString stringWithFormat:@"✓ Registered: %@…%@",
                [udid substringToIndex:8], [udid substringFromIndex:32]];
            self->_statusLabel.textColor = [UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    [UIView animateWithDuration:0.2 animations:^{ self.alpha = 0; }
                                     completion:^(BOOL _) {
                        [self removeFromSuperview];
                        if (self->_completion) self->_completion(udid);
                    }];
                });
        },
        ^{
            self->_polling = NO;
            [self->_spinner stopAnimating];
            self->_spinner.hidden = YES;
            self->_statusLabel.text      = @"Timed out. Tap \"Get UDID\" again.";
            self->_statusLabel.textColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1];
            self->_openSafariBtn.enabled = YES;
            self->_pollBtn.enabled       = YES;
        });
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKProgressOverlay
// ─────────────────────────────────────────────────────────────────────────────
@interface SKProgressOverlay : UIView
@property (nonatomic, strong) UILabel        *titleLabel;
@property (nonatomic, strong) UIProgressView *bar;
@property (nonatomic, strong) UILabel        *percentLabel;
@property (nonatomic, strong) UITextView     *logView;
@property (nonatomic, strong) UIButton       *closeBtn;
@property (nonatomic, strong) UIButton       *openLinkBtn;
@property (nonatomic, copy)   NSString       *uploadedLink;
+ (instancetype)showInView:(UIView *)parent title:(NSString *)title;
- (void)setProgress:(float)p label:(NSString *)label;
- (void)appendLog:(NSString *)msg;
- (void)finish:(BOOL)success message:(NSString *)msg link:(NSString *)link;
@end

@implementation SKProgressOverlay
+ (instancetype)showInView:(UIView *)parent title:(NSString *)title {
    SKProgressOverlay *o = [[SKProgressOverlay alloc] initWithFrame:parent.bounds];
    o.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [parent addSubview:o];
    [o setup:title];
    o.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ o.alpha = 1; }];
    return o;
}
- (void)setup:(NSString *)title {
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
    UIView *card = [UIView new];
    card.backgroundColor    = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1];
    card.layer.cornerRadius = 18;
    card.layer.shadowColor  = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.85;
    card.layer.shadowRadius  = 18;
    card.layer.shadowOffset  = CGSizeMake(0, 6);
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:card];

    UIImageView *titleIcon = symView(@"icloud.and.arrow.up", 13,
        [UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1]);

    self.titleLabel = [UILabel new];
    self.titleLabel.text = title; self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.titleLabel.textAlignment = NSTextAlignmentLeft;
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *titleRow = [[UIStackView alloc] initWithArrangedSubviews:@[titleIcon, self.titleLabel]];
    titleRow.axis = UILayoutConstraintAxisHorizontal; titleRow.spacing = 7;
    titleRow.alignment = UIStackViewAlignmentCenter;
    titleRow.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:titleRow];

    self.bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.bar.trackTintColor = [UIColor colorWithWhite:0.22 alpha:1];
    self.bar.progressTintColor = [UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];
    self.bar.layer.cornerRadius = 3; self.bar.clipsToBounds = YES; self.bar.progress = 0;
    self.bar.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.bar];

    self.percentLabel = [UILabel new];
    self.percentLabel.text = @"0%";
    self.percentLabel.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    self.percentLabel.font = [UIFont boldSystemFontOfSize:11];
    self.percentLabel.textAlignment = NSTextAlignmentRight;
    self.percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.percentLabel];

    self.logView = [UITextView new];
    self.logView.backgroundColor = [UIColor colorWithWhite:0.04 alpha:1];
    self.logView.textColor = [UIColor colorWithRed:0.42 green:0.98 blue:0.58 alpha:1];
    self.logView.font = [UIFont fontWithName:@"Courier" size:10] ?: [UIFont systemFontOfSize:10];
    self.logView.editable = NO; self.logView.selectable = NO;
    self.logView.layer.cornerRadius = 8; self.logView.text = @"";
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.logView];

    self.openLinkBtn = makeSymBtn(@"Open Link in Browser", @"safari",
        [UIColor colorWithRed:0.16 green:0.52 blue:0.92 alpha:1], @selector(openLink), self);
    self.openLinkBtn.hidden = YES;
    [card addSubview:self.openLinkBtn];

    self.closeBtn = makeSymBtn(@"Close", @"xmark",
        [UIColor colorWithWhite:0.20 alpha:1], @selector(dismiss), self);
    self.closeBtn.hidden = YES;
    [card addSubview:self.closeBtn];

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:310],
        [titleRow.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
        [titleRow.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [titleRow.leadingAnchor constraintGreaterThanOrEqualToAnchor:card.leadingAnchor constant:16],
        [titleRow.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-16],
        [titleIcon.widthAnchor constraintEqualToConstant:18],
        [titleIcon.heightAnchor constraintEqualToConstant:18],
        [self.bar.topAnchor constraintEqualToAnchor:titleRow.bottomAnchor constant:14],
        [self.bar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.bar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-72],
        [self.bar.heightAnchor constraintEqualToConstant:6],
        [self.percentLabel.centerYAnchor constraintEqualToAnchor:self.bar.centerYAnchor],
        [self.percentLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [self.percentLabel.widthAnchor constraintEqualToConstant:54],
        [self.logView.topAnchor constraintEqualToAnchor:self.bar.bottomAnchor constant:10],
        [self.logView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [self.logView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [self.logView.heightAnchor constraintEqualToConstant:170],
        [self.openLinkBtn.topAnchor constraintEqualToAnchor:self.logView.bottomAnchor constant:10],
        [self.openLinkBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [self.openLinkBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [self.openLinkBtn.heightAnchor constraintEqualToConstant:42],
        [self.closeBtn.topAnchor constraintEqualToAnchor:self.openLinkBtn.bottomAnchor constant:8],
        [self.closeBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [self.closeBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [self.closeBtn.heightAnchor constraintEqualToConstant:38],
        [card.bottomAnchor constraintEqualToAnchor:self.closeBtn.bottomAnchor constant:18],
    ]];
}
- (void)setProgress:(float)p label:(NSString *)label {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.bar setProgress:MAX(0, MIN(1, p)) animated:YES];
        self.percentLabel.text = label ?: [NSString stringWithFormat:@"%.0f%%", p * 100];
    });
}
- (void)appendLog:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"HH:mm:ss";
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [f stringFromDate:[NSDate date]], msg];
        self.logView.text = [self.logView.text stringByAppendingString:line];
        if (self.logView.text.length)
            [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length - 1, 1)];
    });
}
- (void)finish:(BOOL)ok message:(NSString *)msg link:(NSString *)link {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setProgress:1.0 label:ok ? @"Done" : @"Failed"];
        self.percentLabel.textColor = ok
            ? [UIColor colorWithRed:0.25 green:0.88 blue:0.45 alpha:1]
            : [UIColor colorWithRed:0.90 green:0.28 blue:0.28 alpha:1];
        if (msg.length) [self appendLog:msg];
        self.uploadedLink = link;
        if (link.length) self.openLinkBtn.hidden = NO;
        self.closeBtn.hidden = NO;
        self.closeBtn.backgroundColor = ok
            ? [UIColor colorWithWhite:0.22 alpha:1]
            : [UIColor colorWithRed:0.55 green:0.14 blue:0.14 alpha:1];
    });
}
- (void)openLink {
    NSURL *url = [NSURL URLWithString:self.uploadedLink];
    if (!url) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}
- (void)dismiss {
    [UIView animateWithDuration:0.18 animations:^{ self.alpha = 0; }
                     completion:^(BOOL _){ [self removeFromSuperview]; }];
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKKeyAuthOverlay
// FIX: showInView now receives UIWindow directly from caller
// ─────────────────────────────────────────────────────────────────────────────
@interface SKKeyAuthOverlay : UIView
+ (instancetype)showInView:(UIView *)parent completion:(void (^)(NSString *key))completion;
@end

@implementation SKKeyAuthOverlay {
    UITextField             *_keyField;
    UIButton                *_activateBtn;
    UILabel                 *_statusLabel;
    UIActivityIndicatorView *_spinner;
    UIImageView             *_appIconView;
    UILabel                 *_downloadLabel;
    void (^_completion)(NSString *);
}

+ (instancetype)showInView:(UIView *)parent completion:(void (^)(NSString *))completion {
    SKKeyAuthOverlay *o = [[SKKeyAuthOverlay alloc] initWithFrame:parent.bounds];
    o.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // FIX: ensure touches aren't swallowed by game view
    o.userInteractionEnabled = YES;
    o->_completion = [completion copy];
    [parent addSubview:o];
    [parent bringSubviewToFront:o];
    o.alpha = 0;
    [UIView animateWithDuration:0.25 animations:^{ o.alpha = 1; }];
    return o;
}

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f]; if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.88];
    self.userInteractionEnabled = YES;
    [self buildUI];
    return self;
}

- (void)buildUI {
    UIView *card = [UIView new];
    card.backgroundColor    = [UIColor colorWithRed:0.07 green:0.07 blue:0.12 alpha:1];
    card.layer.cornerRadius = 20;
    card.layer.shadowColor  = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.9; card.layer.shadowRadius = 22;
    card.layer.shadowOffset  = CGSizeMake(0, 8);
    card.clipsToBounds = NO;
    card.userInteractionEnabled = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:card];

    _appIconView = [[UIImageView alloc] init];
    _appIconView.contentMode = UIViewContentModeScaleAspectFit;
    _appIconView.clipsToBounds = YES; _appIconView.hidden = YES;
    _appIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_appIconView];

    _downloadLabel = [UILabel new];
    _downloadLabel.text = @""; _downloadLabel.textColor = [UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:0.70];
    _downloadLabel.font = [UIFont systemFontOfSize:9]; _downloadLabel.textAlignment = NSTextAlignmentCenter;
    _downloadLabel.numberOfLines = 1; _downloadLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_downloadLabel];

    NSString *iconCachePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/SKToolsIcon.png"];
    UIImageView * __unsafe_unretained weakIconView = _appIconView;
    UILabel     * __unsafe_unretained weakDLLabel  = _downloadLabel;
    UIImage *cachedImg = [[NSFileManager defaultManager] fileExistsAtPath:iconCachePath]
        ? [UIImage imageWithContentsOfFile:iconCachePath] : nil;
    if (cachedImg) {
        _appIconView.image = cachedImg; _appIconView.hidden = NO;
        startSpinAnimation(_appIconView.layer);
    } else {
        _downloadLabel.text = @"Downloading asset…";
        NSURL *breadURL = [NSURL URLWithString:@"https://raw.githubusercontent.com/installdot/buildv4/refs/heads/main/breadd.png"];
        [[makeSession() dataTaskWithURL:breadURL completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
            if (!data || e) return;
            UIImage *img = [UIImage imageWithData:data]; if (!img) return;
            NSData *pngData = UIImagePNGRepresentation(img);
            if (pngData) [pngData writeToFile:iconCachePath atomically:YES];
            dispatch_async(dispatch_get_main_queue(), ^{
                UIImageView *iconView = weakIconView; UILabel *dlLabel = weakDLLabel;
                if (!iconView) return;
                dlLabel.text = @""; iconView.image = img; iconView.hidden = NO;
                startSpinAnimation(iconView.layer);
            });
        }] resume];
    }

    // FIX: use loadCachedUDID() — persistentDeviceID() was removed in v12
    NSString *udid = loadCachedUDID();
    UILabel *udidBadge = [UILabel new];
    udidBadge.text = udid ? [NSString stringWithFormat:@"UDID: %@…%@",
        [udid substringToIndex:8], [udid substringFromIndex:32]] : @"";
    udidBadge.textColor = [UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:0.55];
    udidBadge.font = [UIFont fontWithName:@"Courier" size:8] ?: [UIFont systemFontOfSize:8];
    udidBadge.textAlignment = NSTextAlignmentCenter;
    udidBadge.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:udidBadge];

    UILabel *title = [UILabel new];
    title.text = @"iSKE - Key System"; title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:17]; title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:title];

    UILabel *sub = [UILabel new];
    sub.text = @"Enter your key to continue";
    sub.textColor = [UIColor colorWithWhite:0.45 alpha:1];
    sub.font = [UIFont systemFontOfSize:12]; sub.textAlignment = NSTextAlignmentCenter;
    sub.numberOfLines = 2; sub.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:sub];

    _keyField = [UITextField new];
    _keyField.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
    _keyField.textColor = [UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:1];
    _keyField.font = [UIFont fontWithName:@"Courier" size:15] ?: [UIFont systemFontOfSize:15];
    _keyField.textAlignment = NSTextAlignmentCenter;
    _keyField.layer.cornerRadius = 10;
    _keyField.layer.borderColor  = [UIColor colorWithWhite:0.20 alpha:1].CGColor;
    _keyField.layer.borderWidth  = 1;
    _keyField.keyboardType = UIKeyboardTypeASCIICapable;
    _keyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _keyField.autocorrectionType = UITextAutocorrectionTypeNo;
    _keyField.spellCheckingType  = UITextSpellCheckingTypeNo;
    NSDictionary *phAttrs = @{
        NSForegroundColorAttributeName: [UIColor colorWithWhite:0.30 alpha:1],
        NSFontAttributeName: [UIFont fontWithName:@"Courier" size:15] ?: [UIFont systemFontOfSize:15],
    };
    _keyField.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:@"XXXX-XXXX-XXXX-XXXX" attributes:phAttrs];
    _keyField.translatesAutoresizingMaskIntoConstraints = NO;
    [_keyField addTarget:self action:@selector(keyFieldChanged) forControlEvents:UIControlEventEditingChanged];
    [_keyField addTarget:self action:@selector(tapActivate) forControlEvents:UIControlEventEditingDidEndOnExit];
    UIView *lpad = [[UIView alloc] initWithFrame:CGRectMake(0,0,12,1)];
    UIView *rpad = [[UIView alloc] initWithFrame:CGRectMake(0,0,12,1)];
    _keyField.leftView = lpad; _keyField.rightView = rpad;
    _keyField.leftViewMode = UITextFieldViewModeAlways; _keyField.rightViewMode = UITextFieldViewModeAlways;
    [card addSubview:_keyField];

    _statusLabel = [UILabel new];
    _statusLabel.text = @""; _statusLabel.textColor = [UIColor colorWithRed:0.90 green:0.35 blue:0.35 alpha:1];
    _statusLabel.font = [UIFont systemFontOfSize:11]; _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.numberOfLines = 3; _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_statusLabel];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color = [UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];
    _spinner.hidden = YES; _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_spinner];

    _activateBtn = makeSymBtn(@"Activate", @"checkmark.circle",
        [UIColor colorWithRed:0.14 green:0.52 blue:0.28 alpha:1], nil, nil);
    [_activateBtn addTarget:self action:@selector(tapActivate) forControlEvents:UIControlEventTouchUpInside];
    [_activateBtn setTitleColor:[UIColor colorWithWhite:0.7 alpha:1] forState:UIControlStateDisabled];
    [card addSubview:_activateBtn];

    UILabel *footer = [UILabel new];
    footer.text = @"Dylib By Mochi — v2.1"; footer.textColor = [UIColor colorWithWhite:0.22 alpha:1];
    footer.font = [UIFont systemFontOfSize:10]; footer.textAlignment = NSTextAlignmentCenter;
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:footer];

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-30],
        [card.widthAnchor   constraintEqualToConstant:300],
        [_appIconView.topAnchor constraintEqualToAnchor:card.topAnchor constant:28],
        [_appIconView.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [_appIconView.widthAnchor constraintEqualToConstant:50],
        [_appIconView.heightAnchor constraintEqualToConstant:50],
        [_downloadLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:42],
        [_downloadLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:10],
        [_downloadLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10],
        [udidBadge.topAnchor constraintEqualToAnchor:_appIconView.bottomAnchor constant:6],
        [udidBadge.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:10],
        [udidBadge.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10],
        [title.topAnchor constraintEqualToAnchor:udidBadge.bottomAnchor constant:8],
        [title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [sub.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [sub.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [_keyField.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:20],
        [_keyField.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [_keyField.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [_keyField.heightAnchor constraintEqualToConstant:46],
        [_statusLabel.topAnchor constraintEqualToAnchor:_keyField.bottomAnchor constant:8],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [_spinner.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:8],
        [_spinner.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [_activateBtn.topAnchor constraintEqualToAnchor:_spinner.bottomAnchor constant:10],
        [_activateBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [_activateBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [_activateBtn.heightAnchor constraintEqualToConstant:46],
        [footer.topAnchor constraintEqualToAnchor:_activateBtn.bottomAnchor constant:14],
        [footer.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [card.bottomAnchor constraintEqualToAnchor:footer.bottomAnchor constant:18],
    ]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(bgTap)];
    tap.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tap];
}

- (void)bgTap { [_keyField resignFirstResponder]; }
- (void)keyFieldChanged { _statusLabel.text = @""; }

- (void)tapActivate {
    NSString *key = [_keyField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (key.length < 4) { _statusLabel.text = @"Please enter your activation key."; return; }
    [_keyField resignFirstResponder];
    [self setLoading:YES];

    UIImageView * __unsafe_unretained weakIconView = _appIconView;
    performKeyAuth(key, ^(BOOL ok, NSTimeInterval keyExpiry, NSTimeInterval devExpiry, NSString *errorMsg) {
        [self setLoading:NO];
        if (ok) {
            saveSavedKey(key);
            gDeviceExpiry = devExpiry; gKeyExpiry = keyExpiry;
            saveDeviceExpiryLocally(devExpiry);
            UIImageView *iconView = weakIconView;
            if (iconView) [iconView.layer removeAnimationForKey:kSpinKey];
            [UIView animateWithDuration:0.2 animations:^{ self.alpha = 0; }
                             completion:^(BOOL _) {
                [self removeFromSuperview];
                if (self->_completion) self->_completion(key);
            }];
        } else {
            clearSavedKey();
            _statusLabel.text = errorMsg ?: @"Activation failed.";
            _statusLabel.textColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1];
            CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
            shake.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
            shake.duration = 0.40;
            shake.values = @[ @0, @(-7), @7, @(-6), @6, @(-4), @4, @(-2), @2, @0 ];
            [_keyField.layer addAnimation:shake forKey:@"shake"];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{ exit(0); });
        }
    });
}
- (void)setLoading:(BOOL)loading {
    _activateBtn.enabled = !loading; _keyField.enabled = !loading;
    _spinner.hidden = !loading;
    if (loading) [_spinner startAnimating]; else [_spinner stopAnimating];
    if (loading) _statusLabel.text = @"Verifying key…";
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Upload
// FIX: replaced deviceUUID() with loadCachedUDID() — deviceUUID was removed in v12
// ─────────────────────────────────────────────────────────────────────────────
static void performUpload(NSArray<NSString *> *fileNames,
                          SKProgressOverlay *ov,
                          void (^done)(NSString *link, NSString *err)) {
    // FIX: use loadCachedUDID(); fall back to new UUID if somehow missing
    NSString *uuid    = loadCachedUDID() ?: [[NSUUID UUID] UUIDString].lowercaseString;
    NSURLSession *ses = makeSession();
    NSString *docs    = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;

    [ov appendLog:@"Serialising NSUserDefaults…"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSDictionary *snap = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];

    NSError *pe = nil; NSData *pData = nil;
    @try {
        pData = [NSPropertyListSerialization dataWithPropertyList:snap
            format:NSPropertyListXMLFormat_v1_0 options:0 error:&pe];
    } @catch (NSException *ex) {
        done(nil, [NSString stringWithFormat:@"Plist serialise exception: %@", ex.reason]); return;
    }
    if (pe || !pData) {
        done(nil, [NSString stringWithFormat:@"Plist serialise error: %@",
            pe.localizedDescription ?: @"Unknown"]); return;
    }
    NSString *plistXML = [[NSString alloc] initWithData:pData encoding:NSUTF8StringEncoding];
    if (!plistXML) { done(nil, @"Plist UTF-8 conversion failed"); return; }

    if (getSetting(@"autoRij")) {
        NSString *patched = applyAutoRij(plistXML);
        if (patched == plistXML) {
            [ov appendLog:@"Auto Rij: no changes."];
        } else {
            NSUInteger delta = (NSInteger)patched.length - (NSInteger)plistXML.length;
            plistXML = patched;
            [ov appendLog:[NSString stringWithFormat:@"Auto Rij applied (Δ%ld chars).", (long)delta]];
        }
    }

    [ov appendLog:[NSString stringWithFormat:@"PlayerPrefs: %lu keys", (unsigned long)snap.count]];
    [ov appendLog:[NSString stringWithFormat:@"Will upload %lu .data file(s)", (unsigned long)fileNames.count]];
    [ov appendLog:@"Creating cloud session…"];

    MPRequest initMP = buildMP(@{@"action":@"upload", @"uuid":uuid, @"playerpref":plistXML}, nil, nil, nil);
    [ov setProgress:0.05 label:@"5%"];

    skPost(ses, initMP.req, initMP.body, ^(NSDictionary *j, NSError *err) {
        if (err) { done(nil, [NSString stringWithFormat:@"Init failed: %@", err.localizedDescription]); return; }
        NSString *link = j[@"link"] ?: [NSString stringWithFormat:
            @"https://chillysilly.frfrnocap.men/iske.php?view=%@", uuid];
        [ov appendLog:@"Session created"];
        [ov appendLog:[NSString stringWithFormat:@"Link: %@", link]];
        saveSessionUUID(uuid);
        if (!fileNames.count) { done(link, nil); return; }
        [ov appendLog:@"Uploading .data files (parallel)…"];
        NSUInteger total = fileNames.count;
        __block NSUInteger doneN = 0, failN = 0;
        dispatch_group_t group = dispatch_group_create();
        for (NSString *fname in fileNames) {
            NSString *path = [docs stringByAppendingPathComponent:fname];
            NSString *textContent = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            if (!textContent) {
                [ov appendLog:[NSString stringWithFormat:@"Skip %@ (unreadable)", fname]];
                @synchronized(fileNames) { doneN++; failN++; }
                float p = 0.1f + 0.88f * ((float)doneN / (float)total);
                [ov setProgress:p label:[NSString stringWithFormat:@"%lu/%lu", (unsigned long)doneN, (unsigned long)total]];
                continue;
            }
            NSData *fdata = [textContent dataUsingEncoding:NSUTF8StringEncoding];
            [ov appendLog:[NSString stringWithFormat:@"Uploading %@  (%lu chars)", fname, (unsigned long)textContent.length]];
            dispatch_group_enter(group);
            MPRequest fmp = buildMP(@{@"action":@"upload_file",@"uuid":uuid}, @"datafile", fname, fdata);
            skPost(ses, fmp.req, fmp.body, ^(NSDictionary *fj, NSError *ferr) {
                @synchronized(fileNames) { doneN++; }
                if (ferr) {
                    @synchronized(fileNames) { failN++; }
                    [ov appendLog:[NSString stringWithFormat:@"Failed %@: %@", fname, ferr.localizedDescription]];
                } else {
                    [ov appendLog:[NSString stringWithFormat:@"Done %@", fname]];
                }
                float p = 0.10f + 0.88f * ((float)doneN / (float)total);
                [ov setProgress:p label:[NSString stringWithFormat:@"%lu/%lu", (unsigned long)doneN, (unsigned long)total]];
                dispatch_group_leave(group);
            });
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (failN > 0)
                [ov appendLog:[NSString stringWithFormat:@"%lu file(s) failed, %lu succeeded",
                    (unsigned long)failN, (unsigned long)(total - failN)]];
            done(link, nil);
        });
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Smart-diff batched NSUserDefaults writer
// ─────────────────────────────────────────────────────────────────────────────
static const NSUInteger kUDWriteBatchSize = 100;

static BOOL plistValuesEqual(id a, id b) {
    if (a == b) return YES; if (!a || !b) return NO;
    if ([a isKindOfClass:[NSDictionary class]] && [b isKindOfClass:[NSDictionary class]]) {
        NSDictionary *da = a, *db = b;
        if (da.count != db.count) return NO;
        for (NSString *k in da) if (!plistValuesEqual(da[k], db[k])) return NO;
        return YES;
    }
    if ([a isKindOfClass:[NSArray class]] && [b isKindOfClass:[NSArray class]]) {
        NSArray *aa = a, *ab = b;
        if (aa.count != ab.count) return NO;
        for (NSUInteger i = 0; i < aa.count; i++) if (!plistValuesEqual(aa[i], ab[i])) return NO;
        return YES;
    }
    return [a isEqual:b];
}
static NSDictionary *udDiff(NSDictionary *live, NSDictionary *incoming) {
    NSMutableDictionary *diff = [NSMutableDictionary dictionary];
    [incoming enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *_) {
        if (!plistValuesEqual(live[k], v)) diff[k] = v;
    }];
    [live enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *_) {
        if (!incoming[k]) diff[k] = [NSNull null];
    }];
    return diff;
}
static void _applyDiffBatch(NSUserDefaults *ud,
                             NSArray<NSString *> *keys,
                             NSDictionary *diff,
                             NSUInteger start, NSUInteger total,
                             SKProgressOverlay *ov,
                             void (^completion)(NSUInteger changed)) {
    if (start >= total) {
        @try { [ud synchronize]; } @catch (NSException *ex) {}
        completion(total); return;
    }
    @autoreleasepool {
        NSUInteger end = MIN(start + kUDWriteBatchSize, total);
        for (NSUInteger i = start; i < end; i++) {
            NSString *k = keys[i]; id v = diff[k]; if (!k || !v) continue;
            @try {
                if ([v isKindOfClass:[NSNull class]]) [ud removeObjectForKey:k];
                else                                  [ud setObject:v forKey:k];
            } @catch (NSException *ex) {}
        }
        if (ov && (start == 0 || (end % 500 == 0) || end == total)) {
            [ov appendLog:[NSString stringWithFormat:@"  PlayerPrefs diff %lu/%lu…", (unsigned long)end, (unsigned long)total]];
            [ov setProgress:0.10f + 0.28f * ((float)end / (float)total)
                      label:[NSString stringWithFormat:@"%lu/%lu", (unsigned long)end, (unsigned long)total]];
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        _applyDiffBatch(ud, keys, diff, start + kUDWriteBatchSize, total, ov, completion);
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Write .data files
// ─────────────────────────────────────────────────────────────────────────────
static void writeDataFiles(NSDictionary *dataMap, SKProgressOverlay *ov,
                            void (^done)(NSUInteger appliedCount)) {
    NSString *docsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![dataMap isKindOfClass:[NSDictionary class]] || !dataMap.count) {
        [ov appendLog:@"No .data files to write."]; done(0); return;
    }
    NSUInteger fileTotal = dataMap.count;
    __block NSUInteger fi = 0, applied = 0;
    for (NSString *fname in dataMap) {
        id rawValue = dataMap[fname];
        if (![rawValue isKindOfClass:[NSString class]] || !((NSString *)rawValue).length) {
            [ov appendLog:[NSString stringWithFormat:@"Empty/invalid, skipped: %@", fname]];
            fi++; continue;
        }
        NSString *textContent = (NSString *)rawValue;
        NSString *safeName    = [fname lastPathComponent];
        NSString *dst         = [docsPath stringByAppendingPathComponent:safeName];
        [fm removeItemAtPath:dst error:nil];
        NSError *we = nil;
        BOOL ok = [textContent writeToFile:dst atomically:YES encoding:NSUTF8StringEncoding error:&we];
        if (ok) {
            applied++;
            [ov appendLog:[NSString stringWithFormat:@"Written %@  (%lu chars)", safeName, (unsigned long)textContent.length]];
        } else {
            [ov appendLog:[NSString stringWithFormat:@"Write failed %@: %@", safeName, we.localizedDescription ?: @"Unknown"]];
        }
        fi++;
        [ov setProgress:0.40f + 0.58f * ((float)fi / MAX(1.0f, (float)fileTotal))
                  label:[NSString stringWithFormat:@"%lu/%lu", (unsigned long)fi, (unsigned long)fileTotal]];
    }
    done(applied);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Load
// ─────────────────────────────────────────────────────────────────────────────
static void performLoad(SKProgressOverlay *ov, void (^done)(BOOL ok, NSString *msg)) {
    NSString *uuid = loadSessionUUID();
    if (!uuid.length) { done(NO, @"No session found. Upload first."); return; }
    NSURLSession *ses = makeSession();
    [ov appendLog:[NSString stringWithFormat:@"Session: %@…",
        [uuid substringToIndex:MIN(8u, (unsigned)uuid.length)]]];
    [ov appendLog:@"Requesting files from server…"];
    [ov setProgress:0.08 label:@"8%"];

    MPRequest mp = buildMP(@{@"action":@"load", @"uuid":uuid}, nil, nil, nil);
    skPost(ses, mp.req, mp.body, ^(NSDictionary *j, NSError *err) {
        if (err) { done(NO, [NSString stringWithFormat:@"Load failed: %@", err.localizedDescription]); return; }
        if ([j[@"changed"] isEqual:@NO] || [j[@"changed"] isEqual:@0]) {
            clearSessionUUID(); done(YES, @"Server reports no changes. Nothing applied."); return;
        }
        [ov setProgress:0.10 label:@"10%"];
        NSString *ppXML       = j[@"playerpref"];
        NSDictionary *dataMap = j[@"data"];
        if (!ppXML.length) {
            [ov appendLog:@"No PlayerPrefs — writing .data files only."];
            writeDataFiles(dataMap, ov, ^(NSUInteger applied) {
                clearSessionUUID();
                done(YES, [NSString stringWithFormat:@"Loaded %lu file(s). Restart game.", (unsigned long)applied]);
            }); return;
        }
        [ov appendLog:@"Parsing PlayerPrefs…"];
        NSError *pe = nil; NSDictionary *incoming = nil;
        @try {
            incoming = [NSPropertyListSerialization
                propertyListWithData:[ppXML dataUsingEncoding:NSUTF8StringEncoding]
                             options:NSPropertyListMutableContainersAndLeaves
                              format:nil error:&pe];
        } @catch (NSException *ex) { incoming = nil; }
        if (pe || ![incoming isKindOfClass:[NSDictionary class]]) {
            [ov appendLog:@"PlayerPrefs parse failed. Continuing with .data files only…"];
            writeDataFiles(dataMap, ov, ^(NSUInteger applied) {
                clearSessionUUID();
                done(applied > 0,
                    applied > 0
                    ? [NSString stringWithFormat:@"PlayerPrefs failed, %lu file(s) applied. Restart.", (unsigned long)applied]
                    : @"PlayerPrefs parse failed and no .data files written.");
            }); return;
        }
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud synchronize];
        NSDictionary *live = [ud dictionaryRepresentation];
        NSDictionary *diff = udDiff(live, incoming);
        if (!diff.count) {
            [ov appendLog:@"PlayerPrefs unchanged — skipping."];
            [ov setProgress:0.40 label:@"40%"];
            writeDataFiles(dataMap, ov, ^(NSUInteger filesApplied) {
                clearSessionUUID();
                done(YES, [NSString stringWithFormat:
                    @"PlayerPrefs identical (skipped), %lu file(s) applied. Restart.",
                    (unsigned long)filesApplied]);
            }); return;
        }
        NSArray<NSString *> *diffKeys = [diff allKeys];
        NSUInteger total = diffKeys.count, removes = 0;
        for (id v in [diff allValues]) if ([v isKindOfClass:[NSNull class]]) removes++;
        [ov appendLog:[NSString stringWithFormat:
            @"PlayerPrefs diff: %lu set, %lu remove (of %lu total keys)",
            (unsigned long)(total-removes), (unsigned long)removes, (unsigned long)live.count]];
        _applyDiffBatch(ud, diffKeys, diff, 0, total, ov, ^(NSUInteger changed) {
            [ov appendLog:[NSString stringWithFormat:@"PlayerPrefs done (%lu keys changed)", (unsigned long)changed]];
            writeDataFiles(dataMap, ov, ^(NSUInteger filesApplied) {
                clearSessionUUID();
                NSUInteger totalApplied = (changed > 0 ? 1 : 0) + filesApplied;
                done(YES, [NSString stringWithFormat:
                    @"Loaded %lu item(s). Restart the game.", (unsigned long)totalApplied]);
            });
        });
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKSettingsMenu
// ─────────────────────────────────────────────────────────────────────────────
static const CGFloat kSWScale = 0.75f;

@interface SKSettingsMenu : UIView
@property (nonatomic, strong, readonly) UIView *tutRijRow;
@property (nonatomic, strong, readonly) UIView *tutUidRow;
@property (nonatomic, strong, readonly) UIView *tutCloseRow;
- (void)dismiss;
@end

@implementation SKSettingsMenu {
    UIView   *_card;
    UISwitch *_rijSwitch;
    UISwitch *_uidSwitch;
    UISwitch *_closeSwitch;
    UIView   *_tutRijRow;
    UIView   *_tutUidRow;
    UIView   *_tutCloseRow;
}

@synthesize tutRijRow   = _tutRijRow;
@synthesize tutUidRow   = _tutUidRow;
@synthesize tutCloseRow = _tutCloseRow;

+ (instancetype)showInView:(UIView *)parent {
    SKSettingsMenu *m = [[SKSettingsMenu alloc] initWithFrame:parent.bounds];
    m.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [parent addSubview:m];
    m.alpha = 0;
    [UIView animateWithDuration:0.22 animations:^{ m.alpha = 1; }];
    return m;
}
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.68];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(bgTap:)];
    tap.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tap];
    [self buildUI];
    return self;
}
- (void)bgTap:(UITapGestureRecognizer *)g {
    CGPoint pt = [g locationInView:self];
    if (_card && !CGRectContainsPoint(_card.frame, pt)) [self dismiss];
}
- (UIView *)rowWithTitle:(NSString *)title description:(NSString *)desc
                  symName:(NSString *)symName
                  swRef:(__strong UISwitch **)swRef tag:(NSInteger)tag {
    UIView *row = [UIView new];
    row.backgroundColor    = [UIColor colorWithRed:0.12 green:0.12 blue:0.18 alpha:1];
    row.layer.cornerRadius = 10; row.clipsToBounds = YES;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    CGFloat swNativeW = 51.0f, swNativeH = 31.0f;
    CGFloat swContW = swNativeW * kSWScale, swContH = swNativeH * kSWScale;
    UIView *swCont = [UIView new];
    swCont.clipsToBounds = NO; swCont.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:swCont];
    UISwitch *sw = [UISwitch new];
    sw.onTintColor = [UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];
    sw.tag = tag;
    sw.transform = CGAffineTransformMakeScale(kSWScale, kSWScale);
    sw.frame = CGRectMake((swContW-swNativeW)*0.5f,(swContH-swNativeH)*0.5f,swNativeW,swNativeH);
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [swCont addSubview:sw]; *swRef = sw;

    UIImageView *icon = symView(symName, 13, [UIColor colorWithWhite:0.55 alpha:1]);
    [row addSubview:icon];

    UILabel *nameL = [UILabel new];
    nameL.text = title; nameL.textColor = [UIColor whiteColor];
    nameL.font = [UIFont boldSystemFontOfSize:12];
    nameL.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:nameL];
    UILabel *descL = [UILabel new];
    descL.text = desc; descL.textColor = [UIColor colorWithWhite:0.45 alpha:1];
    descL.font = [UIFont systemFontOfSize:9.5]; descL.numberOfLines = 0;
    descL.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:descL];
    [NSLayoutConstraint activateConstraints:@[
        [swCont.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [swCont.centerYAnchor  constraintEqualToAnchor:row.centerYAnchor],
        [swCont.widthAnchor    constraintEqualToConstant:swContW],
        [swCont.heightAnchor   constraintEqualToConstant:swContH],
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12],
        [icon.topAnchor     constraintEqualToAnchor:row.topAnchor constant:12],
        [icon.widthAnchor   constraintEqualToConstant:16],
        [icon.heightAnchor  constraintEqualToConstant:16],
        [nameL.leadingAnchor  constraintEqualToAnchor:icon.trailingAnchor constant:8],
        [nameL.topAnchor      constraintEqualToAnchor:row.topAnchor constant:10],
        [nameL.trailingAnchor constraintLessThanOrEqualToAnchor:swCont.leadingAnchor constant:-8],
        [descL.leadingAnchor  constraintEqualToAnchor:icon.trailingAnchor constant:8],
        [descL.topAnchor      constraintEqualToAnchor:nameL.bottomAnchor constant:3],
        [descL.trailingAnchor constraintLessThanOrEqualToAnchor:swCont.leadingAnchor constant:-8],
        [row.bottomAnchor     constraintEqualToAnchor:descL.bottomAnchor constant:10],
    ]];
    return row;
}
- (void)buildUI {
    _card = [UIView new];
    _card.backgroundColor    = [UIColor colorWithRed:0.07 green:0.07 blue:0.11 alpha:1];
    _card.layer.cornerRadius = 18; _card.clipsToBounds = YES;
    _card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_card];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(cardPan:)];
    [_card addGestureRecognizer:pan];
    UIView *handle = [UIView new];
    handle.backgroundColor    = [UIColor colorWithWhite:0.32 alpha:0.7];
    handle.layer.cornerRadius = 2; handle.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:handle];

    UIImageView *settingsIcon = symView(@"gearshape.fill", 15,
        [UIColor colorWithWhite:0.70 alpha:1]);
    UILabel *titleL = [UILabel new];
    titleL.text = @"Settings"; titleL.textColor = [UIColor whiteColor];
    titleL.font = [UIFont boldSystemFontOfSize:15]; titleL.textAlignment = NSTextAlignmentCenter;
    titleL.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *titleRow = [[UIStackView alloc] initWithArrangedSubviews:@[settingsIcon, titleL]];
    titleRow.axis    = UILayoutConstraintAxisHorizontal;
    titleRow.spacing = 6;
    titleRow.alignment = UIStackViewAlignmentCenter;
    titleRow.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:titleRow];

    UIView *div = [UIView new];
    div.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
    div.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:div];

    UIView *rijRow = [self rowWithTitle:@"Auto Rij"
        description:@"Before uploading, sets all OpenRijTest_ flags from 1 to 0 in PlayerPrefs."
        symName:@"wand.and.stars"
        swRef:&_rijSwitch tag:1];
    [_card addSubview:rijRow];
    _tutRijRow = rijRow;

    UIView *uidRow = [self rowWithTitle:@"Auto Detect UID"
        description:@"Reads PlayerId from SdkStateCache#1 — no manual UID entry needed."
        symName:@"person.badge.key"
        swRef:&_uidSwitch tag:2];
    [_card addSubview:uidRow];
    _tutUidRow = uidRow;

    UIView *closeRow = [self rowWithTitle:@"Auto Close"
        description:@"Terminates the app once save data has finished loading from cloud."
        symName:@"power"
        swRef:&_closeSwitch tag:3];
    [_card addSubview:closeRow];
    _tutCloseRow = closeRow;

    UIButton *closeBtn = makeSymBtn(@"Close", @"xmark",
        [UIColor colorWithWhite:0.20 alpha:1], @selector(dismiss), self);
    [_card addSubview:closeBtn];

    UILabel *footer = [UILabel new];
    footer.text          = @"Dylib By Mochi - Version: 2.1 - Build: 271.ef2ca7";
    footer.textColor     = [UIColor colorWithWhite:0.28 alpha:1];
    footer.font          = [UIFont systemFontOfSize:8.5];
    footer.textAlignment = NSTextAlignmentCenter;
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:footer];

    [NSLayoutConstraint activateConstraints:@[
        [_card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_card.widthAnchor   constraintEqualToConstant:320],
        [handle.topAnchor     constraintEqualToAnchor:_card.topAnchor constant:8],
        [handle.centerXAnchor constraintEqualToAnchor:_card.centerXAnchor],
        [handle.widthAnchor   constraintEqualToConstant:36],
        [handle.heightAnchor  constraintEqualToConstant:4],
        [titleRow.topAnchor      constraintEqualToAnchor:handle.bottomAnchor constant:8],
        [titleRow.centerXAnchor  constraintEqualToAnchor:_card.centerXAnchor],
        [settingsIcon.widthAnchor constraintEqualToConstant:18],
        [settingsIcon.heightAnchor constraintEqualToConstant:18],
        [div.topAnchor      constraintEqualToAnchor:titleRow.bottomAnchor constant:10],
        [div.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:12],
        [div.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-12],
        [div.heightAnchor   constraintEqualToConstant:1],
        [rijRow.topAnchor      constraintEqualToAnchor:div.bottomAnchor constant:10],
        [rijRow.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:10],
        [rijRow.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],
        [uidRow.topAnchor      constraintEqualToAnchor:rijRow.bottomAnchor constant:8],
        [uidRow.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:10],
        [uidRow.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],
        [closeRow.topAnchor      constraintEqualToAnchor:uidRow.bottomAnchor constant:8],
        [closeRow.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:10],
        [closeRow.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],
        [closeBtn.topAnchor      constraintEqualToAnchor:closeRow.bottomAnchor constant:14],
        [closeBtn.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:14],
        [closeBtn.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-14],
        [closeBtn.heightAnchor   constraintEqualToConstant:38],
        [footer.topAnchor      constraintEqualToAnchor:closeBtn.bottomAnchor constant:10],
        [footer.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:8],
        [footer.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-8],
        [_card.bottomAnchor    constraintEqualToAnchor:footer.bottomAnchor constant:14],
    ]];
    [self refreshSwitches];
}
- (void)cardPan:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        CGRect cur = _card.frame;
        for (NSLayoutConstraint *c in self.constraints)
            if (c.firstItem == _card || c.secondItem == _card) c.active = NO;
        _card.translatesAutoresizingMaskIntoConstraints = YES;
        _card.frame = cur;
    }
    CGPoint delta = [g translationInView:self];
    CGRect f = _card.frame;
    CGFloat nx = MAX(0, MIN(self.bounds.size.width  - f.size.width,  f.origin.x + delta.x));
    CGFloat ny = MAX(0, MIN(self.bounds.size.height - f.size.height, f.origin.y + delta.y));
    _card.frame = CGRectMake(nx, ny, f.size.width, f.size.height);
    [g setTranslation:CGPointZero inView:self];
}
- (void)refreshSwitches {
    _rijSwitch.on   = getSetting(@"autoRij");
    _uidSwitch.on   = getSetting(@"autoDetectUID");
    _closeSwitch.on = getSetting(@"autoClose");
}
- (void)switchChanged:(UISwitch *)sw {
    NSString *key;
    switch (sw.tag) {
        case 1: key = @"autoRij";       break;
        case 2: key = @"autoDetectUID"; break;
        case 3: key = @"autoClose";     break;
        default: return;
    }
    setSetting(key, sw.isOn);
    [UIView animateWithDuration:0.07 animations:^{ sw.alpha = 0.25f; }
                     completion:^(BOOL _) {
        [UIView animateWithDuration:0.07 animations:^{ sw.alpha = 1.0f; }];
    }];
}
- (void)dismiss {
    [UIView animateWithDuration:0.18 animations:^{ self.alpha = 0; }
                     completion:^(BOOL _){ [self removeFromSuperview]; }];
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Forward declarations
// ─────────────────────────────────────────────────────────────────────────────
@class SKPanel;
@interface SKTutorialOverlay : UIView
+ (void)showForPanel:(SKPanel *)panel inView:(UIView *)parent;
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKPanel
// ─────────────────────────────────────────────────────────────────────────────
static const CGFloat kPW = 258;
static const CGFloat kBH = 46;
static const CGFloat kCH = 192;

@interface SKPanel : UIView
@property (nonatomic, strong) UIView   *content;
@property (nonatomic, strong) UILabel  *statusLabel;
@property (nonatomic, strong) UILabel  *uidLabel;
@property (nonatomic, strong) UILabel  *expiryLabel;
@property (nonatomic, strong) UIButton *uploadBtn;
@property (nonatomic, strong) UIButton *loadBtn;
@property (nonatomic, strong) UIButton *settingsBtn;
@property (nonatomic, assign) BOOL     expanded;
@property (nonatomic, strong) NSTimer  *expiryTimer;
- (void)refreshStatus;
@end

@implementation SKPanel

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, kPW, kBH)];
    if (!self) return nil;
    self.clipsToBounds      = NO;
    self.layer.cornerRadius = 12;
    self.backgroundColor    = [UIColor colorWithRed:0.06 green:0.06 blue:0.09 alpha:0.96];
    self.layer.shadowColor   = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.82;
    self.layer.shadowRadius  = 9;
    self.layer.shadowOffset  = CGSizeMake(0, 3);
    self.layer.zPosition     = 9999;
    [self buildBar];
    [self buildContent];
    [self addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(onPan:)]];
    return self;
}

- (void)buildBar {
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(kPW/2-20, 7, 40, 3)];
    h.backgroundColor    = [UIColor colorWithWhite:0.45 alpha:0.5];
    h.layer.cornerRadius = 1.5;
    [self addSubview:h];

    UIImageView *gearIcon = [[UIImageView alloc] initWithImage:sym(@"square.stack.3d.up.fill", 11)];
    gearIcon.tintColor    = [UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:1];
    gearIcon.contentMode  = UIViewContentModeScaleAspectFit;
    gearIcon.frame        = CGRectMake(12, 14, 16, 16);
    [self addSubview:gearIcon];

    UILabel *t = [UILabel new];
    t.text = @"iSKE - Panel";
    t.textColor = [UIColor colorWithWhite:0.82 alpha:1];
    t.font = [UIFont boldSystemFontOfSize:12];
    t.textAlignment = NSTextAlignmentCenter;
    t.frame = CGRectMake(0, 14, kPW, 18);
    t.userInteractionEnabled = NO;
    [self addSubview:t];

    UIView *tz = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPW, kBH)];
    tz.backgroundColor = UIColor.clearColor;
    [tz addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(togglePanel)]];
    [self addSubview:tz];
}

- (void)buildContent {
    self.content = [[UIView alloc] initWithFrame:CGRectMake(0, kBH, kPW, kCH)];
    self.content.hidden = YES; self.content.alpha = 0; self.content.clipsToBounds = YES;
    [self addSubview:self.content];

    CGFloat pad = 9, w = kPW - pad * 2;

    self.statusLabel = [UILabel new];
    self.statusLabel.frame         = CGRectMake(pad, 4, w, 12);
    self.statusLabel.font          = [UIFont systemFontOfSize:9.5];
    self.statusLabel.textColor     = [UIColor colorWithWhite:0.44 alpha:1];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.content addSubview:self.statusLabel];

    self.uidLabel = [UILabel new];
    self.uidLabel.frame         = CGRectMake(pad, 18, w, 12);
    self.uidLabel.font          = [UIFont fontWithName:@"Courier" size:9] ?: [UIFont systemFontOfSize:9];
    self.uidLabel.textColor     = [UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:1];
    self.uidLabel.textAlignment = NSTextAlignmentCenter;
    self.uidLabel.text          = @"";
    [self.content addSubview:self.uidLabel];

    self.expiryLabel = [UILabel new];
    self.expiryLabel.frame         = CGRectMake(pad, 32, w, 12);
    self.expiryLabel.font          = [UIFont systemFontOfSize:9];
    self.expiryLabel.textColor     = [UIColor colorWithRed:0.85 green:0.70 blue:0.20 alpha:1];
    self.expiryLabel.textAlignment = NSTextAlignmentCenter;
    self.expiryLabel.text          = @"";
    [self.content addSubview:self.expiryLabel];

    self.uploadBtn = [self btn:@"Upload to Cloud"
                        symName:@"icloud.and.arrow.up"
                          color:[UIColor colorWithRed:0.14 green:0.56 blue:0.92 alpha:1]
                          frame:CGRectMake(pad, 50, w, 42)
                         action:@selector(tapUpload)];
    [self.content addSubview:self.uploadBtn];

    self.loadBtn = [self btn:@"Load from Cloud"
                      symName:@"icloud.and.arrow.down"
                        color:[UIColor colorWithRed:0.18 green:0.70 blue:0.42 alpha:1]
                        frame:CGRectMake(pad, 98, w, 42)
                       action:@selector(tapLoad)];
    [self.content addSubview:self.loadBtn];

    CGFloat halfW = (w - 6) / 2;
    self.settingsBtn = [self btn:@"Settings"
                         symName:@"gearshape"
                           color:[UIColor colorWithRed:0.22 green:0.22 blue:0.30 alpha:1]
                           frame:CGRectMake(pad, 148, halfW, 30)
                          action:@selector(tapSettings)];
    self.settingsBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [self.content addSubview:self.settingsBtn];

    UIButton *hideBtn = [self btn:@"Hide"
                           symName:@"eye.slash"
                             color:[UIColor colorWithRed:0.30 green:0.12 blue:0.12 alpha:1]
                             frame:CGRectMake(pad + halfW + 6, 148, halfW, 30)
                            action:@selector(tapHide)];
    hideBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [self.content addSubview:hideBtn];

    [self refreshStatus];
    [self startExpiryTimer];
}

- (UIButton *)btn:(NSString *)title symName:(NSString *)symName
            color:(UIColor *)c frame:(CGRect)f action:(SEL)s {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f; b.backgroundColor = c; b.layer.cornerRadius = 9;
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightMedium];
    UIImage *img = [[UIImage systemImageNamed:symName withConfiguration:cfg]
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [b setImage:img forState:UIControlStateNormal];
    b.tintColor = [UIColor whiteColor];
    [b setTitle:[NSString stringWithFormat:@"  %@", title] forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:0.80 alpha:1] forState:UIControlStateHighlighted];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)startExpiryTimer {
    [self.expiryTimer invalidate];
    self.expiryTimer = [NSTimer scheduledTimerWithTimeInterval:1
        target:self selector:@selector(refreshExpiry) userInfo:nil repeats:YES];
}

- (void)refreshExpiry {
    NSTimeInterval devExpiry = gDeviceExpiry > 0 ? gDeviceExpiry : loadDeviceExpiryLocally();
    if (devExpiry <= 0) { self.expiryLabel.text = @""; return; }
    NSTimeInterval left = devExpiry - [[NSDate date] timeIntervalSince1970];
    NSString *expiryStr;
    if (left <= 0) {
        expiryStr = @"Device: EXPIRED";
    } else {
        long long d = (long long)(left / 86400);
        long long h = (long long)(fmod(left, 86400) / 3600);
        long long m = (long long)(fmod(left, 3600) / 60);
        long long s = (long long)fmod(left, 60);
        if (d > 0)      expiryStr = [NSString stringWithFormat:@"Device: %lldd %lldh %lldm left", d, h, m];
        else if (h > 0) expiryStr = [NSString stringWithFormat:@"Device: %lldh %lldm %llds left", h, m, s];
        else            expiryStr = [NSString stringWithFormat:@"Device: %lldm %llds left", m, s];
    }
    self.expiryLabel.textColor = [expiryStr hasPrefix:@"Device: EXPIRED"]
        ? [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1]
        : [UIColor colorWithRed:0.85 green:0.70 blue:0.20 alpha:1];
    self.expiryLabel.text = expiryStr;
}

- (void)refreshStatus {
    NSString *uuid = loadSessionUUID();
    self.statusLabel.text = uuid
        ? [NSString stringWithFormat:@"Session: %@…", [uuid substringToIndex:MIN(8u,(unsigned)uuid.length)]]
        : @"No active session";
    if (getSetting(@"autoDetectUID")) {
        NSString *uid = detectPlayerUID();
        self.uidLabel.text = uid ? [NSString stringWithFormat:@"UID: %@", uid] : @"UID: not found";
    } else {
        self.uidLabel.text = @"";
    }
    [self refreshExpiry];
}

- (void)togglePanel {
    self.expanded = !self.expanded;
    if (self.expanded) {
        [self refreshStatus];
        self.content.hidden = NO;
        self.content.frame  = CGRectMake(0, kBH, kPW, kCH);
        [UIView animateWithDuration:0.22 delay:0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            CGRect f = self.frame; f.size.height = kBH + kCH; self.frame = f;
            self.content.alpha = 1;
        } completion:^(BOOL _) {
            [self showTutorialIfNeeded];
        }];
    } else {
        [UIView animateWithDuration:0.18 delay:0
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
            CGRect f = self.frame; f.size.height = kBH; self.frame = f;
            self.content.alpha = 0;
        } completion:^(BOOL _){ self.content.hidden = YES; }];
    }
}

- (void)showTutorialIfNeeded {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"SKTutorialV1Shown"]) return;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"SKTutorialV1Shown"];
    UIView *parent = [self topVC].view ?: self.superview;
    if (!parent) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            [SKTutorialOverlay showForPanel:self inView:parent];
        });
}

- (void)tapSettings {
    UIView *parent = [self topVC].view ?: self.superview;
    [SKSettingsMenu showInView:parent];
}

- (void)tapHide {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Hide Menu"
                         message:@"The panel will be removed until the next app launch."
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Hide" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *_) {
            [self.expiryTimer invalidate];
            [UIView animateWithDuration:0.2 animations:^{
                self.alpha = 0; self.transform = CGAffineTransformMakeScale(0.85f, 0.85f);
            } completion:^(BOOL __) { [self removeFromSuperview]; }];
        }]];
    [[self topVC] presentViewController:a animated:YES completion:nil];
}

- (void)tapUpload {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *all = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil] ?: @[];
    NSMutableArray<NSString*> *dataFiles = [NSMutableArray new];
    for (NSString *f in all)
        if ([f.pathExtension.lowercaseString isEqualToString:@"data"])
            [dataFiles addObject:f];
    NSString *existing = loadSessionUUID();
    UIAlertController *choice = [UIAlertController
        alertControllerWithTitle:@"Select files to upload"
                         message:[NSString stringWithFormat:
            @"Found %lu .data file(s)\n%@",
            (unsigned long)dataFiles.count,
            existing ? @"Existing session will be overwritten." : @""]
                  preferredStyle:UIAlertControllerStyleAlert];
    [choice addAction:[UIAlertAction
        actionWithTitle:[NSString stringWithFormat:@"Upload All (%lu files)", (unsigned long)dataFiles.count]
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) { [self confirmAndUpload:dataFiles]; }]];
    [choice addAction:[UIAlertAction actionWithTitle:@"Specific UID…"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            if (getSetting(@"autoDetectUID")) {
                NSString *uid = detectPlayerUID();
                if (!uid.length) {
                    [self showAlert:@"Auto Detect UID" message:@"PlayerId not found.\nPlease enter UID manually."];
                    [self askUIDThenUpload:dataFiles]; return;
                }
                NSMutableArray<NSString*> *filtered = [NSMutableArray new];
                for (NSString *f in dataFiles) if ([f containsString:uid]) [filtered addObject:f];
                if (!filtered.count) {
                    [self showAlert:@"No files found"
                            message:[NSString stringWithFormat:
                        @"Auto-detected UID \"%@\" matched no .data files.", uid]]; return;
                }
                [self confirmAndUpload:filtered];
            } else { [self askUIDThenUpload:dataFiles]; }
        }]];
    [choice addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [[self topVC] presentViewController:choice animated:YES completion:nil];
}

- (void)askUIDThenUpload:(NSArray<NSString*> *)allFiles {
    UIAlertController *input = [UIAlertController
        alertControllerWithTitle:@"Enter UID"
                         message:@"Only .data files containing this UID will be uploaded."
                  preferredStyle:UIAlertControllerStyleAlert];
    [input addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"e.g. 211062956";
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [input addAction:[UIAlertAction actionWithTitle:@"Upload" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            NSString *uid = [input.textFields.firstObject.text
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!uid.length) { [self showAlert:@"No UID entered" message:@"Please enter a UID."]; return; }
            NSMutableArray<NSString*> *filtered = [NSMutableArray new];
            for (NSString *f in allFiles) if ([f containsString:uid]) [filtered addObject:f];
            if (!filtered.count) {
                [self showAlert:@"No files found"
                        message:[NSString stringWithFormat:@"No .data file contains UID \"%@\".", uid]]; return;
            }
            [self confirmAndUpload:filtered];
        }]];
    [input addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [[self topVC] presentViewController:input animated:YES completion:nil];
}

- (void)confirmAndUpload:(NSArray<NSString*> *)files {
    NSString *rijNote = getSetting(@"autoRij") ? @"\n• Auto Rij ON (OpenRijTest_ → 0)" : @"";
    NSString *msg = [NSString stringWithFormat:
        @"Are you sure?\n\nWill upload:\n• PlayerPrefs (NSUserDefaults)%@\n• %lu .data file(s):\n%@",
        rijNote, (unsigned long)files.count,
        files.count <= 6 ? [files componentsJoinedByString:@"\n"]
            : [[files subarrayWithRange:NSMakeRange(0, 6)] componentsJoinedByString:@"\n"]];
    UIAlertController *confirm = [UIAlertController
        alertControllerWithTitle:@"Confirm Upload" message:msg
        preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Upload" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            UIView *parent = [self topVC].view ?: self.superview;
            SKProgressOverlay *ov = [SKProgressOverlay showInView:parent title:@"Uploading save data…"];
            performUpload(files, ov, ^(NSString *link, NSString *err) {
                [self refreshStatus];
                if (err) {
                    [ov finish:NO message:[NSString stringWithFormat:@"Failed: %@", err] link:nil];
                } else {
                    [UIPasteboard generalPasteboard].string = link;
                    [ov appendLog:@"Link copied to clipboard."];
                    [ov finish:YES message:@"Upload complete" link:link];
                }
            });
        }]];
    [[self topVC] presentViewController:confirm animated:YES completion:nil];
}

- (void)tapLoad {
    if (!loadSessionUUID().length) {
        [self showAlert:@"No Session" message:@"No upload session found. Upload first."];
        return;
    }
    NSString *closeNote = getSetting(@"autoClose")
        ? @"\n\nAuto Close is ON — app will exit after loading." : @"";
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Load Save"
                         message:[NSString stringWithFormat:
            @"Download edited save data and apply it?\n\nCloud session is deleted after loading.%@", closeNote]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Load" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            UIView *parent = [self topVC].view ?: self.superview;
            SKProgressOverlay *ov = [SKProgressOverlay showInView:parent title:@"Loading save data…"];
            performLoad(ov, ^(BOOL ok, NSString *msg) {
                [self refreshStatus];
                [ov finish:ok message:msg link:nil];
                if (ok && getSetting(@"autoClose")) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{ exit(0); });
                }
            });
        }]];
    [[self topVC] presentViewController:alert animated:YES completion:nil];
}

- (void)showAlert:(NSString *)title message:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [[self topVC] presentViewController:a animated:YES completion:nil];
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint d  = [g translationInView:self.superview];
    CGRect  sb = self.superview.bounds;
    CGFloat nx = MAX(self.bounds.size.width/2,
                     MIN(sb.size.width  - self.bounds.size.width/2,  self.center.x + d.x));
    CGFloat ny = MAX(self.bounds.size.height/2,
                     MIN(sb.size.height - self.bounds.size.height/2, self.center.y + d.y));
    self.center = CGPointMake(nx, ny);
    [g setTranslation:CGPointZero inView:self.superview];
}

- (UIViewController *)topVC {
    UIViewController *vc = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows.reverseObjectEnumerator)
        if (!w.isHidden && w.alpha > 0 && w.rootViewController) { vc = w.rootViewController; break; }
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKWelcomeNotification
// FIX: replaced persistentDeviceID() with loadCachedUDID()
// ─────────────────────────────────────────────────────────────────────────────
@interface SKWelcomeNotification : UIView
+ (void)showInView:(UIView *)parent
            expiry:(NSTimeInterval)keyExpiry
      deviceExpiry:(NSTimeInterval)devExpiry;
@end

@implementation SKWelcomeNotification {
    NSTimer *_autoHideTimer;
    NSTimer *_countdownTimer;
    NSTimeInterval _keyExpiry;
    NSTimeInterval _devExpiry;
    UILabel *_keyExpiryLabel;
    UILabel *_devExpiryLabel;
}

+ (void)showInView:(UIView *)parent expiry:(NSTimeInterval)ke deviceExpiry:(NSTimeInterval)de {
    SKWelcomeNotification *n = [[SKWelcomeNotification alloc] initWithFrame:parent.bounds];
    n.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    n->_keyExpiry = ke;
    n->_devExpiry = de;
    [parent addSubview:n];
    [n buildUI];
    n.alpha = 0;
    [UIView animateWithDuration:0.3 delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{ n.alpha = 1; }
                     completion:nil];
    n->_autoHideTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
        target:n selector:@selector(dismiss) userInfo:nil repeats:NO];
    n->_countdownTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
        target:n selector:@selector(tickCountdown) userInfo:nil repeats:YES];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:n action:@selector(dismiss)];
    [n addGestureRecognizer:tap];
}

- (void)buildUI {
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    UIView *card = [UIView new];
    card.backgroundColor     = [UIColor colorWithRed:0.07 green:0.07 blue:0.12 alpha:1];
    card.layer.cornerRadius  = 22;
    card.layer.shadowColor   = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.92;
    card.layer.shadowRadius  = 24;
    card.layer.shadowOffset  = CGSizeMake(0, 8);
    card.clipsToBounds       = NO;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:card];

    UIImageView *iconView = [UIImageView new];
    iconView.contentMode     = UIViewContentModeScaleAspectFit;
    iconView.layer.cornerRadius = 14;
    iconView.clipsToBounds   = YES;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:iconView];

    NSString *iconCachePath = [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Caches/SKToolsIcon.png"];
    UIImage *cached = [UIImage imageWithContentsOfFile:iconCachePath];
    if (cached) {
        iconView.image = cached;
    } else {
        UIImageView * __unsafe_unretained wIcon = iconView;
        NSURL *u = [NSURL URLWithString:@"https://raw.githubusercontent.com/installdot/buildv4/refs/heads/main/breadd.png"];
        [[makeSession() dataTaskWithURL:u completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            if (!d || e) return;
            UIImage *img = [UIImage imageWithData:d];
            if (!img) return;
            NSData *pngData = UIImagePNGRepresentation(img);
            if (pngData) [pngData writeToFile:iconCachePath atomically:YES];
            dispatch_async(dispatch_get_main_queue(), ^{ if (wIcon) wIcon.image = img; });
        }] resume];
    }

    UILabel *greet = [UILabel new];
    NSString *dName = [UIDevice currentDevice].name ?: @"iPhone";
    greet.text          = [NSString stringWithFormat:@"Hello, %@", dName];
    greet.textColor     = [UIColor whiteColor];
    greet.font          = [UIFont boldSystemFontOfSize:21];
    greet.textAlignment = NSTextAlignmentCenter;
    greet.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:greet];

    UILabel *sub = [UILabel new];
    sub.text          = @"✓ Key verified successfully";
    sub.textColor     = [UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];
    sub.font          = [UIFont systemFontOfSize:13];
    sub.textAlignment = NSTextAlignmentCenter;
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:sub];

    UIView *div1 = [UIView new];
    div1.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
    div1.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:div1];

    UILabel *devIDTitle = [UILabel new];
    devIDTitle.text          = @"DEVICE ID";
    devIDTitle.textColor     = [UIColor colorWithWhite:0.38 alpha:1];
    devIDTitle.font          = [UIFont boldSystemFontOfSize:9];
    devIDTitle.textAlignment = NSTextAlignmentCenter;
    devIDTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:devIDTitle];

    UILabel *devIDVal = [UILabel new];
    // FIX: use loadCachedUDID() — persistentDeviceID() was removed in v12
    devIDVal.text          = loadCachedUDID() ?: @"—";
    devIDVal.textColor     = [UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:1];
    devIDVal.font          = [UIFont fontWithName:@"Courier" size:9.5] ?: [UIFont systemFontOfSize:9.5];
    devIDVal.textAlignment = NSTextAlignmentCenter;
    devIDVal.numberOfLines = 2;
    devIDVal.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:devIDVal];

    UIView *div2 = [UIView new];
    div2.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
    div2.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:div2];

    _keyExpiryLabel = [UILabel new];
    _keyExpiryLabel.textColor     = [UIColor colorWithRed:0.85 green:0.70 blue:0.20 alpha:1];
    _keyExpiryLabel.font          = [UIFont boldSystemFontOfSize:11];
    _keyExpiryLabel.textAlignment = NSTextAlignmentCenter;
    _keyExpiryLabel.numberOfLines = 2;
    _keyExpiryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_keyExpiryLabel];

    _devExpiryLabel = [UILabel new];
    _devExpiryLabel.textColor     = [UIColor colorWithRed:0.70 green:0.82 blue:0.95 alpha:1];
    _devExpiryLabel.font          = [UIFont systemFontOfSize:11];
    _devExpiryLabel.textAlignment = NSTextAlignmentCenter;
    _devExpiryLabel.numberOfLines = 2;
    _devExpiryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_devExpiryLabel];

    [self tickCountdown];

    UILabel *hint = [UILabel new];
    hint.text          = @"Tap anywhere to continue";
    hint.textColor     = [UIColor colorWithWhite:0.28 alpha:1];
    hint.font          = [UIFont systemFontOfSize:10];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:hint];

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:290],
        [iconView.topAnchor constraintEqualToAnchor:card.topAnchor constant:24],
        [iconView.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [iconView.widthAnchor constraintEqualToConstant:60],
        [iconView.heightAnchor constraintEqualToConstant:60],
        [greet.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:12],
        [greet.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [greet.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [sub.topAnchor constraintEqualToAnchor:greet.bottomAnchor constant:4],
        [sub.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [sub.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [div1.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:14],
        [div1.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [div1.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [div1.heightAnchor constraintEqualToConstant:1],
        [devIDTitle.topAnchor constraintEqualToAnchor:div1.bottomAnchor constant:10],
        [devIDTitle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [devIDTitle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [devIDVal.topAnchor constraintEqualToAnchor:devIDTitle.bottomAnchor constant:4],
        [devIDVal.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [devIDVal.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [div2.topAnchor constraintEqualToAnchor:devIDVal.bottomAnchor constant:12],
        [div2.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [div2.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [div2.heightAnchor constraintEqualToConstant:1],
        [_keyExpiryLabel.topAnchor constraintEqualToAnchor:div2.bottomAnchor constant:10],
        [_keyExpiryLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [_keyExpiryLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [_devExpiryLabel.topAnchor constraintEqualToAnchor:_keyExpiryLabel.bottomAnchor constant:6],
        [_devExpiryLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [_devExpiryLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [hint.topAnchor constraintEqualToAnchor:_devExpiryLabel.bottomAnchor constant:14],
        [hint.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [card.bottomAnchor constraintEqualToAnchor:hint.bottomAnchor constant:20],
    ]];
}

- (NSString *)countdownFrom:(NSTimeInterval)exp label:(NSString *)label emoji:(NSString *)emoji {
    if (exp <= 0) return @"";
    NSTimeInterval left = exp - [[NSDate date] timeIntervalSince1970];
    if (left <= 0) return [NSString stringWithFormat:@"%@ %@: EXPIRED", emoji, label];
    long long d = (long long)(left / 86400);
    long long h = (long long)(fmod(left, 86400) / 3600);
    long long m = (long long)(fmod(left, 3600) / 60);
    long long s = (long long)fmod(left, 60);
    NSString *timeStr;
    if (d > 0)      timeStr = [NSString stringWithFormat:@"%lldd %lldh %lldm left", d, h, m];
    else if (h > 0) timeStr = [NSString stringWithFormat:@"%lldh %lldm %llds left", h, m, s];
    else if (m > 0) timeStr = [NSString stringWithFormat:@"%lldm %llds left", m, s];
    else            timeStr = [NSString stringWithFormat:@"%llds left", s];
    NSDate *expiryDate = [NSDate dateWithTimeIntervalSince1970:exp];
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"dd/MM/yyyy HH:mm";
    return [NSString stringWithFormat:@"%@ %@: %@\nExpires %@", emoji, label, timeStr, [df stringFromDate:expiryDate]];
}

- (void)tickCountdown {
    if (_keyExpiry > 0)
        _keyExpiryLabel.text = [self countdownFrom:_keyExpiry label:@"Key" emoji:@"🔑"];
    if (_devExpiry > 0)
        _devExpiryLabel.text = [self countdownFrom:_devExpiry label:@"Device" emoji:@"📱"];
}

- (void)dismiss {
    [_autoHideTimer invalidate];  _autoHideTimer  = nil;
    [_countdownTimer invalidate]; _countdownTimer = nil;
    [UIView animateWithDuration:0.2 animations:^{ self.alpha = 0; }
                     completion:^(BOOL _){ [self removeFromSuperview]; }];
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKTutorialSpotlightView
// ─────────────────────────────────────────────────────────────────────────────
@interface SKTutorialSpotlightView : UIView
@property (nonatomic, assign) CGRect    spotRect;
@property (nonatomic, assign) CGPoint   lineEnd;
@property (nonatomic, assign) BOOL      lineVisible;
- (void)animateToSpot:(CGRect)newSpot lineEnd:(CGPoint)lp completion:(void(^)(void))done;
@end

@implementation SKTutorialSpotlightView

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [[UIColor colorWithWhite:0 alpha:0.72] setFill];
    CGContextFillRect(ctx, self.bounds);

    if (!CGRectIsEmpty(_spotRect)) {
        CGRect padded = CGRectInset(_spotRect, -10, -10);
        CGContextSetBlendMode(ctx, kCGBlendModeClear);
        UIBezierPath *hole = [UIBezierPath bezierPathWithRoundedRect:padded cornerRadius:14];
        CGContextSetFillColorWithColor(ctx, [UIColor blackColor].CGColor);
        CGContextAddPath(ctx, hole.CGPath);
        CGContextFillPath(ctx);
        CGContextSetBlendMode(ctx, kCGBlendModeNormal);

        UIBezierPath *border = [UIBezierPath bezierPathWithRoundedRect:padded cornerRadius:14];
        CGContextAddPath(ctx, border.CGPath);
        [[UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:0.85] setStroke];
        CGContextSetLineWidth(ctx, 2.0);
        CGFloat dashes[] = { 6.0, 4.0 };
        CGContextSetLineDash(ctx, 0, dashes, 2);
        CGContextStrokePath(ctx);

        if (_lineVisible && !CGPointEqualToPoint(_lineEnd, CGPointZero)) {
            CGPoint spotCenter = CGPointMake(CGRectGetMidX(padded), CGRectGetMidY(padded));
            CGPoint from = spotCenter;
            CGFloat dx = _lineEnd.x - spotCenter.x;
            CGFloat dy = _lineEnd.y - spotCenter.y;
            CGFloat len = sqrt(dx*dx + dy*dy);
            if (len > 1) {
                CGFloat nx = dx / len, ny = dy / len;
                CGFloat hw = padded.size.width / 2 + 10;
                CGFloat hh = padded.size.height / 2 + 10;
                CGFloat t = MIN(hw / MAX(fabs(nx), 0.001), hh / MAX(fabs(ny), 0.001));
                from = CGPointMake(spotCenter.x + nx * t, spotCenter.y + ny * t);
            }

            CGContextSetBlendMode(ctx, kCGBlendModeNormal);
            CGFloat pDashes[] = { 5.0, 5.0 };
            CGContextSetLineDash(ctx, 0, pDashes, 2);
            CGContextSetLineWidth(ctx, 1.8);
            [[UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:0.75] setStroke];
            CGContextMoveToPoint(ctx, from.x, from.y);
            CGContextAddLineToPoint(ctx, _lineEnd.x, _lineEnd.y);
            CGContextStrokePath(ctx);

            CGContextSetLineDash(ctx, 0, NULL, 0);
            CGFloat arrowSize = 7.0;
            CGFloat angle = atan2(dy, dx);
            CGContextMoveToPoint(ctx, _lineEnd.x, _lineEnd.y);
            CGContextAddLineToPoint(ctx,
                _lineEnd.x - arrowSize * cos(angle - M_PI/7.0),
                _lineEnd.y - arrowSize * sin(angle - M_PI/7.0));
            CGContextMoveToPoint(ctx, _lineEnd.x, _lineEnd.y);
            CGContextAddLineToPoint(ctx,
                _lineEnd.x - arrowSize * cos(angle + M_PI/7.0),
                _lineEnd.y - arrowSize * sin(angle + M_PI/7.0));
            CGContextSetLineWidth(ctx, 2.0);
            [[UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:1] setStroke];
            CGContextStrokePath(ctx);
        }
    }
}

- (void)animateToSpot:(CGRect)newSpot lineEnd:(CGPoint)lp completion:(void(^)(void))done {
    _lineVisible = NO;
    [UIView animateWithDuration:0.28 delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        self.spotRect = newSpot;
        self.lineEnd  = lp;
        [self setNeedsDisplay];
    } completion:^(BOOL _) {
        self.lineVisible = YES;
        [self setNeedsDisplay];
        if (done) done();
    }];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKTutorialOverlay
// ─────────────────────────────────────────────────────────────────────────────
@implementation SKTutorialOverlay {
    SKPanel                  *_panel;
    UIView                   *_parent;
    UIWindow                 *_hostWindow;
    SKTutorialSpotlightView  *_spotlight;
    UIView                   *_tooltipCard;
    UILabel                  *_stepLabel;
    UILabel                  *_titleLabel;
    UILabel                  *_descLabel;
    UIButton                 *_continueBtn;
    NSInteger                 _stepIndex;
    NSArray<NSDictionary *>  *_steps;
    SKSettingsMenu           *_settingsMenu;
}

+ (void)showForPanel:(SKPanel *)panel inView:(UIView *)parent {
    UIWindow *hostWindow = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows.reverseObjectEnumerator)
        if (!w.isHidden && w.alpha > 0) { hostWindow = w; break; }
    UIView *container = hostWindow ?: parent;

    SKTutorialOverlay *o = [[SKTutorialOverlay alloc] initWithFrame:container.bounds];
    o.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    o->_panel       = panel;
    o->_parent      = parent;
    o->_hostWindow  = hostWindow;
    o.layer.zPosition = 1000000;
    [container addSubview:o];
    o.alpha = 0;
    [UIView animateWithDuration:0.25 animations:^{ o.alpha = 1; }
                     completion:^(BOOL _){ [o setupStepsAndStart]; }];
}

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = YES;

    _spotlight = [[SKTutorialSpotlightView alloc] initWithFrame:self.bounds];
    _spotlight.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _spotlight.userInteractionEnabled = NO;
    [self addSubview:_spotlight];

    _tooltipCard = [UIView new];
    _tooltipCard.backgroundColor    = [UIColor colorWithRed:0.06 green:0.08 blue:0.13 alpha:0.98];
    _tooltipCard.layer.cornerRadius = 16;
    _tooltipCard.layer.shadowColor  = [UIColor blackColor].CGColor;
    _tooltipCard.layer.shadowOpacity = 0.88;
    _tooltipCard.layer.shadowRadius  = 16;
    _tooltipCard.layer.shadowOffset  = CGSizeMake(0, 5);
    _tooltipCard.layer.borderColor   = [UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:0.30].CGColor;
    _tooltipCard.layer.borderWidth   = 1;
    _tooltipCard.translatesAutoresizingMaskIntoConstraints = NO;
    _tooltipCard.userInteractionEnabled = YES;
    [self addSubview:_tooltipCard];

    _stepLabel = [UILabel new];
    _stepLabel.textColor  = [UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:0.70];
    _stepLabel.font       = [UIFont boldSystemFontOfSize:10];
    _stepLabel.textAlignment = NSTextAlignmentLeft;
    _stepLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_tooltipCard addSubview:_stepLabel];

    _titleLabel = [UILabel new];
    _titleLabel.textColor  = [UIColor whiteColor];
    _titleLabel.font       = [UIFont boldSystemFontOfSize:15];
    _titleLabel.numberOfLines = 1;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_tooltipCard addSubview:_titleLabel];

    _descLabel = [UILabel new];
    _descLabel.textColor  = [UIColor colorWithWhite:0.72 alpha:1];
    _descLabel.font       = [UIFont systemFontOfSize:12];
    _descLabel.numberOfLines = 0;
    _descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_tooltipCard addSubview:_descLabel];

    _continueBtn = makeSymBtn(@"Continue", @"arrow.right.circle",
        [UIColor colorWithRed:0.14 green:0.52 blue:0.28 alpha:1], @selector(tapContinue), self);
    _continueBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [_tooltipCard addSubview:_continueBtn];

    [NSLayoutConstraint activateConstraints:@[
        [_stepLabel.topAnchor constraintEqualToAnchor:_tooltipCard.topAnchor constant:14],
        [_stepLabel.leadingAnchor constraintEqualToAnchor:_tooltipCard.leadingAnchor constant:16],
        [_stepLabel.trailingAnchor constraintEqualToAnchor:_tooltipCard.trailingAnchor constant:-16],
        [_titleLabel.topAnchor constraintEqualToAnchor:_stepLabel.bottomAnchor constant:4],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_tooltipCard.leadingAnchor constant:16],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_tooltipCard.trailingAnchor constant:-16],
        [_descLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:8],
        [_descLabel.leadingAnchor constraintEqualToAnchor:_tooltipCard.leadingAnchor constant:16],
        [_descLabel.trailingAnchor constraintEqualToAnchor:_tooltipCard.trailingAnchor constant:-16],
        [_continueBtn.topAnchor constraintEqualToAnchor:_descLabel.bottomAnchor constant:14],
        [_continueBtn.leadingAnchor constraintEqualToAnchor:_tooltipCard.leadingAnchor constant:14],
        [_continueBtn.trailingAnchor constraintEqualToAnchor:_tooltipCard.trailingAnchor constant:-14],
        [_continueBtn.heightAnchor constraintEqualToConstant:40],
        [_tooltipCard.bottomAnchor constraintEqualToAnchor:_continueBtn.bottomAnchor constant:14],
        [_tooltipCard.widthAnchor constraintEqualToConstant:270],
    ]];
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *cardHit = [_tooltipCard hitTest:[self convertPoint:point toView:_tooltipCard]
                                  withEvent:event];
    if (cardHit) return cardHit;
    return self;
}

- (void)setupStepsAndStart {
    _steps = @[
        @{
            @"title": @"Upload to Cloud ☁️",
            @"desc":  @"Uploads your save data to the cloud for editing.\n\nBypasses iOS sandbox — works on non-jailbroken devices. After upload you'll get a shareable link to access and edit your data.",
            @"target": @"upload"
        },
        @{
            @"title": @"Load from Cloud ⬇️",
            @"desc":  @"Downloads and applies the save data you edited in the cloud editor.\n\nUse this after you've made your changes via the web link.",
            @"target": @"load"
        },
        @{
            @"title": @"Settings ⚙️",
            @"desc":  @"Configure auto-behaviours for the tool. Tap Continue to walk through each setting.",
            @"target": @"settings"
        },
        @{
            @"title": @"Auto Rij",
            @"desc":  @"By default you'd need to manually edit the Rij value after uploading. When ON, this automatically sets all OpenRijTest_ flags to 0 — no manual step needed.\n\n✅ Enabled by default.",
            @"target": @"rij"
        },
        @{
            @"title": @"Auto Detect UID",
            @"desc":  @"Reads the PlayerId of the account you're currently logged in as.\n\nExample: logged in as UID 123 → only .data files containing '123' are uploaded. No need to type UID manually.",
            @"target": @"uid"
        },
        @{
            @"title": @"Auto Close",
            @"desc":  @"The app must be closed for edited .data files to take effect after loading from cloud.\n\nWith this ON, the app closes automatically — so you don't forget.",
            @"target": @"close"
        },
    ];
    _stepIndex = -1;
    [self advance];
}

- (void)advance {
    _stepIndex++;
    if (_stepIndex >= (NSInteger)_steps.count) {
        [self finishTutorial];
        return;
    }

    NSDictionary *step = _steps[_stepIndex];
    NSString *target   = step[@"target"];

    if (_stepIndex == 3 && !_settingsMenu) {
        UIView *menuHost = _hostWindow ?: _parent;
        _settingsMenu = [SKSettingsMenu showInView:menuHost];
        [self.superview bringSubviewToFront:self];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ [self showStep:step target:target]; });
        return;
    }
    [self showStep:step target:target];
}

- (void)showStep:(NSDictionary *)step target:(NSString *)target {
    CGRect spotRect = [self rectForTarget:target];

    _stepLabel.text  = [NSString stringWithFormat:@"Step %ld of %lu",
        (long)(_stepIndex + 1), (unsigned long)_steps.count];
    _titleLabel.text = step[@"title"];
    _descLabel.text  = step[@"desc"];

    BOOL isLast = _stepIndex == (NSInteger)_steps.count - 1;
    [_continueBtn setTitle:isLast ? @"  Done ✓" : @"  Continue" forState:UIControlStateNormal];

    [self setNeedsLayout];
    [self layoutIfNeeded];
    CGSize cardSize = [_tooltipCard systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];

    CGFloat screenH = self.bounds.size.height;
    CGFloat pad = 16;
    CGFloat cardH = cardSize.height;
    CGFloat cardW = 270;

    CGFloat spotCY = CGRectGetMidY(spotRect);
    CGFloat cardY;
    if (spotCY < screenH * 0.55) {
        cardY = CGRectGetMaxY(spotRect) + 28;
    } else {
        cardY = CGRectGetMinY(spotRect) - cardH - 28;
    }
    cardY = MAX(pad, MIN(screenH - cardH - pad, cardY));

    CGFloat cardX = CGRectGetMinX(spotRect) - cardW - 24;
    if (cardX < pad) cardX = pad;

    [UIView animateWithDuration:0.22 delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        self->_tooltipCard.frame = CGRectMake(cardX, cardY, cardW, cardH);
        self->_tooltipCard.alpha = 1;
    } completion:nil];

    CGRect cardFrame = CGRectMake(cardX, cardY, cardW, cardH);
    CGPoint lineEnd  = [self nearestEdgeOfRect:cardFrame toRect:spotRect];
    [_spotlight animateToSpot:spotRect lineEnd:lineEnd completion:nil];
}

- (CGRect)rectForTarget:(NSString *)target {
    if ([target isEqualToString:@"upload"] && _panel.uploadBtn) {
        return [_panel.uploadBtn convertRect:_panel.uploadBtn.bounds toView:self];
    }
    if ([target isEqualToString:@"load"] && _panel.loadBtn) {
        return [_panel.loadBtn convertRect:_panel.loadBtn.bounds toView:self];
    }
    if ([target isEqualToString:@"settings"] && _panel.settingsBtn) {
        return [_panel.settingsBtn convertRect:_panel.settingsBtn.bounds toView:self];
    }
    if ([target isEqualToString:@"rij"] && _settingsMenu && _settingsMenu.tutRijRow) {
        return [_settingsMenu.tutRijRow convertRect:_settingsMenu.tutRijRow.bounds toView:self];
    }
    if ([target isEqualToString:@"uid"] && _settingsMenu && _settingsMenu.tutUidRow) {
        return [_settingsMenu.tutUidRow convertRect:_settingsMenu.tutUidRow.bounds toView:self];
    }
    if ([target isEqualToString:@"close"] && _settingsMenu && _settingsMenu.tutCloseRow) {
        return [_settingsMenu.tutCloseRow convertRect:_settingsMenu.tutCloseRow.bounds toView:self];
    }
    return CGRectMake(self.bounds.size.width/2 - 60, self.bounds.size.height/2 - 20, 120, 40);
}

- (CGPoint)nearestEdgeOfRect:(CGRect)card toRect:(CGRect)spot {
    CGPoint spotC = CGPointMake(CGRectGetMidX(spot), CGRectGetMidY(spot));
    CGFloat cx = MAX(CGRectGetMinX(card), MIN(CGRectGetMaxX(card), spotC.x));
    CGFloat cy = MAX(CGRectGetMinY(card), MIN(CGRectGetMaxY(card), spotC.y));
    CGFloat dl = fabs(cx - CGRectGetMinX(card));
    CGFloat dr = fabs(cx - CGRectGetMaxX(card));
    CGFloat dt = fabs(cy - CGRectGetMinY(card));
    CGFloat db = fabs(cy - CGRectGetMaxY(card));
    CGFloat minD = MIN(MIN(dl, dr), MIN(dt, db));
    if (minD == dl)      return CGPointMake(CGRectGetMinX(card), cy);
    else if (minD == dr) return CGPointMake(CGRectGetMaxX(card), cy);
    else if (minD == dt) return CGPointMake(cx, CGRectGetMinY(card));
    else                 return CGPointMake(cx, CGRectGetMaxY(card));
}

- (void)tapContinue {
    [UIView animateWithDuration:0.12 animations:^{ self->_tooltipCard.alpha = 0; }
                     completion:^(BOOL _){ [self advance]; }];
}

- (void)finishTutorial {
    if (_settingsMenu) { [_settingsMenu dismiss]; _settingsMenu = nil; }
    [UIView animateWithDuration:0.22 animations:^{ self.alpha = 0; }
                     completion:^(BOOL _){ [self removeFromSuperview]; }];
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - showWelcomeIfNeeded
// ─────────────────────────────────────────────────────────────────────────────
static void showWelcomeIfNeeded(UIView *parent) {
    if (gWelcomeShownThisSession) return;
    gWelcomeShownThisSession = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            [SKWelcomeNotification showInView:parent
                                      expiry:gKeyExpiry
                                deviceExpiry:gDeviceExpiry];
        });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Injection entry point  (v12 UDID-first gate)
// FIX: All overlays now added directly to UIWindow so game engine cannot
//      intercept touches. Buttons are fully clickable.
// ─────────────────────────────────────────────────────────────────────────────
static SKPanel *gPanel = nil;

static void showMainPanel(UIView *root) {
    initDefaultSettings();
    if (gPanel) return;
    gPanel = [SKPanel new];
    gPanel.center = CGPointMake(root.bounds.size.width - gPanel.bounds.size.width/2 - 10, 88);
    gPanel.alpha = 0;
    [root addSubview:gPanel];
    [root bringSubviewToFront:gPanel];
    NSTimeInterval savedDevExp = loadDeviceExpiryLocally();
    if (savedDevExp > 0) gDeviceExpiry = savedDevExp;
    [gPanel refreshStatus];
    [UIView animateWithDuration:0.3 delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{ gPanel.alpha = 1; gPanel.transform = CGAffineTransformIdentity; }
                     completion:^(BOOL _){ showWelcomeIfNeeded(root); }];
}

static void injectPanel(void) {
    // Get the key UIWindow — adding to window bypasses game engine touch interception
    UIWindow *win = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows)
        if (!w.isHidden && w.alpha > 0) { win = w; break; }
    if (!win) return;
    UIView *root = win.rootViewController.view ?: win;

    // ── STEP 2: Key auth gate (called after UDID confirmed) ─────────────────
    void (^proceedWithAuth)(void) = ^{
        NSString *savedKey = loadSavedKey();
        if (savedKey.length) {
            // Silent re-auth spinner
            UIActivityIndicatorView *spinner =
                [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            spinner.color = [UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];
            spinner.center = CGPointMake(root.bounds.size.width - 24, 80);
            spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
            [root addSubview:spinner];
            [spinner startAnimating];

            performKeyAuth(savedKey, ^(BOOL ok, NSTimeInterval keyExpiry, NSTimeInterval devExpiry, NSString *errorMsg) {
                [spinner stopAnimating]; [spinner removeFromSuperview];
                if (ok) {
                    gDeviceExpiry = devExpiry; gKeyExpiry = keyExpiry;
                    saveDeviceExpiryLocally(devExpiry);
                    showMainPanel(root);
                } else {
                    clearSavedKey();
                    NSLog(@"[SKTools] Saved key rejected: %@", errorMsg);
                    UIAlertController *alert = [UIAlertController
                        alertControllerWithTitle:@"Key Invalid"
                                         message:[NSString stringWithFormat:@"%@\n\nPlease enter a valid key.", errorMsg ?: @"Auth failed."]
                                  preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"Enter Key" style:UIAlertActionStyleDefault
                        handler:^(UIAlertAction *_) {
                            // FIX: use win directly so touches work over game view
                            [SKKeyAuthOverlay showInView:win completion:^(NSString *newKey) {
                                showMainPanel(root);
                            }];
                        }]];
                    [alert addAction:[UIAlertAction actionWithTitle:@"Exit" style:UIAlertActionStyleDestructive
                        handler:^(UIAlertAction *_) { exit(0); }]];
                    UIViewController *vc = win.rootViewController;
                    while (vc.presentedViewController) vc = vc.presentedViewController;
                    [vc presentViewController:alert animated:YES completion:nil];
                }
            });
        } else {
            // No saved key → show key entry directly on window
            // FIX: use win instead of vc.view so game engine can't eat touches
            [SKKeyAuthOverlay showInView:win completion:^(NSString *key) {
                showMainPanel(root);
            }];
        }
    };

    // ── STEP 1: UDID gate ────────────────────────────────────────────────────
    NSString *cachedUDID = loadCachedUDID();
    if (cachedUDID.length) {
        // Already enrolled → go straight to auth
        proceedWithAuth();
    } else {
        // No UDID yet → show enrollment on window directly
        // FIX: use win instead of vc.view so buttons are tappable
        // Use showInWindow: — compact frame-based panel, no full-screen overlay.
        // proceedWithAuth (key input/auth) only fires AFTER UDID is confirmed.
        [SKUDIDEnrollOverlay showInWindow:win completion:^(NSString *udid) {
            proceedWithAuth();
        }];
    }
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ injectPanel(); });
    });
}
%end
