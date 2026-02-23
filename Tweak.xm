// tweak.xm — Soul Knight Save Manager v11
// iOS 14+ | Theos/Logos | ARC
// v11.0: KEY AUTH SYSTEM — AES-256-CBC encrypted auth requests,
//         persistent device ID via Keychain (survives reinstall),
//         MITM protection via timestamp echo verification,
//         local timestamp replay guard, auto key save/restore,
//         expiry display in panel.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>

// ── Config ────────────────────────────────────────────────────────────────────
#define API_BASE      @"https://chillysilly.frfrnocap.men/isk.php"
#define AUTH_BASE     @"https://chillysilly.frfrnocap.men/iskeauth.php"

// AES-256 shared secret (32 bytes — must match PHP define AES_SECRET)
// Split across two calls to make binary extraction slightly harder
static NSString *authAESKey(void) {
    return [@"SK@uth_K3y_2024#" stringByAppendingString:@"Secure_Pswd!!!!!"];
}

// Max acceptable timestamp drift for MITM check (seconds)
#define kMaxTsDrift  60

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AES-256-CBC Encrypt / Decrypt  (CommonCrypto)
// ─────────────────────────────────────────────────────────────────────────────
// Format: Base64( random_IV_16_bytes | ciphertext )
// ─────────────────────────────────────────────────────────────────────────────
static NSData *aesEncryptData(NSData *plainData, NSString *keyStr) {
    if (!plainData || !keyStr) return nil;

    // Key: SHA-256 of keyStr → always 32 bytes regardless of input length
    NSData *keyData = [keyStr dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t keyBuf[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(keyData.bytes, (CC_LONG)keyData.length, keyBuf);

    // Random IV
    uint8_t iv[kCCBlockSizeAES128];
    SecRandomCopyBytes(kSecRandomDefault, kCCBlockSizeAES128, iv);

    // Encrypt
    size_t outLen = plainData.length + kCCBlockSizeAES128;
    NSMutableData *ctData = [NSMutableData dataWithLength:outLen];
    size_t moved = 0;
    CCCryptorStatus st = CCCrypt(
        kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
        keyBuf, kCCKeySizeAES256,
        iv,
        plainData.bytes, plainData.length,
        ctData.mutableBytes, outLen,
        &moved);

    if (st != kCCSuccess) return nil;
    [ctData setLength:moved];

    // Prepend IV
    NSMutableData *result = [NSMutableData dataWithBytes:iv length:kCCBlockSizeAES128];
    [result appendData:ctData];
    return result;
}

static NSData *aesDecryptData(NSData *ivPlusCt, NSString *keyStr) {
    if (!ivPlusCt || ivPlusCt.length <= kCCBlockSizeAES128 || !keyStr) return nil;

    NSData *keyData = [keyStr dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t keyBuf[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(keyData.bytes, (CC_LONG)keyData.length, keyBuf);

    const uint8_t *iv = (const uint8_t *)ivPlusCt.bytes;
    const uint8_t *ct = iv + kCCBlockSizeAES128;
    size_t ctLen = ivPlusCt.length - kCCBlockSizeAES128;

    NSMutableData *ptData = [NSMutableData dataWithLength:ctLen + kCCBlockSizeAES128];
    size_t moved = 0;
    CCCryptorStatus st = CCCrypt(
        kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
        keyBuf, kCCKeySizeAES256,
        iv,
        ct, ctLen,
        ptData.mutableBytes, ptData.length,
        &moved);

    if (st != kCCSuccess) return nil;
    [ptData setLength:moved];
    return ptData;
}

static NSString *encryptPayloadToBase64(NSDictionary *payload) {
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!jsonData) return nil;
    NSData *enc = aesEncryptData(jsonData, authAESKey());
    if (!enc) return nil;
    return [enc base64EncodedStringWithOptions:0];
}

static NSDictionary *decryptBase64ToDict(NSString *b64) {
    if (!b64.length) return nil;
    NSData *raw = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    if (!raw) return nil;
    NSData *plain = aesDecryptData(raw, authAESKey());
    if (!plain) return nil;
    return [NSJSONSerialization JSONObjectWithData:plain options:0 error:nil];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Keychain helpers
//
// We store two things in Keychain:
//   1. Persistent device UUID  (service: "SKToolsDevID")
//   2. Saved auth key           (service: "SKToolsAuthKey")
//
// Keychain items with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
// persist across app reinstalls on the same physical device.
// They are NOT synced to iCloud and NOT restored from backup to a different device.
// ─────────────────────────────────────────────────────────────────────────────
static const NSString *kKCSvcDevID  = @"SKToolsDevID";
static const NSString *kKCSvcKey    = @"SKToolsAuthKey";
static const NSString *kKCAccount   = @"sktools";

static NSDictionary *kcBaseQuery(NSString *service) {
    return @{
        (__bridge id)kSecClass:            (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:      service,
        (__bridge id)kSecAttrAccount:      kKCAccount,
        (__bridge id)kSecAttrAccessible:   (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        // Explicitly no sync — ties to this device only
        (__bridge id)kSecAttrSynchronizable: @NO,
    };
}

static NSString *kcRead(NSString *service) {
    NSMutableDictionary *q = [NSMutableDictionary dictionaryWithDictionary:kcBaseQuery(service)];
    q[(__bridge id)kSecReturnData]  = @YES;
    q[(__bridge id)kSecMatchLimit]  = (__bridge id)kSecMatchLimitOne;

    CFTypeRef result = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &result);
    if (st != errSecSuccess || !result) return nil;

    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static BOOL kcWrite(NSString *service, NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return NO;

    // Try update first
    NSMutableDictionary *qFind = [NSMutableDictionary dictionaryWithDictionary:kcBaseQuery(service)];
    NSDictionary *update = @{ (__bridge id)kSecValueData: data };
    OSStatus st = SecItemUpdate((__bridge CFDictionaryRef)qFind, (__bridge CFDictionaryRef)update);

    if (st == errSecItemNotFound) {
        // Add new item
        NSMutableDictionary *qAdd = [NSMutableDictionary dictionaryWithDictionary:kcBaseQuery(service)];
        qAdd[(__bridge id)kSecValueData] = data;
        st = SecItemAdd((__bridge CFDictionaryRef)qAdd, NULL);
    }
    return st == errSecSuccess;
}

static void kcDelete(NSString *service) {
    NSDictionary *q = kcBaseQuery(service);
    SecItemDelete((__bridge CFDictionaryRef)q);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Persistent Device UUID  (Keychain-backed, survives reinstall)
// ─────────────────────────────────────────────────────────────────────────────
static NSString *persistentDeviceID(void) {
    NSString *existing = kcRead((NSString *)kKCSvcDevID);
    if (existing.length) return existing;

    // Generate new UUID and store in Keychain
    NSString *newUUID = [[NSUUID UUID] UUIDString];
    kcWrite((NSString *)kKCSvcDevID, newUUID);
    return newUUID;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Saved Key (Keychain)
// ─────────────────────────────────────────────────────────────────────────────
static NSString *loadSavedKey(void)        { return kcRead((NSString *)kKCSvcKey); }
static void      saveSavedKey(NSString *k) { kcWrite((NSString *)kKCSvcKey, k); }
static void      clearSavedKey(void)       { kcDelete((NSString *)kKCSvcKey); }

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Timestamp replay guard  (local file)
//
// We save the last sent timestamp BEFORE sending.
// On receiving a successful response we verify the echoed timestamp equals it.
// This prevents replaying a captured successful response.
// ─────────────────────────────────────────────────────────────────────────────
static NSString *tsGuardFilePath(void) {
    return [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Preferences/SKToolsLastTS.txt"];
}
static void      saveLastSentTS(NSTimeInterval ts) {
    [[NSString stringWithFormat:@"%.0f", ts]
        writeToFile:tsGuardFilePath() atomically:YES
           encoding:NSUTF8StringEncoding error:nil];
}
static NSTimeInterval loadLastSentTS(void) {
    NSString *s = [NSString stringWithContentsOfFile:tsGuardFilePath()
                                             encoding:NSUTF8StringEncoding error:nil];
    return s.doubleValue;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Expiry cache  (in-memory + NSUserDefaults)
// ─────────────────────────────────────────────────────────────────────────────
static NSTimeInterval gKeyExpiry = 0; // set after successful auth

static void saveExpiryLocally(NSTimeInterval exp) {
    [[NSUserDefaults standardUserDefaults] setDouble:exp forKey:@"SKToolsKeyExpiry"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
static NSTimeInterval loadExpiryLocally(void) {
    return [[NSUserDefaults standardUserDefaults] doubleForKey:@"SKToolsKeyExpiry"];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Session file  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
static NSString *sessionFilePath(void) {
    return [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Preferences/SKToolsSession.txt"];
}
static NSString *loadSessionUUID(void) {
    return [NSString stringWithContentsOfFile:sessionFilePath()
                                     encoding:NSUTF8StringEncoding error:nil];
}
static void saveSessionUUID(NSString *uuid) {
    [uuid writeToFile:sessionFilePath() atomically:YES
             encoding:NSUTF8StringEncoding error:nil];
}
static void clearSessionUUID(void) {
    [[NSFileManager defaultManager] removeItemAtPath:sessionFilePath() error:nil];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Settings  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
static NSString *settingsFilePath(void) {
    return [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Preferences/SKToolsSettings.plist"];
}
static NSMutableDictionary *loadSettingsDict(void) {
    NSMutableDictionary *d = [NSMutableDictionary
        dictionaryWithContentsOfFile:settingsFilePath()];
    return d ?: [NSMutableDictionary dictionary];
}
static void persistSettingsDict(NSMutableDictionary *d) {
    [d writeToFile:settingsFilePath() atomically:YES];
}
static BOOL getSetting(NSString *key) {
    return [loadSettingsDict()[key] boolValue];
}
static void setSetting(NSString *key, BOOL val) {
    NSMutableDictionary *d = loadSettingsDict();
    d[key] = @(val);
    persistSettingsDict(d);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Device info helpers
// ─────────────────────────────────────────────────────────────────────────────
static NSString *deviceUUID(void) {
    NSString *v = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    return v ?: [[NSUUID UUID] UUIDString];
}

static NSString *deviceModel(void) {
    struct utsname info;
    uname(&info);
    return [NSString stringWithCString:info.machine encoding:NSUTF8StringEncoding]
           ?: [UIDevice currentDevice].model;
}

static NSString *systemVersion(void) {
    return [UIDevice currentDevice].systemVersion ?: @"?";
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Auto Detect UID  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
static NSString *detectPlayerUID(void) {
    NSString *raw = [[NSUserDefaults standardUserDefaults]
        stringForKey:@"SdkStateCache#1"];
    if (!raw.length) return nil;
    NSData *jdata = [raw dataUsingEncoding:NSUTF8StringEncoding];
    if (!jdata) return nil;
    NSDictionary *root = [NSJSONSerialization
        JSONObjectWithData:jdata options:0 error:nil];
    if (![root isKindOfClass:[NSDictionary class]]) return nil;
    id user = root[@"User"];
    if (![user isKindOfClass:[NSDictionary class]]) return nil;
    id pid = ((NSDictionary *)user)[@"PlayerId"];
    if (!pid) return nil;
    return [NSString stringWithFormat:@"%@", pid];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Auto Rij  (v10.6 — unchanged)
// ─────────────────────────────────────────────────────────────────────────────
static NSString *applyAutoRij(NSString *plistXML) {
    if (!plistXML.length) return plistXML;
    NSError *rxErr = nil;
    NSRegularExpression *rx = [NSRegularExpression
        regularExpressionWithPattern:
            @"<key>OpenRijTest_\\d+</key>\\s*<integer>1</integer>"
        options:0 error:&rxErr];
    if (!rx || rxErr) { NSLog(@"[SKTools] applyAutoRij regex err: %@", rxErr); return plistXML; }

    NSArray<NSTextCheckingResult *> *matches =
        [rx matchesInString:plistXML options:0 range:NSMakeRange(0, plistXML.length)];
    if (!matches.count) return plistXML;

    NSMutableString *result = [plistXML mutableCopy];
    for (NSTextCheckingResult *match in matches.reverseObjectEnumerator) {
        NSRange   r        = match.range;
        NSString *original = [result substringWithRange:r];
        NSString *patched  = [original
            stringByReplacingOccurrencesOfString:@"<integer>1</integer>"
                                      withString:@"<integer>0</integer>"];
        [result replaceCharactersInRange:r withString:patched];
    }
    NSData *testData = [result dataUsingEncoding:NSUTF8StringEncoding];
    if (!testData) return plistXML;
    NSError *verr = nil; id parsed = nil;
    @try {
        parsed = [NSPropertyListSerialization propertyListWithData:testData
            options:NSPropertyListImmutable format:nil error:&verr];
    } @catch (NSException *ex) { return plistXML; }
    if (verr || !parsed) return plistXML;
    return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - URLSession
// ─────────────────────────────────────────────────────────────────────────────
static NSURLSession *makeSession(void) {
    NSURLSessionConfiguration *c =
        [NSURLSessionConfiguration defaultSessionConfiguration];
    c.timeoutIntervalForRequest  = 120;
    c.timeoutIntervalForResource = 600;
    c.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    return [NSURLSession sessionWithConfiguration:c];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Multipart body builder  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
typedef struct { NSMutableURLRequest *req; NSData *body; } MPRequest;

static MPRequest buildMP(NSDictionary<NSString*,NSString*> *fields,
                          NSString *fileField, NSString *filename, NSData *fileData) {
    NSString *boundary = [NSString stringWithFormat:@"----SKBound%08X%08X",
                          arc4random(), arc4random()];
    NSMutableData *body = [NSMutableData dataWithCapacity:
                           fileData ? fileData.length + 1024 : 1024];
    void (^addField)(NSString *, NSString *) = ^(NSString *n, NSString *v) {
        NSString *s = [NSString stringWithFormat:
            @"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n",
            boundary, n, v];
        [body appendData:[s dataUsingEncoding:NSUTF8StringEncoding]];
    };
    for (NSString *k in fields) addField(k, fields[k]);
    if (fileField && filename && fileData) {
        NSString *hdr = [NSString stringWithFormat:
            @"--%@\r\nContent-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n"
            @"Content-Type: text/plain; charset=utf-8\r\n\r\n",
            boundary, fileField, filename];
        [body appendData:[hdr dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:fileData];
        [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary]
                      dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:API_BASE]
           cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
       timeoutInterval:120];
    req.HTTPMethod = @"POST";
    [req setValue:[NSString stringWithFormat:
        @"multipart/form-data; boundary=%@", boundary]
       forHTTPHeaderField:@"Content-Type"];
    return (MPRequest){ req, body };
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - POST helper  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
static void skPost(NSURLSession *session,
                   NSMutableURLRequest *req,
                   NSData *body,
                   void (^cb)(NSDictionary *json, NSError *err)) {
    [[session uploadTaskWithRequest:req fromData:body
                  completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err) { cb(nil, err); return; }
            if (!data.length) {
                cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:@"Empty server response"}]); return;
            }
            NSError *je = nil;
            NSDictionary *j = [NSJSONSerialization JSONObjectWithData:data options:0 error:&je];
            if (je || !j) {
                NSString *raw = [[NSString alloc] initWithData:data
                    encoding:NSUTF8StringEncoding] ?: @"Non-JSON response";
                cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:raw}]); return;
            }
            if (j[@"error"]) {
                cb(nil, [NSError errorWithDomain:@"SKApi" code:0
                    userInfo:@{NSLocalizedDescriptionKey:j[@"error"]}]); return;
            }
            cb(j, nil);
        });
    }] resume];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Auth Network Request
//
//  Security flow:
//  1. Generate current Unix timestamp T.
//  2. Save T to local file BEFORE sending (replay guard).
//  3. Build JSON payload: { key, timestamp:T, device_id, model, sys_ver }
//  4. AES-256-CBC encrypt payload → base64.
//  5. POST to AUTH_BASE with action=auth, payload=<b64>.
//  6. Server decrypts, validates key, echoes T in encrypted response.
//  7. Device decrypts response, verifies:
//       a. response["timestamp"] == T sent  (MITM check)
//       b. response["timestamp"] == localSavedTS  (replay check)
//       c. abs(now - T) <= kMaxTsDrift          (freshness check)
//  8. If all pass and success==true → save key, save expiry, show panel.
//  9. If anything fails → clear saved key, show error, exit app.
// ─────────────────────────────────────────────────────────────────────────────
static void performKeyAuth(NSString *keyValue,
                           void (^completion)(BOOL ok, NSTimeInterval expiry, NSString *errorMsg)) {

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval sendTS = floor(now);

    // Step 2: Save timestamp locally BEFORE sending
    saveLastSentTS(sendTS);

    NSString *devId  = persistentDeviceID();
    NSString *model  = deviceModel();
    NSString *sysVer = systemVersion();

    NSDictionary *payload = @{
        @"key"       : keyValue ?: @"",
        @"timestamp" : @((long long)sendTS),
        @"device_id" : devId,
        @"model"     : model,
        @"sys_ver"   : sysVer,
    };

    NSString *encPayload = encryptPayloadToBase64(payload);
    if (!encPayload) {
        completion(NO, 0, @"Encryption failed — check AES setup.");
        return;
    }

    // Build request
    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:AUTH_BASE]
           cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
       timeoutInterval:20];
    req.HTTPMethod = @"POST";

    NSString *body = [NSString stringWithFormat:
        @"action=auth&payload=%@",
        [encPayload stringByAddingPercentEncodingWithAllowedCharacters:
            [NSCharacterSet URLQueryAllowedCharacterSet]]];
    req.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    NSURLSession *ses = makeSession();
    [[ses dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{

            if (err) {
                completion(NO, 0, [NSString stringWithFormat:@"Network error: %@",
                    err.localizedDescription]);
                return;
            }
            if (!data.length) {
                completion(NO, 0, @"Empty auth response.");
                return;
            }

            NSError *je = nil;
            NSDictionary *json = [NSJSONSerialization
                JSONObjectWithData:data options:0 error:&je];
            if (je || !json) {
                completion(NO, 0, @"Auth server returned invalid JSON.");
                return;
            }

            // Check for plain error
            if (json[@"error"]) {
                completion(NO, 0, json[@"error"]);
                return;
            }

            NSString *encResp = json[@"payload"];
            if (!encResp.length) {
                completion(NO, 0, @"No encrypted payload in auth response.");
                return;
            }

            // Step 7: Decrypt response
            NSDictionary *respDict = decryptBase64ToDict(encResp);
            if (!respDict) {
                completion(NO, 0, @"Failed to decrypt auth response — possible MITM.");
                return;
            }

            NSTimeInterval echoedTS  = [respDict[@"timestamp"] doubleValue];
            NSTimeInterval expiry    = [respDict[@"expiry"]    doubleValue];
            BOOL           success   = [respDict[@"success"]   boolValue];
            NSString      *message   = respDict[@"message"] ?: @"Unknown error";

            NSTimeInterval currentNow = [[NSDate date] timeIntervalSince1970];
            NSTimeInterval localSaved = loadLastSentTS();

            // ── MITM check: echoed timestamp must equal what we sent ──────────
            if (llabs((long long)echoedTS - (long long)sendTS) > 0) {
                clearSavedKey();
                completion(NO, 0,
                    @"Auth response timestamp mismatch — possible MITM attack. Access denied.");
                return;
            }

            // ── Replay check: local saved TS must match send TS ───────────────
            if (llabs((long long)localSaved - (long long)sendTS) > 0) {
                clearSavedKey();
                completion(NO, 0,
                    @"Replay guard triggered — timestamp inconsistency. Access denied.");
                return;
            }

            // ── Freshness check: response must be recent ──────────────────────
            if (fabs(currentNow - echoedTS) > kMaxTsDrift) {
                clearSavedKey();
                completion(NO, 0,
                    @"Auth response too old — possible replay attack. Access denied.");
                return;
            }

            if (!success) {
                clearSavedKey();
                completion(NO, 0, message);
                return;
            }

            // All checks passed
            completion(YES, expiry, message);
        });
    }] resume];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Expiry display helper
// ─────────────────────────────────────────────────────────────────────────────
static NSString *expiryDisplayString(NSTimeInterval expiry) {
    if (expiry <= 0) return @"";
    NSTimeInterval left = expiry - [[NSDate date] timeIntervalSince1970];
    if (left <= 0) return @"Key: EXPIRED";
    long long d = (long long)(left / 86400);
    long long h = (long long)(fmod(left, 86400) / 3600);
    if (d > 0)
        return [NSString stringWithFormat:@"Key: %lldd %lldh left", d, h];
    long long m = (long long)(fmod(left, 3600) / 60);
    return [NSString stringWithFormat:@"Key: %lldh %lldm left", h, m];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKProgressOverlay  (unchanged)
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
    card.backgroundColor     = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1];
    card.layer.cornerRadius  = 18;
    card.layer.shadowColor   = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.85;
    card.layer.shadowRadius  = 18;
    card.layer.shadowOffset  = CGSizeMake(0, 6);
    card.clipsToBounds       = NO;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:card];

    self.titleLabel = [UILabel new];
    self.titleLabel.text          = title;
    self.titleLabel.textColor     = [UIColor whiteColor];
    self.titleLabel.font          = [UIFont boldSystemFontOfSize:14];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.titleLabel];

    self.bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.bar.trackTintColor    = [UIColor colorWithWhite:0.22 alpha:1];
    self.bar.progressTintColor = [UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];
    self.bar.layer.cornerRadius = 3;
    self.bar.clipsToBounds      = YES;
    self.bar.progress           = 0;
    self.bar.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.bar];

    self.percentLabel = [UILabel new];
    self.percentLabel.text          = @"0%";
    self.percentLabel.textColor     = [UIColor colorWithWhite:0.55 alpha:1];
    self.percentLabel.font          = [UIFont boldSystemFontOfSize:11];
    self.percentLabel.textAlignment = NSTextAlignmentRight;
    self.percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.percentLabel];

    self.logView = [UITextView new];
    self.logView.backgroundColor    = [UIColor colorWithWhite:0.04 alpha:1];
    self.logView.textColor          = [UIColor colorWithRed:0.42 green:0.98 blue:0.58 alpha:1];
    self.logView.font               = [UIFont fontWithName:@"Courier" size:10]
                                     ?: [UIFont systemFontOfSize:10];
    self.logView.editable           = NO;
    self.logView.selectable         = NO;
    self.logView.layer.cornerRadius = 8;
    self.logView.text               = @"";
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.logView];

    self.openLinkBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.openLinkBtn setTitle:@"🌐  Open Link in Browser" forState:UIControlStateNormal];
    [self.openLinkBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.openLinkBtn.titleLabel.font  = [UIFont boldSystemFontOfSize:13];
    self.openLinkBtn.backgroundColor  = [UIColor colorWithRed:0.16 green:0.52 blue:0.92 alpha:1];
    self.openLinkBtn.layer.cornerRadius = 9;
    self.openLinkBtn.hidden             = YES;
    self.openLinkBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.openLinkBtn addTarget:self action:@selector(openLink)
               forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.openLinkBtn];

    self.closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.closeBtn setTitle:@"Close" forState:UIControlStateNormal];
    [self.closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeBtn.titleLabel.font  = [UIFont boldSystemFontOfSize:13];
    self.closeBtn.backgroundColor  = [UIColor colorWithWhite:0.20 alpha:1];
    self.closeBtn.layer.cornerRadius = 9;
    self.closeBtn.hidden             = YES;
    self.closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.closeBtn addTarget:self action:@selector(dismiss)
             forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.closeBtn];

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:310],
        [self.titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [self.bar.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:14],
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
        NSDateFormatter *f = [NSDateFormatter new];
        f.dateFormat = @"HH:mm:ss";
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                          [f stringFromDate:[NSDate date]], msg];
        self.logView.text = [self.logView.text stringByAppendingString:line];
        if (self.logView.text.length)
            [self.logView scrollRangeToVisible:
             NSMakeRange(self.logView.text.length - 1, 1)];
    });
}
- (void)finish:(BOOL)ok message:(NSString *)msg link:(NSString *)link {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setProgress:1.0 label:ok ? @"✓ Done" : @"✗ Failed"];
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
    if (!self.uploadedLink.length) return;
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
// MARK: - SKKeyAuthOverlay  (NEW — key input UI)
// ─────────────────────────────────────────────────────────────────────────────
@interface SKKeyAuthOverlay : UIView
+ (instancetype)showInView:(UIView *)parent
                completion:(void (^)(NSString *key))completion;
