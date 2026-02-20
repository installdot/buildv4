// tweak.xm — Soul Knight Account Manager
// Uses a dedicated overlay UIWindow so buttons ALWAYS appear
// Build: Theos/Logos | iOS 14+ | ARC enabled

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ─────────────────────────────────────────────────────────
//  Storage keys
// ─────────────────────────────────────────────────────────
#define kSavedAccountsKey   @"__TweakSavedAccounts__"
#define kRemovedAccountsKey @"__TweakRemovedAccounts__"

// ─────────────────────────────────────────────────────────
//  Persistence helpers
// ─────────────────────────────────────────────────────────
static NSMutableArray *getSavedAccounts(void) {
    NSArray *a = [[NSUserDefaults standardUserDefaults] arrayForKey:kSavedAccountsKey];
    return a ? [a mutableCopy] : [NSMutableArray new];
}
static void writeSavedAccounts(NSArray *arr) {
    [[NSUserDefaults standardUserDefaults] setObject:arr forKey:kSavedAccountsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
static NSMutableArray *getRemovedAccounts(void) {
    NSArray *a = [[NSUserDefaults standardUserDefaults] arrayForKey:kRemovedAccountsKey];
    return a ? [a mutableCopy] : [NSMutableArray new];
}
static void writeRemovedAccounts(NSArray *arr) {
    [[NSUserDefaults standardUserDefaults] setObject:arr forKey:kRemovedAccountsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
static NSDictionary *parseAccountLine(NSString *line) {
    NSArray *parts = [line componentsSeparatedByString:@"|"];
    if (parts.count >= 4) {
        return @{
            @"email": [parts[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet],
            @"pass":  [parts[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet],
            @"uid":   [parts[2] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet],
            @"token": [parts[3] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        };
    }
    return nil;
}

// ─────────────────────────────────────────────────────────
//  Apply account switch
// ─────────────────────────────────────────────────────────
static void applySwitchAccount(NSDictionary *acc) {
    NSString *token  = acc[@"token"];
    NSString *uidStr = acc[@"uid"];
    NSString *email  = acc[@"email"];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *raw = [ud stringForKey:@"SdkStateCache#1"];
    if (raw) {
        NSError *err = nil;
        NSMutableDictionary *root = [[NSJSONSerialization JSONObjectWithData:
            [raw dataUsingEncoding:NSUTF8StringEncoding]
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
            if (!err && out) {
                [ud setObject:[[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding]
                       forKey:@"SdkStateCache#1"];
                [ud synchronize];
            }
        }
    }

    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *t in @[@"bp_data", @"item_data", @"misc_data",
                           @"season_data", @"statistic_data", @"weapon_evolution_data"]) {
        NSString *src = [docs stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_1_.data", t]];
        NSString *dst = [docs stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%@_.data", t, uidStr]];
        if ([fm fileExistsAtPath:src]) {
            [fm removeItemAtPath:dst error:nil];
            [fm copyItemAtPath:src toPath:dst error:nil];
        }
    }
}

// ─────────────────────────────────────────────────────────
//  Top-most view controller helper
// ─────────────────────────────────────────────────────────
static UIViewController *topViewController(void) {
    UIViewController *vc = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) { vc = w.rootViewController; break; }
                }
            }
        }
    }
    if (!vc) vc = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

// ─────────────────────────────────────────────────────────
//  Input view controller
// ─────────────────────────────────────────────────────────
@interface TweakInputVC : UIViewController
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, copy)   void (^onSave)(NSString *text);
@end

@implementation TweakInputVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.97];

    UILabel *title = [UILabel new];
    title.text = @"Add Accounts";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:16];
    title.textAlignment = NSTextAlignmentCenter;

    UILabel *hint = [UILabel new];
    hint.text = @"One per line:  email|pass|uid|token";
    hint.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    hint.font = [UIFont systemFontOfSize:12];
    hint.textAlignment = NSTextAlignmentCenter;

    self.textView = [UITextView new];
    self.textView.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
    self.textView.textColor = [UIColor colorWithRed:0.4 green:1.0 blue:0.6 alpha:1];
    self.textView.font = [UIFont fontWithName:@"Courier" size:13] ?: [UIFont systemFontOfSize:13];
    self.textView.layer.cornerRadius = 8;
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textView.keyboardType = UIKeyboardTypeASCIICapable;

    UIButton *saveBtn   = [self makeBtn:@"Save"   bg:[UIColor colorWithRed:0.2 green:0.7 blue:0.4 alpha:1]];
    UIButton *cancelBtn = [self makeBtn:@"Cancel" bg:[UIColor colorWithRed:0.65 green:0.2 blue:0.2 alpha:1]];
    [saveBtn   addTarget:self action:@selector(doSave)   forControlEvents:UIControlEventTouchUpInside];
    [cancelBtn addTarget:self action:@selector(doCancel) forControlEvents:UIControlEventTouchUpInside];

    for (UIView *v in @[title, hint, self.textView, saveBtn, cancelBtn]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:v];
    }
    UIView *sv = self.view;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:sv.safeAreaLayoutGuide.topAnchor constant:16],
        [title.leadingAnchor constraintEqualToAnchor:sv.leadingAnchor constant:16],
        [title.trailingAnchor constraintEqualToAnchor:sv.trailingAnchor constant:-16],
        [hint.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [hint.leadingAnchor constraintEqualToAnchor:sv.leadingAnchor constant:16],
        [hint.trailingAnchor constraintEqualToAnchor:sv.trailingAnchor constant:-16],
        [self.textView.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:10],
        [self.textView.leadingAnchor constraintEqualToAnchor:sv.leadingAnchor constant:16],
        [self.textView.trailingAnchor constraintEqualToAnchor:sv.trailingAnchor constant:-16],
        [self.textView.bottomAnchor constraintEqualToAnchor:saveBtn.topAnchor constant:-12],
        [saveBtn.bottomAnchor constraintEqualToAnchor:sv.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [saveBtn.trailingAnchor constraintEqualToAnchor:sv.trailingAnchor constant:-16],
        [saveBtn.widthAnchor constraintEqualToConstant:100],
        [saveBtn.heightAnchor constraintEqualToConstant:44],
        [cancelBtn.bottomAnchor constraintEqualToAnchor:saveBtn.bottomAnchor],
        [cancelBtn.trailingAnchor constraintEqualToAnchor:saveBtn.leadingAnchor constant:-8],
        [cancelBtn.widthAnchor constraintEqualToConstant:100],
        [cancelBtn.heightAnchor constraintEqualToConstant:44],
    ]];
}
- (UIButton *)makeBtn:(NSString *)t bg:(UIColor *)c {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.backgroundColor = c;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    b.layer.cornerRadius = 8;
    return b;
}
- (void)doSave {
    if (self.onSave) self.onSave(self.textView.text);
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)doCancel { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

// ─────────────────────────────────────────────────────────
//  Overlay UIWindow (pass-through on empty areas)
// ─────────────────────────────────────────────────────────
@interface TweakOverlayWindow : UIWindow
@end
@implementation TweakOverlayWindow
- (UIView *)hitTest:(CGPoint)pt withEvent:(UIEvent *)e {
    UIView *hit = [super hitTest:pt withEvent:e];
    // Pass through taps that land directly on the window or root view
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}
@end

// ─────────────────────────────────────────────────────────
//  Floating Panel  (draggable)
// ─────────────────────────────────────────────────────────
@interface TweakPanel : UIView
@end
@implementation TweakPanel

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, 180, 44)];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.60];
    self.layer.cornerRadius  = 11;
    self.layer.borderWidth   = 0.5;
    self.layer.borderColor   = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
    self.layer.shadowColor   = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.5;
    self.layer.shadowOffset  = CGSizeMake(0, 3);
    self.layer.shadowRadius  = 6;
    [self buildButtons];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(drag:)];
    [self addGestureRecognizer:pan];
    return self;
}

