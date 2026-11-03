// Tweak.xm — Chiêu Mộ Đặc Biệt (Prophet Summon) & Extra Tướng SS
//
// Bản cập nhật mới:
// 1. Menu thu nhỏ tối ưu Landscape (490 x 310) vừa vặn trên mọi màn hình iPhone/iPad.
// 2. Tab Chiêu Mộ chia 2 cột ngang + bọc trong UIScrollView -> Nút BẮT ĐẦU luôn nằm ngay trước mắt, không bị khuất, lướt mượt mà.
// 3. Tab Extra thêm thanh lọc hệ (ALL, AGI, VIT, STR, DEX, DARK, LIGHT).
// 4. Tên nhân vật/tướng dùng I2LanguagesHelper.GetTranslation (0x105A738) để lấy TÊN THẬT INGAME (tiếng Việt), không hiện code name kỹ thuật.

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
#define OFF_DB_MANAGER_GET_INSTANCE     0x140C030  // DbManager.GetInstance()
#define OFF_DB_MANAGER_GET_HERO_MODEL   0x140C0BC  // DbManager.GetHeroModel(heroKey)
#define OFF_POPUP_BONUS_SET_MODEL       0x11C36D4  // PopupShowBonusEffect2.SetBonusModel(BonusModel)
#define OFF_POPUP_BONUS_CLOSE_CLICK     0x11C3DC4  // PopupShowBonusEffect2.ButtonCloseClick()
#define OFF_I2_GET_TRANSLATION          0x105A738  // I2LanguagesHelper.GetTranslation(i2Key)

#pragma mark - Faction Enums (Full 6 hệ trong HeroFaction)

typedef NS_ENUM(NSInteger, HeroFactionEnum) {
    FACTION_DARK     = 1, // Dark (Bóng Đêm / Ám)
    FACTION_LIGHT    = 2, // Light (Ánh Sáng / Quang)
    FACTION_DEX      = 3, // Shadow (U Ám / Khéo / Tím)
    FACTION_AGI      = 4, // Fortress (Thành Trì / Tốc / Xanh biển)
    FACTION_VIT      = 5, // Forest (Rừng Xanh / Thủ / Lục)
    FACTION_STR      = 6, // Abyss (Vực Sâu / Công / Đỏ)
};

#pragma mark - il2cpp ABI

typedef struct { void *klass; void *monitor; void *bounds; uintptr_t max_length; } Il2CppArrayHdr;
typedef struct { void *klass; void *monitor; int32_t length; uint16_t chars[]; } Il2CppStringHdr;
typedef struct { void *klass; void *monitor; void *items; int32_t size; int32_t version; } Il2CppListHdr;

static inline BOOL IsValidPtr(const void *p) {
    return p != NULL && ((uintptr_t)p >= 0x100000000ULL);
}

static inline int32_t ILListSize(void *list) {
    if (!IsValidPtr(list)) return 0;
    Il2CppListHdr *l = (Il2CppListHdr *)list;
    int32_t sz = l->size;
    return (sz > 0 && sz < 100000) ? sz : 0;
}

static inline void *ILListAt(void *list, int32_t i) {
    if (!IsValidPtr(list) || i < 0) return NULL;
    Il2CppListHdr *l = (Il2CppListHdr *)list;
    if (!IsValidPtr(l->items) || i >= l->size) return NULL;
    return *(void **)((uint8_t *)l->items + 0x20 + (size_t)8 * (size_t)i);
}

static NSString *ILStr(void *s) {
    if (!IsValidPtr(s)) return nil;
    Il2CppStringHdr *h = (Il2CppStringHdr *)s;
    int32_t len = h->length;
    if (len <= 0 || len > 200000) return nil;
    return [[NSString alloc] initWithCharacters:h->chars length:(NSUInteger)len];
}

#pragma mark - Forward Declarations

static uintptr_t gBase = 0;
static BOOL      gIsAutoSummoning = NO;

@class FloatingMenuController;
static FloatingMenuController *gMenuCtrl = nil;

#pragma mark - Model for Hero Item

@interface HeroItem : NSObject
@property (nonatomic, assign) int heroKey;
@property (nonatomic, assign) int quality;
@property (nonatomic, assign) int faction;
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, copy)   NSString *qualityTag;
@property (nonatomic, copy)   NSString *factionTag;
@end

@implementation HeroItem
@end

#pragma mark - Passthrough Window (Không chặn touch game bên dưới)

@interface PassthroughWindow : UIWindow
@end

@implementation PassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) {
        return nil; // Bỏ qua cửa sổ trong suốt để click xuyên vào game
    }
    return hit;
}
@end

#pragma mark - Floating Menu Controller

@interface FloatingMenuController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UIButton    *floatingBtn;
@property (nonatomic, strong) UIView      *menuView;
@property (nonatomic, strong) UISegmentedControl *tabSegment;
@property (nonatomic, strong) UIScrollView *tabSummonScrollView;
@property (nonatomic, strong) UIView      *tabExtraView;

