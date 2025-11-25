#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - Top VC helper

static UIWindow* firstWindow() {
    for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) return w;
            }
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static UIViewController* topVC() {
    UIWindow *win = firstWindow();
    UIViewController *root = win.rootViewController;
    while (root.presentedViewController)
        root = root.presentedViewController;
    return root;
}

#pragma mark - Plist Helpers

static NSString* dictToPlist(NSDictionary *dict) {
    NSError *err = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:dict
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:&err];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

static NSDictionary* plistToDict(NSString *plist) {
    NSData *data = [plist dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err = nil;
    id obj = [NSPropertyListSerialization propertyListWithData:data
                                                       options:NSPropertyListMutableContainersAndLeaves
                                                        format:nil
                                                         error:&err];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

#pragma mark - Apply Patch

static void applyPatch(NSString *title, NSString *pattern, NSString *replace) {
    NSString *bid = NSBundle.mainBundle.bundleIdentifier;
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSDictionary *domain = [defs persistentDomainForName:bid] ?: @{};

    NSString *plist = dictToPlist(domain);
    if (!plist) return;

    NSError *err = nil;
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:pattern
                                                  options:NSRegularExpressionCaseInsensitive
                                                    error:&err];

    NSString *modified =
        [re stringByReplacingMatchesInString:plist
                                     options:0
                                       range:NSMakeRange(0, plist.length)
                                withTemplate:replace];

    NSDictionary *newDomain = plistToDict(modified);
    if (!newDomain) {
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Patch Failed"
                                                message:@"Broken plist output."
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:alert animated:YES completion:nil];
        return;
    }

    [defs setPersistentDomain:newDomain forName:bid];
    [defs synchronize];

    UIAlertController *done =
        [UIAlertController alertControllerWithTitle:@"Success"
                                            message:[NSString stringWithFormat:@"%@ patched.", title]
                                     preferredStyle:UIAlertControllerStyleAlert];
    [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [topVC() presentViewController:done animated:YES completion:nil];
}

#pragma mark - Gems & Reborn patches

static void patchGems() {
    NSString *bid = NSBundle.mainBundle.bundleIdentifier;
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *domain = [[defs persistentDomainForName:bid] mutableCopy] ?: [NSMutableDictionary dictionary];

    UIAlertController *input =
        [UIAlertController alertControllerWithTitle:@"Set Gems"
                                            message:@"Input new gem value:"
                                     preferredStyle:UIAlertControllerStyleAlert];

    [input addTextFieldWithConfigurationHandler:^(UITextField *textField){
        textField.placeholder = @"Number";
        textField.keyboardType = UIKeyboardTypeNumberPad;
    }];

    [input addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSInteger value = [input.textFields.firstObject.text integerValue];
        NSString *plist = dictToPlist(domain);
        NSError *err = nil;

        NSRegularExpression *reGems = [NSRegularExpression regularExpressionWithPattern:
            @"(<key>\\d+_gems</key>\\s*<integer>)\\d+"
                                                              options:NSRegularExpressionCaseInsensitive error:&err];

        NSString *modified = [reGems stringByReplacingMatchesInString:plist
                                                              options:0
                                                                range:NSMakeRange(0, plist.length)
                                                         withTemplate:[NSString stringWithFormat:@"$1%ld", (long)value]];

        NSRegularExpression *reLastGems = [NSRegularExpression regularExpressionWithPattern:
            @"(<key>\\d+_last_gems</key>\\s*<integer>)\\d+"
                                                              options:NSRegularExpressionCaseInsensitive error:&err];

        modified = [reLastGems stringByReplacingMatchesInString:modified
                                                        options:0
                                                          range:NSMakeRange(0, modified.length)
                                                   withTemplate:[NSString stringWithFormat:@"$1%ld", (long)value]];

        NSDictionary *newDomain = plistToDict(modified);
        [defs setPersistentDomain:newDomain forName:bid];
        [defs synchronize];

        UIAlertController *done =
            [UIAlertController alertControllerWithTitle:@"Gems Updated"
                                                message:[NSString stringWithFormat:@"Set gems to %ld", (long)value]
                                         preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:done animated:YES completion:nil];
    }]];

    [input addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:input animated:YES completion:nil];
}

