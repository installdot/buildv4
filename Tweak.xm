#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonCrypto.h>
#import <substrate.h>

// ─── Helpers ────────────────────────────────────────────────────────────────

NSString* hexString(const void *bytes, size_t length) {
    if (!bytes || length == 0) return @"<empty>";
    const unsigned char *buf = (const unsigned char *)bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:(length * 2)];
    for (size_t i = 0; i < length; i++)
        [hex appendFormat:@"%02x", buf[i]];
    return hex;
}

NSString* algorithmName(CCAlgorithm alg) {
    switch (alg) {
        case kCCAlgorithmAES:       return @"AES";
        case kCCAlgorithmDES:       return @"DES";
        case kCCAlgorithm3DES:      return @"3DES";
        case kCCAlgorithmCAST:      return @"CAST";
        case kCCAlgorithmRC4:       return @"RC4";
        case kCCAlgorithmRC2:       return @"RC2";
        case kCCAlgorithmBlowfish:  return @"Blowfish";
        default:                    return [NSString stringWithFormat:@"Unknown(%u)", alg];
    }
}

NSString* operationName(CCOperation op) {
    return (op == kCCDecrypt) ? @"DECRYPT" : @"ENCRYPT";
}

// Returns correct IV block size per algorithm
size_t ivSizeForAlgorithm(CCAlgorithm alg) {
    switch (alg) {
        case kCCAlgorithm3DES:  return kCCBlockSize3DES;   // 8
        case kCCAlgorithmDES:   return kCCBlockSizeDES;    // 8
        case kCCAlgorithmCAST:  return kCCBlockSizeCAST;   // 8
        case kCCAlgorithmRC2:   return kCCBlockSizeRC2;    // 8
        case kCCAlgorithmAES:
        default:                return kCCBlockSizeAES128; // 16
    }
}

void saveLog(NSString *text) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/crypto_log.txt"];
    NSString *entry = [text stringByAppendingString:@"\n"];
    NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];

    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!file) {
        [data writeToFile:path atomically:YES];
    } else {
        [file seekToEndOfFile];
        [file writeData:data];
        [file closeFile];
    }
}

void logEntry(NSString *tag, CCOperation op, CCAlgorithm alg,
              const void *key, size_t keyLen,
              const void *iv, NSString *extra) {

    size_t ivSize = ivSizeForAlgorithm(alg);
    NSString *ivHex = iv ? hexString(iv, ivSize) : @"NULL";

    NSString *log = [NSString stringWithFormat:
        @"\n[%@] %@ | Algo: %@\n"
         "  Key (%zu bytes): %@\n"
         "  IV:              %@\n"
         "%@"
         "────────────────────────────────",
        tag,
        operationName(op),
        algorithmName(alg),
        keyLen,
        hexString(key, keyLen),
        ivHex,
        extra ? extra : @""
    ];

    saveLog(log);
    NSLog(@"[CryptoHook]%@", log);
}

// ─── CCCrypt (one-shot) ──────────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCrypt)(
    CCOperation, CCAlgorithm, CCOptions,
    const void *, size_t,
    const void *,
    const void *, size_t,
    void *, size_t, size_t *
);

CCCryptorStatus replaced_CCCrypt(
    CCOperation op, CCAlgorithm alg, CCOptions options,
    const void *key, size_t keyLen,
    const void *iv,
    const void *dataIn, size_t dataInLen,
    void *dataOut, size_t dataOutAvail, size_t *dataOutMoved
) {
    NSString *extra = [NSString stringWithFormat:
        @"  Input  (%zu bytes): %@\n",
        dataInLen, hexString(dataIn, dataInLen)];

    logEntry(@"CCCrypt", op, alg, key, keyLen, iv, extra);

    return orig_CCCrypt(op, alg, options, key, keyLen, iv,
                        dataIn, dataInLen, dataOut, dataOutAvail, dataOutMoved);
}

// ─── CCCryptorCreate ─────────────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCryptorCreate)(
    CCOperation, CCAlgorithm, CCOptions,
    const void *, size_t,
    const void *,
    CCCryptorRef *
);

CCCryptorStatus replaced_CCCryptorCreate(
    CCOperation op, CCAlgorithm alg, CCOptions options,
    const void *key, size_t keyLen,
    const void *iv,
    CCCryptorRef *cryptorRef
) {
    logEntry(@"CCCryptorCreate", op, alg, key, keyLen, iv, nil);
    return orig_CCCryptorCreate(op, alg, options, key, keyLen, iv, cryptorRef);
}

// ─── CCCryptorCreateFromData ─────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCryptorCreateFromData)(
    CCOperation, CCAlgorithm, CCOptions,
    const void *, size_t,
    const void *,
    const void *, size_t,
    CCCryptorRef *, size_t *
);

