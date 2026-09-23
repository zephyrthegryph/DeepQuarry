/**
 * Admin surfacing for the generic grant system (doc/rewrite/grants.md). Every
 * grant is already visible in BYOND's native View Variables on `grants` (right
 * click a mob -> View Variables); this adds a one-click "Dump Grants" VV dropdown
 * option (code/modules/mob/mob.dm's vv_get_dropdown()/vv_do_topic(), VV_HK_DUMP_GRANTS
 * in code/__defines/vv.dm) that prints the same thing formatted, without digging
 * through the raw nested list.
 */

/// Human-readable dump of everything currently granted to this mob, across every
/// kind, grouped by kind and id with the sources listed. Used by the "Dump Grants"
/// VV option and callable directly from View Variables.
/mob/proc/dump_grants()
	if(!length(grants))
		return "[src] ([type]) has no grants."
	var/list/lines = list("Grants on [src] ([type]):")
	for(var/kind in grants)
		var/datum/grant_kind/K = grant_kind_by_id(kind)
		lines += "  kind [kind][K ? " ([K.type])" : " (UNREGISTERED)"]:"
		var/list/by_id = grants[kind]
		for(var/id in by_id)
			var/list/sources = by_id[id]
			var/list/source_names = list()
			for(var/datum/source as anything in sources)
				source_names += "[source] ([REF(source)])"
			lines += "    [id]: [source_names.Join(", ")]"
	return lines.Join("\n")
