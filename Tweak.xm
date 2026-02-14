#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Store captured user data
static NSMutableArray *capturedUsers = nil;
static NSString *authToken = nil;
static UIButton *menuButton = nil;

// Menu view controller interface
@interface LocketMenuViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) NSMutableArray *filteredUsers;
@property (nonatomic, strong) NSMutableDictionary *selectedUsers;
@end

@implementation LocketMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    self.selectedUsers = [NSMutableDictionary dictionary];
    self.filteredUsers = [capturedUsers mutableCopy];
    
    // Title label
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 50, self.view.bounds.size.width, 44)];
    titleLabel.text = @"Locket Friends Manager";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [self.view addSubview:titleLabel];
    
    // Status label
    UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 90, self.view.bounds.size.width - 40, 20)];
    statusLabel.text = [NSString stringWithFormat:@"👥 %lu users captured | %@ Token", 
                       (unsigned long)capturedUsers.count,
                       authToken ? @"✓" : @"✗"];
    statusLabel.textAlignment = NSTextAlignmentCenter;
    statusLabel.font = [UIFont systemFontOfSize:12];
    statusLabel.textColor = [UIColor grayColor];
    [self.view addSubview:statusLabel];
    
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
        [self.loginButton setTitle:@"Manual Login (or wait for auto-capture)" forState:UIControlStateNormal];
        self.loginButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:1.0];
    }
    
    [self.loginButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.loginButton.layer.cornerRadius = 8;
    [self.loginButton addTarget:self action:@selector(showLoginPrompt) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.loginButton];
    
    // Search bar
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 174, self.view.bounds.size.width, 56)];
    self.searchBar.placeholder = @"Search by username or name...";
    self.searchBar.delegate = self;
    [self.view addSubview:self.searchBar];
    
    // Table view
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
}

- (void)closeMenu {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showLoginPrompt {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Login to Locket"
                                                                   message:@"Enter your credentials"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Email";
        textField.keyboardType = UIKeyboardTypeEmailAddress;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Password";
        textField.secureTextEntry = YES;
    }];
    
    UIAlertAction *loginAction = [UIAlertAction actionWithTitle:@"Login" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *email = alert.textFields[0].text;
        NSString *password = alert.textFields[1].text;
        [self loginWithEmail:email password:password];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:loginAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)loginWithEmail:(NSString *)email password:(NSString *)password {
    NSURL *url = [NSURL URLWithString:@"https://www.googleapis.com/identitytoolkit/v3/relyingparty/verifyPassword?key=AIzaSyCQngaaXQIfJaH0aS2l7REgIjD7nL431So"];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"content-type"];
    [request setValue:@"*/*" forHTTPHeaderField:@"accept"];
    [request setValue:@"iOS/FirebaseSDK/10.23.1/FirebaseCore-iOS" forHTTPHeaderField:@"x-client-version"];
    [request setValue:@"com.locket.Locket" forHTTPHeaderField:@"x-ios-bundle-identifier"];
    
    NSDictionary *payload = @{
        @"email": email,
        @"password": password,
        @"clientType": @"CLIENT_TYPE_IOS",
        @"returnSecureToken": @YES
    };
    
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [self showAlert:@"Error" message:[NSString stringWithFormat:@"Login failed: %@", error.localizedDescription]];
                return;
            }
            
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (json[@"idToken"]) {
                authToken = json[@"idToken"];
                [self.loginButton setTitle:@"✓ Token Set (Manual Login)" forState:UIControlStateNormal];
                self.loginButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.2 alpha:1.0];
                [self showAlert:@"Success" message:@"Login successful! Token saved."];
            } else {
                [self showAlert:@"Error" message:@"Login failed. Check credentials."];
            }
        });
    }] resume];
}

- (void)deleteUnselectedFriends {
    if (!authToken) {
        [self showAlert:@"Error" message:@"Please login first to get authorization token"];
        return;
    }
    
    NSMutableArray *toDelete = [NSMutableArray array];
    for (NSDictionary *user in self.filteredUsers) {
        NSString *uid = user[@"uid"];
        if (![self.selectedUsers[uid] boolValue]) {
            [toDelete addObject:user];
        }
    }
    
    if (toDelete.count == 0) {
        [self showAlert:@"Info" message:@"No users to delete. All are selected."];
        return;
    }
    
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Confirm Deletion"
                                                                     message:[NSString stringWithFormat:@"Delete %lu friend(s)?", (unsigned long)toDelete.count]
                                                              preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *deleteAction = [UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self performBatchDelete:toDelete];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    
    [confirm addAction:deleteAction];
    [confirm addAction:cancelAction];
    
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)performBatchDelete:(NSArray *)users {
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
            [NSThread sleepForTimeInterval:0.5]; // Rate limiting
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showAlert:@"Deletion Complete" 
                   message:[NSString stringWithFormat:@"Success: %ld\nFailed: %ld", (long)successCount, (long)failCount]];
            [self.tableView reloadData];
        });
    });
}

