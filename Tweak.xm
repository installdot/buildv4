// tweak.xm — Soul Knight Account Manager v6
// iOS 14+ | Theos/Logos | ARC
// Panel has two inline tabs: [Accounts] [Actions]
// Tapping a tab expands/collapses the panel in-place — no modal VCs

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - Keys / Storage

#define kSaved   @"__SKSavedAccounts__"
#define kRemoved @"__SKRemovedAccounts__"

static NSMutableArray *getSaved(void) {
    NSArray *a = [[NSUserDefaults standardUserDefaults] arrayForKey:kSaved];
    return a ? [a mutableCopy] : [NSMutableArray new];
}
static void writeSaved(NSArray *a) {
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:kSaved];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
static NSMutableArray *getRemoved(void) {
    NSArray *a = [[NSUserDefaults standardUserDefaults] arrayForKey:kRemoved];
    return a ? [a mutableCopy] : [NSMutableArray new];
}
static void writeRemoved(NSArray *a) {
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:kRemoved];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
static NSDictionary *parseLine(NSString *line) {
    NSArray *p = [line componentsSeparatedByString:@"|"];
    if (p.count < 4) return nil;
    return @{
        @"email": [p[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet],
        @"pass" : [p[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet],
        @"uid"  : [p[2] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet],
        @"token": [p[3] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
    };
}

#pragma mark - Account Switch

static void applyAccount(NSDictionary *acc) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *newToken = acc[@"token"];
    NSString *newUid   = acc[@"uid"];
    NSString *newEmail = acc[@"email"];

    NSString *oldPlayerId = @"";
    NSString *raw = [ud stringForKey:@"SdkStateCache#1"];
    if (raw) {
        NSError *rxErr = nil;
        NSRegularExpression *idRx = [NSRegularExpression
            regularExpressionWithPattern:@"\"PlayerId\"\\s*:\\s*(\\d+)"
            options:0 error:&rxErr];
        if (!rxErr) {
            NSTextCheckingResult *m = [idRx firstMatchInString:raw options:0
                                                         range:NSMakeRange(0, raw.length)];
            if (m && m.numberOfRanges > 1)
                oldPlayerId = [raw substringWithRange:[m rangeAtIndex:1]];
        }
        NSError *err = nil;
        NSMutableDictionary *root = [[NSJSONSerialization
            JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding]
            options:NSJSONReadingMutableContainers error:&err] mutableCopy];
        if (!err && root) {
            NSMutableDictionary *user    = [root[@"User"]    mutableCopy] ?: [NSMutableDictionary new];
            NSMutableDictionary *session = [root[@"Session"] mutableCopy] ?: [NSMutableDictionary new];
            NSMutableDictionary *legacy  = [user[@"LegacyGateway"] mutableCopy] ?: [NSMutableDictionary new];
            legacy[@"token"]       = newToken;
            user[@"LegacyGateway"] = legacy;
            user[@"Email"]         = newEmail;
            user[@"PlayerId"]      = @([newUid longLongValue]);
            session[@"Token"]      = newToken;
            root[@"User"]          = user;
            root[@"Session"]       = session;
            NSData *out = [NSJSONSerialization dataWithJSONObject:root
                options:NSJSONWritingPrettyPrinted error:&err];
            if (!err && out)
                raw = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
        }
        [ud setObject:raw forKey:@"SdkStateCache#1"];
    }

    // Replace old PlayerId across all NSUserDefaults string values
    if (oldPlayerId.length > 0 && ![oldPlayerId isEqualToString:@"0"]) {
        NSDictionary *all = [ud dictionaryRepresentation];
        for (NSString *key in all) {
            id val = all[key];
            if (![val isKindOfClass:[NSString class]]) continue;
            NSString *s = (NSString *)val;
            if (![s containsString:oldPlayerId]) continue;
            [ud setObject:[s stringByReplacingOccurrencesOfString:oldPlayerId withString:newUid]
                   forKey:key];
        }
    }
    [ud synchronize];

    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *t in @[@"bp_data",@"item_data",@"misc_data",
                          @"season_data",@"statistic_data",@"weapon_evolution_data"]) {
        NSString *src = [docs stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"%@_1_.data", t]];
        NSString *dst = [docs stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"%@_%@_.data", t, newUid]];
        if ([fm fileExistsAtPath:src]) {
            [fm removeItemAtPath:dst error:nil];
            [fm copyItemAtPath:src toPath:dst error:nil];
        }
    }
}

