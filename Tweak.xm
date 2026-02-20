// tweak.xm — Soul Knight Account Manager v4
// iOS 14+ | Theos/Logos | ARC

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

#pragma mark - Regex helper

// Apply regex find/replace on a file (XML plist), returns YES if file was modified
static BOOL regexReplaceInFile(NSString *path, NSString *pattern, NSString *tmpl) {
    NSError *err = nil;
    NSString *content = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:&err];
    if (err || !content) return NO;

    NSRegularExpression *rx = [NSRegularExpression
        regularExpressionWithPattern:pattern
        options:NSRegularExpressionDotMatchesLineSeparators
        error:&err];
    if (err || !rx) return NO;

    NSMutableString *ms = [content mutableCopy];
    // Replace in reverse order so ranges stay valid
    NSArray *matches = [rx matchesInString:content
                                   options:0
                                     range:NSMakeRange(0, content.length)];
    for (NSTextCheckingResult *m in matches.reverseObjectEnumerator) {
        NSString *replacement = [rx replacementStringForResult:m
                                                      inString:ms
                                                        offset:0
                                                      template:tmpl];
        [ms replaceCharactersInRange:m.range withString:replacement];
    }

    if ([ms isEqualToString:content]) return NO; // nothing changed

    NSError *we = nil;
    [ms writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&we];
    return (we == nil);
}

#pragma mark - Account Switch

static void applyAccount(NSDictionary *acc) {
    NSUserDefaults *ud  = [NSUserDefaults standardUserDefaults];
    NSString *newToken  = acc[@"token"];
    NSString *newUid    = acc[@"uid"];
    NSString *newEmail  = acc[@"email"];

    NSString *raw = [ud stringForKey:@"SdkStateCache#1"];
    if (raw) {
        // ── Step 1: extract the current PlayerId as a raw number string
        //    using regex on the raw JSON string (most reliable)
        NSString *oldPlayerId = @"";
        NSError *rxErr = nil;
        NSRegularExpression *idRx = [NSRegularExpression
            regularExpressionWithPattern:@"\"PlayerId\"\\s*:\\s*(\\d+)"
            options:0 error:&rxErr];
        if (!rxErr) {
            NSTextCheckingResult *m = [idRx firstMatchInString:raw
                                                       options:0
                                                         range:NSMakeRange(0, raw.length)];
            if (m && m.numberOfRanges > 1)
                oldPlayerId = [raw substringWithRange:[m rangeAtIndex:1]];
        }

        // ── Step 2: parse JSON, patch every relevant field
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
            if (!err && out) {
                NSString *patched = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];

                // ── Step 3: replace ALL occurrences of old PlayerId number
                //    (covers Id, PlayerId, any field sharing same number)
                if (oldPlayerId.length > 0 && ![oldPlayerId isEqualToString:@"0"]) {
                    patched = [patched stringByReplacingOccurrencesOfString:oldPlayerId
                                                                 withString:newUid];
                }
                [ud setObject:patched forKey:@"SdkStateCache#1"];
            }
        }

        // ── Step 4: replace in ALL other string-type NSUserDefaults keys
        if (oldPlayerId.length > 0 && ![oldPlayerId isEqualToString:@"0"]) {
            NSDictionary *all = ud.dictionaryRepresentation;
            for (NSString *key in all) {
                if ([key isEqualToString:@"SdkStateCache#1"]) continue;
                id val = all[key];
                if ([val isKindOfClass:[NSString class]] && [val containsString:oldPlayerId]) {
                    [ud setObject:[val stringByReplacingOccurrencesOfString:oldPlayerId
                                                                 withString:newUid]
                           forKey:key];
                }
            }
        }
        [ud synchronize];
    }

    // ── Step 5: copy save files *_1_.data → *_{newUid}_.data
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *t in @[@"bp_data",@"item_data",@"misc_data",
                          @"season_data",@"statistic_data",@"weapon_evolution_data"]) {
        NSString *src = [docs stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_1_.data",t]];
        NSString *dst = [docs stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%@_.data",t,newUid]];
        if ([fm fileExistsAtPath:src]) {
            [fm removeItemAtPath:dst error:nil];
            [fm copyItemAtPath:src toPath:dst error:nil];
        }
    }
}

#pragma mark - Unlock helpers

static int runUnlockRegex(NSString *type) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSArray *files = @[@"bp_data_1_.data",@"item_data_1_.data",@"misc_data_1_.data",
                       @"season_data_1_.data",@"statistic_data_1_.data",@"weapon_evolution_data_1_.data"];

    NSString *pattern, *tmpl;
    if ([type isEqualToString:@"Characters"]) {
        pattern = @"(<key>\\d+_c\\d+_unlock[^\\n]*\\n[^>]*>)false";
        tmpl    = @"${1}True";
    } else if ([type isEqualToString:@"Skins"]) {
        pattern = @"(<key>\\d+_c\\d+_skin\\d+[^\\n]*\\n[^>]*>)[+-]?\\d+";
        tmpl    = @"${1}1";
    } else if ([type isEqualToString:@"Skills"]) {
        pattern = @"(<key>\\d+_c_[^\\n]*_skill_\\d_unlock[^\\n]*\\n[^<]*<integer>)\\d";
        tmpl    = @"${1}1";
    } else if ([type isEqualToString:@"Pets"]) {
        pattern = @"(<key>\\d+_p\\d+_unlock[^\\n]*\\n[^>]*>)false";
        tmpl    = @"${1}True";
    } else {
        return 0;
    }

    int changed = 0;
    for (NSString *f in files) {
        NSString *path = [docs stringByAppendingPathComponent:f];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path])
            if (regexReplaceInFile(path, pattern, tmpl)) changed++;
    }
    return changed;
}

