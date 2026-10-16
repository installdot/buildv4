// HeroAge 6.2.10 Mod Menu Tweak
// Source-only delivery for compile with Theos / iOS toolchain
// Architecture: arm64 / arm64e, iOS 14.0+
// Frameworks: UIKit, Foundation, CoreGraphics

#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <stdint.h>
#include <cstring>
#include <climits>
#include <vector>
#include <string>

namespace HA {

struct Object;
struct Class;
struct Method;
struct Field;
struct Type;

// IL2CPP Export pointers
static void* (*domain_get)();
static const void** (*domain_get_assemblies)(void*, size_t*);
static void* (*assembly_get_image)(const void*);
static Class* (*class_from_name)(void*, const char*, const char*);
static Class* (*object_get_class)(Object*);
static Field* (*class_get_field_from_name)(Class*, const char*);
static Field* (*class_get_fields)(Class*, void**);
static const char* (*field_get_name)(Field*);
static const Type* (*field_get_type)(Field*);
static Class* (*class_from_type)(const Type*);
static const char* (*class_get_name)(Class*);
static void (*field_get_value)(Object*, Field*, void*);
static void (*field_static_get_value)(Field*, void*);
static uint32_t (*field_get_flags)(Field*);
static Method* (*class_get_method_from_name)(Class*, const char*, int);
static Method* (*class_get_methods)(Class*, void**);
static Class* (*class_get_parent)(Class*);
static const char* (*method_get_name)(Method*);
static uint32_t (*method_get_param_count)(Method*);
static const Type* (*method_get_param)(Method*, uint32_t);
static int (*type_get_type)(const Type*);
static Object* (*runtime_invoke)(Method*, void*, void**, Object**);
static void* (*object_unbox)(Object*);
static int32_t (*string_length)(Object*);
static const uint16_t* (*string_chars)(Object*);
static void* (*thread_current)();
static void* (*thread_attach)(void*);
static void (*thread_detach)(void*);
static void (*runtime_class_init)(Class*);
static bool ready = false;

static void Fail(NSString* msg) {
    @throw [NSException exceptionWithName:@"HeroAgeException" reason:msg userInfo:nil];
}

static void Init() {
    if (ready) return;
#define LOAD(n) n = reinterpret_cast<decltype(n)>(dlsym(RTLD_DEFAULT, "il2cpp_" #n)); if (!n) Fail(@"Thiếu export il2cpp_" @#n)
    LOAD(domain_get); LOAD(domain_get_assemblies); LOAD(assembly_get_image);
    LOAD(class_from_name); LOAD(object_get_class); LOAD(class_get_field_from_name);
    LOAD(class_get_fields); LOAD(field_get_name); LOAD(field_get_type); LOAD(class_from_type);
    LOAD(class_get_name); LOAD(field_get_value); LOAD(field_static_get_value); LOAD(field_get_flags);
    LOAD(class_get_method_from_name); LOAD(class_get_methods); LOAD(class_get_parent);
    LOAD(method_get_name); LOAD(method_get_param_count); LOAD(method_get_param);
    LOAD(type_get_type); LOAD(runtime_invoke); LOAD(object_unbox);
    LOAD(string_length); LOAD(string_chars); LOAD(thread_current); LOAD(thread_attach);
    LOAD(thread_detach); LOAD(runtime_class_init);
#undef LOAD
    if (!domain_get()) Fail(@"IL2CPP chưa sẵn sàng.");
    ready = true;
}

struct ThreadScope {
    void* attached = nullptr;
    ThreadScope() {
        Init();
        if (!thread_current()) {
            attached = thread_attach(domain_get());
        }
    }
    ~ThreadScope() {
        if (attached) {
            thread_detach(attached);
        }
    }
};

static Class* FindClass(const char* name) {
    size_t count = 0;
    const void** assemblies = domain_get_assemblies(domain_get(), &count);
    Class* res = nullptr;
    for (size_t i = 0; i < count; ++i) {
        Class* c = class_from_name(assembly_get_image(assemblies[i]), "", name);
        if (c) {
            res = c;
            break;
        }
    }
    if (!res) Fail([NSString stringWithFormat:@"Không tìm thấy class: %s", name]);
    runtime_class_init(res);
    return res;
}

static Method* GetMethod(Class* klass, const char* name, int argCount) {
    Method* m = class_get_method_from_name(klass, name, argCount);
    if (!m) Fail([NSString stringWithFormat:@"Không tìm thấy method: %s/%d", name, argCount]);
    return m;
}

static Object* Invoke(Class* klass, Object* obj, const char* name, int argCount = 0, void** args = nullptr) {
    Method* m = GetMethod(klass, name, argCount);
    Object* exc = nullptr;
    Object* ret = runtime_invoke(m, obj, args, &exc);
    if (exc) Fail([NSString stringWithFormat:@"Game ném Exception khi gọi: %s", name]);
    return ret;
}

static Object* Invoke(Object* obj, const char* name, int argCount = 0, void** args = nullptr) {
    if (!obj) Fail(@"Invoke trên null object.");
    return Invoke(object_get_class(obj), obj, name, argCount, args);
}

template<typename T>
static T Unbox(Object* boxed) {
    if (!boxed) Fail(@"Unbox null object.");
    T val;
    memcpy(&val, object_unbox(boxed), sizeof(T));
    return val;
}

template<typename T>
static T GetFieldValue(Class* klass, Object* obj, const char* name) {
    Field* f = class_get_field_from_name(klass, name);
    if (!f) Fail([NSString stringWithFormat:@"Không tìm thấy field: %s", name]);
    T val{};
    if (field_get_flags(f) & 0x10) {
        field_static_get_value(f, &val);
    } else {
        if (!obj) Fail(@"Field instance cần object.");
        field_get_value(obj, f, &val);
    }
    return val;
}

template<typename T>
static void SetFieldValue(Class* klass, Object* obj, const char* name, T val) {
    Field* f = class_get_field_from_name(klass, name);
    if (!f) Fail([NSString stringWithFormat:@"Không tìm thấy field: %s", name]);
    // write to instance field
    if (!(field_get_flags(f) & 0x10)) {
        if (!obj) Fail(@"Field instance cần object.");
        // Offset calculation or direct write
        uint8_t* ptr = reinterpret_cast<uint8_t*>(obj);
        // We can use field accessor or direct pointer if known
    }
}

static Object* GetSingleton(const char* klassName, const char* fieldName) {
    return GetFieldValue<Object*>(FindClass(klassName), nullptr, fieldName);
}

static Object* GetPlayer() {
    Object* p = GetSingleton("Players", "MainPlayer");
    if (!p) Fail(@"Chưa vào game / Chưa chọn nhân vật.");
    return p;
}

static NSString* StringFromIL2CPP(Object* strObj) {
    if (!strObj) return @"";
    int32_t len = string_length(strObj);
    if (len <= 0 || len > 100000) return @"";
    return [[NSString alloc] initWithCharacters:reinterpret_cast<const unichar*>(string_chars(strObj)) length:len];
}

static int ArrayLength(Object* arr) {
    if (!arr) return 0;
    return Unbox<int>(Invoke(arr, "get_Length"));
}

static Object* ArrayGet(Object* arr, int idx) {
    if (!arr) return nullptr;
    for (Class* k = object_get_class(arr); k; k = class_get_parent(k)) {
        void* iter = nullptr;
        while (Method* m = class_get_methods(k, &iter)) {
            if (strcmp(method_get_name(m), "GetValue") == 0 &&
                method_get_param_count(m) == 1 &&
                type_get_type(method_get_param(m, 0)) == 0x08) {
                void* args[] = { &idx };
                Object* exc = nullptr;
                Object* res = runtime_invoke(m, arr, args, &exc);
                if (exc) return nullptr;
                return res;
            }
        }
    }
    return nullptr;
}

static NSString* GetEnumName(const char* enumClassName, int val) {
    Class* k = FindClass(enumClassName);
    void* iter = nullptr;
    while (Field* f = class_get_fields(k, &iter)) {
        if (field_get_flags(f) & 0x40) {
            int c = 0;
            field_static_get_value(f, &c);
            if (c == val) return [NSString stringWithUTF8String:field_get_name(f)];
        }
    }
    return [NSString stringWithFormat:@"%d", val];
}

// -------------------------------------------------------------
// Gameplay & Stats Core
// -------------------------------------------------------------

static int GetPlayerStat(NSString* name) {
    Object* p = GetPlayer();
    std::string methodName = "get_" + std::string([name UTF8String]);
    return Unbox<int>(Invoke(p, methodName.c_str()));
}

static void SetPlayerStat(NSString* name, int value) {
    Object* p = GetPlayer();
    std::string methodName = "set_" + std::string([name UTF8String]);
    void* args[] = { &value };
    Invoke(p, methodName.c_str(), 1, args);
}

static int64_t GetCurrency(NSString* key) {
    if ([key isEqualToString:@"Coin"]) {
        return GetPlayerStat(@"Coin");
    } else if ([key isEqualToString:@"Diamond"]) {
        Class* gc = FindClass("GameConfig");
        return Unbox<int>(Invoke(gc, nullptr, "get_Diamond"));
    } else if ([key isEqualToString:@"WarehouseCoin"]) {
        Class* gc = FindClass("GameConfig");
        return Unbox<int64_t>(Invoke(gc, nullptr, "get_WarehouseCoin"));
    }
    return 0;
}

static void SetCurrency(NSString* key, int64_t val) {
    if ([key isEqualToString:@"Coin"]) {
        int v = (int)val;
        SetPlayerStat(@"Coin", v);
    } else if ([key isEqualToString:@"Diamond"]) {
        int v = (int)val;
        Class* gc = FindClass("GameConfig");
        void* args[] = { &v };
        Invoke(gc, nullptr, "set_Diamond", 1, args);
    } else if ([key isEqualToString:@"WarehouseCoin"]) {
        Class* gc = FindClass("GameConfig");
        void* args[] = { &val };
        Invoke(gc, nullptr, "set_WarehouseCoin", 1, args);
    }
}

// Unlock All Characters & Slots
static void UnlockAllCharacters() {
    Class* gc = FindClass("GameConfig");
    bool t = true;
    void* args[] = { &t };
    Invoke(gc, nullptr, "set_UnlockMagicKnight", 1, args);
    Invoke(gc, nullptr, "set_UnlockSummoner", 1, args);
    Invoke(gc, nullptr, "set_UnlockWarlord", 1, args);
    Invoke(gc, nullptr, "set_UnlockFighter", 1, args);
    Invoke(gc, nullptr, "set_UnlockLancer", 1, args);
    Invoke(gc, nullptr, "set_HasBoughtSlot4", 1, args);
    Invoke(gc, nullptr, "set_HasBoughtSlot5", 1, args);
    Invoke(gc, nullptr, "set_HasBoughtExpandInventory", 1, args);
}

// Skills & Passives
static void UnlockAllSkills(bool maxPoints) {
    Object* p = GetPlayer();
    Object* gc = GetSingleton("GameController", "instance");
    Object* skillModelsArr = GetFieldValue<Object*>(object_get_class(gc), gc, "SkillModels");
    if (!skillModelsArr) Fail(@"Chưa load SkillModels.");
    
    int total = ArrayLength(skillModelsArr);
    int playerClass = Unbox<int>(Invoke(p, "get_ClassType"));
    Class* itemUtilsClass = FindClass("ItemUtils");
    
    int maxPts = 20;
    Field* fMaxPts = class_get_field_from_name(object_get_class(gc), "MaxSkillPoint");
    if (fMaxPts) {
        field_static_get_value(fMaxPts, &maxPts);
        if (maxPts < 1 || maxPts > 100) maxPts = 20;
    }

    for (int i = 0; i < total; ++i) {
        Object* skill = ArrayGet(skillModelsArr, i);
        if (!skill) continue;
        int skillId = (int)GetFieldValue<int16_t>(object_get_class(skill), skill, "Id");
        if (skillId <= 0) continue;
        
        // Check ForClass
        Object* forClassArr = GetFieldValue<Object*>(object_get_class(skill), skill, "ForClass");
        bool classMatch = false;
        if (forClassArr) {
            int fcCount = ArrayLength(forClassArr);
            if (fcCount == 0) classMatch = true;
            for (int c = 0; c < fcCount; ++c) {
                int cType = Unbox<int>(ArrayGet(forClassArr, c));
                if (cType == playerClass) { classMatch = true; break; }
            }
        } else {
            classMatch = true;
        }
        
        if (!classMatch) continue;
        
        void* getArgs[] = { &skillId };
        int currentPts = Unbox<int>(Invoke(p, "GetSkillPoint", 1, getArgs));
        
        if (currentPts <= 0) {
            void* addArgs[] = { &skillId };
            Invoke(p, "AddSkillPoint", 1, addArgs);
            currentPts = 1;
        }
        
        if (maxPoints && currentPts < maxPts) {
            int toAdd = maxPts - currentPts;
            for (int a = 0; a < toAdd; ++a) {
                void* addArgs[] = { &skillId };
                Invoke(p, "AddSkillPoint", 1, addArgs);
            }
        }
    }
}

// Complete All Quests
static void FinishAllQuests() {
    Object* p = GetPlayer();
    Object* qc = GetSingleton("QuestController", "instance");
    Object* questInfoArr = GetFieldValue<Object*>(object_get_class(qc), qc, "QuestInfo");
    if (!questInfoArr) Fail(@"Chưa load danh sách Quest.");
    
    int total = ArrayLength(questInfoArr);
    for (int i = 0; i < total; ++i) {
        Object* qObj = ArrayGet(questInfoArr, i);
        if (!qObj) continue;
        // QuestInfo is a struct, Id is at offset 0
        int qId = *reinterpret_cast<int*>(object_unbox(qObj));
        if (qId <= 0) continue;
        
        void* args[] = { &qId };
        Invoke(p, "SetQuestReceived", 1, args);
        Invoke(p, "SetQuestCompleted", 1, args);
    }
}

// -------------------------------------------------------------
// Dynamic Catalog & Option Detection
// -------------------------------------------------------------

static NSArray<NSDictionary*>* GetOptionListForCategory(int category) {
    NSMutableArray<NSDictionary*>* list = [NSMutableArray array];
    Class* iu = FindClass("ItemUtils");
    
    // Check if category is armor or weapon
    // Weapon categories: Sword=3, Staff=4, Bow=5, Scepter=21
    // Armor categories: Armor=1, Shield=2, Ring=11, Pendant=12, Wing=14, Earring=24
    uint32_t mask = 1 << category;
    bool isArmor = (mask & 0x2C806) != 0;
    bool isWeapon = (mask & 0x201038) != 0;
    
    const char* fieldName = isArmor ? "ArmorOption" : (isWeapon ? "WeaponOption" : nullptr);
    if (fieldName) {
        Object* strArr = GetFieldValue<Object*>(iu, nullptr, fieldName);
        if (strArr) {
            int cnt = ArrayLength(strArr);
            for (int i = 0; i < cnt && i < 8; ++i) {
                Object* s = ArrayGet(strArr, i);
                NSString* label = StringFromIL2CPP(s);
                if (label.length == 0) label = [NSString stringWithFormat:@"Dòng phụ %d", i + 1];
                [list addObject:@{ @"index": @(i), @"label": label }];
            }
        }
    }
    return list;
}

static NSArray<NSDictionary*>* GetRuntimeCatalog() {
    Object* gc = GetSingleton("GameController", "instance");
    NSMutableDictionary<NSString*, NSDictionary*>* unique = [NSMutableDictionary dictionary];
    void* iter = nullptr;
    
    while (Field* f = class_get_fields(object_get_class(gc), &iter)) {
        Class* ft = class_from_type(field_get_type(f));
        if (!ft || strcmp(class_get_name(ft), "ItemModel[]") != 0) continue;
        
        Object* arr = nullptr;
        field_get_value(gc, f, &arr);
        if (!arr) continue;
        
        int n = ArrayLength(arr);
        for (int i = 0; i < n; ++i) {
            Object* m = ArrayGet(arr, i);
            if (!m) continue;
            
            int cat = GetFieldValue<int>(object_get_class(m), m, "Category");
            uint8_t idByte = GetFieldValue<uint8_t>(object_get_class(m), m, "Id");
            int idVal = (int)idByte;
            NSString* name = StringFromIL2CPP(GetFieldValue<Object*>(object_get_class(m), m, "Name"));
            if (name.length == 0) continue;
            
            NSMutableArray* classes = [NSMutableArray array];
            Object* forClass = GetFieldValue<Object*>(object_get_class(m), m, "ForClass");
            if (forClass) {
                int fcCount = ArrayLength(forClass);
                for (int c = 0; c < fcCount; ++c) {
                    [classes addObject:GetEnumName("ClassType", Unbox<int>(ArrayGet(forClass, c)))];
                }
            }
            
            int def = GetFieldValue<int>(object_get_class(m), m, "Defense");
            int minD = GetFieldValue<int>(object_get_class(m), m, "MinDamage");
            int maxD = GetFieldValue<int>(object_get_class(m), m, "MaxDamage");
            int reqLvl = GetFieldValue<int>(object_get_class(m), m, "LevelRequired");
            
            NSString* key = [NSString stringWithFormat:@"%d:%d", cat, idVal];
            unique[key] = @{
                @"name": name,
                @"category": @(cat),
                @"id": @(idVal),
                @"type": GetEnumName("ItemCategory", cat),
                @"classes": [classes componentsJoinedByString:@", "],
                @"defense": @(def),
                @"min": @(minD),
                @"max": @(maxD),
                @"level": @(reqLvl)
            };
        }
    }
    
    return [unique.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
        NSComparisonResult res = [a[@"category"] compare:b[@"category"]];
        return res == NSOrderedSame ? [a[@"id"] compare:b[@"id"]] : res;
    }];
}

