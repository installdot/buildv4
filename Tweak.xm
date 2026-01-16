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

// Method info structure
@interface MethodInfo : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, assign) void *address;
@property (nonatomic, assign) BOOL isHooked;
@end

@implementation MethodInfo
@end

// Forward declarations
static void updateMethodList(void); // ⚡ Forward declaration fixes compiler error
static void hookMethod(MethodInfo *methodInfo);
static void toggleHooks(UIButton *sender);
static void toggleLogView(UIButton *sender);
static void findIL2CPPMethods(void);
static void createUI(void);

// Original function pointers
static bool (*orig_TryUnlockAdvancedBattlePass)(void* self, int bpld, int count, void* source);
static bool (*orig_HasBuyAdvancedBattlePass)(void* self, int bpld);

// Global state
static NSMutableArray<MethodInfo*> *foundMethods = nil;
static BOOL hooksEnabled = NO;
static BOOL logViewVisible = YES;
static UIButton *toggleButton = nil;
static UIButton *logToggleButton = nil;
static UIButton *rescanButton = nil;
static UITextView *logView = nil;
static UIScrollView *methodListView = nil;
static NSMutableArray *logMessages = nil;
static int tryUnlockCallCount = 0;
static int hasBuyCallCount = 0;

// Add log message to screen
static void addLog(NSString *message) {
    if (!logMessages) logMessages = [NSMutableArray new];
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm:ss"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@", timestamp, message];
    [logMessages addObject:logEntry];
    
    if (logMessages.count > 100) [logMessages removeObjectAtIndex:0];
    
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
    addLog(@"━━━━━━━━━━━━━━━━━━━━━━");
    addLog(@"📞 TryUnlock CALLED");
    addLog([NSString stringWithFormat:@"Call #%d | bpld:%d count:%d", tryUnlockCallCount, bpld, count]);
    
    bool result;
    if (hooksEnabled) {
        result = true;
        addLog(@"🟢 FORCED TRUE");
    } else {
        result = orig_TryUnlockAdvancedBattlePass ? orig_TryUnlockAdvancedBattlePass(self, bpld, count, source) : false;
        addLog([NSString stringWithFormat:@"🔵 Original: %@", result ? @"TRUE" : @"FALSE"]);
    }
    addLog(@"━━━━━━━━━━━━━━━━━━━━━━");
    return result;
}

// Hooked HasBuyAdvancedBattlePass
static bool hook_HasBuyAdvancedBattlePass(void* self, int bpld) {
    hasBuyCallCount++;
    addLog(@"━━━━━━━━━━━━━━━━━━━━━━");
    addLog(@"📞 HasBuy CALLED");
    addLog([NSString stringWithFormat:@"Call #%d | bpld:%d", hasBuyCallCount, bpld]);
    
    bool result;
    if (hooksEnabled) {
        result = true;
        addLog(@"🟢 FORCED TRUE");
    } else {
        result = orig_HasBuyAdvancedBattlePass ? orig_HasBuyAdvancedBattlePass(self, bpld) : false;
        addLog([NSString stringWithFormat:@"🔵 Original: %@", result ? @"TRUE" : @"FALSE"]);
    }
    addLog(@"━━━━━━━━━━━━━━━━━━━━━━");
    return result;
}

// Hook specific method
static void hookMethod(MethodInfo *methodInfo) {
    if (methodInfo.isHooked) return;
    
    if ([methodInfo.name isEqualToString:@"TryUnlockAdvancedBattlePass"]) {
        MSHookFunction(methodInfo.address, (void*)hook_TryUnlockAdvancedBattlePass, (void**)&orig_TryUnlockAdvancedBattlePass);
        methodInfo.isHooked = YES;
        addLog([NSString stringWithFormat:@"🎯 Hooked: %@", methodInfo.name]);
    } else if ([methodInfo.name isEqualToString:@"HasBuyAdvancedBattlePass"]) {
        MSHookFunction(methodInfo.address, (void*)hook_HasBuyAdvancedBattlePass, (void**)&orig_HasBuyAdvancedBattlePass);
        methodInfo.isHooked = YES;
        addLog([NSString stringWithFormat:@"🎯 Hooked: %@", methodInfo.name]);
    }
    
    updateMethodList();
}

