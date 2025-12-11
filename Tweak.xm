// Tweak.xm
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - Utilities

static NSString *RandomLetters(NSUInteger n) {
    static NSString *letters = @"abcdefghijklmnopqrstuvwxyz";
    NSMutableString *s = [NSMutableString new];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [letters characterAtIndex:arc4random_uniform((uint32_t)letters.length)];
        [s appendFormat:@"%C", c];
    }
    return s;
}

static NSString *RandomDigits(NSUInteger n) {
    static NSString *digits = @"0123456789";
    NSMutableString *s = [NSMutableString new];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [digits characterAtIndex:arc4random_uniform((uint32_t)digits.length)];
        [s appendFormat:@"%C", c];
    }
    return s;
}

static NSString *RandomEmail(void) {
    return [NSString stringWithFormat:@"mochi%@%@@mochi.owo", RandomLetters(6), RandomDigits(4)];
}

static NSString *RandomUsername11(void) {
    return RandomLetters(11);
}

static NSString *RandomEmojiLastName(void) {
    static NSArray<NSString *> *emojis;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        emojis = @[@"😈",@"✨",@"💀",@"🥺",@"💕",@"🔥",@"😎",@"🩷",@"⭐",@"💫",@"😹",@"🤍",@"🤎",@"🪽"];
    });
    NSUInteger k = 2 + arc4random_uniform(4); // 2..5
    NSMutableString *s = [NSMutableString new];
    for (NSUInteger i=0;i<k;i++) [s appendString:emojis[arc4random_uniform((uint32_t)emojis.count)]];
    return s;
}

static NSString *NowMillisStr(void) {
    long long ms = (long long)([[NSDate date] timeIntervalSince1970]*1000.0);
    ms += arc4random_uniform(1000);
    return [NSString stringWithFormat:@"%lld", ms];
}

static void SleepRand(double a, double b) {
    double u = ((double)arc4random() / (double)UINT32_MAX);
    double secs = a + (b - a)*u;
    [NSThread sleepForTimeInterval:secs];
}

#pragma mark - Target parsing

@interface FRTarget : NSObject
@property (nonatomic, copy) NSString *uid28;     // set if invite URL
@property (nonatomic, copy) NSString *username;  // set if username/URL
@end
@implementation FRTarget @end

static FRTarget *ParseTarget(NSString *raw) {
    FRTarget *t = [FRTarget new];
    NSString *s = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length == 0) return nil;
    if (([s containsString:@"locket.camera"] || [s containsString:@"locket.cam"]) &&
        !([s hasPrefix:@"http://"] || [s hasPrefix:@"https://"])) {
        s = [@"https://" stringByAppendingString:s];
    }
    if ([s hasPrefix:@"http://"] || [s hasPrefix:@"https://"]) {
        NSURLComponents *comp = [NSURLComponents componentsWithString:s];
        NSString *host = comp.host.lowercaseString ?: @"";
        NSString *path = comp.path ?: @"";
        if ([host hasSuffix:@"locket.camera"] && [path hasPrefix:@"/invites/"]) {
            NSString *token = [path substringFromIndex:@"/invites/".length];
            NSRange q = [token rangeOfString:@"?"];
            if (q.location != NSNotFound) token = [token substringToIndex:q.location];
            if (token.length < 28) return nil;
            t.uid28 = [token substringToIndex:28];
            return t;
        }
        if ([host hasSuffix:@"locket.cam"] && path.length > 1) {
            NSString *user = [path substringFromIndex:1];
            NSRange slash = [user rangeOfString:@"/"];
            if (slash.location != NSNotFound) user = [user substringToIndex:slash.location];
            t.username = user;
            return t;
        }
        return nil;
    }
    // plain username
    t.username = s;
    return t;
}

#pragma mark - Proxy support

@interface FRProxyConfig : NSObject
@property (nonatomic, copy) NSString *host;
@property (nonatomic) NSNumber *port;
@property (nonatomic, copy) NSString *user;
@property (nonatomic, copy) NSString *pass;
@end
@implementation FRProxyConfig @end