// Tab 1 state
@property (nonatomic, assign) HeroFactionEnum selectedFaction;
@property (nonatomic, strong) NSMutableArray<UIButton *> *factionButtons;
@property (nonatomic, strong) UILabel     *summonCountLabel;
@property (nonatomic, strong) UIButton    *startSummonBtn;
@property (nonatomic, strong) NSTimer     *summonTimer;
@property (nonatomic, assign) NSInteger    summonBoxCount;
@property (nonatomic, assign) NSTimeInterval summonDelay;
@property (nonatomic, strong) UITextField *delayField;

// Tab 2 state (Extra)
@property (nonatomic, assign) NSInteger    extraFactionFilter; // 0 = all
@property (nonatomic, strong) UISegmentedControl *extraFactionSegment;
@property (nonatomic, strong) UISwitch    *searchEnabledSwitch;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UILabel     *selectedCountLabel;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextView  *resultsTextView;
@property (nonatomic, strong) NSArray<HeroItem *> *allHeroes;
@property (nonatomic, strong) NSArray<HeroItem *> *filteredHeroes;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedHeroNames;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *heroDropCounts;

- (void)handleDroppedHeroKey:(int)heroKey;
@end

@implementation FloatingMenuController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    self.selectedFaction = FACTION_STR; // Mặc định STR
    self.summonDelay     = 0.35;        // Mặc định 0.35s
    self.extraFactionFilter = 0;        // Mặc định ALL
    self.selectedHeroNames = [NSMutableSet new];
    self.heroDropCounts = [NSMutableDictionary new];
    self.factionButtons = [NSMutableArray new];

    [self setupFloatingButton];
    [self setupMenuView];
    [self setupTabSummon];
    [self setupTabExtra];

    [self switchTab:0];
}

#pragma mark - Floating Button

- (void)setupFloatingButton {
    self.floatingBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatingBtn.frame = CGRectMake(16, 80, 52, 52);
    self.floatingBtn.layer.cornerRadius = 26;
    self.floatingBtn.layer.masksToBounds = NO;
    self.floatingBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:0.92];
    self.floatingBtn.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.95 alpha:0.9].CGColor;
    self.floatingBtn.layer.borderWidth = 1.8;

    self.floatingBtn.layer.shadowColor = [UIColor cyanColor].CGColor;
    self.floatingBtn.layer.shadowOffset = CGSizeMake(0, 0);
    self.floatingBtn.layer.shadowOpacity = 0.6;
    self.floatingBtn.layer.shadowRadius = 8;

    [self.floatingBtn setTitle:@"🔮" forState:UIControlStateNormal];
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
    center.y = MAX(r + 14, MIN(scr.height - r - 14, center.y));

    self.floatingBtn.center = center;
    [pan setTranslation:CGPointZero inView:self.view];

    if (pan.state == UIGestureRecognizerStateEnded) {
        [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:0 animations:^{
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
        if (!self.allHeroes.count) {
            [self loadAllHeroesFromDb];
        }
    } else {
        [UIView animateWithDuration:0.16 animations:^{
            self.menuView.transform = CGAffineTransformMakeScale(0.88, 0.88);
            self.menuView.alpha = 0.0;
        } completion:^(BOOL finished) {
            self.menuView.hidden = YES;
            self.menuView.transform = CGAffineTransformIdentity;
        }];
    }
}

#pragma mark - Menu Window Frame (Kích thước nhỏ gọn tối ưu Landscape)

- (void)setupMenuView {
    CGSize scr = [UIScreen mainScreen].bounds.size;
    CGFloat scrW = MAX(scr.width, scr.height); // Chiều dài landscape
    CGFloat scrH = MIN(scr.width, scr.height); // Chiều cao landscape

    // Thu nhỏ menu: chiều ngang 490pt, chiều dọc 308pt để vừa khít màn hình game
    CGFloat w = MIN(490, scrW - 20);
    CGFloat h = MIN(308, scrH - 20);

    self.menuView = [[UIView alloc] initWithFrame:CGRectMake((scrW - w) / 2.0, (scrH - h) / 2.0, w, h)];
    self.menuView.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.13 alpha:0.96];
    self.menuView.layer.cornerRadius = 14;
    self.menuView.layer.borderColor = [UIColor colorWithRed:0.35 green:0.25 blue:0.65 alpha:0.85].CGColor;
    self.menuView.layer.borderWidth = 1.5;
    self.menuView.layer.masksToBounds = YES;
    self.menuView.hidden = YES;

    // Header Bar
    UIView *topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 36)];
    topBar.backgroundColor = [UIColor colorWithRed:0.13 green:0.13 blue:0.22 alpha:0.95];

    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, w - 50, 36)];
    titleLbl.text = @"🔮 MENU CHIÊU MỘ PROPHET";
    titleLbl.font = [UIFont boldSystemFontOfSize:13];
    titleLbl.textColor = [UIColor whiteColor];
    [topBar addSubview:titleLbl];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w - 38, 0, 38, 36);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    closeBtn.tintColor = [UIColor lightGrayColor];
    [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:closeBtn];

    [self.menuView addSubview:topBar];

    // Tab Segment
    self.tabSegment = [[UISegmentedControl alloc] initWithItems:@[@"Chiêu Mộ Đặc Biệt", @"Extra (Tướng SS)"]];
    self.tabSegment.frame = CGRectMake(10, 42, w - 20, 28);
    self.tabSegment.selectedSegmentIndex = 0;
    [self.tabSegment addTarget:self action:@selector(onTabChanged:) forControlEvents:UIControlEventValueChanged];
    if (@available(iOS 13.0, *)) {
        self.tabSegment.selectedSegmentTintColor = [UIColor colorWithRed:0.25 green:0.35 blue:0.65 alpha:1.0];
        [self.tabSegment setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor whiteColor], NSFontAttributeName:[UIFont boldSystemFontOfSize:11]} forState:UIControlStateSelected];
        [self.tabSegment setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor lightGrayColor], NSFontAttributeName:[UIFont systemFontOfSize:11]} forState:UIControlStateNormal];
    }
    [self.menuView addSubview:self.tabSegment];

    // Container cho Tab Content
    CGFloat contentY = 74;
    CGFloat contentH = h - contentY;

    // Bọc Tab 1 trong UIScrollView để lướt mượt mà nếu màn hình quá nhỏ
    self.tabSummonScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, contentY, w, contentH)];
    self.tabSummonScrollView.alwaysBounceVertical = YES;
    self.tabSummonScrollView.showsVerticalScrollIndicator = YES;

    self.tabExtraView = [[UIView alloc] initWithFrame:CGRectMake(0, contentY, w, contentH)];

    [self.menuView addSubview:self.tabSummonScrollView];
    [self.menuView addSubview:self.tabExtraView];

    [self.view addSubview:self.menuView];
}

