/* SKPNetLog — Soul Knight Prequel (iOS) full TLS request/response logger
 *
 * Hook points (UnityFramework, imagebase 0x0, RVAs from IDA UnityFramework.i64):
 *   0x68095A4  UnityTls read shim  : long (void* state, void* buf, int* len)      -> *len = bytes read
 *   0x6809714  UnityTls write shim : long (void* state, const void* buf, int* len) -> *len in/out
 *   → plaintext TLS I/O of ALL game REST traffic (il2cpp System.Net.Http / UnityTls / mono-btls).
 * Plus Tquic.framework (Tencent TnetQuicRequest::AddHeaders / SendRequest) and NSURLSession.
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
#import <zlib.h>

#ifdef __cplusplus
extern "C" {
#endif
void MSHookFunction(void *symbol, void *hook, void **result);
#ifdef __cplusplus
}
#endif

/* ---------------- config ---------------- */
#define MAX_STREAM_BODY (4 * 1024 * 1024)  /* cap per accumulated body */
#define MAX_CHUNK        (64 * 1024 * 1024)
#define FILENAME_PREFIX  "skpnet_"

/* ---------------- globals ---------------- */
static FILE *g_log = NULL;
static FILE *g_err = NULL;
static char  g_dir[512];
static volatile int g_inited = 0;

/* ---------------- util: log file ---------------- */
static FILE *open_log(void) {
    @autoreleasepool {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *dir = [docs stringByAppendingPathComponent:@"skpnet"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"yyyyMMdd_HHmmss"];
        NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@%@.log", @"skpnet_", [df stringFromDate:[NSDate date]]]];
        strncpy(g_dir, dir.fileSystemRepresentation, sizeof(g_dir) - 1);
        return fopen(path.fileSystemRepresentation, "ab");
    }
}

static void lprintf(const char *fmt, ...) __attribute__((format(printf,1,2)));
static void lprintf(const char *fmt, ...) {
    if (!g_log) g_log = open_log();
    if (!g_log) return;
    va_list ap; va_start(ap, fmt);
    vfprintf(g_log, fmt, ap);
    va_end(ap);
    fflush(g_log);
}

static void now_stamp(char *out, size_t n) {
    struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tm; localtime_r(&ts.tv_sec, &tm);
    snprintf(out, n, "%04d-%02d-%02d %02d:%02d:%02d.%03ld",
             tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
             tm.tm_hour, tm.tm_min, tm.tm_sec, ts.tv_nsec / 1000000);
}

/* ---------------- util: buffers ---------------- */
typedef struct {
    unsigned char *data;
    size_t len, cap;
    int    got_head;      /* header block parsed */
    size_t body_start;    /* offset of body in data */
    long   body_expected; /* content-length, -1 = unknown/chunked */
    int    chunked;
    int    is_gzip;
    int    done;          /* record complete */
} acc_t;

static void acc_reset(acc_t *a) {
    a->len = 0; a->got_head = 0; a->body_start = 0;
    a->body_expected = -1; a->chunked = 0; a->is_gzip = 0; a->done = 0;
}

static int acc_append(acc_t *a, const void *src, size_t n) {
    if (n > MAX_CHUNK) n = MAX_CHUNK;
    if (a->len + n + 1 > a->cap) {
        size_t ncap = a->cap ? a->cap * 2 : 8192;
        while (ncap < a->len + n + 1) ncap *= 2;
        if (ncap > MAX_STREAM_BODY * 2) ncap = MAX_STREAM_BODY * 2 + 4096;
        unsigned char *nd = (unsigned char *)realloc(a->data, ncap);
        if (!nd) return 0;
        a->data = nd; a->cap = ncap;
    }
    memcpy(a->data + a->len, src, n);
    a->len += n;
    a->data[a->len] = 0;
    return 1;
}

/* ---------------- util: gzip inflate ---------------- */
static int gunzip(const unsigned char *in, size_t inlen, unsigned char **out, size_t *outlen) {
    size_t cap = inlen * 6 + 256;
    for (int attempt = 0; attempt < 8; attempt++) {
        unsigned char *buf = (unsigned char *)malloc(cap);
        if (!buf) return 0;
        z_stream zs; memset(&zs, 0, sizeof(zs));
        if (inflateInit2(&zs, 15 + 32) != Z_OK) { free(buf); return 0; } /* 15+32: gzip or zlib */
        zs.next_in = (Bytef *)in; zs.avail_in = (uInt)inlen;
        zs.next_out = buf; zs.avail_out = (uInt)cap;
        int rc = inflate(&zs, Z_FINISH);
        size_t produced = cap - zs.avail_out;
        inflateEnd(&zs);
        if (rc == Z_STREAM_END || rc == Z_OK) {
            *out = buf; *outlen = produced;
            return 1;
        }
        free(buf);
        if (rc == Z_BUF_ERROR) { cap *= 4; continue; }
        return 0;
    }
    return 0;
}

