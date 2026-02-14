#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Global variables
static NSMutableArray *capturedUsers = nil;
static NSString *authToken = nil;
static UIWindow *overlayWindow = nil;

// Forward declarations
@interface LocketOverlayWindow : UIWindow
@property (nonatomic, strong) UIButton *floatingButton;
- (void)createFloatingButton;
- (void)openMenu;
@end

@interface LocketMenuViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) NSMutableArray *filteredUsers;
@property (nonatomic, strong) NSMutableDictionary *selectedUsers;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, weak) UIWindow *menuWindow;
@end

// Menu View Controller Implementation
@implementation LocketMenuViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        self.selectedUsers = [NSMutableDictionary dictionary];
        self.filteredUsers = capturedUsers ? [capturedUsers mutableCopy] : [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    @try {
        self.view.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
        
        // Title
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 50, self.view.bounds.size.width, 44)];
        titleLabel.text = @"Locket Friends Manager";
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.font = [UIFont boldSystemFontOfSize:20];
        [self.view addSubview:titleLabel];
        
        // Status
        self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 90, self.view.bounds.size.width - 40, 20)];
        NSInteger userCount = capturedUsers ? capturedUsers.count : 0;
        self.statusLabel.text = [NSString stringWithFormat:@"👥 %ld users | %@ Token", (long)userCount, authToken ? @"✓" : @"✗"];
        self.statusLabel.textAlignment = NSTextAlignmentCenter;
        self.statusLabel.font = [UIFont systemFontOfSize:12];
        self.statusLabel.textColor = [UIColor grayColor];
        [self.view addSubview:self.statusLabel];
        
        // Close button
        UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        closeButton.frame = CGRectMake(self.view.bounds.size.width - 60, 50, 50, 44);
        [closeButton setTitle:@"Close" forState:UIControlStateNormal];
        [closeButton addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:closeButton];
        
        // Login button
        self.loginButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.loginButton.frame = CGRectMake(20, 120, self.view.bounds.size.width - 40, 44);
        if (authToken) {
            [self.loginButton setTitle:@"✓ Token Auto-Captured" forState:UIControlStateNormal];
            self.loginButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.2 alpha:1.0];
        } else {
            [self.loginButton setTitle:@"Manual Login (or wait)" forState:UIControlStateNormal];
            self.loginButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:1.0];
        }
        [self.loginButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.loginButton.layer.cornerRadius = 8;
        [self.loginButton addTarget:self action:@selector(showLoginPrompt) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:self.loginButton];
        
        // Search bar
        self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 174, self.view.bounds.size.width, 56)];
        self.searchBar.placeholder = @"Search username or name...";
        self.searchBar.delegate = self;
        [self.view addSubview:self.searchBar];
        
        // Table
        CGFloat tableY = 230;
        CGFloat tableHeight = self.view.bounds.size.height - tableY - 80;
        self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, tableY, self.view.bounds.size.width, tableHeight) style:UITableViewStylePlain];
        self.tableView.delegate = self;
        self.tableView.dataSource = self;
        [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"UserCell"];
        [self.view addSubview:self.tableView];
        
        // Delete button
        self.deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.deleteButton.frame = CGRectMake(20, self.view.bounds.size.height - 70, self.view.bounds.size.width - 40, 50);
        [self.deleteButton setTitle:@"Delete Unselected Friends" forState:UIControlStateNormal];
        self.deleteButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0];
        [self.deleteButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.deleteButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        self.deleteButton.layer.cornerRadius = 10;
        [self.deleteButton addTarget:self action:@selector(deleteUnselectedFriends) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:self.deleteButton];
        
    } @catch (NSException *e) {
        NSLog(@"[Locket Tweak] Error in viewDidLoad: %@", e);
    }
}

- (void)closeMenu {
    if (self.menuWindow) {
        self.menuWindow.hidden = YES;
        self.menuWindow = nil;
    }
}

- (void)showLoginPrompt {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Login" message:@"Enter credentials" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Email"; tf.keyboardType = UIKeyboardTypeEmailAddress; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Password"; tf.secureTextEntry = YES; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Login" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self loginWithEmail:alert.textFields[0].text password:alert.textFields[1].text];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)loginWithEmail:(NSString *)email password:(NSString *)password {
    NSURL *url = [NSURL URLWithString:@"https://www.googleapis.com/identitytoolkit/v3/relyingparty/verifyPassword?key=AIzaSyCQngaaXQIfJaH0aS2l7REgIjD7nL431So"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"content-type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"email":email, @"password":password, @"clientType":@"CLIENT_TYPE_IOS", @"returnSecureToken":@YES} options:0 error:nil];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!err && data) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (json[@"idToken"]) {
                    authToken = json[@"idToken"];
                    [self.loginButton setTitle:@"✓ Token Set" forState:UIControlStateNormal];
                    self.loginButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.2 alpha:1.0];
                    [self showAlert:@"Success" message:@"Token saved!"];
                } else {
                    [self showAlert:@"Error" message:@"Login failed"];
                }
            } else {
                [self showAlert:@"Error" message:err.localizedDescription];
            }
        });
    }] resume];
}

