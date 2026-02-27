// Tweak.xm
#import <Foundation/Foundation.h>
#include <substrate.h>
#include <CommonCrypto/CommonCryptor.h>
#include <stdio.h>

static void logToFile(NSString *message) {
    NSString *docPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/CCCryptLog.txt"];
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:docPath]) {
        [fm createFileAtPath:docPath contents:nil attributes:nil];
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:docPath];
    [handle seekToEndOfFile];

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *timestamp = [fmt stringFromDate:[NSDate date]];

    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

static NSString *algorithmName(CCAlgorithm alg) {
    switch (alg) {
        case kCCAlgorithmAES:      return @"AES";
        case kCCAlgorithmDES:      return @"DES";
        case kCCAlgorithm3DES:     return @"3DES";
        case kCCAlgorithmCAST:     return @"CAST";
        case kCCAlgorithmRC4:      return @"RC4";
        case kCCAlgorithmRC2:      return @"RC2";
        case kCCAlgorithmBlowfish: return @"Blowfish";
        default:                   return [NSString stringWithFormat:@"Unknown(%u)", (unsigned)alg];
    }
}

static NSString *operationName(CCOperation op) {
    return (op == kCCEncrypt) ? @"Encrypt" : @"Decrypt";
}

static NSString *bytesToHex(const void *bytes, size_t len) {
    if (!bytes || len == 0) return @"<nil>";
    NSMutableString *hex = [NSMutableString stringWithCapacity:len * 2];
    const uint8_t *b = (const uint8_t *)bytes;
    size_t display = len < 32 ? len : 32;
    for (size_t i = 0; i < display; i++) {
        [hex appendFormat:@"%02x", b[i]];
    }
    if (len > 32) [hex appendString:@"..."];
    return hex;
}

// ── CCCrypt (one-shot) ────────────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCrypt)(
    CCOperation op, CCAlgorithm alg, CCOptions opts,
    const void *key, size_t keyLen,
    const void *iv,
    const void *dataIn, size_t dataInLen,
    void *dataOut, size_t dataOutAvail,
    size_t *dataOutMoved
);

static CCCryptorStatus replaced_CCCrypt(
    CCOperation op, CCAlgorithm alg, CCOptions opts,
    const void *key, size_t keyLen,
    const void *iv,
    const void *dataIn, size_t dataInLen,
    void *dataOut, size_t dataOutAvail,
    size_t *dataOutMoved
) {
    CCCryptorStatus result = orig_CCCrypt(op, alg, opts, key, keyLen, iv,
                                          dataIn, dataInLen, dataOut, dataOutAvail, dataOutMoved);

    size_t outLen = (dataOutMoved) ? *dataOutMoved : 0;

    NSString *log = [NSString stringWithFormat:
        @"CCCrypt | Op: %@ | Algo: %@ | Opts: 0x%X\n"
         "  Key    (%zu bytes): %@\n"
         "  IV              : %@\n"
         "  Input  (%zu bytes): %@\n"
         "  Output (%zu bytes): %@\n"
         "  Status: %d\n"
         "----------------------------------------",
        operationName(op), algorithmName(alg), (unsigned)opts,
        keyLen,  bytesToHex(key, keyLen),
                 bytesToHex(iv, 16),
        dataInLen, bytesToHex(dataIn, dataInLen),
        outLen,    bytesToHex(dataOut, outLen),
        result
    ];

    logToFile(log);
    return result;
}

// ── CCCryptorCreate (streaming init) ─────────────────────────────────────────

static CCCryptorStatus (*orig_CCCryptorCreate)(
    CCOperation op, CCAlgorithm alg, CCOptions opts,
    const void *key, size_t keyLen,
    const void *iv, CCCryptorRef *cryptorRef
);

static CCCryptorStatus replaced_CCCryptorCreate(
    CCOperation op, CCAlgorithm alg, CCOptions opts,
    const void *key, size_t keyLen,
    const void *iv, CCCryptorRef *cryptorRef
) {
    CCCryptorStatus result = orig_CCCryptorCreate(op, alg, opts, key, keyLen, iv, cryptorRef);

    NSString *log = [NSString stringWithFormat:
        @"CCCryptorCreate | Op: %@ | Algo: %@ | Opts: 0x%X\n"
         "  Key (%zu bytes): %@\n"
         "  IV            : %@\n"
         "  Status: %d\n"
         "----------------------------------------",
        operationName(op), algorithmName(alg), (unsigned)opts,
        keyLen, bytesToHex(key, keyLen),
                bytesToHex(iv, 16),
        result
    ];

    logToFile(log);
    return result;
}

// ── Constructor ───────────────────────────────────────────────────────────────

%ctor {
    MSHookFunction((void *)CCCrypt,
                   (void *)replaced_CCCrypt,
                   (void **)&orig_CCCrypt);

    MSHookFunction((void *)CCCryptorCreate,
                   (void *)replaced_CCCryptorCreate,
                   (void **)&orig_CCCryptorCreate);

    logToFile(@"=== CCCrypt Hook Loaded ===");
}
