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

// IL2CPP field access
typedef void* (*il2cpp_class_get_field_from_name_t)(void* klass, const char* name);
typedef void (*il2cpp_field_static_get_value_t)(void* field, void** out);

// Forward declaration
static void updateMethodList(void);

// Method info
@interface MethodInfo : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, assign) void *address;
@end
@implementation MethodInfo @end

// Globals
static NSMutableArray<MethodInfo*> *foundMethods = nil;
static UITextView *logView = nil;
static UIScrollView *methodListView = nil;
static NSMutableArray *logMessages = nil;
static UIButton *rescanButton = nil;
static UIButton *hideMethodListButton = nil;
static UIButton *hideLogButton = nil;

static void* battlePassMethod = NULL;
static void* battlePassClass = NULL;
static void* battlePassInstance = NULL;

#pragma mark - Logging
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
            NSMutableString *text = [NSMutableString string];
            [text appendFormat:@"🎮 BattlePass Tweak\n"];
            [text appendFormat:@"📊 Total methods: %lu\n\n", (unsigned long)foundMethods.count];
            [text appendString:[logMessages componentsJoinedByString:@"\n"]];
            logView.text = text;
            [logView scrollRangeToVisible:NSMakeRange(logView.text.length-1,1)];
        }
    });
}

#pragma mark - Fetch Instance
static void fetchBattlePassInstance(void) {
    if (!battlePassClass) { addLog(@"❌ Cannot fetch instance, class not found"); return; }

    il2cpp_class_get_field_from_name_t il2cpp_class_get_field_from_name = 
        (il2cpp_class_get_field_from_name_t)dlsym(RTLD_DEFAULT, "il2cpp_class_get_field_from_name");
    il2cpp_field_static_get_value_t il2cpp_field_static_get_value = 
        (il2cpp_field_static_get_value_t)dlsym(RTLD_DEFAULT, "il2cpp_field_static_get_value");

    if (!il2cpp_class_get_field_from_name || !il2cpp_field_static_get_value) {
        addLog(@"❌ IL2CPP field functions not found"); return;
    }

    void* instanceField = il2cpp_class_get_field_from_name(battlePassClass, "Instance");
    if (!instanceField) { addLog(@"❌ BattlePassData.Instance not found"); return; }

    void* instance = NULL;
    il2cpp_field_static_get_value(instanceField, &instance);
    if (instance) {
        battlePassInstance = instance;
        addLog(@"✅ BattlePassData instance fetched automatically!");
    } else {
        addLog(@"❌ Failed to fetch BattlePassData instance");
    }
}

#pragma mark - Call method
static void callTryUnlockExample() {
    if (!battlePassMethod || !battlePassInstance) {
        addLog(@"❌ Method or instance not found!");
        return;
    }

    int bpld = 1;
    int count = 1;
    NSString* source = @"true";

    bool (*methodPtr)(void*, int, int, void*) = (bool (*)(void*, int, int, void*))battlePassMethod;
    bool result = methodPtr(battlePassInstance, bpld, count, (__bridge void*)source);

    addLog([NSString stringWithFormat:@"📞 Called TryUnlockAdvancedBattlePass(bpld:%d, count:%d, source:%@) -> %@", bpld, count, source, result ? @"TRUE" : @"FALSE"]);
}

#pragma mark - Find method
static void findTryUnlockMethod() {
    addLog(@"🔍 Searching for TryUnlockAdvancedBattlePass...");

    foundMethods = [NSMutableArray new];
    battlePassMethod = NULL;
    battlePassClass = NULL;
    battlePassInstance = NULL;

    void* handle = dlopen(NULL, RTLD_LAZY);
    if (!handle) { addLog(@"❌ IL2CPP handle failed"); return; }

    il2cpp_domain_get_t il2cpp_domain_get = (il2cpp_domain_get_t)dlsym(handle, "il2cpp_domain_get");
    il2cpp_domain_get_assemblies_t il2cpp_domain_get_assemblies = (il2cpp_domain_get_assemblies_t)dlsym(handle, "il2cpp_domain_get_assemblies");
    il2cpp_assembly_get_image_t il2cpp_assembly_get_image = (il2cpp_assembly_get_image_t)dlsym(handle, "il2cpp_assembly_get_image");
    il2cpp_class_from_name_t il2cpp_class_from_name = (il2cpp_class_from_name_t)dlsym(handle, "il2cpp_class_from_name");
    il2cpp_class_get_methods_t il2cpp_class_get_methods = (il2cpp_class_get_methods_t)dlsym(handle, "il2cpp_class_get_methods");
    il2cpp_method_get_name_t il2cpp_method_get_name = (il2cpp_method_get_name_t)dlsym(handle, "il2cpp_method_get_name");

    if (!il2cpp_domain_get || !il2cpp_domain_get_assemblies || !il2cpp_assembly_get_image || !il2cpp_class_from_name || !il2cpp_class_get_methods || !il2cpp_method_get_name) {
        addLog(@"❌ IL2CPP functions failed"); return;
    }

    void* domain = il2cpp_domain_get();
    size_t assemblyCount = 0;
    void** assemblies = (void**)il2cpp_domain_get_assemblies(domain, &assemblyCount);

    for (size_t i=0;i<assemblyCount;i++) {
        void* image = il2cpp_assembly_get_image(assemblies[i]);
        void* klass = il2cpp_class_from_name(image, "RGScript.Data", "BattlePassData");
        if (!klass) continue;

        battlePassClass = klass;

        void* iter = NULL;
        void* method;
        while ((method = il2cpp_class_get_methods(klass, &iter))) {
            const char* name = il2cpp_method_get_name(method);
            if (name && strcmp(name, "TryUnlockAdvancedBattlePass")==0) {
                MethodInfo *info = [MethodInfo new];
                info.name = [NSString stringWithUTF8String:name];
                info.address = method;
                [foundMethods addObject:info];
                battlePassMethod = method;
                addLog(@"✅ Found TryUnlockAdvancedBattlePass!");
                break;
            }
        }
        if (battlePassMethod) break;
    }

    addLog([NSString stringWithFormat:@"📊 Total methods found: %lu", (unsigned long)foundMethods.count]);

    fetchBattlePassInstance();
    updateMethodList();
}

