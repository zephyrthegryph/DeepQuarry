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
