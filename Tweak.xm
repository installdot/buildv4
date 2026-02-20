// tweak.xm — Soul Knight Account Manager
// Injects panel directly into the app's root UIWindow subview
// Most reliable approach for dylib injection — no separate UIWindow
// iOS 14+ | Theos/Logos | ARC

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - Keys

#define kSaved   @"__SKSavedAccounts__"
#define kRemoved @"__SKRemovedAccounts__"

#pragma mark - Storage

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
    NSString *token  = acc[@"token"];
    NSString *uidStr = acc[@"uid"];
    NSString *email  = acc[@"email"];

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
            legacy[@"token"]       = token;
            user[@"LegacyGateway"] = legacy;
            user[@"Email"]         = email;
            user[@"PlayerId"]      = @([uidStr longLongValue]);
            session[@"Token"]      = token;
            root[@"User"]          = user;
            root[@"Session"]       = session;
            NSData *out = [NSJSONSerialization dataWithJSONObject:root
                options:NSJSONWritingPrettyPrinted error:&err];
            if (!err && out)
                [ud setObject:[[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding]
                       forKey:@"SdkStateCache#1"];
            [ud synchronize];
        }
    }

    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *t in @[@"bp_data",@"item_data",@"misc_data",
                          @"season_data",@"statistic_data",@"weapon_evolution_data"]) {
        NSString *src = [docs stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_1_.data",t]];
        NSString *dst = [docs stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%@_.data",t,uidStr]];
        if ([fm fileExistsAtPath:src]) { [fm removeItemAtPath:dst error:nil]; [fm copyItemAtPath:src toPath:dst error:nil]; }
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
    self.tv.keyboardType = UIKeyboardTypeEmailAddress;
    self.tv.translatesAutoresizingMaskIntoConstraints = NO;
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

    self.backgroundColor     = [UIColor colorWithWhite:0.05 alpha:0.82];
    self.layer.cornerRadius  = 11;
    self.layer.shadowColor   = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.75;
    self.layer.shadowRadius  = 6;
    self.layer.shadowOffset  = CGSizeMake(0, 3);
    self.layer.zPosition     = 9999;

    // ── 3 buttons ──────────────────────────────────────────────────────────
    NSArray *titles = @[@"Input", @"Edit", @"Export"];
    NSArray *colors = @[
        [UIColor colorWithRed:0.18 green:0.55 blue:1.00 alpha:1],
        [UIColor colorWithRed:0.18 green:0.78 blue:0.38 alpha:1],
        [UIColor colorWithRed:1.00 green:0.48 blue:0.16 alpha:1]
    ];
    SEL sels[3] = { @selector(tapInput), @selector(tapEdit), @selector(tapExport) };

    CGFloat bw = 56, bh = 34, gap = 2, x = 5, y = 5;
    for (int i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(x + i*(bw+gap), y, bw, bh);
        b.backgroundColor = colors[i];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        b.layer.cornerRadius = 7;
        b.layer.zPosition = 10000;
        [b addTarget:self action:sels[i] forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
    }

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(onPan:)];
    [self addGestureRecognizer:pan];
    return self;
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint d = [g translationInView:self.superview];
    CGRect  f = self.frame;
    CGRect  sb = self.superview.bounds;
    CGFloat nx = self.center.x + d.x;
    CGFloat ny = self.center.y + d.y;
    // Clamp inside superview
    nx = MAX(f.size.width/2,  MIN(sb.size.width  - f.size.width/2,  nx));
    ny = MAX(f.size.height/2, MIN(sb.size.height - f.size.height/2, ny));
    self.center = CGPointMake(nx, ny);
    [g setTranslation:CGPointZero inView:self.superview];
}

// ── Present an alert on the topmost VC ─────────────────────────────────────
- (UIViewController *)topVC {
    UIViewController *vc = nil;
    // Walk windows to find the first non-hidden, non-system window
    NSArray *wins = UIApplication.sharedApplication.windows;
    for (UIWindow *w in wins.reverseObjectEnumerator) {
        if (!w.isHidden && w.alpha > 0 && w.rootViewController) {
            vc = w.rootViewController; break;
        }
    }
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

- (void)alert:(NSString *)title msg:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title
            message:msg preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[self topVC] presentViewController:a animated:YES completion:nil];
    });
}

// ── Input ───────────────────────────────────────────────────────────────────
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
            for (NSDictionary *e in list) if ([e[@"uid"] isEqualToString:a[@"uid"]]) { dup=YES; break; }
            if (!dup) [list addObject:a];
        }
        writeSaved(list);
        [self alert:@"Saved"
                msg:[NSString stringWithFormat:@"Added %lu new. Total: %lu",
                     (unsigned long)(list.count-before),(unsigned long)list.count]];
    };
    [[self topVC] presentViewController:ivc animated:YES completion:nil];
}

// ── Edit ────────────────────────────────────────────────────────────────────
- (void)tapEdit {
    NSMutableArray *list = getSaved();
    if (!list.count) { [self alert:@"No Accounts" msg:@"Use [Input] to add accounts first."]; return; }

    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Choose Account"
        message:@"Account will be applied & removed from saved list."
        preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSDictionary *acc in list) {
        NSString *lbl = [NSString stringWithFormat:@"%@  •  uid:%@", acc[@"email"], acc[@"uid"]];
        [ac addAction:[UIAlertAction actionWithTitle:lbl style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_) {
            NSMutableArray *cur = getSaved(), *rem = getRemoved();
            [cur removeObject:acc]; [rem addObject:acc];
            writeSaved(cur); writeRemoved(rem);
            applyAccount(acc);
            [self alert:@"Account Applied"
                    msg:[NSString stringWithFormat:
                         @"Email : %@\nUID   : %@\nToken : %@\n\n✓ NSUserDefaults patched\n✓ Save files backed up",
                         acc[@"email"],acc[@"uid"],acc[@"token"]]];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        ac.popoverPresentationController.sourceView = self;
        ac.popoverPresentationController.sourceRect = self.bounds;
        ac.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [[self topVC] presentViewController:ac animated:YES completion:nil];
}

// ── Export ──────────────────────────────────────────────────────────────────
- (void)tapExport {
    NSMutableArray *rem = getRemoved();
    if (!rem.count) { [self alert:@"Nothing to Export" msg:@"No removed accounts yet. Use [Edit] first."]; return; }
    NSMutableString *out = [NSMutableString new];
    for (NSDictionary *a in rem) [out appendFormat:@"%@|%@\n", a[@"email"], a[@"pass"]];
    [UIPasteboard generalPasteboard].string = out;
    writeRemoved(@[]);
    [self alert:@"Exported"
            msg:[NSString stringWithFormat:@"Copied %lu account(s) to clipboard:\n\n%@",
                 (unsigned long)rem.count, out]];
}

@end // SKPanel

#pragma mark - Injection Hook

static SKPanel *gPanel = nil;

// Add panel to window's root view directly — most reliable for injected dylibs
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

// Hook viewDidAppear on ANY UIViewController — fires once, safe dispatch_once
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            injectPanel();
        });
    });
}
%end
