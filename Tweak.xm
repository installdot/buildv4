// tweak.xm - Spoof verify_udid.php response for local testing

#import <Foundation/Foundation.h>

// The fake response your server would return on a valid UDID
// Change this to match your actual server's success response format
static NSString *const kFakeResponse = @"{\"status\":\"valid\",\"message\":\"ok\"}";
static NSString *const kTargetHost   = @"chillysilly.frfrnocap.men";
static NSString *const kTargetPath   = @"/verify_udid.php";

// ─────────────────────────────────────────────────────────────
// Hook NSURLSession dataTaskWithRequest to intercept the call
// ─────────────────────────────────────────────────────────────
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    NSURL *url = request.URL;

    if ([url.host containsString:kTargetHost] &&
        [url.path containsString:kTargetPath]) {

        NSLog(@"[VPNSpoofer] Intercepted verify_udid request: %@", url.absoluteString);

        // Build a fake 200 OK response
        NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc]
            initWithURL:url
             statusCode:200
            HTTPVersion:@"HTTP/1.1"
           headerFields:@{@"Content-Type": @"application/json"}];

        NSData *fakeData = [kFakeResponse dataUsingEncoding:NSUTF8StringEncoding];

        // Dispatch async to mimic real network behavior
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            completionHandler(fakeData, fakeResponse, nil);
        });

        // Return a dummy task (never resumed)
        return %orig(request, nil);
    }

    return %orig(request, completionHandler);
}

// ─────────────────────────────────────────────────────────────
// Also hook the delegate-based API in case the app uses that
// ─────────────────────────────────────────────────────────────
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if ([url.host containsString:kTargetHost] &&
        [url.path containsString:kTargetPath]) {

        NSLog(@"[VPNSpoofer] Intercepted verify_udid URL: %@", url.absoluteString);

        NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc]
            initWithURL:url
             statusCode:200
            HTTPVersion:@"HTTP/1.1"
           headerFields:@{@"Content-Type": @"application/json"}];

        NSData *fakeData = [kFakeResponse dataUsingEncoding:NSUTF8StringEncoding];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            completionHandler(fakeData, fakeResponse, nil);
        });

        return %orig(url, nil);
    }

    return %orig(url, completionHandler);
}

%end
