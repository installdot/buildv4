#import <Foundation/Foundation.h>

%hook APIClient

- (void)paid:(void (^)(void))execute {
    if (execute) {
        execute();
    }
}

%end
