// Legacy spellings and subtype paths retain compatibility; implementation lives in the engine.

/datum/om/registry
	parent_type = /datum/definition_registry

/proc/om_registry()
	RETURN_TYPE(/datum/om/registry)
	return definition_registry(arglist(args))

/proc/om_is_abstract(datum/om/D)
	return definition_is_abstract(arglist(args))

/proc/om_effect_expr_refs(expr, list/out)
	return definition_effect_expr_refs(arglist(args))

/proc/om_merge_assoc(list/a, list/b)
	return definition_merge_assoc(arglist(args))

/proc/om_stage_is_category(path, datum/om/registry/reg)
	return definition_stage_is_category(arglist(args))

/proc/om_type_depth(path)
	return definition_type_depth(arglist(args))

/proc/om_run_if_masks(spec, datum/om/pipeline/P, list/masks, negated)
	return definition_run_if_masks(arglist(args))

/proc/om_run_if_fact_names(spec, list/out)
	return definition_run_if_fact_names(arglist(args))

/proc/om_spec_list(spec)
	return definition_spec_list(arglist(args))

/proc/om_compile_related(list/table, datum/om/registry/reg, owner_name)
	return definition_compile_related(arglist(args))

/proc/om_topo_order(list/nodes, datum/om/registry/reg)
	return definition_topo_order(arglist(args))

/proc/om_kahn(list/succ, n)
	return definition_kahn(arglist(args))

/proc/om_reaches(list/succ, start, goal)
	return definition_reaches(arglist(args))

/datum/definition_registry/compatibility_type(path)
	var/static/list/aliases
	if(!aliases)
		aliases = list(
			/datum/om/rec = /datum/scheduler_record,
			/datum/om/scheduler = /datum/time_scheduler,
			/datum/om/ring = /datum/cadence_ring,
			/datum/om/global_owner = /datum/timer_owner,
			/datum/om/behaviour/inline = /datum/scheduled_behaviour/inline,
			/datum/om/event/before = /datum/definition_event/before,
			/datum/om/behaviour = /datum/scheduled_behaviour,
			/datum/om/event = /datum/definition_event,
			/datum/om/relation = /datum/relation_definition,
			/datum/om/edge = /datum/relation_edge,
			/datum/om/check = /datum/requirement_definition,
			/datum/om/derived = /datum/derived_definition,
			/datum/om/effect = /datum/effect_definition,
			/datum/om/clock_def = /datum/clock_definition,
			/datum/om/service = /datum/service_definition,
			/datum/om/bundle = /datum/definition_bundle,
			/datum/om/decl = /datum/definition_decl,
			/datum/om/type_table = /datum/scheduler_type_table,
			/datum/om = /datum/core_definition,
			/datum/om/registry = /datum/definition_registry,
			/datum/om/pipeline = /datum/work_pipeline,
			/datum/om/stage = /datum/work_stage,
			/datum/om/frame = /datum/work_frame,
			/datum/om/plan = /datum/work_plan,
			/datum/om/behaviour/internal/timers = /datum/scheduled_behaviour/internal/timers,
			/datum/om/behaviour/internal/edge_refresh = /datum/scheduled_behaviour/internal/edge_refresh,
			/datum/om/behaviour/sleeper/timed = /datum/scheduled_behaviour/sleeper/timed,
			/datum/om/check/combinator = /datum/requirement_definition/combinator,
			/datum/om/check/fact = /datum/requirement_definition/fact
		)
	return aliases[path] || path

/datum/definition_registry/make_inline_behaviour()
	return new /datum/om/behaviour/inline

/datum/definition_registry/standard_effects()
	return definition_standard_effects()

/datum/definition_registry/presentation_behaviour()
	return behaviour_by_type[/datum/om/behaviour/internal/ui_push]
