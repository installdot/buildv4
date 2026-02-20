// tweak.xm — Soul Knight Account Manager v3
// • Edit picks RANDOM account automatically — no chooser
// • Replaces ALL occurrences of old PlayerId number throughout JSON string
// • Keyboard Done button toolbar
// • OK on result alert → exit(0) so game reloads fresh
// iOS 14+ | Theos/Logos | ARC

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - Keys

#define kSaved   @"__SKSavedAccounts__"
#define kRemoved @"__SKRemovedAccounts__"

#pragma mark - Storage helpers

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
    NSUserDefaults *ud  = [NSUserDefaults standardUserDefaults];
    NSString *newToken  = acc[@"token"];
    NSString *newUid    = acc[@"uid"];
    NSString *newEmail  = acc[@"email"];

    // ── 1. Patch SdkStateCache#1 ─────────────────────────────────────────
    NSString *raw = [ud stringForKey:@"SdkStateCache#1"];
    if (raw) {
        NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
        NSError *err = nil;
        NSMutableDictionary *root = [[NSJSONSerialization JSONObjectWithData:data
            options:NSJSONReadingMutableContainers error:&err] mutableCopy];

        if (!err && root) {
            NSMutableDictionary *user    = [root[@"User"]    mutableCopy] ?: [NSMutableDictionary new];
            NSMutableDictionary *session = [root[@"Session"] mutableCopy] ?: [NSMutableDictionary new];
            NSMutableDictionary *legacy  = [user[@"LegacyGateway"] mutableCopy] ?: [NSMutableDictionary new];

            // Capture old PlayerId string BEFORE patching
            NSString *oldIdStr = @"";
            id oldId = user[@"PlayerId"];
            if (oldId) oldIdStr = [NSString stringWithFormat:@"%@", oldId];

            // Patch individual fields
            legacy[@"token"]       = newToken;
            user[@"LegacyGateway"] = legacy;
            user[@"Email"]         = newEmail;
            user[@"PlayerId"]      = @([newUid longLongValue]);
            session[@"Token"]      = newToken;
            root[@"User"]          = user;
            root[@"Session"]       = session;

            // Serialise to string
            NSData *outData = [NSJSONSerialization dataWithJSONObject:root
                options:NSJSONWritingPrettyPrinted error:&err];
            if (!err && outData) {
                NSString *patched = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding];

                // Global replace: every occurrence of the old id number string → new uid
                if (oldIdStr.length > 0 && ![oldIdStr isEqualToString:@"0"] && ![oldIdStr isEqualToString:newUid]) {
                    patched = [patched stringByReplacingOccurrencesOfString:oldIdStr withString:newUid];
                }

                [ud setObject:patched forKey:@"SdkStateCache#1"];
                [ud synchronize];
            }
        }
    }

    // ── 2. Copy save files *_1_.data → *_{uid}_.data ─────────────────────
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *types = @[@"bp_data", @"item_data", @"misc_data",
                       @"season_data", @"statistic_data", @"weapon_evolution_data"];
    for (NSString *t in types) {
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

#pragma mark - Input VC

@interface SKInputVC : UIViewController
@property (nonatomic, strong) UITextView *tv;
@property (nonatomic, copy)   void (^onSave)(NSString *);
@end

@implementation SKInputVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];

    UILabel *ttl = [UILabel new];
    ttl.text = @"Add Accounts";
    ttl.textColor = UIColor.whiteColor;
    ttl.font = [UIFont boldSystemFontOfSize:17];
    ttl.textAlignment = NSTextAlignmentCenter;
    ttl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:ttl];

    UILabel *hint = [UILabel new];
    hint.text = @"email|pass|uid|token  (one per line)";
    hint.textColor = [UIColor colorWithWhite:0.5 alpha:1];
    hint.font = [UIFont systemFontOfSize:12];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:hint];

    self.tv = [UITextView new];
    self.tv.backgroundColor = [UIColor colorWithWhite:0.17 alpha:1];
    self.tv.textColor = [UIColor colorWithRed:0.4 green:1 blue:0.55 alpha:1];
    self.tv.font = [UIFont fontWithName:@"Courier" size:13] ?: [UIFont systemFontOfSize:13];
    self.tv.layer.cornerRadius = 8;
    self.tv.autocorrectionType = UITextAutocorrectionTypeNo;
    self.tv.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.tv.translatesAutoresizingMaskIntoConstraints = NO;

    // Done button toolbar
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    toolbar.barStyle = UIBarStyleBlack;
    toolbar.translucent = YES;
    UIBarButtonItem *flex = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *doneBtn = [[UIBarButtonItem alloc]
        initWithTitle:@"Done ✓" style:UIBarButtonItemStyleDone
        target:self action:@selector(dismissKeyboard)];
    doneBtn.tintColor = [UIColor colorWithRed:0.4 green:0.9 blue:1.0 alpha:1];
    toolbar.items = @[flex, doneBtn];
    self.tv.inputAccessoryView = toolbar;

    [self.view addSubview:self.tv];

    UIButton *saveBtn   = [self mkBtn:@"Save"   bg:[UIColor colorWithRed:0.18 green:0.68 blue:0.38 alpha:1]];
    UIButton *cancelBtn = [self mkBtn:@"Cancel" bg:[UIColor colorWithRed:0.60 green:0.18 blue:0.18 alpha:1]];
    saveBtn.translatesAutoresizingMaskIntoConstraints   = NO;
    cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [saveBtn   addTarget:self action:@selector(doSave)   forControlEvents:UIControlEventTouchUpInside];
    [cancelBtn addTarget:self action:@selector(doCancel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:saveBtn];
    [self.view addSubview:cancelBtn];

    UIView *v = self.view;
    [NSLayoutConstraint activateConstraints:@[
        [ttl.topAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.topAnchor constant:16],
        [ttl.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:16],
        [ttl.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-16],
        [hint.topAnchor constraintEqualToAnchor:ttl.bottomAnchor constant:6],
        [hint.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:16],
        [hint.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-16],
        [self.tv.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:10],
        [self.tv.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:16],
        [self.tv.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-16],
        [self.tv.bottomAnchor constraintEqualToAnchor:saveBtn.topAnchor constant:-12],
        [cancelBtn.bottomAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [cancelBtn.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:16],
        [cancelBtn.heightAnchor constraintEqualToConstant:44],
        [saveBtn.bottomAnchor constraintEqualToAnchor:cancelBtn.bottomAnchor],
        [saveBtn.leadingAnchor constraintEqualToAnchor:cancelBtn.trailingAnchor constant:8],
        [saveBtn.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-16],
        [saveBtn.widthAnchor constraintEqualToAnchor:cancelBtn.widthAnchor],
        [saveBtn.heightAnchor constraintEqualToConstant:44],
    ]];
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
- (void)dismissKeyboard { [self.tv resignFirstResponder]; }
- (void)doSave   { if (self.onSave) self.onSave(self.tv.text); [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)doCancel { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

#pragma mark - Floating Panel

@interface SKPanel : UIView
@end

@implementation SKPanel

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, 182, 44)];
    if (!self) return nil;
    self.backgroundColor     = [UIColor colorWithWhite:0.05 alpha:0.85];
    self.layer.cornerRadius  = 11;
    self.layer.shadowColor   = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.75;
    self.layer.shadowRadius  = 6;
    self.layer.shadowOffset  = CGSizeMake(0, 3);
    self.layer.zPosition     = 9999;

    NSArray *titles = @[@"Input", @"Edit", @"Export"];
    NSArray *colors = @[
        [UIColor colorWithRed:0.18 green:0.55 blue:1.00 alpha:1],
        [UIColor colorWithRed:0.18 green:0.78 blue:0.38 alpha:1],
        [UIColor colorWithRed:1.00 green:0.48 blue:0.16 alpha:1]
    ];
    SEL sels[3] = { @selector(tapInput), @selector(tapEdit), @selector(tapExport) };

    CGFloat bw = 56, bh = 34, gap = 2, sx = 5, y = 5;
    for (int i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(sx + i*(bw+gap), y, bw, bh);
        b.backgroundColor = colors[i];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font    = [UIFont boldSystemFontOfSize:11];
        b.layer.cornerRadius = 7;
        b.layer.zPosition    = 10000;
        [b addTarget:self action:sels[i] forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
    }
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(onPan:)];
    [self addGestureRecognizer:pan];
    return self;
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint d  = [g translationInView:self.superview];
    CGRect  sb = self.superview.bounds;
    CGFloat nx = MIN(MAX(self.frame.size.width/2,  self.center.x + d.x), sb.size.width  - self.frame.size.width/2);
    CGFloat ny = MIN(MAX(self.frame.size.height/2, self.center.y + d.y), sb.size.height - self.frame.size.height/2);
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

// Alert with optional completion on OK
- (void)alert:(NSString *)title msg:(NSString *)msg completion:(void(^)(void))cb {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title
            message:msg preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *_) { if (cb) cb(); }]];
        [[self topVC] presentViewController:a animated:YES completion:nil];
    });
}

