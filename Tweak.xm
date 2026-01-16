#import <substrate.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// IL2CPP function pointer types
typedef void* (*il2cpp_domain_get_assemblies_t)(void* domain, size_t* size);
typedef void* (*il2cpp_domain_get_t)();
typedef void* (*il2cpp_class_from_name_t)(void* image, const char* namespaze, const char* name);
typedef void* (*il2cpp_class_get_methods_t)(void* klass, void** iter);
typedef const char* (*il2cpp_method_get_name_t)(void* method);
typedef void* (*il2cpp_assembly_get_image_t)(void* assembly);

// Original function pointers
static bool (*orig_TryUnlockAdvancedBattlePass)(void* self, int bpld, int count, void* source);
static bool (*orig_HasBuyAdvancedBattlePass)(void* self, int bpld);

// Global state
static BOOL hooksEnabled = NO;
static UIButton *toggleButton = nil;
static UITextView *logView = nil;
static NSMutableArray *logMessages = nil;

// Add log message to screen
static void addLog(NSString *message) {
    if (!logMessages) {
        logMessages = [NSMutableArray new];
    }
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm:ss"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@", timestamp, message];
    [logMessages addObject:logEntry];
    
    // Keep only last 100 logs
    if (logMessages.count > 100) {
        [logMessages removeObjectAtIndex:0];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (logView) {
            logView.text = [logMessages componentsJoinedByString:@"\n"];
            [logView scrollRangeToVisible:NSMakeRange(logView.text.length - 1, 1)];
        }
    });
    
    NSLog(@"%@", logEntry);
}

// Hooked TryUnlockAdvancedBattlePass
static bool hook_TryUnlockAdvancedBattlePass(void* self, int bpld, int count, void* source) {
    if (hooksEnabled) {
        addLog([NSString stringWithFormat:@"✅ TryUnlock called - bpld:%d count:%d", bpld, count]);
        addLog(@"🔓 Patched [True] - Unlocked!");
        return true;
    } else {
        return orig_TryUnlockAdvancedBattlePass ? orig_TryUnlockAdvancedBattlePass(self, bpld, count, source) : false;
    }
}

// Hooked HasBuyAdvancedBattlePass
static bool hook_HasBuyAdvancedBattlePass(void* self, int bpld) {
    if (hooksEnabled) {
        addLog([NSString stringWithFormat:@"✅ HasBuy called - bpld:%d", bpld]);
        addLog(@"🔓 Patched [True] - Has Advanced!");
        return true;
    } else {
        return orig_HasBuyAdvancedBattlePass ? orig_HasBuyAdvancedBattlePass(self, bpld) : false;
    }
}

// Toggle button action
static void toggleHooks(UIButton *sender) {
    hooksEnabled = !hooksEnabled;
    
    NSString *status = hooksEnabled ? @"🟢 ACTIVE" : @"🔴 STOPPED";
    [sender setTitle:status forState:UIControlStateNormal];
    sender.backgroundColor = hooksEnabled ? [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:0.9] : [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.9];
    
    addLog(hooksEnabled ? @"═══ HOOKS ENABLED ═══" : @"═══ HOOKS DISABLED ═══");
}

