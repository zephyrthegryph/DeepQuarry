// Boot phase timers: wall-clock microseconds of the steps one atom's init is made of, summed over the whole map load and printed to the
// init log ("Atoms boot phase: ..."). Debug tracing, off unless the world starts with `-params boot_phase_timers=1`
// (DQ_WORLD_PARAMS=boot_phase_timers=1 for a build target); off costs one global read per phase. A phase is inclusive: it contains
// the phases and the nested atom inits it triggers, so the rows overlap and do not add up to the total.
#define BOOT_PHASE_CLOCK "boot_phase_clock"
#define BOOT_PHASE_BEGIN(v) var/v = GLOB.boot_phase_on ? rustg_time_microseconds(BOOT_PHASE_CLOCK) : null
#define BOOT_PHASE_END(v, phase) if(!isnull(v)) boot_phase_add(phase, rustg_time_microseconds(BOOT_PHASE_CLOCK) - v)
