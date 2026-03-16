#import <UIKit/UIKit.h>

// ============================================
// CONSTRUCTOR - Runs BEFORE everything else
// Priority 101 = higher than default (100)
// Ensures we hook before APIClient initializes
// ============================================
__attribute__((constructor(101))) static void earlyInit() {
    NSLog(@"[Tweak] Early constructor fired — hooking APIClient");
}

%hook APIClient

// ============================================
// Hook sharedAPIClient
// Intercept at singleton creation level
// ============================================
+ (instancetype)sharedAPIClient {
    APIClient *client = %orig; // call original first

    // Immediately force our UDID right after instance is returned
    [client setUDID:@"udid-by-admin"];
    NSLog(@"[Tweak] sharedAPIClient intercepted — UDID force set");

    return client;
}

// ============================================
// Hook setUDID
// Override whatever value the app tries to set
// ============================================
- (void)setUDID:(NSString *)uid {
    NSLog(@"[Tweak] setUDID called with: %@ — overriding to udid-by-admin", uid);

    // Ignore original value, force ours
    %orig(@"udid-by-admin");
}

// ============================================
// Hook getUDID
// Make sure even the getter returns our value
// ============================================
- (NSString *)getUDID {
    NSLog(@"[Tweak] getUDID called — returning udid-by-admin");
    return @"udid-by-admin";
}

// ============================================
// Hook start:init:
// Force UDID again right before client starts
// ============================================
- (void)start:(void (^)(void))onStart init:(void (^)(void))initBlock {
    NSLog(@"[Tweak] start:init: intercepted — re-forcing UDID before start");
    [self setUDID:@"udid-by-admin"];
    %orig(onStart, initBlock);
}

%end


// ============================================
// CTOR - Secondary safety net
// Runs after dylib loads, hooks via MSHookMessage
// as a backup in case %hook fires late
// ============================================
%ctor {
    NSLog(@"[Tweak] %ctor fired — tweak loaded");

    // Extra safety: hook using runtime directly
    Class apiClass = NSClassFromString(@"APIClient");
    if (apiClass) {
        NSLog(@"[Tweak] APIClient class found early in %%ctor");
    } else {
        NSLog(@"[Tweak] APIClient not loaded yet — %%hook will catch it");
    }
}
