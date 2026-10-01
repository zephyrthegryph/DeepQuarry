/// The speech controller: a verb lane just for handling say's. A system now, not a verb_manager subtype: its lane runs as a
/// phase K work item right after the hosted input services (high priority, second only to SSinput).
SYSTEM_DEF(speech_controller)
	name = "Speech Controller"
	init_stage = INITSTAGE_FIRST
	wait = 1

	/// The queue the work item runs every tick.
	var/datum/verb_lane/lane = new /datum/verb_lane/speech

/datum/verb_lane/speech
	name = "Speech Controller"

/datum/system/speech_controller/reactions()
	. = ..()
	. += every(WORK_EVERY_TICK, PROC_REF(run_queue), phase = KERNEL_PHASE_K, lane = LANE_URGENT)

/// One tick's speech verbs, run to completion like SSverb_manager's queue.
/datum/system/speech_controller/proc/run_queue(dt)
	lane.run_verb_queue()

/datum/system/speech_controller/stat_entry(msg)
	return "[msg][lane.stat_text()]"
