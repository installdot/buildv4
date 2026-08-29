#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ==========================================
// 1. IL2CPP EXPORTS & STRUCTURES
// ==========================================
extern "C" {
    void* il2cpp_domain_get();
    void** il2cpp_domain_get_assemblies(const void* domain, size_t* size);
    void* il2cpp_assembly_get_image(const void* assembly);
    void* il2cpp_class_from_name(const void* image, const char* namespaze, const char* name);
    void* il2cpp_class_get_field_from_name(void* klass, const char* name);
    void* il2cpp_class_get_method_from_name(void* klass, const char* name, int argsCount);
    void* il2cpp_object_get_class(void* obj);
    void il2cpp_field_static_get_value(void* field, void* value);
    void il2cpp_field_get_value(void* obj, void* field, void* value);
    void il2cpp_field_set_value(void* obj, void* field, void* value);
    void* il2cpp_string_new(const char* str);
    void* il2cpp_class_get_type(void* klass);
    void* il2cpp_type_get_object(void* type);
    void* il2cpp_runtime_invoke(void* method, void* obj, void** params, void** exc);
}

// ==========================================
// 2. CONSTANTS & STATE VARIABLES
// ==========================================
static NSString * const API_URL = @"https://bweab.id.vn/iossave.php";
static NSString * const GLB_DISTRO = @"1e7d3ea8-a52c-4c63-9ced-ac384bba061d";
static NSString * const VN_DISTRO = @"06d16cad-861b-4a16-87b7-2f42337932ce";

static NSString *lastCloud = @"";
static NSString *lastEmail = @"";
static NSString *lastPass = @"";
static NSString *lastToken = @"";
static NSString *curDistro = @"GLB";
static NSString *statusMsg = @"Idle";
static NSString *uploadMsg = @"";
static NSString *apiMsg = @"";
static int batchN = 1;

// ==========================================
// 3. FILE SYSTEM & UTILITIES
// ==========================================
static void tryCopy(NSString *val) {
    if (val && val.length > 0) {
        [UIPasteboard generalPasteboard].string = val;
    }
}

static NSString* getSaveDir() {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths firstObject];
}

static BOOL appendLine(NSString *distro, NSString *email, NSString *pass) {
    NSString *fileName = [distro isEqualToString:@"VN"] ? @"vn.txt" : @"glb.txt";
    NSString *filePath = [getSaveDir() stringByAppendingPathComponent:fileName];
    
    NSString *line = [NSString stringWithFormat:@"%@|%@\n", email, pass];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:filePath]) {
        return [data writeToFile:filePath atomically:YES];
    } else {
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
        if (!fileHandle) return NO;
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:data];
        [fileHandle closeFile];
        return YES;
    }
}

