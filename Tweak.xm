// ZSM Drift Tweak v3.0 — il2cpp only, UIKit menu, KHONG patch code
//
// Vi sao v2.x crash:
//   patchRet() ghi RET vao __TEXT page -> vm_protect bo VM_PROT_EXEC tren CA PAGE 16KB
//   -> thread Unity dang chay code khac cung page fault ngay -> SIGSEGV.
//   Log dung ngay sau "patchRet 0x46a9644" xac nhan dieu nay.
//
// v3.0:
//   * KHONG ghi 1 byte code nao (khong patchRet, khong inline hook).
//   * Anticheat chan qua il2cpp: CryptoBase.crackHandler = null,
//     CheckPointReportMgr.SetEnable(false) qua MatchMgr->MatchCommonComponent.
//   * Gameplay: goi THANG native method pointer (MethodInfo->methodPointer) va
//     doc/ghi field offset truc tiep — khong il2cpp_runtime_invoke (nguon GC race).
//   * Menu: UIKit native (UIWindow subclass hitTest passthrough) — khong hook OnGUI,
//     khong chan touch cua game.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
#import <libkern/OSCacheControl.h>
#import <math.h>
#import <string.h>
#import <stdlib.h>
#import <stdarg.h>
#import <unistd.h>
#import <stdio.h>

// ================= LOG =================
static FILE* g_log=nil;
static void zsmLog(const char* fmt,...) __attribute__((format(printf,1,2)));
static void zsmLog(const char* fmt,...){
    char buf[512]; va_list ap; va_start(ap,fmt);
    vsnprintf(buf,sizeof(buf),fmt,ap); va_end(ap);
    NSLog(@"[ZSM] %s",buf);
    if(g_log){ fputs(buf,g_log); fputc('\n',g_log); fflush(g_log); }
}
#define L(...) zsmLog(__VA_ARGS__)
static void logInit(void){
    if(g_log) return;
    @try{
        NSString* d=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        if(!d) return;
        g_log=fopen([[d stringByAppendingPathComponent:@"zsm.log"] fileSystemRepresentation],"a");
        if(g_log){ setvbuf(g_log,nil,_IOLBF,0); fprintf(g_log,"\n==== ZSM v3.0 ====\n"); fflush(g_log); }
    }@catch(NSException*e){}
}

// ================= CONFIG =================
static bool  g_accelOn=true;       static float g_accelMult=1.30f;
static bool  g_autoCutDrift=true;  static bool  g_autoFastOut=false;
static bool  g_contMini=true;      static float g_miniInterval=1.0f;
static float g_extraKmph=0.0f;     static float g_extraDur=1.0f;
static bool  g_steerAssist=false;  static float g_steerStrength=0.60f;
static bool  g_steerInvert=false;

static void cfgSave(void){
    NSUserDefaults*d=[NSUserDefaults standardUserDefaults];
    [d setBool:g_accelOn forKey:@"z_accel"];   [d setFloat:g_accelMult forKey:@"z_mult"];
    [d setBool:g_autoCutDrift forKey:@"z_cut"];[d setBool:g_autoFastOut forKey:@"z_fastout"];
    [d setBool:g_contMini forKey:@"z_mini"];   [d setFloat:g_miniInterval forKey:@"z_miniInt"];
    [d setFloat:g_extraKmph forKey:@"z_exKmph"];[d setFloat:g_extraDur forKey:@"z_exDur"];
    [d setBool:g_steerAssist forKey:@"z_steer"];[d setFloat:g_steerStrength forKey:@"z_steerStr"];
    [d setBool:g_steerInvert forKey:@"z_invert"];
    [d synchronize];
}
static void cfgLoad(void){
    NSUserDefaults*d=[NSUserDefaults standardUserDefaults];
    if([d objectForKey:@"z_accel"])  g_accelOn=[d boolForKey:@"z_accel"];
    if([d objectForKey:@"z_mult"])   g_accelMult=[d floatForKey:@"z_mult"];
    if([d objectForKey:@"z_cut"])    g_autoCutDrift=[d boolForKey:@"z_cut"];
    g_autoFastOut=[d boolForKey:@"z_fastout"];
    if([d objectForKey:@"z_mini"])   g_contMini=[d boolForKey:@"z_mini"];
    if([d floatForKey:@"z_miniInt"]>0.2f) g_miniInterval=[d floatForKey:@"z_miniInt"];
    g_extraKmph=[d floatForKey:@"z_exKmph"];
    if([d floatForKey:@"z_exDur"]>0.2f) g_extraDur=[d floatForKey:@"z_exDur"];
    g_steerAssist=[d boolForKey:@"z_steer"];
    if([d floatForKey:@"z_steerStr"]>0) g_steerStrength=[d floatForKey:@"z_steerStr"];
    g_steerInvert=[d boolForKey:@"z_invert"];
    if(g_accelMult<1)g_accelMult=1; if(g_accelMult>2.5f)g_accelMult=2.5f;
}