@end

@implementation SKKeyAuthOverlay {
    UITextField *_keyField;
    UIButton    *_activateBtn;
    UILabel     *_statusLabel;
    UIActivityIndicatorView *_spinner;
    void (^_completion)(NSString *);
}

+ (instancetype)showInView:(UIView *)parent
                completion:(void (^)(NSString *))completion {
    SKKeyAuthOverlay *o = [[SKKeyAuthOverlay alloc] initWithFrame:parent.bounds];
    o.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    o->_completion = [completion copy];
    [parent addSubview:o];
    o.alpha = 0;
    [UIView animateWithDuration:0.25 animations:^{ o.alpha = 1; }];
    return o;
}

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.88];
    [self buildUI];
    return self;
}

- (void)buildUI {
    UIView *card = [UIView new];
    card.backgroundColor    = [UIColor colorWithRed:0.07 green:0.07 blue:0.12 alpha:1];
    card.layer.cornerRadius = 20;
    card.layer.shadowColor  = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.9;
    card.layer.shadowRadius  = 22;
    card.layer.shadowOffset  = CGSizeMake(0, 8);
    card.clipsToBounds       = NO;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:card];

    // Lock icon
    UILabel *icon = [UILabel new];
    icon.text = @"🔐";
    icon.font = [UIFont systemFontOfSize:38];
    icon.textAlignment = NSTextAlignmentCenter;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:icon];

    // Title
    UILabel *title = [UILabel new];
    title.text          = @"SK Save Manager";
    title.textColor     = [UIColor whiteColor];
    title.font          = [UIFont boldSystemFontOfSize:17];
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:title];

    // Subtitle
    UILabel *sub = [UILabel new];
    sub.text          = @"Enter your activation key to continue";
    sub.textColor     = [UIColor colorWithWhite:0.45 alpha:1];
    sub.font          = [UIFont systemFontOfSize:12];
    sub.textAlignment = NSTextAlignmentCenter;
    sub.numberOfLines = 2;
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:sub];

    // Key input
    _keyField = [UITextField new];
    _keyField.backgroundColor    = [UIColor colorWithWhite:0.06 alpha:1];
    _keyField.textColor          = [UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:1];
    _keyField.font               = [UIFont fontWithName:@"Courier" size:15]
                                  ?: [UIFont systemFontOfSize:15];
    _keyField.textAlignment      = NSTextAlignmentCenter;
    _keyField.layer.cornerRadius = 10;
    _keyField.layer.borderColor  = [UIColor colorWithWhite:0.20 alpha:1].CGColor;
    _keyField.layer.borderWidth  = 1;
    _keyField.keyboardType       = UIKeyboardTypeASCIICapable;
    _keyField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    _keyField.autocorrectionType = UITextAutocorrectionTypeNo;
    _keyField.spellCheckingType  = UITextSpellCheckingTypeNo;
    _keyField.placeholder        = @"XXXX-XXXX-XXXX-XXXX";
    [_keyField setValue:[UIColor colorWithWhite:0.30 alpha:1]
             forKeyPath:@"_placeholderLabel.textColor"];
    _keyField.translatesAutoresizingMaskIntoConstraints = NO;
    [_keyField addTarget:self action:@selector(keyFieldChanged)
        forControlEvents:UIControlEventEditingChanged];
    [_keyField addTarget:self action:@selector(tapActivate)
        forControlEvents:UIControlEventEditingDidEndOnExit];

    UIView *leftPad  = [[UIView alloc] initWithFrame:CGRectMake(0,0,12,1)];
    UIView *rightPad = [[UIView alloc] initWithFrame:CGRectMake(0,0,12,1)];
    _keyField.leftView      = leftPad;
    _keyField.rightView     = rightPad;
    _keyField.leftViewMode  = UITextFieldViewModeAlways;
    _keyField.rightViewMode = UITextFieldViewModeAlways;
    [card addSubview:_keyField];

    // Status label
    _statusLabel = [UILabel new];
    _statusLabel.text          = @"";
    _statusLabel.textColor     = [UIColor colorWithRed:0.90 green:0.35 blue:0.35 alpha:1];
    _statusLabel.font          = [UIFont systemFontOfSize:11];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.numberOfLines = 3;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_statusLabel];

    // Spinner
    _spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color  = [UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];
    _spinner.hidden = YES;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_spinner];

    // Activate button
    _activateBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [_activateBtn setTitle:@"Activate" forState:UIControlStateNormal];
    [_activateBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_activateBtn setTitleColor:[UIColor colorWithWhite:0.7 alpha:1]
                       forState:UIControlStateDisabled];
    _activateBtn.titleLabel.font    = [UIFont boldSystemFontOfSize:14];
    _activateBtn.backgroundColor    = [UIColor colorWithRed:0.14 green:0.52 blue:0.28 alpha:1];
    _activateBtn.layer.cornerRadius = 11;
    _activateBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [_activateBtn addTarget:self action:@selector(tapActivate)
           forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:_activateBtn];

    // Footer
    UILabel *footer = [UILabel new];
    footer.text          = @"Dylib By Mochi — v2.1";
    footer.textColor     = [UIColor colorWithWhite:0.22 alpha:1];
    footer.font          = [UIFont systemFontOfSize:10];
    footer.textAlignment = NSTextAlignmentCenter;
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:footer];

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-30],
        [card.widthAnchor constraintEqualToConstant:300],

        [icon.topAnchor constraintEqualToAnchor:card.topAnchor constant:28],
        [icon.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],

        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:10],
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

    // Keyboard dismiss on bg tap
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(bgTap)];
    tap.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tap];
}

