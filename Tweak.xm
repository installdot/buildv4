// DebugMenu.xm - Full Code

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ===================== Persistent Settings =====================

static NSString * const kDebugPrefsPath = @"/var/mobile/Library/Preferences/com.unitoreios.debug.plist";

static void DebugWritePref(NSString *key, id value) {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:kDebugPrefsPath]
                                 ?: [NSMutableDictionary new];
    if (value) prefs[key] = value;
    else [prefs removeObjectForKey:key];
    [prefs writeToFile:kDebugPrefsPath atomically:YES];
}

static id DebugReadPref(NSString *key) {
    return [NSDictionary dictionaryWithContentsOfFile:kDebugPrefsPath][key];
}

static BOOL IsForceOfflineEnabled(void) {
    return [DebugReadPref(@"ForceOffline") boolValue];
}

// ===================== Runtime Access =====================

extern NSString *keyValidationStatus;
extern NSString *iskey;
extern NSString *encodedcode;
extern NSString *encodestring;

@interface Unitoreios (DebugAccess)
@property (nonatomic, assign) NSInteger remainingSeconds;
+ (NSString *)getCurrentKey;
+ (NSString *)getRemainingTime;
- (BOOL)canUseCachedSession;
- (BOOL)isNetworkAvailable;
- (BOOL)hasStrictValidatedKeySession;
@end

static Unitoreios *GetExtraInfo(void) {
    return (Unitoreios *)[NSClassFromString(@"Unitoreios") valueForKey:@"extraInfo"];
}

// ===================== Session Item Model =====================

typedef NS_ENUM(NSInteger, SessionItemType) {
    SessionItemTypeUserDefaults,
    SessionItemTypeUnitoreiosPref,
    SessionItemTypeRuntime,
};

@interface SessionItem : NSObject
@property (nonatomic, strong) NSString *key;
@property (nonatomic, strong) NSString *value;
@property (nonatomic, strong) NSString *displaySource;
@property (nonatomic, assign) SessionItemType type;
@end

@implementation SessionItem
@end

// ===================== Forward Declarations =====================

@interface UnitoreiosDebugMenuVC : UIViewController
+ (void)presentFromTop;
@end

// ===================== Session Editor VC =====================

@interface UnitoreiosSessionEditorVC : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<SessionItem *> *items;
@property (nonatomic, strong) NSTimer *refreshTimer;
@end

@implementation UnitoreiosSessionEditorVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"✏️ Session Editor";
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:1.0];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Reload" style:UIBarButtonItemStylePlain
               target:self action:@selector(loadItems)];
    self.navigationItem.rightBarButtonItem.tintColor =
        [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleInsetGrouped];
    self.tableView.delegate   = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:1.0];
    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];

    [self loadItems];

    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
        target:self selector:@selector(refreshRuntimeValues) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

- (void)loadItems {
    self.items = [NSMutableArray new];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    // --- NSUserDefaults ---
    NSDictionary *udMap = @{
        @"savedKey":  @"Key đã lưu trên máy",
        @"savedUDID": @"UDID đã bind",
    };
    for (NSString *k in udMap) {
        SessionItem *item  = [SessionItem new];
        item.key           = k;
        item.value         = [ud objectForKey:k] ?: @"(nil)";
        item.displaySource = [NSString stringWithFormat:@"NSUserDefaults · %@", udMap[k]];
        item.type          = SessionItemTypeUserDefaults;
        [self.items addObject:item];
    }

    // --- com.unitoreios.key plist ---
    NSArray *prefPairs = @[
        @[@"BaseURL",     @"Base URL server"],
        @[@"DebHash",     @"Hash package"],
        @[@"PackageName", @"Tên package"],
        @[@"ReturnURL",   @"Return URL (UDID landing)"],
    ];
    for (NSArray *pair in prefPairs) {
        NSString *k = pair[0];
        CFPropertyListRef ref = CFPreferencesCopyAppValue(
            (__bridge CFStringRef)k, CFSTR("com.unitoreios.key"));
        SessionItem *item  = [SessionItem new];
        item.key           = k;
        item.value         = ref ? (__bridge_transfer NSString *)ref : @"(nil)";
        item.displaySource = [NSString stringWithFormat:@"com.unitoreios.key · %@", pair[1]];
        item.type          = SessionItemTypeUnitoreiosPref;
        [self.items addObject:item];
    }

    // --- Runtime RAM ---
    Unitoreios *extra = GetExtraInfo();
    NSArray *rtItems = @[
        @{@"key": @"remainingSeconds",    @"desc": @"⏱ Giây còn lại (đếm ngược)"},
        @{@"key": @"keyValidationStatus", @"desc": @"🔑 Trạng thái xác thực"},
        @{@"key": @"iskey",               @"desc": @"🗝 Key đang active (RAM)"},
        @{@"key": @"encodedcode",         @"desc": @"🔐 Encoded integrity code"},
    ];
    for (NSDictionary *d in rtItems) {
        NSString *k = d[@"key"];
        NSString *val;
        if ([k isEqualToString:@"remainingSeconds"])
            val = [NSString stringWithFormat:@"%ld", (long)extra.remainingSeconds];
        else if ([k isEqualToString:@"keyValidationStatus"])
            val = keyValidationStatus ?: @"(nil)";
        else if ([k isEqualToString:@"iskey"])
            val = iskey ?: @"(nil)";
        else if ([k isEqualToString:@"encodedcode"])
            val = encodedcode ?: @"(nil)";

        SessionItem *item  = [SessionItem new];
        item.key           = k;
        item.value         = val;
        item.displaySource = [NSString stringWithFormat:@"Runtime (RAM) · %@", d[@"desc"]];
        item.type          = SessionItemTypeRuntime;
        [self.items addObject:item];
    }

    [self.tableView reloadData];
}

