#import <Foundation/Foundation.h>
#import <substrate.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <errno.h>
#import <sys/time.h>

// 1. Resolve and cache the log path once. 
static const char *LogFilePath(void) {
    static char path[1024] = {0};
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        @autoreleasepool {
            NSString *documents = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
            [[NSFileManager defaultManager] createDirectoryAtPath:documents
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
            NSString *fullPath = [documents stringByAppendingPathComponent:@"tcp_log.txt"];
            strlcpy(path, [fullPath UTF8String], sizeof(path));
        }
    });
    q8
    return path;
}

// 2. Safe C-based address extraction
static void GetPeerAddress(int fd, char *buffer, size_t buf_size) {
    struct sockaddr_storage addr;
    socklen_t len = sizeof(addr);
    memset(&addr, 0, sizeof(addr));

    if (getpeername(fd, (struct sockaddr *)&addr, &len) != 0) {
        strlcpy(buffer, "unknown", buf_size);
        return;
    }

    if (addr.ss_family == AF_INET) {
        struct sockaddr_in *a = (struct sockaddr_in *)&addr;
        char ip[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &a->sin_addr, ip, sizeof(ip));
        snprintf(buffer, buf_size, "%s:%d", ip, ntohs(a->sin_port));
    } else if (addr.ss_family == AF_INET6) {
        struct sockaddr_in6 *a = (struct sockaddr_in6 *)&addr;
        char ip[INET6_ADDRSTRLEN];
        inet_ntop(AF_INET6, &a->sin6_addr, ip, sizeof(ip));
        snprintf(buffer, buf_size, "[%s]:%d", ip, ntohs(a->sin6_port));
    } else {
        strlcpy(buffer, "unknown", buf_size);
    }
}

static ssize_t (*orig_send)(int, const void *, size_t, int);
static ssize_t (*orig_recv)(int, void *, size_t, int);

// 3. High-performance, crash-safe C logger
static void LogTraffic(const char *direction, int fd, const void *buf, size_t requested, ssize_t actual) {
    if (actual <= 0 || !buf) return;

    FILE *f = fopen(LogFilePath(), "a");
    if (!f) return;

    char peer[128];
    GetPeerAddress(fd, peer, sizeof(peer));

    // Cap the dump size to 1024 bytes to prevent OOM crashes on huge packets
    size_t dump_len = (size_t)actual > 1024 ? 1024 : (size_t)actual;

    // Fast timestamp
    struct timeval tv;
    gettimeofday(&tv, NULL);
    struct tm *tm_info = localtime(&tv.tv_sec);
    char timebuf[32];
    strftime(timebuf, sizeof(timebuf), "%Y-%m-%d %H:%M:%S", tm_info);

    // Print Header
    fprintf(f, "[%s.%03d]\n========== TCP %s ==========\n", timebuf, (int)(tv.tv_usec / 1000), direction);
    fprintf(f, "FD: %d\nPeer: %s\nRequested: %zu bytes\nProcessed: %zd bytes\n", fd, peer, requested, actual);

    const unsigned char *bytes = (const unsigned char *)buf;

    // Print ASCII
    fprintf(f, "ASCII:\n");
    for (size_t i = 0; i < dump_len; i++) {
        unsigned char c = bytes[i];
        fputc((c >= 32 && c <= 126) ? c : '.', f);
    }
    fprintf(f, "\n");

    // Print HEX
    fprintf(f, "HEX:\n");
    for (size_t i = 0; i < dump_len; i++) {
        fprintf(f, "%02X ", bytes[i]);
        if ((i + 1) % 32 == 0) fprintf(f, "\n");
    }

    // Note if truncated
    if ((size_t)actual > dump_len) {
        fprintf(f, "\n... (truncated %zd bytes) ...", actual - dump_len);
    }
    
    fprintf(f, "\n\n");
    fclose(f);
}

static ssize_t hooked_send(int fd, const void *buf, size_t len, int flags) {
    ssize_t result = orig_send(fd, buf, len, flags);
    LogTraffic("SEND", fd, buf, len, result);
    return result;
}

static ssize_t hooked_recv(int fd, void *buf, size_t len, int flags) {
    ssize_t result = orig_recv(fd, buf, len, flags);
    LogTraffic("RECV", fd, buf, len, result);
    return result;
}

%ctor {
    // Standard system functions don't need MSFindSymbol. 
    // You can cast the system function pointers directly.
    MSHookFunction((void *)send, (void *)hooked_send, (void **)&orig_send);
    MSHookFunction((void *)recv, (void *)hooked_recv, (void **)&orig_recv);
}