- (BOOL)deleteFriendWithUID:(NSString *)uid {
    NSURL *url = [NSURL URLWithString:@"https://api.locketcamera.com/deleteFriendRequest"];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"content-type"];
    [request setValue:@"*/*" forHTTPHeaderField:@"accept"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", authToken] forHTTPHeaderField:@"authorization"];
    
    NSDictionary *payload = @{
        @"data": @{
            @"direction": @"incoming",
            @"user_uid": uid
        }
    };
    
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    
    __block BOOL success = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            success = YES;
        }
        dispatch_semaphore_signal(semaphore);
    }] resume];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return success;
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// UITableView DataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredUsers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"UserCell" forIndexPath:indexPath];
    
    NSDictionary *user = self.filteredUsers[indexPath.row];
    NSString *uid = user[@"uid"];
    NSString *firstName = user[@"first_name"] ?: @"";
    NSString *lastName = user[@"last_name"] ?: @"";
    NSString *username = user[@"username"] ?: @"";
    
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@ (@%@)", firstName, lastName, username];
    cell.textLabel.numberOfLines = 2;
    cell.textLabel.font = [UIFont systemFontOfSize:14];
    
    // Checkbox accessory
    BOOL isSelected = [self.selectedUsers[uid] boolValue];
    cell.accessoryType = isSelected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSDictionary *user = self.filteredUsers[indexPath.row];
    NSString *uid = user[@"uid"];
    
    BOOL currentState = [self.selectedUsers[uid] boolValue];
    self.selectedUsers[uid] = @(!currentState);
    
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

// UISearchBar Delegate
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.filteredUsers = [capturedUsers mutableCopy];
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *user, NSDictionary *bindings) {
            NSString *firstName = [user[@"first_name"] lowercaseString] ?: @"";
            NSString *lastName = [user[@"last_name"] lowercaseString] ?: @"";
            NSString *username = [user[@"username"] lowercaseString] ?: @"";
            NSString *search = [searchText lowercaseString];
            
            return [firstName containsString:search] || [lastName containsString:search] || [username containsString:search];
        }];
        
        self.filteredUsers = [[capturedUsers filteredArrayUsingPredicate:predicate] mutableCopy];
    }
    
    [self.tableView reloadData];
}

@end

// Swizzle method to capture network responses
static void (*original_completion)(id, SEL, NSData*, NSURLResponse*, NSError*);

void custom_completion(id self, SEL _cmd, NSData *data, NSURLResponse *response, NSError *error) {
    @try {
        if (data && !error && response) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSString *urlString = httpResponse.URL.absoluteString;
            
            // Capture fetchUserV2 responses
            if ([urlString containsString:@"api.locketcamera.com/fetchUserV2"]) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (json[@"result"][@"data"]) {
                    NSDictionary *userData = json[@"result"][@"data"];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (!capturedUsers) {
                            capturedUsers = [NSMutableArray array];
                        }
                        
                        NSString *uid = userData[@"uid"];
                        BOOL exists = NO;
                        for (NSDictionary *existing in capturedUsers) {
                            if ([existing[@"uid"] isEqualToString:uid]) {
                                exists = YES;
                                break;
                            }
                        }
                        
                        if (!exists && uid) {
                            [capturedUsers addObject:userData];
                            NSLog(@"[Locket Tweak] Captured user: %@ %@ (@%@)", 
                                  userData[@"first_name"], userData[@"last_name"], userData[@"username"]);
                        }
                    });
                }
            }
            
            // Capture authentication token from verifyPassword
            if ([urlString containsString:@"identitytoolkit/v3/relyingparty/verifyPassword"]) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (json[@"idToken"]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        authToken = json[@"idToken"];
                        NSLog(@"[Locket Tweak] Captured auth token automatically!");
                        
                        // Update button title if it exists
                        if (menuButton) {
                            // We'll update it when menu opens
                        }
                    });
                }
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[Locket Tweak] Error in completion handler: %@", exception);
    }
    
    // Call original completion
    if (original_completion) {
        original_completion(self, _cmd, data, response, error);
    }
}

// Hook NSURLSessionTask completion handler
%hook __NSCFLocalDataTask

- (id)initWithOriginalRequest:(NSURLRequest *)request ident:(NSUInteger)ident taskGroup:(id)group {
    id result = %orig;
    return result;
}

%end

