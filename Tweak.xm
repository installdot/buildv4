// tweak.xm — Soul Knight Account Switcher
// iOS 14+ | Theos/Logos | ARC

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

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
    void (^b)(void) = objc_getAssociatedObject(self, &kSKActionBlockKey);
    if (b) b();
}
@end

#pragma mark - Export storage

static NSString *exportsPath(void) {
    return [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Preferences/SKAccountExports.plist"];
}
static NSMutableArray *getExports(void) {
    NSArray *a = [NSArray arrayWithContentsOfFile:exportsPath()];
    return a ? [a mutableCopy] : [NSMutableArray new];
}
static void writeExports(NSArray *a) {
    [a writeToFile:exportsPath() atomically:YES];
}

#pragma mark - Line parser

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

#pragma mark - Reload UserDefaults from disk (simulate fresh game load)

static void reloadUserDefaultsFromDisk(void) {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    if (!bid) return;

    // Path to the plist file on disk that NSUserDefaults writes to
    NSString *prefsPath = [NSString stringWithFormat:
        @"%@/Library/Preferences/%@.plist", NSHomeDirectory(), bid];

    // Tell CFPreferences to release its in-memory cache and re-read from disk
    CFPreferencesSynchronize((__bridge CFStringRef)bid,
                             kCFPreferencesCurrentUser,
                             kCFPreferencesAnyHost);

    // Force NSUserDefaults to drop its in-memory snapshot
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud synchronize];

    // Re-read the plist from disk and push every key back into NSUserDefaults
    // so that any observer / KVO / the game's own cached pointers see new values
    NSDictionary *fresh = [NSDictionary dictionaryWithContentsOfFile:prefsPath];
    if (fresh) {
        // Remove keys that are no longer in the fresh snapshot
        NSDictionary *current = [ud dictionaryRepresentation];
        for (NSString *k in current) {
            if (!fresh[k]) [ud removeObjectForKey:k];
        }
        // Write fresh values
        for (NSString *k in fresh) {
            [ud setObject:fresh[k] forKey:k];
        }
        [ud synchronize];
    }

    // Post a notification so any in-game listener can react
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSUserDefaultsDidChangeNotification
                      object:[NSUserDefaults standardUserDefaults]];
}

#pragma mark - Account Apply

static void applyAccount(NSDictionary *acc) {
    NSString *newToken = acc[@"token"];
    NSString *newEmail = acc[@"email"];
    NSString *newUid   = acc[@"uid"];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    // ── Patch SdkStateCache#2 ─────────────────────────────────────────────────
    NSString *raw2 = [ud stringForKey:@"SdkStateCache#2"];
    if (raw2) {
        NSError *je = nil;
        NSMutableDictionary *root = [[NSJSONSerialization
            JSONObjectWithData:[raw2 dataUsingEncoding:NSUTF8StringEncoding]
            options:NSJSONReadingMutableContainers error:&je] mutableCopy];
        if (!je && root) {
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
                options:NSJSONWritingPrettyPrinted error:&je];
            if (!je && out)
                [ud setObject:[[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding]
                       forKey:@"SdkStateCache#2"];
        }
    }

    // ── Remove conflicting keys ───────────────────────────────────────────────
    [ud removeObjectForKey:@"LastLoginUid"];
    [ud removeObjectForKey:@"emptyLocalCloudSaveId"];

    // ── Flush to disk ─────────────────────────────────────────────────────────
    [ud synchronize];

    // ── Reload from disk so in-memory state matches what game reads on launch ──
    reloadUserDefaultsFromDisk();
}

#pragma mark - Remote fetch

