#import <Foundation/Foundation.h>

static NSString *const kVerifyHost = @"floraflower.life";
static NSString *const kVerifyPath = @"/test";
static BOOL gUnloaded = NO;

static NSData *bodyFromRequest(NSURLRequest *req) {
    if (req.HTTPBody) return req.HTTPBody;
    NSInputStream *s = req.HTTPBodyStream;
    if (!s) return nil;
    NSMutableData *d = [NSMutableData data];
    [s open];
    uint8_t buf[1024]; NSInteger len;
    while ((len = [s read:buf maxLength:sizeof(buf)]) > 0)
        [d appendBytes:buf length:len];
    [s close];
    return d;
}

static BOOL isVerifyRequest(NSURLRequest *req) {
    if (gUnloaded) return NO;
    NSURL *url = req.URL;
    return [url.host isEqualToString:kVerifyHost] &&
           [url.path isEqualToString:kVerifyPath] &&
           [req.HTTPMethod.uppercaseString isEqualToString:@"POST"];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!gUnloaded && isVerifyRequest(request) && completionHandler) {
        NSData *body = bodyFromRequest(request);
        NSString *keyValue = @"unknown";

        if (body) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
            NSString *k = [json isKindOfClass:[NSDictionary class]] ? json[@"key"] : nil;
            if (k.length > 0) keyValue = k;
        }

        NSDictionary *fakeJSON = @{
            @"success": @YES,
            @"code":    @0,
            @"username": keyValue,
            @"test":    @"oke"
        };

        NSData *fakeData = [NSJSONSerialization dataWithJSONObject:fakeJSON options:0 error:nil];
        NSHTTPURLResponse *fakeResp =
            [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                        statusCode:200
                                       HTTPVersion:@"HTTP/1.1"
                                      headerFields:@{@"Content-Type": @"application/json"}];

        completionHandler(fakeData, fakeResp, nil);

        // One-shot: all future calls fall through as if hook never existed
        gUnloaded = YES;

        NSURLSession *dummy = [NSURLSession sessionWithConfiguration:
            [NSURLSessionConfiguration ephemeralSessionConfiguration]];
        NSURLSessionDataTask *task = [dummy dataTaskWithURL:request.URL];
        [task cancel];
        return task;
    }

    return %orig;
}

%end

%ctor {
    %init;
}
