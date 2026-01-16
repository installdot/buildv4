#import <substrate.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

// IL2CPP function pointer types
typedef void* (*il2cpp_domain_get_assemblies_t)(void* domain, size_t* size);
typedef void* (*il2cpp_domain_get_t)();
typedef void* (*il2cpp_class_from_name_t)(void* image, const char* namespaze, const char* name);
typedef void* (*il2cpp_class_get_methods_t)(void* klass, void** iter);
typedef const char* (*il2cpp_method_get_name_t)(void* method);
typedef void* (*il2cpp_assembly_get_image_t)(void* assembly);
typedef const char* (*il2cpp_image_get_name_t)(void* image);

// Original function pointers
static bool (*orig_TryUnlockAdvancedBattlePass)(void* self, int bpld, int count, void* source);
static bool (*orig_HasBuyAdvancedBattlePass)(void* self, int bpld);

// Global state
static BOOL hooksEnabled = NO;
static BOOL logViewVisible = YES;
static UIButton *toggleButton = nil;
static UIButton *logToggleButton = nil;
static UITextView *logView = nil;
static NSMutableArray *logMessages = nil;
static int tryUnlockCallCount = 0;
static int hasBuyCallCount = 0;

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
    tryUnlockCallCount++;
    
    addLog(@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    addLog(@"📞 TryUnlockAdvancedBattlePass CALLED");
    addLog([NSString stringWithFormat:@"   📍 Call #%d", tryUnlockCallCount]);
    addLog([NSString stringWithFormat:@"   🔢 bpld (battle pass ID): %d", bpld]);
    addLog([NSString stringWithFormat:@"   🔢 count: %d", count]);
    addLog([NSString stringWithFormat:@"   📦 source ptr: %p", source]);
    addLog([NSString stringWithFormat:@"   📦 self ptr: %p", self]);
    
    bool result;
    if (hooksEnabled) {
        result = true;
        addLog(@"   🟢 HOOK ACTIVE: Forcing TRUE");
        addLog(@"   ✅ Return: TRUE (Unlocked!)");
    } else {
        result = orig_TryUnlockAdvancedBattlePass ? orig_TryUnlockAdvancedBattlePass(self, bpld, count, source) : false;
        addLog([NSString stringWithFormat:@"   🔵 HOOK DISABLED: Original called"]);
        addLog([NSString stringWithFormat:@"   📤 Return: %@ (Original)", result ? @"TRUE" : @"FALSE"]);
    }
    addLog(@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    return result;
}

// Hooked HasBuyAdvancedBattlePass
static bool hook_HasBuyAdvancedBattlePass(void* self, int bpld) {
    hasBuyCallCount++;
    
    addLog(@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    addLog(@"📞 HasBuyAdvancedBattlePass CALLED");
    addLog([NSString stringWithFormat:@"   📍 Call #%d", hasBuyCallCount]);
    addLog([NSString stringWithFormat:@"   🔢 bpld (battle pass ID): %d", bpld]);
    addLog([NSString stringWithFormat:@"   📦 self ptr: %p", self]);
    
    bool result;
    if (hooksEnabled) {
        result = true;
        addLog(@"   🟢 HOOK ACTIVE: Forcing TRUE");
        addLog(@"   ✅ Return: TRUE (Has Advanced!)");
    } else {
        result = orig_HasBuyAdvancedBattlePass ? orig_HasBuyAdvancedBattlePass(self, bpld) : false;
        addLog([NSString stringWithFormat:@"   🔵 HOOK DISABLED: Original called"]);
        addLog([NSString stringWithFormat:@"   📤 Return: %@ (Original)", result ? @"TRUE" : @"FALSE"]);
    }
    addLog(@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    return result;
}

// Toggle button action
static void toggleHooks(UIButton *sender) {
    hooksEnabled = !hooksEnabled;
    
    NSString *status = hooksEnabled ? @"🟢 ACTIVE" : @"🔴 DISABLED";
    [sender setTitle:status forState:UIControlStateNormal];
    sender.backgroundColor = hooksEnabled ? [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:0.9] : [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.9];
    
    addLog(@"═══════════════════════════════");
    addLog(hooksEnabled ? @"🟢 HOOKS ENABLED - Will bypass checks" : @"🔴 HOOKS DISABLED - Original behavior");
    addLog(@"═══════════════════════════════");
}

// Toggle log view visibility
static void toggleLogView(UIButton *sender) {
    logViewVisible = !logViewVisible;
    
    [UIView animateWithDuration:0.3 animations:^{
        logView.alpha = logViewVisible ? 1.0 : 0.0;
    }];
    
    NSString *icon = logViewVisible ? @"📋" : @"📋";
    [sender setTitle:icon forState:UIControlStateNormal];
    sender.backgroundColor = logViewVisible ? [UIColor colorWithRed:0.2 green:0.6 blue:0.8 alpha:0.9] : [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:0.9];
}

// Find and hook IL2CPP methods
static void hookIL2CPPMethods() {
    addLog(@"═══════════════════════════════");
    addLog(@"🔍 STARTING IL2CPP ANALYSIS");
    addLog(@"═══════════════════════════════");
    
    void* il2cppHandle = dlopen(NULL, RTLD_LAZY);
    if (!il2cppHandle) {
        addLog(@"❌ ERROR: Failed to get IL2CPP handle");
        addLog(@"   This may not be a Unity IL2CPP app");
        return;
    }
    addLog(@"✅ IL2CPP handle acquired");
    
    il2cpp_domain_get_t il2cpp_domain_get = (il2cpp_domain_get_t)dlsym(il2cppHandle, "il2cpp_domain_get");
    il2cpp_domain_get_assemblies_t il2cpp_domain_get_assemblies = (il2cpp_domain_get_assemblies_t)dlsym(il2cppHandle, "il2cpp_domain_get_assemblies");
    il2cpp_assembly_get_image_t il2cpp_assembly_get_image = (il2cpp_assembly_get_image_t)dlsym(il2cppHandle, "il2cpp_assembly_get_image");
    il2cpp_image_get_name_t il2cpp_image_get_name = (il2cpp_image_get_name_t)dlsym(il2cppHandle, "il2cpp_image_get_name");
    il2cpp_class_from_name_t il2cpp_class_from_name = (il2cpp_class_from_name_t)dlsym(il2cppHandle, "il2cpp_class_from_name");
    il2cpp_class_get_methods_t il2cpp_class_get_methods = (il2cpp_class_get_methods_t)dlsym(il2cppHandle, "il2cpp_class_get_methods");
    il2cpp_method_get_name_t il2cpp_method_get_name = (il2cpp_method_get_name_t)dlsym(il2cppHandle, "il2cpp_method_get_name");
    
    if (!il2cpp_domain_get || !il2cpp_domain_get_assemblies || !il2cpp_assembly_get_image || 
        !il2cpp_class_from_name || !il2cpp_class_get_methods || !il2cpp_method_get_name) {
        addLog(@"❌ ERROR: Failed to load IL2CPP functions");
        addLog(@"   Missing function symbols");
        return;
    }
    addLog(@"✅ All IL2CPP functions loaded");
    
    void* domain = il2cpp_domain_get();
    if (!domain) {
        addLog(@"❌ ERROR: Failed to get IL2CPP domain");
        return;
    }
    addLog(@"✅ IL2CPP domain acquired");
    
    size_t assemblyCount = 0;
    void** assemblies = (void**)il2cpp_domain_get_assemblies(domain, &assemblyCount);
    
    addLog([NSString stringWithFormat:@"📦 Found %zu assemblies to scan", assemblyCount]);
    addLog(@"🔎 Searching for BattlePassData...");
    
    BOOL foundClass = NO;
    int methodsFound = 0;
    int methodsHooked = 0;
    
    for (size_t i = 0; i < assemblyCount; i++) {
        void* image = il2cpp_assembly_get_image(assemblies[i]);
        if (!image) continue;
        
        void* battlePassClass = il2cpp_class_from_name(image, "RGScript.Data", "BattlePassData");
        if (!battlePassClass) continue;
        
        foundClass = YES;
        const char* imageName = il2cpp_image_get_name ? il2cpp_image_get_name(image) : "unknown";
        
        addLog(@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        addLog(@"✅ TARGET CLASS FOUND!");
        addLog(@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        addLog([NSString stringWithFormat:@"   📍 Assembly: %s", imageName]);
        addLog(@"   📍 Namespace: RGScript.Data");
        addLog(@"   📍 Class: BattlePassData");
        addLog([NSString stringWithFormat:@"   📍 Class ptr: %p", battlePassClass]);
        addLog(@"");
        addLog(@"🔍 Scanning for methods...");
        
        void* iter = NULL;
        void* method;
        while ((method = il2cpp_class_get_methods(battlePassClass, &iter))) {
            const char* methodName = il2cpp_method_get_name(method);
            if (!methodName) continue;
            
            methodsFound++;
            
            if (strcmp(methodName, "TryUnlockAdvancedBattlePass") == 0) {
                addLog(@"");
                addLog(@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
                addLog(@"🎯 METHOD 1 FOUND & HOOKED");
                addLog(@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
                addLog(@"   Name: TryUnlockAdvancedBattlePass");
                addLog(@"   Signature: Boolean (Int32, Int32, String)");
                addLog([NSString stringWithFormat:@"   Address: %p", method]);
                MSHookFunction(method, (void*)hook_TryUnlockAdvancedBattlePass, (void**)&orig_TryUnlockAdvancedBattlePass);
                addLog(@"   ✅ Hook installed successfully!");
                methodsHooked++;
            }
            
            if (strcmp(methodName, "HasBuyAdvancedBattlePass") == 0) {
                addLog(@"");
                addLog(@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
                addLog(@"🎯 METHOD 2 FOUND & HOOKED");
                addLog(@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
                addLog(@"   Name: HasBuyAdvancedBattlePass");
                addLog(@"   Signature: Boolean (Int32)");
                addLog([NSString stringWithFormat:@"   Address: %p", method]);
                MSHookFunction(method, (void*)hook_HasBuyAdvancedBattlePass, (void**)&orig_HasBuyAdvancedBattlePass);
                addLog(@"   ✅ Hook installed successfully!");
                methodsHooked++;
            }
        }
        
        break;
    }
    
    addLog(@"");
    addLog(@"═══════════════════════════════");
    if (foundClass && methodsHooked > 0) {
        addLog(@"✅ HOOK SETUP COMPLETE!");
        addLog([NSString stringWithFormat:@"   📊 Methods found: %d", methodsFound]);
        addLog([NSString stringWithFormat:@"   🎯 Methods hooked: %d", methodsHooked]);
        addLog(@"");
        addLog(@"🔴 Hooks are DISABLED by default");
        addLog(@"💡 Press the button to ENABLE bypass");
        addLog(@"📋 All method calls will be logged");
    } else if (foundClass) {
        addLog(@"⚠️ Class found but methods not hooked");
        addLog([NSString stringWithFormat:@"   Methods scanned: %d", methodsFound]);
    } else {
        addLog(@"❌ BattlePassData class not found");
        addLog(@"   Check namespace/class name");
    }
    addLog(@"═══════════════════════════════");
}

// Create UI overlay
static void createUI() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        
        // iOS 13+ scene-based approach
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *window in scene.windows) {
                        if (window.isKeyWindow) {
                            keyWindow = window;
                            break;
                        }
                    }
                    if (keyWindow) break;
                }
            }
        }
        
        // Fallback for iOS 12 and below
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
        logView = [[UITextView alloc] initWithFrame:CGRectMake(10, 100, keyWindow.bounds.size.width - 20, 400)];
        logView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.95];
        logView.textColor = [UIColor colorWithRed:0.3 green:1.0 blue:0.3 alpha:1.0];
        logView.font = [UIFont fontWithName:@"Menlo" size:10];
        logView.editable = NO;
        logView.layer.cornerRadius = 10;
        logView.layer.borderWidth = 2;
        logView.layer.borderColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:1.0].CGColor;
        logView.text = @"🎮 BattlePass Tweak v1.0\n📋 Initializing...\n";
        [keyWindow addSubview:logView];
        
        // Create toggle button (hooks)
        toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
        toggleButton.frame = CGRectMake(10, 50, 150, 40);
        [toggleButton setTitle:@"🔴 DISABLED" forState:UIControlStateNormal];
        [toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        toggleButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        toggleButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.9];
        toggleButton.layer.cornerRadius = 8;
        toggleButton.layer.borderWidth = 2;
        toggleButton.layer.borderColor = [UIColor whiteColor].CGColor;
        [toggleButton addTarget:nil action:@selector(invokeToggle:) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:toggleButton];
        
        // Create log toggle button
        logToggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
        logToggleButton.frame = CGRectMake(170, 50, 50, 40);
        [logToggleButton setTitle:@"📋" forState:UIControlStateNormal];
        logToggleButton.titleLabel.font = [UIFont systemFontOfSize:24];
        logToggleButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.8 alpha:0.9];
        logToggleButton.layer.cornerRadius = 8;
        logToggleButton.layer.borderWidth = 2;
        logToggleButton.layer.borderColor = [UIColor whiteColor].CGColor;
        [logToggleButton addTarget:nil action:@selector(invokeLogToggle:) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:logToggleButton];
        
        // Make views draggable
        UIPanGestureRecognizer *logPan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(handlePan:)];
        [logView addGestureRecognizer:logPan];
        
        UIPanGestureRecognizer *buttonPan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(handlePan:)];
        [toggleButton addGestureRecognizer:buttonPan];
        
        UIPanGestureRecognizer *logButtonPan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(handlePan:)];
        [logToggleButton addGestureRecognizer:logButtonPan];
        
        addLog(@"🎮 UI Loaded - Ready!");
    });
}

%hook UIView

%new
- (void)invokeToggle:(UIButton *)sender {
    toggleHooks(sender);
}

%new
- (void)invokeLogToggle:(UIButton *)sender {
    toggleLogView(sender);
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
