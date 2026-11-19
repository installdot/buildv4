// ZSM Drift Tweak — Speed Drifters VN (UnityFramework, il2cpp arm64) — v2.1 crash-fix
//
// Fix so với v1 (crash vài giây sau inject):
//  F1  Resolve method/field MỘT LẦN, cache con trỏ — không gọi il2cpp API trong hot-hook
//      (UpdateECU chạy trên thread Unity physics; il2cpp API + GC không thread-safe).
//  F2  frameTick: null-guard toàn bộ; xác thực class MyVehicle đúng 1 lần (clsNssVehicle).
//  F3  Menu IMGUI: GUI.*(Rect,...) thuần — bỏ GUILayout (nguồn exception-storm chính:
//      overload Label(string,GUIStyle) match 2-arg và nhận nil GUILayoutOption[] sai kiểu).
//      Rect/Color box dùng clsColor (struct 16B, cùng ABI).
//  F4  spawnMenuHost chỉ chạy khi GamePub.GetInstance() != null.
//  F5  hook_OnGUI + tick wrap @try/@catch.
//  F6  reloc16 fail → không ghi entry (không nửa-patch); icache invalidate nguyên page.
//  F7  Patch mạnh (SdcEV/ActorCp) mặc định OFF.
//  F8  Steering assist throttle mỗi 3 tick.
//  F9  inv() log exception 1 lần/method; invoke bỏ qua khi obj=nil.
//  F10 HorizontalScrollbar 6-arg (Rect,value,size,left,right,style) — khớp dump.cs:505698.
//
// Anchor RVA verify trên UnityFramework.i64 (imagebase 0x0, cryptid=0 → RVA==offset==IDB):
//   UpdateECU 0x7AF8938 | Damping 0x7C713DC | KMPH 0x7AFC4A0 | ForceEndDrifting 0xAC74000
//   ForceMini 0x50DBB58 | AddEV 0x50D5F4C | NotifyCrack 0xC7B4F20 | ReportCheat 0x46A9644
//   SdcEV.Update 0x991481C | ActorCp.Update 0x4B3B260 | DemoGUI.OnGUI 0xCA27DCC

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <libkern/OSCacheControl.h>
#import <math.h>
#import <string.h>

#define L(...)  NSLog(@"[ZSM] " __VA_ARGS__)

// ==== 0. Config ====
static bool   g_menuOpen=false;
static bool   g_accelOn=true;
static float  g_accelMult=1.30f;
static float  g_topAddPct=0.0f;
static bool   g_hideKmph=false;
static bool   g_noSlowDrift=true;
static bool   g_autoCutDrift=true;
static bool   g_autoFastOut=false;
static bool   g_contMini=true;
static float  g_miniInterval=1.0f;
static float  g_extraKmph=0.0f;
static float  g_extraDur=1.0f;
static bool   g_steerAssist=false;
static float  g_steerStrength=0.6f;
static bool   g_steerInvert=false;
static bool   g_blockCrack=true;
static bool   g_blockCheatCp=true;
static bool   g_blockSdcEV=false;
static bool   g_blockActorCp=false;
static float  g_kmphScale=1.0f;

