// Compatibility bases retain legacy subtype paths; implementations live in the engine.

/datum/om/bundle
	parent_type = /datum/definition_bundle
	abstract_type = /datum/om/bundle

/datum/om/decl
	parent_type = /datum/definition_decl
	abstract_type = /datum/om/decl

/datum/om/type_table
	parent_type = /datum/scheduler_type_table

/proc/om_read(datum/holder, spec)
	return definition_read(arglist(args))
