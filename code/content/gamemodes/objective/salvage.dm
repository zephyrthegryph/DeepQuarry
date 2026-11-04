/// The material the raiders are to ransack (its name, so not the objective's mind target).
/datum/objective/heist/salvage/var/material_name

/datum/objective/heist/salvage/choose_target()
	switch(rand(1,8))
		if(1)
			material_name = MAT_STEEL
			target_amount = 300
		if(2)
			material_name = MAT_GLASS
			target_amount = 200
		if(3)
			material_name = MAT_PLASTEEL
			target_amount = 100
		if(4)
			material_name = MAT_PHORON
			target_amount = 100
		if(5)
			material_name = MAT_SILVER
			target_amount = 50
		if(6)
			material_name = MAT_GOLD
			target_amount = 20
		if(7)
			material_name = MAT_URANIUM
			target_amount = 20
		if(8)
			material_name = MAT_DIAMOND
			target_amount = 20

	set_explanation_text("Ransack the station and escape with [target_amount] [material_name].")

/datum/objective/heist/salvage/check_completion()

	var/total_amount = 0

	for(var/obj/item/O in locate(/area/shuttle/skipjack)) //Skipjack area pathname

		var/obj/item/stack/material/S
		if(istype(O,/obj/item/stack/material))
			if(O.name == material_name)
				S = O
				total_amount += S.get_amount()
		for(var/obj/I in contents_of(O))
			if(istype(I,/obj/item/stack/material))
				if(I.name == material_name)
					S = I
					total_amount += S.get_amount()

	for(var/datum/mind/raider in antag_raiders().current_antagonists)
		if(raider.current)
			for(var/obj/item/O in raider.current.get_contents())
				if(istype(O,/obj/item/stack/material))
					if(O.name == material_name)
						var/obj/item/stack/material/S = O
						total_amount += S.get_amount()

	if(total_amount >= target_amount) return 1
	return 0
