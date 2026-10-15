// Original TempMail SHA256: 089555f848e2cfe6e53264edaa213214dca2c64305abe59151e157ed0c050fa1
// Passive response observer. No integrity patch, signal handler or automatic login.
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <cstring>
#include <cstdio>
#include <cstdint>
#include <pthread.h>

using Perform = int (*)(void *);
using Writer = size_t (*)(char *, size_t, size_t, void *);
static Perform originalPerform;
static NSString *directory;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned sequence;
static thread_local bool insidePerform;

static void Log(NSString *message) {
    int saved = errno;
    NSLog(@"[TempMailTrace pid=%d] %@", getpid(), message);
    if (directory) {
        NSString *path = [directory stringByAppendingPathComponent:
            [NSString stringWithFormat:@"TempMailTrace-%d.log", getpid()]];
        pthread_mutex_lock(&lock);
        int fd = open(path.fileSystemRepresentation, O_WRONLY|O_APPEND|O_CREAT|O_CLOEXEC|O_NOFOLLOW, 0600);
        if (fd >= 0) {
            NSData *data = [[message stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
            const char *p = (const char *)data.bytes;
            size_t left = data.length;
            while (left) {
                ssize_t n = write(fd,p,left);
                if (n < 0 && errno == EINTR) continue;
                if (n <= 0) break;
                p += n; left -= (size_t)n;
            }
            close(fd);
        }
        pthread_mutex_unlock(&lock);
    }
    errno = saved;
}

struct Capture {
    Writer writer;
    void *userdata;
    int fd;
    size_t stored;
    bool truncated;
    bool ioError;
};

static size_t ObserveBody(char *ptr, size_t size, size_t count, void *opaque) {
    Capture *c = (Capture *)opaque;
    int saved = errno;
    if (size && count > SIZE_MAX/size) {
        errno = saved;
        return c->writer(ptr,size,count,c->userdata);
    }
    size_t bytes = size*count;
    // ponytail: first 1 MiB per response; raise only for a specifically needed larger capture.
    size_t room = 1024*1024-c->stored;
    size_t wanted = bytes < room ? bytes : room;
    c->truncated |= wanted < bytes;
    if (c->fd >= 0) {
        size_t done=0;
        while (done<wanted) {
            ssize_t n=write(c->fd,ptr+done,wanted-done);
            if (n<0 && errno==EINTR) continue;
            if (n<=0) { c->ioError=true; break; }
            done+=(size_t)n;
        }
        c->stored+=done;
    }
    errno=saved;
    // Preserve the original consumer and its exact return value, including pause/error.
    return c->writer(ptr,size,count,c->userdata);
}

template<typename T> static T Read(void *handle,size_t offset) {
    T result; memcpy(&result,(char *)handle+offset,sizeof(result)); return result;
}
template<typename T> static void Store(void *handle,size_t offset,T value) {
    memcpy((char *)handle+offset,&value,sizeof(value));
}

static int ObservePerform(void *handle) {
    if (!handle || insidePerform || Read<uint32_t>(handle,0)!=0xc0dedbad)
        return originalPerform(handle);
    insidePerform=true;
    Writer writer=Read<Writer>(handle,520);
    void *userdata=Read<void *>(handle,448);
    if (!writer) { insidePerform=false; return originalPerform(handle); }
    pthread_mutex_lock(&lock);
    unsigned id=++sequence;
    pthread_mutex_unlock(&lock);
    NSString *path=directory ? [directory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"response-%d-%u.bin",getpid(),id]] : nil;
    Capture capture{writer,userdata,-1,0,false,false};
    if (path) capture.fd=open(path.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_CLOEXEC|O_NOFOLLOW,0600);
    const char *url=Read<const char *>(handle,2088);
    NSString *address=url ? [[NSString alloc] initWithBytes:url length:strnlen(url,8192) encoding:NSUTF8StringEncoding] : nil;
    // Do not log query/userinfo: may contain credentials. Raw response stays in private file only.
    NSURLComponents *parts=address ? [NSURLComponents componentsWithString:address] : nil;
    parts.query=nil; parts.fragment=nil; parts.user=nil; parts.password=nil;
    Log([NSString stringWithFormat:@"BEGIN id=%u endpoint=%@ bodyFile=%@ fileOpen=%d",id,parts.string ?: @"unavailable",path,capture.fd>=0]);
    Store<Writer>(handle,520,ObserveBody);
    Store<void *>(handle,448,&capture);
    int result=originalPerform(handle);
    int saved=errno;
    Store<Writer>(handle,520,writer);
    Store<void *>(handle,448,userdata);
    if(capture.fd>=0) close(capture.fd);
    Log([NSString stringWithFormat:@"END id=%u CURLcode=%d captured=%zu truncated=%d writeError=%d (not HTTP status)",id,result,capture.stored,capture.truncated,capture.ioError]);
    insidePerform=false;
    errno=saved;
    return result;
}

__attribute__((constructor)) static void InstallTrace(void) {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"TempMail"]) return;
        NSURL *docs=[[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
        directory=docs.path;
        Log([NSString stringWithFormat:@"START mode=%@ Documents=%@",[NSProcessInfo.processInfo.arguments containsObject:@"-a"] ? @"child" : @"main",directory]);
        const mach_header *header=_dyld_get_image_header(0);
        if (!header || header->cputype!=CPU_TYPE_ARM64) { Log(@"SKIP unsupported image"); return; }
        const char *name=_dyld_get_image_name(0);
        if (!name || ![[[NSString stringWithUTF8String:name] lastPathComponent] isEqualToString:@"TempMail"]) { Log(@"SKIP wrong executable"); return; }
        uintptr_t base=(uintptr_t)header;
        const unsigned char expected[]={0x60,0x02,0x00,0xb4,0xff,0xc3,0x01,0xd1,0xf6,0x57,0x04,0xa9,0xf4,0x4f,0x05,0xa9};
        if (memcmp((void *)(base+0xba7c90),expected,sizeof(expected))!=0) { Log(@"SKIP perform fingerprint mismatch"); return; }
        using Hook=void (*)(void *,void *,void **);
        Hook hook=(Hook)dlsym(RTLD_DEFAULT,"MSHookFunction");
        if (!hook) { Log(@"SKIP MSHookFunction unavailable; no unsafe inline fallback"); return; }
        // A real relocating hook engine is required. Runtime code mutation may trigger integrity checks.
        hook((void *)(base+0xba7c90),(void *)ObservePerform,(void **)&originalPerform);
        if (!originalPerform) { Log(@"ERROR hook engine returned no trampoline"); return; }
        Log(@"READY response observer; enter your own test key manually. No auth bypass or auto-request.");
    }
}
