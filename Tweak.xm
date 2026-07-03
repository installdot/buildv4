#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CFNetwork/CFNetwork.h>
#import <substrate.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <dlfcn.h>
#include <unistd.h>

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
// Socket address helper
// ─────────────────────────────────────────
static NSString *SockAddrToString(const struct sockaddr *sa) {
    if (!sa) return @"<null>";
    char host[NI_MAXHOST] = {0};
    char port[NI_MAXSERV] = {0};
    int ret = getnameinfo(sa, sa->sa_len, host, sizeof(host),
                          port, sizeof(port),
                          NI_NUMERICHOST | NI_NUMERICSERV);
    if (ret == 0) {
        return [NSString stringWithFormat:@"%s:%s", host, port];
    }
    // Fallback manual parsing
    if (sa->sa_family == AF_INET) {
        struct sockaddr_in *sin = (struct sockaddr_in *)sa;
        return [NSString stringWithFormat:@"%s:%d",
                inet_ntoa(sin->sin_addr), ntohs(sin->sin_port)];
    }
    if (sa->sa_family == AF_INET6) {
        struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)sa;
        char buf[INET6_ADDRSTRLEN] = {0};
        inet_ntop(AF_INET6, &sin6->sin6_addr, buf, sizeof(buf));
        return [NSString stringWithFormat:@"[%s]:%d", buf, ntohs(sin6->sin6_port)];
    }
    return [NSString stringWithFormat:@"<af=%d>", sa->sa_family];
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
// LAYER 1 — NSURLSession (high-level HTTP)
// ─────────────────────────────────────────
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {

    AddLog([NSString stringWithFormat:
            @"[L1·NSURLSession·REQUEST]\nURL:     %@\nMethod:  %@\nHeaders: %@\nBody:    %@",
            request.URL.absoluteString,
            request.HTTPMethod,
            request.allHTTPHeaderFields,
            DataToString(request.HTTPBody)]);

    void (^wrapped)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *resp, NSError *err) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
            AddLog([NSString stringWithFormat:
                    @"[L1·NSURLSession·RESPONSE]\nURL:     %@\nStatus:  %ld\nHeaders: %@\nBody:    %@",
                    request.URL.absoluteString,
                    (long)http.statusCode,
                    http.allHeaderFields,
                    DataToString(data)]);
            if (handler) handler(data, resp, err);
        };
    return %orig(request, wrapped);
}

%end

// ─────────────────────────────────────────
// LAYER 2 — CFNetwork (transport layer TLS/TCP streams)
// ─────────────────────────────────────────

// --- CFReadStreamRead ---
typedef CFIndex (*CFReadStreamRead_t)(CFReadStreamRef, UInt8 *, CFIndex);
static CFReadStreamRead_t orig_CFReadStreamRead = NULL;

static CFIndex hook_CFReadStreamRead(CFReadStreamRef stream, UInt8 *buf, CFIndex len) {
    CFIndex result = orig_CFReadStreamRead(stream, buf, len);
    if (result > 0) {
        NSData *data = [NSData dataWithBytes:buf length:(NSUInteger)result];

        // Extract URL from stream's associated property if available
        CFTypeRef urlProp = CFReadStreamCopyProperty(stream, kCFStreamPropertyHTTPFinalURL);
        NSString *urlStr  = urlProp
            ? [(__bridge NSURL *)urlProp absoluteString]
            : @"<unknown>";
        if (urlProp) CFRelease(urlProp);

        AddLog([NSString stringWithFormat:
                @"[L2·CFReadStream·READ]\nURL:   %@\nBytes: %ld\nData:  %@",
                urlStr, (long)result, DataToString(data)]);
    }
    return result;
}

// --- CFWriteStreamWrite ---
typedef CFIndex (*CFWriteStreamWrite_t)(CFWriteStreamRef, const UInt8 *, CFIndex);
static CFWriteStreamWrite_t orig_CFWriteStreamWrite = NULL;

static CFIndex hook_CFWriteStreamWrite(CFWriteStreamRef stream,
                                       const UInt8 *buf, CFIndex len) {
    if (len > 0) {
        NSData *data     = [NSData dataWithBytes:buf length:(NSUInteger)len];
        CFTypeRef urlProp = CFWriteStreamCopyProperty(stream, kCFStreamPropertyHTTPFinalURL);
        NSString *urlStr  = urlProp
            ? [(__bridge NSURL *)urlProp absoluteString]
            : @"<unknown>";
        if (urlProp) CFRelease(urlProp);

        AddLog([NSString stringWithFormat:
                @"[L2·CFWriteStream·WRITE]\nURL:   %@\nBytes: %ld\nData:  %@",
                urlStr, (long)len, DataToString(data)]);
    }
    return orig_CFWriteStreamWrite(stream, buf, len);
}

// ─────────────────────────────────────────
// LAYER 3 — BSD sockets (kernel syscall boundary)
// ─────────────────────────────────────────

// --- connect ---
typedef int (*connect_t)(int, const struct sockaddr *, socklen_t);
static connect_t orig_connect = NULL;

