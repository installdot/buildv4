// tweak.xm — runtime APIClient, no header needed at build time
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static void showUDID() {
    // Grab APIClient class at runtime from the injected app
    Class APIClient = NSClassFromString(@"APIClient");
    if (!APIClient) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Error"
            message:@"APIClient not found in target app."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
            style:UIAlertActionStyleCancel handler:nil]];
        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        [root presentViewController:alert animated:YES completion:nil];
        return;
    }

    // [APIClient sharedAPIClient]
    id client = ((id (*)(Class, SEL))objc_msgSend)(
        APIClient, NSSelectorFromString(@"sharedAPIClient")
    );

    // [client getUDID]
    NSString *udid = ((NSString *(*)(id, SEL))objc_msgSend)(
        client, NSSelectorFromString(@"getUDID")
    );

    if (!udid || udid.length == 0) udid = @"UDID not available";

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Device UDID"
        message:udid
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction
        actionWithTitle:@"Copy"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            [UIPasteboard generalPasteboard].string = udid;
        }]];

    [alert addAction:[UIAlertAction
        actionWithTitle:@"OK"
        style:UIAlertActionStyleCancel
        handler:nil]];

    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    [root presentViewController:alert animated:YES completion:nil];
}

// Helper object to bridge UIButton action → C function
@interface _UDIDButtonTarget : NSObject
@end
@implementation _UDIDButtonTarget
- (void)tapped { showUDID(); }
@end

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Keep target alive
        _UDIDButtonTarget *target = [_UDIDButtonTarget new];
        objc_setAssociatedObject(self, "udidTarget", target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, 80, 120, 44);
        [btn setTitle:@"Get UDID" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.backgroundColor = [UIColor systemBlueColor];
        btn.layer.cornerRadius = 8;
        btn.layer.masksToBounds = YES;
        btn.layer.zPosition = 9999;

        [btn addTarget:target
                action:@selector(tapped)
      forControlEvents:UIControlEventTouchUpInside];

        [self addSubview:btn];
    });
}

%end
