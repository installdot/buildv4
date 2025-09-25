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
        [prefsButton setTitle:@"Find Key" forState:UIControlStateNormal];
        prefsButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        [prefsButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        prefsButton.layer.cornerRadius = 8.0;
        prefsButton.clipsToBounds = YES;
        [prefsButton addTarget:self action:@selector(findKeyPrompt) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:prefsButton];
    });
}

- (void)findKeyPrompt {
    UIAlertController *searchAlert = [UIAlertController alertControllerWithTitle:@"Search Key"
                                                                         message:@"Enter part of a key name"
                                                                  preferredStyle:UIAlertControllerStyleAlert];

    [searchAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"example_key";
    }];

    [searchAlert addAction:[UIAlertAction actionWithTitle:@"Search"
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction * _Nonnull act) {
        NSString *query = searchAlert.textFields.firstObject.text;
        if (query.length > 0) {
            [self showMatchingKeys:query];
        }
    }]];

    [searchAlert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                    style:UIAlertActionStyleCancel
                                                  handler:nil]];

    UIViewController *rootVC = self.rootViewController;
    if (rootVC) {
        [rootVC presentViewController:searchAlert animated:YES completion:nil];
    }
}

- (void)showMatchingKeys:(NSString *)query {
    NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSMutableArray *matches = [NSMutableArray array];

    for (NSString *key in defaults.allKeys) {
        if ([[key lowercaseString] containsString:[query lowercaseString]]) {
            [matches addObject:key];
        }
    }

    if (matches.count == 0) {
        UIAlertController *none = [UIAlertController alertControllerWithTitle:@"No Match"
                                                                      message:@"No keys found"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [none addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *rootVC = self.rootViewController;
        if (rootVC) {
            [rootVC presentViewController:none animated:YES completion:nil];
        }
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Matching Keys"
                                                                   message:@"Choose a key"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    for (NSString *key in matches) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:key
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull act) {
            [self editValueForKey:key currentValue:defaults[key]];
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

    [editAlert addAction:[UIAlertAction actionWithTitle:@"Save"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull act) {
        NSString *newVal = editAlert.textFields.firstObject.text;

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
