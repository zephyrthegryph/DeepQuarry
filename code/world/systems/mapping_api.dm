// The mapping system's API (code/controllers/subsystems/mapping.dm declares the system).
//
//   SSmapping.set_multiz_level_count(count) / set_multiz_level_traits(level, traits)   the per-z up/down links
//   SSmapping.link_level_up(z, linked)                                                 join (or part) level z and the level above it
//   SSmapping.set_level_links_up(levels)                                               replace the whole set of joined levels (tests restore it)
//   SSmapping.set_engine_loader(loader)                                                the engine loader landmark
//   SSmapping.register_map_template(template)                                          a template by name
//   mapping_*()                                                                        reads (code/contracts/accessors/accessors.dm)

/datum/system/mapping/proc/set_multiz_level_count(count)
	multiz_levels.len = count

/datum/system/mapping/proc/set_multiz_level_traits(level, list/traits)
	multiz_levels[level] = traits

/// Joins level z to the level above it (linked = TRUE) or parts them. Logged: a stray link joins unrelated levels vertically.
/datum/system/mapping/proc/link_level_up(z, linked = TRUE)
	if(!isnum(z) || z < 1)
		stack_trace("link_level_up: bad level [z]")
		return
	if(linked)
		if(!(z in z_links_up))
			log_mapping("multiz: level [z] joined to the level above")
		include_z_links_up(z)
	else
		if(z in z_links_up)
			log_mapping("multiz: level [z] parted from the level above")
		remove_z_links_up(z)

/// Replaces the set of levels joined to the level above them.
/datum/system/mapping/proc/set_level_links_up(list/levels)
	set_z_links_up(levels ? levels.Copy() : null)

/datum/system/mapping/proc/register_map_template(datum/map_template/template)
	map_templates[template.name] = template


/datum/system/mapping/proc/set_engine_loader(obj/effect/landmark/engine_loader/loader)
	rel_set(src, nameof(engine_loader), loader)
