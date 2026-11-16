/* SKPNetLog v2 — Soul Knight Prequel (iOS) TLS plaintext logger
 *
 * Hook points (UnityFramework, imagebase 0x0, verified in IDA):
 *   0x68095A4  il2cpp UnityTls read shim  (0x170 bytes): long f(void* state, void* buf, int* len)
 *   0x6809714  il2cpp UnityTls write shim (0x214 bytes): long f(void* state, const void* buf, int* len)
 *   0x6807A68  mono-btls read trampoline  (0x0B0 bytes): int  f(void* ssl, void* buf, size_t len)
 *   0x6807B18  mono-btls write trampoline (0x0AC bytes): int  f(void* ssl, void* buf, size_t len)
 *   (both pairs resolve "mono_btls_ssl_read"/"mono_btls_ssl_write" from libmono-btls-shared)
 *
 * Install strategy (crash-safe):
 *   Phase 1: wait for UnityFramework image, hook exported il2cpp_unity_install_unitytls_interface
 *   Phase 2: when that export is invoked by the engine (TLS subsystem initializing),
 *            install the 4 TLS I/O hooks + TQUIC hooks. Fallback timer installs phase 2
 *            after 20s if the export fired before we hooked it.
 *   All logging is mutex-protected (game does concurrent TLS I/O on worker threads).
 *
 * Kill switches (NSUserDefaults in the app's domain, standard defaults):
 *   SKPNetLog_Disable  = YES  -> do nothing
 *   SKPNetLog_HookNS   = YES  -> also log NSURLSession (default OFF)
 *
 * Output: <sandbox>/Documents/skpnet/skpnet_YYYYmmdd_HHMMSS.log
 */

#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <stdarg.h>
#import <time.h>
#import <pthread.h>
#import <unistd.h>
#import <zlib.h>

#ifdef __cplusplus
extern "C" {
#endif
void MSHookFunction(void *symbol, void *hook, void **result);
#ifdef __cplusplus
}
#endif

/* ---------------- config ---------------- */
#define ACC_MAX_BYTES   (8 * 1024 * 1024)
#define ACC_MAX_CHUNK   (2 * 1024 * 1024)

/* RVAs (imagebase 0) */
#define RVA_IL2CPP_TLS_READ_SHIM    0x68095A4UL
#define RVA_IL2CPP_TLS_WRITE_SHIM   0x6809714UL
#define RVA_BTLS_READ_TRAMPOLINE    0x6807A68UL
#define RVA_BTLS_WRITE_TRAMPOLINE   0x6807B18UL

/* ---------------- globals ---------------- */
static FILE         *g_log = NULL;
static char          g_dir[512];
static volatile int  g_phase2 = 0;
static volatile int  g_phase1 = 0;
static pthread_mutex_t g_lock;         /* recursive */
static void          g_lock_init_once = 0;

static void lock_init(void) {
    if (!g_lock_init_once) {
        pthread_mutexattr_t a;
        pthread_mutexattr_init(&a);
        pthread_mutexattr_settype(&a, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&g_lock, &a);
        pthread_mutexattr_destroy(&a);
        g_lock_init_once = 1;
    }
}

/* ---------------- kill switches ---------------- */
static BOOL sw_disable(void) { return [[NSUserDefaults standardUserDefaults] boolForKey:@"SKPNetLog_Disable"]; }
static BOOL sw_hook_ns(void) { return [[NSUserDefaults standardUserDefaults] boolForKey:@"SKPNetLog_HookNS"]; }

/* ---------------- log file ---------------- */
static FILE *open_log_locked(void) {
    @autoreleasepool {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *dir = [docs stringByAppendingPathComponent:@"skpnet"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"yyyyMMdd_HHmmss"];
        NSString *path = [dir stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"skpnet_%@.log", [df stringFromDate:[NSDate date]]]];
        strncpy(g_dir, dir.fileSystemRepresentation, sizeof(g_dir) - 1);
        g_dir[sizeof(g_dir) - 1] = 0;
        return fopen(path.fileSystemRepresentation, "ab");
    }
}