- (void)onTabChanged:(UISegmentedControl *)seg {
    [self switchTab:seg.selectedSegmentIndex];
}

- (void)switchTab:(NSInteger)idx {
    self.tabSummonScrollView.hidden = (idx != 0);
    self.tabExtraView.hidden        = (idx != 1);
    if (idx == 1 && !self.allHeroes.count) {
        [self loadAllHeroesFromDb];
    }
}

#pragma mark - Tab 1: Chiêu Mộ (Layout 2 cột ngang + UIScrollView)

- (void)setupTabSummon {
    CGFloat totalW = self.tabSummonScrollView.bounds.size.width;

    // Chia 2 cột:
    // Cột trái (width ~245): 6 nút hệ + Ô nhập số Delay
    // Cột phải (width ~215): Hộp đếm số thùng + Nút BẮT ĐẦU/DỪNG + Đặt lại
    CGFloat leftColW = 246;
    CGFloat rightColX = 262;
    CGFloat rightColW = totalW - rightColX - 10;

    // --- CỘT TRÁI: HỆ & DELAY ---
    UILabel *headerLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 4, leftColW, 16)];
    headerLbl.text = @"CHỌN HỆ CHIÊU MỘ:";
    headerLbl.font = [UIFont boldSystemFontOfSize:10];
    headerLbl.textColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.95 alpha:1.0];
    [self.tabSummonScrollView addSubview:headerLbl];

    NSArray *factions = @[
        @{@"name": @"AGI",   @"desc": @"Tốc/Fortress", @"tag": @(FACTION_AGI)},
        @{@"name": @"VIT",   @"desc": @"Thủ/Forest",   @"tag": @(FACTION_VIT)},
        @{@"name": @"STR",   @"desc": @"Công/Abyss",   @"tag": @(FACTION_STR)},
        @{@"name": @"DEX",   @"desc": @"Khéo/Shadow",  @"tag": @(FACTION_DEX)},
        @{@"name": @"DARK",  @"desc": @"Bóng Đêm/Ám",  @"tag": @(FACTION_DARK)},
        @{@"name": @"LIGHT", @"desc": @"Ánh Sáng/Quang",@"tag": @(FACTION_LIGHT)},
    ];

    CGFloat btnW = (leftColW - 6) / 2.0;
    CGFloat btnH = 28;
    for (int i = 0; i < factions.count; i++) {
        NSDictionary *d = factions[i];
        int row = i / 2;
        int col = i % 2;
        CGFloat x = 10 + col * (btnW + 6);
        CGFloat y = 22 + row * (btnH + 4);

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(x, y, btnW, btnH);
        btn.layer.cornerRadius = 6;
        btn.layer.borderWidth = 1.0;
        btn.layer.borderColor = [UIColor colorWithWhite:0.28 alpha:1.0].CGColor;
        btn.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.9];
        btn.tag = [d[@"tag"] integerValue];

        NSString *title = [NSString stringWithFormat:@"%@ (%@)", d[@"name"], d[@"desc"]];
        [btn setTitle:title forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:10];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

        [btn addTarget:self action:@selector(onFactionBtnClicked:) forControlEvents:UIControlEventTouchUpInside];
        [self.tabSummonScrollView addSubview:btn];
        [self.factionButtons addObject:btn];
    }

    [self updateFactionButtonsState];

    // Cài đặt Delay (Ô nhập số)
    CGFloat delayY = 22 + 3 * (btnH + 4) + 6; // ~124
    UIView *delayRow = [[UIView alloc] initWithFrame:CGRectMake(10, delayY, leftColW, 30)];
    delayRow.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    delayRow.layer.cornerRadius = 6;
    delayRow.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    delayRow.layer.borderWidth = 1.0;

    UILabel *delayTitleLbl = [[UILabel alloc] initWithFrame:CGRectMake(8, 5, 80, 20)];
    delayTitleLbl.text = @"⏱ Delay:";
    delayTitleLbl.font = [UIFont boldSystemFontOfSize:11];
    delayTitleLbl.textColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.95 alpha:1.0];
    [delayRow addSubview:delayTitleLbl];

    self.delayField = [[UITextField alloc] initWithFrame:CGRectMake(74, 3, 70, 24)];
    self.delayField.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
    self.delayField.layer.cornerRadius = 5;
    self.delayField.layer.borderColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.9 alpha:0.8].CGColor;
    self.delayField.layer.borderWidth = 1.0;
    self.delayField.textColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.2 alpha:1.0];
    self.delayField.font = [UIFont boldSystemFontOfSize:12];
    self.delayField.textAlignment = NSTextAlignmentCenter;
    self.delayField.keyboardType = UIKeyboardTypeDecimalPad;
    self.delayField.text = @"0.35";
    self.delayField.delegate = self;
    [self.delayField addTarget:self action:@selector(onDelayFieldChanged:) forControlEvents:UIControlEventEditingChanged];

    // Toolbar nút "Xong" cho DecimalPad
    UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 36)];
    bar.barStyle = UIBarStyleBlack;
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:@"Xong" style:UIBarButtonItemStyleDone target:self.delayField action:@selector(resignFirstResponder)];
    done.tintColor = [UIColor cyanColor];
    bar.items = @[flex, done];
    self.delayField.inputAccessoryView = bar;
    [delayRow addSubview:self.delayField];

    UILabel *delayUnitLbl = [[UILabel alloc] initWithFrame:CGRectMake(150, 5, 80, 20)];
    delayUnitLbl.text = @"giây/lần";
    delayUnitLbl.font = [UIFont systemFontOfSize:10];
    delayUnitLbl.textColor = [UIColor lightGrayColor];
    [delayRow addSubview:delayUnitLbl];

    [self.tabSummonScrollView addSubview:delayRow];

    // --- CỘT PHẢI: STATS & NÚT BẮT ĐẦU ---
    // Stats Box
    UIView *statsBox = [[UIView alloc] initWithFrame:CGRectMake(rightColX, 4, rightColW, 64)];
    statsBox.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    statsBox.layer.cornerRadius = 8;
    statsBox.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    statsBox.layer.borderWidth = 1.0;

    self.summonCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(6, 6, rightColW - 12, 26)];
    self.summonCountLabel.text = @"Đã mở: 0 thùng";
    self.summonCountLabel.font = [UIFont boldSystemFontOfSize:15];
    self.summonCountLabel.textColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.7 alpha:1.0];
    self.summonCountLabel.textAlignment = NSTextAlignmentCenter;
    [statsBox addSubview:self.summonCountLabel];

    UILabel *subStat = [[UILabel alloc] initWithFrame:CGRectMake(6, 34, rightColW - 12, 20)];
    subStat.text = @"(1 thùng = 10 quả cầu)";
    subStat.font = [UIFont systemFontOfSize:10];
    subStat.textColor = [UIColor lightGrayColor];
    subStat.textAlignment = NSTextAlignmentCenter;
    [statsBox addSubview:subStat];

    [self.tabSummonScrollView addSubview:statsBox];

    // Nút BẮT ĐẦU / DỪNG (Nằm ngay bên phải, luôn thấy rõ mà không cần cuộn)
    self.startSummonBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.startSummonBtn.frame = CGRectMake(rightColX, 76, rightColW, 44);
    self.startSummonBtn.layer.cornerRadius = 10;
    self.startSummonBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.72 blue:0.58 alpha:1.0];
    [self.startSummonBtn setTitle:@"BẮT ĐẦU" forState:UIControlStateNormal];
    self.startSummonBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.startSummonBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.startSummonBtn addTarget:self action:@selector(onStartSummonToggle) forControlEvents:UIControlEventTouchUpInside];

    [self.tabSummonScrollView addSubview:self.startSummonBtn];

    // Nút Đặt lại bộ đếm
    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    resetBtn.frame = CGRectMake(rightColX, 126, rightColW, 26);
    [resetBtn setTitle:@"Đặt lại đếm" forState:UIControlStateNormal];
    resetBtn.tintColor = [UIColor grayColor];
    resetBtn.titleLabel.font = [UIFont systemFontOfSize:11];
    [resetBtn addTarget:self action:@selector(resetSummonCount) forControlEvents:UIControlEventTouchUpInside];
    [self.tabSummonScrollView addSubview:resetBtn];

    // Thiết lập contentSize để lướt được nếu màn hình thấp hơn 300
    self.tabSummonScrollView.contentSize = CGSizeMake(totalW, 168);
}

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
            b.layer.borderColor = [UIColor colorWithWhite:0.26 alpha:1.0].CGColor;
            b.layer.borderWidth = 1.0;
            b.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.9];
        }
    }
}

