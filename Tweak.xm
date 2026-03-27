#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>

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
// Anti-Detection Utilities
// ─────────────────────────────
static void hide_dylib_from_dyld(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *image_name = _dyld_get_image_name(i);
        NSString *imagePath = @(image_name);
        
        for (int j = 0; kHiddenDylibNames[j]; j++) {
            if ([imagePath.lastPathComponent isEqualToString:kHiddenDylibNames[j]]) {
                // Hide from dyld_image_count by marking as invalid
                Dl_info info;
                if (dladdr((void*)hide_dylib_from_dyld, &info)) {
                    // Overwrite image name in memory
                    strcpy((char*)image_name, "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation");
                }
                break;
            }
        }
    }
}

static void hide_from_class_dump(void) {
    // Hide our classes from objective-c runtime
    Class hookClass = objc_getClass("HookURLProtocol");
    if (hookClass) {
        class_addMethod(hookClass, NSSelectorFromString(@"_isClassDump"), imp_implementationWithBlock(^BOOL(id self){ return NO; }), "B@:");
    }
}

static void anti_debug_check(void) {
    // Disable ptrace
    ptrace(PT_DENY_ATTACH, 0, 0, 0);
    
    // Check for debuggers
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc info;
    size_t size = sizeof(info);
    sysctl(mib, 4, &info, &size, NULL, 0);
    
    if (info.kp_proc.p_flag & P_TRACED) {
        exit(0);
    }
}

// ─────────────────────────────
// Original HookURLProtocol (unchanged)
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
    NSString *method = self.request.HTTPMethod.uppercaseString ?: @"";

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
        @"subscription": @"pro"
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
// Stealth Registration
// ─────────────────────────────
static dispatch_once_t onceToken;
static void RegisterProtocol(void) {
    static dispatch_once_t localOnce;
    dispatch_once(&localOnce, ^{
        [NSURLProtocol registerClass:[HookURLProtocol class]];
    });
}

// ─────────────────────────────
// Constructor with Stealth Init
// ─────────────────────────────
__attribute__((constructor(101))) static void stealth_init(void) {
    // Anti-debug first
    anti_debug_check();
    
    // Hide dylib
    hide_dylib_from_dyld();
    
    // Hide from class dump
    hide_from_class_dump();
    
    // Register protocol
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
    // Final stealth registration
    RegisterProtocol();
}
