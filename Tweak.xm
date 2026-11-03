// Tweak.xm — Prophet Auto Summon Menu (Siêu Tốc)
//
// Tính năng:
// 1. Nút tròn nổi (Floating Button) di chuyển tự do, chạm để bật/tắt menu.
// 2. Chọn Faction: AGI, VIT, STR, DEX, DARK, LIGHT.
// 3. Tùy chỉnh Delay (giây) tự do bằng ô nhập số.
// 4. Tùy chỉnh Số call mỗi lần gọi (Burst summon: 1, 2, 5, 10, ...).
// 5. Nút Bắt đầu / Ngưng: gọi trực tiếp DataSender.HeroProphetSummon siêu tốc.
// 6. Bộ đếm thời gian thực: Đã dùng X thùng (mỗi lần gọi +10 quả cầu).
// 7. Tự động chặn và đóng sạch toàn bộ popup thưởng (PopupShowBonusEffect & 2).

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

#pragma mark - RVAs in UnityFramework (arm64, imagebase 0)

#define OFF_GAME_CONTEXT_GET_INSTANCE   0x14473AC  // GameContext.GetInstance()
#define OFF_HERO_PROPHET_SUMMON         0x140437C  // DataSender.HeroProphetSummon(this, faction, count)
#define OFF_POPUP1_SET_MODEL            0x11C23A0  // PopupShowBonusEffect.SetBonusModel(BonusModel)
#define OFF_POPUP1_CLOSE_CLICK          0x11C2D54  // PopupShowBonusEffect.ButtonCloseClick()
#define OFF_POPUP2_SET_MODEL            0x11C36D4  // PopupShowBonusEffect2.SetBonusModel(BonusModel)
#define OFF_POPUP2_CLOSE_CLICK          0x11C3DC4  // PopupShowBonusEffect2.ButtonCloseClick()

#pragma mark - Faction Enums (HeroFaction)

typedef NS_ENUM(NSInteger, HeroFactionEnum) {
    FACTION_DARK     = 1, // Bóng Đêm (Ám)
    FACTION_LIGHT    = 2, // Ánh Sáng (Quang)
    FACTION_DEX      = 3, // Shadow (U Ám / Khéo)
    FACTION_AGI      = 4, // Fortress (Thành Trì / Tốc)
    FACTION_VIT      = 5, // Forest (Rừng Xanh / Thủ)
    FACTION_STR      = 6, // Abyss (Vực Sâu / Công)
};

static uintptr_t gBase = 0;
static BOOL      gIsAutoSummoning = NO;

#pragma mark - Passthrough Window (Không chặn touch game bên dưới)

@interface PassthroughWindow : UIWindow
@end

@implementation PassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) {
        return nil; // Cho phép click xuyên vào game
    }
    return hit;
}
@end

#pragma mark - Menu Controller

@interface AutoSummonMenuController : UIViewController <UITextFieldDelegate>
@property (nonatomic, strong) UIButton    *floatingBtn;
@property (nonatomic, strong) UIView      *menuView;

// Faction
@property (nonatomic, assign) HeroFactionEnum selectedFaction;
@property (nonatomic, strong) NSMutableArray<UIButton *> *factionButtons;

// Settings
@property (nonatomic, strong) UITextField *delayField;
@property (nonatomic, strong) UITextField *burstField;
@property (nonatomic, assign) NSTimeInterval summonDelay;
@property (nonatomic, assign) NSInteger    callsPerBurst;

// Stats
@property (nonatomic, strong) UILabel     *counterLabel;
@property (nonatomic, assign) NSInteger    summonBoxCount;
@property (nonatomic, assign) NSInteger    summonOrbCount;

// Action
@property (nonatomic, strong) UIButton    *startBtn;
@property (nonatomic, strong) NSTimer     *summonTimer;
@end

@implementation AutoSummonMenuController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    self.selectedFaction = FACTION_STR; // Mặc định STR
    self.summonDelay     = 0.35;        // Mặc định 0.35s
    self.callsPerBurst   = 1;           // Mặc định 1 call / nhịp
    self.factionButtons  = [NSMutableArray new];

    [self setupFloatingButton];
    [self setupMenuUI];
}

#pragma mark - Floating Button

