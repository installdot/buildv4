/* SKPNetLog v3 — Soul Knight Prequel (iOS) TLS plaintext logger
 *
 * TARGETS: TrollFools / TrollStore / sideload injection (NO Substrate, NO ElleKit,
 *          NO libhooker). This build performs NO code patching at all — no
 *          MSHookFunction, no logos, no inline hooks, no trampolines.
 *
 * HOW IT HOOKS (pure data-pointer swap, verified in IDA):
 *   UnityFramework keeps two writable globals holding the resolved BoringSSL
 *   I/O entry points (mono-btls = BoringSSL embedded in the engine):
 *     RVA 0x9870000  -> pointer to mono_btls_ssl_read   (int f(void* ssl, void* buf, int len))
 *     RVA 0x9870008  -> pointer to mono_btls_ssl_write  (int f(void* ssl, const void* buf, int len))
 *   Both the il2cpp UnityTls shims (0x68095A4 read / 0x6809714 write) and the
 *   mono-side trampolines (0x6807A68 / 0x6807B18) call through exactly these two
 *   globals (6 data xrefs each — the only interception points in the image).
 *   They live in writable __data (the engine itself writes them), so replacing
 *   the pointers is safe, reversible, and needs no code-signing bypass.
 *
 * TIMING: wait until the engine has resolved them (non-NULL) => TLS subsystem is
 *   live and every call will route through our wrappers. A re-arm thread keeps
 *   the pointers swapped if the engine ever re-resolves them.
 *
 * Kill switch (NSUserDefaults of the app):
 *   SKPNetLog_Disable = YES  -> tweak inert
 *   SKPNetLog_HookNS  = YES  -> also log NSURLSession (objective-c runtime swizzle, default OFF)
 *
 * Output: <sandbox>/Documents/skpnet/skpnet_YYYYmmdd_HHMMSS.log
 */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <stdarg.h>
#import <time.h>
#import <pthread.h>
#import <unistd.h>
#import <zlib.h>

/* ---------------- config ---------------- */
#define ACC_MAX_BYTES   (8 * 1024 * 1024)
#define ACC_MAX_CHUNK   (2 * 1024 * 1024)

/* RVA of the two BoringSSL I/O pointers (imagebase 0) */
#define RVA_PTR_SSL_READ   0x9870000UL
#define RVA_PTR_SSL_WRITE  0x9870008UL

/* ---------------- globals ---------------- */
static FILE         *g_log = NULL;
static char          g_dir[512];
static volatile int  g_installed = 0;
static volatile int  g_stop = 0;
static pthread_mutex_t g_lock;
static volatile int  g_lock_init = 0;

static void lock_init(void) {
    if (g_lock_init) return;
    pthread_mutexattr_t a;
    pthread_mutexattr_init(&a);
    pthread_mutexattr_settype(&a, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&g_lock, &a);
    pthread_mutexattr_destroy(&a);
    g_lock_init = 1;
}

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
        const char *fp = path.fileSystemRepresentation;
        const char *dp = dir.fileSystemRepresentation;
        if (dp) { strncpy(g_dir, dp, sizeof(g_dir) - 1); g_dir[sizeof(g_dir) - 1] = 0; }
        return fp ? fopen(fp, "ab") : NULL;
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
    long   body_expected;
    int    chunked;
    int    is_gzip;
    int    done;
} acc_t;

static void acc_reset(acc_t *a) {
    a->len = 0; a->got_head = 0; a->body_start = 0;
    a->body_expected = -1; a->chunked = 0; a->is_gzip = 0; a->done = 0;
}

static void acc_append(acc_t *a, const void *src, size_t n) {
    if (!src || !n || a->done) return;
    if (n > ACC_MAX_CHUNK) n = ACC_MAX_CHUNK;
    if (a->len >= ACC_MAX_BYTES) { a->done = 1; return; }
    size_t room = ACC_MAX_BYTES - a->len - 1;
    if (n > room) n = room;
    if (a->len + n + 1 > a->cap) {
        size_t ncap = a->cap ? a->cap : 16384;
        while (ncap < a->len + n + 1) ncap *= 2;
        unsigned char *nd = (unsigned char *)realloc(a->data, ncap);
        if (!nd) { a->done = 1; return; }
        a->data = nd; a->cap = ncap;
    }
    memcpy(a->data + a->len, src, n);
    a->len += n;
    a->data[a->len] = 0;
}

