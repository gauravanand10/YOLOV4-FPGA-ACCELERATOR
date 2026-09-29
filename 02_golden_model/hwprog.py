"""Hardware program: buffer plan, DDR layout, binary descriptors, weight blob and a
descriptor-level DDR simulator that behaves exactly like the RTL (bit-exact golden for the TB).

DDR conventions
  * feature maps HWC, int8, byte addr = buf_base + (y*W + x)*pix_stride + ch
  * 128-bit beat = 16 consecutive bytes, byte i -> data[8i+7:8i]
  * all region bases 4 KiB aligned

Descriptor = 16 x uint32 (64 bytes), table at DESC_ADDR, layer i at DESC_ADDR + 64*i
  w0  in_addr        (buffer base + input channel byte offset)
  w1  out_addr       (buffer base + output channel byte offset)
  w2  out2_addr
  w3  w_addr         (layer weight blob)
  w4  in_w  | in_h  << 16      (stored input dims, before pooling)
  w5  out_w | out_h << 16      (conv output dims, before upsample)
  w6  in_pix_stride | out_pix_stride << 16   (bytes)
  w7  out2_pix_stride | cin_chunks << 16 | cout_groups << 24
  w8  k[3:0] | stride[7:4] | pad[11:8] | pool_in[12] | upsample[13] | out2_en[14]
  w9  kkcc = k*k*cin_chunks
  w10 group blob bytes = (32 + 32*kkcc) * 16
  w11 conv_in_w | conv_in_h << 16   (after pooling)
  w12..w14 reserved (0), w15 = layer id (debug)

Weight blob per layer, per 32-output-channel group g (at w_addr + g*w10):
  32 param beats  (o=0..31): [31:0] bias int32, [63:32] Mpos, [95:64] Mneg, [101:96] sh
  32*kkcc weight beats ordered [o][tap=ky*k+kx][c]: byte i = W[o][c*16+i][ky][kx]
"""
import numpy as np
import torch
import torch.nn.functional as F
from quant import epilogue, int_conv

ALIGN = 4096
DESC_WORDS = 16


def align(x, a=ALIGN):
    return (x + a - 1) // a * a


class Buf:
    def __init__(self, name, w, h, ch, init=None):
        self.name, self.w, self.h, self.ch = name, w, h, ch  # ch = pix_stride bytes
        self.init = init  # optional initial content (h,w,ch) int8
        self.addr = None

    @property
    def size(self):
        return self.w * self.h * self.ch


class HwLayer:
    def __init__(self, lid, in_buf, in_off, cin, k, s, pad, cout, dests, pool=False, ups=False,
                 wq=None, bias=None, Mp=None, Mn=None, sh=None, name=''):
        assert cin % 16 == 0
        self.lid, self.in_buf, self.in_off, self.cin = lid, in_buf, in_off, cin
        self.k, self.s, self.pad, self.cout = k, s, pad, cout
        self.cout_pad = (cout + 31) // 32 * 32
        self.dests = dests  # list of (Buf, ch_off) , max 2
        self.pool, self.ups = pool, ups
        self.name = name or f'L{lid}'
        cp, co = cin, self.cout_pad
        # pad weights/params to hardware shapes
        W = np.zeros((co, cp, k, k), np.int8); W[:wq.shape[0], :wq.shape[1]] = wq
        self.wq = W
        pad1 = lambda v, fill=0: np.concatenate([np.asarray(v, np.int64), np.full(co - len(v), fill, np.int64)])
        self.bias, self.Mp, self.Mn, self.sh = pad1(bias), pad1(Mp), pad1(Mn), pad1(sh, 1)
        self.w_addr = None

    @property
    def in_wc(self):
        return self.in_buf.w // 2 if self.pool else self.in_buf.w

    @property
    def in_hc(self):
        return self.in_buf.h // 2 if self.pool else self.in_buf.h

    @property
    def out_w(self):
        return (self.in_wc + 2 * self.pad - self.k) // self.s + 1

    @property
    def out_h(self):
        return (self.in_hc + 2 * self.pad - self.k) // self.s + 1

    @property
    def cc(self):
        return self.cin // 16

    @property
    def kkcc(self):
        return self.k * self.k * self.cc

    @property
    def groups(self):
        return self.cout_pad // 32

    @property
    def grp_bytes(self):
        return (32 + 32 * self.kkcc) * 16

    def blob(self):
        out = bytearray()
        k, cc = self.k, self.cc
        for g in range(self.groups):
            for o in range(32):
                oc = g * 32 + o
                out += _param_beat(int(self.bias[oc]), int(self.Mp[oc]), int(self.Mn[oc]), int(self.sh[oc]))
            # weights [o][tap][c][16]
            wg = self.wq[g * 32:(g + 1) * 32]  # (32, cin, k, k)
            wr = wg.reshape(32, cc, 16, k, k).transpose(0, 3, 4, 1, 2)  # o, ky, kx, c, i
            out += np.ascontiguousarray(wr).astype(np.int8).tobytes()
        assert len(out) == self.groups * self.grp_bytes
        return bytes(out)


