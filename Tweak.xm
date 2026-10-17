// HeroAge 6.2.10 Mod Menu Tweak
// Source-only delivery for compile with Theos / iOS toolchain
// Architecture: arm64 / arm64e, iOS 14.0+
// Frameworks: UIKit, Foundation, CoreGraphics, QuartzCore

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <stdint.h>
#include <cstring>
#include <climits>
#include <vector>
#include <string>

namespace HA {

[[noreturn]] static void Fail(NSString* message) {
    @throw [NSException exceptionWithName:@"HeroAgeException" reason:message userInfo:nil];
}

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
static void (*field_set_value)(Object*, Field*, void*);
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
static void (*runtime_class_init)(Class*);
static bool ready = false;
static bool auto_save_enabled = true;

// Continuous Combat Hack States
static float g_MoveSpeedMultiplier = 1.0f;
static int g_AttackSpeedBonus = 0;
static float g_DamageMultiplier = 1.0f;
static bool g_GodMode = false;
static bool g_ZeroMana = false;
static bool g_InfiniteMana = false;
static bool g_OneHitKill = false;
static bool g_NoCooldown = false;
static bool g_AttackAoE = false;
static bool g_AutoKill = false;
static bool g_BossDropEnabled = false;
static bool g_FreeCraft = true;

// 100% Craft Success Rate Hook via __DATA Function Pointer Redirection
typedef int (*RandomRangeInt_t)(int min, int max);
static RandomRangeInt_t orig_RandomRangeInt = nullptr;

static int hooked_RandomRangeInt(int min, int max) {
    if (g_FreeCraft && min == 0 && max == 100) {
        return 0; // 0 < rate (any rate >= 1) is always false for fail check, so craft 100% SUCCEEDS!
    }
    if (orig_RandomRangeInt) {
        return orig_RandomRangeInt(min, max);
    }
    return min;
}

static intptr_t GetUnityFrameworkSlide() {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) {
            return _dyld_get_image_vmaddr_slide(i);
        }
    }
    return -1;
}

static void InstallCraftSuccessHook() {
    intptr_t slide = GetUnityFrameworkSlide();
    if (slide >= 0) {
        // 0x25252D8 is off_25252D8 in __DATA segment
        uint8_t* base = reinterpret_cast<uint8_t*>(slide);
        void** pFuncPtr = reinterpret_cast<void**>(base + 0x25252D8);
        if (pFuncPtr) {
            // Trigger resolution if not yet resolved
            if (*pFuncPtr == nullptr) {
                typedef int (*TriggerFn)(int, int);
                TriggerFn trigger = reinterpret_cast<TriggerFn>(base + 0x1AF1A74);
                if (trigger) {
                    @try { trigger(0, 10); } @catch (id) {}
                }
            }
            if (*pFuncPtr != nullptr && *pFuncPtr != reinterpret_cast<void*>(hooked_RandomRangeInt)) {
                orig_RandomRangeInt = reinterpret_cast<RandomRangeInt_t>(*pFuncPtr);
                *pFuncPtr = reinterpret_cast<void*>(hooked_RandomRangeInt);
            }
        }
    }
}

static void Init() {
    if (ready) return;
#define LOAD(n) n = reinterpret_cast<decltype(n)>(dlsym(RTLD_DEFAULT, "il2cpp_" #n)); if (!n) return
    LOAD(domain_get); LOAD(domain_get_assemblies); LOAD(assembly_get_image);
    LOAD(class_from_name); LOAD(object_get_class); LOAD(class_get_field_from_name);
    LOAD(class_get_fields); LOAD(field_get_name); LOAD(field_get_type); LOAD(class_from_type);
    LOAD(class_get_name); LOAD(field_get_value); LOAD(field_static_get_value); LOAD(field_get_flags);
    LOAD(class_get_method_from_name); LOAD(class_get_methods); LOAD(class_get_parent);
    LOAD(method_get_name); LOAD(method_get_param_count); LOAD(method_get_param);
    LOAD(type_get_type); LOAD(runtime_invoke); LOAD(object_unbox);
    LOAD(string_length); LOAD(string_chars); LOAD(thread_current); LOAD(thread_attach);
    LOAD(runtime_class_init);
    LOAD(field_set_value);
#undef LOAD
    if (!domain_get || !domain_get()) return;
    ready = true;
}

// Thread attachment without destructive detaching that crashes Unity main loop
struct ThreadScope {
    ThreadScope() {
        Init();
        if (domain_get && thread_current && thread_attach) {
            void* domain = domain_get();
            if (domain && !thread_current()) {
                thread_attach(domain);
            }
        }
    }
};

static Class* FindClass(const char* name, const char* namespaze = "") {
    Init();
    if (!domain_get || !domain_get_assemblies || !assembly_get_image || !class_from_name) return nullptr;
    void* domain = domain_get();
    if (!domain) return nullptr;
    
    size_t count = 0;
    const void** assemblies = domain_get_assemblies(domain, &count);
    if (!assemblies || count == 0) return nullptr;
    
    Class* res = nullptr;
    for (size_t i = 0; i < count; ++i) {
        void* img = assembly_get_image(assemblies[i]);
        if (!img) continue;
        Class* c = class_from_name(img, namespaze, name);
        if (c) {
            res = c;
            break;
        }
    }
    if (res && runtime_class_init) {
        runtime_class_init(res);
    }
    return res;
}

// Safe invoke that never throws or crashes
static Object* Invoke(Class* klass, Object* obj, const char* name, int argCount = 0, void** args = nullptr) {
    if (!klass || !runtime_invoke || !class_get_method_from_name) return nullptr;
    Method* m = class_get_method_from_name(klass, name, argCount);
    if (!m) return nullptr;
    Object* exc = nullptr;
    Object* ret = runtime_invoke(m, obj, args, &exc);
    if (exc) return nullptr;
    return ret;
}

static Object* Invoke(Object* obj, const char* name, int argCount = 0, void** args = nullptr) {
    if (!obj || !object_get_class) return nullptr;
    Class* k = object_get_class(obj);
    if (!k) return nullptr;
    return Invoke(k, obj, name, argCount, args);
}

template<typename T>
static T Unbox(Object* boxed) {
    if (!boxed || !object_unbox) return T{};
    T val{};
    memcpy(&val, object_unbox(boxed), sizeof(T));
    return val;
}

template<typename T>
static T GetFieldValue(Class* klass, Object* obj, const char* name) {
    if (!klass || !class_get_field_from_name) return T{};
    Field* f = class_get_field_from_name(klass, name);
    if (!f) return T{};
    T val{};
    if (field_get_flags(f) & 0x10) {
        if (field_static_get_value) field_static_get_value(f, &val);
    } else {
        if (obj && field_get_value) field_get_value(obj, f, &val);
    }
    return val;
}

static Object* GetSingleton(const char* klassName, const char* fieldName) {
    Class* k = FindClass(klassName);
    if (!k) return nullptr;
    return GetFieldValue<Object*>(k, nullptr, fieldName);
}

static Object* GetPlayer() {
    return GetSingleton("Players", "MainPlayer");
}

static Object* GetMainCharacter() {
    Object* gc = GetSingleton("GameController", "instance");
    if (!gc || !object_get_class) return nullptr;
    return GetFieldValue<Object*>(object_get_class(gc), gc, "MainPlayer");
}

static NSString* StringFromIL2CPP(Object* strObj) {
    if (!strObj) return @"";
    @try {
        int32_t len = string_length ? string_length(strObj) : *reinterpret_cast<int32_t*>(reinterpret_cast<uint8_t*>(strObj) + 0x10);
        if (len <= 0 || len > 10000) return @"";
        const uint16_t* chars = string_chars ? string_chars(strObj) : reinterpret_cast<const uint16_t*>(reinterpret_cast<uint8_t*>(strObj) + 0x14);
        if (!chars) return @"";
        return [[NSString alloc] initWithCharacters:reinterpret_cast<const unichar*>(chars) length:len];
    } @catch (id) {
        return @"";
    }
}

// Reference arrays and inline Int32 enum arrays require different element strides.
static int ArrayLength(Object* arr) {
    if (!arr) return 0;
    return *reinterpret_cast<int32_t*>(reinterpret_cast<uint8_t*>(arr) + 0x18);
}

static Object* ArrayGet(Object* arr, int idx) {
    if (!arr) return nullptr;
    int len = ArrayLength(arr);
    if (idx < 0 || idx >= len) return nullptr;
    return reinterpret_cast<Object**>(reinterpret_cast<uint8_t*>(arr) + 0x20)[idx];
}

static int32_t ArrayGetInt32(Object* arr, int idx) {
    if (!arr || idx < 0 || idx >= ArrayLength(arr)) Fail(@"Chỉ số mảng class không hợp lệ.");
    int32_t value;
    memcpy(&value, reinterpret_cast<const uint8_t*>(arr) + 0x20 + sizeof(value) * idx, sizeof(value));
    return value;
}

