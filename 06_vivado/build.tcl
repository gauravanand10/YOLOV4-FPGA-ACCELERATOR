# ZCU104 build for the YOLOv4-tiny INT8 accelerator.
#   vivado -mode batch -source build.tcl [-tclargs bdonly]      (see build.bat)
# Creates project, block design (Zynq US+ PS with ZCU104 preset, everything on pl_clk0,
# M_AXI_HPM0_FPD -> accel AXI-Lite, accel AXI4 master -> S_AXI_HP0_FPD, irq -> pl_ps_irq0),
# runs synthesis + implementation + bitstream, exports .xsa and reports.
# "bdonly" stops after validate_bd_design (quick check, ~1.5 GB RAM).
#
# Clock: the PS PLLs cannot make exactly 200 MHz with the ZCU104 preset (IOPLL 1500 MHz / 8 = 187.5 MHz).
# No MMCM/clk_wiz is used (it crashed Vivado on this 16 GB machine); pl_clk0 runs at whatever the PS
# really produces and that FREQ_HZ is propagated to the module reference.
set here   [file normalize [file dirname [info script]]]
set root   [file normalize $here/..]
set proj   yolo_zcu104
set pdir   $here/proj
set rptdir $here/reports
set outdir $here/out
set jobs   2
set bdonly [expr {[lsearch $argv bdonly] >= 0}]
set runs   [expr {[lsearch $argv runs] >= 0}]
file mkdir $rptdir $outdir

# low-memory settings (16 GB host)
set_param general.maxThreads 4