def _param_beat(bias, Mp, Mn, sh):
    assert -(1 << 31) <= bias < (1 << 31) and 0 <= Mp < (1 << 17) and 0 <= Mn < (1 << 17) and 1 <= sh <= 63
    return np.array([bias & 0xFFFFFFFF, Mp, Mn, sh], np.uint64).astype(np.uint32).tobytes()


class Program:
    def __init__(self, name, bufs, layers, input_buf, outputs):
        self.name, self.bufs, self.layers = name, bufs, layers
        self.input_buf, self.outputs = input_buf, outputs  # outputs: list of (Buf, real_channels)

    def layout(self, base):
        self.base = base
        a = base
        self.desc_addr = a
        a = align(a + DESC_WORDS * 4 * len(self.layers))
        for b in self.bufs:
            b.addr = a
            a = align(a + b.size)
        self.w_base = a
        for L in self.layers:
            L.w_addr = a
            a = align(a + L.groups * L.grp_bytes, 64)
        self.end = align(a)
        return self.end - base

    def descriptors(self):
        out = bytearray()
        for L in self.layers:
            d1b, d1o = L.dests[0]
            d2b, d2o = L.dests[1] if len(L.dests) > 1 else (L.dests[0][0], L.dests[0][1])
            assert d1b.w == L.out_w * (2 if L.ups else 1) and d1b.h == L.out_h * (2 if L.ups else 1), L.name
            assert L.in_off + L.cin <= L.in_buf.ch and d1o + L.cout_pad <= d1b.ch and d2o + L.cout_pad <= d2b.ch
            assert L.in_wc * L.cc <= 1024 and L.kkcc <= 512 and L.in_buf.ch % 16 == 0 and d1b.ch % 32 == 0
            if L.pool:
                assert L.in_buf.w % 2 == 0 and L.in_buf.h % 2 == 0
            w = [0] * DESC_WORDS
            w[0] = L.in_buf.addr + L.in_off
            w[1] = d1b.addr + d1o
            w[2] = d2b.addr + d2o
            w[3] = L.w_addr
            w[4] = L.in_buf.w | L.in_buf.h << 16
            w[5] = L.out_w | L.out_h << 16
            w[6] = L.in_buf.ch | d1b.ch << 16
            w[7] = d2b.ch | L.cc << 16 | L.groups << 24
            w[8] = L.k | L.s << 4 | L.pad << 8 | int(L.pool) << 12 | int(L.ups) << 13 | int(len(L.dests) > 1) << 14
            w[9] = L.kkcc
            w[10] = L.grp_bytes
            w[11] = L.in_wc | L.in_hc << 16
            w[15] = L.lid
            out += np.array(w, np.uint32).tobytes()
        return bytes(out)

    def ddr_image(self, input_hwc=None):
        """Initial DDR content (bytes, relative to base)."""
        mem = np.zeros(self.end - self.base, np.uint8)
        d = self.descriptors()
        mem[self.desc_addr - self.base:][:len(d)] = np.frombuffer(d, np.uint8)
        for L in self.layers:
            b = L.blob()
            mem[L.w_addr - self.base:][:len(b)] = np.frombuffer(b, np.uint8)
        for b in self.bufs:
            if b.init is not None:
                mem[b.addr - self.base:][:b.size] = b.init.astype(np.int8).view(np.uint8).ravel()
        if input_hwc is not None:
            ib = self.input_buf
            mem[ib.addr - self.base:][:ib.size] = input_hwc.astype(np.int8).view(np.uint8).ravel()
        return mem

    def read_buf(self, mem, buf, ch0=0, nch=None):
        nch = buf.ch - ch0 if nch is None else nch
        a = buf.addr - self.base
        t = mem[a:a + buf.size].view(np.int8).reshape(buf.h, buf.w, buf.ch)
        return t[:, :, ch0:ch0 + nch].transpose(2, 0, 1).copy()