static void clearFiles() {
    NSString *dir = getSaveDir();
    [[@"" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[dir stringByAppendingPathComponent:@"vn.txt"] atomically:YES];
    [[@"" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[dir stringByAppendingPathComponent:@"glb.txt"] atomically:YES];
}


// ==========================================
// 4. IL2CPP HELPER FUNCTIONS
// ==========================================
// Scans all loaded assemblies to find a class, equivalent to Lua's Class.fromName()
static void* FindClass(const char* namespaze, const char* name) {
    size_t size = 0;
    void** assemblies = il2cpp_domain_get_assemblies(il2cpp_domain_get(), &size);
    for(size_t i = 0; i < size; i++) {
        void* image = il2cpp_assembly_get_image(assemblies[i]);
        if (!image) continue;
        void* klass = il2cpp_class_from_name(image, namespaze, name);
        if (klass) return klass;
    }
    return nullptr;
}

// Replicates Lua's myClass:findObjects()[1]
static void* FindUnityObjectOfType(void* targetKlass) {
    if (!targetKlass) return nullptr;
    
    void* objKlass = FindClass("UnityEngine", "Object");
    if (!objKlass) return nullptr;
    
    void* findMethod = il2cpp_class_get_method_from_name(objKlass, "FindObjectOfType", 1);
    if (!findMethod) return nullptr;
    
    void* typeObj = il2cpp_type_get_object(il2cpp_class_get_type(targetKlass));
    void* args[1] = { typeObj };
    void* exc = nullptr;
    
    return il2cpp_runtime_invoke(findMethod, nullptr, args, &exc);
}


// ==========================================
// 5. API & GAME LOGIC
// ==========================================
@interface LogicManager : NSObject
+ (void)fetchAPIWithCompletion:(void(^)(BOOL success))completion;
+ (void)runDoOneTask:(void(^)(void))completion;
+ (void)runBatch:(int)count;
@end

@implementation LogicManager

+ (void)fetchAPIWithCompletion:(void(^)(BOOL success))completion {
    statusMsg = @"Fetching API...";
    NSURL *url = [NSURL URLWithString:API_URL];
    
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                apiMsg = @"Network Error";
                statusMsg = @"Fetch Failed";
                if (completion) completion(NO);
            });
            return;
        }
        
        NSString *respStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSError *jsonErr;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            apiMsg = respStr;
            if (!jsonErr && json) {
                lastEmail = json[@"Email"] ?: @"";
                lastPass = json[@"Pass"] ?: @"";
                lastToken = json[@"Token"] ?: @"";
                lastCloud = json[@"CloudID"] ?: @"";
                statusMsg = @"Fetched";
                if (completion) completion(YES);
            } else {
                statusMsg = @"JSON Parse Error";
                if (completion) completion(NO);
            }
        });
    }] resume];
}

+ (BOOL)applyIl2cppLogic {
    @try {
        NSString *distrID = [curDistro isEqualToString:@"VN"] ? VN_DISTRO : GLB_DISTRO;
        void *savingDataObj = nullptr;
        
        // --- 1. NewCloudSaveAgent Logic ---
        void* agentKlass = FindClass("RGScript.Other", "NewCloudSaveAgent");
        if (agentKlass) {
            void* savingDataField = il2cpp_class_get_field_from_name(agentKlass, "savingData");
            if (savingDataField) {
                il2cpp_field_static_get_value(savingDataField, &savingDataObj);
            }
            
            if (savingDataObj) {
                void* dataKlass = il2cpp_object_get_class(savingDataObj);
                
                void* cloudIdField = il2cpp_class_get_field_from_name(dataKlass, "cloudSaveId");
                void* cloudStr = il2cpp_string_new([lastCloud UTF8String]);
                il2cpp_field_set_value(savingDataObj, cloudIdField, cloudStr);
                
                void* platformIdField = il2cpp_class_get_field_from_name(dataKlass, "platformId");
                void* platStr = il2cpp_string_new([distrID UTF8String]);
                il2cpp_field_set_value(savingDataObj, platformIdField, platStr);
            } else {
                NSLog(@"[ModMenu] savingData object is null!");
                return NO;
            }
        }
        
        // --- 2. setBearer Logic ---
        void* blobClientKlass = FindClass("ChillyRoom.SoulKnight.BlobSaveService.V1", "BlobSaveClient");
        void* blobInst = FindUnityObjectOfType(blobClientKlass);
        if (blobInst) {
            void* httpClientField = il2cpp_class_get_field_from_name(blobClientKlass, "_httpClient");
            void* httpClientObj = nullptr;
            il2cpp_field_get_value(blobInst, httpClientField, &httpClientObj);
            
            if (httpClientObj) {
                void* httpKlass = FindClass("System.Net.Http", "HttpClient");
                void* getHeadersMethod = il2cpp_class_get_method_from_name(httpKlass, "get_DefaultRequestHeaders", 0);
                void* exc = nullptr;
                void* headersObj = il2cpp_runtime_invoke(getHeadersMethod, httpClientObj, nullptr, &exc);
                
                if (headersObj) {
                    void* headersBaseKlass = FindClass("System.Net.Http.Headers", "HttpHeaders");
                    
                    // Remove("Authorization")
                    void* removeMethod = il2cpp_class_get_method_from_name(headersBaseKlass, "Remove", 1);
                    void* authStr = il2cpp_string_new("Authorization");
                    void* args1[1] = { authStr };
                    il2cpp_runtime_invoke(removeMethod, headersObj, args1, &exc);
                    
                    // TryAddWithoutValidation("Authorization", "Bearer " + tok)
                    void* addMethod = il2cpp_class_get_method_from_name(headersBaseKlass, "TryAddWithoutValidation", 2);
                    NSString *bearerVal = [NSString stringWithFormat:@"Bearer %@", lastToken];
                    void* bearerStr = il2cpp_string_new([bearerVal UTF8String]);
                    void* args2[2] = { authStr, bearerStr };
                    il2cpp_runtime_invoke(addMethod, headersObj, args2, &exc);
                }
            }
        } else {
            NSLog(@"[ModMenu] BlobSaveClient instance not found!");
            return NO;
        }

        // --- 3. CloudSaveRunner Logic ---
        void* runnerKlass = FindClass("RGScript.Other.CloudSave", "CloudSaveRunner");
        void* runnerInst = FindUnityObjectOfType(runnerKlass);
        if (runnerInst && savingDataObj) {
            void* uploadMethod = il2cpp_class_get_method_from_name(runnerKlass, "DoUploadByBlobSave", 2);
            bool isAuto = false;
            void* exc = nullptr;
            void* args[2] = { savingDataObj, &isAuto }; // Value types (bool) are passed as pointers
            
            il2cpp_runtime_invoke(uploadMethod, runnerInst, args, &exc);
            if (exc) {
                NSLog(@"[ModMenu] DoUploadByBlobSave Threw Exception!");
                return NO;
            }
        } else {
            NSLog(@"[ModMenu] CloudSaveRunner not found!");
            return NO;
        }
        
        return YES;
    } @catch (NSException *e) {
        NSLog(@"[ModMenu] IL2CPP Exception: %@", e.reason);
        return NO;
    }
}