- (void)bgTap { [_keyField resignFirstResponder]; }

- (void)keyFieldChanged {
    NSString *t = _keyField.text;
    // Auto-format: insert dashes after every 4 chars
    NSString *stripped = [[t uppercaseString]
        stringByReplacingOccurrencesOfString:@"-" withString:@""];
    if (stripped.length > 16) stripped = [stripped substringToIndex:16];
    NSMutableString *formatted = [NSMutableString new];
    for (NSUInteger i = 0; i < stripped.length; i++) {
        if (i > 0 && i % 4 == 0) [formatted appendString:@"-"];
        [formatted appendString:[stripped substringWithRange:NSMakeRange(i, 1)]];
    }
    if (![_keyField.text isEqualToString:formatted]) {
        _keyField.text = formatted;
    }
    _statusLabel.text = @"";
}

- (void)tapActivate {
    NSString *key = [_keyField.text
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (key.length < 4) {
        _statusLabel.text = @"Please enter your activation key.";
        return;
    }
    [_keyField resignFirstResponder];
    [self setLoading:YES];

    performKeyAuth(key, ^(BOOL ok, NSTimeInterval expiry, NSString *errorMsg) {
        [self setLoading:NO];
        if (ok) {
            saveSavedKey(key);
            gKeyExpiry = expiry;
            saveExpiryLocally(expiry);
            [UIView animateWithDuration:0.2 animations:^{ self.alpha = 0; }
                             completion:^(BOOL _) {
                [self removeFromSuperview];
                if (self->_completion) self->_completion(key);
            }];
        } else {
            clearSavedKey();
            _statusLabel.text  = errorMsg ?: @"Activation failed.";
            _statusLabel.textColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1];
            [UIView animateWithDuration:0.05 delay:0 options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat animations:^{
                [UIView setAnimationRepeatCount:4];
                _keyField.transform = CGAffineTransformMakeTranslation(6, 0);
            } completion:^(BOOL __) {
                _keyField.transform = CGAffineTransformIdentity;
            }];
            // Close app after short delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    exit(0);
                });
        }
    });
}

