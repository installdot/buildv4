// Tweak.xm
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

// simple global recording state
static BOOL isRecording = NO;
static NSMutableString *logBuffer;

// Helper to read an NSInputStream into NSData (destructive - consumes stream)
static NSData * dataFromInputStream(NSInputStream *stream) {
    if (!stream) return nil;
    @try {
        uint8_t buffer[1024];
        NSMutableData *collected = [NSMutableData data];
        [stream open];
        NSInteger len = 0;
        while ((len = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
            [collected appendBytes:buffer length:len];
        }
        [stream close];
        if (collected.length > 0) return collected;
    } @catch (NSException *ex) {
        // ignore
    }
    return nil;
}

static NSString * stringFromDataIfText(NSData *d) {
    if (!d) return nil;
    // try utf8, fallback to hex if binary
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (s) return s;
    // not text
    NSMutableString *hex = [NSMutableString stringWithCapacity:d.length*2];
    const unsigned char *bytes = (const unsigned char*)d.bytes;
    for (NSUInteger i=0;i<d.length;i++) [hex appendFormat:@"%02x", bytes[i]];
    return [NSString stringWithFormat:@"<hex:%@>", hex];
}

// append safe formatted entry
static void appendLog(NSString *fmt, ...) {
    if (!logBuffer) return;
    va_list args;
    va_start(args, fmt);
    NSString *entry = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    @synchronized (logBuffer) {
        [logBuffer appendString:entry];
        [logBuffer appendString:@"\n"];
    }
}

// UI helpers
%hook UIApplication

- (void)didFinishLaunching:(id)arg {
    %orig(arg);

    // Delay to let UI settle
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
        if (!window) return;

        UIButton *recordBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        recordBtn.frame = CGRectMake(20, 80, 90, 40);
        recordBtn.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
        recordBtn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        recordBtn.layer.cornerRadius = 8;
        [recordBtn setTitle:@"Record" forState:UIControlStateNormal];
        recordBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        recordBtn.tintColor = [UIColor whiteColor];
        recordBtn.tag = 0xF00DB1;
        [recordBtn addTarget:self action:@selector(_tweak_toggleRecord) forControlEvents:UIControlEventTouchUpInside];
        [window addSubview:recordBtn];

        UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        doneBtn.frame = CGRectMake(20, 130, 90, 40);
        doneBtn.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
        doneBtn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        doneBtn.layer.cornerRadius = 8;
        [doneBtn setTitle:@"Done" forState:UIControlStateNormal];
        doneBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        doneBtn.tintColor = [UIColor whiteColor];
        doneBtn.tag = 0xF00DB2;
        [doneBtn addTarget:self action:@selector(_tweak_finishRecord) forControlEvents:UIControlEventTouchUpInside];
        [window addSubview:doneBtn];
    });
}

%new
- (void)_tweak_toggleRecord {
    isRecording = !isRecording;
    if (isRecording) {
        logBuffer = [NSMutableString stringWithString:@"--- Network Recorder Started ---\n"];
        appendLog(@"[Recorder] START at %@", [NSDate date]);
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Recorder" message:@"Recording ON" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:a animated:YES completion:nil];
    } else {
        appendLog(@"[Recorder] PAUSED at %@", [NSDate date]);
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Recorder" message:@"Recording PAUSED" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:a animated:YES completion:nil];
    }
}

%new
- (void)_tweak_finishRecord {
    if (!logBuffer) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Recorder" message:@"No logs" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:a animated:YES completion:nil];
        return;
    }
    appendLog(@"[Recorder] FINISH at %@", [NSDate date]);
    // copy to clipboard
    dispatch_async(dispatch_get_main_queue(), ^{
        UIPasteboard *pb = [UIPasteboard generalPasteboard];
        pb.string = logBuffer;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Recorder" message:@"Logs copied to clipboard" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:a animated:YES completion:nil];
    });
}

%end

// Hook NSMutableURLRequest body setters so we see when app sets code in body
%hook NSMutableURLRequest

- (void)setHTTPBody:(NSData *)body {
    if (isRecording) {
        NSString *s = stringFromDataIfText(body) ?: @"<nil>";
        appendLog(@"[setHTTPBody] URL: %@\nMethod: %@\nBody: %@\nHeaders: %@",
                  self.URL ?: @"<nil>",
                  self.HTTPMethod ?: @"<nil>",
                  s,
                  self.allHTTPHeaderFields ?: @{});
    }
    %orig(body);
}

