// ZSM Drift Tweak — Speed Drifters VN (UnityFramework, il2cpp arm64)
// Build dylib, KHÔNG dùng MSHookFunction: inline hook ARM64 tự viết (mach_vm_remap trick)
// + patch RET thuần cho các hàm chặn anticheat.
//
// Toạ độ đã verify bằng IDA trên UnityFramework.i64 (imagebase 0x0, cryptid=0 → RVA==offset).

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <libkern/OSCacheControl.h>
#import <math.h>
#import <string.h>
#import <stdatomic.h>

#define L(...)  NSLog(@"[ZSM] " __VA_ARGS__)

// =============================================================================================
// 0. Cấu hình runtime (NSUserDefaults)
// =============================================================================================
static void  cfgLoad(void);
static void  cfgSave(void);

static bool   g_menuOpen          = false;
static bool   g_accelOn           = true;    // gia tốc ẩn: nhân torque engine
static float  g_accelMult         = 1.35f;   // 1.0..2.5  (không đổi top speed -> không hiện km/h)
static float  g_topAddPct         = 0.0f;    // 0..100%   (SetForceTopMPS; >0 sẽ hiện km/h)
static bool   g_hideKmph          = false;   // hook ReadVehicleKMPH chia lại số trên đồng hồ
static bool   g_noSlowDrift       = true;    // bỏ ma sát giảm tốc khi drift
static bool   g_autoCutDrift      = true;    // thả nút drift -> ForceEndDrifting ngay
static bool   g_autoFastOut       = false;   // thả nút drift -> DoFastOutCorners
static bool   g_contMini          = true;    // bơm passive mini boost liên tục khi drift
static float  g_miniInterval      = 0.8f;    // giây
static float  g_extraKmph         = 0.0f;    // 0 = tắt; AddExtraVelocity(Mini)
static float  g_extraDur          = 1.0f;    // giây
static bool   g_steerAssist       = false;   // auto lái về track line
static float  g_steerStrength     = 0.6f;    // 0..1 (độ nhạy)
static bool   g_steerInvert       = false;
static bool   g_blockCrack        = true;    // NotifyCrack -> ret
static bool   g_blockCheatCp      = true;    // ReportCheatCheckPoint -> ret
static bool   g_blockSdcEV        = true;    // SdcExtraVelocity.Update -> ret
static bool   g_blockActorCp      = false;   // ActorCpReporter.Update -> ret (mạnh tay, mặc định off)

static float  g_lastKmphScale     = 1.0f;    // áp dụng cho hook KMPH

static void cfgLoad(void){
    NSUserDefaults*d=[NSUserDefaults standardUserDefaults];
    g_accelOn      =[d boolForKey:@"zsm_accelOn"]      ?: g_accelOn;
    g_accelMult    =[d floatForKey:@"zsm_accelMult"]    ?: g_accelMult;
    g_topAddPct    =[d floatForKey:@"zsm_topAddPct"];
    g_hideKmph     =[d boolForKey:@"zsm_hideKmph"];
    g_noSlowDrift  =[d boolForKey:@"zsm_noSlowDrift"]  ?: g_noSlowDrift;
    g_autoCutDrift =[d boolForKey:@"zsm_autoCutDrift"] ?: g_autoCutDrift;
    g_autoFastOut  =[d boolForKey:@"zsm_autoFastOut"];
    g_contMini     =[d boolForKey:@"zsm_contMini"]     ?: g_contMini;
    g_miniInterval =[d floatForKey:@"zsm_miniInterval"] ?: g_miniInterval;
    g_extraKmph    =[d floatForKey:@"zsm_extraKmph"];
    g_extraDur     =[d floatForKey:@"zsm_extraDur"]     ?: g_extraDur;
    g_steerAssist  =[d boolForKey:@"zsm_steerAssist"];
    g_steerStrength=[d floatForKey:@"zsm_steerStrength"] ?: g_steerStrength;
    g_steerInvert  =[d boolForKey:@"zsm_steerInvert"];
    if(g_accelMult<1) g_accelMult=1; if(g_accelMult>2.5f) g_accelMult=2.5f;
}
static void cfgSave(void){
    NSUserDefaults*d=[NSUserDefaults standardUserDefaults];
    [d setBool:g_accelOn forKey:@"zsm_accelOn"];        [d setFloat:g_accelMult forKey:@"zsm_accelMult"];
    [d setFloat:g_topAddPct forKey:@"zsm_topAddPct"];   [d setBool:g_hideKmph forKey:@"zsm_hideKmph"];
    [d setBool:g_noSlowDrift forKey:@"zsm_noSlowDrift"];[d setBool:g_autoCutDrift forKey:@"zsm_autoCutDrift"];
    [d setBool:g_autoFastOut forKey:@"zsm_autoFastOut"];[d setBool:g_contMini forKey:@"zsm_contMini"];
    [d setFloat:g_miniInterval forKey:@"zsm_miniInterval"];[d setFloat:g_extraKmph forKey:@"zsm_extraKmph"];
    [d setFloat:g_extraDur forKey:@"zsm_extraDur"];     [d setBool:g_steerAssist forKey:@"zsm_steerAssist"];
    [d setFloat:g_steerStrength forKey:@"zsm_steerStrength"];[d setBool:g_steerInvert forKey:@"zsm_steerInvert"];
    [d synchronize];
}

// =============================================================================================
// 1. il2cpp dynamic exports
// =============================================================================================
typedef void* (*fn_domain_get)(void);
typedef void* (*fn_thread_attach)(void*);
typedef int   (*fn_domain_assemblies)(void*, void**);
typedef void* (*fn_assembly_image)(void*);
typedef size_t(*fn_img_class_count)(void*);
typedef void* (*fn_img_class)(void*, size_t);
typedef const char* (*fn_class_name)(void*);
typedef const char* (*fn_class_ns)(void*);
typedef void* (*fn_cls_method)(void*, const char*, int);
typedef void* (*fn_cls_field)(void*, const char*);
typedef size_t(*fn_field_off)(void*);
typedef void* (*fn_runtime_invoke)(void*, void*, void**, void**);
typedef void* (*fn_value_box)(void*, void*);
typedef void* (*fn_object_unbox)(void*);
typedef void* (*fn_string_new)(const char*);
typedef void* (*fn_get_corlib)(void);
typedef void* (*fn_cls_from_name)(void*, const char*, const char*);
typedef void* (*fn_obj_class)(void*);
typedef void* (*fn_cls_type)(void*);
typedef void* (*fn_type_obj)(void*);
typedef void* (*fn_obj_new)(void*);
typedef size_t(*fn_field_off)(void*);
typedef void* (*fn_image_of)(void*); // il2cpp_class_get_image

