#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/dyld_images.h>
#import <sys/mman.h>

static NSString *const kVerifyPath = @"/verify";
static BOOL gUnloaded = NO;

static NSString *verifyHost(void) {
    const uint8_t b[] = {
        'f'^0xAA, 'l'^0xAA, 'o'^0xAA, 'r'^0xAA, 'a'^0xAA,
        'f'^0xAA, 'l'^0xAA, 'o'^0xAA, 'w'^0xAA, 'e'^0xAA,
        'r'^0xAA, '.'^0xAA, 'l'^0xAA, 'i'^0xAA, 'f'^0xAA,
        'e'^0xAA, 0
    };
    char out[17];
    for (int i = 0; i < 16; i++) out[i] = (char)(b[i] ^ 0xAA);
    out[16] = 0;
    return [NSString stringWithUTF8String:out];
}

static NSData *bodyFromRequest(NSURLRequest *req) {
    if (req.HTTPBody) return req.HTTPBody;
    NSInputStream *s = req.HTTPBodyStream;
    if (!s) return nil;
    NSMutableData *d = [NSMutableData data];
    [s open];
    uint8_t buf[1024];
    NSInteger len;
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

// ─────────────────────────────
// Wipe image name from dyld_all_image_infos so
// string scanners find nothing even if list entry lingers
// ─────────────────────────────
static void corruptImageName(const char *fname) {
    struct task_dyld_info dyldInfo;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_DYLD_INFO,
                  (task_info_t)&dyldInfo, &count) != KERN_SUCCESS) return;

    struct dyld_all_image_infos *infos =
        (struct dyld_all_image_infos *)dyldInfo.all_image_info_addr;
    if (!infos) return;

    for (uint32_t i = 0; i < infos->infoArrayCount; i++) {
        const char *name = infos->infoArray[i].imageFilePath;
        if (name && strcmp(name, fname) == 0) {
            // Make the name page writable and zero it out
            uintptr_t page = (uintptr_t)name & ~(uintptr_t)0xFFF;
            if (mprotect((void *)page, 0x1000, PROT_READ | PROT_WRITE) == 0) {
                memset((void *)name, 0, strlen(fname));
                mprotect((void *)page, 0x1000, PROT_READ);
            }
            break;
        }
    }
}

static void removeSelfFromDyld(void) {
    Dl_info info;
    if (!dladdr((void *)removeSelfFromDyld, &info)) return;

    // First corrupt the name so scanners can't match it
    corruptImageName(info.dli_fname);

    // Then remove from image list
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strcmp(name, info.dli_fname) == 0) {
            typedef void (*RemoveFn)(uint32_t);
            RemoveFn fn = (RemoveFn)dlsym(RTLD_DEFAULT, "_dyld_remove_image");
            if (fn) fn(i);
            break;
        }
    }
}

static void wipeMachHeader(void) {
    Dl_info info;
    if (!dladdr((void *)wipeMachHeader, &info)) return;
    uintptr_t base = (uintptr_t)info.dli_fbase;
    uintptr_t page = base & ~(uintptr_t)0xFFF;
    struct mach_header_64 *mh = (struct mach_header_64 *)base;
    mprotect((void *)page, 0x1000, PROT_READ | PROT_WRITE);
    mh->ncmds = 0;
    mh->sizeofcmds = 0;
    mprotect((void *)page, 0x1000, PROT_READ | PROT_EXEC);
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
            @"success":      @YES,
            @"code":         @0,
            @"username":     keyValue,
            @"subscription": @"free"
        };

        NSData *fakeData = [NSJSONSerialization dataWithJSONObject:fakeJSON options:0 error:nil];
        NSHTTPURLResponse *fakeResp =
            [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                        statusCode:200
                                       HTTPVersion:@"HTTP/1.1"
                                      headerFields:@{@"Content-Type": @"application/json"}];

        completionHandler(fakeData, fakeResp, nil);
        gUnloaded = YES;

        dispatch_async(dispatch_get_main_queue(), ^{
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
    // Remove immediately on load — before any other dylib can scan
    removeSelfFromDyld();
}