// ================= IL2CPP SYMS =================
typedef void*  (*f_v)(void);
typedef void*  (*f_vp)(void*);
typedef const void** (*f_asms)(void*,size_t*);
typedef size_t (*f_cnt)(void*);
typedef void*  (*f_cls)(void*,size_t);
typedef const char* (*f_nm)(void*);
typedef void*  (*f_meth)(void*,const char*,int);
typedef void*  (*f_fld)(void*,const char*);
typedef size_t (*f_off)(void*);

static f_v     i_domain;   static f_vp i_attach;
static f_asms  i_asms;     static f_vp i_img;
static f_cnt   i_cnt;      static f_cls i_cls;
static f_nm    i_name, i_ns;
static f_meth  i_meth;     static f_fld i_fld;  static f_off i_off;
static f_v     i_corlib;   static f_vp i_ocls, i_parent;
static void*  (*i_str)(const char*);   // il2cpp_string_new
static f_vp    i_ctype, i_tobj;
static void* g_domain=nil;
static bool  g_ready=false;

static bool loadSyms(void){
    #define S(v,n) do{ void*_p=dlsym(RTLD_DEFAULT,n); if(!_p) return false; memcpy(&v,&_p,sizeof(void*)); }while(0)
    S(i_domain,"il2cpp_domain_get");            S(i_attach,"il2cpp_thread_attach");
    S(i_asms,"il2cpp_domain_get_assemblies");   S(i_img,"il2cpp_assembly_get_image");
    S(i_cnt,"il2cpp_image_get_class_count");    S(i_cls,"il2cpp_image_get_class");
    S(i_name,"il2cpp_class_get_name");          S(i_ns,"il2cpp_class_get_namespace");
    S(i_meth,"il2cpp_class_get_method_from_name");
    S(i_fld,"il2cpp_class_get_field_from_name");
    S(i_off,"il2cpp_field_get_offset");
    S(i_corlib,"il2cpp_get_corlib");            S(i_ocls,"il2cpp_object_get_class");
    S(i_str,"il2cpp_string_new");               S(i_parent,"il2cpp_class_get_parent");
    S(i_ctype,"il2cpp_class_get_type");         S(i_tobj,"il2cpp_type_get_object");
    #undef S
    return true;
}
// MethodInfo->methodPointer (offset 0) — goi thang, KHONG runtime_invoke
static inline void* mp(void* method){ return method ? *(void**)method : nil; }
static void* mOf(void* k,const char* n,int c){ return k? i_meth(k,n,c):nil; }
static size_t fOff(void* obj,const char* name){
    void* k=obj? i_ocls(obj):nil;
    void* f=k? i_fld(k,name):nil;
    return f? i_off(f):0;
}

// ================= CLASS/METHOD CACHE =================
static void *kGamePub,*kVehicleFast,*kExtraVelFast,*kExtraVelTrig,*kInputModule,
            *kRoadMap,*kMatchMgr,*kCryptoBase,*kExtraVelType;
static void *mGetInst,*mGetModByName,*mGetMyVehicle,*mForceEndDrift,*mFastOut,
            *mForceMini,*mAddEV,*mSetKey,*mGetKeyFlags,*mNearestTP,
            *mMatchCommon,*mGetCpReporter,*mSetEnable;
static bool g_clsOk=false;