static void printable_dump(const unsigned char *p, size_t n, char *out, size_t outcap) {
    size_t o = 0;
    for (size_t i = 0; i < n && o < outcap - 8; i++) {
        unsigned char c = p[i];
        out[o++] = (c >= 0x20 && c < 0x7f) ? (char)c : (c == '\n' || c == '\r' || c == '\t') ? (char)c : '.';
    }
    out[o] = 0;
}

/* ---------------- HTTP parse ---------------- */
/* find header value (case-insensitive) within header block */
static int http_header_value(const char *head, size_t headlen, const char *name,
                             char *val, size_t valcap) {
    size_t nlen = strlen(name);
    const char *p = head, *end = head + headlen;
    while (p < end) {
        const char *eol = (const char *)memchr(p, '\n', end - p);
        if (!eol) break;
        size_t linelen = eol - p;
        if (linelen > nlen + 1 &&
            strncasecmp(p, name, nlen) == 0 && p[nlen] == ':') {
            const char *v = p + nlen + 1;
            while (v < eol && *v == ' ') v++;
            size_t vl = eol - v;
            while (vl && (v[vl-1] == '\r' || v[vl-1] == ' ')) vl--;
            if (vl >= valcap) vl = valcap - 1;
            memcpy(val, v, vl); val[vl] = 0;
            return 1;
        }
        p = eol + 1;
    }
    return 0;
}

static void log_record(const char *dir, void *conn, const char *tag,
                       const char *line1, size_t line1len,
                       const char *head, size_t headlen,
                       const unsigned char *body, size_t bodylen,
                       int is_gzip) {
    char stamp[64]; now_stamp(stamp, sizeof(stamp));
    char *linebuf = (char *)malloc(line1len + headlen + 2);
    if (!linebuf) return;
    memcpy(linebuf, line1, line1len); memcpy(linebuf + line1len, head, headlen);
    linebuf[line1len + headlen] = 0;
    for (size_t i = 0; i < line1len + headlen; i++)
        if ((unsigned char)linebuf[i] < 0x20 && linebuf[i] != '\n' && linebuf[i] != '\r') linebuf[i] = ' ';

    lprintf("================================================================\n");
    lprintf("[%s] %s conn=%p size=%zu%s\n", tag, stamp, conn,
            bodylen + headlen + line1len, is_gzip ? " (body gzipped)" : "");
    lprintf("%s\n", linebuf);

    unsigned char *dec = NULL; size_t declen = 0;
    const unsigned char *show = body; size_t shown = bodylen;
    if (is_gzip && body && bodylen && gunzip(body, bodylen, &dec, &declen)) {
        show = dec; shown = declen;
        lprintf("--- gunzip: %zu -> %zu bytes\n", bodylen, declen);
    }
    char *pb = (char *)malloc(shown + 1);
    if (pb) {
        printable_dump(show, shown, pb, shown + 1);
        lprintf("--- body (%zu bytes):\n%s\n", shown, pb);
        free(pb);
    }
    if (dec) free(dec);
    free(linebuf);
}