static void lprintf(const char *fmt, ...) {
    if (sw_disable()) return;
    lock_init();
    pthread_mutex_lock(&g_lock);
    if (!g_log) g_log = open_log_locked();
    if (g_log) {
        va_list ap; va_start(ap, fmt);
        vfprintf(g_log, fmt, ap);
        va_end(ap);
        fflush(g_log);
    }
    pthread_mutex_unlock(&g_lock);
}

static void now_stamp(char *out, size_t n) {
    struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tm; localtime_r(&ts.tv_sec, &tm);
    snprintf(out, n, "%04d-%02d-%02d %02d:%02d:%02d.%03ld",
             tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
             tm.tm_hour, tm.tm_min, tm.tm_sec, (long)(ts.tv_nsec / 1000000));
}

/* ---------------- buffers ---------------- */
typedef struct {
    unsigned char *data;
    size_t len, cap;
    int    got_head;
    size_t body_start;
    long   body_expected;   /* -1 = unknown/chunked */
    int    chunked;
    int    is_gzip;
    int    done;
} acc_t;

static void acc_reset(acc_t *a) {
    a->len = 0; a->got_head = 0; a->body_start = 0;
    a->body_expected = -1; a->chunked = 0; a->is_gzip = 0; a->done = 0;
}

static int acc_append(acc_t *a, const void *src, size_t n) {
    if (!src || n == 0) return 1;
    if (n > ACC_MAX_CHUNK) n = ACC_MAX_CHUNK;
    /* hard cap: never grow beyond what we are allowed to store */
    if (a->len >= ACC_MAX_BYTES) { a->done = 1; return 1; }   /* overflow guard: mark to skip */
    size_t room = ACC_MAX_BYTES - a->len - 1;
    if (n > room) n = room;

    if (a->len + n + 1 > a->cap) {
        size_t ncap = a->cap ? a->cap : 16384;
        while (ncap < a->len + n + 1) ncap *= 2;
        unsigned char *nd = (unsigned char *)realloc(a->data, ncap);
        if (!nd) { a->done = 1; return 1; }
        a->data = nd; a->cap = ncap;
    }
    memcpy(a->data + a->len, src, n);
    a->len += n;
    a->data[a->len] = 0;
    return 1;
}

/* ---------------- gzip ---------------- */
static int gunzip(const unsigned char *in, size_t inlen, unsigned char **out, size_t *outlen) {
    size_t cap = inlen * 6 + 256;
    for (int attempt = 0; attempt < 8; attempt++) {
        unsigned char *buf = (unsigned char *)malloc(cap);
        if (!buf) return 0;
        z_stream zs; memset(&zs, 0, sizeof(zs));
        if (inflateInit2(&zs, 15 + 32) != Z_OK) { free(buf); return 0; }
        zs.next_in = (Bytef *)in; zs.avail_in = (uInt)inlen;
        zs.next_out = buf; zs.avail_out = (uInt)cap;
        int rc = inflate(&zs, Z_FINISH);
        size_t produced = cap - zs.avail_out;
        inflateEnd(&zs);
        if (rc == Z_STREAM_END || rc == Z_OK) { *out = buf; *outlen = produced; return 1; }
        free(buf);
        if (rc == Z_BUF_ERROR) { cap *= 4; continue; }
        return 0;
    }
    return 0;
}

static void printable_dump(const unsigned char *p, size_t n, char *out, size_t outcap) {
    if (!out || outcap == 0) return;
    size_t o = 0;
    for (size_t i = 0; i < n && o < outcap - 1; i++) {
        unsigned char c = p[i];
        out[o++] = (c >= 0x20 && c < 0x7f) ? (char)c : (c == '\n' || c == '\r' || c == '\t') ? (char)c : '.';
    }
    out[o] = 0;
}