static void patchReborn() {
    NSString *pattern = @"(<key>\\d+_reborn_card</key>\\s*<integer>)\\d+";
    NSString *replace = @"$11";
    applyPatch(@"Reborn", pattern, replace);
}

#pragma mark - Bypass Patch

static void patchBypass() {
    NSString *pattern = @"(<key>OpenRijTest_\\d+</key>\\s*<integer>)\\d+";
    NSString *replace = @"$10";
    applyPatch(@"Bypass", pattern, replace);
}

#pragma mark - Player Patch Menu

static void patchAll() {
    NSArray *patches = @[@"Characters", @"Skins", @"Skills", @"Pets", @"Level", @"Furniture", @"Reborn", @"Bypass"];
    for (NSString *p in patches) {
        if ([p isEqualToString:@"Reborn"]) patchReborn();
        else if ([p isEqualToString:@"Bypass"]) patchBypass();
        else {
            NSDictionary *dict = @{
                @"Characters": @{@"re": @"(<key>\\d+_c\\d+_unlock.*\n.*)false", @"rep": @"$1True"},
                @"Skins":      @{@"re": @"(<key>\\d+_c\\d+_skin\\d+.*\n.*>)[+-]?\\d+", @"rep": @"$11"},
                @"Skills":     @{@"re": @"(<key>\\d+_c_.*_skill_\\d_unlock.*\n.*<integer>)\\d", @"rep": @"$11"},
                @"Pets":       @{@"re": @"(<key>\\d+_p\\d+_unlock.*\n.*)false", @"rep": @"$1True"},
                @"Level":      @{@"re": @"(<key>\\d+_c\\d+_level+.*\n.*>)[+-]?\\d+", @"rep": @"$18"},
                @"Furniture":  @{@"re": @"(<key>\\d+_furniture+_+.*\n.*>)[+-]?\\d+", @"rep": @"$15"}
            };
            applyPatch(p, dict[p][@"re"], dict[p][@"rep"]);
        }
    }
}

static void showPlayerMenu() {
    UIAlertController *menu =
        [UIAlertController alertControllerWithTitle:@"Player Patches"
                                            message:@"Choose patch"
                                     preferredStyle:UIAlertControllerStyleAlert];

    NSDictionary *patches = @{
        @"Characters": @{@"re": @"(<key>\\d+_c\\d+_unlock.*\n.*)false", @"rep": @"$1True"},
        @"Skins":      @{@"re": @"(<key>\\d+_c\\d+_skin\\d+.*\n.*>)[+-]?\\d+", @"rep": @"$11"},
        @"Skills":     @{@"re": @"(<key>\\d+_c_.*_skill_\\d_unlock.*\n.*<integer>)\\d", @"rep": @"$11"},
        @"Pets":       @{@"re": @"(<key>\\d+_p\\d+_unlock.*\n.*)false", @"rep": @"$1True"},
        @"Level":      @{@"re": @"(<key>\\d+_c\\d+_level+.*\n.*>)[+-]?\\d+", @"rep": @"$18"},
        @"Furniture":  @{@"re": @"(<key>\\d+_furniture+_+.*\n.*>)[+-]?\\d+", @"rep": @"$15"}
    };

    for (NSString *name in patches) {
        [menu addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            applyPatch(name, patches[name][@"re"], patches[name][@"rep"]);
        }]];
    }

    [menu addAction:[UIAlertAction actionWithTitle:@"Gems" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ patchGems(); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Reborn" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ patchReborn(); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Bypass" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ patchBypass(); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Patch All" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ patchAll(); }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:menu animated:YES completion:nil];
}

#pragma mark - Document Folder Helpers

static NSArray* listDocumentsFiles() {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    NSArray *files = [fm contentsOfDirectoryAtPath:docs error:&err];
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSString *f in files) {
        if (![f hasSuffix:@".new"]) [filtered addObject:f];
    }
    return filtered;
}