static FRProxyConfig *ParseProxy(NSString *line) {
    NSString *s = [[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (s.length == 0) return nil;
    NSArray *parts = [s componentsSeparatedByString:@":"];
    if (parts.count == 2 || parts.count == 4) {
        FRProxyConfig *pc = [FRProxyConfig new];
        pc.host = parts[0];
        pc.port = @([parts[1] integerValue]);
        if (parts.count == 4) {
            pc.user = parts[2];
            pc.pass = parts[3];
        }
        return pc;
    }
    return nil;
}

#pragma mark - Networking manager

@interface FRNet : NSObject <NSURLSessionDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) FRProxyConfig *proxy;
@property (nonatomic, copy) NSString *appCheckToken;
@property (nonatomic, assign) BOOL running;
@end

@implementation FRNet

+ (instancetype)shared {
    static FRNet *g; static dispatch_once_t once;
    dispatch_once(&once, ^{ g = [FRNet new]; });
    return g;
}

- (void)configureSession {
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    if (self.proxy) {
        NSDictionary *pd = @{
            (NSString *)kCFStreamPropertyHTTPProxyHost : self.proxy.host ?: @"",
            (NSString *)kCFStreamPropertyHTTPProxyPort : self.proxy.port ?: @0,
            (NSString *)kCFStreamPropertyHTTPSProxyHost: self.proxy.host ?: @"",
            (NSString *)kCFStreamPropertyHTTPSProxyPort: self.proxy.port ?: @0,
            (NSString *)kCFNetworkProxiesHTTPEnable   : @1,
            (NSString *)kCFNetworkProxiesHTTPSEnable  : @1
        };
        cfg.connectionProxyDictionary = pd;
    }
    self.session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
}

#pragma mark NSURLSessionDelegate (proxy auth)
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    if (([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodHTTPProxy] ||
         [challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodNTLM]) &&
        self.proxy.user.length && self.proxy.pass.length) {
        NSURLCredential *cred = [NSURLCredential credentialWithUser:self.proxy.user
                                                           password:self.proxy.pass
                                                        persistence:NSURLCredentialPersistenceForSession];
        completionHandler(NSURLSessionAuthChallengeUseCredential, cred);
        return;
    }
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

#pragma mark - Helpers

- (NSDictionary *)syncJSON:(NSURLRequest *)req status:(NSInteger *)outCode error:(NSError **)outErr {
    __block NSData *data = nil;
    __block NSURLResponse *resp = nil;
    __block NSError *err = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req
                                                 completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        data = d; resp = r; err = e; dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
    if (outCode) *outCode = code;
    if (err) { if (outErr) *outErr = err; return nil; }
    if (!data) return nil;
    NSDictionary *json = nil;
    @try { json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]; }
    @catch (__unused id e) {}
    return json;
}

- (NSMutableURLRequest *)jsonRequest:(NSString *)url headers:(NSDictionary *)headers body:(NSDictionary *)body {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.HTTPMethod = @"POST";
    NSMutableDictionary *h = [headers mutableCopy] ?: [NSMutableDictionary new];
    h[@"content-type"] = @"application/json";
    [req setAllHTTPHeaderFields:h];
    if (body) {
        NSData *d = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        req.HTTPBody = d;
    }
    return req;
}

#pragma mark - API headers

- (NSDictionary *)baseLocketHeaders {
    return @{
        @"accept": @"*/*",
        @"baggage": @"sentry-environment=production,sentry-public_key=78fa64317f434fd89d9cc728dd168f50,sentry-release=com.locket.Locket%402.22.0%2B1,sentry-trace_id=672ff5c9498547b3a0370c7ad8f17b04",
        @"x-firebase-appcheck": self.appCheckToken ?: @"",
        @"accept-encoding": @"gzip, deflate, br",
        @"accept-language": @"vi-VN,vi;q=0.9",
        @"sentry-trace": @"672ff5c9498547b3a0370c7ad8f17b04-74139bdb338f45be-0",
        @"user-agent": @"com.locket.Locket/2.22.0 iPhone/16.6.1 hw/iPhone11_2",
        @"firebase-instance-id-token": @"cSykhyjmf0MNj_3g-HCBBC:APA91bH98zDTvlhpnVGXInOxVAmQC0hjSCdDUD48AxKeAqcRESWQq7-qyovZtRcziPoPh5jUHAzWT5EsMG6nvwGYnpQkaYcOmlBt543pxrp0qQH_SvzJAqY"
    };
}

