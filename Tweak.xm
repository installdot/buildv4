// tweak.xm - TNSpike URL Scanner
// Scans app binary, bundles, NSUserDefaults, Info.plist, loaded classes,
// method names, strings in memory — dumps all findings to Documents/tnspike_scan.txt

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <dlfcn.h>

// ─────────────────────────────────────────
// Keywords to scan for
// ─────────────────────────────────────────
static NSArray<NSString *> *scanKeywords() {
    return @[
        @"app.tnspike.com:2087",
        @"app.tnspike.com",
        @"tnspike.com",
        @"tnspike",
        @":2087",
        @"2087",
        @"verify_udid",
        @"/verify_udid",
        @"TNK-",
        @"activation_key",
        @"package_type",
    ];
}

// ─────────────────────────────────────────
// Output path
// ─────────────────────────────────────────
static NSString *outputPath() {
    NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *dir = docs.firstObject ?: NSTemporaryDirectory();
    return [dir stringByAppendingPathComponent:@"tnspike_scan.txt"];
}

// ─────────────────────────────────────────
// Core scanner
// ─────────────────────────────────────────
static void runScan() {
    NSMutableString *report = [NSMutableString string];
    NSArray *keywords = scanKeywords();
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss";

    [report appendFormat:@"╔══════════════════════════════════════════════╗\n"];
    [report appendFormat:@"║         TNSpike URL Scanner Report           ║\n"];
    [report appendFormat:@"╚══════════════════════════════════════════════╝\n"];
    [report appendFormat:@"Scan time : %@\n", [df stringFromDate:[NSDate date]]];
    [report appendFormat:@"Bundle ID : %@\n", NSBundle.mainBundle.bundleIdentifier];
    [report appendFormat:@"App name  : %@\n", NSBundle.mainBundle.infoDictionary[@"CFBundleName"]];
    [report appendFormat:@"Version   : %@\n\n", NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]];

    NSUInteger totalHits = 0;

    // ── 1. Info.plist ────────────────────────────────────────
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    [report appendString:@"[1] Info.plist\n"];
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    NSUInteger sec1 = 0;
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:info
                                                                   format:NSPropertyListXMLFormat_v1_0
                                                                  options:0
                                                                    error:nil];
    NSString *plistStr = plistData ? [[NSString alloc] initWithData:plistData encoding:NSUTF8StringEncoding] : @"";
    for (NSString *kw in keywords) {
        if ([plistStr.lowercaseString containsString:kw.lowercaseString]) {
            [report appendFormat:@"  ✓ Found keyword: \"%@\"\n", kw];
            sec1++; totalHits++;
        }
    }
    if (sec1 == 0) [report appendString:@"  ✗ No matches\n"];
    [report appendString:@"\n"];

    // ── 2. NSUserDefaults ────────────────────────────────────
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    [report appendString:@"[2] NSUserDefaults\n"];
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    NSUInteger sec2 = 0;
    NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    for (NSString *key in defaults) {
        NSString *val = [NSString stringWithFormat:@"%@", defaults[key]];
        for (NSString *kw in keywords) {
            if ([val.lowercaseString containsString:kw.lowercaseString] ||
                [key.lowercaseString containsString:kw.lowercaseString]) {
                [report appendFormat:@"  ✓ Key: \"%@\" → Value: \"%@\"\n", key, val];
                sec2++; totalHits++;
                break;
            }
        }
    }
    if (sec2 == 0) [report appendString:@"  ✗ No matches\n"];
    [report appendString:@"\n"];

    // ── 3. NSBundle paths / resources ───────────────────────
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    [report appendString:@"[3] Bundle resource paths\n"];
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    NSUInteger sec3 = 0;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *bundlePath = NSBundle.mainBundle.bundlePath;
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:bundlePath];
    NSString *filePath;
    while ((filePath = [enumerator nextObject])) {
        NSString *ext = filePath.pathExtension.lowercaseString;
        // Only scan text-like files
        if ([@[@"plist", @"json", @"xml", @"strings", @"txt", @"js", @"html", @"config", @"cfg"] containsObject:ext]) {
            NSString *fullPath = [bundlePath stringByAppendingPathComponent:filePath];
            NSString *content = [NSString stringWithContentsOfFile:fullPath
                                                          encoding:NSUTF8StringEncoding
                                                             error:nil];
            if (!content) content = [NSString stringWithContentsOfFile:fullPath
                                                              encoding:NSISOLatin1StringEncoding
                                                                 error:nil];
            if (content) {
                for (NSString *kw in keywords) {
                    if ([content.lowercaseString containsString:kw.lowercaseString]) {
                        [report appendFormat:@"  ✓ File: %@\n     Keyword: \"%@\"\n", filePath, kw];
                        sec3++; totalHits++;
                        break;
                    }
                }
            }
        }
    }
    if (sec3 == 0) [report appendString:@"  ✗ No matches\n"];
    [report appendString:@"\n"];

    // ── 4. Loaded dylibs / frameworks ───────────────────────
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    [report appendString:@"[4] Loaded images (dylibs/frameworks)\n"];
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    NSUInteger sec4 = 0;
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0; i < imageCount; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        NSString *imageName = @(name);
        for (NSString *kw in keywords) {
            if ([imageName.lowercaseString containsString:kw.lowercaseString]) {
                [report appendFormat:@"  ✓ Image: %@\n", imageName];
                sec4++; totalHits++;
                break;
            }
        }
    }
    if (sec4 == 0) [report appendString:@"  ✗ No matches\n"];
    [report appendString:@"\n"];

    // ── 5. ObjC class names ──────────────────────────────────
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    [report appendString:@"[5] ObjC class names\n"];
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    NSUInteger sec5 = 0;
    unsigned int classCount = 0;
    const char **classList = objc_copyClassNamesForImage(
        [NSBundle.mainBundle.executablePath UTF8String], &classCount);
    if (classList) {
        for (unsigned int i = 0; i < classCount; i++) {
            NSString *className = @(classList[i]);
            for (NSString *kw in keywords) {
                if ([className.lowercaseString containsString:kw.lowercaseString]) {
                    [report appendFormat:@"  ✓ Class: %@  (keyword: \"%@\")\n", className, kw];
                    sec5++; totalHits++;
                    break;
                }
            }
        }
        free(classList);
    }
    if (sec5 == 0) [report appendString:@"  ✗ No matches\n"];
    [report appendString:@"\n"];

    // ── 6. ObjC method names ─────────────────────────────────
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    [report appendString:@"[6] ObjC method names\n"];
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    NSUInteger sec6 = 0;
    unsigned int cls2Count = 0;
    const char **classList2 = objc_copyClassNamesForImage(
        [NSBundle.mainBundle.executablePath UTF8String], &cls2Count);
    if (classList2) {
        for (unsigned int i = 0; i < cls2Count; i++) {
            Class cls = objc_getClass(classList2[i]);
            if (!cls) continue;
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(cls, &methodCount);
            for (unsigned int m = 0; m < methodCount; m++) {
                NSString *sel = NSStringFromSelector(method_getName(methods[m]));
                for (NSString *kw in keywords) {
                    if ([sel.lowercaseString containsString:kw.lowercaseString]) {
                        [report appendFormat:@"  ✓ [%@ %@]  (keyword: \"%@\")\n",
                            @(classList2[i]), sel, kw];
                        sec6++; totalHits++;
                        break;
                    }
                }
            }
            if (methods) free(methods);
        }
        free(classList2);
    }
    if (sec6 == 0) [report appendString:@"  ✗ No matches\n"];
    [report appendString:@"\n"];

    // ── 7. Mach-O __cstring / __cfstring section scan ───────
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    [report appendString:@"[7] Mach-O __cstring / __cfstring binary scan\n"];
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    NSUInteger sec7 = 0;
    for (uint32_t idx = 0; idx < _dyld_image_count(); idx++) {
        const char *imgName = _dyld_get_image_name(idx);
        if (!imgName) continue;
        // Only scan main app binary
        NSString *imgStr = @(imgName);
        if (![imgStr containsString:NSBundle.mainBundle.bundlePath]) continue;

        const struct mach_header *mh = _dyld_get_image_header(idx);
        intptr_t slide = _dyld_get_image_vmaddr_slide(idx);

        BOOL is64 = (mh->magic == MH_MAGIC_64 || mh->magic == MH_CIGAM_64);
        uintptr_t cur;
        uint32_t ncmds;

        if (is64) {
            const struct mach_header_64 *mh64 = (const struct mach_header_64 *)mh;
            ncmds = mh64->ncmds;
            cur = (uintptr_t)(mh64 + 1);
        } else {
            ncmds = mh->ncmds;
            cur = (uintptr_t)(mh + 1);
        }

        for (uint32_t c = 0; c < ncmds; c++) {
            const struct load_command *lc = (const struct load_command *)cur;
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
                const struct section_64 *sec = (const struct section_64 *)(seg + 1);
                for (uint32_t s = 0; s < seg->nsects; s++, sec++) {
                    NSString *secName = @(sec->sectname);
                    if ([secName containsString:@"__cstring"] ||
                        [secName containsString:@"__cfstring"] ||
                        [secName containsString:@"__ustring"]) {
                        const char *ptr = (const char *)(sec->addr + slide);
                        const char *end = ptr + sec->size;
                        while (ptr < end) {
                            if (*ptr == '\0') { ptr++; continue; }
                            NSString *str = [NSString stringWithUTF8String:ptr];
                            if (str) {
                                for (NSString *kw in keywords) {
                                    if ([str.lowercaseString containsString:kw.lowercaseString]) {
                                        [report appendFormat:@"  ✓ __cstring: \"%@\"  (keyword: \"%@\")\n", str, kw];
                                        sec7++; totalHits++;
                                        break;
                                    }
                                }
                            }
                            ptr += strlen(ptr) + 1;
                        }
                    }
                }
            }
            cur += lc->cmdsize;
        }
    }
    if (sec7 == 0) [report appendString:@"  ✗ No matches\n"];
    [report appendString:@"\n"];

    // ── 8. NSHTTPCookieStorage ───────────────────────────────
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    [report appendString:@"[8] NSHTTPCookieStorage\n"];
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    NSUInteger sec8 = 0;
    for (NSHTTPCookie *cookie in NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies) {
        NSString *combined = [NSString stringWithFormat:@"%@ %@ %@",
            cookie.domain, cookie.name, cookie.value];
        for (NSString *kw in keywords) {
            if ([combined.lowercaseString containsString:kw.lowercaseString]) {
                [report appendFormat:@"  ✓ Cookie domain: %@  name: %@  value: %@\n",
                    cookie.domain, cookie.name, cookie.value];
                sec8++; totalHits++;
                break;
            }
        }
    }
    if (sec8 == 0) [report appendString:@"  ✗ No matches\n"];
    [report appendString:@"\n"];

    // ── 9. Keychain (accessible items) ──────────────────────
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    [report appendString:@"[9] Keychain generic passwords\n"];
    [report appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    NSUInteger sec9 = 0;
    NSDictionary *keychainQuery = @{
        (__bridge id)kSecClass:           (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecReturnAttributes: @YES,
        (__bridge id)kSecReturnData:       @YES,
        (__bridge id)kSecMatchLimit:       (__bridge id)kSecMatchLimitAll
    };
    CFTypeRef keychainResult = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)keychainQuery, &keychainResult) == errSecSuccess) {
        NSArray *items = (__bridge_transfer NSArray *)keychainResult;
        for (NSDictionary *item in items) {
            NSString *acct    = item[(__bridge id)kSecAttrAccount] ?: @"";
            NSString *service = item[(__bridge id)kSecAttrService] ?: @"";
            NSData   *vData   = item[(__bridge id)kSecValueData];
            NSString *val     = vData ? [[NSString alloc] initWithData:vData encoding:NSUTF8StringEncoding] : @"";
            NSString *combined = [NSString stringWithFormat:@"%@ %@ %@", acct, service, val ?: @""];
            for (NSString *kw in keywords) {
                if ([combined.lowercaseString containsString:kw.lowercaseString]) {
                    [report appendFormat:@"  ✓ Service: %@  Account: %@  Value: %@\n",
                        service, acct, val];
                    sec9++; totalHits++;
                    break;
                }
            }
        }
    }
    if (sec9 == 0) [report appendString:@"  ✗ No matches\n"];
    [report appendString:@"\n"];

    // ── Summary ──────────────────────────────────────────────
    [report appendString:@"╔══════════════════════════════════════════════╗\n"];
    [report appendFormat:@"║  TOTAL HITS: %-3lu                            ║\n", (unsigned long)totalHits];
    [report appendString:@"╚══════════════════════════════════════════════╝\n"];
    [report appendFormat:@"Output: %@\n", outputPath()];

    // Write file
    NSError *writeError;
    [report writeToFile:outputPath()
             atomically:YES
               encoding:NSUTF8StringEncoding
                  error:&writeError];

    NSLog(@"[TNSpikeScanner] Done. Hits: %lu  File: %@",
          (unsigned long)totalHits, outputPath());

    // Show alert on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Scan Complete"
            message:[NSString stringWithFormat:
                @"Total hits: %lu\n\nSaved to:\n%@",
                (unsigned long)totalHits, outputPath()]
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        UIViewController *root = UIApplication.sharedApplication
            .keyWindow.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        [root presentViewController:alert animated:YES completion:nil];
    });
}

