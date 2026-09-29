/* YOLO head decode (darknet semantics, scale_x_y) + per-class greedy NMS on INT8 head buffers. */
#ifndef YOLO_POST_H
#define YOLO_POST_H
#include <stdint.h>

typedef struct { float x1, y1, x2, y2, score; int32_t cls; } det_t;   /* normalised [0,1] coords */

/* heads: raw DDR head buffers (HWC, 64 bytes/pixel, channels = 3 anchors x (5 + classes)) */
int yolo_decode(const int8_t *out1, const int8_t *out2, float thresh, det_t *dets, int max_dets);
int yolo_nms(det_t *dets, int n, float iou_thresh);   /* sorts by score, returns kept count */
#endif