static fn_domain_get        il2cpp_domain_get;
static fn_thread_attach     il2cpp_thread_attach;
static fn_domain_assemblies il2cpp_domain_get_assemblies;
static fn_assembly_image    il2cpp_assembly_get_image;
static fn_img_class_count   il2cpp_image_get_class_count;
static fn_img_class         il2cpp_image_get_class;
static fn_class_name        il2cpp_class_get_name;
static fn_class_ns          il2cpp_class_get_namespace;
static fn_cls_method        il2cpp_class_get_method_from_name;
static fn_cls_field         il2cpp_class_get_field_from_name;
static fn_field_off         il2cpp_field_get_offset;
static fn_runtime_invoke    il2cpp_runtime_invoke;
static fn_value_box         il2cpp_value_box;
static fn_object_unbox      il2cpp_object_unbox;
static fn_string_new        il2cpp_string_new;
static fn_get_corlib        il2cpp_get_corlib;
static fn_cls_from_name     il2cpp_class_from_name;
static fn_obj_class         il2cpp_object_get_class;
static fn_cls_type          il2cpp_class_get_type;
static fn_type_obj          il2cpp_type_get_object;
static fn_obj_new           il2cpp_object_new;

static void* g_domain = nil;
static bool  g_il2cppReady = false;

static bool loadIl2cppSyms(void){
    #define SYM(var, name) var = (typeof(var))dlsym(RTLD_DEFAULT, name); if(!var){ L("missing %s", name); return false; }
    SYM(il2cpp_domain_get,             "il2cpp_domain_get")
    SYM(il2cpp_thread_attach,          "il2cpp_thread_attach")
    SYM(il2cpp_domain_get_assemblies,  "il2cpp_domain_get_assemblies")
    SYM(il2cpp_assembly_get_image,     "il2cpp_assembly_get_image")
    SYM(il2cpp_image_get_class_count,  "il2cpp_image_get_class_count")
    SYM(il2cpp_image_get_class,        "il2cpp_image_get_class")
    SYM(il2cpp_class_get_name,         "il2cpp_class_get_name")
    SYM(il2cpp_class_get_namespace,    "il2cpp_class_get_namespace")
    SYM(il2cpp_class_get_method_from_name,"il2cpp_class_get_method_from_name")
    SYM(il2cpp_class_get_field_from_name, "il2cpp_class_get_field_from_name")
    SYM(il2cpp_field_get_offset,       "il2cpp_field_get_offset")
    SYM(il2cpp_runtime_invoke,         "il2cpp_runtime_invoke")
    SYM(il2cpp_value_box,              "il2cpp_value_box")
    SYM(il2cpp_object_unbox,           "il2cpp_object_unbox")
    SYM(il2cpp_string_new,             "il2cpp_string_new")
    SYM(il2cpp_get_corlib,             "il2cpp_get_corlib")
    SYM(il2cpp_class_from_name,        "il2cpp_class_from_name")
    SYM(il2cpp_object_get_class,       "il2cpp_object_get_class")
    SYM(il2cpp_class_get_type,         "il2cpp_class_get_type")
    SYM(il2cpp_type_get_object,        "il2cpp_type_get_object")
    SYM(il2cpp_object_new,             "il2cpp_object_new")
    #undef SYM
    return true;
}

// ---- invoke helper ----
static void* inv(void* method, void* obj, void** args){
    if(!method) return nil;
    void* exc = nil;
    void* r = il2cpp_runtime_invoke(method, obj, args, &exc);
    if(exc){ L("invoke exception on %p", method); return nil; }
    return r;
}
static void* mOf(void* klass, const char* name, int argc){
    return klass ? il2cpp_class_get_method_from_name(klass, name, argc) : nil;
}
static void* boxF(float v){ return il2cpp_value_box(clsFloat(), &v); }
static void* boxB(bool v){  return il2cpp_value_box(clsBool(),  &v); }
static void* boxI(int v){   return il2cpp_value_box(clsInt(),   &v); }

// =============================================================================================
// 2. Class cache (scan toàn bộ image một lần)
// =============================================================================================
static void* clsGamePub, *clsGUILayout, *clsGUI, *clsVehicleFast,
            *clsExtraVelFast, *clsExtraVelTrigFast, *clsInputModule,
            *clsRoadMap, *clsEnumExtraVelType, *clsDemoGUIMsg, *clsGameObject;
static void *clsFloat, *clsBool, *clsInt, *clsRect, *clsVec3, *clsQuat;
static bool g_clsReady = false;

static void* clsFloat(void){ return clsFloat_; }
static void* clsBool(void){ return clsBool_; }
static void* clsInt(void){ return clsInt_; }

// forward decls dùng ở trên — định nghĩa thực dưới đây (C exige)
static void* clsFloat_; static void* clsBool_; static void* clsInt_;

