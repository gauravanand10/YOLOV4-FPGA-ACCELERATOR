# Post-build netlist checks (vivado -mode batch -source netlist_check.tcl):
#  1) hierarchical utilization of the accelerator core on the ROUTED design
#  2) post-synthesis functional netlist of the accelerator (for gate-level xsim of the feature test)
set here [file normalize [file dirname [info script]]]
set runs [file normalize $here/../../06_vivado/proj/yolo_zcu104.runs]
set rpt  [file normalize $here/../../06_vivado/reports]
set_param general.maxThreads 2

open_checkpoint $runs/impl_1/system_wrapper_routed.dcp
set core [get_cells system_i/yolo_accel/inst/u_core]
report_utilization -hierarchical -hierarchical_depth 6 -cells $core -file $rpt/utilization_core_hier.rpt
foreach c {u_eng/u_pe u_eng/u_ep u_eng u_ll u_wl u_wr u_regs} {
  set cell [get_cells -quiet system_i/yolo_accel/inst/u_core/$c]
  if {$cell eq ""} { puts "CELL $c: NOT FOUND"; continue }
  set leaf  [get_cells -quiet -hier -filter "IS_PRIMITIVE && NAME =~ [get_property NAME $cell]/*"]
  set n(lut)   [llength [filter $leaf {PRIMITIVE_GROUP == CLB && REF_NAME =~ LUT*}]]
  set n(ff)    [llength [filter $leaf {PRIMITIVE_GROUP == REGISTER}]]
  set n(carry) [llength [filter $leaf {REF_NAME == CARRY8}]]
  set n(dsp)   [llength [filter $leaf {REF_NAME =~ DSP*}]]
  set n(bram)  [llength [filter $leaf {REF_NAME =~ RAMB*}]]
  puts "CELL $c: LUT=$n(lut) FF=$n(ff) CARRY8=$n(carry) DSP=$n(dsp) RAMB=$n(bram)"
}
close_design

open_checkpoint $runs/synth_1/system_wrapper.dcp
write_verilog -force -mode funcsim -cell [get_cells system_i/yolo_accel/inst] -rename_top yolo_accel_wrap \
  $here/yolo_accel_wrap_funcsim.v
puts "PORTS: [llength [get_pins -of [get_cells system_i/yolo_accel/inst]]]"
close_design
puts "NETLIST CHECK DONE"
