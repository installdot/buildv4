/*
 * NetCapture — Universal Request Logger
 *
 * Captures EVERY outgoing HTTP/HTTPS request the app makes:
 *   - URL, method, headers, body
 *   - Response status, headers, body
 *   - Timing (ms)
 *
 * Output : NSDocumentDirectory/net_capture.txt
 *          Appended in real-time, one entry per request
 *
 * Load order:
 *   constructor(101) → NSURLProtocol registered before ANY app code runs
 *   %ctor           → Logos hooks + overlay
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// =============================================================================
//  MARK: - Constants
// =============================================================================

static NSString *const kNCBypassKey  = @"NCBypassCapture";
static NSString *const kNCHandledKey = @"NCHandled";
static NSString *const kLogFileName  = @"net_capture.txt";

// =============================================================================
//  MARK: - Log writer (thread-safe, append-only)
// =============================================================================

static dispatch_queue_t gLogQueue;

static NSString *LogFilePath(void) {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [docs stringByAppendingPathComponent:kLogFileName];
}

static void NCLog(NSString *entry) {
    dispatch_async(gLogQueue, ^{
        NSString *path = LogFilePath();
        NSFileManager *fm = [NSFileManager defaultManager];

        // Create file with header if it doesn't exist yet
        if (![fm fileExistsAtPath:path]) {
            NSString *header = [NSString stringWithFormat:
                @"╔══════════════════════════════════════════════════════════╗\n"
                 "║             NetCapture — Universal Request Log            ║\n"
                 "║  Bundle : %-46@  ║\n"
                 "║  Start  : %-46@  ║\n"
                 "╚══════════════════════════════════════════════════════════╝\n\n",
                [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown",
                [NSDate date]];
            [header writeToFile:path atomically:YES
                       encoding:NSUTF8StringEncoding error:nil];
        }

        // Append entry
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (fh) {
            [fh seekToEndOfFile];
            NSData *d = [entry dataUsingEncoding:NSUTF8StringEncoding];
            if (d) [fh writeData:d];
            [fh closeFile];
        }
    });
}

static NSString *HexDumpPreview(NSData *data, NSUInteger maxBytes) {
    if (!data || data.length == 0) return @"<empty>";
    NSUInteger len  = MIN(data.length, maxBytes);
    NSString  *utf8 = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, len)]
                                            encoding:NSUTF8StringEncoding];
    if (utf8) {
        // Sanitise control chars for log readability
        NSMutableString *s = [utf8 mutableCopy];
        [s replaceOccurrencesOfString:@"\n" withString:@"↵"
                              options:0 range:NSMakeRange(0, s.length)];
        [s replaceOccurrencesOfString:@"\r" withString:@""
                              options:0 range:NSMakeRange(0, s.length)];
        return (data.length > maxBytes)
            ? [NSString stringWithFormat:@"%@ …(+%lu B)", s,
               (unsigned long)(data.length - maxBytes)]
            : s;
    }
    // Binary fallback — hex preview
    NSMutableString *hex = [NSMutableString string];
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    for (NSUInteger i = 0; i < MIN(len, 64); i++)
        [hex appendFormat:@"%02X ", bytes[i]];
    return [NSString stringWithFormat:@"<binary %lu B> %@",
            (unsigned long)data.length, hex];
}

// =============================================================================
//  MARK: - Capture Protocol (PRIMARY interface first, then extension)
// =============================================================================

@interface NCCaptureProtocol : NSURLProtocol
@property (nonatomic, strong) NSURLSessionDataTask *realTask;
@property (nonatomic, strong) NSMutableData        *responseData;
@property (nonatomic, strong) NSHTTPURLResponse    *responseHTTP;
@property (nonatomic, assign) NSTimeInterval        startTime;
@property (nonatomic, assign) NSUInteger            reqIndex;
@end

@interface NCCaptureProtocol () <NSURLSessionDataDelegate>
@end

// Monotonic request counter (atomic)
static _Atomic(NSUInteger) gReqCounter = 0;

@implementation NCCaptureProtocol

// ── Registration ─────────────────────────────────────────────────────────────

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    // Skip our own forwarded copies
    if ([NSURLProtocol propertyForKey:kNCBypassKey  inRequest:request]) return NO;
    if ([NSURLProtocol propertyForKey:kNCHandledKey inRequest:request]) return NO;
    // Capture everything HTTP/HTTPS
    NSString *scheme = request.URL.scheme.lowercaseString;
    return ([scheme isEqualToString:@"http"] ||
            [scheme isEqualToString:@"https"]);
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a
                       toRequest:(NSURLRequest *)b { return NO; }

// ── Start ─────────────────────────────────────────────────────────────────────

- (void)startLoading {
    self.startTime    = [NSDate date].timeIntervalSince1970;
    self.responseData = [NSMutableData data];
    self.reqIndex     = ++gReqCounter;

    // ── Log REQUEST ──────────────────────────────────────────────────────────
    NSURLRequest *req = self.request;
    NSMutableString *reqLog = [NSMutableString string];

    [reqLog appendFormat:
        @"┌─────────────────────────────────────────────────────────────\n"
         "│  #%-6lu  REQUEST\n"
         "│  Time   : %@\n"
         "│  Method : %@\n"
         "│  URL    : %@\n",
        (unsigned long)self.reqIndex,
        [NSDate date],
        req.HTTPMethod ?: @"GET",
        req.URL.absoluteString ?: @"?"];

    // Request headers
    NSDictionary *rhdrs = req.allHTTPHeaderFields;
    if (rhdrs.count) {
        [reqLog appendString:@"│  Headers:\n"];
        for (NSString *k in rhdrs)
            [reqLog appendFormat:@"│    %@ : %@\n", k, rhdrs[k]];
    }

    // Request body
    NSData *body = req.HTTPBody;
    if (!body && req.HTTPBodyStream) {
        // Read stream into data (max 8 KB preview)
        NSInputStream *stream = req.HTTPBodyStream;
        [stream open];
        NSMutableData *bd = [NSMutableData data];
        uint8_t buf[4096]; NSInteger nb;
        while ([stream hasBytesAvailable] && bd.length < 8192) {
            nb = [stream read:buf maxLength:sizeof(buf)];
            if (nb > 0) [bd appendBytes:buf length:nb]; else break;
        }
        [stream close];
        body = bd.length ? bd : nil;
    }
    if (body.length) {
        [reqLog appendFormat:@"│  Body (%lu B):\n│    %@\n",
            (unsigned long)body.length,
            HexDumpPreview(body, 512)];
    } else {
        [reqLog appendString:@"│  Body : <none>\n"];
    }
    [reqLog appendString:@"│\n"];
    NCLog(reqLog);

    // ── Forward real request on bypass session ────────────────────────────
    NSMutableURLRequest *fwdReq = [req mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kNCBypassKey  inRequest:fwdReq];
    [NSURLProtocol setProperty:@YES forKey:kNCHandledKey inRequest:fwdReq];

    NSURLSessionConfiguration *cfg =
        [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.protocolClasses = @[];   // no custom protocols on bypass session

    NSURLSession *session =
        [NSURLSession sessionWithConfiguration:cfg
                                      delegate:self
                                 delegateQueue:nil];
    self.realTask = [session dataTaskWithRequest:fwdReq];
    [self.realTask resume];
}

- (void)stopLoading {
    [self.realTask cancel];
    self.realTask = nil;
}

// ── NSURLSessionDataDelegate ──────────────────────────────────────────────────

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)task
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {

    self.responseHTTP = [response isKindOfClass:[NSHTTPURLResponse class]]
        ? (NSHTTPURLResponse *)response : nil;

    // Forward to app
    [self.client URLProtocol:self
          didReceiveResponse:response
          cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)task
    didReceiveData:(NSData *)data {
    [self.responseData appendData:data];
    [self.client URLProtocol:self didLoadData:data];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {

    NSTimeInterval elapsed =
        ([NSDate date].timeIntervalSince1970 - self.startTime) * 1000.0;

    // ── Log RESPONSE ─────────────────────────────────────────────────────────
    NSMutableString *respLog = [NSMutableString string];

    if (error) {
        [respLog appendFormat:
            @"│  #%-6lu  RESPONSE  (%.1f ms)\n"
             "│  ERROR  : %@ (code %ld)\n"
             "└─────────────────────────────────────────────────────────────\n\n",
            (unsigned long)self.reqIndex, elapsed,
            error.localizedDescription, (long)error.code];
        NCLog(respLog);
        [self.client URLProtocol:self didFailWithError:error];
        return;
    }

    NSHTTPURLResponse *http = self.responseHTTP;
    [respLog appendFormat:
        @"│  #%-6lu  RESPONSE  (%.1f ms)\n"
         "│  Status : %ld\n",
        (unsigned long)self.reqIndex, elapsed,
        http ? (long)http.statusCode : 0L];

    // Response headers
    NSDictionary *phdrs = http.allHeaderFields;
    if (phdrs.count) {
        [respLog appendString:@"│  Headers:\n"];
        for (NSString *k in phdrs)
            [respLog appendFormat:@"│    %@ : %@\n", k, phdrs[k]];
    }

    // Response body preview
    if (self.responseData.length) {
        [respLog appendFormat:@"│  Body (%lu B):\n│    %@\n",
            (unsigned long)self.responseData.length,
            HexDumpPreview(self.responseData, 1024)];
    } else {
        [respLog appendString:@"│  Body : <none>\n"];
    }

    [respLog appendString:
        @"└─────────────────────────────────────────────────────────────\n\n"];
    NCLog(respLog);

    [self.client URLProtocolDidFinishLoading:self];
}

// Auth challenge passthrough
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition,
                             NSURLCredential *))completionHandler {
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

@end

// =============================================================================
//  MARK: - HIGH PRIORITY CONSTRUCTOR (101)
//  Executes BEFORE +load, BEFORE application:didFinishLaunchingWithOptions:
//  Protocol is capturing from the very first network call the app makes.
// =============================================================================

__attribute__((constructor(101)))
static void ncNetworkInit(void) {
    // Serial queue for all log I/O
    gLogQueue = dispatch_queue_create("com.netcapture.logq",
                                      DISPATCH_QUEUE_SERIAL);
    [NSURLProtocol registerClass:[NCCaptureProtocol class]];
    NSLog(@"[NetCapture][P101] Protocol registered — capturing ALL requests");
    NSLog(@"[NetCapture] Log -> %@", LogFilePath());
}

// =============================================================================
//  MARK: - Overlay (minimisable HUD showing live count + log path)
// =============================================================================

@interface NCOverlayView : UIView
@property (nonatomic, strong) UILabel  *countLabel;
@property (nonatomic, strong) UILabel  *pathLabel;
@property (nonatomic, strong) UIView   *pillView;
@property (nonatomic, strong) UILabel  *pillLabel;
@property (nonatomic, assign) BOOL      minimised;
@end

static UIWindow     *gNCWindow  = nil;
static NCOverlayView *gNCOverlay = nil;

@implementation NCOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    CGFloat W = frame.size.width;

    self.backgroundColor    = [UIColor colorWithWhite:0.07 alpha:0.95];
    self.layer.cornerRadius = 16;
    self.layer.borderWidth  = 1;
    self.layer.borderColor  =
        [UIColor colorWithRed:0.20 green:0.55 blue:1.00 alpha:0.60].CGColor;
    self.clipsToBounds = YES;

    // Header icon + title
    UILabel *ico = [[UILabel alloc] initWithFrame:CGRectMake(12, 10, 22, 18)];
    ico.text = @"🌐"; ico.font = [UIFont systemFontOfSize:13];
    [self addSubview:ico];

    UILabel *ttl = [[UILabel alloc] initWithFrame:CGRectMake(36, 10, W - 72, 18)];
    ttl.text      = @"NetCapture";
    ttl.font      = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    ttl.textColor = [UIColor colorWithRed:0.20 green:0.55 blue:1.00 alpha:1.0];
    [self addSubview:ttl];

    // Minimise button
    UIButton *minBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    minBtn.frame = CGRectMake(W - 34, 6, 26, 26);
    [minBtn setTitle:@"—" forState:UIControlStateNormal];
    minBtn.tintColor       = [UIColor colorWithWhite:0.45 alpha:1.0];
    minBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [minBtn addTarget:self action:@selector(toggleMinimise)
     forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:minBtn];

    // Divider
    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(0, 34, W, 0.5)];
    div.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    [self addSubview:div];

    // Request counter
    UILabel *cLbl = [[UILabel alloc] initWithFrame:CGRectMake(12, 40, 90, 13)];
    cLbl.text      = @"CAPTURED";
    cLbl.font      = [UIFont systemFontOfSize:8 weight:UIFontWeightSemibold];
    cLbl.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    [self addSubview:cLbl];

    self.countLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 53, W - 24, 22)];
    self.countLabel.text      = @"0 requests";
    self.countLabel.font      = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    self.countLabel.textColor = [UIColor colorWithRed:0.20 green:0.55 blue:1.00 alpha:1.0];
    [self addSubview:self.countLabel];

    // Divider 2
    UIView *div2 = [[UIView alloc] initWithFrame:CGRectMake(0, 80, W, 0.5)];
    div2.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    [self addSubview:div2];

    // Log path
    UILabel *pLbl = [[UILabel alloc] initWithFrame:CGRectMake(12, 86, W - 24, 13)];
    pLbl.text      = @"OUTPUT FILE";
    pLbl.font      = [UIFont systemFontOfSize:8 weight:UIFontWeightSemibold];
    pLbl.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    [self addSubview:pLbl];

    self.pathLabel                = [[UILabel alloc] initWithFrame:CGRectMake(12, 100, W - 24, 28)];
    self.pathLabel.text           = LogFilePath();
    self.pathLabel.font           = [UIFont monospacedSystemFontOfSize:7
                                                                weight:UIFontWeightRegular];
    self.pathLabel.textColor      = [UIColor colorWithWhite:0.45 alpha:1.0];
    self.pathLabel.numberOfLines  = 2;
    self.pathLabel.adjustsFontSizeToFitWidth = YES;
    [self addSubview:self.pathLabel];

    // Clear button
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.frame = CGRectMake(12, 134, W - 24, 30);
    [clearBtn setTitle:@"Clear Log" forState:UIControlStateNormal];
    clearBtn.titleLabel.font    = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    clearBtn.tintColor          = [UIColor colorWithRed:0.07 green:0.09 blue:0.12 alpha:1.0];
    clearBtn.backgroundColor    = [UIColor colorWithRed:0.85 green:0.25 blue:0.25 alpha:1.0];
    clearBtn.layer.cornerRadius = 9;
    clearBtn.clipsToBounds      = YES;
    [clearBtn addTarget:self action:@selector(didTapClear)
      forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:clearBtn];

    // Pill (minimised)
    self.pillView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 32)];
    self.pillView.backgroundColor    = [UIColor colorWithWhite:0.07 alpha:0.95];
    self.pillView.layer.cornerRadius = 16;
    self.pillView.layer.borderWidth  = 1;
    self.pillView.layer.borderColor  =
        [UIColor colorWithRed:0.20 green:0.55 blue:1.00 alpha:0.50].CGColor;
    self.pillView.clipsToBounds          = YES;
    self.pillView.hidden                 = YES;
    self.pillView.userInteractionEnabled = YES;

    self.pillLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, W - 20, 32)];
    self.pillLabel.font      = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    self.pillLabel.textColor = [UIColor colorWithRed:0.20 green:0.55 blue:1.00 alpha:1.0];
    self.pillLabel.text      = @"🌐 NetCapture  0 req";
    [self.pillView addSubview:self.pillLabel];

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(toggleMinimise)];
    [self.pillView addGestureRecognizer:tap];
    [self addSubview:self.pillView];

    // Drag
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];

    // Tick counter every second
    [NSTimer scheduledTimerWithTimeInterval:1.0
                                     target:self
                                   selector:@selector(refreshCount)
                                   userInfo:nil
                                    repeats:YES];
    return self;
}

- (void)refreshCount {
    NSUInteger n = gReqCounter;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.countLabel.text = [NSString stringWithFormat:@"%lu request%@",
                                (unsigned long)n, n == 1 ? @"" : @"s"];
        self.pillLabel.text  = [NSString stringWithFormat:@"🌐 NetCapture  %lu req",
                                (unsigned long)n];
    });
}

- (void)didTapClear {
    dispatch_async(gLogQueue, ^{
        [@"" writeToFile:LogFilePath()
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:nil];
        gReqCounter = 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshCount];
        });
    });
}

- (void)toggleMinimise {
    self.minimised = !self.minimised;
    CGFloat fullH = 172;
    if (self.minimised) {
        [UIView animateWithDuration:0.18 animations:^{
            CGRect f = gNCWindow.frame; f.size.height = 32; gNCWindow.frame = f;
            self.frame = CGRectMake(0, 0, f.size.width, 32);
        } completion:^(BOOL _) {
            for (UIView *v in self.subviews) v.hidden = (v != self.pillView);
            self.pillView.hidden    = NO;
            self.layer.cornerRadius = 16;
        }];
    } else {
        for (UIView *v in self.subviews) v.hidden = NO;
        self.pillView.hidden = YES;
        [UIView animateWithDuration:0.18 animations:^{
            CGRect f = gNCWindow.frame; f.size.height = fullH; gNCWindow.frame = f;
            self.frame = CGRectMake(0, 0, f.size.width, fullH);
        }];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint d = [pan translationInView:self.superview];
    CGRect  f = gNCWindow.frame;
    f.origin.x += d.x; f.origin.y += d.y;
    CGRect sc = [UIScreen mainScreen].bounds;
    f.origin.x = MAX(0,  MIN(f.origin.x, sc.size.width  - f.size.width));
    f.origin.y = MAX(20, MIN(f.origin.y, sc.size.height - f.size.height - 20));
    gNCWindow.frame = f;
    [pan setTranslation:CGPointZero inView:self.superview];
}

@end

// =============================================================================
//  MARK: - Window pass-through
// =============================================================================

@interface NCWindow : UIWindow
@end
@implementation NCWindow
- (BOOL)pointInside:(CGPoint)pt withEvent:(UIEvent *)ev {
    for (UIView *s in self.subviews)
        if (!s.hidden &&
            [s pointInside:[self convertPoint:pt toView:s] withEvent:ev])
            return YES;
    return NO;
}
@end

// =============================================================================
//  MARK: - Spawn overlay
// =============================================================================

static void spawnNCOverlay(void) {
    if (gNCWindow) return;
    CGFloat W = 220, H = 172;
    CGRect sc = [UIScreen mainScreen].bounds;

    gNCWindow = [[NCWindow alloc] initWithFrame:
        CGRectMake(sc.size.width - W - 10, sc.size.height * 0.12, W, H)];

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                gNCWindow.windowScene = (UIWindowScene *)scene;
                break;
            }
        }
    }
    gNCWindow.windowLevel     = UIWindowLevelAlert + 200;
    gNCWindow.backgroundColor = [UIColor clearColor];
    gNCOverlay = [[NCOverlayView alloc] initWithFrame:CGRectMake(0, 0, W, H)];
    [gNCWindow addSubview:gNCOverlay];
    gNCWindow.hidden = NO;
    [gNCWindow makeKeyAndVisible];
    NSLog(@"[NetCapture] Overlay ready");
}

// =============================================================================
//  MARK: - Hooks
// =============================================================================

%hook UIApplication
- (BOOL)application:(UIApplication *)app
    didFinishLaunchingWithOptions:(NSDictionary *)opts {
    BOOL r = %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ spawnNCOverlay(); });
    return r;
}
%end

// =============================================================================
//  MARK: - Logos constructor
// =============================================================================

%ctor {
    %init;
    NSLog(@"[NetCapture][%%ctor] hooks live — %@",
          [[NSBundle mainBundle] bundleIdentifier]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ spawnNCOverlay(); });
}
