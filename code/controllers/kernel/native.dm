/// Phase N (kernel.dm): the one native frame per kernel tick.
///
/// The frame is `/datum/system/native` (code/datums/native/system.dm): vg_frame paces the Rust world and its
/// scheduler (timers, keys, rate crossings, watches, gas and heat drains) and the system delivers the records
/// it returns. This proc is the kernel's single call into it; nothing else steps the frame on a live server
/// (SSvg is SS_NO_FIRE). Tests that step Rust by hand use native_system().drain().

/// One native frame. `elapsed` is deciseconds since the last frame (the kernel caps it at
/// KERNEL_NATIVE_MAX_CATCHUP ticks); `budget` is the per-tick wake budget the frame may deliver. Runs at most
/// once per wheel tick, and never on a scheduler running injected time.
/proc/native_frame(elapsed, budget)
	var/datum/om/scheduler/sched = kernel().sched
	if(!sched || !sched.world_frame_begin(world_tick_of(world.time)))
		return
	var/start = TICK_USAGE_REAL
	native_system().kernel_frame(elapsed, budget)
	sched.world_last_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	// The tick meter's om_native system is the Rust world step: charge the frame to it.
	km_meter().charge(KM_SYS_OM_NATIVE, sched.world_last_ms)