- (void)setupFloatingButton {
    self.floatingBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatingBtn.frame = CGRectMake(16, 70, 50, 50);
    self.floatingBtn.layer.cornerRadius = 25;
    self.floatingBtn.layer.masksToBounds = NO;
    self.floatingBtn.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.18 alpha:0.92];
    self.floatingBtn.layer.borderColor = [UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:0.9].CGColor;
    self.floatingBtn.layer.borderWidth = 1.8;

    self.floatingBtn.layer.shadowColor = [UIColor cyanColor].CGColor;
    self.floatingBtn.layer.shadowOffset = CGSizeMake(0, 0);
    self.floatingBtn.layer.shadowOpacity = 0.6;
    self.floatingBtn.layer.shadowRadius = 8;

    [self.floatingBtn setTitle:@"⚡" forState:UIControlStateNormal];
    self.floatingBtn.titleLabel.font = [UIFont systemFontOfSize:24];

    [self.floatingBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.floatingBtn addGestureRecognizer:pan];

    [self.view addSubview:self.floatingBtn];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint trans = [pan translationInView:self.view];
    CGPoint center = self.floatingBtn.center;
    center.x += trans.x;
    center.y += trans.y;

    CGSize scr = [UIScreen mainScreen].bounds.size;
    CGFloat r = self.floatingBtn.bounds.size.width / 2.0;
    center.x = MAX(r + 4, MIN(scr.width - r - 4, center.x));
    center.y = MAX(r + 10, MIN(scr.height - r - 10, center.y));

    self.floatingBtn.center = center;
    [pan setTranslation:CGPointZero inView:self.view];

    if (pan.state == UIGestureRecognizerStateEnded) {
        [UIView animateWithDuration:0.2 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:0 animations:^{
            CGPoint snap = self.floatingBtn.center;
            if (snap.x < scr.width / 2.0) {
                snap.x = r + 8;
            } else {
                snap.x = scr.width - r - 8;
            }
            self.floatingBtn.center = snap;
        } completion:nil];
    }
}

- (void)toggleMenu {
    BOOL willShow = self.menuView.hidden;
    if (willShow) {
        self.menuView.transform = CGAffineTransformMakeScale(0.88, 0.88);
        self.menuView.alpha = 0.0;
        self.menuView.hidden = NO;
        [UIView animateWithDuration:0.2 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
            self.menuView.transform = CGAffineTransformIdentity;
            self.menuView.alpha = 1.0;
        } completion:nil];
    } else {
        [self.view endEditing:YES];
        [UIView animateWithDuration:0.16 animations:^{
            self.menuView.transform = CGAffineTransformMakeScale(0.88, 0.88);
            self.menuView.alpha = 0.0;
        } completion:^(BOOL finished) {
            self.menuView.hidden = YES;
            self.menuView.transform = CGAffineTransformIdentity;
        }];
    }
}

#pragma mark - Menu UI (Gọn gàng, vừa khít mọi màn hình)

