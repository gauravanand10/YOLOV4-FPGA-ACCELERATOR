# Out-of-context synthesis of yolo_accel_wrap (same RTL, same synth defaults as the system build, all ports
# kept) -> post-synthesis functional netlist for gate-level xsim of the 05_tb tests.
# The in-system netlist cannot be cut at the accelerator cell: global synthesis optimises across that
# boundary (constant AXI outputs removed, internal nets turned into ports).
set here [file normalize [file dirname [info script]]]
set rtl  [file normalize $here/../../04_rtl]
set_param general.maxThreads 1
catch {set_param synth.maxThreads 1}
foreach f {yolo_pkg.sv sdp_ram.sv sync_fifo.sv burst_gen.sv axil_regs.sv weight_loader.sv line_loader.sv
           pe_array.sv epilogue.sv conv_engine.sv writer.sv yolo_accel.sv} { read_verilog -sv $rtl/$f }
read_verilog $rtl/yolo_accel_wrap.v
synth_design -top yolo_accel_wrap -part xczu7ev-ffvc1156-2-e -mode out_of_context -flatten_hierarchy rebuilt
create_clock -period 5.333 [get_ports aclk]
report_utilization -hierarchical -hierarchical_depth 4 -file $here/ooc_utilization_hier.rpt
write_verilog -force -mode funcsim $here/yolo_accel_wrap_funcsim.v
puts "OOC SYNTH DONE"
