// The fill queue of the closets the map load made: their spawn lists are made one item at a time inside a budget (a job()), not one whole list per timer call.
//
// A closet's after_init() made its spawn list in one call: an emergency closet is eleven items at about 4 ms each, so a round's first ticks held calls of 140-230 ms
// (PERF_PROFILE 2026-11-13: closet_after_init, 126 emergency closets, 5.2 s in all, longest call 167 ms; the whole kind 9.4 s). A closet loaded with the map while the kernel
// runs (closet_after_init(), A.mapload) joins this queue instead: its spawn list is flattened into one entry per item (starts_with itself, so a closet that is looked
// at meanwhile shows what is still to come), and the job makes one item per step, as many steps as the job's share of the tick lasts. When a closet's list is made it takes
// in the loose items on its turf (closet_collect_loose()), as it did right after its list. Before the kernel runs (world init, where everything is one batch anyway) and in play
// (a closet made by hand, a test) nothing changes: the list is made at once.
//
// Trace: a summary line (CLOSET_FILL) when the queue drains, and a line for any step that took CLOSET_FILL_SLOW_MS or more, with the item.

/// A step (one item made) at least this long is logged.
#define CLOSET_FILL_SLOW_MS 5
/// The share of a tick the fill job may use in one run, in percent.
#define CLOSET_FILL_BUDGET 10

GLOBAL_DATUM_INIT(closet_fill, /datum/closet_fill, new)

CAPABILITIES_PART(/datum/controller/global_vars, closet_fill)
	owns_one(nameof(closet_fill), /datum/closet_fill)

LIFECYCLE_KEEP_UNLESS_FORCED(/datum/closet_fill)
/datum/closet_fill
	/// The closets whose spawn lists are not all made, oldest first.
	var/list/waiting = list()
	/// TRUE while the job runs.
	var/running = FALSE
	/// Counters of the current run of the queue and of the round: closets finished, items made, steps run, ms spent, the longest step.
	var/closets_done = 0
	var/items_made = 0
	var/steps = 0
	var/total_ms = 0
	var/max_step_ms = 0
	var/slow_steps = 0
	var/queued = 0

CAPABILITIES(/datum/closet_fill)
	ref_many(nameof(waiting)) // a closet deleted while it waited leaves the queue by itself

/// `C`, loaded with the map, joins the fill queue. FALSE (it is filled at once) before the kernel runs.
/proc/closet_fill_enqueue(obj/structure/closet/C)
	var/datum/closet_fill/Q = GLOB.closet_fill
	if(!Kernel?.processing)
		return FALSE
	var/list/flat = list()
	for(var/path in C.starts_with)
		var/list/spec = dq_resolve_spawn_value(C.starts_with[path])
		for(var/i in 1 to max(1, spec["count"]))
			flat += path
	C.set_starts_with(flat)
	Q.queued++
	rel_add(Q, nameof(Q.waiting), C)
	if(!Q.running)
		Q.running = TRUE
		job(Q, TYPE_PROC_REF(/datum/closet_fill, fill_step), budget = CLOSET_FILL_BUDGET, then = TYPE_PROC_REF(/datum/closet_fill, fill_done))
	return TRUE

/// One step: one item of the oldest waiting closet, or that closet's loose-item pass when its list is made.
/datum/closet_fill/proc/fill_step(datum/act/timer/A)
	var/started = TICK_USAGE_REAL
	var/what = "nothing"
	while(length(waiting))
		var/obj/structure/closet/C = waiting[1]
		if(QDELETED(C))
			rel_remove(src, nameof(waiting), C)
			continue
		var/list/left = C.starts_with
		if(length(left))
			var/path = left[1]
			C.set_starts_with(left.Copy(2))
			what = "[path] in [C.type]"
			new path(C)
			items_made++
		else
			what = "loose items of [C.type]"
			C.set_starts_with(null)
			rel_remove(src, nameof(waiting), C)
			C.closet_collect_loose(TRUE)
			closets_done++
		break
	var/step_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	steps++
	total_ms += step_ms
	max_step_ms = max(max_step_ms, step_ms)
	if(step_ms >= CLOSET_FILL_SLOW_MS)
		slow_steps++
		log_world("CLOSET_FILL: one step took [round(step_ms, 0.01)] ms ([what]); [slow_steps] such step(s), longest [round(max_step_ms, 0.01)] ms, [length(waiting)] closet(s) still waiting")
	return length(waiting) ? JOB_MORE : JOB_DONE

/// The queue drained.
/datum/closet_fill/proc/fill_done(datum/act/timer/A)
	running = FALSE
	log_world("CLOSET_FILL: [closets_done] of [queued] queued closet(s) filled, [items_made] item(s) in [steps] step(s), [round(total_ms, 0.1)] ms in all, longest step [round(max_step_ms, 0.01)] ms")
