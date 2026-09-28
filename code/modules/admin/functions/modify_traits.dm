/// Allow admin to add or remove traits of datum
/datum/admins/proc/modify_traits(datum/D)
	if(!D)
		return

	om_prompt_sequence(src, usr, list(
		list("key" = "mode", "kind" = "list", "message" = "Remove/Add?", "title" = "Trait Remove/Add", "choices" = list("Add","Remove")),
		PROC_REF(ask_trait),
		PROC_REF(ask_trait_source_kind),
		PROC_REF(ask_trait_source),
	), PROC_REF(traits_answered), list("requires" = PROMPT_ADMIN(R_VAREDIT), "data" = list("datum" = D)))

/// The traits of D that can be added ("Add") or removed ("Remove"), by name.
/datum/admins/proc/modifiable_traits(datum/D, add_or_remove)
	var/list/availible_traits = list()

	switch(add_or_remove)
		if("Add")
			for(var/key in GLOB.traits_by_type)
				if(istype(D,key))
					var/list/traits_for_type = GLOB.traits_by_type[key]
					for(var/trait_name in traits_for_type)
						availible_traits[trait_name] = traits_for_type[trait_name]
		if("Remove")
			if(!GLOB.trait_name_map)
				GLOB.trait_name_map = generate_trait_name_map()
			for(var/trait in D._status_traits)
				var/name = GLOB.trait_name_map[trait] || trait
				availible_traits[name] = trait

	return availible_traits

/datum/admins/proc/ask_trait(mob/admin, datum/om/prompt/ask)
	return list("key" = "trait", "kind" = "list", "message" = "Select trait to modify", "title" = "Trait", "choices" = modifiable_traits(ask.get("datum"), ask.get("mode")))

/datum/admins/proc/ask_trait_source_kind(mob/admin, datum/om/prompt/ask)
	if(ask.get("mode") == "Remove")
		return list("key" = "specific", "kind" = "list", "message" = "All or specific source ?", "title" = "Trait Remove/Add", "choices" = list("All","Specific"))

/datum/admins/proc/ask_trait_source(mob/admin, datum/om/prompt/ask)
	if(ask.get("specific") == "Specific")
		var/datum/D = ask.get("datum")
		var/list/traits = modifiable_traits(D, "Remove")
		return list("key" = "source", "kind" = "list", "message" = "Source to be removed", "title" = "Trait Remove/Add", "choices" = GET_TRAIT_SOURCES(D, traits[ask.get("trait")]))

/datum/admins/proc/traits_answered(mob/admin, datum/om/prompt/ask)
	var/datum/D = ask.get("datum")
	var/list/availible_traits = modifiable_traits(D, ask.get("mode"))
	var/chosen_trait = availible_traits[ask.get("trait")]
	if(!chosen_trait)
		return
	switch(ask.get("mode"))
		if("Add") //Not doing source choosing here intentionally to make this bit faster to use, you can always vv it.
			ADD_TRAIT(D,chosen_trait,"adminabuse")
		if("Remove")
			REMOVE_TRAIT(D,chosen_trait,ask.get("specific") == "All" ? null : ask.get("source"))