static NSString* GetEnumName(const char* enumClassName, int val) {
    Class* k = FindClass(enumClassName);
    if (!k || !class_get_fields) return [NSString stringWithFormat:@"%d", val];
    void* iter = nullptr;
    while (Field* f = class_get_fields(k, &iter)) {
        if (field_get_flags(f) & 0x40) {
            int c = 0;
            if (field_static_get_value) field_static_get_value(f, &c);
            if (c == val && field_get_name) return [NSString stringWithUTF8String:field_get_name(f)];
        }
    }
    return [NSString stringWithFormat:@"%d", val];
}

// -------------------------------------------------------------
// Auto-Save & Manual Save
// -------------------------------------------------------------

static void SaveGameData() {
    @try {
        Object* p = GetPlayer();
        if (p) {
            bool collect = true;
            void* args[] = { &collect };
            Invoke(p, "Save", 1, args);
        }
        Class* gc = FindClass("GameConfig");
        if (gc) {
            Invoke(gc, nullptr, "Save");
        }
    } @catch (id) {}
}

static void CheckAutoSave() {
    if (auto_save_enabled) {
        SaveGameData();
    }
}

// -------------------------------------------------------------
// Gameplay & Stats Core (Crash-Proof)
// -------------------------------------------------------------

static int GetPlayerStat(NSString* name) {
    Object* p = GetPlayer();
    if (!p || !object_get_class) return 0;
    if ([name isEqualToString:@"UpgradeLuck"])
        return GetFieldValue<uint8_t>(object_get_class(p), p, "UpgradeLuck");
    std::string methodName = "get_" + std::string([name UTF8String]);
    Method* m = class_get_method_from_name(object_get_class(p), methodName.c_str(), 0);
    if (!m) return 0;
    Object* exc = nullptr;
    Object* ret = runtime_invoke(m, p, nullptr, &exc);
    if (exc || !ret) return 0;
    return Unbox<int>(ret);
}

static void SetPlayerStat(NSString* name, int value) {
    Object* p = GetPlayer();
    if ([name isEqualToString:@"UpgradeLuck"]) {
        if (!p || !object_get_class || !field_set_value) Fail(@"Chưa có nhân vật hoặc API ghi field.");
        if (value < 0 || value > UINT8_MAX) Fail(@"UpgradeLuck chỉ nhận 0–255.");
        Field* field = class_get_field_from_name(object_get_class(p), "UpgradeLuck");
        if (!field || type_get_type(field_get_type(field)) != 0x05)
            Fail(@"UpgradeLuck không tồn tại hoặc không phải Byte.");
        uint8_t luck = static_cast<uint8_t>(value);
        field_set_value(p, field, &luck);
        uint8_t actual = 0;
        field_get_value(p, field, &actual);
        if (actual != luck) Fail(@"Giá trị UpgradeLuck đọc lại không khớp.");
        CheckAutoSave();
        return;
    }
    if (!p || !object_get_class) return;
    std::string methodName = "set_" + std::string([name UTF8String]);
    void* args[] = { &value };
    Invoke(p, methodName.c_str(), 1, args);
    CheckAutoSave();
}

static int64_t GetCurrency(NSString* key) {
    @try {
        if ([key isEqualToString:@"Coin"]) {
            return GetPlayerStat(@"Coin");
        } else if ([key isEqualToString:@"Diamond"]) {
            Class* gc = FindClass("GameConfig");
            if (!gc) return 0;
            Method* m = class_get_method_from_name(gc, "get_Diamond", 0);
            if (!m) return 0;
            Object* exc = nullptr;
            Object* ret = runtime_invoke(m, nullptr, nullptr, &exc);
            if (exc || !ret) return 0;
            return Unbox<int>(ret);
        } else if ([key isEqualToString:@"WarehouseCoin"]) {
            Class* gc = FindClass("GameConfig");
            if (!gc) return 0;
            Method* m = class_get_method_from_name(gc, "get_WarehouseCoin", 0);
            if (!m) return 0;
            Object* exc = nullptr;
            Object* ret = runtime_invoke(m, nullptr, nullptr, &exc);
            if (exc || !ret) return 0;
            return Unbox<int64_t>(ret);
        }
    } @catch (id) {}
    return 0;
}

static void SetCurrency(NSString* key, int64_t val) {
    if ([key isEqualToString:@"Coin"]) {
        int v = (int)val;
        SetPlayerStat(@"Coin", v);
    } else if ([key isEqualToString:@"Diamond"]) {
        int v = (int)val;
        Class* gc = FindClass("GameConfig");
        if (gc) {
            void* args[] = { &v };
            Invoke(gc, nullptr, "set_Diamond", 1, args);
        }
    } else if ([key isEqualToString:@"WarehouseCoin"]) {
        Class* gc = FindClass("GameConfig");
        if (gc) {
            void* args[] = { &val };
            Invoke(gc, nullptr, "set_WarehouseCoin", 1, args);
        }
    }
    CheckAutoSave();
}

// Unlock All Characters & Slots
static void UnlockAllCharacters() {
    Class* gc = FindClass("GameConfig");
    if (!gc) return;
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
    CheckAutoSave();
}

