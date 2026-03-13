#import "SKFramework.h"

static SKPanel *gPanel;
static SKSettingsMenu *gMenu;

#pragma mark - Auth UI

static void showKeyPrompt(UIView *root) {

    UIViewController *vc = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (vc.presentedViewController)
        vc = vc.presentedViewController;

    UIAlertController *alert =
    [UIAlertController alertControllerWithTitle:@"Enter License Key"
                                        message:@"Input your authentication key."
                                 preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"XXXX-XXXX-XXXX";
        tf.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Login"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a){

        NSString *key = alert.textFields.firstObject.text;
        if (!key.length) return;

        SKProgressOverlay *ov =
        [SKProgressOverlay showInView:root title:@"Authenticating…"];

        SK_performKeyAuth(key, ^(BOOL ok,
                                 NSTimeInterval keyExp,
                                 NSTimeInterval devExp,
                                 NSString *err) {

            dispatch_async(dispatch_get_main_queue(), ^{

                if (ok) {

                    SK_saveSavedKey(key);

                    [ov finish:YES
                       message:@"Authentication successful."
                          link:nil];

                    [gPanel setLabelText:@"Authenticated" forKey:@"status"];

                } else {

                    [ov finish:NO
                       message:err ?: @"Auth failed."
                          link:nil];
                }

            });

        });

    }]];

    [vc presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Panel Builder

static void buildPanel(UIView *root) {

    if (gPanel) return;

    // Settings menu
    gMenu = [SKSettingsMenu new];
    gMenu.menuTitle = @"Auth Test";
    gMenu.footerText = @"SKFramework Demo";

    [gMenu addToggle:@"autoLogin"
               title:@"Auto Login"
         description:@"Try login automatically if key saved"
              symbol:@"person.crop.circle.badge.checkmark"
         defaultValue:YES
             onChange:nil];

    [gMenu addButtonRow:@"clearKey"
                  title:@"Clear Saved Key"
                 symbol:@"trash"
                  color:SKColorRed()
                 action:^{
        SK_clearSavedKey();
        [SKAlert showTitle:@"Done" message:@"Saved key removed."];
    }];

    // Panel
    gPanel = [SKPanel new];
    gPanel.panelTitle = @"Auth Tester";

    [gPanel addLabel:@"status" text:@"Not authenticated"];

    // Login button
    [gPanel addButton:@"Login"
               symbol:@"person.crop.circle.badge.key"
                color:SKColorBlue()
               action:^{
        showKeyPrompt(root);
    }];

    // Check saved key
    [gPanel addButton:@"Check Saved Key"
               symbol:@"checkmark.shield"
                color:SKColorGreen()
               action:^{

        NSString *key = SK_loadSavedKey();

        if (!key) {
            [SKAlert showTitle:@"No Key"
                       message:@"No saved key found."];
            return;
        }

        SKProgressOverlay *ov =
        [SKProgressOverlay showInView:root title:@"Revalidating…"];

        SK_performKeyAuth(key, ^(BOOL ok,
                                 NSTimeInterval k,
                                 NSTimeInterval d,
                                 NSString *err) {

            dispatch_async(dispatch_get_main_queue(), ^{

                if (ok) {

                    [ov finish:YES
                       message:@"Key still valid."
                          link:nil];

                    [gPanel setLabelText:@"Authenticated" forKey:@"status"];

                } else {

                    [ov finish:NO
                       message:err ?: @"Invalid key."
                          link:nil];

                    SK_clearSavedKey();
                }

            });

        });

    }];

    [gPanel addDivider];

    [gPanel addSettingsButton:@"Settings" menu:gMenu];

    [gPanel addSmallButtonsRow:@[
        [SKButton buttonWithTitle:@"Hide"
                           symbol:@"eye.slash"
                            color:SKColorRed()
                           action:^{ [gPanel hide]; }]
    ]];

    [gPanel showInView:root];
}

#pragma mark - Injection

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    static dispatch_once_t once;
    dispatch_once(&once, ^{

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.7 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{

            UIWindow *win = nil;

            for (UIWindow *w in UIApplication.sharedApplication.windows)
                if (!w.hidden && w.alpha > 0) {
                    win = w;
                    break;
                }

            if (!win) return;

            buildPanel(win.rootViewController.view ?: win);

        });

    });
}

%end
