"""Verify: descriptor-level DDR simulator == int8 tensor model (bit-exact), on N valid images."""
import sys, os, glob, pickle, time
import numpy as np
from darknet_parse import load_network, ROOT
from float_model import load_image
from quant import int8_forward, input_q
from hwprog import yolo_program, simulate, input_hwc16
net = load_network(); q = pickle.load(open('out/qparams.pkl', 'rb'))['q']
prog = yolo_program(net, q); sz = prog.layout(0x70000000)
print(f'DDR footprint {sz/2**20:.2f} MiB, weights {(prog.end-prog.w_base)/2**20:.2f} MiB')
N = int(sys.argv[1]) if len(sys.argv) > 1 else 2
ok = True
for p in sorted(glob.glob(os.path.join(ROOT, '01_dataset/images/valid/*.jpg')))[:N]:
    rgb, _ = load_image(p)
    outs, heads = int8_forward(net, q, input_q(rgb))
    t = time.time()
    mem = simulate(prog.ddr_image(input_hwc16(rgb)), prog.base, prog.desc_addr, len(prog.layers))
    dt = time.time() - t
    for (L, h), (b, nc) in zip(heads, prog.outputs):
        hw = prog.read_buf(mem, b, 0, 64)
        same = np.array_equal(hw[:nc], h) and not hw[nc:].any()
        ok &= same
        print(f'{os.path.basename(p)} {b.name}: {"MATCH" if same else "MISMATCH"}  ({dt:.1f}s)')
print('PASS' if ok else 'FAIL')
