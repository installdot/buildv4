#import <UIKit/UIKit.h>
#import "IL2CPPEngine.hpp"

// Navigation States
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

// Data Sources
@property (nonatomic, assign) std::vector<IL2CPP::ClassDef> allClasses;
@property (nonatomic, assign) std::vector<IL2CPP::ClassDef> filteredClasses;
@property (nonatomic, assign) std::vector<IL2CPP::MethodDef> currentMethods;
@property (nonatomic, assign) std::vector<IL2CPP::FieldDef> currentFields;
@property (nonatomic, assign) std::vector<void*> currentInstances;

@property (nonatomic, assign) IL2CPP::ClassDef selectedClass;
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
        _titleLbl.text = @"IL2CPP Inspector";
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
        _searchBar.layer.cornerRadius = 5;
        _searchBar.delegate = self;
        [_searchBar addTarget:self action:@selector(searchChanged:) forControlEvents:UIControlEventEditingChanged];
        [self addSubview:_searchBar];

        _tableView = [[UITableView alloc] initWithFrame:CGRectMake(10, 90, frame.size.width - 20, frame.size.height - 100)];
        _tableView.backgroundColor = [UIColor clearColor];
        _tableView.delegate = self;
        _tableView.dataSource = self;
        _tableView.rowHeight = 40;
        [self addSubview:_tableView];
    }
    return self;
}

- (void)loadAllClasses {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        IL2CPP::thread_attach(IL2CPP::domain_get());
        self.allClasses = IL2CPP::GetAllClasses();
        self.filteredClasses = self.allClasses;
        dispatch_async(dispatch_get_main_queue(), ^{
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

// --- UITableView DataSource & Delegate ---
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (self.currentMode) {
        case ModeClassSearch: return self.filteredClasses.size();
        case ModeClassDetails: return 3; // Methods, Fields, Instances
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
        cell.textLabel.font = [UIFont systemFontOfSize:12];
        cell.textLabel.adjustsFontSizeToFitWidth = YES;
    }
    cell.detailTextLabel.text = @"";

    if (self.currentMode == ModeClassSearch) {
        cell.textLabel.text = [NSString stringWithUTF8String:self.filteredClasses[indexPath.row].fullName.c_str()];
    } 
    else if (self.currentMode == ModeClassDetails) {
        NSArray *opts = @[@"1. View Methods", @"2. View Fields", @"3. Find Active Instances"];
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
        
        // Read memory safely at offset
        int32_t val = 0;
        if (self.selectedInstance) val = *(int32_t*)((uintptr_t)self.selectedInstance + f.offset);
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Offset: 0x%zx | Value (Int32): %d", f.offset, val];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IL2CPP::thread_attach(IL2CPP::domain_get());

    if (self.currentMode == ModeClassSearch) {
        self.selectedClass = self.filteredClasses[indexPath.row];
        [self setMode:ModeClassDetails title:[NSString stringWithUTF8String:self.selectedClass.fullName.c_str()]];
    } 
    else if (self.currentMode == ModeClassDetails) {
        if (indexPath.row == 0) {
            self.currentMethods = IL2CPP::GetMethods(self.selectedClass.klass);
            [self setMode:ModeMethods title:@"Methods"];
        } else if (indexPath.row == 1) {
            self.currentFields = IL2CPP::GetFields(self.selectedClass.klass);
            [self setMode:ModeFields title:@"Fields"];
        } else if (indexPath.row == 2) {
            self.currentInstances = IL2CPP::FindInstances(self.selectedClass.klass);
            [self setMode:ModeInstances title:[NSString stringWithFormat:@"Found %zu Instances", self.currentInstances.size()]];
        }
    }
    else if (self.currentMode == ModeMethods) {
        auto m = self.currentMethods[indexPath.row];
        if (m.paramCount == 0) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Invoke Method?" message:[NSString stringWithUTF8String:m.name.c_str()] preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Invoke on NULL (Static)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                IL2CPP::runtime_invoke(m.method, nullptr, nullptr, nullptr);
            }]];
            if (self.selectedInstance) {
                [alert addAction:[UIAlertAction actionWithTitle:@"Invoke on Selected Instance" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    IL2CPP::runtime_invoke(m.method, self.selectedInstance, nullptr, nullptr);
                }]];
            }
            // Presenting alert from top window
            [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
        }
    }
    else if (self.currentMode == ModeInstances) {
        self.selectedInstance = self.currentInstances[indexPath.row];
        self.currentFields = IL2CPP::GetFields(self.selectedClass.klass);
        [self setMode:ModeInstanceInspector title:[NSString stringWithFormat:@"Inspecting: %p", self.selectedInstance]];
    }
}
@end


// ==========================================
// Floating Button logic
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
            if (menuView.allClasses.size() == 0) [menuView loadAllClasses]; // Load classes on first open
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
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SetupUI(); });
            return;
        }

        if (menuView) return; 

        menuView = [[InspectorUI alloc] initWithFrame:CGRectMake(20, 60, 320, 450)];
        menuView.hidden = YES;
        [window addSubview:menuView];

        FloatingIcon *floater = [FloatingIcon buttonWithType:UIButtonTypeCustom];
        floater.frame = CGRectMake(20, 100, 50, 50);
        floater.backgroundColor = [UIColor purpleColor];
        floater.layer.cornerRadius = 25;
        floater.layer.borderWidth = 2;
        floater.layer.borderColor = [UIColor whiteColor].CGColor;
        [floater setTitle:@"🔍" forState:UIControlStateNormal];
        [floater addTarget:floater action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [window addSubview:floater];
    });
}

// ==========================================
// Initialization Loop
// ==========================================
static void WaitForUnity() {
    while (!IL2CPP::Initialize() || IL2CPP::domain_get() == nullptr) {
        [NSThread sleepForTimeInterval:0.5];
    }
    IL2CPP::thread_attach(IL2CPP::domain_get());
    NSLog(@"[Inspector] Engine Initialized");
    SetupUI();
}

%ctor {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [NSThread sleepForTimeInterval:1.0];
        WaitForUnity();
    });
}