#pragma mark - Unlock (NSUserDefaults)

static int runUnlockInDefaults(NSString *type) {
    NSUserDefaults *ud  = [NSUserDefaults standardUserDefaults];
    NSDictionary   *all = [ud dictionaryRepresentation];
    NSString *pattern, *tmpl;

    if ([type isEqualToString:@"Characters"]) {
        pattern = @"(\"\\d+_c\\d+_unlock[^\"]*\"\\s*:\\s*)false";
        tmpl    = @"${1}true";
    } else if ([type isEqualToString:@"Skins"]) {
        pattern = @"(\"\\d+_c\\d+_skin\\d+[^\"]*\"\\s*:\\s*)[+-]?\\d+";
        tmpl    = @"${1}1";
    } else if ([type isEqualToString:@"Skills"]) {
        pattern = @"(\"\\d+_c_[^\"]*_skill_\\d_unlock[^\"]*\"\\s*:\\s*)\\d";
        tmpl    = @"${1}1";
    } else if ([type isEqualToString:@"Pets"]) {
        pattern = @"(\"\\d+_p\\d+_unlock[^\"]*\"\\s*:\\s*)false";
        tmpl    = @"${1}true";
    } else {
        return 0;
    }

    NSError *rxErr = nil;
    NSRegularExpression *rx = [NSRegularExpression
        regularExpressionWithPattern:pattern
        options:NSRegularExpressionDotMatchesLineSeparators
        error:&rxErr];
    if (rxErr || !rx) return 0;

    int changed = 0;
    for (NSString *key in all) {
        id val = all[key];
        if (![val isKindOfClass:[NSString class]]) continue;
        NSString *s = (NSString *)val;
        NSArray *matches = [rx matchesInString:s options:0 range:NSMakeRange(0, s.length)];
        if (!matches.count) continue;
        NSMutableString *ms = [s mutableCopy];
        for (NSTextCheckingResult *m in matches.reverseObjectEnumerator) {
            NSString *rep = [rx replacementStringForResult:m
                                                  inString:ms offset:0 template:tmpl];
            [ms replaceCharactersInRange:m.range withString:rep];
        }
        if (![ms isEqualToString:s]) {
            [ud setObject:ms forKey:key];
            changed++;
        }
    }
    [ud synchronize];
    return changed;
}

#pragma mark - Unlock Sheet (custom overlay, no UIAlertController)

@interface SKUnlockSheet : UIView
+ (void)showInView:(UIView *)parentView onDone:(void(^)(void))doneBlock;
@end

@implementation SKUnlockSheet {
    UIView *_card;
    UILabel *_statusLabel;
    UIActivityIndicatorView *_spinner;
    void (^_doneBlock)(void);
}