- (void)refreshRuntimeValues {
    Unitoreios *extra = GetExtraInfo();
    NSDictionary *rtNow = @{
        @"remainingSeconds":    [NSString stringWithFormat:@"%ld", (long)extra.remainingSeconds],
        @"keyValidationStatus": keyValidationStatus ?: @"(nil)",
        @"iskey":               iskey ?: @"(nil)",
        @"encodedcode":         encodedcode ?: @"(nil)",
    };
    for (NSInteger i = 0; i < (NSInteger)self.items.count; i++) {
        SessionItem *item = self.items[i];
        if (item.type != SessionItemTypeRuntime) continue;
        NSString *newVal = rtNow[item.key];
        if (newVal && ![item.value isEqualToString:newVal]) {
            item.value = newVal;
            [self.tableView reloadRowsAtIndexPaths:
                @[[NSIndexPath indexPathForRow:i inSection:0]]
                                 withRowAnimation:UITableViewRowAnimationNone];
        }
    }
}

// ===================== TableView =====================

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.items.count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @"Tap = Edit  ·  Swipe trái = Copy / Xóa";
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    return 64;
}

- (UITableViewCell *)tableView:(UITableView *)tv
         cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"sCell"];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"sCell"];

    SessionItem *item = self.items[ip.row];
    cell.textLabel.text = item.key;
    cell.textLabel.font = [UIFont fontWithName:@"Menlo" size:13];
    cell.textLabel.textColor = [self colorForType:item.type];

    // Hiển thị thời gian đẹp nếu là remainingSeconds
    NSString *displayVal = item.value;
    if ([item.key isEqualToString:@"remainingSeconds"]) {
        NSInteger s = [item.value integerValue];
        displayVal = [NSString stringWithFormat:@"%ld  (%ldng %ldg %ldp %lds)",
            (long)s, (long)(s/86400), (long)((s%86400)/3600),
            (long)((s%3600)/60), (long)(s%60)];
    }

    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@",
        displayVal, item.displaySource];
    cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:10];
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    cell.detailTextLabel.numberOfLines = 2;

    switch (item.type) {
        case SessionItemTypeRuntime:
            cell.backgroundColor = [UIColor colorWithRed:0.13 green:0.10 blue:0.05 alpha:1.0];
            break;
        case SessionItemTypeUnitoreiosPref:
            cell.backgroundColor = [UIColor colorWithRed:0.08 green:0.11 blue:0.17 alpha:1.0];
            break;
        default:
            cell.backgroundColor = [UIColor colorWithRed:0.11 green:0.14 blue:0.18 alpha:1.0];
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UIColor *)colorForType:(SessionItemType)type {
    switch (type) {
        case SessionItemTypeUserDefaults:   return [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
        case SessionItemTypeUnitoreiosPref: return [UIColor colorWithRed:0.40 green:0.65 blue:1.00 alpha:1.0];
        case SessionItemTypeRuntime:        return [UIColor systemOrangeColor];
    }
}

// ===================== Edit (Tap) =====================

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [self showEditAlertForItem:self.items[ip.row] atIndex:ip.row];
}