// Update method list UI
static void updateMethodList() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!methodListView) return;
        
        for (UIView *subview in methodListView.subviews) {
            [subview removeFromSuperview];
        }
        
        CGFloat yOffset = 10;
        
        for (int i = 0; i < foundMethods.count; i++) {
            MethodInfo *methodInfo = foundMethods[i];
            
            UIView *container = [[UIView alloc] initWithFrame:CGRectMake(5, yOffset, methodListView.frame.size.width - 10, 80)];
            container.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.95];
            container.layer.cornerRadius = 8;
            container.layer.borderWidth = 1;
            container.layer.borderColor = [UIColor colorWithRed:0.3 green:0.7 blue:0.9 alpha:1.0].CGColor;
            
            UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, container.frame.size.width - 20, 30)];
            nameLabel.text = methodInfo.name;
            nameLabel.textColor = [UIColor colorWithRed:0.3 green:1.0 blue:0.3 alpha:1.0];
            nameLabel.font = [UIFont boldSystemFontOfSize:12];
            nameLabel.numberOfLines = 2;
            nameLabel.adjustsFontSizeToFitWidth = YES;
            [container addSubview:nameLabel];
            
            UILabel *addressLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 35, container.frame.size.width - 20, 15)];
            addressLabel.text = [NSString stringWithFormat:@"0x%lx", (unsigned long)methodInfo.address];
            addressLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
            addressLabel.font = [UIFont fontWithName:@"Menlo" size:10];
            [container addSubview:addressLabel];
            
            UIButton *hookButton = [UIButton buttonWithType:UIButtonTypeSystem];
            hookButton.frame = CGRectMake(10, 52, container.frame.size.width - 20, 25);
            hookButton.tag = i;
            
            if (methodInfo.isHooked) {
                [hookButton setTitle:@"✅ HOOKED" forState:UIControlStateNormal];
                hookButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:0.8];
                hookButton.enabled = NO;
            } else {
                [hookButton setTitle:@"🎯 HOOK THIS" forState:UIControlStateNormal];
                hookButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.8 alpha:0.9];
                [hookButton addTarget:nil action:@selector(invokeHookMethod:) forControlEvents:UIControlEventTouchUpInside];
            }
            
            [hookButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            hookButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
            hookButton.layer.cornerRadius = 5;
            [container addSubview:hookButton];
            
            [methodListView addSubview:container];
            yOffset += 90;
        }
        
        methodListView.contentSize = CGSizeMake(methodListView.frame.size.width, yOffset);
    });
}

// Toggle hooks on/off
static void toggleHooks(UIButton *sender) {
    hooksEnabled = !hooksEnabled;
    
    NSString *status = hooksEnabled ? @"🟢 ACTIVE" : @"🔴 OFF";
    [sender setTitle:status forState:UIControlStateNormal];
    sender.backgroundColor = hooksEnabled ? [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:0.9] : [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.9];
    
    addLog(hooksEnabled ? @"🟢 HOOKS ENABLED" : @"🔴 HOOKS DISABLED");
}

// Toggle log view visibility
static void toggleLogView(UIButton *sender) {
    logViewVisible = !logViewVisible;
    
    [UIView animateWithDuration:0.3 animations:^{
        logView.alpha = logViewVisible ? 1.0 : 0.0;
        methodListView.alpha = logViewVisible ? 1.0 : 0.0; // hide method list too
    }];
    
    sender.backgroundColor = logViewVisible ? [UIColor colorWithRed:0.2 green:0.6 blue:0.8 alpha:0.9] : [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:0.9];
}

