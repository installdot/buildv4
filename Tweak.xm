// Tweak.xm — Chiêu Mộ Đặc Biệt (Prophet Summon) Full Hệ, Ô Nhập Số Delay & Extra Tướng SS
//
// Tính năng:
// 1. Floating button di chuyển được trên màn hình, chạm để đóng/mở menu.
// 2. Tab 1: Chiêu mộ đặc biệt:
//    - ĐẦY ĐỦ TẤT CẢ 6 HỆ: AGI, VIT, STR, DEX, DARK, LIGHT
//    - CÀI ĐẶT DELAY: Ô nhập số tự do (ví dụ: 0.1, 0.35, 1.0,... có bàn phím số + nút Xong)
//    - Nút Bắt đầu / Dừng: spam gọi summon 10 thùng (Prophet Orb x10)
//    - Đếm và hiển thị số lượng thùng đã mở trong thời gian thực
//    - Tự động đóng popup nhận thưởng để vòng lặp spam không bị khựng
// 3. Tab 2: Extra:
//    - Đọc trực tiếp DbManager.m_ListHeroModel trong UnityFramework
//    - Lọc toàn bộ tướng SS (m_Quality == 6) và SSR (m_Quality == 7) kèm hệ của tướng
//    - Thanh tìm kiếm thời gian thực
//    - Tickbox bật/tắt chế độ "Tìm nhân vật"
//    - Chọn nhiều nhân vật cùng lúc (multi-select checkmark)
//    - Bắt event triệu hồi rơi tướng: hiển thị "Tên nhân vật: 1/2/..."

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
@property (nonatomic, strong) UIView      *tabSummonView;
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
    self.floatingBtn.frame = CGRectMake(20, 100, 56, 56);
    self.floatingBtn.layer.cornerRadius = 28;
    self.floatingBtn.layer.masksToBounds = NO;
    self.floatingBtn.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.24 alpha:0.92];
    self.floatingBtn.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.9 alpha:0.9].CGColor;
    self.floatingBtn.layer.borderWidth = 2.0;

    self.floatingBtn.layer.shadowColor = [UIColor cyanColor].CGColor;
    self.floatingBtn.layer.shadowOffset = CGSizeMake(0, 0);
    self.floatingBtn.layer.shadowOpacity = 0.6;
    self.floatingBtn.layer.shadowRadius = 8;

    [self.floatingBtn setTitle:@"🔮" forState:UIControlStateNormal];
    self.floatingBtn.titleLabel.font = [UIFont systemFontOfSize:26];

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
    center.y = MAX(r + 20, MIN(scr.height - r - 20, center.y));

    self.floatingBtn.center = center;
    [pan setTranslation:CGPointZero inView:self.view];

    if (pan.state == UIGestureRecognizerStateEnded) {
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
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
        self.menuView.transform = CGAffineTransformMakeScale(0.85, 0.85);
        self.menuView.alpha = 0.0;
        self.menuView.hidden = NO;
        [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
            self.menuView.transform = CGAffineTransformIdentity;
            self.menuView.alpha = 1.0;
        } completion:nil];
        if (!self.allHeroes.count) {
            [self loadAllHeroesFromDb];
        }
    } else {
        [UIView animateWithDuration:0.18 animations:^{
            self.menuView.transform = CGAffineTransformMakeScale(0.85, 0.85);
            self.menuView.alpha = 0.0;
        } completion:^(BOOL finished) {
            self.menuView.hidden = YES;
            self.menuView.transform = CGAffineTransformIdentity;
        }];
    }
}

#pragma mark - Menu Window Frame

