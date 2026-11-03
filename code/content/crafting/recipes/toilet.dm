//Craftable toilets in vorecode, 2026 oh yeah woo yeah
/transformation/crafting/toilet
CAPABILITIES(/transformation/crafting/toilet)
	configure(transformation(name = "toilet", makes = list(item_term(/obj/structure/toilet, 1)),
		crafted = crafted(reqs = list(list(/obj/item/stack/material/steel = 5), list(/obj/item/reagent_containers/glass/bucket = 1)),
			build_time = 3 SECONDS,
			category = CAT_MISC)))


/transformation/crafting/toilet/on_craft_completion(mob/user, atom/result)
	result.set_dir(user.dir) //face the toilet where you face.