#pragma mark - Input VC (shows existing accounts + add new)

@interface SKInputVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextView  *tv;
@property (nonatomic, strong) NSMutableArray *accounts; // live copy
@property (nonatomic, copy)   void (^onDone)(void);     // called when VC dismissed
@end

@implementation SKInputVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    self.accounts = getSaved();

    // ── Title ────────────────────────────────────────────────────────
    UILabel *ttl = [UILabel new];
    ttl.text = @"Accounts";
    ttl.textColor = UIColor.whiteColor;
    ttl.font = [UIFont boldSystemFontOfSize:17];
    ttl.textAlignment = NSTextAlignmentCenter;
    ttl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:ttl];

    // ── Saved accounts table ─────────────────────────────────────────
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate   = self;
    self.table.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1];
    self.table.separatorColor  = [UIColor colorWithWhite:0.25 alpha:1];
    self.table.layer.cornerRadius = 8;
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];

    // ── Hint ─────────────────────────────────────────────────────────
    UILabel *hint = [UILabel new];
    hint.text = @"Add new  ▸  email|pass|uid|token  (one per line)";
    hint.textColor = [UIColor colorWithWhite:0.5 alpha:1];
    hint.font = [UIFont systemFontOfSize:11];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:hint];

    // ── Text view for adding new accounts ────────────────────────────
    self.tv = [UITextView new];
    self.tv.backgroundColor = [UIColor colorWithWhite:0.17 alpha:1];
    self.tv.textColor = [UIColor colorWithRed:0.4 green:1 blue:0.55 alpha:1];
    self.tv.font = [UIFont fontWithName:@"Courier" size:12] ?: [UIFont systemFontOfSize:12];
    self.tv.layer.cornerRadius = 8;
    self.tv.autocorrectionType = UITextAutocorrectionTypeNo;
    self.tv.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.tv.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tv];

    // ── Keyboard toolbar: Done (dismiss keyboard only) ───────────────
    UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0,0,UIScreen.mainScreen.bounds.size.width,44)];
    bar.barStyle = UIBarStyleBlack;
    bar.translucent = YES;
    UIBarButtonItem *flex = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *doneKb = [[UIBarButtonItem alloc]
        initWithTitle:@"Done"
        style:UIBarButtonItemStyleDone
        target:self
        action:@selector(dismissKeyboard)];
    doneKb.tintColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1];
    bar.items = @[flex, doneKb];
    self.tv.inputAccessoryView = bar;

    // ── Bottom buttons: Cancel | Save ────────────────────────────────
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
        // Title
        [ttl.topAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.topAnchor constant:12],
        [ttl.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:16],
        [ttl.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-16],
        // Table (top half)
        [self.table.topAnchor constraintEqualToAnchor:ttl.bottomAnchor constant:10],
        [self.table.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:12],
        [self.table.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-12],
        [self.table.heightAnchor constraintEqualToAnchor:v.heightAnchor multiplier:0.38],
        // Hint
        [hint.topAnchor constraintEqualToAnchor:self.table.bottomAnchor constant:8],
        [hint.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:12],
        [hint.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-12],
        // Text view (bottom half input)
        [self.tv.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:4],
        [self.tv.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:12],
        [self.tv.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-12],
        [self.tv.bottomAnchor constraintEqualToAnchor:saveBtn.topAnchor constant:-10],
        // Buttons
        [cancelBtn.bottomAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.bottomAnchor constant:-14],
        [cancelBtn.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:12],
        [cancelBtn.heightAnchor constraintEqualToConstant:44],
        [saveBtn.bottomAnchor constraintEqualToAnchor:cancelBtn.bottomAnchor],
        [saveBtn.leadingAnchor constraintEqualToAnchor:cancelBtn.trailingAnchor constant:8],
        [saveBtn.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-12],
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

// UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.accounts.count == 0 ? 1 : (NSInteger)self.accounts.count;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    }
    cell.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1];
    cell.textLabel.textColor    = UIColor.whiteColor;
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    cell.textLabel.font = [UIFont systemFontOfSize:13];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11];

    if (self.accounts.count == 0) {
        cell.textLabel.text = @"No saved accounts";
        cell.detailTextLabel.text = @"";
        cell.userInteractionEnabled = NO;
    } else {
        NSDictionary *a = self.accounts[ip.row];
        cell.textLabel.text = a[@"email"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"uid: %@   token: %@…",
            a[@"uid"], [a[@"token"] substringToIndex:MIN(10u, ((NSString *)a[@"token"]).length)]];
        cell.userInteractionEnabled = YES;
    }
    return cell;
}
// Swipe to delete
- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    return self.accounts.count > 0;
}
- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)es
forRowAtIndexPath:(NSIndexPath *)ip {
    if (es == UITableViewCellEditingStyleDelete) {
        [self.accounts removeObjectAtIndex:ip.row];
        writeSaved(self.accounts);
        if (self.accounts.count == 0)
            [tv reloadData];
        else
            [tv deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)dismissKeyboard { [self.tv resignFirstResponder]; }

- (void)doSave {
    NSString *text = self.tv.text;
    NSUInteger before = self.accounts.count;
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *t = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!t.length) continue;
        NSDictionary *a = parseLine(t);
        if (!a) continue;
        BOOL dup = NO;
        for (NSDictionary *e in self.accounts) if ([e[@"uid"] isEqualToString:a[@"uid"]]) { dup=YES; break; }
        if (!dup) [self.accounts addObject:a];
    }
    writeSaved(self.accounts);
    NSUInteger added = self.accounts.count - before;

    UIAlertController *ok = [UIAlertController
        alertControllerWithTitle:@"Saved"
        message:[NSString stringWithFormat:@"Added %lu new. Total: %lu", (unsigned long)added, (unsigned long)self.accounts.count]
        preferredStyle:UIAlertControllerStyleAlert];
    [ok addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        if (self.onDone) self.onDone();
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:ok animated:YES completion:nil];
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
    self = [super initWithFrame:CGRectMake(0,0,248,62)];
    if (!self) return nil;

    self.backgroundColor     = [UIColor colorWithWhite:0.05 alpha:0.88];
    self.layer.cornerRadius  = 12;
    self.layer.shadowColor   = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.8;
    self.layer.shadowRadius  = 7;
    self.layer.shadowOffset  = CGSizeMake(0, 3);
    self.layer.zPosition     = 9999;

    // ── Info bar ─────────────────────────────────────────────────────
    self.infoLabel = [UILabel new];
    self.infoLabel.frame = CGRectMake(6, 4, 236, 16);
    self.infoLabel.font = [UIFont systemFontOfSize:10];
    self.infoLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1];
    self.infoLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.infoLabel];
    [self refreshInfo];

    // ── 4 Buttons ────────────────────────────────────────────────────
    NSArray *titles = @[@"Input", @"Edit", @"Export", @"Unlock"];
    NSArray *colors = @[
        [UIColor colorWithRed:0.18 green:0.55 blue:1.00 alpha:1],
        [UIColor colorWithRed:0.18 green:0.78 blue:0.38 alpha:1],
        [UIColor colorWithRed:1.00 green:0.48 blue:0.16 alpha:1],
        [UIColor colorWithRed:0.75 green:0.22 blue:0.90 alpha:1]
    ];
    SEL sels[4] = { @selector(tapInput), @selector(tapEdit), @selector(tapExport), @selector(tapUnlock) };

    CGFloat bw = 57, bh = 34, gap = 2, startX = 5, y = 22;
    for (int i = 0; i < 4; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(startX + i*(bw+gap), y, bw, bh);
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

- (void)refreshInfo {
    NSUInteger saved   = getSaved().count;
    NSUInteger exports = getRemoved().count;
    self.infoLabel.text = [NSString stringWithFormat:@" Saved: %lu      Export ready: %lu",
                           (unsigned long)saved, (unsigned long)exports];
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint d = [g translationInView:self.superview];
    CGRect sb = self.superview.bounds;
    CGFloat nx = MAX(self.bounds.size.width/2,  MIN(sb.size.width  - self.bounds.size.width/2,  self.center.x + d.x));
    CGFloat ny = MAX(self.bounds.size.height/2, MIN(sb.size.height - self.bounds.size.height/2, self.center.y + d.y));
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

- (void)alert:(NSString *)title msg:(NSString *)msg exitAfter:(BOOL)ex {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title
            message:msg preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *_) {
                [self refreshInfo];
                if (ex) exit(0);
            }]];
        [[self topVC] presentViewController:a animated:YES completion:nil];
    });
}

