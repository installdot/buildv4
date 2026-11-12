#ifndef CATSSOUP_TWEAK_XM
#define CATSSOUP_TWEAK_XM

// Cats & Soup (Hidea / NEOWIZ) — UnityFramework IL2CPP tweak, TrollFools/TrollStore dylib.
//
// Target: C:\Users\TRUONG\Downloads\UnityFramework
//         Mach-O arm64, IL2CPP, MD5 1a9b692e39e11a98b244681a533f9b90
//
// Every class / method / field name below was verified against Il2CppDumper dump.cs
// for this exact build, and every RVA is recorded in a comment next to the lookup.
// Metadata lookups go through il2cpp reflection, not hardcoded addresses, so the tweak
// survives a re-dump of the same game version and reports a named failure otherwise.
//
// Core design decisions:
//  1. Mutations always go through the game's own public API (AddGold / AddGem /
//     AddFurniture / AddWorkData / ...). That way the ES3 file, the *CheckV4 hashes
//     and the FixedSizeList backup rings are all updated exactly as the game does —
//     which is what makes "save + upload to cloud" stick instead of being rolled back
//     by the next SaveGoldData.
//  2. Anti-cheat is defeated through the game's own flags (isMemoryHackV4 /
//     isSkipMemoryHackV4) plus their dedicated savers, never by patching code pages.
//  3. Content enumeration reads the same Entity_* ScriptableObject lists the game
//     reads (AssetManager + 0x28..0x1xx, each holding `List<T.Param> list` at +0x18),
//     so id spaces match the server's expectations.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <string.h>
#import <stdio.h>
#import <stdint.h>
#import <unistd.h>
#import <math.h>

#pragma mark - il2cpp ABI (exports verified present in this binary)

typedef struct Il2CppDomain Il2CppDomain;
typedef struct Il2CppAssembly Il2CppAssembly;
typedef struct Il2CppImage Il2CppImage;
typedef struct Il2CppClass Il2CppClass;
typedef struct MethodInfo MethodInfo;
typedef struct FieldInfo FieldInfo;
typedef struct Il2CppObject Il2CppObject;

static Il2CppDomain *(*i_domain_get)(void);
static void *(*i_thread_attach)(Il2CppDomain *);
static void **(*i_domain_get_assemblies)(Il2CppDomain *, size_t *);
static Il2CppImage *(*i_assembly_get_image)(Il2CppAssembly *);
static Il2CppClass *(*i_class_from_name)(Il2CppImage *, const char *, const char *);
static MethodInfo *(*i_class_get_method_from_name)(Il2CppClass *, const char *, int);
static FieldInfo *(*i_class_get_field_from_name)(Il2CppClass *, const char *);
static size_t (*i_field_get_offset)(FieldInfo *);
static Il2CppObject *(*i_runtime_invoke)(MethodInfo *, void *, void **, void **);
static void (*i_field_get_value)(Il2CppObject *, FieldInfo *, void *);
static void (*i_field_static_get_value)(FieldInfo *, void *);
static Il2CppClass *(*i_class_get_parent)(Il2CppClass *);
static void *(*i_method_get_param)(MethodInfo *, uint32_t);
static char *(*i_type_get_name)(void *);
static MethodInfo *(*i_class_get_methods)(Il2CppClass *, void **);
static const char *(*i_method_get_name)(MethodInfo *);
static uint32_t (*i_method_get_param_count)(MethodInfo *);

// UnityFramework is loaded by the app with RTLD_LOCAL, so its exported il2cpp_* symbols
// are not visible to dlsym(RTLD_DEFAULT) from an injected dylib — that is the "not IL2CPP"
// status. Resolve in two stages:
//   1. dlsym(RTLD_DEFAULT) for a jailbreak-style global load,
//   2. else dlopen the already-loaded UnityFramework image by path, which returns the
//      existing handle and makes its exports visible to dlsym.
//   3. else scan loaded images with _dyld_get_image_header for the one whose __TEXT
//      contains the IL2CPP marker and resolve by symbol-table lookup on that image.

// This UnityFramework build declares 241 `_il2cpp_*` symbols in LC_SYMTAB but the
// LC_DYLD_EXPORTS_TRIE contains a single empty entry, so the symbols are NOT exported:
// dlsym() can never find them, on any handle, global or not. That is the real cause of
// "Status: not IL2CPP". Resolve by walking the in-memory Mach-O of the loaded image:
//   __mh_execute_header + slide -> LC_SEGMENT_64 (find __TEXT vmaddr/slide)
//   -> LC_SYMTAB -> nlist_64[] (string table indices) -> value + slide.
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/dyld.h>

static const struct mach_header_64 *g_ufHeader = NULL;
static char g_ufPath[1024] = {0};
static uint64_t g_ufTextVMAddr = 0;
static const char *g_ufStrTab = NULL;
static const struct nlist_64 *g_ufSymTab = NULL;
static uint32_t g_ufNSyms = 0;

// LC_SYMTAB stores *file* offsets. In this image __LINKEDIT has fileoff 0x9024000 but
// vmaddr 0x943C000, so `header + symoff` lands in the wrong, already-mapped region and
// every lookup silently misses. Convert file offset -> vm address through the segment
// table before dereferencing.
static const char *uf_ptr_for_fileoff(const struct mach_header_64 *h, uint32_t fileoff) {
    const char *cmdPtr = (const char *)(h + 1);
    for (uint32_t c = 0; c < h->ncmds; c++) {
        const struct load_command *lc = (const struct load_command *)cmdPtr;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (fileoff >= seg->fileoff && fileoff < seg->fileoff + seg->filesize) {
                uint64_t vm = seg->vmaddr + (fileoff - seg->fileoff);
                return (const char *)((uintptr_t)h - (uintptr_t)g_ufTextVMAddr + (uintptr_t)vm);
            }
        }
        cmdPtr += lc->cmdsize;
    }
    return NULL;
}

static BOOL locateUnityFramework(void) {
    if (g_ufHeader) return YES;
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const struct mach_header *mh = _dyld_get_image_header(i);
        if (!mh || mh->magic != MH_MAGIC_64) continue;
        const char *name = _dyld_get_image_name(i);
        if (!name || !strstr(name, "UnityFramework")) continue;

        const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
        const struct symtab_command *symcmd = NULL;
        uint64_t textVM = 0;
        const char *cmdPtr = (const char *)(h + 1);
        for (uint32_t c = 0; c < h->ncmds; c++) {
            const struct load_command *lc = (const struct load_command *)cmdPtr;
            if (lc->cmd == LC_SYMTAB) symcmd = (const struct symtab_command *)lc;
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
                if (seg->fileoff == 0) textVM = seg->vmaddr;      // __TEXT
            }
            cmdPtr += lc->cmdsize;
        }
        if (!symcmd) continue;

        g_ufHeader = h;
        strncpy(g_ufPath, name, sizeof(g_ufPath) - 1);
        g_ufTextVMAddr = textVM;
        g_ufSymTab = (const struct nlist_64 *)uf_ptr_for_fileoff(h, symcmd->symoff);
        g_ufStrTab = uf_ptr_for_fileoff(h, symcmd->stroff);
        g_ufNSyms  = symcmd->nsyms;
        if (!g_ufSymTab || !g_ufStrTab) { g_ufHeader = NULL; continue; }
        return YES;
    }
    return NO;
}

static void *resolveIl2cppSym(const char *name) {
    // Symbols ARE exported (35,358 entries in LC_DYLD_EXPORTS_TRIE, 241 of them
    // _il2cpp_*). The only trap: dlsym() takes the C name *without* the Mach-O
    // leading underscore, i.e. dlsym("il2cpp_domain_get") finds "_il2cpp_domain_get".
    void *p = dlsym(RTLD_DEFAULT, name);
    if (p) return p;

    // RTLD_DEFAULT only covers the global scope; if UnityFramework was loaded with
    // RTLD_LOCAL, dlopen its real path from the dyld image list and resolve there.
    if (!locateUnityFramework()) return NULL;
    void *h = dlopen(g_ufPath, RTLD_NOW | RTLD_NOLOAD);
    if (!h) h = dlopen(g_ufPath, RTLD_NOW);
    if (h) { p = dlsym(h, name); if (p) return p; }

    // Last resort: the in-memory LC_SYMTAB. n_value is a link-time VM address; textBase
    // already carries the dyld slide, so adding slide again would double it.
    const uintptr_t textBase = (uintptr_t)g_ufHeader - (uintptr_t)g_ufTextVMAddr;
    for (uint32_t i = 0; i < g_ufNSyms; i++) {
        const struct nlist_64 *nl = &g_ufSymTab[i];
        uint32_t strx = nl->n_un.n_strx;
        if (!strx || strx >= 0x7FFFFFFF) continue;
        // Symtab entries keep the leading underscore.
        const char *symName = g_ufStrTab + strx;
        if (symName[0] != '_' || strcmp(symName + 1, name) != 0) continue;
        if ((nl->n_type & N_TYPE) != N_SECT || !nl->n_value) continue;
        return (void *)(textBase + (uintptr_t)nl->n_value);
    }
    return NULL;
}