static void showFileActionMenu(NSString *fileName) {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *filePath = [docs stringByAppendingPathComponent:fileName];

    UIAlertController *menu = [UIAlertController alertControllerWithTitle:fileName
                                                                   message:@"Choose Action"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [menu addAction:[UIAlertAction actionWithTitle:@"Export" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSString *content = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
        if (content) UIPasteboard.generalPasteboard.string = content;
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Exported"
                                                                      message:@"Copied contents to clipboard"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:done animated:YES completion:nil];
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Import" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        UIAlertController *input = [UIAlertController alertControllerWithTitle:@"Import"
                                                                       message:@"Paste text to import"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [input addTextFieldWithConfigurationHandler:^(UITextField *textField){
            textField.placeholder = @"Paste text here";
        }];
        [input addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            NSString *text = input.textFields.firstObject.text ?: @"";
            [text writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

            UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Imported"
                                                                          message:@"File overwritten"
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [topVC() presentViewController:done animated:YES completion:nil];
        }]];
        [input addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [topVC() presentViewController:input animated:YES completion:nil];
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        NSError *err = nil;
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:&err];
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Deleted"
                                                                      message:err ? err.localizedDescription : @"File removed"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:done animated:YES completion:nil];
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:menu animated:YES completion:nil];
}

static void showDataMenu() {
    NSArray *files = listDocumentsFiles();
    if (files.count == 0) {
        UIAlertController *empty = [UIAlertController alertControllerWithTitle:@"No Files"
                                                                       message:@"Documents folder is empty."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [empty addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:empty animated:YES completion:nil];
        return;
    }

    UIAlertController *menu =
        [UIAlertController alertControllerWithTitle:@"Documents Folder"
                                            message:@"Select a file"
                                     preferredStyle:UIAlertControllerStyleAlert];

    for (NSString *file in files) {
        [menu addAction:[UIAlertAction actionWithTitle:file style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            showFileActionMenu(file);
        }]];
    }

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:menu animated:YES completion:nil];
}

#pragma mark - Main Menu (Player / Data)

static void showMainMenu() {
    UIAlertController *menu =
        [UIAlertController alertControllerWithTitle:@"Menu"
                                            message:@"Select option"
                                     preferredStyle:UIAlertControllerStyleAlert];

    [menu addAction:[UIAlertAction actionWithTitle:@"Player" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        showPlayerMenu();
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Data" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        showDataMenu();
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:menu animated:YES completion:nil];
}

#pragma mark - Floating Button

static CGPoint startPoint;
static CGPoint btnStart;
static UIButton *floatingButton = nil;

static void toggleMenuVisibility() {
    floatingButton.hidden = !floatingButton.hidden;
}

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *win = firstWindow();

        floatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
        floatingButton.frame = CGRectMake(20, 200, 70, 70);
        floatingButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        floatingButton.layer.cornerRadius = 35;
        floatingButton.tintColor = UIColor.whiteColor;
        [floatingButton setTitle:@"Menu" forState:UIControlStateNormal];
        floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];

        [floatingButton addTarget:nil action:@selector(showMenuPressed) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(handlePan:)];
        [floatingButton addGestureRecognizer:pan];

        // 3-finger double tap gesture
        UITapGestureRecognizer *threeFingerDoubleTap = [[UITapGestureRecognizer alloc] initWithTarget:nil action:@selector(handleThreeFingerDoubleTap:)];
        threeFingerDoubleTap.numberOfTouchesRequired = 3;
        threeFingerDoubleTap.numberOfTapsRequired = 2;
        [win addGestureRecognizer:threeFingerDoubleTap];

        [win addSubview:floatingButton];
    });
}

%hook UIApplication
%new
- (void)showMenuPressed { showMainMenu(); }

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIButton *btn = (UIButton*)pan.view;
    if (pan.state == UIGestureRecognizerStateBegan) {
        startPoint = [pan locationInView:btn.superview];
        btnStart = btn.center;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint pt = [pan locationInView:btn.superview];
        CGFloat dx = pt.x - startPoint.x;
        CGFloat dy = pt.y - startPoint.y;
        btn.center = CGPointMake(btnStart.x + dx, btnStart.y + dy);
    }
}

- (void)handleThreeFingerDoubleTap:(UITapGestureRecognizer*)tap {
    toggleMenuVisibility();
}
%end
