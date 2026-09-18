#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#include <string.h>

// ==========================================
// PHẦN 1: TÀNG HÌNH (ẨN DYLIB KHỎI RAM)
// ==========================================
%hookf(const char *, _dyld_get_image_name, uint32_t image_index) {
    const char *real_name = %orig(image_index);
    if (real_name != NULL) {
        if (strstr(real_name, "CydiaSubstrate") != NULL ||
            strstr(real_name, "TrollStore") != NULL ||
            strstr(real_name, "TenDylibCuaBan") != NULL) {
            return "/usr/lib/libSystem.B.dylib";
        }
    }
    return real_name;
}

// ==========================================
// PHẦN 2: HỆ THỐNG GHI LOG THREAD-SAFE
// ==========================================
void saveNetworkLog(NSString *logData) {
    static dispatch_queue_t writeQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        writeQueue = dispatch_queue_create("com.sniffer.writer", DISPATCH_QUEUE_SERIAL);
    });
    
    dispatch_async(writeQueue, ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *filePath = [[paths firstObject] stringByAppendingPathComponent:@"AppFullNetwork.txt"];
        
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:filePath]) {
            [logData writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:filePath];
            [handle seekToEndOfFile];
            [handle writeData:[logData dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        }
    });
}

// ==========================================
// PHẦN 3: LỚP NSURLPROTOCOL TRUNG GIAN
// Cần viết bằng Objective-C thuần, đặt trước các khối %hook
// ==========================================
static NSString *const kSnifferHandledKey = @"SnifferHandledKey";

@interface FullAPIProtocol : NSURLProtocol <NSURLSessionDataDelegate, NSURLSessionTaskDelegate>
@property (nonatomic, strong) NSURLSessionDataTask *dataTask;
@property (nonatomic, strong) NSMutableData *responseData;
@property (nonatomic, strong) NSURLResponse *currentResponse;
@end

@implementation FullAPIProtocol

// Kích hoạt chặn các request HTTP/HTTPS
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    // Nếu request này đã bị ta chặn và đang xử lý, bỏ qua để chống vòng lặp vô hạn (Infinite Loop)
    if ([NSURLProtocol propertyForKey:kSnifferHandledKey inRequest:request]) return NO;
    if (![request.URL.scheme isEqualToString:@"http"] && ![request.URL.scheme isEqualToString:@"https"]) return NO;
    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

// Khi app bắt đầu gửi request
- (void)startLoading {
    NSMutableURLRequest *newRequest = [self.request mutableCopy];
    // Đánh dấu request này là "Đã bị Sniffer tóm"
    [NSURLProtocol setProperty:@YES forKey:kSnifferHandledKey inRequest:newRequest];
    
    self.responseData = [NSMutableData data];
    
    // Tự tạo một session nội bộ để gửi request đi máy chủ thật
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] 
                                                          delegate:self 
                                                     delegateQueue:nil];
    self.dataTask = [session dataTaskWithRequest:newRequest];
    [self.dataTask resume];
}

- (void)stopLoading {
    [self.dataTask cancel];
    self.dataTask = nil;
}

// NHẬN HEADER TỪ SERVER
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    self.currentResponse = response;
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    completionHandler(NSURLSessionResponseAllow);
}

// NHẬN TỪNG CHUNK DATA (BODY) TỪ SERVER
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [self.responseData appendData:data];
    [self.client URLProtocol:self didLoadData:data];
}

// KHI REQUEST HOÀN TẤT -> TỔNG HỢP VÀ GHI LOG
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        [self.client URLProtocol:self didFailWithError:error];
    } else {
        [self.client URLProtocolDidFinishLoading:self];
        
        NSMutableString *log = [NSMutableString string];
        [log appendString:@"\n======================================================\n"];
        [log appendFormat:@"[REQUEST] %@ %@\n", self.request.HTTPMethod, self.request.URL.absoluteString];
        [log appendFormat:@"[REQ_HEADERS] %@\n", self.request.allHTTPHeaderFields];
        
        if (self.request.HTTPBody) {
            NSString *bodyStr = [[NSString alloc] initWithData:self.request.HTTPBody encoding:NSUTF8StringEncoding];
            [log appendFormat:@"[REQ_BODY] %@\n", bodyStr ? bodyStr : @"<Binary Data>"];
        }
        
        [log appendString:@"\n-------------------- RESPONSE --------------------\n"];
        if ([self.currentResponse isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)self.currentResponse;
            [log appendFormat:@"[STATUS] %ld\n", (long)httpResponse.statusCode];
            [log appendFormat:@"[RES_HEADERS] %@\n", httpResponse.allHeaderFields];
        }
        
        if (self.responseData.length > 0) {
            NSString *resBody = [[NSString alloc] initWithData:self.responseData encoding:NSUTF8StringEncoding];
            [log appendFormat:@"[RES_BODY] %@\n", resBody ? resBody : @"<Binary Data>"];
        }
        [log appendString:@"======================================================\n"];
        
        saveNetworkLog(log);
    }
}
@end

// ==========================================
// PHẦN 4: ÉP ỨNG DỤNG PHẢI SỬ DỤNG TRẠM THU PHÍ (PROTOCOL) CỦA TA
// ==========================================
%hook NSURLSessionConfiguration

// Ép vào mảng config mặc định
- (NSArray *)protocolClasses {
    NSArray *orig = %orig;
    NSMutableArray *newProtocols = [NSMutableArray arrayWithObject:[FullAPIProtocol class]];
    if (orig) [newProtocols addObjectsFromArray:orig];
    return newProtocols;
}

- (void)setProtocolClasses:(NSArray *)protocolClasses {
    NSMutableArray *newProtocols = [NSMutableArray arrayWithObject:[FullAPIProtocol class]];
    if (protocolClasses) [newProtocols addObjectsFromArray:protocolClasses];
    %orig(newProtocols);
}

%end

// Tự động đăng ký khi app vừa khởi động
%ctor {
    [NSURLProtocol registerClass:[FullAPIProtocol class]];
}
