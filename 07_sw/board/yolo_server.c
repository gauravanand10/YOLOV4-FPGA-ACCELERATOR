/* ZCU104 YOLOv4-tiny detection server.
 *
 *   yolo_server [-p port] [-m model_dir] [-t thresh]      TCP server (default port 5000)
 *   yolo_server --selftest <model_dir>                    run golden test vector, compare bit-exact
 *   yolo_server --decode <heads.bin>                      host-side check of decode+NMS (no hardware)
 *
 * Protocol (little endian):
 *   client -> server : u32 magic 'YOLF' (0x464C4F59), u32 frame_id, u32 w (416), u32 h (416), w*h*3 RGB bytes
 *   server -> client : u32 magic 'YOLR' (0x524C4F59), u32 frame_id, u32 ndet, f32 accel_ms, f32 server_ms,
 *                      ndet x { f32 x1, y1, x2, y2 (normalised), f32 score, i32 cls }
 * Pipelining: a receiver thread reads + preprocesses frame k+1 into the free input slot while the
 * accelerator processes frame k (2 slots, 2 descriptor tables).
 */
#define _GNU_SOURCE
#include "model_params.h"
#include "yolo_post.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAX_DETS 4096
/* accelerator clock = PS pl_clk0 (IOPLL 1500 MHz / 8); see 06_vivado/reports/clock.txt */
#ifndef ACCEL_CLK_HZ
#define ACCEL_CLK_HZ 187500000.0
#endif
#define MAGIC_F 0x464C4F59u
#define MAGIC_R 0x524C4F59u
#define HEAD1_BYTES (13 * 13 * HEAD_PIX)
#define HEAD2_BYTES (26 * 26 * HEAD_PIX)

static double __attribute__((unused)) now_ms(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1e3 + t.tv_nsec / 1e6;
}

static int load_bin(const char *p, void *buf, size_t n)
{
    FILE *f = fopen(p, "rb");
    if (!f) { perror(p); return -1; }
    size_t r = fread(buf, 1, n, f);
    fclose(f);
    return r == n ? 0 : -1;
}

static void print_dets(const det_t *d, int n)
{
    for (int i = 0; i < n; i++)
        printf("%s %.4f %.4f %.4f %.4f %.4f\n", CLASS_NAMES[d[i].cls], d[i].score, d[i].x1, d[i].y1, d[i].x2, d[i].y2);
}

static int cmp_print(const void *a, const void *b)
{
    const det_t *x = a, *y = b;
    if (x->score != y->score) return x->score < y->score ? 1 : -1;
    return x->cls - y->cls;
}

/* decode+NMS of a raw heads file: used on the host to validate this C post-processing against Python */
static int run_decode(const char *heads_bin)
{
    static int8_t h[HEAD1_BYTES + HEAD2_BYTES];
    static det_t d[MAX_DETS];
    if (load_bin(heads_bin, h, sizeof(h))) return 1;
    int n = yolo_decode(h, h + HEAD1_BYTES, 0.25f, d, MAX_DETS);
    n = yolo_nms(d, n, 0.45f);
    qsort(d, n, sizeof(det_t), cmp_print);
    print_dets(d, n);
    return 0;
}

#ifdef HOST_ONLY
int main(int argc, char **argv)
{
    if (argc == 3 && !strcmp(argv[1], "--decode")) return run_decode(argv[2]);
    fprintf(stderr, "host build supports only --decode <heads.bin>\n");
    return 1;
}
#else
#include "yolo_accel.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <signal.h>
#include <sys/socket.h>
#include <unistd.h>

static accel_t g_acc;
static float g_thresh = 0.25f;

static int recv_all(int s, void *b, size_t n)
{
    uint8_t *p = b;
    while (n) {
        ssize_t r = recv(s, p, n, 0);
        if (r <= 0) return -1;
        p += r; n -= (size_t)r;
    }
    return 0;
}

static int send_all(int s, const void *b, size_t n)
{
    const uint8_t *p = b;
    while (n) {
        ssize_t r = send(s, p, n, MSG_NOSIGNAL);
        if (r <= 0) return -1;
        p += r; n -= (size_t)r;
    }
    return 0;
}

