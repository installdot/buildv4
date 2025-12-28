//
//  Tweak.xm
//  API Authentication Bypass
//
//  Hooks APIClient methods to bypass authentication
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Interface declaration for APIClient
@interface APIClient : NSObject
- (void)paid:(void (^)(void))execute;
- (void)setToken:(NSString*)token;
- (void)onCheckPackage:(void (^)(NSDictionary *header))success onFailure:(void (^)(NSDictionary *error))failure;
- (void)onCheckDevice:(void (^)(NSDictionary *data))success onFailure:(void (^)(NSDictionary *error))failure;
- (void)onLogin:(NSString *)inputKey onSuccess:(void (^)(NSDictionary *data))success onFailure:(void (^)(NSDictionary *error))failure;
- (NSString*)getKey;
- (NSString*)getExpiryDate;
- (NSString*)getUDID;
@end

// Log all method calls to APIClient
%hook APIClient

// Hook the paid method - this is the main authentication check
- (void)paid:(void (^)(void))execute {
    NSLog(@"[APIBypass] paid: method called - bypassing authentication");
    
    // Directly execute the success callback without checking authentication
    if (execute) {
        execute();
    }
}

// Hook onCheckPackage to always return success
- (void)onCheckPackage:(void (^)(NSDictionary *header))success onFailure:(void (^)(NSDictionary *error))failure {
    NSLog(@"[APIBypass] onCheckPackage: called - returning fake success");
    
    // Create fake success response
    NSDictionary *fakeHeader = @{
        @"status": @"success",
        @"message": @"Package verified (bypassed)",
        @"package_name": @"com.bypassed.package",
        @"valid": @YES
    };
    
    if (success) {
        success(fakeHeader);
    }
}

// Hook onCheckDevice to always return success
- (void)onCheckDevice:(void (^)(NSDictionary *data))success onFailure:(void (^)(NSDictionary *error))failure {
    NSLog(@"[APIBypass] onCheckDevice: called - returning fake success");
    
    // Create fake device check response
    NSDictionary *fakeData = @{
        @"status": @"success",
        @"message": @"Device verified (bypassed)",
        @"device_verified": @YES,
        @"device_id": [[UIDevice currentDevice] identifierForVendor].UUIDString
    };
    
    if (success) {
        success(fakeData);
    }
}

// Hook onLogin to always return success
- (void)onLogin:(NSString *)inputKey onSuccess:(void (^)(NSDictionary *data))success onFailure:(void (^)(NSDictionary *error))failure {
    NSLog(@"[APIBypass] onLogin: called with key: %@ - returning fake success", inputKey);
    
    // Create fake login response
    NSDictionary *fakeData = @{
        @"status": @"success",
        @"message": @"Login successful (bypassed)",
        @"key": inputKey ?: @"BYPASSED-KEY-12345",
        @"expiry_date": @"2099-12-31",
        @"expired_at": @"4102444800", // Timestamp far in future
        @"package_name": @"Premium Package (Bypassed)"
    };
    
    if (success) {
        success(fakeData);
    }
}

// Hook getKey to return a fake key
- (NSString*)getKey {
    NSLog(@"[APIBypass] getKey: called - returning fake key");
    return @"BYPASSED-KEY-12345-PREMIUM";
}

// Hook getExpiryDate to return a far future date
- (NSString*)getExpiryDate {
    NSLog(@"[APIBypass] getExpiryDate: called - returning fake date");
    return @"2099-12-31 23:59:59";
}

// Log setToken calls
- (void)setToken:(NSString*)token {
    NSLog(@"[APIBypass] setToken: called with token: %@", token);
    %orig; // Call original method but it won't matter
}

// Log all method calls
+ (void)load {
    NSLog(@"[APIBypass] Tweak loaded successfully!");
    NSLog(@"[APIBypass] All API authentication checks will be bypassed");
}

%end

// Optional: Hook any view loading functions if needed
// You can add hooks for specific view controllers here

// Constructor
%ctor {
    NSLog(@"[APIBypass] Constructor - Tweak initialization complete");
    NSLog(@"[APIBypass] Target process: %@", [[NSProcessInfo processInfo] processName]);
}
