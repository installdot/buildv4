// tweak.xm — Soul Knight Account Manager v5
// iOS 14+ | Theos/Logos | ARC
// Fixes: keyboard overlay, scrollable input, swipe-delete accounts,
//        custom unlock menu (no alerts), unlock targets NSUserDefaults,
//        ID replace via full NSUserDefaults string scan

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

    // ── Step 1: extract old PlayerId from SdkStateCache#1
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

        // ── Step 2: patch the JSON fields directly
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

    // ── Step 3: scan every NSUserDefaults string value and replace old ID
    //    Dump everything to plain strings, find oldPlayerId, replace with newUid
    if (oldPlayerId.length > 0 && ![oldPlayerId isEqualToString:@"0"]) {
        NSDictionary *all = [ud dictionaryRepresentation];
        for (NSString *key in all) {
            id val = all[key];
            if (![val isKindOfClass:[NSString class]]) continue;
            NSString *s = (NSString *)val;
            if (![s containsString:oldPlayerId]) continue;
            NSString *replaced = [s stringByReplacingOccurrencesOfString:oldPlayerId
                                                               withString:newUid];
            [ud setObject:replaced forKey:key];
        }
    }
    [ud synchronize];

    // ── Step 4: copy save files *_1_.data → *_{newUid}_.data
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

#pragma mark - Unlock (NSUserDefaults, JSON key patterns)

// Runs regex find/replace across every string value in NSUserDefaults.
// Patterns match JSON-encoded keys (Soul Knight stores game state as JSON strings).
static int runUnlockInDefaults(NSString *type) {
    NSUserDefaults *ud  = [NSUserDefaults standardUserDefaults];
    NSDictionary   *all = [ud dictionaryRepresentation];

    NSString *pattern, *tmpl;

    if ([type isEqualToString:@"Characters"]) {
        // "12345_c3_unlock" : false  →  true
        pattern = @"(\"\\d+_c\\d+_unlock[^\"]*\"\\s*:\\s*)false";
        tmpl    = @"${1}true";
    } else if ([type isEqualToString:@"Skins"]) {
        // "12345_c3_skin2" : 0  →  1
        pattern = @"(\"\\d+_c\\d+_skin\\d+[^\"]*\"\\s*:\\s*)[+-]?\\d+";
        tmpl    = @"${1}1";
    } else if ([type isEqualToString:@"Skills"]) {
        // "12345_c_xxx_skill_1_unlock" : 0  →  1
        pattern = @"(\"\\d+_c_[^\"]*_skill_\\d_unlock[^\"]*\"\\s*:\\s*)\\d";
        tmpl    = @"${1}1";
    } else if ([type isEqualToString:@"Pets"]) {
        // "12345_p3_unlock" : false  →  true
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
                                                  inString:ms
                                                    offset:0
                                                  template:tmpl];
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
+ (void)showInView:(UIView *)parentView onDone:(void(^)(NSString *msg))doneBlock;
@end

@implementation SKUnlockSheet {
    UIView *_card;
    UILabel *_statusLabel;
    UIActivityIndicatorView *_spinner;
    void (^_doneBlock)(NSString *);
}

+ (void)showInView:(UIView *)parentView onDone:(void(^)(NSString *))doneBlock {
    SKUnlockSheet *sheet = [[SKUnlockSheet alloc] initWithFrame:parentView.bounds];
    sheet->_doneBlock = doneBlock;
    sheet.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [parentView addSubview:sheet];
    sheet.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ sheet.alpha = 1; }];
}

