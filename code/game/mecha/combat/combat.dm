/obj/mecha/combat
	force = 30
	var/melee_cooldown = 10
	var/melee_can_hit = 1
	//var/list/destroyable_obj = list(/obj/mecha, /obj/structure/window, /obj/structure/grille, /turf/simulated/wall, /obj/structure/girder)
	internal_damage_threshold = 50
	maint_access = 0
	//add_req_access = 0
	//operation_req_access = list(ACCESS_HOS)
	var/am = "d3c2fbcadca903a41161ccc9df9cf948"

	max_hull_equip = 2
	max_weapon_equip = 2
	max_utility_equip = 1
	max_universal_equip = 1
	max_special_equip = 1
	cargo_capacity = 1

	encumbrance_gap = 1.5

	starting_components = list(
		/obj/item/mecha_parts/component/hull/durable,
		/obj/item/mecha_parts/component/actuator,
		/obj/item/mecha_parts/component/armor/reinforced,
		/obj/item/mecha_parts/component/gas,
		/obj/item/mecha_parts/component/electrical
		)

/*
/obj/mecha/combat/range_action(target as obj|mob|turf)
	if(internal_damage&MECHA_INT_CONTROL_LOST)
		target = pick(view(3,target))
	if(selected_weapon)
		selected_weapon.fire(target)
	return
*/

/obj/mecha/combat/melee_action(atom/T)
	if(internal_damage&MECHA_INT_CONTROL_LOST)
		T = safepick(oview(1,src))
	if(!melee_can_hit)
		return
	if(isliving(T))
		var/mob/living/M = T
		if(IS_HARMING(src.occupant) || istype(src.occupant, /mob/living/carbon/brain)) //Brains cannot change intents; Exo-piloting brains lack any form of physical feedback for control, limiting the ability to 'play nice'.
			playsound(src, 'sound/weapons/heavysmash.ogg', 50, 1)
			if(melee_injury_kind == INJURY_BLUNT)
				step_away(M,src,15)
			var/hit_zone = ishuman(M) ? pick(BP_TORSO, BP_TORSO, BP_TORSO, BP_HEAD) : null
			switch(melee_injury_kind)
				if(INJURY_BLUNT)
					M.Paralyse(1)
					M.injure(INJURY_BLUNT, rand(force/2, force), hit_zone, src)
				if(INJURY_BURN)
					M.injure(INJURY_BURN, rand(force/2, force), hit_zone, src)
				if(INJURY_TOXIN)
					if(M.reagents)
						if(M.reagents.get_reagent_amount(REAGENT_ID_CARPOTOXIN) + force < force*2)
							M.reagents.add_reagent(REAGENT_ID_CARPOTOXIN, force)
						if(M.reagents.get_reagent_amount(REAGENT_ID_CRYPTOBIOLIN) + force < force*2)
							M.reagents.add_reagent(REAGENT_ID_CRYPTOBIOLIN, force)
				if(INJURY_PAIN)
					if(ishuman(M))
						var/mob/living/carbon/human/H = M
						H.stun_effect_act(1, force / 2, BP_TORSO, src)
					else
						return
				else
					return
			src.occupant_message("You hit [T].")
			src.visible_message(span_bolddanger("[src.name] hits [T]."))
		else
			step_away(M,src)
			src.occupant_message("You push [T] out of the way.")
			src.visible_message("[src] pushes [T] out of the way.")

		melee_can_hit = 0
		if(do_after_action(melee_cooldown))
			melee_can_hit = 1
		return

	else
		if(istype(T, /obj/machinery/disposal)) // Stops mechs from climbing into disposals
			return
		if(IS_HARMING(src.occupant) || istype(src.occupant, /mob/living/carbon/brain)) // Don't smash unless we mean it
			if(melee_injury_kind == INJURY_BLUNT)
				src.occupant_message("You hit [T].")
				src.visible_message(span_bolddanger("[src.name] hits [T]"))
				playsound(src, 'sound/weapons/heavysmash.ogg', 50, 1)

				if(istype(T, /obj/structure/girder))
					T.take_damage(force * 3, BRUTE, MELEE) //Girders have 200 health by default. Steel, non-reinforced walls take four punches, girders take (with this value-mod) two, girders took five without.
				else
					T.take_damage(force, BRUTE, MELEE)

				melee_can_hit = 0

				if(do_after_action(melee_cooldown))
					melee_can_hit = 1
	return

/obj/mecha/combat/moved_inside(mob/living/carbon/human/H as mob)
	if(..())
		if(H.client)
			H.client.mouse_pointer_icon = file("icons/mecha/mecha_mouse.dmi")
		return 1
	else
		return 0

/obj/mecha/combat/mmi_moved_inside(obj/item/mmi/mmi_as_oc as obj,mob/user as mob)
	if(..())
		if(occupant.client)
			occupant.client.mouse_pointer_icon = file("icons/mecha/mecha_mouse.dmi")
		return 1
	else
		return 0

/obj/mecha/combat/go_out()
	if(src.occupant && src.occupant.client)
		src.occupant.client.mouse_pointer_icon = initial(src.occupant.client.mouse_pointer_icon)
	..()
	return

/obj/mecha/combat/Topic(href,href_list)
	..()
	var/datum/topic_input/top_filter = new (href,href_list)
	if(top_filter.get("close"))
		am = null
		return