static NSData *buildMultipartBody(void) {
    NSString *boundary = @"----WebKitFormBoundaryfGWYLKxAiP6gsfSo";
    NSMutableString *s = [NSMutableString new];
    void (^field)(NSString *, NSString *) = ^(NSString *name, NSString *val) {
        [s appendFormat:@"--%@\r\n", boundary];
        [s appendFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", name];
        [s appendFormat:@"%@\r\n", val];
    };
    field(@"action",   @"check");
    field(@"limit",    @"1");
    field(@"parallel", @"10");
    [s appendFormat:@"--%@--\r\n", boundary];
    return [s dataUsingEncoding:NSUTF8StringEncoding];
}

static void fetchRemoteAccount(void (^completion)(NSDictionary *acc, NSString *errMsg)) {
    NSURL *url = [NSURL URLWithString:@"https://chillysilly.frfrnocap.men/ccacc.php"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
        timeoutInterval:20];
    req.HTTPMethod = @"POST";

    NSString *boundary = @"----WebKitFormBoundaryfGWYLKxAiP6gsfSo";
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]
       forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"*/*"               forHTTPHeaderField:@"Accept"];
    [req setValue:@"vi-VN,vi;q=0.9"   forHTTPHeaderField:@"Accept-Language"];
    [req setValue:@"gzip, deflate, br" forHTTPHeaderField:@"Accept-Encoding"];
    [req setValue:@"cors"              forHTTPHeaderField:@"Sec-Fetch-Mode"];
    [req setValue:@"same-origin"       forHTTPHeaderField:@"Sec-Fetch-Site"];
    [req setValue:@"empty"             forHTTPHeaderField:@"Sec-Fetch-Dest"];
    [req setValue:@"https://chillysilly.frfrnocap.men" forHTTPHeaderField:@"Origin"];
    [req setValue:@"https://chillysilly.frfrnocap.men/ccacc.php" forHTTPHeaderField:@"Referer"];
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 16_6_1 like Mac OS X) "
                   "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
       forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"PHPSESSID=883a6ee3b496cc69822e2144d57cc886; "
                   "token=cf54cf6152d9ae63b1daccc7af669a1d"
       forHTTPHeaderField:@"Cookie"];

    req.HTTPBody = buildMultipartBody();

    NSURLSession *session = [NSURLSession sessionWithConfiguration:
        [NSURLSessionConfiguration defaultSessionConfiguration]];
    [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err || !data) {
                completion(nil, err.localizedDescription ?: @"Network error");
                return;
            }
            NSError *je = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&je];
            if (je || ![json isKindOfClass:[NSDictionary class]]) {
                NSString *raw = [[NSString alloc] initWithData:data
                    encoding:NSUTF8StringEncoding] ?: @"Bad response";
                completion(nil, raw);
                return;
            }
            NSArray *lines = json[@"lines"];
            if (!lines.count) {
                completion(nil, @"No accounts returned\n(file may be empty)");
                return;
            }
            NSDictionary *acc = parseLine(lines[0]);
            if (!acc) {
                completion(nil, [NSString stringWithFormat:@"Could not parse:\n%@", lines[0]]);
                return;
            }
            NSMutableDictionary *m = [acc mutableCopy];
            NSNumber *rem = json[@"remaining_in_file"];
            if (rem) m[@"remaining"] = [rem stringValue];
            completion([m copy], nil);
        });
    }] resume];
}

#pragma mark - Panel dimensions

static const CGFloat kPanelW   = 210;
static const CGFloat kBarH     = 36;
static const CGFloat kBtnH     = 36;
static const CGFloat kBtnGap   = 6;
static const CGFloat kPad      = 6;
static const CGFloat kContentH = 22 + 12 + (kBtnH * 2) + (kBtnGap * 1) + 10;

#pragma mark - SKPanel

@interface SKPanel : UIView
@property (nonatomic, strong) UIView   *contentPane;
@property (nonatomic, strong) UILabel  *infoLabel;
@property (nonatomic, strong) UILabel  *statusLabel;
@property (nonatomic, strong) UIButton *fetchBtn;
@property (nonatomic, assign) BOOL     expanded;
@end