- (void)showEditAlertForItem:(SessionItem *)item atIndex:(NSInteger)idx {
    NSString *typeStr = @[@"NSUserDefaults", @"Plist", @"Runtime"][item.type];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"✏️ %@", item.key]
        message:[NSString stringWithFormat:@"[%@] %@", typeStr, item.displaySource]
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = [item.value isEqualToString:@"(nil)"] ? @"" : item.value;
        tf.font = [UIFont fontWithName:@"Menlo" size:13];
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        tf.placeholder = @"Nhập giá trị mới...";

        // Hint cho remainingSeconds
        if ([item.key isEqualToString:@"remainingSeconds"])
            tf.placeholder = @"Số giây (vd: 86400 = 1 ngày)";
    }];

    UIAlertAction *save = [UIAlertAction actionWithTitle:@"💾 Lưu"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *val = alert.textFields.firstObject.text ?: @"";
        [self writeItem:item newValue:val];
        item.value = val.length > 0 ? val : @"(nil)";
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:idx inSection:0]]
                              withRowAnimation:UITableViewRowAnimationFade];
        [self showBanner:[NSString stringWithFormat:@"✅ Saved %@", item.key]
                   color:[UIColor systemGreenColor]];
    }];

    UIAlertAction *del = [UIAlertAction actionWithTitle:@"🗑 Xóa / Reset"
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self clearItem:item];
        item.value = @"(nil)";
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:idx inSection:0]]
                              withRowAnimation:UITableViewRowAnimationFade];
        [self showBanner:[NSString stringWithFormat:@"🗑 Deleted %@", item.key]
                   color:[UIColor systemRedColor]];
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ"
        style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:del];
    [alert addAction:save];
    [self presentViewController:alert animated:YES completion:nil];
}

// ===================== Swipe Actions =====================

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip
API_AVAILABLE(ios(11.0)) {
    SessionItem *item = self.items[ip.row];

    UIContextualAction *copy = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal title:@"📋 Copy"
        handler:^(UIContextualAction *a, UIView *v, void(^done)(BOOL)) {
        [[UIPasteboard generalPasteboard] setString:item.value];
        [self showBanner:@"📋 Copied!" color:[UIColor systemBlueColor]];
        done(YES);
    }];
    copy.backgroundColor = [UIColor systemBlueColor];

    UIContextualAction *del = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive title:@"🗑 Xóa"
        handler:^(UIContextualAction *a, UIView *v, void(^done)(BOOL)) {
        [self clearItem:item];
        item.value = @"(nil)";
        [self.tableView reloadRowsAtIndexPaths:@[ip]
                              withRowAnimation:UITableViewRowAnimationFade];
        done(YES);
    }];

    return [UISwipeActionsConfiguration configurationWithActions:@[del, copy]];
}

// ===================== Write / Clear =====================

- (void)writeItem:(SessionItem *)item newValue:(NSString *)val {
    switch (item.type) {
        case SessionItemTypeUserDefaults:
            [[NSUserDefaults standardUserDefaults] setObject:val forKey:item.key];
            [[NSUserDefaults standardUserDefaults] synchronize];
            break;
        case SessionItemTypeUnitoreiosPref:
            CFPreferencesSetAppValue((__bridge CFStringRef)item.key,
                (__bridge CFPropertyListRef)val, CFSTR("com.unitoreios.key"));
            CFPreferencesAppSynchronize(CFSTR("com.unitoreios.key"));
            break;
        case SessionItemTypeRuntime:
            [self writeRuntime:item.key value:val];
            break;
    }
    NSLog(@"[DEBUG][SessionEditor] %@ = %@", item.key, val);
}

- (void)writeRuntime:(NSString *)key value:(NSString *)val {
    Unitoreios *extra = GetExtraInfo();
    if ([key isEqualToString:@"remainingSeconds"])
        extra.remainingSeconds = [val integerValue];
    else if ([key isEqualToString:@"keyValidationStatus"])
        keyValidationStatus = val;
    else if ([key isEqualToString:@"iskey"])
        iskey = val;
    else if ([key isEqualToString:@"encodedcode"])
        encodedcode = val;
}

- (void)clearItem:(SessionItem *)item {
    switch (item.type) {
        case SessionItemTypeUserDefaults:
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:item.key];
            [[NSUserDefaults standardUserDefaults] synchronize];
            break;
        case SessionItemTypeUnitoreiosPref:
            CFPreferencesSetAppValue((__bridge CFStringRef)item.key,
                NULL, CFSTR("com.unitoreios.key"));
            CFPreferencesAppSynchronize(CFSTR("com.unitoreios.key"));
            break;
        case SessionItemTypeRuntime:
            [self writeRuntime:item.key value:@""];
            break;
    }
}

