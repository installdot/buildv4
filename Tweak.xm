#import <Foundation/Foundation.h>
#import <Security/SecureTransport.h>

static NSString * const SKYLogFileName = @"sky_http.log";

#pragma mark - File logging

static NSString *SKYDocumentsLogPath(void) {
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

static void SKYWriteLog(NSString *text) {
    @autoreleasepool {
        if (!text) {
            return;
        }

        NSString *line =
            [NSString stringWithFormat:@"[%@] %@\n",
                                       SKYTimestamp(),
                                       text];

        @synchronized([NSObject class]) {
            NSString *path = SKYDocumentsLogPath();

            NSFileManager *fileManager =
                [NSFileManager defaultManager];

            if (![fileManager fileExistsAtPath:path]) {
                [fileManager createFileAtPath:path
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

#pragma mark - Data formatting

static NSString *SKYDataDescription(NSData *data) {
    if (!data || data.length == 0) {
        return @"<empty>";
    }

    NSString *text =
        [[NSString alloc] initWithData:data
                               encoding:NSUTF8StringEncoding];

    if (text) {
        return text;
    }

    return [NSString stringWithFormat:
        @"<binary data: %lu bytes>\n"
         "Base64:\n%@",
        (unsigned long)data.length,
        [data base64EncodedStringWithOptions:0]];
}

#pragma mark - Request logging

static void SKYLogRequest(NSURLRequest *request,
                          NSData *overrideBody,
                          NSString *source) {
    @autoreleasepool {
        if (!request) {
            NSString *message =
                [NSString stringWithFormat:
                    @"\n"
                     "========== REQUEST ==========\n"
                     "Source: %@\n"
                     "Request: <nil>\n"
                     "==============================\n",
                    source ?: @"unknown"];

            SKYWriteLog(message);
            return;
        }

        NSURL *url = request.URL;
        NSString *method = request.HTTPMethod ?: @"<unknown>";
        NSDictionary *headers =
            request.allHTTPHeaderFields ?: @{};
        NSData *body =
            overrideBody ?: request.HTTPBody;

        NSString *message =
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
                SKYDataDescription(body)];

        SKYWriteLog(message);
    }
}

#pragma mark - Response logging

static void SKYLogResponse(NSData *data,
                           NSURLResponse *response,
                           NSError *error,
                           NSString *source) {
    @autoreleasepool {
        NSHTTPURLResponse *httpResponse = nil;

        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            httpResponse = (NSHTTPURLResponse *)response;
        }

        NSString *url =
            response.URL.absoluteString ?: @"<no URL>";

        NSString *message =
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
                SKYDataDescription(data)];

        SKYWriteLog(message);
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
            NSString *message =
                [NSString stringWithFormat:
                    @"\n"
                     "========== UPLOAD FILE ERROR ==========\n"
                     "Source: %@\n"
                     "File: %@\n"
                     "Error: %@\n"
                     "========================================\n",
                    source ?: @"unknown",
                    fileURL,
                    error];

            SKYWriteLog(message);
        }

        SKYLogRequest(request, body, source);
    }
}

#pragma mark - Native SecureTransport logging

static void SKYLogTLSBytes(const char *direction,
                           const void *bytes,
                           size_t length,
                           size_t processed,
                           OSStatus status) {
    @autoreleasepool {
        if (!bytes || length == 0) {
            return;
        }

        size_t actualLength = processed;

        if (actualLength == 0 || actualLength > length) {
            actualLength = length;
        }

        NSData *data =
            [NSData dataWithBytes:bytes
                           length:actualLength];

        NSString *message =
            [NSString stringWithFormat:
                @"\n"
                 "========== TLS %s ==========\n"
                 "Status: %d\n"
                 "Requested length: %lu\n"
                 "Processed length: %lu\n"
                 "Data:\n%@\n"
                 "============================\n",
                direction ?: "UNKNOWN",
                (int)status,
                (unsigned long)length,
                (unsigned long)actualLength,
                SKYDataDescription(data)];

        SKYWriteLog(message);
    }
}

%hookf(OSStatus,
       SSLWrite,
       SSLContextRef context,
       const void *data,
       size_t dataLength,
       size_t *processed) {
    OSStatus status =
        %orig(context,
              data,
              dataLength,
              processed);

    size_t written =
        processed ? *processed : dataLength;

    SKYLogTLSBytes("WRITE",
                   data,
                   dataLength,
                   written,
                   status);

    return status;
}

%hookf(OSStatus,
       SSLRead,
       SSLContextRef context,
       void *data,
       size_t dataLength,
       size_t *processed) {
    OSStatus status =
        %orig(context,
              data,
              dataLength,
              processed);

    size_t received =
        processed ? *processed : 0;

    SKYLogTLSBytes("READ",
                   data,
                   dataLength,
                   received,
                   status);

    return status;
}

#pragma mark - GTMSessionFetcher hooks

%hook GTMSessionFetcher

- (void)setRequest:(NSURLRequest *)request {
    SKYLogRequest(request,
                  nil,
                  @"GTMSessionFetcher setRequest:");

    %orig(request);
}

- (void)beginFetchWithCompletionHandler:(id)handler {
    NSURLRequest *request =
        [(id)self request];

    SKYLogRequest(request,
                  nil,
                  @"GTMSessionFetcher beginFetchWithCompletionHandler:");

    %orig(handler);
}

- (void)fetchWithCompletionHandler:(id)handler {
    NSURLRequest *request =
        [(id)self request];

    SKYLogRequest(request,
                  nil,
                  @"GTMSessionFetcher fetchWithCompletionHandler:");

    %orig(handler);
}

- (void)beginFetchMayDelay:(BOOL)mayDelay
             mayAuthorize:(BOOL)mayAuthorize {
    NSURLRequest *request =
        [(id)self request];

    SKYLogRequest(request,
                  nil,
                  @"GTMSessionFetcher beginFetchMayDelay:mayAuthorize:");

    %orig(mayDelay, mayAuthorize);
}

- (void)beginFetchWithDelegate:(id)delegate
             didFinishSelector:(SEL)selector {
    NSURLRequest *request =
        [(id)self request];

    SKYLogRequest(request,
                  nil,
                  @"GTMSessionFetcher beginFetchWithDelegate:");

    %orig(delegate, selector);
}

%end

#pragma mark - NSURLSessionTask hooks

%hook NSURLSessionTask

- (void)resume {
    @autoreleasepool {
        NSURLRequest *request =
            self.currentRequest ?: self.originalRequest;

        SKYLogRequest(request,
                      nil,
                      @"NSURLSessionTask resume");
    }

    %orig;
}

%end

#pragma mark - NSURLSession hooks

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *,
                                                        NSURLResponse *,
                                                        NSError *))completionHandler {
    SKYLogRequest(request,
                  nil,
                  @"NSURLSession dataTaskWithRequest:");

    void (^wrappedCompletion)(NSData *,
                              NSURLResponse *,
                              NSError *) =
        ^(NSData *data,
          NSURLResponse *response,
          NSError *error) {
            SKYLogResponse(data,
                           response,
                           error,
                           @"NSURLSession dataTask completion");

            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };

    return %orig(request, wrappedCompletion);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *,
                                                    NSURLResponse *,
                                                    NSError *))completionHandler {
    NSURLRequest *request =
        [NSURLRequest requestWithURL:url];

    SKYLogRequest(request,
                  nil,
                  @"NSURLSession dataTaskWithURL:");

    void (^wrappedCompletion)(NSData *,
                              NSURLResponse *,
                              NSError *) =
        ^(NSData *data,
          NSURLResponse *response,
          NSError *error) {
            SKYLogResponse(data,
                           response,
                           error,
                           @"NSURLSession dataTask URL completion");

            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };

    return %orig(url, wrappedCompletion);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                          fromData:(NSData *)bodyData
                                 completionHandler:(void (^)(NSData *,
                                                             NSURLResponse *,
                                                             NSError *))completionHandler {
    SKYLogRequest(request,
                  bodyData,
                  @"NSURLSession uploadTask fromData:");

    void (^wrappedCompletion)(NSData *,
                              NSURLResponse *,
                              NSError *) =
        ^(NSData *data,
          NSURLResponse *response,
          NSError *error) {
            SKYLogResponse(data,
                           response,
                           error,
                           @"NSURLSession upload completion");

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
                     @"NSURLSession uploadTask fromFile:");

    void (^wrappedCompletion)(NSData *,
                              NSURLResponse *,
                              NSError *) =
        ^(NSData *data,
          NSURLResponse *response,
          NSError *error) {
            SKYLogResponse(data,
                           response,
                           error,
                           @"NSURLSession file upload completion");

            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };

    return %orig(request, fileURL, wrappedCompletion);
}

%end

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        NSString *path =
            SKYDocumentsLogPath();

        NSFileManager *fileManager =
            [NSFileManager defaultManager];

        if (![fileManager fileExistsAtPath:path]) {
            [fileManager createFileAtPath:path
                                  contents:nil
                                attributes:nil];
        }

        NSString *message =
            [NSString stringWithFormat:
                @"\n"
                 "================================================\n"
                 "Sky HTTP logging tweak loaded\n"
                 "Full request/response logging enabled\n"
                 "SecureTransport SSLRead/SSLWrite hooks enabled\n"
                 "Log path: %@\n"
                 "================================================\n",
                path];

        SKYWriteLog(message);
    }
}
