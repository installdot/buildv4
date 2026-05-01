#import <UIKit/UIKit.h>

static NSMutableString *globalLog;

#pragma mark - SSL BYPASS

// NSURLSession SSL bypass
%hook NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {

    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSURLCredential *cred = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, cred);
        return;
    }

    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

%end


// NSURLConnection SSL bypass (older apps)
%hook NSURLConnection

+ (BOOL)canHandleRequest:(NSURLRequest *)request {
    return %orig;
}

- (void)connection:(NSURLConnection *)connection
willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {

    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSURLCredential *cred = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        [[challenge sender] useCredential:cred forAuthenticationChallenge:challenge];
    } else {
        [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
    }
}

%end


#pragma mark - NETWORK LOG

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (!globalLog) globalLog = [NSMutableString new];

    NSString *body = @"";
    if (request.HTTPBody) {
        body = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding] ?: @"<binary>";
    }

    [globalLog appendFormat:
     @"\n==== REQUEST ====\nURL: %@\nHeaders: %@\nBody: %@\n",
     request.URL,
     request.allHTTPHeaderFields,
     body];

    return %orig(request, ^(NSData *data, NSURLResponse *res, NSError *err) {

        NSString *resp = @"";
        if (data) {
            resp = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"<binary>";
        }

        [globalLog appendFormat:
         @"\n==== RESPONSE ====\n%@\n",
         resp];

        completionHandler(data, res, err);
    });
}

%end


#pragma mark - UI BUTTON

@interface CopyButton : UIButton
@end

@implementation CopyButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(100, 200, 70, 70)];
    if (self) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        self.layer.cornerRadius = 35;

        [self setTitle:@"COPY" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:12];

        [self addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)copyLog {
    if (!globalLog || globalLog.length == 0) return;

    [UIPasteboard generalPasteboard].string = globalLog;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Copied"
                                                                   message:@"Network logs copied"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    [root presentViewController:alert animated:YES completion:nil];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:nil];
    });
}

- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}

@end


#pragma mark - INJECT UI

%hook UIApplication

- (void)didFinishLaunching {
    %orig;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *win = [UIApplication sharedApplication].keyWindow;
        if (!win) return;

        CopyButton *btn = [[CopyButton alloc] init];
        [win addSubview:btn];
    });
}

%end
