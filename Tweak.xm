#import <Foundation/Foundation.h>

static NSString *const kTargetHost = @"app.tnspike.com";
static NSString *const kTargetPort = @"2087";
static NSString *const kTargetPath = @"/verify_udid";

static NSString *const kFakeBody = @"{"
    "\"message\":\"UDID is valid - 365 days remaining\","
    "\"status\":\"active\","
    "\"activated_at\":\"2026-03-15 20:00:23\","
    "\"expires_at\":\"2027-03-22 20:00:23\","
    "\"remaining\":\"365 days\","
    "\"package_type\":\"VIP\","
    "\"activation_key\":\"TNK-7D-CEBADEDF\","
    "\"client_version\":\"2.0.2\","
    "\"update_notes\":[\"Fixed skill search filter not working\",\"Added Key Info card in DATA MOD tab\",\"Improved menu height and layout\",\"Added Contact button in Data Mod tab\"]"
"}";

static BOOL isTargetURL(NSURL *url) {
    if (!url || !url.host) return NO;
    BOOL hostMatch = [url.host isEqualToString:kTargetHost];
    BOOL portMatch = url.port && [url.port.stringValue isEqualToString:kTargetPort];
    BOOL pathMatch = [url.path containsString:kTargetPath];
    return hostMatch && portMatch && pathMatch;
}

// ─────────────────────────────────────────────────────────────
// Wrapper delegate — lets real request fly, swaps response on arrival
// ─────────────────────────────────────────────────────────────
@interface UDIDInterceptDelegate : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, copy)   void (^completionHandler)(NSData *, NSURLResponse *, NSError *);
@property (nonatomic, strong) NSMutableData *receivedData;
@property (nonatomic, strong) NSURLResponse *receivedResponse;
@end

@implementation UDIDInterceptDelegate

- (instancetype)initWithCompletion:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    self = [super init];
    if (self) {
        _completionHandler = completion;
        _receivedData = [NSMutableData data];
    }
    return self;
}

// Real response headers arrived — grab them
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    self.receivedResponse = response;
    completionHandler(NSURLSessionResponseAllow);
}

// Real data chunks arriving — accumulate
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    [self.receivedData appendData:data];
}

// Request finished — NOW swap the body, keep real headers
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {

    if (error) {
        NSLog(@"[UDIDSpoofer] Request failed: %@", error);
        self.completionHandler(nil, self.receivedResponse, error);
        return;
    }

    // Log original response for debugging
    if (self.receivedData.length > 0) {
        NSString *original = [[NSString alloc] initWithData:self.receivedData encoding:NSUTF8StringEncoding];
        NSLog(@"[UDIDSpoofer] Original response: %@", original);
    }

    // Keep real NSHTTPURLResponse headers but replace body
    NSHTTPURLResponse *realHTTP = (NSHTTPURLResponse *)self.receivedResponse;
    NSHTTPURLResponse *spoofedResponse = [[NSHTTPURLResponse alloc]
        initWithURL:realHTTP.URL
         statusCode:200
        HTTPVersion:@"HTTP/1.1"
       headerFields:realHTTP.allHeaderFields]; // ← real headers preserved

    NSData *spoofedData = [kFakeBody dataUsingEncoding:NSUTF8StringEncoding];

    NSLog(@"[UDIDSpoofer] Swapped response body with fake payload");
    self.completionHandler(spoofedData, spoofedResponse, nil);
}

@end

// ─────────────────────────────────────────────────────────────
// Hook NSURLSession — let request go, intercept on return
// ─────────────────────────────────────────────────────────────
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (completionHandler && isTargetURL(request.URL)) {
        NSLog(@"[UDIDSpoofer] Letting request fly: %@", request.URL.absoluteString);

        // Create a background session with our delegate
        NSURLSessionConfiguration *config = NSURLSessionConfiguration.defaultSessionConfiguration;
        UDIDInterceptDelegate *delegate = [[UDIDInterceptDelegate alloc] initWithCompletion:completionHandler];
        NSURLSession *interceptSession = [NSURLSession sessionWithConfiguration:config
                                                                       delegate:delegate
                                                                  delegateQueue:nil];

        NSURLSessionDataTask *task = [interceptSession dataTaskWithRequest:request];
        [task resume];
        return task;
    }

    return %orig(request, completionHandler);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (completionHandler && isTargetURL(url)) {
        NSLog(@"[UDIDSpoofer] Letting URL fly: %@", url.absoluteString);

        NSURLSessionConfiguration *config = NSURLSessionConfiguration.defaultSessionConfiguration;
        UDIDInterceptDelegate *delegate = [[UDIDInterceptDelegate alloc] initWithCompletion:completionHandler];
        NSURLSession *interceptSession = [NSURLSession sessionWithConfiguration:config
                                                                       delegate:delegate
                                                                  delegateQueue:nil];

        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        NSURLSessionDataTask *task = [interceptSession dataTaskWithRequest:req];
        [task resume];
        return task;
    }

    return %orig(url, completionHandler);
}

%end
