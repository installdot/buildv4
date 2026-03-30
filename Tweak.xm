#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static NSMutableArray *logs;

// ─────────────────────────────────────────
// Logger
// ─────────────────────────────────────────
static void AddLog(NSString *tag, NSString *body) {
    @try {
        if (!logs) logs = [NSMutableArray new];
        NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                     dateStyle:NSDateFormatterNoStyle
                                                     timeStyle:NSDateFormatterMediumStyle];
        [logs addObject:[NSString stringWithFormat:
                         @"[%@] %@\n%@\n────────────────────────────",
                         ts, tag, body]];
    } @catch (...) {}
}

static NSString *DataToHuman(NSData *data) {
    if (!data || data.length == 0) return @"<empty>";
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return s ?: [NSString stringWithFormat:@"<binary %lu bytes>", (unsigned long)data.length];
}

// ─────────────────────────────────────────
// Layer 1: NSURLSession — data task
// ─────────────────────────────────────────
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    NSURLRequest *captured = request; // retain for block

    AddLog(@"REQUEST", [NSString stringWithFormat:
        @"URL    : %@\nMethod : %@\nHeaders: %@\nBody   : %@",
        captured.URL.absoluteString,
        captured.HTTPMethod,
        captured.allHTTPHeaderFields,
        captured.HTTPBody ? DataToHuman(captured.HTTPBody) : @"<none>"
    ]);

    void (^wrapped)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *resp, NSError *err) {
            @try {
                NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
                AddLog(@"RESPONSE", [NSString stringWithFormat:
                    @"URL    : %@\nStatus : %ld\nHeaders: %@\nBody   : %@",
                    captured.URL.absoluteString,
                    (long)http.statusCode,
                    http.allHeaderFields,
                    DataToHuman(data)
                ]);
            } @catch (...) {}
            if (completionHandler) completionHandler(data, resp, err);
        };

    return %orig(request, wrapped);
}

// ─────────────────────────────────────────
// Layer 1b: NSURLSession — upload task
// ─────────────────────────────────────────
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData
                                completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    AddLog(@"UPLOAD", [NSString stringWithFormat:
        @"URL    : %@\nHeaders: %@\nBody   : %@",
        request.URL.absoluteString,
        request.allHTTPHeaderFields,
        DataToHuman(bodyData)
    ]);
    return %orig(request, bodyData, completionHandler);
}

// ─────────────────────────────────────────
// Layer 1c: NSURLSession — resume data task (no completion block variant)
// ─────────────────────────────────────────
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    AddLog(@"REQUEST (no-block)", [NSString stringWithFormat:
        @"URL    : %@\nMethod : %@\nHeaders: %@",
        request.URL.absoluteString,
        request.HTTPMethod,
        request.allHTTPHeaderFields
    ]);
    return %orig(request);
}

%end

// ─────────────────────────────────────────
// Layer 2: NSURLConnection (legacy)
// ─────────────────────────────────────────
%hook NSURLConnection

- (id)initWithRequest:(NSURLRequest *)request
             delegate:(id)delegate
     startImmediately:(BOOL)start {
    AddLog(@"NSURLConnection", [NSString stringWithFormat:
        @"URL    : %@\nMethod : %@\nHeaders: %@\nBody   : %@",
        request.URL.absoluteString,
        request.HTTPMethod,
        request.allHTTPHeaderFields,
        request.HTTPBody ? DataToHuman(request.HTTPBody) : @"<none>"
    ]);
    return %orig(request, delegate, start);
}

+ (void)sendAsynchronousRequest:(NSURLRequest *)request
                          queue:(NSOperationQueue *)queue
              completionHandler:(void (^)(NSURLResponse *, NSData *, NSError *))handler {
    AddLog(@"NSURLConnection async", [NSString stringWithFormat:
        @"URL    : %@\nMethod : %@",
        request.URL.absoluteString,
        request.HTTPMethod
    ]);
    %orig(request, queue, handler);
}

%end

// ─────────────────────────────────────────
// Layer 3: NSURLProtocol — catches everything
// including proxy-bypass sessions
// ─────────────────────────────────────────
@interface CaptureProtocol : NSURLProtocol <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *innerSession;
@property (nonatomic, strong) NSURLSessionDataTask *innerTask;
@property (nonatomic, strong) NSMutableData *responseData;
@end

