import sys, glob, os, time
import numpy as np
from darknet_parse import load_network, CLASSES, ROOT
from float_model import FloatNet, load_image, to_tensor
from yolo_decode import detect
net = load_network(); fn = FloatNet(net)
imgs = sorted(glob.glob(os.path.join(ROOT, '01_dataset/images/valid/*.jpg')))[:int(sys.argv[1]) if len(sys.argv) > 1 else 3]
for p in imgs:
    rgb, (h0, w0) = load_image(p)
    t = time.time(); outs, heads = fn.forward(to_tensor(rgb)); dt = time.time() - t
    dets = detect([x[0].numpy().astype(np.float64) for _, x in heads], [L for L, _ in heads])
    print(os.path.basename(p), f'{dt*1000:.0f} ms')
    for x1, y1, x2, y2, s, c in sorted(dets, key=lambda d: -d[4]):
        print(f'   {CLASSES[c]:8s} {s*100:5.1f}%  left={x1*w0:.0f} top={y1*h0:.0f} w={(x2-x1)*w0:.0f} h={(y2-y1)*h0:.0f}')
