#include "yolo_post.h"
#include "model_params.h"
#include <math.h>
#include <stdlib.h>

static inline float sigm(float x) { return 1.0f / (1.0f + expf(-x)); }

static int decode_head(const head_t *h, const int8_t *buf, float thresh, det_t *d, int n, int max)
{
    const int C = NUM_CLASSES, A = 3;
    const float s = h->scale, sxy = h->scale_x_y;
    for (int y = 0; y < h->h; y++)
        for (int x = 0; x < h->w; x++) {
            const int8_t *px = buf + (y * h->w + x) * HEAD_PIX;
            for (int a = 0; a < A; a++) {
                const int8_t *q = px + a * (5 + C);
                float obj = sigm(q[4] * s);
                if (obj <= thresh) continue;               /* prob = obj * cls <= obj */
                float bx = (x + sigm(q[0] * s) * sxy - (sxy - 1) * 0.5f) / h->w;
                float by = (y + sigm(q[1] * s) * sxy - (sxy - 1) * 0.5f) / h->h;
                float bw = expf(q[2] * s) * h->anchors[a][0] / IN_W;
                float bh = expf(q[3] * s) * h->anchors[a][1] / IN_H;
                for (int c = 0; c < C; c++) {
                    float p = obj * sigm(q[5 + c] * s);
                    if (p > thresh && n < max) {
                        det_t *o = &d[n++];
                        o->x1 = bx - bw / 2; o->y1 = by - bh / 2; o->x2 = bx + bw / 2; o->y2 = by + bh / 2;
                        o->score = p; o->cls = c;
                    }
                }
            }
        }
    return n;
}

int yolo_decode(const int8_t *out1, const int8_t *out2, float thresh, det_t *dets, int max_dets)
{
    int n = decode_head(&HEADS[0], out1, thresh, dets, 0, max_dets);
    return decode_head(&HEADS[1], out2, thresh, dets, n, max_dets);
}

static int cmp_score(const void *a, const void *b)
{
    const det_t *x = a, *y = b;
    if (x->cls != y->cls) return x->cls - y->cls;
    return (x->score < y->score) - (x->score > y->score);
}

static float iou(const det_t *a, const det_t *b)
{
    float ix = fminf(a->x2, b->x2) - fmaxf(a->x1, b->x1);
    float iy = fminf(a->y2, b->y2) - fmaxf(a->y1, b->y1);
    if (ix <= 0 || iy <= 0) return 0;
    float i = ix * iy;
    float u = (a->x2 - a->x1) * (a->y2 - a->y1) + (b->x2 - b->x1) * (b->y2 - b->y1) - i;
    return u > 0 ? i / u : 0;
}

int yolo_nms(det_t *d, int n, float thr)
{
    qsort(d, n, sizeof(det_t), cmp_score);     /* grouped by class, descending score */
    int k = 0;
    for (int i = 0; i < n; i++) {
        if (d[i].score <= 0) continue;
        for (int j = i + 1; j < n && d[j].cls == d[i].cls; j++)
            if (d[j].score > 0 && iou(&d[i], &d[j]) > thr) d[j].score = 0;
        d[k++] = d[i];
    }
    return k;
}
