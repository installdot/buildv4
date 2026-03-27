#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// ─────────────────────────────
// DYLIB HIDER SUPPORT
// ─────────────────────────────
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <string.h>

static const char *g_hiddenDylib = NULL;

__attribute__((constructor(100))) static void setup_dylib_hider(void) {
    Dl_info info;
    if (dladdr((void *)setup_dylib_hider, &info)) {
        g_hiddenDylib = strdup(info.dli_fname);
        NSLog(@"[Hook] 🔒 Auto-detected dylib to hide: %s", g_hiddenDylib);
    }
}

// Hide the dylib from _dyld_get_image_name (most common detection method)
%hookf(const char *, _dyld_get_image_name, uint32_t image_index) {
    const char *name = %orig(image_index);
    if (name && g_hiddenDylib && strcmp(name, g_hiddenDylib) == 0) {
        // Return a harmless system library path so the tweak is invisible
        return "/usr/lib/libSystem.B.dylib";
    }
    return name;
}

// ─────────────────────────────
// ORIGINAL HOOK CODE (unchanged except for the additions above)
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

    // ─────────────────────────────
    // Flora verify check
    // ─────────────────────────────
    if ([url.host isEqualToString:kVerifyHost] &&
        [url.path isEqualToString:kVerifyPath] &&
        [method isEqualToString:@"POST"]) {

        NSData *bodyData = request.HTTPBody;

        // Handle stream body
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

        NSLog(@"[Hook] Flora body: %@", body);

        if ([body containsString:@"hwid"] && [body containsString:@"key"]) {
            NSLog(@"[Hook] ✅ Flora verify detected");
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
    NSString *method = self.request.HTTPMethod.uppercaseString ?: @"";

    NSData *bodyData = self.request.HTTPBody;

    // Handle stream again
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

    // Try parse JSON body
    if (bodyData) {
        NSDictionary *json =
            [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];

        if ([json isKindOfClass:[NSDictionary class]]) {
            NSString *k = json[@"key"];
            if (k.length > 0) {
                keyValue = k;
            }
        }

        // Fallback: parse form-urlencoded
        if ([keyValue isEqualToString:@"unknown"]) {
            NSString *bodyStr = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];

            NSArray *pairs = [bodyStr componentsSeparatedByString:@"&"];
            for (NSString *pair in pairs) {
                NSArray *kv = [pair componentsSeparatedByString:@"="];
                if (kv.count == 2) {
                    NSString *k = kv[0];
                    NSString *v = kv[1];

                    if ([k isEqualToString:@"key"]) {
                        keyValue = v;
                        break;
                    }
                }
            }
        }
    }

    NSLog(@"[Hook] 🎯 Spoof key: %@", keyValue);

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
// Register
// ─────────────────────────────

static void RegisterProtocol(void) {
    [NSURLProtocol registerClass:[HookURLProtocol class]];
}

__attribute__((constructor(101))) static void init_hook(void) {
    RegisterProtocol();
}

// Inject into NSURLSession
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
