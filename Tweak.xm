#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonCrypto.h>
#import <substrate.h>

static CCCryptorStatus (*orig_CCCrypt)(
    CCOperation op,
    CCAlgorithm alg,
    CCOptions options,
    const void *key,
    size_t keyLength,
    const void *iv,
    const void *dataIn,
    size_t dataInLength,
    void *dataOut,
    size_t dataOutAvailable,
    size_t *dataOutMoved
);

NSString* hexString(NSData *data) {
    const unsigned char *dataBuffer = (const unsigned char *)data.bytes;
    if (!dataBuffer) return @"";
    
    NSUInteger dataLength = data.length;
    NSMutableString *hexString  = [NSMutableString stringWithCapacity:(dataLength * 2)];
    
    for (int i = 0; i < dataLength; ++i)
        [hexString appendFormat:@"%02x", dataBuffer[i]];
    
    return hexString;
}

void saveLog(NSString *text) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/crypto_log.txt"];
    
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
    
    if (!file) {
        [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [file seekToEndOfFile];
        [file writeData:[[text stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
        [file closeFile];
    }
}

void showNotification(NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Crypto Captured"
            message:msg
            preferredStyle:UIAlertControllerStyleAlert];
        
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

CCCryptorStatus replaced_CCCrypt(
    CCOperation op,
    CCAlgorithm alg,
    CCOptions options,
    const void *key,
    size_t keyLength,
    const void *iv,
    const void *dataIn,
    size_t dataInLength,
    void *dataOut,
    size_t dataOutAvailable,
    size_t *dataOutMoved
) {

    NSString *operation = (op == kCCDecrypt) ? @"DECRYPT" : @"ENCRYPT";

    NSData *keyData = [NSData dataWithBytes:key length:keyLength];
    NSString *keyHex = hexString(keyData);

    NSString *ivHex = @"NULL";
    if (iv) {
        NSData *ivData = [NSData dataWithBytes:iv length:16];
        ivHex = hexString(ivData);
    }

    NSString *log = [NSString stringWithFormat:
        @"[%@]\nKey: %@\nIV: %@\nInputLength: %lu\n----------------------",
        operation,
        keyHex,
        ivHex,
        (unsigned long)dataInLength
    ];

    saveLog(log);
    showNotification(@"Crypto key captured");

    return orig_CCCrypt(
        op,
        alg,
        options,
        key,
        keyLength,
        iv,
        dataIn,
        dataInLength,
        dataOut,
        dataOutAvailable,
        dataOutMoved
    );
}

%ctor {
    void *handle = dlopen("/usr/lib/system/libcommonCrypto.dylib", RTLD_NOW);
    
    if (handle) {
        void *sym = dlsym(handle, "CCCrypt");
        if (sym) {
            MSHookFunction(sym, (void *)&replaced_CCCrypt, (void **)&orig_CCCrypt);
        }
    }
}