+ (void)showInView:(UIView *)parentView onDone:(void(^)(void))doneBlock {
    SKUnlockSheet *sheet = [[SKUnlockSheet alloc] initWithFrame:parentView.bounds];
    sheet->_doneBlock = doneBlock;
    sheet.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [parentView addSubview:sheet];
    sheet.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ sheet.alpha = 1; }];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(dismiss)];
    tap.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tap];

    _card = [[UIView alloc] init];
    _card.backgroundColor     = [UIColor colorWithRed:0.10 green:0.10 blue:0.13 alpha:1];
    _card.layer.cornerRadius  = 14;
    _card.layer.shadowColor   = UIColor.blackColor.CGColor;
    _card.layer.shadowOpacity = 0.7;
    _card.layer.shadowRadius  = 12;
    _card.layer.shadowOffset  = CGSizeMake(0, 4);
    _card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_card];

    UIView *guard = [[UIView alloc] init];
    guard.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:guard];
    [guard addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(cardTapped)]];

    UILabel *title = [UILabel new];
    title.text = @"Unlock";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:title];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [closeBtn setTitle:@"X" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithWhite:0.65 alpha:1] forState:UIControlStateNormal];
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateHighlighted];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [closeBtn addTarget:self action:@selector(dismiss)
       forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:closeBtn];

    NSArray *types  = @[@"Characters", @"Skins", @"Skills", @"Pets"];
    NSArray *colors = @[
        [UIColor colorWithRed:0.18 green:0.52 blue:1.00 alpha:1],
        [UIColor colorWithRed:0.18 green:0.76 blue:0.38 alpha:1],
        [UIColor colorWithRed:1.00 green:0.46 blue:0.16 alpha:1],
        [UIColor colorWithRed:0.72 green:0.22 blue:0.90 alpha:1]
    ];
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis    = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:stack];
    for (NSUInteger i = 0; i < types.count; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        [btn setTitle:types[i] forState:UIControlStateNormal];
        [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor colorWithWhite:0.75 alpha:1]
                  forState:UIControlStateHighlighted];
        btn.backgroundColor    = colors[i];
        btn.titleLabel.font    = [UIFont boldSystemFontOfSize:14];
        btn.layer.cornerRadius = 9;
        btn.tag = (NSInteger)i;
        [btn addTarget:self action:@selector(typeTapped:)
      forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:btn];
        [btn.heightAnchor constraintEqualToConstant:46].active = YES;
    }

    _statusLabel = [UILabel new];
    _statusLabel.text          = @"";
    _statusLabel.textColor     = [UIColor colorWithRed:0.4 green:1 blue:0.55 alpha:1];
    _statusLabel.font          = [UIFont systemFontOfSize:12];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.numberOfLines = 0;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:_statusLabel];

    _spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color = UIColor.whiteColor;
    _spinner.hidesWhenStopped = YES;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:_spinner];

    [NSLayoutConstraint activateConstraints:@[
        [guard.topAnchor    constraintEqualToAnchor:_card.topAnchor],
        [guard.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor],
        [guard.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor],
        [guard.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor],
        [_card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_card.widthAnchor constraintEqualToConstant:270],
        [title.topAnchor constraintEqualToAnchor:_card.topAnchor constant:18],
        [title.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor  constant:44],
        [title.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-44],
        [closeBtn.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [closeBtn.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-14],
        [closeBtn.widthAnchor  constraintEqualToConstant:32],
        [closeBtn.heightAnchor constraintEqualToConstant:32],
        [stack.topAnchor     constraintEqualToAnchor:title.bottomAnchor constant:16],
        [stack.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor  constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-16],
        [_statusLabel.topAnchor     constraintEqualToAnchor:stack.bottomAnchor constant:12],
        [_statusLabel.leadingAnchor  constraintEqualToAnchor:_card.leadingAnchor  constant:12],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-12],
        [_spinner.topAnchor      constraintEqualToAnchor:_statusLabel.bottomAnchor constant:8],
        [_spinner.centerXAnchor  constraintEqualToAnchor:_card.centerXAnchor],
        [_card.bottomAnchor constraintEqualToAnchor:_spinner.bottomAnchor constant:20],
    ]];
    return self;
}

- (void)cardTapped {}

- (void)typeTapped:(UIButton *)sender {
    NSArray *types = @[@"Characters", @"Skins", @"Skills", @"Pets"];
    if (sender.tag >= (NSInteger)types.count) return;
    NSString *type = types[sender.tag];
    _statusLabel.text = @"Running...";
    _statusLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1];
    [_spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int n = runUnlockInDefaults(type);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_spinner stopAnimating];
            if (n > 0) {
                self->_statusLabel.textColor =
                    [UIColor colorWithRed:0.4 green:1 blue:0.55 alpha:1];
                self->_statusLabel.text = [NSString stringWithFormat:
                    @"Modified %d key(s).\nRestart app to apply.", n];
            } else {
                self->_statusLabel.textColor =
                    [UIColor colorWithRed:1 green:0.5 blue:0.35 alpha:1];
                self->_statusLabel.text =
                    @"No matching keys found.\nLaunch the game at least once first.";
            }
        });
    });
}

- (void)dismiss {
    [UIView animateWithDuration:0.18 animations:^{ self.alpha = 0; }
                     completion:^(BOOL _) {
        if (self->_doneBlock) self->_doneBlock();
        [self removeFromSuperview];
    }];
}

@end

#pragma mark - SKPanel (tabbed, no modal)

typedef NS_ENUM(NSInteger, SKPanelTab) {
    SKPanelTabNone     = 0,
    SKPanelTabAccounts = 1,
    SKPanelTabActions  = 2,
};