// ===================== Banner =====================

- (void)showBanner:(NSString *)text color:(UIColor *)color {
    UILabel *b = [[UILabel alloc] init];
    b.text = text;
    b.backgroundColor = color;
    b.textColor = [UIColor whiteColor];
    b.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    b.textAlignment = NSTextAlignmentCenter;
    b.layer.cornerRadius = 10;
    b.clipsToBounds = YES;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.alpha = 0;
    [self.view addSubview:b];
    [NSLayoutConstraint activateConstraints:@[
        [b.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [b.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [b.widthAnchor constraintEqualToConstant:240],
        [b.heightAnchor constraintEqualToConstant:40],
    ]];
    [UIView animateWithDuration:0.25 animations:^{ b.alpha = 1; } completion:^(BOOL _) {
        [UIView animateWithDuration:0.3 delay:1.5 options:0
            animations:^{ b.alpha = 0; }
            completion:^(BOOL __) { [b removeFromSuperview]; }];
    }];
}

@end

// ===================== Main Debug Menu VC =====================

@interface UnitoreiosDebugMenuVC () <UITableViewDelegate, UITableViewDataSource>
// Tabs
@property (nonatomic, strong) UISegmentedControl *tabControl;
@property (nonatomic, strong) UIView *overviewView;
@property (nonatomic, strong) UIView *settingsView;
// Overview
@property (nonatomic, strong) UILabel *lbKey;
@property (nonatomic, strong) UILabel *lbTime;
@property (nonatomic, strong) UILabel *lbNetwork;
@property (nonatomic, strong) UILabel *lbCached;
@property (nonatomic, strong) UILabel *lbStrict;
@property (nonatomic, strong) UITextView *logView;
// Settings
@property (nonatomic, strong) UISwitch *forceOfflineSwitch;
// Timer
@property (nonatomic, strong) NSTimer *refreshTimer;
@end

@implementation UnitoreiosDebugMenuVC

+ (void)presentFromTop {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top =
            [UIApplication sharedApplication].keyWindow.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;

        UnitoreiosDebugMenuVC *vc = [UnitoreiosDebugMenuVC new];
        UINavigationController *nav =
            [[UINavigationController alloc] initWithRootViewController:vc];
        nav.navigationBar.barTintColor =
            [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:1.0];
        nav.navigationBar.titleTextAttributes =
            @{NSForegroundColorAttributeName: [UIColor whiteColor]};
        nav.navigationBar.tintColor =
            [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
        if (@available(iOS 13.0, *))
            nav.modalPresentationStyle = UIModalPresentationPageSheet;
        [top presentViewController:nav animated:YES completion:nil];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"🛠 Unitoreios Debug";
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:1.0];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Đóng" style:UIBarButtonItemStyleDone
               target:self action:@selector(closeMenu)];

    [self buildTabControl];
    [self buildOverviewTab];
    [self buildSettingsTab];
    [self switchToTab:0];

    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self
        selector:@selector(refreshStats) userInfo:nil repeats:YES];
    [self refreshStats];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

// ===================== Tab Control =====================

- (void)buildTabControl {
    self.tabControl = [[UISegmentedControl alloc]
        initWithItems:@[@"📊 Overview", @"💾 Session", @"⚙️ Settings"]];
    self.tabControl.selectedSegmentIndex = 0;
    if (@available(iOS 13.0, *))
        self.tabControl.selectedSegmentTintColor =
            [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    self.tabControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tabControl];
    [NSLayoutConstraint activateConstraints:@[
        [self.tabControl.topAnchor constraintEqualToAnchor:
            self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [self.tabControl.leadingAnchor constraintEqualToAnchor:
            self.view.leadingAnchor constant:16],
        [self.tabControl.trailingAnchor constraintEqualToAnchor:
            self.view.trailingAnchor constant:-16],
    ]];
    [self.tabControl addTarget:self action:@selector(tabChanged:)
              forControlEvents:UIControlEventValueChanged];
}

- (void)tabChanged:(UISegmentedControl *)s {
    [self switchToTab:s.selectedSegmentIndex];
}

- (void)switchToTab:(NSInteger)idx {
    if (idx == 1) {
        // Push session editor
        self.tabControl.selectedSegmentIndex = 0;
        UnitoreiosSessionEditorVC *vc = [UnitoreiosSessionEditorVC new];
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }
    self.overviewView.hidden = (idx != 0);
    self.settingsView.hidden = (idx != 2);
}

// ===================== Overview Tab =====================

- (void)buildOverviewTab {
    self.overviewView = [[UIView alloc] init];
    self.overviewView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.overviewView];
    [NSLayoutConstraint activateConstraints:@[
        [self.overviewView.topAnchor constraintEqualToAnchor:
            self.tabControl.bottomAnchor constant:12],
        [self.overviewView.leadingAnchor constraintEqualToAnchor:
            self.view.leadingAnchor constant:16],
        [self.overviewView.trailingAnchor constraintEqualToAnchor:
            self.view.trailingAnchor constant:-16],
        [self.overviewView.bottomAnchor constraintEqualToAnchor:
            self.view.bottomAnchor constant:-16],
    ]];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.overviewView addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.overviewView.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.overviewView.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.overviewView.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.overviewView.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor],
    ]];

    [stack addArrangedSubview:[self sectionLabel:@"📊 KEY STATUS"]];
    self.lbKey     = [self statRow:@"Current Key"     stack:stack];
    self.lbTime    = [self statRow:@"Remaining Time"  stack:stack];
    self.lbNetwork = [self statRow:@"Network"         stack:stack];
    self.lbCached  = [self statRow:@"Cached Session"  stack:stack];
    self.lbStrict  = [self statRow:@"Strict Session"  stack:stack];

    [stack addArrangedSubview:[self sectionLabel:@"⚡️ ACTIONS"]];
    [self addBtn:@"📋 Copy All Info"  color:nil        sel:@selector(copyAll)      stack:stack];
    [self addBtn:@"🗑 Xóa savedKey"   color:[UIColor systemRedColor]
                                      sel:@selector(clearKey)     stack:stack];
    [self addBtn:@"🔄 Force Recheck"  color:nil        sel:@selector(forceRecheck) stack:stack];

    [stack addArrangedSubview:[self sectionLabel:@"📝 REALTIME LOG"]];

    self.logView = [[UITextView alloc] init];
    self.logView.backgroundColor =
        [UIColor colorWithRed:0.05 green:0.07 blue:0.10 alpha:1.0];
    self.logView.textColor =
        [UIColor colorWithRed:0.20 green:0.80 blue:0.55 alpha:1.0];
    self.logView.font = [UIFont fontWithName:@"Menlo" size:11];
    self.logView.editable = NO;
    self.logView.layer.cornerRadius = 12;
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.logView.heightAnchor constraintEqualToConstant:160].active = YES;
    [stack addArrangedSubview:self.logView];
}