static void scanClasses(void){
    if(g_clsOk) return;
    if(!g_domain) return;
    size_t n=0;
    const void** asms=i_asms(g_domain,&n);
    if(!asms||!n) return;
    for(size_t i=0;i<n;i++){
        void* img=i_img((void*)asms[i]); if(!img) continue;
        size_t cnt=i_cnt(img);
        for(size_t c=0;c<cnt;c++){
            void* k=i_cls(img,c); if(!k) continue;
            const char* ns=i_ns(k); const char* nm=i_name(k); if(!nm) continue;
            bool gb=!ns||!ns[0];
            #define T(cc,slot) if(cc && !slot) slot=k;
            T(gb&&!strcmp(nm,"GamePub"),kGamePub)
            T(gb&&!strcmp(nm,"VehicleFast"),kVehicleFast)
            T(gb&&!strcmp(nm,"ExtraVelocityFast"),kExtraVelFast)
            T(gb&&!strcmp(nm,"ExtraVelocityTriggerFast"),kExtraVelTrig)
            T(gb&&!strcmp(nm,"InputModule"),kInputModule)
            T(gb&&!strcmp(nm,"RoadMap"),kRoadMap)
            T(gb&&!strcmp(nm,"MatchMgr"),kMatchMgr)
            T(gb&&!strcmp(nm,"CryptoBase"),kCryptoBase)
            T(gb&&!strcmp(nm,"ExtraVelocityType"),kExtraVelType)
            #undef T
        }
        g_clsOk = kGamePub&&kVehicleFast&&kExtraVelTrig&&kInputModule&&kRoadMap;
        if(g_clsOk){ L("classes ok"); return; }
    }
    L("classes incomplete: pub=%p veh=%p trig=%p in=%p road=%p match=%p crypto=%p",
      kGamePub,kVehicleFast,kExtraVelTrig,kInputModule,kRoadMap,kMatchMgr,kCryptoBase);
}

static bool resolveMethods(void){
    if(!g_clsOk) return false;
    if(mGetInst) return true;
    mGetInst      = mOf(kGamePub,"GetInstance",0);
    mGetModByName = mOf(kGamePub,"GetModuleByName",2);
    mGetMyVehicle = mOf(kVehicleFast,"GetMyVehicle",0);
    mForceEndDrift= mOf(kVehicleFast,"ForceEndDrifting",1);
    mFastOut      = mOf(kVehicleFast,"DoFastOutCorners",1);
    mForceMini    = mOf(kExtraVelTrig,"ForceCanTriggerOncePassiveMini",1);
    mAddEV        = mOf(kExtraVelFast,"AddExtraVelocity",6);
    mSetKey       = mOf(kInputModule,"SetKey",2);
    mGetKeyFlags  = mOf(kInputModule,"get_KeyFlags",0);
    mNearestTP    = mOf(kRoadMap,"GetNearestTrackPoint",2);
    if(kMatchMgr) mMatchCommon = mOf(kMatchMgr,"get_MatchCommonComponent",0);
    L("methods: inst=%p veh=%p fed=%p mini=%p setkey=%p tp=%p mc=%p",
      mGetInst,mGetMyVehicle,mForceEndDrift,mForceMini,mSetKey,mNearestTP,mMatchCommon);
    return mGetInst&&mGetMyVehicle&&mForceEndDrift&&mSetKey;
}

// ================= ANTICHEAT qua il2cpp (khong patch) =================
// Tat bao cao checkpoint qua il2cpp (khong ghi code):
//   GamePub.GetInstance() -> GetModuleByName("MatchMgr") -> get_MatchCommonComponent()
//   -> GetCheckPointReportMgr() -> SetEnable(false)
static bool g_acDone=false;
static void disableAnticheat(void){
    if(g_acDone) return;
    if(!mp(mGetInst)||!mp(mGetModByName)||!mp(mMatchCommon)||!i_str){ return; }
    void* gp=((void*(*)(void))mp(mGetInst))();
    if(!gp) return;                                  // GamePub chua init -> thu lai tick sau
    void* mm=((void*(*)(void*,void*,void*))mp(mGetModByName))(gp,i_str("MatchMgr"),nil);
    if(!mm){ L("anticheat: MatchMgr chua co"); return; }
    void* mc=((void*(*)(void*))mp(mMatchCommon))(mm);
    if(!mc){ L("anticheat: MatchCommonComponent chua co"); return; }
    static void* mGetCp=nil,*mSetEn=nil;
    if(!mGetCp){
        void* k=i_ocls(mc);
        mGetCp=mOf(k,"GetCheckPointReportMgr",0);
        if(!mGetCp && i_parent){
            void* cur=k;
            for(int d=0;d<10 && !mGetCp;d++){
                cur=i_parent(cur);
                if(!cur) break;
                mGetCp=mOf(cur,"GetCheckPointReportMgr",0);
            }
        }
        if(!mGetCp){ L("anticheat: GetCheckPointReportMgr not found"); g_acDone=true; return; }
    }
    if(!mGetCp){ L("anticheat: GetCheckPointReportMgr not found"); g_acDone=true; return; }
    void* cp=((void*(*)(void*))mp(mGetCp))(mc);
    if(!cp){ L("anticheat: CheckPointReportMgr null"); g_acDone=true; return; }
    mSetEn=mOf(i_ocls(cp),"SetEnable",1);
    if(!mSetEn){ L("anticheat: SetEnable not found"); g_acDone=true; return; }
    ((void(*)(void*,bool))mp(mSetEn))(cp,false);
    L("anticheat: CheckPointReportMgr.SetEnable(false) OK");
    g_acDone=true;
}

