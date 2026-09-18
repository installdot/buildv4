#import <Foundation/Foundation.h>

// Đường dẫn file chung. App TrollStore có quyền đọc file này.
#define LOG_FILE @"/var/mobile/Documents/NetworkDump.txt"

void logRequest(NSURLRequest *request) {
    NSMutableString *log = [NSMutableString new];
    
    // 1. URL & Method
    [log appendFormat:@"\n[%@] %@\n", request.HTTPMethod, request.URL.absoluteString];
    
    // 2. Headers
    [log appendFormat:@"Headers: %@\n", request.allHTTPHeaderFields];
    
    // 3. Body
    if (request.HTTPBody) {
        NSString *body = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
        [log appendFormat:@"Body: %@\n", body ? body : @"<Binary Data>"];
    }
    [log appendString:@"----------------------------------------\n"];
    
    // Ghi file (Append)
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:LOG_FILE];
    if (!handle) {
        [log writeToFile:LOG_FILE atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [handle seekToEndOfFile];
        [handle writeData:[log dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    }
}

// Hook vào hàm bắt đầu gửi request của iOS
%hook NSURLSessionTask

- (void)resume {
    if ([self respondsToSelector:@selector(originalRequest)]) {
        NSURLRequest *req = [self performSelector:@selector(originalRequest)];
        if (req) {
            logRequest(req);
        }
    }
    %orig; // Tiếp tục gửi request đi
}

%end
