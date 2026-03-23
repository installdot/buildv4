// Tweak.xm - FIXED VERSION
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
        NSLog(@"[Unitoreios Tweak] 🔓 Decrypt OK: %lu bytes", (unsigned long)decryptedSize);
        return result;
    }
    
    NSLog(@"[Unitoreios Tweak] ❌ Decrypt FAILED: %d", (int)cryptStatus);
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
        NSLog(@"[Unitoreios Tweak] 🔐 Encrypt OK: %lu bytes", (unsigned long)encryptedSize);
        return result;
    }
    
    NSLog(@"[Unitoreios Tweak] ❌ Encrypt FAILED: %d", (int)cryptStatus);
    free(buffer);
    return nil;
}

@interface InterceptProtocol : NSURLProtocol <NSURLConnectionDelegate>
@property (nonatomic, strong) NSMutableData *responseData;
@end

@implementation InterceptProtocol {
    NSURLConnection *_connection;
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if (g_HasProcessed) return NO;
    
    NSString *urlString = [[request URL] absoluteString];
    NSLog(@"[Unitoreios Tweak] 🔍 URL: %@", urlString);
    
    if ([urlString rangeOfString:@"apiunitoreios.site/Cheack.php"].location != NSNotFound &&
        [urlString rangeOfString:@"FREEFIRE-DAY-meCJeXGpKanR8ykG"].location != NSNotFound &&
        [urlString rangeOfString:@"D6C95F10-E5C1-40D8-BF40-72D9ADBAA538"].location != NSNotFound) {
        NSLog(@"[Unitoreios Tweak] ✅ TARGET API MATCHED!");
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
    NSLog(@"[Unitoreios Tweak] 📡 Response: %lu bytes", (unsigned long)[g_ReceivedData length]);
    [self processRawResponse];
    [[self client] URLProtocolDidFinishLoading:self];
    g_HasProcessed = YES;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    NSLog(@"[Unitoreios Tweak] ❌ Error: %@", error);
    [[self client] URLProtocol:self didFailWithError:error];
}

- (void)processRawResponse {
    NSString *apiKey = @"unitoreios_api_key_2026_unitorei";
    NSString *ivKey = @"UnitoreiosIV2026";
    
    NSData *encryptedData = g_ReceivedData;
    
    // 🔓 DECRYPT RAW RESPONSE
    NSData *decryptedData = aes256Decrypt(encryptedData, apiKey, ivKey);
    if (!decryptedData) return;
    
    // Parse as JSON (dynamic)
    NSError *error;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:decryptedData options:0 error:&error];
    
    NSMutableDictionary *modifiedJSON;
    if (json && !error) {
        NSLog(@"[Unitoreios Tweak] 📋 JSON: %@", json);
        modifiedJSON = [json mutableCopy];
        modifiedJSON[@"encypttimerkey"] = @"1000000 KEY By unitoreios";
        NSLog(@"[Unitoreios Tweak] ✏️ Fixed timer: %@", modifiedJSON[@"encypttimerkey"]);
    } else {
        // Fallback: treat as raw text and create expected JSON structure
        NSLog(@"[Unitoreios Tweak] 📄 Raw text fallback");
        NSString *decryptedString = [[NSString alloc] initWithData:decryptedData encoding:NSUTF8StringEncoding];
        NSLog(@"[Unitoreios Tweak] Raw decrypted: %@", decryptedString);
        
        modifiedJSON = [NSMutableDictionary dictionaryWithDictionary:@{
            @"trangthaikey": @"successfully",
            @"key": @"FREEFIRE-DAY-meCJeXGpKanR8ykG",
            @"encypttimerkey": @"1000000 KEY By unitoreios",
            @"UUID": @"D6C95F10-E5C1-40D8-BF40-72D9ADBAA538",
            @"timer": @"2026-03-23 09:35:42"
        }];
    }
    
    // JSON -> Data
    NSData *modifiedData = [NSJSONSerialization dataWithJSONObject:modifiedJSON options:0 error:&error];
    if (!modifiedData) {
        NSLog(@"[Unitoreios Tweak] ❌ JSON serialize failed");
        return;
    }
    
    // 🔐 ENCRYPT MODIFIED DATA
    NSData *fakeResponse = aes256Encrypt(modifiedData, apiKey, ivKey);
    if (fakeResponse) {
        [[self client] URLProtocol:self didLoadData:fakeResponse];
        NSLog(@"[Unitoreios Tweak] ✅ FAKE RESPONSE SENT! (%lu->%lu bytes)", 
              (unsigned long)encryptedData.length, (unsigned long)fakeResponse.length);
    }
}

@end

%ctor {
    [NSURLProtocol registerClass:[InterceptProtocol class]];
    NSLog(@"[Unitoreios Tweak] 🚀 LOADED!");
}
