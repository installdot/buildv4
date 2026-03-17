#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonCrypto.h>
#import <substrate.h>

// ─── Config ───────────────────────────────────────────────────────────────────

static NSString *const kTargetHost    = @"app.tnspike.com";
static NSString *const kTargetPath    = @"/api";
static NSString *const kAESDataKey    = @"aes_data";
static NSString *const kLogPath       = @"Documents/crypto_log.txt";

// ─── State ────────────────────────────────────────────────────────────────────

static BOOL     cryptoHooksInstalled  = NO;
static NSString *capturedAESData      = nil;  // latest aes_data value from API

// ─── AES Ref Tracker ─────────────────────────────────────────────────────────

static NSMutableSet        *aesRefs     = nil;
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

// ─── Helpers ──────────────────────────────────────────────────────────────────

static NSString* hexString(const void *bytes, size_t length) {
    if (!bytes || length == 0) return @"<empty>";
    const unsigned char *buf = (const unsigned char *)bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:(length * 2)];
    for (size_t i = 0; i < length; i++)
        [hex appendFormat:@"%02x", buf[i]];
    return hex;
}

static NSString* operationName(CCOperation op) {
    return (op == kCCDecrypt) ? @"DECRYPT" : @"ENCRYPT";
}

static void saveLog(NSString *text) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:kLogPath];
    NSString *entry = [NSString stringWithFormat:@"%@\n", text];
    NSData   *data  = [entry dataUsingEncoding:NSUTF8StringEncoding];

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [data writeToFile:path atomically:YES];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
    }
}

// Check whether the decrypted output matches (or contains) the captured AES payload
static void checkDecryptedOutput(const void *dataOut, size_t length, NSString *tag) {
    if (!capturedAESData || length == 0) return;

    NSString *outHex = hexString(dataOut, length);

    // Match 1: hex of output contains the raw aes_data string hex
    NSData   *aesRaw    = [capturedAESData dataUsingEncoding:NSUTF8StringEncoding];
    NSString *aesHex    = hexString(aesRaw.bytes, aesRaw.length);
    BOOL      hexMatch  = [outHex containsString:aesHex];

    // Match 2: decoded output as UTF-8 contains the aes_data string directly
    NSString *outStr    = [[NSString alloc] initWithBytes:dataOut
                                                   length:length
                                                 encoding:NSUTF8StringEncoding];
    BOOL      strMatch  = outStr && [outStr containsString:capturedAESData];

    if (hexMatch || strMatch) {
        NSString *alert = [NSString stringWithFormat:
            @"\n🎯 [%@] MATCHED aes_data FROM API RESPONSE!\n"
             "  aes_data value : %@\n"
             "  Decrypted hex  : %@\n"
             "  Decrypted text : %@\n"
             "════════════════════════════════",
            tag,
            capturedAESData,
            outHex,
            outStr ?: @"<non-utf8>"];
        saveLog(alert);
        NSLog(@"[CryptoHook]%@", alert);
    }
}

// ─── Crypto Hooks ─────────────────────────────────────────────────────────────

// CCCrypt ─────────────────────────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCrypt)(
    CCOperation, CCAlgorithm, CCOptions,
    const void *, size_t, const void *,
    const void *, size_t,
    void *, size_t, size_t *
);

