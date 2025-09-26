#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// === Global state ===
static BOOL isRecording = NO;
static NSMutableString *logBuffer;

// === Helpers ===
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

static NSString *stringFromDataIfText(NSData *d) {
    if (!d) return @"<nil>";
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (s) return s;
    // fallback to hex
    NSMutableString *hex = [NSMutableString stringWithCapacity:d.length*2];
    const unsigned char *bytes = d.bytes;
    for (NSUInteger i=0;i<d.length;i++) [hex appendFormat:@"%02x", bytes[i]];
    return [NSString stringWithFormat:@"<hex:%@>", hex];
}

static NSData *dataFromInputStream(NSInputStream *stream) {
    if (!stream) return nil;
    NSMutableData *collected = [NSMutableData data];
    uint8_t buffer[1024];
    [stream open];
    NSInteger len;
    while ((len = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
        [collected appendBytes:buffer length:len];
    }
    [stream close];
    return collected.length ? collected : nil;
}

// === UI Buttons (always appear) ===
%hook UIWindow

- (void)becomeKeyWindow {
    %orig;

    if ([self viewWithTag:0xF00DB1]) return;

    UIButton *recordBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    recordBtn.frame = CGRectMake(20, 80, 90, 40);
    recordBtn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    recordBtn.layer.cornerRadius = 8;
    [recordBtn setTitle:@"Record" forState:UIControlStateNormal];
    recordBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    recordBtn.tintColor = [UIColor whiteColor];
    recordBtn.tag = 0xF00DB1;
    [recordBtn addTarget:self action:@selector(_tweak_toggleRecord) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:recordBtn];

    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    doneBtn.frame = CGRectMake(20, 130, 90, 40);
    doneBtn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    doneBtn.layer.cornerRadius = 8;
    [doneBtn setTitle:@"Done" forState:UIControlStateNormal];
    doneBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    doneBtn.tintColor = [UIColor whiteColor];
    doneBtn.tag = 0xF00DB2;
    [doneBtn addTarget:self action:@selector(_tweak_finishRecord) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:doneBtn];
}

%new
- (void)_tweak_toggleRecord {
    isRecording = !isRecording;
    if (isRecording) {
        logBuffer = [NSMutableString stringWithString:@"--- Recording Started ---\n"];
        appendLog(@"[Recorder] START at %@", [NSDate date]);
        NSLog(@"[Recorder] ON");
    } else {
        appendLog(@"[Recorder] PAUSED at %@", [NSDate date]);
        NSLog(@"[Recorder] OFF");
    }
}

%new
- (void)_tweak_finishRecord {
    if (!logBuffer) return;
    appendLog(@"[Recorder] FINISH at %@", [NSDate date]);
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    pb.string = logBuffer;
    NSLog(@"[Recorder] Logs copied to clipboard, length=%lu", (unsigned long)logBuffer.length);
}

%end

// === Network Hooks (unchanged) ===
%hook NSMutableURLRequest
- (void)setHTTPBody:(NSData *)body {
    if (isRecording) {
        appendLog(@"[setHTTPBody] URL: %@\nMethod: %@\nBody: %@",
                  self.URL, self.HTTPMethod, stringFromDataIfText(body));
    }
    %orig(body);
}
- (void)setHTTPBodyStream:(NSInputStream *)stream {
    if (isRecording) {
        NSData *d = dataFromInputStream(stream);
        appendLog(@"[setHTTPBodyStream] URL: %@\nMethod: %@\nBody: %@",
                  self.URL, self.HTTPMethod, stringFromDataIfText(d));
        if (d) @try { [self setHTTPBody:d]; } @catch(...) {}
    }
    %orig(stream);
}
%end

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(id)handler {
    if (isRecording) {
        NSData *d = request.HTTPBody ?: dataFromInputStream(request.HTTPBodyStream);
        appendLog(@"[dataTaskWithRequest] URL: %@\nMethod: %@\nHeaders: %@\nBody: %@",
                  request.URL, request.HTTPMethod,
                  request.allHTTPHeaderFields, stringFromDataIfText(d));
    }
    return %orig(request, handler);
}
%end

%hook NSURLSessionTask
- (void)resume {
    if (isRecording) {
        NSURLRequest *req = [self originalRequest] ?: [self currentRequest];
        NSData *d = req.HTTPBody ?: dataFromInputStream(req.HTTPBodyStream);
        appendLog(@"[Task resume] URL: %@\nMethod: %@\nHeaders: %@\nBody: %@",
                  req.URL, req.HTTPMethod,
                  req.allHTTPHeaderFields, stringFromDataIfText(d));
    }
    %orig;
}
%end

%hook NSURLConnection
+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error {
    if (isRecording) {
        NSData *d = request.HTTPBody ?: dataFromInputStream(request.HTTPBodyStream);
        appendLog(@"[NSURLConnection sync] URL: %@\nMethod: %@\nHeaders: %@\nBody: %@",
                  request.URL, request.HTTPMethod,
                  request.allHTTPHeaderFields, stringFromDataIfText(d));
    }
    return %orig(request, response, error);
}
%end

%ctor {
    logBuffer = [NSMutableString stringWithString:@"--- Recorder Initialized ---\n"];
}