#define BIND(sym) do { *(void **)(&i_##sym) = resolveIl2cppSym("il2cpp_" #sym); \
                       if (!i_##sym) { diag(@"missing _il2cpp_" #sym); return NO; } } while (0)

#pragma mark - Diagnostics

static char g_diag[160] = "booting";
static void diag(NSString *m) { snprintf(g_diag, sizeof(g_diag), "%s", m.UTF8String); }

#pragma mark - Handles

static Il2CppImage *g_img = NULL;
static BOOL g_ready = NO;

static Il2CppClass *K_DataManager, *K_GameManager, *K_GameSaveManager;
static Il2CppClass *K_GameData, *K_AssetManager;

static MethodInfo *M_gmInstance;
static MethodInfo *M_gsmCloudSave, *M_gmCloudSave, *M_gmSaveToServer;
static MethodInfo *M_saveHackFlag, *M_saveSkipHack, *M_saveHackSend;
static MethodInfo *M_addGold, *M_addEnergy, *M_addGem, *M_addCoin, *M_addPlayPoint;
static MethodInfo *M_addTravelPoint, *M_addWelcomeCoin, *M_addSouvenirToken, *M_addVipPoint;
static MethodInfo *M_addTicketGold, *M_addTicketEnergy, *M_addTicketTreasure;
static MethodInfo *M_addChangeTicket, *M_addSelectTicket, *M_addKittyChangeTicket;
static MethodInfo *M_addSpecialFishing, *M_addTelescopeLens, *M_addMinigameToken;
static MethodInfo *M_addUnitData, *M_addKittyData, *M_addFurniture, *M_addWorkData;
static MethodInfo *M_addPropData, *M_addNewRndEquip, *M_addEquipData;
static MethodInfo *M_addTheme, *M_addLamp, *M_addBgm, *M_addGuest, *M_addEventPlace;
static MethodInfo *M_addWorkSkin, *M_addSignSkin, *M_addTimerSkin, *M_addBalloonSkin;
static MethodInfo *M_getReward;
static MethodInfo *M_addTutorialFinish, *M_addPhotoOutline, *M_addPhotoSticker;
static MethodInfo *M_addRewardDecoBlock;
static MethodInfo *M_saveEquipData, *M_applyEquipExp, *M_savePurchase;
static MethodInfo *M_collectionRecv, *M_collectionCan, *M_collectionAdd;
static MethodInfo *M_consumeMoney;

static size_t off_mGameData;
static size_t off_gold, off_gem, off_freeGem, off_coin;
static size_t off_isHackV4, off_isHackSendV4, off_isSkipHackV4;
static size_t off_goldCheck, off_energyCheck, off_gemCheck, off_freeGemCheck;

#pragma mark - State

static BOOL g_noFall = NO;
static BOOL g_bypassAC = NO;
static BOOL g_freeShop = NO;
static BOOL g_noAds = NO;
static uint64_t g_lastGuard = 0;

static inline void *rd(void *o, size_t off) { return (o && off) ? *(void **)((char *)o + off) : NULL; }
static inline int32_t rdi(void *o, size_t off) { return (o && off) ? *(int32_t *)((char *)o + off) : 0; }
static inline void wrb(void *o, size_t off, uint8_t v) { if (o && off) *(uint8_t *)((char *)o + off) = v; }

static uint64_t nowMs(void) { return (uint64_t)([NSDate date].timeIntervalSince1970 * 1000.0); }

// List<T> layout is identical for every instantiation: _items @0x10, _size @0x18,
// array element data @0x20. Verified against dump.cs `List<T>` field order.
static inline int listCount(void *list) { return list ? rdi(list, 0x18) : 0; }
static inline void *listAt(void *list, int i) {
    void *items = rd(list, 0x10);
    if (!items || i < 0) return NULL;
    return *(void **)((char *)items + 0x20 + (size_t)i * 8);
}

#pragma mark - Reflection helpers

// get_Instance() lives on the *generic* base (Singleton<T> / ManagerBase<T> /
// MonoSingleton<T>). The MethodInfo reachable from a concrete class belongs to the
// generic definition, and runtime_invoke on it returns garbage — that is why no feature
// ever did anything. Read the static backing field of the inflated base instead:
//   Singleton<T>     -> private  static T instance
//   MonoSingleton<T> -> protected static T _instance
//   ManagerBase<T>   -> private  static T <Instance>k__BackingField
static void *staticInstance(Il2CppClass *k, const char *fieldName) {
    if (!k || !fieldName) return NULL;
    for (Il2CppClass *c = k; c; c = i_class_get_parent(c)) {
        FieldInfo *f = i_class_get_field_from_name(c, fieldName);
        if (!f) continue;
        void *out = NULL;
        i_field_static_get_value(f, &out);
        if (out) return out;
    }
    return NULL;
}

// AddGold / AddEnergy are overloaded on (int,bool) and (BigNumber,bool). Picking the
// wrong one silently reinterprets 90000 as a float mantissa, so resolve by parameter
// type name instead of by arity.
static MethodInfo *findMethodTyped(Il2CppClass *k, const char *name, int argc,
                                   int probeIdx, const char *wantType) {
    if (!k) return NULL;
    void *iter = NULL;
    MethodInfo *m;
    while ((m = (MethodInfo *)i_class_get_methods(k, &iter)) != NULL) {
        const char *mn = i_method_get_name(m);
        if (!mn || strcmp(mn, name) != 0) continue;
        if ((int)i_method_get_param_count(m) != argc) continue;
        if (probeIdx < 0) return m;
        void *pt = i_method_get_param(m, (uint32_t)probeIdx);
        if (!pt) continue;
        const char *tn = i_type_get_name(pt);
        if (!tn) continue;
        // il2cpp type names are "BigNumber", "System.Int32", "System.Boolean", ...
        // Match on the trailing component: il2cpp hands back "System.Int32" while the
        // caller may ask for "Int32" or "System.Int32"; comparing the tail covers both.
        const char *shortName = tn;
        for (const char *q = tn; *q; q++) if (*q == '.') shortName = q + 1;
        const char *wantTail = wantType;
        for (const char *q = wantType; *q; q++) if (*q == '.') wantTail = q + 1;
        if (strcmp(shortName, wantTail) == 0) return m;
    }
    return NULL;
}

#pragma mark - Bootstrap

static Il2CppImage *locateGameImage(void) {
    if (g_img) return g_img;
    size_t n = 0;
    Il2CppAssembly **asms = (Il2CppAssembly **)i_domain_get_assemblies(i_domain_get(), &n);
    if (!asms) return NULL;
    for (size_t i = 0; i < n; i++) {
        Il2CppImage *img = i_assembly_get_image(asms[i]);
        if (!img) continue;
        if (i_class_from_name(img, "", "DataManager") &&
            i_class_from_name(img, "", "GameData")) { g_img = img; return img; }
    }
    return NULL;
}

static BOOL resolveIl2Cpp(void) {
    if (g_ready) return YES;
    // A failing resolve walks the whole LC_SYMTAB (24k entries); doing that on every tap
    // blocks the main thread and makes the menu look dead. Retry at most every 3 s.
    static uint64_t lastTry = 0;
    uint64_t now = (uint64_t)([NSDate date].timeIntervalSince1970 * 1000.0);
    if (lastTry && now - lastTry < 3000) return NO;
    lastTry = now;
    // Do NOT probe with dlsym here: this image exports nothing (its LC_DYLD_EXPORTS_TRIE
    // holds one empty entry) while 241 _il2cpp_* symbols live in LC_SYMTAB, so only
    // resolveIl2cppSym() can find them.
    if (!resolveIl2cppSym("il2cpp_domain_get")) { diag(@"not IL2CPP"); return NO; }

    BIND(domain_get);
    BIND(thread_attach);
    BIND(domain_get_assemblies);
    BIND(assembly_get_image);
    BIND(class_from_name);
    BIND(class_get_method_from_name);
    BIND(class_get_field_from_name);
    BIND(field_get_offset);
    BIND(runtime_invoke);
    BIND(field_get_value);
    BIND(field_static_get_value);
    BIND(class_get_parent);
    BIND(method_get_param);
    BIND(type_get_name);
    BIND(class_get_methods);
    BIND(method_get_name);
    BIND(method_get_param_count);

    Il2CppDomain *dom = i_domain_get();
    if (!dom) { diag(@"no domain"); return NO; }
    i_thread_attach(dom);

    Il2CppImage *img = locateGameImage();
    if (!img) { diag(@"Assembly-CSharp not found"); return NO; }

    K_DataManager     = i_class_from_name(img, "", "DataManager");
    K_GameData        = i_class_from_name(img, "", "GameData");
    K_GameManager     = i_class_from_name(img, "", "GameManager");
    K_GameSaveManager = i_class_from_name(img, "CnS", "GameSaveManager");
    K_AssetManager    = i_class_from_name(img, "", "AssetManager");


    if (!K_DataManager || !K_GameData || !K_GameManager) { diag(@"core class missing"); return NO; }

    off_mGameData = i_field_get_offset(i_class_get_field_from_name(K_DataManager, "mGameData"));
    off_gold      = i_field_get_offset(i_class_get_field_from_name(K_GameData, "gold"));
    off_gem       = i_field_get_offset(i_class_get_field_from_name(K_GameData, "gem"));
    off_freeGem   = i_field_get_offset(i_class_get_field_from_name(K_GameData, "freeGem"));
    off_coin      = i_field_get_offset(i_class_get_field_from_name(K_GameData, "coin"));
    off_isHackV4      = i_field_get_offset(i_class_get_field_from_name(K_GameData, "isMemoryHackV4"));
    off_isHackSendV4  = i_field_get_offset(i_class_get_field_from_name(K_GameData, "isMemoryHackSendToServerV4"));
    off_isSkipHackV4  = i_field_get_offset(i_class_get_field_from_name(K_GameData, "isSkipMemoryHackV4"));
    off_goldCheck     = i_field_get_offset(i_class_get_field_from_name(K_GameData, "goldCheckV4"));
    off_energyCheck   = i_field_get_offset(i_class_get_field_from_name(K_GameData, "energyCheckV4"));
    off_gemCheck      = i_field_get_offset(i_class_get_field_from_name(K_GameData, "gemCheckV4"));
    off_freeGemCheck  = i_field_get_offset(i_class_get_field_from_name(K_GameData, "freeGemCheckV4"));

    if (!off_mGameData || !off_gold) { diag(@"GameData layout mismatch"); return NO; }

    // Singleton instance getters. The static getter is declared on the generic base
    // (Singleton<T> / ManagerBase<T> / MonoSingleton<T>), so walk the parent chain.
    // GameManager declares a non-generic get_Instance (0x2B0D710) that is safe to
    // invoke; the other managers only expose the generic-base getter, so their
    // instances come from staticInstance().

    M_gmCloudSave    = i_class_get_method_from_name(K_GameManager, "CloudSave", 1);        // 0x2B1DF70
    M_gmSaveToServer = i_class_get_method_from_name(K_GameManager, "SaveDataToServer", 1); // 0x2B21714

    // Anti-cheat savers — three fields, three savers, all with 0 args.
    M_saveHackFlag = i_class_get_method_from_name(K_DataManager, "SaveIsMemoryHackData", 0);
    M_saveHackSend = i_class_get_method_from_name(K_DataManager, "SaveIsMemoryHackSendToServerData", 0);
    M_saveSkipHack = i_class_get_method_from_name(K_DataManager, "SaveIsSkipMemoryHackData", 0);

    // Currency. AddGold/AddEnergy are overloaded on (int,bool) and (BigNumber,bool):
    // resolve by parameter type, never by arity.
    M_addGold         = findMethodTyped(K_DataManager, "AddGold", 2, 0, "BigNumber");
    M_addEnergy       = findMethodTyped(K_DataManager, "AddEnergy", 2, 0, "BigNumber");
    M_addGem          = i_class_get_method_from_name(K_DataManager, "AddGem", 5);            // int,bool,bool,int,string
    M_addCoin         = i_class_get_method_from_name(K_DataManager, "AddCoin", 2);
    M_addPlayPoint    = i_class_get_method_from_name(K_DataManager, "AddPlayPoint", 2);
    M_addTravelPoint  = i_class_get_method_from_name(K_DataManager, "AddTravelPoint", 2);
    M_addWelcomeCoin  = i_class_get_method_from_name(K_DataManager, "AddWelcomeCoin", 2);
    M_addSouvenirToken= i_class_get_method_from_name(K_DataManager, "AddSouvenirToken", 3);
    M_addVipPoint     = i_class_get_method_from_name(K_DataManager, "AddVipPoint", 2);        // void,int,bool

    M_addTicketGold     = i_class_get_method_from_name(K_DataManager, "AddTicketGold", 4);
    M_addTicketEnergy   = i_class_get_method_from_name(K_DataManager, "AddTicketEnergy", 4);
    M_addTicketTreasure = i_class_get_method_from_name(K_DataManager, "AddTicketTreasure", 4);
    // AddChangeTicket / AddSelectTicket have no 2-arg overload: (int,bool,int) and
    // (int,bool,bool) are the shortest forms.
    M_addChangeTicket   = i_class_get_method_from_name(K_DataManager, "AddChangeTicket", 4);
    M_addSelectTicket   = i_class_get_method_from_name(K_DataManager, "AddSelectTicket", 4);
    M_addKittyChangeTicket = i_class_get_method_from_name(K_DataManager, "AddKittyChangeTicket", 2);
    M_addSpecialFishing = i_class_get_method_from_name(K_DataManager, "AddSpecialFishingCount", 3);
    M_addTelescopeLens  = i_class_get_method_from_name(K_DataManager, "AddTelescopeLens", 3);
    M_addMinigameToken  = i_class_get_method_from_name(K_DataManager, "AddMinigameToken", 2);

    // Progression
    M_addUnitData      = i_class_get_method_from_name(K_DataManager, "AddUnitData", 3);
    M_addKittyData     = i_class_get_method_from_name(K_DataManager, "AddKittyData", 2);
    M_addFurniture     = i_class_get_method_from_name(K_DataManager, "AddFurniture", 5);
    M_addWorkData      = i_class_get_method_from_name(K_DataManager, "AddWorkData", 3);
    M_addPropData      = i_class_get_method_from_name(K_DataManager, "AddPropData", 3);
    M_addNewRndEquip   = i_class_get_method_from_name(K_DataManager, "AddNewRndEquip", 5);    // private, reachable
    M_addEquipData     = i_class_get_method_from_name(K_DataManager, "AddEquipData", 4);
    M_addTheme         = i_class_get_method_from_name(K_DataManager, "AddTheme", 3);
    M_addLamp          = i_class_get_method_from_name(K_DataManager, "AddLamp", 1);
    M_addBgm           = i_class_get_method_from_name(K_DataManager, "AddBgm", 2);
    M_addGuest         = i_class_get_method_from_name(K_DataManager, "AddGuest", 1);
    M_addEventPlace    = i_class_get_method_from_name(K_DataManager, "AddEventPlace", 1);
    M_addWorkSkin      = i_class_get_method_from_name(K_DataManager, "AddWorkSkinsData", 1);
    M_addSignSkin      = i_class_get_method_from_name(K_DataManager, "AddSignSkinsData", 1);
    M_addTimerSkin     = i_class_get_method_from_name(K_DataManager, "AddTimerSkinsData", 1);
    M_addBalloonSkin   = i_class_get_method_from_name(K_DataManager, "AddBalloonSkinsData", 2);
    M_addTutorialFinish= i_class_get_method_from_name(K_DataManager, "AddTutorialFinish", 1);
    M_addPhotoOutline  = i_class_get_method_from_name(K_DataManager, "AddPhotoOutline", 1);
    M_addPhotoSticker  = i_class_get_method_from_name(K_DataManager, "AddPhotoSticker", 1);
    M_addRewardDecoBlock  = i_class_get_method_from_name(K_DataManager, "AddRewardDecoBlock", 3);
    M_getReward        = i_class_get_method_from_name(K_DataManager, "GetReward", 9);
    M_collectionRecv   = i_class_get_method_from_name(K_DataManager, "ReceiveCollectionReward", 1);
    M_collectionCan    = i_class_get_method_from_name(K_DataManager, "CanReceiveCollectionReward", 1);
    M_collectionAdd    = i_class_get_method_from_name(K_DataManager, "AddNewCollection", 3);
    M_saveEquipData    = i_class_get_method_from_name(K_DataManager, "SaveEquipData", 0);
    M_savePurchase     = i_class_get_method_from_name(K_DataManager, "SavePurchase", 0);

    // Equip level grants
    M_applyEquipExp    = i_class_get_method_from_name(K_DataManager, "ApplyEquipLevelsFromExp", 1);

    // ConsumeMoney drives every shop purchase; used as a free-shop probe.
    M_consumeMoney     = i_class_get_method_from_name(K_DataManager, "ConsumeMoney", 5);

    g_ready = YES;
    diag(@"ready");
    return YES;
}

#pragma mark - Accessors

static void *gmInstance(void) {
    if (!g_ready || !M_gmInstance) return NULL;
    return i_runtime_invoke(M_gmInstance, NULL, NULL, NULL);
}
static void *dm(void) { return staticInstance(K_DataManager, "instance"); }
static void *gd(void) { void *d = dm(); return d ? rd(d, off_mGameData) : NULL; }
static void *am(void) { return staticInstance(K_AssetManager, "<Instance>k__BackingField"); }

// Entity_*.list at +0x18 inside each ScriptableObject referenced by AssetManager.
static void *entityList(const char *assetField) {
    void *m = am();
    if (!m || !K_AssetManager) return NULL;
    FieldInfo *f = i_class_get_field_from_name(K_AssetManager, assetField);
    if (!f) return NULL;
    void *ent = rd(m, i_field_get_offset(f));
    return ent ? rd(ent, 0x18) : NULL;
}

#pragma mark - Anti-cheat

// IsMemoryHackCheck (0x2BB8764) returns 0 immediately when either flag is set:
//   +0x3B8 isMemoryHackV4  → 0x2BB8818 tbz → return 0
//   +0x3BA isSkipMemoryHackV4 → 0x2BB8848 tbnz → return 0
// Both flags have dedicated savers, so the state persists across restarts exactly the
// way the game persists it.
static void applyAntiCheatBypass(void) {
    // Called straight from a UISwitch action, i.e. on the main thread, which is not an
    // il2cpp-attached thread until resolveIl2Cpp() has run. Ensure both.
    if (!resolveIl2Cpp()) return;
    void *g = gd();
    void *d = dm();
    if (!g || !d) return;

    wrb(g, off_isHackV4, 1);
    wrb(g, off_isHackSendV4, 1);
    wrb(g, off_isSkipHackV4, 1);
    if (off_goldCheck)    *(int64_t *)((char *)g + off_goldCheck) = 0;
    if (off_energyCheck)  *(int64_t *)((char *)g + off_energyCheck) = 0;
    if (off_gemCheck)     *(int64_t *)((char *)g + off_gemCheck) = 0;
    if (off_freeGemCheck) *(int64_t *)((char *)g + off_freeGemCheck) = 0;

    if (M_saveHackFlag) i_runtime_invoke(M_saveHackFlag, d, NULL, NULL);
    if (M_saveHackSend) i_runtime_invoke(M_saveHackSend, d, NULL, NULL);
    if (M_saveSkipHack) i_runtime_invoke(M_saveSkipHack, d, NULL, NULL);
}

// Re-assert once a second: GameServerManager.<CheckBlock>b__86_0 (0x344917C) clears
// isMemoryHackV4 whenever the server replies, so a single assignment is not enough.
static void guardTick(void) {
    if (!g_bypassAC && !g_noFall) return;
    uint64_t t = nowMs();
    if (t - g_lastGuard < 1000) return;
    g_lastGuard = t;
    if (!g_ready) return;              // domain not attached yet
    void *g = gd();
    if (!g) return;
    if (g_bypassAC) {
        wrb(g, off_isHackV4, 1);
        wrb(g, off_isSkipHackV4, 1);
    }
    if (g_noFall) {
        // "Tiền tệ không tuột": the *CheckV4 values are the only thing that can
        // retroactively invalidate a balance, so keep them zeroed while the flag holds.
        if (off_goldCheck)    *(int64_t *)((char *)g + off_goldCheck) = 0;
        if (off_energyCheck)  *(int64_t *)((char *)g + off_energyCheck) = 0;
        if (off_gemCheck)     *(int64_t *)((char *)g + off_gemCheck) = 0;
        if (off_freeGemCheck) *(int64_t *)((char *)g + off_freeGemCheck) = 0;
    }
}

#pragma mark - Currency

typedef struct { float f; int32_t e; int32_t integer; } BigNum;   // BigNumber, 12 B

// 90000 = 0x15F90 — the value UI_Master uses for every "full" button
// (verified at 0x2FD70C4, 0x2FDDE50, 0x2FDDFAC).
#define FULL_VALUE 90000

static void bumpInt(MethodInfo *m, int32_t target) {
    if (!m) return;
    void *d = dm();
    if (!d) return;
    BOOL add = YES;
    void *args[2] = { &target, &add };
    i_runtime_invoke(m, d, args, NULL);
}

static void fillCurrency(void) {
    void *d = dm(); void *g = gd();
    if (!d || !g) return;

    // Top up rather than add blindly: these Add* clamp at the game's own cap (coin /
    // playPoint / travelPoint cap at 999999, gem at 999999), so adding FULL_VALUE to an
    // already-high balance just wastes the call and, for gem, would overshoot the cap.
    int32_t delta;
    delta = FULL_VALUE - rdi(g, off_coin);        if (delta > 0) bumpInt(M_addCoin, delta);
    delta = FULL_VALUE;                            bumpInt(M_addPlayPoint,   delta);
    delta = FULL_VALUE;                            bumpInt(M_addTravelPoint, delta);
    delta = FULL_VALUE;                            bumpInt(M_addWelcomeCoin, delta);

    // gem + freeGem + souvenirToken take extra args.
    if (M_addGem) {
        int32_t paid = FULL_VALUE - rdi(g, off_gem);
        if (paid > 0) {
            BOOL add = YES, isFree = NO; int32_t reason = 0; void *detail = NULL;
            void *a[5] = { &paid, &add, &isFree, &reason, &detail };
            i_runtime_invoke(M_addGem, d, a, NULL);
        }
        int32_t freeV = FULL_VALUE - rdi(g, off_freeGem);
        if (freeV > 0) {
            BOOL add = YES, isFree = YES; int32_t reason = 0; void *detail = NULL;
            void *a[5] = { &freeV, &add, &isFree, &reason, &detail };
            i_runtime_invoke(M_addGem, d, a, NULL);
        }
    }
    if (M_addSouvenirToken) {
        int32_t v = FULL_VALUE; BOOL add = YES, noPopup = YES;
        void *a[3] = { &v, &add, &noPopup };
        i_runtime_invoke(M_addSouvenirToken, d, a, NULL);
    }

    // Gold / energy are BigNumber (float mantissa + exponent + integer).
    if (M_addGold)   { BigNum bn = { (float)FULL_VALUE, 0, 0 }; BOOL add = YES; void *a[2] = { &bn, &add }; i_runtime_invoke(M_addGold, d, a, NULL); }
    if (M_addEnergy) { BigNum bn = { (float)FULL_VALUE, 0, 0 }; BOOL add = YES; void *a[2] = { &bn, &add }; i_runtime_invoke(M_addEnergy, d, a, NULL); }

    if (M_addVipPoint) { int32_t v = FULL_VALUE; BOOL save = YES; void *a[2] = { &v, &save }; i_runtime_invoke(M_addVipPoint, d, a, NULL); }
}

static void fillTickets(void) {
    void *d = dm();
    if (!d) return;
    BOOL add = YES, viaMail = NO;
    for (int32_t idx = 0; idx < 3; idx++) {
        int32_t v = 9999;
        if (M_addTicketGold)     { void *a[4] = { &idx, &v, &viaMail, &add }; i_runtime_invoke(M_addTicketGold, d, a, NULL); }
        if (M_addTicketEnergy)   { void *a[4] = { &idx, &v, &viaMail, &add }; i_runtime_invoke(M_addTicketEnergy, d, a, NULL); }
        if (idx < 2 && M_addTicketTreasure) { void *a[4] = { &idx, &v, &viaMail, &add }; i_runtime_invoke(M_addTicketTreasure, d, a, NULL); }
    }
    int32_t v = 9999;
    int32_t reason = 0;
    if (M_addChangeTicket)     { int32_t t = 1401; void *a[4] = { &t, &v, &add, &reason }; i_runtime_invoke(M_addChangeTicket, d, a, NULL); }
    if (M_addSelectTicket)     { int32_t t = 1403; BOOL noPopup = YES; void *a[4] = { &t, &v, &add, &noPopup }; i_runtime_invoke(M_addSelectTicket, d, a, NULL); }
    if (M_addKittyChangeTicket){ void *a[2] = { &v, &add }; i_runtime_invoke(M_addKittyChangeTicket, d, a, NULL); }
    if (M_addSpecialFishing)   { BOOL np = YES; void *a[3] = { &v, &add, &np }; i_runtime_invoke(M_addSpecialFishing, d, a, NULL); }
    if (M_addTelescopeLens)    { BOOL np = YES; void *a[3] = { &v, &add, &np }; i_runtime_invoke(M_addTelescopeLens, d, a, NULL); }
    if (M_addMinigameToken)    { void *a[2] = { &v, &add }; i_runtime_invoke(M_addMinigameToken, d, a, NULL); }
}

#pragma mark - Content unlock

// ObscuredInt (CodeStage ACTk, TypeDefIndex 13777) field layout:
//   +0x0 currentCryptoKey (int)   +0x4 hiddenValue (int)   +0x8 inited (bool)
//   +0xC fakeValue    (int)       +0x10 fakeValueActive (bool)
// InternalDecrypt (0x2A5F2E8) does `decrypted = key ^ hiddenValue` where `key` is
// currentCryptoKey when non-zero, else the static cryptoKey. The static key is set by
// ObscuredInt..cctor (0x2A60328) to 0x6C81C (`mov w9,#0xc81c; movk w9,#6,lsl#16`).
// Entity_*.Param.index is an ObscuredInt at Param+0x10, so the id is
//   *(int*)(p + 0x10 + 4) ^ (*(int*)(p + 0x10) ?: 0x6C81C)
#define ACTK_STATIC_KEY 0x6C81C

static int32_t paramId(void *param) {
    if (!param) return 0;
    const char *oi = (const char *)param + 0x10;          // Entity_*.Param.index
    int32_t key   = *(const int32_t *)(oi + 0);
    int32_t hidden= *(const int32_t *)(oi + 4);
    int32_t k = key ? key : ACTK_STATIC_KEY;
    return hidden ^ k;
}

// AddUnitData(int _type, int _workId, bool _firstUnit) looks the type up inside
// Entity_CatType.list (List<T>.Find at 0x2C0A090) and throws NullReferenceException —
// which aborts the process via BRK — if the id is not in the table. Driving the loop
// from that same table makes the lookup unconditionally succeed, so only ids obtained
// from the asset list are ever passed in.
static void addAllCats(void) {
    void *d = dm();
    if (!d) return;
    void *list = entityList("asset_catType");
    int n = listCount(list);
    BOOL first = NO;
    int32_t workId = 0;
    for (int i = 0; i < n; i++) {
        void *param = listAt(list, i);
        if (!param) continue;
        int32_t type = paramId(param);
        if (type <= 0) continue;
        if (M_addUnitData) { void *a[3] = { &type, &workId, &first }; i_runtime_invoke(M_addUnitData, d, a, NULL); }
        // Kitties share CatType but live in a separate save list (ltKittyData).
        if (M_addKittyData) { void *a[2] = { &type, &workId }; i_runtime_invoke(M_addKittyData, d, a, NULL); }
    }
}

static void addAllFurniture(void) {
    void *d = dm();
    void *list = entityList("asset_furniture");
    int n = listCount(list);
    for (int i = 0; i < n; i++) {
        if (!M_addFurniture) break;
        void *param = listAt(list, i);
        if (!param) continue;
        BOOL save = NO, newAdd = YES;
        int32_t count = 1, reason = 0;
        void *a[5] = { param, &save, &count, &newAdd, &reason };
        i_runtime_invoke(M_addFurniture, d, a, NULL);
    }
}

typedef struct { int32_t x, y; } Vec2Int;   // UnityEngine.Vector2Int

static void addAllFacilities(void) {
    void *d = dm();
    void *list = entityList("asset_work");
    int n = listCount(list);
    Vec2Int pos = { 0, 0 };
    for (int i = 0; i < n; i++) {
        if (!M_addWorkData) break;
        void *param = listAt(list, i);
        if (!param) continue;
        int32_t level = 1;
        void *a[3] = { param, &level, &pos };
        i_runtime_invoke(M_addWorkData, d, a, NULL);
    }
}

static void addAllSkins(void) {
    void *d = dm();
    struct { const char *field; MethodInfo *m; int extra; const char *cbField; } set[] = {
        { "asset_WorkSkin",    M_addWorkSkin,    0, "asset_WorkSkin"    },
        { "asset_SignSkin",    M_addSignSkin,    0, "asset_SignSkin"    },
        { "asset_TimerSkin",   M_addTimerSkin,   0, "asset_TimerSkin"   },
        { "asset_BalloonSkin", M_addBalloonSkin, 1, "asset_BalloonSkin" },
    };
    for (size_t s = 0; s < sizeof(set)/sizeof(set[0]); s++) {
        if (!set[s].m) continue;
        void *list = entityList(set[s].field);
        int n = listCount(list);
        for (int i = 0; i < n; i++) {
            int32_t idx = paramId(listAt(list, i));
            if (idx <= 0) continue;
            if (set[s].extra) { int32_t gr = 0; void *a[2] = { &idx, &gr }; i_runtime_invoke(set[s].m, d, a, NULL); }
            else              { void *a[1] = { &idx }; i_runtime_invoke(set[s].m, d, a, NULL); }
        }
    }
}

static void addAllMisc(void) {
    void *d = dm();
    int32_t id, reason = 0;
    BOOL reward = NO;

    void *list = entityList("asset_theme");
    for (int i = 0, n = listCount(list); i < n && M_addTheme; i++) {
        id = paramId(listAt(list, i));
        void *a[3] = { &id, &reward, &reason };
        i_runtime_invoke(M_addTheme, d, a, NULL);
    }
    list = entityList("asset_lamp");
    for (int i = 0, n = listCount(list); i < n && M_addLamp; i++) {
        id = paramId(listAt(list, i));
        void *a[1] = { &id };
        i_runtime_invoke(M_addLamp, d, a, NULL);
    }
    list = entityList("asset_bgm");
    for (int i = 0, n = listCount(list); i < n && M_addBgm; i++) {
        id = paramId(listAt(list, i));
        void *a[2] = { &id, &reason };
        i_runtime_invoke(M_addBgm, d, a, NULL);
    }
    list = entityList("asset_guest");
    for (int i = 0, n = listCount(list); i < n && M_addGuest; i++) {
        id = paramId(listAt(list, i));
        void *a[1] = { &id };
        i_runtime_invoke(M_addGuest, d, a, NULL);
    }
    list = entityList("asset_eventPlace");
    for (int i = 0, n = listCount(list); i < n && M_addEventPlace; i++) {
        id = paramId(listAt(list, i));
        void *a[1] = { &id };
        i_runtime_invoke(M_addEventPlace, d, a, NULL);
    }

    // Photo book / profile cosmetics have real Entity_* tables, so enumerate them
    // instead of guessing id ranges (a blind 0..400 loop is both slow and mostly wrong).
    list = entityList("asset_photoOutline");
    for (int i = 0, n = listCount(list); i < n && M_addPhotoOutline; i++) {
        id = paramId(listAt(list, i));
        if (id > 0) { void *a[1] = { &id }; i_runtime_invoke(M_addPhotoOutline, d, a, NULL); }
    }
    list = entityList("asset_photoSticker");
    for (int i = 0, n = listCount(list); i < n && M_addPhotoSticker; i++) {
        id = paramId(listAt(list, i));
        if (id > 0) { void *a[1] = { &id }; i_runtime_invoke(M_addPhotoSticker, d, a, NULL); }
    }

    // Tutorial flags are dense small ints; 64 covers every shipped step. This is the
    // only remaining range loop and it is bounded and cheap.
    if (M_addTutorialFinish) {
        for (int32_t t = 0; t < 64; t++) {
            void *a[1] = { &t };
            i_runtime_invoke(M_addTutorialFinish, d, a, NULL);
        }
    }
}

static void addAllTowerProps(void) {
    void *d = dm();
    void *list = entityList("asset_TowerProp");
    int n = listCount(list);
    for (int i = 0; i < n; i++) {
        if (!M_addPropData) break;
        int32_t id = paramId(listAt(list, i));
        int32_t count = 99; BOOL save = YES;
        void *a[3] = { &id, &count, &save };
        i_runtime_invoke(M_addPropData, d, a, NULL);
    }
}

static void addAllForestDeco(void) {
    void *d = dm();
    if (!d || !M_addRewardDecoBlock) return;
    // Enumerate Entity_BlockReward (AssetManager+0x2A8) instead of a blind 1..200 scan:
    // unknown deco ids are rejected by the game anyway, so the scan only wasted cycles.
    void *list = entityList("asset_BlockReward");
    int n = listCount(list);
    int32_t reason = 0;
    for (int i = 0; i < n; i++) {
        int32_t id = paramId(listAt(list, i));
        if (id <= 0) continue;
        int32_t cnt = 99;
        void *a[3] = { &id, &cnt, &reason };
        i_runtime_invoke(M_addRewardDecoBlock, d, a, NULL);
    }
}

// Equip max. UI_Master.EquipUpgradeAll is an *instance* method on a MonoBehaviour, so
// invoking it with a NULL self would dereference null — the tweak never touches it.
// Instead AddNewRndEquip(count, equipIndex, isGacha, goodsReason, fixedExp) is called
// per equip id: it grants the equip, applies fixedExp and internally runs
// ApplyEquipLevelsFromExp (0x2C0F660 -> 0x2BD0414), so level-ups and the save happen.
static void maxEquips(void) {
    void *d = dm();
    if (!d) return;
    void *list = entityList("asset_equip");
    int n = listCount(list);
    if (!M_addNewRndEquip) {
        // Fallback for a build without the gacha entry point: push exp on owned equips.
        void *g = gd();
        if (!g || !M_addEquipData) return;
        void *equips = rd(g, 0xD8);
        for (int i = 0, m = listCount(equips); i < m; i++) {
            void *eq = listAt(equips, i);
            if (!eq) continue;
            int32_t exp = 100000; BOOL save = YES;
            void *a[4] = { eq, NULL, &exp, &save };
            i_runtime_invoke(M_addEquipData, d, a, NULL);
            if (M_applyEquipExp) { void *b[1] = { eq }; i_runtime_invoke(M_applyEquipExp, d, b, NULL); }
        }
        if (M_saveEquipData) i_runtime_invoke(M_saveEquipData, d, NULL, NULL);
        return;
    }
    for (int i = 0; i < n; i++) {
        void *param = listAt(list, i);
        if (!param) continue;
        int32_t id = paramId(param);
        if (id <= 0) continue;
        int32_t count = 1, reason = 0, exp = 100000;
        BOOL isGacha = NO;
        void *a[5] = { &count, &id, &isGacha, &reason, &exp };
        i_runtime_invoke(M_addNewRndEquip, d, a, NULL);
    }
    if (M_saveEquipData) i_runtime_invoke(M_saveEquipData, d, NULL, NULL);
}

#pragma mark - Extra content

// Consumables / special items / fish / premium builds have no Entity_* list the tweak can
// enumerate reliably (their id spaces are sparse and server-defined), so grant them over
// the documented dense ranges. Every call goes through the game's own adder, which clamps
// and persists exactly like a normal grant.
static void addAllItems(void) {
    void *d = dm();
    if (!d) return;
    int32_t reason = 0;

    // GetReward(int rewardType, int rewardValue, bool useMail, string subIndex,
    //           bool isGacha, int goodsReason) is the master grant dispatcher
    // (0x2BE820C -> GetReward_Inner 0x2C198E0, 102-case jump table). Driving it with
    // the documented defRewardType constants grants every item family through the same
    // code path the shop uses, so clamps, mail fallbacks and saves all apply.
    static const int32_t kRewardTypes[] = {
        5,   // EQUIP
        6,   // FURNITURE
        7,   // FISH
        14,  // LAMP
        15,  // EVENTPLACE
        17,  // SPECIALGUEST
        18,  // SPECIALITEM
        21,  // MUSIC
        22,  // THEME
        23,  // PUDDING
        24,  // MACARON
        26, 27, 28, 32,          // SKIN_WORK / SKIN_SIGN / SKIN_TIMER / SKIN_BALLOON
        40, 41, 42,              // PRIMARY_OUTLINE / PHOTO_OUTLINE / PHOTO_STICKER
        89,                      // BUILD_DECO_BLOCK
        201,                     // TOWER_PROP
    };
    int32_t cnt = 99;
    for (size_t i = 0; i < sizeof(kRewardTypes)/sizeof(kRewardTypes[0]); i++) {
        int32_t rt = kRewardTypes[i];
        // GetReward(int rewardType, int rewardValue, bool useMail, string subIndex,
        //           bool isGacha, bool forceMail, bool forceUnshowPopup,
        //           int goodsReason, string detail)
        BOOL useMail = NO, isGacha = NO, forceMail = NO, noPopup = NO;
        void *subIndex = NULL, *detail = NULL;
        void *a[9] = { &rt, &cnt, &useMail, &subIndex, &isGacha, &forceMail,
                       &noPopup, &reason, &detail };
        i_runtime_invoke(M_getReward, d, a, NULL);
    }

    // Ticket families are addressed by rewardType directly.
    static const int32_t kTicketTypes[] = {
        1101, 1102, 1103, 1201, 1202, 1203, 1301, 1302,
        1401, 1402, 1403, 1404, 1405, 1406, 1407, 1408,
    };
    for (size_t i = 0; i < sizeof(kTicketTypes)/sizeof(kTicketTypes[0]); i++) {
        int32_t rt = kTicketTypes[i];
        // GetReward(int rewardType, int rewardValue, bool useMail, string subIndex,
        //           bool isGacha, bool forceMail, bool forceUnshowPopup,
        //           int goodsReason, string detail)
        BOOL useMail = NO, isGacha = NO, forceMail = NO, noPopup = NO;
        void *subIndex = NULL, *detail = NULL;
        void *a[9] = { &rt, &cnt, &useMail, &subIndex, &isGacha, &forceMail,
                       &noPopup, &reason, &detail };
        i_runtime_invoke(M_getReward, d, a, NULL);
    }
}

static void collectAllCollections(void) {
    void *d = dm();
    if (!d) return;
    void *list = entityList("asset_collection");
    int n = listCount(list);
    for (int i = 0; i < n; i++) {
        void *param = listAt(list, i);
        if (!param) continue;
        int32_t idx = paramId(param);
        if (idx <= 0) continue;
        // AddNewCollection(index, subIndex, totalSubIndex) marks every sub-entry owned.
        if (M_collectionAdd) {
            int32_t sub = 0, total = 32;
            void *a[3] = { &idx, &sub, &total };
            i_runtime_invoke(M_collectionAdd, d, a, NULL);
        }
        if (M_collectionCan && M_collectionRecv) {
            void *a[1] = { &idx };
            Il2CppObject *can = i_runtime_invoke(M_collectionCan, d, a, NULL);
            if (can && *(uint8_t *)((char *)can + 0x10)) i_runtime_invoke(M_collectionRecv, d, a, NULL);
        }
    }
}

#pragma mark - Free shop (ConsumeMoney detour)

// DataManager.ConsumeMoney(moneyType, value, add, goodsReason, detail) is the single
// choke point every purchase path calls (84 call sites verified). With the switch on we
// answer "success" without moving any balance, so all downstream grant code still runs.
// The MethodInfo body pointer is swapped in place; nothing is written into __text and
// the original is restored when the switch goes off.
static void *g_consumeOrig = NULL;
static void *g_consumeMem = NULL;

typedef BOOL (*consume_fn)(void *self, int32_t moneyType, int32_t value, BOOL add,
                           int32_t reason, void *detail);

static BOOL freeConsume(void *self, int32_t moneyType, int32_t value, BOOL add,
                        int32_t reason, void *detail) {
    if (g_freeShop && value > 0) return YES;
    consume_fn orig = (consume_fn)g_consumeOrig;
    return orig ? orig(self, moneyType, value, add, reason, detail) : NO;
}

static void setFreeShop(BOOL on) {
    if (!resolveIl2Cpp()) return;
    if (!M_consumeMoney) return;
    if (on) {
        if (g_consumeOrig) return;
        g_consumeMem  = (void *)M_consumeMoney;
        g_consumeOrig = *(void **)g_consumeMem;      // MethodInfo.methodPointer
        if (!g_consumeOrig) { g_consumeMem = NULL; return; }
        *(void **)g_consumeMem = (void *)&freeConsume;
    } else {
        if (g_consumeMem && g_consumeOrig) *(void **)g_consumeMem = g_consumeOrig;
        g_consumeMem = NULL;
        g_consumeOrig = NULL;
    }
}

#pragma mark - Remove ads

// No-ads is not a boolean in the save: the game derives it from a PurchaseData row in
// GameData.ltPurchase (+0x150) whose _assetIndex is one of the remove-ads shop indices
// (148 / 149 / 188 / 200). AddPurchase persists the row through SavePurchase, so
// inserting it via PurchaseSuccess is the same path the store would take and it survives
// cloud sync.
static void grantRemoveAds(void) {
    if (!resolveIl2Cpp()) return;
    void *d = dm();
    if (!d) return;
    MethodInfo *m = findMethodTyped(K_DataManager, "PurchaseSuccess", 2, 0, "System.Int32");
    if (!m) m = i_class_get_method_from_name(K_DataManager, "PurchaseSuccess", 2);
    if (m) {
        int32_t index = 188;        // 광고제거_180일권, the longest duration shipped
        int32_t reason = 0;
        void *a[2] = { &index, &reason };
        i_runtime_invoke(m, d, a, NULL);
    }
    MethodInfo *mInit = i_class_get_method_from_name(K_DataManager, "InitRemoveAds", 2);
    if (mInit) {
        BOOL active = YES, useMsg = NO;
        void *a[2] = { &active, &useMsg };
        i_runtime_invoke(mInit, d, a, NULL);
    }
    if (M_savePurchase) i_runtime_invoke(M_savePurchase, d, NULL, NULL);
}

#pragma mark - Cloud save

static void pushSave(BOOL toServer) {
    void *gsm = staticInstance(K_GameSaveManager, "<Instance>k__BackingField");
    if (gsm && M_gsmCloudSave) i_runtime_invoke(M_gsmCloudSave, gsm, NULL, NULL);
    void *gm = gmInstance();
    if (gm && M_gmCloudSave) { BOOL force = YES; void *a[1] = { &force }; i_runtime_invoke(M_gmCloudSave, gm, a, NULL); }
    if (toServer && gm && M_gmSaveToServer) { BOOL purchase = NO; void *a[1] = { &purchase }; i_runtime_invoke(M_gmSaveToServer, gm, a, NULL); }
}

#pragma mark - Menu

// Container: a fixed header that is the drag grip, plus an inner UIScrollView that owns
// the controls. The grip must NOT live inside the scroll view — a pan gesture attached to
// a subview of a UIScrollView still competes with the scroll view's own pan recognizer,
// which is why dragging anywhere near the top scrolled the panel instead of the list.
@interface CSMenuView : UIView
@property (readonly) UIView *grip;
@property (readonly) UIScrollView *scroller;
@end

@implementation CSMenuView {
    UILabel *_status;
    CGFloat _y;
    UIScrollView *_scroller;
}
@synthesize grip = _grip;
@synthesize scroller = _scroller;

- (CGFloat)innerWidth { return self.frame.size.width - 28; }

- (UILabel *)line:(NSString *)t size:(CGFloat)s color:(UIColor *)c height:(CGFloat)h {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, _y, [self innerWidth], h)];
    l.text = t; l.font = [UIFont systemFontOfSize:s]; l.textColor = c;
    l.numberOfLines = 0;
    [_scroller addSubview:l]; _y += h + 2;
    return l;
}
- (UIButton *)btn:(NSString *)t sel:(SEL)s color:(UIColor *)c {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(14, _y, [self innerWidth], 34);
    b.backgroundColor = c; b.layer.cornerRadius = 8;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
    [_scroller addSubview:b]; _y += 40;
    return b;
}
- (void)sw:(NSString *)t sel:(SEL)s on:(BOOL)on {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, _y + 4, [self innerWidth] - 56, 24)];
    l.text = t; l.font = [UIFont systemFontOfSize:13]; l.textColor = [UIColor whiteColor];
    [_scroller addSubview:l];
    UISwitch *v = [[UISwitch alloc] initWithFrame:CGRectMake(self.frame.size.width - 66, _y, 51, 31)];
    v.on = on;
    [v addTarget:self action:s forControlEvents:UIControlEventValueChanged];
    [_scroller addSubview:v];
    _y += 38;
}

