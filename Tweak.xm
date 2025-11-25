// Tweak.xm
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

%hook UIApplication

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig;

    // Add button after a slight delay to ensure window is ready
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) return;
        
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(20, 50, 200, 50);
        [button setTitle:@"Show Document Files" forState:UIControlStateNormal];
        button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.layer.cornerRadius = 10;

        [button addTarget:self action:@selector(showDocumentFiles) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:button];
    });

    return result;
}

- (void)showDocumentFiles {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];

    NSError *error = nil;
    NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:documentsDirectory error:&error];
    
    NSString *message;
    if (error) {
        message = [NSString stringWithFormat:@"Error: %@", error.localizedDescription];
    } else {
        message = [files componentsJoinedByString:@"\n"];
        if (message.length == 0) message = @"No files found in Documents folder.";
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Documents Files"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:ok];

    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

%end
