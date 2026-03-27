#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#import <sys/ptrace.h>
#import <objc/runtime.h>

// ─────────────────────────────
// Anti-Detection Constants
// ─────────────────────────────
static NSString *const kVerifyHost = @"floraflower.life";
static NSString *const kVerifyPath = @"/verify";

// Hidden dylib names
static NSString *const kHiddenDylibNames[] = {
    @"HookURLProtocol.dylib",
    @"libhook.dylib",
    @"tweak.dylib",
    @"substrate.dylib",
    @"libsubstrate.dylib",
    @"libhooking.dylib",
    @"libobjc.dylib",
    nil
};

// ─────────────────────────────
// kinfo_proc structure for iOS < 14.0
// ─────────────────────────────
struct kinfo_proc {
    int kp_proc[9];
    int kp_eproc[90];
};

// ─────────────────────────────
// Anti-Detection Utilities
// ─────────────────────────────
static void hide_dylib_from_dyld(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *image_name = _dyld_get_image_name(i);
        if (!image_name) continue;
        
        NSString *imagePath = @(image_name);
        NSString *dylibName = imagePath.lastPathComponent;
        
        for (int j = 0; kHiddenDylibNames[j]; j++) {
            if ([dylibName isEqualToString:kHiddenDylibNames[j]]) {
                // Hide by overwriting with system path
                const char *fake_path = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
                strncpy((char *)image_name, fake_path, strlen(fake_path) + 1);
                break;
            }
        }
    }
}

static void hide_from_class_dump(void) {
    Class hookClass = objc_getClass("HookURLProtocol");
    if (hookClass) {
        class_addMethod(hookClass, 
            NSSelectorFromString(@"_isClassDump"), 
            imp_implementationWithBlock(^(id self){ return NO; }), 
            "B@:");
    }
}

static void anti_debug_check(void) {
    // Disable ptrace
    ptrace(PT_DENY_ATTACH, 0, 0, 0);
    
    // Check for debuggers via sysctl
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc info;
    size_t size = sizeof(info);
    
    if (sysctl(mib, 4, &info, &size, NULL, 0) == 0) {
        if ((info.kp_proc[0] & P_TRACED) != 0) {
            // Debugger detected - exit gracefully
            exit(0);
        }
    }
}

// ─────────────────────────────
// Original HookURLProtocol
// ─────────────────────────────
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
    
    NSData *bodyData = self.request.HTTPBody;

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
            if (k.length > 0) {
                keyValue = k;
            }
        }

        if ([keyValue isEqualToString:@"unknown"]) {
            NSString *bodyStr = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];
            NSArray *pairs = [bodyStr componentsSeparatedByString:@"&"];
            for (NSString *pair in pairs) {
                NSArray *kv = [pair componentsSeparatedByString:@"="];
                if (kv.count == 2) {
                    NSString *k = kv[0];
                    NSString *v = [kv[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                    if ([k isEqualToString:@"key"]) {
                        keyValue = v ?: @"unknown";
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
        @"subscription": @"pro"
    };

    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];

    NSDictionary *headers = @{
        @"Content-Type": @"application/json",
        @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)data.length]
    };

    NSHTTPURLResponse *response =
        [[NSHTTPURLResponse alloc] initWithURL:url
                                    statusCode:200
                                   HTTPVersion:@"HTTP/1.1"
                                  headerFields:headers];

    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {}

@end

// ─────────────────────────────
// Stealth Registration
// ─────────────────────────────
static dispatch_once_t onceToken;
static void RegisterProtocol(void) {
    dispatch_once(&onceToken, ^{
        [NSURLProtocol registerClass:[HookURLProtocol class]];
    });
}

// ─────────────────────────────
// Constructor with Stealth Init
// ─────────────────────────────
__attribute__((constructor(101))) static void stealth_init(void) {
    anti_debug_check();
    hide_dylib_from_dyld();
    hide_from_class_dump();
    RegisterProtocol();
}

// ─────────────────────────────
// Original Hooks with Stealth
// ─────────────────────────────
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
    return %orig(request);
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    RegisterProtocol();
    return %orig(request, completionHandler);
}

%end

%hook NSURLConnection

+ (instancetype)connectionWithRequest:(NSURLRequest *)request delegate:(id)delegate {
    RegisterProtocol();
    return %orig(request, delegate);
}

%end

%ctor {
    RegisterProtocol();
}
