// ZSM Drift Tweak — Speed Drifters VN (UnityFramework, il2cpp arm64)
// dylib build, KHÔNG dùng MSHookFunction/Substrate: inline hook ARM64 tự viết
// (mach_vm_remap trampoline) + patch RET thuần cho các hàm chặn anticheat.
//
// Toạ độ lấy từ Il2CppDumper + verify decompile trên UnityFramework.i64 (imagebase 0x0,
// cryptid=0 nên RVA == file offset == IDB address).

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <libkern/OSCacheControl.h>
#import <math.h>
#import <string.h>

// mach_vm_remap không có trong iOS SDK -> tự khai báo prototype
extern "C" kern_return_t mach_vm_remap(vm_map_t, mach_vm_address_t*, mach_vm_size_t, mach_vm_offset_t, int, vm_map_t, mach_vm_address_t, boolean_t, vm_prot_t*, vm_prot_t*, vm_inherit_t);

#define L(...)  NSLog(@"[ZSM] " __VA_ARGS__)

// =============================================================================================
// 0. Cấu hình runtime
// =============================================================================================
static bool   g_menuOpen       = false;
static bool   g_accelOn        = true;    // gia tốc ẩn: nhân mEngineTorque, không đổi top speed
static float  g_accelMult      = 1.35f;   // 1.0 .. 2.5
static float  g_topAddPct      = 0.0f;    // 0..100% (thêm top speed, sẽ thấy km/h)
static bool   g_hideKmph       = false;   // chia lại ReadVehicleKMPH để đồng hồ như cũ
static bool   g_noSlowDrift    = true;    // chặn DriftingSlideVelDamping = không mất tốc khi drift
static bool   g_autoCutDrift   = true;    // thả nút drift -> ForceEndDrifting ngay
static bool   g_autoFastOut    = false;   // thả nút drift -> DoFastOutCorners
static bool   g_contMini       = true;    // bơm passive mini boost liên tục khi drift
static float  g_miniInterval   = 0.8f;    // giây
static float  g_extraKmph      = 0.0f;    // AddExtraVelocity(Mini), 0 = tắt
static float  g_extraDur       = 1.0f;
static bool   g_steerAssist    = false;   // tự lái về track line
static float  g_steerStrength  = 0.6f;    // 0..1
static bool   g_steerInvert    = false;
static bool   g_blockCrack     = true;    // NotifyCrack -> ret
static bool   g_blockCheatCp   = true;    // ReportCheatCheckPoint -> ret
static bool   g_blockSdcEV     = true;    // SdcExtraVelocity.Update -> ret
static bool   g_blockActorCp   = false;   // ActorCpReporter.Update -> ret (mạnh, mặc định off)

static float  g_kmphScale      = 1.0f;    // áp cho hook đồng hồ khi topAdd>0

static void cfgLoad(void){
    NSUserDefaults*d=[NSUserDefaults standardUserDefaults];
    if([d objectForKey:@"zsm_accelOn"])    g_accelOn      =[d boolForKey:@"zsm_accelOn"];
    if([d objectForKey:@"zsm_accelMult"])  g_accelMult    =[d floatForKey:@"zsm_accelMult"];
    g_topAddPct     =[d floatForKey:@"zsm_topAddPct"];
    g_hideKmph      =[d boolForKey:@"zsm_hideKmph"];
    if([d objectForKey:@"zsm_noSlowDrift"])  g_noSlowDrift =[d boolForKey:@"zsm_noSlowDrift"];
    if([d objectForKey:@"zsm_autoCutDrift"]) g_autoCutDrift=[d boolForKey:@"zsm_autoCutDrift"];
    g_autoFastOut   =[d boolForKey:@"zsm_autoFastOut"];
    if([d objectForKey:@"zsm_contMini"])     g_contMini    =[d boolForKey:@"zsm_contMini"];
    g_miniInterval  =[d floatForKey:@"zsm_miniInterval"]; if(g_miniInterval<=0) g_miniInterval=0.8f;
    g_extraKmph     =[d floatForKey:@"zsm_extraKmph"];
    g_extraDur      =[d floatForKey:@"zsm_extraDur"];     if(g_extraDur<=0)     g_extraDur=1.0f;
    g_steerAssist   =[d boolForKey:@"zsm_steerAssist"];
    g_steerStrength =[d floatForKey:@"zsm_steerStrength"]; if(g_steerStrength<=0) g_steerStrength=0.6f;
    g_steerInvert   =[d boolForKey:@"zsm_steerInvert"];
    if(g_accelMult<1) g_accelMult=1; if(g_accelMult>2.5f) g_accelMult=2.5f;
}
static void cfgSave(void){
    NSUserDefaults*d=[NSUserDefaults standardUserDefaults];
    [d setBool:g_accelOn forKey:@"zsm_accelOn"];          [d setFloat:g_accelMult forKey:@"zsm_accelMult"];
    [d setFloat:g_topAddPct forKey:@"zsm_topAddPct"];     [d setBool:g_hideKmph forKey:@"zsm_hideKmph"];
    [d setBool:g_noSlowDrift forKey:@"zsm_noSlowDrift"];  [d setBool:g_autoCutDrift forKey:@"zsm_autoCutDrift"];
    [d setBool:g_autoFastOut forKey:@"zsm_autoFastOut"];  [d setBool:g_contMini forKey:@"zsm_contMini"];
    [d setFloat:g_miniInterval forKey:@"zsm_miniInterval"];[d setFloat:g_extraKmph forKey:@"zsm_extraKmph"];
    [d setFloat:g_extraDur forKey:@"zsm_extraDur"];       [d setBool:g_steerAssist forKey:@"zsm_steerAssist"];
    [d setFloat:g_steerStrength forKey:@"zsm_steerStrength"];[d setBool:g_steerInvert forKey:@"zsm_steerInvert"];
    [d synchronize];
}

