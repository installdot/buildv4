#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - Safe topVC finder (Works iOS 13+)

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

#pragma mark - Regex Patch Logic

static void applyPatch(NSString *title, NSString *pattern, NSString *replace) {

    NSString *bid = NSBundle.mainBundle.bundleIdentifier;
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];

    NSDictionary *domain = [defs persistentDomainForName:bid];
    if (!domain) domain = @{};

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
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [topVC() presentViewController:alert animated:YES completion:nil];
        return;
    }

    [defs setPersistentDomain:newDomain forName:bid];
    [defs synchronize];

    UIAlertController *done =
        [UIAlertController alertControllerWithTitle:@"Success"
                                            message:[NSString stringWithFormat:@"%@ patched.", title]
                                     preferredStyle:UIAlertControllerStyleAlert];
    [done addAction:[UIAlertAction actionWithTitle:@"OK"
                                            style:UIAlertActionStyleDefault
                                          handler:nil]];
    [topVC() presentViewController:done animated:YES completion:nil];
}

#pragma mark - Menu

static void showMenu() {

    UIAlertController *menu =
        [UIAlertController alertControllerWithTitle:@"Menu"
                                            message:@"Choose a patch to apply"
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
        NSDictionary *p = patches[name];
        [menu addAction:[UIAlertAction actionWithTitle:name
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *a){
            applyPatch(name, p[@"re"], p[@"rep"]);
        }]];
    }

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];

    [topVC() presentViewController:menu animated:YES completion:nil];
}

#pragma mark - Floating Button

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

        [btn addTarget:nil action:@selector(showMenuPressed)
              forControlEvents:UIControlEventTouchUpInside];

        [win addSubview:btn];
    });
}

%hook UIApplication
%new
- (void)showMenuPressed {
    showMenu();
}
%end
