/*
 * AppDumper - Comprehensive App Data Harvester
 *
 * Dumps everything the app holds:
 *   - Keychain (all classes)
 *   - NSUserDefaults (all suites + standard)
 *   - All files in app container (Documents, Library, tmp, Caches)
 *   - Named + general UIPasteboard
 *   - HTTP cookies (NSHTTPCookieStorage)
 *   - Loaded ObjC classes + key methods
 *   - NSURLCache cached responses
 *   - CoreData stores found on disk
 *   - SQLite databases found on disk
 *   - /var/mobile/Library/Preferences plists
 *   - Environment variables + process info
 *   - Memory scan for target UDID string
 *     "00008020-000640860179002E"
 *
 * Output: <App Documents>/full_dump.txt
 *
 * Auto-runs on app launch via %ctor + UIApplication hook
 */

#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>

// ─────────────────────────────────────────────
#define TARGET_UDID  @"00008020-000640860179002E"
#define TARGET_C     "00008020-000640860179002E"
// ─────────────────────────────────────────────

static NSMutableString *gReport   = nil;
static BOOL             gDumping  = NO;

// =============================================================================
//  MARK: - Report helpers
// =============================================================================

static void rHeader(NSString *title) {
    [gReport appendFormat:
        @"\n╔══════════════════════════════════════════╗\n"
          "║  %@\n"
          "╚══════════════════════════════════════════╝\n",
        title];
}

static void rLine(NSString *s) {
    [gReport appendFormat:@"  %@\n", s];
}

static void rFound(NSString *where, NSString *context) {
    [gReport appendFormat:
        @"\n  ★★★ TARGET UDID FOUND ★★★\n"
          "  Location : %@\n"
          "  Context  : %@\n\n",
        where, context];
    NSLog(@"[AppDumper] ★ FOUND: %@ in %@", TARGET_UDID, where);
}

static void checkForUDID(NSString *where, NSString *value) {
    if (!value) return;
    if ([value rangeOfString:TARGET_UDID options:NSCaseInsensitiveSearch].location
            != NSNotFound)
        rFound(where, value);
}

// =============================================================================
//  MARK: - 1. Keychain dump
// =============================================================================

static void dumpKeychain(void) {
    rHeader(@"KEYCHAIN");
    gDumping = YES;

    CFTypeRef classes[] = {
        kSecClassGenericPassword, kSecClassInternetPassword,
        kSecClassCertificate, kSecClassKey, kSecClassIdentity
    };
    NSArray *names = @[@"GenericPassword",@"InternetPassword",
                       @"Certificate",@"Key",@"Identity"];

    for (int i = 0; i < 5; i++) {
        [gReport appendFormat:@"\n  ── %@ ──\n", names[i]];
        NSDictionary *q = @{
            (__bridge id)kSecClass           : (__bridge id)classes[i],
            (__bridge id)kSecMatchLimit       : (__bridge id)kSecMatchLimitAll,
            (__bridge id)kSecReturnAttributes : @YES,
            (__bridge id)kSecReturnData       : @YES
        };
        CFTypeRef cfr = NULL;
        OSStatus s = SecItemCopyMatching((__bridge CFDictionaryRef)q, &cfr);
        if (s == errSecSuccess && cfr) {
            id raw = CFBridgingRelease(cfr);
            NSArray *items = [raw isKindOfClass:[NSArray class]] ? raw : @[raw];
            [gReport appendFormat:@"  Count: %lu\n", (unsigned long)items.count];
            for (NSDictionary *item in items) {
                [gReport appendString:@"  ┌──────────────────────────────────\n"];
                for (NSString *key in item) {
                    id val = item[key];
                    NSString *strVal = nil;
                    if ([val isKindOfClass:[NSData class]]) {
                        strVal = [[NSString alloc] initWithData:(NSData *)val
                                      encoding:NSUTF8StringEncoding];
                        if (!strVal) strVal = [NSString stringWithFormat:
                            @"<data %lu B>", (unsigned long)[(NSData*)val length]];
                    } else {
                        strVal = [NSString stringWithFormat:@"%@", val];
                    }
                    [gReport appendFormat:@"  │ %-24@ = %@\n", key, strVal];
                    checkForUDID([NSString stringWithFormat:@"Keychain[%@].%@",
                                    names[i], key], strVal);
                }
                [gReport appendString:@"  └──────────────────────────────────\n"];
            }
        } else if (s == errSecItemNotFound) {
            [gReport appendString:@"  (no items)\n"];
        } else {
            [gReport appendFormat:@"  OSStatus: %d\n", (int)s];
        }
    }
    gDumping = NO;
}