- (void)setLoading:(BOOL)loading {
    _activateBtn.enabled = !loading;
    _keyField.enabled    = !loading;
    _spinner.hidden      = !loading;
    if (loading) [_spinner startAnimating]; else [_spinner stopAnimating];
    if (loading) _statusLabel.text = @"Verifying key…";
}
@end

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Upload  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
static void performUpload(NSArray<NSString *> *fileNames,
                          SKProgressOverlay *ov,
                          void (^done)(NSString *link, NSString *err)) {
    NSString *uuid    = deviceUUID();
    NSURLSession *ses = makeSession();
    NSString *docs    = NSSearchPathForDirectoriesInDomains(
                            NSDocumentDirectory, NSUserDomainMask, YES).firstObject;

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

    MPRequest initMP = buildMP(
        @{@"action":@"upload", @"uuid":uuid, @"playerpref":plistXML}, nil, nil, nil);
    [ov setProgress:0.05 label:@"5%"];

    skPost(ses, initMP.req, initMP.body, ^(NSDictionary *j, NSError *err) {
        if (err) { done(nil, [NSString stringWithFormat:@"Init failed: %@", err.localizedDescription]); return; }
        NSString *link = j[@"link"] ?: [NSString stringWithFormat:
            @"https://chillysilly.frfrnocap.men/isk.php?view=%@", uuid];
        [ov appendLog:@"Session created ✓"];
        [ov appendLog:[NSString stringWithFormat:@"Link: %@", link]];
        saveSessionUUID(uuid);
        if (!fileNames.count) { done(link, nil); return; }
        [ov appendLog:@"Uploading .data files (parallel)…"];
        NSUInteger total = fileNames.count;
        __block NSUInteger doneN = 0, failN = 0;
        dispatch_group_t group = dispatch_group_create();
        for (NSString *fname in fileNames) {
            NSString *path = [docs stringByAppendingPathComponent:fname];
            NSString *textContent = [NSString stringWithContentsOfFile:path
                encoding:NSUTF8StringEncoding error:nil];
            if (!textContent) {
                [ov appendLog:[NSString stringWithFormat:@"⚠ Skip %@ (unreadable)", fname]];
                @synchronized(fileNames) { doneN++; failN++; }
                float p = 0.1f + 0.88f * ((float)doneN / (float)total);
                [ov setProgress:p label:[NSString stringWithFormat:
                    @"%lu/%lu", (unsigned long)doneN, (unsigned long)total]];
                continue;
            }
            NSData *fdata = [textContent dataUsingEncoding:NSUTF8StringEncoding];
            [ov appendLog:[NSString stringWithFormat:@"↑ %@  (%lu chars)",
                fname, (unsigned long)textContent.length]];
            dispatch_group_enter(group);
            MPRequest fmp = buildMP(@{@"action":@"upload_file",@"uuid":uuid},
                @"datafile", fname, fdata);
            skPost(ses, fmp.req, fmp.body, ^(NSDictionary *fj, NSError *ferr) {
                @synchronized(fileNames) { doneN++; }
                if (ferr) {
                    @synchronized(fileNames) { failN++; }
                    [ov appendLog:[NSString stringWithFormat:@"✗ %@: %@",
                        fname, ferr.localizedDescription]];
                } else {
                    [ov appendLog:[NSString stringWithFormat:@"✓ %@", fname]];
                }
                float p = 0.10f + 0.88f * ((float)doneN / (float)total);
                [ov setProgress:p label:[NSString stringWithFormat:
                    @"%lu/%lu", (unsigned long)doneN, (unsigned long)total]];
                dispatch_group_leave(group);
            });
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (failN > 0)
                [ov appendLog:[NSString stringWithFormat:
                    @"⚠ %lu file(s) failed, %lu succeeded",
                    (unsigned long)failN, (unsigned long)(total - failN)]];
            done(link, nil);
        });
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Smart-diff batched NSUserDefaults writer  (unchanged)
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
                             NSUInteger start,
                             NSUInteger total,
                             SKProgressOverlay *ov,
                             void (^completion)(NSUInteger changed)) {
    if (start >= total) {
        @try { [ud synchronize]; } @catch (NSException *ex) {
            NSLog(@"[SKTools] ud synchronize exception: %@", ex.reason);
        }
        completion(total); return;
    }
    @autoreleasepool {
        NSUInteger end = MIN(start + kUDWriteBatchSize, total);
        for (NSUInteger i = start; i < end; i++) {
            NSString *k = keys[i]; id v = diff[k];
            if (!k || !v) continue;
            @try {
                if ([v isKindOfClass:[NSNull class]]) [ud removeObjectForKey:k];
                else                                  [ud setObject:v forKey:k];
            } @catch (NSException *ex) {
                NSLog(@"[SKTools] ud apply exception for key %@: %@", k, ex.reason);
            }
        }
        if (ov && (start == 0 || (end % 500 == 0) || end == total)) {
            [ov appendLog:[NSString stringWithFormat:
                @"  PlayerPrefs diff %lu/%lu…", (unsigned long)end, (unsigned long)total]];
            [ov setProgress:0.10f + 0.28f * ((float)end / (float)total)
                      label:[NSString stringWithFormat:
                @"%lu/%lu", (unsigned long)end, (unsigned long)total]];
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        _applyDiffBatch(ud, keys, diff, start + kUDWriteBatchSize, total, ov, completion);
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Write .data files  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
static void writeDataFiles(NSDictionary *dataMap,
                            SKProgressOverlay *ov,
                            void (^done)(NSUInteger appliedCount)) {
    NSString *docsPath = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![dataMap isKindOfClass:[NSDictionary class]] || !dataMap.count) {
        [ov appendLog:@"No .data files to write."]; done(0); return;
    }
    NSUInteger fileTotal = dataMap.count;
    __block NSUInteger fi = 0, applied = 0;
    for (NSString *fname in dataMap) {
        id rawValue = dataMap[fname];
        if (![rawValue isKindOfClass:[NSString class]] || !((NSString *)rawValue).length) {
            [ov appendLog:[NSString stringWithFormat:@"⚠ %@ — empty/invalid, skipped", fname]];
            fi++; continue;
        }
        NSString *textContent = (NSString *)rawValue;
        NSString *safeName    = [fname lastPathComponent];
        NSString *dst         = [docsPath stringByAppendingPathComponent:safeName];
        [fm removeItemAtPath:dst error:nil];
        NSError *we = nil;
        BOOL ok = [textContent writeToFile:dst atomically:YES
                                  encoding:NSUTF8StringEncoding error:&we];
        if (ok) {
            applied++;
            [ov appendLog:[NSString stringWithFormat:@"✓ %@  (%lu chars)",
                safeName, (unsigned long)textContent.length]];
        } else {
            [ov appendLog:[NSString stringWithFormat:@"✗ %@ write failed: %@",
                safeName, we.localizedDescription ?: @"Unknown error"]];
        }
        fi++;
        [ov setProgress:0.40f + 0.58f * ((float)fi / MAX(1.0f, (float)fileTotal))
                  label:[NSString stringWithFormat:
            @"%lu/%lu", (unsigned long)fi, (unsigned long)fileTotal]];
    }
    done(applied);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Load  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
static void performLoad(SKProgressOverlay *ov,
                        void (^done)(BOOL ok, NSString *msg)) {
    NSString *uuid = loadSessionUUID();
    if (!uuid.length) { done(NO, @"No session found. Upload first."); return; }

    NSURLSession *ses = makeSession();
    [ov appendLog:[NSString stringWithFormat:@"Session: %@…",
                   [uuid substringToIndex:MIN(8u, (unsigned)uuid.length)]]];
    [ov appendLog:@"Requesting files from server…"];
    [ov setProgress:0.08 label:@"8%"];

    MPRequest mp = buildMP(@{@"action":@"load", @"uuid":uuid}, nil, nil, nil);
    skPost(ses, mp.req, mp.body, ^(NSDictionary *j, NSError *err) {
        if (err) { done(NO, [NSString stringWithFormat:@"✗ Load failed: %@", err.localizedDescription]); return; }
        if ([j[@"changed"] isEqual:@NO] || [j[@"changed"] isEqual:@0]) {
            clearSessionUUID();
            done(YES, @"ℹ Server reports no changes. Nothing applied."); return;
        }
        [ov setProgress:0.10 label:@"10%"];
        NSString *ppXML       = j[@"playerpref"];
        NSDictionary *dataMap = j[@"data"];
        if (!ppXML.length) {
            [ov appendLog:@"No PlayerPrefs — writing .data files only."];
            writeDataFiles(dataMap, ov, ^(NSUInteger applied) {
                clearSessionUUID();
                done(YES, [NSString stringWithFormat:
                    @"✓ Loaded %lu file(s). Restart game.", (unsigned long)applied]);
            }); return;
        }
        [ov appendLog:@"Parsing PlayerPrefs…"];
        NSError *pe = nil; NSDictionary *incoming = nil;
        @try {
            incoming = [NSPropertyListSerialization
                propertyListWithData:[ppXML dataUsingEncoding:NSUTF8StringEncoding]
                             options:NSPropertyListMutableContainersAndLeaves
                              format:nil error:&pe];
        } @catch (NSException *ex) {
            [ov appendLog:[NSString stringWithFormat:@"⚠ plist exception: %@", ex.reason]];
            incoming = nil;
        }
        if (pe || ![incoming isKindOfClass:[NSDictionary class]]) {
            NSString *reason = pe.localizedDescription ?: @"Not a dictionary";
            [ov appendLog:[NSString stringWithFormat:@"⚠ PlayerPrefs parse failed: %@", reason]];
            [ov appendLog:@"Continuing with .data files only…"];
            writeDataFiles(dataMap, ov, ^(NSUInteger applied) {
                clearSessionUUID();
                done(applied > 0,
                    applied > 0
                    ? [NSString stringWithFormat:
                        @"⚠ PlayerPrefs failed (parse error), %lu file(s) applied. Restart.",
                        (unsigned long)applied]
                    : @"✗ PlayerPrefs parse failed and no .data files written.");
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
                    @"✓ PlayerPrefs identical (skipped), %lu file(s) applied. Restart.",
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
            [ov appendLog:[NSString stringWithFormat:
                @"PlayerPrefs ✓ (%lu keys changed)", (unsigned long)changed]];
            writeDataFiles(dataMap, ov, ^(NSUInteger filesApplied) {
                clearSessionUUID();
                NSUInteger totalApplied = (changed > 0 ? 1 : 0) + filesApplied;
                done(YES, [NSString stringWithFormat:
                    @"✓ Loaded %lu item(s). Restart the game.", (unsigned long)totalApplied]);
            });
        });
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SKSettingsMenu  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
static const CGFloat kSWScale = 0.75f;

@interface SKSettingsMenu : UIView
@end

@implementation SKSettingsMenu {
    UIView   *_card;
    UISwitch *_rijSwitch;
    UISwitch *_uidSwitch;
    UISwitch *_closeSwitch;
}
+ (instancetype)showInView:(UIView *)parent {
    SKSettingsMenu *m = [[SKSettingsMenu alloc] initWithFrame:parent.bounds];
    m.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
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
        [nameL.leadingAnchor  constraintEqualToAnchor:row.leadingAnchor constant:12],
        [nameL.topAnchor      constraintEqualToAnchor:row.topAnchor constant:10],
        [nameL.trailingAnchor constraintLessThanOrEqualToAnchor:swCont.leadingAnchor constant:-8],
        [descL.leadingAnchor  constraintEqualToAnchor:row.leadingAnchor constant:12],
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
    UILabel *titleL = [UILabel new];
    titleL.text = @"⚙  Settings"; titleL.textColor = [UIColor whiteColor];
    titleL.font = [UIFont boldSystemFontOfSize:15]; titleL.textAlignment = NSTextAlignmentCenter;
    titleL.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:titleL];
    UIView *div = [UIView new];
    div.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
    div.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:div];
    UIView *rijRow = [self rowWithTitle:@"Auto Rij"
        description:@"Before uploading, sets all OpenRijTest_ flags from 1 → 0 in PlayerPrefs."
        swRef:&_rijSwitch tag:1];
    [_card addSubview:rijRow];
    UIView *uidRow = [self rowWithTitle:@"Auto Detect UID"
        description:@"Reads PlayerId from SdkStateCache#1 — no manual UID entry needed."
        swRef:&_uidSwitch tag:2];
    [_card addSubview:uidRow];
    UIView *closeRow = [self rowWithTitle:@"Auto Close"
        description:@"Terminates the app once save data has finished loading from cloud."
        swRef:&_closeSwitch tag:3];
    [_card addSubview:closeRow];
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [closeBtn setTitle:@"Close" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font    = [UIFont boldSystemFontOfSize:13];
    closeBtn.backgroundColor    = [UIColor colorWithWhite:0.20 alpha:1];
    closeBtn.layer.cornerRadius = 9;
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [closeBtn addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
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
        [titleL.topAnchor      constraintEqualToAnchor:handle.bottomAnchor constant:8],
        [titleL.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor constant:16],
        [titleL.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-16],
        [div.topAnchor      constraintEqualToAnchor:titleL.bottomAnchor constant:10],
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
    CGRect  f = _card.frame;
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
// MARK: - SKPanel  (modified — added expiry label + expiry timer)
// ─────────────────────────────────────────────────────────────────────────────
static const CGFloat kPW = 258;
static const CGFloat kBH = 46;
static const CGFloat kCH = 188;  // increased from 168 to fit expiry label

@interface SKPanel : UIView
@property (nonatomic, strong) UIView   *content;
@property (nonatomic, strong) UILabel  *statusLabel;
@property (nonatomic, strong) UILabel  *uidLabel;
@property (nonatomic, strong) UILabel  *expiryLabel;   // NEW
@property (nonatomic, strong) UIButton *uploadBtn;
@property (nonatomic, strong) UIButton *loadBtn;
@property (nonatomic, assign) BOOL     expanded;
@property (nonatomic, strong) NSTimer  *expiryTimer;   // NEW
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
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(kPW/2-20, 8, 40, 3)];
    h.backgroundColor    = [UIColor colorWithWhite:0.45 alpha:0.5];
    h.layer.cornerRadius = 1.5;
    [self addSubview:h];
    UILabel *t = [UILabel new];
    t.text = @"⚙  SK Save Manager";
    t.textColor = [UIColor colorWithWhite:0.82 alpha:1];
    t.font = [UIFont boldSystemFontOfSize:12];
    t.textAlignment = NSTextAlignmentCenter;
    t.frame = CGRectMake(0, 14, kPW, 22);
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
    self.uidLabel.font          = [UIFont fontWithName:@"Courier" size:9]
                                 ?: [UIFont systemFontOfSize:9];
    self.uidLabel.textColor     = [UIColor colorWithRed:0.35 green:0.90 blue:0.55 alpha:1];
    self.uidLabel.textAlignment = NSTextAlignmentCenter;
    self.uidLabel.text          = @"";
    [self.content addSubview:self.uidLabel];

    // NEW: Key expiry label
    self.expiryLabel = [UILabel new];
    self.expiryLabel.frame         = CGRectMake(pad, 32, w, 12);
    self.expiryLabel.font          = [UIFont systemFontOfSize:9];
    self.expiryLabel.textColor     = [UIColor colorWithRed:0.85 green:0.70 blue:0.20 alpha:1];
    self.expiryLabel.textAlignment = NSTextAlignmentCenter;
    self.expiryLabel.text          = @"";
    [self.content addSubview:self.expiryLabel];

    self.uploadBtn = [self btn:@"⬆  Upload to Cloud"
                         color:[UIColor colorWithRed:0.14 green:0.56 blue:0.92 alpha:1]
                         frame:CGRectMake(pad, 50, w, 42)
                        action:@selector(tapUpload)];
    [self.content addSubview:self.uploadBtn];

    self.loadBtn = [self btn:@"⬇  Load from Cloud"
                       color:[UIColor colorWithRed:0.18 green:0.70 blue:0.42 alpha:1]
                       frame:CGRectMake(pad, 98, w, 42)
                      action:@selector(tapLoad)];
    [self.content addSubview:self.loadBtn];

    CGFloat halfW = (w - 6) / 2;
    UIButton *settingsBtn = [self btn:@"⚙ Settings"
                                color:[UIColor colorWithRed:0.22 green:0.22 blue:0.30 alpha:1]
                                frame:CGRectMake(pad, 148, halfW, 30)
                               action:@selector(tapSettings)];
    settingsBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [self.content addSubview:settingsBtn];

    UIButton *hideBtn = [self btn:@"✕ Hide Menu"
                            color:[UIColor colorWithRed:0.30 green:0.12 blue:0.12 alpha:1]
                            frame:CGRectMake(pad + halfW + 6, 148, halfW, 30)
                           action:@selector(tapHide)];
    hideBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [self.content addSubview:hideBtn];

    [self refreshStatus];
    [self startExpiryTimer];
}

// NEW: expiry timer — updates every 30s while expanded
- (void)startExpiryTimer {
    [self.expiryTimer invalidate];
    self.expiryTimer = [NSTimer scheduledTimerWithTimeInterval:30
        target:self selector:@selector(refreshExpiry) userInfo:nil repeats:YES];
}

- (void)refreshExpiry {
    NSTimeInterval expiry = gKeyExpiry > 0 ? gKeyExpiry : loadExpiryLocally();
    NSString *expiryStr = expiryDisplayString(expiry);
    if ([expiryStr hasPrefix:@"Key: EXPIRED"]) {
        self.expiryLabel.textColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1];
    } else {
        self.expiryLabel.textColor = [UIColor colorWithRed:0.85 green:0.70 blue:0.20 alpha:1];
    }
    self.expiryLabel.text = expiryStr;
}

- (UIButton *)btn:(NSString *)t color:(UIColor *)c frame:(CGRect)f action:(SEL)s {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f; b.backgroundColor = c; b.layer.cornerRadius = 9;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:0.80 alpha:1] forState:UIControlStateHighlighted];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)refreshStatus {
    NSString *uuid = loadSessionUUID();
    self.statusLabel.text = uuid
        ? [NSString stringWithFormat:@"Session: %@…",
           [uuid substringToIndex:MIN(8u, (unsigned)uuid.length)]]
        : @"No active session";
    if (getSetting(@"autoDetectUID")) {
        NSString *uid = detectPlayerUID();
        self.uidLabel.text = uid
            ? [NSString stringWithFormat:@"UID: %@", uid]
            : @"UID: not found";
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
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.18 delay:0
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
            CGRect f = self.frame; f.size.height = kBH; self.frame = f;
            self.content.alpha = 0;
        } completion:^(BOOL _){ self.content.hidden = YES; }];
    }
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
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Hide"
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
            [self.expiryTimer invalidate];
            [UIView animateWithDuration:0.2 animations:^{
                self.alpha = 0; self.transform = CGAffineTransformMakeScale(0.85f, 0.85f);
            } completion:^(BOOL __) { [self removeFromSuperview]; }];
        }]];
    [[self topVC] presentViewController:a animated:YES completion:nil];
}

