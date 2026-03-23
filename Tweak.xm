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

// ─────────────────────────────────────────
// NSData → NSString
// ─────────────────────────────────────────
static NSString *DataToString(NSData *data) {
    if (!data) return @"<empty>";
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return str ?: [NSString stringWithFormat:@"<%lu bytes>", (unsigned long)data.length];
}

// ─────────────────────────────────────────
// 📋 Copy to Clipboard
// ─────────────────────────────────────────
static void CopyLogsToClipboard() {
    NSString *all = [logs componentsJoinedByString:@"\n"];

    [UIPasteboard generalPasteboard].string = all;

    NSLog(@"[EXPORT] Copied logs to clipboard");

    // Optional alert
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Export"
                             message:@"Logs copied to clipboard"
                      preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];

        UIWindow *keyWindow = UIApplication.sharedApplication.keyWindow;
        [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

// ─────────────────────────────────────────
// Floating Button
// ─────────────────────────────────────────
@interface FloatingButton : UIButton
@end

@implementation FloatingButton
@end

static void AddFloatingButton() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = UIApplication.sharedApplication.keyWindow;
        if (!window) return;

        // Prevent duplicate
        if ([window viewWithTag:9999]) return;

        FloatingButton *btn = [FloatingButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(40, 200, 100, 50);
        btn.tag = 9999;

        btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        [btn setTitle:@"Copy Logs" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.layer.cornerRadius = 10;

        [btn addTarget:[NSBlockOperation blockOperationWithBlock:^{
            CopyLogsToClipboard();
        }] action:@selector(main) forControlEvents:UIControlEventTouchUpInside];

        // Drag support
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
            initWithTarget:btn action:@selector(handlePan:)];
        [btn addGestureRecognizer:pan];

        [window addSubview:btn];
    });
}

// Drag handler
@implementation FloatingButton (Drag)
- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x,
                              self.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.superview];
}
@end

// ─────────────────────────────────────────
// NSURLSession Hook
// ─────────────────────────────────────────
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    NSString *reqLog = [NSString stringWithFormat:
        @"[REQUEST]\nURL: %@\nMethod: %@\nHeaders: %@\nBody: %@",
        request.URL.absoluteString,
        request.HTTPMethod,
        request.allHTTPHeaderFields,
        DataToString(request.HTTPBody)
    ];

    AddLog(reqLog);

    return %orig(request, ^(NSData *data, NSURLResponse *response, NSError *error) {

        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;

        NSString *respLog = [NSString stringWithFormat:
            @"[RESPONSE]\nURL: %@\nStatus: %ld\nHeaders: %@\nBody: %@",
            request.URL.absoluteString,
            (long)http.statusCode,
            http.allHeaderFields,
            DataToString(data)
        ];

        AddLog(respLog);

        if (completionHandler) {
            completionHandler(data, response, error);
        }
    });
}

%end

// ─────────────────────────────────────────
// Inject button when app launches
// ─────────────────────────────────────────
%hook UIApplication

- (void)didFinishLaunching {
    %orig;
    AddFloatingButton();
}

%end

// ─────────────────────────────────────────
// Fallback
// ─────────────────────────────────────────
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        AddFloatingButton();
    });
}
