#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <signal.h>
#include <setjmp.h>
#include <vector>
#include <string>

// =============================================
// 1. CRASH-PROOF SIGNAL HANDLER
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
    const char *(*il2cpp_class_get_namespace)(void *klass);
    void       *(*il2cpp_class_get_method_from_name)(void *klass, const char *name, int args);
    const void *(*il2cpp_class_get_type)(void *klass);
    void       *(*il2cpp_type_get_object)(const void *type);
    void       *(*il2cpp_runtime_invoke)(void *method, void *obj, void **params, void **exc);
    
    // Additional APIs for the Inspector
    void       *(*il2cpp_class_get_methods)(void *klass, void **iter);
    const char *(*il2cpp_method_get_name)(const void *method);
    uint32_t    (*il2cpp_method_get_param_count)(const void *method);
    void       *(*il2cpp_class_get_fields)(void *klass, void **iter);
    const char *(*il2cpp_field_get_name)(void *field);
    size_t      (*il2cpp_field_get_offset)(void *field);
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
    BIND(il2cpp_class_get_namespace);
    BIND(il2cpp_class_get_method_from_name);
    BIND(il2cpp_class_get_type);
    BIND(il2cpp_type_get_object);
    BIND(il2cpp_runtime_invoke);
    BIND(il2cpp_class_get_methods);
    BIND(il2cpp_method_get_name);
    BIND(il2cpp_method_get_param_count);
    BIND(il2cpp_class_get_fields);
    BIND(il2cpp_field_get_name);
    BIND(il2cpp_field_get_offset);
    #undef BIND

    s_attached = true;
}

// =============================================
// 3. SAFE INSPECTOR LOGIC
// =============================================
struct ClassDef { std::string fullName; void* klass; };
struct MethodDef { std::string name; int paramCount; void* method; };
struct FieldDef { std::string name; size_t offset; void* field; };

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
            if (name && strcmp(name, targetName) == 0) return klass;
        }
    }
    return nullptr;
}

static std::vector<ClassDef> GetAllClasses() {
    std::vector<ClassDef> classes;
    if (!s_attached) return classes;
    void *domain = IL2CPP::il2cpp_domain_get();
    size_t asmCount = 0;
    void **assemblies = IL2CPP::il2cpp_domain_get_assemblies(domain, &asmCount);
    for (size_t ai = 0; ai < asmCount; ai++) {
        void *img = (void *)IL2CPP::il2cpp_assembly_get_image(assemblies[ai]);
        if (!img) continue;
        uint32_t classCount = IL2CPP::il2cpp_image_get_class_count(img);
        for (uint32_t ci = 0; ci < classCount; ci++) {
            void *klass = IL2CPP::il2cpp_image_get_class(img, ci);
            if (!klass) continue;
            const char *ns = IL2CPP::il2cpp_class_get_namespace(klass);
            const char *name = IL2CPP::il2cpp_class_get_name(klass);
            std::string fullName = (ns && ns[0] != '\0') ? std::string(ns) + "." + name : std::string(name);
            classes.push_back({fullName, klass});
        }
    }
    return classes;
}

static std::vector<MethodDef> GetMethods(void* klass) {
    std::vector<MethodDef> methods;
    if (!klass) return methods;
    void* iter = nullptr;
    while (void* method = IL2CPP::il2cpp_class_get_methods(klass, &iter)) {
        methods.push_back({IL2CPP::il2cpp_method_get_name(method), (int)IL2CPP::il2cpp_method_get_param_count(method), method});
    }
    return methods;
}

static std::vector<FieldDef> GetFields(void* klass) {
    std::vector<FieldDef> fields;
    if (!klass) return fields;
    void* iter = nullptr;
    while (void* field = IL2CPP::il2cpp_class_get_fields(klass, &iter)) {
        fields.push_back({IL2CPP::il2cpp_field_get_name(field), IL2CPP::il2cpp_field_get_offset(field), field});
    }
    return fields;
}

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
        uintptr_t len = *(uintptr_t*)((uint8_t*)arr + 0x18);
        if (len < 500000) { // Safety bounds
            for (uintptr_t i = 0; i < len; i++) {
                void* elem = *((void**)((uint8_t*)arr + 0x20) + i);
                if (elem) instances.push_back(elem);
            }
        }
    }
    return instances;
}

// ==========================================
// 4. BIG MENU INTERFACE
// ==========================================
typedef NS_ENUM(NSInteger, InspectorMode) {
    ModeClassSearch,
    ModeClassDetails,
    ModeMethods,
    ModeFields,
    ModeInstances,
    ModeInstanceInspector
};

@interface InspectorUI : UIView <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *searchBar;
@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) UILabel *titleLbl;
@property (nonatomic, assign) InspectorMode currentMode;

// Data State
@property (nonatomic, assign) std::vector<ClassDef> allClasses;
@property (nonatomic, assign) std::vector<ClassDef> filteredClasses;
@property (nonatomic, assign) std::vector<MethodDef> currentMethods;
@property (nonatomic, assign) std::vector<FieldDef> currentFields;
@property (nonatomic, assign) std::vector<void*> currentInstances;
@property (nonatomic, assign) ClassDef selectedClass;
@property (nonatomic, assign) void* selectedInstance;
@end

