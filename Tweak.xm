#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - Top ViewController Helpers

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
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:dict
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0 error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

static NSDictionary* plistToDict(NSString *plist) {
    NSData *data = [plist dataUsingEncoding:NSUTF8StringEncoding];
    id obj = [NSPropertyListSerialization propertyListWithData:data
                                                       options:NSPropertyListMutableContainersAndLeaves
                                                        format:nil error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

#pragma mark - Apply Regex Patch

static void applyPatch(NSString *title, NSString *pattern, NSString *replace) {
    NSString *bid = NSBundle.mainBundle.bundleIdentifier;
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];

    NSMutableDictionary *domain = [[defs persistentDomainForName:bid] mutableCopy];
    if (!domain) domain = [NSMutableDictionary new];

    NSString *plist = dictToPlist(domain);
    if (!plist) return;

    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                        options:NSRegularExpressionCaseInsensitive
                                                                          error:nil];
    NSString *modified = [re stringByReplacingMatchesInString:plist
                                                     options:0
                                                       range:NSMakeRange(0, plist.length)
                                                withTemplate:replace];

    NSDictionary *newDomain = plistToDict(modified);
    if (!newDomain) return;

    [defs setPersistentDomain:newDomain forName:bid];
    [defs synchronize];

    UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Success"
                                                                 message:[NSString stringWithFormat:@"%@ patched.", title]
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [topVC() presentViewController:done animated:YES completion:nil];
}

#pragma mark - Gems Handler

static void handleGems() {
    UIAlertController *inputAlert = [UIAlertController alertControllerWithTitle:@"Set Gems"
                                                                        message:@"Enter gem value:"
                                                                 preferredStyle:UIAlertControllerStyleAlert];
    [inputAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.placeholder = @"Gem number";
    }];

    [inputAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [inputAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *value = inputAlert.textFields.firstObject.text;
        if (!value.length) return;

        NSString *bid = NSBundle.mainBundle.bundleIdentifier;
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        NSMutableDictionary *domain = [[defs persistentDomainForName:bid] mutableCopy];
        if (!domain) domain = [NSMutableDictionary new];

        NSString *plist = dictToPlist(domain);
        if (!plist) return;

        NSRegularExpression *reGems = [NSRegularExpression regularExpressionWithPattern:@"(<key>\\d+_gems</key>\\s*<integer>)\\d+" options:0 error:nil];
        plist = [reGems stringByReplacingMatchesInString:plist options:0 range:NSMakeRange(0, plist.length) withTemplate:[NSString stringWithFormat:@"$1%@", value]];

        NSRegularExpression *reLastGems = [NSRegularExpression regularExpressionWithPattern:@"(<key>\\d+_last_gems</key>\\s*<integer>)\\d+" options:0 error:nil];
        plist = [reLastGems stringByReplacingMatchesInString:plist options:0 range:NSMakeRange(0, plist.length) withTemplate:[NSString stringWithFormat:@"$1%@", value]];

        NSDictionary *newDomain = plistToDict(plist);
        [defs setPersistentDomain:newDomain forName:bid];
        [defs synchronize];

        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Success" message:@"Gems updated." preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC() presentViewController:done animated:YES completion:nil];
    }]];

    [topVC() presentViewController:inputAlert animated:YES completion:nil];
}

#pragma mark - Reborn Handler

static void handleReborn() {
    NSString *bid = NSBundle.mainBundle.bundleIdentifier;
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *domain = [[defs persistentDomainForName:bid] mutableCopy];
    if (!domain) domain = [NSMutableDictionary new];

    NSString *plist = dictToPlist(domain);
    if (!plist) return;

    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(<key>\\d+_reborn_card</key>\\s*<integer>)\\d+" options:0 error:nil];
    plist = [re stringByReplacingMatchesInString:plist options:0 range:NSMakeRange(0, plist.length) withTemplate:@"$11"];

    NSDictionary *newDomain = plistToDict(plist);
    [defs setPersistentDomain:newDomain forName:bid];
    [defs synchronize];

    UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Success" message:@"Reborn updated." preferredStyle:UIAlertControllerStyleAlert];
    [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [topVC() presentViewController:done animated:YES completion:nil];
}

#pragma mark - Patch All Handler

static void handlePatchAll() {
    NSDictionary *patches = @{
        @"Characters": @"(<key>\\d+_c\\d+_unlock.*\\n.*)false",
        @"Skins": @"(<key>\\d+_c\\d+_skin\\d+.*\\n.*>)[+-]?\\d+",
        @"Skills": @"(<key>\\d+_c_.*_skill_\\d_unlock.*\\n.*<integer>)\\d",
        @"Pets": @"(<key>\\d+_p\\d+_unlock.*\\n.*)false",
        @"Level": @"(<key>\\d+_c\\d+_level+.*\\n.*>)[+-]?\\d+",
        @"Furniture": @"(<key>\\d+_furniture+_+.*\\n.*>)[+-]?\\d+"
    };
    for (NSString *key in patches) {
        applyPatch(key, patches[key], key.equals(@"Level") ? @"8" : @"1");
    }
}

#pragma mark - Show Menu

static void showMenu() {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Menu"
                                                                   message:@"Choose patch"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    NSArray *options = @[@"Characters",@"Skins",@"Skills",@"Pets",@"Level",@"Furniture",@"Gems",@"Reborn",@"Patch All"];
    for (NSString *opt in options) {
        [menu addAction:[UIAlertAction actionWithTitle:opt style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            if ([opt isEqualToString:@"Gems"]) handleGems();
            else if ([opt isEqualToString:@"Reborn"]) handleReborn();
            else if ([opt isEqualToString:@"Patch All"]) handlePatchAll();
            else {
                NSString *replace = ([opt isEqualToString:@"Level"] ? @"8" : @"1");
                NSDictionary *dict = @{
                    @"Characters": @"(<key>\\d+_c\\d+_unlock.*\\n.*)false",
                    @"Skins": @"(<key>\\d+_c\\d+_skin\\d+.*\\n.*>)[+-]?\\d+",
                    @"Skills": @"(<key>\\d+_c_.*_skill_\\d_unlock.*\\n.*<integer>)\\d",
                    @"Pets": @"(<key>\\d+_p\\d+_unlock.*\\n.*)false",
                    @"Furniture": @"(<key>\\d+_furniture+_+.*\\n.*>)[+-]?\\d+"
                };
                applyPatch(opt, dict[opt], replace);
            }
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [topVC() presentViewController:menu animated:YES completion:nil];
}

#pragma mark - Floating Draggable Button

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *win = firstWindow();
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, 200, 70, 70);
        btn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        btn.layer.cornerRadius = 35;
        btn.tintColor = UIColor.whiteColor;
        [btn setTitle:@"Menu" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];

        // Add drag gesture
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(handlePan:)];
        [btn addGestureRecognizer:pan];

        [btn addTarget:nil action:@selector(showMenuPressed) forControlEvents:UIControlEventTouchUpInside];
        [win addSubview:btn];
    });
}

%hook UIApplication
%new
- (void)showMenuPressed { showMenu(); }

%new
- (void)handlePan:(UIPanGestureRecognizer*)pan {
    UIView *v = pan.view;
    CGPoint translation = [pan translationInView:v.superview];
    v.center = CGPointMake(v.center.x + translation.x, v.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:v.superview];
}
%end