- (void)setupMenuUI {
    CGSize scr = [UIScreen mainScreen].bounds.size;
    CGFloat scrW = MAX(scr.width, scr.height);
    CGFloat scrH = MIN(scr.width, scr.height);

    CGFloat w = 336;
    CGFloat h = 266;

    self.menuView = [[UIView alloc] initWithFrame:CGRectMake((scrW - w) / 2.0, (scrH - h) / 2.0, w, h)];
    self.menuView.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.12 alpha:0.96];
    self.menuView.layer.cornerRadius = 14;
    self.menuView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:0.85].CGColor;
    self.menuView.layer.borderWidth = 1.5;
    self.menuView.layer.masksToBounds = YES;
    self.menuView.hidden = YES;

    // 1. Top Bar
    UIView *topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 34)];
    topBar.backgroundColor = [UIColor colorWithRed:0.11 green:0.11 blue:0.19 alpha:0.95];

    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, w - 46, 34)];
    titleLbl.text = @"⚡ PROPHET AUTO SUMMON";
    titleLbl.font = [UIFont boldSystemFontOfSize:13];
    titleLbl.textColor = [UIColor whiteColor];
    [topBar addSubview:titleLbl];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w - 36, 0, 36, 34);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    closeBtn.tintColor = [UIColor lightGrayColor];
    [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:closeBtn];

    [self.menuView addSubview:topBar];

    // 2. Faction Selection (2 dòng x 3 cột)
    UILabel *facTitleLbl = [[UILabel alloc] initWithFrame:CGRectMake(12, 38, w - 24, 16)];
    facTitleLbl.text = @"HỆ CHIÊU MỘ:";
    facTitleLbl.font = [UIFont boldSystemFontOfSize:10];
    facTitleLbl.textColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.95 alpha:1.0];
    [self.menuView addSubview:facTitleLbl];

    NSArray *factions = @[
        @{@"name": @"AGI",   @"desc": @"Tốc",   @"tag": @(FACTION_AGI)},
        @{@"name": @"VIT",   @"desc": @"Thủ",   @"tag": @(FACTION_VIT)},
        @{@"name": @"STR",   @"desc": @"Công",  @"tag": @(FACTION_STR)},
        @{@"name": @"DEX",   @"desc": @"Khéo",  @"tag": @(FACTION_DEX)},
        @{@"name": @"DARK",  @"desc": @"Ám",    @"tag": @(FACTION_DARK)},
        @{@"name": @"LIGHT", @"desc": @"Quang", @"tag": @(FACTION_LIGHT)},
    ];

    CGFloat btnW = (w - 24 - 12) / 3.0;
    CGFloat btnH = 26;
    for (int i = 0; i < factions.count; i++) {
        NSDictionary *d = factions[i];
        int row = i / 3;
        int col = i % 3;
        CGFloat x = 12 + col * (btnW + 6);
        CGFloat y = 56 + row * (btnH + 4);

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(x, y, btnW, btnH);
        btn.layer.cornerRadius = 6;
        btn.layer.borderWidth = 1.0;
        btn.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
        btn.backgroundColor = [UIColor colorWithWhite:0.13 alpha:0.9];
        btn.tag = [d[@"tag"] integerValue];

        NSString *title = [NSString stringWithFormat:@"%@ (%@)", d[@"name"], d[@"desc"]];
        [btn setTitle:title forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:10];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

        [btn addTarget:self action:@selector(onFactionBtnClicked:) forControlEvents:UIControlEventTouchUpInside];
        [self.menuView addSubview:btn];
        [self.factionButtons addObject:btn];
    }
    [self updateFactionButtonsState];

    // 3. Settings: Delay & Số Call mỗi lần gọi (Ngang hàng)
    CGFloat setY = 56 + 2 * (btnH + 4) + 6; // ~122
    CGFloat halfW = (w - 24 - 8) / 2.0;

    // Box Delay bên trái
    UIView *delayBox = [[UIView alloc] initWithFrame:CGRectMake(12, setY, halfW, 30)];
    delayBox.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    delayBox.layer.cornerRadius = 6;
    delayBox.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    delayBox.layer.borderWidth = 0.8;

    UILabel *dLbl = [[UILabel alloc] initWithFrame:CGRectMake(6, 5, 46, 20)];
    dLbl.text = @"Delay:";
    dLbl.font = [UIFont boldSystemFontOfSize:10];
    dLbl.textColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.95 alpha:1.0];
    [delayBox addSubview:dLbl];

    self.delayField = [[UITextField alloc] initWithFrame:CGRectMake(54, 3, 56, 24)];
    self.delayField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    self.delayField.layer.cornerRadius = 4;
    self.delayField.textColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.2 alpha:1.0];
    self.delayField.font = [UIFont boldSystemFontOfSize:11];
    self.delayField.textAlignment = NSTextAlignmentCenter;
    self.delayField.keyboardType = UIKeyboardTypeDecimalPad;
    self.delayField.text = @"0.35";
    self.delayField.delegate = self;
    [self.delayField addTarget:self action:@selector(onDelayFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [self attachDoneToolbarToField:self.delayField];
    [delayBox addSubview:self.delayField];

    UILabel *dUnit = [[UILabel alloc] initWithFrame:CGRectMake(114, 5, 30, 20)];
    dUnit.text = @"giây";
    dUnit.font = [UIFont systemFontOfSize:9];
    dUnit.textColor = [UIColor lightGrayColor];
    [delayBox addSubview:dUnit];

    [self.menuView addSubview:delayBox];

    // Box Số Call bên phải
    UIView *burstBox = [[UIView alloc] initWithFrame:CGRectMake(12 + halfW + 8, setY, halfW, 30)];
    burstBox.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    burstBox.layer.cornerRadius = 6;
    burstBox.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    burstBox.layer.borderWidth = 0.8;

    UILabel *bLbl = [[UILabel alloc] initWithFrame:CGRectMake(6, 5, 48, 20)];
    bLbl.text = @"Số call:";
    bLbl.font = [UIFont boldSystemFontOfSize:10];
    bLbl.textColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.95 alpha:1.0];
    [burstBox addSubview:bLbl];

    self.burstField = [[UITextField alloc] initWithFrame:CGRectMake(56, 3, 48, 24)];
    self.burstField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    self.burstField.layer.cornerRadius = 4;
    self.burstField.textColor = [UIColor colorWithRed:0.3 green:1.0 blue:0.6 alpha:1.0];
    self.burstField.font = [UIFont boldSystemFontOfSize:11];
    self.burstField.textAlignment = NSTextAlignmentCenter;
    self.burstField.keyboardType = UIKeyboardTypeNumberPad;
    self.burstField.text = @"1";
    self.burstField.delegate = self;
    [self.burstField addTarget:self action:@selector(onBurstFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [self attachDoneToolbarToField:self.burstField];
    [burstBox addSubview:self.burstField];

    UILabel *bUnit = [[UILabel alloc] initWithFrame:CGRectMake(108, 5, 36, 20)];
    bUnit.text = @"lần/nhịp";
    bUnit.font = [UIFont systemFontOfSize:9];
    bUnit.textColor = [UIColor lightGrayColor];
    [burstBox addSubview:bUnit];

    [self.menuView addSubview:burstBox];

    // 4. Live Counter Box (Mỗi lần gọi +10 quả cầu)
    CGFloat countY = setY + 30 + 8; // ~160
    UIView *countBox = [[UIView alloc] initWithFrame:CGRectMake(12, countY, w - 24, 44)];
    countBox.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.08 alpha:0.95];
    countBox.layer.cornerRadius = 8;
    countBox.layer.borderColor = [UIColor colorWithRed:0.0 green:0.75 blue:0.6 alpha:0.7].CGColor;
    countBox.layer.borderWidth = 1.0;

    self.counterLabel = [[UILabel alloc] initWithFrame:CGRectMake(6, 4, countBox.bounds.size.width - 12, 22)];
    self.counterLabel.text = @"ĐÃ DÙNG: 0 thùng (0 quả cầu)";
    self.counterLabel.font = [UIFont boldSystemFontOfSize:13];
    self.counterLabel.textColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.6 alpha:1.0];
    self.counterLabel.textAlignment = NSTextAlignmentCenter;
    [countBox addSubview:self.counterLabel];

    UILabel *subCountLbl = [[UILabel alloc] initWithFrame:CGRectMake(6, 24, countBox.bounds.size.width - 12, 16)];
    subCountLbl.text = @"(1 thùng = 10 quả cầu • Đã tự động chặn popup)";
    subCountLbl.font = [UIFont systemFontOfSize:9];
    subCountLbl.textColor = [UIColor lightGrayColor];
    subCountLbl.textAlignment = NSTextAlignmentCenter;
    [countBox addSubview:subCountLbl];

    [self.menuView addSubview:countBox];

    // 5. Nút BẮT ĐẦU / NGƯNG & ĐẶT LẠI
    CGFloat actY = countY + 44 + 8; // ~212
    self.startBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.startBtn.frame = CGRectMake(12, actY, w - 24 - 88, 38);
    self.startBtn.layer.cornerRadius = 9;
    self.startBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.72 blue:0.58 alpha:1.0];
    [self.startBtn setTitle:@"BẮT ĐẦU" forState:UIControlStateNormal];
    self.startBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.startBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.startBtn addTarget:self action:@selector(onStartToggle) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:self.startBtn];

    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    resetBtn.frame = CGRectMake(w - 12 - 80, actY, 80, 38);
    resetBtn.layer.cornerRadius = 9;
    resetBtn.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    resetBtn.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1.0].CGColor;
    resetBtn.layer.borderWidth = 0.8;
    [resetBtn setTitle:@"Đặt lại" forState:UIControlStateNormal];
    resetBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [resetBtn setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    [resetBtn addTarget:self action:@selector(onResetCount) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:resetBtn];

    [self.view addSubview:self.menuView];
}

