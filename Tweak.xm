// Tweak.xm
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface Unitoreios : NSObject
- (void)activehack:(NSString *)title message:(NSString *)message font:(UIFont *)font;
- (void)showOfflineNoticeIfNeeded;
@end

// ─── Blocked domain ───────────────────────────────────────────────
static NSString *const kBlockedHost = @"apiunitoreios.site";

static BOOL isBlockedURL(NSURL *url) {
    if (!url) return NO;
    NSString *host = url.host.lowercaseString;
    return host && ([host isEqualToString:kBlockedHost] ||
                    [host hasSuffix:[NSString stringWithFormat:@".%@", kBlockedHost]]);
}

// ─── Date helper ──────────────────────────────────────────────────
static NSString *getDateString() {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [fmt stringFromDate:[NSDate date]];
}

// ─── Debug banner ─────────────────────────────────────────────────
static void showDebugBanner() {
    Class unitoreiosClass = objc_getClass("Unitoreios");
    if (!unitoreiosClass) return;

    id instance = [unitoreiosClass new];
    if (!instance) return;

    NSString *msg = [NSString stringWithFormat:@"Hôm nay là ngày: %@", getDateString()];
    SEL sel = NSSelectorFromString(@"activehack:message:font:");
    if ([instance respondsToSelector:sel]) {
        UIFont *font = [UIFont fontWithName:@"AvenirNext-Bold" size:13];
        typedef void (*MsgSendType)(id, SEL, NSString *, NSString *, UIFont *);
        MsgSendType send = (MsgSendType)objc_msgSend;
        send(instance, sel, @"Trần Quang Hải - Crack key thành công...", msg, font);
    }
}


// ══════════════════════════════════════════════════════════════════
//  BLOCK: NSURLSession — dataTaskWithRequest / dataTaskWithURL
// ══════════════════════════════════════════════════════════════════
%hook NSURLSession

// --- dataTaskWithRequest:completionHandler: ---
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (isBlockedURL(request.URL)) {
        NSLog(@"[XumodBlock] BLOCKED (dataTaskWithRequest): %@", request.URL);
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:NSURLErrorDomain
                                               code:NSURLErrorNotConnectedToInternet
                                           userInfo:@{NSLocalizedDescriptionKey: @"Blocked by Xumod"}];
            dispatch_async(dispatch_get_main_queue(), ^{ completionHandler(nil, nil, err); });
        }
        // Return a dummy cancelled task so callers don't crash
        return %orig([NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]], completionHandler);
    }
    return %orig;
}

// --- dataTaskWithRequest: (no completion) ---
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    if (isBlockedURL(request.URL)) {
        NSLog(@"[XumodBlock] BLOCKED (dataTaskWithRequest no-cb): %@", request.URL);
        NSMutableURLRequest *blank = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]];
        return %orig(blank);
    }
    return %orig;
}

// --- dataTaskWithURL:completionHandler: ---
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (isBlockedURL(url)) {
        NSLog(@"[XumodBlock] BLOCKED (dataTaskWithURL): %@", url);
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:NSURLErrorDomain
                                               code:NSURLErrorNotConnectedToInternet
                                           userInfo:@{NSLocalizedDescriptionKey: @"Blocked by Xumod"}];
            dispatch_async(dispatch_get_main_queue(), ^{ completionHandler(nil, nil, err); });
        }
        return %orig([NSURL URLWithString:@"about:blank"], completionHandler);
    }
    return %orig;
}

// --- dataTaskWithURL: (no completion) ---
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url {
    if (isBlockedURL(url)) {
        NSLog(@"[XumodBlock] BLOCKED (dataTaskWithURL no-cb): %@", url);
        return %orig([NSURL URLWithString:@"about:blank"]);
    }
    return %orig;
}

