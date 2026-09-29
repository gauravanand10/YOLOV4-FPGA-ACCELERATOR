"""INT8 quantization + bit-exact integer tensor model.

Arithmetic contract (identical in RTL, descriptor simulator and this model):
  acc  = sum(wq * xq)                                   (int32)
  t    = sat27(acc + bias32)                            (27-bit signed)
  M    = Mneg if t < 0 else Mpos                        (Mneg = round(0.1*Mpos) for leaky, = Mpos for linear)
  y    = clamp_int8((t * M + (1 << (sh-1))) >>> sh)     (arithmetic shift = floor)
Activations: per-tensor symmetric scale per conv output. Input image: q = pixel >> 1 (scale 2/255).
Consumer convs fold the per-input-channel scale vector into the weights, then quantize per output channel.
"""
import numpy as np
import torch
import torch.nn.functional as F

T27_MIN, T27_MAX = -(1 << 26), (1 << 26) - 1
IN_SCALE = 2.0 / 255.0
M_BITS = 16  # Mpos normalised into [2^15, 2^16] -> fits DSP 18-bit signed port


def quant_multiplier(m):
    """Return (M, sh) with m ~= M * 2^-sh, M in [2^15, 2^16]."""
    if m <= 0:
        return 0, 1
    sh = int(np.floor(np.log2((1 << M_BITS) / m)))
    if (m * 2.0 ** sh) >= (1 << M_BITS):
        sh -= 1
    while m * 2.0 ** sh < (1 << (M_BITS - 1)):
        sh += 1
    sh = max(1, min(sh, 56))
    M = int(round(m * 2.0 ** sh))
    return M, sh


def epilogue(acc, bias, Mp, Mn, sh):
    """acc: int64 array (C,H,W); per-channel vectors bias/Mp/Mn/sh (int64). Returns int8 array."""
    t = acc + bias[:, None, None]
    t = np.clip(t, T27_MIN, T27_MAX)
    M = np.where(t < 0, Mn[:, None, None], Mp[:, None, None])
    sh_ = sh[:, None, None]
    y = (t * M + (np.int64(1) << (sh_ - 1))) >> sh_
    return np.clip(y, -128, 127).astype(np.int8)