- (void)attachDoneToolbarToField:(UITextField *)tf {
    UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 36)];
    bar.barStyle = UIBarStyleBlack;
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:@"Xong" style:UIBarButtonItemStyleDone target:tf action:@selector(resignFirstResponder)];
    done.tintColor = [UIColor cyanColor];
    bar.items = @[flex, done];
    tf.inputAccessoryView = bar;
}

#pragma mark - Faction & Settings Handlers

- (void)onFactionBtnClicked:(UIButton *)btn {
    self.selectedFaction = (HeroFactionEnum)btn.tag;
    [self updateFactionButtonsState];
}

- (void)updateFactionButtonsState {
    for (UIButton *b in self.factionButtons) {
        if (b.tag == self.selectedFaction) {
            b.layer.borderColor = [UIColor cyanColor].CGColor;
            b.layer.borderWidth = 1.8;
            b.backgroundColor = [UIColor colorWithRed:0.2 green:0.3 blue:0.55 alpha:1.0];
        } else {
            b.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
            b.layer.borderWidth = 1.0;
            b.backgroundColor = [UIColor colorWithWhite:0.13 alpha:0.9];
        }
    }
}

- (void)onDelayFieldChanged:(UITextField *)tf {
    NSString *clean = [tf.text stringByReplacingOccurrencesOfString:@"," withString:@"."];
    double val = [clean doubleValue];
    if (val >= 0.01 && val <= 60.0) {
        self.summonDelay = val;
        [self restartTimerIfRunning];
    }
}

