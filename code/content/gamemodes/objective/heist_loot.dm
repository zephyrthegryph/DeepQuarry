/// The type the raiders are to steal (a path, so not the objective's mind target).
/datum/objective/heist/loot/var/loot_path

/datum/objective/heist/loot/choose_target()
	var/loot = "an object"
	switch(rand(1,8))
		if(1)
			loot_path = /obj/structure/particle_accelerator
			target_amount = 6
			loot = "a complete particle accelerator"
		if(2)
			loot_path = /obj/machinery/the_singularitygen
			target_amount = 1
			loot = "a gravitational generator"
		if(3)
			loot_path = /obj/machinery/power/emitter
			target_amount = 4
			loot = "four emitters"
		if(4)
			loot_path = /obj/machinery/nuclearbomb
			target_amount = 1
			loot = "a nuclear bomb"
		if(5)
			loot_path = /obj/item/gun
			target_amount = 6
			loot = "six guns"
		if(6)
			loot_path = /obj/item/gun/energy
			target_amount = 4
			loot = "four energy guns"
		if(7)
			loot_path = /obj/item/gun/energy/laser
			target_amount = 2
			loot = "two laser guns"
		if(8)
			loot_path = /obj/item/gun/energy/ionrifle
			target_amount = 1
			loot = "an ion gun"

	set_explanation_text("It's a buyer's market out here. Steal [loot] for resale.")

/datum/objective/heist/loot/check_completion()
	var/total_amount = 0

	for(var/obj/O in locate(/area/shuttle/skipjack)) // Shuttle area pathname
		if(istype(O, loot_path)) total_amount++
		for(var/obj/I in contents_of(O))
			if(istype(I, loot_path)) total_amount++
		if(total_amount >= target_amount) return 1

	for(var/datum/mind/raider in antag_raiders().current_antagonists)
		if(raider.current)
			for(var/obj/O in raider.current.get_contents())
				if(istype(O, loot_path)) total_amount++
				if(total_amount >= target_amount) return 1

	return 0