- (instancetype)initWithFrame:(CGRect)fr {
    self = [super initWithFrame:fr];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithRed:0.07 green:0.08 blue:0.11 alpha:0.97];
    self.layer.cornerRadius = 14; self.layer.borderWidth = 1;
    self.layer.borderColor = [UIColor colorWithRed:0.3 green:0.75 blue:0.45 alpha:0.8].CGColor;
    self.layer.masksToBounds = YES;

    // --- fixed header: the only drag surface ---
    const CGFloat headerH = 40.0;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, fr.size.width, headerH)];
    header.backgroundColor = [UIColor colorWithRed:0.10 green:0.12 blue:0.16 alpha:1.0];
    header.userInteractionEnabled = YES;
    [self addSubview:header];
    _grip = header;

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, fr.size.width - 16, headerH)];
    t.text = @"CATS & SOUP — MENU";
    t.font = [UIFont boldSystemFontOfSize:15];
    t.textColor = [UIColor colorWithRed:0.4 green:0.9 blue:0.6 alpha:1];
    t.textAlignment = NSTextAlignmentCenter;
    t.userInteractionEnabled = NO;
    [header addSubview:t];

    // --- scrollable body: owns every control and its own pan recognizer ---
    _scroller = [[UIScrollView alloc] initWithFrame:CGRectMake(0, headerH, fr.size.width, fr.size.height - headerH)];
    _scroller.showsVerticalScrollIndicator = YES;
    _scroller.showsHorizontalScrollIndicator = NO;
    _scroller.alwaysBounceVertical = YES;
    // Default YES: a drag is claimed by the scroll view (so the list scrolls) while a
    // quick tap still reaches the button. Setting this to NO is what made the panel
    // impossible to scroll — every touch went straight to a control.
    _scroller.delaysContentTouches = YES;
    _scroller.canCancelContentTouches = YES;
    [self addSubview:_scroller];

    _y = 10;
    _status = [self line:@"Status: opening" size:10 color:[UIColor colorWithWhite:0.65 alpha:1] height:28];

    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(14, _y, [self innerWidth], 1)];
    div.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1];
    [_scroller addSubview:div]; _y += 10;

    [self sw:@"Bypass Anti-Cheat"     sel:@selector(ac:) on:g_bypassAC];
    [self sw:@"Tiền tệ không tuột"    sel:@selector(nf:) on:g_noFall];
    [self sw:@"Free Shop Purchase"    sel:@selector(fs:) on:g_freeShop];
    [self sw:@"Xóa quảng cáo vĩnh viễn" sel:@selector(ad:) on:g_noAds];

    _y += 4; [self line:@"── TIỀN TỆ ──" size:12 color:[UIColor colorWithWhite:0.5 alpha:1] height:18];
    [self btn:@"Full tất cả tiền tệ" sel:@selector(a1) color:[UIColor colorWithRed:0.14 green:0.42 blue:0.58 alpha:0.95]];
    [self btn:@"Full tất cả vé" sel:@selector(a2) color:[UIColor colorWithRed:0.14 green:0.42 blue:0.58 alpha:0.95]];

    _y += 4; [self line:@"── NỘI DUNG ──" size:12 color:[UIColor colorWithWhite:0.5 alpha:1] height:18];
    [self btn:@"Mở tất cả mèo" sel:@selector(b1) color:[UIColor colorWithRed:0.28 green:0.28 blue:0.52 alpha:0.95]];
    [self btn:@"Mở tất cả khung / skin" sel:@selector(b2) color:[UIColor colorWithRed:0.28 green:0.28 blue:0.52 alpha:0.95]];
    [self btn:@"Mở tất cả chức năng khoá" sel:@selector(b3) color:[UIColor colorWithRed:0.28 green:0.28 blue:0.52 alpha:0.95]];
    [self btn:@"Thêm tất cả nội thất" sel:@selector(b4) color:[UIColor colorWithRed:0.28 green:0.28 blue:0.52 alpha:0.95]];
    [self btn:@"Thêm tất cả cơ sở quản lý" sel:@selector(b5) color:[UIColor colorWithRed:0.28 green:0.28 blue:0.52 alpha:0.95]];
    [self btn:@"Thêm tất cả tháp trang trí" sel:@selector(b6) color:[UIColor colorWithRed:0.28 green:0.28 blue:0.52 alpha:0.95]];
    [self btn:@"Thêm tất cả trang trí rừng" sel:@selector(b7) color:[UIColor colorWithRed:0.28 green:0.28 blue:0.52 alpha:0.95]];
    [self btn:@"Thêm tất cả vật phẩm" sel:@selector(b8) color:[UIColor colorWithRed:0.28 green:0.28 blue:0.52 alpha:0.95]];
    [self btn:@"Mở tất cả bộ sưu tập" sel:@selector(b9) color:[UIColor colorWithRed:0.28 green:0.28 blue:0.52 alpha:0.95]];

    _y += 4; [self line:@"── NÂNG CẤP ──" size:12 color:[UIColor colorWithWhite:0.5 alpha:1] height:18];
    [self btn:@"Nâng cấp full mọi facility" sel:@selector(c1) color:[UIColor colorWithRed:0.52 green:0.38 blue:0.14 alpha:0.95]];
    [self btn:@"Full đồ cho mèo (equip)" sel:@selector(c2) color:[UIColor colorWithRed:0.52 green:0.38 blue:0.14 alpha:0.95]];

    _y += 4; [self line:@"── LƯU ──" size:12 color:[UIColor colorWithWhite:0.5 alpha:1] height:18];
    [self btn:@"Lưu Local + Cloud" sel:@selector(d1) color:[UIColor colorWithRed:0.18 green:0.52 blue:0.28 alpha:0.95]];
    [self btn:@"Lưu + Upload Server" sel:@selector(d2) color:[UIColor colorWithRed:0.18 green:0.52 blue:0.28 alpha:0.95]];

    _y += 8;
    [self btn:@"Đóng" sel:@selector(closeTap) color:[UIColor colorWithRed:0.58 green:0.2 blue:0.2 alpha:0.9]];

    _scroller.contentSize = CGSizeMake(fr.size.width, _y + 30);
    return self;
}