/* ---------------- HTTP ---------------- */
static int http_header_value(const char *head, size_t headlen, const char *name,
                             char *val, size_t valcap) {
    size_t nlen = strlen(name);
    const char *p = head, *end = head + headlen;
    while (p < end) {
        const char *eol = (const char *)memchr(p, '\n', (size_t)(end - p));
        if (!eol) break;
        size_t linelen = (size_t)(eol - p);
        if (linelen > nlen + 1 && strncasecmp(p, name, nlen) == 0 && p[nlen] == ':') {
            const char *v = p + nlen + 1;
            while (v < eol && *v == ' ') v++;
            size_t vl = (size_t)(eol - v);
            while (vl && (v[vl-1] == '\r' || v[vl-1] == ' ')) vl--;
            if (vl >= valcap) vl = valcap - 1;
            memcpy(val, v, vl); val[vl] = 0;
            return 1;
        }
        p = eol + 1;
    }
    return 0;
}

static void log_record(const char *tag, void *conn, const char *head, size_t headlen,
                       const unsigned char *body, size_t bodylen, int is_gzip) {
    char stamp[64]; now_stamp(stamp, sizeof(stamp));
    char *headbuf = (char *)malloc(headlen + 2);
    if (!headbuf) return;
    memcpy(headbuf, head, headlen);
    headbuf[headlen] = 0;
    for (size_t i = 0; i < headlen; i++)
        if ((unsigned char)headbuf[i] < 0x20 && headbuf[i] != '\n' && headbuf[i] != '\r') headbuf[i] = ' ';

    lock_init();
    pthread_mutex_lock(&g_lock);
    lprintf("================================================================\n");
    lprintf("[%s] %s conn=%p headlen=%zu bodylen=%zu%s\n", tag, stamp, conn,
            headlen, bodylen, is_gzip ? " (body gzipped)" : "");
    lprintf("%s\n", headbuf);

    unsigned char *dec = NULL; size_t declen = 0;
    const unsigned char *show = body; size_t shown = bodylen;
    if (is_gzip && body && bodylen && gunzip(body, bodylen, &dec, &declen)) {
        show = dec; shown = declen;
        lprintf("--- gunzip: %zu -> %zu bytes\n", bodylen, declen);
    }
    if (show && shown) {
        char *pb = (char *)malloc(shown + 1);
        if (pb) {
            printable_dump(show, shown, pb, shown + 1);
            lprintf("--- body (%zu bytes):\n%s\n", shown, pb);
            free(pb);
        }
    }
    if (dec) free(dec);
    free(headbuf);
    pthread_mutex_unlock(&g_lock);
}

static int acc_try_complete(acc_t *a, void *conn, const char *tag) {
    if (a->done || a->len < 8 || !a->data) return 0;
    if (!a->got_head) {
        const char *head_end = (a->len >= 4) ? (const char *)memmem(a->data, a->len, "\r\n\r\n", 4) : NULL;
        if (!head_end) return 0;
        a->got_head = 1;
        a->body_start = (size_t)(head_end - (const char *)a->data) + 4;
        char clen[32] = {0}, cenc[64] = {0}, cte[64] = {0};
        http_header_value((const char *)a->data, a->body_start, "Content-Length", clen, sizeof(clen));
        http_header_value((const char *)a->data, a->body_start, "Content-Encoding", cenc, sizeof(cenc));
        http_header_value((const char *)a->data, a->body_start, "Transfer-Encoding", cte, sizeof(cte));
        a->body_expected = clen[0] ? strtol(clen, NULL, 10) : -1;
        if (strstr(cte, "chunked")) a->chunked = 1;
        a->is_gzip = (strstr(cenc, "gzip") != NULL) ||
                     (a->len > a->body_start + 1 &&
                      a->data[a->body_start] == 0x1f && a->data[a->body_start + 1] == 0x8b);
    }
    size_t bodylen = a->len - a->body_start;
    if (!a->chunked && a->body_expected >= 0) {
        if (bodylen < (size_t)a->body_expected) return 0;
        bodylen = (size_t)a->body_expected;
    } else if (a->chunked) {
        if (a->len < a->body_start + 5) return 0;
        if (!memmem(a->data + a->body_start, a->len - a->body_start, "0\r\n\r\n", 5)) return 0;
        bodylen = a->len - a->body_start;   /* stays chunk-encoded in log */
    } else {
        /* no content-length and not chunked: treat as complete on next record gap —
           fall back: if body looks like a new HTTP record started, cut here */
        return 0;
    }
    a->done = 1;
    log_record(tag, conn, (const char *)a->data, a->body_start,
               a->data + a->body_start, bodylen, a->is_gzip);
    return 1;
}