- (UILabel *)statRow:(NSString *)title stack:(UIStackView *)stack {
    UIView *card = [self card:52];

    UILabel *t = [[UILabel alloc] init];
    t.text = title;
    t.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    t.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    t.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *v = [[UILabel alloc] init];
    v.text = @"—";
    v.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    v.textColor = [UIColor whiteColor];
    v.textAlignment = NSTextAlignmentRight;
    v.numberOfLines = 2;
    v.translatesAutoresizingMaskIntoConstraints = NO;

    [card addSubview:t]; [card addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
        [t.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [t.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [t.widthAnchor constraintEqualToConstant:115],
        [v.leadingAnchor constraintEqualToAnchor:t.trailingAnchor constant:8],
        [v.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [v.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
    ]];
    [stack addArrangedSubview:card];
    return v;
}

- (void)refreshStats {
    Unitoreios *inst = [NSClassFromString(@"Unitoreios") new];
    NSString *key   = [NSClassFromString(@"Unitoreios") getCurrentKey] ?: @"nil";
    NSString *time  = [NSClassFromString(@"Unitoreios") getRemainingTime] ?: @"nil";
    BOOL net        = IsForceOfflineEnabled() ? NO : [inst isNetworkAvailable];
    BOOL cached     = [inst canUseCachedSession];
    BOOL strict     = [inst hasStrictValidatedKeySession];

    self.lbKey.text     = key;
    self.lbKey.textColor =
        [key containsString:@"Lỗi"] ? [UIColor systemRedColor] : [UIColor whiteColor];

    self.lbTime.text     = time;
    self.lbTime.textColor =
        [time containsString:@"hết"] ? [UIColor systemRedColor] : [UIColor systemYellowColor];

    self.lbNetwork.text =
        IsForceOfflineEnabled() ? @"🔴 FORCED OFFLINE" : (net ? @"✅ Online" : @"❌ Offline");
    self.lbNetwork.textColor = net ? [UIColor systemGreenColor] : [UIColor systemRedColor];

    self.lbCached.text       = cached ? @"✅ YES" : @"❌ NO";
    self.lbCached.textColor  = cached ? [UIColor systemGreenColor] : [UIColor systemRedColor];

    self.lbStrict.text       = strict ? @"✅ YES" : @"❌ NO";
    self.lbStrict.textColor  = strict ? [UIColor systemGreenColor] : [UIColor systemRedColor];

    // Log
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"HH:mm:ss";
    self.logView.text = [[NSString stringWithFormat:
        @"[%@] net=%@ cached=%@ strict=%@ fo=%@\n",
        [f stringFromDate:[NSDate date]],
        net?@"Y":@"N", cached?@"Y":@"N",
        strict?@"Y":@"N", IsForceOfflineEnabled()?@"Y":@"N"]
        stringByAppendingString:self.logView.text ?: @""];
}

// ===================== Settings Tab =====================

- (void)buildSettingsTab {
    self.settingsView = [[UIView alloc] init];
    self.settingsView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.settingsView];
    [NSLayoutConstraint activateConstraints:@[
        [self.settingsView.topAnchor constraintEqualToAnchor:
            self.tabControl.bottomAnchor constant:12],
        [self.settingsView.leadingAnchor constraintEqualToAnchor:
            self.view.leadingAnchor constant:16],
        [self.settingsView.trailingAnchor constraintEqualToAnchor:
            self.view.trailingAnchor constant:-16],
        [self.settingsView.bottomAnchor constraintEqualToAnchor:
            self.view.bottomAnchor constant:-16],
    ]];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.settingsView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.settingsView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.settingsView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.settingsView.trailingAnchor],
    ]];

    [stack addArrangedSubview:[self sectionLabel:@"🌐 NETWORK OVERRIDE"]];

    // Force Offline Toggle Row
    UIView *card = [self card:60];
    UILabel *mainL = [[UILabel alloc] init];
    mainL.text = @"Force Offline Mode";
    mainL.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    mainL.textColor = [UIColor whiteColor];
    mainL.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *subL = [[UILabel alloc] init];
    subL.text = @"Hook isNetworkAvailable → NO (persistent)";
    subL.font = [UIFont systemFontOfSize:11];
    subL.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    subL.translatesAutoresizingMaskIntoConstraints = NO;

    self.forceOfflineSwitch = [[UISwitch alloc] init];
    self.forceOfflineSwitch.on = IsForceOfflineEnabled();
    self.forceOfflineSwitch.onTintColor = [UIColor systemOrangeColor];
    self.forceOfflineSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.forceOfflineSwitch addTarget:self action:@selector(toggleOffline:)
                      forControlEvents:UIControlEventValueChanged];

    UIStackView *ts = [[UIStackView alloc] initWithArrangedSubviews:@[mainL, subL]];
    ts.axis = UILayoutConstraintAxisVertical;
    ts.spacing = 3;
    ts.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:ts]; [card addSubview:self.forceOfflineSwitch];
    [NSLayoutConstraint activateConstraints:@[
        [ts.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [ts.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [self.forceOfflineSwitch.trailingAnchor constraintEqualToAnchor:
            card.trailingAnchor constant:-12],
        [self.forceOfflineSwitch.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
    ]];
    [stack addArrangedSubview:card];

    UILabel *warn = [[UILabel alloc] init];
    warn.text = @"⚠️ Lưu vào plist, giữ nguyên khi thoát/mở lại app.";
    warn.font = [UIFont systemFontOfSize:12];
    warn.textColor = [UIColor systemOrangeColor];
    warn.numberOfLines = 0;
    [stack addArrangedSubview:warn];

    [stack addArrangedSubview:[self sectionLabel:@"🧹 RESET"]];
    [self addBtn:@"🔄 Reset All Debug Settings"
           color:[UIColor systemRedColor]
             sel:@selector(resetDebugPrefs)
           stack:stack];
}

- (void)toggleOffline:(UISwitch *)sw {
    DebugWritePref(@"ForceOffline", @(sw.isOn));
    NSLog(@"[DEBUG] ForceOffline → %@", sw.isOn ? @"ON" : @"OFF");
    [self showToast:sw.isOn ? @"🔴 Force Offline ON" : @"✅ Force Offline OFF"
              color:sw.isOn ? [UIColor systemOrangeColor] : [UIColor systemGreenColor]];
}

- (void)resetDebugPrefs {
    DebugWritePref(@"ForceOffline", @NO);
    self.forceOfflineSwitch.on = NO;
    [self showToast:@"♻️ Debug prefs reset" color:[UIColor systemGrayColor]];
}

// ===================== Actions =====================

- (void)copyAll {
    Unitoreios *inst = [NSClassFromString(@"Unitoreios") new];
    NSString *s = [NSString stringWithFormat:
        @"Key: %@\nTime: %@\nNetwork: %@\nCached: %@\nStrict: %@\nForceOffline: %@\n"
        @"remainingSeconds: %ld\nkeyValidationStatus: %@\niskey: %@",
        [NSClassFromString(@"Unitoreios") getCurrentKey],
        [NSClassFromString(@"Unitoreios") getRemainingTime],
        IsForceOfflineEnabled() ? @"FORCED" : ([inst isNetworkAvailable] ? @"Online" : @"Offline"),
        @([inst canUseCachedSession]),
        @([inst hasStrictValidatedKeySession]),
        @(IsForceOfflineEnabled()),
        (long)GetExtraInfo().remainingSeconds,
        keyValidationStatus ?: @"nil",
        iskey ?: @"nil"];
    [[UIPasteboard generalPasteboard] setString:s];
    [self showToast:@"📋 Copied!" color:[UIColor systemBlueColor]];
}

- (void)clearKey {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"savedKey"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self showToast:@"🗑 savedKey cleared" color:[UIColor systemRedColor]];
}

- (void)forceRecheck {
    [[NSClassFromString(@"Unitoreios") new] performSelector:NSSelectorFromString(@"checkKey")];
    [self showToast:@"🔄 checkKey triggered" color:[UIColor systemPurpleColor]];
}

- (void)closeMenu {
    [self.refreshTimer invalidate];
    [self dismissViewControllerAnimated:YES completion:nil];
}

// ===================== UI Helpers =====================

- (UIView *)card:(CGFloat)height {
    UIView *v = [[UIView alloc] init];
    v.backgroundColor = [UIColor colorWithRed:0.12 green:0.15 blue:0.20 alpha:1.0];
    v.layer.cornerRadius = 12;
    v.translatesAutoresizingMaskIntoConstraints = NO;
    if (height > 0)
        [v.heightAnchor constraintEqualToConstant:height].active = YES;
    return v;
}

- (UILabel *)sectionLabel:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    l.textColor = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0];
    return l;
}

