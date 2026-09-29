"""Cycle / fps model of the accelerator micro-architecture (per layer, per 32-oc group).

Per layer : descriptor fetch (4 beats + read latency), then for each group
            weight load  = 32 param + 32*kkcc weight beats (+ latency), not overlapped
            stream       = max(compute, line-load) + fill of first rows + pipeline depth
              compute    = out_h*out_w*kkcc cycles (one (tap, cin_chunk) per cycle, 512 MAC)
              line-load  = stored input beats / read efficiency
            then wait for write responses.
"""
import os, sys, pickle
import numpy as np

F_CLK = 200e6
RD_LAT = 64        # cycles from AR to first R beat (PS DDR via HP port, conservative)
RD_EFF = 0.85      # achievable read beats/cycle on HP0 for long bursts
PIPE = 24          # compute + epilogue + writer pipeline depth


def layer_cycles(L, rd_lat=RD_LAT, rd_eff=RD_EFF):
    cc, kk = L.cc, L.k * L.k
    wload = 32 + 32 * L.kkcc + rd_lat
    compute = L.out_h * L.out_w * L.kkcc
    rows_f = 2 if L.pool else 1
    row_beats = L.in_buf.w * cc * rows_f
    total_load = L.in_hc * row_beats
    first_rows = min(L.k - L.pad, L.in_hc)
    fill = rd_lat + first_rows * row_beats / rd_eff
    stream = max(compute, total_load / rd_eff) + fill + PIPE
    g = L.groups
    tot = 4 + rd_lat + g * (wload + stream) + rd_lat
    return dict(name=L.name, groups=g, macs=L.out_h * L.out_w * L.cout * L.cin * kk,
                ideal=g * compute, wload=g * wload, stream=g * stream, total=tot,
                rd_bytes=g * (total_load + 32 + 32 * L.kkcc) * 16,
                wr_bytes=L.out_h * L.out_w * L.cout_pad * len(L.dests) * (4 if L.ups else 1))


def report(prog, **kw):
    rows = [layer_cycles(L, **kw) for L in prog.layers]
    lines = [f'{"layer":6s} {"grp":>3s} {"MMAC":>8s} {"ideal":>9s} {"wload":>8s} {"total":>9s} {"eff%":>5s} {"ms":>6s}']
    for r in rows:
        lines.append(f'{r["name"]:6s} {r["groups"]:3d} {r["macs"]/1e6:8.1f} {r["ideal"]:9d} {r["wload"]:8d} '
                     f'{int(r["total"]):9d} {100*r["ideal"]/r["total"]:5.1f} {r["total"]/F_CLK*1e3:6.2f}')
    ideal = sum(r['ideal'] for r in rows); tot = sum(r['total'] for r in rows)
    macs = sum(r['macs'] for r in rows)
    rdb = sum(r['rd_bytes'] for r in rows); wrb = sum(r['wr_bytes'] for r in rows)
    lines += [f'executed MACs (incl. pad): {macs/1e9:.3f} GMAC',
              f'ideal cycles (512 MAC/clk): {ideal/1e6:.3f} M  -> {F_CLK/ideal:.1f} fps (compute bound)',
              f'modelled cycles           : {tot/1e6:.3f} M  -> {F_CLK/tot:.1f} fps @ {F_CLK/1e6:.0f} MHz',
              f'PE utilisation            : {macs/(tot*512)*100:.1f} %',
              f'DDR traffic per frame     : read {rdb/2**20:.1f} MiB, write {wrb/2**20:.1f} MiB '
              f'({(rdb+wrb)*F_CLK/tot/1e9:.2f} GB/s avg)']
    return '\n'.join(lines), tot


def end_to_end(accel_cycles, sw_ms=(8.0, 14.0)):
    t_acc = accel_cycles / F_CLK * 1e3
    # board software (receive 519 KB frame over GbE ~4.2 ms, preprocess ~2 ms, decode+NMS ~1 ms, send)
    # runs in parallel with the accelerator (double-buffered) -> fps limited by max(accel, sw), serial if not.
    res = []
    for s in sw_ms:
        res.append((s, 1e3 / max(t_acc, s), 1e3 / (t_acc + s)))
    return t_acc, res


if __name__ == '__main__':
    sys.path.insert(0, os.path.dirname(__file__))
    from darknet_parse import load_network
    from hwprog import yolo_program
    net = load_network()
    q = pickle.load(open(os.path.join(os.path.dirname(__file__), 'out', 'qparams.pkl'), 'rb'))['q']
    prog = yolo_program(net, q); prog.layout(0x70000000)
    txt, tot = report(prog)
    t_acc, e2e = end_to_end(tot)
    txt += f'\naccelerator latency       : {t_acc:.2f} ms/frame'
    for s, fp, fs in e2e:
        txt += f'\nend-to-end (sw {s:4.1f} ms)    : {fp:.1f} fps pipelined, {fs:.1f} fps serial'
    print(txt)
    open(os.path.join(os.path.dirname(__file__), 'out', 'perf_model.txt'), 'w').write(txt + '\n')