- (void)setDoneBlock:(void(^)(NSString *))b { _doneBlock = b; }

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    // Dim overlay — tap outside = close
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    UITapGestureRecognizer *tapDismiss = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(dismiss)];
    tapDismiss.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tapDismiss];

    // Card
    _card = [[UIView alloc] init];
    _card.backgroundColor     = [UIColor colorWithRed:0.10 green:0.10 blue:0.13 alpha:1];
    _card.layer.cornerRadius  = 14;
    _card.layer.shadowColor   = UIColor.blackColor.CGColor;
    _card.layer.shadowOpacity = 0.7;
    _card.layer.shadowRadius  = 12;
    _card.layer.shadowOffset  = CGSizeMake(0, 4);
    _card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_card];

    // Block touches on card from reaching the dismiss tap recognizer
    UIView *cardTouchGuard = [[UIView alloc] initWithFrame:_card.bounds];
    cardTouchGuard.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [_card addSubview:cardTouchGuard];
    // (adding a recognizer that does nothing prevents passthrough)
    [cardTouchGuard addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(cardTapped)]];

    // Title
    UILabel *title = [UILabel new];
    title.text = @"Unlock";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:title];

    // Close button (top-right X)
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [closeBtn setTitle:@"X" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithWhite:0.65 alpha:1] forState:UIControlStateNormal];
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateHighlighted];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [closeBtn addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:closeBtn];

    // Type buttons
    NSArray *types  = @[@"Characters", @"Skins", @"Skills", @"Pets"];
    NSArray *colors = @[
        [UIColor colorWithRed:0.18 green:0.52 blue:1.00 alpha:1],
        [UIColor colorWithRed:0.18 green:0.76 blue:0.38 alpha:1],
        [UIColor colorWithRed:1.00 green:0.46 blue:0.16 alpha:1],
        [UIColor colorWithRed:0.72 green:0.22 blue:0.90 alpha:1]
    ];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis         = UILayoutConstraintAxisVertical;
    stack.spacing      = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:stack];

    for (NSUInteger i = 0; i < types.count; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        [btn setTitle:types[i] forState:UIControlStateNormal];
        [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor colorWithWhite:0.75 alpha:1] forState:UIControlStateHighlighted];
        btn.backgroundColor = colors[i];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        btn.layer.cornerRadius = 9;
        btn.tag = (NSInteger)i;
        [btn addTarget:self action:@selector(typeTapped:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:btn];
        [btn.heightAnchor constraintEqualToConstant:46].active = YES;
    }

    // Status label
    _statusLabel = [UILabel new];
    _statusLabel.text            = @"";
    _statusLabel.textColor       = [UIColor colorWithRed:0.4 green:1 blue:0.55 alpha:1];
    _statusLabel.font            = [UIFont systemFontOfSize:12];
    _statusLabel.textAlignment   = NSTextAlignmentCenter;
    _statusLabel.numberOfLines   = 0;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:_statusLabel];

    // Spinner
    _spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color = UIColor.whiteColor;
    _spinner.hidesWhenStopped = YES;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [_card addSubview:_spinner];

    // Constraints
    [NSLayoutConstraint activateConstraints:@[
        // Card: centered, fixed width, hugs content vertically
        [_card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_card.widthAnchor constraintEqualToConstant:270],
        // Title
        [title.topAnchor constraintEqualToAnchor:_card.topAnchor constant:18],
        [title.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:44],
        [title.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-44],
        // Close button
        [closeBtn.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [closeBtn.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-14],
        [closeBtn.widthAnchor constraintEqualToConstant:32],
        [closeBtn.heightAnchor constraintEqualToConstant:32],
        // Stack of type buttons
        [stack.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-16],
        // Status label
        [_statusLabel.topAnchor constraintEqualToAnchor:stack.bottomAnchor constant:12],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:12],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-12],
        // Spinner
        [_spinner.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:8],
        [_spinner.centerXAnchor constraintEqualToAnchor:_card.centerXAnchor],
        // Card bottom
        [_card.bottomAnchor constraintEqualToAnchor:_spinner.bottomAnchor constant:20],
    ]];

    return self;
}

- (void)cardTapped {} // absorb taps on card

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
                self->_statusLabel.textColor = [UIColor colorWithRed:0.4 green:1 blue:0.55 alpha:1];
                self->_statusLabel.text = [NSString stringWithFormat:
                    @"Modified %d NSUserDefaults key(s).\nRestart the app to apply.", n];
            } else {
                self->_statusLabel.textColor = [UIColor colorWithRed:1 green:0.5 blue:0.35 alpha:1];
                self->_statusLabel.text = @"No matching keys found.\nMake sure you have launched the game at least once.";
            }
        });
    });
}

- (void)dismiss {
    [UIView animateWithDuration:0.18 animations:^{ self.alpha = 0; }
                     completion:^(BOOL _) { [self removeFromSuperview]; }];
}

@end

#pragma mark - Input VC (keyboard-aware, scrollable, swipe-to-delete)

