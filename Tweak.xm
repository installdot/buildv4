#import <Foundation/Foundation.h>
#import <dlfcn.h>

static NSString *const kVerifyHost = @"floraflower.life";
static NSString *const kVerifyPath = @"/test";

static NSData *(*orig_dataTaskResume)(id, SEL) = NULL;
static BOOL gUnloaded = NO;

// ─────────────────────────────
// Dyld interpose structs
// ─────────────────────────────

typedef struct {
    const void *replacement;
    const void *replacee;
} DyldInterpose;

static NSData *bodyFromRequest(NSURLRequest *req) {
    if (req.HTTPBody) return req.HTTPBody;
    NSInputStream *s = req.HTTPBodyStream;
    if (!s) return nil;
    NSMutableData *d = [NSMutableData data];
    [s open];
    uint8_t buf[1024]; NSInteger len;
    while ((len = [s read:buf maxLength:sizeof(buf)]) > 0)
        [d appendBytes:buf length:len];
    [s close];
    return d;
}

static BOOL isVerifyRequest(NSURLRequest *req) {
    if (gUnloaded) return NO;
    NSURL *url = req.URL;
    return [url.host isEqualToString:kVerifyHost] &&
           [url.path isEqualToString:kVerifyPath] &&
           [req.HTTPMethod.uppercaseString isEqualToString:@"POST"];
}

// ─────────────────────────────
// Replacement for CFURLConnectionSendSynchronousRequest / NSURLSession task
// We interpose at objc_msgSend level via fishhook or just swizzle dataTaskWithRequest:
// ─────────────────────────────

// Interpose NSURLSession dataTaskWithRequest:completionHandler:
static NSURLSessionDataTask *replaced_dataTask(
    NSURLSession *session,
    NSURLRequest *request,
    void (^completionHandler)(NSData *, NSURLResponse *, NSError *))
{
    if (!gUnloaded && isVerifyRequest(request) && completionHandler) {
        NSData *body = bodyFromRequest(request);
        NSString *keyValue = @"unknown";

        if (body) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
            NSString *k = [json isKindOfClass:[NSDictionary class]] ? json[@"key"] : nil;
            if (k.length > 0) keyValue = k;
        }

        NSDictionary *fakeJSON = @{
            @"success": @YES,
            @"code":    @0,
            @"username": keyValue,
            @"test":    @"oke"
        };

        NSData *fakeData = [NSJSONSerialization dataWithJSONObject:fakeJSON options:0 error:nil];
        NSHTTPURLResponse *fakeResp =
            [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                        statusCode:200
                                       HTTPVersion:@"HTTP/1.1"
                                      headerFields:@{@"Content-Type": @"application/json"}];

        // Fire completion inline, then self-destruct
        completionHandler(fakeData, fakeResp, nil);

        gUnloaded = YES; // Mark as done — no further interception

        // Return a dummy cancelled task so the caller has a non-nil object
        NSURLSession *dummy = [NSURLSession sessionWithConfiguration:
            [NSURLSessionConfiguration ephemeralSessionConfiguration]];
        NSURLSessionDataTask *task = [dummy dataTaskWithURL:request.URL];
        [task cancel];
        return task;
    }

    // Pass through normally
    typedef NSURLSessionDataTask *(*Fn)(NSURLSession *, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *));
    Fn orig = (Fn)dlsym(RTLD_NEXT, ""); // resolved via interpose table below
    (void)orig;
    return [session dataTaskWithRequest:request completionHandler:completionHandler];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!gUnloaded && isVerifyRequest(request) && completionHandler) {
        NSData *body = bodyFromRequest(request);
        NSString *keyValue = @"unknown";

        if (body) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
            NSString *k = [json isKindOfClass:[NSDictionary class]] ? json[@"key"] : nil;
            if (k.length > 0) keyValue = k;
        }

        NSDictionary *fakeJSON = @{
            @"success": @YES,
            @"code":    @0,
            @"username": keyValue,
            @"test":    @"oke"
        };

        NSData *fakeData = [NSJSONSerialization dataWithJSONObject:fakeJSON options:0 error:nil];
        NSHTTPURLResponse *fakeResp =
            [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                        statusCode:200
                                       HTTPVersion:@"HTTP/1.1"
                                      headerFields:@{@"Content-Type": @"application/json"}];

        completionHandler(fakeData, fakeResp, nil);

        // Self-destruct: unhook and vanish
        gUnloaded = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            %init; // no-op after, but stops future hooking
        });

        NSURLSession *dummy = [NSURLSession sessionWithConfiguration:
            [NSURLSessionConfiguration ephemeralSessionConfiguration]];
        NSURLSessionDataTask *task = [dummy dataTaskWithURL:request.URL];
        [task cancel];
        return task;
    }

    return %orig;
}

%end

%ctor {
    if (!gUnloaded) {
        %init;
    }
}
