/obj/mecha/micro
	icon = 'icons/mecha/micro.dmi'
	force = 10 //still a robot
	anchored = FALSE //light enough to push and pull, but you still can't just walk past them. Like people on non-help.
	opacity = 0 //small enough to see around, like people.
	step_energy_drain = 2 // They're light and small. A compact is gonna get better MPG than a truck.
	var/melee_cooldown = 10
	var/melee_can_hit = 1
	var/static/list/destroyable_obj = list(/obj/mecha, /obj/structure/window, /obj/structure/grille, /turf/simulated/wall)
	internal_damage_threshold = 50
	maint_access = 0
	max_hull_equip = 1
	max_weapon_equip = 0
	max_utility_equip = 0
	max_universal_equip = 0
	max_special_equip = 1
	max_micro_utility_equip = 1
	max_micro_weapon_equip = 1
	var/am = "d3c2fbcadca903a41161ccc9df9cf948"
	damage_minimum = 0				//Incoming damage lower than this won't actually deal damage. Scrapes shouldn't be a real thing.
	minimum_penetration = 0		//Incoming damage won't be fully applied if you don't have at least 20. Almost all AP clears this.

/obj/mecha/micro/melee_action(target as obj|mob|turf)
	if(mech_body_plan().has_affliction(src, MECHA_INT_CONTROL_LOST))
		target = safepick(oview(1,src))
	if(!melee_can_hit || !istype(target, /atom)) return
	if(isliving(target))
		var/mob/living/M = target
		if(pilot_is_harming())
			play_sfx(src, SFX_WEAPONS_PUNCH4)
			if(melee_injury_kind == INJURY_BLUNT)
				step_away(M,src,15)
			var/hit_zone = ishuman(M) ? pick(BP_TORSO, BP_TORSO, BP_TORSO, BP_HEAD) : null
			switch(melee_injury_kind)
				if(INJURY_BLUNT)
					if(!ishuman(M))
						M.status_at_least(STAT_PARALYZED, 1)
					M.injure(INJURY_BLUNT, rand(force/2, force), hit_zone, src)
				if(INJURY_BURN)
					M.injure(INJURY_BURN, rand(force/2, force), hit_zone, src)
				if(INJURY_TOXIN)
					if(M.reagents)
						if(M.reagents.get_reagent_amount(REAGENT_ID_CARPOTOXIN) + force < force*2)
							M.reagents.add_reagent(REAGENT_ID_CARPOTOXIN, force)
						if(M.reagents.get_reagent_amount(REAGENT_ID_CRYPTOBIOLIN) + force < force*2)
							M.reagents.add_reagent(REAGENT_ID_CRYPTOBIOLIN, force)
				else
					return
			src.occupant_message(span_attack("You hit [target]."))
			src.visible_message(span_bolddanger("[src.name] hits [target]."))
		else
			step_away(M,src)
			src.occupant_message("You push [target] out of the way.")
			src.visible_message("[src] pushes [target] out of the way.")

		melee_can_hit = 0
		after(src, melee_cooldown, PROC_REF(reset_melee))
		return

	else
		if(melee_injury_kind == INJURY_BLUNT)
			for(var/target_type in src.destroyable_obj)
				if(istype(target, target_type) && hascall(target, "attackby"))
					src.occupant_message(span_attack("You hit [target]."))
					src.visible_message(span_bolddanger("[src.name] hits [target]."))
					if(!istype(target, /turf/simulated/wall))
						var/atom/target_atom = target
						target_atom.attackby(src,src?.slot_item(MECHA_SLOT_PILOT))
					else
						play_sfx(src, SFX_WEAPONS_SMASH)
					melee_can_hit = 0
					after(src, melee_cooldown, PROC_REF(reset_melee))
					break
	return


/obj/mecha/micro/topic_close(datum/act/op/A)
	am = null

// override move_inside() so only micro crew can use them

/obj/mecha/micro/move_inside(mob/user)
	if (user.get_effective_size(TRUE) >= 0.5)
		to_chat(user, span_warning("You can't fit in this suit!"))
		return
	else
		..()

/obj/mecha/micro/move_inside_passenger(mob/user, obj/item/held, datum/interaction/interaction)
	if(!user)
		return
	if (user.get_effective_size(TRUE) >= 0.5)
		to_chat(user, span_warning("You can't fit in this suit!"))
		return
	else
		..()

// override move/turn procs so they play more appropriate sounds. Placeholder sounds for now, but mechmove04 at least sounds like tracks for the poleat.

/obj/mecha/micro/mechturn(direction)
	set_dir(direction)
	play_sfx(src, SFX_MECHA_MECHMOVE03)
	return 1

/obj/mecha/micro/mechstep(direction)
	var/result = step(src,direction)
	if(result)
		play_sfx(src, SFX_MECHA_MECHMOVE04)
	return result

/obj/mecha/micro/mechsteprand()
	var/result = step_rand(src)
	if(result)
		play_sfx(src, SFX_MECHA_MECHMOVE04)
	return result

/obj/effect/decal/mecha_wreckage/micro
	icon = 'icons/mecha/micro.dmi'

/obj/mecha/micro/proc/reset_melee()
	melee_can_hit = 1
