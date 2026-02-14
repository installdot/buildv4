#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Store captured user data
static NSMutableArray *capturedUsers = nil;
static NSString *authToken = nil;
static UIButton *globalMenuButton = nil;

// Custom NSURLProtocol for intercepting requests
@interface LocketURLProtocol : NSURLProtocol
@end

@implementation LocketURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:@"LocketHandled" inRequest:request]) {
        return NO;
    }
    
    NSString *urlString = request.URL.absoluteString;
    return [urlString containsString:@"api.locketcamera.com/fetchUserV2"] || 
           [urlString containsString:@"identitytoolkit/v3/relyingparty/verifyPassword"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSMutableURLRequest *newRequest = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"LocketHandled" inRequest:newRequest];
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:newRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            [self.client URLProtocol:self didFailWithError:error];
            return;
        }
        
        if (data) {
            // Intercept and parse the response
            @try {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                
                // Check for fetchUserV2 response
                if (json[@"result"][@"data"]) {
                    NSDictionary *userData = json[@"result"][@"data"];
                    [self captureUserData:userData];
                }
                
                // Check for Firebase auth response
                if (json[@"idToken"]) {
                    authToken = json[@"idToken"];
                    NSLog(@"[Locket Tweak] Auto-captured auth token!");
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (globalMenuButton) {
                            // Visual feedback
                            globalMenuButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.2 alpha:0.9];
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                globalMenuButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
                            });
                        }
                    });
                }
            } @catch (NSException *exception) {
                NSLog(@"[Locket Tweak] Parse error: %@", exception);
            }
            
            [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            [self.client URLProtocol:self didLoadData:data];
        }
        
        [self.client URLProtocolDidFinishLoading:self];
    }];
    
    [task resume];
}

- (void)stopLoading {
    // Nothing to do
}

- (void)captureUserData:(NSDictionary *)userData {
    if (!userData[@"uid"]) return;
    
    if (!capturedUsers) {
        capturedUsers = [NSMutableArray array];
    }
    
    NSString *uid = userData[@"uid"];
    
    // Check if already exists
    @synchronized(capturedUsers) {
        BOOL exists = NO;
        for (NSDictionary *existing in capturedUsers) {
            if ([existing[@"uid"] isEqualToString:uid]) {
                exists = YES;
                break;
            }
        }
        
        if (!exists) {
            [capturedUsers addObject:userData];
            NSLog(@"[Locket Tweak] Captured: %@ %@ (@%@)", 
                  userData[@"first_name"], 
                  userData[@"last_name"], 
                  userData[@"username"]);
        }
    }
}

@end

// Menu view controller
@interface LocketMenuViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSMutableArray *filteredUsers;
@property (nonatomic, strong) NSMutableDictionary *selectedUsers;
@end

@implementation LocketMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    self.selectedUsers = [NSMutableDictionary dictionary];
    
    @synchronized(capturedUsers) {
        self.filteredUsers = [capturedUsers mutableCopy];
    }
    
    [self setupUI];
}

- (void)setupUI {
    // Title label
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 50, self.view.bounds.size.width, 44)];
    titleLabel.text = @"Locket Friends Manager";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [self.view addSubview:titleLabel];
    
    // Close button
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(self.view.bounds.size.width - 70, 50, 60, 44);
    [closeButton setTitle:@"Close" forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeButton];
    
    // Status label (token status)
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, self.view.bounds.size.width - 40, 30)];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    if (authToken) {
        self.statusLabel.text = [NSString stringWithFormat:@"✓ Token Set | %lu Users Captured", (unsigned long)capturedUsers.count];
        self.statusLabel.textColor = [UIColor colorWithRed:0.0 green:0.6 blue:0.0 alpha:1.0];
    } else {
        self.statusLabel.text = @"⚠ No Token (Login in Locket app to auto-capture)";
        self.statusLabel.textColor = [UIColor colorWithRed:0.8 green:0.4 blue:0.0 alpha:1.0];
    }
    [self.view addSubview:self.statusLabel];
    
    // Search bar
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 140, self.view.bounds.size.width, 56)];
    self.searchBar.placeholder = @"Search username or name...";
    self.searchBar.delegate = self;
    [self.view addSubview:self.searchBar];
    
    // Table view
    CGFloat tableY = 196;
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
}

