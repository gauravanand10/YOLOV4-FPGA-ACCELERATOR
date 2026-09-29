"""Darknet (AlexeyAB) cfg + weights parser for YOLOv4-tiny.

Produces a list of layer dicts in cfg order. Conv layers carry BN-folded float
weights (OIHW, float64) and biases. BN folding follows the project spec:
    w' = w * scale / (sqrt(var) + 1e-6),  b' = beta - mean * scale / (sqrt(var) + 1e-6)
"""
import os
import struct
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
CFG = os.path.join(ROOT, '00_model', 'cfg', 'yolov4-tiny-7class-train.cfg')
WEIGHTS = os.path.join(ROOT, '00_model', 'weights', 'yolov4-tiny-7class-train_final.weights')
CLASSES = ['person', 'car', 'bicycle', 'bottle', 'chair', 'laptop', 'cup']


def parse_cfg(path):
    sections = []
    cur = None
    with open(path) as f:
        for line in f:
            line = line.split('#')[0].strip()
            if not line:
                continue
            if line.startswith('['):
                cur = {'type': line[1:-1].strip()}
                sections.append(cur)
            else:
                k, v = line.split('=', 1)
                cur[k.strip()] = v.strip()
    return sections


def _ints(s):
    return [int(x) for x in s.split(',') if x.strip()]


def load_network(cfg_path=CFG, weights_path=WEIGHTS):
    secs = parse_cfg(cfg_path)
    net = secs[0]
    assert net['type'] == 'net'
    H, W, C = int(net['height']), int(net['width']), int(net['channels'])
    layers = []
    shapes = []  # (c, h, w) output of each layer
    fw = open(weights_path, 'rb')
    major, minor, rev = struct.unpack('3i', fw.read(12))
    if major * 10 + minor >= 2:
        fw.read(8)
    else:
        fw.read(4)
    cin, h, w = C, H, W
    for i, s in enumerate(secs[1:]):
        t = s['type']
        L = {'idx': i, 'type': t}
        if t == 'convolutional':
            n = int(s['filters'])
            k = int(s['size'])
            st = int(s.get('stride', 1))
            pad = k // 2 if int(s.get('pad', 0)) else int(s.get('padding', 0))
            bn = int(s.get('batch_normalize', 0))
            act = s.get('activation', 'logistic')
            if bn:
                b, sc, mu, var = [np.frombuffer(fw.read(4 * n), np.float32).astype(np.float64) for _ in range(4)]
            else:
                b = np.frombuffer(fw.read(4 * n), np.float32).astype(np.float64)
            wt = np.frombuffer(fw.read(4 * n * cin * k * k), np.float32).astype(np.float64).reshape(n, cin, k, k)
            if bn:
                f = sc / (np.sqrt(var) + 1e-6)
                wt = wt * f[:, None, None, None]
                b = b - mu * f
            ho = (h + 2 * pad - k) // st + 1
            wo = (w + 2 * pad - k) // st + 1
            L.update(cin=cin, cout=n, k=k, stride=st, pad=pad, act=act, w=wt, b=b,
                     in_shape=(cin, h, w), out_shape=(n, ho, wo))
            cin, h, w = n, ho, wo
        elif t == 'maxpool':
            k = int(s['size']); st = int(s['stride'])
            assert k == 2 and st == 2 and h % 2 == 0 and w % 2 == 0
            h, w = h // 2, w // 2
            L.update(size=k, stride=st, out_shape=(cin, h, w))
        elif t == 'route':
            refs = [r if r >= 0 else i + r for r in _ints(s['layers'])]
            groups = int(s.get('groups', 1)); gid = int(s.get('group_id', 0))
            cs = [shapes[r][0] // groups for r in refs]
            h, w = shapes[refs[0]][1], shapes[refs[0]][2]
            for r in refs:
                assert shapes[r][1:] == (h, w)
            cin = sum(cs)
            L.update(refs=refs, groups=groups, group_id=gid, out_shape=(cin, h, w))
        elif t == 'upsample':
            st = int(s['stride']); h, w = h * st, w * st
            L.update(stride=st, out_shape=(cin, h, w))
        elif t == 'yolo':
            mask = _ints(s['mask'])
            anc = _ints(s['anchors'])
            anc = [(anc[2 * j], anc[2 * j + 1]) for j in range(len(anc) // 2)]
            L.update(mask=mask, anchors=[anc[m] for m in mask], classes=int(s['classes']),
                     scale_x_y=float(s.get('scale_x_y', 1.0)), out_shape=(cin, h, w))
        else:
            raise ValueError(t)
        shapes.append(L['out_shape'])
        layers.append(L)
    rest = fw.read()
    fw.close()
    assert len(rest) == 0, f'{len(rest)} bytes left in weights file'
    return {'H': H, 'W': W, 'C': C, 'layers': layers}


def macs(net):
    tot = 0
    for L in net['layers']:
        if L['type'] == 'convolutional':
            c, h, w = L['out_shape']
            tot += c * h * w * L['cin'] * L['k'] ** 2
    return tot


if __name__ == '__main__':
    net = load_network()
    for L in net['layers']:
        extra = ''
        if L['type'] == 'convolutional':
            extra = f"k{L['k']} s{L['stride']} {L['cin']}->{L['cout']} {L['act']}"
        elif L['type'] == 'route':
            extra = f"refs={L['refs']} groups={L['groups']} gid={L['group_id']}"
        print(f"{L['idx']:2d} {L['type']:13s} out={L['out_shape']} {extra}")
    print(f'GMAC/frame = {macs(net) / 1e9:.3f}')