- (NSDictionary *)baseFirebaseHeaders {
    return @{
        @"accept": @"*/*",
        @"baggage": @"sentry-environment=production,sentry-public_key=78fa64317f434fd89d9cc728dd168f50,sentry-release=com.locket.Locket%402.22.0%2B1,sentry-trace_id=672ff5c9498547b3a0370c7ad8f17b04",
        @"x-client-version": @"iOS/FirebaseSDK/10.23.1/FirebaseCore-iOS",
        @"x-firebase-appcheck": self.appCheckToken ?: @"",
        @"x-ios-bundle-identifier": @"com.locket.Locket",
        @"sentry-trace": @"672ff5c9498547b3a0370c7ad8f17b04-74139bdb338f45be-0",
        @"accept-language": @"vi",
        @"accept-encoding": @"gzip, deflate, br",
        @"user-agent": @"FirebaseAuth.iOS/10.23.1 com.locket.Locket/2.22.0 iPhone/16.6.1 hw/iPhone11_2",
        @"x-firebase-gmpid": @"1:641029076083:ios:cc8eb46290d69b234fa606"
    };
}

#pragma mark - API calls (sync)

- (NSString *)fetchAppCheckToken {
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://chillysilly.frfrnocap.men/lcapi.php"]];
    NSInteger code=0; NSError *err=nil;
    NSDictionary *j = [self syncJSON:req status:&code error:&err];
    if (!j) { NSLog(@"[FR] AppCheck error %@ code %ld", err, (long)code); return nil; }
    return j[@"token"];
}

- (NSString *)createAccountEmail:(NSString *)email password:(NSString *)pass {
    NSString *url = @"https://api.locketcamera.com/createAccountWithEmailPassword";
    NSMutableDictionary *headers = [[self baseLocketHeaders] mutableCopy];
    NSDictionary *payload = @{
        @"data": @{
            @"email": email,
            @"client_token": @"27a286f7b6d72b83a3665fe30a1daa78d0b08b04",
            @"password": pass,
            @"client_email_verif": @YES,
            @"analytics": @{
                    @"ios_version": @"2.22.0.1",
                    @"experiments": @{
                        @"flag_18": @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value":@"1203"},
                        @"flag_7":  @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value":@"800"},
                        @"flag_10": @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value":@"505"},
                        @"flag_15": @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value":@"501"},
                        @"flag_6":  @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value":@"2000"},
                        @"flag_23": @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value":@"500"},
                        @"flag_14": @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value":@"502"},
                        @"flag_25": @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value":@"76"},
                        @"flag_4":  @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value":@"43"},
                        @"flag_9":  @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value":@"11"},
                        @"flag_3":  @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value":@"600"},
                        @"flag_16": @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value":@"303"},
                        @"flag_22": @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value":@"1203"},
                        @"flag_8":  @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value":@"500"}
                    },
                    @"amplitude": @{
                        @"device_id": @"391C19B6-8B49-4CDD-9DB0-7249ACCB8A28",
                        @"session_id": @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value", @"value": NowMillisStr()}
                    },
                    @"google_analytics": @{@"app_instance_id": @"FFB0AAA7EDC047E899B2E116D1BEDACD"},
                    @"platform": @"ios"
            },
            @"platform": @"ios"
        }
    };
    NSMutableURLRequest *req = [self jsonRequest:url headers:headers body:payload];
    NSInteger code=0; NSError *err=nil;
    NSDictionary *j = [self syncJSON:req status:&code error:&err];
    if (!j) { NSLog(@"[FR] createAccount err %@ code %ld", err, (long)code); return nil; }
    return j[@"result"][@"token"]; // custom token
}

- (NSString *)verifyCustomToken:(NSString *)customToken {
    NSString *url = @"https://www.googleapis.com/identitytoolkit/v3/relyingparty/verifyCustomToken?key=AIzaSyCQngaaXQIfJaH0aS2l7REgIjD7nL431So";
    NSDictionary *payload = @{@"token": customToken, @"returnSecureToken": @YES};
    NSMutableURLRequest *req = [self jsonRequest:url headers:[self baseFirebaseHeaders] body:payload];
    NSInteger code=0; NSError *err=nil;
    NSDictionary *j = [self syncJSON:req status:&code error:&err];
    if (!j) { NSLog(@"[FR] verifyCustomToken err %@ code %ld", err, (long)code); return nil; }
    return j[@"idToken"];
}