def int_conv(xq, wq, stride, pad):
    """Exact integer conv using float32. xq (C,H,W) int8, wq (O,C,k,k) int8. Returns int32 (O,H',W').
    |x*w| <= 2^14, so a group of <= 1024 products stays <= 2^24 (exact in float32); input channels are
    split into such groups and the partial sums are added in int32 (network max |acc| < 2^27)."""
    C, k = wq.shape[1], wq.shape[2]
    cg = max(1, 1024 // (k * k))
    acc = None
    for c0 in range(0, C, cg):
        x = torch.from_numpy(xq[c0:c0 + cg].astype(np.float32))[None]
        w = torch.from_numpy(wq[:, c0:c0 + cg].astype(np.float32))
        y = np.rint(F.conv2d(x, w, stride=stride, padding=pad)[0].numpy()).astype(np.int32)
        acc = y if acc is None else acc + y
    return acc


# ---------------------------------------------------------------------------------------------
def calibrate(net, fnet, images, pct=99.999, log=print):
    """Collect per-conv-output absolute-value statistics on float model. Returns {idx: scale}."""
    from float_model import load_image, to_tensor
    samples = {L['idx']: [] for L in net['layers'] if L['type'] == 'convolutional'}
    maxes = {k: 0.0 for k in samples}
    rng = np.random.default_rng(0)
    for n, p in enumerate(images):
        rgb, _ = load_image(p)
        outs, _ = fnet.forward(to_tensor(rgb))
        for k in samples:
            a = outs[k].abs().flatten().numpy()
            maxes[k] = max(maxes[k], float(a.max()))
            if a.size > 100000:
                a = rng.choice(a, 100000, replace=False)
            samples[k].append(a)
        if (n + 1) % 20 == 0:
            log(f'  calib {n + 1}/{len(images)}')
    scales = {}
    for k, v in samples.items():
        v = np.concatenate(v)
        r = float(np.percentile(v, pct))
        scales[k] = max(r, 1e-6) / 127.0
    return scales, maxes


def quantize_network(net, act_scales):
    """Returns {idx: qparams} for every conv. qparams: wq (O,Cin,k,k) int8, bias, Mp, Mn, sh (int64 vecs),
    s_out (float), s_in (vector), leaky (bool)."""
    layers = net['layers']
    ch_scale = {}  # per-layer-output per-channel scale vectors
    q = {}
    in_scale = np.full(net['C'], IN_SCALE)
    prev = in_scale
    for L in layers:
        t = L['type']
        if t == 'convolutional':
            s_in = prev
            w = L['w'] * s_in[None, :, None, None]
            sw = np.abs(w).reshape(w.shape[0], -1).max(1) / 127.0
            sw = np.where(sw > 0, sw, 1.0)
            wq = np.clip(np.rint(w / sw[:, None, None, None]), -127, 127).astype(np.int8)
            bias = np.clip(np.rint(L['b'] / sw), -(1 << 31), (1 << 31) - 1).astype(np.int64)
            s_out = act_scales[L['idx']]
            leaky = L['act'] == 'leaky'
            Mp = np.zeros(L['cout'], np.int64); Mn = np.zeros_like(Mp); sh = np.ones_like(Mp)
            for o in range(L['cout']):
                M, s = quant_multiplier(sw[o] / s_out)
                Mp[o] = M; sh[o] = s
                Mn[o] = int(round(0.1 * M)) if leaky else M
            q[L['idx']] = dict(wq=wq, bias=bias, Mp=Mp, Mn=Mn, sh=sh, s_out=s_out, s_in=s_in, sw=sw,
                               leaky=leaky, k=L['k'], stride=L['stride'], pad=L['pad'])
            cur = np.full(L['cout'], s_out)
        elif t == 'maxpool' or t == 'upsample' or t == 'yolo':
            cur = prev
        elif t == 'route':
            parts = []
            for r in L['refs']:
                v = ch_scale[r]
                if L['groups'] > 1:
                    c = len(v) // L['groups']
                    v = v[c * L['group_id']:c * (L['group_id'] + 1)]
                parts.append(v)
            cur = np.concatenate(parts)
        ch_scale[L['idx']] = cur
        prev = cur
    return q


def input_q(rgb_u8):
    """uint8 HWC RGB -> int8 CHW (pixel >> 1)."""
    return (rgb_u8 >> 1).astype(np.int8).transpose(2, 0, 1).copy()


def int8_forward(net, q, xq):
    """Integer tensor-level model. xq (3,H,W) int8. Returns (per-layer outputs, [(yolo layer, int8 head)])."""
    outs = []
    heads = []
    x = xq
    for L in net['layers']:
        t = L['type']
        if t == 'convolutional':
            p = q[L['idx']]
            acc = int_conv(x, p['wq'], p['stride'], p['pad'])
            x = epilogue(acc, p['bias'], p['Mp'], p['Mn'], p['sh'])
        elif t == 'maxpool':
            C, H, W = x.shape
            x = x.reshape(C, H // 2, 2, W // 2, 2).max(axis=(2, 4))
        elif t == 'route':
            parts = []
            for r in L['refs']:
                o = outs[r]
                if L['groups'] > 1:
                    c = o.shape[0] // L['groups']
                    o = o[c * L['group_id']:c * (L['group_id'] + 1)]
                parts.append(o)
            x = np.concatenate(parts, 0)
        elif t == 'upsample':
            x = x.repeat(L['stride'], 1).repeat(L['stride'], 2)
        elif t == 'yolo':
            heads.append((L, x))
        outs.append(x)
    return outs, heads


def dequant_heads(net, q, heads):
    """Heads -> float raw values. heads [(yolo L, int8 (36,H,W))]."""
    res = []
    for L, h in heads:
        conv_idx = L['idx'] - 1
        res.append(h.astype(np.float64) * q[conv_idx]['s_out'])
    return res