- (void)addBtn:(NSString *)title color:(UIColor *)color
           sel:(SEL)sel stack:(UIStackView *)stack {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.backgroundColor = [UIColor colorWithRed:0.14 green:0.17 blue:0.22 alpha:1.0];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:(color ?: [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0])
             forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    btn.layer.cornerRadius = 12;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn.heightAnchor constraintEqualToConstant:46].active = YES;
    [btn addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:btn];
}

- (void)showToast:(NSString *)text color:(UIColor *)color {
    UILabel *b = [[UILabel alloc] init];
    b.text = text;
    b.backgroundColor = color;
    b.textColor = [UIColor whiteColor];
    b.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    b.textAlignment = NSTextAlignmentCenter;
    b.layer.cornerRadius = 10;
    b.clipsToBounds = YES;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.alpha = 0;
    [self.view addSubview:b];
    [NSLayoutConstraint activateConstraints:@[
        [b.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [b.bottomAnchor constraintEqualToAnchor:
            self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [b.widthAnchor constraintEqualToConstant:240],
        [b.heightAnchor constraintEqualToConstant:40],
    ]];
    [UIView animateWithDuration:0.25 animations:^{ b.alpha=1; } completion:^(BOOL _) {
        [UIView animateWithDuration:0.3 delay:1.5 options:0
            animations:^{ b.alpha=0; }
            completion:^(BOOL __) { [b removeFromSuperview]; }];
    }];
}

@end

// ===================== Floating Button =====================

@interface UnitoreiosFloatingButton : UIWindow
+ (instancetype)shared;
- (void)show;
@end

@implementation UnitoreiosFloatingButton

+ (instancetype)shared {
    static UnitoreiosFloatingButton *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inst = [[self alloc] initWithFrame:CGRectMake(0,0,60,60)];
    });
    return inst;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.windowLevel = UIWindowLevelAlert + 100;
    self.backgroundColor = [UIColor clearColor];
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes)
            if ([s isKindOfClass:[UIWindowScene class]])
            { self.windowScene = (UIWindowScene *)s; break; }
    }
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    self.center = CGPointMake(sw - 40, sh * 0.45);
    [self buildButton];
    [self addGestureRecognizer:
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    return self;
}

