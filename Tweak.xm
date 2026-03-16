#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ============================================================
//  TNSpikeSpoof — network intercept for app.tnspike.com UDID
//  Spoofs /verify_udid response with a valid 7-day activation.
//  Dates are always computed at intercept-time (always +7 days).
// ============================================================

static NSString *const kTargetHost = @"app.tnspike.com";
static NSString *const kTargetPath = @"/verify_udid";
static NSString *const kHandledKey = @"TNSpikeHandled";

// ── Dynamic response builder ─────────────────────────────────
// activated_at = NOW  |  expires_at = NOW + 7 days
// Both values recalculate on every intercepted request.
static NSDictionary *BuildSpoofedResponse(void) {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    fmt.timeZone   = [NSTimeZone timeZoneWithName:@"UTC"];

    NSDate *now     = [NSDate date];
    NSDate *expires = [now dateByAddingTimeInterval:7.0 * 24 * 60 * 60];

    return @{
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
}

// ── Top-most presented view controller helper ─────────────────
static UIViewController *TopViewController(void) {
    UIViewController *root = nil;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) { root = w.rootViewController; break; }
            }
            if (root) break;
        }
    }
    if (!root) root = [UIApplication sharedApplication].keyWindow.rootViewController;

    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}

// ── Custom popup ─────────────────────────────────────────────
static void ShowSpoofPopup(NSDictionary *resp) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = TopViewController();
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
        NSLog(@"[TNSpikeSpoof] ✅ Popup shown — expires %@", resp[@"expires_at"]);
    });
}

// ── NSURLProtocol subclass ────────────────────────────────────
@interface TNSpikeURLProtocol : NSURLProtocol
@end

@implementation TNSpikeURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:kHandledKey inRequest:request]) return NO;

    NSString *host = request.URL.host ?: @"";
    NSString *path = request.URL.path ?: @"";

    BOOL match = [host isEqualToString:kTargetHost] &&
                 [path hasPrefix:kTargetPath];

    if (match) NSLog(@"[TNSpikeSpoof] 🎯 Intercepted: %@", request.URL.absoluteString);
    return match;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b {
    return NO;
}

- (void)startLoading {
    NSLog(@"[TNSpikeSpoof] 🔄 Building spoofed payload…");

    NSDictionary *payload = BuildSpoofedResponse();

    NSError *err  = nil;
    NSData  *json = [NSJSONSerialization dataWithJSONObject:payload
                                                    options:NSJSONWritingPrettyPrinted
                                                      error:&err];
    if (!json || err) {
        NSLog(@"[TNSpikeSpoof] ❌ JSON error: %@", err);
        [self.client URLProtocol:self didFailWithError:
            err ?: [NSError errorWithDomain:@"TNSpikeSpoof" code:-1 userInfo:nil]];
        return;
    }

    NSHTTPURLResponse *fakeResp =
        [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                    statusCode:200
                                   HTTPVersion:@"HTTP/1.1"
                                  headerFields:@{
                                      @"Content-Type"   : @"application/json; charset=utf-8",
                                      @"Content-Length" : [@(json.length) stringValue],
                                      @"X-Spoofed-By"   : @"TNSpikeSpoof"
                                  }];

    [self.client URLProtocol:self didReceiveResponse:fakeResp
          cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:json];
    [self.client URLProtocolDidFinishLoading:self];

    ShowSpoofPopup(payload);
}

- (void)stopLoading {
    // No real network request was made; nothing to cancel.
}

@end

// ── Hook NSURLSessionConfiguration to inject protocol into sessions ──
%hook NSURLSessionConfiguration

- (void)setProtocolClasses:(NSArray *)protocolClasses {
    NSMutableArray *patched = [NSMutableArray arrayWithObject:[TNSpikeURLProtocol class]];
    if (protocolClasses) [patched addObjectsFromArray:protocolClasses];
    %orig(patched);
}

%end

// ── Constructor / Destructor ──────────────────────────────────
%ctor {
    @autoreleasepool {
        [NSURLProtocol registerClass:[TNSpikeURLProtocol class]];
        NSLog(@"[TNSpikeSpoof] 🚀 Loaded — intercepting https://%@%@",
              kTargetHost, kTargetPath);
    }
}

%dtor {
    [NSURLProtocol unregisterClass:[TNSpikeURLProtocol class]];
    NSLog(@"[TNSpikeSpoof] 🛑 Unloaded");
}
