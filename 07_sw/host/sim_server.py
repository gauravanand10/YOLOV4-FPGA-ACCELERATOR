"""Board emulator: speaks the yolo_server TCP protocol but computes with the bit-exact INT8 golden
model on the PC (slow, ~0.5 s/frame). Used to test yolo_client.py without hardware.

usage: python sim_server.py [--port 5000]
"""
import argparse, os, sys, socket, struct, pickle, time
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.join(ROOT, '02_golden_model'))
from darknet_parse import load_network           # noqa: E402
from quant import int8_forward, input_q, dequant_heads  # noqa: E402
from yolo_decode import detect                    # noqa: E402

MAGIC_F, MAGIC_R = 0x464C4F59, 0x524C4F59


def recv_all(s, n):
    b = bytearray()
    while len(b) < n:
        c = s.recv(n - len(b))
        if not c:
            raise ConnectionError
        b += c
    return bytes(b)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--port', type=int, default=5000); a = ap.parse_args()
    net = load_network()
    q = pickle.load(open(os.path.join(ROOT, '02_golden_model/out/qparams.pkl'), 'rb'))['q']
    ls = socket.socket(); ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ls.bind(('0.0.0.0', a.port)); ls.listen(1)
    print(f'sim_server on port {a.port}')
    while True:
        c, addr = ls.accept(); print('client', addr)
        try:
            while True:
                magic, fid, w, h = struct.unpack('<4I', recv_all(c, 16))
                assert magic == MAGIC_F and w == 416 and h == 416
                rgb = np.frombuffer(recv_all(c, w * h * 3), np.uint8).reshape(h, w, 3)
                t = time.time()
                _, heads = int8_forward(net, q, input_q(rgb))
                dets = detect(dequant_heads(net, q, heads), [L for L, _ in heads], thresh=0.25)
                ms = (time.time() - t) * 1e3
                body = b''.join(struct.pack('<5fi', x1, y1, x2, y2, s, cl) for x1, y1, x2, y2, s, cl in dets)
                c.sendall(struct.pack('<3I2f', MAGIC_R, fid, len(dets), ms, ms) + body)
        except (ConnectionError, OSError, AssertionError) as e:
            print('client gone', e)
            c.close()


if __name__ == '__main__':
    main()
