#import <UIKit/UIKit.h>

@interface UIWindow (Overlay)
@end

@implementation UIWindow (Overlay)

- (void)layoutSubviews {
    [super layoutSubviews];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // === Floating Button ===
        UIButton *dumpButton = [UIButton buttonWithType:UIButtonTypeSystem];
        dumpButton.frame = CGRectMake(50, 150, 180, 40);
        [dumpButton setTitle:@"Dump Defaults" forState:UIControlStateNormal];
        dumpButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
        [dumpButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        dumpButton.layer.cornerRadius = 8.0;
        dumpButton.clipsToBounds = YES;

        [dumpButton addTarget:self action:@selector(dumpNSUserDefaults) forControlEvents:UIControlEventTouchUpInside];

        [self addSubview:dumpButton];
    });
}

- (void)dumpNSUserDefaults {
    // Get all defaults
    NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];

    if (defaults.count == 0) {
        UIPasteboard.generalPasteboard.string = @"No NSUserDefaults found!";
    } else {
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:defaults options:NSJSONWritingPrettyPrinted error:&error];

        if (!error && jsonData) {
            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            UIPasteboard.generalPasteboard.string = jsonString;

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Dumped!"
                                                                           message:@"NSUserDefaults copied to clipboard"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];

            // Present on top window
            UIViewController *rootVC = self.rootViewController;
            if (rootVC) {
                [rootVC presentViewController:alert animated:YES completion:nil];
            }
        }
    }
}

@end
