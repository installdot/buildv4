// SKCrypto.h — Encryption, HMAC, and Keychain utilities
// Part of SKFramework · iOS 14+ · ARC · Theos/Logos compatible
//
// Provides:
//   • AES-256-CBC encryption/decryption with PKCS7 padding
//   • HMAC-SHA256 authentication tag (encrypt-then-MAC)
//   • JSON payload → Base64 "box" helpers
//   • Keychain read/write/delete (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
//   • Persistent device UUID (survives app reinstall via Keychain)
//   • Timestamp replay-guard file helpers
//
// REQUIRED FRAMEWORKS (add to Makefile / build settings):
//   $(THEOS_PROJECT_DIR)/frameworks: CommonCrypto, Security
//   Makefile:  XXX_FRAMEWORKS = Security
//              XXX_EXTRA_FRAMEWORKS = CommonCrypto   (usually implicit on iOS)

#pragma once
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §1  Key configuration — CHANGE BOTH BEFORE SHIPPING
//
// Both keys must be exactly 64 hex characters (= 32 raw bytes).
// AES key  → used for AES-256-CBC encryption/decryption.
// HMAC key → used for HMAC-SHA256 integrity tag (appended after ciphertext).
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the 64-char hex AES-256 key string.
/// Replace the value inside with your own secret before building.
static NSString *authAESKeyHex(void) {
    return @"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"; // ← CHANGE
}

