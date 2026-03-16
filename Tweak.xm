#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <substrate.h>

// ============================================
// Forward declare APIClient so compiler knows it
// ============================================
@interface APIClient : NSObject
+ (instancetype)sharedAPIClient;
- (void)setUDID:(NSString *)uid;
- (NSString *)getUDID;
- (void)start:(void (^)(void))onStart init:(void (^)(void))initBlock;
@end

// ============================================
// EARLY CONSTRUCTOR
// Priority must be between 101-255
// ============================================
static void earlyInit(void) __attribute__((constructor));
static void earlyInit(void) {
    NSLog(@"[Tweak] Early init fired");
}

%hook APIClient

+ (instancetype)sharedAPIClient {
    APIClient *client = %orig;
    if (client) {
        [client setUDID:@"udid-by-admin"];
        NSLog(@"[Tweak] sharedAPIClient — UDID forced");
    }
    return client;
}

- (void)setUDID:(NSString *)uid {
    NSLog(@"[Tweak] setUDID blocked: %@ → udid-by-admin", uid);
    %orig(@"udid-by-admin");
}

- (NSString *)getUDID {
    NSLog(@"[Tweak] getUDID hooked");
    return @"udid-by-admin";
}

- (void)start:(void (^)(void))onStart init:(void (^)(void))initBlock {
    NSLog(@"[Tweak] start:init: — forcing UDID before start");
    [self setUDID:@"udid-by-admin"];
    %orig(onStart, initBlock);
}

%end

%ctor {
    NSLog(@"[Tweak] Tweak loaded successfully");

    Class apiClass = NSClassFromString(@"APIClient");
    if (apiClass) {
        NSLog(@"[Tweak] APIClient found at %%ctor");
    } else {
        NSLog(@"[Tweak] APIClient not yet loaded");
    }
}
