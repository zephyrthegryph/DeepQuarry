// MOVE_COST: the per-step cost trace (defines: code/defines/engine/move_cost.dm).

/// TRUE while a client's step is being measured (client/Move() sets it around the move itself).
GLOBAL_VAR_INIT(move_cost_on, FALSE)
/// Tick usage spent in each part of the step being measured (MOVE_COST_* slots).
GLOBAL_LIST_INIT(move_cost_parts, new /list(MOVE_COST_PART_COUNT))
/// Steps measured, steps traced because of the sampling, steps traced because they were slow, and the dearest step so far (ms).
GLOBAL_VAR_INIT(move_cost_steps, 0)
GLOBAL_VAR_INIT(move_cost_sampled, 0)
GLOBAL_VAR_INIT(move_cost_slow, 0)
GLOBAL_VAR_INIT(move_cost_worst_ms, 0)
/// Total ms of every measured step.
GLOBAL_VAR_INIT(move_cost_total_ms, 0)

/// A client's step begins: clears the parts and starts the clock. Returns the tick usage the step started at, for move_cost_end().
/proc/move_cost_begin()
	for(var/part in 1 to MOVE_COST_PART_COUNT)
		GLOB.move_cost_parts[part] = 0
	GLOB.move_cost_on = TRUE
	return TICK_USAGE_REAL

/// The step ends (`started` from move_cost_begin()): it is counted, and traced when sampled or slow. `mover` is the mob, `from`/`to` where it was and is.
/// `marks_before` and `chunks_before` are refresh_marks_raised and interest_chunks_entered at the start, `light_queue_before` the lights waiting.
/proc/move_cost_end(started, mob/mover, turf/from, marks_before, chunks_before, light_queue_before)
	GLOB.move_cost_on = FALSE
	var/total_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	GLOB.move_cost_steps++
	GLOB.move_cost_total_ms += total_ms
	if(total_ms > GLOB.move_cost_worst_ms)
		GLOB.move_cost_worst_ms = total_ms
	var/slow = total_ms >= MOVE_COST_SLOW_MS
	var/sampled = !(GLOB.move_cost_steps % MOVE_COST_SAMPLE_EVERY)
	if(!slow && !sampled)
		return
	if(slow)
		GLOB.move_cost_slow++
	else
		GLOB.move_cost_sampled++
	var/list/parts = GLOB.move_cost_parts
	var/moved_ms = TICK_DELTA_TO_MS(parts[MOVE_COST_MOVED])
	var/inside_ms = TICK_DELTA_TO_MS(parts[MOVE_COST_LIGHTS] + parts[MOVE_COST_PROXIMITY] + parts[MOVE_COST_LIFEFORM] + parts[MOVE_COST_MOB_PUBLISH] + parts[MOVE_COST_EYE])
	log_world("MOVE_COST: [slow ? "SLOW " : ""]step [mover] [from ? "[from.x],[from.y],[from.z]" : "null"] -> [mover?.loc ? "[mover.x],[mover.y],[mover.z]" : "null"] took [round(total_ms, 0.01)] ms: move handlers [round(TICK_DELTA_TO_MS(parts[MOVE_COST_MOVE]), 0.01)] (pre_move, Exit/Enter/Crossed), Moved chain [round(moved_ms, 0.01)] (lights [round(TICK_DELTA_TO_MS(parts[MOVE_COST_LIGHTS]), 0.01)], proximity [round(TICK_DELTA_TO_MS(parts[MOVE_COST_PROXIMITY]), 0.01)], lifeform [round(TICK_DELTA_TO_MS(parts[MOVE_COST_LIFEFORM]), 0.01)], mob publish [round(TICK_DELTA_TO_MS(parts[MOVE_COST_MOB_PUBLISH]), 0.01)], eye/interest [round(TICK_DELTA_TO_MS(parts[MOVE_COST_EYE]), 0.01)], other overrides [round(max(0, moved_ms - inside_ms), 0.01)]), rest of client Move [round(max(0, total_ms - moved_ms - TICK_DELTA_TO_MS(parts[MOVE_COST_MOVE])), 0.01)]; marks raised [GLOB.refresh_marks_raised - marks_before], chunks scanned [GLOB.interest_chunks_entered - chunks_before], lights queued [SSlighting.pending_source_count() - light_queue_before], tick usage now [round(TICK_USAGE_REAL, 1)]%; steps [GLOB.move_cost_steps], mean [round(GLOB.move_cost_total_ms / GLOB.move_cost_steps, 0.01)] ms, worst [round(GLOB.move_cost_worst_ms, 0.01)] ms")
