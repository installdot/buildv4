#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static NSString * const SKYLogFileName = @"sky_http.log";

static NSString *SKYDocumentsPath(void) {
    NSArray *paths =
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                            NSUserDomainMask,
                                            YES);

    NSString *documents =
        paths.firstObject ?: NSTemporaryDirectory();

    return [documents stringByAppendingPathComponent:SKYLogFileName];
}

static NSString *SKYTimestamp(void) {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale =
            [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    });

    return [formatter stringFromDate:[NSDate date]];
}

static NSString *SKYDataText(NSData *data) {
    if (!data || data.length == 0) {
        return @"<empty>";
    }

    NSString *utf8 =
        [[NSString alloc] initWithData:data
                               encoding:NSUTF8StringEncoding];

    if (utf8) {
        return utf8;
    }

    return [NSString stringWithFormat:
        @"<binary data: %lu bytes>\nBase64:\n%@",
        (unsigned long)data.length,
        [data base64EncodedStringWithOptions:0]];
}

static void SKYWriteLog(NSString *text) {
    @autoreleasepool {
        NSString *line =
            [NSString stringWithFormat:
                @"[%@] %@\n",
                SKYTimestamp(),
                text];

        @synchronized([NSObject class]) {
            NSString *path = SKYDocumentsPath();

            NSFileManager *fm = [NSFileManager defaultManager];

            if (![fm fileExistsAtPath:path]) {
                [fm createFileAtPath:path
                            contents:nil
                          attributes:nil];
            }

            NSFileHandle *handle =
                [NSFileHandle fileHandleForWritingAtPath:path];

            if (!handle) {
                NSLog(@"[SkyHTTP] Cannot open log file: %@", path);
                return;
            }

            @try {
                [handle seekToEndOfFile];

                NSData *data =
                    [line dataUsingEncoding:NSUTF8StringEncoding];

                [handle writeData:data];
                [handle synchronizeFile];
            }
            @catch (NSException *exception) {
                NSLog(@"[SkyHTTP] Log write exception: %@", exception);
            }
            @finally {
                [handle closeFile];
            }
        }
    }
}

static void SKYLogRequest(NSURLRequest *request,
                          NSData *overrideBody,
                          NSString *source) {
    @autoreleasepool {
        if (!request) {
            SKYWriteLog(
                [NSString stringWithFormat:
                    @"REQUEST source=%@ request=<nil>",
                    source ?: @"unknown"]);
            return;
        }

        NSURL *url = request.URL;
        NSString *method = request.HTTPMethod ?: @"<unknown>";
        NSDictionary *headers = request.allHTTPHeaderFields ?: @{};
        NSData *body = overrideBody ?: request.HTTPBody;

        NSString *log =
            [NSString stringWithFormat:
                @"\n"
                 "========== REQUEST ==========\n"
                 "Source: %@\n"
                 "URL: %@\n"
                 "Method: %@\n"
                 "Headers: %@\n"
                 "Body length: %lu\n"
                 "Body:\n%@\n"
                 "==============================\n",
                source ?: @"unknown",
                url.absoluteString ?: @"<no URL>",
                method,
                headers,
                (unsigned long)body.length,
                SKYDataText(body)];

        SKYWriteLog(log);
    }
}

static void SKYLogResponse(NSData *data,
                           NSURLResponse *response,
                           NSError *error,
                           NSString *source) {
    @autoreleasepool {
        NSHTTPURLResponse *httpResponse = nil;

        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            httpResponse = (NSHTTPURLResponse *)response;
        }

        NSString *url = response.URL.absoluteString ?: @"<no URL>";

        NSString *log =
            [NSString stringWithFormat:
                @"\n"
                 "========== RESPONSE ==========\n"
                 "Source: %@\n"
                 "URL: %@\n"
                 "Status code: %ld\n"
                 "Headers: %@\n"
                 "Error: %@\n"
                 "Body length: %lu\n"
                 "Body:\n%@\n"
                 "===============================\n",
                source ?: @"unknown",
                url,
                (long)httpResponse.statusCode,
                httpResponse.allHeaderFields ?: @{},
                error ?: @"<none>",
                (unsigned long)data.length,
                SKYDataText(data)];

        SKYWriteLog(log);
    }
}