/* ---------------- gzip ---------------- */
static int gunzip_buf(const unsigned char *in, size_t inlen, unsigned char **out, size_t *outlen) {
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
    if (!out || !outcap) return;
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
    lprintf("[%s] %s conn=%p head=%zu body=%zu%s\n", tag, stamp, conn,
            headlen, bodylen, is_gzip ? " (gzip)" : "");
    lprintf("%s\n", headbuf);

    unsigned char *dec = NULL; size_t declen = 0;
    const unsigned char *show = body; size_t shown = bodylen;
    if (is_gzip && body && bodylen && gunzip_buf(body, bodylen, &dec, &declen)) {
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
        const char *he = (const char *)memmem(a->data, a->len, "\r\n\r\n", 4);
        if (!he) return 0;
        a->got_head = 1;
        a->body_start = (size_t)(he - (const char *)a->data) + 4;
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
        bodylen = a->len - a->body_start;
    } else {
        /* no length info: only flush if a new record clearly started */
        const char *nxt = (a->len > 8)
            ? (const char *)memmem(a->data + 8, a->len - 8, "HTTP/1.", 7) : NULL;
        if (!nxt) return 0;
        bodylen = (size_t)(nxt - (const char *)a->data);
        a->done = 1;
        log_record(tag, conn, (const char *)a->data, a->body_start,
                   a->data + a->body_start, bodylen > a->body_start ? bodylen - a->body_start : 0, a->is_gzip);
        return 1;
    }
    a->done = 1;
    log_record(tag, conn, (const char *)a->data, a->body_start,
               a->data + a->body_start, bodylen, a->is_gzip);
    return 1;
}

/* ---------------- connection table ---------------- */
typedef struct { void *key; acc_t out; acc_t in; } conn_t;
#define MAX_CONNS 128
static conn_t g_conns[MAX_CONNS];

static conn_t *conn_get(void *key) {
    if (!key) return NULL;
    lock_init();
    pthread_mutex_lock(&g_lock);
    conn_t *slot = NULL;
    for (int i = 0; i < MAX_CONNS; i++) {
        if (g_conns[i].key == key) { pthread_mutex_unlock(&g_lock); return &g_conns[i]; }
        if (!g_conns[i].key && !slot) slot = &g_conns[i];
    }
    if (!slot) {
        slot = &g_conns[0];
        if (slot->out.data) { free(slot->out.data); slot->out.data = NULL; }
        if (slot->in.data)  { free(slot->in.data);  slot->in.data = NULL; }
        memset(slot, 0, sizeof(*slot));
    }
    memset(slot, 0, sizeof(*slot));
    slot->key = key;
    slot->out.body_expected = -1;
    slot->in.body_expected = -1;
    pthread_mutex_unlock(&g_lock);
    return slot;
}

static void conn_feed(void *key, int is_out, const void *buf, size_t n) {
    if (sw_disable() || !buf || !n) return;
    conn_t *c = conn_get(key);
    if (!c) return;
    acc_t *a = is_out ? &c->out : &c->in;
    pthread_mutex_lock(&g_lock);
    if (!a->done) {
        acc_append(a, buf, n);
        if (acc_try_complete(a, key, is_out ? ">>> OUT" : "<<< IN ")) acc_reset(a);
    }
    pthread_mutex_unlock(&g_lock);
}

/* ---------------- BoringSSL wrappers (data-pointer swap) ---------------- */
/* Real signatures: int mono_btls_ssl_read(void* ssl, void* buf, int len)
 *                  int mono_btls_ssl_write(void* ssl, const void* buf, int len) */
typedef int (*btls_read_t)(void *ssl, void *buf, int len);
typedef int (*btls_write_t)(void *ssl, const void *buf, int len);

static btls_read_t  g_orig_read  = NULL;
static btls_write_t g_orig_write = NULL;

static int my_btls_write(void *ssl, const void *buf, int len) {
    if (!g_orig_write) return -1;
    int n = g_orig_write(ssl, buf, len);
    if (n > 0 && buf) conn_feed(ssl, 1, buf, (size_t)n);
    return n;
}

static int my_btls_read(void *ssl, void *buf, int len) {
    if (!g_orig_read) return -1;
    int n = g_orig_read(ssl, buf, len);
    if (n > 0 && buf) conn_feed(ssl, 0, buf, (size_t)n);
    return n;
}