static void cfgLoad(void){
    NSUserDefaults*d=[NSUserDefaults standardUserDefaults];
    if([d objectForKey:@"zsm_accelOn"])     g_accelOn     =[d boolForKey:@"zsm_accelOn"];
    if([d objectForKey:@"zsm_accelMult"])   g_accelMult   =[d floatForKey:@"zsm_accelMult"];
    g_topAddPct    =[d floatForKey:@"zsm_topAddPct"];
    g_hideKmph     =[d boolForKey:@"zsm_hideKmph"];
    if([d objectForKey:@"zsm_noSlowDrift"]) g_noSlowDrift =[d boolForKey:@"zsm_noSlowDrift"];
    if([d objectForKey:@"zsm_autoCutDrift"])g_autoCutDrift=[d boolForKey:@"zsm_autoCutDrift"];
    g_autoFastOut  =[d boolForKey:@"zsm_autoFastOut"];
    if([d objectForKey:@"zsm_contMini"])    g_contMini    =[d boolForKey:@"zsm_contMini"];
    g_miniInterval =[d floatForKey:@"zsm_miniInterval"]; if(g_miniInterval<0.3f) g_miniInterval=1.0f;
    g_extraKmph    =[d floatForKey:@"zsm_extraKmph"];
    g_extraDur     =[d floatForKey:@"zsm_extraDur"];     if(g_extraDur<0.3f)     g_extraDur=1.0f;
    g_steerAssist  =[d boolForKey:@"zsm_steerAssist"];
    g_steerStrength=[d floatForKey:@"zsm_steerStrength"];if(g_steerStrength<=0)  g_steerStrength=0.6f;
    g_steerInvert  =[d boolForKey:@"zsm_steerInvert"];
    if(g_accelMult<1) g_accelMult=1; if(g_accelMult>2.5f) g_accelMult=2.5f;
}
static void cfgSave(void){
    NSUserDefaults*d=[NSUserDefaults standardUserDefaults];
    [d setBool:g_accelOn forKey:@"zsm_accelOn"];           [d setFloat:g_accelMult forKey:@"zsm_accelMult"];
    [d setFloat:g_topAddPct forKey:@"zsm_topAddPct"];      [d setBool:g_hideKmph forKey:@"zsm_hideKmph"];
    [d setBool:g_noSlowDrift forKey:@"zsm_noSlowDrift"];   [d setBool:g_autoCutDrift forKey:@"zsm_autoCutDrift"];
    [d setBool:g_autoFastOut forKey:@"zsm_autoFastOut"];   [d setBool:g_contMini forKey:@"zsm_contMini"];
    [d setFloat:g_miniInterval forKey:@"zsm_miniInterval"];[d setFloat:g_extraKmph forKey:@"zsm_extraKmph"];
    [d setFloat:g_extraDur forKey:@"zsm_extraDur"];        [d setBool:g_steerAssist forKey:@"zsm_steerAssist"];
    [d setFloat:g_steerStrength forKey:@"zsm_steerStrength"];[d setBool:g_steerInvert forKey:@"zsm_steerInvert"];
    [d synchronize];
}

// ==== 1. il2cpp ====
typedef void* (*fn_domain_get)(void);
typedef void* (*fn_thread_attach)(void*);
typedef size_t(*fn_domain_assemblies)(void*, void**);
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
    // dlsym trả void* — gán thẳng, không cần cast (typeof/__typeof__ không portable trên mọi toolchain)
    #define SYM(var, name) do{ var=dlsym(RTLD_DEFAULT,name); if(!(var)){L("missing %s",name); return false;} }while(0)
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
    if(!method||!obj) return nil;
    void* exc=nil;
    void* r=il2cpp_runtime_invoke(method,obj,args,&exc);
    if(exc){
        static void* lastBad=nil;
        if(lastBad!=method){ lastBad=method; L("invoke exc @%p",(void*)method); }
        return nil;
    }
    return r;
}
static void* mOf(void* k,const char* n,int c){ return k?il2cpp_class_get_method_from_name(k,n,c):nil; }

static void *clsFloat,*clsBool,*clsInt,*clsColor;
static void* boxF(float v){ return clsFloat?il2cpp_value_box(clsFloat,&v):nil; }
static void* boxB(bool v){  return clsBool ?il2cpp_value_box(clsBool,&v):nil; }
static void* boxI(int v){   return clsInt  ?il2cpp_value_box(clsInt,&v):nil; }

// ==== 2. Class scan ====
static void *clsGamePub,*clsVehicleFast,*clsExtraVelFast,*clsExtraVelTrigFast,
            *clsInputModule,*clsRoadMap,*clsEnumExtraVelType,
            *clsGUI,*clsGameObject,*clsNssVehicle,*clsDemoGUIMsg;
static bool  g_clsReady=false;

static void** g_strCache=nil; static int g_strCount=0;
enum { STR_BTN_OPEN,STR_BTN_CLOSE,STR_TITLE,
       S_GA1,S_GA2,S_GA3,S_GA4,
       S_DR1,S_DR2,S_DR3,
       S_MB1,S_MB2,S_MB3,S_MB4,
       S_ST1,S_ST2,S_ST3,
       S_AC1,S_AC2,S_AC3,S_AC4,
       S_LBL_TOC,S_LBL_DR,S_LBL_MB,S_LBL_ST,S_LBL_AC,
       STR_COUNT };