// =============================================================================================
// 1. il2cpp exports
// =============================================================================================
typedef void* (*fn_domain_get)(void);
typedef void* (*fn_thread_attach)(void*);
typedef void**(*fn_domain_assemblies)(void*, size_t*);
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

static void* g_domain=nil; static bool g_il2cppReady=false;

static bool loadIl2cppSyms(void){
    #define SYM(var, name) do{ var=(__typeof__(var))dlsym(RTLD_DEFAULT,name); if(!var){L("missing %s",name); return false;} }while(0)
    SYM(il2cpp_domain_get,             "il2cpp_domain_get");
    SYM(il2cpp_thread_attach,          "il2cpp_thread_attach");
    SYM(il2cpp_domain_get_assemblies,  "il2cpp_domain_get_assemblies");
    SYM(il2cpp_assembly_get_image,     "il2cpp_assembly_get_image");
    SYM(il2cpp_image_get_class_count,  "il2cpp_image_get_class_count");
    SYM(il2cpp_image_get_class,        "il2cpp_image_get_class");
    SYM(il2cpp_class_get_name,         "il2cpp_class_get_name");
    SYM(il2cpp_class_get_namespace,    "il2cpp_class_get_namespace");
    SYM(il2cpp_class_get_method_from_name,"il2cpp_class_get_method_from_name");
    SYM(il2cpp_class_get_field_from_name, "il2cpp_class_get_field_from_name");
    SYM(il2cpp_field_get_offset,       "il2cpp_field_get_offset");
    SYM(il2cpp_runtime_invoke,         "il2cpp_runtime_invoke");
    SYM(il2cpp_value_box,              "il2cpp_value_box");
    SYM(il2cpp_object_unbox,           "il2cpp_object_unbox");
    SYM(il2cpp_string_new,             "il2cpp_string_new");
    SYM(il2cpp_get_corlib,             "il2cpp_get_corlib");
    SYM(il2cpp_class_from_name,        "il2cpp_class_from_name");
    SYM(il2cpp_object_get_class,       "il2cpp_object_get_class");
    SYM(il2cpp_class_get_type,         "il2cpp_class_get_type");
    SYM(il2cpp_type_get_object,        "il2cpp_type_get_object");
    SYM(il2cpp_object_new,             "il2cpp_object_new");
    #undef SYM
    return true;
}

static void* inv(void* method, void* obj, void** args){
    if(!method) return nil;
    void* exc=nil;
    void* r = il2cpp_runtime_invoke(method, obj, args, &exc);
    if(exc){ L("invoke exception on %p", method); return nil; }
    return r;
}
static void* mOf(void* k, const char* n, int c){ return k? il2cpp_class_get_method_from_name(k,n,c):nil; }

static void *clsFloat, *clsBool, *clsInt, *clsColor;
static void* boxF(float v){ return il2cpp_value_box(clsFloat,&v); }
static void* boxB(bool v){  return il2cpp_value_box(clsBool,&v); }
static void* boxI(int v){   return il2cpp_value_box(clsInt,&v); }
// Color là struct 4 float — box bằng System.Drawing-like class riêng; Unity Color class không có
// trong corlib → dùng Rect (4 float, cùng layout) làm carrier khi cần.
static void* boxColor(float r,float g,float b,float a){
    float c[4]={r,g,b,a}; return il2cpp_value_box(clsColor?clsColor:clsFloat, c);
}

// =============================================================================================
// 2. Class cache
// =============================================================================================
static void *clsGamePub, *clsGUILayout, *clsGUI, *clsVehicleFast,
            *clsExtraVelFast, *clsExtraVelTrigFast, *clsInputModule,
            *clsRoadMap, *clsEnumExtraVelType, *clsDemoGUIMsg, *clsGameObject;
static bool g_clsReady=false;

