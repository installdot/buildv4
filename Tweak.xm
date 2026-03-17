#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@interface APIClient : NSObject
- (void)setUDID:(NSString *)uid;
- (NSString *)getUDID;
- (void)paid:(void (^)(void))execute;
- (void)setToken:(NSString *)token;
@end

// ── Saved UDID storage ──
static NSString *_savedUDID = nil;

// ── Simple alert helper ──
static void showUDID() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = UIApplication.sharedApplication.keyWindow;
        if (!window) return;

        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Saved UDID"
            message:_savedUDID ?: @"No UDID captured yet."
            preferredStyle:UIAlertControllerStyleAlert];

        // Copy button
        if (_savedUDID) {
            [alert addAction:[UIAlertAction actionWithTitle:@"Copy"
                style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *a) {
                    [UIPasteboard generalPasteboard].string = _savedUDID;
            }]];
        }

        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
            style:UIAlertActionStyleCancel handler:nil]];

        [window.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

// ── Floating button ──
static void injectButton() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{

        UIWindow *window = UIApplication.sharedApplication.keyWindow;
        if (!window) return;

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(20, 120, 130, 40);
        btn.backgroundColor = [UIColor colorWithRed:0.1 green:0.6 blue:0.9 alpha:1.0];
        btn.layer.cornerRadius = 10;
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [btn setTitle:@"Show UDID" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

        // Use a block via objc associated objects trick via target/action
        [btn addTarget:[UIApplication sharedApplication]
                action:@selector(udidButtonTapped)
      forControlEvents:UIControlEventTouchUpInside];

        btn.tag = 9876;
        [window addSubview:btn];
    });
}

// ── Extend UIApplication to handle button tap ──
%hook UIApplication

- (void)udidButtonTapped {
    showUDID();
}

%end

// ── Hook APIClient ──
%hook APIClient

// Capture UDID when set
- (void)setUDID:(NSString *)uid {
    if (uid && uid.length > 0) {
        _savedUDID = [uid copy];
        NSLog(@"[UDIDExtract] setUDID captured: %@", _savedUDID);
    }
    %orig;
}

// Capture UDID from getter too
- (NSString *)getUDID {
    NSString *result = %orig;
    if (result && result.length > 0) {
        _savedUDID = [result copy];
        NSLog(@"[UDIDExtract] getUDID captured: %@", _savedUDID);
    }
    return result;
}

// Hook paid to call getUDID at the right moment so it gets captured
- (void)paid:(void (^)(void))execute {
    NSString *udid = [self getUDID];
    if (udid && udid.length > 0) {
        _savedUDID = [udid copy];
        NSLog(@"[UDIDExtract] paid: UDID captured: %@", _savedUDID);
    }
    if (execute) execute(); // bypass
}

%end

// ── Inject button on app start ──
%hook UIApplicationDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)options {
    BOOL result = %orig;
    injectButton();
    return result;
}

%end
