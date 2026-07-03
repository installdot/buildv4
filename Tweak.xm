#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static NSString *const kTargetHost = @"api.cheatiosvip.net";

@interface HookURLProtocol : NSURLProtocol
@end

@implementation HookURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSURL *url = request.URL;
    if (!url) return NO;

    if (![url.host isEqualToString:kTargetHost]) return NO;
    if ([NSURLProtocol propertyForKey:@"HookHandled" inRequest:request]) return NO;

    NSString *path = url.path;
    NSString *method = request.HTTPMethod.uppercaseString;

    if ([method isEqualToString:@"GET"]) {
        if ([path containsString:@"/api/status"] ||
            [path containsString:@"/api/app/config"] ||
            [path containsString:@"/api/chat/messages"]) {
            
            NSLog(@"[Hook] ✅ Intercepted: %@", path);
            return YES;
        }
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
    NSString *path = url.path;
    NSData *data = nil;

    // ─────────────────────────────
    // 1. /api/status
    // ─────────────────────────────
    if ([path containsString:@"/api/status"]) {
        NSDictionary *json = @{
            @"success": @YES,
            @"message": @"Authorized"
        };
        data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
        NSLog(@"[Hook] Status spoofed → Authorized");
    }

    // ─────────────────────────────
    // 2. /api/app/config (keyless_mode = true)
    // ─────────────────────────────
    else if ([path containsString:@"/api/app/config"]) {
        NSDictionary *json = @{
            @"success": @YES,
            @"data": @{
                @"status": @"active",
                @"version": @"1.123.1",
                @"needsUpdate": @NO,
                @"updateLink": @"https://t.me/canhioscrack",
                @"contactLink": @"",
                @"notifyTitle": @"",
                @"notifyMessage": @"",
                @"notifyColor": @"",
                @"changelog": @"",
                @"keyless_mode": @YES,
                @"killApp": @NO,
                @"fullscreen_video_enabled": @NO,
                @"fullscreen_video_url": @"https://cheatiosvip.net/ngu.mp4",
                @"appTimeEnabled": @YES,
                @"appStartTime": @1782745200,
                @"appEndTime": @1785337200,
                @"app_notice_enabled": @NO,
                @"app_notice_title": @"Crack done",
                @"app_notice_message": @"Ngu si tứ chi phát triển",
                @"tabAimbot": @YES,
                @"tabEsp": @YES,
                @"tabOther": @YES,
                @"tabHome": @YES,
                @"tabNotify": @YES,
                @"tabAccount": @YES,
                @"tabSettings": @YES,
                @"startButton": @YES,
                @"signInButton": @YES,
                @"keyField": @YES,
                @"gateAimbot": @YES,
                @"gateEsp": @YES,
                @"gateOther": @YES
            }
        };
        data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
        NSLog(@"[Hook] App config spoofed with keyless_mode = true");
    }

    // ─────────────────────────────
    // 3. /api/chat/messages (NEW - only 2 messages)
    // ─────────────────────────────
    else if ([path containsString:@"/api/chat/messages"]) {
        NSDictionary *json = @{
            @"success": @YES,
            @"data": @[
                @{
                    @"_id": @"6a4535d648ce5311ab5f9781",
                    @"maskedKey": @"📢 System",
                    @"message": @"Quá đẳng cấp!!!",
                    @"isSystem": @YES,
                    @"createdAt": @"2026-07-04T00:00:00.000Z",
                    @"__v": @0
                },
                @{
                    @"_id": @"6a4706fa94db463b8cf37ce5",
                    @"maskedKey": @"Admin",
                    @"message": @"Đã bị crack bởi xD",
                    @"isSystem": @NO,
                    @"createdAt": @"2026-07-04T00:01:00.000Z",
                    @"__v": @0
                }
            ]
        };
        data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
        NSLog(@"[Hook] Chat messages spoofed (2 messages only)");
    }

    if (!data) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:@"Hook" code:0 userInfo:nil]];
        return;
    }

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url
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

// Register
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
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    RegisterProtocol();
    return %orig;
}
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    RegisterProtocol();
    return %orig;
}
%end

%hook NSURLConnection
+ (instancetype)connectionWithRequest:(NSURLRequest *)request delegate:(id)delegate {
    RegisterProtocol();
    return %orig;
}
%end

%ctor {
    RegisterProtocol();
}