@implementation SKPanel

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, kPanelW, kBarH)];
    if (!self) return nil;
    self.clipsToBounds      = NO;
    self.layer.cornerRadius = 10;
    self.backgroundColor    = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:0.96];
    self.layer.shadowColor   = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.75;
    self.layer.shadowRadius  = 8;
    self.layer.shadowOffset  = CGSizeMake(0, 3);
    self.layer.zPosition     = 9999;
    [self buildBar];
    [self buildContent];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(onPan:)];
    [self addGestureRecognizer:pan];
    return self;
}

- (void)buildBar {
    UIView *handle = [[UIView alloc] initWithFrame:CGRectMake(kPanelW/2-16, 5, 32, 3)];
    handle.backgroundColor    = [UIColor colorWithWhite:0.50 alpha:0.45];
    handle.layer.cornerRadius = 1.5;
    [self addSubview:handle];

    UILabel *title = [UILabel new];
    title.text          = @"SK Manager";
    title.textColor     = [UIColor colorWithWhite:0.78 alpha:1];
    title.font          = [UIFont boldSystemFontOfSize:11];
    title.textAlignment = NSTextAlignmentCenter;
    title.frame         = CGRectMake(0, 12, kPanelW, 18);
    title.userInteractionEnabled = NO;
    [self addSubview:title];

    UIView *tapZone = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPanelW, kBarH)];
    tapZone.backgroundColor = UIColor.clearColor;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(toggleExpand)];
    [tapZone addGestureRecognizer:tap];
    [self addSubview:tapZone];
}

- (void)buildContent {
    self.contentPane = [[UIView alloc]
        initWithFrame:CGRectMake(0, kBarH, kPanelW, kContentH)];
    self.contentPane.hidden        = YES;
    self.contentPane.alpha         = 0;
    self.contentPane.clipsToBounds = YES;
    [self addSubview:self.contentPane];

    UIView  *p = self.contentPane;
    CGFloat w  = kPanelW - kPad * 2;
    CGFloat y  = 6;

    self.infoLabel = [UILabel new];
    self.infoLabel.frame         = CGRectMake(kPad, y, w, 12);
    self.infoLabel.textColor     = [UIColor colorWithWhite:0.52 alpha:1];
    self.infoLabel.font          = [UIFont systemFontOfSize:9];
    self.infoLabel.textAlignment = NSTextAlignmentCenter;
    [p addSubview:self.infoLabel];
    [self refreshInfo];
    y += 14;

    self.statusLabel = [UILabel new];
    self.statusLabel.frame         = CGRectMake(kPad, y, w, 10);
    self.statusLabel.font          = [UIFont systemFontOfSize:8];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor     = [UIColor colorWithWhite:0.45 alpha:1];
    self.statusLabel.text          = @"Ready";
    self.statusLabel.numberOfLines = 2;
    [p addSubview:self.statusLabel];
    y += 14;

    UIButton *(^makeBtn)(NSString *, UIColor *) = ^(NSString *t, UIColor *bg) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(kPad, y, w, kBtnH);
        [b setTitle:t forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [b setTitleColor:[UIColor colorWithWhite:0.75 alpha:1] forState:UIControlStateHighlighted];
        b.titleLabel.font    = [UIFont boldSystemFontOfSize:11];
        b.backgroundColor    = bg;
        b.layer.cornerRadius = 7;
        return b;
    };

    self.fetchBtn = makeBtn(@"Fetch & Apply",
        [UIColor colorWithRed:0.18 green:0.72 blue:0.38 alpha:1]);
    [self.fetchBtn addTarget:self action:@selector(tapFetch)
           forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:self.fetchBtn];
    y += kBtnH + kBtnGap;

    UIButton *expBtn = makeBtn(@"Export (copy to clipboard)",
        [UIColor colorWithRed:1.00 green:0.46 blue:0.16 alpha:1]);
    expBtn.frame = CGRectMake(kPad, y, w, kBtnH);
    [expBtn addTarget:self action:@selector(tapExport)
     forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:expBtn];
}

- (void)refreshInfo {
    self.infoLabel.text = [NSString stringWithFormat:@"Saved: %lu account(s)",
                           (unsigned long)getExports().count];
}

