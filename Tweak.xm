// tweak.xm — Soul Knight Account Manager Tweak
// Adds 3 floating buttons: [Input] [Edit] [Export]
// Compatible with iOS 14+ | Theos/Logos

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ─────────────────────────────────────────────
//  Storage Keys  (stored in app's own NSUserDefaults)
// ─────────────────────────────────────────────
#define kSavedAccountsKey   @"__TweakSavedAccounts__"
#define kRemovedAccountsKey @"__TweakRemovedAccounts__"

// ─────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────
static NSDictionary *parseAccountLine(NSString *line) {
    NSArray *parts = [line componentsSeparatedByString:@"|"];
    if (parts.count >= 4) {
        return @{
            @"email" : [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]],
            @"pass"  : [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]],
            @"uid"   : [parts[2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]],
            @"token" : [parts[3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        };
    }
    return nil;
}

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

// Apply token + playerId into SdkStateCache#1 and copy save files
static void applySwitchAccount(NSDictionary *acc) {
    NSUserDefaults *ud     = [NSUserDefaults standardUserDefaults];
    NSString       *token  = acc[@"token"];
    NSString       *uidStr = acc[@"uid"];
    NSString       *email  = acc[@"email"];

    // ── 1. Patch SdkStateCache#1 ──────────────────────────────────────
    NSString *raw = [ud stringForKey:@"SdkStateCache#1"];
    if (raw) {
        NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
        NSError *err = nil;
        NSMutableDictionary *root = [[NSJSONSerialization JSONObjectWithData:data
                                       options:NSJSONReadingMutableContainers
                                       error:&err] mutableCopy];
        if (!err && root) {
            NSMutableDictionary *user    = [root[@"User"]    mutableCopy] ?: [NSMutableDictionary new];
            NSMutableDictionary *session = [root[@"Session"] mutableCopy] ?: [NSMutableDictionary new];
            NSMutableDictionary *legacy  = [user[@"LegacyGateway"] mutableCopy] ?: [NSMutableDictionary new];

            // Patch token
            legacy[@"token"]        = token;
            user[@"LegacyGateway"]  = legacy;

            // Patch email & PlayerId
            user[@"Email"]          = email;
            user[@"PlayerId"]       = @([uidStr longLongValue]);

            // Patch session
            session[@"Token"]       = token;

            root[@"User"]           = user;
            root[@"Session"]        = session;

            NSData *out = [NSJSONSerialization dataWithJSONObject:root
                                                         options:NSJSONWritingPrettyPrinted
                                                           error:&err];
            if (!err && out) {
                [ud setObject:[[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding]
                       forKey:@"SdkStateCache#1"];
                [ud synchronize];
            }
        }
    }

    // ── 2. Copy save files  bp_data_1_.data → bp_data_{uid}_.data ─────
    NSString     *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSFileManager *fm  = [NSFileManager defaultManager];
    NSArray *types = @[@"bp_data", @"item_data", @"misc_data",
                       @"season_data", @"statistic_data", @"weapon_evolution_data"];

    for (NSString *t in types) {
        NSString *src = [docs stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"%@_1_.data", t]];
        NSString *dst = [docs stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"%@_%@_.data", t, uidStr]];
        if ([fm fileExistsAtPath:src]) {
            [fm removeItemAtPath:dst error:nil];
            NSError *cpErr = nil;
            [fm copyItemAtPath:src toPath:dst error:&cpErr];
            if (cpErr) NSLog(@"[Tweak] copy %@ → %@ failed: %@", src, dst, cpErr);
        }
    }
}

// ─────────────────────────────────────────────
//  Input VC  (multiline UITextView modal)
// ─────────────────────────────────────────────
@interface TweakInputVC : UIViewController <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, copy)   void (^onSave)(NSString *text);
@end