// ── Input ─────────────────────────────────────────────────────────────────
- (void)tapInput {
    SKInputVC *ivc = [SKInputVC new];
    ivc.modalPresentationStyle = UIModalPresentationFormSheet;
    ivc.onDone = ^{ [self refreshInfo]; };
    [[self topVC] presentViewController:ivc animated:YES completion:nil];
}

// ── Edit: pick random, apply, exit on OK ─────────────────────────────────
- (void)tapEdit {
    NSMutableArray *list = getSaved();
    if (!list.count) {
        [self alert:@"No Accounts" msg:@"Use [Input] to add accounts first." exitAfter:NO];
        return;
    }
    NSUInteger idx = arc4random_uniform((uint32_t)list.count);
    NSDictionary *acc = list[idx];

    NSMutableArray *rem = getRemoved();
    [list removeObjectAtIndex:idx];
    [rem addObject:acc];
    writeSaved(list);
    writeRemoved(rem);

    applyAccount(acc);

    NSString *msg = [NSString stringWithFormat:
        @"Email : %@\nUID   : %@\nToken : %@\n\n✓ All IDs replaced globally\n✓ NSUserDefaults patched\n✓ Save files backed up\n\nRemaining saved: %lu\n\nPress OK to close the app.",
        acc[@"email"], acc[@"uid"], acc[@"token"], (unsigned long)list.count];
    [self alert:@"Account Applied" msg:msg exitAfter:YES];
}

// ── Export ────────────────────────────────────────────────────────────────
- (void)tapExport {
    NSMutableArray *rem = getRemoved();
    if (!rem.count) {
        [self alert:@"Nothing to Export" msg:@"No removed accounts yet. Use [Edit] first." exitAfter:NO];
        return;
    }
    NSMutableString *out = [NSMutableString new];
    for (NSDictionary *a in rem) [out appendFormat:@"%@|%@\n", a[@"email"], a[@"pass"]];
    [UIPasteboard generalPasteboard].string = out;
    writeRemoved(@[]);
    [self refreshInfo];
    [self alert:@"Exported"
            msg:[NSString stringWithFormat:@"Copied %lu account(s) to clipboard:\n\n%@",
                 (unsigned long)rem.count, out]
      exitAfter:NO];
}

// ── Unlock ────────────────────────────────────────────────────────────────
- (void)tapUnlock {
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Unlock"
        message:@"Choose what to unlock in save files"
        preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSString *type in @[@"Characters", @"Skins", @"Skills", @"Pets"]) {
        [ac addAction:[UIAlertAction actionWithTitle:type
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *_) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
                    int n = runUnlockRegex(type);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSString *msg = n > 0
                            ? [NSString stringWithFormat:@"Modified %d save file(s).\nRestart the app to see changes.", n]
                            : @"No matching entries found.\nMake sure save files exist in Documents.";
                        [self alert:[NSString stringWithFormat:@"Unlock %@", type]
                                msg:msg
                          exitAfter:(n > 0)];
                    });
                });
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

@end

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
    gPanel.center = CGPointMake(sw - gPanel.bounds.size.width/2 - 8, 110);
    [root addSubview:gPanel];
    [root bringSubviewToFront:gPanel];
}

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
