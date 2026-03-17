// KeychainInspector - Tweak.xm
// Theos tweak: dump / read / edit / delete Keychain + NSUserDefaults + plist persistence
// Build: theos build package install
// Requires: iOS 13+ jailbreak (Dopamine / Palera1n / Unc0ver)

#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <objc/runtime.h>

// ─────────────────────────────────────────────
// MARK: - Helpers
// ─────────────────────────────────────────────

static NSString *KI_DocsPath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.firstObject;
}

static NSString *KI_LogPath(void) {
    return [KI_DocsPath() stringByAppendingPathComponent:@"keychain_dump.txt"];
}

static NSString *KI_FormatValue(id obj) {
    if (!obj) return @"<nil>";
    if ([obj isKindOfClass:[NSData class]]) {
        NSData *d = (NSData *)obj;
        NSString *str = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (str) return [NSString stringWithFormat:@"(str) %@", str];
        return [NSString stringWithFormat:@"(hex) %@", [d description]];
    }
    if ([obj isKindOfClass:[NSDate class]]) return [obj description];
    return [NSString stringWithFormat:@"%@", obj];
}

// ─────────────────────────────────────────────
// MARK: - Keychain Operations
// ─────────────────────────────────────────────

static NSArray<NSDictionary *> *KI_FetchAllKeychainItems(void) {
    NSMutableArray *result = [NSMutableArray array];
    // Classes to query
    NSArray *classes = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];
    for (id cls in classes) {
        NSDictionary *query = @{
            (__bridge id)kSecClass:            cls,
            (__bridge id)kSecReturnAttributes: @YES,
            (__bridge id)kSecReturnData:        @YES,
            (__bridge id)kSecMatchLimit:        (__bridge id)kSecMatchLimitAll,
        };
        CFTypeRef ref = NULL;
        OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)query, &ref);
        if (st == errSecSuccess && ref) {
            NSArray *items = (__bridge_transfer NSArray *)ref;
            for (NSDictionary *item in items) {
                NSMutableDictionary *m = [item mutableCopy];
                m[@"_secClass"] = cls;
                [result addObject:m];
            }
        }
    }
    return result;
}

static NSString *KI_FormatKeychainItems(NSArray<NSDictionary *> *items) {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"=== Keychain Dump — %@ ===\n\n", [NSDate date]];
    [s appendFormat:@"Total items: %lu\n\n", (unsigned long)items.count];
    NSUInteger idx = 0;
    for (NSDictionary *item in items) {
        [s appendFormat:@"─── Item #%lu ───────────────────────\n", (unsigned long)idx++];
        for (NSString *key in [item.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            [s appendFormat:@"  %-20s = %@\n", key.UTF8String, KI_FormatValue(item[key])];
        }
        [s appendString:@"\n"];
    }
    return s;
}

static NSString *KI_FetchUserDefaults(void) {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"=== NSUserDefaults — %@ ===\n\n", [NSDate date]];
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    for (NSString *key in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [s appendFormat:@"  %-40s = %@\n", key.UTF8String, KI_FormatValue(all[key])];
    }
    return s;
}

static NSString *KI_FetchPersistentFiles(void) {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"=== App Documents / Library ===\n\n"];
    NSArray *dirs = @[
        KI_DocsPath(),
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"],
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in dirs) {
        [s appendFormat:@"[%@]\n", dir];
        NSArray *contents = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *f in contents) {
            NSString *full = [dir stringByAppendingPathComponent:f];
            NSDictionary *attr = [fm attributesOfItemAtPath:full error:nil];
            [s appendFormat:@"  %@  (%llu bytes)\n", f, [attr[NSFileSize] unsignedLongLongValue]];
        }
        [s appendString:@"\n"];
    }
    return s;
}

static BOOL KI_DeleteKeychainItem(NSDictionary *item) {
    id cls = item[@"_secClass"];
    if (!cls) return NO;
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    q[(__bridge id)kSecClass] = cls;
    // use acct + svce as primary key for generic passwords
    if (item[(__bridge id)kSecAttrAccount])
        q[(__bridge id)kSecAttrAccount] = item[(__bridge id)kSecAttrAccount];
    if (item[(__bridge id)kSecAttrService])
        q[(__bridge id)kSecAttrService] = item[(__bridge id)kSecAttrService];
    if (item[(__bridge id)kSecAttrServer])
        q[(__bridge id)kSecAttrServer]  = item[(__bridge id)kSecAttrServer];
    OSStatus st = SecItemDelete((__bridge CFDictionaryRef)q);
    return st == errSecSuccess;
}