- (void)buildButtons {
    NSArray *titles = @[@"Input", @"Edit", @"Export"];
    NSArray *colors = @[
        [UIColor colorWithRed:0.18 green:0.52 blue:1.0  alpha:1],
        [UIColor colorWithRed:0.14 green:0.76 blue:0.36 alpha:1],
        [UIColor colorWithRed:1.0  green:0.46 blue:0.14 alpha:1],
    ];
    SEL sels[3] = { @selector(tapInput), @selector(tapEdit), @selector(tapExport) };
    CGFloat bw = 53, bh = 34, gap = 4, x = 5;
    for (int i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(x + i*(bw+gap), 5, bw, bh);
        b.backgroundColor = colors[i];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.layer.cornerRadius = 7;
        [b addTarget:self action:sels[i] forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
    }
}

- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint d = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + d.x, self.center.y + d.y);
    [g setTranslation:CGPointZero inView:self.superview];
}

// ── Input ─────────────────────────────────────────────────────────
- (void)tapInput {
    TweakInputVC *ivc = [TweakInputVC new];
    ivc.modalPresentationStyle = UIModalPresentationPageSheet;
    ivc.onSave = ^(NSString *text) {
        NSMutableArray *accounts = getSavedAccounts();
        NSUInteger before = accounts.count;
        NSArray *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
        for (NSString *raw in lines) {
            NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!line.length) continue;
            NSDictionary *acc = parseAccountLine(line);
            if (!acc) continue;
            BOOL dup = NO;
            for (NSDictionary *e in accounts)
                if ([e[@"uid"] isEqualToString:acc[@"uid"]]) { dup=YES; break; }
            if (!dup) [accounts addObject:acc];
        }
        writeSavedAccounts(accounts);
        UIAlertController *ok = [UIAlertController
            alertControllerWithTitle:@"Saved"
            message:[NSString stringWithFormat:@"Added %lu new account(s).\nTotal saved: %lu",
                     (unsigned long)(accounts.count-before), (unsigned long)accounts.count]
            preferredStyle:UIAlertControllerStyleAlert];
        [ok addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topViewController() presentViewController:ok animated:YES completion:nil];
    };
    [topViewController() presentViewController:ivc animated:YES completion:nil];
}

