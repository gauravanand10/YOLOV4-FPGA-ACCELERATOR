/* YOLOv4-tiny accelerator user-space driver.
 * Memory: a 256 MiB reserved-memory region at DDR_BASE (0x7000_0000, no-map) accessed through /dev/mem
 * with O_SYNC (non-cacheable). The accelerator's HP0 port is not cache coherent, so no cached
 * mapping is used. Layout (offsets from DDR_BASE) comes from model_params.h (generated).
 * A second input buffer + descriptor table (identical except layer 0 in_addr) enables double buffering.
 */
#define _GNU_SOURCE
#include "yolo_accel.h"
#include "model_params.h"
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define DESC_BYTES   (NUM_LAYERS * 64)
#define IN_BYTES     (IN_W * IN_H * IN_PIX)
#define DESC2_OFF    (DESC_OFF + 0x800u)                       /* same 4 KiB page, after table 0 */
#define IN2_OFF      ((DDR_BYTES + 0xFFFu) & ~0xFFFu)          /* first free page after the model */

static inline void wr32(accel_t *a, unsigned off, uint32_t v) { a->regs[off >> 2] = v; }
static inline uint32_t rd32(accel_t *a, unsigned off) { return a->regs[off >> 2]; }

void dev_write(volatile uint8_t *dst, const void *src, size_t n)
{
    volatile uint64_t *d = (volatile uint64_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    size_t i;
    for (i = 0; i + 8 <= n; i += 8) { uint64_t v; memcpy(&v, s + i, 8); *d++ = v; }
    if (i < n) { uint64_t v = 0; memcpy(&v, s + i, n - i); *d = v; }  /* n is a multiple of 8 in practice */
}

void dev_read(void *dst, const volatile uint8_t *src, size_t n)
{
    const volatile uint64_t *s = (const volatile uint64_t *)src;
    uint8_t *d = (uint8_t *)dst;
    for (size_t i = 0; i < n; i += 8) { uint64_t v = *s++; memcpy(d + i, &v, (n - i) < 8 ? (n - i) : 8); }
}

int accel_open(accel_t *a)
{
    memset(a, 0, sizeof(*a));
    a->fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (a->fd < 0) { perror("open /dev/mem"); return -1; }
    a->regs = mmap(NULL, ACCEL_REG_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, a->fd, ACCEL_REG_BASE);
    a->ddr  = mmap(NULL, RESERVED_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED, a->fd, DDR_BASE);
    if (a->regs == MAP_FAILED || a->ddr == MAP_FAILED) { perror("mmap"); return -1; }
    uint32_t id = rd32(a, REG_ID);
    if (id != ACCEL_ID) { fprintf(stderr, "accelerator ID mismatch: 0x%08x (bitstream loaded?)\n", id); return -1; }
    if (IN2_OFF + IN_BYTES > RESERVED_BYTES) { fprintf(stderr, "reserved region too small\n"); return -1; }
    a->in_off[0] = IN_OFF;   a->desc_off[0] = DESC_OFF;
    a->in_off[1] = IN2_OFF;  a->desc_off[1] = DESC2_OFF;
    return 0;
}

void accel_close(accel_t *a)
{
    if (a->regs && a->regs != MAP_FAILED) munmap((void *)a->regs, ACCEL_REG_SIZE);
    if (a->ddr && a->ddr != MAP_FAILED) munmap((void *)a->ddr, RESERVED_BYTES);
    if (a->fd > 0) close(a->fd);
}

static void *read_file(const char *p, size_t *n)
{
    FILE *f = fopen(p, "rb");
    if (!f) { perror(p); return NULL; }
    fseek(f, 0, SEEK_END); *n = (size_t)ftell(f); fseek(f, 0, SEEK_SET);
    void *b = malloc(*n + 8);
    if (fread(b, 1, *n, f) != *n) { fclose(f); free(b); return NULL; }
    fclose(f);
    return b;
}

int accel_load_model(accel_t *a, const char *desc_bin, const char *weights_bin)
{
    size_t nd, nw;
    uint32_t *d = read_file(desc_bin, &nd);
    uint8_t *w = read_file(weights_bin, &nw);
    if (!d || !w) return -1;
    if (nd != DESC_BYTES || nw != W_BYTES) {
        fprintf(stderr, "model size mismatch: desc %zu/%u weights %zu/%u\n", nd, DESC_BYTES, nw, W_BYTES);
        return -1;
    }
    dev_write(a->ddr + W_OFF, w, nw);
    dev_write(a->ddr + DESC_OFF, d, nd);
    /* slot 1: layer 0 (first descriptor, word 0 = in_addr) reads input buffer 2 */
    d[0] = DDR_BASE + IN2_OFF;
    dev_write(a->ddr + DESC2_OFF, d, nd);
    /* zero both input buffers once (channels 3..15 stay zero afterwards) */
    static const uint8_t z[4096];
    for (int s = 0; s < NUM_SLOTS; s++)
        for (uint32_t o = 0; o < IN_BYTES; o += sizeof(z)) dev_write(a->ddr + a->in_off[s] + o, z, sizeof(z));
    free(d); free(w);
    return 0;
}

void accel_write_input(accel_t *a, int slot, const uint8_t *rgb)
{
    volatile uint64_t *p = (volatile uint64_t *)(a->ddr + a->in_off[slot]);
    for (int i = 0; i < IN_W * IN_H; i++, rgb += 3) {
        /* 16-byte pixel: bytes 0..2 = R>>1, G>>1, B>>1, rest 0; upper 8 bytes already zero */
        p[2 * i] = (uint64_t)(rgb[0] >> 1) | ((uint64_t)(rgb[1] >> 1) << 8) | ((uint64_t)(rgb[2] >> 1) << 16);
    }
}

int accel_run(accel_t *a, int slot, accel_stats_t *st, int timeout_ms)
{
    struct timespec t0, t;
    wr32(a, REG_STATUS, 2);                        /* clear stale done */
    wr32(a, REG_DESC, DDR_BASE + a->desc_off[slot]);
    wr32(a, REG_NLAYERS, NUM_LAYERS);
    __sync_synchronize();
    wr32(a, REG_CTRL, 1);                          /* start, irq disabled (polling) */
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (;;) {
        uint32_t s = rd32(a, REG_STATUS);
        if (s & 2) break;
        clock_gettime(CLOCK_MONOTONIC, &t);
        long ms = (t.tv_sec - t0.tv_sec) * 1000 + (t.tv_nsec - t0.tv_nsec) / 1000000;
        if (ms > timeout_ms) { fprintf(stderr, "accelerator timeout, layer %u\n", rd32(a, REG_LAYER)); return -1; }
        if (ms > 2) usleep(200);
    }
    if (st) {
        st->cycles = rd32(a, REG_CYCLES);   st->stall_row = rd32(a, REG_STALL_ROW);
        st->stall_out = rd32(a, REG_STALL_OUT); st->wload = rd32(a, REG_WLOAD);
    }
    wr32(a, REG_STATUS, 2);
    return 0;
}

void accel_read_heads(accel_t *a, int8_t *out1, int8_t *out2)
{
    dev_read(out1, a->ddr + HEADS[0].off, (size_t)HEADS[0].w * HEADS[0].h * HEAD_PIX);
    dev_read(out2, a->ddr + HEADS[1].off, (size_t)HEADS[1].w * HEADS[1].h * HEAD_PIX);
}
