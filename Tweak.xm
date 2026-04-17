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
// Shared: present alert from key window
// ─────────────────────────────────────────
static void PresentAlert(UIAlertController *alert) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
        if (keyWindow.rootViewController) {
            [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
        }
    });
}

// ─────────────────────────────────────────
// Copy to clipboard
// ─────────────────────────────────────────
static void CopyLogsToClipboard() {
    NSString *all = [logs componentsJoinedByString:@"\n"];
    [UIPasteboard generalPasteboard].string = all;

    NSLog(@"[EXPORT] Copied logs to clipboard");

    UIAlertController *alert = [UIAlertController
                                alertControllerWithTitle:@"Export"
                                message:@"Logs copied to clipboard"
                                preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    PresentAlert(alert);
}

// ─────────────────────────────────────────
// Save logs to Documents directory
// ─────────────────────────────────────────
static void SaveLogsToFile() {
    NSString *all = [logs componentsJoinedByString:@"\n"];
    NSData *data = [all dataUsingEncoding:NSUTF8StringEncoding];

    // Build a timestamped filename: logs_YYYYMMDD_HHmmss.txt
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"yyyyMMdd_HHmmss";
    NSString *timestamp = [fmt stringFromDate:[NSDate date]];
    NSString *filename = [NSString stringWithFormat:@"logs_%@.txt", timestamp];

    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *filePath = [docsDir stringByAppendingPathComponent:filename];

    NSError *error = nil;
    BOOL success = [data writeToFile:filePath options:NSDataWritingAtomic error:&error];

    NSLog(@"[EXPORT] Save to file: %@ — success: %d", filePath, success);

    NSString *message = success
        ? [NSString stringWithFormat:@"Saved to:\n%@", filePath]
        : [NSString stringWithFormat:@"Failed to save:\n%@", error.localizedDescription];

    UIAlertController *alert = [UIAlertController
                                alertControllerWithTitle:success ? @"Saved" : @"Error"
                                message:message
                                preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    PresentAlert(alert);
}

// ─────────────────────────────────────────
// Floating button
// ─────────────────────────────────────────
@interface FloatingButton : UIButton
@end

@implementation FloatingButton

- (void)handleTap {
    // Present an action sheet so the user can pick export method
    UIAlertController *sheet = [UIAlertController
                                alertControllerWithTitle:@"Export Logs"
                                message:nil
                                preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy to Clipboard"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        CopyLogsToClipboard();
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Save to Documents"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        SaveLogsToFile();
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    // iPad needs a source view for the popover
    sheet.popoverPresentationController.sourceView = self;
    sheet.popoverPresentationController.sourceRect = self.bounds;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
        if (keyWindow.rootViewController) {
            [keyWindow.rootViewController presentViewController:sheet animated:YES completion:nil];
        }
    });
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
@interface PassthroughWindow : UIWindow
@end

@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
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
        [btn setTitle:@"Export Logs" forState:UIControlStateNormal];
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