// =============================================================================
//  MARK: - 2. NSUserDefaults
// =============================================================================

static void dumpUserDefaults(void) {
    rHeader(@"NSUSERDEFAULTS");

    // Standard defaults
    NSDictionary *std = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    [gReport appendFormat:@"\n  [Standard]  %lu keys\n", (unsigned long)std.count];
    for (NSString *key in std) {
        NSString *val = [NSString stringWithFormat:@"%@", std[key]];
        [gReport appendFormat:@"  %-40@ = %@\n", key, val];
        checkForUDID([NSString stringWithFormat:@"UserDefaults.standard[%@]", key], val);
    }

    // App group suites — probe common bundle-derived names
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSArray *suites = @[
        [NSString stringWithFormat:@"group.%@", bundleID],
        [NSString stringWithFormat:@"%@.shared", bundleID],
        @"group.com.tnspike",
        @"group.com.tnnguy",
        @"com.tnnguy.auth",
        @"com.tnspike.shared"
    ];
    for (NSString *suite in suites) {
        NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:suite];
        NSDictionary *d = [ud dictionaryRepresentation];
        if (d.count == 0) continue;
        [gReport appendFormat:@"\n  [Suite: %@]  %lu keys\n", suite, (unsigned long)d.count];
        for (NSString *key in d) {
            NSString *val = [NSString stringWithFormat:@"%@", d[key]];
            [gReport appendFormat:@"  %-40@ = %@\n", key, val];
            checkForUDID([NSString stringWithFormat:@"UserDefaults[%@][%@]", suite, key], val);
        }
    }
}

// =============================================================================
//  MARK: - 3. File system scan
// =============================================================================

