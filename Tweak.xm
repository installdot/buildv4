// Tweak.xm
#import <substrate.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCryptor.h>

static BOOL g_HasProcessed = NO;
static NSMutableData *g_ReceivedData = nil;

// AES256 CBC Decryption
NSData *aes256Decrypt(NSData *cipherData, NSString *keyString, NSString *ivString) {
    const void *keyBytes = [keyString UTF8String];
    const void *ivBytes = [ivString UTF8String];
    
    size_t bufferSize = [cipherData length];
    void *buffer = malloc(bufferSize);
    size_t decryptedSize = 0;
    
    CCCryptorStatus cryptStatus = CCCrypt(kCCDecrypt,
                                         kCCAlgorithmAES128,
                                         kCCOptionPKCS7Padding,
                                         keyBytes, kCCKeySizeAES256,
                                         ivBytes,
                                         [cipherData bytes], bufferSize,
                                         buffer, bufferSize,
                                         &decryptedSize);
    
    if (cryptStatus == kCCSuccess) {
        NSData *result = [NSData dataWithBytesNoCopy:buffer length:decryptedSize];
        NSLog(@"[Unitoreios Tweak] Decryption successful: %lu bytes", (unsigned long)decryptedSize);
        return result;
    }
    
    NSLog(@"[Unitoreios Tweak] Decryption failed: %d", (int)cryptStatus);
    free(buffer);
    return nil;
}

// AES256 CBC Encryption
NSData *aes256Encrypt(NSData *plainData, NSString *keyString, NSString *ivString) {
    const void *keyBytes = [keyString UTF8String];
    const void *ivBytes = [ivString UTF8String];
    
    size_t bufferSize = [plainData length] + kCCBlockSizeAES128;
    void *buffer = malloc(bufferSize);
    size_t encryptedSize = 0;
    
    CCCryptorStatus cryptStatus = CCCrypt(kCCEncrypt,
                                         kCCAlgorithmAES128,
                                         kCCOptionPKCS7Padding,
                                         keyBytes, kCCKeySizeAES256,
                                         ivBytes,
                                         [plainData bytes], [plainData length],
                                         buffer, bufferSize,
                                         &encryptedSize);
    
    if (cryptStatus == kCCSuccess) {
        NSData *result = [NSData dataWithBytesNoCopy:buffer length:encryptedSize];
        NSLog(@"[Unitoreios Tweak] Encryption successful: %lu bytes", (unsigned long)encryptedSize);
        return result;
    }
    
    NSLog(@"[Unitoreios Tweak] Encryption failed: %d", (int)cryptStatus);
    free(buffer);
    return nil;
}

// URL Protocol to intercept requests
@interface InterceptProtocol : NSURLProtocol <NSURLConnectionDelegate>
@property (nonatomic, strong) NSMutableData *responseData;
@end

@implementation InterceptProtocol {
    NSURLConnection *_connection;
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if (g_HasProcessed) return NO;
    
    NSString *urlString = [[request URL] absoluteString];
    NSLog(@"[Unitoreios Tweak] Checking URL: %@", urlString);
    
    if ([urlString rangeOfString:@"apiunitoreios.site/Cheack.php"].location != NSNotFound &&
        [urlString rangeOfString:@"FREEFIRE-DAY-meCJeXGpKanR8ykG"].location != NSNotFound &&
        [urlString rangeOfString:@"D6C95F10-E5C1-40D8-BF40-72D9ADBAA538"].location != NSNotFound) {
        NSLog(@"[Unitoreios Tweak] ✅ MATCHED TARGET API!");
        g_ReceivedData = [NSMutableData data];
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    self.responseData = [NSMutableData data];
    NSMutableURLRequest *mutableRequest = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"InterceptProtocolHandled" inRequest:mutableRequest];
    
    _connection = [[NSURLConnection alloc] initWithRequest:mutableRequest delegate:self startImmediately:YES];
}