static void scanClasses(void){
    if(g_clsReady) return;
    void* corlib = il2cpp_get_corlib();
    if(!corlib) return;
    clsFloat_ = il2cpp_class_from_name(corlib, "System", "Single");
    clsBool_  = il2cpp_class_from_name(corlib, "System", "Boolean");
    clsInt_   = il2cpp_class_from_name(corlib, "System", "Int32");
    if(!clsFloat_||!clsBool_||!clsInt_) return;

    size_t nAsm = 0;
    void** asms = nil; // il2cpp trả mảng trong bộ đếm riêng
    // il2cpp_domain_get_assemblies(domain, &sizePtr) → mảng
    size_t sizeVal = 0;
    asms = (void**)il2cpp_domain_get_assemblies(g_domain, &sizeVal);
    nAsm = sizeVal;
    if(!asms || !nAsm) return;

    for(size_t i=0;i<nAsm;i++){
        void* img = il2cpp_assembly_get_image(asms[i]);
        if(!img) continue;
        size_t n = il2cpp_image_get_class_count(img);
        for(size_t c=0;c<n;c++){
            void* k = il2cpp_image_get_class(img, c);
            if(!k) continue;
            const char* ns = il2cpp_class_get_namespace(k);
            const char* nm = il2cpp_class_get_name(k);
            if(!nm) continue;
            bool global = (ns==nil || ns[0]==0);
            #define TAKE(cond, slot) if(cond && !slot){ slot = k; }
            TAKE(global && !strcmp(nm,"GamePub"),                    clsGamePub)
            TAKE(!strcmp(ns,"UnityEngine") && !strcmp(nm,"GUILayout"), clsGUILayout)
            TAKE(!strcmp(ns,"UnityEngine") && !strcmp(nm,"GUI"),      clsGUI)
            TAKE(!strcmp(ns,"UnityEngine") && !strcmp(nm,"Rect"),     clsRect)
            TAKE(!strcmp(ns,"UnityEngine") && !strcmp(nm,"Vector3"),  clsVec3)
            TAKE(!strcmp(ns,"UnityEngine") && !strcmp(nm,"Quaternion"),clsQuat)
            TAKE(!strcmp(ns,"UnityEngine") && !strcmp(nm,"GameObject"),clsGameObject)
            TAKE(global && !strcmp(nm,"VehicleFast"),                 clsVehicleFast)
            TAKE(global && !strcmp(nm,"ExtraVelocityFast"),           clsExtraVelFast)
            TAKE(global && !strcmp(nm,"ExtraVelocityTriggerFast"),    clsExtraVelTrigFast)
            TAKE(global && !strcmp(nm,"InputModule"),                 clsInputModule)
            TAKE(global && !strcmp(nm,"RoadMap"),                     clsRoadMap)
            TAKE(global && !strcmp(nm,"ExtraVelocityType"),           clsEnumExtraVelType)
            TAKE(!strcmp(ns,"RootMotion") && !strcmp(nm,"DemoGUIMessage"), clsDemoGUIMsg)
            #undef TAKE
        }
        if(clsGamePub&&clsGUILayout&&clsGUI&&clsVehicleFast&&clsExtraVelFast&&clsExtraVelTrigFast
           &&clsInputModule&&clsRoadMap&&clsEnumExtraVelType&&clsDemoGUIMsg&&clsRect&&clsVec3
           &&clsQuat&&clsGameObject){
            g_clsReady = true;
            L("all classes resolved");
            return;
        }
    }
}

// =============================================================================================
// 3. Memory patch + inline hook ARM64 (không Substrate)
// =============================================================================================
static uintptr_t g_base = 0;
static void findBase(void){
    for(uint32_t i=_dyld_image_count(); i-->0;){
        const char* n = _dyld_get_image_name(i);
        if(n && strstr(n, "UnityFramework")){
            g_base = (uintptr_t)_dyld_get_image_vmaddr_slide(i);
            return;
        }
    }
}
static bool memWrite(uintptr_t addr, const void* data, size_t len){
    vm_address_t page = (vm_address_t)(addr & ~(vm_page_size-1));
    vm_size_t sz = (((addr+len)+vm_page_size-1) & ~(vm_page_size-1)) - page;
    if(vm_protect(mach_task_self(), page, sz, false,
                  VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY) != KERN_SUCCESS){
        L("vm_protect RW fail @%p", (void*)addr); return false;
    }
    memcpy((void*)addr, data, len);
    vm_protect(mach_task_self(), page, sz, false, VM_PROT_READ|VM_PROT_EXECUTE);
    sys_icache_invalidate((void*)addr, len);
    return true;
}
static bool patchRet(uintptr_t rva, uint32_t saved[4], bool* done){
    if(!g_base) return false;
    uintptr_t a = g_base + rva;
    if(*done) return true;
    if(!saved[0]){ memcpy(saved, (void*)a, 16); }
    uint32_t ret = 0xD65F03C0; // RET
    if(!memWrite(a, &ret, 4)) return false;
    *done = true; L("patchRet ok @0x%llx", (unsigned long long)rva);
    return true;
}
static bool unpatchRet(uintptr_t rva, uint32_t saved[4], bool* done){
    if(!*done) return true;
    if(!memWrite(g_base+rva, saved, 16)) return false;
    *done=false; return true;
}

// ---- trampoline: sao chép 1 trang __TEXT qua mach_vm_remap (kết quả ghi được mà vẫn X) ----
static uint8_t* g_trampBase = nil; static size_t g_trampOff = 0;
static void* trampAlloc(size_t sz){
    if(!g_trampBase){
        mach_vm_address_t dst = 0;
        vm_address_t src = ((vm_address_t)&trampAlloc) & ~(vm_page_size-1);
        vm_prot_t cur=0, mx=0;
        kern_return_t k = mach_vm_remap(mach_task_self(), &dst, vm_page_size, 0, VM_FLAGS_ANYWHERE,
                                        mach_task_self(), src, FALSE, &cur, &mx, VM_INHERIT_COPY);
        if(k != KERN_SUCCESS){ L("vm_remap fail %d", k); return nil; }
        if(vm_protect(mach_task_self(), (vm_address_t)dst, vm_page_size, 0,
                      VM_PROT_READ|VM_PROT_WRITE) != KERN_SUCCESS){ L("tramp RW fail"); return nil; }
        g_trampBase = (uint8_t*)dst; g_trampOff = 0;
        L("trampoline page @%p", (void*)dst);
    }
    void* p = g_trampBase + g_trampOff;
    g_trampOff += (sz + 15) & ~15UL;
    return p;
}

