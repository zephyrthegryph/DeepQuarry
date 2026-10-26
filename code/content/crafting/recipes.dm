// Locate one of the things that set the material type, and update it from the default (glass)
/transformation/crafting/spear/on_craft_completion(mob/user, atom/result)
	var/obj/item/material/M
	var/datum/xform/rule = xform_of(type)
	for(var/path in rule.parts)
		var/obj/item/material/N = locate_within(result, path)
		if(istype(N, path))
			if(!istype(M))
				M = N
			else
				N.forceMove(get_turf(result))
	if(!istype(M))
		return

	var/obj/item/material/twohanded/spear/S = result
	S.set_material(M.material.name)
	spent(M, user)

/transformation/crafting/surgerytable
CAPABILITIES(/transformation/crafting/surgerytable)
	configure(transformation(name = "surgery table", makes = list(item_term(/obj/machinery/optable, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/silver = 12), list(/obj/item/stack/rods = 10), list(/obj/item/stack/material/leather = 1)),
			build_time = 24 SECONDS,
			category = CAT_MISC)))