@implementation InspectorUI
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        self.layer.cornerRadius = 10;
        self.layer.masksToBounds = YES;
        self.currentMode = ModeClassSearch;

        _titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(50, 10, frame.size.width - 60, 30)];
        _titleLbl.text = @"Loading IL2CPP...";
        _titleLbl.textColor = [UIColor whiteColor];
        _titleLbl.font = [UIFont boldSystemFontOfSize:16];
        [self addSubview:_titleLbl];

        _backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _backBtn.frame = CGRectMake(10, 10, 40, 30);
        [_backBtn setTitle:@"<" forState:UIControlStateNormal];
        _backBtn.backgroundColor = [UIColor darkGrayColor];
        _backBtn.layer.cornerRadius = 5;
        [_backBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [_backBtn addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
        _backBtn.hidden = YES;
        [self addSubview:_backBtn];

        _searchBar = [[UITextField alloc] initWithFrame:CGRectMake(10, 45, frame.size.width - 20, 35)];
        _searchBar.placeholder = @" Search Classes...";
        _searchBar.backgroundColor = [UIColor whiteColor];
        _searchBar.textColor = [UIColor blackColor];
        _searchBar.layer.cornerRadius = 5;
        _searchBar.delegate = self;
        [_searchBar addTarget:self action:@selector(searchChanged:) forControlEvents:UIControlEventEditingChanged];
        [self addSubview:_searchBar];

        _tableView = [[UITableView alloc] initWithFrame:CGRectMake(10, 90, frame.size.width - 20, frame.size.height - 100)];
        _tableView.backgroundColor = [UIColor clearColor];
        _tableView.delegate = self;
        _tableView.dataSource = self;
        _tableView.rowHeight = 45;
        [self addSubview:_tableView];
    }
    return self;
}

- (void)loadAllClasses {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        IL2CPP::il2cpp_thread_attach(IL2CPP::il2cpp_domain_get());
        self.allClasses = GetAllClasses();
        self.filteredClasses = self.allClasses;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.titleLbl.text = @"IL2CPP Inspector";
            [self.tableView reloadData];
        });
    });
}

- (void)setMode:(InspectorMode)mode title:(NSString *)title {
    self.currentMode = mode;
    self.titleLbl.text = title;
    self.backBtn.hidden = (mode == ModeClassSearch);
    self.searchBar.hidden = (mode != ModeClassSearch);
    
    CGRect tableFrame = self.tableView.frame;
    tableFrame.origin.y = self.searchBar.hidden ? 45 : 90;
    tableFrame.size.height = self.frame.size.height - tableFrame.origin.y - 10;
    self.tableView.frame = tableFrame;
    [self.tableView reloadData];
}

- (void)goBack {
    if (self.currentMode == ModeClassDetails) [self setMode:ModeClassSearch title:@"IL2CPP Inspector"];
    else if (self.currentMode == ModeMethods || self.currentMode == ModeFields || self.currentMode == ModeInstances) 
        [self setMode:ModeClassDetails title:[NSString stringWithUTF8String:self.selectedClass.fullName.c_str()]];
    else if (self.currentMode == ModeInstanceInspector) 
        [self setMode:ModeInstances title:@"Active Instances"];
}

