#import <Foundation/Foundation.h>

// Redeclare the interface so the compiler knows about APIClient
@interface APIClient : NSObject
- (void)paid:(void (^)(void))execute;
@end

// Hook the APIClient class
%hook APIClient

// Override paid: method
- (void)paid:(void (^)(void))execute {
    // Skip all server validation, directly fire the block
    if (execute) {
        execute(); // <-- jumps straight to your loadview(), menuSetup(), etc.
    }
}

%end
