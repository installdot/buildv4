#import <Foundation/Foundation.h>
#include <substrate.h>
#include <CommonCrypto/CommonCryptor.h>
#include <stdio.h>
#include <time.h>
#include <pthread.h>

static pthread_key_t sInHookKey;
static pthread_once_t sOnce = PTHREAD_ONCE_INIT;

static void makeKey(void) {
    pthread_key_create(&sInHookKey, NULL);
}

static int isInHook(void) {
    pthread_once(&sOnce, makeKey);
    return (int)(uintptr_t)pthread_getspecific(sInHookKey);
}

static void setInHook(int val) {
    pthread_once(&sOnce, makeKey);
    pthread_setspecific(sInHookKey, (void *)(uintptr_t)val);
}

static void logToFile(const char *msg) {
    static char logPath[1024] = {0};
    if (logPath[0] == '\0') {
        NSString *home = NSHomeDirectory();
        snprintf(logPath, sizeof(logPath), "%s/Documents/CCCryptLog.txt",
                 [home UTF8String]);
    }
    FILE *f = fopen(logPath, "a");
    if (!f) return;
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    fprintf(f, "[%04d-%02d-%02d %02d:%02d:%02d] %s\n",
            t->tm_year + 1900, t->tm_mon + 1, t->tm_mday,
            t->tm_hour, t->tm_min, t->tm_sec, msg);
    fclose(f);
}

static void bytesToHexBuf(const void *bytes, size_t len, char *out, size_t outSize) {
    if (!bytes || len == 0) { snprintf(out, outSize, "<nil>"); return; }
    size_t display = len < 32 ? len : 32;
    size_t pos = 0;
    const uint8_t *b = (const uint8_t *)bytes;
    for (size_t i = 0; i < display && pos + 3 < outSize; i++) {
        pos += snprintf(out + pos, outSize - pos, "%02x", b[i]);
    }
    if (len > 32 && pos + 4 < outSize) {
        snprintf(out + pos, outSize - pos, "...");
    }
}

static const char *algoName(CCAlgorithm a) {
    switch (a) {
        case kCCAlgorithmAES:      return "AES";
        case kCCAlgorithmDES:      return "DES";
        case kCCAlgorithm3DES:     return "3DES";
        case kCCAlgorithmCAST:     return "CAST";
        case kCCAlgorithmRC4:      return "RC4";
        case kCCAlgorithmRC2:      return "RC2";
        case kCCAlgorithmBlowfish: return "Blowfish";
        default:                   return "Unknown";
    }
}

static CCCryptorStatus (*orig_CCCrypt)(
    CCOperation, CCAlgorithm, CCOptions,
    const void *, size_t,
    const void *,
    const void *, size_t,
    void *, size_t, size_t *
);

static CCCryptorStatus replaced_CCCrypt(
    CCOperation op, CCAlgorithm alg, CCOptions opts,
    const void *key,    size_t keyLen,
    const void *iv,
    const void *dataIn, size_t dataInLen,
    void *dataOut,      size_t dataOutAvail,
    size_t *dataOutMoved
) {
    CCCryptorStatus result = orig_CCCrypt(op, alg, opts,
                                          key, keyLen, iv,
                                          dataIn, dataInLen,
                                          dataOut, dataOutAvail, dataOutMoved);
    if (isInHook()) return result;
    setInHook(1);

    char keyHex[80]  = {0};
    char ivHex[80]   = {0};
    char inHex[80]   = {0};
    char outHex[80]  = {0};

    bytesToHexBuf(key,     keyLen,                           keyHex,  sizeof(keyHex));
    bytesToHexBuf(iv,      iv ? 16 : 0,                      ivHex,   sizeof(ivHex));
    bytesToHexBuf(dataIn,  dataInLen,                         inHex,   sizeof(inHex));
    bytesToHexBuf(dataOut, dataOutMoved ? *dataOutMoved : 0,  outHex,  sizeof(outHex));

    char buf[1024];
    snprintf(buf, sizeof(buf),
        "CCCrypt | Op: %s | Algo: %s | Opts: 0x%X\n"
        "  Key   (%zu): %s\n"
        "  IV         : %s\n"
        "  Input (%zu): %s\n"
        "  Output(%zu): %s\n"
        "  Status: %d\n"
        "----------------------------------------",
        (op == kCCEncrypt) ? "Encrypt" : "Decrypt",
        algoName(alg), (unsigned)opts,
        keyLen,  keyHex,
                 ivHex,
        dataInLen, inHex,
        dataOutMoved ? *dataOutMoved : 0, outHex,
        result);

    logToFile(buf);
    setInHook(0);
    return result;
}

static CCCryptorStatus (*orig_CCCryptorCreate)(
    CCOperation, CCAlgorithm, CCOptions,
    const void *, size_t,
    const void *, CCCryptorRef *
);

static CCCryptorStatus replaced_CCCryptorCreate(
    CCOperation op, CCAlgorithm alg, CCOptions opts,
    const void *key, size_t keyLen,
    const void *iv,  CCCryptorRef *ref
) {
    CCCryptorStatus result = orig_CCCryptorCreate(op, alg, opts, key, keyLen, iv, ref);

    if (isInHook()) return result;
    setInHook(1);

    char keyHex[80] = {0};
    char ivHex[80]  = {0};
    bytesToHexBuf(key, keyLen,       keyHex, sizeof(keyHex));
    bytesToHexBuf(iv,  iv ? 16 : 0,  ivHex,  sizeof(ivHex));

    char buf[512];
    snprintf(buf, sizeof(buf),
        "CCCryptorCreate | Op: %s | Algo: %s | Opts: 0x%X\n"
        "  Key (%zu): %s\n"
        "  IV       : %s\n"
        "  Status: %d\n"
        "----------------------------------------",
        (op == kCCEncrypt) ? "Encrypt" : "Decrypt",
        algoName(alg), (unsigned)opts,
        keyLen, keyHex, ivHex,
        result);

    logToFile(buf);
    setInHook(0);
    return result;
}

%ctor {
    MSHookFunction((void *)CCCrypt,
                   (void *)replaced_CCCrypt,
                   (void **)&orig_CCCrypt);

    MSHookFunction((void *)CCCryptorCreate,
                   (void *)replaced_CCCryptorCreate,
                   (void **)&orig_CCCryptorCreate);

    logToFile("=== CCCrypt Hook Loaded ===");
}