static void scanClasses(void){
    if(g_clsReady) return;
    void* corlib = il2cpp_get_corlib(); if(!corlib) return;
    clsFloat  = il2cpp_class_from_name(corlib,"System","Single");
    clsBool   = il2cpp_class_from_name(corlib,"System","Boolean");
    clsInt    = il2cpp_class_from_name(corlib,"System","Int32");
    if(!clsFloat||!clsBool||!clsInt) return;

    size_t n=0;
    void** asms = (void**)il2cpp_domain_get_assemblies(g_domain, &n);
    if(!asms||!n) return;
    for(size_t i=0;i<n && !g_clsReady;i++){
        void* img = il2cpp_assembly_get_image(asms[i]); if(!img) continue;
        size_t cnt = il2cpp_image_get_class_count(img);
        for(size_t c=0;c<cnt;c++){
            void* k = il2cpp_image_get_class(img,c); if(!k) continue;
            const char* ns = il2cpp_class_get_namespace(k);
            const char* nm = il2cpp_class_get_name(k); if(!nm) continue;
            bool global = !ns || !ns[0];
            #define TAKEN(cond,slot) if(cond && !slot) slot = k;
            TAKEN(global && !strcmp(nm,"GamePub"),                       clsGamePub)
            TAKEN(!strcmp(ns?ns:"","UnityEngine") && !strcmp(nm,"GUILayout"), clsGUILayout)
            TAKEN(!strcmp(ns?ns:"","UnityEngine") && !strcmp(nm,"GUI"),       clsGUI)
            TAKEN(!strcmp(ns?ns:"","UnityEngine") && !strcmp(nm,"Color"),     clsColor)
            TAKEN(!strcmp(ns?ns:"","UnityEngine") && !strcmp(nm,"GameObject"),clsGameObject)
            TAKEN(global && !strcmp(nm,"VehicleFast"),              clsVehicleFast)
            TAKEN(global && !strcmp(nm,"ExtraVelocityFast"),        clsExtraVelFast)
            TAKEN(global && !strcmp(nm,"ExtraVelocityTriggerFast"), clsExtraVelTrigFast)
            TAKEN(global && !strcmp(nm,"InputModule"),              clsInputModule)
            TAKEN(global && !strcmp(nm,"RoadMap"),                  clsRoadMap)
            TAKEN(global && !strcmp(nm,"ExtraVelocityType"),        clsEnumExtraVelType)
            TAKEN(!strcmp(ns?ns:"","RootMotion") && !strcmp(nm,"DemoGUIMessage"), clsDemoGUIMsg)
            #undef TAKEN
        }
        g_clsReady = clsGamePub&&clsGUILayout&&clsGUI&&clsVehicleFast&&clsExtraVelFast
                   &&clsExtraVelTrigFast&&clsInputModule&&clsRoadMap&&clsEnumExtraVelType
                   &&clsDemoGUIMsg&&clsGameObject;
        if(g_clsReady) L("classes resolved");
    }
}

// =============================================================================================
// 3. Memory patch + inline hook ARM64
// =============================================================================================
static uintptr_t g_base=0;
static void findBase(void){
    for(uint32_t i=_dyld_image_count(); i-->0;){
        const char* n=_dyld_get_image_name(i);
        if(n && strstr(n,"UnityFramework")){ g_base=(uintptr_t)_dyld_get_image_vmaddr_slide(i); return; }
    }
}
static bool memWrite(uintptr_t addr,const void* data,size_t len){
    vm_address_t page = addr & ~(vm_page_size-1);
    vm_size_t sz = ((addr+len+vm_page_size-1)&~(vm_page_size-1)) - page;
    if(vm_protect(mach_task_self(),page,sz,false,VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY)!=KERN_SUCCESS){
        L("vm_protect fail @%p",(void*)addr); return false;
    }
    memcpy((void*)addr,data,len);
    vm_protect(mach_task_self(),page,sz,false,VM_PROT_READ|VM_PROT_EXECUTE);
    sys_icache_invalidate((void*)addr,len);
    return true;
}
static bool patchRet(uintptr_t rva,uint32_t saved[4],bool* done){
    if(!g_base||*done) return *done;
    uintptr_t a=g_base+rva;
    if(!saved[0]) memcpy(saved,(void*)a,16);
    uint32_t ret=0xD65F03C0;
    if(!memWrite(a,&ret,4)) return false;
    *done=true; L("patchRet 0x%llx ok",(unsigned long long)rva); return true;
}
static bool unpatchRet(uintptr_t rva,uint32_t saved[4],bool* done){
    if(!*done) return true;
    if(!memWrite(g_base+rva,saved,16)) return false;
    *done=false; L("unpatchRet 0x%llx",(unsigned long long)rva); return true;
}

// trampoline page
static uint8_t* g_trampBase=nil; static size_t g_trampOff=0;
static void* trampAlloc(size_t sz){
    if(!g_trampBase){
        mach_vm_address_t dst=0;
        vm_address_t src=((vm_address_t)&trampAlloc)&~(vm_page_size-1);
        vm_prot_t cur=0,mx=0;
        if(mach_vm_remap(mach_task_self(),&dst,vm_page_size,0,VM_FLAGS_ANYWHERE,
                         mach_task_self(),src,FALSE,&cur,&mx,VM_INHERIT_COPY)!=KERN_SUCCESS){
            L("vm_remap fail"); return nil;
        }
        if(vm_protect(mach_task_self(),(vm_address_t)dst,vm_page_size,0,VM_PROT_READ|VM_PROT_WRITE)!=KERN_SUCCESS){
            L("tramp RW fail"); return nil;
        }
        g_trampBase=(uint8_t*)dst; g_trampOff=0;
        L("trampoline @%p",(void*)dst);
    }
    void* p=g_trampBase+g_trampOff; g_trampOff+=(sz+15)&~15UL; return p;
}