static void scanDirectory(NSString *dir, int depth) {
    if (depth > 6) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    NSArray *contents = [fm contentsOfDirectoryAtPath:dir error:&err];
    if (!contents) return;

    for (NSString *name in contents) {
        NSString *full = [dir stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        [fm fileExistsAtPath:full isDirectory:&isDir];

        if (isDir) {
            scanDirectory(full, depth + 1);
        } else {
            // Log the file
            NSDictionary *attr = [fm attributesOfItemAtPath:full error:nil];
            unsigned long long sz = [attr[NSFileSize] unsignedLongLongValue];
            [gReport appendFormat:@"  [FILE] %@  (%llu B)\n", full, sz];

            // Try to read small text files and search for UDID
            if (sz > 0 && sz < 512 * 1024) {
                NSString *ext = full.pathExtension.lowercaseString;
                BOOL isText = [@[@"txt",@"plist",@"json",@"db",@"sqlite",
                                 @"log",@"xml",@"dat",@"cfg",@"conf",
                                 @"realm",@""] containsObject:ext];
                if (isText) {
                    NSData *data = [NSData dataWithContentsOfFile:full];
                    if (data) {
                        // Search raw bytes for UDID string
                        NSData *target = [TARGET_UDID
                            dataUsingEncoding:NSUTF8StringEncoding];
                        NSRange found = [data rangeOfData:target
                            options:0
                            range:NSMakeRange(0, data.length)];
                        if (found.location != NSNotFound) {
                            rFound([NSString stringWithFormat:@"File: %@", full],
                                   [NSString stringWithFormat:
                                    @"bytes offset %lu", (unsigned long)found.location]);
                        }

                        // Also try as UTF8 string
                        NSString *str = [[NSString alloc]
                            initWithData:data encoding:NSUTF8StringEncoding];
                        if (str)
                            checkForUDID([NSString stringWithFormat:@"File: %@", full], str);
                    }
                }
            }
        }
    }
}

static void dumpFileSystem(void) {
    rHeader(@"FILE SYSTEM SCAN");

    NSArray *roots = @[
        NSHomeDirectory(),
        NSTemporaryDirectory(),
        @"/var/mobile/Library/Preferences",
        @"/var/mobile/Library/Application Support",
        @"/var/mobile/Library/Caches/com.apple.UIKit.pboard",
        @"/var/jb/var/mobile/Library/Preferences"
    ];

    for (NSString *root in roots) {
        [gReport appendFormat:@"\n  ── Scanning: %@ ──\n", root];
        scanDirectory(root, 0);
    }
}

// =============================================================================
//  MARK: - 4. UIPasteboard
// =============================================================================

static void dumpPasteboard(void) {
    rHeader(@"UIPASTEBOARD");

    // General pasteboard
    UIPasteboard *gen = [UIPasteboard generalPasteboard];
    NSString *genStr  = [gen string];
    rLine([NSString stringWithFormat:@"[General] changeCount=%ld  string=%@",
           (long)gen.changeCount, genStr ?: @"(nil)"]);
    checkForUDID(@"UIPasteboard.general", genStr ?: @"");

    // Known named pasteboards
    NSArray *names = @[
        @"com.persist.data",
        @"com.tnspike.pb",
        @"com.tnnguy.pb",
        [NSString stringWithFormat:@"%@.pb",
            [[NSBundle mainBundle] bundleIdentifier] ?: @"app"]
    ];
    for (NSString *n in names) {
        UIPasteboard *pb = [UIPasteboard pasteboardWithName:n create:NO];
        if (!pb) continue;
        NSString *s = [pb string];
        rLine([NSString stringWithFormat:@"[%@] = %@", n, s ?: @"(nil)"]);
        checkForUDID([NSString stringWithFormat:@"UIPasteboard[%@]", n], s ?: @"");
    }
}

// =============================================================================
//  MARK: - 5. HTTP Cookies
// =============================================================================

static void dumpCookies(void) {
    rHeader(@"HTTP COOKIES");
    NSArray *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies];
    [gReport appendFormat:@"  Count: %lu\n", (unsigned long)cookies.count];
    for (NSHTTPCookie *c in cookies) {
        NSString *line = [NSString stringWithFormat:
            @"  domain=%-30@  name=%-24@  value=%@",
            c.domain, c.name, c.value];
        rLine(line);
        checkForUDID([NSString stringWithFormat:@"Cookie[%@][%@]", c.domain, c.name],
                     c.value);
    }
}

// =============================================================================
//  MARK: - 6. NSURLCache
// =============================================================================

static void dumpURLCache(void) {
    rHeader(@"NSURLCACHE");
    NSURLCache *cache = [NSURLCache sharedURLCache];
    rLine([NSString stringWithFormat:
        @"currentMemoryUsage=%lu B  currentDiskUsage=%lu B",
        (unsigned long)cache.currentMemoryUsage,
        (unsigned long)cache.currentDiskUsage]);
}

// =============================================================================
//  MARK: - 7. Loaded ObjC classes (app-specific)
// =============================================================================

static void dumpClasses(void) {
    rHeader(@"LOADED OBJC CLASSES (app bundle)");

    NSString *execPath = [[NSBundle mainBundle] executablePath];
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);

    int logged = 0;
    for (unsigned int i = 0; i < classCount && logged < 300; i++) {
        Class cls = classes[i];
        // Only log classes from the main bundle image
        const char *imgName = class_getImageName(cls);
        if (!imgName) continue;
        NSString *img = [NSString stringWithUTF8String:imgName];
        if (![img isEqualToString:execPath]) continue;

        NSString *name = [NSString stringWithUTF8String:class_getName(cls)];

        // Log class + interesting properties/methods
        unsigned int propCount = 0;
        objc_property_t *props = class_copyPropertyList(cls, &propCount);
        NSMutableArray *propNames = [NSMutableArray array];
        for (unsigned int p = 0; p < propCount && p < 20; p++) {
            [propNames addObject:[NSString stringWithUTF8String:
                property_getName(props[p])]];
        }
        free(props);

        [gReport appendFormat:@"  %@  {%@}\n",
            name, [propNames componentsJoinedByString:@", "]];
        logged++;
    }
    free(classes);
    [gReport appendFormat:@"\n  Total app classes logged: %d\n", logged];
}

