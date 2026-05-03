// Tweak.xm
// Intercepts:
//   tmd-game.duckdns.org  – maintenance + bootstrap
//   firebaseremoteconfig.googleapis.com – remote config patch

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Constants
// ─────────────────────────────────────────────────────────────────────────────

static NSString *const kTMDHost          = @"tmd-game.duckdns.org";
static NSString *const kPathMaintenance  = @"/v1/servers/server001/maintenance";
static NSString *const kPathBootstrap    = @"/v1/auth/bootstrap";

static NSString *const kFirebaseHost     = @"firebaseremoteconfig.googleapis.com";
static NSString *const kFirebasePath     = @"/v1/projects/thienmadao-4d4f1/namespaces/firebase:fetch";

static BOOL sBootstrapFired = NO;

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Shared registration
// ─────────────────────────────────────────────────────────────────────────────

static void RegisterAllProtocols(void);   // forward decl

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - TMD Game Protocol
// ─────────────────────────────────────────────────────────────────────────────

@interface TMDHookProtocol : NSURLProtocol
@end

@implementation TMDHookProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSURL *url = request.URL;
    if (!url) return NO;
    if (![url.host isEqualToString:kTMDHost]) return NO;
    if ([NSURLProtocol propertyForKey:@"TMDHandled" inRequest:request]) return NO;

    NSString *path = url.path;
    return [path isEqualToString:kPathMaintenance] ||
           [path isEqualToString:kPathBootstrap];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSString *path = self.request.URL.path;
    NSDictionary *json = nil;

    if ([path isEqualToString:kPathMaintenance]) {
        json = @{ @"isMaintenance": @NO };
        NSLog(@"[TMDHook] → Maintenance override: false");
    }
    else if ([path isEqualToString:kPathBootstrap]) {
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSSSSS'Z'";
        fmt.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
        NSString *nowString = [fmt stringFromDate:[NSDate date]];
        NSString *uid = @"NRdxit8cyKXIG9alQGBk970luxb2";

        if (!sBootstrapFired) {
            sBootstrapFired = YES;
            json = @{
                @"uid":           uid,
                @"serverTimeUtc": nowString,
                @"isBanned":      @YES,
                @"banReason":     @"Anti-Ban 2.0 Bypass F4CK - Antiban chứ đ phải anti xoá dữ liệu acc"
            };
            NSLog(@"[TMDHook] → Bootstrap (1st): banned");
        } else {
            json = @{
                @"uid":           uid,
                @"serverTimeUtc": nowString,
                @"isBanned":      @NO,
                @"banReason":     @""
            };
            NSLog(@"[TMDHook] → Bootstrap (repeat): clean");
        }
    }

    if (!json) {
        [self.client URLProtocol:self didFailWithError:
            [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil]];
        return;
    }

    [self sendJSON:json];
}

