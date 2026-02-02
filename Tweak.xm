#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <substrate.h>
#import <fcntl.h>
#import <sys/stat.h>

static NSString *allowedHome;
static NSString *allowedBundle;
static BOOL enabled = YES;

#pragma mark - Helper

static NSString *actionFromFlags(int flags) {
    if (flags & O_WRONLY) return @"WRITE";
    if (flags & O_RDWR)   return @"READ + WRITE";
    return @"READ";
}

static void showAlert(NSString *method, NSString *action, NSString *path) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *msg = [NSString stringWithFormat:
            @"Method : %@\nAction : %@\nPath   : %@",
            method, action, path];

        UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Sandbox Blocked"
                                            message:msg
                                     preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];

        UIWindow *win = UIApplication.sharedApplication.keyWindow;
        UIViewController *vc = win.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        [vc presentViewController:alert animated:YES completion:nil];
    });
}

static BOOL checkPath(const char *cpath,
                      NSString *method,
                      NSString *action) {
    if (!enabled || !cpath) return YES;

    NSString *path = [NSString stringWithUTF8String:cpath];

    if ([path hasPrefix:allowedHome]) return YES;
    if ([path hasPrefix:allowedBundle]) return YES;

    showAlert(method, action, path);
    errno = EACCES;
    return NO;
}

#pragma mark - libc hooks

static int (*orig_open)(const char *, int, ...);
static int hooked_open(const char *path, int flags, ...) {
    if (!checkPath(path, @"open()", actionFromFlags(flags)))
        return -1;
    return orig_open(path, flags);
}

static int (*orig_openat)(int, const char *, int, ...);
static int hooked_openat(int fd, const char *path, int flags, ...) {
    if (!checkPath(path, @"openat()", actionFromFlags(flags)))
        return -1;
    return orig_openat(fd, path, flags);
}

static FILE *(*orig_fopen)(const char *, const char *);
static FILE *hooked_fopen(const char *path, const char *mode) {
    NSString *action = strchr(mode, 'w') ? @"WRITE" : @"READ";
    if (!checkPath(path, @"fopen()", action))
        return NULL;
    return orig_fopen(path, mode);
}

static int (*orig_access)(const char *, int);
static int hooked_access(const char *path, int mode) {
    if (!checkPath(path, @"access()", @"CHECK PERMISSION"))
        return -1;
    return orig_access(path, mode);
}

static int (*orig_stat)(const char *, struct stat *);
static int hooked_stat(const char *path, struct stat *buf) {
    if (!checkPath(path, @"stat()", @"FILE INFO"))
        return -1;
    return orig_stat(path, buf);
}

static int (*orig_lstat)(const char *, struct stat *);
static int hooked_lstat(const char *path, struct stat *buf) {
    if (!checkPath(path, @"lstat()", @"FILE INFO"))
        return -1;
    return orig_lstat(path, buf);
}

#pragma mark - Foundation hooks

%hook NSFileManager

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    if (!checkPath(path.UTF8String,
                   @"NSFileManager contentsOfDirectoryAtPath",
                   @"LIST DIRECTORY")) {
        if (error)
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:EACCES
                                     userInfo:nil];
        return nil;
    }
    return %orig;
}

- (BOOL)fileExistsAtPath:(NSString *)path {
    if (!checkPath(path.UTF8String,
                   @"NSFileManager fileExistsAtPath",
                   @"CHECK EXISTS"))
        return NO;
    return %orig;
}

%end

%hook NSData
+ (instancetype)dataWithContentsOfFile:(NSString *)path {
    if (!checkPath(path.UTF8String,
                   @"NSData dataWithContentsOfFile",
                   @"READ FILE"))
        return nil;
    return %orig;
}
%end

%hook NSString
+ (instancetype)stringWithContentsOfFile:(NSString *)path
                                encoding:(NSStringEncoding)enc
                                   error:(NSError **)error {
    if (!checkPath(path.UTF8String,
                   @"NSString stringWithContentsOfFile",
                   @"READ TEXT")) {
        if (error)
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:EACCES
                                     userInfo:nil];
        return nil;
    }
    return %orig;
}
%end

#pragma mark - Init

%ctor {
    @autoreleasepool {
        allowedHome   = NSHomeDirectory();
        allowedBundle = [NSBundle mainBundle].bundlePath;

        MSHookFunction(open,    hooked_open,    (void **)&orig_open);
        MSHookFunction(openat, hooked_openat, (void **)&orig_openat);
        MSHookFunction(fopen,  hooked_fopen,  (void **)&orig_fopen);
        MSHookFunction(access, hooked_access, (void **)&orig_access);
        MSHookFunction(stat,   hooked_stat,   (void **)&orig_stat);
        MSHookFunction(lstat,  hooked_lstat,  (void **)&orig_lstat);
    }
}