- (void)ac:(UISwitch *)s { g_bypassAC = s.isOn; if (s.isOn) applyAntiCheatBypass(); }
- (void)nf:(UISwitch *)s { g_noFall = s.isOn; if (s.isOn) applyAntiCheatBypass(); guardTick(); }
- (void)fs:(UISwitch *)s { g_freeShop = s.isOn; setFreeShop(s.isOn); }
- (void)ad:(UISwitch *)s { g_noAds = s.isOn; if (s.isOn) grantRemoveAds(); }

// Bulk operations touch hundreds of objects and each Add* performs an ES3 write plus a
// V4 hash recompute. Running that synchronously inside a UI action freezes the main
// thread for seconds (and the watchdog can kill the app), which is why the buttons
// looked dead. Run the work on a background thread with the il2cpp thread attached and
// marshal only the status text back.
- (void)run:(NSString *)name work:(void (^)(void))blk {
    // Reflection lookups and the first il2cpp touch must stay on the main thread.
    if (!resolveIl2Cpp()) {
        _status.text = [NSString stringWithFormat:@"ERR %s", g_diag];
        return;
    }
    // ES3 (_esFile) and the FixedSizeList rings are not thread-safe, so bulk work runs
    // on one dedicated serial queue rather than the global pool: still off the main
    // thread (the UI stays responsive), but never two bulk ops at once.
    static dispatch_queue_t bulkQ; static dispatch_once_t onceQ;
    dispatch_once(&onceQ, ^{ bulkQ = dispatch_queue_create("catsoup.bulk", 0); });
    _status.text = [NSString stringWithFormat:@"... %@", name];
    dispatch_async(bulkQ, ^{
        @autoreleasepool { blk(); }
        NSString *msg = [NSString stringWithFormat:@"OK: %@", name];
        dispatch_async(dispatch_get_main_queue(), ^{ self->_status.text = msg; });
    });
}
- (void)a1 { [self run:@"full currency" work:^{ fillCurrency(); }]; }
- (void)a2 { [self run:@"full tickets"  work:^{ fillTickets(); }]; }
- (void)b1 { [self run:@"all cats"      work:^{ addAllCats(); }]; }
- (void)b2 { [self run:@"all skins"     work:^{ addAllSkins(); }]; }
- (void)b3 { [self run:@"all features"  work:^{ addAllMisc(); }]; }
- (void)b4 { [self run:@"all furniture" work:^{ addAllFurniture(); }]; }
- (void)b5 { [self run:@"all facilities" work:^{ addAllFacilities(); }]; }
- (void)b6 { [self run:@"all tower props" work:^{ addAllTowerProps(); }]; }
- (void)b7 { [self run:@"all forest deco" work:^{ addAllForestDeco(); }]; }
- (void)b8 { [self run:@"all items" work:^{ addAllItems(); }]; }
- (void)b9 { [self run:@"all collections" work:^{ collectAllCollections(); }]; }
- (void)c1 { [self run:@"upgrade facilities" work:^{ addAllFacilities(); }]; }
- (void)c2 { [self run:@"equip max"     work:^{ maxEquips(); }]; }
- (void)d1 { [self run:@"cloud save"    work:^{ pushSave(NO); }]; }
- (void)d2 { [self run:@"server save"   work:^{ pushSave(YES); }]; }
- (void)closeTap { self.hidden = YES; }
@end

