// tweak.xm - VPN Spoofer (crash-fixed)

#import <substrate.h>
#import <NetworkExtension/NetworkExtension.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <dlfcn.h>

// ─────────────────────────────────────────
// 1. NEVPNConnection – always report disconnected
// ─────────────────────────────────────────
%hook NEVPNConnection
- (NEVPNStatus)status {
    return NEVPNStatusDisconnected;
}
%end

// ─────────────────────────────────────────
// 2. NETunnelProviderSession – block tunnel status too
// ─────────────────────────────────────────
%hook NETunnelProviderSession
- (NEVPNStatus)status {
    return NEVPNStatusDisconnected;
}
%end

// ─────────────────────────────────────────
// 3. getifaddrs – strip utun/tun/ppp/ipsec interfaces
// ─────────────────────────────────────────
static int (*orig_getifaddrs)(struct ifaddrs **) = NULL;

static int hooked_getifaddrs(struct ifaddrs **ifap) {
    if (!ifap) return -1;

    int ret = orig_getifaddrs(ifap);
    if (ret != 0 || *ifap == NULL) return ret;

    struct ifaddrs *prev = NULL;
    struct ifaddrs *ifa  = *ifap;

    while (ifa != NULL) {
        struct ifaddrs *next = ifa->ifa_next;

        if (ifa->ifa_name != NULL) {
            const char *name = ifa->ifa_name;
            BOOL shouldHide = (
                strncmp(name, "utun",  4) == 0 ||
                strncmp(name, "tun",   3) == 0 ||
                strncmp(name, "ppp",   3) == 0 ||
                strncmp(name, "ipsec", 5) == 0
            );

            if (shouldHide) {
                if (prev == NULL) {
                    *ifap = next;
                } else {
                    prev->ifa_next = next;
                }
                ifa = next;
                continue;
            }
        }

        prev = ifa;
        ifa  = next;
    }

    return ret;
}

// ─────────────────────────────────────────
// 4. SCNetworkReachabilityGetFlags – spoof as plain WiFi
// ─────────────────────────────────────────
static Boolean (*orig_SCFlags)(SCNetworkReachabilityRef, SCNetworkReachabilityFlags *) = NULL;

static Boolean hooked_SCFlags(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags) {
    Boolean result = orig_SCFlags(target, flags);
    if (result && flags) {
        *flags &= ~kSCNetworkReachabilityFlagsIsWWAN;
        *flags &= ~kSCNetworkReachabilityFlagsTransientConnection;
        *flags |=  kSCNetworkReachabilityFlagsReachable;
    }
    return result;
}

// ─────────────────────────────────────────
// 5. Constructor — safe symbol resolution
// ─────────────────────────────────────────
%ctor {
    @autoreleasepool {
        // Hook getifaddrs via dlsym (safer than MSFindSymbol)
        void *libsys = dlopen("/usr/lib/libSystem.B.dylib", RTLD_NOW | RTLD_NOLOAD);
        if (libsys) {
            void *sym = dlsym(libsys, "getifaddrs");
            if (sym) {
                MSHookFunction(sym,
                    (void *)hooked_getifaddrs,
                    (void **)&orig_getifaddrs);
            }
        }

        // Hook SCNetworkReachabilityGetFlags
        void *sc = dlopen(
            "/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration",
            RTLD_NOW | RTLD_NOLOAD
        );
        if (sc) {
            void *sym = dlsym(sc, "SCNetworkReachabilityGetFlags");
            if (sym) {
                MSHookFunction(sym,
                    (void *)hooked_SCFlags,
                    (void **)&orig_SCFlags);
            }
        }
    }
}