- (void)buildButton {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0,0,60,60);
    btn.layer.cornerRadius = 30;
    btn.clipsToBounds = YES;

    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = btn.bounds;
    g.cornerRadius = 30;
    g.colors = @[
        (__bridge id)[UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithRed:0.05 green:0.50 blue:0.38 alpha:1.0].CGColor
    ];
    [btn.layer insertSublayer:g atIndex:0];

    btn.layer.shadowColor   = [UIColor colorWithRed:0.10 green:0.78 blue:0.55 alpha:0.6].CGColor;
    btn.layer.shadowOffset  = CGSizeMake(0, 4);
    btn.layer.shadowRadius  = 10;
    btn.layer.shadowOpacity = 0.8;
    btn.layer.masksToBounds = NO;

    // Icon
    UILabel *icon = [[UILabel alloc] initWithFrame:btn.bounds];
    icon.text = @"🛠";
    icon.font = [UIFont systemFontOfSize:26];
    icon.textAlignment = NSTextAlignmentCenter;
    [btn addSubview:icon];

    // Offline badge
    UIView *badge = [[UIView alloc] initWithFrame:CGRectMake(40, 0, 18, 18)];
    badge.tag = 9900;
    badge.backgroundColor =
        IsForceOfflineEnabled() ? [UIColor systemOrangeColor] : [UIColor clearColor];
    badge.layer.cornerRadius = 9;
    UILabel *bl = [[UILabel alloc] initWithFrame:badge.bounds];
    bl.text = @"F";
    bl.font = [UIFont systemFontOfSize:9 weight:UIFontWeightBold];
    bl.textColor = [UIColor whiteColor];
    bl.textAlignment = NSTextAlignmentCenter;
    [badge addSubview:bl];
    [btn addSubview:badge];

    // Pulse
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    pulse.fromValue = @1.0; pulse.toValue = @1.08;
    pulse.duration = 1.2; pulse.autoreverses = YES;
    pulse.repeatCount = INFINITY;
    [btn.layer addAnimation:pulse forKey:@"pulse"];

    [btn addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:btn];
}

