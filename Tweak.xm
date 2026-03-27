#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>

// ─────────────────────────────
// iOS Version Detection
// ─────────────────────────────
#define IOS_VERSION_EQUAL_TO(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define IOS_VERSION_GREATER_THAN(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define IOS_VERSION_GREATER_THAN_OR_EQUAL_TO(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

// ─────────────────────────────
// Anti-Detection Constants
// ─────────────────────────────
static NSString *const kVerifyHost = @"floraflower.life";
static NSString *const kVerifyPath = @"/verify";

static NSString *const kHiddenDylibNames[] = {
    @"HookURLProtocol.dylib",
    @"libhook.dylib",
    @"tweak.dylib",
    @"substrate.dylib",
    @"libsubstrate.dylib",
    @"libhooking.dylib",
    nil
};

// ─────────────────────────────
// Safe Anti-Debug (No ptrace/sysctl)
// ─────────────────────────────
static void safe_anti_debug(void) {
    // Time-based check (simple but effective)
    static CFAbsoluteTime startTime = 0;
    if (startTime == 0) {
        startTime = CFAbsoluteTimeGetCurrent();
    } else {
        CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - startTime;
        if (elapsed < 0.1 && elapsed > 0) { // Suspicious timing
            exit(0);
        }
    }
    
    // Check for common debugger ports
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock != -1) {
        struct sockaddr_in addr = {0};
        addr.sin_family = AF_INET;
        addr.sin_port = htons(1234); // Common debug port
        if (connect(sock, (struct sockaddr*)&addr, sizeof(addr)) == 0) {
            close(sock);
            exit(0);
        }
        close(sock);
    }
}

// ─────────────────────────────
// Safe Dylib Hiding
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
                const char *fake_path = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
                strlcpy((char *)image_name, fake_path, 256);
                break;
            }
        }
    }
}

static void hide_from_class_dump(void) {
    Class hookClass = objc_getClass("HookURLProtocol");
    if (hookClass) {
        IMP block_imp = imp_implementationWithBlock(^BOOL(id self){
            return NO;
        });
        class_addMethod(hookClass, 
            NSSelectorFromString(@"_isClassDump"), 
            block_imp, 
            "B@:");
    }
}

// ─────────────────────────────
// HookURLProtocol (Core Logic)
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

    // Flora verify check
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
    NSData *bodyData = self.request.HTTPBody;

    // Handle stream body again
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

    // Parse JSON
    if (bodyData) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
        if ([json isKindOfClass:[NSDictionary class]]) {
            NSString *k = json[@"key"];
            if (k.length > 0) keyValue = k;
        }
    }

    // Fallback: parse form-urlencoded
    if ([keyValue isEqualToString:@"unknown"] && bodyData) {
        NSString *bodyStr = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];
        NSArray *pairs = [bodyStr componentsSeparatedByString:@"&"];
        for (NSString *pair in pairs) {
            NSArray *kv = [pair componentsSeparatedByString:@"="];
            if (kv.count == 2) {
                NSString *k = kv[0];
                NSString *v = [kv[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                if ([k isEqualToString:@"key"] && v.length > 0) {
                    keyValue = v;
                    break;
                }
            }
        }
    }

    NSLog(@"[Hook] 🎯 Spoof key: %@", keyValue);

    NSDictionary *responseJSON = @{
        @"success": @YES,
        @"code": @0,
        @"username": keyValue,
        @"subscription": @"free"
    };

    NSData *data = [NSJSONSerialization dataWithJSONObject:responseJSON options:0 error:nil];

    NSDictionary *headers = @{
        @"Content-Type": @"application/json",
        @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)data.length ?: 0]
    };

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] 
        initWithURL:url statusCode:200 
        HTTPVersion:@"HTTP/1.1" headerFields:headers];

    [self.client URLProtocol:self didReceiveResponse:response 
        cacheStoragePolicy:NSURLCacheStorageNotAllowed];
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
// Constructor
// ─────────────────────────────
__attribute__((constructor(101))) static void stealth_init(void) {
    safe_anti_debug();
    hide_dylib_from_dyld();
    hide_from_class_dump();
    RegisterProtocol();
}

// ─────────────────────────────
// Hooks
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
