/datum/objective/steal
	var/steal_target
	var/target_name

	var/global/possible_items[] = list(
		"the Site Manager's antique laser gun" = /obj/item/gun/energy/captain,
		"a hand teleporter" = /obj/item/hand_tele,
		"an RCD" = /obj/item/rcd,
		"a jetpack" = /obj/item/tank/jetpack,
		"a site manager's jumpsuit" = /obj/item/clothing/under/rank/captain,
		"a functional AI" = /obj/item/aicard,
		"a pair of magboots" = /obj/item/clothing/shoes/magboots,
		"the station blueprints" = /obj/item/areaeditor/blueprints,
		"a nasa voidsuit" = /obj/item/clothing/suit/space/void,
		"28 moles of phoron (full tank)" = /obj/item/tank,
		"a sample of slime extract" = /obj/item/slime_extract,
		"a piece of corgi meat" = /obj/item/reagent_containers/food/snacks/meat/corgi,
		"a research director's jumpsuit" = /obj/item/clothing/under/rank/research_director,
		"a chief engineer's jumpsuit" = /obj/item/clothing/under/rank/chief_engineer,
		"a chief medical officer's jumpsuit" = /obj/item/clothing/under/rank/chief_medical_officer,
		"a head of security's jumpsuit" = /obj/item/clothing/under/rank/head_of_security,
		"a head of personnel's jumpsuit" = VARIANT(/obj/item/clothing/under/rank/head_of_personnel),
		"the hypospray" = /obj/item/reagent_containers/hypospray/vial,
		"the site manager's pinpointer" = /obj/item/pinpointer,
		"an ablative armor vest" = /obj/item/clothing/suit/armor/laserproof,
	)

	var/global/possible_items_special[] = list(
		/*"nuclear authentication disk" = /obj/item/disk/nuclear,*///Broken with the change to nuke disk making it respawn on z level change.
		"nuclear gun" = /obj/item/gun/energy/gun/nuclear,
		"diamond drill" = /obj/item/pickaxe/diamonddrill,
		"bag of holding" = /obj/item/storage/backpack/holding,
		"hyper-capacity cell" = /obj/item/cell/hyper,
		"10 diamonds" = /obj/item/stack/material/diamond,
		"50 gold bars" = /obj/item/stack/material/gold,
		"25 refined uranium bars" = /obj/item/stack/material/uranium,
	)

/datum/objective/steal/proc/set_target(item_name)
	target_name = item_name
	steal_target = possible_items[target_name]
	if (!steal_target )
		steal_target = possible_items_special[target_name]
	set_explanation_text("Steal [target_name].")
	return steal_target

/datum/objective/steal/find_target()
	return set_target(pick(possible_items))

/// The admin objective editor's steal answers (a possible item name, or "custom" with an item type and a name).
/datum/objective/steal/proc/apply_steal_choice(new_target, custom_target, custom_name) // custom_target: an item type path
	if (!new_target) return
	if (new_target == "custom")
		if (!custom_target || !custom_name) return
		target_name = custom_name
		steal_target = custom_target
		set_explanation_text("Steal [target_name].")
	else
		set_target(new_target)
	return steal_target

/datum/objective/steal/check_completion()
	if(!steal_target || !owner.current)	return 0
	if(!isliving(owner.current))	return 0
	var/list/all_items = owner.current.get_contents()
	switch (target_name)
		if("28 moles of phoron (full tank)","10 diamonds","50 gold bars","25 refined uranium bars")
			var/target_amount = text2num(target_name)//Non-numbers are ignored.
			var/found_amount = 0.0//Always starts as zero.

			for(var/obj/item/I in all_items) //Check for phoron tanks
				if(variant_is(I, steal_target))
					if(target_name=="28 moles of phoron (full tank)")
						var/obj/item/tank/phoron_tank = I
						found_amount += LINDA_GAS_AMT(phoron_tank.air_contents, GAS_PHORON) // XGM .gas[id] → LINDA
					else
						var/obj/item/stack/counted_stack = I
						found_amount += counted_stack.amount
			return found_amount>=target_amount

		if("50 coins (in bag)")
			var/obj/item/moneybag/B = locate_in_list(all_items, /obj/item/moneybag)

			if(B)
				var/target = text2num(target_name)
				var/found_amount = 0.0
				for(var/obj/item/coin/C in B)
					found_amount++
				return found_amount>=target

		if("a functional AI")

			for(var/obj/item/aicard/C in all_items) //Check for ai card
				for(var/mob/living/silicon/ai/M in C)
					if(isAI(M) && M.stat != 2) //See if any AI's are alive inside that card.
						return 1

			for(var/mob/living/silicon/ai/ai in REGISTRY_MEMBERS(REGISTRY_MOBS))
				var/turf/T = get_turf(ai)
				if(istype(T))
					var/area/check_area = get_area(ai)
					if(istype(check_area, /area/shuttle/escape/centcom))
						return 1
					if(istype(check_area, /area/shuttle/escape_pod1/centcom))
						return 1
					if(istype(check_area, /area/shuttle/escape_pod2/centcom))
						return 1
					if(istype(check_area, /area/shuttle/escape_pod3/centcom))
						return 1
					if(istype(check_area, /area/shuttle/escape_pod5/centcom))
						return 1
		else

			for(var/obj/I in all_items) //Check for items
				if(variant_is(I, steal_target))
					return 1
	return 0
