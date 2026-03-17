#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonCrypto.h>
#import <substrate.h>

// ─── AES Ref Tracker ─────────────────────────────────────────────────────────
// CCCryptorUpdate/Final/Reset have no alg param, so we track which refs are AES

static NSMutableSet *aesRefs = nil;
static dispatch_semaphore_t aesRefsLock;

static void trackAESRef(CCCryptorRef ref) {
    if (!ref) return;
    dispatch_semaphore_wait(aesRefsLock, DISPATCH_TIME_FOREVER);
    [aesRefs addObject:[NSValue valueWithPointer:ref]];
    dispatch_semaphore_signal(aesRefsLock);
}

static BOOL isAESRef(CCCryptorRef ref) {
    if (!ref) return NO;
    dispatch_semaphore_wait(aesRefsLock, DISPATCH_TIME_FOREVER);
    BOOL found = [aesRefs containsObject:[NSValue valueWithPointer:ref]];
    dispatch_semaphore_signal(aesRefsLock);
    return found;
}

static void untrackAESRef(CCCryptorRef ref) {
    if (!ref) return;
    dispatch_semaphore_wait(aesRefsLock, DISPATCH_TIME_FOREVER);
    [aesRefs removeObject:[NSValue valueWithPointer:ref]];
    dispatch_semaphore_signal(aesRefsLock);
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

NSString* hexString(const void *bytes, size_t length) {
    if (!bytes || length == 0) return @"<empty>";
    const unsigned char *buf = (const unsigned char *)bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:(length * 2)];
    for (size_t i = 0; i < length; i++)
        [hex appendFormat:@"%02x", buf[i]];
    return hex;
}

NSString* operationName(CCOperation op) {
    return (op == kCCDecrypt) ? @"DECRYPT" : @"ENCRYPT";
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

// ─── CCCrypt (one-shot) ───────────────────────────────────────────────────────

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
    CCCryptorStatus status = orig_CCCrypt(op, alg, options, key, keyLen, iv,
                                          dataIn, dataInLen, dataOut, dataOutAvail, dataOutMoved);

    if (alg != kCCAlgorithmAES) return status;

    NSString *ivHex = iv ? hexString(iv, kCCBlockSizeAES128) : @"NULL";

    NSString *log = [NSString stringWithFormat:
        @"\n[CCCrypt] %@\n"
         "  Key   (%zu bytes): %@\n"
         "  IV:               %@\n"
         "  Input (%zu bytes): %@\n"
         "  Output(%zu bytes): %@\n"
         "  Status: %d\n"
         "────────────────────────────────",
        operationName(op),
        keyLen,   hexString(key, keyLen),
        ivHex,
        dataInLen, hexString(dataIn, dataInLen),
        *dataOutMoved, hexString(dataOut, *dataOutMoved),
        status];

    saveLog(log);
    NSLog(@"[CryptoHook]%@", log);

    return status;
}

// ─── CCCryptorCreate ──────────────────────────────────────────────────────────

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
    CCCryptorStatus status = orig_CCCryptorCreate(op, alg, options, key, keyLen, iv, cryptorRef);

    if (alg != kCCAlgorithmAES) return status;

    if (status == kCCSuccess && cryptorRef && *cryptorRef)
        trackAESRef(*cryptorRef);

    NSString *ivHex = iv ? hexString(iv, kCCBlockSizeAES128) : @"NULL";

    NSString *log = [NSString stringWithFormat:
        @"\n[CCCryptorCreate] %@\n"
         "  Key (%zu bytes): %@\n"
         "  IV:              %@\n"
         "  Ref: %p\n"
         "  Status: %d\n"
         "────────────────────────────────",
        operationName(op),
        keyLen, hexString(key, keyLen),
        ivHex,
        cryptorRef ? *cryptorRef : NULL,
        status];

    saveLog(log);
    NSLog(@"[CryptoHook]%@", log);

    return status;
}

// ─── CCCryptorCreateFromData ──────────────────────────────────────────────────

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
    CCCryptorStatus status = orig_CCCryptorCreateFromData(op, alg, options, key, keyLen, iv,
                                                          data, dataLen, cryptorRef, dataUsed);

    if (alg != kCCAlgorithmAES) return status;

    if (status == kCCSuccess && cryptorRef && *cryptorRef)
        trackAESRef(*cryptorRef);

    NSString *ivHex = iv ? hexString(iv, kCCBlockSizeAES128) : @"NULL";

    NSString *log = [NSString stringWithFormat:
        @"\n[CCCryptorCreateFromData] %@\n"
         "  Key (%zu bytes): %@\n"
         "  IV:              %@\n"
         "  Ref: %p\n"
         "  Status: %d\n"
         "────────────────────────────────",
        operationName(op),
        keyLen, hexString(key, keyLen),
        ivHex,
        cryptorRef ? *cryptorRef : NULL,
        status];

    saveLog(log);
    NSLog(@"[CryptoHook]%@", log);

    return status;
}

