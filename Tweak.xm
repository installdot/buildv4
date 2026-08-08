#import <Foundation/Foundation.h>

// ==========================================================
// 1. Define our custom NSURLProtocol
// ==========================================================
@interface ZFCustomProtocol : NSURLProtocol <NSURLSessionDataDelegate, NSURLSessionTaskDelegate>
@property (nonatomic, strong) NSURLSessionDataTask *dataTask;
@property (nonatomic, strong) NSMutableData *mutableData;
@property (nonatomic, strong) NSURLResponse *customResponse;
@end

@implementation ZFCustomProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *urlStr = request.URL.absoluteString;
    
    if ([urlStr containsString:@"zfighterz.ch/sqlconnect/Super_Saga/launcherResources.php"] ||
        [urlStr containsString:@"zfighterz.ch/sqlconnect/Super_Saga/enterServer.php"] ||
        [urlStr containsString:@"zfighterz.ch/sqlconnect/Super_Saga/playerData.php"] ||
        [urlStr containsString:@"zfighterz.ch/sqlconnect/Super_Saga/inventory_v2.php"]) {
        
        // Prevent infinite looping by checking if we already marked this request
        if ([NSURLProtocol propertyForKey:@"ZFTweakHandled" inRequest:request]) {
            return NO;
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
    // Mark the request so it doesn't get intercepted by us again
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

// Intercept the response but don't pass it to the client yet (we need to fix Content-Length first)
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    self.customResponse = response;
    completionHandler(NSURLSessionResponseAllow);
}

// Collect the incoming data stream
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [self.mutableData appendData:data];
}

// Request finished downloading, now we modify and send it to Unity
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        [self.client URLProtocol:self didFailWithError:error];
        return;
    }
    
    NSData *finalData = self.mutableData;
    NSString *urlStr = self.request.URL.absoluteString;
    
    @try {
        NSError *jsonError;
        NSMutableDictionary *outerDict = [NSJSONSerialization JSONObjectWithData:finalData options:NSJSONReadingMutableContainers error:&jsonError];
        
        if (!jsonError && outerDict[@"data"]) {
            NSString *innerJsonString = outerDict[@"data"];
            NSData *innerData = [innerJsonString dataUsingEncoding:NSUTF8StringEncoding];
            NSMutableDictionary *innerDict = [NSJSONSerialization JSONObjectWithData:innerData options:NSJSONReadingMutableContainers error:nil];
            
            if (innerDict) {
                // Mod 1: Launcher
                if ([urlStr containsString:@"launcherResources.php"]) {
                    NSMutableDictionary *result = innerDict[@"result"];
                    if (result) {
                        NSMutableArray *serverList = result[@"serverList"];
                        for (NSMutableDictionary *server in serverList) {
                            if ([server[@"server_id"] intValue] == 15) {
                                server[@"server_name"] = @"Mochi De Silly";
                            }
                        }
                    }
                } 
                // Mod 2: User Status
                else {
                    NSMutableDictionary *currentStatus = innerDict[@"currentStatus"];
                    if (currentStatus) {
                        currentStatus[@"vip"] = @(69);
                        currentStatus[@"coin"] = @"369 M";
                        currentStatus[@"diamond"] = @"369 M";
                        currentStatus[@"level"] = @(69);
                        currentStatus[@"totalAttack"] = @(369);
                        currentStatus[@"totalDefense"] = @(369);
                        currentStatus[@"diamondInt"] = @(369000);
                        currentStatus[@"coinInt"] = @(369000);
                    }
                }
                
                NSData *modifiedInnerData = [NSJSONSerialization dataWithJSONObject:innerDict options:0 error:nil];
                NSString *modifiedInnerString = [[NSString alloc] initWithData:modifiedInnerData encoding:NSUTF8StringEncoding];
                outerDict[@"data"] = modifiedInnerString;
                
                NSData *modifiedOuterData = [NSJSONSerialization dataWithJSONObject:outerDict options:0 error:nil];
                if (modifiedOuterData) {
                    finalData = modifiedOuterData; 
                }
            }
        }
    } @catch (NSException *e) {
        // If JSON parsing fails, do nothing and fallback to sending the original unmodified data
    }
    
    // Fix Content-Length Headers (Very important for UnityWebRequest)
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
    
    // Give Unity the Modified Data and flag as finished
    [self.client URLProtocol:self didLoadData:finalData];
    [self.client URLProtocolDidFinishLoading:self];
}
@end


// ==========================================================
// 2. Logos Hooks to Inject the Protocol into the Game
// ==========================================================

%hook NSURLSessionConfiguration

- (NSArray *)protocolClasses {
    NSArray *classes = %orig;
    NSMutableArray *newClasses = classes ? [classes mutableCopy] : [NSMutableArray array];
    
    Class customProtocol = NSClassFromString(@"ZFCustomProtocol");
    if (customProtocol && ![newClasses containsObject:customProtocol]) {
        [newClasses insertObject:customProtocol atIndex:0]; // Force ours to run first
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

// Register globally on tweak initialization
%ctor {
    [NSURLProtocol registerClass:NSClassFromString(@"ZFCustomProtocol")];
}
