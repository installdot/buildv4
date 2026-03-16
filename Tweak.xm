#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ============================================================
//  TNSpikeSpoof — NSURLSession-level intercept
//  Hooks dataTask methods directly so the request never reaches
//  the network. NSURLProtocol alone does NOT intercept modern
//  NSURLSession traffic.
// ============================================================

static NSString *const kTargetHost = @"app.tnspike.com";
static NSString *const kTargetPath = @"/verify_udid";

// ── URL match check ───────────────────────────────────────────
static BOOL IsTargetURL(NSURL *url) {
    if (!url) return NO;
    NSString *host = url.host ?: @"";
    NSString *path = url.path ?: @"";
    return [host isEqualToString:kTargetHost] &&
           [path hasPrefix:kTargetPath];
}

// ── Dynamic spoofed JSON ──────────────────────────────────────
static NSData *BuildSpoofedJSON(void) {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    fmt.timeZone   = [NSTimeZone timeZoneWithName:@"UTC"];

    NSDate *now     = [NSDate date];
    NSDate *expires = [now dateByAddingTimeInterval:7.0 * 24 * 60 * 60];

    NSDictionary *payload = @{
        @"message"        : @"UDID is valid - 7 days remaining",
        @"status"         : @"active",
        @"activated_at"   : [fmt stringFromDate:now],
        @"expires_at"     : [fmt stringFromDate:expires],
        @"remaining"      : @"7 days",
        @"package_type"   : @"BASIC",
        @"activation_key" : @"TNK-7D-CEBADEDF",
        @"client_version" : @"2.0.2",
        @"update_notes"   : @[
            @"Fixed skill search filter not working",
            @"Added Key Info card in DATA MOD tab",
            @"Improved menu height and layout",
            @"Added Contact button in Data Mod tab"
        ]
    };

    return [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
}

// ── Fake HTTP 200 response ────────────────────────────────────
static NSHTTPURLResponse *BuildFakeResponse(NSURL *url, NSUInteger length) {
    return [[NSHTTPURLResponse alloc] initWithURL:url
                                       statusCode:200
                                      HTTPVersion:@"HTTP/1.1"
                                     headerFields:@{
                                         @"Content-Type"   : @"application/json; charset=utf-8",
                                         @"Content-Length" : [@(length) stringValue],
                                         @"X-Spoofed-By"   : @"TNSpikeSpoof"
                                     }];
}

// ── Top view controller ───────────────────────────────────────
static UIViewController *TopVC(void) {
    UIViewController *root = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { root = w.rootViewController; break; }
            }
            if (root) break;
        }
    }
    if (!root) root = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}

// ── Popup ─────────────────────────────────────────────────────
static void ShowSpoofPopup(NSDictionary *resp) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = TopVC();
        if (!vc) return;

        NSString *body = [NSString stringWithFormat:
            @"🟢  Status       :  %@\n"
             "📦  Package    :  %@\n"
             "🔑  Key           :  %@\n"
             "🕐  Activated  :  %@\n"
             "📅  Expires     :  %@\n"
             "⏳  Remaining :  %@",
            resp[@"status"],
            resp[@"package_type"],
            resp[@"activation_key"],
            resp[@"activated_at"],
            resp[@"expires_at"],
            resp[@"remaining"]
        ];

        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"🛡️ TNSpike — Spoofed"
                                                message:body
                                         preferredStyle:UIAlertControllerStyleAlert];

        @try { [alert setValue:[UIColor systemGreenColor] forKey:@"titleTextColor"]; }
        @catch (...) {}

        [alert addAction:[UIAlertAction actionWithTitle:@"OK  ✓"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];

        [vc presentViewController:alert animated:YES completion:nil];
    });
}

static void ShowSpoofPopupFromData(NSData *json) {
    NSDictionary *d = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    if (d) ShowSpoofPopup(d);
}

// ============================================================
//  HOOKS
// ============================================================

%hook NSURLSession

// ── (1) dataTaskWithRequest:completionHandler: ───────────────
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    if (!IsTargetURL(request.URL) || !handler) return %orig;

    NSLog(@"[TNSpikeSpoof] 🎯 Intercepted (req+handler): %@", request.URL);

    NSData            *json     = BuildSpoofedJSON();
    NSHTTPURLResponse *fakeResp = BuildFakeResponse(request.URL, json.length);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        handler(json, fakeResp, nil);
        ShowSpoofPopupFromData(json);
    });

    // Dummy NSURLRequest for the real call — handler is nil so nothing fires
    NSURLRequest *dummyReq = [NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]];
    return %orig(dummyReq, nil);
}

// ── (2) dataTaskWithURL:completionHandler: ───────────────────
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    if (!IsTargetURL(url) || !handler) return %orig;

    NSLog(@"[TNSpikeSpoof] 🎯 Intercepted (url+handler): %@", url);

    NSData            *json     = BuildSpoofedJSON();
    NSHTTPURLResponse *fakeResp = BuildFakeResponse(url, json.length);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        handler(json, fakeResp, nil);
        ShowSpoofPopupFromData(json);
    });

    // Must pass NSURL* here — not NSURLRequest*
    NSURL *dummyURL = [NSURL URLWithString:@"about:blank"];
    return %orig(dummyURL, nil);
}

// ── (3) dataTaskWithRequest: (delegate-based) ────────────────
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    if (!IsTargetURL(request.URL)) return %orig;
    NSLog(@"[TNSpikeSpoof] 🎯 Intercepted (req, delegate): %@", request.URL);
    NSURLRequest *dummyReq = [NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]];
    return %orig(dummyReq);
}

// ── (4) dataTaskWithURL: (delegate-based) ────────────────────
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url {
    if (!IsTargetURL(url)) return %orig;
    NSLog(@"[TNSpikeSpoof] 🎯 Intercepted (url, delegate): %@", url);
    return %orig([NSURL URLWithString:@"about:blank"]);
}

%end

// ── Constructor ───────────────────────────────────────────────
%ctor {
    @autoreleasepool {
        NSLog(@"[TNSpikeSpoof] 🚀 Loaded — hooking NSURLSession for https://%@%@",
              kTargetHost, kTargetPath);
    }
}

%dtor {
    NSLog(@"[TNSpikeSpoof] 🛑 Unloaded");
}