// Dedicated overlay window. Attaching our views to the game's own UIWindow is what made
// the panel unresponsive: Unity's view sits above and claims the pan gestures, and a
// re-parent on the game's window churn keeps cancelling in-flight scrolls. A window of
// its own at a higher level, whose hitTest returns nil outside our two views, lets every
// other touch fall straight through to the game.
@interface CSOverlayWindow : UIWindow
@property (retain) UIView *fab;
@property (retain) UIView *panel;
@end

@implementation CSOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(id)event {
    if (self.hidden || !self.userInteractionEnabled || self.alpha < 0.01) return nil;
    UIView *cands[2] = { self.panel, self.fab };
    for (int i = 0; i < 2; i++) {
        UIView *v = cands[i];
        if (!v || v.hidden || !v.userInteractionEnabled) continue;
        CGPoint p = [self convertPoint:point toView:v];
        if ([v pointInside:p withEvent:event]) {
            UIView *hit = [v hitTest:p withEvent:event];
            if (hit) return hit;
        }
    }
    return nil;   // pass through to the game
}
@end

@interface CSMenu : NSObject
@property (retain) CSOverlayWindow *host;
@property (retain) UIButton *fab;
@property (retain) CSMenuView *panel;
@property (retain) CADisplayLink *link;
@end

