// Legacy spellings and subtype paths retain compatibility; implementation lives in the engine.

/datum/om/stage
	parent_type = /datum/work_stage
	abstract_type = /datum/om/stage

/datum/om/frame
	parent_type = /datum/work_frame

/datum/om/check/fact
	parent_type = /datum/requirement_definition/fact
	abstract_type = /datum/om/check/fact

/datum/om/plan
	parent_type = /datum/work_plan

/datum/om/pipeline
	parent_type = /datum/work_pipeline
	abstract_type = /datum/om/pipeline

/datum/om/behaviour/sleeper
	parent_type = /datum/scheduled_behaviour/sleeper
	abstract_type = /datum/om/behaviour/sleeper

/datum/om/behaviour/sleeper/timed
	parent_type = /datum/scheduled_behaviour/sleeper/timed
	abstract_type = /datum/om/behaviour/sleeper/timed

/proc/om_stage_timed(datum/om/stage/T, datum/E, datum/om/frame/F, datum/om/scheduler/sched, stride)
	return pipeline_stage_timed(arglist(args))

/proc/om_stage_throttle(datum/om/frame/S, i, datum/om/stage/T, now)
	return pipeline_stage_throttle(arglist(args))

/proc/om_pipe_state(datum/E, P, create = FALSE)
	return pipeline_pipe_state(arglist(args))

/proc/om_pipe_words(n)
	return pipeline_pipe_words(arglist(args))

/proc/om_pipe_set_all(datum/om/frame/S, asleep, idle_frames = null)
	return pipeline_pipe_set_all(arglist(args))

/proc/om_stage_idle(datum/E, P, stage_type)
	return pipeline_stage_idle(arglist(args))

/proc/om_plan_position(datum/om/frame/S, stage_type)
	return pipeline_plan_position(arglist(args))

/proc/om_pipe_parked(datum/E, P)
	return pipeline_pipe_parked(arglist(args))

/proc/om_stage_add(datum/E, stage_type)
	return pipeline_stage_add(arglist(args))

/proc/om_pipe_replan(datum/E, P, datum/om/frame/S)
	return pipeline_pipe_replan(arglist(args))

/proc/om_stage_run_now(datum/E, stage_type)
	return pipeline_stage_run_now(arglist(args))

/proc/om_run_frame_now(datum/E, P)
	return pipeline_run_frame_now(arglist(args))

/proc/om_pipeline_parked_count(P, datum/om/scheduler/sched)
	return pipeline_pipeline_parked_count(arglist(args))

/proc/om_pipeline_audit(datum/om/scheduler/sched, parked_sample = 400, awake_sample = 100, expected = FALSE)
	return pipeline_pipeline_audit(arglist(args))

/proc/om_sleeper_audit(sample = 64, report = FALSE)
	return pipeline_sleeper_audit(arglist(args))

/proc/om_trace(datum/E)
	return pipeline_trace(arglist(args))

/proc/om_traced_count(datum/E)
	return pipeline_traced_count(arglist(args))

/proc/om_untrace(datum/E)
	return pipeline_untrace(arglist(args))

/datum/proc/om_plan_key()
	return pipeline_plan_key()

/datum/proc/om_sleep_violation()
	return pipeline_sleep_violation()
