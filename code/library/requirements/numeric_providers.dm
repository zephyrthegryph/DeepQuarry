// Dependency providers for the actual material mass fold; other folds need their own readers.
/datum/property_provider/material/mass/requirement_read_keys(datum/thing)
	var/obj/O = thing
	. = list(list(O, nameof(O.material_template)), list(O, nameof(O.material_total)), list(O, nameof(O.material_bulk_material)), list(O, OP_KEY_CAP_DATA))
	var/datum/material_build/B = material_build_of(O)
	if(B)
		. += list(list(B, nameof(B.mix)), list(B, nameof(B.overrides)))
	if(istype(O, /obj/item/stack/material))
		var/obj/item/stack/material/S = O
		. += list(list(S, nameof(S.material)))
		if(S.material)
			. += list(list(S.material, nameof(S.material.composite_material)))

/datum/property_provider/equipment/mass/requirement_read_keys(datum/thing)
	var/mob/M = thing
	. = list(list(M, SLOT_OCCUPANCY_KEY))
	var/datum/property_registry/R = dq_property_registry()
	for(var/obj/item/I in M.get_equipped_items())
		. += R.requirement_read_keys(I, property)

/datum/property_provider/type_var/size_class/requirement_read_keys(datum/thing)
	var/obj/O = thing
	return list(list(O, nameof(O.w_class)))
