// HeroAge 6.2.10 / Unity IL2CPP. Objective-C++17, ARC, UIKit, Foundation.
// Source-only delivery: not compiled or tested on iOS. No Frida, Logos or hook library.
// No shop/warehouse purchase bypass, anti-cheat patch, or automatic cloud/save calls.
// Back up your save first. The game's normal saves/sync can persist changes independently.
// Native floating button opens a searchable runtime catalog and CharacterData editor.
// Deliberate limits: no unverified "strongest/admin set", god-extension, all-quest reward,
// or max-passive shortcut. Those need additional game-specific invariant validation.
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <stdint.h>
#include <cstring>
#include <climits>

namespace HA {
struct Object; struct Class; struct Method; struct Field; struct Type;
static void *(*domain_get)();
static const void **(*domain_get_assemblies)(void *, size_t *);
static void *(*assembly_get_image)(const void *);
static Class *(*class_from_name)(void *, const char *, const char *);
static Class *(*object_get_class)(Object *);
static Field *(*class_get_field_from_name)(Class *, const char *);
static Field *(*class_get_fields)(Class *, void **);
static const char *(*field_get_name)(Field *);
static const Type *(*field_get_type)(Field *);
static Class *(*class_from_type)(const Type *);
static const char *(*class_get_name)(Class *);
static void (*field_get_value)(Object *, Field *, void *);
static void (*field_static_get_value)(Field *, void *);
static uint32_t (*field_get_flags)(Field *);
static Method *(*class_get_method_from_name)(Class *, const char *, int);
static Method *(*class_get_methods)(Class *, void **);
static Class *(*class_get_parent)(Class *);
static const char *(*method_get_name)(Method *);
static uint32_t (*method_get_param_count)(Method *);
static const Type *(*method_get_param)(Method *, uint32_t);
static int (*type_get_type)(const Type *);
static Object *(*runtime_invoke)(Method *, void *, void **, Object **);
static void *(*object_unbox)(Object *);
static int32_t (*string_length)(Object *);
static const uint16_t *(*string_chars)(Object *);
static void *(*thread_current)();
static void *(*thread_attach)(void *);
static void (*thread_detach)(void *);
static void (*runtime_class_init)(Class *);
static bool ready;

static void Fail(NSString *message) {
    @throw [NSException exceptionWithName:@"HeroAgeMenu" reason:message userInfo:nil];
}
static void Init() {
    if (ready) return;
#define LOAD(n) n = reinterpret_cast<decltype(n)>(dlsym(RTLD_DEFAULT, "il2cpp_" #n)); if (!n) Fail(@"Thiếu export il2cpp_" @#n)
    LOAD(domain_get); LOAD(domain_get_assemblies); LOAD(assembly_get_image);
    LOAD(class_from_name); LOAD(object_get_class); LOAD(class_get_field_from_name);
    LOAD(class_get_fields); LOAD(field_get_name); LOAD(field_get_type); LOAD(class_from_type);
    LOAD(class_get_name); LOAD(field_get_value); LOAD(field_static_get_value); LOAD(field_get_flags);
    LOAD(class_get_method_from_name); LOAD(runtime_invoke); LOAD(object_unbox);
    LOAD(class_get_methods); LOAD(class_get_parent); LOAD(method_get_name);
    LOAD(method_get_param_count); LOAD(method_get_param); LOAD(type_get_type);
    LOAD(string_length); LOAD(string_chars); LOAD(thread_current); LOAD(thread_attach);
    LOAD(thread_detach); LOAD(runtime_class_init);
#undef LOAD
    if (!domain_get()) Fail(@"IL2CPP chưa sẵn sàng; vào game rồi thử lại.");
    ready = true;
}
struct Thread {
    void *owned = nullptr;
    Thread() { Init(); if (!thread_current()) owned = thread_attach(domain_get());
        if (!thread_current()) Fail(@"Không attach được IL2CPP thread."); }
    ~Thread() { if (owned) thread_detach(owned); }
};
static Class *Find(const char *name) {
    size_t count = 0;
    const void **assemblies = domain_get_assemblies(domain_get(), &count);
    Class *found = nullptr;
    for (size_t i = 0; i < count; ++i) {
        Class *candidate = class_from_name(assembly_get_image(assemblies[i]), "", name);
        if (!candidate) continue;
        if (found && found != candidate) Fail(@"Tên class trùng giữa các assembly.");
        found = candidate;
    }
    if (!found) Fail([NSString stringWithFormat:@"Không tìm thấy class %s", name]);
    runtime_class_init(found);
    return found;
}
static Method *MethodOf(Class *klass, const char *name, int count) {
    Method *m = class_get_method_from_name(klass, name, count);
    if (!m) Fail([NSString stringWithFormat:@"Thiếu method %s/%d", name, count]);
    return m;
}
static Object *Call(Class *klass, Object *object, const char *name, int count = 0, void **args = nullptr) {
    Object *exception = nullptr;
    Object *result = runtime_invoke(MethodOf(klass, name, count), object, args, &exception);
    if (exception) Fail([NSString stringWithFormat:@"Game ném exception tại %s; dừng thao tác. Có thể đã thay đổi một phần.", name]);
    return result;
}
static Object *Call(Object *object, const char *name, int count = 0, void **args = nullptr) {
    if (!object) Fail(@"Object chưa được game tạo.");
    return Call(object_get_class(object), object, name, count, args);
}
template<class T> static T Value(Object *boxed) {
    if (!boxed) Fail(@"Method không trả về value.");
    T value; memcpy(&value, object_unbox(boxed), sizeof(value)); return value;
}
template<class T> static T Read(Class *klass, Object *object, const char *name) {
    Field *field = class_get_field_from_name(klass, name);
    if (!field) Fail([NSString stringWithFormat:@"Thiếu field %s", name]);
    T value{};
    if (field_get_flags(field) & 0x10) field_static_get_value(field, &value);
    else { if (!object) Fail(@"Field instance chưa có object."); field_get_value(object, field, &value); }
    return value;
}
template<class T> static T Read(Object *object, const char *name) {
    if (!object) Fail(@"Object chưa sẵn sàng.");
    return Read<T>(object_get_class(object), object, name);
}
static Object *Singleton(const char *klass, const char *field) {
    Object *object = Read<Object *>(Find(klass), nullptr, field);
    if (!object) Fail([NSString stringWithFormat:@"%s.%s chưa sẵn sàng; vào nhân vật trước.", klass, field]);
    return object;
}
static Object *Player() { return Singleton("Players", "MainPlayer"); }
static NSString *Text(Object *string) {
    if (!string) return @"";
    int32_t n = string_length(string);
    if (n < 0 || n > 1000000) Fail(@"Chuỗi runtime không hợp lệ.");
    return [[NSString alloc] initWithCharacters:reinterpret_cast<const unichar *>(string_chars(string)) length:(NSUInteger)n];
}
static int Count(Object *array) {
    int count = Value<int>(Call(array, "get_Length"));
    if (count < 0 || count > 100000) Fail(@"Kích thước collection bất thường.");
    return count;
}
static Object *At(Object *array, int index) {
    if (!array) Fail(@"Array chưa sẵn sàng.");
    // GetValue has Int32, Int64 and array overloads sharing the same arity.
    for (Class *klass = object_get_class(array); klass; klass = class_get_parent(klass)) {
        void *iterator = nullptr;
        while (Method *method = class_get_methods(klass, &iterator)) {
            if (strcmp(method_get_name(method), "GetValue") || method_get_param_count(method) != 1 ||
                type_get_type(method_get_param(method, 0)) != 0x08) continue;
            void *args[] = {&index}; Object *exception = nullptr;
            Object *result = runtime_invoke(method, array, args, &exception);
            if (exception) Fail(@"Array.GetValue(Int32) thất bại.");
            return result;
        }
    }
    Fail(@"Thiếu Array.GetValue(Int32).");
    return nullptr;
}
static NSString *EnumName(const char *name, int value) {
    Class *klass = Find(name); void *iterator = nullptr;
    while (Field *field = class_get_fields(klass, &iterator)) {
        if (!(field_get_flags(field) & 0x40)) continue;
        int candidate = 0; field_static_get_value(field, &candidate);
        if (candidate == value) return [NSString stringWithUTF8String:field_get_name(field)];
    }
    return [NSString stringWithFormat:@"%d", value];
}
static int Stat(Object *player, NSString *name) {
    return Value<int>(Call(player, [[@"get_" stringByAppendingString:name] UTF8String]));
}
static void SetStat(Object *player, NSString *name, int value) {
    void *args[] = {&value};
    Call(player, [[@"set_" stringByAppendingString:name] UTF8String], 1, args);
    if (Stat(player, name) != value) Fail(@"Game không giữ giá trị yêu cầu; không báo thành công.");
}
static NSArray<NSDictionary *> *Catalog() {
    Object *controller = Singleton("GameController", "instance");
    NSMutableDictionary<NSString *, NSDictionary *> *unique = [NSMutableDictionary dictionary];
    void *iterator = nullptr;
    while (Field *field = class_get_fields(object_get_class(controller), &iterator)) {
        Class *type = class_from_type(field_get_type(field));
        if (!type || strcmp(class_get_name(type), "ItemModel[]")) continue;
        Object *array = nullptr; field_get_value(controller, field, &array);
        if (!array) continue;
        for (int i = 0, n = Count(array); i < n; ++i) {
            Object *model = At(array, i); if (!model) continue;
            int category = Read<int>(model, "Category");
            int identifier = Read<uint8_t>(model, "Id");
            NSString *name = Text(Read<Object *>(model, "Name"));
            NSMutableArray *classes = [NSMutableArray array];
            Object *forClass = Read<Object *>(model, "ForClass");
            if (forClass) for (int j = 0, m = Count(forClass); j < m; ++j)
                [classes addObject:EnumName("ClassType", Value<int>(At(forClass, j)))];
            NSString *key = [NSString stringWithFormat:@"%d:%d", category, identifier];
            unique[key] = @{@"name":name, @"category":@(category), @"id":@(identifier),
                @"type":EnumName("ItemCategory", category), @"classes":[classes componentsJoinedByString:@", "],
                @"defense":@(Read<int>(model, "Defense")), @"min":@(Read<int>(model, "MinDamage")),
                @"max":@(Read<int>(model, "MaxDamage")), @"level":@(Read<int>(model, "LevelRequired"))};
        }
    }
    if (!unique.count) Fail(@"Catalog chưa được load; vào map rồi tải lại.");
    return [unique.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult order = [a[@"category"] compare:b[@"category"]];
        return order == NSOrderedSame ? [a[@"id"] compare:b[@"id"]] : order;
    }];
}
static void AddItem(NSDictionary *selected, int quantity, int level, bool superItem, bool fullOptions) {
    if (quantity < 1 || quantity > 100) Fail(@"Số lượng mỗi lần phải từ 1 đến 100.");
    // ponytail: 5-bit encoding ceiling, not a claim about legal enchant limits.
    if (level < 0 || level > 31) Fail(@"Level item vượt phạm vi mã hóa 5-bit (0..31).");
    bool exists = false;
    for (NSDictionary *row in Catalog())
        if ([row[@"category"] isEqual:selected[@"category"]] && [row[@"id"] isEqual:selected[@"id"]]) { exists = true; break; }
    if (!exists) Fail(@"Item không còn trong catalog hiện tại.");
    Object *player = Player(); Object *bucket = Read<Object *>(player, "InventoryItems");
    int length = Value<int>(Call(bucket, "get_Length"));
    if (length < 0 || length > 10000) Fail(@"Inventory length không hợp lệ.");
    NSMutableArray<NSNumber *> *free = [NSMutableArray array];
    for (int i = 0; i < length; ++i) {
        void *args[] = {&i};
        if (!Value<int64_t>(Call(bucket, "get_Item", 1, args))) [free addObject:@(i)];
    }
    if (free.count < (NSUInteger)quantity) Fail(@"Không đủ ô trống; không thêm một phần.");
    int category = [selected[@"category"] intValue], identifier = [selected[@"id"] intValue];
    int amount = 0;
    void *args[] = {&category, &identifier, &level, &superItem, &amount, &fullOptions};
    MethodOf(object_get_class(player), "SetGiftItem", 6);
    for (int i = 0; i < quantity; ++i) {
        Call(player, "SetGiftItem", 6, args);
        int index = free[i].intValue; void *get[] = {&index};
        int64_t item = Value<int64_t>(Call(bucket, "get_Item", 1, get));
        void *itemArgs[] = {&item};
        if (!item || Value<int>(Call(Find("ItemUtils"), nullptr, "GetCategory", 1, itemArgs)) != category ||
            Value<int>(Call(Find("ItemUtils"), nullptr, "GetId", 1, itemArgs)) != identifier)
            Fail(@"Đọc lại inventory không khớp. Dừng; các item trước đó có thể đã được thêm.");
    }
}
} // namespace HA

