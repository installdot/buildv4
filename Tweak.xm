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

// MARK: - Show current UDID + option to set custom
static void showUDIDMenu() {
    id client = getClient();
    if (!client) {
        UIAlertController *err = [UIAlertController
            alertControllerWithTitle:@"Error"
            message:@"APIClient not found in target app."
            preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [topVC() presentViewController:err animated:YES completion:nil];
        return;
    }

    NSString *udid = ((MsgSendStr)objc_msgSend)(client, NSSelectorFromString(@"getUDID"));
    if (!udid || udid.length == 0) udid = @"(not set)";

    UIAlertController *menu = [UIAlertController
        alertControllerWithTitle:@"UDID Manager"
        message:[NSString stringWithFormat:@"Current UDID:\n%@", udid]
        preferredStyle:UIAlertControllerStyleAlert];

    // Copy current
    [menu addAction:[UIAlertAction
        actionWithTitle:@"Copy Current"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            [UIPasteboard generalPasteboard].string = udid;
        }]];

    // Set custom UDID
    [menu addAction:[UIAlertAction
        actionWithTitle:@"Set Custom UDID"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            UIAlertController *input = [UIAlertController
                alertControllerWithTitle:@"Set Custom UDID"
                message:@"Enter the UDID to write into APIClient"
                preferredStyle:UIAlertControllerStyleAlert];

            [input addTextFieldWithConfigurationHandler:^(UITextField *tf) {
                tf.placeholder = @"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
                tf.text = udid; // pre-fill with current value
                tf.clearButtonMode = UITextFieldViewModeWhileEditing;
                tf.autocorrectionType = UITextAutocorrectionTypeNo;
                tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
            }];

            [input addAction:[UIAlertAction
                actionWithTitle:@"Write"
                style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *a) {
                    NSString *custom = input.textFields.firstObject.text;
                    if (custom.length == 0) return;

                    ((MsgSendSetStr)objc_msgSend)(client, NSSelectorFromString(@"setUDID:"), custom);

                    // Confirm
                    UIAlertController *ok = [UIAlertController
                        alertControllerWithTitle:@"Done"
                        message:[NSString stringWithFormat:@"UDID set to:\n%@", custom]
                        preferredStyle:UIAlertControllerStyleAlert];
                    [ok addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                    [topVC() presentViewController:ok animated:YES completion:nil];
                }]];

            [input addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [topVC() presentViewController:input animated:YES completion:nil];
        }]];

    // Dismiss
    [menu addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:menu animated:YES completion:nil];
}

// MARK: - Button target
@interface _UDIDButtonTarget : NSObject
@end
@implementation _UDIDButtonTarget
- (void)tapped { showUDIDMenu(); }
@end

// MARK: - Inject floating button
%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _UDIDButtonTarget *target = [_UDIDButtonTarget new];
        objc_setAssociatedObject(self, "udidTarget", target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, 80, 120, 44);
        [btn setTitle:@"UDID" forState:UIControlStateNormal];
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