// Find and hook IL2CPP methods
static void hookIL2CPPMethods() {
    addLog(@"🔍 Starting IL2CPP method search...");
    
    void* il2cppHandle = dlopen(NULL, RTLD_LAZY);
    if (!il2cppHandle) {
        addLog(@"❌ Failed to get IL2CPP handle");
        return;
    }
    
    il2cpp_domain_get_t il2cpp_domain_get = (il2cpp_domain_get_t)dlsym(il2cppHandle, "il2cpp_domain_get");
    il2cpp_domain_get_assemblies_t il2cpp_domain_get_assemblies = (il2cpp_domain_get_assemblies_t)dlsym(il2cppHandle, "il2cpp_domain_get_assemblies");
    il2cpp_assembly_get_image_t il2cpp_assembly_get_image = (il2cpp_assembly_get_image_t)dlsym(il2cppHandle, "il2cpp_assembly_get_image");
    il2cpp_class_from_name_t il2cpp_class_from_name = (il2cpp_class_from_name_t)dlsym(il2cppHandle, "il2cpp_class_from_name");
    il2cpp_class_get_methods_t il2cpp_class_get_methods = (il2cpp_class_get_methods_t)dlsym(il2cppHandle, "il2cpp_class_get_methods");
    il2cpp_method_get_name_t il2cpp_method_get_name = (il2cpp_method_get_name_t)dlsym(il2cppHandle, "il2cpp_method_get_name");
    
    if (!il2cpp_domain_get || !il2cpp_domain_get_assemblies || !il2cpp_assembly_get_image || 
        !il2cpp_class_from_name || !il2cpp_class_get_methods || !il2cpp_method_get_name) {
        addLog(@"❌ Failed to load IL2CPP functions");
        return;
    }
    
    void* domain = il2cpp_domain_get();
    if (!domain) {
        addLog(@"❌ Failed to get IL2CPP domain");
        return;
    }
    
    size_t assemblyCount = 0;
    void** assemblies = (void**)il2cpp_domain_get_assemblies(domain, &assemblyCount);
    
    addLog([NSString stringWithFormat:@"📦 Searching %zu assemblies...", assemblyCount]);
    
    BOOL foundClass = NO;
    int methodsHooked = 0;
    
    for (size_t i = 0; i < assemblyCount; i++) {
        void* image = il2cpp_assembly_get_image(assemblies[i]);
        if (!image) continue;
        
        void* battlePassClass = il2cpp_class_from_name(image, "RGScript.Data", "BattlePassData");
        if (!battlePassClass) continue;
        
        foundClass = YES;
        addLog(@"✅ Found BattlePassData class!");
        
        void* iter = NULL;
        void* method;
        while ((method = il2cpp_class_get_methods(battlePassClass, &iter))) {
            const char* methodName = il2cpp_method_get_name(method);
            if (!methodName) continue;
            
            if (strcmp(methodName, "TryUnlockAdvancedBattlePass") == 0) {
                MSHookFunction(method, (void*)hook_TryUnlockAdvancedBattlePass, (void**)&orig_TryUnlockAdvancedBattlePass);
                addLog(@"🎯 Hooked: TryUnlockAdvancedBattlePass");
                methodsHooked++;
            }
            
            if (strcmp(methodName, "HasBuyAdvancedBattlePass") == 0) {
                MSHookFunction(method, (void*)hook_HasBuyAdvancedBattlePass, (void**)&orig_HasBuyAdvancedBattlePass);
                addLog(@"🎯 Hooked: HasBuyAdvancedBattlePass");
                methodsHooked++;
            }
        }
        
        break;
    }
    
    if (foundClass && methodsHooked > 0) {
        addLog([NSString stringWithFormat:@"✅ Successfully hooked %d methods!", methodsHooked]);
        addLog(@"💡 Press button to activate hooks");
    } else {
        addLog(@"❌ Could not find target methods");
    }
}

// Create UI overlay
static void createUI() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) {
            for (UIWindow *window in [UIApplication sharedApplication].windows) {
                if (window.isKeyWindow) {
                    keyWindow = window;
                    break;
                }
            }
        }
        
        if (!keyWindow) return;
        
        // Create log view
        logView = [[UITextView alloc] initWithFrame:CGRectMake(10, 100, keyWindow.bounds.size.width - 20, 300)];
        logView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        logView.textColor = [UIColor greenColor];
        logView.font = [UIFont fontWithName:@"Menlo" size:11];
        logView.editable = NO;
        logView.layer.cornerRadius = 10;
        logView.layer.borderWidth = 2;
        logView.layer.borderColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:1.0].CGColor;
        logView.text = @"BattlePass Tweak - Logs will appear here...\n";
        [keyWindow addSubview:logView];
        
        // Create toggle button
        toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
        toggleButton.frame = CGRectMake(10, 50, 150, 40);
        [toggleButton setTitle:@"🔴 STOPPED" forState:UIControlStateNormal];
        [toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        toggleButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        toggleButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.9];
        toggleButton.layer.cornerRadius = 8;
        toggleButton.layer.borderWidth = 2;
        toggleButton.layer.borderColor = [UIColor whiteColor].CGColor;
        [toggleButton addTarget:nil action:@selector(invokeToggle:) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:toggleButton];
        
        // Make views draggable
        UIPanGestureRecognizer *logPan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(handlePan:)];
        [logView addGestureRecognizer:logPan];
        
        UIPanGestureRecognizer *buttonPan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(handlePan:)];
        [toggleButton addGestureRecognizer:buttonPan];
        
        addLog(@"🎮 UI Loaded - Ready to use!");
    });
}

%hook UIView

%new
- (void)invokeToggle:(UIButton *)sender {
    toggleHooks(sender);
}

%new
- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *view = gesture.view;
    CGPoint translation = [gesture translationInView:view.superview];
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:view.superview];
}

%end

%ctor {
    addLog(@"🚀 BattlePass Tweak Loading...");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        createUI();
        hookIL2CPPMethods();
    });
}