// --- uploadTaskWithRequest:fromData:completionHandler: ---
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData
                                completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (isBlockedURL(request.URL)) {
        NSLog(@"[XumodBlock] BLOCKED (uploadTask): %@", request.URL);
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:NSURLErrorDomain
                                               code:NSURLErrorNotConnectedToInternet
                                           userInfo:@{NSLocalizedDescriptionKey: @"Blocked by Xumod"}];
            dispatch_async(dispatch_get_main_queue(), ^{ completionHandler(nil, nil, err); });
        }
        NSMutableURLRequest *blank = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]];
        return %orig(blank, bodyData, completionHandler);
    }
    return %orig;
}

// --- downloadTaskWithRequest:completionHandler: ---
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                    completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))completionHandler {
    if (isBlockedURL(request.URL)) {
        NSLog(@"[XumodBlock] BLOCKED (downloadTask): %@", request.URL);
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:NSURLErrorDomain
                                               code:NSURLErrorNotConnectedToInternet
                                           userInfo:@{NSLocalizedDescriptionKey: @"Blocked by Xumod"}];
            dispatch_async(dispatch_get_main_queue(), ^{ completionHandler(nil, nil, err); });
        }
        NSMutableURLRequest *blank = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]];
        return %orig(blank, completionHandler);
    }
    return %orig;
}

%end


// ══════════════════════════════════════════════════════════════════
//  BLOCK: NSURLConnection (legacy API)
// ══════════════════════════════════════════════════════════════════
%hook NSURLConnection

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                 returningResponse:(NSURLResponse **)response
                             error:(NSError **)error {
    if (isBlockedURL(request.URL)) {
        NSLog(@"[XumodBlock] BLOCKED (sendSynchronousRequest): %@", request.URL);
        if (error) *error = [NSError errorWithDomain:NSURLErrorDomain
                                                code:NSURLErrorNotConnectedToInternet
                                            userInfo:@{NSLocalizedDescriptionKey: @"Blocked by Xumod"}];
        return nil;
    }
    return %orig;
}

+ (void)sendAsynchronousRequest:(NSURLRequest *)request
                          queue:(NSOperationQueue *)queue
              completionHandler:(void (^)(NSURLResponse *, NSData *, NSError *))handler {
    if (isBlockedURL(request.URL)) {
        NSLog(@"[XumodBlock] BLOCKED (sendAsynchronousRequest): %@", request.URL);
        if (handler) {
            NSError *err = [NSError errorWithDomain:NSURLErrorDomain
                                               code:NSURLErrorNotConnectedToInternet
                                           userInfo:@{NSLocalizedDescriptionKey: @"Blocked by Xumod"}];
            [queue addOperationWithBlock:^{ handler(nil, nil, err); }];
        }
        return;
    }
    %orig;
}

- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate {
    if (isBlockedURL(request.URL)) {
        NSLog(@"[XumodBlock] BLOCKED (initWithRequest:delegate:): %@", request.URL);
        return nil;
    }
    return %orig;
}

- (id)initWithRequest:(NSURLRequest *)request
             delegate:(id)delegate
     startImmediately:(BOOL)startImmediately {
    if (isBlockedURL(request.URL)) {
        NSLog(@"[XumodBlock] BLOCKED (initWithRequest:delegate:startImmediately:): %@", request.URL);
        return nil;
    }
    return %orig;
}

%end


// ══════════════════════════════════════════════════════════════════
//  ORIGINAL Unitoreios hooks (unchanged)
// ══════════════════════════════════════════════════════════════════
%hook Unitoreios

- (BOOL)isNetworkAvailable {
    return NO;
}

- (BOOL)canUseCachedSession {
    return YES;
}

- (void)showOfflineNoticeIfNeeded {
    // Suppress offline notice — no %orig
}

