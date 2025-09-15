#import <UIKit/UIKit.h>
#import <DeviceCheck/DeviceCheck.h>

static NSString *savedURLKey = @"com.chillysilly.savedURL";

@interface TokenOverlayView : UIView
@property (nonatomic, strong) UITextView *logBox;
@property (nonatomic, strong) UILabel *urlLabel;
@property (nonatomic, strong) UITextField *urlField;
@end

@implementation TokenOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
        self.layer.cornerRadius = 12;
        self.clipsToBounds = YES;

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, frame.size.width, 30)];
        title.text = @"Device Token";
        title.textAlignment = NSTextAlignmentCenter;
        title.textColor = [UIColor whiteColor];
        title.font = [UIFont boldSystemFontOfSize:18];
        [self addSubview:title];

        self.logBox = [[UITextView alloc] initWithFrame:CGRectMake(10, 50, frame.size.width-20, 120)];
        self.logBox.backgroundColor = [UIColor blackColor];
        self.logBox.textColor = [UIColor greenColor];
        self.logBox.font = [UIFont systemFontOfSize:12];
        self.logBox.editable = NO;
        self.logBox.layer.cornerRadius = 6;
        [self addSubview:self.logBox];

        UIButton *genBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        genBtn.frame = CGRectMake(10, 180, frame.size.width-20, 40);
        [genBtn setTitle:@"Generate" forState:UIControlStateNormal];
        genBtn.backgroundColor = [UIColor darkGrayColor];
        genBtn.tintColor = [UIColor whiteColor];
        genBtn.layer.cornerRadius = 8;
        [genBtn addTarget:self action:@selector(generateToken) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:genBtn];

        self.urlLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 230, frame.size.width-20, 20)];
        self.urlLabel.textColor = [UIColor whiteColor];
        self.urlLabel.font = [UIFont systemFontOfSize:12];
        [self addSubview:self.urlLabel];

        self.urlField = [[UITextField alloc] initWithFrame:CGRectMake(10, 260, frame.size.width-100, 30)];
        self.urlField.borderStyle = UITextBorderStyleRoundedRect;
        self.urlField.placeholder = @"Enter URL";
        [self addSubview:self.urlField];

        UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        saveBtn.frame = CGRectMake(frame.size.width-80, 260, 70, 30);
        [saveBtn setTitle:@"Save" forState:UIControlStateNormal];
        [saveBtn addTarget:self action:@selector(saveURL) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:saveBtn];

        UILabel *credit = [[UILabel alloc] initWithFrame:CGRectMake(0, frame.size.height-20, frame.size.width, 20)];
        credit.text = @"@mochiteyvat";
        credit.textAlignment = NSTextAlignmentCenter;
        credit.textColor = [UIColor lightGrayColor];
        credit.font = [UIFont italicSystemFontOfSize:12];
        [self addSubview:credit];

        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(frame.size.width-40, 10, 30, 30);
        [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:closeBtn];

        NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:savedURLKey];
        if (saved) {
            self.urlLabel.text = [NSString stringWithFormat:@"Current URL: %@", saved];
        }
    }
    return self;
}

- (void)appendLog:(NSString *)text {
    self.logBox.text = [self.logBox.text stringByAppendingFormat:@"%@\n", text];
    [self.logBox scrollRangeToVisible:NSMakeRange(self.logBox.text.length, 0)];
}

- (void)saveURL {
    if (self.urlField.text.length == 0) return;
    [[NSUserDefaults standardUserDefaults] setObject:self.urlField.text forKey:savedURLKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    self.urlLabel.text = [NSString stringWithFormat:@"Current URL: %@", self.urlField.text];
    [self appendLog:@"[+] Saved new URL"];
}

- (void)generateToken {
    [self.logBox setText:@""]; // clear log
    [self appendLog:@"Hooking into app main…"];
    [self appendLog:@"Request Apple API…"];

    if (![DCDevice currentDevice].isSupported) {
        [self appendLog:@"[!] DeviceCheck not supported"];
        return;
    }

    [[DCDevice currentDevice] generateTokenWithCompletionHandler:^(NSData * _Nullable data, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [self appendLog:[NSString stringWithFormat:@"Error: %@", error.localizedDescription]];
                return;
            }
            if (data) {
                NSString *token = [data base64EncodedStringWithOptions:0];
                [UIPasteboard generalPasteboard].string = token;
                [self appendLog:@"Generated device token"];
                [self appendLog:token];

                NSString *urlStr = [[NSUserDefaults standardUserDefaults] stringForKey:savedURLKey];
                if (!urlStr) {
                    [self appendLog:@"[!] No saved URL"];
                    return;
                }
                NSURL *url = [NSURL URLWithString:urlStr];
                NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
                req.HTTPMethod = @"POST";
                [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

                NSDictionary *json = @{@"device_token": token};
                NSData *body = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
                req.HTTPBody = body;

                [self appendLog:@"Sending to saved URL…"];

                [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (error) {
                            [self appendLog:[NSString stringWithFormat:@"Send failed: %@", error.localizedDescription]];
                        } else {
                            [self appendLog:@"[✓] Token sent successfully!"];
                        }
                    });
                }] resume];
            }
        });
    }];
}

- (void)closeMenu {
    self.hidden = YES;
    UIWindow *keyWin = [UIApplication sharedApplication].windows.firstObject;
    UIButton *floatBtn = [keyWin viewWithTag:77777];
    floatBtn.hidden = NO;
}

@end


%hook UIApplication

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    BOOL r = %orig;

    UIWindow *keyWin = [UIApplication sharedApplication].windows.firstObject;

    // floating button
    UIButton *floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    floatBtn.frame = CGRectMake(20, 100, 60, 60);
    floatBtn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    floatBtn.layer.cornerRadius = 30;
    [floatBtn setTitle:@"☰" forState:UIControlStateNormal];
    [floatBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    floatBtn.tag = 77777;
    [floatBtn addTarget:self action:@selector(showOverlay:) forControlEvents:UIControlEventTouchUpInside];

    TokenOverlayView *overlay = [[TokenOverlayView alloc] initWithFrame:CGRectMake(20, 200, keyWin.bounds.size.width-40, 320)];
    overlay.hidden = YES;
    overlay.tag = 88888;

    [keyWin addSubview:overlay];
    [keyWin addSubview:floatBtn];

    return r;
}

%new
- (void)showOverlay:(UIButton *)sender {
    UIWindow *keyWin = [UIApplication sharedApplication].windows.firstObject;
    UIView *overlay = [keyWin viewWithTag:88888];
    overlay.hidden = NO;
    sender.hidden = YES;
}

%end