- (void)setHTTPBodyStream:(NSInputStream *)stream {
    if (isRecording) {
        NSData *d = dataFromInputStream(stream);
        NSString *s = stringFromDataIfText(d) ?: @"<stream:nil>";
        appendLog(@"[setHTTPBodyStream] URL: %@\nMethod: %@\nBodyStream (read): %@\nHeaders: %@",
                  self.URL ?: @"<nil>",
                  self.HTTPMethod ?: @"<nil>",
                  s,
                  self.allHTTPHeaderFields ?: @{});

        // try to convert into HTTPBody for safety (so future reads still see it)
        if (d && [self isKindOfClass:[NSMutableURLRequest class]]) {
            @try {
                [(NSMutableURLRequest *)self setHTTPBody:d];
            } @catch (NSException *ex) {
                // ignore
            }
        }
    }
    %orig(stream);
}

%end

// Hook NSURLSession creation flow and task resume point
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(id)handler {
    if (isRecording) {
        NSString *bodyStr = @"<nil>";
        if ([request HTTPBody]) bodyStr = stringFromDataIfText([request HTTPBody]) ?: @"<binary>";
        else if ([request HTTPBodyStream]) {
            NSData *d = dataFromInputStream([request HTTPBodyStream]);
            bodyStr = stringFromDataIfText(d) ?: @"<binary>";
            // try to replace stream with body when possible - best effort
            if (d && [request isKindOfClass:[NSMutableURLRequest class]]) {
                @try { [(NSMutableURLRequest *)request setHTTPBody:d]; } @catch (NSException *e) {}
            }
        }
        appendLog(@"[dataTaskWithRequest] URL: %@\nMethod: %@\nHeaders: %@\nBody: %@",
                  request.URL ?: @"<nil>",
                  request.HTTPMethod ?: @"<nil>",
                  request.allHTTPHeaderFields ?: @{},
                  bodyStr);
    }
    return %orig(request, handler);
}

%end

%hook NSURLSessionTask

- (void)resume {
    if (isRecording) {
        NSURLRequest *req = nil;
        @try {
            req = [self originalRequest] ?: [self currentRequest];
        } @catch (NSException *ex) { req = nil; }

        if (req) {
            NSString *bodyStr = @"<nil>";
            if ([req HTTPBody]) bodyStr = stringFromDataIfText([req HTTPBody]) ?: @"<binary>";
            else if ([req HTTPBodyStream]) {
                NSData *d = dataFromInputStream([req HTTPBodyStream]);
                bodyStr = stringFromDataIfText(d) ?: @"<binary>";
                if (d && [req isKindOfClass:[NSMutableURLRequest class]]) {
                    @try { [(NSMutableURLRequest *)req setHTTPBody:d]; } @catch (NSException *e) {}
                }
            }
            appendLog(@"[Task resume] Task: %p\nURL: %@\nMethod: %@\nHeaders: %@\nBody: %@",
                      self,
                      req.URL ?: @"<nil>",
                      req.HTTPMethod ?: @"<nil>",
                      req.allHTTPHeaderFields ?: @{},
                      bodyStr);
        } else {
            appendLog(@"[Task resume] Task: %p (no request available)", self);
        }
    }
    %orig;
}

%end

// Hook older NSURLConnection sync send as fallback
%hook NSURLConnection

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse * __autoreleasing *)response error:(NSError * __autoreleasing *)error {
    if (isRecording) {
        NSString *bodyStr = @"<nil>";
        if ([request HTTPBody]) bodyStr = stringFromDataIfText([request HTTPBody]) ?: @"<binary>";
        else if ([request HTTPBodyStream]) {
            NSData *d = dataFromInputStream([request HTTPBodyStream]);
            bodyStr = stringFromDataIfText(d) ?: @"<binary>";
            if (d && [request isKindOfClass:[NSMutableURLRequest class]]) {
                @try { [(NSMutableURLRequest *)request setHTTPBody:d]; } @catch (NSException *e) {}
            }
        }
        appendLog(@"[NSURLConnection sendSynchronousRequest] URL: %@\nMethod: %@\nHeaders: %@\nBody: %@",
                  request.URL ?: @"<nil>",
                  request.HTTPMethod ?: @"<nil>",
                  request.allHTTPHeaderFields ?: @{},
                  bodyStr);
    }
    return %orig(request, response, error);
}

%end

// Constructor to initialize buffer
%ctor {
    logBuffer = [NSMutableString stringWithString:@"--- Recorder Initialized ---\n"];
}
