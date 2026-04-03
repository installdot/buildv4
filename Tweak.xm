#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

typedef id           (*MsgSendId)    (Class, SEL);
typedef NSString    *(*MsgSendStr)   (id, SEL);
typedef void         (*MsgSendSetStr)(id, SEL, NSString *);

static id getClient() {
    Class APIClient = NSClassFromString(@"APIClient");
    if (!APIClient) return nil;
    return ((MsgSendId)objc_msgSend)(APIClient, NSSelectorFromString(@"sharedAPIClient"));
}

static UIViewController *topVC() {
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}

// MARK: - Transparent passthrough root VC
// Lets touches outside the button fall through to the app
@interface _PassthroughVC : UIViewController
@end
@implementation _PassthroughVC
- (void)loadView {
    self.view = [[UIView alloc] init];
    self.view.backgroundColor = [UIColor clearColor];
    self.view.userInteractionEnabled = NO; // passthrough by default
}
@end

// MARK: - Overlay window (lives above everything)
@interface _UDIDOverlayWindow : UIWindow
@end
@implementation _UDIDOverlayWindow
// Only intercept touches that land directly on subviews (the button)
// Everything else falls through to the app window
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}
@end

// MARK: - UDID actions
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
        actionWithTitle:@"Copy Current"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            [UIPasteboard generalPasteboard].string = udid;
        }]];

    [menu addAction:[UIAlertAction
        actionWithTitle:@"Set Custom UDID"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            UIAlertController *input = [UIAlertController
                alertControllerWithTitle:@"Set Custom UDID"
                message:@"Enter UDID to write into APIClient"
                preferredStyle:UIAlertControllerStyleAlert];

            [input addTextFieldWithConfigurationHandler:^(UITextField *tf) {
                tf.placeholder = @"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
                tf.text = udid;
                tf.clearButtonMode = UITextFieldViewModeWhileEditing;
                tf.autocorrectionType = UITextAutocorrectionTypeNo;
                tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
            }];

            [input addAction:[UIAlertAction
                actionWithTitle:@"Write"
                style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *a) {
                    NSString *custom = input.textFields.firstObject.text;
                    if (!client || custom.length == 0) return;
                    ((MsgSendSetStr)objc_msgSend)(client, NSSelectorFromString(@"setUDID:"), custom);

                    UIAlertController *ok = [UIAlertController
                        alertControllerWithTitle:@"Done"
                        message:[NSString stringWithFormat:@"UDID set:\n%@", custom]
                        preferredStyle:UIAlertControllerStyleAlert];
                    [ok addAction:[UIAlertAction actionWithTitle:@"OK"
                        style:UIAlertActionStyleCancel handler:nil]];
                    [topVC() presentViewController:ok animated:YES completion:nil];
                }]];

            [input addAction:[UIAlertAction actionWithTitle:@"Cancel"
                style:UIAlertActionStyleCancel handler:nil]];
            [topVC() presentViewController:input animated:YES completion:nil];
        }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Close"
        style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:menu animated:YES completion:nil];
}

// MARK: - Button target
@interface _UDIDButtonTarget : NSObject
@end
@implementation _UDIDButtonTarget
- (void)tapped { showUDIDMenu(); }
@end

// MARK: - Inject overlay window once app is ready
%hook UIApplication

- (void)applicationDidBecomeActive:(id)delegate {
    %orig;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _PassthroughVC *vc = [_PassthroughVC new];

        _UDIDOverlayWindow *overlayWindow = [[_UDIDOverlayWindow alloc]
            initWithFrame:[UIScreen mainScreen].bounds];
        overlayWindow.rootViewController = vc;
        overlayWindow.windowLevel = UIWindowLevelAlert + 100; // above everything
        overlayWindow.backgroundColor = [UIColor clearColor];
        overlayWindow.hidden = NO;
        overlayWindow.userInteractionEnabled = YES;

        // Keep window alive
        objc_setAssociatedObject([UIApplication sharedApplication],
            "udidOverlay", overlayWindow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        _UDIDButtonTarget *target = [_UDIDButtonTarget new];
        objc_setAssociatedObject(overlayWindow,
            "udidTarget", target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, 80, 120, 44);
        [btn setTitle:@"UDID" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.backgroundColor = [UIColor systemBlueColor];
        btn.layer.cornerRadius = 8;
        btn.layer.masksToBounds = YES;
        btn.userInteractionEnabled = YES;

        [btn addTarget:target
                action:@selector(tapped)
      forControlEvents:UIControlEventTouchUpInside];

        [vc.view addSubview:btn];
        vc.view.userInteractionEnabled = YES; // allow button to receive touches
    });
}

%end
