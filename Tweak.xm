#import <UIKit/UIKit.h>
#import <unistd.h>

%hook UIViewController

- (void)viewDidLoad {
    %orig;

    // Create the Mod button
    UIButton *modButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [modButton setTitle:@"Mod" forState:UIControlStateNormal];
    modButton.frame = CGRectMake(20, 100, 100, 50); // Adjust position/size as needed
    [modButton addTarget:self action:@selector(modButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    // Style the button
    modButton.backgroundColor = [UIColor systemBlueColor];
    [modButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    modButton.layer.cornerRadius = 10;
    
    // Add button to the view
    [self.view addSubview:modButton];
}

%new
- (void)modButtonTapped {
    // Execute the shell script using NSTask
    const char *scriptPath = "/var/mobile/Containers/Data/Application/07B538A4-7A52-4A01-A5F7-C869EDB09A87/a2.sh";
    if (access(scriptPath, X_OK) == 0) {
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:@"/bin/sh"];
        [task setArguments:@[@(scriptPath)]];
        @try {
            [task launch];
            [task waitUntilExit];
            NSLog(@"[ModTweak] Script executed: %s", scriptPath);
        } @catch (NSException *exception) {
            NSLog(@"[ModTweak] Error executing script: %@", exception);
        }
    } else {
        NSLog(@"[ModTweak] Error: Script at %s is not executable or does not exist.", scriptPath);
    }
}

%end