- (void)searchChanged:(UITextField *)sender {
    NSString *query = sender.text.lowercaseString;
    self.filteredClasses.clear();
    if (query.length == 0) {
        self.filteredClasses = self.allClasses;
    } else {
        for (const auto& c : self.allClasses) {
            if (NSString *nsStr = [NSString stringWithUTF8String:c.fullName.c_str()]) {
                if ([nsStr.lowercaseString containsString:query]) {
                    self.filteredClasses.push_back(c);
                }
            }
        }
    }
    [self.tableView reloadData];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (self.currentMode) {
        case ModeClassSearch: return self.filteredClasses.size();
        case ModeClassDetails: return 3;
        case ModeMethods: return self.currentMethods.size();
        case ModeFields: return self.currentFields.size();
        case ModeInstances: return self.currentInstances.size();
        case ModeInstanceInspector: return self.currentFields.size();
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:12];
        cell.textLabel.adjustsFontSizeToFitWidth = YES;
    }
    cell.detailTextLabel.text = @"";

    if (self.currentMode == ModeClassSearch) {
        cell.textLabel.text = [NSString stringWithUTF8String:self.filteredClasses[indexPath.row].fullName.c_str()];
    } 
    else if (self.currentMode == ModeClassDetails) {
        NSArray *opts = @[@"▶ View Methods", @"▶ View Fields", @"▶ Find Active Instances"];
        cell.textLabel.text = opts[indexPath.row];
    } 
    else if (self.currentMode == ModeMethods) {
        auto m = self.currentMethods[indexPath.row];
        cell.textLabel.text = [NSString stringWithUTF8String:m.name.c_str()];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Params: %d", m.paramCount];
    }
    else if (self.currentMode == ModeFields) {
        auto f = self.currentFields[indexPath.row];
        cell.textLabel.text = [NSString stringWithUTF8String:f.name.c_str()];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Offset: 0x%zx", f.offset];
    }
    else if (self.currentMode == ModeInstances) {
        cell.textLabel.text = [NSString stringWithFormat:@"Instance Pointer: %p", self.currentInstances[indexPath.row]];
    }
    else if (self.currentMode == ModeInstanceInspector) {
        auto f = self.currentFields[indexPath.row];
        cell.textLabel.text = [NSString stringWithUTF8String:f.name.c_str()];
        
        // SAFE MEMORY READ
        int32_t val = 0;
        if (self.selectedInstance) {
            tls_in_safe = 1;
            if (sigsetjmp(tls_jmpbuf, 1) == 0) {
                val = *(int32_t*)((uintptr_t)self.selectedInstance + f.offset);
                tls_in_safe = 0;
            } else {
                tls_in_safe = 0;
                InstallSafeSignalHandlers();
            }
        }
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Offset: 0x%zx | Value (Int32): %d", f.offset, val];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IL2CPP::il2cpp_thread_attach(IL2CPP::il2cpp_domain_get());

    if (self.currentMode == ModeClassSearch) {
        self.selectedClass = self.filteredClasses[indexPath.row];
        [self setMode:ModeClassDetails title:[NSString stringWithUTF8String:self.selectedClass.fullName.c_str()]];
    } 
    else if (self.currentMode == ModeClassDetails) {
        if (indexPath.row == 0) {
            self.currentMethods = GetMethods(self.selectedClass.klass);
            [self setMode:ModeMethods title:@"Methods"];
        } else if (indexPath.row == 1) {
            self.currentFields = GetFields(self.selectedClass.klass);
            [self setMode:ModeFields title:@"Fields"];
        } else if (indexPath.row == 2) {
            self.currentInstances = GetActiveInstances(self.selectedClass.klass);
            [self setMode:ModeInstances title:[NSString stringWithFormat:@"Found %zu Instances", self.currentInstances.size()]];
        }
    }
    else if (self.currentMode == ModeMethods) {
        auto m = self.currentMethods[indexPath.row];
        if (m.paramCount == 0) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Invoke Method" message:[NSString stringWithUTF8String:m.name.c_str()] preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Invoke Static (NULL Instance)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                
                // CRASH-PROOF INVOKE
                void* exc = nullptr;
                tls_in_safe = 1;
                if (sigsetjmp(tls_jmpbuf, 1) == 0) {
                    IL2CPP::il2cpp_runtime_invoke(m.method, nullptr, nullptr, &exc);
                    tls_in_safe = 0;
                } else {
                    tls_in_safe = 0;
                    InstallSafeSignalHandlers();
                    NSLog(@"[Inspector] SIGSEGV prevented during Static Invoke!");
                }
            }]];
            
            if (self.selectedInstance) {
                [alert addAction:[UIAlertAction actionWithTitle:@"Invoke on Selected Instance" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    
                    void* exc = nullptr;
                    tls_in_safe = 1;
                    if (sigsetjmp(tls_jmpbuf, 1) == 0) {
                        IL2CPP::il2cpp_runtime_invoke(m.method, self.selectedInstance, nullptr, &exc);
                        tls_in_safe = 0;
                    } else {
                        tls_in_safe = 0;
                        InstallSafeSignalHandlers();
                        NSLog(@"[Inspector] SIGSEGV prevented during Instance Invoke!");
                    }
                }]];
            }
            [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
        }
    }
    else if (self.currentMode == ModeInstances) {
        self.selectedInstance = self.currentInstances[indexPath.row];
        self.currentFields = GetFields(self.selectedClass.klass);
        [self setMode:ModeInstanceInspector title:[NSString stringWithFormat:@"Inspecting: %p", self.selectedInstance]];
    }
}
@end

// ==========================================
// 5. FLOATING DRAGGABLE BUTTON
// ==========================================
InspectorUI *menuView = nil;

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
            if (menuView.allClasses.size() == 0) [menuView loadAllClasses];
        }
    }
}
@end

static UIWindow* GetActiveWindow() {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) if (window.isKeyWindow) return window;
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

        menuView = [[InspectorUI alloc] initWithFrame:CGRectMake(20, 60, 320, 450)];
        menuView.hidden = YES;
        [window addSubview:menuView];

        FloatingIcon *floater = [FloatingIcon buttonWithType:UIButtonTypeCustom];
        floater.frame = CGRectMake(20, 100, 50, 50);
        floater.backgroundColor = [UIColor systemBlueColor];
        floater.layer.cornerRadius = 25;
        floater.layer.borderWidth = 2;
        floater.layer.borderColor = [UIColor whiteColor].CGColor;
        [floater setTitle:@"🔍" forState:UIControlStateNormal];
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