- (void)onDelayFieldChanged:(UITextField *)tf {
    NSString *clean = [tf.text stringByReplacingOccurrencesOfString:@"," withString:@"."];
    double val = [clean doubleValue];
    if (val >= 0.01 && val <= 60.0) {
        self.summonDelay = val;
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
}

- (void)resetSummonCount {
    self.summonBoxCount = 0;
    self.summonCountLabel.text = @"Đã mở: 0 thùng";
}

- (void)onStartSummonToggle {
    if (!gIsAutoSummoning) {
        NSString *clean = [self.delayField.text stringByReplacingOccurrencesOfString:@"," withString:@"."];
        double val = [clean doubleValue];
        if (val >= 0.01 && val <= 60.0) {
            self.summonDelay = val;
        } else if (self.summonDelay < 0.01) {
            self.summonDelay = 0.35;
            self.delayField.text = @"0.35";
        }
        [self.delayField resignFirstResponder];

        gIsAutoSummoning = YES;
        [self.startSummonBtn setTitle:@"DỪNG" forState:UIControlStateNormal];
        self.startSummonBtn.backgroundColor = [UIColor colorWithRed:0.85 green:0.2 blue:0.2 alpha:1.0];

        NSTimeInterval d = (self.summonDelay >= 0.01) ? self.summonDelay : 0.35;
        self.summonTimer = [NSTimer scheduledTimerWithTimeInterval:d
                                                            target:self
                                                          selector:@selector(onSummonTimerTick)
                                                          userInfo:nil
                                                           repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.summonTimer forMode:NSRunLoopCommonModes];
    } else {
        gIsAutoSummoning = NO;
        [self.summonTimer invalidate];
        self.summonTimer = nil;
        [self.startSummonBtn setTitle:@"BẮT ĐẦU" forState:UIControlStateNormal];
        self.startSummonBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.72 blue:0.58 alpha:1.0];
    }
}