CCCryptorStatus replaced_CCCrypt(
    CCOperation op, CCAlgorithm alg, CCOptions options,
    const void *key, size_t keyLen, const void *iv,
    const void *dataIn,  size_t dataInLen,
    void *dataOut, size_t dataOutAvail, size_t *dataOutMoved
) {
    CCCryptorStatus status = orig_CCCrypt(op, alg, options, key, keyLen, iv,
                                          dataIn, dataInLen,
                                          dataOut, dataOutAvail, dataOutMoved);

    if (alg != kCCAlgorithmAES) return status;

    NSString *log = [NSString stringWithFormat:
        @"\n[CCCrypt] %@\n"
         "  Key   (%zu bytes): %@\n"
         "  IV:               %@\n"
         "  Input (%zu bytes): %@\n"
         "  Output(%zu bytes): %@\n"
         "  Status: %d\n"
         "────────────────────────────────",
        operationName(op),
        keyLen,        hexString(key, keyLen),
        iv ? hexString(iv, kCCBlockSizeAES128) : @"NULL",
        dataInLen,     hexString(dataIn, dataInLen),
        *dataOutMoved, hexString(dataOut, *dataOutMoved),
        status];

    saveLog(log);
    NSLog(@"[CryptoHook]%@", log);

    if (op == kCCDecrypt && status == kCCSuccess)
        checkDecryptedOutput(dataOut, *dataOutMoved, @"CCCrypt");

    return status;
}

// CCCryptorCreate ─────────────────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCryptorCreate)(
    CCOperation, CCAlgorithm, CCOptions,
    const void *, size_t, const void *,
    CCCryptorRef *
);

CCCryptorStatus replaced_CCCryptorCreate(
    CCOperation op, CCAlgorithm alg, CCOptions options,
    const void *key, size_t keyLen, const void *iv,
    CCCryptorRef *cryptorRef
) {
    CCCryptorStatus status = orig_CCCryptorCreate(op, alg, options,
                                                   key, keyLen, iv, cryptorRef);
    if (alg != kCCAlgorithmAES) return status;

    if (status == kCCSuccess && cryptorRef && *cryptorRef)
        trackAESRef(*cryptorRef);

    NSString *log = [NSString stringWithFormat:
        @"\n[CCCryptorCreate] %@\n"
         "  Key (%zu bytes): %@\n"
         "  IV:              %@\n"
         "  Ref: %p | Status: %d\n"
         "────────────────────────────────",
        operationName(op),
        keyLen, hexString(key, keyLen),
        iv ? hexString(iv, kCCBlockSizeAES128) : @"NULL",
        cryptorRef ? *cryptorRef : NULL,
        status];

    saveLog(log);
    NSLog(@"[CryptoHook]%@", log);
    return status;
}

// CCCryptorCreateFromData ─────────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCryptorCreateFromData)(
    CCOperation, CCAlgorithm, CCOptions,
    const void *, size_t, const void *,
    const void *, size_t,
    CCCryptorRef *, size_t *
);

CCCryptorStatus replaced_CCCryptorCreateFromData(
    CCOperation op, CCAlgorithm alg, CCOptions options,
    const void *key, size_t keyLen, const void *iv,
    const void *data, size_t dataLen,
    CCCryptorRef *cryptorRef, size_t *dataUsed
) {
    CCCryptorStatus status = orig_CCCryptorCreateFromData(op, alg, options,
                                                          key, keyLen, iv,
                                                          data, dataLen,
                                                          cryptorRef, dataUsed);
    if (alg != kCCAlgorithmAES) return status;

    if (status == kCCSuccess && cryptorRef && *cryptorRef)
        trackAESRef(*cryptorRef);

    NSString *log = [NSString stringWithFormat:
        @"\n[CCCryptorCreateFromData] %@\n"
         "  Key (%zu bytes): %@\n"
         "  IV:              %@\n"
         "  Ref: %p | Status: %d\n"
         "────────────────────────────────",
        operationName(op),
        keyLen, hexString(key, keyLen),
        iv ? hexString(iv, kCCBlockSizeAES128) : @"NULL",
        cryptorRef ? *cryptorRef : NULL,
        status];

    saveLog(log);
    NSLog(@"[CryptoHook]%@", log);
    return status;
}

// CCCryptorUpdate ─────────────────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCryptorUpdate)(
    CCCryptorRef, const void *, size_t,
    void *, size_t, size_t *
);

CCCryptorStatus replaced_CCCryptorUpdate(
    CCCryptorRef cryptorRef,
    const void *dataIn,  size_t dataInLen,
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
        dataInLen,     hexString(dataIn, dataInLen),
        *dataOutMoved, hexString(dataOut, *dataOutMoved),
        status];

    saveLog(log);
    NSLog(@"[CryptoHook]%@", log);

    if (status == kCCSuccess)
        checkDecryptedOutput(dataOut, *dataOutMoved, @"CCCryptorUpdate");

    return status;
}