// dịch chuyển 4 lệnh đầu (16B): ADRP/ADR/B/BL/B.cond/CBZ/CBNZ/TBZ/TBNZ/LDR-literal; còn lại copy.
static bool reloc16(uint32_t* dst, uint64_t dstAddr, uint32_t* src, uint64_t srcAddr){
    for(int i=0;i<4;i++){
        uint32_t ins = src[i];
        uint64_t pc = srcAddr + 4ULL*i;
        uint64_t npc = dstAddr + 4ULL*i;
        uint32_t op = ins & 0x1F000000;
        if((ins & 0x9F000000) == 0x90000000){ // ADRP
            int64_t imm = (int64_t)(((ins>>29)&3) | (((ins>>5)&0x7FFFF)<<2));
            if(imm & 0x100000) imm -= 0x200000;
            uint64_t tgt = (pc & ~0xFFFULL) + (imm<<12);
            int64_t npg = ((int64_t)tgt - (int64_t)(npc & ~0xFFFULL)) >> 12;
            uint32_t hi = (uint32_t)(((npg>>2)&0x7FFFF)<<5) | (uint32_t)(((npg&3)<<29));
            dst[i] = (ins & 0x9F00001F) | hi | 0x80000000; // bit33..? giữ rd; dựng lại immhi/lo
            dst[i] = (ins & 0x001F001F) | (uint32_t)((((npg>>2)&0x7FFFF)<<5)) | (uint32_t)(((npg&3))<<29) | 0x90000000;
        } else if((ins & 0x9F000000) == 0x10000000){ // ADR
            int64_t imm = (int64_t)(((ins>>29)&3) | (((ins>>5)&0x7FFFF)<<2));
            if(imm & 0x100000) imm -= 0x200000;
            int64_t off = (int64_t)(pc + imm - npc);
            dst[i] = (ins & 0x9F00001F) | (uint32_t)(((off>>2)&0x7FFFF)<<5) | (uint32_t)((off&3)<<29);
        } else if(op == 0x14000000 || op == 0x94000000){ // B / BL
            int64_t off = (int64_t)(ins & 0x03FFFFFF); if(off & 0x2000000) off -= 0x4000000;
            uint64_t tgt = pc + off*4;
            if(op == 0x94000000){ // BL -> LDR X16,=tgt ; BLR X16 (chỉ an toàn ở prologue)
                dst[i]   = 0x58000030; // LDR X16, [PC, #8]
                dst[i+1] = 0xD63F0200; // BLR X16
                *(uint64_t*)(dst+i+2) = tgt;
                // đẩy phần còn lại của khối 16B sang slot sau
                for(int j=i+2;j<4;j++) dst[j+2] = src[j];
                // ghi đuôi: B tới (srcAddr+16)
                uint64_t backTgt = srcAddr+16;
                *(uint32_t*)(dst+i+4) = 0x14000000; // sẽ sửa bên dưới
                // đặt B tuyệt đối qua x16 tại dst[i+4].. cần 12B: dùng LDR/BR
                *(uint32_t*)(dst+i+4) = 0x58000050; // LDR X16,[PC,#8]
                *(uint32_t*)(dst+i+5) = 0xD61F0200; // BR X16
                *(uint64_t*)(dst+i+6) = backTgt;
                return true; // đã dùng thêm 12B sau khối 16B
            } else {
                int64_t noff = ((int64_t)tgt - (int64_t)npc)/4;
                if(noff < -(1<<25) || noff >= (1<<25)){ L("B out of range"); return false; }
                dst[i] = (ins & 0xFC000000) | (uint32_t)(noff & 0x03FFFFFF);
            }
        } else if((ins & 0xFF000010) == 0x54000000){ // B.cond
            int64_t off = (int64_t)((ins>>5)&0x7FFFF); if(off & 0x40000) off -= 0x80000;
            uint64_t tgt = pc + off*4;
            int64_t noff = ((int64_t)tgt - (int64_t)npc)/4;
            if(noff < -(1<<18) || noff >= (1<<18)){ L("B.cond out of range"); return false; }
            dst[i] = (ins & 0xFF00001F) | (uint32_t)((noff & 0x7FFFF)<<5);
        } else if((ins & 0x7E000000) == 0x34000000){ // CBZ/CBNZ (32/64)
            int64_t off = (int64_t)((ins>>5)&0x7FFFF); if(off & 0x40000) off -= 0x80000;
            uint64_t tgt = pc + off*4;
            int64_t noff = ((int64_t)tgt - (int64_t)npc)/4;
            if(noff < -(1<<18) || noff >= (1<<18)){ L("CBZ out of range"); return false; }
            dst[i] = (ins & 0xFF00001F) | (uint32_t)((noff & 0x7FFFF)<<5);
        } else if((ins & 0x7E000000) == 0x36000000){ // TBZ/TBNZ
            int64_t off = (int64_t)((ins>>5)&0x3FFF); if(off & 0x2000) off -= 0x4000;
            uint64_t tgt = pc + off*4;
            int64_t noff = ((int64_t)tgt - (int64_t)npc)/4;
            if(noff < -(1<<13) || noff >= (1<<13)){ L("TBZ out of range"); return false; }
            dst[i] = (ins & 0xFFF8001F) | (uint32_t)((noff & 0x3FFF)<<5);
        } else if((ins & 0xFF000000) == 0x18000000){ // LDR literal (32/64, imm19)
            int64_t off = (int64_t)((ins>>5)&0x7FFFF); if(off & 0x40000) off -= 0x80000;
            uint64_t tgt = pc + off*4;
            int64_t noff = ((int64_t)tgt - (int64_t)npc)/4;
            if(noff < -(1<<18) || noff >= (1<<18)){ L("LDRlit out of range"); return false; }
            dst[i] = (ins & 0xFF00001F) | (uint32_t)((noff & 0x7FFFF)<<5);
        } else {
            dst[i] = ins;
        }
    }
    return true;
}

