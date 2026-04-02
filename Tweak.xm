#import <substrate.h>
#import <dobby.h>
#import <Foundation/Foundation.h>

static uintptr_t getBase() {
    return (uintptr_t)_dyld_get_image_vmaddr_slide(0);
}

// ─── Typedefs ───────────────────────────────────────────

typedef void* (*CreateCloudSaveSundry_t)(void* cloudData);
typedef void  (*CheckIllegalMaterial_t)(void* self, void* cloudData);
typedef double(*GetVariance_t)(void* data);
typedef double(*GetVarianceRMM_t)(void* data);
typedef long  (*GetMaterialTotal_t)(void* itemData);

static CreateCloudSaveSundry_t orig_CreateCloudSaveSundry = NULL;

// ─── Hook: CheckIllegalMaterial → no-op ─────────────────

static void hook_CheckIllegalMaterial(void* self, void* cloudData) {
    // do nothing — skip entirely
}

// ─── Hook: Variance checks → return 0 ───────────────────

static double hook_GetVariance(void* data) { return 0.0; }
static double hook_GetVarianceRMM(void* data) { return 0.0; }
static long   hook_GetMaterialTotal(void* itemData) { return 0L; }

// ─── Hook: CreateCloudSaveSundry → clean fields after ───

static void* hook_CreateCloudSaveSundry(void* cloudData) {
    void* result = orig_CreateCloudSaveSundry(cloudData);
    if (!result) return result;

    uint8_t* obj = (uint8_t*)result;

    // Set gem/fish/token fields to 99999999 in sundry report
    // so server sees plausible numbers matching what we set
    *(int*)(obj + 0x08) = 99999999; // Gem
    *(int*)(obj + 0x14) = 99999999; // FishChip

    // Zero out all variance/suspicion fields
    *(double*)(obj + 0x48) = 0.0;   // ItemVariance
    *(double*)(obj + 0x58) = 0.0;   // SeedItemVariance
    *(double*)(obj + 0x68) = 0.0;   // MaterialsItemVariance
    *(double*)(obj + 0x78) = 0.0;   // TokenTicketsVariance

    // Null out UnKnownMaterial array (the main cheat flag)
    *(uintptr_t*)(obj + 0x30) = 0;

    return result;
}

// ─── Hook: AboGameData.CreateFromPlayerPref → patch values

typedef void* (*AboCreateFromPref_t)(void);
static AboCreateFromPref_t orig_AboCreate = NULL;

static void* hook_AboCreate(void) {
    void* result = orig_AboCreate();
    if (!result) return result;

    uint8_t* obj = (uint8_t*)result;

    // AboGameData field offsets:
    *(int*)(obj + 0x40) = 99999999; // gems
    *(int*)(obj + 0x5C) = 99999999; // fishChip

    // Note: tokenTickets live in ItemData, not directly here
    // patch via CloudSaveGameData.itemData if needed

    return result;
}

// ─── Constructor ─────────────────────────────────────────

__attribute__((constructor))
static void initialize() {
    uintptr_t base = getBase();

    // Kill CheckIllegalMaterial
    DobbyHook(
        (void*)(base + 0x6A09C8),
        (void*)hook_CheckIllegalMaterial,
        NULL
    );

    // Neutralize variance methods
    DobbyHook((void*)(base + 0x6A1F20), (void*)hook_GetVariance,     NULL);
    DobbyHook((void*)(base + 0x6A1078), (void*)hook_GetVarianceRMM,  NULL);
    DobbyHook((void*)(base + 0x6A0F6C), (void*)hook_GetMaterialTotal, NULL);

    // Hook CreateCloudSaveSundry (save original for chaining)
    DobbyHook(
        (void*)(base + 0x698EA4),
        (void*)hook_CreateCloudSaveSundry,
        (void**)&orig_CreateCloudSaveSundry
    );

    // Hook AboGameData.CreateFromPlayerPref
    DobbyHook(
        (void*)(base + 0x1D04A60),
        (void*)hook_AboCreate,
        (void**)&orig_AboCreate
    );

    NSLog(@"[TWEAK] Hooks installed successfully");
}