static void SKYLogUploadFile(NSURL *fileURL,
                             NSURLRequest *request,
                             NSString *source) {
    @autoreleasepool {
        NSError *error = nil;

        NSData *body =
            [NSData dataWithContentsOfURL:fileURL
                                   options:NSDataReadingMappedIfSafe
                                     error:&error];

        if (error) {
            SKYWriteLog(
                [NSString stringWithFormat:
                    @"UPLOAD FILE READ ERROR\n"
                     "Source: %@\n"
                     "File: %@\n"
                     "Error: %@\n",
                    source,
                    fileURL,
                    error]);
        }

        SKYLogRequest(request, body, source);
    }
}

%hook NSURLSessionTask

- (void)resume {
    @autoreleasepool {
        NSURLRequest *request =
            self.currentRequest ?: self.originalRequest;

        SKYLogRequest(request, nil, @"NSURLSessionTask resume");
    }

    %orig;
}

%end

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *,
                                                        NSURLResponse *,
                                                        NSError *))completionHandler {
    SKYLogRequest(request, nil, @"dataTaskWithRequest");

    void (^wrappedCompletion)(NSData *,
                              NSURLResponse *,
                              NSError *) =
        ^(NSData *data,
          NSURLResponse *response,
          NSError *error) {
            SKYLogResponse(data,
                           response,
                           error,
                           @"dataTask completion");

            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };

    return %orig(request, wrappedCompletion);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                          fromData:(NSData *)bodyData
                                 completionHandler:(void (^)(NSData *,
                                                             NSURLResponse *,
                                                             NSError *))completionHandler {
    SKYLogRequest(request,
                  bodyData,
                  @"uploadTaskWithRequest fromData");

    void (^wrappedCompletion)(NSData *,
                              NSURLResponse *,
                              NSError *) =
        ^(NSData *data,
          NSURLResponse *response,
          NSError *error) {
            SKYLogResponse(data,
                           response,
                           error,
                           @"uploadTask completion");

            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };

    return %orig(request, bodyData, wrappedCompletion);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                          fromFile:(NSURL *)fileURL
                                 completionHandler:(void (^)(NSData *,
                                                             NSURLResponse *,
                                                             NSError *))completionHandler {
    SKYLogUploadFile(fileURL,
                     request,
                     @"uploadTaskWithRequest fromFile");

    void (^wrappedCompletion)(NSData *,
                              NSURLResponse *,
                              NSError *) =
        ^(NSData *data,
          NSURLResponse *response,
          NSError *error) {
            SKYLogResponse(data,
                           response,
                           error,
                           @"uploadTask file completion");

            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };

    return %orig(request, fileURL, wrappedCompletion);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *,
                                                    NSURLResponse *,
                                                    NSError *))completionHandler {
    NSURLRequest *request =
        [NSURLRequest requestWithURL:url];

    SKYLogRequest(request,
                  nil,
                  @"dataTaskWithURL");

    void (^wrappedCompletion)(NSData *,
                              NSURLResponse *,
                              NSError *) =
        ^(NSData *data,
          NSURLResponse *response,
          NSError *error) {
            SKYLogResponse(data,
                           response,
                           error,
                           @"dataTask URL completion");

            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };

    return %orig(url, wrappedCompletion);
}

%end

%ctor {
    @autoreleasepool {
        NSString *path = SKYDocumentsPath();

        NSFileManager *fm = [NSFileManager defaultManager];

        if (![fm fileExistsAtPath:path]) {
            [fm createFileAtPath:path
                        contents:nil
                      attributes:nil];
        }

        SKYWriteLog(
            @"========== tweak loaded; full HTTP logging enabled ==========");
    }
}
