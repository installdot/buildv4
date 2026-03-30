#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Network/Network.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <dlfcn.h>
#import <substrate.h>

static NSMutableArray *logs;

// ─────────────────────────────────────────
// Logger
// ─────────────────────────────────────────
static void AddLog(NSString *tag, NSString *body) {
    if (!logs) logs = [NSMutableArray new];

    NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                 dateStyle:NSDateFormatterNoStyle
                                                 timeStyle:NSDateFormatterMediumStyle];
    NSString *entry = [NSString stringWithFormat:
                       @"[%@] %@\n%@\n%@",
                       ts, tag, body,
                       @"────────────────────────────"];
    [logs addObject:entry];
    NSLog(@"[NetCapture] %@", entry);
}

static NSString *BytesToString(const void *buf, size_t len) {
    if (!buf || len == 0) return @"<empty>";
    NSData *data = [NSData dataWithBytes:buf length:MIN(len, 4096)];
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return str ?: [NSString stringWithFormat:@"<binary %zu bytes>", len];
}

// ─────────────────────────────────────────
// Layer 1: NSURLSession
// ─────────────────────────────────────────
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    AddLog(@"NSURLSession REQUEST", [NSString stringWithFormat:
        @"URL    : %@\nMethod : %@\nHeaders: %@\nBody   : %@",
        request.URL.absoluteString,
        request.HTTPMethod,
        request.allHTTPHeaderFields,
        request.HTTPBody
            ? ([[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding] ?: @"<binary>")
            : @"<none>"
    ]);

    void (^wrapped)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *resp, NSError *err) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
            AddLog(@"NSURLSession RESPONSE", [NSString stringWithFormat:
                @"URL    : %@\nStatus : %ld\nHeaders: %@\nBody   : %@",
                request.URL.absoluteString,
                (long)http.statusCode,
                http.allHeaderFields,
                [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"<binary>"
            ]);
            if (completionHandler) completionHandler(data, resp, err);
        };

    return %orig(request, wrapped);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData
                                completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    AddLog(@"NSURLSession UPLOAD", [NSString stringWithFormat:
        @"URL    : %@\nHeaders: %@\nBody   : %@",
        request.URL.absoluteString,
        request.allHTTPHeaderFields,
        [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding] ?: @"<binary>"
    ]);
    return %orig(request, bodyData, completionHandler);
}

%end

// ─────────────────────────────────────────
// Layer 2: NSURLConnection
// ─────────────────────────────────────────
%hook NSURLConnection

- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate startImmediately:(BOOL)start {
    AddLog(@"NSURLConnection REQUEST", [NSString stringWithFormat:
        @"URL    : %@\nMethod : %@\nHeaders: %@",
        request.URL.absoluteString,
        request.HTTPMethod,
        request.allHTTPHeaderFields
    ]);
    return %orig(request, delegate, start);
}

%end

// ─────────────────────────────────────────
// Layer 3: BSD Socket hooks
// ─────────────────────────────────────────
static ssize_t (*orig_send)(int fd, const void *buf, size_t len, int flags);
static ssize_t (*orig_recv)(int fd, void *buf, size_t len, int flags);
static ssize_t (*orig_write)(int fd, const void *buf, size_t nbyte);
static ssize_t (*orig_read)(int fd, void *buf, size_t nbyte);

static BOOL IsNetworkSocket(int fd) {
    struct sockaddr_storage addr;
    socklen_t addrLen = sizeof(addr);
    if (getpeername(fd, (struct sockaddr *)&addr, &addrLen) != 0) return NO;
    return addr.ss_family == AF_INET || addr.ss_family == AF_INET6;
}

static NSString *PeerInfo(int fd) {
    struct sockaddr_storage addr;
    socklen_t addrLen = sizeof(addr);
    if (getpeername(fd, (struct sockaddr *)&addr, &addrLen) != 0)
        return @"unknown";

    char ipStr[INET6_ADDRSTRLEN] = {0};
    uint16_t port = 0;

    if (addr.ss_family == AF_INET) {
        struct sockaddr_in *s = (struct sockaddr_in *)&addr;
        inet_ntop(AF_INET, &s->sin_addr, ipStr, sizeof(ipStr));
        port = ntohs(s->sin_port);
    } else {
        struct sockaddr_in6 *s = (struct sockaddr_in6 *)&addr;
        inet_ntop(AF_INET6, &s->sin6_addr, ipStr, sizeof(ipStr));
        port = ntohs(s->sin6_port);
    }
    return [NSString stringWithFormat:@"%s:%d", ipStr, port];
}