- (void)tapUpload {
    NSString *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *all = [[NSFileManager defaultManager]
                    contentsOfDirectoryAtPath:docs error:nil] ?: @[];
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
            existing ? @"⚠ Existing session will be overwritten." : @""]
                  preferredStyle:UIAlertControllerStyleAlert];
    [choice addAction:[UIAlertAction
        actionWithTitle:[NSString stringWithFormat:@"Upload All (%lu files)",
                         (unsigned long)dataFiles.count]
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) { [self confirmAndUpload:dataFiles]; }]];
    [choice addAction:[UIAlertAction
        actionWithTitle:@"Specific UID…"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            if (getSetting(@"autoDetectUID")) {
                NSString *uid = detectPlayerUID();
                if (!uid.length) {
                    [self showAlert:@"Auto Detect UID"
                            message:@"PlayerId not found.\nPlease enter UID manually."];
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
    [choice addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
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
                        message:[NSString stringWithFormat:
                    @"No .data file contains UID \"%@\" in its name.", uid]]; return;
            }
            [self confirmAndUpload:filtered];
        }]];
    [input addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
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
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Yes, Upload"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            UIView *parent = [self topVC].view ?: self.superview;
            SKProgressOverlay *ov = [SKProgressOverlay showInView:parent title:@"Uploading save data…"];
            performUpload(files, ov, ^(NSString *link, NSString *err) {
                [self refreshStatus];
                if (err) {
                    [ov finish:NO message:[NSString stringWithFormat:@"✗ %@", err] link:nil];
                } else {
                    [UIPasteboard generalPasteboard].string = link;
                    [ov appendLog:@"Link copied to clipboard."];
                    [ov finish:YES message:@"Upload complete ✓" link:link];
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
        ? @"\n\n⚠ Auto Close is ON — app will exit after loading." : @"";
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Load Save"
                         message:[NSString stringWithFormat:
            @"Download edited save data and apply it?\n\n"
            @"Cloud session is deleted after loading.%@", closeNote]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Yes, Load"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIView *parent = [self topVC].view ?: self.superview;
        SKProgressOverlay *ov = [SKProgressOverlay showInView:parent title:@"Loading save data…"];
        performLoad(ov, ^(BOOL ok, NSString *msg) {
            [self refreshStatus];
            [ov finish:ok message:msg link:nil];
            if (ok && getSetting(@"autoClose")) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(1.6 * NSEC_PER_SEC)),
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
// MARK: - Injection  (modified — auth check before showing panel)
// ─────────────────────────────────────────────────────────────────────────────
static SKPanel *gPanel = nil;

static void showMainPanel(void) {
    UIWindow *win = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows)
        if (!w.isHidden && w.alpha > 0) { win = w; break; }
    if (!win) return;
    UIView *root = win.rootViewController.view ?: win;
    gPanel = [SKPanel new];
    gPanel.center = CGPointMake(
        root.bounds.size.width - gPanel.bounds.size.width/2 - 10, 88);
    [root addSubview:gPanel];
    [root bringSubviewToFront:gPanel];
    // Update expiry from cache
    NSTimeInterval exp = loadExpiryLocally();
    if (exp > 0) gKeyExpiry = exp;
    [gPanel refreshStatus];
}

// ─────────────────────────────────────────────────────────────────────────────
// Auth Gate:
//   1. If saved key found → silently re-auth (verifies key still valid + device binding)
//   2. If no saved key → show key entry overlay
//   3. On success → show main panel
//   4. On failure → show error + exit after delay
// ─────────────────────────────────────────────────────────────────────────────
static void injectPanel(void) {
    UIWindow *win = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows)
        if (!w.isHidden && w.alpha > 0) { win = w; break; }
    if (!win) return;
    UIView *root = win.rootViewController.view ?: win;

    NSString *savedKey = loadSavedKey();

    if (savedKey.length) {
        // Silent re-auth — show a small spinner indicator
        UIActivityIndicatorView *spinner =
            [[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spinner.color = [UIColor colorWithRed:0.18 green:0.78 blue:0.44 alpha:1];
        spinner.center = CGPointMake(root.bounds.size.width - 24, 80);
        spinner.autoresizingMask =
            UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
        [root addSubview:spinner];
        [spinner startAnimating];

        performKeyAuth(savedKey, ^(BOOL ok, NSTimeInterval expiry, NSString *errorMsg) {
            [spinner stopAnimating];
            [spinner removeFromSuperview];

            if (ok) {
                gKeyExpiry = expiry;
                saveExpiryLocally(expiry);
                showMainPanel();
            } else {
                // Key invalid/expired/banned — clear it, force re-entry
                clearSavedKey();
                NSLog(@"[SKTools] Saved key rejected: %@", errorMsg);

                // Show error then key-entry
                UIAlertController *alert = [UIAlertController
                    alertControllerWithTitle:@"Key Invalid"
                                     message:[NSString stringWithFormat:
                        @"%@\n\nPlease enter a valid key.", errorMsg ?: @"Authentication failed."]
                              preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Enter Key"
                    style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                        UIViewController *vc = win.rootViewController;
                        while (vc.presentedViewController) vc = vc.presentedViewController;
                        [SKKeyAuthOverlay showInView:vc.view completion:^(NSString *newKey) {
                            showMainPanel();
                        }];
                    }]];
                [alert addAction:[UIAlertAction actionWithTitle:@"Exit"
                    style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
                        exit(0);
                    }]];
                UIViewController *vc = win.rootViewController;
                while (vc.presentedViewController) vc = vc.presentedViewController;
                [vc presentViewController:alert animated:YES completion:nil];
            }
        });
    } else {
        // No saved key — show key entry overlay
        UIViewController *vc = win.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        [SKKeyAuthOverlay showInView:(vc.view ?: root) completion:^(NSString *key) {
            showMainPanel();
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