static const CGFloat kPanelWidth       = 282;
static const CGFloat kTabBarHeight     = 44;
static const CGFloat kAccountsContentH = 330;
static const CGFloat kActionsContentH  = 200;

@interface SKPanel : UIView <UITableViewDataSource, UITableViewDelegate>
// Tab bar buttons
@property (nonatomic, strong) UIButton    *tabAccounts;
@property (nonatomic, strong) UIButton    *tabActions;
// Accounts pane
@property (nonatomic, strong) UIView      *accountsPane;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextView  *tv;
// Actions pane
@property (nonatomic, strong) UIView      *actionsPane;
@property (nonatomic, strong) UILabel     *infoLabel;
// State
@property (nonatomic, assign) SKPanelTab  activeTab;
@property (nonatomic, assign) CGPoint     preKeyboardCenter;
@property (nonatomic, assign) BOOL        keyboardVisible;
@end

@implementation SKPanel

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, kPanelWidth, kTabBarHeight)];
    if (!self) return nil;

    self.clipsToBounds      = NO;
    self.layer.cornerRadius = 12;
    self.backgroundColor    = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:0.96];
    self.layer.shadowColor   = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.75;
    self.layer.shadowRadius  = 8;
    self.layer.shadowOffset  = CGSizeMake(0, 3);
    self.layer.zPosition     = 9999;

    [self buildTabBar];
    [self buildAccountsPane];
    [self buildActionsPane];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(onPan:)];
    [self addGestureRecognizer:pan];

    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(keyboardWillShow:)
               name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(keyboardWillHide:)
               name:UIKeyboardWillHideNotification object:nil];

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

// ── Tab bar ──────────────────────────────────────────────────────────────

- (void)buildTabBar {
    // Small drag-handle hint
    UIView *handle = [[UIView alloc]
        initWithFrame:CGRectMake(kPanelWidth / 2 - 20, 5, 40, 3)];
    handle.backgroundColor    = [UIColor colorWithWhite:0.5 alpha:0.45];
    handle.layer.cornerRadius = 1.5;
    [self addSubview:handle];

    CGFloat btnW = (kPanelWidth - 2) / 2.0;
    CGFloat btnH = kTabBarHeight - 10;
    CGFloat btnY = (kTabBarHeight - btnH) / 2.0;

    self.tabAccounts = [self makeTabBtn:@"Accounts"
                                  frame:CGRectMake(1, btnY, btnW, btnH)];
    self.tabActions  = [self makeTabBtn:@"Actions"
                                  frame:CGRectMake(1 + btnW, btnY, btnW, btnH)];

    [self.tabAccounts addTarget:self action:@selector(tapTabAccounts)
               forControlEvents:UIControlEventTouchUpInside];
    [self.tabActions  addTarget:self action:@selector(tapTabActions)
               forControlEvents:UIControlEventTouchUpInside];

    [self addSubview:self.tabAccounts];
    [self addSubview:self.tabActions];
}

- (UIButton *)makeTabBtn:(NSString *)title frame:(CGRect)frame {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = frame;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:0.60 alpha:1] forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateHighlighted];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    b.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1];
    b.layer.cornerRadius = 7;
    return b;
}

- (void)tapTabAccounts {
    if (self.activeTab == SKPanelTabAccounts) [self collapse];
    else [self switchToTab:SKPanelTabAccounts];
}
- (void)tapTabActions {
    if (self.activeTab == SKPanelTabActions) [self collapse];
    else [self switchToTab:SKPanelTabActions];
}

- (void)switchToTab:(SKPanelTab)tab {
    [self.tv resignFirstResponder];
    self.activeTab = tab;
    [self updateTabHighlight];

    CGFloat targetH;
    UIView *show, *hide;

    if (tab == SKPanelTabAccounts) {
        targetH = kTabBarHeight + kAccountsContentH;
        show = self.accountsPane;
        hide = self.actionsPane;
        [self.table reloadData];
    } else {
        targetH = kTabBarHeight + kActionsContentH;
        show = self.actionsPane;
        hide = self.accountsPane;
        [self refreshInfo];
    }

    hide.hidden = YES;
    hide.alpha  = 0;
    show.hidden = NO;
    show.frame  = CGRectMake(0, kTabBarHeight, kPanelWidth, targetH - kTabBarHeight);

    [UIView animateWithDuration:0.22 delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        CGRect f = self.frame;
        f.size.height = targetH;
        self.frame = f;
        show.alpha = 1;
    } completion:nil];
}