static bool hookRVA(uintptr_t rva, void* repl, void** origTramp){
    if(!g_base) return false;
    uintptr_t target = g_base + rva;
    // 1) trampoline: 16B lệnh gốc (đã reloc) + LDR X16/BR + đích trở lại
    uint8_t* tr = (uint8_t*)trampAlloc(64);
    if(!tr) return false;
    uint64_t trAddr = (uint64_t)tr;
    uint32_t* src = (uint32_t*)target;
    if(!reloc16((uint32_t*)tr, trAddr, src, target)) return false;
    // trở về target+16: LDR X16,[PC,#8]; BR X16; .quad
    uint32_t* back = (uint32_t*)(tr+16);
    back[0] = 0x58000050; back[1] = 0xD61F0200;
    *(uint64_t*)(back+2) = target+16;
    sys_icache_invalidate(tr, 64);
    // 2) ghi 16B entry tại target: LDR X16,[PC,#8]; BR X16; .quad repl
    uint32_t entry[4];
    entry[0] = 0x58000050; entry[1] = 0xD61F0200;
    *(uint64_t*)(entry+2) = (uint64_t)repl;
    if(!memWrite(target, entry, 16)) return false;
    *origTramp = tr;
    L("hook ok @0x%llx", (unsigned long long)rva);
    return true;
}

// =============================================================================================
// 4. Trạng thái game + method cache
// =============================================================================================
static void *mGetInst, *mGetModuleByName, *mGetMyVehicle, *mForceEndDrift, *mFastOut,
            *mForceMini, *mAddEV, *mSetKey, *mGetKeyFlags, *mNearestTP,
            *mGUIBeginArea, *mGUIEndArea, *mGUIBox, *mGUIButton, *mGUIColor,
            *mGBtn, *mGTgl, *mGLabel, *mGSlider, *mGSpace;
static size_t off_mECU=0, off_mState=0, off_mTorque=0, off_mNormalTop=0;
static void* g_inputModule=nil, *g_roadMap=nil, *g_lastTP=nil;

static bool resolveMethods(void){
    if(!g_clsReady) return false;
    if(mGetInst) return true;
    mGetInst      = mOf(clsGamePub,   "GetInstance", 0);
    mGetModuleByName = mOf(clsGamePub,"GetModuleByName", 2);
    mGetMyVehicle = mOf(clsVehicleFast,"GetMyVehicle", 0);
    mForceEndDrift= mOf(clsVehicleFast,"ForceEndDrifting", 1);
    mFastOut      = mOf(clsVehicleFast,"DoFastOutCorners", 1);
    mForceMini    = mOf(clsExtraVelTrigFast,"ForceCanTriggerOncePassiveMini", 1);
    mAddEV        = mOf(clsExtraVelFast,"AddExtraVelocity", 6);
    mSetKey       = mOf(clsInputModule,"SetKey", 2);
    mGetKeyFlags  = mOf(clsInputModule,"get_KeyFlags", 0);
    mNearestTP    = mOf(clsRoadMap,   "GetNearestTrackPoint", 2);
    mGUIBeginArea = mOf(clsGUILayout, "BeginArea", 1);
    mGUIEndArea   = mOf(clsGUILayout, "EndArea", 0);
    mGBtn         = mOf(clsGUILayout, "Button", 2);
    mGTgl         = mOf(clsGUILayout, "Toggle", 3);
    mGLabel       = mOf(clsGUILayout, "Label", 2);
    mGSlider      = mOf(clsGUILayout, "HorizontalScrollbar", 5);
    mGSpace       = mOf(clsGUILayout, "Space", 1);
    mGUIBox       = mOf(clsGUI,       "Box", 2);           // (Rect,string)
    mGUIButton    = mOf(clsGUI,       "Button", 2);        // (Rect,string)
    mGUIColor     = mOf(clsGUI,       "set_backgroundColor", 1);
    if(!mGetInst||!mGetMyVehicle||!mForceEndDrift||!mSetKey){ L("resolveMethods partial fail"); return false; }
    // field offsets
    void* f;
    if((f=il2cpp_class_get_field_from_name(clsGamePub? 0:0, 0))==nil){} // no-op giữ compiler
    extern void* clsGameObject;
    void* dvK = clsGameObject; // placeholder
    (void)dvK;
    // DynamicVehicle/NssPhyVehicleECU classes không scan trực tiếp: lấy offset qua object runtime
    return true;
}
static size_t fieldOff(void* obj, const char* name){
    void* k = il2cpp_object_get_class(obj);
    void* f = k ? il2cpp_class_get_field_from_name(k, name) : nil;
    return f ? il2cpp_field_get_offset(f) : 0;
}

// =============================================================================================
// 5. Gameplay frame logic (chạy trên main thread qua CADisplayLink)
// =============================================================================================
static bool  g_prevDriftKey=false;
static double g_nextMiniT=0, g_nextExtraT=0;

static void* getVeh(void){
    if(!mGetMyVehicle) return nil;
    return inv(mGetMyVehicle, nil, nil);
}
static void* getECU(void* veh, size_t* pStateOff, size_t* pTorqueOff, size_t* pTopOff){
    if(!veh) return nil;
    void* dv = inv(mOf(il2cpp_object_get_class(veh), "GetDynamicVehicle", 0), veh, nil);
    if(!dv) return nil;
    if(!off_mECU){ off_mECU = fieldOff(dv, "mECU"); }
    if(!off_mECU) return nil;
    void* ecu = *(void**)((char*)dv + off_mECU);
    if(!ecu) return nil;
    if(!off_mState){ off_mState = fieldOff(ecu, "mState"); }
    if(!off_mTorque){ off_mTorque = fieldOff(ecu, "mEngineTorque"); }
    if(!off_mNormalTop){ off_mNormalTop = fieldOff(ecu, "mNormalTopMPS"); }
    if(pStateOff)*pStateOff=off_mState; if(pTorqueOff)*pTorqueOff=off_mTorque; if(pTopOff)*pTopOff=off_mNormalTop;
    return ecu;
}

