#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// MARK: - Preset UDID storage key
static NSString *const kPresetUDIDKey = @"com.tweak.presetUDID";

static NSString *getPresetUDID() {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kPresetUDIDKey];
}

static void savePresetUDID(NSString *udid) {
    [[NSUserDefaults standardUserDefaults] setObject:udid forKey:kPresetUDIDKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// MARK: - Hook APIClient getUDID — always return preset if set
%hook NSObject

- (NSString *)getUDID {
    NSString *preset = getPresetUDID();
    if (preset && preset.length > 0) {
        return preset;
    }
    return %orig;
}

%end

// MARK: - UI
static UIViewController *topVC() {
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}

static void showMenu() {
    NSString *current = getPresetUDID() ?: @"(not set — using real UDID)";

    UIAlertController *menu = [UIAlertController
        alertControllerWithTitle:@"UDID Overwrite"
        message:[NSString stringWithFormat:@"Preset UDID:\n%@", current]
        preferredStyle:UIAlertControllerStyleAlert];

    // Set preset
    [menu addAction:[UIAlertAction
        actionWithTitle:@"Set Preset UDID"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            UIAlertController *input = [UIAlertController
                alertControllerWithTitle:@"Set Preset UDID"
                message:@"Every getUDID call will return this value"
                preferredStyle:UIAlertControllerStyleAlert];

            [input addTextFieldWithConfigurationHandler:^(UITextField *tf) {
                tf.placeholder = @"Enter UDID";
                tf.text = getPresetUDID();
                tf.clearButtonMode = UITextFieldViewModeWhileEditing;
                tf.autocorrectionType = UITextAutocorrectionTypeNo;
                tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
            }];

            [input addAction:[UIAlertAction
                actionWithTitle:@"Save"
                style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *a) {
                    NSString *val = input.textFields.firstObject.text;
                    if (val.length == 0) return;
                    savePresetUDID(val);
                    UIAlertController *done = [UIAlertController
                        alertControllerWithTitle:@"Saved"
                        message:[NSString stringWithFormat:@"getUDID will now return:\n%@", val]
                        preferredStyle:UIAlertControllerStyleAlert];
                    [done addAction:[UIAlertAction actionWithTitle:@"OK"
                        style:UIAlertActionStyleCancel handler:nil]];
                    [topVC() presentViewController:done animated:YES completion:nil];
                }]];

            [input addAction:[UIAlertAction actionWithTitle:@"Cancel"
                style:UIAlertActionStyleCancel handler:nil]];
            [topVC() presentViewController:input animated:YES completion:nil];
        }]];

    // Clear preset (restore real UDID)
    [menu addAction:[UIAlertAction
        actionWithTitle:@"Clear Preset (use real UDID)"
        style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *a) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPresetUDIDKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Close"
        style:UIAlertActionStyleCancel handler:nil]];

    [topVC() presentViewController:menu animated:YES completion:nil];
}

// MARK: - Overlay window
@interface _UDIDWindow : UIWindow
@end
@implementation _UDIDWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}
@end

@interface _BtnTarget : NSObject
@end
@implementation _BtnTarget
- (void)tapped { showMenu(); }
@end

static void injectOverlay() {
    CGRect screen = [UIScreen mainScreen].bounds;

    _UDIDWindow *win = [[_UDIDWindow alloc] initWithFrame:screen];
    win.windowLevel = UIWindowLevelStatusBar + 1;
    win.backgroundColor = [UIColor clearColor];
    win.userInteractionEnabled = YES;

    UIViewController *vc = [UIViewController new];
    vc.view.frame = screen;
    vc.view.backgroundColor = [UIColor clearColor];
    win.rootViewController = vc;
    [win makeKeyAndVisible];

    objc_setAssociatedObject([UIApplication sharedApplication],
        "udidWin", win, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    _BtnTarget *target = [_BtnTarget new];
    objc_setAssociatedObject(win, "btnTarget", target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(20, 100, 110, 40);
    [btn setTitle:@"UDID" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    btn.backgroundColor = [UIColor systemBlueColor];
    btn.layer.cornerRadius = 8;
    btn.layer.masksToBounds = YES;
    btn.alpha = 0.9f;

    [btn addTarget:target action:@selector(tapped)
        forControlEvents:UIControlEventTouchUpInside];

    [vc.view addSubview:btn];
}

%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
            (int64_t)(0.5 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ injectOverlay(); });
    });
}
%end