- (void)tapped {
    // Bounce
    UIView *btn = self.subviews.firstObject;
    [UIView animateWithDuration:0.1 animations:^{
        btn.transform = CGAffineTransformMakeScale(0.88, 0.88);
    } completion:^(BOOL _) {
        [UIView animateWithDuration:0.15 animations:^{
            btn.transform = CGAffineTransformIdentity;
        } completion:^(BOOL __) {
            [UnitoreiosDebugMenuVC presentFromTop];
        }];
    }];
}

- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self];
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    self.center = CGPointMake(
        MAX(30, MIN(sw-30, self.center.x + t.x)),
        MAX(60, MIN(sh-60, self.center.y + t.y)));
    [g setTranslation:CGPointZero inView:self];

    if (g.state == UIGestureRecognizerStateEnded) {
        CGFloat tx = (self.center.x < sw/2) ? 30 : sw-30;
        [UIView animateWithDuration:0.3 delay:0
             usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0
             animations:^{ self.center = CGPointMake(tx, self.center.y); }
             completion:nil];
    }
}

- (void)show {
    self.hidden = NO;
    UIView *btn = self.subviews.firstObject;
    btn.alpha = 0;
    btn.transform = CGAffineTransformMakeScale(0.1, 0.1);
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.6
      initialSpringVelocity:0.8 options:0
      animations:^{ btn.alpha=1; btn.transform=CGAffineTransformIdentity; }
      completion:nil];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}

@end

// ===================== Hooks =====================

%hook Unitoreios

- (BOOL)isNetworkAvailable {
    if (IsForceOfflineEnabled()) {
        NSLog(@"[DEBUG] isNetworkAvailable → FORCED OFFLINE");
        return NO;
    }
    BOOL r = %orig;
    NSLog(@"[DEBUG] isNetworkAvailable → %@", r ? @"YES" : @"NO");
    return r;
}

- (BOOL)canUseCachedSession {
    BOOL r = %orig;
    NSLog(@"[DEBUG] canUseCachedSession → %@", r ? @"YES" : @"NO");
    return r;
}

- (void)checkKey {
    NSLog(@"[DEBUG] checkKey called");
    %orig;
}

%end

// ===================== Constructor =====================

__attribute__((constructor(101)))
static void UnitoreiosDebugInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[UnitoreiosFloatingButton shared] show];
        NSLog(@"[DEBUG] DebugMenu ready | ForceOffline=%@",
              IsForceOfflineEnabled() ? @"ON" : @"OFF");
    });
}
