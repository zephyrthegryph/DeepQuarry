/// Phase N (kernel.dm): the one native frame per tick. STUB for the Rust owner (W4): this file is replaced by
/// `vg_frame(elapsed, budget)` and the `/datum/system/native` delivery.
///
/// Until then the frame is what the kernel already owns: the OM world wheel (timers, keys, rate crossings, native
/// watches; vg_world_step). The other native drivers still run where they always did: SSvg fires vg_world_tick,
/// vg_entity_tick_all and vg_drain_events every 0.5 s, and SSair fires the gas phases and vg_heat_tick. Moving those
/// three calls into this proc (and deleting the two subsystems' drivers) is the native cutover, not a kernel change.

/// One native frame. `elapsed` is deciseconds since the last frame, capped at KERNEL_NATIVE_MAX_CATCHUP ticks;
/// `budget` is the wake budget the frame may deliver.
/proc/native_frame(elapsed, budget)
	var/datum/om/scheduler/sched = kernel().sched
	if(!sched)
		return
	sched.world_budget = budget
	sched.world_step()
