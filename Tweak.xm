#import <Foundation/Foundation.h>
#import <substrate.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <errno.h>
#import <time.h>

static ssize_t (*orig_send)(int, const void *, size_t, int);
static ssize_t (*orig_recv)(int, void *, size_t, int);

static NSString *LogPath(void) {
    static NSString *path = nil;

    if (!path) {
        NSString *documents =
            [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];

        [[NSFileManager defaultManager]
            createDirectoryAtPath:documents
            withIntermediateDirectories:YES
            attributes:nil
            error:nil];

        path = [documents stringByAppendingPathComponent:@"tcp_log.txt"];
    }

    return path;
}

static NSString *Timestamp(void) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    return [formatter stringFromDate:[NSDate date]];
}

static NSString *HexDump(const void *data, size_t length) {
    const unsigned char *bytes = data;

    NSMutableString *out =
        [NSMutableString stringWithCapacity:length * 3];

    for (size_t i = 0; i < length; i++) {
        [out appendFormat:@"%02X ", bytes[i]];

        // New line every 32 bytes for readability
        if ((i + 1) % 32 == 0)
            [out appendString:@"\n"];
    }

    return out;
}

static NSString *ASCIIData(const void *data, size_t length) {
    const unsigned char *bytes = data;

    NSMutableString *out =
        [NSMutableString stringWithCapacity:length];

    for (size_t i = 0; i < length; i++) {
        unsigned char c = bytes[i];

        if (c >= 32 && c <= 126) {
            [out appendFormat:@"%c", c];
        } else {
            [out appendString:@"."];
        }
    }

    return out;
}

static NSString *PeerAddress(int fd) {
    struct sockaddr_storage addr;
    socklen_t len = sizeof(addr);

    memset(&addr, 0, sizeof(addr));

    if (getpeername(fd, (struct sockaddr *)&addr, &len) != 0)
        return @"unknown";

    if (addr.ss_family == AF_INET) {
        struct sockaddr_in *a =
            (struct sockaddr_in *)&addr;

        char ip[INET_ADDRSTRLEN];

        inet_ntop(
            AF_INET,
            &a->sin_addr,
            ip,
            sizeof(ip)
        );

        return [NSString stringWithFormat:@"%s:%d",
                ip,
                ntohs(a->sin_port)];
    }

    if (addr.ss_family == AF_INET6) {
        struct sockaddr_in6 *a =
            (struct sockaddr_in6 *)&addr;

        char ip[INET6_ADDRSTRLEN];

        inet_ntop(
            AF_INET6,
            &a->sin6_addr,
            ip,
            sizeof(ip)
        );

        return [NSString stringWithFormat:@"[%s]:%d",
                ip,
                ntohs(a->sin6_port)];
    }

    return @"unknown";
}

static void WriteLog(NSString *text) {
    @autoreleasepool {
        NSString *line =
            [NSString stringWithFormat:
                @"[%@]\n%@\n\n",
                Timestamp(),
                text];

        NSFileHandle *file =
            [NSFileHandle fileHandleForWritingAtPath:LogPath()];

        if (!file) {
            [line writeToFile:LogPath()
                   atomically:YES
                     encoding:NSUTF8StringEncoding
                        error:nil];
            return;
        }

        [file seekToEndOfFile];

        NSData *data =
            [line dataUsingEncoding:NSUTF8StringEncoding];

        [file writeData:data];
        [file closeFile];
    }
}

static ssize_t hooked_send(
    int fd,
    const void *buf,
    size_t len,
    int flags
) {
    ssize_t result =
        orig_send(fd, buf, len, flags);

    if (result > 0) {
        @autoreleasepool {
            NSString *peer = PeerAddress(fd);

            NSString *log =
                [NSString stringWithFormat:
                    @"========== TCP SEND ==========\n"
                    @"FD: %d\n"
                    @"Peer: %@\n"
                    @"Requested: %zu bytes\n"
                    @"Sent: %zd bytes\n"
                    @"ASCII:\n%@\n"
                    @"HEX:\n%@",
                    fd,
                    peer,
                    len,
                    result,
                    ASCIIData(buf, (size_t)result),
                    HexDump(buf, (size_t)result)];

            WriteLog(log);
        }
    }

    return result;
}

static ssize_t hooked_recv(
    int fd,
    void *buf,
    size_t len,
    int flags
) {
    ssize_t result =
        orig_recv(fd, buf, len, flags);

    if (result > 0) {
        @autoreleasepool {
            NSString *peer = PeerAddress(fd);

            NSString *log =
                [NSString stringWithFormat:
                    @"========== TCP RECV ==========\n"
                    @"FD: %d\n"
                    @"Peer: %@\n"
                    @"Requested: %zu bytes\n"
                    @"Received: %zd bytes\n"
                    @"ASCII:\n%@\n"
                    @"HEX:\n%@",
                    fd,
                    peer,
                    len,
                    result,
                    ASCIIData(buf, (size_t)result),
                    HexDump(buf, (size_t)result)];

            WriteLog(log);
        }
    }

    return result;
}

%ctor {
    orig_send = (ssize_t (*)(int, const void *, size_t, int))
        MSFindSymbol(NULL, "_send");

    orig_recv = (ssize_t (*)(int, void *, size_t, int))
        MSFindSymbol(NULL, "_recv");

    if (orig_send) {
        MSHookFunction(
            (void *)orig_send,
            (void *)hooked_send,
            (void **)&orig_send
        );
    }

    if (orig_recv) {
        MSHookFunction(
            (void *)orig_recv,
            (void *)hooked_recv,
            (void **)&orig_recv
        );
    }
}