- (void)stopLoading {
    [_connection cancel];
    _connection = nil;
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response {
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"InterceptProtocolHandled" inRequest:mutableRequest];
    return mutableRequest;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.responseData appendData:data];
    [g_ReceivedData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    NSLog(@"[Unitoreios Tweak] 📡 Full response received: %lu bytes", (unsigned long)[g_ReceivedData length]);
    
    [self processDynamicResponse];
    [[self client] URLProtocolDidFinishLoading:self];
    g_HasProcessed = YES;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    NSLog(@"[Unitoreios Tweak] ❌ Connection failed: %@", error);
    [[self client] URLProtocol:self didFailWithError:error];
}

- (void)processDynamicResponse {
    NSString *apiKey = @"unitoreios_api_key_2026_unitorei";
    NSString *ivKey = @"UnitoreiosIV2026";
    
    NSData *encryptedResponse = g_ReceivedData;
    
    if (!encryptedResponse || encryptedResponse.length == 0) {
        NSLog(@"[Unitoreios Tweak] No encrypted data to process");
        return;
    }
    
    // 🔓 DYNAMIC DECRYPTION
    NSData *decryptedData = aes256Decrypt(encryptedResponse, apiKey, ivKey);
    
    if (!decryptedData) {
        NSLog(@"[Unitoreios Tweak] ❌ Failed to decrypt response");
        return;
    }
    
    // Parse JSON dynamically
    NSError *jsonError;
    NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:decryptedData 
                                                             options:kNilOptions 
                                                               error:&jsonError];
    
    if (!jsonDict || jsonError) {
        NSString *decryptedString = [[NSString alloc] initWithData:decryptedData encoding:NSUTF8StringEncoding];
        NSLog(@"[Unitoreios Tweak] ❌ JSON parse failed: %@ | Raw: %@", jsonError, decryptedString);
        return;
    }
    
    NSLog(@"[Unitoreios Tweak] 📋 Original JSON: %@", jsonDict);
    
    // Modify encypttimerkey dynamically
    NSMutableDictionary *modifiedJSON = [jsonDict mutableCopy];
    modifiedJSON[@"encypttimerkey"] = @"1000000 KEY By unitoreios";
    
    NSLog(@"[Unitoreios Tweak] ✏️ Modified encypttimerkey: %@", modifiedJSON[@"encypttimerkey"]);
    
    // Convert back to JSON data
    NSData *modifiedJSONData = [NSJSONSerialization dataWithJSONObject:modifiedJSON options:0 error:&jsonError];
    
    if (!modifiedJSONData || jsonError) {
        NSLog(@"[Unitoreios Tweak] ❌ JSON serialization failed: %@", jsonError);
        return;
    }
    
    // 🔐 RE-ENCRYPT
    NSData *fakeEncryptedResponse = aes256Encrypt(modifiedJSONData, apiKey, ivKey);
    
    if (fakeEncryptedResponse) {
        // Send the fake encrypted response to the app
        [[self client] URLProtocol:self didLoadData:fakeEncryptedResponse];
        NSLog(@"[Unitoreios Tweak] ✅ Fake response sent! Original: %lu -> Modified: %lu bytes", 
              (unsigned long)encryptedResponse.length, (unsigned long)fakeEncryptedResponse.length);
    } else {
        NSLog(@"[Unitoreios Tweak] ❌ Failed to re-encrypt modified data");
    }
}

@end

// Register the protocol
static void (*orig_registerClass)(Class, Class);
static void hooked_registerClass(Class cls, Class protoClass) {
    if (cls == [NSURLProtocol class] && protoClass == [InterceptProtocol class]) {
        NSLog(@"[Unitoreios Tweak] Protocol registered");
    }
    orig_registerClass(cls, protoClass);
}

+ (void)load {
    [NSURLProtocol registerClass:[InterceptProtocol class]];
    
    // Hook NSURLProtocol registerClass for extra safety
    MSHookFunction((void *)[[NSURLProtocol class] methodForSelector:@selector(registerClass:)],
                   (void *)hooked_registerClass,
                   (void **)&orig_registerClass);
    
    NSLog(@"[Unitoreios Tweak] 🚀 Tweak loaded - Ready to intercept!");
}