static void frameTick(void){
    if(!g_clsReady || !resolveMethods()) return;
    void* veh = getVeh();
    if(!veh){ g_lastTP=nil; g_prevDriftKey=false; g_inputModule=nil; g_roadMap=nil; return; }

    size_t stOff, tqOff, topOff;
    void* ecu = getECU(veh, &stOff, &tqOff, &topOff);

    // ---- input module ----
    if(!g_inputModule){
        void* gp = inv(mGetInst, nil, nil);
        if(gp && mGetModuleByName){
            void* s = il2cpp_string_new("InputModule");
            void* a[2] = { s, gp };
            g_inputModule = inv(mGetModuleByName, gp, a);
        }
    }
    int keyFlags = 0;
    if(g_inputModule && mGetKeyFlags){
        void* r = inv(mGetKeyFlags, g_inputModule, nil);
        if(r) keyFlags = *(int*)il2cpp_object_unbox(r);
    }
    bool driftKey = (keyFlags >> 8) & 1;   // InputKeyType.Drift = 8

    // ---- trạng thái xe ----
    int vState = 0;
    if(ecu && stOff) vState = *(int*)((char*)ecu + stOff);  // NssVehicleState: 2 = Drifting

    // ---- ngắt drift khi thả nút ----
    bool released = g_prevDriftKey && !driftKey;
    if(released && vState==2){
        if(g_autoCutDrift){ void* a[1] = { veh }; inv(mForceEndDrift, nil, a); }
        if(g_autoFastOut){ void* a[1] = { veh }; inv(mFastOut, nil, a); }
    }
    g_prevDriftKey = driftKey;

    double now = CACurrentMediaTime();

    // ---- mini boost liên tục ----
    if(vState==2 && g_contMini && mForceMini && now >= g_nextMiniT){
        void* a[1] = { veh }; inv(mForceMini, nil, a);
        g_nextMiniT = now + g_miniInterval;
    }
    // ---- boost thêm (ExtraVelocityType.Mini = 1) ----
    if(g_extraKmph > 0.5f && mAddEV && now >= g_nextExtraT){
        float kmph = g_extraKmph, torque = g_extraKmph*0.35f, dur = g_extraDur;
        int evType = 1; bool imm=false;
        void* eb = il2cpp_value_box(clsEnumExtraVelType, &evType);
        void* a[6] = { veh, eb, boxF(kmph), boxF(torque), boxF(dur), boxB(imm) };
        inv(mAddEV, nil, a);
        g_nextExtraT = now + 1.0;
    }

    // ---- steering assist về track line ----
    if(g_steerAssist && g_inputModule && mSetKey && mNearestTP){
        if(!g_roadMap){
            void* gp = inv(mGetInst, nil, nil);
            if(gp){ void* s = il2cpp_string_new("RoadMap"); void* a[2] = { s, gp };
                    g_roadMap = inv(mGetModuleByName, gp, a); }
        }
        if(g_roadMap){
            void* mPos = mOf(il2cpp_object_get_class(veh), "get_Position", 0);
            void* mFwd = mOf(il2cpp_object_get_class(veh), "get_Forward", 0);
            void* rp = inv(mPos, veh, nil), *rf = inv(mFwd, veh, nil);
            if(rp && rf){
                float* pos = (float*)il2cpp_object_unbox(rp);
                float* fwd = (float*)il2cpp_object_unbox(rf);
                void* aTP[2] = { il2cpp_value_box(clsVec3, pos), g_lastTP };
                void* tp = inv(mNearestTP, g_roadMap, aTP);
                if(tp){
                    g_lastTP = tp;
                    void* mDir = mOf(il2cpp_object_get_class(tp), "get_Direction", 0);
                    void* rd = mDir ? inv(mDir, tp, nil) : nil;
                    if(rd){
                        float* dir = (float*)il2cpp_object_unbox(rd);
                        float cx = fwd[0]*dir[2] - fwd[2]*dir[0]; // cross.y (x,z)
                        float dot = fwd[0]*dir[0] + fwd[2]*dir[2];
                        float deg = atan2f(cx, dot) * 57.29578f;
                        if(g_steerInvert) deg = -deg;
                        float dead = 30.0f - 28.0f*g_steerStrength; // 30°..2°
                        bool wantL = (deg < -dead), wantR = (deg >  dead);
                        int kf1 = 1, kf2 = 2; bool pr = true, rl = false;
                        void* aL[2] = { boxI(kf1), boxB(wantL?pr:rl) };
                        void* aR[2] = { boxI(kf2), boxB(wantR?pr:rl) };
                        inv(mSetKey, g_inputModule, aL);
                        inv(mSetKey, g_inputModule, aR);
                    }
                } else g_lastTP = nil;
            }
        }
    }
}