@interface SKInputVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextView  *tv;
@property (nonatomic, strong) NSMutableArray *accounts;
@property (nonatomic, copy)   void (^onDone)(void);
// Bottom constraint we adjust when keyboard shows/hides
@property (nonatomic, strong) NSLayoutConstraint *bottomConstraint;
@end

@implementation SKInputVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    self.accounts = getSaved();

    // Title
    UILabel *ttl = [UILabel new];
    ttl.text           = @"Accounts";
    ttl.textColor      = UIColor.whiteColor;
    ttl.font           = [UIFont boldSystemFontOfSize:17];
    ttl.textAlignment  = NSTextAlignmentCenter;
    ttl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:ttl];

    // Saved accounts table
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.dataSource       = self;
    self.table.delegate         = self;
    self.table.backgroundColor  = [UIColor colorWithWhite:0.14 alpha:1];
    self.table.separatorColor   = [UIColor colorWithWhite:0.25 alpha:1];
    self.table.layer.cornerRadius = 8;
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];

    // Hint
    UILabel *hint = [UILabel new];
    hint.text          = @"Add new  —  email|pass|uid|token  (one per line)";
    hint.textColor     = [UIColor colorWithWhite:0.5 alpha:1];
    hint.font          = [UIFont systemFontOfSize:11];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:hint];

    // Text view — scrollable input
    self.tv = [UITextView new];
    self.tv.backgroundColor          = [UIColor colorWithWhite:0.17 alpha:1];
    self.tv.textColor                = [UIColor colorWithRed:0.4 green:1 blue:0.55 alpha:1];
    self.tv.font                     = [UIFont fontWithName:@"Courier" size:12] ?: [UIFont systemFontOfSize:12];
    self.tv.layer.cornerRadius       = 8;
    self.tv.autocorrectionType       = UITextAutocorrectionTypeNo;
    self.tv.autocapitalizationType   = UITextAutocapitalizationTypeNone;
    self.tv.scrollEnabled            = YES;                 // scrollable
    self.tv.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tv];

    // Keyboard toolbar (Done key = dismiss keyboard only)
    UIToolbar *bar = [[UIToolbar alloc]
        initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 44)];
    bar.barStyle   = UIBarStyleBlack;
    bar.translucent = YES;
    UIBarButtonItem *flex = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *doneKb = [[UIBarButtonItem alloc]
        initWithTitle:@"Done"
        style:UIBarButtonItemStyleDone
        target:self action:@selector(dismissKeyboard)];
    doneKb.tintColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1];
    bar.items = @[flex, doneKb];
    self.tv.inputAccessoryView = bar;

    // Bottom buttons: Cancel | Save
    UIButton *saveBtn   = [self mkBtn:@"Save"
                                   bg:[UIColor colorWithRed:0.18 green:0.68 blue:0.38 alpha:1]];
    UIButton *cancelBtn = [self mkBtn:@"Cancel"
                                   bg:[UIColor colorWithRed:0.60 green:0.18 blue:0.18 alpha:1]];
    saveBtn.translatesAutoresizingMaskIntoConstraints   = NO;
    cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [saveBtn   addTarget:self action:@selector(doSave)   forControlEvents:UIControlEventTouchUpInside];
    [cancelBtn addTarget:self action:@selector(doCancel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:saveBtn];
    [self.view addSubview:cancelBtn];

    UIView *v = self.view;

    // Bottom constraint — this one moves up when keyboard appears
    self.bottomConstraint = [cancelBtn.bottomAnchor
        constraintEqualToAnchor:v.safeAreaLayoutGuide.bottomAnchor constant:-14];

    [NSLayoutConstraint activateConstraints:@[
        // Title
        [ttl.topAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.topAnchor constant:12],
        [ttl.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:16],
        [ttl.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-16],
        // Table — top 36% of view
        [self.table.topAnchor constraintEqualToAnchor:ttl.bottomAnchor constant:10],
        [self.table.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:12],
        [self.table.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-12],
        [self.table.heightAnchor constraintEqualToAnchor:v.heightAnchor multiplier:0.36],
        // Hint
        [hint.topAnchor constraintEqualToAnchor:self.table.bottomAnchor constant:8],
        [hint.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:12],
        [hint.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-12],
        // Text view grows to fill space above buttons
        [self.tv.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:4],
        [self.tv.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:12],
        [self.tv.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-12],
        [self.tv.bottomAnchor constraintEqualToAnchor:saveBtn.topAnchor constant:-10],
        // Cancel button
        self.bottomConstraint,
        [cancelBtn.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:12],
        [cancelBtn.heightAnchor constraintEqualToConstant:44],
        // Save button
        [saveBtn.bottomAnchor constraintEqualToAnchor:cancelBtn.bottomAnchor],
        [saveBtn.leadingAnchor constraintEqualToAnchor:cancelBtn.trailingAnchor constant:8],
        [saveBtn.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-12],
        [saveBtn.widthAnchor constraintEqualToAnchor:cancelBtn.widthAnchor],
        [saveBtn.heightAnchor constraintEqualToConstant:44],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(keyboardWillShow:)
               name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(keyboardWillHide:)
               name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:UIKeyboardWillHideNotification object:nil];
}

- (void)keyboardWillShow:(NSNotification *)n {
    CGRect kbFrame = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    // Convert to view coordinates to handle safe-area edge correctly
    CGRect kbInView = [self.view convertRect:kbFrame fromView:nil];
    CGFloat overlap = CGRectGetMaxY(self.view.frame) - CGRectGetMinY(kbInView);
    if (overlap <= 0) return;

    NSTimeInterval dur = [n.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    NSInteger rawCurve = [n.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    UIViewAnimationOptions opts = (UIViewAnimationOptions)(rawCurve << 16) | UIViewAnimationOptionBeginFromCurrentState;
    self.bottomConstraint.constant = -(overlap + 8);
    [UIView animateWithDuration:dur delay:0 options:opts animations:^{
        [self.view layoutIfNeeded];
    } completion:nil];
}

- (void)keyboardWillHide:(NSNotification *)n {
    NSTimeInterval dur = [n.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    NSInteger rawCurve = [n.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    UIViewAnimationOptions opts = (UIViewAnimationOptions)(rawCurve << 16) | UIViewAnimationOptionBeginFromCurrentState;
    self.bottomConstraint.constant = -14;
    [UIView animateWithDuration:dur delay:0 options:opts animations:^{
        [self.view layoutIfNeeded];
    } completion:nil];
}

- (UIButton *)mkBtn:(NSString *)t bg:(UIColor *)c {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    b.backgroundColor = c;
    b.layer.cornerRadius = 8;
    return b;
}

// UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.accounts.count == 0 ? 1 : (NSInteger)self.accounts.count;
}
- (UITableViewCell *)tableView:(UITableView *)tv
         cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"c"];
    cell.backgroundColor           = [UIColor colorWithWhite:0.14 alpha:1];
    cell.textLabel.textColor       = UIColor.whiteColor;
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    cell.textLabel.font            = [UIFont systemFontOfSize:13];
    cell.detailTextLabel.font      = [UIFont systemFontOfSize:11];

    if (self.accounts.count == 0) {
        cell.textLabel.text       = @"No saved accounts";
        cell.detailTextLabel.text = @"";
        cell.userInteractionEnabled = NO;
    } else {
        NSDictionary *a = self.accounts[ip.row];
        cell.textLabel.text = a[@"email"];
        NSString *tok = a[@"token"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"uid: %@   token: %@...",
            a[@"uid"], [tok substringToIndex:MIN((NSUInteger)10, tok.length)]];
        cell.userInteractionEnabled = YES;
    }
    return cell;
}

// Swipe-to-delete
- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    return self.accounts.count > 0;
}
- (UITableViewCellEditingStyle)tableView:(UITableView *)tv
           editingStyleForRowAtIndexPath:(NSIndexPath *)ip {
    return self.accounts.count > 0 ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}
- (void)tableView:(UITableView *)tv
commitEditingStyle:(UITableViewCellEditingStyle)es
forRowAtIndexPath:(NSIndexPath *)ip {
    if (es == UITableViewCellEditingStyleDelete) {
        [self.accounts removeObjectAtIndex:ip.row];
        writeSaved(self.accounts);
        if (self.accounts.count == 0)
            [tv reloadData];
        else
            [tv deleteRowsAtIndexPaths:@[ip]
                      withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)dismissKeyboard { [self.tv resignFirstResponder]; }

- (void)doSave {
    NSString *text = self.tv.text;
    NSUInteger before = self.accounts.count;
    for (NSString *line in [text componentsSeparatedByCharactersInSet:
                             NSCharacterSet.newlineCharacterSet]) {
        NSString *t = [line stringByTrimmingCharactersInSet:
                       NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!t.length) continue;
        NSDictionary *a = parseLine(t);
        if (!a) continue;
        BOOL dup = NO;
        for (NSDictionary *e in self.accounts)
            if ([e[@"uid"] isEqualToString:a[@"uid"]]) { dup = YES; break; }
        if (!dup) [self.accounts addObject:a];
    }
    writeSaved(self.accounts);
    NSUInteger added = self.accounts.count - before;
    self.tv.text = @"";
    [self.table reloadData];

    // Inline status instead of UIAlertController
    UILabel *toast = [UILabel new];
    toast.text = [NSString stringWithFormat:@"Added %lu  |  Total: %lu",
                  (unsigned long)added, (unsigned long)self.accounts.count];
    toast.textColor    = [UIColor colorWithRed:0.4 green:1 blue:0.55 alpha:1];
    toast.font         = [UIFont boldSystemFontOfSize:13];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    toast.layer.cornerRadius = 8;
    toast.clipsToBounds = YES;
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:toast];
    [NSLayoutConstraint activateConstraints:@[
        [toast.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [toast.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [toast.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor constant:-40],
        [toast.heightAnchor constraintEqualToConstant:38],
    ]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{ toast.alpha = 0; }
                         completion:^(BOOL _) { [toast removeFromSuperview]; }];
    });

    if (self.onDone) self.onDone();
}

- (void)doCancel {
    if (self.onDone) self.onDone();
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Panel

@interface SKPanel : UIView
@property (nonatomic, strong) UILabel *infoLabel;
@end

@implementation SKPanel

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, 248, 62)];
    if (!self) return nil;

    self.backgroundColor     = [UIColor colorWithWhite:0.05 alpha:0.88];
    self.layer.cornerRadius  = 12;
    self.layer.shadowColor   = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.8;
    self.layer.shadowRadius  = 7;
    self.layer.shadowOffset  = CGSizeMake(0, 3);
    self.layer.zPosition     = 9999;

    // Info bar (no emoji)
    self.infoLabel = [UILabel new];
    self.infoLabel.frame         = CGRectMake(6, 4, 236, 16);
    self.infoLabel.font          = [UIFont systemFontOfSize:10];
    self.infoLabel.textColor     = [UIColor colorWithWhite:0.75 alpha:1];
    self.infoLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.infoLabel];
    [self refreshInfo];

    // 4 buttons
    NSArray *titles = @[@"Input", @"Edit", @"Export", @"Unlock"];
    NSArray *colors = @[
        [UIColor colorWithRed:0.18 green:0.55 blue:1.00 alpha:1],
        [UIColor colorWithRed:0.18 green:0.78 blue:0.38 alpha:1],
        [UIColor colorWithRed:1.00 green:0.48 blue:0.16 alpha:1],
        [UIColor colorWithRed:0.75 green:0.22 blue:0.90 alpha:1]
    ];
    SEL sels[4] = { @selector(tapInput), @selector(tapEdit),
                    @selector(tapExport), @selector(tapUnlock) };

    CGFloat bw = 57, bh = 34, gap = 2, startX = 5, y = 22;
    for (int i = 0; i < 4; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(startX + i * (bw + gap), y, bw, bh);
        b.backgroundColor = colors[i];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font   = [UIFont boldSystemFontOfSize:11];
        b.layer.cornerRadius = 7;
        b.layer.zPosition   = 10000;
        [b addTarget:self action:sels[i] forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
    }

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(onPan:)];
    [self addGestureRecognizer:pan];
    return self;
}

