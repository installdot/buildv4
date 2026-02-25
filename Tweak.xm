// FakeUDID.xm
// Compile with Theos as a standard tweak dylib
// Put in your tweak folder, create filter.plist if you want to inject only into specific app (recommended)
// Example filter.plist:
// { Filter = { Bundles = ( "com.your.target.app" ); }; }

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static short const kUDIDLength = 40;
static short const kPrefixLength = 25;
static short const kSuffixLength = 9;

/// <key>UDID</key>\n\t<string>
static uint8_t const kPrefix[kPrefixLength] = {
  0x3C, 0x6B, 0x65, 0x79, 0x3E, 0x55, 0x44, 0x49,
  0x44, 0x3C, 0x2F, 0x6B, 0x65, 0x79, 0x3E, 0x0A,
  0x09, 0x3C, 0x73, 0x74, 0x72, 0x69, 0x6E, 0x67,
  0x3E
};

/// </string>
static uint8_t const kSuffix[kSuffixLength] = {
  0x3C, 0x2F, 0x73, 0x74, 0x72, 0x69, 0x6E, 0x67, 0x3E
};

static NSString *kPrefsFile = @"/var/mobile/Library/Preferences/com.bao.fakeudid.plist";
static NSString *currentCustomUDID = nil;

static NSString *generateRandomUDID(void) {
    // Original style shuffle but on proper 40-char hex base (website usually accepts any 40 chars anyway)
    NSMutableString *randomizedText = [NSMutableString stringWithString:@"0123456789ABCDEF0123456789ABCDEF0123456789"];
    for (NSInteger i = randomizedText.length - 1, j; i >= 0; i--) {
        j = arc4random_uniform((uint32_t)(i + 1));
        [randomizedText exchangeCharactersInRange:NSMakeRange(i, 1) withRange:NSMakeRange(j, 1)];
    }
    return [randomizedText copy];
}

static void loadPrefs(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsFile];
    currentCustomUDID = prefs[@"CustomUDID"];
    if (currentCustomUDID.length != 40) currentCustomUDID = nil;
}

static void savePrefs(NSString *udid) {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionary];
    if (udid.length == 40) {
        prefs[@"CustomUDID"] = [udid uppercaseString];
        currentCustomUDID = [udid uppercaseString];
    } else {
        [prefs removeObjectForKey:@"CustomUDID"];
        currentCustomUDID = nil;
    }
    [prefs writeToFile:kPrefsFile atomically:YES];
}

static NSData *replacedUUIDData(NSData *data) {
    if (data.length < kPrefixLength + kUDIDLength + kSuffixLength) {
        return data;
    }

    NSMutableData *mutableData = [data mutableCopy];
    uint8_t *bytes = (uint8_t *)mutableData.mutableBytes;
    uint8_t *ptr = bytes;
    uint8_t *end = bytes + mutableData.length - (kPrefixLength + kUDIDLength + kSuffixLength) + 1;

    while (ptr < end) {
        if (memcmp(ptr, kPrefix, kPrefixLength) == 0 &&
            memcmp(ptr + kPrefixLength + kUDIDLength, kSuffix, kSuffixLength) == 0) {
            
            NSString *fakeUDID = currentCustomUDID ?: generateRandomUDID();
            NSLog(@"[FakeUDID] Found UDID location → replacing with: %@", fakeUDID);
            strncpy((char *)(ptr + kPrefixLength), [fakeUDID UTF8String], kUDIDLength);
            break;
        }
        ptr++;
    }
    return mutableData;
}

%hook MCHTTPTransaction
- (void)setData:(id)arg1 {
    if ([arg1 isKindOfClass:[NSData class]]) {
        %orig(replacedUUIDData(arg1));
    } else {
        %orig(arg1);
    }
}
%end

// ==================== FLOATING MENU BUTTON ====================
@interface FakeUDIDButton : UIButton
@property (nonatomic, assign) CGPoint lastLocation;
@end

@implementation FakeUDIDButton

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:0.9];
        self.layer.cornerRadius = 30;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.6;
        self.layer.shadowRadius = 5;
        self.layer.shadowOffset = CGSizeMake(0, 3);
        
        [self setTitle:@"UDID" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        self.titleLabel.numberOfLines = 2;
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        
        [self addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIWindow *window = self.window;
    if (!window) return;
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.lastLocation = [gesture locationInView:window];
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:window];
        CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
        
        // Keep button inside screen
        newCenter.x = MAX(35, MIN(newCenter.x, window.bounds.size.width - 35));
        newCenter.y = MAX(35, MIN(newCenter.y, window.bounds.size.height - 35));
        
        self.center = newCenter;
        [gesture setTranslation:CGPointZero inView:window];
    }
}

- (void)buttonTapped {
    UIViewController *topVC = [[UIApplication sharedApplication] keyWindow].rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Fake UDID Menu"
                                                                  message:currentCustomUDID ? [NSString stringWithFormat:@"Current custom:\n%@", currentCustomUDID] : @"Mode: Random (auto-generated)"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    
    [menu addAction:[UIAlertAction actionWithTitle:@"Generate Random & Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *rnd = generateRandomUDID();
        savePrefs(rnd);
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Saved!" message:rnd preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [topVC presentViewController:done animated:YES completion:nil];
    }]];
    
    [menu addAction:[UIAlertAction actionWithTitle:@"Set Custom UDID" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UIAlertController *input = [UIAlertController alertControllerWithTitle:@"Enter 40-char UDID"
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [input addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"DF9249D4418QE1E79C87D1A58FE4247434EFF1D1";
            textField.text = currentCustomUDID;
            textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
            textField.keyboardType = UIKeyboardTypeASCIICapable;
        }];
        
        [input addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *inputText = input.textFields.firstObject.text;
            if (inputText.length == 40) {
                savePrefs(inputText);
            } else {
                UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Error" message:@"Must be exactly 40 characters" preferredStyle:UIAlertControllerStyleAlert];
                [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [topVC presentViewController:err animated:YES completion:nil];
            }
        }]];
        [input addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [topVC presentViewController:input animated:YES completion:nil];
    }]];
    
    [menu addAction:[UIAlertAction actionWithTitle:@"Use Random (clear custom)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        savePrefs(nil);
    }]];
    
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [topVC presentViewController:menu animated:YES completion:nil];
}

@end

%ctor {
    loadPrefs();
    
    // Add floating button to ANY app the tweak is injected into
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
            if (!keyWindow) {
                if (@available(iOS 13.0, *)) {
                    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                        if (scene.activationState == UISceneActivationStateForegroundActive) {
                            keyWindow = scene.windows.firstObject;
                            break;
                        }
                    }
                }
            }
            if (keyWindow && ![keyWindow viewWithTag:13371337]) {
                FakeUDIDButton *btn = [[FakeUDIDButton alloc] initWithFrame:CGRectMake(keyWindow.bounds.size.width - 75, keyWindow.bounds.size.height - 180, 60, 60)];
                btn.tag = 13371337; // prevent duplicates
                [keyWindow addSubview:btn];
                NSLog(@"[FakeUDID] Floating menu button added");
            }
        });
    }];
    
    NSLog(@"[FakeUDID] Loaded by Bảo | Custom UDID: %@", currentCustomUDID ?: @"(random each time)");
    %init;
}
