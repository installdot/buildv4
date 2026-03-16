#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ============================================================
//  TNSpikeSpoof — redirect intercept
//  When the app calls app.tnspike.com/verify_udid (any port),
//  we silently redirect the request to our own server and
//  forward the real response back to the app.
//  A popup confirms the redirect fired.
// ============================================================

static NSString *const kTargetHost  = @"app.tnspike.com";
static NSString *const kTargetPath  = @"/verify_udid";
static NSString *const kSpoofURL    = @"https://chillysilly.frfrnocap.men/verify_udid.php";

// ── URL match ─────────────────────────────────────────────────
static BOOL IsTargetURL(NSURL *url) {
    if (!url) return NO;
    return [[url.host ?: @""] isEqualToString:kTargetHost] &&
           [[url.path ?: @""] hasPrefix:kTargetPath];
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

// ── Popup (shown after we get a response from our server) ─────
static void ShowSpoofPopup(NSDictionary *resp) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = TopVC();
        if (!vc) return;

        NSString *body = [NSString stringWithFormat:
            @"🔀  Redirected to spoof server\n\n"
             "🟢  Status       :  %@\n"
             "📦  Package    :  %@\n"
             "🔑  Key           :  %@\n"
             "🕐  Activated  :  %@\n"
             "📅  Expires     :  %@\n"
             "⏳  Remaining :  %@",
            resp[@"status"]         ?: @"-",
            resp[@"package_type"]   ?: @"-",
            resp[@"activation_key"] ?: @"-",
            resp[@"activated_at"]   ?: @"-",
            resp[@"expires_at"]     ?: @"-",
            resp[@"remaining"]      ?: @"-"
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

// ── Build redirected NSURLRequest preserving method/body ──────
static NSURLRequest *BuildRedirectedRequest(NSURLRequest *original) {
    NSURL *spoofURL = [NSURL URLWithString:kSpoofURL];

    // Preserve original query string if any
    NSURLComponents *comps = [NSURLComponents componentsWithURL:spoofURL
                                        resolvingAgainstBaseURL:NO];
    NSURLComponents *origComps = [NSURLComponents componentsWithURL:original.URL
                                            resolvingAgainstBaseURL:NO];
    if (origComps.query.length) comps.query = origComps.query;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:comps.URL];
    req.HTTPMethod         = original.HTTPMethod ?: @"GET";
    req.HTTPBody           = original.HTTPBody;
    req.timeoutInterval    = 15.0;

    // Forward original headers except Host
    [original.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        if (![k.lowercaseString isEqualToString:@"host"]) {
            [req setValue:v forHTTPHeaderField:k];
        }
    }];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    return [req copy];
}

// ── Core redirect + forward ───────────────────────────────────
// Fetches our spoof server and calls the original completion handler
// with the spoofed data, making the app think it talked to TNSpike.
static void PerformRedirect(NSURL *originalURL,
                            NSURLRequest *originalRequest,
                            void (^handler)(NSData *, NSURLResponse *, NSError *)) {

    NSLog(@"[TNSpikeSpoof] 🔀 Redirecting %@ → %@", originalURL, kSpoofURL);

    NSURLRequest *redirected = BuildRedirectedRequest(
        originalRequest ?: [NSURLRequest requestWithURL:originalURL]
    );

    NSURLSession *session = [NSURLSession sessionWithConfiguration:
                             [NSURLSessionConfiguration ephemeralSessionConfiguration]];

    NSURLSessionDataTask *task =
        [session dataTaskWithRequest:redirected
                   completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

        if (error || !data) {
            NSLog(@"[TNSpikeSpoof] ❌ Spoof server error: %@", error);
            // Fall back: report error to original handler
            if (handler) handler(nil, nil, error);
            return;
        }

        // Swap the response URL back to the original so the app isn't confused
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        NSHTTPURLResponse *maskedResp =
            [[NSHTTPURLResponse alloc] initWithURL:originalURL
                                        statusCode:httpResp.statusCode
                                       HTTPVersion:@"HTTP/1.1"
                                      headerFields:httpResp.allHeaderFields];

        if (handler) handler(data, maskedResp, nil);

        // Show popup with parsed JSON
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data
                                                             options:0
                                                               error:nil];
        if (dict) ShowSpoofPopup(dict);

        NSLog(@"[TNSpikeSpoof] ✅ Spoof response delivered (%lu bytes)", (unsigned long)data.length);
    }];

    [task resume];
}

// ============================================================
//  HOOKS
// ============================================================

%hook NSURLSession

// ── (1) dataTaskWithRequest:completionHandler: ───────────────
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    if (!IsTargetURL(request.URL) || !handler) return %orig;

    NSURL *originalURL = request.URL;
    PerformRedirect(originalURL, request, handler);

    // Return a dummy suspended task — the real call is handled above
    NSURLRequest *dummyReq = [NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]];
    return %orig(dummyReq, nil);
}

// ── (2) dataTaskWithURL:completionHandler: ───────────────────
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    if (!IsTargetURL(url) || !handler) return %orig;

    PerformRedirect(url, nil, handler);

    NSURL *dummyURL = [NSURL URLWithString:@"about:blank"];
    return %orig(dummyURL, nil);
}

// ── (3) dataTaskWithRequest: (delegate-based) ────────────────
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    if (!IsTargetURL(request.URL)) return %orig;
    NSLog(@"[TNSpikeSpoof] 🎯 Intercepted delegate-req: %@", request.URL);
    NSURLRequest *dummyReq = [NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]];
    return %orig(dummyReq);
}

// ── (4) dataTaskWithURL: (delegate-based) ────────────────────
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url {
    if (!IsTargetURL(url)) return %orig;
    NSLog(@"[TNSpikeSpoof] 🎯 Intercepted delegate-url: %@", url);
    return %orig([NSURL URLWithString:@"about:blank"]);
}

%end

// ── Constructor ───────────────────────────────────────────────
%ctor {
    @autoreleasepool {
        NSLog(@"[TNSpikeSpoof] 🚀 Loaded — redirecting %@%@ → %@",
              kTargetHost, kTargetPath, kSpoofURL);
    }
}

%dtor {
    NSLog(@"[TNSpikeSpoof] 🛑 Unloaded");
}