- (void)setupMenuView {
    CGSize scr = [UIScreen mainScreen].bounds.size;
    CGFloat w = MIN(350, scr.width - 20);
    CGFloat h = MIN(480, scr.height - 30);

    self.menuView = [[UIView alloc] initWithFrame:CGRectMake((scr.width - w) / 2.0, (scr.height - h) / 2.0, w, h)];
    self.menuView.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.14 alpha:0.96];
    self.menuView.layer.cornerRadius = 16;
    self.menuView.layer.borderColor = [UIColor colorWithRed:0.4 green:0.2 blue:0.8 alpha:0.8].CGColor;
    self.menuView.layer.borderWidth = 1.5;
    self.menuView.layer.masksToBounds = YES;
    self.menuView.hidden = YES;

    // Header Bar
    UIView *topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 44)];
    topBar.backgroundColor = [UIColor colorWithRed:0.14 green:0.14 blue:0.24 alpha:0.9];

    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, w - 60, 44)];
    titleLbl.text = @"🔮 MENU CHIÊU MỘ PROPHET";
    titleLbl.font = [UIFont boldSystemFontOfSize:14];
    titleLbl.textColor = [UIColor whiteColor];
    [topBar addSubview:titleLbl];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w - 44, 0, 44, 44);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    closeBtn.tintColor = [UIColor lightGrayColor];
    [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:closeBtn];

    [self.menuView addSubview:topBar];

    // Tab Segment
    self.tabSegment = [[UISegmentedControl alloc] initWithItems:@[@"Chiêu Mộ Đặc Biệt", @"Extra (Tướng SS)"]];
    self.tabSegment.frame = CGRectMake(12, 52, w - 24, 32);
    self.tabSegment.selectedSegmentIndex = 0;
    [self.tabSegment addTarget:self action:@selector(onTabChanged:) forControlEvents:UIControlEventValueChanged];
    if (@available(iOS 13.0, *)) {
        self.tabSegment.selectedSegmentTintColor = [UIColor colorWithRed:0.3 green:0.2 blue:0.7 alpha:1.0];
        [self.tabSegment setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor whiteColor], NSFontAttributeName:[UIFont boldSystemFontOfSize:12]} forState:UIControlStateSelected];
        [self.tabSegment setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor lightGrayColor], NSFontAttributeName:[UIFont systemFontOfSize:12]} forState:UIControlStateNormal];
    }
    [self.menuView addSubview:self.tabSegment];

    CGFloat contentH = h - 94;
    self.tabSummonView = [[UIView alloc] initWithFrame:CGRectMake(0, 90, w, contentH)];
    self.tabExtraView  = [[UIView alloc] initWithFrame:CGRectMake(0, 90, w, contentH)];

    [self.menuView addSubview:self.tabSummonView];
    [self.menuView addSubview:self.tabExtraView];

    [self.view addSubview:self.menuView];
}

- (void)onTabChanged:(UISegmentedControl *)seg {
    [self switchTab:seg.selectedSegmentIndex];
}

- (void)switchTab:(NSInteger)idx {
    self.tabSummonView.hidden = (idx != 0);
    self.tabExtraView.hidden  = (idx != 1);
    if (idx == 1 && !self.allHeroes.count) {
        [self loadAllHeroesFromDb];
    }
}

#pragma mark - Tab 1: Chiêu Mộ Đặc Biệt (Full 6 hệ + Ô Nhập Số Delay)

