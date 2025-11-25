// Tweak.xm
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - Helpers

static UIViewController *topVC() {
    UIViewController *root = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (root.presentedViewController)
        root = root.presentedViewController;
    return root;
}

// Convert NSDictionary → XML plist
static NSString *dictToPlist(NSDictionary *dict) {
    NSError *err = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:dict
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:&err];
    if (!data) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

// Parse XML plist → NSDictionary
static NSDictionary *plistToDict(NSString *plist) {
    if (!plist) return nil;
    NSData *data = [plist dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err = nil;
    id obj = [NSPropertyListSerialization propertyListWithData:data
                                                       options:NSPropertyListMutableContainersAndLeaves
                                                        format:nil
                                                         error:&err];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

#pragma mark - Apply Regex Patch

static void applyPatch(NSString *title, NSString *pattern, NSString *replace) {
    NSString *bid = NSBundle.mainBundle.bundleIdentifier;
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];

    // 1. Get persistent domain
    NSDictionary *domain = [defs persistentDomainForName:bid];
    if (!domain) domain = @{};

    // 2. Convert to plist text
    NSString *plist = dictToPlist(domain);
    if (!plist) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Error"
            message:@"Unable to convert preferences to plist."
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:0 handler:nil]];
        [topVC() presentViewController:a animated:YES completion:nil];
        return;
    }

    // 3. Regex replace
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

    // 4. Convert modified plist back to dictionary
    NSDictionary *newDomain = plistToDict(modified);
    if (!newDomain) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Patch Failed"
            message:@"Resulting plist invalid." preferredStyle:1];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:0 handler:nil]];
        [topVC() presentViewController:a animated:YES completion:nil];
        return;
    }

    // 5. Save domain
    [defs setPersistentDomain:newDomain forName:bid];
    [defs synchronize];

    // 6. Done alert
    UIAlertController *a =
        [UIAlertController alertControllerWithTitle:@"Done"
                                            message:[NSString stringWithFormat:@"%@ updated.", title]
                                     preferredStyle:1];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:0 handler:nil]];
    [topVC() presentViewController:a animated:YES completion:nil];
}

#pragma mark - Menu

static void showMenu() {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Menu"
                                            message:@"Choose a patch"
                                     preferredStyle:UIAlertControllerStyleAlert];

    NSDictionary *patches = @{
        @"Characters":
            @{@"re": @"(<key>\\d+_c\\d+_unlock.*\n.*)false", @"rep": @"$1True"},
        @"Skins":
            @{@"re": @"(<key>\\d+_c\\d+_skin\\d+.*\n.*>)[+-]?\\d+", @"rep": @"$11"},
        @"Skills":
            @{@"re": @"(<key>\\d+_c_.*_skill_\\d_unlock.*\n.*<integer>)\\d", @"rep": @"$11"},
        @"Pets":
            @{@"re": @"(<key>\\d+_p\\d+_unlock.*\n.*)false", @"rep": @"$1True"},
        @"Level":
            @{@"re": @"(<key>\\d+_c\\d+_level+.*\n.*>)[+-]?\\d+", @"rep": @"$18"},
        @"Furniture":
            @{@"re": @"(<key>\\d+_furniture+_+.*\n.*>)[+-]?\\d+", @"rep": @"$15"}
    };

    // Create button for each patch
    for (NSString *name in patches) {
        NSDictionary *p = patches[name];
        [alert addAction:[UIAlertAction actionWithTitle:name style:0 handler:^(id _){
            applyPatch(name, p[@"re"], p[@"rep"]);
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:1 handler:nil]];
    [topVC() presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Floating Button Init

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{

        UIWindow *win = UIApplication.sharedApplication.keyWindow;

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, 200, 70, 70);
        btn.layer.cornerRadius = 35;
        btn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        btn.tintColor = UIColor.whiteColor;
        [btn setTitle:@"Menu" forState:0];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];

        [btn addTarget:nil action:@selector(showMenuPressed) forControlEvents:UIControlEventTouchUpInside];

        [win addSubview:btn];
        [win bringSubviewToFront:btn];
    });
}

// Add the selector for the button
%hook UIApplication
%new
- (void)showMenuPressed {
    showMenu();
}
%end