static const char* g_strTabSrc[STR_COUNT]={
    "ZSM","ZSM <","  ZSM DRIFT MENU",
    "Bat gia toc an (torque)","Luc day 0-150%","Top speed +0-100%","Gia dong ho km/h",
    "Drift khong giam toc","Tu ngat drift khi tha nut","Fast-out-corners khi tha",
    "Lien tuc + miniboost","Chu ky miniboost (s)","Boost them km/h (0=off)","Thoi luong boost (s)",
    "Tu lai ve track line","Steering strength","Dao chieu lai",
    "Chan NotifyCrack","Chan bao cheat checkpoint","Chan SdcExtraVelocity",
    "Chan ActorCpReporter (nguy hiem)",
    "== Gia toc (an) ==","== Drift ==","== Mini boost ==","== Steering assist ==",
    "== Chong anticheat ==",
};
static void* str(int i){ return (i>=0&&i<g_strCount&&g_strCache)?g_strCache[i]:nil; }
static void buildStrCache(void){
    g_strCount=STR_COUNT;
    g_strCache=(void**)malloc(sizeof(void*)*STR_COUNT);
    for(int i=0;i<STR_COUNT;i++) g_strCache[i]=il2cpp_string_new(g_strTabSrc[i]);
}

static void scanClasses(void){
    if(g_clsReady) return;
    void* corlib=il2cpp_get_corlib(); if(!corlib) return;
    clsFloat=il2cpp_class_from_name(corlib,"System","Single");
    clsBool =il2cpp_class_from_name(corlib,"System","Boolean");
    clsInt  =il2cpp_class_from_name(corlib,"System","Int32");
    if(!clsFloat||!clsBool||!clsInt) return;
    size_t n=0;
    void** asms=(void**)il2cpp_domain_get_assemblies(g_domain,&n);
    if(!asms||!n) return;
    for(size_t i=0;i<n;i++){
        void* img=il2cpp_assembly_get_image(asms[i]); if(!img) continue;
        size_t cnt=il2cpp_image_get_class_count(img);
        for(size_t c=0;c<cnt;c++){
            void* k=il2cpp_image_get_class(img,c); if(!k) continue;
            const char* ns=il2cpp_class_get_namespace(k);
            const char* nm=il2cpp_class_get_name(k); if(!nm) continue;
            bool gb=!ns||!ns[0];
            const char* nsS=ns?ns:"";
            #define TK(cond,slot) if(cond && !slot) slot=k;
            TK(gb && !strcmp(nm,"GamePub"),                       clsGamePub)
            TK(!strcmp(nsS,"UnityEngine") && !strcmp(nm,"GUI"),       clsGUI)
            TK(!strcmp(nsS,"UnityEngine") && !strcmp(nm,"Color"),     clsColor)
            TK(!strcmp(nsS,"UnityEngine") && !strcmp(nm,"GameObject"),clsGameObject)
            TK(gb && !strcmp(nm,"VehicleFast"),               clsVehicleFast)
            TK(gb && !strcmp(nm,"ExtraVelocityFast"),         clsExtraVelFast)
            TK(gb && !strcmp(nm,"ExtraVelocityTriggerFast"),  clsExtraVelTrigFast)
            TK(gb && !strcmp(nm,"InputModule"),               clsInputModule)
            TK(gb && !strcmp(nm,"RoadMap"),                   clsRoadMap)
            TK(gb && !strcmp(nm,"ExtraVelocityType"),         clsEnumExtraVelType)
            TK(gb && !strcmp(nm,"NssVehicle"),                clsNssVehicle)
            TK(!strcmp(nsS,"RootMotion") && !strcmp(nm,"DemoGUIMessage"), clsDemoGUIMsg)
            #undef TK
        }
        g_clsReady = clsGamePub&&clsVehicleFast&&clsExtraVelFast&&clsExtraVelTrigFast
                   &&clsInputModule&&clsRoadMap&&clsEnumExtraVelType
                   &&clsGUI&&clsColor&&clsGameObject&&clsNssVehicle;
        if(g_clsReady){ buildStrCache(); L("classes+strings ready"); return; }
    }
}

