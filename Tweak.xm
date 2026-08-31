#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <signal.h>
#include <setjmp.h>
#include <vector>
#include <string>

// =============================================
// 1. CRASH-PROOF SIGNAL HANDLER (From your code)
// =============================================
static __thread sigjmp_buf  tls_jmpbuf;
static __thread volatile int tls_in_safe = 0;

static void safe_sig_handler(int sig) {
    if (tls_in_safe) {
        tls_in_safe = 0;
        sigset_t unblock;
        sigemptyset(&unblock);
        sigaddset(&unblock, SIGSEGV);
        sigaddset(&unblock, SIGBUS);
        pthread_sigmask(SIG_UNBLOCK, &unblock, nullptr);
        siglongjmp(tls_jmpbuf, sig);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

static void InstallSafeSignalHandlers() {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = safe_sig_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGSEGV, &sa, nullptr);
    sigaction(SIGBUS,  &sa, nullptr);
}

// =============================================
// 2. IL2CPP ENGINE & APIS
// =============================================
namespace IL2CPP {
    void       *(*il2cpp_domain_get)();
    void       *(*il2cpp_thread_attach)(void *domain);
    void      **(*il2cpp_domain_get_assemblies)(const void *domain, size_t *size);
    const void *(*il2cpp_assembly_get_image)(const void *assembly);
    uint32_t    (*il2cpp_image_get_class_count)(void *image);
    void       *(*il2cpp_image_get_class)(void *image, uint32_t index);
    const char *(*il2cpp_class_get_name)(void *klass);
    void       *(*il2cpp_class_get_method_from_name)(void *klass, const char *name, int args);
    const void *(*il2cpp_class_get_type)(void *klass);
    void       *(*il2cpp_type_get_object)(const void *type);
    void       *(*il2cpp_runtime_invoke)(void *method, void *obj, void **params, void **exc);
}

static bool s_attached = false;

static void Il2CppAttach() {
    if (s_attached) return;
    NSString *fwPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Frameworks/UnityFramework.framework/UnityFramework"];
    void *handle = dlopen([fwPath UTF8String], RTLD_LAZY | RTLD_GLOBAL);
    
    for (int i = 0; !handle && i < 15; i++) {
        [NSThread sleepForTimeInterval:1.0];
        handle = dlopen([fwPath UTF8String], RTLD_LAZY | RTLD_GLOBAL);
    }
    if (!handle) return;

    #define BIND(fn) IL2CPP::fn = reinterpret_cast<decltype(IL2CPP::fn)>(dlsym(handle, #fn))
    BIND(il2cpp_domain_get);
    BIND(il2cpp_thread_attach);
    BIND(il2cpp_domain_get_assemblies);
    BIND(il2cpp_assembly_get_image);
    BIND(il2cpp_image_get_class_count);
    BIND(il2cpp_image_get_class);
    BIND(il2cpp_class_get_name);
    BIND(il2cpp_class_get_method_from_name);
    BIND(il2cpp_class_get_type);
    BIND(il2cpp_type_get_object);
    BIND(il2cpp_runtime_invoke);
    #undef BIND

    s_attached = true;
}

// =============================================
// 3. SAFE SEARCH & INVOKE LOGIC
// =============================================
static void* FindClassGlobal(const char* targetName) {
    if (!s_attached) return nullptr;
    void *domain = IL2CPP::il2cpp_domain_get();
    if (!domain) return nullptr;
    
    size_t asmCount = 0;
    void **assemblies = IL2CPP::il2cpp_domain_get_assemblies(domain, &asmCount);
    if (!assemblies || asmCount == 0) return nullptr;

    for (size_t ai = 0; ai < asmCount; ai++) {
        void *img = (void *)IL2CPP::il2cpp_assembly_get_image(assemblies[ai]);
        if (!img) continue;
        
        uint32_t classCount = IL2CPP::il2cpp_image_get_class_count(img);
        for (uint32_t ci = 0; ci < classCount; ci++) {
            void *klass = IL2CPP::il2cpp_image_get_class(img, ci);
            if (!klass) continue;
            
            const char *name = IL2CPP::il2cpp_class_get_name(klass);
            if (name && strcmp(name, targetName) == 0) {
                return klass;
            }
        }
    }
    return nullptr;
}

// Uses your safe array parsing (0x18 / 0x20 offsets)
static std::vector<void*> GetActiveInstances(void* klass) {
    std::vector<void*> instances;
    if (!klass) return instances;

    void* unityObjClass = FindClassGlobal("Object");
    if (!unityObjClass) return instances;

    void* findMethod = IL2CPP::il2cpp_class_get_method_from_name(unityObjClass, "FindObjectsOfType", 1);
    if (!findMethod) return instances;

    const void* typeObj = IL2CPP::il2cpp_class_get_type(klass);
    void* typeParam = IL2CPP::il2cpp_type_get_object(typeObj);
    if (!typeParam) return instances;

    uintptr_t fp = *(uintptr_t*)findMethod;
    if (!fp) return instances;

    using Fn = void*(*)(void*, void*);
    void* arr = nullptr;
    
    tls_in_safe = 1;
    if (sigsetjmp(tls_jmpbuf, 1) == 0) {
        arr = reinterpret_cast<Fn>(fp)(typeParam, findMethod);
        tls_in_safe = 0;
    } else {
        tls_in_safe = 0;
        InstallSafeSignalHandlers();
        return instances;
    }

    if (arr) {
        // Your safe pointer math instead of structs
        uintptr_t len = *(uintptr_t*)((uint8_t*)arr + 0x18);
        for (uintptr_t i = 0; i < len; i++) {
            void* elem = *((void**)((uint8_t*)arr + 0x20) + i);
            if (elem) instances.push_back(elem);
        }
    }
    return instances;
}

// =============================================
// 4. FLOATING UI (LibTool Style)
// =============================================
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

- (void)log:(NSString *)msg {
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

    [self log:[NSString stringWithFormat:@"\n[*] Searching for Class: %@", className]];

    if (IL2CPP::il2cpp_thread_attach && IL2CPP::il2cpp_domain_get) {
        IL2CPP::il2cpp_thread_attach(IL2CPP::il2cpp_domain_get());
    }

    void *klass = FindClassGlobal(className.UTF8String);
    if (!klass) {
        [self log:@"[-] Class not found in any loaded assembly."];
        return;
    }

    void *method = IL2CPP::il2cpp_class_get_method_from_name(klass, methodName.UTF8String, 0);
    if (!method) {
        [self log:@"[-] Method not found. (Note: Must have 0 arguments)."];
        return;
    }

    [self log:@"[*] Scanning memory for active instances..."];
    std::vector<void*> instances = GetActiveInstances(klass);

    if (instances.empty()) {
        [self log:@"[-] No active instances found in the current scene."];
        return;
    }

    [self log:[NSString stringWithFormat:@"[+] Found %zu instances. Invoking...", instances.size()]];

    for (size_t i = 0; i < instances.size(); i++) {
        void* instance = instances[i];
        [self log:[NSString stringWithFormat:@"  -> Invoking on %p", instance]];

        void* exc = nullptr;
        
        // CRASH-PROOF INVOKE BLOCK
        tls_in_safe = 1;
        if (sigsetjmp(tls_jmpbuf, 1) == 0) {
            IL2CPP::il2cpp_runtime_invoke(method, instance, nullptr, &exc);
            tls_in_safe = 0;
            if (exc) {
                [self log:@"  [!] Exception thrown during execution!"];
            } else {
                [self log:@"  [+] Success!"];
            }
        } else {
            tls_in_safe = 0;
            InstallSafeSignalHandlers();
            [self log:@"  [!] Prevented fatal SIGSEGV crash during invoke!"];
        }
    }
}
@end

// ==========================================
// 5. FLOATING DRAGGABLE BUTTON
// ==========================================
ModMenuUI *menuView = nil;

@interface FloatingIcon : UIButton
@end
@implementation FloatingIcon
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    self.center = [touch locationInView:self.superview];
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
        floater.backgroundColor = [UIColor redColor];
        floater.layer.cornerRadius = 25;
        floater.layer.borderWidth = 2;
        floater.layer.borderColor = [UIColor whiteColor].CGColor;
        [floater setTitle:@"🛠" forState:UIControlStateNormal];
        [floater addTarget:floater action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [window addSubview:floater];
    });
}

// ==========================================
// 6. INITIALIZATION
// ==========================================
%ctor {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        InstallSafeSignalHandlers();
        Il2CppAttach();
        
        while (!s_attached || IL2CPP::il2cpp_domain_get == nullptr) {
            [NSThread sleepForTimeInterval:0.5];
        }
        
        SetupUI();
    });
}