- (void)onSummonTimerTick {
    if (!gIsAutoSummoning || !gBase) return;

    // GameContext.GetInstance() @ 0x14473AC
    typedef void *(*GC_GetInstance_t)(void);
    GC_GetInstance_t getGC = (GC_GetInstance_t)(gBase + OFF_GAME_CONTEXT_GET_INSTANCE);
    void *gc = getGC ? getGC() : NULL;
    if (!gc || (uintptr_t)gc < 0x100000000ULL) return;

    // dataSender ở offset 0x1A0 (416 decimal)
    void *dataSender = *(void **)((uint8_t *)gc + 0x1A0);
    if (!dataSender || (uintptr_t)dataSender < 0x100000000ULL) return;

    // DataSender.HeroProphetSummon(dataSender, faction, 10) @ 0x140437C
    typedef void (*Summon_t)(void *, int, int);
    Summon_t summon = (Summon_t)(gBase + OFF_HERO_PROPHET_SUMMON);
    if (summon) {
        summon(dataSender, (int)self.selectedFaction, 10);
        self.summonBoxCount += 1;
        self.summonCountLabel.text = [NSString stringWithFormat:@"Đã mở: %ld thùng", (long)self.summonBoxCount];
    }
}

#pragma mark - Tab 2: Extra (Phân theo hệ + Tìm kiếm + Tên thật In-Game)

