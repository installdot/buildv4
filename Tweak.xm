#import <UIKit/UIKit.h>
#import <objc/runtime.h>

%hook UIApplication

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) return;

        UIButton *modButton = [UIButton buttonWithType:UIButtonTypeSystem];
        modButton.frame = CGRectMake(20, 100, 60, 40);
        modButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        [modButton setTitle:@"Mod" forState:UIControlStateNormal];
        [modButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        modButton.layer.cornerRadius = 10;
        modButton.layer.masksToBounds = YES;
        [modButton addTarget:self action:@selector(runModScript) forControlEvents:UIControlEventTouchUpInside];

        [keyWindow addSubview:modButton];
        [keyWindow bringSubviewToFront:modButton];
    });
}

%new
- (void)runModScript {
    system("sh /var/mobile/Containers/Data/Application/07B538A4-7A52-4A01-A5F7-C869EDB09A87/a2.sh");
}

%end