// ==== 3. Patch + hook ====
static uintptr_t g_base=0;
static void findBase(void){
    for(uint32_t i=_dyld_image_count(); i-->0;){
        const char* nm=_dyld_get_image_name(i);
        if(nm && strstr(nm,"UnityFramework")){ g_base=(uintptr_t)_dyld_get_image_vmaddr_slide(i); return; }
    }
}
static bool memWrite(uintptr_t addr,const void* data,size_t len){
    vm_address_t page=addr&~(vm_page_size-1);
    vm_size_t sz=((addr+len+vm_page_size-1)&~(vm_page_size-1))-page;
    if(vm_protect(mach_task_self(),page,sz,false,VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY)!=KERN_SUCCESS){
        L("vm_protect fail @%p",(void*)addr); return false;
    }
    memcpy((void*)addr,data,len);
    vm_protect(mach_task_self(),page,sz,false,VM_PROT_READ|VM_PROT_EXECUTE);
    sys_icache_invalidate((void*)page,sz);
    return true;
}
static bool patchRet(uintptr_t rva,uint32_t saved[4],bool* done){
    if(!g_base||*done) return *done;
    uintptr_t a=g_base+rva;
    if(!saved[0]) memcpy(saved,(void*)a,16);
    uint32_t ret=0xD65F03C0;
    if(!memWrite(a,&ret,4)) return false;
    *done=true; L("patchRet 0x%llx",(unsigned long long)rva); return true;
}
static bool unpatchRet(uintptr_t rva,uint32_t saved[4],bool* done){
    if(!*done) return true;
    if(!memWrite(g_base+rva,saved,16)) return false;
    *done=false; return true;
}
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
static bool reloc16(uint32_t* dst,uint64_t dstAddr,uint32_t* src,uint64_t srcAddr){
    for(int i=0;i<4;i++){
        uint32_t ins=src[i];
        uint64_t pc=srcAddr+4ULL*i,npc=dstAddr+4ULL*i;
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
        } else if(op==0x94000000){ // BL
            int64_t off=(int64_t)(ins&0x03FFFFFF); if(off&0x2000000) off-=0x4000000;
            uint64_t tgt=pc+off*4, back=srcAddr+16;
            dst[i]=0x58000030; dst[i+1]=0xD63F0200;
            *(uint64_t*)(dst+i+2)=tgt;
            uint32_t* b=(uint32_t*)(dst+i+4);
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
    if(!reloc16((uint32_t*)tr,(uint64_t)tr,(uint32_t*)target,target)){
        L("reloc fail 0x%llx — skip",(unsigned long long)rva);
        return false;
    }
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

// ==== 4. Method cache ====
static void *mGetInst,*mGetModuleByName,*mGetMyVehicle,*mForceEndDrift,*mFastOut,
            *mForceMini,*mAddEV,*mSetKey,*mGetKeyFlags,*mNearestTP,
            *mGBox,*mGButton,*mGColor,*mGLabel,*mGSliderR;
static size_t off_mECU=0,off_mTorque=0,off_mNormalTop=0,off_mPowerChain=0,off_pcForceTop=0;
static void *g_inputModule=nil,*g_roadMap=nil,*g_lastTP=nil;

static bool resolveAll(void){
    if(!g_clsReady) return false;
    if(mGetInst) return true;
    mGetInst        = mOf(clsGamePub,"GetInstance",0);
    mGetModuleByName= mOf(clsGamePub,"GetModuleByName",2);
    mGetMyVehicle   = mOf(clsVehicleFast,"GetMyVehicle",0);
    mForceEndDrift  = mOf(clsVehicleFast,"ForceEndDrifting",1);
    mFastOut        = mOf(clsVehicleFast,"DoFastOutCorners",1);
    mForceMini      = mOf(clsExtraVelTrigFast,"ForceCanTriggerOncePassiveMini",1);
    mAddEV          = mOf(clsExtraVelFast,"AddExtraVelocity",6);
    mSetKey         = mOf(clsInputModule,"SetKey",2);
    mGetKeyFlags    = mOf(clsInputModule,"get_KeyFlags",0);
    mNearestTP      = mOf(clsRoadMap,"GetNearestTrackPoint",2);
    mGBox           = mOf(clsGUI,"Box",2);
    mGButton        = mOf(clsGUI,"Button",2);
    mGColor         = mOf(clsGUI,"set_backgroundColor",1);
    mGLabel         = mOf(clsGUI,"Label",2);
    mGSliderR       = mOf(clsGUI,"HorizontalScrollbar",6);
    if(!mGetInst||!mGetMyVehicle||!mForceEndDrift||!mSetKey||!mGetKeyFlags||!mGBox||!mGButton){
        L("resolveAll incomplete");
        return false;
    }
    L("methods resolved");
    return true;
}

// ==== 5. Gameplay tick ====
static bool g_prevDriftKey=false;
static double g_nextMiniT=0,g_nextExtraT=0;
static int    g_tickDiv=0;
static bool   g_inRace=false;

static void frameTick(void){
    if(!g_clsReady||!resolveAll()) return;
    if(++g_tickDiv>3) g_tickDiv=0;

    void* veh=inv(mGetMyVehicle,nil,nil);
    if(!veh){
        if(g_inRace){ g_inRace=false; g_inputModule=nil; g_roadMap=nil; g_lastTP=nil;
                      g_prevDriftKey=false; L("left race"); }
        return;
    }
    if(!g_inRace){
        if(il2cpp_object_get_class(veh)!=clsNssVehicle) return;
        g_inRace=true; L("entered race");
    }
    if(!g_inputModule||!g_roadMap){
        void* gp=inv(mGetInst,nil,nil);
        if(gp&&mGetModuleByName){
            if(!g_inputModule){ void* a[2]={il2cpp_string_new("InputModule"),gp};
                                g_inputModule=inv(mGetModuleByName,gp,a); }
            if(!g_roadMap){     void* a[2]={il2cpp_string_new("RoadMap"),gp};
                                g_roadMap=inv(mGetModuleByName,gp,a); }
        }
        if(!g_inputModule) return;
    }
    void* rK=inv(mGetKeyFlags,g_inputModule,nil);
    if(!rK) return;
    int keyFlags=*(int*)il2cpp_object_unbox(rK);
    bool driftKey=(keyFlags>>8)&1;

    static void* mGetDV=nil,*mGetVS=nil; static void* lastEcuClass=nil;
    if(!mGetDV){
        mGetDV=mOf(il2cpp_object_get_class(veh),"GetDynamicVehicle",0);
        if(!mGetDV) return;
    }
    void* dv=inv(mGetDV,veh,nil);
    if(!dv) return;
    if(!off_mECU){
        void* f=il2cpp_class_get_field_from_name(il2cpp_object_get_class(dv),"mECU");
        off_mECU=f?il2cpp_field_get_offset(f):0;
        if(!off_mECU) return;
    }
    void* ecu=*(void**)((char*)dv+off_mECU);
    if(!ecu) return;
    void* ecuK=il2cpp_object_get_class(ecu);
    if(ecuK!=lastEcuClass){
        lastEcuClass=ecuK;
        mGetVS=mOf(ecuK,"get_VehicleState",0);
        if(!off_mTorque){
            void* f =il2cpp_class_get_field_from_name(ecuK,"mEngineTorque");
            off_mTorque=f ?il2cpp_field_get_offset(f):0;
            void* f2=il2cpp_class_get_field_from_name(ecuK,"mNormalTopMPS");
            off_mNormalTop=f2?il2cpp_field_get_offset(f2):0;
            void* f3=il2cpp_class_get_field_from_name(ecuK,"mPowerChain");
            off_mPowerChain=f3?il2cpp_field_get_offset(f3):0;
            if(off_mPowerChain){
                void* pc=*(void**)((char*)ecu+off_mPowerChain);
                if(pc){
                    void* f4=il2cpp_class_get_field_from_name(il2cpp_object_get_class(pc),"mForceTopMPS");
                    off_pcForceTop=f4?il2cpp_field_get_offset(f4):0;
                }
            }
            L("offs tq=%zu top=%zu pc=%zu pcf=%zu",off_mTorque,off_mNormalTop,off_mPowerChain,off_pcForceTop);
        }
    }
    int vState=0;
    if(mGetVS){
        void* r=inv(mGetVS,ecu,nil);
        if(r) vState=*(int*)il2cpp_object_unbox(r);
    }

    bool released=g_prevDriftKey&&!driftKey;
    if(released&&vState==2){
        if(g_autoCutDrift){ void* a[1]={veh}; inv(mForceEndDrift,nil,a); }
        if(g_autoFastOut){ void* a[1]={veh}; inv(mFastOut,nil,a); }
    }
    g_prevDriftKey=driftKey;

    double now=CACurrentMediaTime();
    if(vState==2&&g_contMini&&mForceMini&&now>=g_nextMiniT){
        void* a[1]={veh}; inv(mForceMini,nil,a);
        g_nextMiniT=now+g_miniInterval;
    }
    if(g_extraKmph>0.5f&&mAddEV&&now>=g_nextExtraT){
        int evType=1; float kmph=g_extraKmph,tq=g_extraKmph*0.35f,dur=g_extraDur; bool imm=false;
        void* et=il2cpp_value_box(clsEnumExtraVelType,&evType);
        if(et){
            void* a[6]={veh,et,boxF(kmph),boxF(tq),boxF(dur),boxB(imm)};
            inv(mAddEV,nil,a);
        }
        g_nextExtraT=now+1.0;
    }

    if(g_steerAssist&&g_tickDiv==0&&mSetKey&&mNearestTP&&g_roadMap){
        static void* mVehGetPos=nil,*mVehGetFwd=nil;
        if(!mVehGetPos){
            void* k=il2cpp_object_get_class(veh);
            mVehGetPos=mOf(k,"get_Position",0);
            mVehGetFwd=mOf(k,"get_Forward",0);
            if(!mVehGetPos||!mVehGetFwd) return;
        }
        void* rp=inv(mVehGetPos,veh,nil);
        void* rf=inv(mVehGetFwd,veh,nil);
        if(!rp||!rf) return;
        float* pos=(float*)il2cpp_object_unbox(rp);
        float* fwd=(float*)il2cpp_object_unbox(rf);
        if(!pos||!fwd) return;
        void* vec3K=il2cpp_object_get_class(rp);
        void* aTP[2]={il2cpp_value_box(vec3K,pos),g_lastTP};
        void* tp=inv(mNearestTP,g_roadMap,aTP);
        if(tp){
            g_lastTP=tp;
            static void* mDir=nil; static void* lastTpClass=nil;
            void* tpK=il2cpp_object_get_class(tp);
            if(!mDir||tpK!=lastTpClass){ lastTpClass=tpK; mDir=mOf(tpK,"get_Direction",0); }
            void* rd=mDir?inv(mDir,tp,nil):nil;
            if(rd){
                float* dir=(float*)il2cpp_object_unbox(rd);
                float cx=fwd[0]*dir[2]-fwd[2]*dir[0];
                float dot=fwd[0]*dir[0]+fwd[2]*dir[2];
                float deg=atan2f(cx,dot)*57.29578f;
                if(g_steerInvert) deg=-deg;
                float dead=30.0f-28.0f*g_steerStrength;
                bool wantL=(deg<-dead),wantR=(deg>dead);
                void* aL[2]={boxI(1),boxB(wantL)};
                void* aR[2]={boxI(2),boxB(wantR)};
                inv(mSetKey,g_inputModule,aL);
                inv(mSetKey,g_inputModule,aR);
            }
        } else g_lastTP=nil;
    }
}

// ==== 6. Menu (GUI.* Rect-based, zero-alloc) ====
static void menuLabelR(float x,float y,float w,float h,int idx){
    if(!mGLabel) return;
    float r[4]={x,y,w,h};
    void* rr=il2cpp_value_box(clsColor,r); if(!rr) return;
    void* a[2]={rr,str(idx)};
    inv(mGLabel,nil,a);
}
static bool menuBtnR(float x,float y,float w,float h,int idx){
    if(!mGButton) return false;
    float r[4]={x,y,w,h};
    void* rr=il2cpp_value_box(clsColor,r); if(!rr) return false;
    void* a[2]={rr,str(idx)};
    void* res=inv(mGButton,nil,a);
    return res&&*(bool*)il2cpp_object_unbox(res);
}
static float menuSliderR(float x,float y,float w,float h,float v,float lo,float hi){
    if(!mGSliderR) return v;
    float r[4]={x,y,w,h};
    void* rr=il2cpp_value_box(clsColor,r); if(!rr) return v;
    void* a[6]={rr,boxF(v),boxF(1.0f),boxF(lo),boxF(hi),nil};
    void* res=inv(mGSliderR,nil,a);
    return res?*(float*)il2cpp_object_unbox(res):v;
}

static void drawMenu(void){
    if(!g_clsReady||!mGButton||!mGBox) return;
    @try {
        if(menuBtnR(14,60,86,36,g_menuOpen?STR_BTN_CLOSE:STR_BTN_OPEN)){ g_menuOpen=!g_menuOpen; cfgSave(); }
        if(!g_menuOpen) return;
        if(mGColor){
            float bg[4]={0.05f,0.05f,0.09f,0.82f};
            void* c=il2cpp_value_box(clsColor,bg);
            if(c){ void* ca[1]={c}; inv(mGColor,nil,ca); }
        }
        { float wb[4]={10,40,320,700};
          void* r=il2cpp_value_box(clsColor,wb);
          if(r){ void* ba[2]={r,str(STR_TITLE)}; inv(mGBox,nil,ba);} }

        float x=16,y=52,w=296;
        menuLabelR(x,y,w,22,S_LBL_TOC); y+=24;
        if(menuBtnR(x,y,w,26,S_GA1)) g_accelOn=!g_accelOn; y+=30;
        menuLabelR(x,y,w,20,S_GA2); y+=22;
        { float pct=(g_accelMult-1.0f)*100.0f;
          float nv=menuSliderR(x,y,w,20,pct,0,150);
          g_accelMult=1.0f+nv/100.0f; y+=24; }
        menuLabelR(x,y,w,20,S_GA3); y+=22;
        g_topAddPct=menuSliderR(x,y,w,20,g_topAddPct,0,100); y+=24;
        if(menuBtnR(x,y,w,26,S_GA4)) g_hideKmph=!g_hideKmph; y+=34;
        menuLabelR(x,y,w,22,S_LBL_DR); y+=24;
        if(menuBtnR(x,y,w,26,S_DR1)) g_noSlowDrift=!g_noSlowDrift; y+=30;
        if(menuBtnR(x,y,w,26,S_DR2)) g_autoCutDrift=!g_autoCutDrift; y+=30;
        if(menuBtnR(x,y,w,26,S_DR3)) g_autoFastOut=!g_autoFastOut; y+=34;
        menuLabelR(x,y,w,22,S_LBL_MB); y+=24;
        if(menuBtnR(x,y,w,26,S_MB1)) g_contMini=!g_contMini; y+=30;
        menuLabelR(x,y,w,20,S_MB2); y+=22;
        g_miniInterval=menuSliderR(x,y,w,20,g_miniInterval,0.2f,3.0f); y+=24;
        menuLabelR(x,y,w,20,S_MB3); y+=22;
        g_extraKmph=menuSliderR(x,y,w,20,g_extraKmph,0,80); y+=24;
        menuLabelR(x,y,w,20,S_MB4); y+=22;
        g_extraDur=menuSliderR(x,y,w,20,g_extraDur,0.3f,3.0f); y+=28;
        menuLabelR(x,y,w,22,S_LBL_ST); y+=24;
        if(menuBtnR(x,y,w,26,S_ST1)) g_steerAssist=!g_steerAssist; y+=30;
        menuLabelR(x,y,w,20,S_ST2); y+=22;
        { float s=g_steerStrength*100.0f;
          g_steerStrength=menuSliderR(x,y,w,20,s,0,100)/100.0f; } y+=24;
        if(menuBtnR(x,y,w,26,S_ST3)) g_steerInvert=!g_steerInvert; y+=34;
        menuLabelR(x,y,w,22,S_LBL_AC); y+=24;
        if(menuBtnR(x,y,w,26,S_AC1)) g_blockCrack=!g_blockCrack; y+=30;
        if(menuBtnR(x,y,w,26,S_AC2)) g_blockCheatCp=!g_blockCheatCp; y+=30;
        if(menuBtnR(x,y,w,26,S_AC3)) g_blockSdcEV=!g_blockSdcEV; y+=30;
        if(menuBtnR(x,y,w,26,S_AC4)) g_blockActorCp=!g_blockActorCp; y+=30;
        cfgSave();
    } @catch(NSException* e){
        static int logged=0; if(logged++<3) L("menu exc: %@",e.name);
    }
}

// ==== 7. Hook bodies ====
static void* orig_OnGUI=nil;
static void hook_OnGUI(void* self){
    if(orig_OnGUI) ((void(*)(void*))orig_OnGUI)(self);
    drawMenu();
}
static void* orig_UpdateECU=nil;
static void hook_UpdateECU(void* self,float dt){
    if(orig_UpdateECU) ((void(*)(void*,float))orig_UpdateECU)(self,dt);
    if(g_accelOn&&g_accelMult>1.001f&&off_mTorque){
        float* t=(float*)((char*)self+off_mTorque);
        if(*t>0) *t*=g_accelMult;
    }
    if(g_topAddPct>0.5f&&off_mPowerChain&&off_pcForceTop){
        void* pc=*(void**)((char*)self+off_mPowerChain);
        if(pc){
            static float baseTop=0;
            if(baseTop<=0&&off_mNormalTop) baseTop=*(float*)((char*)self+off_mNormalTop);
            if(baseTop>0){
                *(float*)((char*)pc+off_pcForceTop)=baseTop*(1.0f+g_topAddPct/100.0f);
                g_kmphScale=1.0f/(1.0f+g_topAddPct/100.0f);
            }
        }
    }
}
static void* orig_Damping=nil;
static void hook_Damping(void* self,float curMPS,float dampingCoef,int stateType,float dt){
    if(g_noSlowDrift) return;
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

// ==== 8. Menu host ====
static bool g_hostSpawned=false;
static bool trySpawnMenuHost(void){
    if(g_hostSpawned||!g_clsReady||!clsGameObject||!clsDemoGUIMsg) return false;
    void* gp=inv(mGetInst,nil,nil);
    if(!gp) return false;
    void* mCtor=mOf(clsGameObject,".ctor",1);
    void* mAdd =mOf(clsGameObject,"AddComponent",1);
    if(!mCtor||!mAdd) return false;
    void* go=il2cpp_object_new(clsGameObject);
    if(!go) return false;
    { void* a[1]={il2cpp_string_new("ZSMMenuHost")}; inv(mCtor,go,a); }
    void* t=il2cpp_type_get_object(il2cpp_class_get_type(clsDemoGUIMsg));
    if(!t) return false;
    { void* a[1]={t}; inv(mAdd,go,a); }
    g_hostSpawned=true;
    L("menu host spawned");
    if(!hookRVA(0xCA27DCC,(void*)hook_OnGUI,&orig_OnGUI))
        L("!! OnGUI hook fail");
    return true;
}

// ==== 9. Driver ====
@interface ZSMDriver : NSObject
- (void)tick:(CADisplayLink*)dl;
@end
@implementation ZSMDriver
- (void)tick:(CADisplayLink*)dl{
    (void)dl;
    @try {
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
            bool ok1=hookRVA(0x7AF8938,(void*)hook_UpdateECU,&orig_UpdateECU);
            bool ok2=hookRVA(0x7C713DC,(void*)hook_Damping,&orig_Damping);
            bool ok3=hookRVA(0x7AFC4A0,(void*)hook_KMPH,&orig_KMPH);
            L("hooks ecu=%d damp=%d kmph=%d",ok1,ok2,ok3);
            hooksDone=true;
            applyAcPatches();
        }
        if(!g_hostSpawned && resolveAll()) trySpawnMenuHost();
        applyAcPatches();
        frameTick();
    } @catch(NSException* e){
        static int n=0; if(n++<3) L("tick exc: %@",e.name);
    }
}
@end
static ZSMDriver* g_driver=nil;

__attribute__((constructor))
static void zsmInit(void){
    cfgLoad();
    findBase();
    L("ctor v2.1 base=0x%llx",(unsigned long long)g_base);
    dispatch_async(dispatch_get_main_queue(), ^{
        g_driver=[ZSMDriver new];
        CADisplayLink* dl=[CADisplayLink displayLinkWithTarget:g_driver selector:@selector(tick:)];
        dl.preferredFramesPerSecond=30;
        [dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        L("displaylink started");
    });
}