+ (void)runDoOneTask:(void(^)(void))completion {
    [self fetchAPIWithCompletion:^(BOOL success) {
        if (!success || lastCloud.length == 0 || lastToken.length == 0) {
            uploadMsg = @"ERR: no API data";
            if (completion) completion();
            return;
        }
        
        // 1. Inject into Game (Unity)
        BOOL il2cppSuccess = [self applyIl2cppLogic];
        
        // 2. Save to text file
        BOOL savedFile = appendLine(curDistro, lastEmail, lastPass);
        
        // 3. Update Status
        if (il2cppSuccess && savedFile) {
            uploadMsg = [NSString stringWithFormat:@"OK cloud=%@ file=%@.txt saved=1", lastCloud, [curDistro lowercaseString]];
        } else {
            uploadMsg = [NSString stringWithFormat:@"ERR: il2cpp=%d, saved=%d", il2cppSuccess, savedFile];
        }
        
        statusMsg = @"Task Complete";
        if (completion) completion();
    }];
}

+ (void)runBatch:(int)count {
    if (count <= 0) return;
    
    [self runDoOneTask:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self runBatch:count - 1];
        });
    }];
}
@end


// ==========================================
// 6. MOD MENU UI (NATIVE UIKit)
// ==========================================
@interface ModMenuManager : NSObject
@property (nonatomic, strong) UIWindow *menuWindow;
@property (nonatomic, strong) UIView *menuView;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *batchLabel;
@property (nonatomic, strong) NSTimer *loopTimer;
@property (nonatomic, strong) UIButton *btnGLB;
@property (nonatomic, strong) UIButton *btnVN;
+ (instancetype)sharedInstance;
@end

@implementation ModMenuManager

+ (instancetype)sharedInstance {
    static ModMenuManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[ModMenuManager alloc] init]; });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self setupUI];
        });
    }
    return self;
}