// ================= GAME STATE =================
typedef struct { float x,y,z; } V3;

static void *g_veh=nil, *g_ecu=nil, *g_input=nil, *g_road=nil, *g_lastTP=nil;
static size_t off_mECU=0, off_mState=0, off_mTorque=0;
static double g_nextMini=0, g_nextEV=0;
static bool   g_prevDrift=false;
static int    g_failCount=0;

static bool tick(void){
    if(!g_ready||!resolveMethods()) return false;

    // --- my vehicle (goi thang methodPointer) ---
    g_veh = ((void*(*)(void))mp(mGetMyVehicle))();
    if(!g_veh){ g_ecu=nil; g_input=nil; g_road=nil; g_lastTP=nil; g_prevDrift=false; return false; }

    // --- InputModule / RoadMap: lay 1 lan ---
    if(!g_input||!g_road){
        void* gp=((void*(*)(void))mp(mGetInst))();
        if(gp){
            if(!g_input && i_str) g_input=((void*(*)(void*,void*,void*))mp(mGetModByName))(gp,i_str("InputModule"),nil);
            if(!g_road  && i_str) g_road =((void*(*)(void*,void*,void*))mp(mGetModByName))(gp,i_str("RoadMap"),nil);
        }
        if(!g_input) return false;
    }

    // --- ECU + offsets (cache) ---
    static void* mDV=nil;
    if(!off_mECU){
        if(!mDV){
            void* k=i_ocls(g_veh);
            mDV=mOf(k,"GetDynamicVehicle",0);
            if(!mDV && i_parent){
                void* cur=k;
                for(int d=0;d<10 && !mDV;d++){ cur=i_parent(cur); if(!cur) break; mDV=mOf(cur,"GetDynamicVehicle",0); }
            }
        }
        if(!mDV){ L("GetDynamicVehicle not found"); return false; }
        void* dv=((void*(*)(void*))mp(mDV))(g_veh);
        if(!dv) return false;
        off_mECU=fOff(dv,"mECU");
        if(!off_mECU) return false;
        g_ecu=*(void**)((char*)dv+off_mECU);
        if(!g_ecu) return false;
        off_mState =fOff(g_ecu,"mState");
        off_mTorque=fOff(g_ecu,"mEngineTorque");
        L("offsets: ecu=%zu state=%zu torque=%zu",off_mECU,off_mState,off_mTorque);
    } else if(!g_ecu && mDV){
        void* dv=((void*(*)(void*))mp(mDV))(g_veh);
        if(dv) g_ecu=*(void**)((char*)dv+off_mECU);
    }
    if(!g_ecu) return false;

    // --- state ---
    int vState = off_mState? *(int*)((char*)g_ecu+off_mState) : 0;

    // --- key flags ---
    int kf = mGetKeyFlags? ((int(*)(void*))mp(mGetKeyFlags))(g_input) : 0;
    bool driftKey=(kf>>8)&1;

    // --- accel an: chi ghi torque field, khong doi top speed ---
    if(g_accelOn && g_accelMult>1.001f && off_mTorque){
        float* t=(float*)((char*)g_ecu+off_mTorque);
        if(*t>0.0f) *t*=g_accelMult;
    }

    // --- tha nut drift -> ket thuc ngay ---
    if(g_prevDrift && !driftKey && vState==2){
        if(g_autoCutDrift && mp(mForceEndDrift)) ((void(*)(void*))mp(mForceEndDrift))(g_veh);
        if(g_autoFastOut && mp(mFastOut))        ((void(*)(void*))mp(mFastOut))(g_veh);
    }
    g_prevDrift=driftKey;

    double now=CACurrentMediaTime();

    // --- miniboost lien tuc khi drift ---
    if(vState==2 && g_contMini && mp(mForceMini) && now>=g_nextMini){
        ((void(*)(void*))mp(mForceMini))(g_veh);
        g_nextMini=now+g_miniInterval;
    }
    // --- boost them (ExtraVelocityType.Mini=1) ---
    if(g_extraKmph>0.5f && mp(mAddEV) && now>=g_nextEV){
        ((int(*)(void*,int,float,float,float,bool))mp(mAddEV))(g_veh,1,g_extraKmph,g_extraKmph*0.35f,g_extraDur,false);
        g_nextEV=now+1.0;
    }
    // --- steering assist ve track line ---
    if(g_steerAssist && mp(mNearestTP) && g_road && mp(mSetKey)){
        static void* mPos=nil,*mFwd=nil;
        if(!mPos){ void* k=i_ocls(g_veh); mPos=mOf(k,"get_Position",0); mFwd=mOf(k,"get_Forward",0); }
        if(mPos&&mFwd){
            V3 p=((V3(*)(void*))mp(mPos))(g_veh);
            V3 f=((V3(*)(void*))mp(mFwd))(g_veh);
            void* tp=((void*(*)(void*,float,float,float,float))mp(mNearestTP))(g_road,p.x,p.y,p.z,3.4e38f);
            if(tp){
                g_lastTP=tp;
                void* mDir=mOf(i_ocls(tp),"get_Direction",0);
                if(mDir){
                    V3 d=((V3(*)(void*))mp(mDir))(tp);
                    float cx=f.x*d.z-f.z*d.x;
                    float dot=f.x*d.x+f.z*d.z;
                    float deg=atan2f(cx,dot)*57.29578f;
                    if(g_steerInvert) deg=-deg;
                    float dead=30.0f-28.0f*g_steerStrength;
                    ((void(*)(void*,int,bool))mp(mSetKey))(g_input,1,deg<-dead);
                    ((void(*)(void*,int,bool))mp(mSetKey))(g_input,2,deg> dead);
                }
            } else g_lastTP=nil;
        }
    }
    return true;
}