@implementation TweakInputVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.97];

    UILabel *title = [UILabel new];
    title.text = @"Add Accounts";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    UILabel *hint = [UILabel new];
    hint.text = @"One account per line:   email|pass|uid|token";
    hint.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    hint.font = [UIFont systemFontOfSize:12];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:hint];

    self.textView = [UITextView new];
    self.textView.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
    self.textView.textColor = [UIColor colorWithRed:0.4 green:1.0 blue:0.6 alpha:1];
    self.textView.font = [UIFont fontWithName:@"Courier" size:13] ?: [UIFont systemFontOfSize:13];
    self.textView.layer.cornerRadius = 8;
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.textView];

    UIButton *saveBtn   = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [saveBtn   setTitle:@"Save"   forState:UIControlStateNormal];
    [cancelBtn setTitle:@"Cancel" forState:UIControlStateNormal];
    saveBtn.backgroundColor   = [UIColor colorWithRed:0.2 green:0.7 blue:0.4 alpha:1];
    cancelBtn.backgroundColor = [UIColor colorWithRed:0.6 green:0.2 blue:0.2 alpha:1];
    [saveBtn   setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [cancelBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    saveBtn.layer.cornerRadius   = 8;
    cancelBtn.layer.cornerRadius = 8;
    saveBtn.translatesAutoresizingMaskIntoConstraints   = NO;
    cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:saveBtn];
    [self.view addSubview:cancelBtn];
    [saveBtn   addTarget:self action:@selector(doSave)   forControlEvents:UIControlEventTouchUpInside];
    [cancelBtn addTarget:self action:@selector(doCancel) forControlEvents:UIControlEventTouchUpInside];

    UIView *v = self.view;
    NSDictionary *views = NSDictionaryOfVariableBindings(title, hint, _textView, saveBtn, cancelBtn);
    [v addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(16)-[title]-(16)-|" options:0 metrics:nil views:views]];
    [v addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(16)-[hint]-(16)-|" options:0 metrics:nil views:views]];
    [v addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(16)-[_textView]-(16)-|" options:0 metrics:nil views:views]];
    [v addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(16)-[cancelBtn]-(8)-[saveBtn(==cancelBtn)]-(16)-|" options:0 metrics:nil views:views]];
    [v addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(50)-[title(30)]-(6)-[hint(20)]-(10)-[_textView]-(12)-[saveBtn(44)]-(30)-|" options:0 metrics:nil views:views]];
    [v addConstraint:[NSLayoutConstraint constraintWithItem:cancelBtn attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:saveBtn attribute:NSLayoutAttributeTop multiplier:1 constant:0]];
    [v addConstraint:[NSLayoutConstraint constraintWithItem:cancelBtn attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:saveBtn attribute:NSLayoutAttributeHeight multiplier:1 constant:0]];
}
- (void)doSave {
    if (self.onSave) self.onSave(self.textView.text);
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)doCancel { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

// ─────────────────────────────────────────────
//  Floating Panel  (draggable)
// ─────────────────────────────────────────────
@interface TweakFloatingPanel : UIView
+ (void)installOnWindow:(UIWindow *)window;
@end

@implementation TweakFloatingPanel {
    CGPoint _lastTouch;
}

+ (void)installOnWindow:(UIWindow *)window {
    CGFloat w = 175, h = 40;
    CGFloat x = window.bounds.size.width - w - 8;
    CGFloat y = 80;
    TweakFloatingPanel *panel = [[TweakFloatingPanel alloc] initWithFrame:CGRectMake(x, y, w, h)];
    panel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    [window addSubview:panel];
    window.windowLevel = UIWindowLevelAlert + 1;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.zPosition = 999999;
        [self buildButtons];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)buildButtons {
    struct { NSString *title; NSString *hex; SEL sel; } defs[3] = {
        { @"Input",  @"hex", @selector(tapInput)  },
        { @"Edit",   @"hex", @selector(tapEdit)   },
        { @"Export", @"hex", @selector(tapExport) }
    };
    UIColor *colors[3] = {
        [UIColor colorWithRed:0.18 green:0.55 blue:1.00 alpha:0.92],
        [UIColor colorWithRed:0.18 green:0.78 blue:0.38 alpha:0.92],
        [UIColor colorWithRed:1.00 green:0.48 blue:0.16 alpha:0.92]
    };
    CGFloat bw = 54, bh = 36, gap = 3.5, startX = 2;
    for (int i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(startX + i * (bw + gap), 2, bw, bh);
        b.backgroundColor = colors[i];
        [b setTitle:defs[i].title forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        b.layer.cornerRadius = 7;
        b.layer.shadowColor  = [UIColor blackColor].CGColor;
        b.layer.shadowOpacity = 0.4;
        b.layer.shadowOffset  = CGSizeMake(0, 2);
        [b addTarget:self action:defs[i].sel forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
    }
}

// Drag support
- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint delta = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + delta.x, self.center.y + delta.y);
    [g setTranslation:CGPointZero inView:self.superview];
}

- (UIViewController *)topVC {
    UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

// ─── Input ──────────────────────────────────────────────────────────────────
- (void)tapInput {
    TweakInputVC *ivc = [TweakInputVC new];
    ivc.modalPresentationStyle = UIModalPresentationFormSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = ivc.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.largeDetent];
    }

    ivc.onSave = ^(NSString *text) {
        NSMutableArray *accounts = getSavedAccounts();
        NSUInteger before = accounts.count;

        NSArray *lines = [text componentsSeparatedByCharactersInSet:
                          [NSCharacterSet newlineCharacterSet]];
        for (NSString *line in lines) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!trimmed.length) continue;
            NSDictionary *acc = parseAccountLine(trimmed);
            if (!acc) continue;
            BOOL dup = NO;
            for (NSDictionary *e in accounts)
                if ([e[@"uid"] isEqualToString:acc[@"uid"]]) { dup = YES; break; }
            if (!dup) [accounts addObject:acc];
        }
        writeSavedAccounts(accounts);

        UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"Saved"
            message:[NSString stringWithFormat:@"Added %lu new account(s). Total: %lu",
                     (unsigned long)(accounts.count - before),
                     (unsigned long)accounts.count]
            preferredStyle:UIAlertControllerStyleAlert];
        [ok addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[self topVC] presentViewController:ok animated:YES completion:nil];
    };

    [[self topVC] presentViewController:ivc animated:YES completion:nil];
}

// ─── Edit ───────────────────────────────────────────────────────────────────
- (void)tapEdit {
    NSMutableArray *accounts = getSavedAccounts();
    if (!accounts.count) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"No Accounts"
            message:@"No saved accounts. Use [Input] first."
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[self topVC] presentViewController:a animated:YES completion:nil];
        return;
    }

    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Choose Account"
        message:@"Tap an account to switch to it.\nIt will be removed from the saved list."
        preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSDictionary *acc in accounts) {
        NSString *label = [NSString stringWithFormat:@"%@  (uid: %@)", acc[@"email"], acc[@"uid"]];
        [picker addAction:[UIAlertAction actionWithTitle:label
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *_) {
            // Remove from saved → move to removed
            NSMutableArray *cur     = getSavedAccounts();
            NSMutableArray *removed = getRemovedAccounts();
            [cur removeObject:acc];
            [removed addObject:acc];
            writeSavedAccounts(cur);
            writeRemovedAccounts(removed);

            // Patch NSUserDefaults + copy save files
            applySwitchAccount(acc);

            NSString *info = [NSString stringWithFormat:
                @"✓ Switched to:\nEmail : %@\nUID   : %@\nToken : %@\n\nNSUserDefaults patched.\nSave files backed up.",
                acc[@"email"], acc[@"uid"], acc[@"token"]];

            UIAlertController *res = [UIAlertController alertControllerWithTitle:@"Account Applied"
                message:info preferredStyle:UIAlertControllerStyleAlert];
            [res addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [[self topVC] presentViewController:res animated:YES completion:nil];
        }]];
    }

    [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    // iPad popover fix
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        picker.popoverPresentationController.sourceView  = self;
        picker.popoverPresentationController.sourceRect  = self.bounds;
        picker.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }

    [[self topVC] presentViewController:picker animated:YES completion:nil];
}

// ─── Export ─────────────────────────────────────────────────────────────────
- (void)tapExport {
    NSMutableArray *removed = getRemovedAccounts();
    if (!removed.count) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Nothing to Export"
            message:@"No removed accounts yet. Use [Edit] first."
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[self topVC] presentViewController:a animated:YES completion:nil];
        return;
    }

    NSMutableString *out = [NSMutableString new];
    for (NSDictionary *acc in removed)
        [out appendFormat:@"%@|%@\n", acc[@"email"], acc[@"pass"]];

    // Copy to clipboard
    [UIPasteboard generalPasteboard].string = out;

    // Clear removed list
    writeRemovedAccounts(@[]);

    UIAlertController *a = [UIAlertController alertControllerWithTitle:
        [NSString stringWithFormat:@"Exported %lu Account(s)", (unsigned long)removed.count]
        message:[NSString stringWithFormat:@"Copied to clipboard:\n\n%@", out]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:nil]];
    [[self topVC] presentViewController:a animated:YES completion:nil];
}

@end

// ─────────────────────────────────────────────
//  Hook — inject panel once window is ready
// ─────────────────────────────────────────────
%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [TweakFloatingPanel installOnWindow:self];
        });
    });
}
%end