@interface HAMenu : UITableViewController <UISearchResultsUpdating>
@property(nonatomic, strong) NSArray<NSDictionary *> *items;
@property(nonatomic, strong) NSArray<NSDictionary *> *filtered;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic) BOOL itemPage;
@end

@implementation HAMenu
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.itemPage ? @"Item runtime" : @"HeroAge";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 70;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];
    if (self.itemPage) {
        self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
        self.search.searchResultsUpdater = self;
        self.search.obscuresBackgroundDuringPresentation = NO;
        self.navigationItem.searchController = self.search;
        self.definesPresentationContext = YES;
    }
    [self refresh];
}
- (void)close { [self.navigationController dismissViewControllerAnimated:YES completion:nil]; }
- (void)message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"HeroAge" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)perform:(void (^)(void))work success:(NSString *)success {
    @try { HA::Thread thread; work(); if (success) [self message:success]; }
    @catch (NSException *e) { [self message:e.reason ?: @"Lỗi không xác định."]; }
}
- (void)refresh {
    if (self.itemPage) [self perform:^{ self.items = HA::Catalog(); [self updateSearchResultsForSearchController:self.search]; } success:nil];
    else [self.tableView reloadData];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *query = controller.searchBar.text ?: @"";
    self.filtered = query.length ? [self.items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
        NSString *text = [NSString stringWithFormat:@"%@ %@ %@ %@:%@", item[@"name"], item[@"type"], item[@"classes"], item[@"category"], item[@"id"]];
        return [text rangeOfString:query options:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)].location != NSNotFound;
    }]] : self.items;
    [self.tableView reloadData];
}
- (NSArray<NSString *> *)stats {
    return @[@"Level", @"Experience", @"Point", @"SkillPoint", @"Strength", @"Agility", @"Vitality", @"Energy", @"Command", @"Health", @"Mana", @"CurrentHealth", @"CurrentMana", @"Coin", @"ResetCount", @"RelifeCount"];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.itemPage ? self.filtered.count : self.stats.count + 2;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"row"];
    cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (self.itemPage) {
        NSDictionary *item = self.filtered[indexPath.row];
        cell.textLabel.text = item[@"name"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@:%@ · %@ · %@\nDamage %@–%@ · Defense %@ · Required level %@", item[@"category"], item[@"id"], item[@"type"], item[@"classes"], item[@"min"], item[@"max"], item[@"defense"], item[@"level"]];
    } else {
        NSInteger row = indexPath.row;
        cell.textLabel.text = row == 0 ? @"Catalog / thêm item" : row == 1 ? @"Lưu nhân vật" : self.stats[row - 2];
        cell.detailTextLabel.text = row == 0 ? @"Tên, loại, class và ID đọc trực tiếp từ game" : row == 1 ? @"Ghi save local; không gọi API cloud" : @"Đọc và chỉnh qua property getter/setter của game";
    }
    return cell;
}
- (int)integer:(NSString *)text {
    NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
    long long number = 0;
    if (![scanner scanLongLong:&number] || !scanner.isAtEnd || number < 0 || number > INT_MAX)
        HA::Fail(@"Nhập số nguyên từ 0 đến 2147483647.");
    return (int)number;
}
- (void)editStat:(NSString *)name {
    [self perform:^{
        int current = HA::Stat(HA::Player(), name);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:name message:@"Sửa qua setter của game. Không bỏ qua kiểm tra toàn vẹn. Sao lưu save trước." preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = [NSString stringWithFormat:@"%d", current]; field.keyboardType = UIKeyboardTypeNumberPad; field.accessibilityLabel = name; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Áp dụng" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self perform:^{
                int value = [self integer:alert.textFields.firstObject.text];
                if ([name isEqualToString:@"Level"]) {
                    int max = HA::Read<int>(HA::Find("GameController"), nullptr, "MaxLevel");
                    if (value < 1 || max < 1 || value > max) HA::Fail(@"Level ngoài giới hạn GameController.MaxLevel hiện tại.");
                }
                HA::SetStat(HA::Player(), name, value);
            } success:@"Đã gọi setter và đọc lại đúng giá trị. Chưa chủ động ghi save."];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    } success:nil];
}
- (void)addItem:(NSDictionary *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item[@"name"] message:@"Mỗi item chiếm một ô trống. Level/options có thể bị game coi là bất hợp lệ; không có bypass anti-cheat. 31 chỉ là giới hạn mã hóa, không phải level hợp lệ tối đa." preferredStyle:UIAlertControllerStyleAlert];
    NSArray *labels = @[@"Số lượng (1..100)", @"Level (0..31)", @"Super (0 hoặc 1)", @"Full options (0 hoặc 1)"];
    for (NSUInteger i = 0; i < labels.count; ++i) {
        NSString *label = labels[i]; NSString *initial = i == 0 ? @"1" : @"0";
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = label; field.accessibilityLabel = label; field.text = initial; field.keyboardType = UIKeyboardTypeNumberPad; }];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add inventory" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self perform:^{
            int quantity = [self integer:alert.textFields[0].text], level = [self integer:alert.textFields[1].text];
            int superValue = [self integer:alert.textFields[2].text], fullValue = [self integer:alert.textFields[3].text];
            if (superValue > 1 || fullValue > 1) HA::Fail(@"Super / full options chỉ nhận 0 hoặc 1.");
            HA::AddItem(item, quantity, level, superValue != 0, fullValue != 0);
        } success:@"Đã gọi SetGiftItem và đọc lại category/ID tại các ô inventory. Chưa chủ động ghi save; mở lại inventory để refresh UI."];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.itemPage) { [self addItem:self.filtered[indexPath.row]]; return; }
    if (indexPath.row == 0) {
        HAMenu *page = [[HAMenu alloc] initWithStyle:UITableViewStyleInsetGrouped]; page.itemPage = YES;
        [self.navigationController pushViewController:page animated:YES];
    } else if (indexPath.row == 1) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Ghi save?" message:@"Ghi đè save nhân vật hiện tại. Không có undo; game có thể đồng bộ ở luồng riêng. Chỉ tiếp tục nếu đã có bản sao lưu." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Ghi save" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self perform:^{ bool position = false; void *args[] = {&position}; HA::Call(HA::Player(), "Save", 1, args); }
                success:@"Save trả về không có managed exception. Chưa kiểm chứng reload hoặc cloud."];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    } else [self editStat:self.stats[indexPath.row - 2]];
}
@end