// dịch 4 lệnh đầu (16B). Xử lý PC-relative: ADRP/ADR/B/BL/B.cond/CBZ/CBNZ/TBZ/TBNZ/LDR-lit.
static bool reloc16(uint32_t* dst,uint64_t dstAddr,uint32_t* src,uint64_t srcAddr){
    for(int i=0;i<4;i++){
        uint32_t ins=src[i];
        uint64_t pc=srcAddr+4ULL*i, npc=dstAddr+4ULL*i;
        uint32_t op=ins&0x1F000000;
        if((ins&0x9F000000)==0x90000000){ // ADRP
            int64_t imm=(int64_t)(((ins>>29)&3)|(((ins>>5)&0x7FFFF)<<2));
            if(imm&0x100000) imm-=0x200000;
            uint64_t tgt=(pc&~0xFFFULL)+(imm<<12);
            int64_t npg=((int64_t)tgt-(int64_t)(npc&~0xFFFULL))>>12;
            dst[i]=(ins&0x9F00001F)|(uint32_t)((npg&3)<<29)|(uint32_t)(((npg>>2)&0x7FFFF)<<5)|0x90000000;
        } else if((ins&0x9F000000)==0x10000000){ // ADR
            int64_t imm=(int64_t)(((ins>>29)&3)|(((ins>>5)&0x7FFFF)<<2));
            if(imm&0x100000) imm-=0x200000;
            int64_t off=(int64_t)(pc+imm-npc);
            dst[i]=(ins&0x9F00001F)|(uint32_t)((off&3)<<29)|(uint32_t)(((off>>2)&0x7FFFF)<<5);
        } else if(op==0x94000000){ // BL → LDR X16,[PC,#8]; BLR X16; .quad tgt; rồi B về target+16
            int64_t off=(int64_t)(ins&0x03FFFFFF); if(off&0x2000000) off-=0x4000000;
            uint64_t tgt=pc+off*4, back=srcAddr+16;
            dst[i]=0x58000030; dst[i+1]=0xD63F0200;      // LDR X16,[PC,#8]; BLR X16
            *(uint64_t*)(dst+i+2)=tgt;                    // literal
            uint32_t* b=(uint32_t*)(dst+i+4);             // LDR X16,[PC,#8]; BR X16; .quad back
            b[0]=0x58000050; b[1]=0xD61F0200;
            *(uint64_t*)(b+2)=back;
            return true;
        } else if(op==0x14000000){ // B
            int64_t off=(int64_t)(ins&0x03FFFFFF); if(off&0x2000000) off-=0x4000000;
            uint64_t tgt=pc+off*4, back=srcAddr+16;
            dst[i]=0x58000050; dst[i+1]=0xD61F0200;
            *(uint64_t*)(dst+i+2)=tgt;
            uint32_t* b=(uint32_t*)(dst+i+4);
            b[0]=0x58000050; b[1]=0xD61F0200;
            *(uint64_t*)(b+2)=back;
            return true;
        } else if((ins&0xFF000010)==0x54000000){ // B.cond
            int64_t off=(int64_t)((ins>>5)&0x7FFFF); if(off&0x40000) off-=0x80000;
            int64_t noff=(pc+off*4-(int64_t)npc)/4;
            if(noff<-(1<<18)||noff>=(1<<18)) return false;
            dst[i]=(ins&0xFF00001F)|(uint32_t)((noff&0x7FFFF)<<5);
        } else if((ins&0x7E000000)==0x34000000){ // CBZ/CBNZ
            int64_t off=(int64_t)((ins>>5)&0x7FFFF); if(off&0x40000) off-=0x80000;
            int64_t noff=(pc+off*4-(int64_t)npc)/4;
            if(noff<-(1<<18)||noff>=(1<<18)) return false;
            dst[i]=(ins&0xFF00001F)|(uint32_t)((noff&0x7FFFF)<<5);
        } else if((ins&0x7E000000)==0x36000000){ // TBZ/TBNZ
            int64_t off=(int64_t)((ins>>5)&0x3FFF); if(off&0x2000) off-=0x4000;
            int64_t noff=(pc+off*4-(int64_t)npc)/4;
            if(noff<-(1<<13)||noff>=(1<<13)) return false;
            dst[i]=(ins&0xFFF8001F)|(uint32_t)((noff&0x3FFF)<<5);
        } else if((ins&0xFF000000)==0x18000000){ // LDR literal
            int64_t off=(int64_t)((ins>>5)&0x7FFFF); if(off&0x40000) off-=0x80000;
            int64_t noff=(pc+off*4-(int64_t)npc)/4;
            if(noff<-(1<<18)||noff>=(1<<18)) return false;
            dst[i]=(ins&0xFF00001F)|(uint32_t)((noff&0x7FFFF)<<5);
        } else dst[i]=ins;
    }
    return true;
}
static bool hookRVA(uintptr_t rva,void* repl,void** origTramp){
    if(!g_base) return false;
    uintptr_t target=g_base+rva;
    uint8_t* tr=(uint8_t*)trampAlloc(64); if(!tr) return false;
    if(!reloc16((uint32_t*)tr,(uint64_t)tr,(uint32_t*)target,target)) return false;
    uint32_t* back=(uint32_t*)(tr+16);
    back[0]=0x58000050; back[1]=0xD61F0200;
    *(uint64_t*)(back+2)=target+16;
    sys_icache_invalidate(tr,64);
    uint32_t entry[4];
    entry[0]=0x58000050; entry[1]=0xD61F0200;
    *(uint64_t*)(entry+2)=(uint64_t)repl;
    if(!memWrite(target,entry,16)) return false;
    *origTramp=tr;
    L("hook 0x%llx ok",(unsigned long long)rva);
    return true;
}