- (void)setupUI {
    self.menuWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.menuWindow.windowLevel = UIWindowLevelStatusBar + 100;
    self.menuWindow.hidden = NO;
    self.menuWindow.backgroundColor = [UIColor clearColor];
    
    UIViewController *rootVC = [[UIViewController alloc] init];
    self.menuWindow.rootViewController = rootVC;

    // Toggle Button
    UIButton *toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    toggleBtn.frame = CGRectMake(20, 50, 50, 50);
    toggleBtn.backgroundColor = [UIColor systemBlueColor];
    toggleBtn.layer.cornerRadius = 25;
    [toggleBtn setTitle:@"MENU" forState:UIControlStateNormal];
    [toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [toggleBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [rootVC.view addSubview:toggleBtn];
    [toggleBtn addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragView:)]];

    // Main Menu
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(20, 110, 320, 480)];
    self.menuView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.9];
    self.menuView.layer.cornerRadius = 10;
    self.menuView.hidden = YES;
    [rootVC.view addSubview:self.menuView];
    [self.menuView addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragView:)]];
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 320, 30)];
    title.text = @"Cloud Save -> vn.txt / glb.txt";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:16];
    [self.menuView addSubview:title];

    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(10, 50, 300, 420)];
    [self.menuView addSubview:self.scrollView];

    CGFloat y = 0;
    
    // Distro Selector
    UILabel *distroLbl = [[UILabel alloc] initWithFrame:CGRectMake(0, y, 80, 30)];
    distroLbl.text = @"Distro:";
    distroLbl.textColor = [UIColor whiteColor];
    [self.scrollView addSubview:distroLbl];
    
    self.btnGLB = [self makeBtn:@"GLB" frame:CGRectMake(80, y, 60, 30) action:@selector(setGLB)];
    self.btnVN = [self makeBtn:@"VN" frame:CGRectMake(150, y, 60, 30) action:@selector(setVN)];
    [self.scrollView addSubview:self.btnGLB];
    [self.scrollView addSubview:self.btnVN];
    [self refreshDistroBtns];
    y += 40;

    // Info Rows
    void (^addRow)(NSString*, SEL) = ^(NSString *labelPrefix, SEL action) {
        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(0, y, 200, 30)];
        lbl.textColor = [UIColor lightGrayColor];
        lbl.font = [UIFont systemFontOfSize:11];
        lbl.tag = y; 
        [self.scrollView addSubview:lbl];
        
        UIButton *btn = [self makeBtn:@"Copy" frame:CGRectMake(210, y, 80, 30) action:action];
        [self.scrollView addSubview:btn];
        y += 40;
    };

    addRow(@"CloudID", @selector(cpCloud));
    addRow(@"Email", @selector(cpEmail));
    addRow(@"Pass", @selector(cpPass));
    addRow(@"Token", @selector(cpToken));

    // Action Buttons
    UIButton *fetchBtn = [self makeBtn:@"Fetch API" frame:CGRectMake(0, y, 290, 35) action:@selector(actionFetch)];
    [self.scrollView addSubview:fetchBtn]; y += 45;
    
    UIButton *createBtn = [self makeBtn:@"Create x1" frame:CGRectMake(0, y, 290, 35) action:@selector(actionOne)];
    [self.scrollView addSubview:createBtn]; y += 45;
    
    // Batch Controls
    UISwitch *loopSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(0, y, 50, 30)];
    [loopSwitch addTarget:self action:@selector(toggleLoop:) forControlEvents:UIControlEventValueChanged];
    [self.scrollView addSubview:loopSwitch];
    
    UILabel *loopLbl = [[UILabel alloc] initWithFrame:CGRectMake(60, y, 100, 30)];
    loopLbl.text = @"Loop (2.5s)";
    loopLbl.textColor = [UIColor whiteColor];
    [self.scrollView addSubview:loopLbl];
    y += 40;

    self.batchLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, y, 100, 30)];
    self.batchLabel.text = @"Batch: 1";
    self.batchLabel.textColor = [UIColor whiteColor];
    [self.scrollView addSubview:self.batchLabel];
    
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(100, y, 190, 30)];
    slider.minimumValue = 1; slider.maximumValue = 30;
    [slider addTarget:self action:@selector(sliderChange:) forControlEvents:UIControlEventValueChanged];
    [self.scrollView addSubview:slider]; y += 40;

    UIButton *batchBtn = [self makeBtn:@"Create Batch" frame:CGRectMake(0, y, 290, 35) action:@selector(actionBatch)];
    [self.scrollView addSubview:batchBtn]; y += 45;

    UIButton *clearBtn = [self makeBtn:@"Clear vn.txt & glb.txt" frame:CGRectMake(0, y, 290, 35) action:@selector(actionClear)];
    clearBtn.backgroundColor = [UIColor systemRedColor];
    [self.scrollView addSubview:clearBtn]; y += 45;

    // Status Label
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, y, 290, 100)];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textColor = [UIColor greenColor];
    self.statusLabel.font = [UIFont systemFontOfSize:11];
    [self updateUI];
    [self.scrollView addSubview:self.statusLabel];
    
    self.scrollView.contentSize = CGSizeMake(300, y + 120);
    
    [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [self updateUI];
    }];
}