// ── Edit ──────────────────────────────────────────────────────────
- (void)tapEdit {
    NSMutableArray *accounts = getSavedAccounts();
    if (!accounts.count) {
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:@"No Accounts"
            message:@"Use [Input] to add accounts first."
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topViewController() presentViewController:a animated:YES completion:nil];
        return;
    }

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:@"Switch Account"
        message:@"Tap to apply. Account is removed from list."
        preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSDictionary *acc in accounts) {
        NSString *label = [NSString stringWithFormat:@"%@  (uid: %@)", acc[@"email"], acc[@"uid"]];
        [sheet addAction:[UIAlertAction actionWithTitle:label
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *_) {
                NSMutableArray *cur = getSavedAccounts();
                NSMutableArray *rem = getRemovedAccounts();
                [cur removeObject:acc];
                [rem addObject:acc];
                writeSavedAccounts(cur);
                writeRemovedAccounts(rem);

                applySwitchAccount(acc);

                UIAlertController *res = [UIAlertController
                    alertControllerWithTitle:@"✅ Switched"
                    message:[NSString stringWithFormat:
                        @"Email : %@\nUID   : %@\nToken : %@\n\n"
                        @"• SdkStateCache#1 patched\n• Save files copied with UID suffix",
                        acc[@"email"], acc[@"uid"], acc[@"token"]]
                    preferredStyle:UIAlertControllerStyleAlert];
                [res addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [topViewController() presentViewController:res animated:YES completion:nil];
            }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *top = topViewController();
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = top.view;
        sheet.popoverPresentationController.sourceRect =
            CGRectMake(top.view.bounds.size.width/2, 100, 1, 1);
    }
    [top presentViewController:sheet animated:YES completion:nil];
}

// ── Export ────────────────────────────────────────────────────────
- (void)tapExport {
    NSMutableArray *removed = getRemovedAccounts();
    if (!removed.count) {
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:@"Nothing to Export"
            message:@"No used accounts yet. Use [Edit] first."
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topViewController() presentViewController:a animated:YES completion:nil];
        return;
    }

    NSMutableString *out = [NSMutableString new];
    for (NSDictionary *acc in removed)
        [out appendFormat:@"%@|%@\n", acc[@"email"], acc[@"pass"]];

    [UIPasteboard generalPasteboard].string = out;
    writeRemovedAccounts(@[]);

    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"📋 Exported %lu", (unsigned long)removed.count]
        message:[NSString stringWithFormat:@"Copied to clipboard:\n\n%@", out]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:nil]];
    [topViewController() presentViewController:a animated:YES completion:nil];
}

@end

// ─────────────────────────────────────────────────────────
//  Global overlay window
// ─────────────────────────────────────────────────────────
static TweakOverlayWindow *gOverlayWindow = nil;
static BOOL gInstalled = NO;

static void installPanel(void) {
    if (gInstalled) return;
    gInstalled = YES;

    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
        if (scene) {
            gOverlayWindow = [[TweakOverlayWindow alloc] initWithWindowScene:scene];
        }
    }
    if (!gOverlayWindow) {
        gOverlayWindow = [[TweakOverlayWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    }

    gOverlayWindow.windowLevel = UIWindowLevelStatusBar + 200;
    gOverlayWindow.backgroundColor = UIColor.clearColor;
    gOverlayWindow.userInteractionEnabled = YES;

    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    gOverlayWindow.rootViewController = root;
    gOverlayWindow.hidden = NO;

    TweakPanel *panel = [TweakPanel new];
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    panel.center = CGPointMake(sw - panel.frame.size.width/2 - 10, 88);
    [gOverlayWindow addSubview:panel];

    NSLog(@"[TweakPanel] ✅ Panel installed on overlay window");
}

// ─────────────────────────────────────────────────────────
//  Hook: applicationDidBecomeActive (most reliable trigger)
// ─────────────────────────────────────────────────────────
%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)app {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gInstalled) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5*NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                installPanel();
            });
        }
    });
}
%end
