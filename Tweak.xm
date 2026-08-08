#import <Foundation/Foundation.h>

// Forward declaration of recursive modification helper
static void modifyJsonStructure(id container);

// Helper to recursively parse and modify dictionaries/arrays and stringified JSON
static void modifyJsonStructure(id container) {
    if ([container isKindOfClass:[NSMutableDictionary class]]) {
        NSMutableDictionary *dict = (NSMutableDictionary *)container;

        // 1. Check and modify Server Name if server_id == 15
        if (dict[@"server_id"] && [dict[@"server_id"] intValue] == 15) {
            dict[@"server_name"] = @"Mochi De Silly";
        }

        // 2. Check and modify Player Stats whenever the keys exist
        if (dict[@"vip"] != nil) dict[@"vip"] = @(69);
        if (dict[@"level"] != nil) dict[@"level"] = @(69);
        if (dict[@"coin"] != nil) dict[@"coin"] = @"369 M";
        if (dict[@"diamond"] != nil) dict[@"diamond"] = @"369 M";
        if (dict[@"totalAttack"] != nil) dict[@"totalAttack"] = @(369);
        if (dict[@"totalDefense"] != nil) dict[@"totalDefense"] = @(369);
        if (dict[@"coinInt"] != nil) dict[@"coinInt"] = @(369000);
        if (dict[@"diamondInt"] != nil) dict[@"diamondInt"] = @(369000);

        // 3. Traverse all keys/values
        for (NSString *key in [dict allKeys]) {
            id value = dict[key];

            // If the value is a nested dictionary or array, recurse
            if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
                modifyJsonStructure(value);
            }
            // If the value is a stringified JSON (like "data": "{...}")
            else if ([value isKindOfClass:[NSString class]]) {
                NSString *strVal = (NSString *)value;
                NSString *trimmed = [strVal stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                
                if ([trimmed hasPrefix:@"{"] || [trimmed hasPrefix:@"["]) {
                    NSData *subData = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
                    if (subData) {
                        NSError *subErr = nil;
                        id subJson = [NSJSONSerialization JSONObjectWithData:subData
                                                                     options:NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves
                                                                       error:&subErr];
                        if (!subErr && subJson) {
                            modifyJsonStructure(subJson);
                            
                            // Re-encode back into string and re-assign to key
                            NSData *reserializedData = [NSJSONSerialization dataWithJSONObject:subJson options:0 error:nil];
                            if (reserializedData) {
                                dict[key] = [[NSString alloc] initWithData:reserializedData encoding:NSUTF8StringEncoding];
                            }
                        }
                    }
                }
            }
        }
    } else if ([container isKindOfClass:[NSMutableArray class]]) {
        NSMutableArray *array = (NSMutableArray *)container;
        for (id item in array) {
            modifyJsonStructure(item);
        }
    }
}

// ==========================================================
// Custom NSURLProtocol to Intercept All Network Calls
// ==========================================================
@interface ZFCustomProtocol : NSURLProtocol <NSURLSessionDataDelegate, NSURLSessionTaskDelegate>
@property (nonatomic, strong) NSURLSessionDataTask *dataTask;
@property (nonatomic, strong) NSMutableData *mutableData;
@property (nonatomic, strong) NSURLResponse *customResponse;
@end

@implementation ZFCustomProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *urlStr = request.URL.absoluteString;
    
    // Intercept all requests directed to the game domain
    if ([urlStr containsString:@"zfighterz.ch"] || [urlStr containsString:@"zfighterzbundles.de"]) {
        if ([NSURLProtocol propertyForKey:@"ZFTweakHandled" inRequest:request]) {
            return NO; // Already processed
        }
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSMutableURLRequest *newRequest = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"ZFTweakHandled" inRequest:newRequest];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    
    self.mutableData = [NSMutableData data];
    self.dataTask = [session dataTaskWithRequest:newRequest];
    [self.dataTask resume];
}

- (void)stopLoading {
    [self.dataTask cancel];
    self.dataTask = nil;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    self.customResponse = response;
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [self.mutableData appendData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        [self.client URLProtocol:self didFailWithError:error];
        return;
    }
    
    NSData *finalData = self.mutableData;
    
    @try {
        if (finalData.length > 0) {
            NSError *jsonError = nil;
            id rootJson = [NSJSONSerialization JSONObjectWithData:finalData
                                                          options:NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves
                                                            error:&jsonError];
            
            if (!jsonError && rootJson) {
                // Recursively inspect and modify every dictionary/array/string in the response
                modifyJsonStructure(rootJson);
                
                NSData *modifiedOuterData = [NSJSONSerialization dataWithJSONObject:rootJson options:0 error:nil];
                if (modifiedOuterData) {
                    finalData = modifiedOuterData;
                }
            }
        }
    } @catch (NSException *e) {
        // Fall back to original raw data if response is binary (e.g., image, asset bundle)
    }
    
    // Correct Content-Length header for UnityWebRequest
    if ([self.customResponse isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)self.customResponse;
        NSMutableDictionary *headers = [[httpResponse allHeaderFields] mutableCopy];
        headers[@"Content-Length"] = [NSString stringWithFormat:@"%lu", (unsigned long)finalData.length];
        
        NSHTTPURLResponse *newResponse = [[NSHTTPURLResponse alloc] initWithURL:httpResponse.URL
                                                                     statusCode:httpResponse.statusCode
                                                                    HTTPVersion:@"HTTP/1.1"
                                                                   headerFields:headers];
        [self.client URLProtocol:self didReceiveResponse:newResponse cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    } else {
        [self.client URLProtocol:self didReceiveResponse:self.customResponse cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    }
    
    [self.client URLProtocol:self didLoadData:finalData];
    [self.client URLProtocolDidFinishLoading:self];
}
@end

// ==========================================================
// Hook Protocol Classes Configuration
// ==========================================================
%hook NSURLSessionConfiguration

- (NSArray *)protocolClasses {
    NSArray *classes = %orig;
    NSMutableArray *newClasses = classes ? [classes mutableCopy] : [NSMutableArray array];
    
    Class customProtocol = NSClassFromString(@"ZFCustomProtocol");
    if (customProtocol && ![newClasses containsObject:customProtocol]) {
        [newClasses insertObject:customProtocol atIndex:0];
    }
    return newClasses;
}

- (void)setProtocolClasses:(NSArray *)classes {
    NSMutableArray *newClasses = classes ? [classes mutableCopy] : [NSMutableArray array];
    
    Class customProtocol = NSClassFromString(@"ZFCustomProtocol");
    if (customProtocol && ![newClasses containsObject:customProtocol]) {
        [newClasses insertObject:customProtocol atIndex:0]; 
    }
    %orig(newClasses);
}

%end

%ctor {
    [NSURLProtocol registerClass:NSClassFromString(@"ZFCustomProtocol")];
}
