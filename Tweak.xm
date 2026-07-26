#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static NSMutableArray *logs;

// ─────────────────────────────────────────
// Logger
// ─────────────────────────────────────────
static void AddLog(NSString *log) {
    if (!logs) logs = [NSMutableArray new];

    NSString *entry = [NSString stringWithFormat:
                       @"\n====================\n%@\n====================\n", log];
    [logs addObject:entry];
    NSLog(@"%@", entry);
}

static NSString *DataToString(NSData *data) {
    if (!data) return @"<empty>";
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return str ?: [NSString stringWithFormat:@"<%lu bytes>", (unsigned long)data.length];
}

// ─────────────────────────────────────────
// Copy to clipboard
// ─────────────────────────────────────────
static void CopyLogsToClipboard() {
    NSString *all = [logs componentsJoinedByString:@"\n"];
    [UIPasteboard generalPasteboard].string = all;

    NSLog(@"[EXPORT] Copied logs to clipboard");

    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
                                    alertControllerWithTitle:@"Export"
                                    message:@"Logs copied to clipboard"
                                    preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];

        UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
        if (keyWindow.rootViewController) {
            [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
        }
    });
}

// ─────────────────────────────────────────
// Floating button
// ─────────────────────────────────────────
@interface FloatingButton : UIButton
@end

@implementation FloatingButton

- (void)handleTap {
    CopyLogsToClipboard();
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x,
                              self.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.superview];
}

@end

// ─────────────────────────────────────────
// Overlay window (always on top, passthrough)
// ─────────────────────────────────────────

// Only intercept touches that actually land on the button.
// Everything else returns nil so UIKit passes the touch to the app window below.
@interface PassthroughWindow : UIWindow
@end

@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // If the hit view is our own background, ignore it and let the app handle it
    if (hit == self.rootViewController.view || hit == self) {
        return nil;
    }
    return hit;
}

@end

@interface PassthroughViewController : UIViewController
@end

@implementation PassthroughViewController
@end

static PassthroughWindow *overlayWindow = nil;

// ─────────────────────────────────────────
// Add floating button
// ─────────────────────────────────────────
static void AddFloatingButton() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (overlayWindow) return;

        // Dedicated window so the app can never draw over the button
        overlayWindow = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        overlayWindow.windowLevel = UIWindowLevelAlert + 100;
        overlayWindow.backgroundColor = [UIColor clearColor];
        overlayWindow.userInteractionEnabled = YES;
        overlayWindow.hidden = NO;

        PassthroughViewController *vc = [PassthroughViewController new];
        vc.view.backgroundColor = [UIColor clearColor];
        overlayWindow.rootViewController = vc;

        FloatingButton *btn = [FloatingButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(40, 200, 120, 50);
        btn.tag = 9999;
        btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        [btn setTitle:@"Copy Logs" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.layer.cornerRadius = 10;

        [btn addTarget:btn action:@selector(handleTap) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:btn action:@selector(handlePan:)];
        [btn addGestureRecognizer:pan];

        [vc.view addSubview:btn];
    });
}

// ─────────────────────────────────────────
// Hook NSURLSession
// ─────────────────────────────────────────
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    NSString *reqLog = [NSString stringWithFormat:
                        @"[REQUEST]\nURL: %@\nMethod: %@\nHeaders: %@\nBody: %@",
                        request.URL.absoluteString,
                        request.HTTPMethod,
                        request.allHTTPHeaderFields,
                        DataToString(request.HTTPBody)];

    AddLog(reqLog);

    // Block must be declared as a variable — Logos cannot parse a literal block inside %orig(...)
    void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {

            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;

            NSString *respLog = [NSString stringWithFormat:
                                 @"[RESPONSE]\nURL: %@\nStatus: %ld\nHeaders: %@\nBody: %@",
                                 request.URL.absoluteString,
                                 (long)http.statusCode,
                                 http.allHeaderFields,
                                 DataToString(data)];

            AddLog(respLog);

            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };

    return %orig(request, wrappedHandler);
}

%end

// ─────────────────────────────────────────
// Add floating button on app launch
// ─────────────────────────────────────────
%hook UIApplication

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig(application, launchOptions);
    AddFloatingButton();
    return result;
}

%end

// ─────────────────────────────────────────
// Constructor fallback
// ─────────────────────────────────────────
__attribute__((constructor(101))) static void init_hook(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        AddFloatingButton();
    });
}
