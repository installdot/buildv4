#import <Foundation/Foundation.h>

static NSString *const kTargetHost = @"app.tnspike.com";
static NSString *const kTargetPort = @"2087";
static NSString *const kTargetPath = @"/verify_udid";

static NSString *const kFakeResponse = @"{"
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

static void deliverFakeResponse(NSURL *url, void (^completionHandler)(NSData *, NSURLResponse *, NSError *)) {
    NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc]
        initWithURL:url
         statusCode:200
        HTTPVersion:@"HTTP/1.1"
       headerFields:@{@"Content-Type": @"application/json"}];
    NSData *fakeData = [kFakeResponse dataUsingEncoding:NSUTF8StringEncoding];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        completionHandler(fakeData, fakeResponse, nil);
    });
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (completionHandler && isTargetURL(request.URL)) {
        NSLog(@"[UDIDSpoofer] Intercepted request: %@", request.URL.absoluteString);
        deliverFakeResponse(request.URL, completionHandler);
        return %orig(request, nil);
    }
    return %orig(request, completionHandler);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (completionHandler && isTargetURL(url)) {
        NSLog(@"[UDIDSpoofer] Intercepted URL: %@", url.absoluteString);
        deliverFakeResponse(url, completionHandler);
        return %orig(url, nil);
    }
    return %orig(url, completionHandler);
}

%end