// -------------------------------------------------------------
// Robust Item Creation & Inventory Injection
// -------------------------------------------------------------

static void AddItemToInventory(int category, int itemId, int level, bool isSuper, int quantity, const std::vector<int>& activeOptions) {
    Object* p = GetPlayer();
    Object* bucket = GetFieldValue<Object*>(object_get_class(p), p, "InventoryItems");
    if (!bucket) Fail(@"Không tìm thấy Inventory.");
    
    int bucketLen = Unbox<int>(Invoke(bucket, "get_Length"));
    std::vector<int> freeSlots;
    for (int i = 0; i < bucketLen; ++i) {
        void* args[] = { &i };
        int64_t val = Unbox<int64_t>(Invoke(bucket, "get_Item", 1, args));
        if (val == 0) freeSlots.push_back(i);
    }
    
    if (freeSlots.size() < (size_t)quantity) {
        Fail([NSString stringWithFormat:@"Không đủ ô trống trong túi đồ (Cần %d, Còn %lu).", quantity, freeSlots.size()]);
    }
    
    Class* itemUtils = FindClass("ItemUtils");
    Class* gameConfig = FindClass("GameConfig");
    
    // Check if category is stackable/consumable
    bool isConsumable = (category == 6 || category == 8 || category == 10 || category == 17 || category == 20);
    
    for (int q = 0; q < quantity; ++q) {
        int opt1 = 0, opt2 = 0, opt3 = 0, opt4 = 0, opt5 = 0, opt6 = 0, opt7 = 0;
        int64_t opt8 = 0;
        
        if (!isConsumable) {
            for (int optIdx : activeOptions) {
                switch (optIdx) {
                    case 0: opt1 = 1; break;
                    case 1: opt2 = 1; break;
                    case 2: opt3 = 1; break;
                    case 3: opt4 = 1; break;
                    case 4: opt5 = 1; break;
                    case 5: opt6 = 1; break;
                    case 6: opt7 = 1; break;
                    case 7: opt8 = 1; break;
                }
            }
        }
        
        void* createArgs[] = {
            &category, &itemId, &level,
            &opt1, &opt2, &opt3, &opt4, &opt5, &opt6, &opt7, &opt8
        };
        
        int64_t rawItem = Unbox<int64_t>(Invoke(itemUtils, nullptr, "CreateItem", 11, createArgs));
        if (rawItem == 0) Fail(@"Không tạo được item qua ItemUtils.CreateItem.");
        
        if (isSuper) {
            void* superArgs[] = { &rawItem };
            rawItem = Unbox<int64_t>(Invoke(itemUtils, nullptr, "SetSuper", 1, superArgs));
        }
        
        if (isConsumable) {
            // Set amount = 1 per slot
            uint8_t amt = 1;
            void* amtArgs[] = { &rawItem, &amt };
            rawItem = Unbox<int64_t>(Invoke(itemUtils, nullptr, "SetAmount", 2, amtArgs));
        }
        
        // Place in free slot
        int slot = freeSlots[q];
        void* setArgs[] = { &slot, &rawItem };
        Invoke(bucket, "set_Item", 2, setArgs);
        
        // Register item in GameConfig to prevent disappearance
        void* regArgs[] = { &rawItem };
        Invoke(gameConfig, nullptr, "RegisterItem", 1, regArgs);
    }
    
    // Refresh UI if open
    Object* uiMgr = GetSingleton("UIManager", "instance");
    if (uiMgr) {
        Object* invDiag = GetFieldValue<Object*>(object_get_class(uiMgr), uiMgr, "InventoryDialog");
        if (invDiag) {
            Invoke(invDiag, "FillData");
        }
    }
}

} // namespace HA

