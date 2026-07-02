#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Hooking a main application lifecycle method to start our waiting script.
// If this is a Unity game, you can hook UnityAppController. 
// For standard iOS apps, AppDelegate is typically used.
%hook UnityAppController

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    
    // 1. Wait until the callback exists (Checking every 1 second)
    [NSTimer scheduledTimerWithTimeInterval:1.0 
                                    repeats:YES 
                                      block:^(NSTimer * _Nonnull timer) {
        
        // 2. Find the class
        Class AppCertificateManagerClass = objc_getClass("AppCertificateManager"); // or %c(AppCertificateManager)
        
        if (AppCertificateManagerClass) {
            
            // 3. Get the instance (using performSelector for dynamic method calling)
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id instance = [AppCertificateManagerClass performSelector:@selector(yju)];
            #pragma clang diagnostic pop
            
            if (instance) {
                
                // 4. Read _callBack (Using Key-Value Coding to access the private variable)
                // Assuming the callback is a standard Objective-C block taking a boolean
                typedef void (^CallbackBlock)(BOOL);
                CallbackBlock callback = [instance valueForKey:@"_callBack"];
                
                if (callback) {
                    // 5. Invoke the callback with true (YES)
                    callback(YES);
                    
                    // 6. Optional: Remove the callback so it doesn't trigger again
                    [instance setValue:nil forKey:@"_callBack"];
                    
                    // Stop the timer since our job here is done
                    [timer invalidate]; 
                    
                    NSLog(@"[Tweak] Successfully invoked and cleared AppCertificateManager._callBack!");
                }
            }
        }
    }];
}

%end
