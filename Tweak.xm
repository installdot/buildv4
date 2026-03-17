#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#import <dlfcn.h>
#import <substrate.h>

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Helpers
// ═══════════════════════════════════════════════════════════════════════════════

// Full hex — no truncation
NSString* hexString(const void *bytes, size_t length) {
    if (!bytes || length == 0) return @"<empty>";
    const unsigned char *buf = (const unsigned char *)bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:(length * 2)];
    for (size_t i = 0; i < length; i++)
        [hex appendFormat:@"%02x", buf[i]];
    return hex;
}

// Serial log queue — prevents interleaved writes from concurrent hooks
static dispatch_queue_t logQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ q = dispatch_queue_create("com.cryptohook.log", DISPATCH_QUEUE_SERIAL); });
    return q;
}

// ── Atomic counter for unique bin filenames ───────────────────────────────────
static uint64_t blobCounter = 0;

// Returns the Documents directory path
static NSString *docsPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
}

// Write text log entry (appends to crypto_log.txt)
void saveLog(NSString *text) {
    dispatch_async(logQueue(), ^{
        NSString *path = [docsPath() stringByAppendingPathComponent:@"crypto_log.txt"];
        NSString *timestamped = [NSString stringWithFormat:@"%@ %@\n",
            [[NSDate date] description], text];
        NSData *data = [timestamped dataUsingEncoding:NSUTF8StringEncoding];

        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) {
            [data writeToFile:path atomically:YES];
        } else {
            [fh seekToEndOfFile];
            [fh writeData:data];
            [fh closeFile];
        }
    });
}

// Save raw bytes to a uniquely named .bin file and return the filename
// so the text log can reference it.
// Files land at: ~/Documents/blobs/<counter>_<tag>.bin
NSString* saveBlob(const void *bytes, size_t length, NSString *tag) {
    if (!bytes || length == 0) return nil;

    uint64_t idx = __sync_fetch_and_add(&blobCounter, 1);

    // Sanitise tag for use in a filename
    NSString *safeTag = [[tag componentsSeparatedByCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@"/ |[]():"]]
        componentsJoinedByString:@"_"];

    NSString *blobDir = [docsPath() stringByAppendingPathComponent:@"blobs"];

    // Ensure blobs/ directory exists
    [[NSFileManager defaultManager]
        createDirectoryAtPath:blobDir
        withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *filename = [NSString stringWithFormat:@"%06llu_%@.bin", (unsigned long long)idx, safeTag];
    NSString *fullPath = [blobDir stringByAppendingPathComponent:filename];

    NSData *blob = [NSData dataWithBytes:bytes length:length];
    dispatch_async(logQueue(), ^{
        [blob writeToFile:fullPath atomically:YES];
    });

    return filename;
}

// Convenience: log a field, save the raw bytes, and embed the filename reference
NSString* fieldWithBlob(NSString *label, const void *bytes, size_t length, NSString *blobTag) {
    if (!bytes || length == 0)
        return [NSString stringWithFormat:@"  %@: <empty>", label];

    NSString *blobFile = saveBlob(bytes, length, blobTag);
    return [NSString stringWithFormat:@"  %@ (%zu bytes): %@\n  %@ blob → blobs/%@",
        label, length,
        hexString(bytes, length),   // full hex, no truncation
        label, blobFile
    ];
}

void logSection(NSString *tag, NSString *body) {
    NSString *entry = [NSString stringWithFormat:
        @"\n┌─[%@]\n%@\n└─────────────────────────", tag, body];
    saveLog(entry);
    NSLog(@"[CryptoHook]%@", entry);
}

// ─── CommonCrypto Helpers ─────────────────────────────────────────────────────

NSString* cc_algorithmName(CCAlgorithm alg) {
    switch (alg) {
        case kCCAlgorithmAES:      return @"AES";
        case kCCAlgorithmDES:      return @"DES";
        case kCCAlgorithm3DES:     return @"3DES";
        case kCCAlgorithmCAST:     return @"CAST";
        case kCCAlgorithmRC4:      return @"RC4";
        case kCCAlgorithmRC2:      return @"RC2";
        case kCCAlgorithmBlowfish: return @"Blowfish";
        default:                   return [NSString stringWithFormat:@"Unknown(%u)", alg];
    }
}

NSString* cc_operationName(CCOperation op) {
    return (op == kCCDecrypt) ? @"DECRYPT" : @"ENCRYPT";
}

size_t cc_ivSize(CCAlgorithm alg) {
    switch (alg) {
        case kCCAlgorithm3DES: return kCCBlockSize3DES;
        case kCCAlgorithmDES:  return kCCBlockSizeDES;
        case kCCAlgorithmCAST: return kCCBlockSizeCAST;
        case kCCAlgorithmRC2:  return kCCBlockSizeRC2;
        default:               return kCCBlockSizeAES128;
    }
}

