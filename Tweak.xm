#import <UIKit/UIKit.h>

@interface UIWindow (Overlay)
@end

@implementation UIWindow (Overlay)

- (void)layoutSubviews {
    [super layoutSubviews];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIButton *plistButton = [UIButton buttonWithType:UIButtonTypeSystem];
        plistButton.frame = CGRectMake(50, 150, 160, 40);
        [plistButton setTitle:@"Edit Prefs" forState:UIControlStateNormal];
        plistButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
        [plistButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        plistButton.layer.cornerRadius = 8.0;
        plistButton.clipsToBounds = YES;

        [plistButton addTarget:self action:@selector(showPlistKeys) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:plistButton];
    });
}

- (NSString *)appPrefsPlistPath {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    return [NSString stringWithFormat:@"/var/mobile/Containers/Data/Application/%@/Library/Preferences/%@.plist",
            [[NSBundle mainBundle] bundleIdentifier], bundleID];
}

- (void)showPlistKeys {
    NSString *plistPath = [self appPrefsPlistPath];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    if (!dict) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                       message:@"Plist not found"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self.rootViewController presentViewController:alert animated:YES completion:nil];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Select Key"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];

    for (NSString *key in dict.allKeys) {
        [alert addAction:[UIAlertAction actionWithTitle:key
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [self editValueForKey:key inPlist:plistPath];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.rootViewController presentViewController:alert animated:YES completion:nil];
}

- (void)editValueForKey:(NSString *)key inPlist:(NSString *)plistPath {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    if (!dict) return;

    NSString *currentValue = [NSString stringWithFormat:@"%@", dict[key]];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:key
                                                                   message:@"Edit value"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.text = currentValue;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Save"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        NSString *newValue = alert.textFields.firstObject.text;
        dict[key] = newValue; // stores as string
        [dict writeToFile:plistPath atomically:YES];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.rootViewController presentViewController:alert animated:YES completion:nil];
}

@end