// Better approach: Hook the session delegate methods
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    
    void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        @try {
            if (data && !error && response) {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                NSString *urlString = httpResponse.URL.absoluteString;
                
                // Capture fetchUserV2 responses
                if ([urlString containsString:@"api.locketcamera.com/fetchUserV2"]) {
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if (json[@"result"][@"data"]) {
                        NSDictionary *userData = json[@"result"][@"data"];
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (!capturedUsers) {
                                capturedUsers = [NSMutableArray array];
                            }
                            
                            NSString *uid = userData[@"uid"];
                            BOOL exists = NO;
                            for (NSDictionary *existing in capturedUsers) {
                                if ([existing[@"uid"] isEqualToString:uid]) {
                                    exists = YES;
                                    break;
                                }
                            }
                            
                            if (!exists && uid) {
                                [capturedUsers addObject:userData];
                                NSLog(@"[Locket Tweak] Captured user: %@ %@ (@%@)", 
                                      userData[@"first_name"], userData[@"last_name"], userData[@"username"]);
                            }
                        });
                    }
                }
                
                // Capture authentication token from verifyPassword
                if ([urlString containsString:@"identitytoolkit/v3/relyingparty/verifyPassword"]) {
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if (json[@"idToken"]) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            authToken = json[@"idToken"];
                            NSLog(@"[Locket Tweak] ✓ Auto-captured auth token from login!");
                        });
                    }
                }
            }
        } @catch (NSException *exception) {
            NSLog(@"[Locket Tweak] Error capturing response: %@", exception);
        }
        
        // Call original completion handler
        if (completionHandler) {
            completionHandler(data, response, error);
        }
    };
    
    return %orig(request, wrappedHandler);
}

%end

// Add button to open menu - safer approach
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                UIWindow *window = [UIApplication sharedApplication].keyWindow;
                if (!window) {
                    window = [UIApplication sharedApplication].windows.firstObject;
                }
                
                if (window && !menuButton) {
                    // Create floating button
                    menuButton = [UIButton buttonWithType:UIButtonTypeCustom];
                    menuButton.frame = CGRectMake(20, 100, 60, 60);
                    menuButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
                    menuButton.layer.cornerRadius = 30;
                    menuButton.layer.shadowColor = [UIColor blackColor].CGColor;
                    menuButton.layer.shadowOffset = CGSizeMake(0, 2);
                    menuButton.layer.shadowOpacity = 0.3;
                    menuButton.layer.shadowRadius = 4;
                    [menuButton setTitle:@"🔧" forState:UIControlStateNormal];
                    menuButton.titleLabel.font = [UIFont systemFontOfSize:30];
                    
                    [menuButton addTarget:menuButton action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
                    
                    // Make it draggable
                    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:menuButton action:@selector(handlePan:)];
                    [menuButton addGestureRecognizer:pan];
                    
                    [window addSubview:menuButton];
                    menuButton.layer.zPosition = 999;
                    
                    NSLog(@"[Locket Tweak] Menu button created successfully");
                }
            } @catch (NSException *exception) {
                NSLog(@"[Locket Tweak] Error creating button: %@", exception);
            }
        });
    });
}

%new
- (void)openMenu {
    @try {
        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }
        
        if (rootVC) {
            LocketMenuViewController *menuVC = [[LocketMenuViewController alloc] init];
            menuVC.modalPresentationStyle = UIModalPresentationFullScreen;
            [rootVC presentViewController:menuVC animated:YES completion:nil];
            NSLog(@"[Locket Tweak] Menu opened");
        }
    } @catch (NSException *exception) {
        NSLog(@"[Locket Tweak] Error opening menu: %@", exception);
    }
}

%new
- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    @try {
        UIButton *button = (UIButton *)gesture.view;
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        
        CGPoint translation = [gesture translationInView:window];
        button.center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
        [gesture setTranslation:CGPointZero inView:window];
        
        if (gesture.state == UIGestureRecognizerStateEnded) {
            // Snap to edges
            CGFloat screenWidth = window.bounds.size.width;
            CGFloat screenHeight = window.bounds.size.height;
            
            CGPoint center = button.center;
            if (center.x < screenWidth / 2) {
                center.x = 40;
            } else {
                center.x = screenWidth - 40;
            }
            
            if (center.y < 80) center.y = 80;
            if (center.y > screenHeight - 80) center.y = screenHeight - 80;
            
            [UIView animateWithDuration:0.3 animations:^{
                button.center = center;
            }];
        }
    } @catch (NSException *exception) {
        NSLog(@"[Locket Tweak] Error in pan gesture: %@", exception);
    }
}

%end

%ctor {
    @try {
        NSLog(@"[Locket Tweak] ===== INITIALIZING =====");
        capturedUsers = [NSMutableArray array];
        authToken = nil;
        NSLog(@"[Locket Tweak] ✓ Loaded successfully!");
        NSLog(@"[Locket Tweak] ✓ Auto-capturing enabled for:");
        NSLog(@"[Locket Tweak]   - fetchUserV2 (user data)");
        NSLog(@"[Locket Tweak]   - verifyPassword (auth token)");
    } @catch (NSException *exception) {
        NSLog(@"[Locket Tweak] ERROR in constructor: %@", exception);
    }
}
