# Pre-hook for synth_1 / impl_1 runs (set by build.tcl): keep peak memory low on a 16 GB PC.
# Synthesis otherwise starts up to 4 helper processes of ~2 GB each.
set_param general.maxThreads 1
catch {set_param synth.maxThreads 1}