@implementation CSMenu
+ (instancetype)shared {
    static CSMenu *i; static dispatch_once_t once;
    dispatch_once(&once, ^{ i = [CSMenu new]; });
    return i;
}
- (void)attach {
    if (!self.host) {
        CGRect scr = [UIScreen mainScreen].bounds;
        CSOverlayWindow *w = [[CSOverlayWindow alloc] initWithFrame:scr];
        w.backgroundColor = [UIColor clearColor];
        w.windowLevel = UIWindowLevelStatusBar + 100.0;
        w.userInteractionEnabled = YES;
        self.host = w;
        [w makeKeyAndVisible];
        if (self.fab)   { [w addSubview:self.fab];   w.fab = self.fab; }
        if (self.panel) { [w addSubview:self.panel]; w.panel = self.panel; }
        return;
    }
    // Only re-seat if iOS actually tore the views down; never re-add on a timer.
    if (self.fab && self.fab.superview != self.host) {
        [self.host addSubview:self.fab];
        self.host.fab = self.fab;
    }
    if (self.panel && self.panel.superview != self.host) {
        CGPoint off = self.panel.scroller.contentOffset;
        [self.host addSubview:self.panel];
        self.host.panel = self.panel;
        self.panel.scroller.contentOffset = off;
    }
}