- (void)refreshInfo {
    NSUInteger saved   = getSaved().count;
    NSUInteger exports = getRemoved().count;
    self.infoLabel.text = [NSString stringWithFormat:@"Saved: %lu     Export ready: %lu",
                           (unsigned long)saved, (unsigned long)exports];
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint d  = [g translationInView:self.superview];
    CGRect sb  = self.superview.bounds;
    CGFloat nx = MAX(self.bounds.size.width  / 2,
                     MIN(sb.size.width  - self.bounds.size.width  / 2, self.center.x + d.x));
    CGFloat ny = MAX(self.bounds.size.height / 2,
                     MIN(sb.size.height - self.bounds.size.height / 2, self.center.y + d.y));
    self.center = CGPointMake(nx, ny);
    [g setTranslation:CGPointZero inView:self.superview];
}

- (UIViewController *)topVC {
    UIViewController *vc = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
        if (!w.isHidden && w.alpha > 0 && w.rootViewController) { vc = w.rootViewController; break; }
    }
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

// Inline toast (replaces all alert dialogs in the panel)
- (void)showToast:(NSString *)msg exitAfter:(BOOL)ex {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *root = [self topVC].view ?: self.superview;

        UILabel *toast = [UILabel new];
        toast.text            = msg;
        toast.textColor       = UIColor.whiteColor;
        toast.font            = [UIFont systemFontOfSize:13];
        toast.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.13 alpha:0.96];
        toast.layer.cornerRadius = 10;
        toast.clipsToBounds   = YES;
        toast.numberOfLines   = 0;
        toast.textAlignment   = NSTextAlignmentCenter;
        toast.translatesAutoresizingMaskIntoConstraints = NO;

        UIEdgeInsets padding = UIEdgeInsetsMake(10, 14, 10, 14);
        toast.layoutMargins = padding;

        [root addSubview:toast];
        [NSLayoutConstraint activateConstraints:@[
            [toast.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
            [toast.centerYAnchor constraintEqualToAnchor:root.centerYAnchor],
            [toast.widthAnchor constraintLessThanOrEqualToAnchor:root.widthAnchor constant:-40],
        ]];

        NSTimeInterval delay = ex ? 2.5 : 2.0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{ toast.alpha = 0; }
                             completion:^(BOOL _) {
                [toast removeFromSuperview];
                [self refreshInfo];
                if (ex) exit(0);
            }];
        });
    });
}

