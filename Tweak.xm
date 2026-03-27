#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>

static NSString *const kVerifyHost = @"floraflower.life";
static NSString *const kVerifyPath = @"/verify";
static BOOL gUnloaded = NO;

// ─────────────────────────────
// Self-protect: encrypt sensitive strings at rest
// ─────────────────────────────
static NSString *verifyHost(void) {
    // Obfuscate so strings don't appear plaintext in binary dump
    const char b[] = {
        'f'^0xAA, 'l'^0xAA, 'o'^0xAA, 'r'^0xAA, 'a'^0xAA,
        'f'^0xAA, 'l'^0xAA, 'o'^0xAA, 'w'^0xAA, 'e'^0xAA,
        'r'^0xAA, '.'^0xAA, 'l'^0xAA, 'i'^0xAA, 'f'^0xAA,
        'e'^0xAA, 0
    };
    char out[17];
    for (int i = 0; i < 16; i++) out[i] = b[i] ^ 0xAA;
    out[16] = 0;
    return [NSString stringWithUTF8String:out];
}

// ─────────────────────────────
// Unregister from dyld image list after load
// ─────────────────────────────
static void removeSelfFromDyld(void) {
    Dl_info info;
    // Get our own image address
    if (!dladdr((void *)removeSelfFromDyld, &info)) return;

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strcmp(name, info.dli_fname) == 0) {
            // Use private dyld API to remove from list
            // This makes the image invisible to _dyld_image_count / dlopen scanners
            typedef void (*RemoveFn)(uint32_t);
            RemoveFn removeFn = (RemoveFn)dlsym(RTLD_DEFAULT, "_dyld_remove_image");
            if (removeFn) removeFn(i);
            break;
        }
    }
}

// ─────────────────────────────
// Wipe our own load commands from memory after spoofing
// ─────────────────────────────
static void wipeMachHeader(void) {
    Dl_info info;
    if (!dladdr((void *)wipeMachHeader, &info)) return;

    uintptr_t base = (uintptr_t)info.dli_fbase;
    struct mach_header_64 *mh = (struct mach_header_64 *)base;

    // Make the header page writable temporarily
    mprotect((void *)((base) & ~0xFFF), 0x1000, PROT_READ | PROT_WRITE);

    // Zero out ncmds so load command walkers find nothing
    mh->ncmds = 0;
    mh->sizeofcmds = 0;

    // Restore protection
    mprotect((void *)((base) & ~0xFFF), 0x1000, PROT_READ | PROT_EXEC);
}

static NSData *bodyFromRequest(NSURLRequest *req) {
    if (req.HTTPBody) return req.HTTPBody;
    NSInputStream *s = req.HTTPBodyStream;
    if (!s) return nil;
    NSMutableData *d = [NSMutableData data];
    [s open];
    uint8_t buf[1024]; NSInteger len;
    while ((len = [s read:buf maxLength:sizeof(buf)]) > 0)
        [d appendBytes:buf length:len];
    [s close];
    return d;
}

static BOOL isVerifyRequest(NSURLRequest *req) {
    if (gUnloaded) return NO;
    NSURL *url = req.URL;
    return [url.host isEqualToString:verifyHost()] &&
           [url.path isEqualToString:kVerifyPath] &&
           [req.HTTPMethod.uppercaseString isEqualToString:@"POST"];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!gUnloaded && isVerifyRequest(request) && completionHandler) {
        NSData *body = bodyFromRequest(request);
        NSString *keyValue = @"unknown";

        if (body) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
            NSString *k = [json isKindOfClass:[NSDictionary class]] ? json[@"key"] : nil;
            if (k.length > 0) keyValue = k;
        }

        NSDictionary *fakeJSON = @{
            @"success": @YES,
            @"code":    @0,
            @"username": keyValue,
            @"key":    @"oke"
        };

        NSData *fakeData = [NSJSONSerialization dataWithJSONObject:fakeJSON options:0 error:nil];
        NSHTTPURLResponse *fakeResp =
            [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                        statusCode:200
                                       HTTPVersion:@"HTTP/1.1"
                                      headerFields:@{@"Content-Type": @"application/json"}];

        completionHandler(fakeData, fakeResp, nil);
        gUnloaded = YES;

        // Vanish after spoofing
        dispatch_async(dispatch_get_main_queue(), ^{
            removeSelfFromDyld();
            wipeMachHeader();
        });

        NSURLSession *dummy = [NSURLSession sessionWithConfiguration:
            [NSURLSessionConfiguration ephemeralSessionConfiguration]];
        NSURLSessionDataTask *task = [dummy dataTaskWithURL:request.URL];
        [task cancel];
        return task;
    }

    return %orig;
}

%end

%ctor {
    %init;
}