- (void)onBurstFieldChanged:(UITextField *)tf {
    NSInteger val = [tf.text integerValue];
    if (val >= 1 && val <= 100) {
        self.callsPerBurst = val;
    }
}

- (void)onResetCount {
    self.summonBoxCount = 0;
    self.summonOrbCount = 0;
    self.counterLabel.text = @"ĐÃ DÙNG: 0 thùng (0 quả cầu)";
}

- (void)restartTimerIfRunning {
    if (gIsAutoSummoning && self.summonTimer) {
        [self.summonTimer invalidate];
        self.summonTimer = [NSTimer scheduledTimerWithTimeInterval:self.summonDelay
                                                            target:self
                                                          selector:@selector(onSummonTimerTick)
                                                          userInfo:nil
                                                           repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.summonTimer forMode:NSRunLoopCommonModes];
    }
}

#pragma mark - Start / Stop Summon Loop (Call DataSender trực tiếp)

- (void)onStartToggle {
    if (!gIsAutoSummoning) {
        // Đồng bộ lại cài đặt từ ô nhập số
        NSString *clean = [self.delayField.text stringByReplacingOccurrencesOfString:@"," withString:@"."];
        double dVal = [clean doubleValue];
        self.summonDelay = (dVal >= 0.01 && dVal <= 60.0) ? dVal : 0.35;

        NSInteger bVal = [self.burstField.text integerValue];
        self.callsPerBurst = (bVal >= 1 && bVal <= 100) ? bVal : 1;

        [self.view endEditing:YES];

        gIsAutoSummoning = YES;
        [self.startBtn setTitle:@"NGƯNG" forState:UIControlStateNormal];
        self.startBtn.backgroundColor = [UIColor colorWithRed:0.85 green:0.2 blue:0.2 alpha:1.0];

        self.summonTimer = [NSTimer scheduledTimerWithTimeInterval:self.summonDelay
                                                            target:self
                                                          selector:@selector(onSummonTimerTick)
                                                          userInfo:nil
                                                           repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.summonTimer forMode:NSRunLoopCommonModes];
    } else {
        gIsAutoSummoning = NO;
        [self.summonTimer invalidate];
        self.summonTimer = nil;
        [self.startBtn setTitle:@"BẮT ĐẦU" forState:UIControlStateNormal];
        self.startBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.72 blue:0.58 alpha:1.0];
    }
}

- (void)onSummonTimerTick {
    if (!gIsAutoSummoning || !gBase) return;

    // 1. Lấy GameContext.GetInstance() @ 0x14473AC
    typedef void *(*GC_GetInstance_t)(void);
    GC_GetInstance_t getGC = (GC_GetInstance_t)(gBase + OFF_GAME_CONTEXT_GET_INSTANCE);
    void *gc = getGC ? getGC() : NULL;
    if (!gc || (uintptr_t)gc < 0x100000000ULL) return;

    // 2. dataSender ở offset 0x1A0 (416 decimal)
    void *dataSender = *(void **)((uint8_t *)gc + 0x1A0);
    if (!dataSender || (uintptr_t)dataSender < 0x100000000ULL) return;

    // 3. Gọi DataSender.HeroProphetSummon siêu tốc @ 0x140437C
    typedef void (*Summon_t)(void *, int, int);
    Summon_t summon = (Summon_t)(gBase + OFF_HERO_PROPHET_SUMMON);
    if (!summon) return;

    NSInteger burst = (self.callsPerBurst >= 1) ? self.callsPerBurst : 1;
    int faction = (int)self.selectedFaction;

    for (NSInteger i = 0; i < burst; i++) {
        summon(dataSender, faction, 10);
        self.summonBoxCount += 1;
        self.summonOrbCount += 10;
    }

    self.counterLabel.text = [NSString stringWithFormat:@"ĐÃ DÙNG: %ld thùng (%ld quả cầu)",
                              (long)self.summonBoxCount, (long)self.summonOrbCount];
}