// Skills & Passives
static void UnlockAllSkills(bool maxPoints) {
    Object* p = GetPlayer();
    if (!p) return;
    Object* gc = GetSingleton("GameController", "instance");
    if (!gc) return;
    Object* skillModelsArr = GetFieldValue<Object*>(object_get_class(gc), gc, "SkillModels");
    if (!skillModelsArr) return;
    
    int total = ArrayLength(skillModelsArr);
    int playerClass = Unbox<int>(Invoke(p, "get_ClassType"));
    
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
        
        Object* forClassArr = GetFieldValue<Object*>(object_get_class(skill), skill, "ForClass");
        bool classMatch = false;
        if (forClassArr) {
            int fcCount = ArrayLength(forClassArr);
            if (fcCount == 0) classMatch = true;
            for (int c = 0; c < fcCount; ++c) {
                int cType = ArrayGetInt32(forClassArr, c);
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
    CheckAutoSave();
}

// Complete All Quests
static void FinishAllQuests() {
    Object* p = GetPlayer();
    if (!p) return;
    Object* qc = GetSingleton("QuestController", "instance");
    if (!qc) return;
    Object* questInfoArr = GetFieldValue<Object*>(object_get_class(qc), qc, "QuestInfo");
    if (!questInfoArr) return;
    
    int total = ArrayLength(questInfoArr);
    for (int i = 0; i < total; ++i) {
        Object* qObj = ArrayGet(questInfoArr, i);
        if (!qObj) continue;
        int qId = *reinterpret_cast<int*>(object_unbox(qObj));
        if (qId <= 0) continue;
        
        void* args[] = { &qId };
        Invoke(p, "SetQuestReceived", 1, args);
        Invoke(p, "SetQuestCompleted", 1, args);
    }
    CheckAutoSave();
}

// -------------------------------------------------------------
// Monster Management & Boss Drops (Direct Memory List Access)
// -------------------------------------------------------------

static int ConvertAllMonstersToBossDrop() {
    Object* gc = GetSingleton("GameController", "instance");
    if (!gc) return 0;
    
    Object* list = GetFieldValue<Object*>(object_get_class(gc), gc, "_monsters");
    if (!list) return 0;
    
    int32_t size = *reinterpret_cast<int32_t*>(reinterpret_cast<uint8_t*>(list) + 0x18);
    uint8_t* itemsArray = *reinterpret_cast<uint8_t**>(reinterpret_cast<uint8_t*>(list) + 0x10);
    if (!itemsArray || size <= 0 || size > 1000) return 0;
    
    Object** items = reinterpret_cast<Object**>(itemsArray + 0x20);
    int converted = 0;
    for (int i = 0; i < size; ++i) {
        Object* monster = items[i];
        if (!monster) continue;
        
        uint8_t* pM = reinterpret_cast<uint8_t*>(monster);
        
        int32_t* pLevel = reinterpret_cast<int32_t*>(pM + 0x74);
        if (*pLevel < 350) *pLevel = 350;
        
        int32_t* pEffectLvl = reinterpret_cast<int32_t*>(pM + 0xB0);
        *pEffectLvl = 3;
        
        bool* pSuper = reinterpret_cast<bool*>(pM + 0xB4);
        *pSuper = true;
        bool* pGod = reinterpret_cast<bool*>(pM + 0xB5);
        *pGod = true;
        
        float* pDef = reinterpret_cast<float*>(pM + 0x90);
        *pDef = 0.0f;
        float* pDefRate = reinterpret_cast<float*>(pM + 0x94);
        *pDefRate = 0.0f;
        float* pEliteRes = reinterpret_cast<float*>(pM + 0x124);
        *pEliteRes = 0.0f;
        uint8_t* pIgnoreDmg = reinterpret_cast<uint8_t*>(pM + 0x12C);
        *pIgnoreDmg = 0;
        
        converted++;
    }
    return converted;
}

static int KillAllMonsters() {
    Object* gc = GetSingleton("GameController", "instance");
    if (!gc) return 0;
    
    Object* list = GetFieldValue<Object*>(object_get_class(gc), gc, "_monsters");
    if (!list) return 0;
    
    int32_t size = *reinterpret_cast<int32_t*>(reinterpret_cast<uint8_t*>(list) + 0x18);
    uint8_t* itemsArray = *reinterpret_cast<uint8_t**>(reinterpret_cast<uint8_t*>(list) + 0x10);
    if (!itemsArray || size <= 0 || size > 1000) return 0;
    
    Object** items = reinterpret_cast<Object**>(itemsArray + 0x20);
    int killed = 0;
    
    int finalDmg = 99999999;
    bool bFalse = false;
    void* hitArgs[] = { nullptr, &finalDmg, &finalDmg, &bFalse, &bFalse, &bFalse, &bFalse };
    
    for (int i = 0; i < size; ++i) {
        Object* monster = items[i];
        if (!monster) continue;
        
        bool isDied = GetFieldValue<bool>(object_get_class(monster), monster, "IsDied");
        if (!isDied) {
            if (g_BossDropEnabled) {
                uint8_t* pM = reinterpret_cast<uint8_t*>(monster);
                *reinterpret_cast<int32_t*>(pM + 0x74) = 350;
                *reinterpret_cast<int32_t*>(pM + 0xB0) = 3;
                *reinterpret_cast<bool*>(pM + 0xB4) = true;
                *reinterpret_cast<bool*>(pM + 0xB5) = true;
                *reinterpret_cast<float*>(pM + 0x90) = 0.0f;
                *reinterpret_cast<float*>(pM + 0x94) = 0.0f;
                *reinterpret_cast<float*>(pM + 0x124) = 0.0f;
                *reinterpret_cast<uint8_t*>(pM + 0x12C) = 0;
            }
            @try {
                Invoke(monster, "Hit", 7, hitArgs);
            } @catch (id) {
                @try { Invoke(monster, "Die"); } @catch (id) {}
            }
            killed++;
        }
    }
    return killed;
}

static void SpawnBoss(int bossType) {
    Object* gc = GetSingleton("GameController", "instance");
    if (!gc) return;
    
    Object* wm = GetFieldValue<Object*>(object_get_class(gc), gc, "WorldManager");
    if (!wm) return;
    
    switch (bossType) {
        case 0: Invoke(wm, "CheckAndCreateBoss"); break;
        case 1: Invoke(wm, "CheckAndCreateGlobalBoss"); break;
        case 2: Invoke(wm, "CheckAndCreateNarkanBoss"); break;
        case 3: Invoke(wm, "CheckAndCheckShadowOfNatas"); break;
        case 4: Invoke(wm, "CreateDarkMonaEvent"); break;
        default: break;
    }
}

static void SetExpRateMultiplier(int multiplier) {
    Class* gcClass = FindClass("GameController");
    if (!gcClass) return;
    Field* fExp = class_get_field_from_name(gcClass, "ExpRate");
    if (fExp && field_static_get_value) {
        field_static_get_value(fExp, &multiplier);
    }
}

// -------------------------------------------------------------
// Continuous Combat Parameters Applicator (Frame Loop)
// -------------------------------------------------------------

static void ApplyCombatModifiers() {
    Object* ch = GetMainCharacter();
    if (ch) {
        uint8_t* pCh = reinterpret_cast<uint8_t*>(ch);
        
        int32_t* pMoveRune = reinterpret_cast<int32_t*>(pCh + 0x150);
        *pMoveRune = static_cast<int32_t>((g_MoveSpeedMultiplier - 1.0f) * 100.0f);
        
        int32_t* pAtkRune = reinterpret_cast<int32_t*>(pCh + 0x14C);
        *pAtkRune = g_AttackSpeedBonus;
        int32_t* pAtkBuff = reinterpret_cast<int32_t*>(pCh + 0x304);
        *pAtkBuff = g_AttackSpeedBonus;
        
        float* pApproach = reinterpret_cast<float*>(pCh + 0x230);
        if (g_MoveSpeedMultiplier > 1.0f) *pApproach = 35.0f;
        
        float* pDmgDecrease = reinterpret_cast<float*>(pCh + 0x100);
        if (g_GodMode) {
            *pDmgDecrease = 100.0f;
        }
        
        *reinterpret_cast<int32_t*>(pCh + 0x334) = 99999999;
        *reinterpret_cast<int32_t*>(pCh + 0x314) = 99999999;
        *reinterpret_cast<int32_t*>(pCh + 0x324) = 100;
        *reinterpret_cast<uint8_t*>(pCh + 0x128) = 100;
        
        float* pWlDmg = reinterpret_cast<float*>(pCh + 0x11C);
        int32_t* pMinDmg = reinterpret_cast<int32_t*>(pCh + 0xE0);
        int32_t* pMaxDmg = reinterpret_cast<int32_t*>(pCh + 0xE4);
        int32_t* pMaxDmgRune = reinterpret_cast<int32_t*>(pCh + 0x13C);
        
        if (g_OneHitKill) {
            *pMinDmg = 99999999;
            *pMaxDmg = 99999999;
            *pMaxDmgRune = 99999999;
            *pWlDmg = 99999.0f;
        } else if (g_DamageMultiplier > 1.0f) {
            *pWlDmg = (g_DamageMultiplier - 1.0f) * 100.0f;
            *pMinDmg = static_cast<int32_t>(*pMinDmg * g_DamageMultiplier);
            *pMaxDmg = static_cast<int32_t>(*pMaxDmg * g_DamageMultiplier);
        }
    }
    
    Object* p = GetPlayer();
    if (p) {
        if (g_GodMode) {
            int maxHp = 99999999;
            void* hpArgs[] = { &maxHp };
            Invoke(p, "set_Health", 1, hpArgs);
            Invoke(p, "set_CurrentHealth", 1, hpArgs);
        }
        if (g_InfiniteMana) {
            int maxMp = 99999999;
            void* mpArgs[] = { &maxMp };
            Invoke(p, "set_Mana", 1, mpArgs);
            Invoke(p, "set_CurrentMana", 1, mpArgs);
        }
    }
    
    Object* gc = GetSingleton("GameController", "instance");
    if (gc) {
        Object* skillModelsArr = GetFieldValue<Object*>(object_get_class(gc), gc, "SkillModels");
        if (skillModelsArr) {
            int cnt = ArrayLength(skillModelsArr);
            for (int i = 0; i < cnt; ++i) {
                Object* sk = ArrayGet(skillModelsArr, i);
                if (!sk) continue;
                
                uint8_t* pSk = reinterpret_cast<uint8_t*>(sk);
                
                if (g_NoCooldown) {
                    *reinterpret_cast<float*>(pSk + 0x80) = 0.0f;
                }
                if (g_ZeroMana) {
                    *reinterpret_cast<float*>(pSk + 0x50) = 0.0f;
                }
                if (g_AttackAoE) {
                    *reinterpret_cast<float*>(pSk + 0x58) = 60.0f;
                    *reinterpret_cast<float*>(pSk + 0x5C) = 60.0f;
                    *reinterpret_cast<bool*>(pSk + 0x54) = true;
                }
                if (g_OneHitKill) {
                    *reinterpret_cast<float*>(pSk + 0x48) = 99999999.0f;
                    *reinterpret_cast<float*>(pSk + 0x4C) = 99999999.0f;
                }
            }
        }
        
        if (g_DamageMultiplier > 1.0f || g_OneHitKill) {
            Object* list = GetFieldValue<Object*>(object_get_class(gc), gc, "_monsters");
            if (list) {
                int32_t size = *reinterpret_cast<int32_t*>(reinterpret_cast<uint8_t*>(list) + 0x18);
                uint8_t* itemsArray = *reinterpret_cast<uint8_t**>(reinterpret_cast<uint8_t*>(list) + 0x10);
                if (itemsArray && size > 0 && size <= 1000) {
                    Object** items = reinterpret_cast<Object**>(itemsArray + 0x20);
                    for (int i = 0; i < size; ++i) {
                        Object* m = items[i];
                        if (!m) continue;
                        uint8_t* pM = reinterpret_cast<uint8_t*>(m);
                        *reinterpret_cast<float*>(pM + 0x90) = 0.0f;
                        *reinterpret_cast<float*>(pM + 0x94) = 0.0f;
                        *reinterpret_cast<float*>(pM + 0x124) = 0.0f;
                        *reinterpret_cast<uint8_t*>(pM + 0x12C) = 0;
                    }
                }
            }
        }
    }
}

// -------------------------------------------------------------
// Dynamic Catalog & Comprehensive Item Creation
// -------------------------------------------------------------

static NSArray<NSDictionary*>* GetOptionListForCategory(int category) {
    NSMutableArray<NSDictionary*>* list = [NSMutableArray array];
    Class* iu = FindClass("ItemUtils");
    if (!iu) return list;
    
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
    if (!gc || !object_get_class) return @[];
    
    Class* gcKlass = object_get_class(gc);
    if (!gcKlass) return @[];
    
    NSMutableDictionary<NSString*, NSDictionary*>* unique = [NSMutableDictionary dictionary];
    void* iter = nullptr;
    
    while (Field* f = class_get_fields(gcKlass, &iter)) {
        const Type* fType = field_get_type(f);
        if (!fType) continue;
        Class* ft = class_from_type(fType);
        if (!ft) continue;
        const char* ftName = class_get_name(ft);
        if (!ftName || strcmp(ftName, "ItemModel[]") != 0) continue;
        
        Object* arr = nullptr;
        field_get_value(gc, f, &arr);
        if (!arr) continue;
        
        int n = ArrayLength(arr);
        for (int i = 0; i < n; ++i) {
            Object* m = ArrayGet(arr, i);
            if (!m) continue;
            
            Class* mKlass = object_get_class(m);
            if (!mKlass) continue;
            
            int cat = GetFieldValue<int>(mKlass, m, "Category");
            uint8_t idByte = GetFieldValue<uint8_t>(mKlass, m, "Id");
            int idVal = (int)idByte;
            NSString* name = StringFromIL2CPP(GetFieldValue<Object*>(mKlass, m, "Name"));
            if (name.length == 0) continue;
            
            NSMutableArray* classes = [NSMutableArray array];
            Object* forClass = GetFieldValue<Object*>(mKlass, m, "ForClass");
            if (forClass) {
                int fcCount = ArrayLength(forClass);
                for (int c = 0; c < fcCount; ++c) {
                    int cVal = ArrayGetInt32(forClass, c);
                    [classes addObject:GetEnumName("ClassType", cVal)];
                }
            }
            
            int def = GetFieldValue<int>(mKlass, m, "Defense");
            int minD = GetFieldValue<int>(mKlass, m, "MinDamage");
            int maxD = GetFieldValue<int>(mKlass, m, "MaxDamage");
            int reqLvl = GetFieldValue<int>(mKlass, m, "LevelRequired");
            
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
// Advanced Item Creation: Full Options, God Type, Harmony, Sockets
// -------------------------------------------------------------

struct ItemOptionsConfig {
    int category;
    int itemId;
    int level;
    int quantity;
    bool isSuper;
    bool isHarmony;
    bool isChip;
    bool isPrimitive;
    int godType;
    int legendOption;
    int specialOption;
    std::vector<int> subOptions;
    bool dropAtPlayer;
};

static void CreateAndInjectItem(const ItemOptionsConfig& cfg) {
    Object* p = GetPlayer();
    if (!p) Fail(@"Chưa vào game.");
    Object* bucket = GetFieldValue<Object*>(object_get_class(p), p, "InventoryItems");
    if (!bucket) Fail(@"Không tìm thấy Inventory.");
    
    int bucketLen = Unbox<int>(Invoke(bucket, "get_Length"));
    std::vector<int> freeSlots;
    for (int i = 0; i < bucketLen; ++i) {
        void* args[] = { &i };
        int64_t val = Unbox<int64_t>(Invoke(bucket, "get_Item", 1, args));
        if (val == 0) freeSlots.push_back(i);
    }
    
    if (!cfg.dropAtPlayer && freeSlots.size() < (size_t)cfg.quantity) {
        Fail([NSString stringWithFormat:@"Không đủ ô trống trong túi đồ (Cần %d, Còn %lu).", cfg.quantity, freeSlots.size()]);
    }
    
    Class* itemUtils = FindClass("ItemUtils");
    Class* gameConfig = FindClass("GameConfig");
    
    bool isConsumable = (cfg.category == 6 || cfg.category == 8 || cfg.category == 10 || cfg.category == 17 || cfg.category == 20);
    
    for (int q = 0; q < cfg.quantity; ++q) {
        int opt1 = 0, opt2 = 0, opt3 = 0, opt4 = 0, opt5 = 0, opt6 = 0, opt7 = 0;
        int64_t opt8 = 0;
        
        if (!isConsumable) {
            for (int optIdx : cfg.subOptions) {
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
        
        int cat = cfg.category;
        int idVal = cfg.itemId;
        int lvl = cfg.level;
        
        void* createArgs[] = {
            &cat, &idVal, &lvl,
            &opt1, &opt2, &opt3, &opt4, &opt5, &opt6, &opt7, &opt8
        };
        
        int64_t rawItem = Unbox<int64_t>(Invoke(itemUtils, nullptr, "CreateItem", 11, createArgs));
        if (rawItem == 0) Fail(@"Không tạo được item qua ItemUtils.CreateItem.");
        
        if (cfg.isSuper) {
            void* superArgs[] = { &rawItem };
            rawItem = Unbox<int64_t>(Invoke(itemUtils, nullptr, "SetSuper", 1, superArgs));
        }
        
        if (cfg.isHarmony) {
            void* harmArgs[] = { &rawItem };
            rawItem = Unbox<int64_t>(Invoke(itemUtils, nullptr, "SetHarmony", 1, harmArgs));
        }
        
        if (cfg.isChip) {
            void* chipArgs[] = { &rawItem };
            rawItem = Unbox<int64_t>(Invoke(itemUtils, nullptr, "SetChipAttribute", 1, chipArgs));
        }
        
        if (cfg.godType > 0) {
            int gType = cfg.godType;
            void* godArgs[] = { &rawItem, &gType };
            Invoke(itemUtils, nullptr, "SetGodType", 2, godArgs);
        }
        
        if (cfg.legendOption >= 0) {
            int lOpt = cfg.legendOption;
            void* legArgs[] = { &rawItem, &lOpt };
            Invoke(itemUtils, nullptr, "SetLegendOption", 2, legArgs);
        }
        
        if (cfg.specialOption >= 0) {
            int sOpt = cfg.specialOption;
            void* specArgs[] = { &rawItem, &sOpt };
            Invoke(itemUtils, nullptr, "SetSpecialOption", 2, specArgs);
        }
        
        if (cfg.isPrimitive) {
            bool bTrue = true;
            void* primArgs[] = { &rawItem, &bTrue };
            Invoke(itemUtils, nullptr, "SetPrimitive", 2, primArgs);
        }
        
        if (isConsumable) {
            uint8_t amt = 1;
            void* amtArgs[] = { &rawItem, &amt };
            rawItem = Unbox<int64_t>(Invoke(itemUtils, nullptr, "SetAmount", 2, amtArgs));
        }
        
        void* regArgs[] = { &rawItem };
        Invoke(gameConfig, nullptr, "RegisterItem", 1, regArgs);
        
        if (cfg.dropAtPlayer) {
            Object* ch = GetMainCharacter();
            if (ch) {
                float posX = *reinterpret_cast<float*>(reinterpret_cast<uint8_t*>(ch) + 0x15C);
                float posY = *reinterpret_cast<float*>(reinterpret_cast<uint8_t*>(ch) + 0x160);
                
                @try {
                    Object* poolMgr = GetSingleton("PoolManager", "instance");
                    if (poolMgr) {
                        Method* mSpawn = class_get_method_from_name(object_get_class(poolMgr), "Spawn", 2);
                        if (mSpawn) {
                            void* args[] = { &rawItem };
                            Object* dropObj = Invoke(poolMgr, "Spawn", 2, args);
                            if (dropObj) {
                                void* setPosArgs[] = { &posX, &posY };
                                Invoke(dropObj, "SetPosition", 2, setPosArgs);
                                void* setItemArgs[] = { &rawItem };
                                Invoke(dropObj, "SetItem", 1, setItemArgs);
                            }
                        }
                    }
                } @catch (id) {
                    if (!freeSlots.empty()) {
                        int slot = freeSlots.back();
                        freeSlots.pop_back();
                        void* setArgs[] = { &slot, &rawItem };
                        Invoke(bucket, "set_Item", 2, setArgs);
                    }
                }
            }
        } else {
            int slot = freeSlots[q];
            void* setArgs[] = { &slot, &rawItem };
            Invoke(bucket, "set_Item", 2, setArgs);
        }
    }
    
    @try {
        Object* uiMgr = GetSingleton("UIManager", "instance");
        if (uiMgr) {
            Object* invDiag = GetFieldValue<Object*>(object_get_class(uiMgr), uiMgr, "InventoryDialog");
            if (invDiag) {
                Invoke(invDiag, "FillData");
            }
        }
    } @catch (id) {}
    
    CheckAutoSave();
}

// -------------------------------------------------------------
// In-Game Craft Machine Helper (Free Crafting, No Materials Needed)
// -------------------------------------------------------------

static int UpgradeAllEquippedToMax() {
    Object* p = GetPlayer();
    if (!p) return 0;
    
    Class* itemUtils = FindClass("ItemUtils");
    Class* gameConfig = FindClass("GameConfig");
    if (!itemUtils || !gameConfig) return 0;
    
    const char* slotProps[] = {
        "ArmorItem", "LeftHandItem", "RightHandItem", "LeftRing", "RightRing",
        "Pendant", "Wing", "Pet", "LeftEarring", "RightEarring"
    };
    
    int upgraded = 0;
    for (const char* prop : slotProps) {
        std::string getter = "get_" + std::string(prop);
        std::string setter = "set_" + std::string(prop);
        
        int64_t item = Unbox<int64_t>(Invoke(p, getter.c_str()));
        if (item != 0) {
            int lvl = 15;
            void* lvlArgs[] = { &item, &lvl };
            int64_t newItem = Unbox<int64_t>(Invoke(itemUtils, nullptr, "SetLevel", 2, lvlArgs));
            
            void* itemArgs[] = { &newItem };
            newItem = Unbox<int64_t>(Invoke(itemUtils, nullptr, "SetHarmony", 1, itemArgs));
            newItem = Unbox<int64_t>(Invoke(itemUtils, nullptr, "SetChipAttribute", 1, itemArgs));
            
            for (int opt = 0; opt < 8; ++opt) {
                void* optArgs[] = { &newItem, &opt };
                newItem = Unbox<int64_t>(Invoke(itemUtils, nullptr, "SetOption", 2, optArgs));
            }
            
            void* setArgs[] = { &newItem };
            Invoke(p, setter.c_str(), 1, setArgs);
            
            void* regArgs[] = { &newItem };
            Invoke(gameConfig, nullptr, "RegisterItem", 1, regArgs);
            
            upgraded++;
        }
    }
    CheckAutoSave();
    return upgraded;
}

static bool AutoFillCraftMachine() {
    @try {
        Object* uiMgr = GetSingleton("UIManager", "instance");
        if (!uiMgr || !object_get_class) return false;
        
        Object* craftDiag = GetFieldValue<Object*>(object_get_class(uiMgr), uiMgr, "CraftDialog");
        if (!craftDiag || !object_get_class) return false;
        
        // Check if CraftDialog is active using Component.get_gameObject and GameObject.get_activeInHierarchy
        Class* compClass = FindClass("Component", "UnityEngine");
        if (!compClass) return false;
        Object* go = Invoke(compClass, craftDiag, "get_gameObject");
        if (!go || !object_get_class) return false;
        
        Class* goClass = object_get_class(go);
        if (!goClass) return false;
        Method* mActive = class_get_method_from_name(goClass, "get_activeInHierarchy", 0);
        if (!mActive) return false;
        Object* exc = nullptr;
        Object* resActive = runtime_invoke(mActive, go, nullptr, &exc);
        if (exc || !resActive) return false;
        bool isActive = Unbox<bool>(resActive);
        if (!isActive) return false; // Dialog is closed! Don't do anything!
        
        Object* p = GetPlayer();
        if (!p) return false;
        Object* craftBucket = GetFieldValue<Object*>(object_get_class(p), p, "CraftItems");
        if (!craftBucket) return false;
        
        uint8_t* pDiag = reinterpret_cast<uint8_t*>(craftDiag);
        int mode = *reinterpret_cast<int32_t*>(pDiag + 0x120);
        
        Class* itemUtils = FindClass("ItemUtils");
        Class* gameConfig = FindClass("GameConfig");
        if (!itemUtils || !gameConfig) return false;
        
        auto setCraftSlot = [&](int slot, int cat, int id, int lvl, int optCount) {
            int opt1 = optCount > 0 ? 1 : 0;
            int opt2 = optCount > 1 ? 1 : 0;
            int opt3 = optCount > 2 ? 1 : 0;
            int opt4 = optCount > 3 ? 1 : 0;
            int opt5 = optCount > 4 ? 1 : 0;
            int opt6 = optCount > 5 ? 1 : 0;
            int opt7 = optCount > 6 ? 1 : 0;
            int64_t opt8 = optCount > 7 ? 1 : 0;
            
            void* createArgs[] = { &cat, &id, &lvl, &opt1, &opt2, &opt3, &opt4, &opt5, &opt6, &opt7, &opt8 };
            int64_t rawItem = Unbox<int64_t>(Invoke(itemUtils, nullptr, "CreateItem", 11, createArgs));
            if (cat == 6 || cat == 8 || cat == 20) {
                uint8_t amt = 10;
                void* amtArgs[] = { &rawItem, &amt };
                rawItem = Unbox<int64_t>(Invoke(itemUtils, nullptr, "SetAmount", 2, amtArgs));
            }
            void* setArgs[] = { &slot, &rawItem };
            Invoke(craftBucket, "set_Item", 2, setArgs);
            void* regArgs[] = { &rawItem };
            Invoke(gameConfig, nullptr, "RegisterItem", 1, regArgs);
        };
        
        int dummySlot = 0;
        void* slot0Args[] = { &dummySlot };
        int64_t slot0Val = Unbox<int64_t>(Invoke(craftBucket, "get_Item", 1, slot0Args));
        
        if (slot0Val == 0) {
            switch (mode) {
                case 1:
                    setCraftSlot(0, 3, 1, 10, 4);
                    setCraftSlot(1, 6, 1, 0, 0);
                    break;
                case 2:
                    setCraftSlot(0, 3, 1, 10, 6);
                    setCraftSlot(1, 6, 11, 0, 0);
                    break;
                case 3:
                    setCraftSlot(0, 14, 1, 10, 6);
                    setCraftSlot(1, 6, 11, 0, 0);
                    setCraftSlot(2, 6, 13, 0, 0);
                    break;
                case 4:
                    setCraftSlot(0, 14, 16, 15, 8);
                    setCraftSlot(1, 6, 14, 0, 0);
                    setCraftSlot(2, 6, 15, 0, 0);
                    break;
                case 5:
                case 6:
                    setCraftSlot(0, 6, 18, 0, 0);
                    setCraftSlot(1, 6, 19, 0, 0);
                    break;
                case 7:
                    setCraftSlot(0, 6, 22, 0, 0);
                    setCraftSlot(1, 6, 2, 0, 0);
                    setCraftSlot(2, 6, 3, 0, 0);
                    setCraftSlot(3, 6, 4, 0, 0);
                    setCraftSlot(4, 6, 5, 0, 0);
                    break;
                case 8:
                    setCraftSlot(0, 6, 23, 0, 0);
                    break;
                case 11:
                    setCraftSlot(0, 6, 24, 0, 0);
                    setCraftSlot(1, 3, 1, 15, 8);
                    break;
                case 12:
                case 20:
                    setCraftSlot(0, 16, 32, 0, 0);
                    setCraftSlot(1, 6, 1, 0, 0);
                    break;
                case 16:
                    setCraftSlot(0, 14, 16, 15, 8);
                    setCraftSlot(1, 14, 17, 15, 8);
                    break;
                case 18:
                    setCraftSlot(0, 6, 37, 0, 0);
                    setCraftSlot(1, 6, 39, 0, 0);
                    setCraftSlot(2, 6, 40, 0, 0);
                    break;
                case 19:
                    setCraftSlot(0, 6, 52, 0, 0);
                    break;
                case 21:
                    setCraftSlot(0, 6, 26, 0, 0);
                    setCraftSlot(1, 6, 27, 0, 0);
                    setCraftSlot(2, 6, 28, 0, 0);
                    break;
                case 22:
                    setCraftSlot(0, 23, 1, 0, 0);
                    setCraftSlot(1, 23, 2, 0, 0);
                    setCraftSlot(2, 23, 3, 0, 0);
                    setCraftSlot(3, 23, 4, 0, 0);
                    break;
                default:
                    setCraftSlot(0, 3, 1, 15, 8);
                    setCraftSlot(1, 6, 1, 0, 0);
                    setCraftSlot(2, 6, 11, 0, 0);
                    break;
            }
        }
        
        Invoke(craftDiag, "UpdateStatus");
        
        Class* cdKlass = object_get_class(craftDiag);
        Object* btn = GetFieldValue<Object*>(cdKlass, craftDiag, "CombineButton");
        if (btn) {
            bool bTrue = true;
            void* intArgs[] = { &bTrue };
            Invoke(btn, "set_interactable", 1, intArgs);
        }
        
        return true;
    } @catch (id) {
        return false;
    }
}

} // namespace HA

// -------------------------------------------------------------
// Continuous Frame Loop Engine (Prevents Resets & Drives AutoKill)
// -------------------------------------------------------------

@interface HAEngineLoop : NSObject
@property (nonatomic, strong) CADisplayLink* displayLink;
+ (instancetype)shared;
- (void)start;
- (void)stop;
@end

@implementation HAEngineLoop

+ (instancetype)shared {
    static HAEngineLoop* s = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [[HAEngineLoop alloc] init];
    });
    return s;
}

- (void)start {
    if (self.displayLink) return;
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onTick:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stop {
    [self.displayLink invalidate];
    self.displayLink = nil;
}

- (void)onTick:(CADisplayLink*)link {
    static int tickCount = 0;
    tickCount++;
    
    @try {
        HA::ThreadScope scope;
        
        // Hook 100% craft success rate if not yet hooked
        if (tickCount % 60 == 0) {
            HA::InstallCraftSuccessHook();
        }
        
        // Only run combat modifications if character exists
        if (HA::GetMainCharacter() && HA::GetPlayer()) {
            HA::ApplyCombatModifiers();
            
            if (HA::g_AutoKill && (tickCount % 10 == 0)) {
                HA::KillAllMonsters();
            }
            
            if (HA::g_FreeCraft && (tickCount % 30 == 0)) {
                HA::AutoFillCraftMachine();
            }
        }
    } @catch (id) {}
}

@end

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
@property (nonatomic, assign) BOOL isHarmony;
@property (nonatomic, assign) BOOL isChip;
@property (nonatomic, assign) BOOL isPrimitive;
@property (nonatomic, assign) NSInteger godType;
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
    self.itemLevel = 15;
    self.isSuper = YES;
    self.isHarmony = YES;
    self.isChip = YES;
    self.isPrimitive = NO;
    self.godType = 1;
    
    int cat = [self.itemData[@"category"] intValue];
    self.availableOptions = HA::GetOptionListForCategory(cat);
    for (NSDictionary* opt in self.availableOptions) {
        [self.selectedOptions addObject:opt[@"index"]];
    }
    
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
    [self executeCreateItem:NO];
}

- (void)executeCreateItem:(BOOL)dropOnGround {
    HA::ItemOptionsConfig cfg;
    cfg.category = [self.itemData[@"category"] intValue];
    cfg.itemId = [self.itemData[@"id"] intValue];
    cfg.level = (int)self.itemLevel;
    cfg.quantity = (int)self.quantity;
    cfg.isSuper = self.isSuper;
    cfg.isHarmony = self.isHarmony;
    cfg.isChip = self.isChip;
    cfg.isPrimitive = self.isPrimitive;
    cfg.godType = (int)self.godType;
    cfg.legendOption = 0;
    cfg.specialOption = 0;
    cfg.dropAtPlayer = dropOnGround;
    
    for (NSNumber* n in self.selectedOptions) {
        cfg.subOptions.push_back([n intValue]);
    }
    
    @try {
        HA::ThreadScope scope;
        HA::CreateAndInjectItem(cfg);
        
        NSString* msg = dropOnGround ? 
            [NSString stringWithFormat:@"Đã rớt %ldx %@ Full Dòng ngay chân bạn!", (long)self.quantity, self.itemData[@"name"]] :
            [NSString stringWithFormat:@"Đã thêm %ldx %@ Full Dòng vào túi đồ!", (long)self.quantity, self.itemData[@"name"]];
            
        UIAlertController* a = [UIAlertController alertControllerWithTitle:@"Thành công"
                                                                   message:msg
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
    return self.availableOptions.count > 0 ? 5 : 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Thông tin Vật phẩm";
    if (section == 1) return @"Cài đặt Cấp độ & Số lượng";
    if (section == 2) return @"Dòng Đặc Biệt (Tím / Vàng / Super / Chip)";
    if (section == 3) return @"Hành động Nhanh";
    return @"Dòng phụ thường (Option dòng)";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;
    if (section == 1) return 2;
    if (section == 2) return 5;
    if (section == 3) return 2;
    return self.availableOptions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"C"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"C"];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
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
            cell.textLabel.text = @"Số lượng tạo";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)self.quantity];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"Cấp độ (Level 0 - 15)";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"+%ld", (long)self.itemLevel];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Dòng Hoàn Hảo (Super / Ex)";
            UISwitch* sw = [[UISwitch alloc] init];
            sw.on = self.isSuper;
            [sw addTarget:self action:@selector(onSuperToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Dòng Tím (Harmony / Đá Tạo Hóa)";
            UISwitch* sw = [[UISwitch alloc] init];
            sw.on = self.isHarmony;
            [sw addTarget:self action:@selector(onHarmonyToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Dòng Chip (Chip Attribute)";
            UISwitch* sw = [[UISwitch alloc] init];
            sw.on = self.isChip;
            [sw addTarget:self action:@selector(onChipToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Dòng Vàng / Thần (God Set)";
            cell.detailTextLabel.text = self.godType > 0 ? [NSString stringWithFormat:@"Set Thần #%ld", (long)self.godType] : @"Tắt";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"Dòng Nguyên Thủy (Primitive)";
            UISwitch* sw = [[UISwitch alloc] init];
            sw.on = self.isPrimitive;
            [sw addTarget:self action:@selector(onPrimitiveToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Rớt đồ ngay chân người chơi (Spawn on Ground)";
            cell.detailTextLabel.text = @"Rớt xuống đất";
        } else {
            cell.textLabel.text = @"Tối Thượng: Bật Hết Dòng (Max All)";
            cell.detailTextLabel.text = @"+15, Tím, Vàng, Chip, Super, Full Dòng";
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

- (void)onSuperToggled:(UISwitch*)sw { self.isSuper = sw.on; }
- (void)onHarmonyToggled:(UISwitch*)sw { self.isHarmony = sw.on; }
- (void)onChipToggled:(UISwitch*)sw { self.isChip = sw.on; }
- (void)onPrimitiveToggled:(UISwitch*)sw { self.isPrimitive = sw.on; }

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            UIAlertController* a = [UIAlertController alertControllerWithTitle:@"Số lượng" message:@"Nhập số lượng muốn tạo (1 - 50)" preferredStyle:UIAlertControllerStyleAlert];
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
    } else if (indexPath.section == 2 && indexPath.row == 3) {
        UIAlertController* a = [UIAlertController alertControllerWithTitle:@"Set Thần (Dòng Vàng)" message:@"Nhập ID Set Thần (0 = Tắt, 1 đến 10)" preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.keyboardType = UIKeyboardTypeNumberPad;
            textField.text = [NSString stringWithFormat:@"%ld", (long)self.godType];
        }];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            int g = [a.textFields.firstObject.text intValue];
            if (g >= 0 && g <= 100) self.godType = g;
            [self.tableView reloadData];
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            [self executeCreateItem:YES];
        } else {
            self.itemLevel = 15;
            self.isSuper = YES;
            self.isHarmony = YES;
            self.isChip = YES;
            self.isPrimitive = YES;
            self.godType = 1;
            for (NSDictionary* opt in self.availableOptions) {
                [self.selectedOptions addObject:opt[@"index"]];
            }
            [self.tableView reloadData];
        }
    } else if (indexPath.section == 4) {
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
    
    self.tabControl = [[UISegmentedControl alloc] initWithItems:@[@"Vật Phẩm", @"Chỉ Số", @"Chiến Đấu", @"Chế Tạo", @"Quái & Boss", @"Tiến Trình"]];
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
    } @catch (id) {
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
    if (tab == 1) return 3; // Level/Exp, Stats, Currencies
    if (tab == 2) return 3; // GodMode/OneHit/Mana, Speed/Damage, Skill Cooldown/AoE
    if (tab == 3) return 1; // In-Game Craft Machine (100% Rate & Auto-Fill)
    if (tab == 4) return 2; // Monster Kill/Boss drops, Boss Spawns & Exp
    return 2; // Skills/Quests, Save & Options
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSInteger tab = self.tabControl.selectedSegmentIndex;
    if (tab == 0) return [NSString stringWithFormat:@"Danh mục Item (%lu)", (unsigned long)self.filteredItems.count];
    if (tab == 1) {
        if (section == 0) return @"Cấp độ & Điểm";
        if (section == 1) return @"Thuộc tính Nhân vật";
        return @"Tiền tệ Game";
    }
    if (tab == 2) {
        if (section == 0) return @"Đặc Quyền Bất Tử & Sát Thương";
        if (section == 1) return @"Tốc Độ & Sát Thương";
        return @"Cơ Chế Kỹ Năng";
    }
    if (tab == 3) {
        return @"Máy Ép Đồ Game & Trang Bị (100% Success Rate)";
    }
    if (tab == 4) {
        if (section == 0) return @"Tiêu Diệt & Rớt Đồ";
        return @"Triệu Hồi Boss & Hệ Số Exp";
    }
    return section == 0 ? @"Mở Khóa Nhân Vật & Tiến Trình" : @"Lưu Trữ Dữ Liệu";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger tab = self.tabControl.selectedSegmentIndex;
    if (tab == 0) return self.filteredItems.count;
    if (tab == 1) {
        if (section == 0) return 6;
        if (section == 1) return 7;
        return 3;
    }
    if (tab == 2) {
        if (section == 0) return 4;
        if (section == 1) return 3;
        return 2;
    }
    if (tab == 3) {
        return 2; // Free Craft Mode Switch, Max Upgrade All Equipped
    }
    if (tab == 4) {
        if (section == 0) return 3;
        return 6;
    }
    return section == 0 ? 4 : 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger tab = self.tabControl.selectedSegmentIndex;
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"M"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"M"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessoryView = nil;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    
    if (tab == 0) {
        if (indexPath.row < (NSInteger)self.filteredItems.count) {
            NSDictionary* it = self.filteredItems[indexPath.row];
            cell.textLabel.text = it[@"name"];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ | ID: %@ | Class: %@", it[@"type"], it[@"id"], it[@"classes"]];
        }
    } else if (tab == 1) {
        if (indexPath.section == 0) {
            NSArray* s0 = @[@"Level", @"Experience", @"Point", @"SkillPoint", @"ResetCount", @"UpgradeLuck"];
            NSString* statName = s0[indexPath.row];
            cell.textLabel.text = statName;
            @try {
                HA::ThreadScope scope;
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", HA::GetPlayerStat(statName)];
            } @catch (id) { cell.detailTextLabel.text = @"-"; }
        } else if (indexPath.section == 1) {
            NSArray* s1 = @[@"Strength", @"Agility", @"Vitality", @"Energy", @"Command", @"CurrentHealth", @"CurrentMana"];
            NSString* statName = s1[indexPath.row];
            cell.textLabel.text = statName;
            @try {
                HA::ThreadScope scope;
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", HA::GetPlayerStat(statName)];
            } @catch (id) { cell.detailTextLabel.text = @"-"; }
        } else {
            NSArray* cNames = @[@"Coin", @"Diamond", @"WarehouseCoin"];
            NSString* c = cNames[indexPath.row];
            cell.textLabel.text = c;
            @try {
                HA::ThreadScope scope;
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%lld", (long long)HA::GetCurrency(c)];
            } @catch (id) { cell.detailTextLabel.text = @"-"; }
        }
    } else if (tab == 2) {
        if (indexPath.section == 0) {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Bất Tử (God Mode / 100% Defense)";
                UISwitch* sw = [[UISwitch alloc] init];
                sw.on = HA::g_GodMode;
                [sw addTarget:self action:@selector(onGodModeToggled:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Vô Hạn Mana (Infinite MP)";
                UISwitch* sw = [[UISwitch alloc] init];
                sw.on = HA::g_InfiniteMana;
                [sw addTarget:self action:@selector(onInfiniteManaToggled:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
            } else if (indexPath.row == 2) {
                cell.textLabel.text = @"0 Mana Cost (Skill không tốn MP)";
                UISwitch* sw = [[UISwitch alloc] init];
                sw.on = HA::g_ZeroMana;
                [sw addTarget:self action:@selector(onZeroManaToggled:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
            } else {
                cell.textLabel.text = @"One-Hit Kill (Một Đòn Hạ Quái)";
                UISwitch* sw = [[UISwitch alloc] init];
                sw.on = HA::g_OneHitKill;
                [sw addTarget:self action:@selector(onOneHitToggled:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
            }
        } else if (indexPath.section == 1) {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Tốc độ di chuyển (Move Speed)";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1fx bình thường", HA::g_MoveSpeedMultiplier];
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Tốc độ đánh (Attack Speed Buff)";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"+%d tốc đánh", HA::g_AttackSpeedBonus];
            } else {
                cell.textLabel.text = @"Khuếch đại sát thương (Damage Multiplier)";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1fx sát thương", HA::g_DamageMultiplier];
            }
        } else {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Bỏ hồi chiêu (0s Cooldown All Skills)";
                UISwitch* sw = [[UISwitch alloc] init];
                sw.on = HA::g_NoCooldown;
                [sw addTarget:self action:@selector(onNoCooldownToggled:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
            } else {
                cell.textLabel.text = @"Phạm vi đánh AoE toàn map (Max Range + 360°)";
                UISwitch* sw = [[UISwitch alloc] init];
                sw.on = HA::g_AttackAoE;
                [sw addTarget:self action:@selector(onAttackAoEToggled:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
            }
        }
    } else if (tab == 3) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Chế Tạo Miễn Phí 100% (Free Craft Mode)";
            cell.detailTextLabel.text = @"Mở máy ép đồ game là bấm ép được luôn, tỷ lệ 100% không xịt";
            UISwitch* sw = [[UISwitch alloc] init];
            sw.on = HA::g_FreeCraft;
            [sw addTarget:self action:@selector(onFreeCraftToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else {
            cell.textLabel.text = @"Nâng cấp toàn bộ đồ đang mặc lên +15 Full Dòng";
            cell.detailTextLabel.text = @"Vũ khí, giáp, cánh, nhẫn, bông tai đang mặc lên +15, Tím, Vàng, Chip";
        }
    } else if (tab == 4) {
        if (indexPath.section == 0) {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Tự Động Diệt Quái Liên Tục (Auto-Kill Loop)";
                UISwitch* sw = [[UISwitch alloc] init];
                sw.on = HA::g_AutoKill;
                [sw addTarget:self action:@selector(onAutoKillToggled:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Tiêu diệt toàn bộ quái ngay lập tức (Kill All Now)";
                cell.detailTextLabel.text = @"Hạ quái hợp lệ, kích hoạt rơi đồ, exp và nhiệm vụ";
            } else {
                cell.textLabel.text = @"Chuyển drop quái thành Boss (Super & God Drop)";
                UISwitch* sw = [[UISwitch alloc] init];
                sw.on = HA::g_BossDropEnabled;
                [sw addTarget:self action:@selector(onBossDropToggled:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
            }
        } else {
            NSArray* bossList = @[
                @"Triệu hồi Boss Map (Spawn Map Boss)",
                @"Triệu hồi Global Boss",
                @"Triệu hồi Narkan Boss",
                @"Triệu hồi Shadow of Natas",
                @"Kích hoạt Dark Mona Event",
                @"Nhân hệ số Exp quái (Exp Rate Multiplier)"
            ];
            cell.textLabel.text = bossList[indexPath.row];
            cell.detailTextLabel.text = @"Nhấn để kích hoạt";
        }
    } else {
        if (indexPath.section == 0) {
            NSArray* acts = @[
                @"Mở khóa tất cả Nhân vật & Ô Slot",
                @"Mở khóa tất cả Kỹ năng",
                @"Max điểm toàn bộ Kỹ năng",
                @"Hoàn thành toàn bộ Nhiệm vụ"
            ];
            NSArray* descs = @[
                @"MagicKnight, Summoner, Warlord, Fighter, Lancer, Slot 4/5",
                @"Mở khóa toàn bộ skill của Class hiện tại",
                @"Nâng tối đa level tất cả skill đã học",
                @"Hoàn tất toàn bộ quest trong game"
            ];
            cell.textLabel.text = acts[indexPath.row];
            cell.detailTextLabel.text = descs[indexPath.row];
        } else {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Lưu Dữ Liệu Game (Save Now)";
                cell.detailTextLabel.text = @"Ghi toàn bộ trạng thái vào bộ nhớ lưu trữ";
            } else {
                cell.textLabel.text = @"Tự động lưu sau mỗi thao tác (Auto-Save)";
                UISwitch* sw = [[UISwitch alloc] init];
                sw.on = HA::auto_save_enabled;
                [sw addTarget:self action:@selector(onAutoSaveToggled:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
            }
        }
    }
    return cell;
}

- (void)onGodModeToggled:(UISwitch*)sw { HA::g_GodMode = sw.on; }
- (void)onInfiniteManaToggled:(UISwitch*)sw { HA::g_InfiniteMana = sw.on; }
- (void)onZeroManaToggled:(UISwitch*)sw { HA::g_ZeroMana = sw.on; }
- (void)onOneHitToggled:(UISwitch*)sw { HA::g_OneHitKill = sw.on; }
- (void)onNoCooldownToggled:(UISwitch*)sw { HA::g_NoCooldown = sw.on; }
- (void)onAttackAoEToggled:(UISwitch*)sw { HA::g_AttackAoE = sw.on; }
- (void)onAutoKillToggled:(UISwitch*)sw { HA::g_AutoKill = sw.on; }
- (void)onBossDropToggled:(UISwitch*)sw {
    HA::g_BossDropEnabled = sw.on;
    if (sw.on) {
        @try {
            HA::ThreadScope scope;
            HA::ConvertAllMonstersToBossDrop();
        } @catch (id) {}
    }
}
- (void)onFreeCraftToggled:(UISwitch*)sw {
    HA::g_FreeCraft = sw.on;
    if (sw.on) {
        @try { HA::ThreadScope sc; HA::AutoFillCraftMachine(); } @catch (id) {}
    }
}
- (void)onAutoSaveToggled:(UISwitch*)sw { HA::auto_save_enabled = sw.on; }

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSInteger tab = self.tabControl.selectedSegmentIndex;
    
    if (tab == 0) {
        if (indexPath.row < (NSInteger)self.filteredItems.count) {
            NSDictionary* it = self.filteredItems[indexPath.row];
            HAItemDetailVC* detail = [[HAItemDetailVC alloc] init];
            detail.itemData = it;
            [self.navigationController pushViewController:detail animated:YES];
        }
    } else if (tab == 1) {
        if (indexPath.section == 0) {
            NSArray* s0 = @[@"Level", @"Experience", @"Point", @"SkillPoint", @"ResetCount", @"UpgradeLuck"];
            NSString* statName = s0[indexPath.row];
            [self promptInputForStat:statName];
        } else if (indexPath.section == 1) {
            NSArray* s1 = @[@"Strength", @"Agility", @"Vitality", @"Energy", @"Command", @"CurrentHealth", @"CurrentMana"];
            NSString* statName = s1[indexPath.row];
            [self promptInputForStat:statName];
        } else {
            NSArray* cNames = @[@"Coin", @"Diamond", @"WarehouseCoin"];
            NSString* c = cNames[indexPath.row];
            [self promptInputForCurrency:c];
        }
    } else if (tab == 2) {
        if (indexPath.section == 1) {
            if (indexPath.row == 0) {
                UIAlertController* a = [UIAlertController alertControllerWithTitle:@"Tốc độ di chuyển" message:@"Nhập hệ số tốc độ (Ví dụ: 1.0, 2.5, 5.0, 10.0)" preferredStyle:UIAlertControllerStyleAlert];
                [a addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
                    textField.keyboardType = UIKeyboardTypeDecimalPad;
                    textField.text = [NSString stringWithFormat:@"%.1f", HA::g_MoveSpeedMultiplier];
                }];
                [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    float val = [a.textFields.firstObject.text floatValue];
                    if (val >= 1.0f && val <= 50.0f) {
                        HA::g_MoveSpeedMultiplier = val;
                    }
                    [self.tableView reloadData];
                }]];
                [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:a animated:YES completion:nil];
            } else if (indexPath.row == 1) {
                UIAlertController* a = [UIAlertController alertControllerWithTitle:@"Tốc độ đánh" message:@"Nhập chỉ số cộng thêm (+100, +500, +1000)" preferredStyle:UIAlertControllerStyleAlert];
                [a addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
                    textField.keyboardType = UIKeyboardTypeNumberPad;
                    textField.text = [NSString stringWithFormat:@"%d", HA::g_AttackSpeedBonus];
                }];
                [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    int val = [a.textFields.firstObject.text intValue];
                    if (val >= 0 && val <= 10000) {
                        HA::g_AttackSpeedBonus = val;
                    }
                    [self.tableView reloadData];
                }]];
                [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:a animated:YES completion:nil];
            } else {
                UIAlertController* a = [UIAlertController alertControllerWithTitle:@"Khuếch đại sát thương" message:@"Nhập hệ số nhân dame (Ví dụ: 2.0, 10.0, 100.0)" preferredStyle:UIAlertControllerStyleAlert];
                [a addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
                    textField.keyboardType = UIKeyboardTypeDecimalPad;
                    textField.text = [NSString stringWithFormat:@"%.1f", HA::g_DamageMultiplier];
                }];
                [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    float val = [a.textFields.firstObject.text floatValue];
                    if (val >= 1.0f && val <= 10000.0f) {
                        HA::g_DamageMultiplier = val;
                    }
                    [self.tableView reloadData];
                }]];
                [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:a animated:YES completion:nil];
            }
        }
    } else if (tab == 3) {
        @try {
            HA::ThreadScope scope;
            if (indexPath.row == 1) {
                int up = HA::UpgradeAllEquippedToMax();
                [self showSuccessAlert:[NSString stringWithFormat:@"Đã nâng cấp %d trang bị đang mặc lên +15 Full Dòng thành công!", up]];
            }
        } @catch (NSException* e) {
            [self showErrorAlert:e.reason];
        }
    } else if (tab == 4) {
        if (indexPath.section == 0) {
            if (indexPath.row == 1) {
                @try {
                    HA::ThreadScope scope;
                    int killed = HA::KillAllMonsters();
                    [self showSuccessAlert:[NSString stringWithFormat:@"Đã tiêu diệt %d quái vật trên map và kích hoạt rơi đồ!", killed]];
                } @catch (NSException* e) {
                    [self showErrorAlert:e.reason];
                }
            }
        } else {
            @try {
                HA::ThreadScope scope;
                if (indexPath.row >= 0 && indexPath.row <= 4) {
                    HA::SpawnBoss((int)indexPath.row);
                    [self showSuccessAlert:@"Đã gửi lệnh triệu hồi Boss thành công!"];
                } else if (indexPath.row == 5) {
                    UIAlertController* a = [UIAlertController alertControllerWithTitle:@"Hệ số Exp" message:@"Nhập hệ số nhân kinh nghiệm (Ví dụ: 10, 50, 100)" preferredStyle:UIAlertControllerStyleAlert];
                    [a addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
                        textField.keyboardType = UIKeyboardTypeNumberPad;
                        textField.text = @"10";
                    }];
                    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        int r = [a.textFields.firstObject.text intValue];
                        if (r >= 1 && r <= 10000) {
                            @try {
                                HA::ThreadScope sc;
                                HA::SetExpRateMultiplier(r);
                            } @catch (id) {}
                        }
                    }]];
                    [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
                    [self presentViewController:a animated:YES completion:nil];
                }
            } @catch (NSException* e) {
                [self showErrorAlert:e.reason];
            }
        }
    } else {
        if (indexPath.section == 0) {
            @try {
                HA::ThreadScope scope;
                if (indexPath.row == 0) {
                    HA::UnlockAllCharacters();
                    [self showSuccessAlert:@"Đã mở khóa toàn bộ nhân vật và slot!"];
                } else if (indexPath.row == 1) {
                    HA::UnlockAllSkills(false);
                    [self showSuccessAlert:@"Đã mở khóa toàn bộ kỹ năng!"];
                } else if (indexPath.row == 2) {
                    HA::UnlockAllSkills(true);
                    [self showSuccessAlert:@"Đã nâng tối đa điểm kỹ năng!"];
                } else if (indexPath.row == 3) {
                    HA::FinishAllQuests();
                    [self showSuccessAlert:@"Đã hoàn thành toàn bộ nhiệm vụ!"];
                }
            } @catch (NSException* e) {
                [self showErrorAlert:e.reason];
            }
        } else {
            if (indexPath.row == 0) {
                @try {
                    HA::ThreadScope scope;
                    HA::SaveGameData();
                    [self showSuccessAlert:@"Đã lưu dữ liệu nhân vật và cấu hình game thành công!"];
                } @catch (NSException* e) {
                    [self showErrorAlert:e.reason];
                }
            }
        }
    }
}

- (void)promptInputForStat:(NSString*)statName {
    if ([statName isEqualToString:@"UpgradeLuck"]) {
        int current;
        @try {
            HA::ThreadScope scope;
            if (!HA::GetPlayer()) HA::Fail(@"Vào nhân vật trước khi chỉnh luck.");
            current = HA::GetPlayerStat(statName);
        } @catch (NSException* error) { [self showErrorAlert:error.reason]; return; }
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"UpgradeLuck"
            message:@"Nhập 0–255. Từ 26 có thể bị game tính thành luck 0; không đảm bảo craft 100%."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField* field) {
            field.text = [NSString stringWithFormat:@"%d", current];
            field.keyboardType = UIKeyboardTypeNumberPad;
            field.accessibilityLabel = @"UpgradeLuck từ 0 đến 255";
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Áp dụng" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
            @try {
                NSString* text = alert.textFields.firstObject.text ?: @"";
                NSCharacterSet* invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
                if (!text.length || text.length > 3 || [text rangeOfCharacterFromSet:invalid].location != NSNotFound)
                    HA::Fail(@"Nhập số nguyên 0–255, không dùng ký tự khác.");
                HA::ThreadScope scope;
                HA::SetPlayerStat(@"UpgradeLuck", text.intValue);
                [self.tableView reloadData];
            } @catch (NSException* error) {
                dispatch_async(dispatch_get_main_queue(), ^{ [self showErrorAlert:error.reason]; });
            }
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
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
        } @catch (NSException* e) {}
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)promptInputForCurrency:(NSString*)c {
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
}

- (void)showSuccessAlert:(NSString*)msg {
    UIAlertController* a = [UIAlertController alertControllerWithTitle:@"Thành công" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)showErrorAlert:(NSString*)msg {
    UIAlertController* a = [UIAlertController alertControllerWithTitle:@"Lỗi" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
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
    UIApplication* app = UIApplication.sharedApplication;
    if (app.applicationState != UIApplicationStateActive) return;
    
    UIWindow* win = nil;
    for (UIScene* s in app.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]] ||
            s.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow* w in ((UIWindowScene*)s).windows) {
            if (w.hidden || w.alpha <= 0 || !w.rootViewController ||
                w.windowLevel != UIWindowLevelNormal) continue;
            if (!win || w.isKeyWindow) win = w;
            if (w.isKeyWindow) break;
        }
        if (win.isKeyWindow) break;
    }
    // Unity builds without a scene manifest still use application windows on iOS 17.
    if (!win) {
        for (UIWindow* w in app.windows) {
            if (w.hidden || w.alpha <= 0 || !w.rootViewController ||
                w.windowLevel != UIWindowLevelNormal) continue;
            if (!win || w.isKeyWindow) win = w;
            if (w.isKeyWindow) break;
        }
    }
    if (!win) return;
    if (self.floatBtn.superview == win) {
        [win bringSubviewToFront:self.floatBtn];
        return;
    }
    if (self.floatBtn) {
        [self.floatBtn removeFromSuperview];
        self.floatBtn.frame = CGRectMake(win.bounds.size.width - 65, 120, 50, 50);
        [win addSubview:self.floatBtn];
        return;
    }
    
    self.floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatBtn.frame = CGRectMake(win.bounds.size.width - 65, 120, 50, 50);
    self.floatBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
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
    dispatch_async(dispatch_get_main_queue(), ^{
        static HAButtonLauncher* launcher;
        launcher = [[HAButtonLauncher alloc] init];
        [launcher attach];
        // Recheck late Unity roots, replacement windows and views covering the launcher.
        [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer* timer) {
            [launcher attach];
        }];
        
        [HAEngineLoop.shared start];
        
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            [launcher attach];
            [HAEngineLoop.shared start];
        }];
    });
}
