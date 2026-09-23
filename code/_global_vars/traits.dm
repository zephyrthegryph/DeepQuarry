/*
 * FUN ZONE OF ADMIN LISTINGS
 * Try to keep this in sync with __DEFINES/traits.dm
 * Not to be confused with character creator traits
*/
GLOBAL_LIST_INIT(traits_by_type, list(
	/mob = list(
		"TRAIT_THINKING_IN_CHARACTER" = TRAIT_THINKING_IN_CHARACTER,
		/*
		"TRAIT_BLIND" = TRAIT_BLIND,
	*/
		"TRAIT_DREAMING" = TRAIT_DREAMING,
		"TRAIT_MUTE" = TRAIT_MUTE,
		"TRAIT_XENO_HOST" = TRAIT_XENO_HOST,
		"TRAIT_MIME" = TRAIT_MIME,
		"TRAIT_ANTIMAGIC" = TRAIT_ANTIMAGIC,
		"TRAIT_HOLY" = TRAIT_HOLY,
	),
	/*
	/obj/item/bodypart = list(
		/*
		"TRAIT_PARALYSIS" = TRAIT_PARALYSIS
		*/
		),
	*/
	/obj/item = list(
		/*
		*/
		"TRAIT_NODROP" = TRAIT_NODROP,
		"TRAIT_DISRUPTED" = TRAIT_DISRUPTED,
		/*
		"TRAIT_T_RAY_VISIBLE" = TRAIT_T_RAY_VISIBLE,
		"TRAIT_NO_TELEPORT" = TRAIT_NO_TELEPORT
		*/
		)
	))

/// value -> trait name, generated on use from trait_by_type global
GLOBAL_LIST(trait_name_map)

/proc/generate_trait_name_map()
	. = list()
	for(var/key in GLOB.traits_by_type)
		for(var/tname in GLOB.traits_by_type[key])
			var/val = GLOB.traits_by_type[key][tname]
			.[val] = tname
