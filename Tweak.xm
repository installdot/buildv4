#import <Foundation/Foundation.h>
#import <IOKit/pwr_mgt/IOPMLib.h>

static IOPMAssertionID assertionID = 0;

void preventSleep() {
    if (assertionID == 0) {
        IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep,
                                    kIOPMAssertionLevelOn,
                                    CFSTR("Preventing Sleep for Google Cloud Shell"),
                                    &assertionID);
        NSLog(@"[NoSleepCloudShell] Sleep prevention activated.");
    }
}

void allowSleep() {
    if (assertionID != 0) {
        IOPMAssertionRelease(assertionID);
        assertionID = 0;
        NSLog(@"[NoSleepCloudShell] Sleep prevention disabled.");
    }
}

%hook UIApplication

// Prevent sleep when the app starts
- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;
    preventSleep();
}

// Keep preventing sleep when app becomes active
- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    preventSleep();
}

// Allow sleep only when the app is fully terminated
- (void)applicationWillTerminate:(UIApplication *)application {
    %orig;
    allowSleep();
}

%end