# ------------------------------------------------------------------------------------------------
# Descriptor-level simulator: reads only DDR bytes (descriptors, blobs, maps), like the RTL does.
def _u32(mem, a):
    return int(mem[a:a + 4].view('<u4')[0])


def simulate(mem, base, desc_addr, num_layers, trace=None):
    for i in range(num_layers):
        da = desc_addr - base + 64 * i
        w = [_u32(mem, da + 4 * j) for j in range(16)]
        in_addr, out_addr, out2_addr, w_addr = w[0] - base, w[1] - base, w[2] - base, w[3] - base
        in_w, in_h = w[4] & 0xFFFF, w[4] >> 16
        out_w, out_h = w[5] & 0xFFFF, w[5] >> 16
        ips, ops = w[6] & 0xFFFF, w[6] >> 16
        o2ps, cc, ng = w[7] & 0xFFFF, (w[7] >> 16) & 0xFF, w[7] >> 24
        k, s, pad = w[8] & 15, (w[8] >> 4) & 15, (w[8] >> 8) & 15
        pool, ups, o2en = (w[8] >> 12) & 1, (w[8] >> 13) & 1, (w[8] >> 14) & 1
        kkcc, gbytes = w[9], w[10]
        assert kkcc == k * k * cc
        # gather input
        cin = cc * 16
        pix = (np.arange(in_h)[:, None] * in_w + np.arange(in_w)[None, :]) * ips + in_addr
        idx = pix[:, :, None] + np.arange(cin)[None, None, :]
        x = mem[idx].view(np.int8)  # (H,W,cin)
        if pool:
            x = x.reshape(in_h // 2, 2, in_w // 2, 2, cin).max(axis=(1, 3))
        x = x.transpose(2, 0, 1)
        # weights + params
        nco = ng * 32
        Wt = np.zeros((nco, cin, k, k), np.int8)
        bias = np.zeros(nco, np.int64); Mp = np.zeros_like(bias); Mn = np.zeros_like(bias); sh = np.zeros_like(bias)
        for g in range(ng):
            ga = w_addr + g * gbytes
            pr = mem[ga:ga + 512].view('<u4').reshape(32, 4).astype(np.int64)
            bias[g * 32:(g + 1) * 32] = pr[:, 0].astype(np.uint32).view(np.int32)
            Mp[g * 32:(g + 1) * 32] = pr[:, 1] & 0x1FFFF
            Mn[g * 32:(g + 1) * 32] = pr[:, 2] & 0x1FFFF
            sh[g * 32:(g + 1) * 32] = pr[:, 3] & 63
            wr = mem[ga + 512:ga + 512 + 32 * kkcc * 16].view(np.int8).reshape(32, k, k, cc, 16)
            Wt[g * 32:(g + 1) * 32] = wr.transpose(0, 3, 4, 1, 2).reshape(32, cin, k, k)
        acc = int_conv(x, Wt, s, pad)
        assert acc.shape[1:] == (out_h, out_w), (acc.shape, out_h, out_w)
        y = epilogue(acc, bias, Mp, Mn, sh)  # (nco, oh, ow)
        yh = y.transpose(1, 2, 0)
        dests = [(out_addr, ops, ups)] + ([(out2_addr, o2ps, ups)] if o2en else [])
        for a0, ps, up in dests:
            f = 2 if up else 1
            yy = yh.repeat(f, 0).repeat(f, 1) if up else yh
            H2, W2 = yy.shape[:2]
            pix = (np.arange(H2)[:, None] * W2 + np.arange(W2)[None, :]) * ps + a0
            idx = pix[:, :, None] + np.arange(nco)[None, None, :]
            mem[idx] = yy.view(np.uint8)
        if trace is not None:
            trace.append(dict(layer=w[15], acc=acc, y=y))
    return mem


# ------------------------------------------------------------------------------------------------
def yolo_program(net, q):
    """Buffer plan of the handoff spec for YOLOv4-tiny (416)."""
    B = {}
    def buf(name, w, h, ch):
        B[name] = Buf(name, w, h, ch); return B[name]
    IN = buf('IN', 416, 416, 16)
    buf('B0', 208, 208, 32); buf('B1', 104, 104, 64)
    buf('B8', 104, 104, 128); buf('B6', 104, 104, 64)
    buf('B16', 52, 52, 256); buf('B14', 52, 52, 128)
    buf('B24', 26, 26, 512); buf('B22', 26, 26, 256); buf('B34', 26, 26, 384)
    buf('B26', 13, 13, 512); buf('B27', 13, 13, 256); buf('B28', 13, 13, 512)
    buf('B35', 26, 26, 256)
    buf('OUT1', 13, 13, 64); buf('OUT2', 26, 26, 64)
    # (lid, in_buf, in_off, cin, dests, pool, ups)
    plan = [
        (0, 'IN', 0, 16, [('B0', 0)], 0, 0),
        (1, 'B0', 0, 32, [('B1', 0)], 0, 0),
        (2, 'B1', 0, 64, [('B8', 0)], 0, 0),
        (4, 'B8', 32, 32, [('B6', 32)], 0, 0),
        (5, 'B6', 32, 32, [('B6', 0)], 0, 0),
        (7, 'B6', 0, 64, [('B8', 64)], 0, 0),
        (10, 'B8', 0, 128, [('B16', 0)], 1, 0),
        (12, 'B16', 64, 64, [('B14', 64)], 0, 0),
        (13, 'B14', 64, 64, [('B14', 0)], 0, 0),
        (15, 'B14', 0, 128, [('B16', 128)], 0, 0),
        (18, 'B16', 0, 256, [('B24', 0)], 1, 0),
        (20, 'B24', 128, 128, [('B22', 128)], 0, 0),
        (21, 'B22', 128, 128, [('B22', 0)], 0, 0),
        (23, 'B22', 0, 256, [('B24', 256), ('B34', 128)], 0, 0),
        (26, 'B24', 0, 512, [('B26', 0)], 1, 0),
        (27, 'B26', 0, 512, [('B27', 0)], 0, 0),
        (28, 'B27', 0, 256, [('B28', 0)], 0, 0),
        (29, 'B28', 0, 512, [('OUT1', 0)], 0, 0),
        (32, 'B27', 0, 256, [('B34', 0)], 0, 1),
        (35, 'B34', 0, 384, [('B35', 0)], 0, 0),
        (36, 'B35', 0, 256, [('OUT2', 0)], 0, 0),
    ]
    layers = []
    for lid, ib, io, cin, dests, pool, ups in plan:
        L = net['layers'][lid]; p = q[lid]
        layers.append(HwLayer(lid, B[ib], io, cin, L['k'], L['stride'], L['pad'], L['cout'],
                              [(B[n], o) for n, o in dests], bool(pool), bool(ups),
                              p['wq'], p['bias'], p['Mp'], p['Mn'], p['sh']))
    return Program('yolov4tiny', list(B.values()), layers, IN, [(B['OUT1'], 36), (B['OUT2'], 36)])


def input_hwc16(rgb_u8):
    """uint8 416x416x3 RGB -> int8 416x416x16 (pixel>>1, channels 3..15 zero). Same as board preprocessing."""
    h, w, _ = rgb_u8.shape
    x = np.zeros((h, w, 16), np.int8)
    x[:, :, :3] = (rgb_u8 >> 1).astype(np.int8)
    return x


# ------------------------------------------------------------------------------------------------
def _rand_layer(rng, lid, in_buf, in_off, cin, k, s, pad, cout, dests, pool=False, ups=False):
    """Random weights/params that keep outputs spread over the int8 range, plus saturation corner cases."""
    wq = rng.integers(-128, 128, (cout, cin, k, k)).astype(np.int8)
    n = cin * k * k
    acc_std = 74.0 * 74.0 * np.sqrt(n)
    Mp = rng.integers(1 << 15, 1 << 16, cout)
    sh = np.zeros(cout, np.int64)
    for o in range(cout):
        m = rng.uniform(40, 200) / (2 * acc_std)
        sh[o] = int(np.clip(np.round(np.log2(Mp[o] / m)), 1, 63))
    bias = rng.integers(-int(acc_std), int(acc_std), cout)
    bias[0] = (1 << 31) - 1          # -> sat27 positive
    if cout > 1:
        bias[1] = -(1 << 31)         # -> sat27 negative
    if cout > 2:
        sh[2] = max(1, sh[2] - 6)    # strong gain -> int8 saturation
    leaky = rng.integers(0, 2, cout).astype(bool)
    Mn = np.where(leaky, np.rint(0.1 * Mp).astype(np.int64), Mp)
    return HwLayer(lid, in_buf, in_off, cin, k, s, pad, cout, dests, pool, ups, wq, bias, Mp, Mn, sh)


def feature_program(seed=1):
    rng = np.random.default_rng(seed)
    ri = lambda h, w, c: rng.integers(-128, 128, (h, w, c)).astype(np.int8)
    IN = Buf('IN', 40, 24, 16)
    A = Buf('A', 20, 12, 96)            # non power-of-2 stride -> pixels straddle 4 KiB pages
    D = Buf('D', 20, 12, 64)
    Bb = Buf('B', 20, 12, 64)
    C = Buf('C', 10, 6, 128)
    E = Buf('E', 20, 12, 64)
    R = Buf('R', 13, 7, 32, ri(7, 13, 32))
    F_ = Buf('F', 7, 4, 64)
    G = Buf('G', 5, 3, 512, ri(3, 5, 512))
    H = Buf('H', 5, 3, 32)
    WR = Buf('WR', 64, 2, 256, ri(2, 64, 256))
    I = Buf('I', 64, 2, 32)
    P = Buf('P', 16, 20, 32, ri(20, 16, 32))
    Q = Buf('Q', 8, 10, 32)
    L = [
        _rand_layer(rng, 0, IN, 0, 16, 3, 2, 1, 64, [(A, 0), (D, 0)]),        # s2, dual dest, 2 groups
        _rand_layer(rng, 1, A, 32, 32, 3, 1, 1, 32, [(A, 64)]),               # group-split read, concat write
        _rand_layer(rng, 2, A, 0, 96, 1, 1, 0, 64, [(Bb, 0)]),                # 1x1, cc=6 strided
        _rand_layer(rng, 3, Bb, 0, 64, 3, 1, 1, 96, [(C, 32)], pool=True),   # pool + 3x3, 3 groups
        _rand_layer(rng, 4, D, 0, 64, 1, 1, 0, 32, [(C, 0)], pool=True),     # pool + 1x1
        _rand_layer(rng, 5, C, 0, 128, 1, 1, 0, 32, [(E, 0)], ups=True),     # upsample writer
        _rand_layer(rng, 6, R, 0, 32, 3, 2, 1, 36, [(F_, 0)]),               # odd dims s2, head padding 36->64
        _rand_layer(rng, 7, G, 0, 512, 3, 1, 1, 32, [(H, 0)]),               # kkcc = 288
        _rand_layer(rng, 8, WR, 0, 256, 1, 1, 0, 32, [(I, 0)]),              # 1024-beat line
        _rand_layer(rng, 9, P, 0, 32, 3, 1, 1, 32, [(Q, 0)], pool=True),     # pooled rows > 8 slots
        _rand_layer(rng, 10, E, 0, 32, 3, 1, 1, 32, [(E, 32)]),              # reads upsampled data
    ]
    IN.init = ri(24, 40, 16)
    return Program('feature', [IN, A, D, Bb, C, E, R, F_, G, H, WR, I, P, Q], L, IN,
                   [(b, b.ch) for b in (A, D, Bb, C, E, F_, H, I, Q)])