// =============================================================================
//  MARK: - 8. Process / environment info
// =============================================================================

static void dumpProcessInfo(void) {
    rHeader(@"PROCESS INFO");

    NSProcessInfo *pi = [NSProcessInfo processInfo];
    rLine([NSString stringWithFormat:@"processName    : %@", pi.processName]);
    rLine([NSString stringWithFormat:@"processID      : %d", pi.processIdentifier]);
    rLine([NSString stringWithFormat:@"bundleID       : %@",
           [[NSBundle mainBundle] bundleIdentifier]]);
    rLine([NSString stringWithFormat:@"appVersion     : %@",
           [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]]);
    rLine([NSString stringWithFormat:@"build          : %@",
           [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]]);
    rLine([NSString stringWithFormat:@"systemVersion  : %@ %@",
           [UIDevice currentDevice].systemName,
           [UIDevice currentDevice].systemVersion]);
    rLine([NSString stringWithFormat:@"deviceModel    : %@",
           [UIDevice currentDevice].model]);
    rLine([NSString stringWithFormat:@"identifierFVD  : %@",
           [UIDevice currentDevice].identifierForVendor.UUIDString]);

    // Environment
    NSDictionary *env = pi.environment;
    [gReport appendFormat:@"\n  Environment (%lu vars):\n", (unsigned long)env.count];
    for (NSString *key in env) {
        NSString *val = env[key];
        [gReport appendFormat:@"    %-30@ = %@\n", key, val];
        checkForUDID([NSString stringWithFormat:@"ENV[%@]", key], val);
    }
}

// =============================================================================
//  MARK: - 9. Loaded dylibs / frameworks
// =============================================================================

static void dumpDylibs(void) {
    rHeader(@"LOADED DYLIBS");
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name) rLine([NSString stringWithUTF8String:name]);
    }
}

// =============================================================================
//  MARK: - 10. Memory scan for target UDID
//  Scans readable VM regions of this process for the UDID string
// =============================================================================

static void memoryScan(void) {
    rHeader([NSString stringWithFormat:@"MEMORY SCAN FOR: %@", TARGET_UDID]);

    const char *needle  = TARGET_C;
    size_t      needleLen = strlen(needle);

    mach_port_t task  = mach_task_self();
    vm_address_t addr = 0;
    vm_size_t    size = 0;
    natural_t    depth = 1;

    int found = 0;

    while (1) {
        struct vm_region_submap_info_64 info;
        mach_msg_type_number_t infoCount = VM_REGION_SUBMAP_INFO_COUNT_64;

        kern_return_t kr = vm_region_recurse_64(
            task, &addr, &size, &depth,
            (vm_region_recurse_info_t)&info, &infoCount);

        if (kr != KERN_SUCCESS) break;

        // Only scan readable, non-executable regions to avoid crashes
        BOOL readable   = (info.protection & VM_PROT_READ)    != 0;
        BOOL executable = (info.protection & VM_PROT_EXECUTE) != 0;
        BOOL writable   = (info.protection & VM_PROT_WRITE)   != 0;

        if (readable && !executable && size > 0 && size < 128 * 1024 * 1024) {
            // Try to read region
            vm_offset_t   data = 0;
            mach_msg_type_number_t dataCnt = 0;
            kern_return_t readKR = vm_read(task, addr, size, &data, &dataCnt);

            if (readKR == KERN_SUCCESS && data && dataCnt >= needleLen) {
                uint8_t *buf = (uint8_t *)data;
                for (mach_msg_type_number_t i = 0;
                     i + needleLen <= dataCnt; i++) {
                    if (memcmp(buf + i, needle, needleLen) == 0) {
                        found++;
                        rFound(
                            [NSString stringWithFormat:
                                @"Memory 0x%llx (rw=%d size=%lluKB)",
                                (uint64_t)(addr + i),
                                writable ? 1 : 0,
                                (uint64_t)(size / 1024)],
                            [NSString stringWithFormat:
                                @"at region addr=0x%llx offset=%u",
                                (uint64_t)addr, i]
                        );
                        i += needleLen - 1; // skip past this match
                    }
                }
                vm_deallocate(task, data, dataCnt);
            }
        }

        addr += size;
    }

    if (found == 0)
        rLine([NSString stringWithFormat:
            @"Not found in any readable memory region"]);
    else
        rLine([NSString stringWithFormat:@"Total occurrences found: %d", found]);
}