- (void)setupTabSummon {
    CGFloat w = self.tabSummonView.bounds.size.width;

    UILabel *headerLbl = [[UILabel alloc] initWithFrame:CGRectMake(14, 6, w - 28, 18)];
    headerLbl.text = @"CHỌN HỆ CHIÊU MỘ:";
    headerLbl.font = [UIFont boldSystemFontOfSize:11];
    headerLbl.textColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.95 alpha:1.0];
    [self.tabSummonView addSubview:headerLbl];

    // ĐẦY ĐỦ TẤT CẢ 6 HỆ: 2 cột x 3 dòng
    NSArray *factions = @[
        @{@"name": @"AGI",   @"desc": @"Fortress/Tốc",  @"tag": @(FACTION_AGI)},
        @{@"name": @"VIT",   @"desc": @"Forest/Thủ",    @"tag": @(FACTION_VIT)},
        @{@"name": @"STR",   @"desc": @"Abyss/Công",    @"tag": @(FACTION_STR)},
        @{@"name": @"DEX",   @"desc": @"Shadow/Khéo",   @"tag": @(FACTION_DEX)},
        @{@"name": @"DARK",  @"desc": @"Bóng Đêm/Ám",   @"tag": @(FACTION_DARK)},
        @{@"name": @"LIGHT", @"desc": @"Ánh Sáng/Quang",@"tag": @(FACTION_LIGHT)},
    ];

    CGFloat btnW = (w - 38) / 2.0;
    CGFloat btnH = 32;
    for (int i = 0; i < factions.count; i++) {
        NSDictionary *d = factions[i];
        int row = i / 2;
        int col = i % 2;
        CGFloat x = 14 + col * (btnW + 10);
        CGFloat y = 26 + row * (btnH + 5);

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(x, y, btnW, btnH);
        btn.layer.cornerRadius = 7;
        btn.layer.borderWidth = 1.0;
        btn.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1.0].CGColor;
        btn.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.9];
        btn.tag = [d[@"tag"] integerValue];

        NSString *title = [NSString stringWithFormat:@"%@  (%@)", d[@"name"], d[@"desc"]];
        [btn setTitle:title forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

        [btn addTarget:self action:@selector(onFactionBtnClicked:) forControlEvents:UIControlEventTouchUpInside];
        [self.tabSummonView addSubview:btn];
        [self.factionButtons addObject:btn];
    }

    [self updateFactionButtonsState];

    // CÀI ĐẶT DELAY: Ô nhập số tự do kèm thanh công cụ Xong
    CGFloat delayY = 26 + 3 * (btnH + 5) + 8; // ~145
    UIView *delayRow = [[UIView alloc] initWithFrame:CGRectMake(14, delayY, w - 28, 34)];
    delayRow.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    delayRow.layer.cornerRadius = 8;
    delayRow.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    delayRow.layer.borderWidth = 1.0;

    UILabel *delayTitleLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 7, 130, 20)];
    delayTitleLbl.text = @"⏱ Delay (giây):";
    delayTitleLbl.font = [UIFont boldSystemFontOfSize:12];
    delayTitleLbl.textColor = [UIColor colorWithRed:0.0 green:0.85 blue:0.95 alpha:1.0];
    [delayRow addSubview:delayTitleLbl];

    self.delayField = [[UITextField alloc] initWithFrame:CGRectMake(140, 4, 80, 26)];
    self.delayField.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
    self.delayField.layer.cornerRadius = 6;
    self.delayField.layer.borderColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.9 alpha:0.8].CGColor;
    self.delayField.layer.borderWidth = 1.0;
    self.delayField.textColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.2 alpha:1.0];
    self.delayField.font = [UIFont boldSystemFontOfSize:13];
    self.delayField.textAlignment = NSTextAlignmentCenter;
    self.delayField.keyboardType = UIKeyboardTypeDecimalPad;
    self.delayField.text = @"0.35";
    self.delayField.delegate = self;
    [self.delayField addTarget:self action:@selector(onDelayFieldChanged:) forControlEvents:UIControlEventEditingChanged];

    // Toolbar có nút "Xong" để đóng bàn phím số DecimalPad trên iPhone
    UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 38)];
    bar.barStyle = UIBarStyleBlack;
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:@"Xong" style:UIBarButtonItemStyleDone target:self.delayField action:@selector(resignFirstResponder)];
    done.tintColor = [UIColor cyanColor];
    bar.items = @[flex, done];
    self.delayField.inputAccessoryView = bar;
    [delayRow addSubview:self.delayField];

    UILabel *delayUnitLbl = [[UILabel alloc] initWithFrame:CGRectMake(226, 7, 70, 20)];
    delayUnitLbl.text = @"giây/lần";
    delayUnitLbl.font = [UIFont systemFontOfSize:11];
    delayUnitLbl.textColor = [UIColor lightGrayColor];
    [delayRow addSubview:delayUnitLbl];

    [self.tabSummonView addSubview:delayRow];

    // Stats Box
    CGFloat statsY = delayY + 34 + 8; // ~187
    UIView *statsBox = [[UIView alloc] initWithFrame:CGRectMake(14, statsY, w - 28, 54)];
    statsBox.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    statsBox.layer.cornerRadius = 10;
    statsBox.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    statsBox.layer.borderWidth = 1.0;

    self.summonCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 4, statsBox.bounds.size.width - 20, 24)];
    self.summonCountLabel.text = @"Đã mở: 0 thùng";
    self.summonCountLabel.font = [UIFont boldSystemFontOfSize:16];
    self.summonCountLabel.textColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.7 alpha:1.0];
    self.summonCountLabel.textAlignment = NSTextAlignmentCenter;
    [statsBox addSubview:self.summonCountLabel];

    UILabel *subStat = [[UILabel alloc] initWithFrame:CGRectMake(10, 28, statsBox.bounds.size.width - 20, 20)];
    subStat.text = @"(Mỗi thùng = 10 quả cầu tiên tri)";
    subStat.font = [UIFont systemFontOfSize:11];
    subStat.textColor = [UIColor lightGrayColor];
    subStat.textAlignment = NSTextAlignmentCenter;
    [statsBox addSubview:subStat];

    [self.tabSummonView addSubview:statsBox];

    // Nút BẮT ĐẦU / DỪNG
    CGFloat startY = statsY + 54 + 10; // ~251
    self.startSummonBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.startSummonBtn.frame = CGRectMake(14, startY, w - 28, 44);
    self.startSummonBtn.layer.cornerRadius = 11;
    self.startSummonBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.72 blue:0.58 alpha:1.0];
    [self.startSummonBtn setTitle:@"BẮT ĐẦU" forState:UIControlStateNormal];
    self.startSummonBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.startSummonBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.startSummonBtn addTarget:self action:@selector(onStartSummonToggle) forControlEvents:UIControlEventTouchUpInside];

    [self.tabSummonView addSubview:self.startSummonBtn];

    // Nút Đặt lại bộ đếm
    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    resetBtn.frame = CGRectMake(14, startY + 44 + 6, w - 28, 24);
    [resetBtn setTitle:@"Đặt lại bộ đếm" forState:UIControlStateNormal];
    resetBtn.tintColor = [UIColor grayColor];
    resetBtn.titleLabel.font = [UIFont systemFontOfSize:11];
    [resetBtn addTarget:self action:@selector(resetSummonCount) forControlEvents:UIControlEventTouchUpInside];
    [self.tabSummonView addSubview:resetBtn];
}