- (void)setStatus:(NSString *)text color:(UIColor *)color {
    self.statusLabel.text      = text;
    self.statusLabel.textColor = color;
}

- (void)toggleExpand {
    self.expanded = !self.expanded;
    if (self.expanded) {
        self.contentPane.hidden = NO;
        self.contentPane.frame  = CGRectMake(0, kBarH, kPanelW, kContentH);
        [UIView animateWithDuration:0.22 delay:0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            CGRect f = self.frame; f.size.height = kBarH + kContentH; self.frame = f;
            self.contentPane.alpha = 1;
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.18 delay:0
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
            CGRect f = self.frame; f.size.height = kBarH; self.frame = f;
            self.contentPane.alpha = 0;
        } completion:^(BOOL _) { self.contentPane.hidden = YES; }];
    }
}

- (void)tapFetch {
    self.fetchBtn.enabled = NO;
    [self.fetchBtn setTitle:@"Fetching…" forState:UIControlStateNormal];
    self.fetchBtn.backgroundColor = [UIColor colorWithWhite:0.28 alpha:1];
    [self setStatus:@"Contacting server…"
              color:[UIColor colorWithWhite:0.55 alpha:1]];

    fetchRemoteAccount(^(NSDictionary *acc, NSString *errMsg) {
        self.fetchBtn.enabled = YES;
        [self.fetchBtn setTitle:@"Fetch & Apply" forState:UIControlStateNormal];
        self.fetchBtn.backgroundColor = [UIColor colorWithRed:0.18 green:0.72 blue:0.38 alpha:1];

        if (!acc) {
            [self setStatus:[NSString stringWithFormat:@"Error: %@", errMsg]
                      color:[UIColor colorWithRed:0.90 green:0.30 blue:0.30 alpha:1]];
            [self showToast:[NSString stringWithFormat:@"Fetch failed:\n%@", errMsg] success:NO];
            return;
        }
        [self showConfirmCard:acc];
    });
}

- (void)tapExport {
    NSMutableArray *exports = getExports();
    if (!exports.count) {
        [self showToast:@"Nothing to export.\nFetch & apply an account first." success:NO];
        return;
    }
    NSMutableString *out = [NSMutableString new];
    for (NSDictionary *a in exports)
        [out appendFormat:@"%@|%@\n", a[@"email"], a[@"pass"]];
    [UIPasteboard generalPasteboard].string = out;
    writeExports(@[]);
    [self refreshInfo];
    [self setStatus:@"Exported & cleared"
              color:[UIColor colorWithRed:0.28 green:0.82 blue:0.42 alpha:1]];
    [self showToast:[NSString stringWithFormat:
        @"Copied %lu account(s) to clipboard.\nList cleared.",
        (unsigned long)exports.count] success:YES];
}

#pragma mark - Confirm card

