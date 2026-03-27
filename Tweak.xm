#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// ─────────────────────────────
// SAFE DYLIB HIDER (self-hiding from runtime & app)
// ─────────────────────────────
#include <mach-o/dyld.h>
#include <string.h>

%hookf(const char *, _dyld_get_image_name, uint32_t image_index) {
    const char *name = %orig(image_index);
    if (name && strstr(name, "iSK") != NULL) {
        NSLog(@"[Hook] 🔒 Hidden dylib: %s", name);
        return "/usr/lib/libSystem.B.dylib";   // fake system library
    }
    return name;
}

// ─────────────────────────────
// Flora Verify Spoof (crash-safe)
// ─────────────────────────────

static NSString *const kVerifyHost = @"floraflower.life";
static NSString *const kVerifyPath = @"/verify";

@interface HookURLProtocol : NSURLProtocol
@end

@implementation HookURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSURL *url = request.URL;
    if (!url) return NO;

    if ([NSURLProtocol propertyForKey:@"HookHandled" inRequest:request]) {
        return NO;
    }

    NSString *method = request.HTTPMethod.uppercaseString ?: @"";

    if ([url.host isEqualToString:kVerifyHost] &&
        [url.path isEqualToString:kVerifyPath] &&
        [method isEqualToString:@"POST"]) {

        NSLog(@"[Hook] ✅ Flora verify request detected");
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

    NSData *bodyData = self.request.HTTPBody;

    // Handle stream (only read here)
    if (!bodyData && self.request.HTTPBodyStream) {
        NSInputStream *stream = self.request.HTTPBodyStream;
        NSMutableData *d = [NSMutableData data];

        [stream open];
        uint8_t buffer[1024];
        NSInteger len;
        while ((len = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
            [d appendBytes:buffer length:len];
        }
        [stream close];
        bodyData = d;
    }

    NSString *keyValue = @"unknown";

    if (bodyData) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
        if ([json isKindOfClass:[NSDictionary class]]) {
            NSString *k = json[@"key"];
            if (k.length > 0) keyValue = k;
        }

        // Fallback form-urlencoded
        if ([keyValue isEqualToString:@"unknown"]) {
            NSString *bodyStr = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];
            NSArray *pairs = [bodyStr componentsSeparatedByString:@"&"];
            for (NSString *pair in pairs) {
                NSArray *kv = [pair componentsSeparatedByString:@"="];
                if (kv.count == 2 && [kv[0] isEqualToString:@"key"]) {
                    keyValue = kv[1];
                    break;
                }
            }
        }
    }

    NSLog(@"[Hook] 🎯 Spoofing key → %@", keyValue);

    NSDictionary *json = @{
        @"success": @YES,
        @"code": @0,
        @"username": keyValue,
        @"subscription": @"free"
    };

    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];

    NSHTTPURLResponse *response =
        [[NSHTTPURLResponse alloc] initWithURL:url
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

// ─────────────────────────────
// Register Protocol
// ─────────────────────────────

static void RegisterProtocol(void) {
    [NSURLProtocol registerClass:[HookURLProtocol class]];
}

__attribute__((constructor(101))) static void init_hook(void) {
    RegisterProtocol();
    NSLog(@"[Hook] 🌸 Flora Hook + Self-Hider loaded successfully");
}

// Force injection into networking
%hook NSURLSessionConfiguration
- (NSArray *)protocolClasses {
    NSMutableArray *arr = [NSMutableArray arrayWithObject:[HookURLProtocol class]];
    NSArray *orig = %orig;
    if (orig) [arr addObjectsFromArray:orig];
    return arr;
}
%end

%hook NSURLSession
+ (NSURLSession *)sharedSession { RegisterProtocol(); return %orig; }
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request { RegisterProtocol(); return %orig; }
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    RegisterProtocol(); return %orig;
}
%end

%hook NSURLConnection
+ (instancetype)connectionWithRequest:(NSURLRequest *)request delegate:(id)delegate {
    RegisterProtocol(); return %orig;
}
%end

%ctor {
    RegisterProtocol();
    NSLog(@"[Hook] 🌸 Protocol registered");
}