- (void)setupTabExtra {
    CGFloat totalW = self.tabExtraView.bounds.size.width;
    CGFloat totalH = self.tabExtraView.bounds.size.height;

    // Cột trái (width ~290): Thanh lọc hệ + Tìm kiếm + Bảng tướng
    // Cột phải (width ~175): Bật/tắt + Khung kết quả đếm
    CGFloat leftColW = 290;
    CGFloat rightColX = 302;
    CGFloat rightColW = totalW - rightColX - 10;

    // 1. Ô tìm kiếm
    self.searchField = [[UITextField alloc] initWithFrame:CGRectMake(8, 4, leftColW, 26)];
    self.searchField.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    self.searchField.layer.cornerRadius = 6;
    self.searchField.layer.borderColor = [UIColor grayColor].CGColor;
    self.searchField.layer.borderWidth = 0.8;
    self.searchField.textColor = [UIColor whiteColor];
    self.searchField.font = [UIFont systemFontOfSize:11];
    self.searchField.placeholder = @"🔍 Nhập tên tướng cần tìm...";
    self.searchField.delegate = self;
    self.searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    [self.searchField addTarget:self action:@selector(onSearchTextChanged:) forControlEvents:UIControlEventEditingChanged];

    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 6, 26)];
    self.searchField.leftView = pad;
    self.searchField.leftViewMode = UITextFieldViewModeAlways;
    [self.tabExtraView addSubview:self.searchField];

    // 2. THANH LỌC HỆ (TẤT CẢ, AGI, VIT, STR, DEX, ÁM, QUANG)
    NSArray *facTabs = @[@"ALL", @"AGI", @"VIT", @"STR", @"DEX", @"ÁM", @"QUANG"];
    self.extraFactionSegment = [[UISegmentedControl alloc] initWithItems:facTabs];
    self.extraFactionSegment.frame = CGRectMake(8, 34, leftColW, 24);
    self.extraFactionSegment.selectedSegmentIndex = 0;
    [self.extraFactionSegment addTarget:self action:@selector(onExtraFactionChanged:) forControlEvents:UIControlEventValueChanged];
    if (@available(iOS 13.0, *)) {
        self.extraFactionSegment.selectedSegmentTintColor = [UIColor colorWithRed:0.25 green:0.35 blue:0.65 alpha:1.0];
        [self.extraFactionSegment setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor whiteColor], NSFontAttributeName:[UIFont boldSystemFontOfSize:9]} forState:UIControlStateSelected];
        [self.extraFactionSegment setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor lightGrayColor], NSFontAttributeName:[UIFont systemFontOfSize:9]} forState:UIControlStateNormal];
    }
    [self.tabExtraView addSubview:self.extraFactionSegment];

    // 3. TableView danh sách tướng (Chiều cao tự co dãn vừa vặn)
    CGFloat tableY = 62;
    CGFloat tableH = totalH - tableY - 4;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(8, tableY, leftColW, tableH) style:UITableViewStylePlain];
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    self.tableView.layer.cornerRadius = 6;
    self.tableView.layer.masksToBounds = YES;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 32;
    self.tableView.separatorColor = [UIColor colorWithWhite:0.22 alpha:1.0];
    [self.tabExtraView addSubview:self.tableView];

    // --- CỘT PHẢI: SWITCH & KHUNG KẾT QUẢ ---
    UIView *swRow = [[UIView alloc] initWithFrame:CGRectMake(rightColX, 4, rightColW, 28)];
    UILabel *swLbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 4, 110, 20)];
    swLbl.text = @"Tìm tướng:";
    swLbl.font = [UIFont boldSystemFontOfSize:11];
    swLbl.textColor = [UIColor whiteColor];
    [swRow addSubview:swLbl];

    self.searchEnabledSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(rightColW - 48, 0, 44, 26)];
    self.searchEnabledSwitch.transform = CGAffineTransformMakeScale(0.75, 0.75);
    self.searchEnabledSwitch.on = YES;
    [swRow addSubview:self.searchEnabledSwitch];
    [self.tabExtraView addSubview:swRow];

    self.selectedCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(rightColX, 34, rightColW, 16)];
    self.selectedCountLabel.text = @"Đã chọn: 0 tướng";
    self.selectedCountLabel.font = [UIFont systemFontOfSize:10];
    self.selectedCountLabel.textColor = [UIColor cyanColor];
    [self.tabExtraView addSubview:self.selectedCountLabel];

    // Khung kết quả rơi tướng
    CGFloat resY = 54;
    CGFloat resH = totalH - resY - 32;
    self.resultsTextView = [[UITextView alloc] initWithFrame:CGRectMake(rightColX, resY, rightColW, resH)];
    self.resultsTextView.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.08 alpha:0.95];
    self.resultsTextView.layer.cornerRadius = 6;
    self.resultsTextView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.75 blue:0.6 alpha:0.7].CGColor;
    self.resultsTextView.layer.borderWidth = 1.0;
    self.resultsTextView.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0];
    self.resultsTextView.font = [UIFont boldSystemFontOfSize:10];
    self.resultsTextView.editable = NO;
    self.resultsTextView.text = @"(Chưa rơi tướng mục tiêu)";
    [self.tabExtraView addSubview:self.resultsTextView];

    // Nút Xoá kết quả
    UIButton *clearResBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearResBtn.frame = CGRectMake(rightColX, totalH - 28, rightColW, 24);
    [clearResBtn setTitle:@"Xoá kết quả" forState:UIControlStateNormal];
    clearResBtn.tintColor = [UIColor grayColor];
    clearResBtn.titleLabel.font = [UIFont systemFontOfSize:10];
    [clearResBtn addTarget:self action:@selector(clearResults) forControlEvents:UIControlEventTouchUpInside];
    [self.tabExtraView addSubview:clearResBtn];
}

- (void)onExtraFactionChanged:(UISegmentedControl *)seg {
    // 0: ALL, 1: AGI(4), 2: VIT(5), 3: STR(6), 4: DEX(3), 5: DARK(1), 6: LIGHT(2)
    NSInteger tags[] = { 0, FACTION_AGI, FACTION_VIT, FACTION_STR, FACTION_DEX, FACTION_DARK, FACTION_LIGHT };
    NSInteger idx = seg.selectedSegmentIndex;
    if (idx >= 0 && idx < 7) {
        self.extraFactionFilter = tags[idx];
        [self filterHeroes];
    }
}