- (void)showConfirmCard:(NSDictionary *)acc {
    UIView *parent = self.superview ?: [self topVC].view;
    if (!parent) return;

    UIView *backdrop = [[UIView alloc] initWithFrame:parent.bounds];
    backdrop.backgroundColor  = [UIColor colorWithWhite:0 alpha:0.50];
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [parent addSubview:backdrop];

    UIView *card = [UIView new];
    card.backgroundColor     = [UIColor colorWithRed:0.10 green:0.10 blue:0.14 alpha:1];
    card.layer.cornerRadius  = 13;
    card.layer.shadowColor   = UIColor.blackColor.CGColor;
    card.layer.shadowOpacity = 0.70;
    card.layer.shadowRadius  = 10;
    card.layer.shadowOffset  = CGSizeMake(0, 4);
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview:card];

    UILabel *emailLbl = [UILabel new];
    emailLbl.text = acc[@"email"];
    emailLbl.textColor = UIColor.whiteColor;
    emailLbl.font = [UIFont boldSystemFontOfSize:12];
    emailLbl.textAlignment = NSTextAlignmentCenter;
    emailLbl.numberOfLines = 1;
    emailLbl.adjustsFontSizeToFitWidth = YES;
    emailLbl.minimumScaleFactor = 0.7;
    emailLbl.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:emailLbl];

    UILabel *uidLbl = [UILabel new];
    uidLbl.text = [NSString stringWithFormat:@"UID: %@", acc[@"uid"]];
    uidLbl.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    uidLbl.font = [UIFont systemFontOfSize:10];
    uidLbl.textAlignment = NSTextAlignmentCenter;
    uidLbl.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:uidLbl];

    NSString *tok = acc[@"token"];
    UILabel *tokLbl = [UILabel new];
    tokLbl.text = [NSString stringWithFormat:@"Token: %@…",
        [tok substringToIndex:MIN((NSUInteger)12, tok.length)]];
    tokLbl.textColor = [UIColor colorWithWhite:0.48 alpha:1];
    tokLbl.font = [UIFont fontWithName:@"Courier" size:9] ?: [UIFont systemFontOfSize:9];
    tokLbl.textAlignment = NSTextAlignmentCenter;
    tokLbl.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:tokLbl];

    NSString *remStr = acc[@"remaining"];
    UILabel *remLbl = [UILabel new];
    remLbl.text = remStr
        ? [NSString stringWithFormat:@"Remaining on server: %@", remStr] : @"";
    remLbl.textColor = [UIColor colorWithRed:0.40 green:0.78 blue:1.00 alpha:1];
    remLbl.font = [UIFont systemFontOfSize:9];
    remLbl.textAlignment = NSTextAlignmentCenter;
    remLbl.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:remLbl];

    UIView *sep = [UIView new];
    sep.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:sep];

    UIButton *applyBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [applyBtn setTitle:@"Apply this account" forState:UIControlStateNormal];
    [applyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    applyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    applyBtn.backgroundColor = [UIColor colorWithRed:0.18 green:0.62 blue:0.38 alpha:1];
    applyBtn.layer.cornerRadius = 8;
    applyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:applyBtn];

    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [cancelBtn setTitle:@"Cancel" forState:UIControlStateNormal];
    [cancelBtn setTitleColor:[UIColor colorWithWhite:0.60 alpha:1] forState:UIControlStateNormal];
    cancelBtn.titleLabel.font = [UIFont systemFontOfSize:11];
    cancelBtn.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1];
    cancelBtn.layer.cornerRadius = 8;
    cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:cancelBtn];

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:parent.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:parent.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:248],

        [emailLbl.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [emailLbl.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [emailLbl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],

        [uidLbl.topAnchor constraintEqualToAnchor:emailLbl.bottomAnchor constant:4],
        [uidLbl.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [uidLbl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],

        [tokLbl.topAnchor constraintEqualToAnchor:uidLbl.bottomAnchor constant:3],
        [tokLbl.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [tokLbl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],

        [remLbl.topAnchor constraintEqualToAnchor:tokLbl.bottomAnchor constant:3],
        [remLbl.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [remLbl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],

        [sep.topAnchor constraintEqualToAnchor:remLbl.bottomAnchor constant:10],
        [sep.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [sep.heightAnchor constraintEqualToConstant:1],

        [applyBtn.topAnchor constraintEqualToAnchor:sep.bottomAnchor constant:10],
        [applyBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:10],
        [applyBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10],
        [applyBtn.heightAnchor constraintEqualToConstant:40],

        [cancelBtn.topAnchor constraintEqualToAnchor:applyBtn.bottomAnchor constant:6],
        [cancelBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:10],
        [cancelBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10],
        [cancelBtn.heightAnchor constraintEqualToConstant:32],

        [card.bottomAnchor constraintEqualToAnchor:cancelBtn.bottomAnchor constant:12],
    ]];

    void (^dismiss)(void) = ^{
        [UIView animateWithDuration:0.15 animations:^{
            backdrop.alpha = 0; card.alpha = 0;
        } completion:^(BOOL _) {
            [backdrop removeFromSuperview]; [card removeFromSuperview];
        }];
    };

    objc_setAssociatedObject(backdrop, "dismissBlock",
        [dismiss copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
    UITapGestureRecognizer *bgTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(backdropTapped:)];
    bgTap.cancelsTouchesInView = NO;
    [backdrop addGestureRecognizer:bgTap];

    [applyBtn sk_setActionBlock:^{
        dismiss();

        applyAccount(acc);

        NSMutableArray *exports = getExports();
        [exports addObject:acc];
        writeExports(exports);
        [self refreshInfo];

        NSString *shortTok = [tok substringToIndex:MIN((NSUInteger)10, tok.length)];
        NSString *msg = [NSString stringWithFormat:
            @"Applied ✓\n\nEmail : %@\nUID   : %@\nToken : %@…\n\nPrefs patched & reloaded.",
            acc[@"email"], acc[@"uid"], shortTok];
        [self setStatus:@"Account applied ✓"
                  color:[UIColor colorWithRed:0.28 green:0.82 blue:0.42 alpha:1]];
        [self showToast:msg success:YES];
    }];

    [cancelBtn sk_setActionBlock:^{ dismiss(); }];

    card.alpha = 0; backdrop.alpha = 0;
    [UIView animateWithDuration:0.18 animations:^{ backdrop.alpha = 1; card.alpha = 1; }];
}

- (void)backdropTapped:(UITapGestureRecognizer *)g {
    void (^d)(void) = objc_getAssociatedObject(g.view, "dismissBlock");
    if (d) d();
}

// No exit parameter — toast just fades and stays gone, app keeps running
- (void)showToast:(NSString *)msg success:(BOOL)ok {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *parent = self.superview ?: [self topVC].view;
        UILabel *t = [UILabel new];
        t.text            = msg;
        t.textColor       = UIColor.whiteColor;
        t.font            = [UIFont systemFontOfSize:11];
        t.backgroundColor = ok
            ? [UIColor colorWithRed:0.08 green:0.20 blue:0.10 alpha:0.97]
            : [UIColor colorWithRed:0.20 green:0.08 blue:0.08 alpha:0.97];
        t.layer.cornerRadius = 9;
        t.layer.borderColor  = ok
            ? [UIColor colorWithRed:0.28 green:0.78 blue:0.38 alpha:0.5].CGColor
            : [UIColor colorWithRed:0.78 green:0.28 blue:0.28 alpha:0.5].CGColor;
        t.layer.borderWidth  = 1;
        t.clipsToBounds  = YES;
        t.numberOfLines  = 0;
        t.textAlignment  = NSTextAlignmentCenter;
        t.translatesAutoresizingMaskIntoConstraints = NO;
        [parent addSubview:t];
        [NSLayoutConstraint activateConstraints:@[
            [t.centerXAnchor constraintEqualToAnchor:parent.centerXAnchor],
            [t.centerYAnchor constraintEqualToAnchor:parent.centerYAnchor],
            [t.widthAnchor constraintLessThanOrEqualToAnchor:parent.widthAnchor constant:-40],
        ]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{ t.alpha = 0; }
                             completion:^(BOOL _) { [t removeFromSuperview]; }];
        });
    });
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint d  = [g translationInView:self.superview];
    CGRect  sb = self.superview.bounds;
    CGFloat nx = MAX(self.bounds.size.width/2,
        MIN(sb.size.width  - self.bounds.size.width/2,  self.center.x + d.x));
    CGFloat ny = MAX(self.bounds.size.height/2,
        MIN(sb.size.height - self.bounds.size.height/2, self.center.y + d.y));
    self.center = CGPointMake(nx, ny);
    [g setTranslation:CGPointZero inView:self.superview];
}

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
    gPanel.center = CGPointMake(gPanel.bounds.size.width / 2 + 8, 80);
    [root addSubview:gPanel];
    [root bringSubviewToFront:gPanel];
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ injectPanel(); });
    });
}
%end
