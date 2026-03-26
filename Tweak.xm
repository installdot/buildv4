#import <substrate.h>

%hook Unitoreios

- (BOOL)isNetworkAvailable {
    return NO;
}

%end
