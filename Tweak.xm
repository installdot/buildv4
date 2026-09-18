#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Tập hợp lưu các địa chỉ RAM đã quét để tránh lặp vô hạn (Infinite Loop)
static NSMutableSet *visitedObjects;
static NSMutableString *dumpResult;

// Kiểm tra xem Class này do Dev viết (Main Bundle) hay của Apple (UIKit/Foundation)
BOOL isAppCustomClass(Class cls) {
    if (!cls) return NO;
    NSBundle *bundle = [NSBundle bundleForClass:cls];
    return bundle == [NSBundle mainBundle];
}

// Hàm quét sâu (Đệ quy) vào một Object
void deepDumpObject(id object, int level) {
    if (!object) return;
    
    // Nếu đã quét object này rồi thì bỏ qua để chống crash/lặp vô hạn
    NSString *memoryAddress = [NSString stringWithFormat:@"%p", object];
    if ([visitedObjects containsObject:memoryAddress]) return;
    [visitedObjects addObject:memoryAddress];

    Class cls = [object class];
    NSString *indent = [@"" stringByPaddingToLength:(level * 4) withString:@"-" startingAtIndex:0];
    
    [dumpResult appendFormat:@"\n%@> [%@] Address: %@\n", indent, cls, memoryAddress];
    
    // Chỉ quét sâu vào các biến nếu đây là Class do Dev ứng dụng viết.
    // Tránh quét sâu vào UIView, NSString của hệ thống làm treo máy.
    if (isAppCustomClass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        
        for (unsigned int i = 0; i < count; i++) {
            Ivar ivar = ivars[i];
            NSString *varName = [NSString stringWithUTF8String:ivar_getName(ivar)];
            
            @try {
                // Lấy giá trị biến
                id value = [object valueForKey:varName];
                
                if (value) {
                    [dumpResult appendFormat:@"%@    |__ %@ = %@\n", indent, varName, [value class]];
                    
                    // NẾU giá trị này cũng là một Object do Dev viết, tiếp tục quét sâu vào nó!
                    if (isAppCustomClass([value class])) {
                        deepDumpObject(value, level + 1);
                    } else {
                        // Nếu là String, Number, Array cơ bản thì in thẳng giá trị ra
                        [dumpResult appendFormat:@"%@        Value: %@\n", indent, value];
                    }
                } else {
                    [dumpResult appendFormat:@"%@    |__ %@ = nil\n", indent, varName];
                }
            } @catch (NSException *e) {
                [dumpResult appendFormat:@"%@    |__ %@ = <Unreadable>\n", indent, varName];
            }
        }
        free(ivars);
    }
}

// Hàm khởi chạy tiến trình quét
void startDeepDump() {
    visitedObjects = [NSMutableSet new];
    dumpResult = [NSMutableString new];
    
    [dumpResult appendString:@"========================================\n"];
    [dumpResult appendString:@"   DEEP DUMP LIVE OBJECTS & VARIABLES   \n"];
    [dumpResult appendString:@"========================================\n"];
    
    // 1. Quét App Delegate (Nơi thường chứa các Manager, Store)
    id appDelegate = [UIApplication sharedApplication].delegate;
    [dumpResult appendString:@"\n--- DUMPING APP DELEGATE ---"];
    deepDumpObject(appDelegate, 0);
    
    // 2. Quét toàn bộ Giao diện và các ViewModel/Controller đính kèm
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    [dumpResult appendString:@"\n--- DUMPING VIEW HIERARCHY ---"];
    deepDumpObject(keyWindow, 0);
    
    // Lưu ra file
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [paths firstObject];
    NSString *filePath = [docDir stringByAppendingPathComponent:@"DeepLiveValuesDump.txt"];
    
    [dumpResult writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    // Dọn dẹp RAM sau khi quét xong
    visitedObjects = nil;
    dumpResult = nil;
    
    // Thông báo cho user biết file đã lưu ở đâu
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Quét Hoàn Tất!" 
                                                                       message:[NSString stringWithFormat:@"Đã quét toàn bộ biến hiện tại.\nLưu tại: %@", filePath] 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Đã hiểu" style:UIAlertActionStyleDefault handler:nil]];
        [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

// ==========================================
// HOOK VÀO THAO TÁC LẮC ĐIỆN THOẠI ĐỂ DUMP
// ==========================================
%hook UIWindow

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    %orig;
    if (event.type == UIEventTypeMotion && event.subtype == UIEventSubtypeMotionShake) {
        startDeepDump();
    }
}

%end
