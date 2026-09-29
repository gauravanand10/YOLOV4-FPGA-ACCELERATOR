"""YOLO head decode (darknet semantics incl. scale_x_y) and greedy per-class NMS."""
import numpy as np


def sigmoid(x):
    return 1.0 / (1.0 + np.exp(-x))


def decode_head(raw, anchors, classes, scale_x_y, net_w=416, net_h=416, thresh=0.25):
    """raw: (A*(5+C), H, W) float array. Returns array Nx(4+1+1+C): x1,y1,x2,y2 (normalised), score, cls, probs."""
    A = len(anchors)
    _, H, W = raw.shape
    r = raw.reshape(A, 5 + classes, H, W)
    gy, gx = np.meshgrid(np.arange(H), np.arange(W), indexing='ij')
    dets = []
    for a in range(A):
        tx, ty, tw, th, to = r[a, 0], r[a, 1], r[a, 2], r[a, 3], r[a, 4]
        bx = (gx + sigmoid(tx) * scale_x_y - (scale_x_y - 1) / 2) / W
        by = (gy + sigmoid(ty) * scale_x_y - (scale_x_y - 1) / 2) / H
        bw = np.exp(tw) * anchors[a][0] / net_w
        bh = np.exp(th) * anchors[a][1] / net_h
        obj = sigmoid(to)
        probs = obj[None] * sigmoid(r[a, 5:])
        probs = np.where(probs > thresh, probs, 0.0)
        keep = probs.max(0) > 0
        if not keep.any():
            continue
        p = probs[:, keep].T
        x1 = bx[keep] - bw[keep] / 2; y1 = by[keep] - bh[keep] / 2
        x2 = bx[keep] + bw[keep] / 2; y2 = by[keep] + bh[keep] / 2
        dets.append(np.concatenate([np.stack([x1, y1, x2, y2], 1), p], 1))
    if not dets:
        return np.zeros((0, 4 + classes))
    return np.concatenate(dets, 0)


def iou(a, b):
    x1 = np.maximum(a[0], b[:, 0]); y1 = np.maximum(a[1], b[:, 1])
    x2 = np.minimum(a[2], b[:, 2]); y2 = np.minimum(a[3], b[:, 3])
    inter = np.clip(x2 - x1, 0, None) * np.clip(y2 - y1, 0, None)
    ua = (a[2] - a[0]) * (a[3] - a[1]) + (b[:, 2] - b[:, 0]) * (b[:, 3] - b[:, 1]) - inter
    return inter / np.maximum(ua, 1e-12)


def nms(dets, classes, iou_thresh=0.45):
    """Darknet do_nms_sort-like: per class, sorted by prob, suppress IoU>thr. Returns list (x1,y1,x2,y2,score,cls)."""
    out = []
    for c in range(classes):
        p = dets[:, 4 + c]
        idx = np.where(p > 0)[0]
        if idx.size == 0:
            continue
        idx = idx[np.argsort(-p[idx], kind='stable')]
        boxes = dets[idx, :4]
        alive = np.ones(len(idx), bool)
        for i in range(len(idx)):
            if not alive[i]:
                continue
            out.append((*boxes[i], p[idx[i]], c))
            if i + 1 < len(idx):
                ov = iou(boxes[i], boxes[i + 1:])
                alive[i + 1:] &= ov <= iou_thresh
    return out


def detect(heads_raw, head_layers, classes=7, thresh=0.25, nms_thresh=0.45, net_wh=(416, 416)):
    d = [decode_head(r, L['anchors'], classes, L['scale_x_y'], net_wh[0], net_wh[1], thresh)
         for r, L in zip(heads_raw, head_layers)]
    d = np.concatenate(d, 0) if d else np.zeros((0, 4 + classes))
    return nms(d, classes, nms_thresh)
