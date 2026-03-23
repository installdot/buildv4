#import <Foundation/Foundation.h>

static NSString *const kTargetURL = @"https://apiunitoreios.site/Cheack.php?key=FREEFIRE-DAY-meCJeXGpKanR8ykG&uuid=D6C95F10-E5C1-40D8-BF40-72D9ADBAA538&hash=unitoreios-bygDhw6QHLtrTeVIPqMY0WuZScs5X7UG61a006ffa0b610067a4422d53ed59b5c";
static NSString *const kReplacementURL = @"https://chillysilly.frfrnocap.men/bypassvip.php";

@interface HookURLProtocol : NSURLProtocol
@end

@implementation HookURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *urlString = request.URL.absoluteString;
    if ([urlString isEqualToString:kTargetURL]) {
        if ([NSURLProtocol propertyForKey:@"HookHandled" inRequest:request]) {
            return NO;
        }
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSURL *replacementURL = [NSURL URLWithString:kReplacementURL];
    NSMutableURLRequest *newRequest = [NSMutableURLRequest requestWithURL:replacementURL];
    newRequest.HTTPMethod = self.request.HTTPMethod;
    newRequest.allHTTPHeaderFields = self.request.allHTTPHeaderFields;

    [NSURLProtocol setProperty:@YES forKey:@"HookHandled" inRequest:newRequest];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:newRequest
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                [self.client URLProtocol:self didFailWithError:error];
                return;
            }

            NSHTTPURLResponse *origResponse = (NSHTTPURLResponse *)response;
            NSHTTPURLResponse *spoofed = [[NSHTTPURLResponse alloc]
                initWithURL:self.request.URL
                statusCode:origResponse.statusCode
               HTTPVersion:nil
              headerFields:origResponse.allHeaderFields];

            [self.client URLProtocol:self didReceiveResponse:spoofed
                  cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            [self.client URLProtocol:self didLoadData:data];
            [self.client URLProtocolDidFinishLoading:self];
        }];
    [task resume];
}

- (void)stopLoading {}

@end

// ─── High-priority constructor (101 = earliest safe priority) ──────────────

__attribute__((constructor(101))) static void RegisterProtocolEarly(void) {
    [NSURLProtocol registerClass:[HookURLProtocol class]];
}

// ─── Hook NSURLSession as a safety net ────────────────────────────────────

%hook NSURLSession

+ (NSURLSession *)sharedSession {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSURLProtocol registerClass:[HookURLProtocol class]];
    });
    return %orig;
}

%end

// ─── Logos fallback ctor ──────────────────────────────────────────────────

%ctor {
    [NSURLProtocol registerClass:[HookURLProtocol class]];
}