// =============================================================================================
// 6. Menu IMGUI (hook DemoGUIMessage.OnGUI)
// =============================================================================================
static void* GUIColorBox = nil; // cached màu
static void drawMenu(void){
    if(!g_clsReady || !mGUIBeginArea || !mGUIBox) return;
    // nút mở/đóng góc trái
    {   float r[4] = { 14, 40, 14+72, 40+34 }; // xmin,ymin,xmax,ymax
        void* rb = il2cpp_value_box(clsRect, r);
        void* a[2] = { rb, il2cpp_string_new(g_menuOpen? @"ZSM ◀" : @"ZSM") };
        void* res = inv(mGUIButton, nil, a);
        if(res && *(bool*)il2cpp_object_unbox(res)){ g_menuOpen = !g_menuOpen; cfgSave(); }
    }
    if(!g_menuOpen) return;

    // nền
    float bg[4] = { 0, 0, 0.78f, 0.78f, 0.78f }; // 4 phần tử cuối là màu — sửa: dùng mảng riêng
    (void)bg;
    float rcol[4] = {0.05f,0.05f,0.08f,0.85f};
    if(mGUIColor){ void* cb = il2cpp_value_box(clsQuat, rcol); /* Color==4 float, boxing 16B */ 
        void* a[1] = { cb }; inv(mGUIColor, nil, a); }
    float rbox[4] = { 10, 30, 10+300, 30+560 };
    {   void* rb = il2cpp_value_box(clsRect, rbox);
        void* a[2] = { rb, il2cpp_string_new("  ZSM DRIFT MENU") };
        inv(mGUIBox, nil, a); }

    float rarea[4] = { 16, 44, 16+290, 44+540 };
    {   void* rb = il2cpp_value_box(clsRect, rarea);
        void* a[1] = { rb }; inv(mGUIBeginArea, nil, a); }

    // helpers nội dòng
    #define LB(s) { void* a[2] = { il2cpp_string_new(s), nil }; inv(mGLabel, nil, a); }
    #define SP(x){ float f=x; void* a[1] = { boxF(f) }; inv(mGSpace, nil, a); }
    #define TGL(fl, name) { void* a[3] = { boxB(fl), il2cpp_string_new(name), nil }; \
        void* r = inv(mGTgl, nil, a); if(r){ bool nv = *(bool*)il2cpp_object_unbox(r); if(nv!=fl){ fl=nv; cfgSave(); } } }
    #define SLD(fl, lo, hi, name){ LB(name); float v = fl; void* a[5] = { boxF(v), boxF(1.0f), boxF(lo), boxF(hi), nil }; \
        void* r = inv(mGSlider, nil, a); if(r){ float nv = *(float*)il2cpp_object_unbox(r); if(fabsf(nv-v)>0.0001f){ fl=nv; cfgSave(); } } }

    LB("== Gia toc (an) ==");          // torque mult: không đổi top speed -> đồng hồ không lệch
    TGL(g_accelOn, "Bat gia toc an");
    { static float pct = 0; pct = (g_accelMult-1.0f)*100.0f;
      SLDR(pct, 0, 150, "Luc day (0-150%)");
      g_accelMult = 1.0f + pct/100.0f; }
    SLDF(g_topAddPct, 0, 100, "Top speed +0-100% (HIENT km/h)");
    TGL(g_hideKmph, "Gia km/h dong ho (neu top>0)");
    SP(6);
    LB("== Drift ==");                 // DriftingSlideVelDamping bị hook -> không giảm tốc
    TGL(g_noSlowDrift, "Drift khong giam toc");
    TGL(g_autoCutDrift, "Tu ngat drift khi tha nut");
    TGL(g_autoFastOut, "Fast-out-corners khi tha");
    SP(6);
    LB("== Mini boost ==");            // ForceCanTriggerOncePassiveMini
    TGL(g_contMini, "Lien tuc + miniboost");
    { static float iv = 0; iv = g_miniInterval;
      SLDR(iv, 0.2f, 3.0f, "Chu ky (giay)");
      g_miniInterval = iv; }
    SLDF(g_extraKmph, 0, 80, "Boost them km/h (0=off)");
    SLDF(g_extraDur, 0.3f, 3.0f, "Thoi luong boost (s)");
    SP(6);
    LB("== Steering assist ==");       // GetNearestTrackPoint -> SetKey(Left/Right)
    TGL(g_steerAssist, "Tu lai ve track line");
    { static float s = 0; s = g_steerStrength*100.0f;
      SLDR(s, 0, 100, "Steering strength");
      g_steerStrength = s/100.0f; }
    TGL(g_steerInvert, "Dao chieu lai");
    SP(6);
    LB("== Chong anticheat ==");       // patch RET
    TGL(g_blockCrack, "Chan NotifyCrack");
    TGL(g_blockCheatCp, "Chan bao cheat checkpoint");
    TGL(g_blockSdcEV, "Chan SdcExtraVelocity");
    TGL(g_blockActorCp, "Chan ActorCpReporter (nguy hiem)");
    #undef LB
    #undef SP
    #undef TGL
    { void* a[1] = { nil }; inv(mGUIEndArea, nil, a); }
}
// macro SLDR/SLDF nạp sau khi dùng — khai báo forward bằng 2 bản riêng
static void menuSliderPct(float* v, float lo, float hi, const char* name);

// bản thực của slider (dùng chung cho 2 macro)
static void menuSliderRaw(float* fl, float lo, float hi, const char* name){
    if(!mGSlider) return;
    void* a[5] = { boxF(*fl), boxF(1.0f), boxF(lo), boxF(hi), nil };
    void* r = inv(mGSlider, nil, a);
    if(r){ float nv = *(float*)il2cpp_object_unbox(r);
           if(fabsf(nv-*fl)>0.0001f){ *fl = nv; } }
}

// =============================================================================================
// 7. Hook bodies
// =============================================================================================
static void* orig_OnGUI = nil;
static void hook_OnGUI(void* self){
    if(orig_OnGUI) ((void(*)(void*))orig_OnGUI)(self);
    drawMenu();
}
static void* orig_UpdateECU = nil;
static void hook_UpdateECU(void* self, float dt){
    if(orig_UpdateECU) ((void(*)(void*,float))orig_UpdateECU)(self, dt);
    if(g_accelOn && g_accelMult > 1.001f && g_clsReady && off_mTorque){
        float* t = (float*)((char*)self + off_mTorque);
        if(*t > 0) *t *= g_accelMult;   // gia tốc ẩn: chỉ torque, top speed giữ nguyên
    }
    if(g_topAddPct > 0.5f && g_clsReady){
        // SetForceTopMPS(normalTop * (1+pct)) mỗi frame sau UpdateECU
        static void* mSetForceTop = nil;
        if(!mSetForceTop && self) mSetForceTop = mOf(il2cpp_object_get_class(self), "SetForceTopMPS", 1);
        if(mSetForceTop && off_mNormalTop){
            float base = *(float*)((char*)self + off_mNormalTop);
            float v = base * (1.0f + g_topAddPct/100.0f);
            void* a[1] = { boxF(v) };
            inv(mSetForceTop, self, a);
            g_lastKmphScale = 1.0f / (1.0f + g_topAddPct/100.0f);
        }
    }
}
static void* orig_Damping = nil;
static void hook_Damping(void* self, float curMPS, float dampingCoef, int stateType, float dt){
    if(g_noSlowDrift && g_clsReady) return; // bỏ toàn bộ áp ma sát drift
    if(orig_Damping) ((void(*)(void*,float,float,int,float))orig_Damping)(self, curMPS, dampingCoef, stateType, dt);
}
static void* orig_KMPH = nil;
static float hook_KMPH(void* self){
    float v = orig_KMPH ? ((float(*)(void*))orig_KMPH)(self) : 0;
    if(g_hideKmph && g_clsReady) return v * g_lastKmphScale;
    return v;
}

