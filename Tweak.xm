#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Security/Security.h>

static BOOL kBypassPaid = YES;
static NSString *TARGET_UDID = @"00008020-000640860179002E";

#pragma mark - Logger

void writeLog(NSString *log) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/log.txt"];
    NSString *line = [NSString stringWithFormat:@"%@\n", log];

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        NSFileHandle *f = [NSFileHandle fileHandleForWritingAtPath:path];
        [f seekToEndOfFile];
        [f writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [f closeFile];
    }
}

#pragma mark - Menu

void showMenu() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        UIViewController *root = keyWindow.rootViewController;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"API Control"
                                                                       message:@"Toggle Bypass Paid"
                                                                preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *toggle = [UIAlertAction actionWithTitle:(kBypassPaid ? @"Disable Bypass" : @"Enable Bypass")
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *action) {
            kBypassPaid = !kBypassPaid;
            writeLog([NSString stringWithFormat:@"[TOGGLE] Bypass = %d", kBypassPaid]);
        }];

        UIAlertAction *close = [UIAlertAction actionWithTitle:@"Close"
                                                       style:UIAlertActionStyleCancel
                                                     handler:nil];

        [alert addAction:toggle];
        [alert addAction:close];

        [root presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - APIClient Hook

%hook APIClient

- (void)setUDID:(NSString *)uid {
    writeLog([NSString stringWithFormat:@"[setUDID] %@", uid]);

    if ([uid containsString:TARGET_UDID]) {
        writeLog(@"[MATCH] UDID detected in setUDID");
    }

    %orig;

    // dump ivars
    unsigned int count;
    Ivar *ivars = class_copyIvarList([self class], &count);

    for (int i = 0; i < count; i++) {
        Ivar ivar = ivars[i];
        const char *name = ivar_getName(ivar);
        id value = object_getIvar(self, ivar);

        if ([value isKindOfClass:[NSString class]] &&
            [(NSString *)value containsString:TARGET_UDID]) {

            writeLog([NSString stringWithFormat:@"[IVAR] %s = %@", name, value]);
        }
    }

    free(ivars);
}

- (NSString *)getUDID {
    NSString *u = %orig;
    writeLog([NSString stringWithFormat:@"[getUDID] %@", u]);
    return u;
}

// 🚀 AUTO BYPASS
- (void)paid:(void (^)(void))execute {
    writeLog(@"[paid] called");

    if (kBypassPaid) {
        writeLog(@"[BYPASS] paid forced success");
        if (execute) execute();
        return;
    }

    %orig;
}

%end

#pragma mark - NSUserDefaults

%hook NSUserDefaults

- (void)setObject:(id)value forKey:(NSString *)key {

    if ([value isKindOfClass:[NSString class]] &&
        [(NSString *)value containsString:TARGET_UDID]) {

        writeLog([NSString stringWithFormat:@"[NSUserDefaults] %@ = %@", key, value]);
    }

    %orig;
}

%end

#pragma mark - Keychain Hooks

%hookf(OSStatus, SecItemAdd, CFDictionaryRef attributes, CFTypeRef *result) {

    NSDictionary *dict = (__bridge NSDictionary *)attributes;

    if ([[dict description] containsString:TARGET_UDID]) {
        writeLog([NSString stringWithFormat:@"[Keychain ADD] %@", dict]);
    }

    return %orig;
}

%hookf(OSStatus, SecItemUpdate, CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {

    NSDictionary *q = (__bridge NSDictionary *)query;
    NSDictionary *u = (__bridge NSDictionary *)attributesToUpdate;

    if ([[q description] containsString:TARGET_UDID] ||
        [[u description] containsString:TARGET_UDID]) {

        writeLog([NSString stringWithFormat:@"[Keychain UPDATE] %@ -> %@", q, u]);
    }

    return %orig;
}

#pragma mark - Network Hook

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    NSData *body = request.HTTPBody;

    if (body) {
        NSString *str = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];

        if ([str containsString:TARGET_UDID]) {
            writeLog([NSString stringWithFormat:@"[HTTP] %@", str]);
        }
    }

    return %orig;
}

%end

#pragma mark - Auto Init

%ctor {
    writeLog(@"===== TWEAK LOADED =====");
    writeLog([NSString stringWithFormat:@"[INIT] Auto bypass = %d", kBypassPaid]);

    showMenu(); // auto show menu
}
