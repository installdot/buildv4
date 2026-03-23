// Tweak.xm - PROXY MODE (Sends real request + modifies response)
#import <substrate.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCryptor.h>

static BOOL g_HasProcessed = NO;
static NSMutableData *g_ServerResponse = nil;

// AES256 CBC Decryption/Encryption (same as before)
NSData *aes256Decrypt(NSData *cipherData, NSString *keyString, NSString *ivString) {
    const void *keyBytes = [keyString UTF8String];
    const void *ivBytes = [ivString UTF8String];
    
    size_t bufferSize = [cipherData length];
    void *buffer = malloc(bufferSize);
    size_t decryptedSize = 0;
    
    CCCryptorStatus cryptStatus = CCCrypt(kCCDecrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
                                         keyBytes, kCCKeySizeAES256, ivBytes,
                                         [cipherData bytes], bufferSize,
                                         buffer, bufferSize, &decryptedSize);
    
    if (cryptStatus == kCCSuccess) {
        return [NSData dataWithBytesNoCopy:buffer length:decryptedSize];
    }
    free(buffer);
    return nil;
}

NSData *aes256Encrypt(NSData *plainData, NSString *keyString, NSString *ivString) {
    const void *keyBytes = [keyString UTF8String];
    const void *ivBytes = [ivString UTF8String];
    
    size_t bufferSize = [plainData length] + kCCBlockSizeAES128;
    void *buffer = malloc(bufferSize);
    size_t encryptedSize = 0;
    
    CCCryptorStatus cryptStatus = CCCrypt(kCCEncrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
                                         keyBytes, kCCKeySizeAES256, ivBytes,
                                         [plainData bytes], [plainData length],
                                         buffer, bufferSize, &encryptedSize);
    
    if (cryptStatus == kCCSuccess) {
        return [NSData dataWithBytesNoCopy:buffer length:encryptedSize];
    }
    free(buffer);
    return nil;
}

@interface InterceptProtocol : NSURLProtocol <NSURLConnectionDelegate> {
    NSURLConnection *_connection;
    NSMutableData *_responseData;
}
@end

@implementation InterceptProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if (g_HasProcessed) return NO;
    
    NSString *urlString = [[request URL] absoluteString];
    if ([urlString rangeOfString:@"apiunitoreios.site/Cheack.php"].location != NSNotFound &&
        [urlString rangeOfString:@"FREEFIRE-DAY-meCJeXGpKanR8ykG"].location != NSNotFound &&
        [urlString rangeOfString:@"D6C95F10-E5C1-40D8-BF40-72D9ADBAA538"].location != NSNotFound) {
        NSLog(@"[Unitoreios Tweak] ✅ TARGET API DETECTED: %@", urlString);
        g_ServerResponse = [NSMutableData data];
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSLog(@"[Unitoreios Tweak] ➡️ FORWARDING REQUEST TO SERVER...");
    
    // 🚀 FORWARD THE ORIGINAL REQUEST TO SERVER (NOT BLOCKED!)
    NSMutableURLRequest *originalRequest = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"InterceptProtocolHandled" inRequest:originalRequest];
    
    _responseData = [NSMutableData data];
    _connection = [[NSURLConnection alloc] initWithRequest:originalRequest delegate:self startImmediately:YES];
}

- (void)stopLoading {
    if (_connection) {
        [_connection cancel];
        _connection = nil;
    }
}

#pragma mark - NSURLConnectionDelegate

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response {
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"InterceptProtocolHandled" inRequest:mutableRequest];
    return mutableRequest;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [_responseData appendData:data];
    [g_ServerResponse appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    NSLog(@"[Unitoreios Tweak] ✅ SERVER RESPONSE RECEIVED: %lu bytes", (unsigned long)g_ServerResponse.length);
    
    // 🛠️ PROCESS & MODIFY RESPONSE
    NSData *modifiedResponse = [self modifyServerResponse:g_ServerResponse];
    
    if (modifiedResponse) {
        [[self client] URLProtocol:self didLoadData:modifiedResponse];
        NSLog(@"[Unitoreios Tweak] ✅ MODIFIED RESPONSE SENT TO APP!");
        g_HasProcessed = YES;
    } else {
        // Fallback: send original response
        NSLog(@"[Unitoreios Tweak] ⚠️ Modification failed, sending original");
        [[self client] URLProtocol:self didLoadData:g_ServerResponse];
    }
    
    [[self client] URLProtocolDidFinishLoading:self];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    NSLog(@"[Unitoreios Tweak] ❌ SERVER ERROR: %@", error);
    [[self client] URLProtocol:self didFailWithError:error];
}

- (NSData *)modifyServerResponse:(NSData *)serverResponse {
    NSString *apiKey = @"unitoreios_api_key_2026_unitorei";
    NSString *ivKey = @"UnitoreiosIV2026";
    
    // 🔓 DECRYPT SERVER RESPONSE
    NSData *decryptedData = aes256Decrypt(serverResponse, apiKey, ivKey);
    if (!decryptedData) {
        NSLog(@"[Unitoreios Tweak] ❌ Decryption failed");
        return nil;
    }
    
    NSLog(@"[Unitoreios Tweak] 📥 Decrypted: %lu bytes", (unsigned long)decryptedData.length);
    
    // Parse JSON
    NSError *error;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:decryptedData 
                                                        options:kNilOptions 
                                                          error:&error];
    
    NSMutableDictionary *modifiedJSON;
    if (json && !error) {
        NSLog(@"[Unitoreios Tweak] 📋 Original JSON: %@", json);
        modifiedJSON = [json mutableCopy];
        modifiedJSON[@"encypttimerkey"] = @"1000000 KEY By unitoreios";
        NSLog(@"[Unitoreios Tweak] ✏️ Modified: %@", modifiedJSON[@"encypttimerkey"]);
    } else {
        // Fallback for raw text responses
        NSLog(@"[Unitoreios Tweak] 📄 Raw fallback");
        modifiedJSON = [NSMutableDictionary dictionaryWithDictionary:@{
            @"trangthaikey": @"successfully",
            @"key": @"FREEFIRE-DAY-meCJeXGpKanR8ykG",
            @"encypttimerkey": @"1000000 KEY By unitoreios",
            @"UUID": @"D6C95F10-E5C1-40D8-BF40-72D9ADBAA538",
            @"timer": @"2026-03-23 09:35:42"
        }];
    }
    
    // JSON -> Data -> Encrypt
    NSData *modifiedJSONData = [NSJSONSerialization dataWithJSONObject:modifiedJSON 
                                                              options:0 
                                                                error:&error];
    if (!modifiedJSONData) {
        NSLog(@"[Unitoreios Tweak] ❌ JSON serialize failed");
        return nil;
    }
    
    NSData *fakeEncrypted = aes256Encrypt(modifiedJSONData, apiKey, ivKey);
    NSLog(@"[Unitoreios Tweak] 🔄 Fake encrypted: %lu bytes", (unsigned long)fakeEncrypted.length);
    
    return fakeEncrypted;
}

@end

%ctor {
    [NSURLProtocol registerClass:[InterceptProtocol class]];
    NSLog(@"[Unitoreios Tweak] 🚀 PROXY MODE ACTIVE!");
}