/* try to parse & flush a complete record; returns 1 if complete record emitted */
static int acc_try_complete(acc_t *a, void *conn, const char *tag, const char *dir) {
    if (a->done || a->len < 8) return 0;
    const char *head_end = NULL;
    if (!a->got_head) {
        head_end = (a->len >= 4) ? (const char *)memmem(a->data, a->len, "\r\n\r\n", 4) : NULL;
        if (!head_end) {
            /* head still incomplete — wait for more */
            return 0;
        }
        a->got_head = 1;
        a->body_start = (size_t)(head_end - (const char *)a->data) + 4;
        char clen[32] = {0}, cenc[64] = {0}, cte[64] = {0};
        http_header_value((const char *)a->data, a->body_start, "Content-Length", clen, sizeof(clen));
        http_header_value((const char *)a->data, a->body_start, "Content-Encoding", cenc, sizeof(cenc));
        http_header_value((const char *)a->data, a->body_start, "Transfer-Encoding", cte, sizeof(cte));
        a->body_expected = clen[0] ? strtol(clen, NULL, 10) : -1;
        if (strstr(cte, "chunked")) a->chunked = 1;
        a->is_gzip = (strstr(cenc, "gzip") != NULL) ||
                     (a->len > a->body_start + 1 && a->data[a->body_start] == 0x1f && a->data[a->body_start + 1] == 0x8b);
    }
    size_t bodylen = a->len - a->body_start;
    if (!a->chunked && a->body_expected >= 0) {
        if (bodylen < (size_t)a->body_expected) return 0;
        bodylen = (size_t)a->body_expected;
    } else if (a->chunked) {
        /* complete when terminating "0\r\n\r\n" (or bare "0\r\n\r\n" body) appears in body */
        size_t scan_from = a->body_start;
        const char *term = NULL;
        if (a->len > 5) term = (const char *)memmem(a->data + scan_from, a->len - scan_from, "0\r\n\r\n", 5);
        if (!term) return 0;
        /* NOTE: chunked body stays chunk-encoded in log; good enough for reading */
        bodylen = a->len - a->body_start;
    }
    a->done = 1;
    log_record(dir, conn, tag, (const char *)a->data, 0,
               (const char *)a->data, a->body_start - 4,
               a->data + a->body_start, bodylen, a->is_gzip);
    return 1;
}

/* ---------------- connection table ---------------- */
typedef struct { void *key; acc_t out; acc_t in; int used; } conn_t;
#define MAX_CONNS 64
static conn_t g_conns[MAX_CONNS];

static conn_t *conn_get(void *key) {
    conn_t *free_slot = NULL;
    for (int i = 0; i < MAX_CONNS; i++) {
        if (g_conns[i].used && g_conns[i].key == key) return &g_conns[i];
        if (!g_conns[i].used && !free_slot) free_slot = &g_conns[i];
    }
    if (!free_slot) {
        /* evict slot 0 */
        free_slot = &g_conns[0];
        if (free_slot->out.data) { free(free_slot->out.data); free_slot->out.data = NULL; }
        if (free_slot->in.data)  { free(free_slot->in.data);  free_slot->in.data = NULL; }
        memset(free_slot, 0, sizeof(*free_slot));
    }
    memset(free_slot, 0, sizeof(*free_slot));
    free_slot->used = 1; free_slot->key = key;
    free_slot->out.body_expected = -1; free_slot->in.body_expected = -1;
    return free_slot;
}

/* ---------------- UnityTls hooks ---------------- */
typedef long (*unitytls_read_t) (void *state, void *buf, int *len);
typedef long (*unitytls_write_t)(void *state, const void *buf, int *len);

static unitytls_read_t  orig_tls_read  = NULL;
static unitytls_write_t orig_tls_write = NULL;

/* RVA in UnityFramework (imagebase 0x0) */
#define RVA_TLS_READ_SHIM   0x68095A4UL   /* calls mono_btls_ssl_read  */
#define RVA_TLS_WRITE_SHIM  0x6809714UL   /* calls mono_btls_ssl_write */

static void *get_base_unityframework(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework")) {
            return (void *)(_dyld_get_image_header(i) + _dyld_get_image_vmaddr_slide(i));
        }
    }
    return NULL;
}

static long my_tls_write(void *state, const void *buf, int *len) {
    long rc = orig_tls_write(state, buf, len);
    int written = (rc == 0 && len) ? *len : 0;
    if (rc == 0 && buf && written > 0) {
        conn_t *c = conn_get(state);
        if (c && acc_append(&c->out, buf, (size_t)written)) {
            if (acc_try_complete(&c->out, state, ">>> OUT", g_dir)) {
                acc_reset(&c->out);   /* ready for next request on keep-alive */
            }
        }
    }
    return rc;
}

static long my_tls_read(void *state, void *buf, int *len) {
    long rc = orig_tls_read(state, buf, len);
    if (rc == 0 && buf && len && *len > 0) {
        conn_t *c = conn_get(state);
        if (c && acc_append(&c->in, buf, (size_t)*len)) {
            if (acc_try_complete(&c->in, state, "<<< IN ", g_dir)) {
                acc_reset(&c->in);
            }
        }
    }
    return rc;
}

/* ---------------- TQUIC hooks (Tencent QUIC transport) ---------------- */
static void *h_quic = NULL;
typedef void *(*addheaders_t)(void *self, const char *a, const char *b, char c);
typedef void *(*sendrequest_t)(void *self, const char *a, int b, char c);
static addheaders_t  orig_quic_addheaders  = NULL;
static sendrequest_t orig_quic_sendrequest = NULL;