// ================= UIKIT MENU =================
@interface ZSMRoot : UIWindow
@end
@interface ZSMUI : NSObject
@property(nonatomic,strong) ZSMRoot* win;
@property(nonatomic,strong) UIButton* fab;
@property(nonatomic,strong) UIView* panel;
@property(nonatomic,strong) UIScrollView* scroll;
@property(nonatomic) BOOL open;
@end

@implementation ZSMRoot
// chi nhan touch ben trong subview cua ta -> moi cho khac roi xuong game
- (UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e{
    UIView* v=[super hitTest:p withEvent:e];
    return (v==self)? nil : v;
}
@end

static ZSMUI* g_ui=nil;

@implementation ZSMUI

- (UILabel*)mkLabel:(NSString*)t y:(CGFloat)y size:(CGFloat)s color:(UIColor*)c {
    UILabel* l=[UILabel new];
    l.text=t; l.font=[UIFont boldSystemFontOfSize:s];
    l.textColor=c?:UIColor.whiteColor;
    l.frame=CGRectMake(12,y,self.scroll.bounds.size.width-24,20);
    l.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    return l;
}
- (UISwitch*)mkSwitch:(CGFloat)y get:(BOOL*)get {
    UISwitch* s=[UISwitch new];
    s.frame=CGRectMake(self.scroll.bounds.size.width-64,y-4,51,31);
    s.on=*get; s.tag=(NSInteger)get;
    s.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;
    [s addTarget:self action:@selector(swChanged:) forControlEvents:UIControlEventValueChanged];
    return s;
}
- (void)swChanged:(UISwitch*)s{ BOOL* p=(BOOL*)s.tag; if(p){ *p=s.on; cfgSave(); } }
- (UISlider*)mkSlider:(CGFloat)y min:(float)mn max:(float)mx get:(float*)get {
    UISlider* sl=[UISlider new];
    sl.frame=CGRectMake(12,y,self.scroll.bounds.size.width-24,28);
    sl.minimumValue=mn; sl.maximumValue=mx; sl.value=*get;
    sl.tag=(NSInteger)get;
    sl.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    [sl addTarget:self action:@selector(slChanged:) forControlEvents:UIControlEventValueChanged];
    return sl;
}
- (void)slChanged:(UISlider*)s{ float* p=(float*)s.tag; if(p){ *p=s.value; cfgSave(); } }

- (void)buildPanel:(CGRect)r {
    self.panel=[[UIView alloc] initWithFrame:r];
    self.panel.backgroundColor=[UIColor colorWithWhite:0.06 alpha:0.94];
    self.panel.layer.cornerRadius=14;
    self.panel.layer.borderWidth=1;
    self.panel.layer.borderColor=[UIColor colorWithWhite:0.35 alpha:1].CGColor;
    self.panel.autoresizingMask=UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleBottomMargin;
    self.panel.userInteractionEnabled=YES;   // panel nhan touch; ngoai panel hitTest tra nil -> game nhan

    UILabel* title=[UILabel new];
    title.text=@"  ZSM DRIFT MENU";
    title.font=[UIFont boldSystemFontOfSize:15];
    title.textColor=[UIColor colorWithRed:.3 green:.85 blue:1 alpha:1];
    title.frame=CGRectMake(0,0,r.size.width,40);
    [self.panel addSubview:title];

    self.scroll=[[UIScrollView alloc] initWithFrame:CGRectMake(0,44,r.size.width,r.size.height-52)];
    self.scroll.showsVerticalScrollIndicator=YES;
    [self.panel addSubview:self.scroll];

    CGFloat W=r.size.width, y=4;
    #define LABEL(t,c) { UILabel* l=[self mkLabel:(t) y:y size:12 color:(c)]; [self.scroll addSubview:l]; y+=18; }
    #define SWITCH(t,var) { UILabel* l=[self mkLabel:(t) y:y size:13 color:UIColor.whiteColor]; [self.scroll addSubview:l]; \
                            UISwitch* s=[self mkSwitch:y get:&var]; [self.scroll addSubview:s]; y+=38; }
    #define SLIDER(t,var,mn,mx) { UILabel* l=[self mkLabel:(t) y:y size:12 color:UIColor.lightGrayColor]; [self.scroll addSubview:l]; y+=18; \
                            UISlider* s=[self mkSlider:y min:(mn) max:(mx) get:&var]; [self.scroll addSubview:s]; y+=34; }

    LABEL(@"== GIA TOC AN ==", [UIColor colorWithRed:.3 green:.85 blue:1 alpha:1])
    SWITCH(@"Bat gia toc (torque)", g_accelOn)
    SLIDER(@"Luc day", g_accelMult, 1.0f, 2.5f)
    y+=6;
    LABEL(@"== DRIFT ==", [UIColor colorWithRed:.3 green:.85 blue:1 alpha:1])
    SWITCH(@"Tu ngat khi tha nut", g_autoCutDrift)
    SWITCH(@"Fast-out khi tha", g_autoFastOut)
    y+=6;
    LABEL(@"== MINI BOOST ==", [UIColor colorWithRed:.3 green:.85 blue:1 alpha:1])
    SWITCH(@"Lien tuc + miniboost", g_contMini)
    SLIDER(@"Chu ky (giay)", g_miniInterval, 0.2f, 3.0f)
    SLIDER(@"Boost them km/h", g_extraKmph, 0.0f, 80.0f)
    SLIDER(@"Thoi luong (giay)", g_extraDur, 0.3f, 3.0f)
    y+=6;
    LABEL(@"== LAI TU DONG ==", [UIColor colorWithRed:.3 green:.85 blue:1 alpha:1])
    SWITCH(@"Bam track line", g_steerAssist)
    SLIDER(@"Do manh lai", g_steerStrength, 0.0f, 1.0f)
    SWITCH(@"Dao chieu", g_steerInvert)
    y+=6;
    LABEL(@"== ANTICHEAT ==", [UIColor colorWithRed:.3 green:.85 blue:1 alpha:1])
    LABEL(@"CrackHandler + CheckPoint da tat qua il2cpp", UIColor.lightGrayColor)
    #undef LABEL
    #undef SWITCH
    #undef SLIDER

    self.scroll.contentSize=CGSizeMake(W,y+10);
}