- (void)collapse {
    [self.tv resignFirstResponder];
    self.activeTab = SKPanelTabNone;
    [self updateTabHighlight];

    UIView *pane = (self.accountsPane.alpha > 0) ? self.accountsPane : self.actionsPane;
    [UIView animateWithDuration:0.18 delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        CGRect f = self.frame;
        f.size.height = kTabBarHeight;
        self.frame = f;
        pane.alpha = 0;
    } completion:^(BOOL _) {
        pane.hidden = YES;
        self.accountsPane.alpha = 0;
        self.actionsPane.alpha  = 0;
    }];
}

- (void)updateTabHighlight {
    UIColor *on   = [UIColor colorWithRed:0.18 green:0.45 blue:0.90 alpha:1];
    UIColor *off  = [UIColor colorWithWhite:0.16 alpha:1];
    UIColor *textOn  = UIColor.whiteColor;
    UIColor *textOff = [UIColor colorWithWhite:0.58 alpha:1];

    BOOL accOn = (self.activeTab == SKPanelTabAccounts);
    BOOL actOn = (self.activeTab == SKPanelTabActions);

    self.tabAccounts.backgroundColor = accOn ? on : off;
    self.tabActions.backgroundColor  = actOn ? on : off;
    [self.tabAccounts setTitleColor:accOn ? textOn : textOff forState:UIControlStateNormal];
    [self.tabActions  setTitleColor:actOn ? textOn : textOff forState:UIControlStateNormal];
}

// ── Accounts pane ────────────────────────────────────────────────────────

- (void)buildAccountsPane {
    self.accountsPane = [[UIView alloc]
        initWithFrame:CGRectMake(0, kTabBarHeight, kPanelWidth, kAccountsContentH)];
    self.accountsPane.hidden = YES;
    self.accountsPane.alpha  = 0;
    self.accountsPane.clipsToBounds = YES;
    [self addSubview:self.accountsPane];

    UIView  *p   = self.accountsPane;
    CGFloat pad  = 8;
    CGFloat w    = kPanelWidth - pad * 2;

    // Saved accounts table
    self.table = [[UITableView alloc]
        initWithFrame:CGRectMake(pad, 6, w, 140) style:UITableViewStylePlain];
    self.table.dataSource       = self;
    self.table.delegate         = self;
    self.table.backgroundColor  = [UIColor colorWithWhite:0.12 alpha:1];
    self.table.separatorColor   = [UIColor colorWithWhite:0.22 alpha:1];
    self.table.layer.cornerRadius = 7;
    self.table.clipsToBounds    = YES;
    [p addSubview:self.table];

    // Hint
    UILabel *hint = [UILabel new];
    hint.text = @"email|pass|uid|token  (one per line)";
    hint.textColor = [UIColor colorWithWhite:0.42 alpha:1];
    hint.font = [UIFont systemFontOfSize:10];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.frame = CGRectMake(pad, 152, w, 14);
    [p addSubview:hint];

    // Text view — scrollable input
    self.tv = [UITextView new];
    self.tv.backgroundColor        = [UIColor colorWithWhite:0.15 alpha:1];
    self.tv.textColor              = [UIColor colorWithRed:0.4 green:1 blue:0.55 alpha:1];
    self.tv.font                   = [UIFont fontWithName:@"Courier" size:11]
                                     ?: [UIFont systemFontOfSize:11];
    self.tv.layer.cornerRadius     = 7;
    self.tv.autocorrectionType     = UITextAutocorrectionTypeNo;
    self.tv.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.tv.scrollEnabled          = YES;
    self.tv.frame                  = CGRectMake(pad, 170, w, 108);
    [p addSubview:self.tv];

    // Keyboard toolbar
    UIToolbar *bar = [[UIToolbar alloc]
        initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 44)];
    bar.barStyle  = UIBarStyleBlack;
    bar.translucent = YES;
    UIBarButtonItem *flex = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                             target:nil action:nil];
    UIBarButtonItem *doneKb = [[UIBarButtonItem alloc]
        initWithTitle:@"Done" style:UIBarButtonItemStyleDone
               target:self action:@selector(dismissKeyboard)];
    doneKb.tintColor = [UIColor colorWithRed:0.4 green:0.8 blue:1 alpha:1];
    bar.items = @[flex, doneKb];
    self.tv.inputAccessoryView = bar;

    // Save button
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [saveBtn setTitle:@"Save Accounts" forState:UIControlStateNormal];
    [saveBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    saveBtn.titleLabel.font  = [UIFont boldSystemFontOfSize:13];
    saveBtn.backgroundColor  = [UIColor colorWithRed:0.18 green:0.65 blue:0.38 alpha:1];
    saveBtn.layer.cornerRadius = 8;
    saveBtn.frame = CGRectMake(pad, 284, w, 38);
    [saveBtn addTarget:self action:@selector(doSave)
      forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:saveBtn];
}

// UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    NSUInteger c = getSaved().count;
    return c == 0 ? 1 : (NSInteger)c;
}
- (UITableViewCell *)tableView:(UITableView *)tv
         cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"c"];
    cell.backgroundColor           = [UIColor colorWithWhite:0.12 alpha:1];
    cell.textLabel.textColor       = UIColor.whiteColor;
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.48 alpha:1];
    cell.textLabel.font            = [UIFont systemFontOfSize:12];
    cell.detailTextLabel.font      = [UIFont systemFontOfSize:10];

    NSMutableArray *list = getSaved();
    if (list.count == 0) {
        cell.textLabel.text       = @"No saved accounts";
        cell.detailTextLabel.text = @"";
        cell.userInteractionEnabled = NO;
    } else {
        NSDictionary *a = list[ip.row];
        cell.textLabel.text = a[@"email"];
        NSString *tok = a[@"token"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"uid: %@  token: %@...",
            a[@"uid"], [tok substringToIndex:MIN((NSUInteger)10, tok.length)]];
        cell.userInteractionEnabled = YES;
    }
    return cell;
}
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    return 34;
}
// Swipe-to-delete
- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    return getSaved().count > 0;
}
- (UITableViewCellEditingStyle)tableView:(UITableView *)tv
           editingStyleForRowAtIndexPath:(NSIndexPath *)ip {
    return getSaved().count > 0
        ? UITableViewCellEditingStyleDelete
        : UITableViewCellEditingStyleNone;
}
- (void)tableView:(UITableView *)tv
commitEditingStyle:(UITableViewCellEditingStyle)es
forRowAtIndexPath:(NSIndexPath *)ip {
    if (es != UITableViewCellEditingStyleDelete) return;
    NSMutableArray *list = getSaved();
    if (ip.row >= (NSInteger)list.count) return;
    [list removeObjectAtIndex:ip.row];
    writeSaved(list);
    if (list.count == 0)
        [tv reloadData];
    else
        [tv deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)dismissKeyboard { [self.tv resignFirstResponder]; }

- (void)doSave {
    NSMutableArray *list = getSaved();
    NSUInteger before = list.count;
    for (NSString *line in [self.tv.text
            componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *t = [line stringByTrimmingCharactersInSet:
                       NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!t.length) continue;
        NSDictionary *a = parseLine(t);
        if (!a) continue;
        BOOL dup = NO;
        for (NSDictionary *e in list)
            if ([e[@"uid"] isEqualToString:a[@"uid"]]) { dup = YES; break; }
        if (!dup) [list addObject:a];
    }
    writeSaved(list);
    self.tv.text = @"";
    [self.tv resignFirstResponder];
    [self.table reloadData];
    NSUInteger added = list.count - before;
    [self showToast:[NSString stringWithFormat:
        @"Added %lu  |  Total: %lu", (unsigned long)added, (unsigned long)list.count]
            success:YES exit:NO];
}

// ── Actions pane ─────────────────────────────────────────────────────────

- (void)buildActionsPane {
    self.actionsPane = [[UIView alloc]
        initWithFrame:CGRectMake(0, kTabBarHeight, kPanelWidth, kActionsContentH)];
    self.actionsPane.hidden = YES;
    self.actionsPane.alpha  = 0;
    self.actionsPane.clipsToBounds = YES;
    [self addSubview:self.actionsPane];

    UIView  *p   = self.actionsPane;
    CGFloat pad  = 8;
    CGFloat w    = kPanelWidth - pad * 2;

    // Info label
    self.infoLabel = [UILabel new];
    self.infoLabel.frame         = CGRectMake(pad, 8, w, 14);
    self.infoLabel.textColor     = [UIColor colorWithWhite:0.55 alpha:1];
    self.infoLabel.font          = [UIFont systemFontOfSize:10];
    self.infoLabel.textAlignment = NSTextAlignmentCenter;
    [p addSubview:self.infoLabel];
    [self refreshInfo];

    NSArray *titles = @[@"Edit  (apply random)", @"Export used accounts", @"Unlock..."];
    NSArray *colors = @[
        [UIColor colorWithRed:0.18 green:0.72 blue:0.38 alpha:1],
        [UIColor colorWithRed:1.00 green:0.46 blue:0.16 alpha:1],
        [UIColor colorWithRed:0.70 green:0.20 blue:0.90 alpha:1]
    ];
    SEL sels[3] = { @selector(tapEdit), @selector(tapExport), @selector(tapUnlock) };

    for (int i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(pad, 28 + i * 52, w, 44);
        b.backgroundColor = colors[i];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [b setTitleColor:[UIColor colorWithWhite:0.80 alpha:1] forState:UIControlStateHighlighted];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        b.layer.cornerRadius = 9;
        [b addTarget:self action:sels[i] forControlEvents:UIControlEventTouchUpInside];
        [p addSubview:b];
    }
}

- (void)refreshInfo {
    NSUInteger saved   = getSaved().count;
    NSUInteger exports = getRemoved().count;
    self.infoLabel.text = [NSString stringWithFormat:@"Saved: %lu     Export ready: %lu",
                           (unsigned long)saved, (unsigned long)exports];
}

// ── Action handlers ──────────────────────────────────────────────────────

- (void)tapEdit {
    NSMutableArray *list = getSaved();
    if (!list.count) {
        [self showToast:@"No accounts saved.\nUse Accounts tab to add some."
                success:NO exit:NO];
        return;
    }
    NSUInteger idx    = arc4random_uniform((uint32_t)list.count);
    NSDictionary *acc = list[idx];
    NSMutableArray *rem = getRemoved();
    [list removeObjectAtIndex:idx];
    [rem addObject:acc];
    writeSaved(list);
    writeRemoved(rem);
    applyAccount(acc);
    [self refreshInfo];

    NSString *tok = acc[@"token"];
    NSString *msg = [NSString stringWithFormat:
        @"Applied\n\nEmail : %@\nUID   : %@\nToken : %@...\n\nIDs replaced globally\nNSUserDefaults patched\nSave files backed up\n\nRemaining: %lu\nClosing app...",
        acc[@"email"], acc[@"uid"],
        [tok substringToIndex:MIN((NSUInteger)10, tok.length)],
        (unsigned long)list.count];
    [self showToast:msg success:YES exit:YES];
}

- (void)tapExport {
    NSMutableArray *rem = getRemoved();
    if (!rem.count) {
        [self showToast:@"Nothing to export.\nUse Edit first." success:NO exit:NO];
        return;
    }
    NSMutableString *out = [NSMutableString new];
    for (NSDictionary *a in rem)
        [out appendFormat:@"%@|%@\n", a[@"email"], a[@"pass"]];
    [UIPasteboard generalPasteboard].string = out;
    writeRemoved(@[]);
    [self refreshInfo];
    [self showToast:[NSString stringWithFormat:
        @"Copied %lu account(s) to clipboard.", (unsigned long)rem.count]
            success:YES exit:NO];
}

- (void)tapUnlock {
    UIView *root = [self topVC].view ?: self.superview;
    [SKUnlockSheet showInView:root onDone:^{ [self refreshInfo]; }];
}

// ── Toast ────────────────────────────────────────────────────────────────

- (void)showToast:(NSString *)msg success:(BOOL)success exit:(BOOL)ex {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *parent = self.superview ?: [self topVC].view;

        UILabel *toast = [UILabel new];
        toast.text            = msg;
        toast.textColor       = UIColor.whiteColor;
        toast.font            = [UIFont systemFontOfSize:12];
        toast.backgroundColor = success
            ? [UIColor colorWithRed:0.08 green:0.20 blue:0.10 alpha:0.97]
            : [UIColor colorWithRed:0.20 green:0.08 blue:0.08 alpha:0.97];
        toast.layer.cornerRadius = 10;
        toast.layer.borderColor  = (success
            ? [UIColor colorWithRed:0.28 green:0.78 blue:0.38 alpha:0.5]
            : [UIColor colorWithRed:0.78 green:0.28 blue:0.28 alpha:0.5]).CGColor;
        toast.layer.borderWidth = 1;
        toast.clipsToBounds     = YES;
        toast.numberOfLines     = 0;
        toast.textAlignment     = NSTextAlignmentCenter;
        toast.translatesAutoresizingMaskIntoConstraints = NO;

        [parent addSubview:toast];
        [NSLayoutConstraint activateConstraints:@[
            [toast.centerXAnchor constraintEqualToAnchor:parent.centerXAnchor],
            [toast.centerYAnchor constraintEqualToAnchor:parent.centerYAnchor],
            [toast.widthAnchor constraintLessThanOrEqualToAnchor:parent.widthAnchor constant:-40],
        ]];

        NSTimeInterval delay = ex ? 2.8 : 1.8;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{ toast.alpha = 0; }
                             completion:^(BOOL _) {
                [toast removeFromSuperview];
                if (ex) exit(0);
            }];
        });
    });
}