/// Returns the 64-char hex HMAC-SHA256 key string.
/// Replace the value inside with your own secret before building.
static NSString *authHMACKeyHex(void) {
    return @"fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"; // ← CHANGE
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §2  Hex ↔ NSData
// ─────────────────────────────────────────────────────────────────────────────

/// Converts a hex string (e.g. @"deadbeef") to NSData.
/// Returns nil if `hex` is empty or malformed.
static NSData *SK_dataFromHexString(NSString *hex) {
    NSMutableData *d = [NSMutableData dataWithCapacity:hex.length / 2];
    for (NSUInteger i = 0; i + 2 <= hex.length; i += 2) {
        NSRange r = NSMakeRange(i, 2);
        NSString *byteStr = [hex substringWithRange:r];
        unsigned int byte = 0;
        [[NSScanner scannerWithString:byteStr] scanHexInt:&byte];
        uint8_t b = (uint8_t)byte;
        [d appendBytes:&b length:1];
    }
    return d;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §3  AES-256-CBC + HMAC-SHA256 (Encrypt-then-MAC)
//
// Wire format of the returned "box":
//   [ IV (16 bytes) | ciphertext (N bytes) | HMAC-SHA256 (32 bytes) ]
// ─────────────────────────────────────────────────────────────────────────────

/// Encrypts `plainData` and returns an authenticated ciphertext blob.
///
/// @param plainData  Raw bytes to protect.
/// @param aesKey     32-byte AES-256 key  (use SK_dataFromHexString(authAESKeyHex())).
/// @param hmacKey    32-byte HMAC key     (use SK_dataFromHexString(authHMACKeyHex())).
/// @return  Encrypted box, or nil on failure.
static NSData *SK_encryptBox(NSData *plainData, NSData *aesKey, NSData *hmacKey) {
    if (!plainData || !aesKey || aesKey.length != 32 || !hmacKey || hmacKey.length != 32) return nil;

    // --- generate random IV ---
    uint8_t iv[kCCBlockSizeAES128];
    (void)SecRandomCopyBytes(kSecRandomDefault, kCCBlockSizeAES128, iv);

    // --- AES-256-CBC encrypt ---
    size_t outLen = plainData.length + kCCBlockSizeAES128;
    NSMutableData *cipher = [NSMutableData dataWithLength:outLen];
    size_t moved = 0;
    CCCryptorStatus st = CCCrypt(
        kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
        aesKey.bytes, kCCKeySizeAES256, iv,
        plainData.bytes, plainData.length,
        cipher.mutableBytes, outLen, &moved);
    if (st != kCCSuccess) return nil;
    [cipher setLength:moved];

    // --- HMAC-SHA256 over IV + ciphertext ---
    NSMutableData *forHmac = [NSMutableData dataWithBytes:iv length:kCCBlockSizeAES128];
    [forHmac appendData:cipher];
    uint8_t hmac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, hmacKey.length,
           forHmac.bytes, forHmac.length, hmac);

    // --- assemble box ---
    NSMutableData *box = [NSMutableData dataWithBytes:iv length:kCCBlockSizeAES128];
    [box appendData:cipher];
    [box appendBytes:hmac length:CC_SHA256_DIGEST_LENGTH];
    return box;
}

/// Verifies the HMAC then decrypts a box produced by SK_encryptBox().
///
/// @return  Plaintext bytes, or nil if HMAC check fails or decryption errors.
static NSData *SK_decryptBox(NSData *box, NSData *aesKey, NSData *hmacKey) {
    if (!box || box.length < (kCCBlockSizeAES128 + CC_SHA256_DIGEST_LENGTH + 1)) return nil;
    if (!aesKey || aesKey.length != 32 || !hmacKey || hmacKey.length != 32) return nil;

    NSData *iv     = [box subdataWithRange:NSMakeRange(0, kCCBlockSizeAES128)];
    NSData *hmac   = [box subdataWithRange:
                        NSMakeRange(box.length - CC_SHA256_DIGEST_LENGTH, CC_SHA256_DIGEST_LENGTH)];
    NSData *cipher = [box subdataWithRange:
                        NSMakeRange(kCCBlockSizeAES128,
                                    box.length - kCCBlockSizeAES128 - CC_SHA256_DIGEST_LENGTH)];

    // --- verify HMAC ---
    NSMutableData *forHmac = [NSMutableData dataWithData:iv];
    [forHmac appendData:cipher];
    uint8_t calc[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, hmacKey.length,
           forHmac.bytes, forHmac.length, calc);
    if (![[NSData dataWithBytes:calc length:CC_SHA256_DIGEST_LENGTH] isEqualToData:hmac]) return nil;

    // --- AES-256-CBC decrypt ---
    size_t outLen = cipher.length + kCCBlockSizeAES128;
    NSMutableData *plain = [NSMutableData dataWithLength:outLen];
    size_t moved = 0;
    CCCryptorStatus st = CCCrypt(
        kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
        aesKey.bytes, kCCKeySizeAES256, iv.bytes,
        cipher.bytes, cipher.length,
        plain.mutableBytes, outLen, &moved);
    if (st != kCCSuccess) return nil;
    [plain setLength:moved];
    return plain;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §4  JSON ↔ Base64 encrypted payload helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Serialises `payload` → JSON → encrypted box → Base64 string.
/// Uses the keys returned by authAESKeyHex() / authHMACKeyHex().
/// @return  Base64 string, or nil on any error.
static NSString *SK_encryptPayloadToBase64(NSDictionary *payload) {
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!jsonData) return nil;
    NSData *box = SK_encryptBox(jsonData,
                                SK_dataFromHexString(authAESKeyHex()),
                                SK_dataFromHexString(authHMACKeyHex()));
    return box ? [box base64EncodedStringWithOptions:0] : nil;
}

/// Decodes a Base64 string → decrypted box → JSON dictionary.
/// Uses the keys returned by authAESKeyHex() / authHMACKeyHex().
/// @return  NSDictionary, or nil if decryption or JSON parsing fails.
static NSDictionary *SK_decryptBase64ToDict(NSString *b64) {
    if (!b64.length) return nil;
    NSData *box = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    if (!box) return nil;
    NSData *plain = SK_decryptBox(box,
                                  SK_dataFromHexString(authAESKeyHex()),
                                  SK_dataFromHexString(authHMACKeyHex()));
    if (!plain) return nil;
    return [NSJSONSerialization JSONObjectWithData:plain options:0 error:nil];
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §5  Keychain helpers
//
// Two logical "slots" are exposed:
//   kSKKCSvcDevID  — persistent device UUID (survives reinstalls)
//   kSKKCSvcKey    — auth key entered by the user
//
// Both share the account string kSKKCAccount.
// Accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
//                (available after first unlock, NOT backed up / NOT device-transferable)
// ─────────────────────────────────────────────────────────────────────────────

static NSString * const kSKKCSvcDevID  = @"SKToolsDevID";   ///< Keychain service for device UUID
static NSString * const kSKKCSvcKey    = @"SKToolsAuthKey"; ///< Keychain service for auth key
static NSString * const kSKKCAccount   = @"sktools";        ///< Shared account string

/// Builds the base Keychain attribute dictionary for a given service.
static NSDictionary *SK_kcBaseQuery(NSString *service) {
    return @{
        (__bridge id)kSecClass:              (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:        service,
        (__bridge id)kSecAttrAccount:        kSKKCAccount,
        (__bridge id)kSecAttrAccessible:     (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        (__bridge id)kSecAttrSynchronizable: @NO,
    };
}

/// Reads a UTF-8 string from the Keychain for `service`. Returns nil if not found.
static NSString *SK_kcRead(NSString *service) {
    NSMutableDictionary *q = [NSMutableDictionary dictionaryWithDictionary:SK_kcBaseQuery(service)];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &result);
    if (st != errSecSuccess || !result) return nil;
    NSData *data = (__bridge NSData *)result;
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    CFRelease(result);
    return str;
}

/// Writes `value` as UTF-8 to the Keychain for `service`. Returns YES on success.
static BOOL SK_kcWrite(NSString *service, NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return NO;
    NSMutableDictionary *qFind = [NSMutableDictionary dictionaryWithDictionary:SK_kcBaseQuery(service)];
    NSDictionary *update = @{ (__bridge id)kSecValueData: data };
    OSStatus st = SecItemUpdate((__bridge CFDictionaryRef)qFind, (__bridge CFDictionaryRef)update);
    if (st == errSecItemNotFound) {
        NSMutableDictionary *qAdd = [NSMutableDictionary dictionaryWithDictionary:SK_kcBaseQuery(service)];
        qAdd[(__bridge id)kSecValueData] = data;
        st = SecItemAdd((__bridge CFDictionaryRef)qAdd, NULL);
    }
    return st == errSecSuccess;
}

/// Deletes the Keychain item for `service`.
static void SK_kcDelete(NSString *service) {
    SecItemDelete((__bridge CFDictionaryRef)SK_kcBaseQuery(service));
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §6  Persistent device UUID
// ─────────────────────────────────────────────────────────────────────────────

/// Returns a stable UUID for this device/app combo.
/// Generated once and stored in the Keychain so it survives app reinstalls.
static NSString *SK_persistentDeviceID(void) {
    NSString *existing = SK_kcRead(kSKKCSvcDevID);
    if (existing.length) return existing;
    NSString *newUUID = [[NSUUID UUID] UUIDString];
    SK_kcWrite(kSKKCSvcDevID, newUUID);
    return newUUID;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §7  Auth-key Keychain convenience wrappers
// ─────────────────────────────────────────────────────────────────────────────

/// Loads the saved auth key from Keychain. Returns nil if not stored yet.
static NSString *SK_loadSavedKey(void)        { return SK_kcRead(kSKKCSvcKey); }

/// Saves the auth key to Keychain.
static void      SK_saveSavedKey(NSString *k) { SK_kcWrite(kSKKCSvcKey, k); }

/// Removes the auth key from Keychain (e.g. after failed re-validation).
static void      SK_clearSavedKey(void)       { SK_kcDelete(kSKKCSvcKey); }

// ─────────────────────────────────────────────────────────────────────────────
// MARK: §8  Timestamp replay-guard file
//
// A last-sent timestamp is persisted to a flat file so we can detect
// replay attacks between requests.
// ─────────────────────────────────────────────────────────────────────────────

/// Filesystem path for the replay-guard timestamp file.
static NSString *SK_tsGuardFilePath(void) {
    return [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Preferences/SKToolsLastTS.txt"];
}

/// Persists `ts` (Unix epoch) to the replay-guard file.
static void SK_saveLastSentTS(NSTimeInterval ts) {
    [[NSString stringWithFormat:@"%.0f", ts]
        writeToFile:SK_tsGuardFilePath() atomically:YES
           encoding:NSUTF8StringEncoding error:nil];
}

/// Reads the last persisted timestamp from the replay-guard file (0 if missing).
static NSTimeInterval SK_loadLastSentTS(void) {
    NSString *s = [NSString stringWithContentsOfFile:SK_tsGuardFilePath()
                                             encoding:NSUTF8StringEncoding error:nil];
    return s.doubleValue;
}

#pragma clang diagnostic pop