static ssize_t hook_send(int fd, const void *buf, size_t len, int flags) {
    ssize_t result = orig_send(fd, buf, len, flags);
    if (result > 0 && IsNetworkSocket(fd)) {
        AddLog(@"BSD send()", [NSString stringWithFormat:
            @"fd     : %d\nPeer   : %@\nBytes  : %zd\nData   : %@",
            fd, PeerInfo(fd), result, BytesToString(buf, (size_t)result)
        ]);
    }
    return result;
}

static ssize_t hook_recv(int fd, void *buf, size_t len, int flags) {
    ssize_t result = orig_recv(fd, buf, len, flags);
    if (result > 0 && IsNetworkSocket(fd)) {
        AddLog(@"BSD recv()", [NSString stringWithFormat:
            @"fd     : %d\nPeer   : %@\nBytes  : %zd\nData   : %@",
            fd, PeerInfo(fd), result, BytesToString(buf, (size_t)result)
        ]);
    }
    return result;
}

static ssize_t hook_write(int fd, const void *buf, size_t nbyte) {
    ssize_t result = orig_write(fd, buf, nbyte);
    if (result > 0 && IsNetworkSocket(fd)) {
        AddLog(@"BSD write()", [NSString stringWithFormat:
            @"fd     : %d\nPeer   : %@\nBytes  : %zd\nData   : %@",
            fd, PeerInfo(fd), result, BytesToString(buf, (size_t)result)
        ]);
    }
    return result;
}

static ssize_t hook_read(int fd, void *buf, size_t nbyte) {
    ssize_t result = orig_read(fd, buf, nbyte);
    if (result > 0 && IsNetworkSocket(fd)) {
        AddLog(@"BSD read()", [NSString stringWithFormat:
            @"fd     : %d\nPeer   : %@\nBytes  : %zd\nData   : %@",
            fd, PeerInfo(fd), result, BytesToString(buf, (size_t)result)
        ]);
    }
    return result;
}

// ─────────────────────────────────────────
// Layer 4: Network.framework nw_connection
// ─────────────────────────────────────────
%hook OS_nw_connection

- (void)sendContent:(id)content
            context:(id)context
         isComplete:(BOOL)isComplete
         completion:(nw_connection_send_completion_t)completion {

    if (content && [content conformsToProtocol:@protocol(OS_dispatch_data)]) {
        dispatch_data_t dispData = (dispatch_data_t)content;
        dispatch_data_apply(dispData, ^bool(dispatch_data_t region,
                                             size_t offset,
                                             const void *buffer,
                                             size_t size) {
            AddLog(@"nw_connection SEND", [NSString stringWithFormat:
                @"Bytes  : %zu\nData   : %@",
                size, BytesToString(buffer, size)
            ]);
            return true;
        });
    }

    %orig(content, context, isComplete, completion);
}

%end

// ─────────────────────────────────────────
// Floating button UI
// ─────────────────────────────────────────
@interface FloatingButton : UIButton
@end

@implementation FloatingButton

- (void)handleTap {
    NSString *all = [logs componentsJoinedByString:@"\n"];
    [UIPasteboard generalPasteboard].string = all;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:[NSString stringWithFormat:@"📡 %lu requests captured", (unsigned long)logs.count]
                             message:@"Logs copied to clipboard"
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

// ─────────────────────────────────────────
// Passthrough window (touches pass through bg)
// ─────────────────────────────────────────
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

        overlayWindow = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        overlayWindow.windowLevel = UIWindowLevelAlert + 100;
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
                                       initWithTarget:btn
                                               action:@selector(handlePan:)];
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
    AddFloatingButton();
    return r;
}

%end

// ─────────────────────────────────────────
// Constructor — BSD hooks + button fallback
// ─────────────────────────────────────────
__attribute__((constructor(101))) static void init_hook(void) {

    MSHookFunction((void *)send,  (void *)hook_send,  (void **)&orig_send);
    MSHookFunction((void *)recv,  (void *)hook_recv,  (void **)&orig_recv);
    MSHookFunction((void *)write, (void *)hook_write, (void **)&orig_write);
    MSHookFunction((void *)read,  (void *)hook_read,  (void **)&orig_read);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        AddFloatingButton();
    });
}