// -------------------------------------------------------------
// UI: Premium Mod Menu (iOS Dark Native Design)
// -------------------------------------------------------------

@interface HAItemDetailVC : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) NSDictionary* itemData;
@property (nonatomic, strong) UITableView* tableView;
@property (nonatomic, strong) NSArray<NSDictionary*>* availableOptions;
@property (nonatomic, strong) NSMutableSet<NSNumber*>* selectedOptions;
@property (nonatomic, assign) NSInteger itemLevel;
@property (nonatomic, assign) NSInteger quantity;
@property (nonatomic, assign) BOOL isSuper;
@end

@interface HAMenuMainVC : UIViewController <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>
@property (nonatomic, strong) UISegmentedControl* tabControl;
@property (nonatomic, strong) UITableView* tableView;
@property (nonatomic, strong) UISearchController* searchController;
@property (nonatomic, strong) NSArray<NSDictionary*>* catalogItems;
@property (nonatomic, strong) NSArray<NSDictionary*>* filteredItems;
@end

@implementation HAItemDetailVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.itemData[@"name"];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    
    self.selectedOptions = [NSMutableSet set];
    self.quantity = 1;
    self.itemLevel = 0;
    self.isSuper = NO;
    
    int cat = [self.itemData[@"category"] intValue];
    self.availableOptions = HA::GetOptionListForCategory(cat);
    
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Thêm vào túi"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(onAddTapped)];
}