static void *my_quic_addheaders(void *self, const char *a, const char *b, char c) {
    char stamp[64]; now_stamp(stamp, sizeof(stamp));
    lprintf("----------------------------------------------------------------\n");
    lprintf("[QUIC-HDR] %s conn=%p a=%s b=%s c=%d\n", stamp, self,
            a ? a : "(null)", b ? b : "(null)", (int)c);
    return orig_quic_addheaders(self, a, b, c);
}

static void *my_quic_sendrequest(void *self, const char *a, int b, char c) {
    char stamp[64]; now_stamp(stamp, sizeof(stamp));
    lprintf("----------------------------------------------------------------\n");
    lprintf("[QUIC-REQ] %s conn=%p len=%d flag=%d\n", stamp, self, b, (int)c);
    if (a && b > 0) {
        size_t n = (size_t)b;
        char *pb = (char *)malloc(n + 1);
        if (pb) { printable_dump((const unsigned char *)a, n, pb, n + 1); lprintf("--- body:\n%s\n", pb); free(pb); }
    }
    return orig_quic_sendrequest(self, a, b, c);
}

/* ---------------- NSURLSession logging (SDK traffic) ---------------- */
%group NSURLSessionLog
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    @try {
        char stamp[64]; now_stamp(stamp, sizeof(stamp));
        NSString *meth = request.HTTPMethod ?: @"GET";
        lprintf("----------------------------------------------------------------\n");
        lprintf("[NS-REQ] %s %s %s\n", stamp, meth.UTF8String, request.URL.absoluteString.UTF8String);
        NSDictionary *hs = request.allHTTPHeaderFields;
        for (NSString *k in hs) lprintf("    %s: %s\n", k.UTF8String, [[hs objectForKey:k] UTF8String]);
        NSData *b = request.HTTPBody;
        if (b.length) {
            char *pb = (char *)malloc((size_t)b.length + 1);
            if (pb) {
                printable_dump((const unsigned char *)b.bytes, (size_t)b.length > 16384 ? 16384 : (size_t)b.length, pb, (size_t)b.length + 1);
                lprintf("--- body (%lu bytes):\n%s\n", (unsigned long)b.length, pb);
                free(pb);
            }
        }
    } @catch (id e) {}
    return %orig;
}
%end
%end /* group */

/* ---------------- install ---------------- */
static void install_hooks(void) {
    void *base = get_base_unityframework();
    if (!base) return;

    /* UnityTls plaintext I/O */
    void *p_read  = (void *)((uintptr_t)base + RVA_TLS_READ_SHIM);
    void *p_write = (void *)((uintptr_t)base + RVA_TLS_WRITE_SHIM);
    MSHookFunction(p_write, (void *)my_tls_write, (void **)&orig_tls_write);
    MSHookFunction(p_read,  (void *)my_tls_read,  (void **)&orig_tls_read);

    /* TQUIC */
    void *h = dlopen("@rpath/Tquic.framework/Tquic", RTLD_LAZY);
    if (!h) h = dlopen("Tquic", RTLD_LAZY);
    if (h) {
        void *p1 = dlsym(h, "__ZN15TnetQuicRequest10AddHeadersEPKcS1_b");
        void *p2 = dlsym(h, "__ZN15TnetQuicRequest11SendRequestEPKcib");
        if (p1) MSHookFunction(p1, (void *)my_quic_addheaders, (void **)&orig_quic_addheaders);
        if (p2) MSHookFunction(p2, (void *)my_quic_sendrequest, (void **)&orig_quic_sendrequest);
        h_quic = h;
    }

    char stamp[64]; now_stamp(stamp, sizeof(stamp));
    lprintf("[SKPNetLog] installed %s base=%p read=%p write=%p quic=%p\n",
            stamp, base, p_read, p_write, h_quic);
    g_inited = 1;
}

static void *watchdog(void *arg) {
    for (int i = 0; i < 1200 && !g_inited; i++) {      /* poll up to ~120s */
        if (get_base_unityframework()) { install_hooks(); break; }
        usleep(100000);
    }
    return NULL;
}

%ctor {
    @autoreleasepool {
        %init(NSURLSessionLog);          /* activate the NSURLSession %hook group */
        g_log = open_log();
        lprintf("[SKPNetLog] injected\n");
        pthread_t t;
        pthread_create(&t, NULL, watchdog, NULL);
        pthread_detach(t);
    }
}