- (void)onSearchTextChanged:(UITextField *)tf {
    [self filterHeroes];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)clearResults {
    [self.heroDropCounts removeAllObjects];
    [self updateResultsDisplay];
}

#pragma mark - Database Loader (Dùng Tên Thật Ingame từ I2LanguagesHelper)

- (void)loadAllHeroesFromDb {
    if (!gBase) return;

    // 1. Lấy DbManager.GetInstance() @ 0x140C030
    typedef void *(*Db_GetInstance_t)(void);
    Db_GetInstance_t getDb = (Db_GetInstance_t)(gBase + OFF_DB_MANAGER_GET_INSTANCE);
    void *db = getDb ? getDb() : NULL;
    if (!db || (uintptr_t)db < 0x100000000ULL) return;

    // 2. m_ListHeroModel ở offset 0x38 (56 decimal)
    void *list = *(void **)((uint8_t *)db + 0x38);
    int32_t count = ILListSize(list);
    if (count <= 0) return;

    // 3. Hàm dịch tên ingame I2LanguagesHelper.GetTranslation @ 0x105A738
    typedef void *(*GetTranslation_t)(void *, void *);
    GetTranslation_t getTrans = (GetTranslation_t)(gBase + OFF_I2_GET_TRANSLATION);

    NSMutableSet<NSString *> *seen = [NSMutableSet new];
    NSMutableArray<HeroItem *> *arr = [NSMutableArray new];

    for (int i = 0; i < count; i++) {
        void *hero = ILListAt(list, i);
        if (!hero || (uintptr_t)hero < 0x100000000ULL) continue;

        // m_Quality ở offset 0x60 (96 decimal): 6 = SS, 7 = SSR
        int quality = *(int *)((uint8_t *)hero + 0x60);
        if (quality < 6) continue;

        // m_HeroName ở offset 0x28 (40 decimal)
        void *namePtr = *(void **)((uint8_t *)hero + 0x28);
        if (!IsValidPtr(namePtr)) continue;

        // LẤY TÊN THẬT INGAME: Dịch qua bộ Localization của game
        NSString *realName = nil;
        if (getTrans) {
            void *transPtr = getTrans(namePtr, NULL);
            if (IsValidPtr(transPtr)) {
                realName = ILStr(transPtr);
            }
        }
        // Dự phòng nếu không có dịch thì dùng string gốc
        if (!realName.length) {
            realName = ILStr(namePtr);
        }
        if (!realName.length) continue;

        // Lọc trùng tên
        if ([seen containsObject:realName]) continue;
        [seen addObject:realName];

        int heroKey = *(int *)((uint8_t *)hero + 0x18);
        int faction = *(int *)((uint8_t *)hero + 0x3C);

        NSString *facTag = @"?";
        switch (faction) {
            case 1: facTag = @"Ám"; break;
            case 2: facTag = @"Quang"; break;
            case 3: facTag = @"DEX"; break;
            case 4: facTag = @"AGI"; break;
            case 5: facTag = @"VIT"; break;
            case 6: facTag = @"STR"; break;
        }

        HeroItem *it = [HeroItem new];
        it.heroKey = heroKey;
        it.name = realName;
        it.quality = quality;
        it.qualityTag = (quality >= 7) ? @"SSR" : @"SS";
        it.faction = faction;
        it.factionTag = facTag;
        [arr addObject:it];
    }

    // Sắp xếp: SSR trước, rồi SS, rồi tên A-Z (Sửa lỗi NSComparisonResult)
    [arr sortUsingComparator:^NSComparisonResult(HeroItem *a, HeroItem *b) {
        if (a.quality != b.quality) {
            return (b.quality > a.quality) ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];

    self.allHeroes = arr;
    [self filterHeroes];
}

- (void)filterHeroes {
    NSString *kw = [self.searchField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSInteger factionTag = self.extraFactionFilter;

    NSMutableArray *res = [NSMutableArray new];
    for (HeroItem *it in self.allHeroes) {
        // Lọc theo hệ (nếu khác 0)
        if (factionTag > 0 && it.faction != factionTag) {
            continue;
        }
        // Lọc theo từ khóa tìm kiếm
        if (kw.length > 0 && [it.name rangeOfString:kw options:NSCaseInsensitiveSearch].location == NSNotFound) {
            continue;
        }
        [res addObject:it];
    }

    self.filteredHeroes = res;
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredHeroes.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"HeroCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:11];
        cell.detailTextLabel.font = [UIFont boldSystemFontOfSize:9];
    }

    HeroItem *item = self.filteredHeroes[indexPath.row];
    cell.textLabel.text = item.name;

    if (item.quality >= 7) {
        cell.textLabel.textColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.1 alpha:1.0]; // Vàng SSR
        cell.detailTextLabel.textColor = [UIColor orangeColor];
    } else {
        cell.textLabel.textColor = [UIColor whiteColor]; // Trắng SS
        cell.detailTextLabel.textColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.9 alpha:1.0];
    }
    cell.detailTextLabel.text = [NSString stringWithFormat:@"[%@] [%@]", item.qualityTag, item.factionTag];

    if ([self.selectedHeroNames containsObject:item.name]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
        cell.tintColor = [UIColor cyanColor];
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    HeroItem *item = self.filteredHeroes[indexPath.row];

    if ([self.selectedHeroNames containsObject:item.name]) {
        [self.selectedHeroNames removeObject:item.name];
    } else {
        [self.selectedHeroNames addObject:item.name];
    }

    self.selectedCountLabel.text = [NSString stringWithFormat:@"Đã chọn: %lu tướng", (unsigned long)self.selectedHeroNames.count];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - Xử lý tướng rơi ra khi summon

- (void)handleDroppedHeroKey:(int)heroKey {
    if (!gBase) return;

    typedef void *(*Db_GetInstance_t)(void);
    Db_GetInstance_t getDb = (Db_GetInstance_t)(gBase + OFF_DB_MANAGER_GET_INSTANCE);
    void *db = getDb ? getDb() : NULL;
    if (!db) return;

    typedef void *(*GetHero_t)(void *, int);
    GetHero_t getHero = (GetHero_t)(gBase + OFF_DB_MANAGER_GET_HERO_MODEL);
    void *hero = getHero ? getHero(db, heroKey) : NULL;
    if (!hero || (uintptr_t)hero < 0x100000000ULL) return;

    int quality = *(int *)((uint8_t *)hero + 0x60);

    // LẤY TÊN THẬT INGAME CỦA TƯỚNG RƠI RA
    void *namePtr = *(void **)((uint8_t *)hero + 0x28);
    NSString *realName = nil;
    if (IsValidPtr(namePtr)) {
        typedef void *(*GetTranslation_t)(void *, void *);
        GetTranslation_t getTrans = (GetTranslation_t)(gBase + OFF_I2_GET_TRANSLATION);
        if (getTrans) {
            void *transPtr = getTrans(namePtr, NULL);
            if (IsValidPtr(transPtr)) realName = ILStr(transPtr);
        }
        if (!realName.length) realName = ILStr(namePtr);
    }
    if (!realName.length) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL isTarget = [self.selectedHeroNames containsObject:realName];

        if (self.searchEnabledSwitch.on) {
            if (!isTarget) return;
        } else {
            if (quality < 6) return;
        }

        NSInteger cur = [self.heroDropCounts[realName] integerValue];
        self.heroDropCounts[realName] = @(cur + 1);

        [self updateResultsDisplay];
    });
}

