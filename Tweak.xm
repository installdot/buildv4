#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static NSString *const kTargetHost = @"tmd-game.duckdns.org";

@interface HookURLProtocol : NSURLProtocol
@end

@implementation HookURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSURL *url = request.URL;
    if (!url) return NO;

    if (![url.host isEqualToString:kTargetHost]) return NO;

    if ([NSURLProtocol propertyForKey:@"HookHandled" inRequest:request]) {
        return NO;
    }

    NSString *path = url.path.lowercaseString;

    if ([path isEqualToString:@"/v1/auth/bootstrap"] ||
        [path isEqualToString:@"/v1/auth/ban-status"]) {
        NSLog(@"[TMD Hook] ✅ Intercepted: %@", path);
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

    NSURL *url = self.request.URL;
    NSString *path = url.path.lowercaseString;
    BOOL isBootstrap = [path isEqualToString:@"/v1/auth/bootstrap"];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL alreadyFirstSpoofed = [defaults boolForKey:@"TMD_FirstBanSpoofed"];

    // ====================== FIRST LAUNCH: Force Ban with Dynamic UID ======================
    if (isBootstrap && !alreadyFirstSpoofed) {
        NSLog(@"[TMD Hook] 🚀 First launch detected - Forcing ban");

        NSURLSession *session = [NSURLSession sharedSession];
        // ✅ Use `req` (with HookHandled set) to prevent infinite intercept loop
        NSURLSessionDataTask *realTask = [session dataTaskWithRequest:req
                                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

            if (error || !data) {
                [self sendFakeBanResponseWithUID:@"UnknownUID"];
                return;
            }

            NSError *jsonError = nil;
            NSMutableDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                       options:NSJSONReadingMutableContainers
                                                                         error:&jsonError];

            // ✅ Guard against parse failure to prevent crash on json[@"uid"]
            if (!json || jsonError) {
                [self sendFakeBanResponseWithUID:@"UnknownUID"];
                return;
            }

            NSString *uid = json[@"uid"] ?: @"UnknownUID";

            json[@"isBanned"] = @YES;
            json[@"banReason"] = [NSString stringWithFormat:@"User UID: %@ - Dev Client By Mochi", uid];

            NSData *modifiedData = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

            [self.client URLProtocol:self didReceiveResponse:httpResponse cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            [self.client URLProtocol:self didLoadData:modifiedData ?: data];
            [self.client URLProtocolDidFinishLoading:self];

            [defaults setBool:YES forKey:@"TMD_FirstBanSpoofed"];
            [defaults synchronize];

            NSLog(@"[TMD Hook] ✅ First launch ban applied | UID: %@", uid);
        }];

        [realTask resume];
        return;
    }

    // ====================== NORMAL CASE: Remove any ban ======================
    NSURLSession *session = [NSURLSession sharedSession];
    // ✅ Use `req` (with HookHandled set) to prevent infinite intercept loop
    NSURLSessionDataTask *task = [session dataTaskWithRequest:req
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

        if (error) {
            [self.client URLProtocol:self didFailWithError:error];
            return;
        }

        NSData *finalData = data;
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;

        if (data) {
            NSError *jsonError = nil;
            NSMutableDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                       options:NSJSONReadingMutableContainers
                                                                         error:&jsonError];

            if (json && !jsonError) {
                if ([json[@"isBanned"] boolValue]) {
                    NSLog(@"[TMD Hook] 🛡️ Ban detected on %@ → Removing", path);
                    json[@"isBanned"] = @NO;
                    json[@"banReason"] = @"";
                }

                finalData = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
            }
        }

        [self.client URLProtocol:self didReceiveResponse:httpResp cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        if (finalData) [self.client URLProtocol:self didLoadData:finalData];
        [self.client URLProtocolDidFinishLoading:self];
    }];

    [task resume];
}

- (void)sendFakeBanResponseWithUID:(NSString *)uid {
    NSDictionary *fakeJson = @{
        @"uid": uid,
        @"serverTimeUtc": @"2026-04-30T07:00:00.0000000Z",
        @"isBanned": @YES,
        @"banReason": [NSString stringWithFormat:@"User UID: %@ - Hacked Client By Mochi", uid]
    };

    NSData *data = [NSJSONSerialization dataWithJSONObject:fakeJson options:0 error:nil];

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                             statusCode:200
                                                            HTTPVersion:@"HTTP/1.1"
                                                           headerFields:@{@"Content-Type": @"application/json"}];

    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {}

@end

// ====================== Registration ======================

static void RegisterProtocol(void) {
    [NSURLProtocol registerClass:[HookURLProtocol class]];
}

__attribute__((constructor(101))) static void init_hook(void) {
    RegisterProtocol();
}

%hook NSURLSessionConfiguration

- (NSArray *)protocolClasses {
    NSMutableArray *arr = [NSMutableArray arrayWithObject:[HookURLProtocol class]];
    NSArray *orig = %orig;
    if (orig) [arr addObjectsFromArray:orig];
    return arr;
}

%end

%hook NSURLSession

+ (NSURLSession *)sharedSession {
    RegisterProtocol();
    return %orig;
}

%end

%ctor {
    RegisterProtocol();
    NSLog(@"[TMD Dev Client By Mochi] ✅ Loaded - Anti Ban + First Launch Spoof");
}
