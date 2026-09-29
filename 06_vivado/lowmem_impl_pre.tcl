# Pre-hook for impl_1 opt_design (set by build.tcl): params persist for place/route in the same process.
# Fewer threads = lower peak memory on the 16 GB build PC (route_design otherwise uses 8).
set_param general.maxThreads 2