// Find IL2CPP methods (NO HOOKING)
static void findIL2CPPMethods() {
    addLog(@"═══════════════════════");
    addLog(@"🔍 SCANNING FOR METHODS");
    addLog(@"═══════════════════════");
    
    foundMethods = [NSMutableArray new];
    
    void* il2cppHandle = dlopen(NULL, RTLD_LAZY);
    if (!il2cppHandle) {
        addLog(@"❌ IL2CPP handle failed");
        return;
    }
    addLog(@"✅ IL2CPP handle OK");
    
    il2cpp_domain_get_t il2cpp_domain_get = (il2cpp_domain_get_t)dlsym(il2cppHandle, "il2cpp_domain_get");
    il2cpp_domain_get_assemblies_t il2cpp_domain_get_assemblies = (il2cpp_domain_get_assemblies_t)dlsym(il2cppHandle, "il2cpp_domain_get_assemblies");
    il2cpp_assembly_get_image_t il2cpp_assembly_get_image = (il2cpp_assembly_get_image_t)dlsym(il2cppHandle, "il2cpp_assembly_get_image");
    il2cpp_class_from_name_t il2cpp_class_from_name = (il2cpp_class_from_name_t)dlsym(il2cppHandle, "il2cpp_class_from_name");
    il2cpp_class_get_methods_t il2cpp_class_get_methods = (il2cpp_class_get_methods_t)dlsym(il2cppHandle, "il2cpp_class_get_methods");
    il2cpp_method_get_name_t il2cpp_method_get_name = (il2cpp_method_get_name_t)dlsym(il2cppHandle, "il2cpp_method_get_name");
    
    if (!il2cpp_domain_get || !il2cpp_domain_get_assemblies || !il2cpp_assembly_get_image || 
        !il2cpp_class_from_name || !il2cpp_class_get_methods || !il2cpp_method_get_name) {
        addLog(@"❌ IL2CPP functions failed");
        return;
    }
    addLog(@"✅ IL2CPP functions OK");
    
    void* domain = il2cpp_domain_get();
    if (!domain) {
        addLog(@"❌ Domain failed");
        return;
    }
    
    size_t assemblyCount = 0;
    void** assemblies = (void**)il2cpp_domain_get_assemblies(domain, &assemblyCount);
    
    addLog([NSString stringWithFormat:@"📦 Scanning %zu assemblies", assemblyCount]);
    
    for (size_t i = 0; i < assemblyCount; i++) {
        void* image = il2cpp_assembly_get_image(assemblies[i]);
        if (!image) continue;
        
        void* battlePassClass = il2cpp_class_from_name(image, "RGScript.Data", "BattlePassData");
        if (!battlePassClass) continue;
        
        addLog(@"✅ Found BattlePassData!");
        addLog(@"📋 Listing methods...");
        
        void* iter = NULL;
        void* method;
        while ((method = il2cpp_class_get_methods(battlePassClass, &iter))) {
            const char* methodName = il2cpp_method_get_name(method);
            if (!methodName) continue;
            
            if (strcmp(methodName, "TryUnlockAdvancedBattlePass") == 0 || 
                strcmp(methodName, "HasBuyAdvancedBattlePass") == 0) {
                
                MethodInfo *info = [[MethodInfo alloc] init];
                info.name = [NSString stringWithUTF8String:methodName];
                info.address = method;
                info.isHooked = NO;
                [foundMethods addObject:info];
                
                addLog([NSString stringWithFormat:@"✅ %s", methodName]);
            }
        }
        break;
    }
    
    addLog(@"═══════════════════════");
    addLog([NSString stringWithFormat:@"📊 Found %lu methods", (unsigned long)foundMethods.count]);
    addLog(@"💡 Select methods to hook");
    addLog(@"═══════════════════════");
    
    updateMethodList();
}