CCCryptorStatus replaced_CCCryptorCreateFromData(
    CCOperation op, CCAlgorithm alg, CCOptions options,
    const void *key, size_t keyLen,
    const void *iv,
    const void *data, size_t dataLen,
    CCCryptorRef *cryptorRef, size_t *dataUsed
) {
    logEntry(@"CCCryptorCreateFromData", op, alg, key, keyLen, iv, nil);
    return orig_CCCryptorCreateFromData(op, alg, options, key, keyLen, iv,
                                        data, dataLen, cryptorRef, dataUsed);
}

// ─── CCCryptorUpdate ─────────────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCryptorUpdate)(
    CCCryptorRef, const void *, size_t,
    void *, size_t, size_t *
);

CCCryptorStatus replaced_CCCryptorUpdate(
    CCCryptorRef cryptorRef,
    const void *dataIn, size_t dataInLen,
    void *dataOut, size_t dataOutAvail, size_t *dataOutMoved
) {
    NSString *log = [NSString stringWithFormat:
        @"\n[CCCryptorUpdate]\n"
         "  Input (%zu bytes): %@\n"
         "────────────────────────────────",
        dataInLen, hexString(dataIn, dataInLen)];
    saveLog(log);

    return orig_CCCryptorUpdate(cryptorRef, dataIn, dataInLen,
                                dataOut, dataOutAvail, dataOutMoved);
}

// ─── CCCryptorFinal ──────────────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCryptorFinal)(
    CCCryptorRef, void *, size_t, size_t *
);

CCCryptorStatus replaced_CCCryptorFinal(
    CCCryptorRef cryptorRef,
    void *dataOut, size_t dataOutAvail, size_t *dataOutMoved
) {
    CCCryptorStatus status = orig_CCCryptorFinal(cryptorRef, dataOut,
                                                  dataOutAvail, dataOutMoved);

    // Log output AFTER final so we capture the completed plaintext/ciphertext
    NSString *log = [NSString stringWithFormat:
        @"\n[CCCryptorFinal]\n"
         "  Output (%zu bytes): %@\n"
         "  Status: %d\n"
         "────────────────────────────────",
        *dataOutMoved,
        hexString(dataOut, *dataOutMoved),
        status];
    saveLog(log);

    return status;
}

// ─── CCCryptorReset ──────────────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCryptorReset)(CCCryptorRef, const void *);

CCCryptorStatus replaced_CCCryptorReset(CCCryptorRef cryptorRef, const void *iv) {
    NSString *log = [NSString stringWithFormat:
        @"\n[CCCryptorReset]\n"
         "  New IV: %@\n"
         "────────────────────────────────",
        iv ? hexString(iv, 16) : @"NULL"];
    saveLog(log);

    return orig_CCCryptorReset(cryptorRef, iv);
}

// ─── CCCryptorRelease ────────────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCryptorRelease)(CCCryptorRef);

CCCryptorStatus replaced_CCCryptorRelease(CCCryptorRef cryptorRef) {
    saveLog(@"\n[CCCryptorRelease] Cryptor destroyed\n────────────────────────────────");
    return orig_CCCryptorRelease(cryptorRef);
}

// ─── Constructor ─────────────────────────────────────────────────────────────

%ctor {
    // No dlopen/dlsym needed — CommonCrypto is already linked.
    // MSHookFunction resolves symbols directly.

    MSHookFunction((void *)CCCrypt,
                   (void *)replaced_CCCrypt,
                   (void **)&orig_CCCrypt);

    MSHookFunction((void *)CCCryptorCreate,
                   (void *)replaced_CCCryptorCreate,
                   (void **)&orig_CCCryptorCreate);

    MSHookFunction((void *)CCCryptorCreateFromData,
                   (void *)replaced_CCCryptorCreateFromData,
                   (void **)&orig_CCCryptorCreateFromData);

    MSHookFunction((void *)CCCryptorUpdate,
                   (void *)replaced_CCCryptorUpdate,
                   (void **)&orig_CCCryptorUpdate);

    MSHookFunction((void *)CCCryptorFinal,
                   (void *)replaced_CCCryptorFinal,
                   (void **)&orig_CCCryptorFinal);

    MSHookFunction((void *)CCCryptorReset,
                   (void *)replaced_CCCryptorReset,
                   (void **)&orig_CCCryptorReset);

    MSHookFunction((void *)CCCryptorRelease,
                   (void *)replaced_CCCryptorRelease,
                   (void **)&orig_CCCryptorRelease);

    saveLog(@"========== CryptoHook Loaded ==========");
    NSLog(@"[CryptoHook] All hooks installed");
}