void logCCCipher(NSString *tag, CCOperation op, CCAlgorithm alg,
                 const void *key, size_t keyLen,
                 const void *iv,
                 const void *dataIn, size_t dataInLen)
{
    size_t ivLen = cc_ivSize(alg);
    NSString *body = [NSString stringWithFormat:
        @"  Op:   %@\n"
         "  Algo: %@\n"
         "%@\n"
         "  IV:   %@\n"
         "%@",
        cc_operationName(op),
        cc_algorithmName(alg),
        fieldWithBlob(@"Key",   key,    keyLen,    [NSString stringWithFormat:@"%@_%@_key",   tag, cc_algorithmName(alg)]),
        iv ? hexString(iv, ivLen) : @"NULL",
        dataIn ? fieldWithBlob(@"Input", dataIn, dataInLen, [NSString stringWithFormat:@"%@_%@_input", tag, cc_operationName(op)])
               : @"  Input: NULL"
    ];
    logSection([NSString stringWithFormat:@"CommonCrypto | %@", tag], body);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - CommonCrypto — Cipher
// ═══════════════════════════════════════════════════════════════════════════════

static CCCryptorStatus (*orig_CCCrypt)(
    CCOperation, CCAlgorithm, CCOptions,
    const void *, size_t, const void *,
    const void *, size_t, void *, size_t, size_t *);

CCCryptorStatus replaced_CCCrypt(
    CCOperation op, CCAlgorithm alg, CCOptions options,
    const void *key, size_t keyLen, const void *iv,
    const void *dataIn, size_t dataInLen,
    void *dataOut, size_t dataOutAvail, size_t *dataOutMoved)
{
    logCCCipher(@"CCCrypt", op, alg, key, keyLen, iv, dataIn, dataInLen);
    CCCryptorStatus status = orig_CCCrypt(op, alg, options, key, keyLen, iv,
                                          dataIn, dataInLen,
                                          dataOut, dataOutAvail, dataOutMoved);
    if (dataOut && *dataOutMoved > 0)
        saveBlob(dataOut, *dataOutMoved,
            [NSString stringWithFormat:@"CCCrypt_%@_output", cc_operationName(op)]);
    return status;
}

static CCCryptorStatus (*orig_CCCryptorCreate)(
    CCOperation, CCAlgorithm, CCOptions,
    const void *, size_t, const void *, CCCryptorRef *);

CCCryptorStatus replaced_CCCryptorCreate(
    CCOperation op, CCAlgorithm alg, CCOptions options,
    const void *key, size_t keyLen, const void *iv, CCCryptorRef *ref)
{
    logCCCipher(@"CCCryptorCreate", op, alg, key, keyLen, iv, NULL, 0);
    return orig_CCCryptorCreate(op, alg, options, key, keyLen, iv, ref);
}

static CCCryptorStatus (*orig_CCCryptorCreateFromData)(
    CCOperation, CCAlgorithm, CCOptions,
    const void *, size_t, const void *,
    const void *, size_t, CCCryptorRef *, size_t *);

CCCryptorStatus replaced_CCCryptorCreateFromData(
    CCOperation op, CCAlgorithm alg, CCOptions options,
    const void *key, size_t keyLen, const void *iv,
    const void *data, size_t dataLen, CCCryptorRef *ref, size_t *dataUsed)
{
    logCCCipher(@"CCCryptorCreateFromData", op, alg, key, keyLen, iv, data, dataLen);
    return orig_CCCryptorCreateFromData(op, alg, options, key, keyLen, iv,
                                        data, dataLen, ref, dataUsed);
}

static CCCryptorStatus (*orig_CCCryptorUpdate)(
    CCCryptorRef, const void *, size_t, void *, size_t, size_t *);

CCCryptorStatus replaced_CCCryptorUpdate(
    CCCryptorRef ref, const void *dataIn, size_t dataInLen,
    void *dataOut, size_t dataOutAvail, size_t *dataOutMoved)
{
    logSection(@"CommonCrypto | CCCryptorUpdate",
        fieldWithBlob(@"Input", dataIn, dataInLen, @"CCCryptorUpdate_input"));

    CCCryptorStatus status = orig_CCCryptorUpdate(ref, dataIn, dataInLen,
                                                   dataOut, dataOutAvail, dataOutMoved);
    if (dataOut && *dataOutMoved > 0)
        saveBlob(dataOut, *dataOutMoved, @"CCCryptorUpdate_output");
    return status;
}

static CCCryptorStatus (*orig_CCCryptorFinal)(CCCryptorRef, void *, size_t, size_t *);

CCCryptorStatus replaced_CCCryptorFinal(
    CCCryptorRef ref, void *dataOut, size_t dataOutAvail, size_t *dataOutMoved)
{
    CCCryptorStatus status = orig_CCCryptorFinal(ref, dataOut, dataOutAvail, dataOutMoved);
    NSString *outField = (dataOut && *dataOutMoved > 0)
        ? fieldWithBlob(@"Output", dataOut, *dataOutMoved, @"CCCryptorFinal_output")
        : @"  Output: <empty>";
    logSection(@"CommonCrypto | CCCryptorFinal",
        [NSString stringWithFormat:@"%@\n  Status: %d", outField, status]);
    return status;
}

static CCCryptorStatus (*orig_CCCryptorReset)(CCCryptorRef, const void *);

CCCryptorStatus replaced_CCCryptorReset(CCCryptorRef ref, const void *iv) {
    logSection(@"CommonCrypto | CCCryptorReset", [NSString stringWithFormat:
        @"  New IV: %@", iv ? hexString(iv, 16) : @"NULL"]);
    return orig_CCCryptorReset(ref, iv);
}

static CCCryptorStatus (*orig_CCCryptorRelease)(CCCryptorRef);

CCCryptorStatus replaced_CCCryptorRelease(CCCryptorRef ref) {
    logSection(@"CommonCrypto | CCCryptorRelease", @"  Cryptor context destroyed");
    return orig_CCCryptorRelease(ref);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - CommonCrypto — Digest
// ═══════════════════════════════════════════════════════════════════════════════

#define DEFINE_DIGEST_HOOK(name, digestLen) \
static unsigned char *(*orig_##name)(const void *, CC_LONG, unsigned char *); \
unsigned char *replaced_##name(const void *data, CC_LONG len, unsigned char *md) { \
    unsigned char *result = orig_##name(data, len, md); \
    NSString *body = [NSString stringWithFormat:@"%@\n  Digest: %@", \
        fieldWithBlob(@"Input", data, len, @#name "_input"), \
        hexString(md, digestLen)]; \
    logSection(@"Digest | " @#name, body); \
    saveBlob(md, digestLen, @#name "_digest"); \
    return result; \
}

DEFINE_DIGEST_HOOK(CC_MD5,    CC_MD5_DIGEST_LENGTH)
DEFINE_DIGEST_HOOK(CC_SHA1,   CC_SHA1_DIGEST_LENGTH)
DEFINE_DIGEST_HOOK(CC_SHA256, CC_SHA256_DIGEST_LENGTH)
DEFINE_DIGEST_HOOK(CC_SHA384, CC_SHA384_DIGEST_LENGTH)
DEFINE_DIGEST_HOOK(CC_SHA512, CC_SHA512_DIGEST_LENGTH)

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - CommonCrypto — HMAC
// ═══════════════════════════════════════════════════════════════════════════════

NSString* hmacAlgoName(CCHmacAlgorithm alg) {
    switch (alg) {
        case kCCHmacAlgMD5:    return @"HMAC-MD5";
        case kCCHmacAlgSHA1:   return @"HMAC-SHA1";
        case kCCHmacAlgSHA256: return @"HMAC-SHA256";
        case kCCHmacAlgSHA384: return @"HMAC-SHA384";
        case kCCHmacAlgSHA512: return @"HMAC-SHA512";
        case kCCHmacAlgSHA224: return @"HMAC-SHA224";
        default:               return [NSString stringWithFormat:@"HMAC-Unknown(%u)", alg];
    }
}

size_t hmacOutputSize(CCHmacAlgorithm alg) {
    switch (alg) {
        case kCCHmacAlgMD5:    return CC_MD5_DIGEST_LENGTH;
        case kCCHmacAlgSHA1:   return CC_SHA1_DIGEST_LENGTH;
        case kCCHmacAlgSHA256: return CC_SHA256_DIGEST_LENGTH;
        case kCCHmacAlgSHA384: return CC_SHA384_DIGEST_LENGTH;
        case kCCHmacAlgSHA512: return CC_SHA512_DIGEST_LENGTH;
        case kCCHmacAlgSHA224: return CC_SHA224_DIGEST_LENGTH;
        default:               return 32;
    }
}

static void (*orig_CCHmac)(CCHmacAlgorithm, const void *, size_t,
                            const void *, size_t, void *);

void replaced_CCHmac(CCHmacAlgorithm alg,
                     const void *key, size_t keyLen,
                     const void *data, size_t dataLen, void *macOut)
{
    orig_CCHmac(alg, key, keyLen, data, dataLen, macOut);
    size_t macLen = hmacOutputSize(alg);
    NSString *body = [NSString stringWithFormat:@"  Algo: %@\n%@\n%@\n  MAC: %@",
        hmacAlgoName(alg),
        fieldWithBlob(@"Key",  key,    keyLen,  @"CCHmac_key"),
        fieldWithBlob(@"Data", data,   dataLen, @"CCHmac_data"),
        hexString(macOut, macLen)
    ];
    logSection(@"HMAC | CCHmac", body);
    saveBlob(macOut, macLen, @"CCHmac_mac");
}

static void (*orig_CCHmacInit)(CCHmacContext *, CCHmacAlgorithm, const void *, size_t);

void replaced_CCHmacInit(CCHmacContext *ctx, CCHmacAlgorithm alg,
                          const void *key, size_t keyLen)
{
    logSection(@"HMAC | CCHmacInit", [NSString stringWithFormat:
        @"  Algo: %@\n%@",
        hmacAlgoName(alg),
        fieldWithBlob(@"Key", key, keyLen, @"CCHmacInit_key")
    ]);
    orig_CCHmacInit(ctx, alg, key, keyLen);
}

static void (*orig_CCHmacUpdate)(CCHmacContext *, const void *, size_t);

void replaced_CCHmacUpdate(CCHmacContext *ctx, const void *data, size_t dataLen) {
    logSection(@"HMAC | CCHmacUpdate",
        fieldWithBlob(@"Data", data, dataLen, @"CCHmacUpdate_data"));
    orig_CCHmacUpdate(ctx, data, dataLen);
}

static void (*orig_CCHmacFinal)(CCHmacContext *, void *);

void replaced_CCHmacFinal(CCHmacContext *ctx, void *macOut) {
    orig_CCHmacFinal(ctx, macOut);
    // Output size unknown here without tracking alg — dump 64 bytes max safely
    logSection(@"HMAC | CCHmacFinal", [NSString stringWithFormat:
        @"  MAC: %@", hexString(macOut, 64)]);
    saveBlob(macOut, 64, @"CCHmacFinal_mac");
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - CommonCrypto — PBKDF2
// ═══════════════════════════════════════════════════════════════════════════════

static int (*orig_CCKeyDerivationPBKDF)(
    CCPBKDFAlgorithm, const char *, size_t,
    const uint8_t *, size_t,
    CCPseudoRandomAlgorithm, uint32_t,
    uint8_t *, size_t);

int replaced_CCKeyDerivationPBKDF(
    CCPBKDFAlgorithm algorithm,
    const char *password, size_t passwordLen,
    const uint8_t *salt, size_t saltLen,
    CCPseudoRandomAlgorithm prf, uint32_t rounds,
    uint8_t *derivedKey, size_t derivedKeyLen)
{
    int result = orig_CCKeyDerivationPBKDF(algorithm, password, passwordLen,
                                            salt, saltLen, prf, rounds,
                                            derivedKey, derivedKeyLen);
    NSString *body = [NSString stringWithFormat:
        @"  Rounds: %u\n"
         "%@\n"
         "%@\n"
         "%@",
        rounds,
        fieldWithBlob(@"Password",   password,   passwordLen,   @"PBKDF2_password"),
        fieldWithBlob(@"Salt",       salt,        saltLen,       @"PBKDF2_salt"),
        fieldWithBlob(@"DerivedKey", derivedKey,  derivedKeyLen, @"PBKDF2_derivedkey")
    ];
    logSection(@"KDF | PBKDF2", body);
    return result;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Security.framework — SecKey
// ═══════════════════════════════════════════════════════════════════════════════

static OSStatus (*orig_SecKeyEncrypt)(
    SecKeyRef, SecPadding, const uint8_t *, size_t, uint8_t *, size_t *);

OSStatus replaced_SecKeyEncrypt(
    SecKeyRef key, SecPadding padding,
    const uint8_t *plainText, size_t plainTextLen,
    uint8_t *cipherText, size_t *cipherTextLen)
{
    OSStatus status = orig_SecKeyEncrypt(key, padding, plainText, plainTextLen,
                                          cipherText, cipherTextLen);
    logSection(@"SecKey | SecKeyEncrypt", [NSString stringWithFormat:
        @"  Padding: %u\n%@\n%@\n  Status: %d",
        padding,
        fieldWithBlob(@"PlainText",  plainText,  plainTextLen,   @"SecKeyEncrypt_plain"),
        fieldWithBlob(@"CipherText", cipherText, *cipherTextLen, @"SecKeyEncrypt_cipher"),
        (int)status
    ]);
    return status;
}

static OSStatus (*orig_SecKeyDecrypt)(
    SecKeyRef, SecPadding, const uint8_t *, size_t, uint8_t *, size_t *);

OSStatus replaced_SecKeyDecrypt(
    SecKeyRef key, SecPadding padding,
    const uint8_t *cipherText, size_t cipherTextLen,
    uint8_t *plainText, size_t *plainTextLen)
{
    OSStatus status = orig_SecKeyDecrypt(key, padding, cipherText, cipherTextLen,
                                          plainText, plainTextLen);
    logSection(@"SecKey | SecKeyDecrypt", [NSString stringWithFormat:
        @"  Padding: %u\n%@\n%@\n  Status: %d",
        padding,
        fieldWithBlob(@"CipherText", cipherText, cipherTextLen, @"SecKeyDecrypt_cipher"),
        fieldWithBlob(@"PlainText",  plainText,  *plainTextLen, @"SecKeyDecrypt_plain"),
        (int)status
    ]);
    return status;
}

static CFDataRef (*orig_SecKeyCreateEncryptedData)(
    SecKeyRef, SecKeyAlgorithm, CFDataRef, CFErrorRef *);

CFDataRef replaced_SecKeyCreateEncryptedData(
    SecKeyRef key, SecKeyAlgorithm algorithm,
    CFDataRef plaintext, CFErrorRef *error)
{
    CFDataRef result = orig_SecKeyCreateEncryptedData(key, algorithm, plaintext, error);
    NSData *pt = (__bridge NSData *)plaintext;
    NSData *ct = (__bridge NSData *)result;
    logSection(@"SecKey | SecKeyCreateEncryptedData", [NSString stringWithFormat:
        @"  Algorithm: %@\n%@\n%@",
        algorithm,
        fieldWithBlob(@"PlainText",  pt.bytes, pt.length,
                      @"SecKeyCreateEncryptedData_plain"),
        ct ? fieldWithBlob(@"CipherText", ct.bytes, ct.length,
                            @"SecKeyCreateEncryptedData_cipher")
           : @"  CipherText: <nil>"
    ]);
    return result;
}

static CFDataRef (*orig_SecKeyCreateDecryptedData)(
    SecKeyRef, SecKeyAlgorithm, CFDataRef, CFErrorRef *);

CFDataRef replaced_SecKeyCreateDecryptedData(
    SecKeyRef key, SecKeyAlgorithm algorithm,
    CFDataRef ciphertext, CFErrorRef *error)
{
    CFDataRef result = orig_SecKeyCreateDecryptedData(key, algorithm, ciphertext, error);
    NSData *ct = (__bridge NSData *)ciphertext;
    NSData *pt = (__bridge NSData *)result;
    logSection(@"SecKey | SecKeyCreateDecryptedData", [NSString stringWithFormat:
        @"  Algorithm: %@\n%@\n%@",
        algorithm,
        fieldWithBlob(@"CipherText", ct.bytes, ct.length,
                      @"SecKeyCreateDecryptedData_cipher"),
        pt ? fieldWithBlob(@"PlainText", pt.bytes, pt.length,
                            @"SecKeyCreateDecryptedData_plain")
           : @"  PlainText: <nil>"
    ]);
    return result;
}

static OSStatus (*orig_SecKeyRawSign)(
    SecKeyRef, SecPadding, const uint8_t *, size_t, uint8_t *, size_t *);

OSStatus replaced_SecKeyRawSign(
    SecKeyRef key, SecPadding padding,
    const uint8_t *dataToSign, size_t dataToSignLen,
    uint8_t *sig, size_t *sigLen)
{
    OSStatus status = orig_SecKeyRawSign(key, padding, dataToSign, dataToSignLen, sig, sigLen);
    logSection(@"SecKey | SecKeyRawSign", [NSString stringWithFormat:
        @"  Padding: %u\n%@\n%@",
        padding,
        fieldWithBlob(@"Data",      dataToSign, dataToSignLen, @"SecKeyRawSign_data"),
        fieldWithBlob(@"Signature", sig,        *sigLen,       @"SecKeyRawSign_sig")
    ]);
    return status;
}

static OSStatus (*orig_SecKeyRawVerify)(
    SecKeyRef, SecPadding, const uint8_t *, size_t, const uint8_t *, size_t);

OSStatus replaced_SecKeyRawVerify(
    SecKeyRef key, SecPadding padding,
    const uint8_t *signedData, size_t signedDataLen,
    const uint8_t *sig, size_t sigLen)
{
    OSStatus status = orig_SecKeyRawVerify(key, padding, signedData, signedDataLen, sig, sigLen);
    logSection(@"SecKey | SecKeyRawVerify", [NSString stringWithFormat:
        @"  Padding: %u\n%@\n%@\n  Valid: %@",
        padding,
        fieldWithBlob(@"Data",      signedData, signedDataLen, @"SecKeyRawVerify_data"),
        fieldWithBlob(@"Signature", sig,        sigLen,        @"SecKeyRawVerify_sig"),
        status == errSecSuccess ? @"YES" : @"NO"
    ]);
    return status;
}

static CFDataRef (*orig_SecKeyCreateSignature)(
    SecKeyRef, SecKeyAlgorithm, CFDataRef, CFErrorRef *);

CFDataRef replaced_SecKeyCreateSignature(
    SecKeyRef key, SecKeyAlgorithm algorithm,
    CFDataRef dataToSign, CFErrorRef *error)
{
    CFDataRef sig = orig_SecKeyCreateSignature(key, algorithm, dataToSign, error);
    NSData *d = (__bridge NSData *)dataToSign;
    NSData *s = (__bridge NSData *)sig;
    logSection(@"SecKey | SecKeyCreateSignature", [NSString stringWithFormat:
        @"  Algorithm: %@\n%@\n%@",
        algorithm,
        fieldWithBlob(@"Data",      d.bytes, d.length,
                      @"SecKeyCreateSignature_data"),
        s ? fieldWithBlob(@"Signature", s.bytes, s.length,
                           @"SecKeyCreateSignature_sig")
          : @"  Signature: <nil>"
    ]);
    return sig;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - SecureTransport — TLS
// ═══════════════════════════════════════════════════════════════════════════════

typedef void *SSLContext_t;

static OSStatus (*orig_SSLHandshake)(SSLContext_t);
OSStatus replaced_SSLHandshake(SSLContext_t ctx) {
    logSection(@"TLS | SSLHandshake", @"  Handshake initiated");
    OSStatus status = orig_SSLHandshake(ctx);
    logSection(@"TLS | SSLHandshake", [NSString stringWithFormat:
        @"  Handshake complete — Status: %d", (int)status]);
    return status;
}

static OSStatus (*orig_SSLWrite)(SSLContext_t, const void *, size_t, size_t *);
OSStatus replaced_SSLWrite(SSLContext_t ctx, const void *data,
                            size_t dataLen, size_t *processed)
{
    logSection(@"TLS | SSLWrite",
        fieldWithBlob(@"Data", data, dataLen, @"SSLWrite_data"));
    return orig_SSLWrite(ctx, data, dataLen, processed);
}

static OSStatus (*orig_SSLRead)(SSLContext_t, void *, size_t, size_t *);
OSStatus replaced_SSLRead(SSLContext_t ctx, void *data,
                           size_t dataLen, size_t *processed)
{
    OSStatus status = orig_SSLRead(ctx, data, dataLen, processed);
    if (*processed > 0)
        logSection(@"TLS | SSLRead",
            fieldWithBlob(@"Data", data, *processed, @"SSLRead_data"));
    return status;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - OpenSSL / BoringSSL — EVP
// ═══════════════════════════════════════════════════════════════════════════════

typedef struct evp_cipher_ctx_st EVP_CIPHER_CTX;
typedef struct evp_cipher_st     EVP_CIPHER;
typedef struct engine_st         ENGINE;

typedef int (*EVP_EncryptInit_ex_t)(EVP_CIPHER_CTX *, const EVP_CIPHER *,
                                     ENGINE *, const unsigned char *, const unsigned char *);
typedef int (*EVP_EncryptUpdate_t)(EVP_CIPHER_CTX *, unsigned char *, int *,
                                    const unsigned char *, int);
typedef int (*EVP_EncryptFinal_ex_t)(EVP_CIPHER_CTX *, unsigned char *, int *);
typedef int (*EVP_DecryptInit_ex_t)(EVP_CIPHER_CTX *, const EVP_CIPHER *,
                                     ENGINE *, const unsigned char *, const unsigned char *);
typedef int (*EVP_DecryptUpdate_t)(EVP_CIPHER_CTX *, unsigned char *, int *,
                                    const unsigned char *, int);
typedef int (*EVP_DecryptFinal_ex_t)(EVP_CIPHER_CTX *, unsigned char *, int *);
typedef const char *(*EVP_CIPHER_name_t)(const EVP_CIPHER *);

static EVP_EncryptInit_ex_t  orig_EVP_EncryptInit_ex;
static EVP_EncryptUpdate_t   orig_EVP_EncryptUpdate;
static EVP_EncryptFinal_ex_t orig_EVP_EncryptFinal_ex;
static EVP_DecryptInit_ex_t  orig_EVP_DecryptInit_ex;
static EVP_DecryptUpdate_t   orig_EVP_DecryptUpdate;
static EVP_DecryptFinal_ex_t orig_EVP_DecryptFinal_ex;
static EVP_CIPHER_name_t     fn_EVP_CIPHER_name;

int replaced_EVP_EncryptInit_ex(EVP_CIPHER_CTX *ctx, const EVP_CIPHER *type,
                                 ENGINE *impl,
                                 const unsigned char *key, const unsigned char *iv)
{
    NSString *algo = (fn_EVP_CIPHER_name && type)
        ? [NSString stringWithUTF8String:fn_EVP_CIPHER_name(type)] : @"?";
    logSection(@"OpenSSL | EVP_EncryptInit_ex", [NSString stringWithFormat:
        @"  Cipher: %@\n"
         "%@\n"
         "  IV: %@",
        algo,
        key ? fieldWithBlob(@"Key", key, 32, @"EVP_EncryptInit_key") : @"  Key: NULL (existing)",
        iv  ? hexString(iv, 16) : @"NULL (existing)"
    ]);
    return orig_EVP_EncryptInit_ex(ctx, type, impl, key, iv);
}

int replaced_EVP_EncryptUpdate(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl,
                                const unsigned char *in, int inl)
{
    logSection(@"OpenSSL | EVP_EncryptUpdate",
        fieldWithBlob(@"Input", in, inl, @"EVP_EncryptUpdate_input"));
    int result = orig_EVP_EncryptUpdate(ctx, out, outl, in, inl);
    if (out && *outl > 0)
        saveBlob(out, *outl, @"EVP_EncryptUpdate_output");
    return result;
}

int replaced_EVP_EncryptFinal_ex(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl) {
    int result = orig_EVP_EncryptFinal_ex(ctx, out, outl);
    if (out && *outl > 0) {
        logSection(@"OpenSSL | EVP_EncryptFinal_ex",
            fieldWithBlob(@"FinalBlock", out, *outl, @"EVP_EncryptFinal_output"));
    }
    return result;
}

int replaced_EVP_DecryptInit_ex(EVP_CIPHER_CTX *ctx, const EVP_CIPHER *type,
                                 ENGINE *impl,
                                 const unsigned char *key, const unsigned char *iv)
{
    NSString *algo = (fn_EVP_CIPHER_name && type)
        ? [NSString stringWithUTF8String:fn_EVP_CIPHER_name(type)] : @"?";
    logSection(@"OpenSSL | EVP_DecryptInit_ex", [NSString stringWithFormat:
        @"  Cipher: %@\n"
         "%@\n"
         "  IV: %@",
        algo,
        key ? fieldWithBlob(@"Key", key, 32, @"EVP_DecryptInit_key") : @"  Key: NULL (existing)",
        iv  ? hexString(iv, 16) : @"NULL (existing)"
    ]);
    return orig_EVP_DecryptInit_ex(ctx, type, impl, key, iv);
}

int replaced_EVP_DecryptUpdate(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl,
                                const unsigned char *in, int inl)
{
    logSection(@"OpenSSL | EVP_DecryptUpdate",
        fieldWithBlob(@"Input", in, inl, @"EVP_DecryptUpdate_input"));
    int result = orig_EVP_DecryptUpdate(ctx, out, outl, in, inl);
    if (out && *outl > 0)
        saveBlob(out, *outl, @"EVP_DecryptUpdate_output");
    return result;
}

int replaced_EVP_DecryptFinal_ex(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl) {
    int result = orig_EVP_DecryptFinal_ex(ctx, out, outl);
    if (out && *outl > 0) {
        logSection(@"OpenSSL | EVP_DecryptFinal_ex",
            fieldWithBlob(@"FinalBlock", out, *outl, @"EVP_DecryptFinal_output"));
    }
    return result;
}

static void hookOpenSSLIfPresent(void) {
    NSArray<NSString *> *paths = @[
        @"/usr/lib/libcrypto.dylib",
        @"/usr/local/lib/libcrypto.dylib",
        @"/usr/lib/libcrypto.1.1.dylib",
        [[NSBundle mainBundle].privateFrameworksPath stringByAppendingPathComponent:@"libcrypto.dylib"],
        [[NSBundle mainBundle].privateFrameworksPath stringByAppendingPathComponent:@"libcrypto.1.1.dylib"],
        [[NSBundle mainBundle].bundlePath           stringByAppendingPathComponent:@"libcrypto.dylib"],
    ];

    void *handle = NULL;
    for (NSString *path in paths) {
        handle = dlopen(path.UTF8String, RTLD_NOW | RTLD_NOLOAD);
        if (handle) { logSection(@"OpenSSL", [NSString stringWithFormat:@"  Found: %@", path]); break; }
    }
    if (!handle) { saveLog(@"\n[OpenSSL] Not present — skipping EVP hooks"); return; }

    fn_EVP_CIPHER_name = (EVP_CIPHER_name_t)dlsym(handle, "EVP_CIPHER_name");

#define HOOK_EVP(sym) do { \
    void *_s = dlsym(handle, #sym); \
    if (_s) MSHookFunction(_s, (void *)replaced_##sym, (void **)&orig_##sym); \
    else saveLog(@"  [OpenSSL] Missing: " @#sym); \
} while(0)

    HOOK_EVP(EVP_EncryptInit_ex);
    HOOK_EVP(EVP_EncryptUpdate);
    HOOK_EVP(EVP_EncryptFinal_ex);
    HOOK_EVP(EVP_DecryptInit_ex);
    HOOK_EVP(EVP_DecryptUpdate);
    HOOK_EVP(EVP_DecryptFinal_ex);

#undef HOOK_EVP
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Constructor
// ═══════════════════════════════════════════════════════════════════════════════

%ctor {
    // Ensure blobs directory exists at startup
    NSString *blobDir = [docsPath() stringByAppendingPathComponent:@"blobs"];
    [[NSFileManager defaultManager]
        createDirectoryAtPath:blobDir
        withIntermediateDirectories:YES attributes:nil error:nil];

    saveLog(@"\n╔══════════════════════════════════╗"
             "\n║     CryptoHook — Loading…        ║"
             "\n╚══════════════════════════════════╝");

    // CommonCrypto — Cipher
    MSHookFunction((void *)CCCrypt,                  (void *)replaced_CCCrypt,                  (void **)&orig_CCCrypt);
    MSHookFunction((void *)CCCryptorCreate,          (void *)replaced_CCCryptorCreate,          (void **)&orig_CCCryptorCreate);
    MSHookFunction((void *)CCCryptorCreateFromData,  (void *)replaced_CCCryptorCreateFromData,  (void **)&orig_CCCryptorCreateFromData);
    MSHookFunction((void *)CCCryptorUpdate,          (void *)replaced_CCCryptorUpdate,          (void **)&orig_CCCryptorUpdate);
    MSHookFunction((void *)CCCryptorFinal,           (void *)replaced_CCCryptorFinal,           (void **)&orig_CCCryptorFinal);
    MSHookFunction((void *)CCCryptorReset,           (void *)replaced_CCCryptorReset,           (void **)&orig_CCCryptorReset);
    MSHookFunction((void *)CCCryptorRelease,         (void *)replaced_CCCryptorRelease,         (void **)&orig_CCCryptorRelease);

    // CommonCrypto — Digest
    MSHookFunction((void *)CC_MD5,    (void *)replaced_CC_MD5,    (void **)&orig_CC_MD5);
    MSHookFunction((void *)CC_SHA1,   (void *)replaced_CC_SHA1,   (void **)&orig_CC_SHA1);
    MSHookFunction((void *)CC_SHA256, (void *)replaced_CC_SHA256, (void **)&orig_CC_SHA256);
    MSHookFunction((void *)CC_SHA384, (void *)replaced_CC_SHA384, (void **)&orig_CC_SHA384);
    MSHookFunction((void *)CC_SHA512, (void *)replaced_CC_SHA512, (void **)&orig_CC_SHA512);

    // CommonCrypto — HMAC
    MSHookFunction((void *)CCHmac,       (void *)replaced_CCHmac,       (void **)&orig_CCHmac);
    MSHookFunction((void *)CCHmacInit,   (void *)replaced_CCHmacInit,   (void **)&orig_CCHmacInit);
    MSHookFunction((void *)CCHmacUpdate, (void *)replaced_CCHmacUpdate, (void **)&orig_CCHmacUpdate);
    MSHookFunction((void *)CCHmacFinal,  (void *)replaced_CCHmacFinal,  (void **)&orig_CCHmacFinal);

    // CommonCrypto — KDF
    MSHookFunction((void *)CCKeyDerivationPBKDF, (void *)replaced_CCKeyDerivationPBKDF, (void **)&orig_CCKeyDerivationPBKDF);

    // Security.framework
    MSHookFunction((void *)SecKeyEncrypt,               (void *)replaced_SecKeyEncrypt,               (void **)&orig_SecKeyEncrypt);
    MSHookFunction((void *)SecKeyDecrypt,               (void *)replaced_SecKeyDecrypt,               (void **)&orig_SecKeyDecrypt);
    MSHookFunction((void *)SecKeyRawSign,               (void *)replaced_SecKeyRawSign,               (void **)&orig_SecKeyRawSign);
    MSHookFunction((void *)SecKeyRawVerify,             (void *)replaced_SecKeyRawVerify,             (void **)&orig_SecKeyRawVerify);
    MSHookFunction((void *)SecKeyCreateEncryptedData,   (void *)replaced_SecKeyCreateEncryptedData,   (void **)&orig_SecKeyCreateEncryptedData);
    MSHookFunction((void *)SecKeyCreateDecryptedData,   (void *)replaced_SecKeyCreateDecryptedData,   (void **)&orig_SecKeyCreateDecryptedData);
    MSHookFunction((void *)SecKeyCreateSignature,       (void *)replaced_SecKeyCreateSignature,       (void **)&orig_SecKeyCreateSignature);

    // SecureTransport
    MSHookFunction((void *)SSLHandshake, (void *)replaced_SSLHandshake, (void **)&orig_SSLHandshake);
    MSHookFunction((void *)SSLWrite,     (void *)replaced_SSLWrite,     (void **)&orig_SSLWrite);
    MSHookFunction((void *)SSLRead,      (void *)replaced_SSLRead,      (void **)&orig_SSLRead);

    // OpenSSL/BoringSSL (dynamic)
    hookOpenSSLIfPresent();

    saveLog(@"\n╔══════════════════════════════════╗"
             "\n║     CryptoHook — Ready           ║"
             "\n╚══════════════════════════════════╝");
}
