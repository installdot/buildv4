#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static NSString *const kTargetHost = @"app.tnspike.com";
static NSString *const kTargetPath = @"/verify_udid";

@interface HookURLProtocol : NSURLProtocol
@end

@implementation HookURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSURL *url = request.URL;
    if (!url) return NO;

    BOOL isTarget =
        [url.host isEqualToString:kTargetHost] &&
        [url.path isEqualToString:kTargetPath];

    if (!isTarget) return NO;

    if ([NSURLProtocol propertyForKey:@"HookHandled" inRequest:request]) {
        return NO;
    }

    NSLog(@"[Hook] ✅ verify_udid request detected");
    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {

    NSMutableURLRequest *req = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"HookHandled" inRequest:req];

    NSData *data = nil;

    // ─────────────────────────────
    // BUILD FULL VIP RESPONSE
    // ─────────────────────────────

    NSDate *now = [NSDate date];
    NSDate *expires = [now dateByAddingTimeInterval:100.0 * 365.25 * 86400.0];

    NSDateComponents *diff =
    [[NSCalendar currentCalendar] components:NSCalendarUnitDay
                                    fromDate:now
                                      toDate:expires
                                     options:0];

    NSInteger days = diff.day;

    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    fmt.locale = [NSLocale currentLocale];          // ✅ device locale
    fmt.timeZone = [NSTimeZone localTimeZone];      // ✅ device timezone

    NSDictionary *json = @{
        @"message" : [NSString stringWithFormat:
                      @"UDID is valid - %ld days remaining", (long)days],

        @"status" : @"active",

        @"activated_at" : [fmt stringFromDate:now],

        @"expires_at" : [fmt stringFromDate:expires],

        @"remaining" : [NSString stringWithFormat:@"%ld days", (long)days],

        @"package_type" : @"VIP",

        @"activation_key" : [NSString stringWithFormat:
                             @"TNK-VIP-%ldD", (long)days],

        @"client_version" : @"2.0.3",

        @"update_notes" : @[
            @"Fixed skill search filter not working",
            @"Added Key Info card in DATA MOD tab",
            @"Improved menu height and layout",
            @"Added Contact button in Data Mod tab"
        ]
    };

    data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];

    NSLog(@"[Hook] 📦 Spoofed Response: %@",
          [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

    // ─────────────────────────────
    // SEND RESPONSE
    // ─────────────────────────────

    NSHTTPURLResponse *response =
        [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                    statusCode:200
                                   HTTPVersion:@"HTTP/1.1"
                                  headerFields:@{
                                      @"Content-Type": @"application/json",
                                      @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)data.length]
                                  }];

    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {}

@end

// ─────────────────────────────────────────
// Register helper
// ─────────────────────────────────────────

static void RegisterProtocol(void) {
    [NSURLProtocol registerClass:[HookURLProtocol class]];
}

// Early load (HIGH PRIORITY)
__attribute__((constructor(101))) static void init_hook(void) {
    RegisterProtocol();
}

// Force into sessions
%hook NSURLSessionConfiguration

- (NSArray *)protocolClasses {
    NSMutableArray *arr = [NSMutableArray arrayWithObject:[HookURLProtocol class]];
    NSArray *orig = %orig;
    if (orig) [arr addObjectsFromArray:orig];
    return arr;
}

%end

// Cover all NSURLSession usage
%hook NSURLSession

+ (NSURLSession *)sharedSession {
    RegisterProtocol();
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    RegisterProtocol();
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    RegisterProtocol();
    return %orig;
}

%end

// NSURLConnection fallback
%hook NSURLConnection

+ (instancetype)connectionWithRequest:(NSURLRequest *)request delegate:(id)delegate {
    RegisterProtocol();
    return %orig;
}

%end

%ctor {
    RegisterProtocol();
}
