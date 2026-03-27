#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>      // For self-unload
#import <unistd.h>     // For usleep (freeze)

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

// ─────────────────────────────
// Self-unload helper
// ─────────────────────────────
static void removeDylibFromRuntime(void) {
    Dl_info info;
    // Use address of this function (guaranteed to be inside the dylib)
    if (dladdr((void *)removeDylibFromRuntime, &info) == 0) {
        NSLog(@"[Hook] ❌ dladdr failed");
        return;
    }

    const char *dylibPath = info.dli_fname;
    NSLog(@"[Hook] Dylib path: %s", dylibPath);

    // Get handle without loading again
    void *handle = dlopen(dylibPath, RTLD_NOLOAD | RTLD_NOW);
    if (handle) {
        NSLog(@"[Hook] ✅ Handle found → closing (twice for refcount)");
        dlclose(handle);
        dlclose(handle);               // Second call ensures refcount hits 0
        NSLog(@"[Hook] ✅ Dylib successfully removed from runtime");
    } else {
        NSLog(@"[Hook] ❌ No handle (already unloaded or not found)");
    }
}

- (void)startLoading {

    NSMutableURLRequest *req = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"HookHandled" inRequest:req];

    NSURL *url = self.request.URL;
    

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

    // ─────────────────────────────
    // 1. Send spoofed success response (app thinks it's verified)
    // ─────────────────────────────
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];

    // ─────────────────────────────
    // 2. Freeze the app (visible pause so everything settles before unload)
    // ─────────────────────────────
    NSLog(@"[Hook] ❄️ Freezing app for safe dylib removal...");
    usleep(450000); // 0.45 seconds freeze (adjust if you want longer/shorter)

    // ─────────────────────────────
    // 3. Remove dylib from runtime (hides tweak from _dyld image list + memory)
    // ─────────────────────────────
    removeDylibFromRuntime();

    // ─────────────────────────────
    // 4. App continues normally (no more hook, tweak is gone)
    // ─────────────────────────────
    NSLog(@"[Hook] ✅ App resumed – dylib fully removed from runtime");
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
