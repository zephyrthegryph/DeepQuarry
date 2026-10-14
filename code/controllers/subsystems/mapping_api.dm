/datum/system/mapping/proc/ensure_multiz_capacity(levels)
	if(length(multiz_levels) < levels)
		multiz_levels.len = levels

/// Preserve the authored list itself; the atmos bridge fills its own per-level lists.
/datum/system/mapping/proc/set_multiz_atmos_traits(z, list/traits)
	multiz_levels[z] = traits

/datum/system/mapping/proc/register_engine_loader(obj/effect/landmark/engine_loader/loader)
	engine_loader = loader

/datum/system/mapping/proc/register_uploaded_template(datum/map_template/template)
	map_templates[template.name] = template
