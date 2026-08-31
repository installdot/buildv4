#import <UIKit/UIKit.h>
#import "IL2CPPUtils.hpp"

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

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, frame.size.width - 20, 30)];
        title.text = @"LibTool IL2CPP Inspector";
        title.textColor = [UIColor whiteColor];
        title.font = [UIFont boldSystemFontOfSize:16];
        [self addSubview:title];

        _classField = [[UITextField alloc] initWithFrame:CGRectMake(10, 50, frame.size.width - 20, 35)];
        _classField.placeholder = @"Class Name (e.g. PlayerController)";
        _classField.backgroundColor = [UIColor whiteColor];
        _classField.layer.cornerRadius = 5;
        [self addSubview:_classField];

        _methodField = [[UITextField alloc] initWithFrame:CGRectMake(10, 95, frame.size.width - 20, 35)];
        _methodField.placeholder = @"Method Name (e.g. AddCoins)";
        _methodField.backgroundColor = [UIColor whiteColor];
        _methodField.layer.cornerRadius = 5;
        [self addSubview:_methodField];

        UIButton *execBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        execBtn.frame = CGRectMake(10, 140, frame.size.width - 20, 40);
        [execBtn setTitle:@"Find Instances & Call Method" forState:UIControlStateNormal];
        execBtn.backgroundColor = [UIColor systemBlueColor];
        [execBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        execBtn.layer.cornerRadius = 5;
        [execBtn addTarget:self action:@selector(executeLogic) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:execBtn];

        _console = [[UITextView alloc] initWithFrame:CGRectMake(10, 190, frame.size.width - 20, frame.size.height - 200)];
        _console.backgroundColor = [UIColor blackColor];
        _console.textColor = [UIColor greenColor];
        _console.editable = NO;
        _console.font = [UIFont fontWithName:@"Courier" size:12];
        [self addSubview:_console];
    }
    return self;
}

- (void)log:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.console.text = [NSString stringWithFormat:@"%@\n%@", self.console.text, msg];
        NSRange range = NSMakeRange(self.console.text.length, 0);
        [self.console scrollRangeToVisible:range];
    });
}

- (void)executeLogic {
    [self endEditing:YES]; // Hide keyboard
    NSString *className = _classField.text;
    NSString *methodName = _methodField.text;

    if (className.length == 0 || methodName.length == 0) {
        [self log:@"[!] Error: Enter class and method name."];
        return;
    }

    [self log:[NSString stringWithFormat:@"[*] Searching for Class: %@", className]];
    
    // Attach thread just in case UIKit thread isn't registered
    IL2CPP::thread_attach(IL2CPP::domain_get());

    // 1. Find Class
    Il2CppClass *klass = IL2CPP::FindClassGlobal(className.UTF8String);
    if (!klass) {
        [self log:@"[-] Class not found in any loaded assembly."];
        return;
    }

    // 2. Find Method (assuming 0 parameters for dynamic invocation safety)
    MethodInfo *method = IL2CPP::class_get_method_from_name(klass, methodName.UTF8String, 0);
    if (!method) {
        [self log:@"[-] Method not found. Ensure it takes 0 arguments (or update script to handle params)."];
        return;
    }

    // 3. Find Instances dynamically via Unity Heap
    [self log:@"[*] Class found. Scanning memory for active instances..."];
    std::vector<void*> instances = IL2CPP::FindInstances(klass);
    
    if (instances.empty()) {
        [self log:@"[-] No active instances found in the current scene."];
        return;
    }

    [self log:[NSString stringWithFormat:@"[+] Found %zu instances. Invoking method...", instances.size()]];

    // 4. Invoke Method on all found instances
    for (size_t i = 0; i < instances.size(); i++) {
        void* instance = instances[i];
        [self log:[NSString stringWithFormat:@"  -> Invoking on instance at %p", instance]];
        
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
// Floating Button Logic
// ==========================================
ModMenuUI *menuView;

@interface FloatingIcon : UIButton
@end
@implementation FloatingIcon
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInView:self.superview];
    self.center = location;
}
@end

void SetupUI() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window) return;

        // The Main Menu Window
        menuView = [[ModMenuUI alloc] initWithFrame:CGRectMake(20, 50, 300, 350)];
        menuView.hidden = YES; // Hidden by default
        [window addSubview:menuView];

        // The Draggable Floating Icon
        FloatingIcon *floater = [FloatingIcon buttonWithType:UIButtonTypeCustom];
        floater.frame = CGRectMake(20, 100, 50, 50);
        floater.backgroundColor = [UIColor redColor];
        floater.layer.cornerRadius = 25;
        floater.layer.borderWidth = 2;
        floater.layer.borderColor = [UIColor whiteColor].CGColor;
        [floater setTitle:@"🛠" forState:UIControlStateNormal];
        
        [floater addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
            menuView.hidden = !menuView.hidden; // Toggle menu visibility
            if(!menuView.hidden) [window bringSubviewToFront:menuView];
        }] forControlEvents:UIControlEventTouchUpInside];
        
        [window addSubview:floater];
    });
}


// ==========================================
// Loader Initialization
// ==========================================
void WaitForUnity() {
    // Poll until IL2CPP domain is fully loaded by the game engine
    while (!IL2CPP::Initialize() || IL2CPP::domain_get() == nullptr) {
        [NSThread sleepForTimeInterval:1.0];
    }
    NSLog(@"[LibTool-iOS] Unity IL2CPP Initialized!");
    SetupUI();
}

%ctor {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        WaitForUnity();
    });
}
