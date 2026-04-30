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

    // ─────────────────────────────
    // First time: Force ban with dynamic UID
    // ─────────────────────────────
    if (isBootstrap && !alreadyFirstSpoofed) {
        NSLog(@"[TMD Hook] 🚀 First launch - Forcing ban with real UID");

        NSURLSession *session = [NSURLSession sharedSession];
        NSURLSessionDataTask *task = [session dataTaskWithRequest:self.request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

            if (error || !data) {
                [self.client URLProtocol:self didFailWithError:error ?: [NSError errorWithDomain:@"TMDHook" code:-1 userInfo:nil]];
                return;
            }

            NSError *jsonError = nil;
            NSMutableDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                       options:NSJSONReadingMutableContainers
                                                                         error:&jsonError];

            NSString *uid = json[@"uid"] ?: @"UnknownUID";

            // Create custom ban message with dynamic UID
            NSString *banReason = [NSString stringWithFormat:@"User UID: %@ - Hacked Client By Mochiii", uid];

            json[@"isBanned"] = @YES;
            json[@"banReason"] = banReason;

            NSData *modifiedData = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];

            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;

            [self.client URLProtocol:self didReceiveResponse:httpResp cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            [self.client URLProtocol:self didLoadData:modifiedData];
            [self.client URLProtocolDidFinishLoading:self];

            // Mark as spoofed so we don't do it again
            [defaults setBool:YES forKey:@"TMD_FirstBanSpoofed"];
            [defaults synchronize];

            NSLog(@"[TMD Hook] ✅ First ban applied | UID: %@ | Reason: %@", uid, banReason);
        }];

        [task resume];
        return;
    }

    // ─────────────────────────────
    // Normal requests: Remove ban if exists
    // ─────────────────────────────
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:self.request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

        if (error) {
            [self.client URLProtocol:self didFailWithError:error];
            return;
        }

        NSData *finalData = data;
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        if (data) {
            NSError *jsonError = nil;
            NSMutableDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                       options:NSJSONReadingMutableContainers
                                                                         error:&jsonError];

            if (json && !jsonError) {
                if ([json[@"isBanned"] boolValue] == YES) {
                    NSLog(@"[TMD Hook] 🛡️ Ban detected → Removing ban");
                    json[@"isBanned"] = @NO;
                    json[@"banReason"] = @"";
                }

                finalData = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
            }
        }

        [self.client URLProtocol:self didReceiveResponse:httpResponse cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        if (finalData) [self.client URLProtocol:self didLoadData:finalData];
        [self.client URLProtocolDidFinishLoading:self];
    }];

    [task resume];
}

- (void)stopLoading {}

@end

// MARK: - Registration & Hooks

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
    NSLog(@"[TMD Dev Client By Mochi] ✅ Anti-Ban + First Launch Spoof Loaded");
}
