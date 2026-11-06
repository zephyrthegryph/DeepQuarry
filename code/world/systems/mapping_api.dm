// The mapping system's API (code/controllers/subsystems/mapping.dm declares the system).
//
//   SSmapping.set_multiz_level_count(count) / set_multiz_level_traits(level, traits)   the per-z up/down links
//   SSmapping.set_engine_loader(loader)                                                the engine loader landmark
//   SSmapping.register_map_template(template)                                          a template by name
//   mapping_*()                                                                        reads (code/contracts/accessors/accessors.dm)

/datum/system/mapping/proc/set_multiz_level_count(count)
	multiz_levels.len = count

/datum/system/mapping/proc/set_multiz_level_traits(level, list/traits)
	multiz_levels[level] = traits

/datum/system/mapping/proc/register_map_template(datum/map_template/template)
	map_templates[template.name] = template


/datum/system/mapping/proc/set_engine_loader(obj/effect/landmark/engine_loader/loader)
	rel_set(src, nameof(engine_loader), loader)