- (void)onFab {
    self.open=!self.open;
    [UIView animateWithDuration:0.2 animations:^{
        self.panel.alpha=self.open?1:0;
        self.panel.transform=self.open?CGAffineTransformIdentity:CGAffineTransformMakeScale(0.9,0.9);
    }];
    if(self.open) self.panel.hidden=NO;
    else dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(!self.open) self.panel.hidden=YES;
    });
}

- (void)onRotate {
    CGRect b=[UIScreen mainScreen].bounds;
    self.win.frame=b;
    self.fab.frame=CGRectMake(6,b.size.height*0.42,64,44);
    self.panel.frame=CGRectMake(MAX(70.0,b.size.width*0.5-150),90,300,MIN(b.size.height-160,560));
    self.scroll.frame=CGRectMake(0,44,self.panel.bounds.size.width,self.panel.bounds.size.height-52);
    L("rotate -> %.0fx%.0f",b.size.width,b.size.height);
}
- (void)attach {
    CGFloat sw=[UIScreen mainScreen].bounds.size.width;
    CGFloat sh=[UIScreen mainScreen].bounds.size.height;
    self.win=[[ZSMRoot alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.win.windowLevel=UIWindowLevelAlert-1;      // duoi alert, tren game
    self.win.backgroundColor=UIColor.clearColor;
    UIViewController* vc=[UIViewController new];
    vc.view.backgroundColor=UIColor.clearColor;
    self.win.rootViewController=vc;
    self.win.hidden=NO;

    self.fab=[UIButton buttonWithType:UIButtonTypeSystem];
    self.fab.frame=CGRectMake(6,sh*0.42,64,44);
    [self.fab setTitle:@"ZSM" forState:UIControlStateNormal];
    [self.fab setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.fab.titleLabel.font=[UIFont boldSystemFontOfSize:14];
    self.fab.backgroundColor=[UIColor colorWithRed:.1 green:.5 blue:.9 alpha:0.9];
    self.fab.layer.cornerRadius=10;
    [self.fab addTarget:self action:@selector(onFab) forControlEvents:UIControlEventTouchUpInside];
    [self.win addSubview:self.fab];

    CGRect pr=CGRectMake(sw*0.5-150, 90, 300, MIN(sh-160, 560));
    if(pr.origin.x<70) pr.origin.x=70;
    [self buildPanel:pr];
    self.panel.alpha=0; self.panel.hidden=YES;
    [self.win addSubview:self.panel];
    // theo doi xoay man hinh: anchor lai fab + panel
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onRotate)
                                                 name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    L("menu attached (fab %.0f,%.0f)",self.fab.frame.origin.x,self.fab.frame.origin.y);
}
@end

// ================= DRIVER =================
@interface ZSMDriver : NSObject
- (void)tick:(CADisplayLink*)dl;
@end
@implementation ZSMDriver
- (void)tick:(CADisplayLink*)dl{
    (void)dl;
    @try{
        if(!g_ready){
            if(!loadSyms()) return;
            g_domain=i_domain();
            if(!g_domain) return;
            i_attach(g_domain);
            g_ready=true;
            L("il2cpp attached domain=%p",g_domain);
        }
        if(!g_clsOk) scanClasses();
        if(!g_clsOk) return;
        if(!resolveMethods()) return;
        if(!g_ui){ g_ui=[ZSMUI new]; [g_ui attach]; }
        disableAnticheat();
        tick();
    }@catch(NSException*e){
        static int n=0; if(n++<3) L("tick exc: %s",e.name.UTF8String);
    }
}
@end
static ZSMDriver* g_drv=nil;

__attribute__((constructor))
static void zsmInit(void){
    cfgLoad();
    logInit();
    L("ctor v3.0");
    dispatch_async(dispatch_get_main_queue(),^{
        g_drv=[ZSMDriver new];
        CADisplayLink* l=[CADisplayLink displayLinkWithTarget:g_drv selector:@selector(tick:)];
        l.preferredFramesPerSecond=30;
        [l addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        L("driver started");
    });
}
