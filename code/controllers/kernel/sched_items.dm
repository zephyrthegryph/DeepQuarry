/// The OM scheduler's pass as kernel work items (doc/rewrite/final_api.html, section 19 "E6": the scheduler and pipelines are
/// re-hosted as kernel items until phases 4 and 5 delete them).
///
/// The kernel tick no longer calls the scheduler's passes itself. Each piece of a pass is a work item of SSbehaviours in the
/// phase it ran in, first in that phase's list (`first`), so the phase walk runs it ahead of every other item (the missed-wake
/// audit, SSbehaviours' own item, is in subsystems/behaviours.dm):
///
///   D   sched_deadlines   the deadline wheel, within OM_DEADLINE_SHARE of the pass
///   P   sched_borrow      the borrow pass for rings near their staleness bound (lane 1, before sched_lane)
///   P   sched_lane        one lane's share of the pass: its queued wakes, derived values and rings (one item per lane)
///   R   sched_leftovers   what is left of the tick
///
/// The pass's own bookends stay in the kernel tick: pass_begin() opens it before phase N (the native frame reads its budget)
/// and pass_end() closes it after the last leftover.
///
/// Pieces belong to the live graph and to a test's (`shared_graph`): the test clock lends the kernel its own scheduler for a
/// slot, and a piece runs whichever scheduler the kernel holds (`K.sched`).

#define SCHED_PIECE_DEADLINES "deadlines"
#define SCHED_PIECE_BORROW "borrow"
#define SCHED_PIECE_LANE "lane"
#define SCHED_PIECE_LEFTOVERS "leftovers"

/datum/work_item/sched_piece
	first = TRUE
	shared_graph = TRUE
	/// SCHED_PIECE_*.
	var/piece

/datum/work_item/sched_piece/New(piece, phase = KERNEL_PHASE_P, lane = LANE_URGENT, list/after = null)
	..("sched_[piece]", WORK_EVERY_TICK, null, null, phase, after, 0, lane)
	src.piece = piece
	name = lane_piece() ? "sched_lane_[lane]" : "sched_[piece]"

/datum/work_item/sched_piece/proc/lane_piece()
	return piece == SCHED_PIECE_LANE

/// The key of a lane piece carries the lane: "[owner]:sched_lane_<n>".
/datum/work_item/sched_piece/item_key(owner_type)
	return lane_piece() ? "[owner_type]:sched_lane_[lane]" : "[owner_type]:sched_[piece]"

/datum/work_item/sched_piece/owner()
	return SSbehaviours

/// The lane-level latency gate (kernel/kernel.dm run_lane_phase()) already decides whether a lane runs while shedding: a piece
/// is never shed on its own.
/datum/work_item/sched_piece/latency_class()
	return LATENCY_L2

/// A piece is due on every pass of its phase, on the live clock and on a test's injected one (its due date never moves).
// ALLOW(sys_world_time_write): the kernel clock: the default is the pass's own timestamp, handed through; nothing stores it
/datum/work_item/sched_piece/sweep(datum/controller/kernel/K, datum/owner, limit_abs, now = world.time)
	var/datum/time_scheduler/S = K.sched
	next_run = 0
	if(!S)
		return TRUE
	var/started = TICK_USAGE
	switch(piece)
		if(SCHED_PIECE_DEADLINES)
			S.pass_deadlines(limit_abs)
		if(SCHED_PIECE_BORROW)
			S.pass_borrow(limit_abs)
		if(SCHED_PIECE_LANE)
			S.pass_lane(lane, limit_abs)
		if(SCHED_PIECE_LEFTOVERS)
			S.pass_leftovers(limit_abs)
	K.sched_ms_tick += TICK_USAGE_TO_MS(started)
	return TRUE

/// Registers the scheduler's pieces with kernel `K` (the first kernel() call after world/New opened registration).
/proc/kernel_register_sched_pieces(datum/controller/kernel/K)
	var/owner = /datum/system/behaviours
	K.register_work(owner, new /datum/work_item/sched_piece(SCHED_PIECE_DEADLINES, KERNEL_PHASE_D))
	K.register_work(owner, new /datum/work_item/sched_piece(SCHED_PIECE_BORROW, KERNEL_PHASE_P, LANE_URGENT))
	for(var/lane in 1 to OM_LANE_COUNT)
		var/list/after = (lane == LANE_URGENT) ? list("[owner]:sched_borrow") : null
		K.register_work(owner, new /datum/work_item/sched_piece(SCHED_PIECE_LANE, KERNEL_PHASE_P, lane, after))
	K.register_work(owner, new /datum/work_item/sched_piece(SCHED_PIECE_LEFTOVERS, KERNEL_PHASE_R))