// ── Input ─────────────────────────────────────────────────────────────────
- (void)tapInput {
    SKInputVC *ivc = [SKInputVC new];
    ivc.modalPresentationStyle = UIModalPresentationFormSheet;
    ivc.onSave = ^(NSString *text) {
        NSMutableArray *list = getSaved();
        NSUInteger before = list.count;
        for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            NSString *t = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!t.length) continue;
            NSDictionary *a = parseLine(t);
            if (!a) continue;
            BOOL dup = NO;
            for (NSDictionary *e in list) if ([e[@"uid"] isEqualToString:a[@"uid"]]) { dup = YES; break; }
            if (!dup) [list addObject:a];
        }
        writeSaved(list);
        [self alert:@"Saved"
                msg:[NSString stringWithFormat:@"Added %lu new. Total: %lu",
                     (unsigned long)(list.count - before), (unsigned long)list.count]
         completion:nil];
    };
    [[self topVC] presentViewController:ivc animated:YES completion:nil];
}

// ── Edit — random pick, apply, then exit on OK ────────────────────────────
- (void)tapEdit {
    NSMutableArray *list = getSaved();
    if (!list.count) {
        [self alert:@"No Accounts" msg:@"Use [Input] to add accounts first." completion:nil];
        return;
    }

    // Pick random
    NSUInteger idx  = arc4random_uniform((uint32_t)list.count);
    NSDictionary *acc = list[idx];

    // Move to removed list
    NSMutableArray *cur = getSaved(), *rem = getRemoved();
    [cur removeObjectAtIndex:idx];
    [rem addObject:acc];
    writeSaved(cur);
    writeRemoved(rem);

    // Apply patch + file copy
    applyAccount(acc);

    NSString *info = [NSString stringWithFormat:
        @"Email : %@\nUID   : %@\nToken : %@\n\n"
        @"✓ All IDs replaced in NSUserDefaults\n"
        @"✓ Save files backed up\n\n"
        @"Tap OK to close the app — relaunch to play.",
        acc[@"email"], acc[@"uid"], acc[@"token"]];

    // exit(0) after OK → game relaunches clean with new account
    [self alert:@"Account Applied" msg:info completion:^{
        exit(0);
    }];
}