- (void)activehack:(NSString *)title message:(NSString *)message font:(UIFont *)font {
    CGFloat screenWidth  = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    CGFloat maxWidth     = screenWidth * 0.75;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, maxWidth, 0)];
    titleLabel.text          = title;
    titleLabel.textAlignment = NSTextAlignmentLeft;
    titleLabel.font          = font;
    titleLabel.textColor     = [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:1.0];
    titleLabel.numberOfLines = 0;
    [titleLabel sizeToFit];

    UILabel *messageLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, maxWidth, 0)];
    messageLabel.text          = message;
    messageLabel.textAlignment = NSTextAlignmentLeft;
    messageLabel.font          = [UIFont fontWithName:@"AvenirNext-Bold" size:10];
    messageLabel.textColor     = [UIColor whiteColor];
    messageLabel.numberOfLines = 0;
    [messageLabel sizeToFit];

    CGFloat rectWidth  = MAX(titleLabel.frame.size.width, messageLabel.frame.size.width) + 60;
    CGFloat rectHeight = titleLabel.frame.size.height + messageLabel.frame.size.height + 16;
    CGFloat rectX      = screenWidth;
    CGFloat rectY      = screenHeight * 0.10;

    UIWindow *mainWindow = [[[UIApplication sharedApplication] delegate] window];

    UIView *rect2 = [[UIView alloc] initWithFrame:CGRectMake(rectX, rectY, 0, rectHeight)];
    rect2.backgroundColor = [UIColor blackColor];
    [mainWindow addSubview:rect2];

    UIView *rect1 = [[UIView alloc] initWithFrame:CGRectMake(rectX, rectY, 0, rectHeight)];
    rect1.backgroundColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:1.0];
    [mainWindow addSubview:rect1];

    [UIView animateWithDuration:0.5 animations:^{
        rect1.frame = CGRectMake(rectX - rectWidth + 0.5, rectY, rectWidth, rectHeight);
        rect2.frame = CGRectMake(rectX - rectWidth + 0.5, rectY, rectWidth, rectHeight);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 delay:0.0 options:0 animations:^{
            rect1.frame = CGRectMake(rectX - rectWidth + 0.5, rectY, screenWidth * 0.005, rectHeight);
        } completion:^(BOOL finished) {
            titleLabel.alpha   = 1;
            messageLabel.alpha = 1;
            [mainWindow addSubview:titleLabel];
            [mainWindow addSubview:messageLabel];
            titleLabel.center   = CGPointMake(rectX - rectWidth / 2 + 12, rectY + rectHeight / 2 - messageLabel.frame.size.height / 2 - 2);
            messageLabel.center = CGPointMake(rectX - rectWidth / 2 + 12, rectY + rectHeight / 2 + titleLabel.frame.size.height / 2 + 2);

            [UIView animateWithDuration:0.5 delay:12.0 options:0 animations:^{
                rect1.frame         = CGRectMake(rectX - rectWidth + 0.5, rectY, rectWidth, rectHeight);
                titleLabel.center   = CGPointMake(rectX + rectWidth / 2 + 12, rectY + rectHeight / 2 - messageLabel.frame.size.height / 2 - 2);
                messageLabel.center = CGPointMake(rectX + rectWidth / 2 + 12, rectY + rectHeight / 2 + titleLabel.frame.size.height / 2 + 2);
            } completion:^(BOOL finished) {
                [UIView animateWithDuration:0.15 delay:0.0 options:0 animations:^{
                    rect1.frame        = CGRectMake(rectX, rectY, 0, rectHeight);
                    rect2.frame        = CGRectMake(rectX, rectY, 0, rectHeight);
                    titleLabel.alpha   = 0;
                    messageLabel.alpha = 0;
                } completion:^(BOOL finished) {
                    [rect1 removeFromSuperview];
                    [rect2 removeFromSuperview];
                    [titleLabel removeFromSuperview];
                    [messageLabel removeFromSuperview];
                }];
            }];
        }];
    }];
}

%end


// ══════════════════════════════════════════════════════════════════
//  Constructor
// ══════════════════════════════════════════════════════════════════
%ctor {
    NSLog(@"[UnitoreiosDebug] ctor fired — hooks active (URL blocker ON for: %@)", kBlockedHost);
    %init;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        showDebugBanner();
    });
}