if {$runs} {
  # stage 2 (fresh, small Vivado process): open the prepared project and run synth/impl/bitstream
  open_project $pdir/$proj.xpr
  # reuse a finished, up-to-date synthesis (build.bat runs); otherwise start clean
  set s1 [get_runs synth_1]
  if {[get_property PROGRESS $s1] eq "100%" && [get_property NEEDS_REFRESH $s1] == 0 && [string match "*Complete*" [get_property STATUS $s1]]} {
    puts "INFO: reusing completed synth_1"
  } else { reset_run synth_1 }
  set i1 [get_runs impl_1]
  set have_bit [llength [glob -nocomplain $pdir/$proj.runs/impl_1/*.bit]]
  if {$have_bit && [get_property PROGRESS $i1] eq "100%" && [get_property NEEDS_REFRESH $i1] == 0 && [string match "*write_bitstream Complete*" [get_property STATUS $i1]]} {
    puts "INFO: reusing completed impl_1 (bitstream present)"
  } else { reset_run impl_1 }
  set_property STEPS.OPT_DESIGN.TCL.PRE [file normalize $here/lowmem_impl_pre.tcl] [get_runs impl_1]
  set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
} else {
set_param board.repoPaths [list [file normalize $::env(XILINX_VIVADO)/data/xhub/boards/XilinxBoardStore/boards]]
create_project $proj $pdir -part xczu7ev-ffvc1156-2-e -force
set bp [lindex [get_board_parts -quiet -latest_file_version {*zcu104*}] 0]
if {$bp ne ""} { set_property board_part $bp [current_project]; puts "INFO: board part $bp" } \
else { puts "WARNING: ZCU104 board part not found, using bare part" }

set rtl {yolo_pkg.sv sdp_ram.sv sync_fifo.sv burst_gen.sv axil_regs.sv weight_loader.sv
         line_loader.sv pe_array.sv epilogue.sv conv_engine.sv writer.sv yolo_accel.sv yolo_accel_wrap.v}
foreach f $rtl { add_files -norecurse $root/04_rtl/$f }
foreach f [get_files *.sv] { set_property file_type SystemVerilog $f }
update_compile_order -fileset sources_1

# ---------------- block design ----------------
create_bd_design system
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e zynq_ps]
if {$bp ne ""} {
  apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} $ps
}
set_property -dict [list \
  CONFIG.PSU__USE__M_AXI_GP0 {1} CONFIG.PSU__MAXIGP0__DATA_WIDTH {32} \
  CONFIG.PSU__USE__M_AXI_GP1 {0} CONFIG.PSU__USE__M_AXI_GP2 {0} \
  CONFIG.PSU__USE__S_AXI_GP2 {1} CONFIG.PSU__SAXIGP2__DATA_WIDTH {128} \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {200} \
  CONFIG.PSU__USE__IRQ0 {1} \
  CONFIG.PSU__FPGA_PL0_ENABLE {1} \
] $ps

# read back what the PS really generates; fall back to 187.5 MHz (IOPLL/8) when 200 is not exact
set act [get_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ $ps]
puts "PLCLK: requested 200 MHz, PS actual $act MHz"
if {abs($act - 200.0) > 1e-4} {
  set_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {187.5} $ps
  set act [get_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ $ps]
  puts "PLCLK: 200 MHz not exact -> requested 187.5 MHz, PS actual $act MHz"
}

set acc [create_bd_cell -type module -reference yolo_accel_wrap yolo_accel]
set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_pl0]
set sc_ctl [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect sc_ctrl]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $sc_ctl
set sc_mem [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect sc_mem]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $sc_mem

set clk [get_bd_pins zynq_ps/pl_clk0]
connect_bd_net $clk [get_bd_pins zynq_ps/maxihpm0_fpd_aclk] [get_bd_pins zynq_ps/saxihp0_fpd_aclk] \
  [get_bd_pins yolo_accel/aclk] [get_bd_pins rst_pl0/slowest_sync_clk] \
  [get_bd_pins sc_ctrl/aclk] [get_bd_pins sc_mem/aclk]
connect_bd_net [get_bd_pins zynq_ps/pl_resetn0] [get_bd_pins rst_pl0/ext_reset_in]
connect_bd_net [get_bd_pins rst_pl0/peripheral_aresetn] [get_bd_pins yolo_accel/aresetn]
connect_bd_net [get_bd_pins rst_pl0/interconnect_aresetn] [get_bd_pins sc_ctrl/aresetn] [get_bd_pins sc_mem/aresetn]

connect_bd_intf_net [get_bd_intf_pins zynq_ps/M_AXI_HPM0_FPD] [get_bd_intf_pins sc_ctrl/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_ctrl/M00_AXI] [get_bd_intf_pins yolo_accel/s_axi]
connect_bd_intf_net [get_bd_intf_pins yolo_accel/m_axi] [get_bd_intf_pins sc_mem/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_mem/M00_AXI] [get_bd_intf_pins zynq_ps/S_AXI_HP0_FPD]
connect_bd_net [get_bd_pins yolo_accel/irq] [get_bd_pins zynq_ps/pl_ps_irq0]

# make the module reference carry exactly the pl_clk0 frequency (no fixed FREQ_HZ in the HDL any more)
set fhz [get_property CONFIG.FREQ_HZ $clk]
puts "PLCLK: pl_clk0 FREQ_HZ = $fhz"
set_property CONFIG.FREQ_HZ $fhz [get_bd_pins yolo_accel/aclk]
foreach i {s_axi m_axi} { catch {set_property CONFIG.FREQ_HZ $fhz [get_bd_intf_pins yolo_accel/$i]} }

assign_bd_address
# AXI-Lite register window: 4 KiB at 0xA000_0000
set seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces zynq_ps/Data] -filter {NAME =~ *yolo_accel*}]
if {$seg ne ""} { set_property offset 0xA0000000 $seg; set_property range 4K $seg }
# accelerator master: PS DDR low (0x0000_0000 - 0x7FFF_FFFF) only
foreach s [get_bd_addr_segs -of_objects [get_bd_addr_spaces yolo_accel/m_axi]] {
  if {![string match *DDR_LOW* [get_property NAME $s]]} { catch {exclude_bd_addr_seg $s} }
}
validate_bd_design
save_bd_design
puts "BD VALIDATED: pl_clk0 $act MHz"
puts "ADDRESS MAP:"
foreach s [get_bd_addr_segs -of_objects [get_bd_addr_spaces -of_objects [get_bd_cells *]]] {
  catch {puts "  [get_property NAME $s] offset=[get_property OFFSET $s] range=[get_property RANGE $s]"}
}
set f [open $rptdir/clock.txt w]; puts $f "PL0_ACT_FREQMHZ $act"; puts $f "FREQ_HZ $fhz"; close $f
if {$bdonly} { puts "BDONLY DONE"; return }

set bdf [get_files system.bd]
# global synthesis of the BD: one synth run instead of one OOC run per IP (much lower peak memory)
set_property synth_checkpoint_mode None $bdf
generate_target all $bdf
make_wrapper -files $bdf -top
add_files -norecurse [file normalize $pdir/$proj.gen/sources_1/bd/system/hdl/system_wrapper.v]
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1
close_bd_design [current_bd_design]
set_property STEPS.SYNTH_DESIGN.TCL.PRE [file normalize $here/lowmem_pre.tcl] [get_runs synth_1]
set_property STEPS.OPT_DESIGN.TCL.PRE [file normalize $here/lowmem_impl_pre.tcl] [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
close_project
puts "PREP DONE"
return
}

# ---------------- synth / impl ----------------
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
  launch_runs synth_1 -jobs $jobs
  wait_on_run synth_1
}
if {[get_property PROGRESS [get_runs synth_1]] ne "100%" || [string match *ERROR* [get_property STATUS [get_runs synth_1]]]} {
  error "synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
# the parent does not open the synthesized design (keeps it ~1 GB); use the report the synth run wrote
file copy -force $pdir/$proj.runs/synth_1/system_wrapper_utilization_synth.rpt $rptdir/utilization_synth.rpt

if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
  launch_runs impl_1 -to_step write_bitstream -jobs $jobs
  wait_on_run impl_1
}
if {[get_property PROGRESS [get_runs impl_1]] ne "100%" || [string match *ERROR* [get_property STATUS [get_runs impl_1]]]} {
  error "implementation failed: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1
report_utilization -file $rptdir/utilization_impl.rpt
report_utilization -hierarchical -hierarchical_depth 4 -file $rptdir/utilization_hier.rpt
report_timing_summary -max_paths 20 -report_unconstrained -file $rptdir/timing_impl.rpt
report_power -file $rptdir/power.rpt
report_drc -file $rptdir/drc.rpt

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "TIMING: WNS=$wns ns WHS=$whs ns"
# pl_clk0 frequency as recorded by the prep stage
set act ?
catch {set cf [open $rptdir/clock.txt]; regexp {PL0_ACT_FREQMHZ\s+(\S+)} [read $cf] -> act; close $cf}
set f [open $rptdir/summary.txt w]
puts $f "PL0_MHz $act"
puts $f "WNS_ns $wns"
puts $f "WHS_ns $whs"
close $f
if {$wns < 0 || $whs < 0} { error "TIMING FAILED: WNS=$wns WHS=$whs (see $rptdir/timing_impl.rpt)" }

write_hw_platform -fixed -include_bit -force -file $outdir/yolo_zcu104.xsa
set bit [glob -nocomplain $pdir/$proj.runs/impl_1/*.bit]
if {$bit eq ""} { error "no bitstream produced" }
file copy -force [lindex $bit 0] $outdir/yolo_zcu104.bit
puts "BUILD DONE"