// ── Export ────────────────────────────────────────────────────────────────
- (void)tapExport {
    NSMutableArray *rem = getRemoved();
    if (!rem.count) {
        [self alert:@"Nothing to Export" msg:@"No removed accounts yet. Use [Edit] first." completion:nil];
        return;
    }
    NSMutableString *out = [NSMutableString new];
    for (NSDictionary *a in rem) [out appendFormat:@"%@|%@\n", a[@"email"], a[@"pass"]];
    [UIPasteboard generalPasteboard].string = out;
    writeRemoved(@[]);
    [self alert:@"Exported"
            msg:[NSString stringWithFormat:@"Copied %lu account(s) to clipboard:\n\n%@",
                 (unsigned long)rem.count, out]
     completion:nil];
}

@end // SKPanel

#pragma mark - Injection

static SKPanel *gPanel = nil;

static void injectPanel(void) {
    UIWindow *win = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (!w.isHidden && w.alpha > 0) { win = w; break; }
    }
    if (!win) return;
    UIView *root = win.rootViewController.view ?: win;
    gPanel = [SKPanel new];
    CGFloat sw = root.bounds.size.width;
    gPanel.center = CGPointMake(sw - gPanel.bounds.size.width/2 - 8, 100);
    [root addSubview:gPanel];
    [root bringSubviewToFront:gPanel];
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ injectPanel(); });
    });
}
%end