- (void)onFactionBtnClicked:(UIButton *)btn {
    self.selectedFaction = (HeroFactionEnum)btn.tag;
    [self updateFactionButtonsState];
}

- (void)updateFactionButtonsState {
    for (UIButton *b in self.factionButtons) {
        if (b.tag == self.selectedFaction) {
            b.layer.borderColor = [UIColor cyanColor].CGColor;
            b.layer.borderWidth = 2.0;
            b.backgroundColor = [UIColor colorWithRed:0.2 green:0.28 blue:0.52 alpha:1.0];
        } else {
            b.layer.borderColor = [UIColor colorWithWhite:0.28 alpha:1.0].CGColor;
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

        // Nếu đang bật auto spam thì restart timer ngay với tốc độ mới
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
        // Cập nhật lại delay từ ô nhập số trước khi bắt đầu
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

#pragma mark - Tab 2: Extra (Danh Sách Tướng SS)

- (void)setupTabExtra {
    CGFloat w = self.tabExtraView.bounds.size.width;
    CGFloat h = self.tabExtraView.bounds.size.height;

    // 1. Switch tìm nhân vật
    UIView *switchBar = [[UIView alloc] initWithFrame:CGRectMake(12, 6, w - 24, 32)];
    UILabel *swLbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 4, 180, 24)];
    swLbl.text = @"Tìm nhân vật:";
    swLbl.font = [UIFont boldSystemFontOfSize:13];
    swLbl.textColor = [UIColor whiteColor];
    [switchBar addSubview:swLbl];

    self.searchEnabledSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(w - 24 - 55, 0, 50, 30)];
    self.searchEnabledSwitch.on = YES;
    [switchBar addSubview:self.searchEnabledSwitch];
    [self.tabExtraView addSubview:switchBar];

    // 2. Thanh tìm kiếm
    self.searchField = [[UITextField alloc] initWithFrame:CGRectMake(12, 42, w - 24, 32)];
    self.searchField.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    self.searchField.layer.cornerRadius = 8;
    self.searchField.layer.borderColor = [UIColor grayColor].CGColor;
    self.searchField.layer.borderWidth = 0.8;
    self.searchField.textColor = [UIColor whiteColor];
    self.searchField.font = [UIFont systemFontOfSize:12];
    self.searchField.placeholder = @"🔍 Nhập tên tướng SS cần tìm...";
    self.searchField.delegate = self;
    self.searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    [self.searchField addTarget:self action:@selector(onSearchTextChanged:) forControlEvents:UIControlEventEditingChanged];

    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 32)];
    self.searchField.leftView = pad;
    self.searchField.leftViewMode = UITextFieldViewModeAlways;
    [self.tabExtraView addSubview:self.searchField];

    // 3. Label số tướng đã chọn
    self.selectedCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 78, w - 24, 18)];
    self.selectedCountLabel.text = @"Đã chọn: 0 tướng mục tiêu";
    self.selectedCountLabel.font = [UIFont systemFontOfSize:11];
    self.selectedCountLabel.textColor = [UIColor cyanColor];
    [self.tabExtraView addSubview:self.selectedCountLabel];

    // 4. Kết quả tìm kiếm rơi tướng
    self.resultsTextView = [[UITextView alloc] initWithFrame:CGRectMake(12, 98, w - 24, 60)];
    self.resultsTextView.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:0.95];
    self.resultsTextView.layer.cornerRadius = 8;
    self.resultsTextView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.6 alpha:0.6].CGColor;
    self.resultsTextView.layer.borderWidth = 1.0;
    self.resultsTextView.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0];
    self.resultsTextView.font = [UIFont boldSystemFontOfSize:11];
    self.resultsTextView.editable = NO;
    self.resultsTextView.text = @"(Chưa có kết quả rơi tướng mục tiêu)";
    [self.tabExtraView addSubview:self.resultsTextView];

    // 5. TableView danh sách tướng
    CGFloat tableY = 162;
    CGFloat tableH = h - tableY - 8;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(12, tableY, w - 24, tableH) style:UITableViewStylePlain];
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    self.tableView.layer.cornerRadius = 8;
    self.tableView.layer.masksToBounds = YES;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 36;
    self.tableView.separatorColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    [self.tabExtraView addSubview:self.tableView];
}

