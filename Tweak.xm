#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

typedef id        (*MsgSendId)    (Class, SEL);
typedef NSString *(*MsgSendStr)   (id, SEL);
typedef void      (*MsgSendSetStr)(id, SEL, NSString *);

static id getClient() {
    Class cls = NSClassFromString(@"APIClient");
    if (!cls) return nil;
    return ((MsgSendId)objc_msgSend)(cls, NSSelectorFromString(@"sharedAPIClient"));
}

static UIViewController *topVC() {
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}

static void showUDIDMenu() {
    id client = getClient();
    NSString *udid = client
        ? ((MsgSendStr)objc_msgSend)(client, NSSelectorFromString(@"getUDID"))
        : nil;
    if (!udid || udid.length == 0) udid = @"(not set)";

    UIAlertController *menu = [UIAlertController
        alertControllerWithTitle:@"UDID Manager"
        message:[NSString stringWithFormat:@"Current:\n%@", udid]
        preferredStyle:UIAlertControllerStyleAlert];

    [menu addAction:[UIAlertAction
        actionWithTitle:@"Copy"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            [UIPasteboard generalPasteboard].string = udid;
        }]];

    [menu addAction:[UIAlertAction
        actionWithTitle:@"Set Custom UDID"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            UIAlertController *inputAlert = [UIAlertController
                alertControllerWithTitle:@"Set Custom UDID"
                message:@"Enter UDID to write into APIClient"
                preferredStyle:UIAlertControllerStyleAlert];

            [inputAlert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
                tf.placeholder = @"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
                tf.text = udid;
                tf.clearButtonMode = UITextFieldViewModeWhileEditing;
                tf.autocorrectionType = UITextAutocorrectionTypeNo;
                tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
            }];

            [inputAlert addAction:[UIAlertAction
                actionWithTitle:@"Write"
                style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *a) {
                    NSString *custom = inputAlert.textFields.firstObject.text;
                    if (!client || custom.length == 0) return;
                    ((MsgSendSetStr)objc_msgSend)(client,
                        NSSelectorFromString(@"setUDID:"), custom);
                    UIAlertController *done = [UIAlertController
                        alertControllerWithTitle:@"Done"
                        message:[NSString stringWithFormat:@"UDID set:\n%@", custom]
                        preferredStyle:UIAlertControllerStyleAlert];
                    [done addAction:[UIAlertAction actionWithTitle:@"OK"
                        style:UIAlertActionStyleCancel handler:nil]];
                    [topVC() presentViewController:done animated:YES completion:nil];
                }]];

            [inputAlert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                style:UIAlertActionStyleCancel handler:nil]];
            [topVC() presentViewController:inputAlert animated:YES completion:nil];
        }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Close"
        style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:menu animated:YES completion:nil];
}

// Passthrough window — only the button receives touches, rest falls to app
@interface _UDIDWindow : UIWindow
@end
@implementation _UDIDWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}
@end

@interface _UDIDButtonTarget : NSObject
@end
@implementation _UDIDButtonTarget
- (void)tapped { showUDIDMenu(); }
@end

static void injectOverlay() {
    CGRect screen = [UIScreen mainScreen].bounds;

    _UDIDWindow *win = [[_UDIDWindow alloc] initWithFrame:screen];
    win.windowLevel      = UIWindowLevelStatusBar + 1;
    win.backgroundColor  = [UIColor clearColor];
    win.userInteractionEnabled = YES;

    // Simple root VC with clear full-screen view
    UIViewController *vc = [UIViewController new];
    vc.view.frame           = screen;
    vc.view.backgroundColor = [UIColor clearColor];
    win.rootViewController  = vc;
    [win makeKeyAndVisible];

    // Store alive
    objc_setAssociatedObject([UIApplication sharedApplication],
        "udidWin", win, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    _UDIDButtonTarget *target = [_UDIDButtonTarget new];
    objc_setAssociatedObject(win, "udidTarget", target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(20, 100, 110, 40);
    [btn setTitle:@"UDID" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    btn.backgroundColor = [UIColor systemBlueColor];
    btn.layer.cornerRadius  = 8;
    btn.layer.masksToBounds = YES;
    btn.alpha = 0.9f;

    [btn addTarget:target
            action:@selector(tapped)
  forControlEvents:UIControlEventTouchUpInside];

    [vc.view addSubview:btn];
}

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    // Only inject once, after the main app window is ready
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
            (int64_t)(0.5 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                injectOverlay();
        });
    });
}

%end