static int model_load(const char *dir)
{
    char d[512], w[512];
    snprintf(d, sizeof d, "%s/yolo_desc.bin", dir);
    snprintf(w, sizeof w, "%s/yolo_weights.bin", dir);
    if (accel_open(&g_acc) || accel_load_model(&g_acc, d, w)) return -1;
    return 0;
}

static int run_selftest(const char *dir)
{
    static uint8_t rgb[IN_W * IN_H * 3];
    static int8_t exp_h[HEAD1_BYTES + HEAD2_BYTES], got[HEAD1_BYTES + HEAD2_BYTES];
    static det_t d[MAX_DETS];
    char p[512];
    if (model_load(dir)) return 1;
    snprintf(p, sizeof p, "%s/test_input_rgb.bin", dir);
    if (load_bin(p, rgb, sizeof rgb)) return 1;
    snprintf(p, sizeof p, "%s/test_heads.bin", dir);
    if (load_bin(p, exp_h, sizeof exp_h)) return 1;
    int fails = 0;
    for (int slot = 0; slot < NUM_SLOTS; slot++) {
        accel_stats_t st;
        double t0 = now_ms();
        accel_write_input(&g_acc, slot, rgb);
        double t1 = now_ms();
        if (accel_run(&g_acc, slot, &st, 2000)) return 1;
        double t2 = now_ms();
        accel_read_heads(&g_acc, got, got + HEAD1_BYTES);
        int mism = 0;
        for (size_t i = 0; i < sizeof got; i++) mism += got[i] != exp_h[i];
        printf("slot %d: preprocess %.2f ms, accel %.2f ms (%u cycles = %.2f ms @%.1fMHz, %.1f fps), "
               "stall_row %u stall_out %u wload %u, head mismatches %d -> %s\n",
               slot, t1 - t0, t2 - t1, st.cycles, st.cycles * 1e3 / ACCEL_CLK_HZ, ACCEL_CLK_HZ / 1e6, ACCEL_CLK_HZ / st.cycles,
               st.stall_row, st.stall_out, st.wload, mism, mism ? "FAIL" : "PASS");
        fails += mism != 0;
    }
    int n = yolo_decode(got, got + HEAD1_BYTES, 0.25f, d, MAX_DETS);
    n = yolo_nms(d, n, 0.45f);
    qsort(d, n, sizeof(det_t), cmp_print);
    print_dets(d, n);
    /* throughput: back-to-back runs */
    double t0 = now_ms();
    for (int i = 0; i < 50; i++) accel_run(&g_acc, i & 1, NULL, 2000);
    printf("accelerator throughput: %.1f fps (50 back-to-back runs)\n", 50e3 / (now_ms() - t0));
    return fails ? 1 : 0;
}

/* ---------------- server ---------------- */
typedef struct { uint32_t frame_id; int valid; } slot_t;
static slot_t g_slot[NUM_SLOTS];
static pthread_mutex_t g_mx = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_cv = PTHREAD_COND_INITIALIZER;
static int g_rx_done;

typedef struct { int sock; } rx_arg_t;

static void *rx_thread(void *arg)
{
    int s = ((rx_arg_t *)arg)->sock;
    static uint8_t rgb[IN_W * IN_H * 3];
    int slot = 0;
    for (;;) {
        uint32_t hdr[4];
        if (recv_all(s, hdr, sizeof hdr) || hdr[0] != MAGIC_F || hdr[2] != IN_W || hdr[3] != IN_H) break;
        if (recv_all(s, rgb, sizeof rgb)) break;
        pthread_mutex_lock(&g_mx);
        while (g_slot[slot].valid) pthread_cond_wait(&g_cv, &g_mx);   /* slot still owned by worker */
        pthread_mutex_unlock(&g_mx);
        accel_write_input(&g_acc, slot, rgb);
        pthread_mutex_lock(&g_mx);
        g_slot[slot].frame_id = hdr[1];
        g_slot[slot].valid = 1;
        pthread_cond_broadcast(&g_cv);
        pthread_mutex_unlock(&g_mx);
        slot ^= 1;
    }
    pthread_mutex_lock(&g_mx);
    g_rx_done = 1;
    pthread_cond_broadcast(&g_cv);
    pthread_mutex_unlock(&g_mx);
    return NULL;
}