// Create UI overlay
static void createUI() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        
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
        
        if (!keyWindow) {
            for (UIWindow *window in [UIApplication sharedApplication].windows) {
                if (window.isKeyWindow) {
                    keyWindow = window;
                    break;
                }
            }
        }
        
        if (!keyWindow) return;
        
        CGFloat screenWidth = keyWindow.bounds.size.width;
        CGFloat boxWidth = (screenWidth - 30) / 2;
        
        // Method list view (LEFT)
        methodListView = [[UIScrollView alloc] initWithFrame:CGRectMake(10, 100, boxWidth, 200)];
        methodListView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.95];
        methodListView.layer.cornerRadius = 10;
        methodListView.layer.borderWidth = 2;
        methodListView.layer.borderColor = [UIColor colorWithRed:0.3 green:0.7 blue:0.9 alpha:1.0].CGColor;
        [keyWindow addSubview:methodListView];
        
        // Log view (RIGHT)
        logView = [[UITextView alloc] initWithFrame:CGRectMake(boxWidth + 20, 100, boxWidth, 200)];
        logView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.95];
        logView.textColor = [UIColor colorWithRed:0.3 green:1.0 blue:0.3 alpha:1.0];
        logView.font = [UIFont fontWithName:@"Menlo" size:9];
        logView.editable = NO;
        logView.layer.cornerRadius = 10;
        logView.layer.borderWidth = 2;
        logView.layer.borderColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:1.0].CGColor;
        logView.text = @"🎮 BattlePass Tweak\n";
        [keyWindow addSubview:logView];
        
        // Toggle button (hooks)
        toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
        toggleButton.frame = CGRectMake(10, 50, 80, 40);
        [toggleButton setTitle:@"🔴 OFF" forState:UIControlStateNormal];
        [toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        toggleButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        toggleButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.9];
        toggleButton.layer.cornerRadius = 8;
        toggleButton.layer.borderWidth = 2;
        toggleButton.layer.borderColor = [UIColor whiteColor].CGColor;
        [toggleButton addTarget:nil action:@selector(invokeToggle:) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:toggleButton];
        
        // Log toggle button
        logToggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
        logToggleButton.frame = CGRectMake(100, 50, 40, 40);
        [logToggleButton setTitle:@"📋" forState:UIControlStateNormal];
        logToggleButton.titleLabel.font = [UIFont systemFontOfSize:20];
        logToggleButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.8 alpha:0.9];
        logToggleButton.layer.cornerRadius = 8;
        logToggleButton.layer.borderWidth = 2;
        logToggleButton.layer.borderColor = [UIColor whiteColor].CGColor;
        [logToggleButton addTarget:nil action:@selector(invokeLogToggle:) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:logToggleButton];
        
        // Rescan button
        rescanButton = [UIButton buttonWithType:UIButtonTypeSystem];
        rescanButton.frame = CGRectMake(150, 50, 80, 40);
        [rescanButton setTitle:@"🔄 Rescan" forState:UIControlStateNormal];
        [rescanButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        rescanButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        rescanButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.5 blue:0.2 alpha:0.9];
        rescanButton.layer.cornerRadius = 8;
        rescanButton.layer.borderWidth = 2;
        rescanButton.layer.borderColor = [UIColor whiteColor].CGColor;
        [rescanButton addTarget:nil action:@selector(invokeRescan:) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:rescanButton];
        
        // Make views draggable
        for (UIView *v in @[methodListView, logView, toggleButton, logToggleButton, rescanButton]) {
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(handlePan:)];
            [v addGestureRecognizer:pan];
        }
        
        addLog(@"🎮 UI Ready!");
    });
}

%hook UIView

%new
- (void)invokeToggle:(UIButton *)sender { toggleHooks(sender); }

%new
- (void)invokeLogToggle:(UIButton *)sender { toggleLogView(sender); }

%new
- (void)invokeHookMethod:(UIButton *)sender {
    NSInteger index = sender.tag;
    if (index >= 0 && index < foundMethods.count) hookMethod(foundMethods[index]);
}

%new
- (void)invokeRescan:(UIButton *)sender { findIL2CPPMethods(); }

%new
- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *view = gesture.view;
    CGPoint translation = [gesture translationInView:view.superview];
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:view.superview];
}

%end

%ctor {
    addLog(@"🚀 Loading...");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        createUI();
        findIL2CPPMethods();
    });
}
