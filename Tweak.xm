#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ==============================
// EDIT RESPONSE HERE
// ==============================

static NSString *FAKE_RESPONSE = @"{\n"
@"  \"status\": \"active\",\n"
@"  \"code\": \"ok\",\n"
@"  \"message\": \"Crack By Mochi.\",\n"
@"  \"key_code\": \"Mochi-120B4AFE\",\n"
@"  \"expired_at\": \"2036-08-15 16:09:53\",\n"
@"  \"seconds_left\": 854699999,\n"
@"  \"duration_days\": 99999,\n"
@"  \"mod_type\": \"\"\n"
@"}";

// ==============================

@interface FakeAPIProtocol : NSURLProtocol
@end

@implementation FakeAPIProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    return [request.URL.absoluteString isEqualToString:@"https://getuid.vip/check_key.php"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (void)startLoading
{
    NSLog(@"[FakeAPI] Blocked and Mocked: %@", self.request.URL.absoluteString);

    NSData *data = [FAKE_RESPONSE dataUsingEncoding:NSUTF8StringEncoding];

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                              statusCode:200
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{
                                                                @"Content-Type": @"application/json",
                                                                @"Access-Control-Allow-Origin": @"*"
                                                            }];

    [self.client URLProtocol:self
          didReceiveResponse:response
          cacheStoragePolicy:NSURLCacheStorageNotAllowed];

    [self.client URLProtocol:self didLoadData:data];

    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading
{
}

@end

// ==============================
// Hook NSURLSession to intercept all modern API calls
// ==============================

%hook NSURLSessionConfiguration

+ (NSURLSessionConfiguration *)defaultSessionConfiguration
{
    NSURLSessionConfiguration *config = %orig;
    NSMutableArray *protocols = [config.protocolClasses mutableCopy] ?: [NSMutableArray array];
    if (![protocols containsObject:[FakeAPIProtocol class]]) {
        [protocols insertObject:[FakeAPIProtocol class] atIndex:0];
        config.protocolClasses = protocols;
    }
    return config;
}

+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration
{
    NSURLSessionConfiguration *config = %orig;
    NSMutableArray *protocols = [config.protocolClasses mutableCopy] ?: [NSMutableArray array];
    if (![protocols containsObject:[FakeAPIProtocol class]]) {
        [protocols insertObject:[FakeAPIProtocol class] atIndex:0];
        config.protocolClasses = protocols;
    }
    return config;
}

%end

%ctor
{
    @autoreleasepool {
        [NSURLProtocol registerClass:[FakeAPIProtocol class]];
        NSLog(@"[FakeAPI] Hook Loaded");
    }
}