// trạng thái patch anticheat
static uint32_t sv_crack[4]={0};  static bool done_crack=false;
static uint32_t sv_cheatcp[4]={0};static bool done_cheatcp=false;
static uint32_t sv_sdcev[4]={0};  static bool done_sdcev=false;
static uint32_t sv_actorcp[4]={0};static bool done_actorcp=false;
static void applyAcPatches(void){
    if(!g_base) return;
    g_blockCrack   ? patchRet(0xC7B4F20, sv_crack,   &done_crack)   : unpatchRet(0xC7B4F20, sv_crack,   &done_crack);
    g_blockCheatCp ? patchRet(0x46A9644, sv_cheatcp, &done_cheatcp) : unpatchRet(0x46A9644, sv_cheatcp, &done_cheatcp);
    g_blockSdcEV   ? patchRet(0x991481C, sv_sdcev,   &done_sdcev)   : unpatchRet(0x991481C, sv_sdcev,   &done_sdcev);
    g_blockActorCp ? patchRet(0x4B3B260, sv_actorcp, &done_actorcp) : unpatchRet(0x4B3B260, sv_actorcp, &done_actorcp);
}

// =============================================================================================
// 8. Menu host: tạo GameObject + DemoGUIMessage (MonoBehaviour có OnGUI sẵn trong binary)
// =============================================================================================
static bool g_hostSpawned = false;
static void spawnMenuHost(void){
    if(g_hostSpawned || !g_clsReady || !clsGameObject || !clsDemoGUIMsg) return;
    void* mCtor = mOf(clsGameObject, ".ctor", 1);
    void* mAdd  = mOf(clsGameObject, "AddComponent", 1);
    void* mDDOL = nil;
    void* corlibObj = il2cpp_get_corlib();
    (void)corlibObj;
    if(!mCtor || !mAdd){ L("menu host methods missing"); return; }
    void* go = il2cpp_object_new(clsGameObject);
    if(!go) return;
    { void* a[1] = { il2cpp_string_new("ZSMMenuHost") }; inv(mCtor, go, a); }
    void* t = il2cpp_type_get_object(il2cpp_class_get_type(clsDemoGUIMsg));
    { void* a[1] = { t }; inv(mAdd, go, a); }
    // DontDestroyOnLoad
    void* objK = nil; // UnityEngine.Object class từ corlib image
    // lớp Object nằm CoreModule; scan đã bỏ qua — dùng GameObject chính nó (kế thừa) không được.
    // Cách chắc: gọi qua method class GameObject "DontDestroyOnLoad"? nó thuộc Object — tìm từ class GameObject:
    mDDOL = il2cpp_class_get_method_from_name(clsGameObject, "DontDestroyOnLoad", 1); // không tồn tại → nil
    if(!mDDOL){
        // fallback: class cha của GameObject
        void* k = clsGameObject;
        for(int i=0;i<4 && !mDDOL && k;i++){
            k = *(void**)k; // il2cpp klass->parent tại offset 0x28? — bỏ, dùng Image scan đã có sẵn UnityEngine.Object nếu cần
            (void)0;
        }
    }
    if(mDDOL){ void* a[1] = { go }; inv(mDDOL, nil, a); }
    g_hostSpawned = true;
    L("menu host spawned");
    if(!hookRVA(0xCA27DCC /*DemoGUIMessage.OnGUI*/, (void*)hook_OnGUI, &orig_OnGUI))
        L("!! OnGUI hook fail — menu sẽ không hiện");
}

// =============================================================================================
// 9. Driver: CADisplayLink (main thread — trùng thread Unity player loop)
// =============================================================================================
@interface ZSMDriver : NSObject
- (void)tick:(CADisplayLink*)dl;
@end
@implementation ZSMDriver
- (void)tick:(CADisplayLink*)dl{
    (void)dl;
    if(!g_il2cppReady){
        if(!loadIl2cppSyms()) return;
        g_domain = il2cpp_domain_get();
        if(!g_domain) return;
        il2cpp_thread_attach(g_domain);
        g_il2cppReady = true;
        L("il2cpp attached");
    }
    if(!g_base) findBase();
    if(!g_base) return;
    if(!g_clsReady) scanClasses();
    if(!g_clsReady) return;
    static bool hooksDone = false;
    if(!hooksDone){
        bool ok1 = hookRVA(0x7AF8938 /*NssPhyVehicleECU.UpdateECU*/, (void*)hook_UpdateECU, &orig_UpdateECU);
        bool ok2 = hookRVA(0x7C713DC /*DriftingSlideVelDamping*/,     (void*)hook_Damping,  &orig_Damping);
        bool ok3 = hookRVA(0x7AFC4A0 /*ReadVehicleKMPH*/,             (void*)hook_KMPH,     &orig_KMPH);
        L("hooks: ecu=%d damping=%d kmph=%d", ok1, ok2, ok3);
        if(ok1) off_mTorque = 0; // sẽ resolve lần tick đầu qua fieldOff (object thật)
        hooksDone = true;
        applyAcPatches();
        spawnMenuHost();
    }
    applyAcPatches(); // toggle menu cập nhật patch động
    frameTick();
}
@end
static ZSMDriver* g_driver = nil;

// =============================================================================================
// 10. Entry
// =============================================================================================
__attribute__((constructor))
static void zsmInit(void){
    cfgLoad();
    findBase();
    L("ctor base=0x%llx", (unsigned long long)g_base);
    dispatch_async(dispatch_get_main_queue(), ^{
        g_driver = [ZSMDriver new];
        CADisplayLink* dl = [CADisplayLink displayLinkWithTarget:g_driver selector:@selector(tick:)];
        dl.preferredFramesPerSecond = 30;
        [dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        L("displaylink started");
    });
}
