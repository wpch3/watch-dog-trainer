/* xmemlzx - minimal LZX (XMemCompress) stream decoder CLI
 * built on libmspack lzxd.c (LGPL-2.1) - memory-backed mspack system */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <system.h>
#include <lzx.h>

struct mem_file { unsigned char *buf; size_t len, pos; size_t rest; };

static struct mspack_file *mf_open(struct mspack_system *self, const char *fn, int mode) {
    (void)self; (void)fn; (void)mode;
    return (struct mspack_file *)fn; /* opaque: we pass the mem_file ptr directly */
}
static void mf_close(struct mspack_file *f) { (void)f; }
/* XMemCompress chunk sub-block header logic (QuickBMS appDecompressLZX_read) */
static int mf_read(struct mspack_file *f, void *b, int n) {
    struct mem_file *m = (struct mem_file *)f;
    if (!m->rest) {
        if (m->pos < m->len && m->buf[m->pos] == 0xFF && m->pos + 5 <= m->len) {
            /* [0]=FF [1,2]=uncompressed block size [3,4]=compressed block size (BE u16) */
            m->rest = ((size_t)m->buf[m->pos + 3] << 8) | m->buf[m->pos + 4];
            m->pos += 5;
        } else if (m->pos + 2 <= m->len) {
            /* [0,1] = compressed size */
            m->rest = ((size_t)m->buf[m->pos + 0] << 8) | m->buf[m->pos + 1];
            m->pos += 2;
        } else {
            return 0;
        }
        if (m->rest > m->len - m->pos) m->rest = m->len - m->pos;
    }
    size_t avail = m->len - m->pos;
    size_t take = (size_t)n < m->rest ? (size_t)n : m->rest;
    if (take > avail) take = avail;
    if (take) { memcpy(b, m->buf + m->pos, take); m->pos += take; m->rest -= take; }
    return (int)take;
}
static int mf_write(struct mspack_file *f, void *b, int n) {
    struct mem_file *m = (struct mem_file *)f;
    if (m->pos + (size_t)n > m->len) return -1;
    memcpy(m->buf + m->pos, b, (size_t)n); m->pos += (size_t)n;
    return n;
}
static int mf_seek(struct mspack_file *f, off_t off, int mode) {
    struct mem_file *m = (struct mem_file *)f;
    size_t np = m->pos;
    if (mode == MSPACK_SYS_SEEK_START) np = (size_t)off;
    else if (mode == MSPACK_SYS_SEEK_CUR) np = m->pos + (size_t)off;
    else if (mode == MSPACK_SYS_SEEK_END) np = (off < 0 && (size_t)(-off) > m->len) ? 0 : m->len + (size_t)off;
    if (np > m->len) return -1;
    m->pos = np; return 0;
}
static off_t mf_tell(struct mspack_file *f) { return (off_t)((struct mem_file *)f)->pos; }
static void mf_msg(struct mspack_file *f, const char *fmt, ...) { (void)f; (void)fmt; }
static void *mf_alloc(struct mspack_system *self, size_t n) { (void)self; return malloc(n); }
static void mf_free(void *p) { free(p); }
static void mf_copy(void *src, void *dst, size_t n) { memcpy(dst, src, n); }

static struct mspack_system mem_sys = {
    mf_open, mf_close, mf_read, mf_write, mf_seek, mf_tell,
    mf_msg, mf_alloc, mf_free, mf_copy, NULL
};

int main(int argc, char **argv) {
    if (argc != 5) { fprintf(stderr, "usage: %s in out window_bits outlen\n", argv[0]); return 2; }
    int wb = atoi(argv[3]);
    long outlen = atol(argv[4]);

    FILE *fi = fopen(argv[1], "rb");
    if (!fi) { fprintf(stderr, "open in failed\n"); return 2; }
    fseek(fi, 0, SEEK_END); long inlen = ftell(fi); fseek(fi, 0, SEEK_SET);
    unsigned char *inbuf = malloc(inlen ? (size_t)inlen : 1);
    if (fread(inbuf, 1, (size_t)inlen, fi) != (size_t)inlen) { fclose(fi); return 2; }
    fclose(fi);

    unsigned char *outbuf = calloc(1, outlen ? (size_t)outlen : 1);
    struct mem_file inmf = { inbuf, (size_t)inlen, 0 };
    struct mem_file outmf = { outbuf, (size_t)outlen, 0 };

    struct lzxd_stream *lzx = lzxd_init(&mem_sys, (struct mspack_file *)&inmf,
                                        (struct mspack_file *)&outmf, wb, 0, 4096,
                                        (off_t)outlen, 0);
    if (!lzx) { fprintf(stderr, "ERR init\n"); return 3; }
    int r = lzxd_decompress(lzx, (off_t)outlen);
    if (r != MSPACK_ERR_OK) { fprintf(stderr, "ERR %d\n", r); lzxd_free(lzx); return 1; }
    if (outmf.pos != (size_t)outlen) { fprintf(stderr, "ERR short %zu/%ld\n", outmf.pos, outlen); lzxd_free(lzx); return 1; }
    FILE *fo = fopen(argv[2], "wb");
    if (!fo) { return 2; }
    fwrite(outbuf, 1, (size_t)outlen, fo);
    fclose(fo);
    lzxd_free(lzx);
    return 0;
}