// =============================================================================================
// 4. Method/field cache
// =============================================================================================
static void *mGetInst,*mGetModuleByName,*mGetMyVehicle,*mForceEndDrift,*mFastOut,
            *mForceMini,*mAddEV,*mSetKey,*mGetKeyFlags,*mNearestTP,
            *mGBeginArea,*mGEndArea,*mGBox,*mGButton,*mGColor,*mGBtn,*mGTgl,
            *mGLabel,*mGSlider,*mGSpace;
static size_t off_mECU=0, off_mState=0, off_mTorque=0, off_mNormalTop=0, off_mPowerChain=0, off_pcForceTop=0;
static void *g_inputModule=nil,*g_roadMap=nil,*g_lastTP=nil;

static bool resolveMethods(void){
    if(!g_clsReady) return false;
    if(mGetInst) return true;
    mGetInst       = mOf(clsGamePub,"GetInstance",0);
    mGetModuleByName=mOf(clsGamePub,"GetModuleByName",2);
    mGetMyVehicle  = mOf(clsVehicleFast,"GetMyVehicle",0);
    mForceEndDrift = mOf(clsVehicleFast,"ForceEndDrifting",1);
    mFastOut       = mOf(clsVehicleFast,"DoFastOutCorners",1);
    mForceMini     = mOf(clsExtraVelTrigFast,"ForceCanTriggerOncePassiveMini",1);
    mAddEV         = mOf(clsExtraVelFast,"AddExtraVelocity",6);
    mSetKey        = mOf(clsInputModule,"SetKey",2);
    mGetKeyFlags   = mOf(clsInputModule,"get_KeyFlags",0);
    mNearestTP     = mOf(clsRoadMap,"GetNearestTrackPoint",2);
    mGBeginArea    = mOf(clsGUILayout,"BeginArea",1);
    mGEndArea      = mOf(clsGUILayout,"EndArea",0);
    mGBtn          = mOf(clsGUILayout,"Button",2);
    mGTgl          = mOf(clsGUILayout,"Toggle",3);
    mGLabel        = mOf(clsGUILayout,"Label",2);
    mGSlider       = mOf(clsGUILayout,"HorizontalScrollbar",5);
    mGSpace        = mOf(clsGUILayout,"Space",1);
    mGBox          = mOf(clsGUI,"Box",2);
    mGButton       = mOf(clsGUI,"Button",2);
    mGColor        = mOf(clsGUI,"set_backgroundColor",1);
    if(!mGetInst||!mGetMyVehicle||!mForceEndDrift||!mSetKey){
        L("resolveMethods incomplete: inst=%p veh=%p fed=%p setk=%p",mGetInst,mGetMyVehicle,mForceEndDrift,mSetKey);
        return false;
    }
    return true;
}
static size_t fieldOff(void* obj,const char* name){
    void* k=il2cpp_object_get_class(obj);
    void* f=k?il2cpp_class_get_field_from_name(k,name):nil;
    return f?il2cpp_field_get_offset(f):0;
}

// =============================================================================================
// 5. Gameplay tick
// =============================================================================================
static bool g_prevDriftKey=false;
static double g_nextMiniT=0,g_nextExtraT=0;