- (void)updateResultsDisplay {
    if (!self.heroDropCounts.count) {
        self.resultsTextView.text = @"(Chưa rơi tướng mục tiêu)";
        return;
    }

    NSMutableString *s = [NSMutableString new];
    for (NSString *name in self.heroDropCounts.allKeys) {
        NSInteger c = [self.heroDropCounts[name] integerValue];
        if (s.length) [s appendString:@"\n"];
        [s appendFormat:@"%@: %ld", name, (long)c];
    }
    self.resultsTextView.text = s;
}

@end

#pragma mark - Hooks

static void (*orig_SetBonusModel)(void *, void *) = NULL;

static void Hook_SetBonusModel(void *self, void *bonusModel) {
    if (orig_SetBonusModel) orig_SetBonusModel(self, bonusModel);

    // Đọc danh sách tướng nhận được trong BonusModel.m_LstBonusHero @ +0x10
    if (bonusModel && (uintptr_t)bonusModel >= 0x100000000ULL) {
        void *heroList = *(void **)((uint8_t *)bonusModel + 0x10);
        int32_t count = ILListSize(heroList);
        for (int i = 0; i < count; i++) {
            void *bonusHero = ILListAt(heroList, i);
            if (!bonusHero || (uintptr_t)bonusHero < 0x100000000ULL) continue;
            int heroKey = *(int *)((uint8_t *)bonusHero + 0x14);
            if (gMenuCtrl) {
                [gMenuCtrl handleDroppedHeroKey:heroKey];
            }
        }
    }

    // Nếu đang bật auto summon: tự động bấm nút đóng để game tiếp tục spam
    if (gIsAutoSummoning && gBase) {
        typedef void (*CloseClick_t)(void *);
        CloseClick_t closeClick = (CloseClick_t)(gBase + OFF_POPUP_BONUS_CLOSE_CLICK);
        if (closeClick && self) {
            closeClick(self);
        }
    }
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

            gMenuCtrl = [FloatingMenuController new];
            gOverlayWindow.rootViewController = gMenuCtrl;
            gOverlayWindow.hidden = NO;
        });
    });
}

static void InstallIl2CppHooks(uintptr_t base) {
    static BOOL done = NO;
    if (done || !base) return;
    done = YES;
    gBase = base;

    MSHookFunction((void *)(base + OFF_POPUP_BONUS_SET_MODEL),
                   (void *)&Hook_SetBonusModel,
                   (void **)&orig_SetBonusModel);
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
static void InitMod(void) {
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
