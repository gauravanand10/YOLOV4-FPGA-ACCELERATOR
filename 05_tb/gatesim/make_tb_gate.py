"""Generate tb_top_gate.sv (gate-level copy of ../tb_top.sv): drop the dut.u_core peeks, wait for glbl GSR."""
import os, re
here = os.path.dirname(os.path.abspath(__file__))
s = open(os.path.join(here, '..', 'tb_top.sv')).read()
a = s.index('  // ---------------- per-layer progress ----------------')
b = s.index('  // ---------------- test ----------------')
s = s[:a] + '  // (gate-level copy: per-layer progress monitor removed, it peeks into the RTL hierarchy)\n\n' + s[b:]
s = re.sub(r'\$fatal\(1, "TIMEOUT after %0d cycles \(layer %0d\)", maxcyc, dut\.u_core\.layer\);',
           '$fatal(1, "TIMEOUT after %0d cycles", maxcyc);', s)
old = '    repeat (10) @(posedge clk);\n    rst_n = 1;'
assert old in s
s = s.replace(old, '    repeat (10) @(posedge clk);\n    #200 @(posedge clk);   // gate-level: wait for glbl GSR (100 ns) to end\n    rst_n = 1;')
assert 'dut.u_core' not in s, [l for l in s.splitlines() if 'u_core' in l]
open(os.path.join(here, 'tb_top_gate.sv'), 'w').write(
    '// GENERATED from ../tb_top.sv by make_tb_gate.py (gate-level flow) - do not edit\n' + s)
print('tb_top_gate.sv written')