- (void)deleteUnselectedFriends {
    if (!authToken) {
        [self showAlert:@"Error" message:@"Please login first"];
        return;
    }
    
    NSMutableArray *toDelete = [NSMutableArray array];
    for (NSDictionary *user in self.filteredUsers) {
        if (![self.selectedUsers[user[@"uid"]] boolValue]) {
            [toDelete addObject:user];
        }
    }
    
    if (toDelete.count == 0) {
        [self showAlert:@"Info" message:@"No users to delete"];
        return;
    }
    
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Confirm" message:[NSString stringWithFormat:@"Delete %lu friend(s)?", (unsigned long)toDelete.count] preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self performBatchDelete:toDelete];
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)performBatchDelete:(NSArray *)users {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSInteger success = 0, fail = 0;
        for (NSDictionary *user in users) {
            if ([self deleteFriendWithUID:user[@"uid"]]) success++; else fail++;
            [NSThread sleepForTimeInterval:0.5];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showAlert:@"Complete" message:[NSString stringWithFormat:@"Success: %ld, Failed: %ld", (long)success, (long)fail]];
            [self.tableView reloadData];
        });
    });
}

- (BOOL)deleteFriendWithUID:(NSString *)uid {
    NSURL *url = [NSURL URLWithString:@"https://api.locketcamera.com/deleteFriendRequest"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"content-type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", authToken] forHTTPHeaderField:@"authorization"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"data":@{@"direction":@"incoming",@"user_uid":uid}} options:0 error:nil];
    
    __block BOOL success = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (!e && d) success = YES;
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    return success;
}

- (void)showAlert:(NSString *)title message:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.filteredUsers ? self.filteredUsers.count : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"UserCell" forIndexPath:ip];
    if (ip.row < self.filteredUsers.count) {
        NSDictionary *user = self.filteredUsers[ip.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ %@ (@%@)", user[@"first_name"]?:@"", user[@"last_name"]?:@"", user[@"username"]?:@""];
        cell.textLabel.numberOfLines = 2;
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.accessoryType = [self.selectedUsers[user[@"uid"]] boolValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.row < self.filteredUsers.count) {
        NSDictionary *user = self.filteredUsers[ip.row];
        NSString *uid = user[@"uid"];
        self.selectedUsers[uid] = @(![self.selectedUsers[uid] boolValue]);
        [tv reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)searchBar:(UISearchBar *)sb textDidChange:(NSString *)text {
    if (!capturedUsers) {
        self.filteredUsers = [NSMutableArray array];
    } else if (text.length == 0) {
        self.filteredUsers = [capturedUsers mutableCopy];
    } else {
        NSString *search = [text lowercaseString];
        self.filteredUsers = [[capturedUsers filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *u, NSDictionary *b) {
            return [[u[@"first_name"] lowercaseString] containsString:search] || [[u[@"last_name"] lowercaseString] containsString:search] || [[u[@"username"] lowercaseString] containsString:search];
        }]] mutableCopy];
    }
    [self.tableView reloadData];
}

@end

// Overlay Window Implementation
@implementation LocketOverlayWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.windowLevel = UIWindowLevelStatusBar + 100;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    self.windowScene = (UIWindowScene *)scene;
                    break;
                }
            }
        }
        
        self.rootViewController = [[UIViewController alloc] init];
        self.rootViewController.view.backgroundColor = [UIColor clearColor];
        self.rootViewController.view.userInteractionEnabled = YES;
        
        [self createFloatingButton];
        self.hidden = NO;
    }
    return self;
}

- (void)createFloatingButton {
    @try {
        self.floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatingButton.frame = CGRectMake(20, 100, 60, 60);
        self.floatingButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
        self.floatingButton.layer.cornerRadius = 30;
        self.floatingButton.layer.shadowColor = [UIColor blackColor].CGColor;
        self.floatingButton.layer.shadowOffset = CGSizeMake(0, 2);
        self.floatingButton.layer.shadowOpacity = 0.3;
        self.floatingButton.layer.shadowRadius = 4;
        [self.floatingButton setTitle:@"🔧" forState:UIControlStateNormal];
        self.floatingButton.titleLabel.font = [UIFont systemFontOfSize:30];
        [self.floatingButton addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self.floatingButton addGestureRecognizer:pan];
        
        [self.rootViewController.view addSubview:self.floatingButton];
        
        NSLog(@"[Locket Tweak] ✓ Button created in overlay window");
    } @catch (NSException *e) {
        NSLog(@"[Locket Tweak] Error creating button: %@", e);
    }
}