/* ---------------- connection table (mutex-protected) ---------------- */
typedef struct { void *key; acc_t out; acc_t in; } conn_t;
#define MAX_CONNS 128
static conn_t g_conns[MAX_CONNS];

static conn_t *conn_get(void *key) {
    if (!key) return NULL;
    lock_init();
    pthread_mutex_lock(&g_lock);
    conn_t *free_slot = NULL;
    for (int i = 0; i < MAX_CONNS; i++) {
        if (g_conns[i].key == key) {
            pthread_mutex_unlock(&g_lock);
            return &g_conns[i];
        }
        if (!g_conns[i].key && !free_slot) free_slot = &g_conns[i];
    }
    if (!free_slot) {
        free_slot = &g_conns[0];
        if (free_slot->out.data) { free(free_slot->out.data); free_slot->out.data = NULL; }
        if (free_slot->in.data)  { free(free_slot->in.data);  free_slot->in.data = NULL; }
        memset(free_slot, 0, sizeof(*free_slot));
    }
    memset(free_slot, 0, sizeof(*free_slot));
    free_slot->key = key;
    free_slot->out.body_expected = -1;
    free_slot->in.body_expected = -1;
    pthread_mutex_unlock(&g_lock);
    return free_slot;
}

static void conn_feed(void *key, int is_out, const void *buf, size_t n) {
    if (sw_disable() || !buf || n == 0) return;
    conn_t *c = conn_get(key);
    if (!c) return;
    acc_t *a = is_out ? &c->out : &c->in;
    pthread_mutex_lock(&g_lock);
    if (!a->done) {
        if (acc_append(a, buf, n) && acc_try_complete(a, key, is_out ? ">>> OUT" : "<<< IN ")) {
            acc_reset(a);
        }
    }
    pthread_mutex_unlock(&g_lock);
}

/* ---------------- TLS hooks ---------------- */
/* il2cpp UnityTls shims: long f(void* state, void* buf, int* len) */
typedef long (*tls_shim_t)(void *state, void *buf, int *len);
/* mono-btls trampolines: int f(void* ssl, void* buf, size_t len) */
typedef int (*btls_io_t)(void *ssl, void *buf, size_t len);

static tls_shim_t orig_shim_read = NULL, orig_shim_write = NULL;
static btls_io_t  orig_tramp_read = NULL, orig_tramp_write = NULL;

static long my_shim_write(void *state, void *buf, int *len) {
    long rc = orig_shim_write(state, buf, len);
    int written = (rc == 0 && len) ? *len : 0;
    if (written > 0 && buf) conn_feed(state, 1, buf, (size_t)written);
    return rc;
}

static long my_shim_read(void *state, void *buf, int *len) {
    long rc = orig_shim_read(state, buf, len);
    if (rc == 0 && buf && len && *len > 0) conn_feed(state, 0, buf, (size_t)*len);
    return rc;
}

static int my_tramp_write(void *ssl, void *buf, size_t len) {
    if (buf && len) conn_feed(ssl, 1, buf, len);
    return orig_tramp_write(ssl, buf, len);
}

static int my_tramp_read(void *ssl, void *buf, size_t len) {
    int r = orig_tramp_read(ssl, buf, len);
    if (r > 0 && buf) conn_feed(ssl, 0, buf, (size_t)r);
    return r;
}