// =============================================================================
//  MARK: - Master dump function
// =============================================================================

static void RunFullDump(void) {
    gReport = [NSMutableString string];

    [gReport appendFormat:
        @"╔══════════════════════════════════════════════════╗\n"
          "║          AppDumper — Full Harvest Report         ║\n"
          "╠══════════════════════════════════════════════════╣\n"
          "║  Date   : %-38@ ║\n"
          "║  Bundle : %-38@ ║\n"
          "║  PID    : %-38d ║\n"
          "║  Target : %-38@ ║\n"
          "╚══════════════════════════════════════════════════╝\n",
        [NSDate date],
        [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown",
        (int)getpid(),
        TARGET_UDID];

    dumpProcessInfo();
    dumpKeychain();
    dumpUserDefaults();
    dumpPasteboard();
    dumpCookies();
    dumpURLCache();
    dumpFileSystem();
    dumpClasses();
    dumpDylibs();
    memoryScan();

    [gReport appendString:
        @"\n╔══════════════════════════════════════════════════╗\n"
          "║                   END OF DUMP                   ║\n"
          "╚══════════════════════════════════════════════════╝\n"];

    // Write output
    NSArray *paths = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [paths firstObject];
    NSString *path   = [docDir stringByAppendingPathComponent:@"full_dump.txt"];

    NSError *err = nil;
    BOOL ok = [gReport writeToFile:path atomically:YES
                          encoding:NSUTF8StringEncoding error:&err];
    NSLog(@"[AppDumper] Dump %@ -> %@  err=%@",
          ok ? @"OK" : @"FAILED", path, err);

    gReport = nil;
}

// =============================================================================
//  OVERLAY VIEW
// =============================================================================

@interface ADOverlayView : UIView
@property (nonatomic, strong) UIButton *dumpButton;
@property (nonatomic, strong) UILabel  *statusLabel;
@property (nonatomic, strong) UIView   *pillView;
@property (nonatomic, strong) UILabel  *pillLabel;
@property (nonatomic, assign) BOOL      minimised;
@end

static UIWindow      *gWindow  = nil;
static ADOverlayView *gOverlay = nil;

@implementation ADOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    CGFloat W = frame.size.width;

    self.backgroundColor    = [UIColor colorWithWhite:0.07 alpha:0.95];
    self.layer.cornerRadius = 18;
    self.layer.borderWidth  = 1;
    self.layer.borderColor  =
        [UIColor colorWithRed:0.85 green:0.30 blue:0.10 alpha:0.7].CGColor;
    self.clipsToBounds = YES;

    UILabel *icon = [[UILabel alloc] initWithFrame:CGRectMake(14,12,24,20)];
    icon.text = @"🕵️"; icon.font = [UIFont systemFontOfSize:14];
    [self addSubview:icon];

    UILabel *ttl = [[UILabel alloc] initWithFrame:CGRectMake(40,12,W-80,18)];
    ttl.text      = @"AppDumper";
    ttl.font      = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    ttl.textColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.10 alpha:1.0];
    [self addSubview:ttl];

    UIButton *minBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    minBtn.frame = CGRectMake(W-36, 8, 28, 28);
    [minBtn setTitle:@"—" forState:UIControlStateNormal];
    minBtn.tintColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    minBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [minBtn addTarget:self action:@selector(toggleMinimise)
     forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:minBtn];

    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(0,38,W,0.5)];
    div.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.09];
    [self addSubview:div];

    UILabel *sec = [[UILabel alloc] initWithFrame:CGRectMake(14,46,W-28,13)];
    sec.text      = @"FULL APP HARVEST + MEMORY SCAN";
    sec.font      = [UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    sec.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    [self addSubview:sec];

    self.statusLabel               = [[UILabel alloc] initWithFrame:CGRectMake(0,62,W,14)];
    self.statusLabel.text          = @"Ready — auto-dumped on launch";
    self.statusLabel.font          = [UIFont systemFontOfSize:9];
    self.statusLabel.textColor     = [UIColor colorWithWhite:0.40 alpha:1.0];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.statusLabel];

    // Target UDID display
    UILabel *udidLbl = [[UILabel alloc] initWithFrame:CGRectMake(8,78,W-16,20)];
    udidLbl.font          = [UIFont monospacedSystemFontOfSize:8
                                                        weight:UIFontWeightRegular];
    udidLbl.textColor     = [UIColor colorWithRed:1.0 green:0.55 blue:0.10 alpha:0.8];
    udidLbl.textAlignment = NSTextAlignmentCenter;
    udidLbl.numberOfLines = 1;
    udidLbl.adjustsFontSizeToFitWidth = YES;
    udidLbl.text          = [NSString stringWithFormat:@"🔍 %@", TARGET_UDID];
    [self addSubview:udidLbl];

    self.dumpButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.dumpButton.frame = CGRectMake(14, 102, W-28, 36);
    [self.dumpButton setTitle:@"Dump Everything Now" forState:UIControlStateNormal];
    self.dumpButton.titleLabel.font    = [UIFont systemFontOfSize:12
                                                           weight:UIFontWeightSemibold];
    self.dumpButton.tintColor          = [UIColor colorWithRed:0.07 green:0.09 blue:0.12 alpha:1.0];
    [self.dumpButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.dumpButton.backgroundColor    = [UIColor colorWithRed:1.0 green:0.55 blue:0.10 alpha:1.0];
    self.dumpButton.layer.cornerRadius = 10;
    self.dumpButton.clipsToBounds      = YES;
    [self.dumpButton addTarget:self action:@selector(didTapDump)
              forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.dumpButton];

    // Pill
    self.pillView = [[UIView alloc] initWithFrame:CGRectMake(0,0,W,36)];
    self.pillView.backgroundColor    = [UIColor colorWithWhite:0.07 alpha:0.94];
    self.pillView.layer.cornerRadius = 18;
    self.pillView.layer.borderWidth  = 1;
    self.pillView.layer.borderColor  =
        [UIColor colorWithRed:1.0 green:0.55 blue:0.10 alpha:0.5].CGColor;
    self.pillView.clipsToBounds = YES;
    self.pillView.hidden        = YES;

    self.pillLabel = [[UILabel alloc] initWithFrame:CGRectMake(10,0,W-20,36)];
    self.pillLabel.font      = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.pillLabel.textColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.10 alpha:1.0];
    self.pillLabel.text      = @"🕵️ AppDumper";
    [self.pillView addSubview:self.pillLabel];

    UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(toggleMinimise)];
    self.pillView.userInteractionEnabled = YES;
    [self.pillView addGestureRecognizer:t];
    [self addSubview:self.pillView];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];
    return self;
}