static void serve(int c)
{
    static int8_t h1[HEAD1_BYTES], h2[HEAD2_BYTES];
    static det_t d[MAX_DETS];
    static uint8_t msg[20 + MAX_DETS * 24];
    pthread_t th;
    rx_arg_t ra = {c};
    memset(g_slot, 0, sizeof g_slot);
    g_rx_done = 0;
    pthread_create(&th, NULL, rx_thread, &ra);
    int slot = 0, frames = 0;
    double t_start = now_ms();
    for (;;) {
        pthread_mutex_lock(&g_mx);
        while (!g_slot[slot].valid && !g_rx_done) pthread_cond_wait(&g_cv, &g_mx);
        int ok = g_slot[slot].valid;
        uint32_t fid = g_slot[slot].frame_id;
        pthread_mutex_unlock(&g_mx);
        if (!ok) break;
        double t0 = now_ms();
        accel_stats_t st;
        if (accel_run(&g_acc, slot, &st, 2000)) break;
        accel_read_heads(&g_acc, h1, h2);
        pthread_mutex_lock(&g_mx);                  /* release slot to the receiver */
        g_slot[slot].valid = 0;
        pthread_cond_broadcast(&g_cv);
        pthread_mutex_unlock(&g_mx);
        int n = yolo_decode(h1, h2, g_thresh, d, MAX_DETS);
        n = yolo_nms(d, n, 0.45f);
        float acc_ms = (float)(st.cycles * 1e3 / ACCEL_CLK_HZ), srv_ms = (float)(now_ms() - t0);
        uint32_t hdr[3] = {MAGIC_R, fid, (uint32_t)n};
        memcpy(msg, hdr, 12);
        memcpy(msg + 12, &acc_ms, 4);
        memcpy(msg + 16, &srv_ms, 4);
        memcpy(msg + 20, d, (size_t)n * 24);
        if (send_all(c, msg, 20 + (size_t)n * 24)) break;
        slot ^= 1;
        if (++frames % 100 == 0)
            printf("%d frames, %.1f fps, accel %.2f ms, last %d dets\n", frames,
                   frames * 1e3 / (now_ms() - t_start), acc_ms, n);
    }
    shutdown(c, SHUT_RDWR);
    pthread_join(th, NULL);
    close(c);
    printf("client disconnected after %d frames\n", frames);
}

int main(int argc, char **argv)
{
    const char *dir = ".";
    int port = 5000;
    if (argc == 3 && !strcmp(argv[1], "--decode")) return run_decode(argv[2]);
    if (argc >= 2 && !strcmp(argv[1], "--selftest")) return run_selftest(argc > 2 ? argv[2] : ".");
    for (int i = 1; i + 1 < argc; i += 2) {
        if (!strcmp(argv[i], "-p")) port = atoi(argv[i + 1]);
        else if (!strcmp(argv[i], "-m")) dir = argv[i + 1];
        else if (!strcmp(argv[i], "-t")) g_thresh = (float)atof(argv[i + 1]);
    }
    signal(SIGPIPE, SIG_IGN);
    if (model_load(dir)) return 1;
    int ls = socket(AF_INET, SOCK_STREAM, 0), one = 1;
    setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a = {0};
    a.sin_family = AF_INET; a.sin_port = htons((uint16_t)port); a.sin_addr.s_addr = INADDR_ANY;
    if (bind(ls, (struct sockaddr *)&a, sizeof a) || listen(ls, 1)) { perror("bind/listen"); return 1; }
    printf("yolo_server listening on port %d (thresh %.2f)\n", port, g_thresh);
    for (;;) {
        int c = accept(ls, NULL, NULL);
        if (c < 0) continue;
        setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
        printf("client connected\n");
        serve(c);
    }
    return 0;
}
#endif
