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
			for(var/trait in trait_list(D))
				var/name = GLOB.trait_name_map[trait] || trait
				availible_traits[name] = trait

	return availible_traits

/// The names of the sources granting `trait`, for the pick list.
/datum/admins/proc/trait_source_names(datum/D, trait)
	. = list()
	for(var/datum/source as anything in trait_sources(D, trait))
		. |= "[source]"

/// Applies the answers: `source` is null to remove the trait from every source.
/datum/admins/proc/traits_answered(datum/D, mode, trait_name, source)
	var/list/availible_traits = modifiable_traits(D, mode)
	var/chosen_trait = availible_traits[trait_name]
	if(!chosen_trait)
		return
	switch(mode)
		if("Add") //Not doing source choosing here intentionally to make this bit faster to use, you can always vv it.
			add_trait(D,chosen_trait,"adminabuse")
		if("Remove")
			remove_trait(D,chosen_trait,source)