/* ---------------- NSURLSession (optional, runtime swizzle) ---------------- */
static IMP g_orig_dataTask = NULL;

static id my_dataTask(id self, SEL _cmd, NSURLRequest *req, id handler) {
    if (!sw_disable() && sw_hook_ns()) {
        @try {
            char stamp[64]; now_stamp(stamp, sizeof(stamp));
            NSString *meth = req.HTTPMethod ?: @"GET";
            NSString *url  = req.URL.absoluteString ?: @"(null)";
            lprintf("----------------------------------------------------------------\n");
            lprintf("[NS-REQ] %s %s %s\n", stamp, meth.UTF8String ?: "GET", url.UTF8String ?: "?");
            NSDictionary *hs = req.allHTTPHeaderFields;
            for (NSString *k in hs)
                lprintf("    %s: %s\n", k.UTF8String ?: "?", [[hs objectForKey:k] UTF8String] ?: "?");
            NSData *b = req.HTTPBody;
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
    if (!g_orig_dataTask) return nil;
    id (*fn)(id, SEL, NSURLRequest *, id) = (id (*)(id, SEL, NSURLRequest *, id))g_orig_dataTask;
    return fn(self, _cmd, req, handler);
}

static void install_ns_hook(void) {
    @autoreleasepool {
        Class cls = objc_getClass("NSURLSession");
        if (!cls) return;
        SEL sel = @selector(dataTaskWithRequest:completionHandler:);
        Method m = class_getInstanceMethod(cls, sel);
        if (!m) return;
        g_orig_dataTask = method_setImplementation(m, (IMP)my_dataTask);
        lprintf("[SKPNetLog] NSURLSession swizzled\n");
    }
}

/* ---------------- base / install ---------------- */
static void *get_base_unityframework(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework"))
            return (void *)(_dyld_get_image_header(i) + _dyld_get_image_vmaddr_slide(i));
    }
    return NULL;
}

/* swap a pointer in writable data; returns previous value */
static void *swap_ptr(void *base, unsigned long rva, void *newval) {
    void **slot = (void **)((uintptr_t)base + rva);
    void *old = *slot;
    *slot = newval;
    return old;
}

static void rearm_once(void *base) {
    void **rslot = (void **)((uintptr_t)base + RVA_PTR_SSL_READ);
    void **wslot = (void **)((uintptr_t)base + RVA_PTR_SSL_WRITE);
    if (*rslot && *rslot != (void *)my_btls_read) {
        if (!g_orig_read) g_orig_read = (btls_read_t)*rslot;
        *rslot = (void *)my_btls_read;
    }
    if (*wslot && *wslot != (void *)my_btls_write) {
        if (!g_orig_write) g_orig_write = (btls_write_t)*wslot;
        *wslot = (void *)my_btls_write;
    }
}

static void *watcher(void *arg) {
    (void)arg;
    void *base = NULL;
    for (int i = 0; i < 1200 && !g_stop && !sw_disable(); i++) {
        base = get_base_unityframework();
        if (base) break;
        usleep(100000);
    }
    if (!base || sw_disable()) return NULL;

    /* wait until the engine resolved the BoringSSL entry points */
    for (int i = 0; i < 1800 && !g_stop && !sw_disable(); i++) {
        void **rslot = (void **)((uintptr_t)base + RVA_PTR_SSL_READ);
        void **wslot = (void **)((uintptr_t)base + RVA_PTR_SSL_WRITE);
        if (*rslot && *wslot) break;
        usleep(50000);
    }

    if (sw_disable()) return NULL;
    rearm_once(base);
    g_installed = (g_orig_read != NULL || g_orig_write != NULL);
    lprintf("[SKPNetLog] v3 installed base=%p read_orig=%p write_orig=%p\n",
            base, (void *)g_orig_read, (void *)g_orig_write);

    /* keep pointers swapped if the engine ever re-resolves them */
    while (!g_stop) {
        sleep(3);
        if (sw_disable()) break;
        rearm_once(base);
    }
    return NULL;
}

__attribute__((constructor))
static void skpnetlog_init(void) {
    @autoreleasepool {
        lock_init();
        if (sw_disable()) return;
        lprintf("[SKPNetLog] v3 dylib loaded pid=%d (no-substrate build)\n", getpid());
        if (sw_hook_ns()) install_ns_hook();
        pthread_t t;
        if (pthread_create(&t, NULL, watcher, NULL) == 0) pthread_detach(t);
    }
}