- (void)closeMenu {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)deleteUnselectedFriends {
    if (!authToken) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Token" 
                                                                       message:@"Please login in the Locket app first. The token will be auto-captured." 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSMutableArray *toDelete = [NSMutableArray array];
    @synchronized(capturedUsers) {
        for (NSDictionary *user in self.filteredUsers) {
            NSString *uid = user[@"uid"];
            if (![self.selectedUsers[uid] boolValue]) {
                [toDelete addObject:user];
            }
        }
    }
    
    if (toDelete.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Info" 
                                                                       message:@"No users to delete. All are selected." 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Confirm Deletion"
                                                                     message:[NSString stringWithFormat:@"Delete %lu friend(s)?", (unsigned long)toDelete.count]
                                                              preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *deleteAction = [UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self performBatchDelete:toDelete];
    }];
    
    [confirm addAction:deleteAction];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)performBatchDelete:(NSArray *)users {
    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"Deleting..." 
                                                                           message:@"Please wait..." 
                                                                    preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progressAlert animated:YES completion:nil];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSInteger successCount = 0;
        NSInteger failCount = 0;
        
        for (NSDictionary *user in users) {
            NSString *uid = user[@"uid"];
            if ([self deleteFriendWithUID:uid]) {
                successCount++;
            } else {
                failCount++;
            }
            [NSThread sleepForTimeInterval:0.5];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [progressAlert dismissViewControllerAnimated:YES completion:^{
                UIAlertController *result = [UIAlertController alertControllerWithTitle:@"Complete" 
                                                                               message:[NSString stringWithFormat:@"Success: %ld\nFailed: %ld", (long)successCount, (long)failCount] 
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [result addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:result animated:YES completion:nil];
                [self.tableView reloadData];
            }];
        });
    });
}

- (BOOL)deleteFriendWithUID:(NSString *)uid {
    NSURL *url = [NSURL URLWithString:@"https://api.locketcamera.com/deleteFriendRequest"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"content-type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", authToken] forHTTPHeaderField:@"authorization"];
    
    NSDictionary *payload = @{@"data": @{@"direction": @"incoming", @"user_uid": uid}};
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    
    __block BOOL success = NO;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        success = !error && data;
        dispatch_semaphore_signal(sema);
    }] resume];
    
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return success;
}

// Table View
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredUsers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"UserCell" forIndexPath:indexPath];
    NSDictionary *user = self.filteredUsers[indexPath.row];
    NSString *uid = user[@"uid"];
    
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@ (@%@)", 
                          user[@"first_name"] ?: @"", 
                          user[@"last_name"] ?: @"", 
                          user[@"username"] ?: @""];
    cell.textLabel.numberOfLines = 2;
    cell.textLabel.font = [UIFont systemFontOfSize:14];
    cell.accessoryType = [self.selectedUsers[uid] boolValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *user = self.filteredUsers[indexPath.row];
    NSString *uid = user[@"uid"];
    self.selectedUsers[uid] = @(![self.selectedUsers[uid] boolValue]);
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

// Search
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    @synchronized(capturedUsers) {
        if (searchText.length == 0) {
            self.filteredUsers = [capturedUsers mutableCopy];
        } else {
            NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *user, NSDictionary *bindings) {
                NSString *search = [searchText lowercaseString];
                return [[user[@"first_name"] lowercaseString] containsString:search] ||
                       [[user[@"last_name"] lowercaseString] containsString:search] ||
                       [[user[@"username"] lowercaseString] containsString:search];
            }];
            self.filteredUsers = [[capturedUsers filteredArrayUsingPredicate:predicate] mutableCopy];
        }
    }
    [self.tableView reloadData];
}

@end

// Hook UIApplication to add button
%hook UIApplication

- (void)setDelegate:(id<UIApplicationDelegate>)delegate {
    %orig;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!globalMenuButton) {
            UIWindow *keyWindow = nil;
            for (UIWindow *window in self.windows) {
                if (window.isKeyWindow) {
                    keyWindow = window;
                    break;
                }
            }
            
            if (keyWindow) {
                UIButton *menuButton = [UIButton buttonWithType:UIButtonTypeCustom];
                menuButton.frame = CGRectMake(20, 100, 60, 60);
                menuButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
                menuButton.layer.cornerRadius = 30;
                menuButton.layer.shadowColor = [UIColor blackColor].CGColor;
                menuButton.layer.shadowOffset = CGSizeMake(0, 2);
                menuButton.layer.shadowOpacity = 0.3;
                menuButton.layer.shadowRadius = 4;
                [menuButton setTitle:@"🔧" forState:UIControlStateNormal];
                menuButton.titleLabel.font = [UIFont systemFontOfSize:30];
                
                [menuButton addTarget:menuButton action:@selector(openMenu:) forControlEvents:UIControlEventTouchUpInside];
                
                UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:menuButton action:@selector(handlePan:)];
                [menuButton addGestureRecognizer:pan];
                
                [keyWindow addSubview:menuButton];
                menuButton.layer.zPosition = 999;
                globalMenuButton = menuButton;
                
                NSLog(@"[Locket Tweak] Menu button added!");
            }
        }
    });
}

%new
- (void)openMenu:(id)sender {
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    
    LocketMenuViewController *menuVC = [[LocketMenuViewController alloc] init];
    menuVC.modalPresentationStyle = UIModalPresentationFullScreen;
    [rootVC presentViewController:menuVC animated:YES completion:nil];
}

%new
- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIButton *button = (UIButton *)gesture.view;
    CGPoint translation = [gesture translationInView:button.superview];
    button.center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:button.superview];
}

%end

%ctor {
    @autoreleasepool {
        NSLog(@"[Locket Tweak] Initializing...");
        capturedUsers = [NSMutableArray array];
        
        // Register custom URL protocol for continuous capture
        [NSURLProtocol registerClass:[LocketURLProtocol class]];
        
        NSLog(@"[Locket Tweak] Loaded! Capturing all fetchUserV2 and auth requests...");
    }
}
