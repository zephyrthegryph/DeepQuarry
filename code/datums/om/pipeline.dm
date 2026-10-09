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



/proc/om_pipe_state(datum/E, P, create = FALSE)
	return pipeline_pipe_state(arglist(args))


/proc/om_pipe_set_all(datum/om/frame/S, asleep, idle_frames = null)
	return pipeline_pipe_set_all(arglist(args))

/proc/om_stage_idle(datum/E, P, stage_type)
	return pipeline_stage_idle(arglist(args))






/proc/om_run_frame_now(datum/E, P)
	return pipeline_run_frame_now(arglist(args))


/proc/om_pipeline_audit(datum/om/scheduler/sched, parked_sample = 400, awake_sample = 100, expected = FALSE)
	return pipeline_pipeline_audit(arglist(args))


/proc/om_trace(datum/E)
	return pipeline_trace(arglist(args))

/proc/om_traced_count(datum/E)
	return pipeline_traced_count(arglist(args))

/proc/om_untrace(datum/E)
	return pipeline_untrace(arglist(args))