static void frameTick(void){
    if(!g_clsReady||!resolveMethods()) return;
    void* veh = inv(mGetMyVehicle,nil,nil);
    if(!veh){ g_inputModule=nil; g_roadMap=nil; g_lastTP=nil; g_prevDriftKey=false; return; }

    // ECU offsets (lần đầu)
    if(!off_mECU){
        void* mDV = mOf(il2cpp_object_get_class(veh),"GetDynamicVehicle",0);
        void* dv  = mDV?inv(mDV,veh,nil):nil;
        if(dv){
            off_mECU = fieldOff(dv,"mECU");
            if(off_mECU){
                void* ecu=*(void**)((char*)dv+off_mECU);
                if(ecu){
                    off_mState     = fieldOff(ecu,"mState");        // +0x10
                    off_mTorque    = fieldOff(ecu,"mEngineTorque"); // +0x138
                    off_mNormalTop = fieldOff(ecu,"mNormalTopMPS"); // +0x108
                    off_mPowerChain= fieldOff(ecu,"mPowerChain");   // +0x68
                    if(off_mPowerChain){
                        void* pc=*(void**)((char*)ecu+off_mPowerChain);
                        if(pc) off_pcForceTop = fieldOff(pc,"mForceTopMPS"); // +0x34
                    }
                    L("offsets: ecu=%zu state=%zu torque=%zu top=%zu pc=%zu pcf=%zu",
                      off_mECU,off_mState,off_mTorque,off_mNormalTop,off_mPowerChain,off_pcForceTop);
                }
            }
        }
    }

    // input module + road map
    if(!g_inputModule||!g_roadMap){
        void* gp=inv(mGetInst,nil,nil);
        if(gp&&mGetModuleByName){
            if(!g_inputModule){ void* a[2]={il2cpp_string_new("InputModule"),gp}; g_inputModule=inv(mGetModuleByName,gp,a); }
            if(!g_roadMap){     void* a[2]={il2cpp_string_new("RoadMap"),gp};     g_roadMap    =inv(mGetModuleByName,gp,a); }
        }
    }
    int keyFlags=0;
    if(g_inputModule&&mGetKeyFlags){
        void* r=inv(mGetKeyFlags,g_inputModule,nil);
        if(r) keyFlags=*(int*)il2cpp_object_unbox(r);
    }
    bool driftKey=(keyFlags>>8)&1; // InputKeyType.Drift=8

    // trạng thái xe: đọc qua get_VehicleState của ECU (an toàn hơn offset vì có logic Leaping)
    int vState=0;
    {
        void* dv = nil;
        void* mDV = mOf(il2cpp_object_get_class(veh),"GetDynamicVehicle",0);
        dv = mDV?inv(mDV,veh,nil):nil;
        if(dv&&off_mECU){
            void* ecu=*(void**)((char*)dv+off_mECU);
            if(ecu){
                void* mGS = mOf(il2cpp_object_get_class(ecu),"get_VehicleState",0);
                void* r = mGS?inv(mGS,ecu,nil):nil;
                if(r) vState=*(int*)il2cpp_object_unbox(r); // 2 = Drifting
            }
        }
        if(!vState && off_mState) { /* fallback: giữ 0 */ }
    }

    // ---- tự ngắt drift khi thả nút ----
    bool released = g_prevDriftKey && !driftKey;
    if(released && vState==2){
        if(g_autoCutDrift){ void* a[1]={veh}; inv(mForceEndDrift,nil,a); }
        if(g_autoFastOut){ void* a[1]={veh}; inv(mFastOut,nil,a); }
    }
    g_prevDriftKey=driftKey;

    double now=CACurrentMediaTime();

    // ---- mini boost liên tục ----
    if(vState==2 && g_contMini && mForceMini && now>=g_nextMiniT){
        void* a[1]={veh}; inv(mForceMini,nil,a);
        g_nextMiniT=now+g_miniInterval;
    }
    // ---- boost thêm (ExtraVelocityType.Mini=1) ----
    if(g_extraKmph>0.5f && mAddEV && now>=g_nextExtraT){
        int evType=1; float kmph=g_extraKmph, tq=g_extraKmph*0.35f, dur=g_extraDur; bool imm=false;
        void* et=il2cpp_value_box(clsEnumExtraVelType,&evType);
        void* a[6]={veh,et,boxF(kmph),boxF(tq),boxF(dur),boxB(imm)};
        inv(mAddEV,nil,a);
        g_nextExtraT=now+1.0;
    }

    // ---- steering assist ----
    if(g_steerAssist && g_inputModule && mSetKey && mNearestTP && g_roadMap){
        void* mPos=mOf(il2cpp_object_get_class(veh),"get_Position",0);
        void* mFwd=mOf(il2cpp_object_get_class(veh),"get_Forward",0);
        void* rp=mPos?inv(mPos,veh,nil):nil;
        void* rf=mFwd?inv(mFwd,veh,nil):nil;
        if(rp&&rf){
            float* pos=(float*)il2cpp_object_unbox(rp);
            float* fwd=(float*)il2cpp_object_unbox(rf);
            void* aTP[2]={il2cpp_value_box(mOf(clsGameObject,"transform",0)?clsGameObject:clsGameObject,pos),g_lastTP};
            // Vector3 box: dùng class Vector3 — scan không lưu, lấy từ GameObject class không được.
            // Cách chắc: box bằng class của object pos (chính là Vector3 khi get_Position trả về object)
            void* vec3K=il2cpp_object_get_class(rp);
            aTP[0]=il2cpp_value_box(vec3K,pos);
            void* tp=inv(mNearestTP,g_roadMap,aTP);
            if(tp){
                g_lastTP=tp;
                void* mDir=mOf(il2cpp_object_get_class(tp),"get_Direction",0);
                void* rd=mDir?inv(mDir,tp,nil):nil;
                if(rd){
                    float* dir=(float*)il2cpp_object_unbox(rd);
                    float cx=fwd[0]*dir[2]-fwd[2]*dir[0];
                    float dot=fwd[0]*dir[0]+fwd[2]*dir[2];
                    float deg=atan2f(cx,dot)*57.29578f;
                    if(g_steerInvert) deg=-deg;
                    float dead=30.0f-28.0f*g_steerStrength;
                    bool wantL=(deg<-dead), wantR=(deg>dead);
                    void* aL[2]={boxI(1),boxB(wantL)}; // Left=1
                    void* aR[2]={boxI(2),boxB(wantR)}; // Right=2
                    inv(mSetKey,g_inputModule,aL);
                    inv(mSetKey,g_inputModule,aR);
                }
            } else g_lastTP=nil;
        }
    }
}

// =============================================================================================
// 6. Menu (IMGUI qua hook OnGUI của DemoGUIMessage — MonoBehaviour có sẵn trong binary)
// =============================================================================================
static void menuSlider(float* v,float lo,float hi,const char* name){
    if(!mGLabel) return;
    { void* a[2]={il2cpp_string_new(name),nil}; inv(mGLabel,nil,a); }
    if(!mGSlider) return;
    void* a[5]={boxF(*v),boxF(1.0f),boxF(lo),boxF(hi),nil};
    void* r=inv(mGSlider,nil,a);
    if(r){ float nv=*(float*)il2cpp_object_unbox(r); if(fabsf(nv-*v)>1e-4f){ *v=nv; } }
}
static bool menuToggle(bool v,const char* name){
    if(!mGTgl) return v;
    void* a[3]={boxB(v),il2cpp_string_new(name),nil};
    void* r=inv(mGTgl,nil,a);
    return r?*(bool*)il2cpp_object_unbox(r):v;
}
static void menuLabel(const char* s){
    if(mGLabel){ void* a[2]={il2cpp_string_new(s),nil}; inv(mGLabel,nil,a); }
}
static void menuSpace(float f){ if(mGSpace){ void* a[1]={boxF(f)}; inv(mGSpace,nil,a); } }