// Input
- (void)tapInput {
    SKInputVC *ivc             = [SKInputVC new];
    ivc.modalPresentationStyle = UIModalPresentationFormSheet;
    ivc.onDone                 = ^{ [self refreshInfo]; };
    [[self topVC] presentViewController:ivc animated:YES completion:nil];
}

// Edit: pick random, apply, show toast then exit
- (void)tapEdit {
    NSMutableArray *list = getSaved();
    if (!list.count) {
        [self showToast:@"No Accounts\nUse [Input] to add accounts first." exitAfter:NO];
        return;
    }
    NSUInteger idx     = arc4random_uniform((uint32_t)list.count);
    NSDictionary *acc  = list[idx];

    NSMutableArray *rem = getRemoved();
    [list removeObjectAtIndex:idx];
    [rem addObject:acc];
    writeSaved(list);
    writeRemoved(rem);

    applyAccount(acc);

    NSString *msg = [NSString stringWithFormat:
        @"Account Applied\n\nEmail : %@\nUID   : %@\nToken : %@...\n\nAll IDs replaced\nNSUserDefaults patched\nSave files backed up\n\nRemaining: %lu\nApp will close in 2 sec.",
        acc[@"email"], acc[@"uid"],
        ((NSString *)acc[@"token"]).length >= 10
            ? [acc[@"token"] substringToIndex:10] : acc[@"token"],
        (unsigned long)list.count];
    [self showToast:msg exitAfter:YES];
}

// Export
- (void)tapExport {
    NSMutableArray *rem = getRemoved();
    if (!rem.count) {
        [self showToast:@"Nothing to Export\nNo removed accounts yet.\nUse [Edit] first." exitAfter:NO];
        return;
    }
    NSMutableString *out = [NSMutableString new];
    for (NSDictionary *a in rem)
        [out appendFormat:@"%@|%@\n", a[@"email"], a[@"pass"]];
    [UIPasteboard generalPasteboard].string = out;
    writeRemoved(@[]);
    [self refreshInfo];
    [self showToast:[NSString stringWithFormat:@"Exported %lu account(s) to clipboard.",
                     (unsigned long)rem.count]
         exitAfter:NO];
}

// Unlock: show custom sheet
- (void)tapUnlock {
    UIView *root = [self topVC].view ?: self.superview;
    [SKUnlockSheet showInView:root onDone:^(NSString *msg) {
        [self refreshInfo];
    }];
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
    gPanel.center = CGPointMake(sw - gPanel.bounds.size.width / 2 - 8, 110);
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
