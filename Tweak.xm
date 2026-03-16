// tweak.xm
// VPN Spoofer - Makes apps think device is on normal WiFi

#import <substrate.h>
#import <NetworkExtension/NetworkExtension.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <arpa/inet.h>
#import <dlfcn.h>

// ─────────────────────────────────────────
// 1. Hook NEVPNConnection to spoof VPN status
// ─────────────────────────────────────────
%hook NEVPNConnection

- (NEVPNStatus)status {
    return NEVPNStatusDisconnected; // Always report as disconnected
}

%end

// ─────────────────────────────────────────
// 2. Hook NEVPNManager
// ─────────────────────────────────────────
%hook NEVPNManager

- (NEVPNConnection *)connection {
    NEVPNConnection *conn = %orig;
    return conn; // Returned conn will report Disconnected via hook above
}

%end

// ─────────────────────────────────────────
// 3. Hook getifaddrs to hide utun/tun/ppp interfaces
//    Apps inspect interfaces to detect VPN tunnels
// ─────────────────────────────────────────
static int (*orig_getifaddrs)(struct ifaddrs **);

static int hooked_getifaddrs(struct ifaddrs **ifap) {
    int ret = orig_getifaddrs(ifap);
    if (ret != 0 || ifap == NULL) return ret;

    struct ifaddrs *prev = NULL;
    struct ifaddrs *ifa = *ifap;

    while (ifa != NULL) {
        struct ifaddrs *next = ifa->ifa_next;
        const char *name = ifa->ifa_name;

        // Remove VPN-related interfaces
        BOOL isVPNIface = (
            strncmp(name, "utun", 4) == 0 ||
            strncmp(name, "tun",  3) == 0 ||
            strncmp(name, "ppp",  3) == 0 ||
            strncmp(name, "ipsec",5) == 0 ||
            strncmp(name, "eph",  3) == 0
        );

        if (isVPNIface) {
            // Unlink this node
            if (prev == NULL) {
                *ifap = next;
            } else {
                prev->ifa_next = next;
            }
        } else {
            prev = ifa;
        }

        ifa = next;
    }

    return ret;
}

// ─────────────────────────────────────────
// 4. Hook SCNetworkReachability flags
//    Apps check flags to detect WWAN vs WiFi vs VPN
// ─────────────────────────────────────────
static Boolean (*orig_SCNetworkReachabilityGetFlags)(SCNetworkReachabilityRef, SCNetworkReachabilityFlags *);

static Boolean hooked_SCNetworkReachabilityGetFlags(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags) {
    Boolean result = orig_SCNetworkReachabilityGetFlags(target, flags);
    if (result && flags) {
        // Clear VPN/WWAN-specific flags, keep reachable + WiFi flags
        *flags &= ~kSCNetworkReachabilityFlagsIsWWAN;        // Not cellular
        *flags &= ~kSCNetworkReachabilityFlagsTransientConnection; // Not transient (VPN marker)
        *flags |=  kSCNetworkReachabilityFlagsReachable;     // Reachable
    }
    return result;
}

// ─────────────────────────────────────────
// 5. Constructor – install all hooks
// ─────────────────────────────────────────
%ctor {
    // Hook getifaddrs from libSystem
    MSHookFunction(
        (void *)MSFindSymbol(NULL, "_getifaddrs"),
        (void *)hooked_getifaddrs,
        (void **)&orig_getifaddrs
    );

    // Hook SCNetworkReachabilityGetFlags from SystemConfiguration
    void *scHandle = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_NOW);
    if (scHandle) {
        void *sym = dlsym(scHandle, "SCNetworkReachabilityGetFlags");
        if (sym) {
            MSHookFunction(sym,
                (void *)hooked_SCNetworkReachabilityGetFlags,
                (void **)&orig_SCNetworkReachabilityGetFlags
            );
        }
    }
}