static void drawMenu(void){
    if(!g_clsReady||!mGButton||!mGBox||!mGBeginArea) return;
    // nút bật/tắt menu
    {
        float r[4]={14,60,86,96}; // Rect {x,y,w,h} == Color {r,g,b,a} — 16B, cùng ABI
        void* rb=il2cpp_value_box(clsColor?clsColor:clsFloat,r);
        void* a[2]={rb,il2cpp_string_new(g_menuOpen?"ZSM \xE2\x97\x80":"ZSM")};
        void* res=inv(mGButton,nil,a);
        if(res&&*(bool*)il2cpp_object_unbox(res)){ g_menuOpen=!g_menuOpen; cfgSave(); }
    }
    if(!g_menuOpen) return;
    if(mGColor){ void* a[1]={boxColor(0.05f,0.05f,0.09f,0.85f)}; inv(mGColor,nil,a); }
    {   float rb[4]={10,40,320,700};
        void* r=il2cpp_value_box(clsColor?clsColor:clsFloat,rb);
        void* a[2]={r,il2cpp_string_new("  ZSM DRIFT MENU")};
        inv(mGBox,nil,a); }
    {   float ra[4]={14,52,316,696};
        void* r=il2cpp_value_box(clsColor?clsColor:clsFloat,ra);
        void* a[1]={r}; inv(mGBeginArea,nil,a); }

    menuLabel("== Gia toc (an) ==");
    g_accelOn = menuToggle(g_accelOn,"Bat gia toc an (torque)");
    { float pct=(g_accelMult-1.0f)*100.0f;
      menuSlider(&pct,0,150,"Luc day 0-150%");
      g_accelMult=1.0f+pct/100.0f; }
    menuSlider(&g_topAddPct,0,100,"Top speed +0-100% (HIENT km/h)");
    g_hideKmph = menuToggle(g_hideKmph,"Gia dong ho km/h");
    menuSpace(8);
    menuLabel("== Drift ==");
    g_noSlowDrift  = menuToggle(g_noSlowDrift,"Drift khong giam toc");
    g_autoCutDrift = menuToggle(g_autoCutDrift,"Tu ngat drift khi tha nut");
    g_autoFastOut  = menuToggle(g_autoFastOut,"Fast-out-corners khi tha");
    menuSpace(8);
    menuLabel("== Mini boost ==");
    g_contMini = menuToggle(g_contMini,"Lien tuc + miniboost");
    menuSlider(&g_miniInterval,0.2f,3.0f,"Chu ky miniboost (s)");
    menuSlider(&g_extraKmph,0,80,"Boost them km/h (0=off)");
    menuSlider(&g_extraDur,0.3f,3.0f,"Thoi luong boost (s)");
    menuSpace(8);
    menuLabel("== Steering assist ==");
    g_steerAssist = menuToggle(g_steerAssist,"Tu lai ve track line");
    { float s=g_steerStrength*100.0f;
      menuSlider(&s,0,100,"Steering strength");
      g_steerStrength=s/100.0f; }
    g_steerInvert = menuToggle(g_steerInvert,"Dao chieu lai");
    menuSpace(8);
    menuLabel("== Chong anticheat ==");
    g_blockCrack   = menuToggle(g_blockCrack,"Chan NotifyCrack");
    g_blockCheatCp = menuToggle(g_blockCheatCp,"Chan bao cheat checkpoint");
    g_blockSdcEV   = menuToggle(g_blockSdcEV,"Chan SdcExtraVelocity");
    g_blockActorCp = menuToggle(g_blockActorCp,"Chan ActorCpReporter (nguy hiem)");
    cfgSave();
    if(mGEndArea){ void* a[1]={nil}; inv(mGEndArea,nil,a); }
}

// =============================================================================================
// 7. Hook bodies
// =============================================================================================
static void* orig_OnGUI=nil;
static void hook_OnGUI(void* self){
    if(orig_OnGUI) ((void(*)(void*))orig_OnGUI)(self);
    drawMenu();
}
static void* orig_UpdateECU=nil;
static void hook_UpdateECU(void* self,float dt){
    if(orig_UpdateECU) ((void(*)(void*,float))orig_UpdateECU)(self,dt);
    if(g_accelOn&&g_accelMult>1.001f){
        if(!off_mTorque){
            off_mTorque=fieldOff(self,"mEngineTorque");
            off_mNormalTop=fieldOff(self,"mNormalTopMPS");
            off_mPowerChain=fieldOff(self,"mPowerChain");
            if(off_mPowerChain){
                void* pc=*(void**)((char*)self+off_mPowerChain);
                if(pc) off_pcForceTop=fieldOff(pc,"mForceTopMPS");
            }
            if(off_mTorque) L("torque off=%zu top=%zu",off_mTorque,off_mNormalTop);
        }
        if(off_mTorque){
            float* t=(float*)((char*)self+off_mTorque);
            if(*t>0) *t*=g_accelMult; // gia tốc ẩn — chỉ torque, top speed giữ nguyên
        }
        if(g_topAddPct>0.5f&&off_mPowerChain&&off_pcForceTop){
            void* pc=*(void**)((char*)self+off_mPowerChain);
            if(pc){
                // mForceTopMPS (0x34) chỉ là "force" override — đặt trực tiếp field mỗi frame
                float base=g_topAddPct>0? 0 : 0;
                (void)base;
                // đọc mCurBaseTorque để lấy top gốc? đơn giản: lưu normalTop lần đầu
                static float baseTop=0;
                if(baseTop<=0&&off_mNormalTop) baseTop=*(float*)((char*)self+off_mNormalTop);
                if(baseTop>0){
                    *(float*)((char*)pc+off_pcForceTop)=baseTop*(1.0f+g_topAddPct/100.0f);
                    g_kmphScale=1.0f/(1.0f+g_topAddPct/100.0f);
                }
            }
        }
    }
}
static void* orig_Damping=nil;
static void hook_Damping(void* self,float curMPS,float dampingCoef,int stateType,float dt){
    if(g_noSlowDrift) return; // bỏ toàn bộ ma sát drift (chặn native PHY_VehicleApplyExtraDriftFriction)
    if(orig_Damping) ((void(*)(void*,float,float,int,float))orig_Damping)(self,curMPS,dampingCoef,stateType,dt);
}
static void* orig_KMPH=nil;
static float hook_KMPH(void* self){
    float v=orig_KMPH?((float(*)(void*))orig_KMPH)(self):0;
    return (g_hideKmph&&g_kmphScale<1.0f)? v*g_kmphScale : v;
}

