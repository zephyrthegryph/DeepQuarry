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




