// CCCryptorFinal ──────────────────────────────────────────────────────────────

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

    if (status == kCCSuccess)
        checkDecryptedOutput(dataOut, *dataOutMoved, @"CCCryptorFinal");

    return status;
}

// CCCryptorReset ──────────────────────────────────────────────────────────────

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

// CCCryptorRelease ────────────────────────────────────────────────────────────

static CCCryptorStatus (*orig_CCCryptorRelease)(CCCryptorRef);

CCCryptorStatus replaced_CCCryptorRelease(CCCryptorRef cryptorRef) {
    BOOL wasAES = isAESRef(cryptorRef);
    CCCryptorStatus status = orig_CCCryptorRelease(cryptorRef);

    if (wasAES) {
        untrackAESRef(cryptorRef);
        NSString *log = [NSString stringWithFormat:
            @"\n[CCCryptorRelease] AES ref %p destroyed\n"
             "────────────────────────────────", cryptorRef];
        saveLog(log);
        NSLog(@"[CryptoHook]%@", log);
    }
    return status;
}

// ─── Install Hooks ────────────────────────────────────────────────────────────

static void installCryptoHooks(void) {
    if (cryptoHooksInstalled) return;
    cryptoHooksInstalled = YES;

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

    saveLog(@"\n========== CryptoHook ACTIVE ==========");
    NSLog(@"[CryptoHook] All AES hooks installed");
}

// ─── NSURLSession Hook (network monitor) ─────────────────────────────────────

// We hook the completion handler variant used for POST requests.
// When the response is from our target host + path, we parse aes_data
// and arm the crypto hooks before the app's own handler runs.



static void processAPIResponse(NSData *data, NSURLResponse *response) {
    NSURL *url = [(NSHTTPURLResponse *)response URL];
    if (!url) return;

    // Must match target host and path
    if (![url.host isEqualToString:kTargetHost]) return;
    if (![url.path hasPrefix:kTargetPath]) return;

    // Parse JSON
    NSError *err = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                         options:0
                                                           error:&err];
    if (!json || err || ![json isKindOfClass:[NSDictionary class]]) return;

    NSString *aesData = json[kAESDataKey];
    if (!aesData || ![aesData isKindOfClass:[NSString class]]) return;

    // Store and arm
    capturedAESData = [aesData copy];

    NSString *log = [NSString stringWithFormat:
        @"\n[NetworkMonitor] POST response from %@%@\n"
         "  aes_data captured: %@\n"
         "  Arming crypto hooks...\n"
         "────────────────────────────────",
        kTargetHost, url.path,
        capturedAESData];
    saveLog(log);
    NSLog(@"[CryptoHook]%@", log);

    // Install hooks now that we know decryption is about to happen
    installCryptoHooks();
}

// Hook -[NSURLSession dataTaskWithRequest:completionHandler:]
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {

    // Only intercept POST to our target
    BOOL isTarget = ([request.URL.host isEqualToString:kTargetHost] &&
                     [request.URL.path hasPrefix:kTargetPath] &&
                     [request.HTTPMethod isEqualToString:@"POST"]);

    if (!isTarget) {
        return %orig(request, handler);
    }

    // Wrap the completion handler
    void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {

            if (data && response && !error)
                processAPIResponse(data, response);

            if (handler) handler(data, response, error);
        };

    return %orig(request, wrappedHandler);
}

%end

// ─── Constructor ──────────────────────────────────────────────────────────────

%ctor {
    aesRefs     = [NSMutableSet new];
    aesRefsLock = dispatch_semaphore_create(1);

    saveLog(@"========== CryptoHook Loaded — waiting for API response ==========");
    NSLog(@"[CryptoHook] Network monitor active, crypto hooks dormant");
}