static uint32_t sv_crack[4],sv_cheatcp[4],sv_sdcev[4],sv_actorcp[4];
static bool done_crack,done_cheatcp,done_sdcev,done_actorcp;
static void applyAcPatches(void){
    if(!g_base) return;
    g_blockCrack  ?patchRet(0xC7B4F20,sv_crack,&done_crack)    :unpatchRet(0xC7B4F20,sv_crack,&done_crack);
    g_blockCheatCp?patchRet(0x46A9644,sv_cheatcp,&done_cheatcp):unpatchRet(0x46A9644,sv_cheatcp,&done_cheatcp);
    g_blockSdcEV  ?patchRet(0x991481C,sv_sdcev,&done_sdcev)    :unpatchRet(0x991481C,sv_sdcev,&done_sdcev);
    g_blockActorCp?patchRet(0x4B3B260,sv_actorcp,&done_actorcp):unpatchRet(0x4B3B260,sv_actorcp,&done_actorcp);
}

// =============================================================================================
// 8. Menu host
// =============================================================================================
static bool g_hostSpawned=false;
static void spawnMenuHost(void){
    if(g_hostSpawned||!g_clsReady||!clsGameObject||!clsDemoGUIMsg) return;
    void* mCtor=mOf(clsGameObject,".ctor",1);
    void* mAdd =mOf(clsGameObject,"AddComponent",1);
    if(!mCtor||!mAdd){ L("menu host methods missing"); return; }
    void* go=il2cpp_object_new(clsGameObject);
    if(!go) return;
    { void* a[1]={il2cpp_string_new("ZSMMenuHost")}; inv(mCtor,go,a); }
    void* t=il2cpp_type_get_object(il2cpp_class_get_type(clsDemoGUIMsg));
    { void* a[1]={t}; inv(mAdd,go,a); }
    g_hostSpawned=true;
    L("menu host spawned");
    if(!hookRVA(0xCA27DCC /*DemoGUIMessage.OnGUI*/, (void*)hook_OnGUI, &orig_OnGUI))
        L("!! OnGUI hook fail");
}

// =============================================================================================
// 9. Driver
// =============================================================================================
@interface ZSMDriver : NSObject
- (void)tick:(CADisplayLink*)dl;
@end
@implementation ZSMDriver
- (void)tick:(CADisplayLink*)dl{
    (void)dl;
    if(!g_il2cppReady){
        if(!loadIl2cppSyms()) return;
        g_domain=il2cpp_domain_get();
        if(!g_domain) return;
        il2cpp_thread_attach(g_domain);
        g_il2cppReady=true;
        L("il2cpp attached");
    }
    if(!g_base) findBase();
    if(!g_base) return;
    if(!g_clsReady) scanClasses();
    if(!g_clsReady) return;
    static bool hooksDone=false;
    if(!hooksDone){
        bool ok1=hookRVA(0x7AF8938 /*NssPhyVehicleECU.UpdateECU*/,(void*)hook_UpdateECU,&orig_UpdateECU);
        bool ok2=hookRVA(0x7C713DC /*DriftingSlideVelDamping*/,(void*)hook_Damping,&orig_Damping);
        bool ok3=hookRVA(0x7AFC4A0 /*ReadVehicleKMPH*/,(void*)hook_KMPH,&orig_KMPH);
        L("hooks ecu=%d damping=%d kmph=%d",ok1,ok2,ok3);
        hooksDone=true;
        spawnMenuHost();
    }
    applyAcPatches();
    frameTick();
}
@end
static ZSMDriver* g_driver=nil;

__attribute__((constructor))
static void zsmInit(void){
    cfgLoad();
    findBase();
    L("ctor base=0x%llx",(unsigned long long)g_base);
    dispatch_async(dispatch_get_main_queue(), ^{
        g_driver=[ZSMDriver new];
        CADisplayLink* dl=[CADisplayLink displayLinkWithTarget:g_driver selector:@selector(tick:)];
        dl.preferredFramesPerSecond=30;
        [dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        L("displaylink started");
    });
}
