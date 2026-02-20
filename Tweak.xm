// tweak.xm — Soul Knight Account Manager v6
// iOS 14+ | Theos/Logos | ARC
// Panel has two inline tabs: [Accounts] [Actions]
// Tapping a tab expands/collapses the panel in-place — no modal VCs

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// UIButton block-based tap handler (avoids target/selector boilerplate for inline closures)
@interface UIButton (SKActionBlock)
- (void)sk_setActionBlock:(void(^)(void))block;
@end

@implementation UIButton (SKActionBlock)
static char kSKActionBlockKey;
- (void)sk_setActionBlock:(void(^)(void))block {
    objc_setAssociatedObject(self, &kSKActionBlockKey,
        [block copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self removeTarget:self action:@selector(sk_invokeActionBlock)
      forControlEvents:UIControlEventTouchUpInside];
    [self addTarget:self action:@selector(sk_invokeActionBlock)
   forControlEvents:UIControlEventTouchUpInside];
}
- (void)sk_invokeActionBlock {
    void (^block)(void) = objc_getAssociatedObject(self, &kSKActionBlockKey);
    if (block) block();
}
@end

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

    // Serialize ALL of NSUserDefaults to plist XML text, replace every occurrence
    // of the old player ID (in both keys and values of any type), then parse back
    // and write every changed or renamed key back into NSUserDefaults.
    if (oldPlayerId.length > 0 && ![oldPlayerId isEqualToString:@"0"]) {
        NSDictionary *snapshot = [ud dictionaryRepresentation];

        NSError *serErr = nil;
        NSData *plistData = [NSPropertyListSerialization
            dataWithPropertyList:snapshot
            format:NSPropertyListXMLFormat_v1_0
            options:0 error:&serErr];

        if (!serErr && plistData) {
            NSString *xml = [[NSString alloc] initWithData:plistData
                                                  encoding:NSUTF8StringEncoding];
            NSString *patched = [xml stringByReplacingOccurrencesOfString:oldPlayerId
                                                               withString:newUid];
            if (![patched isEqualToString:xml]) {
                NSError *parseErr = nil;
                NSDictionary *newSnap = [NSPropertyListSerialization
                    propertyListWithData:[patched dataUsingEncoding:NSUTF8StringEncoding]
                    options:NSPropertyListMutableContainersAndLeaves
                    format:nil error:&parseErr];

                if (!parseErr && newSnap) {
                    // Remove keys whose names contained the old ID (they get re-added below
                    // under the new name from newSnap)
                    for (NSString *oldKey in snapshot) {
                        if ([oldKey containsString:oldPlayerId]) {
                            [ud removeObjectForKey:oldKey];
                        }
                    }
                    // Write all keys that are new or changed
                    for (NSString *key in newSnap) {
                        id oldVal = snapshot[key];
                        id newVal = newSnap[key];
                        if (!oldVal || ![oldVal isEqual:newVal]) {
                            [ud setObject:newVal forKey:key];
                        }
                    }
                }
            }
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

#pragma mark - SKPanel (tabbed, no modal)

typedef NS_ENUM(NSInteger, SKPanelTab) {
    SKPanelTabNone     = 0,
    SKPanelTabAccounts = 1,
    SKPanelTabActions  = 2,
};

static const CGFloat kPanelWidth       = 282;
static const CGFloat kTabBarHeight     = 44;
static const CGFloat kAccountsContentH = 330;
static const CGFloat kActionsContentH  = 148;

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

// Row tap — show inline Apply / Remove action card
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSMutableArray *list = getSaved();
    if (ip.row >= (NSInteger)list.count) return;
    NSDictionary *acc = list[ip.row];
    [self showAccountActionForAccount:acc atRow:ip.row];
}

- (void)showAccountActionForAccount:(NSDictionary *)acc atRow:(NSInteger)row {
    // Build a small floating card anchored on the panel's superview
    UIView *parent = self.superview ?: [self topVC].view;
    if (!parent) return;

    // Dim backdrop — tap to dismiss
    UIView *backdrop = [[UIView alloc] initWithFrame:parent.bounds];
    backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [parent addSubview:backdrop];

    // Card
    UIView *card = [[UIView alloc] init];
    card.backgroundColor     = [UIColor colorWithRed:0.10 green:0.10 blue:0.14 alpha:1];
    card.layer.cornerRadius  = 12;
    card.layer.shadowColor   = UIColor.blackColor.CGColor;
    card.layer.shadowOpacity = 0.65;
    card.layer.shadowRadius  = 10;
    card.layer.shadowOffset  = CGSizeMake(0, 4);
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview:card];

    // Header — email
    UILabel *header = [UILabel new];
    header.text          = acc[@"email"];
    header.textColor     = UIColor.whiteColor;
    header.font          = [UIFont boldSystemFontOfSize:13];
    header.textAlignment = NSTextAlignmentCenter;
    header.numberOfLines = 1;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:header];

    // Sub — uid
    UILabel *sub = [UILabel new];
    sub.text          = [NSString stringWithFormat:@"uid: %@", acc[@"uid"]];
    sub.textColor     = [UIColor colorWithWhite:0.52 alpha:1];
    sub.font          = [UIFont systemFontOfSize:11];
    sub.textAlignment = NSTextAlignmentCenter;
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:sub];

    // Separator
    UIView *sep = [[UIView alloc] init];
    sep.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:sep];

    // Apply button
    UIButton *applyBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [applyBtn setTitle:@"Apply this account" forState:UIControlStateNormal];
    [applyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [applyBtn setTitleColor:[UIColor colorWithWhite:0.75 alpha:1]
                   forState:UIControlStateHighlighted];
    applyBtn.titleLabel.font  = [UIFont boldSystemFontOfSize:13];
    applyBtn.backgroundColor  = [UIColor colorWithRed:0.18 green:0.62 blue:0.38 alpha:1];
    applyBtn.layer.cornerRadius = 9;
    applyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:applyBtn];

    // Remove button
    UIButton *removeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [removeBtn setTitle:@"Remove" forState:UIControlStateNormal];
    [removeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [removeBtn setTitleColor:[UIColor colorWithWhite:0.75 alpha:1]
                    forState:UIControlStateHighlighted];
    removeBtn.titleLabel.font  = [UIFont boldSystemFontOfSize:13];
    removeBtn.backgroundColor  = [UIColor colorWithRed:0.68 green:0.18 blue:0.18 alpha:1];
    removeBtn.layer.cornerRadius = 9;
    removeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:removeBtn];

    // Cancel button
    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [cancelBtn setTitle:@"Cancel" forState:UIControlStateNormal];
    [cancelBtn setTitleColor:[UIColor colorWithWhite:0.60 alpha:1] forState:UIControlStateNormal];
    [cancelBtn setTitleColor:UIColor.whiteColor forState:UIControlStateHighlighted];
    cancelBtn.titleLabel.font  = [UIFont systemFontOfSize:12];
    cancelBtn.backgroundColor  = [UIColor colorWithWhite:0.16 alpha:1];
    cancelBtn.layer.cornerRadius = 9;
    cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:cancelBtn];

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:parent.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:parent.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:260],
        [header.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [header.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [header.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [sub.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:4],
        [sub.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [sub.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [sep.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:12],
        [sep.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:0],
        [sep.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:0],
        [sep.heightAnchor constraintEqualToConstant:1],
        [applyBtn.topAnchor constraintEqualToAnchor:sep.bottomAnchor constant:12],
        [applyBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [applyBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [applyBtn.heightAnchor constraintEqualToConstant:44],
        [removeBtn.topAnchor constraintEqualToAnchor:applyBtn.bottomAnchor constant:8],
        [removeBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [removeBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [removeBtn.heightAnchor constraintEqualToConstant:44],
        [cancelBtn.topAnchor constraintEqualToAnchor:removeBtn.bottomAnchor constant:8],
        [cancelBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [cancelBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [cancelBtn.heightAnchor constraintEqualToConstant:36],
        [card.bottomAnchor constraintEqualToAnchor:cancelBtn.bottomAnchor constant:14],
    ]];

    // Dismiss helper
    void (^dismiss)(void) = ^{
        [UIView animateWithDuration:0.15 animations:^{
            backdrop.alpha = 0;
            card.alpha     = 0;
        } completion:^(BOOL _) {
            [backdrop removeFromSuperview];
            [card removeFromSuperview];
        }];
    };

    // Backdrop tap — store dismiss block via associated object so the gesture target can call it
    objc_setAssociatedObject(backdrop, "dismissBlock",
        [dismiss copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
    UITapGestureRecognizer *bgTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(actionBackdropTapped:)];
    bgTap.cancelsTouchesInView = NO;
    [backdrop addGestureRecognizer:bgTap];

    // Apply
    [applyBtn sk_setActionBlock:^{
        dismiss();
        // Move account to "removed" pool then apply
        NSMutableArray *list = getSaved();
        if (row >= (NSInteger)list.count) return;
        NSDictionary *a = list[row];
        NSMutableArray *rem = getRemoved();
        [list removeObjectAtIndex:row];
        [rem addObject:a];
        writeSaved(list);
        writeRemoved(rem);
        applyAccount(a);
        [self.table reloadData];
        [self refreshInfo];
        NSString *tok = a[@"token"];
        NSString *msg = [NSString stringWithFormat:
            @"Applied\n\nEmail : %@\nUID   : %@\nToken : %@...\n\nIDs replaced globally\nNSUserDefaults patched\n\nRemaining: %lu\nClosing app...",
            a[@"email"], a[@"uid"],
            [tok substringToIndex:MIN((NSUInteger)10, tok.length)],
            (unsigned long)list.count];
        [self showToast:msg success:YES exit:YES];
    }];

    // Remove
    [removeBtn sk_setActionBlock:^{
        dismiss();
        NSMutableArray *list = getSaved();
        if (row >= (NSInteger)list.count) return;
        [list removeObjectAtIndex:row];
        writeSaved(list);
        [self.table reloadData];
        [self showToast:@"Account removed." success:NO exit:NO];
    }];

    // Cancel
    [cancelBtn sk_setActionBlock:^{ dismiss(); }];

    // Animate in
    card.alpha     = 0;
    backdrop.alpha = 0;
    [UIView animateWithDuration:0.18 animations:^{
        backdrop.alpha = 1;
        card.alpha     = 1;
    }];
}

- (void)actionBackdropTapped:(UITapGestureRecognizer *)g {
    UIView *bd = g.view;
    void (^dismiss)(void) = objc_getAssociatedObject(bd, "dismissBlock");
    if (dismiss) dismiss();
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

    NSArray *titles = @[@"Edit  (apply random)", @"Export used accounts"];
    NSArray *colors = @[
        [UIColor colorWithRed:0.18 green:0.72 blue:0.38 alpha:1],
        [UIColor colorWithRed:1.00 green:0.46 blue:0.16 alpha:1]
    ];
    SEL sels[2] = { @selector(tapEdit), @selector(tapExport) };

    for (int i = 0; i < 2; i++) {
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
