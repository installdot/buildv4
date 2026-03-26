#import <Foundation/Foundation.h>

// Import class nếu có header
@interface Unitoreios : NSObject
- (BOOL)isNetworkAvailable;
@end

%hook Unitoreios

- (BOOL)isNetworkAvailable {
    NSLog(@"[Unitoreios] Forced Offline Mode");
    return NO;
}

%end
