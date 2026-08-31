#import <UIKit/UIKit.h>
#import "IL2CPPUtils.hpp"

// ==========================================
// File Logger System
// ==========================================
static NSString *logFilePath = nil;

static void SetupFileLogger() {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    logFilePath = [documentsDirectory stringByAppendingPathComponent:@"LibTool_CrashLog.txt"];
    
    NSString *startupMsg = [NSString stringWithFormat:@"\n\n--- LibTool Initialized at %@ ---\n", [NSDate date]];
    [startupMsg writeToFile:logFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void WriteToFileLog(NSString *message) {
    if (!logFilePath) return;
    NSString *formattedMessage = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], message];
    
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForUpdatingAtPath:logFilePath];
    if (fileHandle) {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[formattedMessage dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    } else {
        [formattedMessage writeToFile:logFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

// ==========================================
// User Interface Elements
// ==========================================
@interface ModMenuUI : UIView
@property (nonatomic, strong) UITextField *classField;
@property (nonatomic, strong) UITextField *methodField;
@property (nonatomic, strong) UITextView *console;
@end

@implementation ModMenuUI
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        self.layer.cornerRadius = 10;
        self.layer.masksToBounds = YES;

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, frame.size.width - 20, 25)];
        title.text = @"LibTool IL2CPP Inspector";
        title.textColor = [UIColor whiteColor];
        title.font = [UIFont boldSystemFontOfSize:16];
        [self addSubview:title];

        _classField = [[UITextField alloc] initWithFrame:CGRectMake(10, 45, frame.size.width - 20, 35)];
        _classField.placeholder = @" Class Name (e.g. PlayerController)";
        _classField.backgroundColor = [UIColor whiteColor];
        _classField.textColor = [UIColor blackColor];
        _classField.layer.cornerRadius = 5;
        _classField.autocorrectionType = UITextAutocorrectionTypeNo;
        _classField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        [self addSubview:_classField];

        _methodField = [[UITextField alloc] initWithFrame:CGRectMake(10, 88, frame.size.width - 20, 35)];
        _methodField.placeholder = @" Method Name (e.g. AddCoins)";
        _methodField.backgroundColor = [UIColor whiteColor];
        _methodField.textColor = [UIColor blackColor];
        _methodField.layer.cornerRadius = 5;
        _methodField.autocorrectionType = UITextAutocorrectionTypeNo;
        _methodField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        [self addSubview:_methodField];

        UIButton *execBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        execBtn.frame = CGRectMake(10, 130, frame.size.width - 20, 38);
        [execBtn setTitle:@"Find Instances & Call Method" forState:UIControlStateNormal];
        execBtn.backgroundColor = [UIColor systemBlueColor];
        [execBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        execBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        execBtn.layer.cornerRadius = 5;
        [execBtn addTarget:self action:@selector(executeLogic) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:execBtn];

        _console = [[UITextView alloc] initWithFrame:CGRectMake(10, 175, frame.size.width - 20, frame.size.height - 185)];
        _console.backgroundColor = [UIColor blackColor];
        _console.textColor = [UIColor greenColor];
        _console.editable = NO;
        _console.font = [UIFont fontWithName:@"Courier" size:12];
        _console.layer.cornerRadius = 5;
        [self addSubview:_console];
    }
    return self;
}

// Logs to both UI and File
- (void)log:(NSString *)msg {
    WriteToFileLog(msg); // Write to physical file
    dispatch_async(dispatch_get_main_queue(), ^{
        self.console.text = [NSString stringWithFormat:@"%@\n%@", self.console.text, msg];
        NSRange range = NSMakeRange(self.console.text.length, 0);
        [self.console scrollRangeToVisible:range];
    });
}

- (void)executeLogic {
    [self endEditing:YES];
    NSString *className = _classField.text;
    NSString *methodName = _methodField.text;

    if (className.length == 0 || methodName.length == 0) {
        [self log:@"[!] Error: Enter class and method name."];
        return;
    }

    [self log:[NSString stringWithFormat:@"[*] Searching for Class: %@", className]];
    IL2CPP::thread_attach(IL2CPP::domain_get());

    Il2CppClass *klass = IL2CPP::FindClassGlobal(className.UTF8String);
    if (!klass) {
        [self log:@"[-] Class not found in any loaded assembly."];
        return;
    }

    MethodInfo *method = IL2CPP::class_get_method_from_name(klass, methodName.UTF8String, 0);
    if (!method) {
        [self log:@"[-] Method not found (Ensure it takes 0 arguments)."];
        return;
    }

    [self log:@"[*] Scanning memory for active instances..."];
    std::vector<void*> instances = IL2CPP::FindInstances(klass);

    if (instances.empty()) {
        [self log:@"[-] No active instances found in the current scene."];
        return;
    }

    [self log:[NSString stringWithFormat:@"[+] Found %zu instances. Invoking...", instances.size()]];

    for (size_t i = 0; i < instances.size(); i++) {
        void* instance = instances[i];
        [self log:[NSString stringWithFormat:@"  -> Invoking on pointer %p", instance]];

        Il2CppObject* exception = nullptr;
        IL2CPP::runtime_invoke(method, instance, nullptr, &exception);

        if (exception) {
            [self log:@"  [!] Exception thrown during execution!"];
        } else {
            [self log:@"  [+] Success!"];
        }
    }
}
@end

// ==========================================
// Floating Draggable Button & Init
// ==========================================
ModMenuUI *menuView = nil;

@interface FloatingIcon : UIButton
@end
@implementation FloatingIcon
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInView:self.superview];
    self.center = location;
}
- (void)toggleMenu {
    if (menuView) {
        menuView.hidden = !menuView.hidden;
        if (!menuView.hidden) {
            [menuView.superview bringSubviewToFront:menuView];
        }
    }
}
@end

static UIWindow* GetActiveWindow() {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) return window;
            }
            if (windowScene.windows.count > 0) return windowScene.windows.firstObject;
        }
    }
    return [UIApplication sharedApplication].windows.firstObject;
}

static void SetupUI() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = GetActiveWindow();
        if (!window) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SetupUI();
            });
            return;
        }

        if (menuView) return; 

        menuView = [[ModMenuUI alloc] initWithFrame:CGRectMake(20, 60, 300, 350)];
        menuView.hidden = YES;
        [window addSubview:menuView];

        FloatingIcon *floater = [FloatingIcon buttonWithType:UIButtonTypeCustom];
        floater.frame = CGRectMake(20, 100, 50, 50);
        floater.backgroundColor = [UIColor colorWithRed:0.85 green:0.2 blue:0.2 alpha:1.0];
        floater.layer.cornerRadius = 25;
        floater.layer.borderWidth = 2;
        floater.layer.borderColor = [UIColor whiteColor].CGColor;
        [floater setTitle:@"🛠" forState:UIControlStateNormal];
        [floater addTarget:floater action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [window addSubview:floater];
    });
}

static void WaitForUnity() {
    while (!IL2CPP::Initialize() || IL2CPP::domain_get() == nullptr) {
        [NSThread sleepForTimeInterval:0.5];
    }
    WriteToFileLog(@"IL2CPP runtime attached successfully.");
    SetupUI();
}

%ctor {
    SetupFileLogger(); // Start file logging instantly
    WriteToFileLog(@"Tweak loaded into process.");
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [NSThread sleepForTimeInterval:1.0];
        WaitForUnity();
    });
}