static int hook_connect(int fd, const struct sockaddr *addr, socklen_t len) {
    AddLog([NSString stringWithFormat:
            @"[L3·BSD·connect]\nfd:      %d\nremote:  %@",
            fd, SockAddrToString(addr)]);
    return orig_connect(fd, addr, len);
}

// --- send ---
typedef ssize_t (*send_t)(int, const void *, size_t, int);
static send_t orig_send = NULL;

static ssize_t hook_send(int fd, const void *buf, size_t len, int flags) {
    if (len > 0) {
        NSData *data = [NSData dataWithBytes:buf length:MIN(len, 256)];
        AddLog([NSString stringWithFormat:
                @"[L3·BSD·send]\nfd:    %d\nflags: %d\nbytes: %zu\ndata:  %@",
                fd, flags, len, DataToString(data)]);
    }
    return orig_send(fd, buf, len, flags);
}

// --- recv ---
typedef ssize_t (*recv_t)(int, void *, size_t, int);
static recv_t orig_recv = NULL;

static ssize_t hook_recv(int fd, void *buf, size_t len, int flags) {
    ssize_t result = orig_recv(fd, buf, len, flags);
    if (result > 0) {
        NSData *data = [NSData dataWithBytes:buf length:(NSUInteger)MIN(result, 256)];
        AddLog([NSString stringWithFormat:
                @"[L3·BSD·recv]\nfd:    %d\nflags: %d\nbytes: %zd\ndata:  %@",
                fd, flags, result, DataToString(data)]);
    }
    return result;
}

// --- sendto (UDP / raw sockets) ---
typedef ssize_t (*sendto_t)(int, const void *, size_t, int,
                            const struct sockaddr *, socklen_t);
static sendto_t orig_sendto = NULL;

static ssize_t hook_sendto(int fd, const void *buf, size_t len, int flags,
                           const struct sockaddr *dest, socklen_t addrlen) {
    if (len > 0) {
        NSData *data = [NSData dataWithBytes:buf length:MIN(len, 256)];
        AddLog([NSString stringWithFormat:
                @"[L3·BSD·sendto]\nfd:     %d\nremote: %@\nbytes:  %zu\ndata:   %@",
                fd, SockAddrToString(dest), len, DataToString(data)]);
    }
    return orig_sendto(fd, buf, len, flags, dest, addrlen);
}

// --- recvfrom (UDP / raw sockets) ---
typedef ssize_t (*recvfrom_t)(int, void *, size_t, int,
                              struct sockaddr *, socklen_t *);
static recvfrom_t orig_recvfrom = NULL;

static ssize_t hook_recvfrom(int fd, void *buf, size_t len, int flags,
                             struct sockaddr *src, socklen_t *addrlen) {
    ssize_t result = orig_recvfrom(fd, buf, len, flags, src, addrlen);
    if (result > 0) {
        NSData *data = [NSData dataWithBytes:buf length:(NSUInteger)MIN(result, 256)];
        AddLog([NSString stringWithFormat:
                @"[L3·BSD·recvfrom]\nfd:     %d\nsource: %@\nbytes:  %zd\ndata:   %@",
                fd, src ? SockAddrToString(src) : @"<any>",
                result, DataToString(data)]);
    }
    return result;
}

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

// ─────────────────────────────────────────
// Constructor — install all C-level hooks
// ─────────────────────────────────────────
__attribute__((constructor(101))) static void init_hook(void) {
    // ── Layer 2: CFNetwork ──
    orig_CFReadStreamRead  = (CFReadStreamRead_t)
        MSHookFunction((void *)CFReadStreamRead,
                       (void *)hook_CFReadStreamRead,
                       (void **)&orig_CFReadStreamRead);

    orig_CFWriteStreamWrite = (CFWriteStreamWrite_t)
        MSHookFunction((void *)CFWriteStreamWrite,
                       (void *)hook_CFWriteStreamWrite,
                       (void **)&orig_CFWriteStreamWrite);

    // ── Layer 3: BSD sockets ──
    // libsystem_kernel.dylib owns the real syscall stubs;
    // libsystem_c.dylib wraps them with errno handling — hook the wrapper.
    void *libC = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY | RTLD_NOLOAD);

    orig_connect  = (connect_t)
        MSHookFunction(dlsym(libC, "connect"),
                       (void *)hook_connect,
                       (void **)&orig_connect);

    orig_send     = (send_t)
        MSHookFunction(dlsym(libC, "send"),
                       (void *)hook_send,
                       (void **)&orig_send);

    orig_recv     = (recv_t)
        MSHookFunction(dlsym(libC, "recv"),
                       (void *)hook_recv,
                       (void **)&orig_recv);

    orig_sendto   = (sendto_t)
        MSHookFunction(dlsym(libC, "sendto"),
                       (void *)hook_sendto,
                       (void **)&orig_sendto);

    orig_recvfrom = (recvfrom_t)
        MSHookFunction(dlsym(libC, "recvfrom"),
                       (void *)hook_recvfrom,
                       (void **)&orig_recvfrom);

    // Floating button fallback (fires after app window is ready)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        AddFloatingButton();
    });
}
