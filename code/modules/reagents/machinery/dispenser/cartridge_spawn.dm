ADMIN_VERB(spawn_chemdisp_cartridge, R_SPAWN, "Spawn Chemical Dispenser Cartridge", "Spawns a chemical dispenser catridge.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	var/size = verb_ask(user, "a1", args, /datum/prompt/choice, question = "Select the catridge size", title = "Select Size", choices = list("small", "medium", "large"), default = "small")
	if(isnull(size))
		return
	if(!size)
		return
	var/reagent = verb_ask(user, "a2", args, /datum/prompt/choice, question = "Select the reagent to put into the catridge", title = "Select Reagent", choices = SSchemistry.ready().chemical_reagents)
	if(isnull(reagent))
		return
	if(!reagent)
		return
	var/obj/item/reagent_containers/chem_disp_cartridge/new_catridge
	var/mob/user_mob = user.mob
	switch(size)
		if("small") new_catridge = new /obj/item/reagent_containers/chem_disp_cartridge/small(user_mob.loc)
		if("medium") new_catridge = new /obj/item/reagent_containers/chem_disp_cartridge/medium(user_mob.loc)
		if("large") new_catridge = new /obj/item/reagent_containers/chem_disp_cartridge(user_mob.loc)
	new_catridge.reagents.add_reagent(reagent, new_catridge.volume)
	var/datum/reagent/used_reagent = SSchemistry.ready().chemical_reagents[reagent]
	new_catridge.setLabel(used_reagent.name)
	log_admin("[key_name(user)] spawned a [size] reagent container containing [reagent] at ([user_mob.x],[user_mob.y],[user_mob.z])")
