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

    // ─────────────────────────────
    // 1. GET notifications
    // ─────────────────────────────
    if ([method isEqualToString:@"GET"]) {
        NSString *query = url.query ?: @"";
        if ([query containsString:@"action=get_notifications"]) {
            NSLog(@"[Hook] ✅ Notifications request detected");
            return YES;
        }
    }

    // ─────────────────────────────
    // 2. POST validate
    // ─────────────────────────────
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

        BOOL match =
            [body containsString:@"action=validate"] &&
            [body containsString:@"key="] &&
            [body containsString:@"hwid="];

        if (match) {
            NSLog(@"[Hook] ✅ Validate request detected");
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

    // ─────────────────────────────
    // 1. Notifications spoof
    // ─────────────────────────────
    if ([method isEqualToString:@"GET"]) {
        NSString *query = url.query ?: @"";

        if ([query containsString:@"action=get_notifications"]) {

            NSDictionary *json = @{
                @"success": @YES,
                @"count": @1,
                @"notifications": @[
                    @{
                        @"id": @7,
                        @"title": @"Óc Cảnh iOS",
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

    // ─────────────────────────────
    // 2. Validate spoof
    // ─────────────────────────────
    if (!data && [method isEqualToString:@"POST"]) {

        NSDictionary *json = @{
            @"success": @YES,
            @"message": @"License validated successfully",
            @"data": @{
                @"subscription_type": @"daily",
                @"expiry_date": @"2026-04-24 17:41:33",
                @"remaining_days": @26,
                @"remaining_hours": @22,
                @"activated_at": @"2026-03-23 17:41:33",
                @"is_trial": @NO,
                @"is_pro": @1
            }
        };

        data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    }

    // ─────────────────────────────
    // Send response
    // ─────────────────────────────

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

// Early load
__attribute__((constructor(101))) static void init_hook(void) {
    RegisterProtocol();
}

// Force into sessions
%hook NSURLSessionConfiguration

- (NSArray *)protocolClasses {
    NSMutableArray *arr = [NSMutableArray arrayWithObject:[HookURLProtocol class]];
    NSArray *orig = %orig;
    if (orig) [arr addObjectsFromArray:orig];
    return arr;
}

%end

// Cover all NSURLSession usage
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

// NSURLConnection fallback
%hook NSURLConnection

+ (instancetype)connectionWithRequest:(NSURLRequest *)request delegate:(id)delegate {
    RegisterProtocol();
    return %orig;
}

%end

%ctor {
    RegisterProtocol();
}