#pragma mark - Update UI
static void updateMethodList() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!methodListView) return;
        for (UIView *v in methodListView.subviews) [v removeFromSuperview];

        CGFloat y = 10;
        CGFloat containerHeight = 40;
        for (int i=0;i<foundMethods.count;i++) {
            MethodInfo *m = foundMethods[i];
            UIView *container = [[UIView alloc] initWithFrame:CGRectMake(5,y,methodListView.frame.size.width-10,containerHeight)];
            container.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.95];
            container.layer.cornerRadius = 5;

            UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(10,0,container.frame.size.width-20,20)];
            nameLabel.text = [NSString stringWithFormat:@"%@\nAddr:0x%lx", m.name, (unsigned long)m.address];
            nameLabel.textColor = [UIColor colorWithRed:0.3 green:1 blue:0.3 alpha:1];
            nameLabel.font = [UIFont systemFontOfSize:10];
            nameLabel.numberOfLines = 2;
            [container addSubview:nameLabel];

            UIButton *callBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            callBtn.frame = CGRectMake(10,20,container.frame.size.width-20,18);
            [callBtn setTitle:@"▶ Call" forState:UIControlStateNormal];
            callBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.8 alpha:0.9];
            callBtn.layer.cornerRadius = 3;
            [callBtn addTarget:nil action:@selector(invokeCallTryUnlock:) forControlEvents:UIControlEventTouchUpInside];
            [container addSubview:callBtn];

            [methodListView addSubview:container];
            y += containerHeight + 5;
        }
        methodListView.contentSize = CGSizeMake(methodListView.frame.size.width, y);
    });
}

#pragma mark - Create UI
static void createUI() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *window in scene.windows) {
                        if (window.isKeyWindow) { keyWindow = window; break; }
                    }
                    if (keyWindow) break;
                }
            }
        } else {
            keyWindow = [UIApplication sharedApplication].keyWindow;
        }
        if (!keyWindow) return;

        CGFloat screenWidth = keyWindow.bounds.size.width;
        CGFloat boxWidth = (screenWidth-30)/2;

        methodListView = [[UIScrollView alloc] initWithFrame:CGRectMake(10,100,boxWidth,150)];
        methodListView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.95];
        methodListView.layer.cornerRadius = 5;
        [keyWindow addSubview:methodListView];

        logView = [[UITextView alloc] initWithFrame:CGRectMake(10,260,boxWidth,150)];
        logView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.95];
        logView.textColor = [UIColor colorWithRed:0.3 green:1 blue:0.3 alpha:1];
        logView.font = [UIFont fontWithName:@"Menlo" size:8];
        logView.editable = NO;
        logView.layer.cornerRadius = 5;
        [keyWindow addSubview:logView];

        // Hide buttons
        hideMethodListButton = [UIButton buttonWithType:UIButtonTypeSystem];
        hideMethodListButton.frame = CGRectMake(10,60,60,30);
        [hideMethodListButton setTitle:@"Hide List" forState:UIControlStateNormal];
        hideMethodListButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.3 blue:0.3 alpha:0.9];
        hideMethodListButton.layer.cornerRadius = 5;
        [hideMethodListButton addTarget:nil action:@selector(invokeHideMethodList:) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:hideMethodListButton];

        hideLogButton = [UIButton buttonWithType:UIButtonTypeSystem];
        hideLogButton.frame = CGRectMake(80,60,60,30);
        [hideLogButton setTitle:@"Hide Log" forState:UIControlStateNormal];
        hideLogButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.8 alpha:0.9];
        hideLogButton.layer.cornerRadius = 5;
        [hideLogButton addTarget:nil action:@selector(invokeHideLog:) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:hideLogButton];

        rescanButton = [UIButton buttonWithType:UIButtonTypeSystem];
        rescanButton.frame = CGRectMake(150,60,60,30);
        [rescanButton setTitle:@"Rescan" forState:UIControlStateNormal];
        rescanButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.5 blue:0.2 alpha:0.9];
        rescanButton.layer.cornerRadius = 5;
        [rescanButton addTarget:nil action:@selector(invokeRescan:) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:rescanButton];

        // Draggable
        for (UIView *v in @[methodListView, logView, hideMethodListButton, hideLogButton, rescanButton]) {
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(handlePan:)];
            [v addGestureRecognizer:pan];
        }

        addLog(@"🎮 UI Ready!");
    });
}

#pragma mark - UIView hooks
%hook UIView
%new
- (void)invokeCallTryUnlock:(UIButton*)sender { callTryUnlockExample(); }
%new
- (void)invokeRescan:(UIButton*)sender { findTryUnlockMethod(); }
%new
- (void)invokeHideMethodList:(UIButton*)sender { methodListView.hidden = !methodListView.hidden; }
%new
- (void)invokeHideLog:(UIButton*)sender { logView.hidden = !logView.hidden; }
%new
- (void)handlePan:(UIPanGestureRecognizer*)gesture {
    UIView *view = gesture.view;
    CGPoint t = [gesture translationInView:view.superview];
    view.center = CGPointMake(view.center.x+t.x, view.center.y+t.y);
    [gesture setTranslation:CGPointZero inView:view.superview];
}
%end

%ctor {
    addLog(@"🚀 Loading...");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        createUI();
        findTryUnlockMethod();
    });
}
