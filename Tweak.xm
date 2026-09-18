#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h> // Để sử dụng các hàm dyld

// ==========================================
// PHẦN 1: THEO DÕI VÀ LƯU HTTPS REQUEST VÀO FILE
// ==========================================

// Hàm helper để tạo đường dẫn và ghi file vào Document
void saveRequestToDocument(NSString *logData) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [paths firstObject];
    NSString *filePath = [docDir stringByAppendingPathComponent:@"AppNetworkRequests.txt"];
    
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    if (!handle) {
        // Nếu file chưa tồn tại, tạo mới
        [logData writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        // Nếu file đã tồn tại, ghi tiếp vào cuối file (append)
        [handle seekToEndOfFile];
        [handle writeData:[logData dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    }
}

%hook NSURLSessionTask

- (void)resume {
    NSURLRequest *request = nil;
    
    // Lấy request từ Task
    if ([self respondsToSelector:@selector(originalRequest)]) {
        request = [self performSelector:@selector(originalRequest)];
    } else if ([self respondsToSelector:@selector(currentRequest)]) {
        request = [self performSelector:@selector(currentRequest)];
    }
    
    if (request && request.URL) {
        NSMutableString *log = [NSMutableString string];
        [log appendString:@"\n========================================\n"];
        [log appendFormat:@"[URL]: %@ %@\n", request.HTTPMethod, request.URL.absoluteString];
        [log appendFormat:@"[HEADERS]: %@\n", request.allHTTPHeaderFields];
        
        // Đọc Body nếu có (ví dụ: data gửi lên server khi POST)
        if (request.HTTPBody) {
            NSString *bodyStr = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
            [log appendFormat:@"[BODY]: %@\n", bodyStr ? bodyStr : @"<Binary Data / Unreadable>"];
        }
        [log appendString:@"========================================\n"];
        
        // Lưu vào file chạy ngầm
        saveRequestToDocument(log);
    }
    
    // Đừng quên gọi %orig để request thực sự được gửi đi, nếu không app sẽ mất mạng
    %orig;
}

%end

// ==========================================
// PHẦN 2: ẨN MODULE / TÀNG HÌNH TRÊN RAM (dyld Bypass)
// ==========================================

// Hook vào hàm lấy tên module của C
%hookf(const char *, _dyld_get_image_name, uint32_t image_index) {
    // Lấy tên thật của file dylib đang nạp ở vị trí image_index
    const char *real_name = %orig(image_index);
    
    if (real_name != NULL) {
        NSString *nameStr = [NSString stringWithUTF8String:real_name];
        
        // Nếu tên module có chứa các từ khóa nhạy cảm
        if ([nameStr containsString:@"CydiaSubstrate"] || 
            [nameStr containsString:@"Substrate"] || 
            [nameStr containsString:@"TrollStore"] ||
            [nameStr containsString:@"frida"] ||
            [nameStr containsString:@"Bypass"]) { // THAY TÊN DYLIB CỦA BẠN VÀO ĐÂY
            
            // TRẢ VỀ TÊN GIẢ MẠO: Thay vì trả về nil (dễ gây crash app), 
            // ta nói dối app rằng đây là một thư viện hệ thống vô hại của Apple.
            return "/usr/lib/libSystem.B.dylib";
        }
    }
    
    // Nếu là thư viện bình thường, trả về tên thật
    return real_name;
}