- (BOOL)sendVerifyEmail:(NSString *)idToken {
    NSString *url = @"https://www.googleapis.com/identitytoolkit/v3/relyingparty/getOobConfirmationCode?key=AIzaSyCQngaaXQIfJaH0aS2l7REgIjD7nL431So";
    NSDictionary *payload = @{@"idToken": idToken, @"requestType": @"VERIFY_EMAIL", @"clientType": @"CLIENT_TYPE_IOS"};
    NSMutableURLRequest *req = [self jsonRequest:url headers:[self baseFirebaseHeaders] body:payload];
    NSInteger code=0; NSError *err=nil;
    NSDictionary *j = [self syncJSON:req status:&code error:&err];
    if (!j) { NSLog(@"[FR] getOOB err %@ code %ld", err, (long)code); return NO; }
    return YES;
}

- (BOOL)finalizeTempUser:(NSString *)idToken username:(NSString *)username first:(NSString *)first last:(NSString *)last {
    NSString *url = @"https://api.locketcamera.com/finalizeTemporaryUser";
    NSMutableDictionary *h = [[self baseLocketHeaders] mutableCopy];
    h[@"authorization"] = [@"Bearer " stringByAppendingString:(idToken ?: @"")];
    NSDictionary *payload = @{
        @"data": @{
            @"analytics": @{
                @"ios_version": @"2.22.0.1",
                @"amplitude": @{@"device_id": @"391C19B6-8B49-4CDD-9DB0-7249ACCB8A28",
                                @"session_id": @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value": NowMillisStr()}},
                @"experiments": @{@"flag_18": @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value":@"1203"}},
                @"google_analytics": @{@"app_instance_id": @"FFB0AAA7EDC047E899B2E116D1BEDACD"},
                @"platform": @"ios"
            },
            @"username": username,
            @"last_name": last,
            @"require_username": @YES,
            @"first_name": first
        }
    };
    NSMutableURLRequest *req = [self jsonRequest:url headers:h body:payload];
    NSInteger code=0; NSError *err=nil;
    NSDictionary *j = [self syncJSON:req status:&code error:&err];
    if (!j) { NSLog(@"[FR] finalize err %@ code %ld", err, (long)code); return NO; }
    return YES;
}

- (BOOL)setAccountInfo:(NSString *)idToken displayName:(NSString *)name {
    NSString *url = @"https://www.googleapis.com/identitytoolkit/v3/relyingparty/setAccountInfo?key=AIzaSyCQngaaXQIfJaH0aS2l7REgIjD7nL431So";
    NSDictionary *payload = @{@"idToken": idToken, @"returnSecureToken": @YES, @"displayName": name ?: @""};
    NSMutableURLRequest *req = [self jsonRequest:url headers:[self baseFirebaseHeaders] body:payload];
    NSInteger code=0; NSError *err=nil;
    NSDictionary *j = [self syncJSON:req status:&code error:&err];
    if (!j) { NSLog(@"[FR] setAccountInfo err %@ code %ld", err, (long)code); return NO; }
    return YES;
}

- (NSString *)getUIDByUsername:(NSString *)idToken username:(NSString *)username {
    NSString *url = @"https://api.locketcamera.com/getUserByUsername";
    NSMutableDictionary *h = [[self baseLocketHeaders] mutableCopy];
    h[@"authorization"] = [@"Bearer " stringByAppendingString:(idToken ?: @"")];
    NSDictionary *payload = @{@"data": @{@"username": username ?: @"",
                                         @"analytics": @{@"ios_version": @"2.22.0.1"}}};
    NSMutableURLRequest *req = [self jsonRequest:url headers:h body:payload];
    NSInteger code=0; NSError *err=nil;
    NSDictionary *j = [self syncJSON:req status:&code error:&err];
    if (!j) { NSLog(@"[FR] getUserByUsername err %@ code %ld", err, (long)code); return nil; }
    return j[@"result"][@"data"][@"uid"];
}

- (BOOL)sendFriendRequest:(NSString *)idToken targetUID:(NSString *)uid {
    NSString *url = @"https://api.locketcamera.com/sendFriendRequest";
    NSMutableDictionary *h = [[self baseLocketHeaders] mutableCopy];
    h[@"authorization"] = [@"Bearer " stringByAppendingString:(idToken ?: @"")];
    NSDictionary *payload = @{
        @"data": @{
            @"source": @"navStandard",
            @"user_uid": uid ?: @"",
            @"platform": @"iOS",
            @"messenger": @"Messages",
            @"analytics": @{@"ios_version": @"2.22.0.1",
                            @"amplitude": @{@"device_id": @"391C19B6-8B49-4CDD-9DB0-7249ACCB8A28",
                                            @"session_id": @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value",@"value": NowMillisStr()}}},
            @"share_history_eligible": @YES,
            @"create_ofr_for_temp_users": @NO,
            @"get_reengagement_status": @NO,
            @"prompted_reengagement": @NO,
            @"invite_variant": @{@"@type":@"type.googleapis.com/google.protobuf.Int64Value", @"value": @"1002"},
            @"rollcall": @NO
        }
    };
    NSMutableURLRequest *req = [self jsonRequest:url headers:h body:payload];
    NSInteger code=0; NSError *err=nil;
    NSDictionary *j = [self syncJSON:req status:&code error:&err];
    if (!j) { NSLog(@"[FR] sendFriendRequest err %@ code %ld", err, (long)code); return NO; }
    return YES;
}

#pragma mark - One full cycle

- (BOOL)runOneCycleWithFirstName:(NSString *)first target:(FRTarget *)target delayMin:(double)delayMin delayMax:(double)delayMax {
    if (!self.running) return NO;

    // Build identity
    NSString *email = RandomEmail();
    NSString *password = @"haidanh912"; // adjust if needed
    NSString *username = RandomUsername11();
    NSString *last = RandomEmojiLastName();
    NSString *displayName = [NSString stringWithFormat:@"%@ %@", first.length?first:@"Hai", last];

    NSLog(@"[FR] Creating acct email=%@ username=%@ display=%@", email, username, displayName);

    // Create → verify → (optional) OOB → finalize → set name
    NSString *custom = [self createAccountEmail:email password:password];
    if (!custom) return NO;

    NSString *idToken = [self verifyCustomToken:custom];
    if (!idToken) return NO;

    [self sendVerifyEmail:idToken]; // non-fatal if fails

    if (![self finalizeTempUser:idToken username:username first:(first.length?first:@"Hai") last:last]) return NO;
    [self setAccountInfo:idToken displayName:displayName];

    // Resolve target uid if needed
    NSString *uid = target.uid28;
    if (!uid && target.username.length) {
        uid = [self getUIDByUsername:idToken username:target.username];
    }
    if (!uid) { NSLog(@"[FR] No UID resolved."); return NO; }

    // SEND INSTANTLY after account creation
    BOOL ok = [self sendFriendRequest:idToken targetUID:uid];
    NSLog(@"[FR] Friend request %@", ok?@"✅ SENT":@"❌ FAILED");

    // Delay for a few seconds (range)
    double a = MAX(0.0, delayMin);
    double b = MAX(a, delayMax);
    SleepRand(a, b);
    return ok;
}

@end

#pragma mark - UI Controller

@interface FRUI : NSObject
@property (nonatomic, strong) UIButton *floating;
@property (nonatomic, weak) UIAlertController *panel;
@property (nonatomic, assign) BOOL panelShown;
@end

@implementation FRUI

+ (instancetype)shared {
    static FRUI *g; static dispatch_once_t once;
    dispatch_once(&once, ^{ g = [FRUI new]; });
    return g;
}

- (void)installFloatingButton {
    if (self.floating) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *win = UIApplication.sharedApplication.keyWindow ?: UIApplication.sharedApplication.windows.firstObject;
        if (!win) return;
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(win.bounds.size.width-70, win.bounds.size.height-150, 56, 56);
        btn.layer.cornerRadius = 28;
        btn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        [btn setTitle:@"FR" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        btn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
        [btn addTarget:self action:@selector(showPanel) forControlEvents:UIControlEventTouchUpInside];
        [win addSubview:btn];
        self.floating = btn;
    });
}

- (void)showPanel {
    if (self.panelShown) return;
    self.panelShown = YES;

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Friend Request Runner"
                                                                message:@"Enter target, proxy (optional), count & delay"
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextField:^(UITextField *tf){ tf.placeholder = @"Target (invite URL / username URL / username)"; }];
    [ac addTextField:^(UITextField *tf){ tf.placeholder = @"First name (default: Hai)"; }];
    [ac addTextField:^(UITextField *tf){ tf.placeholder = @"Proxy (optional: ip:port or ip:port:user:pass)"; tf.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
    [ac addTextField:^(UITextField *tf){ tf.placeholder = @"Count (e.g. 10 or inf)"; tf.keyboardType = UIKeyboardTypeDefault; }];
    [ac addTextField:^(UITextField *tf){ tf.placeholder = @"Delay seconds (e.g. 2 or 1-3)"; tf.keyboardType = UIKeyboardTypeDecimalPad; }];

    __weak typeof(self) weakSelf = self;

    UIAlertAction *run = [UIAlertAction actionWithTitle:@"Run" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
        __strong typeof(self) self = weakSelf;
        NSArray<UITextField *> *tfs = ac.textFields;
        NSString *targetStr = tfs[0].text ?: @"";
        NSString *firstName = tfs[1].text ?: @"";
        NSString *proxyStr  = tfs[2].text ?: @"";
        NSString *countStr  = tfs[3].text ?: @"";
        NSString *delayStr  = tfs[4].text ?: @"";

        FRTarget *target = ParseTarget(targetStr);
        if (!target) { NSLog(@"[FR] Invalid target input"); return; }

        // Parse count
        NSInteger count = 0; // 0=forever
        if (countStr.length) {
            NSString *lc = countStr.lowercaseString;
            if ([lc isEqualToString:@"inf"] || [lc isEqualToString:@"infinite"]) {
                count = 0;
            } else {
                count = MAX(1, [countStr integerValue]);
            }
        }

        // Parse delay
        double dmin = 1.0, dmax = 2.0;
        if (delayStr.length) {
            NSRange dash = [delayStr rangeOfString:@"-"];
            if (dash.location != NSNotFound) {
                double a = [[delayStr substringToIndex:dash.location] doubleValue];
                double b = [[delayStr substringFromIndex:dash.location+1] doubleValue];
                if (a > 0 && b >= a) { dmin = a; dmax = b; }
            } else {
                double d = [delayStr doubleValue];
                if (d > 0) { dmin = dmax = d; }
            }
        }

        // Proxy
        FRProxyConfig *proxy = proxyStr.length ? ParseProxy(proxyStr) : nil;

        // Start run
        FRNet *net = [FRNet shared];
        net.proxy = proxy;
        [net configureSession];
        net.appCheckToken = [net fetchAppCheckToken];
        if (!net.appCheckToken.length) { NSLog(@"[FR] No AppCheck token"); return; }
        net.running = YES;

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSInteger i = 0;
            while (net.running && (count == 0 || i < count)) {
                @autoreleasepool {
                    NSString *first = firstName.length ? firstName : @"Hai";
                    BOOL ok = [net runOneCycleWithFirstName:first target:target delayMin:dmin delayMax:dmax];
                    NSLog(@"[FR] Cycle %ld %@", (long)(i+1), ok?@"OK":@"FAIL");
                    i++;
                }
            }
            NSLog(@"[FR] Runner stopped.");
        });
    }];

    UIAlertAction *stop = [UIAlertAction actionWithTitle:@"Stop" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){
        [FRNet shared].running = NO;
        // Best-effort cancel any in-flight tasks
        [[FRNet shared].session invalidateAndCancel];
        NSLog(@"[FR] Stop requested.");
    }];

    UIAlertAction *close = [UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *a){
        self.panelShown = NO;
    }];

    [ac addAction:run];
    [ac addAction:stop];
    [ac addAction:close];

    UIViewController *root = UIApplication.sharedApplication.keyWindow.rootViewController ?: UIApplication.sharedApplication.windows.firstObject.rootViewController;
    [root presentViewController:ac animated:YES completion:nil];
    self.panel = ac;
}

@end

#pragma mark - Hook

%hook UIApplication
- (void)setDelegate:(id)delegate {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[FRUI shared] installFloatingButton];
    });
}
%end
