#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <zlib.h>
// ============================================================
//  TNSpikeSpoof — redirect intercept
//  Redirects app.tnspike.com/verify_udid to our spoof server.
// ============================================================

static NSString *const kTargetHost = @"app.tnspike.com";
static NSString *const kTargetPath = @"/verify_udid";
static NSString *const kSpoofURL   = @"https://chillysilly.frfrnocap.men/verify_udid.php";

// ── URL match — NO ternary inside [] (Logos preprocessor bug) ─
static BOOL IsTargetURL(NSURL *url) {
    if (!url) return NO;
    NSString *host = url.host ? url.host : @"";
    NSString *path = url.path ? url.path : @"";
    return [host isEqualToString:kTargetHost] &&
           [path hasPrefix:kTargetPath];
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

        NSString *status  = resp[@"status"]         ? resp[@"status"]         : @"-";
        NSString *pkg     = resp[@"package_type"]   ? resp[@"package_type"]   : @"-";
        NSString *key     = resp[@"activation_key"] ? resp[@"activation_key"] : @"-";
        NSString *actAt   = resp[@"activated_at"]   ? resp[@"activated_at"]   : @"-";
        NSString *expAt   = resp[@"expires_at"]     ? resp[@"expires_at"]     : @"-";
        NSString *remain  = resp[@"remaining"]      ? resp[@"remaining"]      : @"-";

        NSString *body = [NSString stringWithFormat:
            @"🔀  Redirected to spoof server\n\n"
             "🟢  Status       :  %@\n"
             "📦  Package    :  %@\n"
             "🔑  Key           :  %@\n"
             "🕐  Activated  :  %@\n"
             "📅  Expires     :  %@\n"
             "⏳  Remaining :  %@",
            status, pkg, key, actAt, expAt, remain
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

// ── Build redirected request ──────────────────────────────────
static NSURLRequest *BuildRedirectedRequest(NSURLRequest *original, NSURL *originalURL) {
    NSURL *spoofURL = [NSURL URLWithString:kSpoofURL];

    NSURLComponents *comps = [NSURLComponents componentsWithURL:spoofURL
                                        resolvingAgainstBaseURL:NO];
    NSURLComponents *origComps = [NSURLComponents componentsWithURL:originalURL
                                            resolvingAgainstBaseURL:NO];
    if (origComps.query.length) comps.query = origComps.query;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:comps.URL];
    req.timeoutInterval = 15.0;

    if (original) {
        NSString *method = original.HTTPMethod;
        req.HTTPMethod = method ? method : @"GET";
        req.HTTPBody   = original.HTTPBody;

        NSDictionary *hdrs = original.allHTTPHeaderFields;
        if (hdrs) {
            [hdrs enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
                NSString *lower = [k lowercaseString];
                if (![lower isEqualToString:@"host"]) {
                    [req setValue:v forHTTPHeaderField:k];
                }
            }];
        }
    } else {
        req.HTTPMethod = @"GET";
    }

    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    return [req copy];
}

// ── Core redirect ─────────────────────────────────────────────
static void PerformRedirect(NSURL *originalURL,
                            NSURLRequest *originalRequest,
                            void (^handler)(NSData *, NSURLResponse *, NSError *)) {

    NSLog(@"[TNSpikeSpoof] 🔀 Redirecting %@ -> %@", originalURL, kSpoofURL);

    NSURLRequest *redirected = BuildRedirectedRequest(originalRequest, originalURL);

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];

    NSURLSessionDataTask *task =
        [session dataTaskWithRequest:redirected
                   completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

        if (error || !data) {
            NSLog(@"[TNSpikeSpoof] ❌ Spoof server error: %@", error);
            if (handler) handler(nil, nil, error);
            return;
        }

        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        NSHTTPURLResponse *maskedResp =
            [[NSHTTPURLResponse alloc] initWithURL:originalURL
                                        statusCode:httpResp.statusCode
                                       HTTPVersion:@"HTTP/1.1"
                                      headerFields:httpResp.allHeaderFields];

        if (handler) handler(data, maskedResp, nil);

        // Decompress gzip before parsing for popup
        NSData *jsonData = data;
        NSString *enc = httpResp.allHeaderFields[@"Content-Encoding"];
        if (enc && [enc rangeOfString:@"gzip" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            NSMutableData *decompressed = [NSMutableData dataWithLength:data.length * 4];
            z_stream strm;
            strm.zalloc    = Z_NULL;
            strm.zfree     = Z_NULL;
            strm.opaque    = Z_NULL;
            strm.avail_in  = (uInt)data.length;
            strm.next_in   = (Bytef *)data.bytes;
            strm.avail_out = (uInt)decompressed.length;
            strm.next_out  = (Bytef *)decompressed.mutableBytes;

            if (inflateInit2(&strm, 16 + MAX_WBITS) == Z_OK) {
                int ret = inflate(&strm, Z_FINISH);
                if (ret == Z_STREAM_END) {
                    decompressed.length = strm.total_out;
                    jsonData = decompressed;
                }
                inflateEnd(&strm);
            }
        }

        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        if (dict) ShowSpoofPopup(dict);

        NSLog(@"[TNSpikeSpoof] ✅ Delivered %lu bytes", (unsigned long)data.length);
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

// ── (3) dataTaskWithRequest: (delegate) ──────────────────────
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    if (!IsTargetURL(request.URL)) return %orig;
    NSLog(@"[TNSpikeSpoof] 🎯 delegate-req: %@", request.URL);
    NSURLRequest *dummyReq = [NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]];
    return %orig(dummyReq);
}

// ── (4) dataTaskWithURL: (delegate) ──────────────────────────
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url {
    if (!IsTargetURL(url)) return %orig;
    NSLog(@"[TNSpikeSpoof] 🎯 delegate-url: %@", url);
    return %orig([NSURL URLWithString:@"about:blank"]);
}

%end

// ── Constructor ───────────────────────────────────────────────
%ctor {
    @autoreleasepool {
        NSLog(@"[TNSpikeSpoof] 🚀 Loaded — %@%@ -> %@",
              kTargetHost, kTargetPath, kSpoofURL);
    }
}

%dtor {
    NSLog(@"[TNSpikeSpoof] 🛑 Unloaded");
}