- (void)onAddTapped {
    std::vector<int> opts;
    for (NSNumber* n in self.selectedOptions) {
        opts.push_back([n intValue]);
    }
    
    int cat = [self.itemData[@"category"] intValue];
    int itemId = [self.itemData[@"id"] intValue];
    
    @try {
        HA::ThreadScope scope;
        HA::AddItemToInventory(cat, itemId, (int)self.itemLevel, self.isSuper, (int)self.quantity, opts);
        
        UIAlertController* a = [UIAlertController alertControllerWithTitle:@"Thành công"
                                                                   message:[NSString stringWithFormat:@"Đã thêm %ldx %@ vào túi đồ!", (long)self.quantity, self.itemData[@"name"]]
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self.navigationController popViewControllerAnimated:YES];
        }]];
        [self presentViewController:a animated:YES completion:nil];
    } @catch (NSException* e) {
        UIAlertController* a = [UIAlertController alertControllerWithTitle:@"Lỗi"
                                                                   message:e.reason
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.availableOptions.count > 0 ? 3 : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Thông tin & Cấu hình";
    if (section == 1) return @"Cài đặt Cấp độ & Thuộc tính";
    return @"Chọn dòng phụ (Option dòng)";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;
    if (section == 1) return 3;
    return self.availableOptions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"C"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"C"];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Loại";
            cell.detailTextLabel.text = self.itemData[@"type"];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Phù hợp Class";
            cell.detailTextLabel.text = self.itemData[@"classes"];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.textLabel.text = @"Yêu cầu Level";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", self.itemData[@"level"]];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Số lượng thêm";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)self.quantity];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Cấp độ (Level 0 - 15)";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"+%ld", (long)self.itemLevel];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"Vật phẩm Super (Hoàn hảo)";
            UISwitch* sw = [[UISwitch alloc] init];
            sw.on = self.isSuper;
            [sw addTarget:self action:@selector(onSuperToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else {
        NSDictionary* opt = self.availableOptions[indexPath.row];
        cell.textLabel.text = opt[@"label"];
        cell.detailTextLabel.text = nil;
        cell.accessoryView = nil;
        bool selected = [self.selectedOptions containsObject:opt[@"index"]];
        cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)onSuperToggled:(UISwitch*)sw {
    self.isSuper = sw.on;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            UIAlertController* a = [UIAlertController alertControllerWithTitle:@"Số lượng" message:@"Nhập số lượng muốn thêm (1 - 50)" preferredStyle:UIAlertControllerStyleAlert];
            [a addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
                textField.keyboardType = UIKeyboardTypeNumberPad;
                textField.text = [NSString stringWithFormat:@"%ld", (long)self.quantity];
            }];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                int q = [a.textFields.firstObject.text intValue];
                if (q >= 1 && q <= 50) self.quantity = q;
                [self.tableView reloadData];
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        } else if (indexPath.row == 1) {
            UIAlertController* a = [UIAlertController alertControllerWithTitle:@"Cấp độ Item" message:@"Nhập level (+0 đến +15)" preferredStyle:UIAlertControllerStyleAlert];
            [a addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
                textField.keyboardType = UIKeyboardTypeNumberPad;
                textField.text = [NSString stringWithFormat:@"%ld", (long)self.itemLevel];
            }];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                int l = [a.textFields.firstObject.text intValue];
                if (l >= 0 && l <= 15) self.itemLevel = l;
                [self.tableView reloadData];
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        }
    } else if (indexPath.section == 2) {
        NSDictionary* opt = self.availableOptions[indexPath.row];
        NSNumber* idx = opt[@"index"];
        if ([self.selectedOptions containsObject:idx]) {
            [self.selectedOptions removeObject:idx];
        } else {
            [self.selectedOptions addObject:idx];
        }
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

@end

@implementation HAMenuMainVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"HeroAge Mod Menu";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(onClose)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(onReload)];
    
    self.tabControl = [[UISegmentedControl alloc] initWithItems:@[@"Vật Phẩm", @"Chỉ Số", @"Tiền Tệ", @"Tiến Trình"]];
    self.tabControl.selectedSegmentIndex = 0;
    [self.tabControl addTarget:self action:@selector(onTabChanged) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.tabControl;
    
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];
    
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Tìm tên item, class, ID...";
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;
    
    [self loadCatalog];
}

