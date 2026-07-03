#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <substrate.h>

// ─────────────────────────────────────────
// Logger
// ─────────────────────────────────────────
static NSMutableArray *logs;
static dispatch_queue_t logQueue;

static void EnsureLogger(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        logs     = [NSMutableArray new];
        logQueue = dispatch_queue_create("net.sniffer.log", DISPATCH_QUEUE_SERIAL);
    });
}

static void AddLog(NSString *log) {
    EnsureLogger();
    NSString *ts    = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                     dateStyle:NSDateFormatterNoStyle
                                                     timeStyle:NSDateFormatterMediumStyle];
    NSString *entry = [NSString stringWithFormat:
                       @"\n====================\n[%@] %@\n====================\n", ts, log];
    dispatch_async(logQueue, ^{
        [logs addObject:entry];
    });
    NSLog(@"%@", entry);
}

static NSString *DataToHexPreview(NSData *data, NSUInteger maxBytes) {
    if (!data || data.length == 0) return @"<empty>";
    NSUInteger len     = MIN(data.length, maxBytes);
    const uint8_t *buf = (const uint8_t *)data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:len * 3];
    for (NSUInteger i = 0; i < len; i++) {
        [hex appendFormat:@"%02x ", buf[i]];
    }
    if (data.length > maxBytes) {
        [hex appendFormat:@"... (%lu bytes total)", (unsigned long)data.length];
    }
    return hex;
}

static NSString *DataToString(NSData *data) {
    if (!data || data.length == 0) return @"<empty>";
    // Try UTF-8 first, fall back to hex preview
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return str ?: [NSString stringWithFormat:@"<binary> hex: %@",
                   DataToHexPreview(data, 64)];
}

// ─────────────────────────────────────────
// Copy to clipboard / export
// ─────────────────────────────────────────
static void CopyLogsToClipboard(void) {
    __block NSString *all;
    dispatch_sync(logQueue, ^{
        all = [logs componentsJoinedByString:@"\n"];
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIPasteboard generalPasteboard].string = all;
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Export"
                                                message:[NSString stringWithFormat:
                                                         @"Copied %lu entries to clipboard",
                                                         (unsigned long)logs.count]
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        UIWindow *w = [UIApplication sharedApplication].windows.firstObject;
        [w.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

// ─────────────────────────────────────────
// Floating button + overlay window
// ─────────────────────────────────────────
@interface FloatingButton : UIButton
@end
@implementation FloatingButton
- (void)handleTap              { CopyLogsToClipboard(); }
- (void)handlePan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}
@end

@interface PassthroughWindow     : UIWindow     @end
@interface PassthroughViewController : UIViewController @end
@implementation PassthroughWindow
- (UIView *)hitTest:(CGPoint)pt withEvent:(UIEvent *)e {
    UIView *hit = [super hitTest:pt withEvent:e];
    if (hit == self.rootViewController.view || hit == self) return nil;
    return hit;
}
@end
@implementation PassthroughViewController @end

static PassthroughWindow *overlayWindow = nil;

static void AddFloatingButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (overlayWindow) return;
        overlayWindow = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        overlayWindow.windowLevel         = UIWindowLevelAlert + 100;
        overlayWindow.backgroundColor     = [UIColor clearColor];
        overlayWindow.userInteractionEnabled = YES;
        overlayWindow.hidden              = NO;

        PassthroughViewController *vc     = [PassthroughViewController new];
        vc.view.backgroundColor           = [UIColor clearColor];
        overlayWindow.rootViewController  = vc;

        FloatingButton *btn = [FloatingButton buttonWithType:UIButtonTypeSystem];
        btn.frame           = CGRectMake(40, 200, 130, 50);
        btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
        [btn setTitle:@"Copy Logs" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.layer.cornerRadius = 10;
        [btn addTarget:btn action:@selector(handleTap)
      forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan =
            [[UIPanGestureRecognizer alloc] initWithTarget:btn action:@selector(handlePan:)];
        [btn addGestureRecognizer:pan];
        [vc.view addSubview:btn];
    });
}

// ─────────────────────────────────────────
// LAYER 1 — NSURLSession (HTTPS capture)
// ─────────────────────────────────────────
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {

    // Filter to capture ONLY HTTPS traffic
    BOOL isHTTPS = [request.URL.scheme.lowercaseString isEqualToString:@"https"];

    if (isHTTPS) {
        AddLog([NSString stringWithFormat:
                @"[HTTPS·REQUEST]\nURL:     %@\nMethod:  %@\nHeaders: %@\nBody:    %@",
                request.URL.absoluteString,
                request.HTTPMethod,
                request.allHTTPHeaderFields,
                DataToString(request.HTTPBody)]);
    }

    void (^wrapped)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (isHTTPS) {
                NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
                AddLog([NSString stringWithFormat:
                        @"[HTTPS·RESPONSE]\nURL:     %@\nStatus:  %ld\nHeaders: %@\nBody:    %@",
                        request.URL.absoluteString,
                        (long)http.statusCode,
                        http.allHeaderFields,
                        DataToString(data)]);
            }
            if (handler) handler(data, resp, err);
        };
    return %orig(request, wrapped);
}

%end

// ─────────────────────────────────────────
// App lifecycle hooks
// ─────────────────────────────────────────
%hook UIApplication

- (BOOL)application:(UIApplication *)app
didFinishLaunchingWithOptions:(NSDictionary *)opts {
    BOOL result = %orig(app, opts);
    AddFloatingButton();
    return result;
}

%end

// Fallback in case the app doesn't trigger didFinishLaunchingWithOptions standardly
__attribute__((constructor)) static void init_ui(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        AddFloatingButton();
    });
}