- (void)didTapDump {
    self.dumpButton.enabled = NO;
    [self.dumpButton setTitle:@"Dumping everything..." forState:UIControlStateNormal];
    self.dumpButton.backgroundColor =
        [UIColor colorWithWhite:0.25 alpha:1.0];
    self.statusLabel.text      = @"Scanning memory + storage...";
    self.statusLabel.textColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.10 alpha:1.0];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RunFullDump();
        dispatch_async(dispatch_get_main_queue(), ^{
            UIColor *orange = [UIColor colorWithRed:1.0 green:0.55 blue:0.10 alpha:1.0];
            UIColor *green  = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
            [self.dumpButton setTitle:@"Saved to full_dump.txt!"
                             forState:UIControlStateNormal];
            self.dumpButton.backgroundColor = green;
            self.statusLabel.text      = @"Documents/full_dump.txt";
            self.statusLabel.textColor = green;
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,(int64_t)(4.0*NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    [self.dumpButton setTitle:@"Dump Everything Now"
                                     forState:UIControlStateNormal];
                    self.dumpButton.backgroundColor = orange;
                    self.dumpButton.enabled = YES;
                    self.statusLabel.text = @"Ready";
                    self.statusLabel.textColor = [UIColor colorWithWhite:0.40 alpha:1.0];
            });
        });
    });
}

