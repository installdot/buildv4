// Tweak.xm
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <substrate.h>

static CGPoint startPoint;
static CGPoint btnStart;

// Helper to get the first window
UIWindow *firstWindow() {
    NSArray *windows = [UIApplication sharedApplication].windows;
    return windows.firstObject;
}

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *win = firstWindow();
        if (!win) return;

        CGFloat btnSize = 70;
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];

        // Place button in the middle of the screen
        btn.frame = CGRectMake((win.bounds.size.width - btnSize)/2,
                               (win.bounds.size.height - btnSize)/2,
                               btnSize,
                               btnSize);

        btn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        btn.layer.cornerRadius = btnSize / 2;
        btn.tintColor = UIColor.whiteColor;
        [btn setTitle:@"Menu" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];

        [btn addTarget:nil action:@selector(showMenuPressed) forControlEvents:UIControlEventTouchUpInside];

        [win addSubview:btn];
    });
}

// Function to show Documents files
%new
- (void)showMenuPressed {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];

    NSError *error = nil;
    NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:documentsDirectory error:&error];

    NSString *message;
    if (error) {
        message = [NSString stringWithFormat:@"Error: %@", error.localizedDescription];
    } else {
        message = [files componentsJoinedByString:@"\n"];
        if (message.length == 0) message = @"No files found in Documents folder.";
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Documents Files"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:ok];

    UIWindow *win = firstWindow();
    [win.rootViewController presentViewController:alert animated:YES completion:nil];
}