- (UIButton *)makeBtn:(NSString *)title frame:(CGRect)rect action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = rect;
    btn.backgroundColor = [UIColor darkGrayColor];
    btn.layer.cornerRadius = 5;
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)dragView:(UIPanGestureRecognizer *)gesture {
    UIView *target = gesture.view;
    CGPoint trans = [gesture translationInView:target.superview];
    target.center = CGPointMake(target.center.x + trans.x, target.center.y + trans.y);
    [gesture setTranslation:CGPointZero inView:target.superview];
}

- (void)toggleMenu { self.menuView.hidden = !self.menuView.hidden; }
- (void)setGLB { curDistro = @"GLB"; [self refreshDistroBtns]; }
- (void)setVN { curDistro = @"VN"; [self refreshDistroBtns]; }
- (void)refreshDistroBtns {
    self.btnGLB.backgroundColor = [curDistro isEqualToString:@"GLB"] ? [UIColor systemBlueColor] : [UIColor darkGrayColor];
    self.btnVN.backgroundColor = [curDistro isEqualToString:@"VN"] ? [UIColor systemBlueColor] : [UIColor darkGrayColor];
}
- (void)cpCloud { tryCopy(lastCloud); }
- (void)cpEmail { tryCopy(lastEmail); }
- (void)cpPass { tryCopy(lastPass); }
- (void)cpToken { tryCopy(lastToken); }

- (void)actionFetch { [LogicManager fetchAPIWithCompletion:nil]; }
- (void)actionOne { [LogicManager runDoOneTask:nil]; }
- (void)actionBatch { [LogicManager runBatch:batchN]; }
- (void)actionClear { clearFiles(); statusMsg = @"Files Cleared"; [self updateUI]; }

- (void)sliderChange:(UISlider *)sender {
    batchN = (int)round(sender.value);
    self.batchLabel.text = [NSString stringWithFormat:@"Batch: %d", batchN];
}

- (void)toggleLoop:(UISwitch *)sender {
    if (sender.isOn) {
        self.loopTimer = [NSTimer scheduledTimerWithTimeInterval:2.5 repeats:YES block:^(NSTimer * _Nonnull timer) {
            [self actionOne];
        }];
    } else {
        [self.loopTimer invalidate];
        self.loopTimer = nil;
    }
}

- (void)updateUI {
    for (UIView *view in self.scrollView.subviews) {
        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)view;
            if (lbl.tag == 40) lbl.text = [NSString stringWithFormat:@"CloudID: %@", lastCloud];
            if (lbl.tag == 80) lbl.text = [NSString stringWithFormat:@"Email: %@", lastEmail];
            if (lbl.tag == 120) lbl.text = [NSString stringWithFormat:@"Pass: %@", lastPass];
            if (lbl.tag == 160) lbl.text = [NSString stringWithFormat:@"Token: %@", lastToken];
        }
    }
    
    NSString *shortApi = apiMsg.length > 70 ? [[apiMsg substringToIndex:70] stringByAppendingString:@"..."] : apiMsg;
    self.statusLabel.text = [NSString stringWithFormat:@"Status: %@\nLast: %@\nAPI: %@\nDir: %@", 
                             statusMsg, uploadMsg, shortApi, getSaveDir()];
}
@end

// ==========================================
// 7. INJECTION POINT
// ==========================================
%ctor {
    NSLog(@"[CloudSaveMod] Loaded Native Mod Menu!");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [ModMenuManager sharedInstance];
    });
}
