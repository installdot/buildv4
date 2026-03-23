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

    BOOL match =
        [url.host isEqualToString:kTargetHost] &&
        [url.path isEqualToString:kTargetPath] &&
        [request.HTTPMethod.uppercaseString isEqualToString:@"POST"];

    if (match) {
        if ([NSURLProtocol propertyForKey:@"HookHandled" inRequest:request]) {
            return NO;
        }

        NSLog(@"[Hook] Intercepted request: %@", url.absoluteString);
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

    NSDictionary *json = @{
        @"success": @YES,
        @"message": @"License validated successfully",
        @"data": @{
            @"subscription_type": @"daily",
            @"expiry_date": @"2027-03-24 17:41:33",
            @"remaining_days": @365,
            @"remaining_hours": @0,
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
                                      @"Content-Type": @"application/json"
                                  }];

    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {}

@end

// ─────────────────────────────────────────
// Central register function
// ─────────────────────────────────────────

static void RegisterProtocol(void) {
    [NSURLProtocol registerClass:[HookURLProtocol class]];
}

// ─────────────────────────────────────────
// EARLY LOAD
// ─────────────────────────────────────────

__attribute__((constructor(101))) static void init_hook(void) {
    RegisterProtocol();
}

// ─────────────────────────────────────────
// FORCE into ALL sessions
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
// Hook ALL request creation paths
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
// NSURLConnection fallback (older apps)
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