- (void)toggleMinimise {
    self.minimised = !self.minimised;
    CGFloat fullH = 150;
    if (self.minimised) {
        [UIView animateWithDuration:0.20 animations:^{
            CGRect f = gWindow.frame; f.size.height = 36; gWindow.frame = f;
            self.frame = CGRectMake(0,0,f.size.width,36);
        } completion:^(BOOL _) {
            for (UIView *v in self.subviews) v.hidden = (v != self.pillView);
            self.pillView.hidden = NO;
            self.layer.cornerRadius = 18;
        }];
    } else {
        for (UIView *v in self.subviews) v.hidden = NO;
        self.pillView.hidden = YES;
        [UIView animateWithDuration:0.20 animations:^{
            CGRect f = gWindow.frame; f.size.height = fullH; gWindow.frame = f;
            self.frame = CGRectMake(0,0,f.size.width,fullH);
        }];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint d = [pan translationInView:self.superview];
    CGRect  f = gWindow.frame;
    f.origin.x += d.x; f.origin.y += d.y;
    CGRect sc = [UIScreen mainScreen].bounds;
    f.origin.x = MAX(0, MIN(f.origin.x, sc.size.width  - f.size.width));
    f.origin.y = MAX(20, MIN(f.origin.y, sc.size.height - f.size.height - 20));
    gWindow.frame = f;
    [pan setTranslation:CGPointZero inView:self.superview];
}

@end

// =============================================================================
//  WINDOW
// =============================================================================

@interface ADWindow : UIWindow
@end
@implementation ADWindow
- (BOOL)pointInside:(CGPoint)pt withEvent:(UIEvent *)ev {
    for (UIView *s in self.subviews)
        if (!s.hidden && [s pointInside:[self convertPoint:pt toView:s] withEvent:ev])
            return YES;
    return NO;
}
@end

// =============================================================================
//  SPAWN
// =============================================================================

static void spawnOverlay(void) {
    if (gWindow) return;
    CGFloat W = 250, H = 150;
    CGRect sc = [UIScreen mainScreen].bounds;
    gWindow = [[ADWindow alloc] initWithFrame:CGRectMake(
        sc.size.width - W - 10, sc.size.height * 0.20, W, H)];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                gWindow.windowScene = (UIWindowScene *)scene; break;
            }
        }
    }
    gWindow.windowLevel     = UIWindowLevelAlert + 100;
    gWindow.backgroundColor = [UIColor clearColor];
    gOverlay = [[ADOverlayView alloc] initWithFrame:CGRectMake(0,0,W,H)];
    [gWindow addSubview:gOverlay];
    gWindow.hidden = NO;
    [gWindow makeKeyAndVisible];
    NSLog(@"[AppDumper] Overlay ready");
}

// =============================================================================
//  HOOKS
// =============================================================================

%hook UIApplication
- (BOOL)application:(UIApplication *)app
    didFinishLaunchingWithOptions:(NSDictionary *)opts {
    BOOL r = %orig;

    // Auto-dump on every launch (background thread, 2s delay to let app init)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2.0*NSEC_PER_SEC)),
        dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
            NSLog(@"[AppDumper] Auto-dumping on launch...");
            RunFullDump();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ spawnOverlay(); });

    return r;
}
%end

// =============================================================================
//  CONSTRUCTOR
// =============================================================================

%ctor {
    %init;
    NSLog(@"[AppDumper] Loaded in %@",
          [[NSBundle mainBundle] bundleIdentifier]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ spawnOverlay(); });
}
