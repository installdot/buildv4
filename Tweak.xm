#import <UIKit/UIKit.h>

@interface UIWindow (Overlay)
@end

@implementation UIWindow (Overlay)

- (void)layoutSubviews {
    [super layoutSubviews];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIButton *prefsButton = [UIButton buttonWithType:UIButtonTypeSystem];
        prefsButton.frame = CGRectMake(50, 100, 120, 40);
        [prefsButton setTitle:@"Edit Prefs" forState:UIControlStateNormal];
        prefsButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        [prefsButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        prefsButton.layer.cornerRadius = 8.0;
        prefsButton.clipsToBounds = YES;
        [prefsButton addTarget:self action:@selector(showNSUserDefaultsEditor) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:prefsButton];
    });
}

- (void)showNSUserDefaultsEditor {
    NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSArray *keys = [defaults allKeys];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"NSUserDefaults"
                                                                   message:@"Select a key to edit"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    for (NSString *key in keys) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:key
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull act) {
            [self editValueForKey:key currentValue:[defaults objectForKey:key]];
        }];
        [alert addAction:action];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *rootVC = self.rootViewController;
    if (rootVC) {
        [rootVC presentViewController:alert animated:YES completion:nil];
    }
}

- (void)editValueForKey:(NSString *)key currentValue:(id)value {
    NSString *valueString = value ? [value description] : @"";

    UIAlertController *editAlert = [UIAlertController alertControllerWithTitle:key
                                                                       message:@"Edit value"
                                                                preferredStyle:UIAlertControllerStyleAlert];

    [editAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = valueString;
    }];

    [editAlert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull act) {
        NSString *newVal = editAlert.textFields.firstObject.text;

        // Save back into NSUserDefaults
        [[NSUserDefaults standardUserDefaults] setObject:newVal forKey:key];
        [[NSUserDefaults standardUserDefaults] synchronize];

        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Saved!"
                                                                      message:[NSString stringWithFormat:@"%@ = %@", key, newVal]
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *rootVC = self.rootViewController;
        if (rootVC) {
            [rootVC presentViewController:done animated:YES completion:nil];
        }
    }]];

    [editAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *rootVC = self.rootViewController;
    if (rootVC) {
        [rootVC presentViewController:editAlert animated:YES completion:nil];
    }
}

@end