// ─── CCCryptorUpdate ──────────────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCryptorUpdate)(
    CCCryptorRef, const void *, size_t,
    void *, size_t, size_t *
);

CCCryptorStatus replaced_CCCryptorUpdate(
    CCCryptorRef cryptorRef,
    const void *dataIn, size_t dataInLen,
    void *dataOut, size_t dataOutAvail, size_t *dataOutMoved
) {
    CCCryptorStatus status = orig_CCCryptorUpdate(cryptorRef, dataIn, dataInLen,
                                                   dataOut, dataOutAvail, dataOutMoved);

    if (!isAESRef(cryptorRef)) return status;

    NSString *log = [NSString stringWithFormat:
        @"\n[CCCryptorUpdate] Ref: %p\n"
         "  Input (%zu bytes):  %@\n"
         "  Output(%zu bytes):  %@\n"
         "  Status: %d\n"
         "────────────────────────────────",
        cryptorRef,
        dataInLen,    hexString(dataIn, dataInLen),
        *dataOutMoved, hexString(dataOut, *dataOutMoved),
        status];

    saveLog(log);
    NSLog(@"[CryptoHook]%@", log);

    return status;
}

// ─── CCCryptorFinal ───────────────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCryptorFinal)(
    CCCryptorRef, void *, size_t, size_t *
);

CCCryptorStatus replaced_CCCryptorFinal(
    CCCryptorRef cryptorRef,
    void *dataOut, size_t dataOutAvail, size_t *dataOutMoved
) {
    CCCryptorStatus status = orig_CCCryptorFinal(cryptorRef, dataOut,
                                                  dataOutAvail, dataOutMoved);

    if (!isAESRef(cryptorRef)) return status;

    NSString *log = [NSString stringWithFormat:
        @"\n[CCCryptorFinal] Ref: %p\n"
         "  Output(%zu bytes): %@\n"
         "  Status: %d\n"
         "────────────────────────────────",
        cryptorRef,
        *dataOutMoved, hexString(dataOut, *dataOutMoved),
        status];

    saveLog(log);
    NSLog(@"[CryptoHook]%@", log);

    return status;
}

// ─── CCCryptorReset ───────────────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCryptorReset)(CCCryptorRef, const void *);

CCCryptorStatus replaced_CCCryptorReset(CCCryptorRef cryptorRef, const void *iv) {
    CCCryptorStatus status = orig_CCCryptorReset(cryptorRef, iv);

    if (!isAESRef(cryptorRef)) return status;

    NSString *log = [NSString stringWithFormat:
        @"\n[CCCryptorReset] Ref: %p\n"
         "  New IV: %@\n"
         "  Status: %d\n"
         "────────────────────────────────",
        cryptorRef,
        iv ? hexString(iv, kCCBlockSizeAES128) : @"NULL",
        status];

    saveLog(log);
    NSLog(@"[CryptoHook]%@", log);

    return status;
}

// ─── CCCryptorRelease ─────────────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCryptorRelease)(CCCryptorRef);

CCCryptorStatus replaced_CCCryptorRelease(CCCryptorRef cryptorRef) {
    BOOL wasAES = isAESRef(cryptorRef);

    CCCryptorStatus status = orig_CCCryptorRelease(cryptorRef);

    if (wasAES) {
        untrackAESRef(cryptorRef);
        NSString *log = [NSString stringWithFormat:
            @"\n[CCCryptorRelease] AES ref %p destroyed\n"
             "────────────────────────────────",
            cryptorRef];
        saveLog(log);
        NSLog(@"[CryptoHook]%@", log);
    }

    return status;
}

// ─── Constructor ──────────────────────────────────────────────────────────────

%ctor {
    aesRefs = [NSMutableSet new];
    aesRefsLock = dispatch_semaphore_create(1);

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

    saveLog(@"========== CryptoHook Loaded (AES only) ==========");
    NSLog(@"[CryptoHook] All hooks installed — AES filter active");
}