@end

#pragma mark - Tự động chặn & đóng sạch Popup thưởng (Popup 1 & 2)

static void (*orig_Popup1_SetBonusModel)(void *, void *) = NULL;
static void Hook_Popup1_SetBonusModel(void *self, void *bonusModel) {
    if (gIsAutoSummoning && gBase) {
        typedef void (*CloseClick_t)(void *);
        CloseClick_t closeClick = (CloseClick_t)(gBase + OFF_POPUP1_CLOSE_CLICK);
        if (closeClick && self) {
            closeClick(self);
            return; // Chặn đứng popup 1
        }
    }
    if (orig_Popup1_SetBonusModel) orig_Popup1_SetBonusModel(self, bonusModel);
}

static void (*orig_Popup2_SetBonusModel)(void *, void *) = NULL;
static void Hook_Popup2_SetBonusModel(void *self, void *bonusModel) {
    if (gIsAutoSummoning && gBase) {
        typedef void (*CloseClick_t)(void *);
        CloseClick_t closeClick = (CloseClick_t)(gBase + OFF_POPUP2_CLOSE_CLICK);
        if (closeClick && self) {
            closeClick(self);
            return; // Chặn đứng popup 2
        }
    }
    if (orig_Popup2_SetBonusModel) orig_Popup2_SetBonusModel(self, bonusModel);
}

#pragma mark - UI Setup & Bootstrap

static PassthroughWindow *gOverlayWindow = nil;

static void SetupOverlayUI(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            CGRect bounds = [UIScreen mainScreen].bounds;
            if (@available(iOS 13.0, *)) {
                UIWindowScene *scene = nil;
                for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                    if (s.activationState == UISceneActivationStateForegroundActive && [s isKindOfClass:[UIWindowScene class]]) {
                        scene = (UIWindowScene *)s;
                        break;
                    }
                }
                if (scene) {
                    gOverlayWindow = [[PassthroughWindow alloc] initWithWindowScene:scene];
                } else {
                    gOverlayWindow = [[PassthroughWindow alloc] initWithFrame:bounds];
                }
            } else {
                gOverlayWindow = [[PassthroughWindow alloc] initWithFrame:bounds];
            }

            gOverlayWindow.windowLevel = UIWindowLevelAlert + 100.0;
            gOverlayWindow.backgroundColor = [UIColor clearColor];

            AutoSummonMenuController *ctrl = [AutoSummonMenuController new];
            gOverlayWindow.rootViewController = ctrl;
            gOverlayWindow.hidden = NO;
        });
    });
}

static void InstallIl2CppHooks(uintptr_t base) {
    static BOOL done = NO;
    if (done || !base) return;
    done = YES;
    gBase = base;

    // Chặn Popup 1
    MSHookFunction((void *)(base + OFF_POPUP1_SET_MODEL),
                   (void *)&Hook_Popup1_SetBonusModel,
                   (void **)&orig_Popup1_SetBonusModel);

    // Chặn Popup 2
    MSHookFunction((void *)(base + OFF_POPUP2_SET_MODEL),
                   (void *)&Hook_Popup2_SetBonusModel,
                   (void **)&orig_Popup2_SetBonusModel);
}

static void OnImageAdded(const struct mach_header *mh, intptr_t vmaddr_slide) {
    Dl_info info;
    if (dladdr(mh, &info) && info.dli_fname) {
        if (strstr(info.dli_fname, "UnityFramework")) {
            InstallIl2CppHooks((uintptr_t)mh);
        }
    }
}

#pragma mark - Constructor

__attribute__((constructor))
static void InitAutoSummon(void) {
    @autoreleasepool {
        _dyld_register_func_for_add_image(OnImageAdded);

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            SetupOverlayUI();
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SetupOverlayUI();
        });
    }
}
