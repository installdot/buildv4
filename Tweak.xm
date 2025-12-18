#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <substrate.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <spawn.h>
#import <stdarg.h>
#import <sys/stat.h>
#import <sys/types.h>
#import <unistd.h>

static NSString *gLogPath = nil;

static void TraceLog(NSString *fmt, ...)
{
    @autoreleasepool {
        va_list ap;
        va_start(ap, fmt);
        NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
        va_end(ap);

        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];

        // Console
        NSLog(@"%@", line);

        // File
        if (!gLogPath) return;

        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
        if (!fh) {
            [[NSFileManager defaultManager] createFileAtPath:gLogPath contents:nil attributes:nil];
            fh = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
            if (!fh) return;
        }

        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

/* ===================== C function hooks (MSHookFunction) ===================== */

typedef int     (*open_t)(const char *path, int oflag, ...);
typedef ssize_t (*write_t)(int fd, const void *buf, size_t count);
typedef int     (*close_t)(int fd);
typedef int     (*unlink_t)(const char *path);
typedef int     (*rename_t)(const char *oldp, const char *newp);
typedef int     (*mkdir_t)(const char *path, mode_t mode);
typedef int     (*rmdir_t)(const char *path);
typedef int     (*chmod_t)(const char *path, mode_t mode);
typedef void *  (*dlopen_t)(const char *path, int mode);

typedef int (*posix_spawn_t)(
    pid_t *pid,
    const char *path,
    const posix_spawn_file_actions_t *file_actions,
    const posix_spawnattr_t *attrp,
    char *const argv[],
    char *const envp[]
);

typedef int (*execve_t)(const char *path, char *const argv[], char *const envp[]);
typedef int (*system_t)(const char *command); // DO NOT reference `system` symbol directly (SDK marks it unavailable)

static open_t        orig_open = NULL;
static write_t       orig_write = NULL;
static close_t       orig_close = NULL;
static unlink_t      orig_unlink = NULL;
static rename_t      orig_rename = NULL;
static mkdir_t       orig_mkdir = NULL;
static rmdir_t       orig_rmdir = NULL;
static chmod_t       orig_chmod = NULL;
static dlopen_t      orig_dlopen = NULL;
static posix_spawn_t orig_posix_spawn = NULL;
static execve_t      orig_execve = NULL;
static system_t      orig_system = NULL;

static int my_open(const char *path, int flags, ...)
{
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode_t mode = (mode_t)va_arg(ap, int);
        va_end(ap);

        TraceLog(@"open(path=%s flags=0x%x mode=%o)", path ? path : "(null)", flags, mode);
        return orig_open ? orig_open(path, flags, mode) : -1;
    }

    TraceLog(@"open(path=%s flags=0x%x)", path ? path : "(null)", flags);
    return orig_open ? orig_open(path, flags) : -1;
}

static ssize_t my_write(int fd, const void *buf, size_t count)
{
    TraceLog(@"write(fd=%d size=%zu)", fd, count);
    return orig_write ? orig_write(fd, buf, count) : -1;
}

static int my_close(int fd)
{
    TraceLog(@"close(fd=%d)", fd);
    return orig_close ? orig_close(fd) : -1;
}

static int my_unlink(const char *path)
{
    TraceLog(@"unlink(%s)", path ? path : "(null)");
    return orig_unlink ? orig_unlink(path) : -1;
}

static int my_rename(const char *oldp, const char *newp)
{
    TraceLog(@"rename(%s -> %s)", oldp ? oldp : "(null)", newp ? newp : "(null)");
    return orig_rename ? orig_rename(oldp, newp) : -1;
}

static int my_mkdir(const char *path, mode_t mode)
{
    TraceLog(@"mkdir(%s mode=%o)", path ? path : "(null)", mode);
    return orig_mkdir ? orig_mkdir(path, mode) : -1;
}

static int my_rmdir(const char *path)
{
    TraceLog(@"rmdir(%s)", path ? path : "(null)");
    return orig_rmdir ? orig_rmdir(path) : -1;
}