static BOOL KI_UpdateKeychainItem(NSDictionary *item, NSString *newValue) {
    id cls = item[@"_secClass"];
    if (!cls) return NO;
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    q[(__bridge id)kSecClass] = cls;
    if (item[(__bridge id)kSecAttrAccount])
        q[(__bridge id)kSecAttrAccount] = item[(__bridge id)kSecAttrAccount];
    if (item[(__bridge id)kSecAttrService])
        q[(__bridge id)kSecAttrService] = item[(__bridge id)kSecAttrService];
    if (item[(__bridge id)kSecAttrServer])
        q[(__bridge id)kSecAttrServer]  = item[(__bridge id)kSecAttrServer];

    NSData *newData = [newValue dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attrs = @{ (__bridge id)kSecValueData: newData };
    OSStatus st = SecItemUpdate((__bridge CFDictionaryRef)q, (__bridge CFDictionaryRef)attrs);
    return st == errSecSuccess;
}

// ─────────────────────────────────────────────
// MARK: - Edit Cell
// ─────────────────────────────────────────────

@interface KI_KeyValueCell : UITableViewCell
@property (nonatomic, strong) UILabel *keyLbl;
@property (nonatomic, strong) UILabel *valLbl;
- (void)configureKey:(NSString *)key value:(NSString *)val;
@end

@implementation KI_KeyValueCell
- (instancetype)initWithStyle:(UITableViewCellStyle)s reuseIdentifier:(NSString *)r {
    self = [super initWithStyle:s reuseIdentifier:r];
    self.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1];
    self.selectionStyle = UITableViewCellSelectionStyleDefault;

    _keyLbl = [[UILabel alloc] init];
    _keyLbl.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold];
    _keyLbl.textColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1];
    _keyLbl.translatesAutoresizingMaskIntoConstraints = NO;

    _valLbl = [[UILabel alloc] init];
    _valLbl.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _valLbl.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    _valLbl.numberOfLines = 3;
    _valLbl.lineBreakMode = NSLineBreakByTruncatingTail;
    _valLbl.translatesAutoresizingMaskIntoConstraints = NO;

    [self.contentView addSubview:_keyLbl];
    [self.contentView addSubview:_valLbl];

    [NSLayoutConstraint activateConstraints:@[
        [_keyLbl.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
        [_keyLbl.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
        [_keyLbl.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14],
        [_valLbl.topAnchor constraintEqualToAnchor:_keyLbl.bottomAnchor constant:3],
        [_valLbl.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
        [_valLbl.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14],
        [_valLbl.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
    ]];
    return self;
}
- (void)configureKey:(NSString *)key value:(NSString *)val {
    _keyLbl.text = key;
    _valLbl.text = val ?: @"<nil>";
}
@end

// ─────────────────────────────────────────────
// MARK: - Item Detail VC (edit / delete single item)
// ─────────────────────────────────────────────

@interface KI_ItemDetailVC : UITableViewController
@property (nonatomic, strong) NSDictionary *item;
@property (nonatomic, copy) void (^onChanged)(void);
@end

@implementation KI_ItemDetailVC {
    NSArray<NSString *> *_keys;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Item Detail";
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    self.tableView.separatorColor  = [UIColor colorWithWhite:0.18 alpha:1];
    [self.tableView registerClass:[KI_KeyValueCell class] forCellReuseIdentifier:@"kvcell"];

    _keys = [_item.allKeys sortedArrayUsingSelector:@selector(compare:)];

    UIBarButtonItem *del = [[UIBarButtonItem alloc]
        initWithTitle:@"🗑 Delete"
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(deleteItem)];
    del.tintColor = [UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1];

    UIBarButtonItem *edit = [[UIBarButtonItem alloc]
        initWithTitle:@"✏️ Edit Value"
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(editItemValue)];
    edit.tintColor = [UIColor colorWithRed:0.4 green:0.9 blue:0.5 alpha:1];

    self.navigationItem.rightBarButtonItems = @[del, edit];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return _keys.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    KI_KeyValueCell *c = [tv dequeueReusableCellWithIdentifier:@"kvcell" forIndexPath:ip];
    NSString *k = _keys[ip.row];
    [c configureKey:k value:KI_FormatValue(_item[k])];
    return c;
}

- (void)deleteItem {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Confirm Delete"
        message:@"This will permanently remove this keychain entry."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
        BOOL ok = KI_DeleteKeychainItem(self->_item);
        NSString *msg = ok ? @"Item deleted successfully." : @"Delete failed (check entitlements / class).";
        UIAlertController *r = [UIAlertController alertControllerWithTitle:@"Result" message:msg preferredStyle:UIAlertControllerStyleAlert];
        [r addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
            if (ok) {
                if (self->_onChanged) self->_onChanged();
                [self.navigationController popViewControllerAnimated:YES];
            }
        }]];
        [self presentViewController:r animated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editItemValue {
    // Show text field pre-filled with current value data
    NSData *existing = _item[(__bridge id)kSecValueData];
    NSString *current = existing ? ([[NSString alloc] initWithData:existing encoding:NSUTF8StringEncoding] ?: @"") : @"";

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Edit Value Data"
        message:@"New UTF-8 value for kSecValueData:"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.text = current;
        tf.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSString *newVal = alert.textFields.firstObject.text ?: @"";
        BOOL ok = KI_UpdateKeychainItem(self->_item, newVal);
        NSString *msg = ok ? @"Value updated successfully." : @"Update failed.";
        UIAlertController *r = [UIAlertController alertControllerWithTitle:@"Result" message:msg preferredStyle:UIAlertControllerStyleAlert];
        [r addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
            if (ok && self->_onChanged) self->_onChanged();
        }]];
        [self presentViewController:r animated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

// ─────────────────────────────────────────────
// MARK: - Item List VC (browse all keychain items)
// ─────────────────────────────────────────────

@interface KI_ItemListVC : UITableViewController
@end

@implementation KI_ItemListVC {
    NSArray<NSDictionary *> *_items;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"All Keychain Items";
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    self.tableView.separatorColor  = [UIColor colorWithWhite:0.18 alpha:1];
    [self.tableView registerClass:[KI_KeyValueCell class] forCellReuseIdentifier:@"itemcell"];
    [self reload];
}

- (void)reload {
    _items = KI_FetchAllKeychainItems();
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return _items.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    KI_KeyValueCell *c = [tv dequeueReusableCellWithIdentifier:@"itemcell" forIndexPath:ip];
    NSDictionary *item = _items[ip.row];
    NSString *acct = item[(__bridge id)kSecAttrAccount] ?: @"—";
    NSString *svce = item[(__bridge id)kSecAttrService] ?: item[(__bridge id)kSecAttrServer] ?: @"—";
    [c configureKey:[NSString stringWithFormat:@"[%lu]  acct: %@", (unsigned long)ip.row, acct]
              value:[NSString stringWithFormat:@"svce/server: %@", svce]];
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    KI_ItemDetailVC *vc = [[KI_ItemDetailVC alloc] initWithStyle:UITableViewStylePlain];
    vc.item = _items[ip.row];
    __weak typeof(self) ws = self;
    vc.onChanged = ^{ [ws reload]; };
    [self.navigationController pushViewController:vc animated:YES];
}
@end

// ─────────────────────────────────────────────
// MARK: - Main Inspector VC
// ─────────────────────────────────────────────

@interface KI_MainVC : UIViewController
@end

@implementation KI_MainVC {
    UITextView *_log;
    UIActivityIndicatorView *_spinner;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"🔑 KeychainInspector";
    self.view.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];

    // ── Toolbar ─────────────────────────────────
    UIStackView *bar = [[UIStackView alloc] init];
    bar.axis = UILayoutConstraintAxisHorizontal;
    bar.distribution = UIStackViewDistributionFillEqually;
    bar.spacing = 6;
    bar.translatesAutoresizingMaskIntoConstraints = NO;

    struct { NSString *title; SEL sel; UIColor *color; } btns[] = {
        { @"⬇ Dump All",  @selector(dumpAll),        [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1] },
        { @"📋 Browse",    @selector(browseItems),    [UIColor colorWithRed:0.3 green:0.85 blue:0.5 alpha:1] },
        { @"💾 Save .txt", @selector(saveLog),        [UIColor colorWithRed:1.0 green:0.75 blue:0.2 alpha:1] },
        { @"🗑 Clear Log", @selector(clearLog),       [UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:1] },
    };
    for (int i = 0; i < 4; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:btns[i].title forState:UIControlStateNormal];
        [b setTitleColor:btns[i].color forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold];
        b.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        b.layer.cornerRadius = 8;
        b.layer.borderWidth = 1;
        b.layer.borderColor = [btns[i].color CGColor];
        [b addTarget:self action:btns[i].sel forControlEvents:UIControlEventTouchUpInside];
        [bar addArrangedSubview:b];
    }

    // ── Log TextView ────────────────────────────
    _log = [[UITextView alloc] init];
    _log.editable = NO;
    _log.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _log.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    _log.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1];
    _log.layer.cornerRadius = 10;
    _log.translatesAutoresizingMaskIntoConstraints = NO;
    _log.text = @"Tap ⬇ Dump All to begin…\n\nAll data is read from this process's keychain access group.\nSave .txt writes to this app's Documents folder.";

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color = [UIColor whiteColor];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.hidesWhenStopped = YES;

    [self.view addSubview:bar];
    [self.view addSubview:_log];
    [self.view addSubview:_spinner];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [bar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:10],
        [bar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-10],
        [bar.heightAnchor constraintEqualToConstant:44],

        [_log.topAnchor constraintEqualToAnchor:bar.bottomAnchor constant:10],
        [_log.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:10],
        [_log.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-10],
        [_log.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10],

        [_spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

// ── Actions ─────────────────────────────────────

- (void)dumpAll {
    [_spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *items = KI_FetchAllKeychainItems();
        NSString *kc   = KI_FormatKeychainItems(items);
        NSString *ud   = KI_FetchUserDefaults();
        NSString *fs   = KI_FetchPersistentFiles();
        NSString *full = [NSString stringWithFormat:@"%@\n\n%@\n\n%@", kc, ud, fs];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_log.text = full;
            [self->_spinner stopAnimating];
        });
    });
}

