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

    BOOL isTarget =
        [url.host isEqualToString:kTargetHost] &&
        [url.path isEqualToString:kTargetPath];

    if (!isTarget) return NO;

    if ([NSURLProtocol propertyForKey:@"HookHandled" inRequest:request]) {
        return NO;
    }

    NSString *method = request.HTTPMethod.uppercaseString;

    // ───────── GET notifications ─────────
    if ([method isEqualToString:@"GET"]) {
        NSString *query = url.query ?: @"";
        if ([query containsString:@"action=get_notifications"]) {
            NSLog(@"[Hook] ✅ Notifications request detected");
            return YES;
        }
    }

    // ───────── POST (all actions) ─────────
    if ([method isEqualToString:@"POST"]) {
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

        if ([body containsString:@"action=validate"] ||
            [body containsString:@"action=check_kill_switch_v2"]) {
            NSLog(@"[Hook] ✅ POST action detected");
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
    NSString *method = self.request.HTTPMethod.uppercaseString;

    NSData *data = nil;

    // ───────── GET spoof ─────────
    if ([method isEqualToString:@"GET"]) {
        NSString *query = url.query ?: @"";

        if ([query containsString:@"action=get_notifications"]) {

            NSDictionary *json = @{
                @"success": @YES,
                @"count": @1,
                @"notifications": @[
                    @{
                        @"id": @7,
                        @"title": @"Óc Cảnh iOS làm anti crack như cc đéo biết mã hoá payload",
                        @"message": @"Crack by Hải",
                        @"time": @"09/12/2025",
                        @"priority": @2,
                        @"created_at": @"2025-12-09 17:06:20"
                    }
                ]
            };

            data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
        }
    }

    // ───────── POST spoof (ALL IN ONE) ─────────
    if (!data && [method isEqualToString:@"POST"]) {

        NSData *bodyData = self.request.HTTPBody;

        if (!bodyData && self.request.HTTPBodyStream) {
            NSInputStream *stream = self.request.HTTPBodyStream;
            NSMutableData *dataStream = [NSMutableData data];

            [stream open];
            uint8_t buffer[1024];
            NSInteger len;

            while ((len = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
                [dataStream appendBytes:buffer length:len];
            }

            [stream close];
            bodyData = dataStream;
        }

        NSString *body = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];

        // ───────── 1. Kill switch (PRIORITY) ─────────
        if ([body containsString:@"action=check_kill_switch_v2"]) {

            NSDictionary *json = @{
                @"success": @NO,
                @"killed": @NO,
                @"message": @"Service active",
                @"server_time": @"2026-05-04 12:36:28"
            };

            data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];

            NSLog(@"[Hook] 🔥 Kill switch spoofed");
        }

        // ───────── 2. Validate ─────────
        else if ([body containsString:@"action=validate"] &&
                 [body containsString:@"key="] &&
                 [body containsString:@"hwid="]) {

            NSDictionary *json = @{
                @"success": @YES,
                @"message": @"License validated successfully",
                @"data": @{
                    @"subscription_type": @"daily",
                    @"expiry_date": @"2026-03-24 17:41:33",
                    @"remaining_days": @0,
                    @"remaining_hours": @22,
                    @"activated_at": @"2026-03-23 17:41:33",
                    @"is_trial": @NO,
                    @"is_pro": @1
                }
            };

            data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];

            NSLog(@"[Hook] ✅ Validate spoofed");
        }
    }

    // ───────── FAILSAFE (avoid crash) ─────────
    if (!data) {
        data = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    }

    // ───────── RESPONSE ─────────
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

// ───────── REGISTER ─────────

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