// ─────────────────────────────────────────────────────────────
// Floating scan button injected into the app
// ─────────────────────────────────────────────────────────────
@interface TNSpikeScanButton : UIButton
@end

@implementation TNSpikeScanButton

+ (void)inject {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *window = UIApplication.sharedApplication.keyWindow;
        if (!window) return;

        TNSpikeScanButton *btn = [TNSpikeScanButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(window.bounds.size.width - 80, 80, 64, 64);
        btn.backgroundColor = [UIColor colorWithRed:0.1 green:0.6 blue:1.0 alpha:0.92];
        btn.layer.cornerRadius = 32;
        btn.layer.shadowColor  = UIColor.blackColor.CGColor;
        btn.layer.shadowOpacity = 0.4f;
        btn.layer.shadowOffset  = CGSizeMake(0, 3);
        btn.layer.shadowRadius  = 6;
        [btn setTitle:@"🔍" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:28];
        [btn addTarget:btn
                action:@selector(tapped)
      forControlEvents:UIControlEventTouchUpInside];
        btn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
                             | UIViewAutoresizingFlexibleBottomMargin;
        [window addSubview:btn];
        [window bringSubviewToFront:btn];
    });
}

- (void)tapped {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        runScan();
    });
}

@end

// ─────────────────────────────────────────────────────────────
// Hook UIApplication to inject button after app is ready
// ─────────────────────────────────────────────────────────────
%hook UIApplication

- (void)_reportAppLaunchFinished {
    %orig;
    [TNSpikeScanButton inject];
}

%end

%ctor {
    // Fallback injection in case _reportAppLaunchFinished doesn't fire
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (![[UIApplication.sharedApplication.keyWindow.subviews
               filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary *b) {
                   return [obj isKindOfClass:[TNSpikeScanButton class]];
               }]] count]) {
            [TNSpikeScanButton inject];
        }
    });
}