@interface HALauncher : NSObject
@property(nonatomic, strong) UIButton *button;
- (void)install;
- (void)open;
@end
@implementation HALauncher
- (void)install {
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.gnik.heroage"]) return;
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows)
            if (candidate.isKeyWindow && candidate.rootViewController) { window = candidate; break; }
        if (window) break;
    }
    if (!window || self.button.superview == window) return;
    [self.button removeFromSuperview];
    self.button = [UIButton buttonWithType:UIButtonTypeSystem];
    self.button.translatesAutoresizingMaskIntoConstraints = NO;
    self.button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.button.layer.cornerRadius = 22;
    [self.button setTitle:@"HA" forState:UIControlStateNormal];
    self.button.accessibilityLabel = @"Mở menu HeroAge";
    [self.button addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:self.button];
    [NSLayoutConstraint activateConstraints:@[
        [self.button.widthAnchor constraintEqualToConstant:44], [self.button.heightAnchor constraintEqualToConstant:44],
        [self.button.trailingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [self.button.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:12]]];
}
- (void)open {
    UIViewController *presenter = self.button.window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    if (!presenter || [presenter isKindOfClass:UIAlertController.class] ||
        ([presenter isKindOfClass:UINavigationController.class] && [((UINavigationController *)presenter).topViewController isKindOfClass:HAMenu.class])) return;
    HAMenu *menu = [[HAMenu alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:menu];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    [presenter presentViewController:navigation animated:YES completion:nil];
}
@end

__attribute__((constructor)) static void HAStart() {
    dispatch_async(dispatch_get_main_queue(), ^{
        static HALauncher *launcher;
        launcher = [HALauncher new];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [launcher install]; }];
        [launcher install];
    });
}
