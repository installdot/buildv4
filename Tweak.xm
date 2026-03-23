#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static NSString *const kTargetHost = @"api.cheatiosvip.vn";
static NSString *const kTargetPath = @"/api.php";

@interface HookURLProtocol : NSURLProtocol
@end

@implementation HookURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSURL *url = request.URL;
    if (!url) return NO;

    // ─── Basic filter ─────────────────────────────
    BOOL isTarget =
        [url.host isEqualToString:kTargetHost] &&
        [url.path isEqualToString:kTargetPath] &&
        [request.HTTPMethod.uppercaseString isEqualToString:@"POST"];

    if (!isTarget) return NO;

    if ([NSURLProtocol propertyForKey:@"HookHandled" inRequest:request]) {
        return NO;
    }

    // ─── Read POST body ──────────────────────────
    NSData *bodyData = request.HTTPBody;

    if (!bodyData && request.HTTPBodyStream) {
        NSInputStream *stream = request.HTTPBodyStream;
        NSMutableData *data = [NSMutableData data];

        [stream open];
        uint8_t buffer[1024];
        NSInteger len;

        while ((len = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
            [data appendBytes:buffer length:len];
        }

        [stream close];
        bodyData = data;
    }

    if (!bodyData) return NO;

    NSString *body = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];
    if (!body) return NO;

    NSLog(@"[Hook] POST Body: %@", body);

    // ─── Format-based matching ───────────────────
    BOOL match =
        [body containsString:@"action=validate"] &&
        [body containsString:@"key="] &&
        [body containsString:@"hwid="];

    if (match) {
        NSLog(@"[Hook] ✅ Format match detected");
        return YES;
    }

    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {

    NSMutableURLRequest *req = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"HookHandled" inRequest:req];

    // ─── Spoofed JSON ────────────────────────────
    NSDictionary *json = @{
        @"success": @YES,
        @"message": @"License validated successfully",
        @"data": @{
            @"subscription_type": @"daily",
            @"expiry_date": @"2027-03-24 17:41:33",
            @"remaining_days": @365,
            @"remaining_hours": @22,
            @"activated_at": @"2026-03-23 17:41:33",
            @"is_trial": @NO,
            @"is_pro": @1
        }
    };

    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];

    NSHTTPURLResponse *response =
        [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                    statusCode:200
                                   HTTPVersion:@"HTTP/1.1"
                                  headerFields:@{
                                      @"Content-Type": @"application/json",
                                      @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)data.length]
                                  }];

    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {}

@end

// ─────────────────────────────────────────
// Register helper
// ─────────────────────────────────────────

static void RegisterProtocol(void) {
    [NSURLProtocol registerClass:[HookURLProtocol class]];
}

// ─────────────────────────────────────────
// Early injection
// ─────────────────────────────────────────

__attribute__((constructor(101))) static void init_hook(void) {
    RegisterProtocol();
}

// ─────────────────────────────────────────
// Force into all sessions
// ─────────────────────────────────────────

%hook NSURLSessionConfiguration

- (NSArray *)protocolClasses {
    NSMutableArray *arr = [NSMutableArray arrayWithObject:[HookURLProtocol class]];
    NSArray *orig = %orig;
    if (orig) [arr addObjectsFromArray:orig];
    return arr;
}

%end

// ─────────────────────────────────────────
// Cover all NSURLSession paths
// ─────────────────────────────────────────

%hook NSURLSession

+ (NSURLSession *)sharedSession {
    RegisterProtocol();
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    RegisterProtocol();
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    RegisterProtocol();
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url {
    RegisterProtocol();
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                       completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    RegisterProtocol();
    return %orig;
}

%end

// ─────────────────────────────────────────
// NSURLConnection fallback
// ─────────────────────────────────────────

%hook NSURLConnection

+ (instancetype)connectionWithRequest:(NSURLRequest *)request delegate:(id)delegate {
    RegisterProtocol();
    return %orig;
}

- (instancetype)initWithRequest:(NSURLRequest *)request delegate:(id)delegate {
    RegisterProtocol();
    return %orig;
}

%end

// ─────────────────────────────────────────
// Logos fallback
// ─────────────────────────────────────────

%ctor {
    RegisterProtocol();
}