static int my_chmod(const char *path, mode_t mode)
{
    TraceLog(@"chmod(%s mode=%o)", path ? path : "(null)", mode);
    return orig_chmod ? orig_chmod(path, mode) : -1;
}

static void *my_dlopen(const char *path, int mode)
{
    TraceLog(@"dlopen(%s)", path ? path : "(null)");
    return orig_dlopen ? orig_dlopen(path, mode) : NULL;
}

static int my_posix_spawn(
    pid_t *pid,
    const char *path,
    const posix_spawn_file_actions_t *file_actions,
    const posix_spawnattr_t *attrp,
    char *const argv[],
    char *const envp[]
) {
    TraceLog(@"posix_spawn(%s)", path ? path : "(null)");
    if (argv) {
        for (int i = 0; argv[i]; i++) {
            TraceLog(@"  argv[%d]=%s", i, argv[i]);
        }
    }
    return orig_posix_spawn ? orig_posix_spawn(pid, path, file_actions, attrp, argv, envp) : -1;
}

static int my_execve(const char *path, char *const argv[], char *const envp[])
{
    TraceLog(@"execve(%s)", path ? path : "(null)");
    if (argv) {
        for (int i = 0; argv[i]; i++) {
            TraceLog(@"  argv[%d]=%s", i, argv[i]);
        }
    }
    return orig_execve ? orig_execve(path, argv, envp) : -1;
}

static int my_system(const char *command)
{
    TraceLog(@"system(%s)", command ? command : "(null)");
    return orig_system ? orig_system(command) : -1;
}

/* ===================== Objective-C hooks ===================== */

%hook NSFileManager

- (BOOL)copyItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)err
{
    TraceLog(@"NSFileManager copy %@ -> %@", src, dst);
    return %orig(src, dst, err);
}

- (BOOL)moveItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)err
{
    TraceLog(@"NSFileManager move %@ -> %@", src, dst);
    return %orig(src, dst, err);
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)err
{
    TraceLog(@"NSFileManager remove %@", path);
    return %orig(path, err);
}

- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary *)attr
{
    TraceLog(@"NSFileManager create %@ size=%lu", path, (unsigned long)data.length);
    return %orig(path, data, attr);
}

%end

/* ===================== ctor ===================== */

%ctor
{
    @autoreleasepool {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        gLogPath = [docs stringByAppendingPathComponent:@"patch_trace.log"];

        TraceLog(@"===== PatchTrace injected =====");
        TraceLog(@"Log file: %@", gLogPath);

        // File ops
        MSHookFunction((void *)open,   (void *)my_open,   (void **)&orig_open);
        MSHookFunction((void *)write,  (void *)my_write,  (void **)&orig_write);
        MSHookFunction((void *)close,  (void *)my_close,  (void **)&orig_close);
        MSHookFunction((void *)unlink, (void *)my_unlink, (void **)&orig_unlink);
        MSHookFunction((void *)rename, (void *)my_rename, (void **)&orig_rename);
        MSHookFunction((void *)mkdir,  (void *)my_mkdir,  (void **)&orig_mkdir);
        MSHookFunction((void *)rmdir,  (void *)my_rmdir,  (void **)&orig_rmdir);
        MSHookFunction((void *)chmod,  (void *)my_chmod,  (void **)&orig_chmod);

        // Process + load
        MSHookFunction((void *)posix_spawn, (void *)my_posix_spawn, (void **)&orig_posix_spawn);
        MSHookFunction((void *)execve,      (void *)my_execve,      (void **)&orig_execve);
        MSHookFunction((void *)dlopen,      (void *)my_dlopen,      (void **)&orig_dlopen);

        // system() is "unavailable" in modern SDK headers — hook it only via dlsym (no direct symbol reference)
        void *sysPtr = dlsym(RTLD_DEFAULT, "system");
        if (sysPtr) {
            MSHookFunction(sysPtr, (void *)my_system, (void **)&orig_system);
            TraceLog(@"Hooked system() via dlsym");
        } else {
            TraceLog(@"system() symbol not found (OK)");
        }
    }
}