- (void)browseItems {
    KI_ItemListVC *vc = [[KI_ItemListVC alloc] initWithStyle:UITableViewStylePlain];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    nav.navigationBar.translucent = YES;
    nav.navigationBar.tintColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)saveLog {
    NSString *text = _log.text;
    if (!text.length || [text hasPrefix:@"Tap"]) {
        [self showAlert:@"Nothing to Save" message:@"Run Dump All first."];
        return;
    }
    NSString *path = KI_LogPath();
    NSError *err = nil;
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) {
        [self showAlert:@"Save Failed" message:err.localizedDescription];
    } else {
        [self showAlert:@"Saved ✓" message:[NSString stringWithFormat:@"Written to:\n%@", path]];
    }
}

- (void)clearLog {
    _log.text = @"Log cleared.";
}

- (void)showAlert:(NSString *)title message:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
@end

// ─────────────────────────────────────────────
// MARK: - Floating Button Injected into Every App
// ─────────────────────────────────────────────

@interface KI_FloatButton : UIButton
@property (nonatomic, weak) UIWindow *hostWindow;
@end

@implementation KI_FloatButton
- (instancetype)init {
    self = [super init];
    if (self) {
        [self setTitle:@"🔑" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont systemFontOfSize:22];
        self.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.15 alpha:0.90];
        self.layer.cornerRadius = 28;
        self.layer.shadowColor  = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:1].CGColor;
        self.layer.shadowOpacity = 0.85;
        self.layer.shadowRadius  = 10;
        self.layer.shadowOffset  = CGSizeMake(0, 4);
        self.layer.borderWidth = 1.5;
        self.layer.borderColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:0.6].CGColor;
        [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];

        // Drag gesture
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)tapped {
    UIWindow *win = self.hostWindow;
    UIViewController *root = win.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;

    KI_MainVC *vc = [[KI_MainVC alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.navigationBar.barStyle  = UIBarStyleBlack;
    nav.navigationBar.translucent = YES;
    nav.navigationBar.tintColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1];
    nav.modalPresentationStyle  = UIModalPresentationPageSheet;
    [root presentViewController:nav animated:YES completion:nil];
}

- (void)dragged:(UIPanGestureRecognizer *)gr {
    CGPoint delta = [gr translationInView:self.superview];
    self.center = CGPointMake(self.center.x + delta.x, self.center.y + delta.y);
    [gr setTranslation:CGPointZero inView:self.superview];

    if (gr.state == UIGestureRecognizerStateEnded) {
        CGRect b = self.superview.bounds;
        CGFloat x = self.center.x < b.size.width / 2 ? 44 : b.size.width - 44;
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0 options:0 animations:^{
            self.center = CGPointMake(x, self.center.y);
        } completion:nil];
    }
}
@end

// ─────────────────────────────────────────────
// MARK: - Hook UIApplication to inject button
// ─────────────────────────────────────────────

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIWindow *win = self;
            KI_FloatButton *btn = [[KI_FloatButton alloc] init];
            btn.hostWindow = win;
            CGRect scr = win.bounds;
            btn.frame = CGRectMake(scr.size.width - 72, scr.size.height * 0.70, 56, 56);
            btn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
            [win addSubview:btn];
        });
    });
}
%end