// ── Keyboard avoidance ───────────────────────────────────────────────────

- (void)keyboardWillShow:(NSNotification *)n {
    if (!self.tv.isFirstResponder) return;
    if (self.keyboardVisible) return;
    self.keyboardVisible   = YES;
    self.preKeyboardCenter = self.center;

    CGRect kbFrame = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval dur = [n.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    NSInteger rawCurve = [n.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    UIViewAnimationOptions opts = (UIViewAnimationOptions)(rawCurve << 16)
                                | UIViewAnimationOptionBeginFromCurrentState;

    CGFloat panelBottom = self.frame.origin.y + self.frame.size.height;
    CGFloat overlap     = panelBottom - kbFrame.origin.y + 10;
    if (overlap <= 0) return;

    CGPoint newCenter = CGPointMake(self.center.x, self.center.y - overlap);
    [UIView animateWithDuration:dur delay:0 options:opts animations:^{
        self.center = newCenter;
    } completion:nil];
}

- (void)keyboardWillHide:(NSNotification *)n {
    if (!self.keyboardVisible) return;
    self.keyboardVisible = NO;
    NSTimeInterval dur = [n.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    NSInteger rawCurve = [n.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    UIViewAnimationOptions opts = (UIViewAnimationOptions)(rawCurve << 16)
                                | UIViewAnimationOptionBeginFromCurrentState;
    CGPoint restore = self.preKeyboardCenter;
    [UIView animateWithDuration:dur delay:0 options:opts animations:^{
        self.center = restore;
    } completion:nil];
}

// ── Drag ─────────────────────────────────────────────────────────────────

- (void)onPan:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan)
        [self.tv resignFirstResponder];
    CGPoint d  = [g translationInView:self.superview];
    CGRect  sb = self.superview.bounds;
    CGFloat nx = MAX(self.bounds.size.width  / 2,
                     MIN(sb.size.width  - self.bounds.size.width  / 2, self.center.x + d.x));
    CGFloat ny = MAX(self.bounds.size.height / 2,
                     MIN(sb.size.height - self.bounds.size.height / 2, self.center.y + d.y));
    self.center = CGPointMake(nx, ny);
    [g setTranslation:CGPointZero inView:self.superview];
}

// ── Top VC ───────────────────────────────────────────────────────────────

- (UIViewController *)topVC {
    UIViewController *vc = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows.reverseObjectEnumerator)
        if (!w.isHidden && w.alpha > 0 && w.rootViewController) { vc = w.rootViewController; break; }
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

@end

#pragma mark - Injection

static SKPanel *gPanel = nil;

static void injectPanel(void) {
    UIWindow *win = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows)
        if (!w.isHidden && w.alpha > 0) { win = w; break; }
    if (!win) return;
    UIView *root = win.rootViewController.view ?: win;

    gPanel = [SKPanel new];
    CGFloat sw = root.bounds.size.width;
    gPanel.center = CGPointMake(sw - gPanel.bounds.size.width / 2 - 8, 80);
    [root addSubview:gPanel];
    [root bringSubviewToFront:gPanel];
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            injectPanel();
        });
    });
}
%end
