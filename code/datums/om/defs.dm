// Compatibility bases retain legacy subtype paths; implementations live in the engine.

/datum/om/behaviour/inline
	parent_type = /datum/scheduled_behaviour/inline
	abstract_type = /datum/om/behaviour/inline

/datum/om/event/before
	parent_type = /datum/definition_event/before
	abstract_type = /datum/om/event/before

/datum/om/behaviour
	parent_type = /datum/scheduled_behaviour
	abstract_type = /datum/om/behaviour

/datum/om/event
	parent_type = /datum/definition_event
	abstract_type = /datum/om/event

/datum/om/relation
	parent_type = /datum/relation_definition
	abstract_type = /datum/om/relation

/datum/om/edge
	parent_type = /datum/relation_edge

/datum/om/check
	parent_type = /datum/requirement_definition
	abstract_type = /datum/om/check

/datum/om/derived
	parent_type = /datum/derived_definition
	abstract_type = /datum/om/derived

/datum/om/clock_def
	parent_type = /datum/clock_definition
	abstract_type = /datum/om/clock_def

/datum/om/service
	parent_type = /datum/service_definition
	abstract_type = /datum/om/service

/datum/om
	parent_type = /datum/core_definition
	abstract_type = /datum/om