- (void)sendJSON:(NSDictionary *)json {
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    NSHTTPURLResponse *resp =
        [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                    statusCode:200
                                   HTTPVersion:@"HTTP/1.1"
                                  headerFields:@{
                                      @"Content-Type":   @"application/json",
                                      @"Content-Length": [NSString stringWithFormat:@"%lu",
                                                          (unsigned long)data.length]
                                  }];
    [self.client URLProtocol:self didReceiveResponse:resp
          cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {}

@end

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Firebase Remote Config Protocol  (pass-through + patch)
// ─────────────────────────────────────────────────────────────────────────────

@interface FirebaseConfigHookProtocol : NSURLProtocol
@property (nonatomic, strong) NSURLSessionDataTask *realTask;
@end

@implementation FirebaseConfigHookProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSURL *url = request.URL;
    if (!url) return NO;
    if (![url.host isEqualToString:kFirebaseHost]) return NO;
    if (![url.path isEqualToString:kFirebasePath]) return NO;
    if ([NSURLProtocol propertyForKey:@"FBHandled" inRequest:request]) return NO;
    NSLog(@"[FBHook] ✅ Intercepting Firebase Remote Config");
    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    // Build a real copy of the request (marked so we don't re-intercept it)
    NSMutableURLRequest *real = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"FBHandled" inRequest:real];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    // Insert our protocol so NSURLSession doesn't strip it, but FBHandled prevents re-entry
    NSMutableArray *protos = [NSMutableArray arrayWithObject:[FirebaseConfigHookProtocol class]];
    if (cfg.protocolClasses) [protos addObjectsFromArray:cfg.protocolClasses];
    cfg.protocolClasses = protos;

    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];

    __weak typeof(self) weakSelf = self;
    self.realTask = [session dataTaskWithRequest:real
                               completionHandler:^(NSData *data,
                                                   NSURLResponse *response,
                                                   NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (error || !data) {
            NSLog(@"[FBHook] Real request failed: %@", error);
            [self.client URLProtocol:self didFailWithError:error ?: 
                [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil]];
            return;
        }

        // ── Parse real response ──
        NSMutableDictionary *root = nil;
        NSError *parseErr = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&parseErr];

        if ([parsed isKindOfClass:[NSMutableDictionary class]]) {
            root = (NSMutableDictionary *)parsed;
        } else {
            // Unexpected shape — pass through unmodified
            NSLog(@"[FBHook] ⚠️ Unexpected response shape, passing through");
            [self.client URLProtocol:self didReceiveResponse:response
                  cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            [self.client URLProtocol:self didLoadData:data];
            [self.client URLProtocolDidFinishLoading:self];
            return;
        }

        // ── Patch entries ──
        // Firebase Remote Config wraps values inside "entries" dict
        NSMutableDictionary *entries = root[@"entries"];
        if (![entries isKindOfClass:[NSMutableDictionary class]]) {
            entries = [NSMutableDictionary dictionary];
            root[@"entries"] = entries;
        }

        // 1. Milestone — always enabled
        entries[@"enable_recharge_milestone"] = @"true";

        // 2. Game notification — override content + url, keep enable:true
        NSDictionary *notifPatch = @{
            @"enable":      @YES,
            @"content":     @"Hacked Client By F4CK",
            @"url_require": @"https://t.me/F4ckCheat"
        };
        NSData *notifData = [NSJSONSerialization dataWithJSONObject:notifPatch options:0 error:nil];
        NSString *notifString = [[NSString alloc] initWithData:notifData encoding:NSUTF8StringEncoding];
        entries[@"game_notification"] = notifString;

        NSLog(@"[FBHook] ✅ Patched entries: %@", entries);

        // ── Serialise patched response ──
        NSData *patched = [NSJSONSerialization dataWithJSONObject:root options:0 error:nil];
        if (!patched) patched = data;   // fallback

        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        NSMutableDictionary *headers = [httpResp.allHeaderFields mutableCopy] ?: [NSMutableDictionary dictionary];
        headers[@"Content-Type"]   = @"application/json";
        headers[@"Content-Length"] = [NSString stringWithFormat:@"%lu", (unsigned long)patched.length];

        NSHTTPURLResponse *newResp =
            [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                        statusCode:httpResp.statusCode
                                       HTTPVersion:@"HTTP/1.1"
                                      headerFields:headers];

        [self.client URLProtocol:self didReceiveResponse:newResp
              cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:patched];
        [self.client URLProtocolDidFinishLoading:self];
    }];

    [self.realTask resume];
}

- (void)stopLoading {
    [self.realTask cancel];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Registration
// ─────────────────────────────────────────────────────────────────────────────

static void RegisterAllProtocols(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSURLProtocol registerClass:[TMDHookProtocol class]];
        [NSURLProtocol registerClass:[FirebaseConfigHookProtocol class]];
        NSLog(@"[Hook] All protocols registered");
    });
}

__attribute__((constructor(101))) static void init_hook(void) {
    RegisterAllProtocols();
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - NSURLSessionConfiguration hook (covers custom sessions)
// ─────────────────────────────────────────────────────────────────────────────

%hook NSURLSessionConfiguration

- (NSArray *)protocolClasses {
    NSMutableArray *arr = [NSMutableArray arrayWithObjects:
        [TMDHookProtocol class],
        [FirebaseConfigHookProtocol class],
        nil];
    NSArray *orig = %orig;
    if (orig) [arr addObjectsFromArray:orig];
    return arr;
}

%end

%hook NSURLSession

+ (NSURLSession *)sharedSession {
    RegisterAllProtocols();
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    RegisterAllProtocols();
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))h {
    RegisterAllProtocols();
    return %orig;
}

%end

%hook NSURLConnection

+ (instancetype)connectionWithRequest:(NSURLRequest *)request delegate:(id)delegate {
    RegisterAllProtocols();
    return %orig;
}

%end

%ctor {
    RegisterAllProtocols();
}