- (void)onSearchTextChanged:(UITextField *)tf {
    [self filterHeroes];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Database Loader

- (void)loadAllHeroesFromDb {
    if (!gBase) return;

    // DbManager.GetInstance() @ 0x140C030
    typedef void *(*Db_GetInstance_t)(void);
    Db_GetInstance_t getDb = (Db_GetInstance_t)(gBase + OFF_DB_MANAGER_GET_INSTANCE);
    void *db = getDb ? getDb() : NULL;
    if (!db || (uintptr_t)db < 0x100000000ULL) return;

    // m_ListHeroModel ở offset 0x38 (56 decimal)
    void *list = *(void **)((uint8_t *)db + 0x38);
    int32_t count = ILListSize(list);
    if (count <= 0) return;

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
        NSString *name = ILStr(namePtr);
        if (!name.length) continue;

        if ([seen containsObject:name]) continue;
        [seen addObject:name];

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
        it.name = name;
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
    if (!kw.length) {
        self.filteredHeroes = [self.allHeroes copy];
    } else {
        NSPredicate *p = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@", kw];
        self.filteredHeroes = [self.allHeroes filteredArrayUsingPredicate:p];
    }
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
        cell.textLabel.font = [UIFont boldSystemFontOfSize:12];
        cell.detailTextLabel.font = [UIFont boldSystemFontOfSize:10];
    }

    HeroItem *item = self.filteredHeroes[indexPath.row];
    cell.textLabel.text = item.name;

    if (item.quality >= 7) {
        cell.textLabel.textColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.1 alpha:1.0];
        cell.detailTextLabel.textColor = [UIColor orangeColor];
    } else {
        cell.textLabel.textColor = [UIColor whiteColor];
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

    self.selectedCountLabel.text = [NSString stringWithFormat:@"Đã chọn: %lu tướng mục tiêu", (unsigned long)self.selectedHeroNames.count];
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
    NSString *name = ILStr(*(void **)((uint8_t *)hero + 0x28));
    if (!name.length) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL isTarget = [self.selectedHeroNames containsObject:name];

        if (self.searchEnabledSwitch.on) {
            if (!isTarget) return;
        } else {
            if (quality < 6) return;
        }

        NSInteger cur = [self.heroDropCounts[name] integerValue];
        self.heroDropCounts[name] = @(cur + 1);

        [self updateResultsDisplay];
    });
}

- (void)updateResultsDisplay {
    if (!self.heroDropCounts.count) {
        self.resultsTextView.text = @"(Chưa rơi tướng mục tiêu nào)";
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