- (void)setup {

    if (!self.fab) {
        self.fab = [UIButton buttonWithType:UIButtonTypeCustom];
        self.fab.frame = CGRectMake(18, 110, 46, 46);
        self.fab.backgroundColor = [UIColor colorWithRed:0.15 green:0.65 blue:0.35 alpha:0.85];
        self.fab.layer.cornerRadius = 23;
        self.fab.layer.borderWidth = 1.5;
        self.fab.layer.borderColor = [UIColor whiteColor].CGColor;
        [self.fab setTitle:@"CS" forState:UIControlStateNormal];
        [self.fab setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.fab.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [self.fab addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self.fab addGestureRecognizer:pan];
    }
    if (!self.panel) {
        self.panel = [[CSMenuView alloc] initWithFrame:CGRectMake(26, 96, 292, 610)];
        self.panel.hidden = YES;
        // Drag handle: the title bar only, so the scroll view keeps its own pan.
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)];
        pan.cancelsTouchesInView = YES;
        [self.panel.grip addGestureRecognizer:pan];
    }
    [self attach];
    [self.host bringSubviewToFront:self.panel];
    [self.host bringSubviewToFront:self.fab];
    if (!self.link) {
        self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
        [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}
- (void)tick {
    guardTick();
    // Our window is independent of the game's, so nothing here can cancel a scroll mid-drag.
    if (!self.panel.window || !self.fab.window) [self attach];
    else if (self.host.hidden) self.host.hidden = NO;   // iOS un-hides stolen key windows
}
- (void)dragPanel:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self.panel.superview];
    self.panel.center = CGPointMake(self.panel.center.x + t.x, self.panel.center.y + t.y);
    [p setTranslation:CGPointZero inView:self.panel.superview];
}
- (void)toggle {
    self.panel.hidden = !self.panel.hidden;
    if (!self.panel.hidden) [self.host bringSubviewToFront:self.panel];
}
- (void)drag:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self.fab.superview];
    self.fab.center = CGPointMake(self.fab.center.x + t.x, self.fab.center.y + t.y);
    [p setTranslation:CGPointZero inView:self.fab.superview];
}
@end

#pragma mark - Lifecycle

__attribute__((constructor))
static void cs_init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[CSMenu shared] setup];
    });
}

#endif