- (void)openMenu {
    @try {
        NSLog(@"[Locket Tweak] Opening menu...");
        
        if (!capturedUsers) capturedUsers = [NSMutableArray array];
        
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        UIWindow *menuWindow = [[UIWindow alloc] initWithFrame:screenBounds];
        menuWindow.windowLevel = UIWindowLevelAlert;
        menuWindow.backgroundColor = [UIColor clearColor];
        
        if (@available(iOS 13.0, *)) {
            menuWindow.windowScene = self.windowScene;
        }
        
        LocketMenuViewController *menuVC = [[LocketMenuViewController alloc] init];
        menuWindow.rootViewController = menuVC;
        menuVC.menuWindow = menuWindow;
        menuWindow.hidden = NO;
        
        // Keep reference
        static NSMutableArray *menuWindows = nil;
        if (!menuWindows) menuWindows = [NSMutableArray array];
        [menuWindows addObject:menuWindow];
        
        NSLog(@"[Locket Tweak] ✓ Menu opened");
    } @catch (NSException *e) {
        NSLog(@"[Locket Tweak] Error opening menu: %@", e);
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    @try {
        UIButton *btn = (UIButton *)gesture.view;
        CGPoint translation = [gesture translationInView:self.rootViewController.view];
        btn.center = CGPointMake(btn.center.x + translation.x, btn.center.y + translation.y);
        [gesture setTranslation:CGPointZero inView:self.rootViewController.view];
        
        if (gesture.state == UIGestureRecognizerStateEnded) {
            CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
            CGPoint c = btn.center;
            c.x = (c.x < w/2) ? 40 : w-40;
            if (c.y < 80) c.y = 80;
            if (c.y > h-80) c.y = h-80;
            [UIView animateWithDuration:0.3 animations:^{ btn.center = c; }];
        }
    } @catch (NSException *e) {
        NSLog(@"[Locket Tweak] Error in pan: %@", e);
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}

@end

// Network capture hook
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    
    void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        @try {
            if (data && !error && response) {
                NSString *url = ((NSHTTPURLResponse *)response).URL.absoluteString;
                
                // Capture user data
                if ([url containsString:@"api.locketcamera.com/fetchUserV2"]) {
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if (json[@"result"][@"data"]) {
                        NSDictionary *userData = json[@"result"][@"data"];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (!capturedUsers) capturedUsers = [NSMutableArray array];
                            NSString *uid = userData[@"uid"];
                            BOOL exists = NO;
                            for (NSDictionary *u in capturedUsers) {
                                if ([u[@"uid"] isEqualToString:uid]) { exists = YES; break; }
                            }
                            if (!exists && uid) {
                                [capturedUsers addObject:userData];
                                NSLog(@"[Locket Tweak] Captured: %@ %@", userData[@"first_name"], userData[@"last_name"]);
                            }
                        });
                    }
                }
                
                // Capture auth token
                if ([url containsString:@"identitytoolkit/v3/relyingparty/verifyPassword"]) {
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if (json[@"idToken"]) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            authToken = json[@"idToken"];
                            NSLog(@"[Locket Tweak] ✓ Token auto-captured!");
                        });
                    }
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[Locket Tweak] Error capturing: %@", e);
        }
        
        if (completionHandler) completionHandler(data, response, error);
    };
    
    return %orig(request, wrappedHandler);
}

%end

// Create overlay window on app launch
%hook UIApplication

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                CGRect bounds = [UIScreen mainScreen].bounds;
                overlayWindow = [[LocketOverlayWindow alloc] initWithFrame:bounds];
                NSLog(@"[Locket Tweak] ✓ Overlay window created");
            } @catch (NSException *e) {
                NSLog(@"[Locket Tweak] Error creating overlay: %@", e);
            }
        });
    });
}

%end

%ctor {
    @try {
        NSLog(@"[Locket Tweak] ===== INITIALIZING =====");
        capturedUsers = [NSMutableArray array];
        authToken = nil;
        NSLog(@"[Locket Tweak] ✓ Loaded successfully!");
    } @catch (NSException *e) {
        NSLog(@"[Locket Tweak] Error in ctor: %@", e);
    }
}