/* ---------------- TQUIC ---------------- */
typedef void (*quic_addheaders_t)(void *self, const char *a, const char *b, char c);
typedef void (*quic_sendrequest_t)(void *self, const char *a, int b, char c);
static quic_addheaders_t  orig_quic_addheaders = NULL;
static quic_sendrequest_t orig_quic_sendrequest = NULL;

static void my_quic_addheaders(void *self, const char *a, const char *b, char c) {
    char stamp[64]; now_stamp(stamp, sizeof(stamp));
    lprintf("----------------------------------------------------------------\n");
    lprintf("[QUIC-HDR] %s conn=%p a=%s b=%s c=%d\n", stamp, self,
            a ? a : "(null)", b ? b : "(null)", (int)c);
    orig_quic_addheaders(self, a, b, c);
}

static void my_quic_sendrequest(void *self, const char *a, int b, char c) {
    char stamp[64]; now_stamp(stamp, sizeof(stamp));
    lprintf("----------------------------------------------------------------\n");
    lprintf("[QUIC-REQ] %s conn=%p len=%d flag=%d\n", stamp, self, b, (int)c);
    if (a && b > 0 && b < (1 << 20)) {
        char *pb = (char *)malloc((size_t)b + 1);
        if (pb) {
            printable_dump((const unsigned char *)a, (size_t)b, pb, (size_t)b + 1);
            lprintf("--- body:\n%s\n", pb);
            free(pb);
        }
    }
    orig_quic_sendrequest(self, a, b, c);
}

/* ---------------- NSURLSession (opt-in) ---------------- */
%group NSURLSessionLog
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    if (!sw_disable() && sw_hook_ns()) {
        @try {
            char stamp[64]; now_stamp(stamp, sizeof(stamp));
            NSString *meth = request.HTTPMethod ?: @"GET";
            lprintf("----------------------------------------------------------------\n");
            lprintf("[NS-REQ] %s %s %s\n", stamp, meth.UTF8String ?: "GET",
                    request.URL.absoluteString.UTF8String ?: "(null)");
            NSDictionary *hs = request.allHTTPHeaderFields;
            for (NSString *k in hs)
                lprintf("    %s: %s\n", k.UTF8String ?: "?", [[hs objectForKey:k] UTF8String] ?: "?");
            NSData *b = request.HTTPBody;
            if (b.length) {
                size_t n = (size_t)b.length > 16384 ? 16384 : (size_t)b.length;
                char *pb = (char *)malloc(n + 1);
                if (pb) {
                    printable_dump((const unsigned char *)b.bytes, n, pb, n + 1);
                    lprintf("--- body (%lu bytes):\n%s\n", (unsigned long)b.length, pb);
                    free(pb);
                }
            }
        } @catch (id e) {}
    }
    return %orig;
}
%end
%end

/* ---------------- base / install ---------------- */
static void *get_base_unityframework(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework")) {
            return (void *)(_dyld_get_image_header(i) + _dyld_get_image_vmaddr_slide(i));
        }
    }
    return NULL;
}

static int safe_hook(void *target, void *hook, void **orig) {
    if (!target || !hook) return 0;
    unsigned char first[4];
    memcpy(first, target, 4);
    static const unsigned char z[4] = {0, 0, 0, 0};
    if (!memcmp(first, z, 4)) return 0;      /* sanity: not mapped/zeroed */
    MSHookFunction(target, hook, orig);
    return 1;
}

