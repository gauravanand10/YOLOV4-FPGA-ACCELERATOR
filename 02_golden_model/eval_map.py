"""mAP@0.5 (VOC all-point interpolation, darknet 'detector map' style) for float vs INT8 model.

usage: python eval_map.py [N=500] [start=0]    -> evaluates valid images [start:start+N] with both models
"""
import sys, os, glob, pickle, time, json
import numpy as np
from darknet_parse import load_network, ROOT, CLASSES
from float_model import FloatNet, load_image, to_tensor
from yolo_decode import detect
from quant import int8_forward, input_q, dequant_heads

OUT = os.path.join(os.path.dirname(__file__), 'out')


def load_labels(img_path):
    lp = os.path.join(ROOT, '01_dataset/labels/valid', os.path.splitext(os.path.basename(img_path))[0] + '.txt')
    gt = []
    if os.path.exists(lp):
        for line in open(lp):
            v = line.split()
            if len(v) == 5:
                c, cx, cy, w, h = int(v[0]), *map(float, v[1:])
                gt.append((cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, c))
    return gt


def box_iou(a, b):
    ix = max(0, min(a[2], b[2]) - max(a[0], b[0])); iy = max(0, min(a[3], b[3]) - max(a[1], b[1]))
    i = ix * iy
    u = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - i
    return i / u if u > 0 else 0


def compute_map(all_dets, all_gts, ncls, iou_thr=0.5):
    aps = []
    for c in range(ncls):
        dets = [(s, i, d) for i, ds in enumerate(all_dets) for d in ds if d[5] == c for s in [d[4]]]
        dets.sort(key=lambda x: -x[0])
        gts = {i: [g for g in gs if g[4] == c] for i, gs in enumerate(all_gts)}
        npos = sum(len(v) for v in gts.values())
        used = {i: np.zeros(len(v), bool) for i, v in gts.items()}
        tp = np.zeros(len(dets)); fp = np.zeros(len(dets))
        for k, (s, i, d) in enumerate(dets):
            best, bj = 0, -1
            for j, g in enumerate(gts[i]):
                o = box_iou(d, g)
                if o > best:
                    best, bj = o, j
            if best >= iou_thr and not used[i][bj]:
                tp[k] = 1; used[i][bj] = True
            else:
                fp[k] = 1
        if npos == 0:
            aps.append(float('nan')); continue
        tp = np.cumsum(tp); fp = np.cumsum(fp)
        rec = tp / npos; prec = tp / np.maximum(tp + fp, 1e-12)
        mrec = np.concatenate([[0], rec, [1]]); mpre = np.concatenate([[0], prec, [0]])
        for k in range(len(mpre) - 2, -1, -1):
            mpre[k] = max(mpre[k], mpre[k + 1])
        idx = np.where(mrec[1:] != mrec[:-1])[0]
        aps.append(float(np.sum((mrec[idx + 1] - mrec[idx]) * mpre[idx + 1])))
    return aps


def main():
    N = int(sys.argv[1]) if len(sys.argv) > 1 else 500
    start = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    net = load_network(); fn = FloatNet(net)
    qp = pickle.load(open(os.path.join(OUT, 'qparams.pkl'), 'rb'))
    q = qp['q']
    imgs = sorted(glob.glob(os.path.join(ROOT, '01_dataset/images/valid/*.jpg')))[start:start + N]
    dets_f, dets_q, gts = [], [], []
    agree = []
    t0 = time.time()
    for n, p in enumerate(imgs):
        rgb, _ = load_image(p)
        _, hf = fn.forward(to_tensor(rgb))
        heads_f = [x[0].numpy().astype(np.float64) for _, x in hf]
        hl = [L for L, _ in hf]
        _, hq = int8_forward(net, q, input_q(rgb))
        heads_q = dequant_heads(net, q, hq)
        dets_f.append(detect(heads_f, hl, thresh=0.005))
        dets_q.append(detect(heads_q, hl, thresh=0.005))
        gts.append(load_labels(p))
        for a, b in zip(heads_f, heads_q):
            agree.append(np.corrcoef(a.ravel(), b.ravel())[0, 1])
        if (n + 1) % 50 == 0:
            print(f'  {n + 1}/{len(imgs)}  {time.time() - t0:.0f}s', flush=True)
    apf = compute_map(dets_f, gts, len(CLASSES))
    apq = compute_map(dets_q, gts, len(CLASSES))
    lines = [f'mAP@0.5 on valid[{start}:{start + N}] ({len(imgs)} images), calib pct={qp["pct"]}',
             f'{"class":10s} {"float":>8s} {"int8":>8s}']
    for c, n in enumerate(CLASSES):
        lines.append(f'{n:10s} {apf[c] * 100:8.2f} {apq[c] * 100:8.2f}')
    mf, mq = np.nanmean(apf) * 100, np.nanmean(apq) * 100
    lines.append(f'{"mAP":10s} {mf:8.2f} {mq:8.2f}   (delta {mq - mf:+.2f})')
    lines.append(f'head raw-output correlation float vs int8: mean {np.mean(agree):.4f} min {np.min(agree):.4f}')
    print('\n'.join(lines))
    with open(os.path.join(OUT, 'map_results.txt'), 'w') as f:
        f.write('\n'.join(lines) + '\n')
    json.dump({'float': apf, 'int8': apq, 'map_float': mf, 'map_int8': mq}, open(os.path.join(OUT, 'map_results.json'), 'w'))


if __name__ == '__main__':
    main()