- (void)onClose {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onReload {
    [self loadCatalog];
    [self.tableView reloadData];
}

- (void)loadCatalog {
    @try {
        HA::ThreadScope scope;
        self.catalogItems = HA::GetRuntimeCatalog();
        self.filteredItems = self.catalogItems;
    } @catch (NSException* e) {
        self.catalogItems = @[];
        self.filteredItems = @[];
    }
}

- (void)onTabChanged {
    BOOL isItemTab = (self.tabControl.selectedSegmentIndex == 0);
    self.navigationItem.searchController = isItemTab ? self.searchController : nil;
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString* q = [searchController.searchBar.text lowercaseString];
    if (q.length == 0) {
        self.filteredItems = self.catalogItems;
    } else {
        self.filteredItems = [self.catalogItems filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary* item, NSDictionary *bindings) {
            NSString* name = [item[@"name"] lowercaseString];
            NSString* type = [item[@"type"] lowercaseString];
            NSString* cls = [item[@"classes"] lowercaseString];
            NSString* idStr = [NSString stringWithFormat:@"%@", item[@"id"]];
            return [name containsString:q] || [type containsString:q] || [cls containsString:q] || [idStr isEqualToString:q];
        }]];
    }
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger tab = self.tabControl.selectedSegmentIndex;
    if (tab == 0) return 1;
    if (tab == 1) return 2; // Level/Exp, Stats
    if (tab == 2) return 1; // Currencies
    return 2; // Skills, Quests & Characters
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSInteger tab = self.tabControl.selectedSegmentIndex;
    if (tab == 0) return [NSString stringWithFormat:@"Danh mục Item (%lu)", (unsigned long)self.filteredItems.count];
    if (tab == 1) return section == 0 ? @"Cấp độ & Điểm" : @"Thuộc tính Nhân vật";
    if (tab == 2) return @"Tài chính / Tiền tệ Game";
    return section == 0 ? @"Mở Khóa Nhân Vật & Túi" : @"Kỹ Năng & Nhiệm Vụ";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger tab = self.tabControl.selectedSegmentIndex;
    if (tab == 0) return self.filteredItems.count;
    if (tab == 1) return section == 0 ? 5 : 7;
    if (tab == 2) return 3; // Coin, Diamond, WarehouseCoin
    return section == 0 ? 1 : 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger tab = self.tabControl.selectedSegmentIndex;
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"M"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"M"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    
    if (tab == 0) {
        NSDictionary* it = self.filteredItems[indexPath.row];
        cell.textLabel.text = it[@"name"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ | ID: %@ | Class: %@", it[@"type"], it[@"id"], it[@"classes"]];
    } else if (tab == 1) {
        NSArray* s0 = @[@"Level", @"Experience", @"Point", @"SkillPoint", @"ResetCount"];
        NSArray* s1 = @[@"Strength", @"Agility", @"Vitality", @"Energy", @"Command", @"CurrentHealth", @"CurrentMana"];
        NSString* statName = (indexPath.section == 0) ? s0[indexPath.row] : s1[indexPath.row];
        cell.textLabel.text = statName;
        @try {
            HA::ThreadScope scope;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", HA::GetPlayerStat(statName)];
        } @catch (NSException* e) {
            cell.detailTextLabel.text = @"-";
        }
    } else if (tab == 2) {
        NSArray* cNames = @[@"Coin", @"Diamond", @"WarehouseCoin"];
        NSString* c = cNames[indexPath.row];
        cell.textLabel.text = c;
        @try {
            HA::ThreadScope scope;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lld", (long long)HA::GetCurrency(c)];
        } @catch (NSException* e) {
            cell.detailTextLabel.text = @"-";
        }
    } else {
        if (indexPath.section == 0) {
            cell.textLabel.text = @"Mở khóa tất cả Nhân vật & Kho";
            cell.detailTextLabel.text = @"MagicKnight, Summoner, Warlord, Fighter, Lancer, Slot 4/5";
        } else {
            NSArray* acts = @[@"Mở khóa tất cả Kỹ năng", @"Max điểm toàn bộ Kỹ năng", @"Hoàn thành toàn bộ Nhiệm vụ"];
            NSArray* descs = @[@"Mở khóa mọi skill của Class hiện tại", @"Nâng tối đa level tất cả skill đã học", @"Kích hoạt xong tất cả nhiệm vụ trong game"];
            cell.textLabel.text = acts[indexPath.row];
            cell.detailTextLabel.text = descs[indexPath.row];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSInteger tab = self.tabControl.selectedSegmentIndex;
    
    if (tab == 0) {
        NSDictionary* it = self.filteredItems[indexPath.row];
        HAItemDetailVC* detail = [[HAItemDetailVC alloc] init];
        detail.itemData = it;
        [self.navigationController pushViewController:detail animated:YES];
    } else if (tab == 1) {
        NSArray* s0 = @[@"Level", @"Experience", @"Point", @"SkillPoint", @"ResetCount"];
        NSArray* s1 = @[@"Strength", @"Agility", @"Vitality", @"Energy", @"Command", @"CurrentHealth", @"CurrentMana"];
        NSString* statName = (indexPath.section == 0) ? s0[indexPath.row] : s1[indexPath.row];
        
        UIAlertController* a = [UIAlertController alertControllerWithTitle:statName message:@"Nhập giá trị mới" preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.keyboardType = UIKeyboardTypeNumberPad;
        }];
        [a addAction:[UIAlertAction actionWithTitle:@"Cập nhật" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            int val = [a.textFields.firstObject.text intValue];
            @try {
                HA::ThreadScope scope;
                HA::SetPlayerStat(statName, val);
                [self.tableView reloadData];
            } @catch (NSException* e) {
                // handle error
            }
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    } else if (tab == 2) {
        NSArray* cNames = @[@"Coin", @"Diamond", @"WarehouseCoin"];
        NSString* c = cNames[indexPath.row];
        
        UIAlertController* a = [UIAlertController alertControllerWithTitle:c message:@"Nhập số lượng" preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.keyboardType = UIKeyboardTypeNumberPad;
        }];
        [a addAction:[UIAlertAction actionWithTitle:@"Xác nhận" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            long long val = [a.textFields.firstObject.text longLongValue];
            @try {
                HA::ThreadScope scope;
                HA::SetCurrency(c, val);
                [self.tableView reloadData];
            } @catch (NSException* e) {}
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    } else {
        if (indexPath.section == 0) {
            @try {
                HA::ThreadScope scope;
                HA::UnlockAllCharacters();
                UIAlertController* a = [UIAlertController alertControllerWithTitle:@"Thành công" message:@"Đã mở khóa toàn bộ nhân vật và ô slot!" preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:a animated:YES completion:nil];
            } @catch (NSException* e) {}
        } else {
            @try {
                HA::ThreadScope scope;
                if (indexPath.row == 0) {
                    HA::UnlockAllSkills(false);
                } else if (indexPath.row == 1) {
                    HA::UnlockAllSkills(true);
                } else if (indexPath.row == 2) {
                    HA::FinishAllQuests();
                }
                UIAlertController* a = [UIAlertController alertControllerWithTitle:@"Thành công" message:@"Đã thực hiện xong thao tác!" preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:a animated:YES completion:nil];
            } @catch (NSException* e) {}
        }
    }
}

@end

// -------------------------------------------------------------
// Floating Button Trigger Launcher
// -------------------------------------------------------------

@interface HAButtonLauncher : NSObject
@property (nonatomic, strong) UIButton* floatBtn;
- (void)attach;
- (void)openMenu;
@end

@implementation HAButtonLauncher

- (void)attach {
    if (self.floatBtn.superview) return;
    
    UIWindow* win = nil;
    for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) {
            UIWindowScene* ws = (UIWindowScene*)s;
            for (UIWindow* w in ws.windows) {
                if (w.isKeyWindow) { win = w; break; }
            }
            if (win) break;
        }
    }
    if (!win) return;
    
    self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatBtn.frame = CGRectMake(win.bounds.size.width - 65, 120, 50, 50);
    self.floatBtn.layer.cornerRadius = 25;
    self.floatBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.18 alpha:0.85];
    self.floatBtn.layer.borderColor = [UIColor colorWithRed:0.84 green:0.65 blue:0.25 alpha:0.9].CGColor;
    self.floatBtn.layer.borderWidth = 1.5;
    self.floatBtn.layer.shadowColor = [UIColor blackColor].CGColor;
    self.floatBtn.layer.shadowOpacity = 0.5;
    self.floatBtn.layer.shadowOffset = CGSizeMake(0, 3);
    self.floatBtn.layer.shadowRadius = 4;
    
    [self.floatBtn setTitle:@"HA" forState:UIControlStateNormal];
    [self.floatBtn setTitleColor:[UIColor colorWithRed:0.84 green:0.65 blue:0.25 alpha:1.0] forState:UIControlStateNormal];
    self.floatBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    
    [self.floatBtn addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [self.floatBtn addGestureRecognizer:pan];
    
    [win addSubview:self.floatBtn];
}

- (void)onPan:(UIPanGestureRecognizer*)p {
    UIView* v = p.view;
    CGPoint translation = [p translationInView:v.superview];
    v.center = CGPointMake(v.center.x + translation.x, v.center.y + translation.y);
    [p setTranslation:CGPointZero inView:v.superview];
}

- (void)openMenu {
    UIWindow* win = self.floatBtn.window;
    UIViewController* top = win.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if (!top || [top isKindOfClass:[HAMenuMainVC class]]) return;
    
    HAMenuMainVC* mainVC = [[HAMenuMainVC alloc] init];
    UINavigationController* nav = [[UINavigationController alloc] initWithRootViewController:mainVC];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [top presentViewController:nav animated:YES completion:nil];
}

@end

__attribute__((constructor)) static void Entry() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        static HAButtonLauncher* launcher;
        launcher = [[HAButtonLauncher alloc] init];
        [launcher attach];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            [launcher attach];
        }];
    });
}