static void install_phase2(void) {
    if (g_phase2 || sw_disable()) return;
    void *base = get_base_unityframework();
    if (!base) return;

    safe_hook((void *)((uintptr_t)base + RVA_IL2CPP_TLS_WRITE_SHIM),  (void *)my_shim_write,  (void **)&orig_shim_write);
    safe_hook((void *)((uintptr_t)base + RVA_IL2CPP_TLS_READ_SHIM),   (void *)my_shim_read,   (void **)&orig_shim_read);
    safe_hook((void *)((uintptr_t)base + RVA_BTLS_WRITE_TRAMPOLINE),  (void *)my_tramp_write, (void **)&orig_tramp_write);
    safe_hook((void *)((uintptr_t)base + RVA_BTLS_READ_TRAMPOLINE),   (void *)my_tramp_read,  (void **)&orig_tramp_read);

    /* TQUIC — installed lazily here; framework may not be loaded yet, retry below */
    void *h = dlopen("@rpath/Tquic.framework/Tquic", RTLD_LAZY);
    if (!h) h = dlopen("Tquic", RTLD_LAZY);
    if (h) {
        void *p1 = dlsym(h, "__ZN15TnetQuicRequest10AddHeadersEPKcS1_b");
        void *p2 = dlsym(h, "__ZN15TnetQuicRequest11SendRequestEPKcib");
        if (p1) safe_hook(p1, (void *)my_quic_addheaders,  (void **)&orig_quic_addheaders);
        if (p2) safe_hook(p2, (void *)my_quic_sendrequest, (void **)&orig_quic_sendrequest);
    }

    g_phase2 = 1;
    char stamp[64]; now_stamp(stamp, sizeof(stamp));
    lprintf("[SKPNetLog] phase2 installed %s base=%p\n", stamp, base);
}

/* Phase 1: hook the exported interface installer — perfect timing signal */
typedef void (*install_unitytls_t)(const void *iface);
static install_unitytls_t orig_install_unitytls = NULL;

static void my_install_unitytls(const void *iface) {
    orig_install_unitytls(iface);
    install_phase2();
}

static void *watchdog(void *arg) {
    for (int i = 0; i < 1200 && !g_phase1 && !sw_disable(); i++) {  /* up to ~120s */
        void *base = get_base_unityframework();
        if (base) {
            /* resolve the export on the already-loaded image */
            for (uint32_t j = 0; j < _dyld_image_count(); j++) {
                const char *nm = _dyld_get_image_name(j);
                if (strstr(nm, "UnityFramework")) {
                    void *h = dlopen(nm, RTLD_LAZY | RTLD_NOLOAD);
                    if (h) {
                        void *p = dlsym(h, "il2cpp_unity_install_unitytls_interface");
                        if (p && safe_hook(p, (void *)my_install_unitytls, (void **)&orig_install_unitytls)) {
                            g_phase1 = 1;
                            lprintf("[SKPNetLog] phase1 hooked il2cpp_unity_install_unitytls_interface\n");
                        }
                    }
                    break;
                }
            }
            break;
        }
        usleep(100000);
    }
    /* fallback: if engine called the export before our phase-1 hook was ready */
    for (int i = 0; i < 200 && !g_phase2 && !sw_disable(); i++) {   /* up to 20s */
        usleep(100000);
    }
    if (!g_phase2 && !sw_disable()) install_phase2();
    /* late TQUIC retry in case the framework wasn't loaded during phase 2 */
    for (int i = 0; i < 300 && !orig_quic_addheaders && !sw_disable(); i++) {
        usleep(100000);
        void *h = dlopen("@rpath/Tquic.framework/Tquic", RTLD_LAZY);
        if (!h) h = dlopen("Tquic", RTLD_LAZY);
        if (h) {
            void *p1 = dlsym(h, "__ZN15TnetQuicRequest10AddHeadersEPKcS1_b");
            void *p2 = dlsym(h, "__ZN15TnetQuicRequest11SendRequestEPKcib");
            if ((p1 || p2) && g_phase2) {
                if (p1) safe_hook(p1, (void *)my_quic_addheaders,  (void **)&orig_quic_addheaders);
                if (p2) safe_hook(p2, (void *)my_quic_sendrequest, (void **)&orig_quic_sendrequest);
                break;
            }
        }
    }
    return NULL;
}

%ctor {
    @autoreleasepool {
        lock_init();
        if (sw_disable()) return;
        %init(NSURLSessionLog);
        lprintf("[SKPNetLog] v2 injected pid=%d\n", getpid());
        pthread_t t;
        if (pthread_create(&t, NULL, watchdog, NULL) == 0) pthread_detach(t);
    }
}