@implementation CaptureProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    // Avoid infinite loop — only intercept untagged requests
    if ([NSURLProtocol propertyForKey:@"CaptureProtocolHandled" inRequest:request]) {
        return NO;
    }
    NSString *scheme = request.URL.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSMutableURLRequest *tagged = self.request.mutableCopy;
    [NSURLProtocol setProperty:@YES forKey:@"CaptureProtocolHandled" inRequest:tagged];

    AddLog(@"NSURLProtocol REQUEST", [NSString stringWithFormat:
        @"URL    : %@\nMethod : %@\nHeaders: %@\nBody   : %@",
        tagged.URL.absoluteString,
        tagged.HTTPMethod,
        tagged.allHTTPHeaderFields,
        tagged.HTTPBody ? DataToHuman(tagged.HTTPBody) : @"<none>"
    ]);

    self.responseData = [NSMutableData new];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    self.innerSession = [NSURLSession sessionWithConfiguration:cfg
                                                      delegate:self
                                                 delegateQueue:nil];
    self.innerTask = [self.innerSession dataTaskWithRequest:tagged];
    [self.innerTask resume];
}

- (void)stopLoading {
    [self.innerTask cancel];
    [self.innerSession invalidateAndCancel];
}

// delegate
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    [self.client URLProtocol:self didReceiveResponse:response
          cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    [self.responseData appendData:data];
    [self.client URLProtocol:self didLoadData:data];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (error) {
        [self.client URLProtocol:self didFailWithError:error];
    } else {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)task.response;
        AddLog(@"NSURLProtocol RESPONSE", [NSString stringWithFormat:
            @"URL    : %@\nStatus : %ld\nHeaders: %@\nBody   : %@",
            self.request.URL.absoluteString,
            (long)http.statusCode,
            http.allHeaderFields,
            DataToHuman(self.responseData)
        ]);
        [self.client URLProtocolDidFinishLoading:self];
    }
}

@end

// ─────────────────────────────────────────
// Floating button
// ─────────────────────────────────────────
@interface FloatingButton : UIButton
@end

@implementation FloatingButton

- (void)handleTap {
    NSString *all = logs.count
        ? [logs componentsJoinedByString:@"\n"]
        : @"No logs yet.";
    [UIPasteboard generalPasteboard].string = all;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:[NSString stringWithFormat:
                                      @"📡 %lu captured", (unsigned long)logs.count]
                             message:@"Copied to clipboard"
                      preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:@"Clear"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *a) {
            [logs removeAllObjects];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];

        UIWindow *w = [UIApplication sharedApplication].windows.firstObject;
        [w.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}

@end

@interface PassthroughWindow : UIWindow
@end

@implementation PassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self.rootViewController.view || hit == self) ? nil : hit;
}
@end

@interface PassthroughVC : UIViewController
@end
@implementation PassthroughVC
@end

static PassthroughWindow *overlayWindow;

static void AddFloatingButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (overlayWindow) return;

        overlayWindow = [[PassthroughWindow alloc]
                         initWithFrame:[UIScreen mainScreen].bounds];
        overlayWindow.windowLevel     = UIWindowLevelAlert + 100;
        overlayWindow.backgroundColor = UIColor.clearColor;
        overlayWindow.userInteractionEnabled = YES;
        overlayWindow.hidden = NO;

        PassthroughVC *vc = [PassthroughVC new];
        vc.view.backgroundColor = UIColor.clearColor;
        overlayWindow.rootViewController = vc;

        FloatingButton *btn = [FloatingButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, 200, 120, 44);
        btn.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.85];
        [btn setTitle:@"📡 Logs" forState:UIControlStateNormal];
        [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        btn.layer.cornerRadius = 12;
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];

        [btn addTarget:btn
                action:@selector(handleTap)
      forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
                                       initWithTarget:btn action:@selector(handlePan:)];
        [btn addGestureRecognizer:pan];
        [vc.view addSubview:btn];
    });
}

// ─────────────────────────────────────────
// App launch hook
// ─────────────────────────────────────────
%hook UIApplication

- (BOOL)application:(UIApplication *)app
didFinishLaunchingWithOptions:(NSDictionary *)opts {
    BOOL r = %orig(app, opts);

    // Register NSURLProtocol — catches all HTTP/HTTPS including proxy-bypass sessions
    [NSURLProtocol registerClass:[CaptureProtocol class]];

    AddFloatingButton();
    return r;
}

%end

// ─────────────────────────────────────────
// Constructor — minimal, no MSHookFunction
// ─────────────────────────────────────────
__attribute__((constructor(101))) static void init_hook(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        AddFloatingButton();
    });
}
