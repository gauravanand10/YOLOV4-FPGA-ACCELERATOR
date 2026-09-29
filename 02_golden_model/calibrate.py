"""Calibrate activation scales on validation images [1000:1100] (disjoint from mAP eval set) and save qparams."""
import sys, os, glob, pickle, time
import numpy as np
from darknet_parse import load_network, ROOT
from float_model import FloatNet
from quant import calibrate, quantize_network

OUT = os.path.join(os.path.dirname(__file__), 'out')
os.makedirs(OUT, exist_ok=True)

def valid_images():
    return sorted(glob.glob(os.path.join(ROOT, '01_dataset/images/valid/*.jpg')))

if __name__ == '__main__':
    pct = float(sys.argv[1]) if len(sys.argv) > 1 else 99.999
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 100
    net = load_network(); fn = FloatNet(net)
    imgs = valid_images()[1000:1000 + n]
    t = time.time()
    scales, maxes = calibrate(net, fn, imgs, pct)
    q = quantize_network(net, scales)
    for k in sorted(scales):
        print(f'  L{k:2d}  max={maxes[k]:9.4f}  clip={scales[k]*127:9.4f}  s_out={scales[k]:.6f}')
    with open(os.path.join(OUT, f'qparams.pkl'), 'wb') as f:
        pickle.dump({'scales': scales, 'q': q, 'pct': pct, 'calib_images': imgs}, f)
    print(f'saved out/qparams.pkl  pct={pct}  ({time.time()-t:.0f}s)')
