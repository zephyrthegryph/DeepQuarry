// Tool work on walls (cutting, the reinforced layers, repair) is the wall
// construction graph and its interactions: wall_construction.dm.

/turf/simulated/wall/proc/toggle_open(mob/user)

	if(can_open == WALL_OPENING)
		return

	if(density)
		can_open = WALL_OPENING
		//flick("[material.icon_base]fwall_opening", src)
		density = FALSE
		blocks_air = ZONE_BLOCKED
		update_icon()
		update_air()
		set_light(0)
		src.blocks_air = 0
		set_opacity(0)
		for(var/turf/simulated/turf in loc)
			SSair.mark_for_update(turf)
	else
		can_open = WALL_OPENING
		//flick("[material.icon_base]fwall_closing", src)
		density = TRUE
		blocks_air = AIR_BLOCKED
		update_icon()
		update_air()
		set_light(1)
		src.blocks_air = 1
		set_opacity(1)
		for(var/turf/simulated/turf in loc)
			SSair.mark_for_update(turf)

	can_open = WALL_CAN_OPEN
	update_icon()

/turf/simulated/wall/proc/update_air()
	if(!SSair)
		return

	for(var/turf/simulated/turf in loc)
		update_thermal(turf)
		SSair.mark_for_update(turf)

/turf/simulated/wall/proc/update_thermal(turf/simulated/source)
	if(istype(source))
		if(density && opacity)
			source.thermal_conductivity = WALL_HEAT_TRANSFER_COEFFICIENT
		else
			source.thermal_conductivity = initial(source.thermal_conductivity)
		source.update_heat_cell()

/turf/simulated/wall/proc/fail_smash(mob/user)
	var/damage_lower = 25
	var/damage_upper = 75
	if(isanimal(user))
		var/mob/living/simple_mob/S = user
		playsound(src, S.attack_sound, 75, 1)
		if(!(S.melee_damage_upper >= STRUCTURE_MIN_DAMAGE_THRESHOLD * 2))
			to_chat(user, span_notice("You bounce against the wall."))
			return FALSE
		damage_lower = S.melee_damage_lower
		damage_upper = S.melee_damage_upper
	to_chat(user, span_danger("You smash against the wall!"))
	user.do_attack_animation(src)
	receive_generic_attack(user, rand(damage_lower,damage_upper))

/turf/simulated/wall/proc/success_smash(mob/user)
	to_chat(user, span_danger("You smash through the wall!"))
	user.do_attack_animation(src)
	if(isanimal(user))
		var/mob/living/simple_mob/S = user
		playsound(src, S.attack_sound, 75, 1)
	addtimer(CALLBACK(src, PROC_REF(dismantle_wall), 1), 1)

/turf/simulated/wall/proc/try_touch(mob/user, rotting)

	if(rotting)
		if(reinf_material)
			to_chat(user, span_danger("\The [reinf_material.display_name] feels porous and crumbly."))
		else
			to_chat(user, span_danger("\The [material.display_name] crumbles under your touch!"))
			dismantle_wall()
			return 1

	if(!can_open)
		if(!material.wall_touch_special(src, user))
			to_chat(user, span_notice("You push the wall, but nothing happens."))
			playsound(src, 'sound/weapons/genhit.ogg', 25, 1)
	else
		toggle_open(user)
	return 0

/turf/simulated/wall/attack_ai(mob/user)
	if(!Adjacent(user))
		return
	if(!isrobot((user)))
		return
	var/rotting = (locate(/obj/effect/overlay/wallrot) in src)
	try_touch(user, rotting)

/turf/simulated/wall/attack_hand(mob/user)

	radiate()
	add_fingerprint(user)
	user.setClickCooldown(user.get_attack_speed())
	var/rotting = (locate(/obj/effect/overlay/wallrot) in src)
	if (HULK in user.mutations)
		if (rotting || !prob(material.hardness))
			success_smash(user)
		else
			fail_smash(user)
			return 1

	try_touch(user, rotting)

/turf/simulated/wall/attack_generic(mob/user, damage, attack_message)

	radiate()
	user.setClickCooldown(user.get_attack_speed())
	var/rotting = (locate(/obj/effect/overlay/wallrot) in src)
	if(damage < STRUCTURE_MIN_DAMAGE_THRESHOLD * 2)
		try_touch(user, rotting)
		return

	if(rotting)
		return success_smash(user)

	if(reinf_material)
		if(damage >= max(material.hardness, reinf_material.hardness) )
			return success_smash(user)
	else if(damage >= material.hardness)
		return success_smash(user)
	return fail_smash(user)

/turf/simulated/wall/attackby(obj/item/W, mob/user, attack_modifier, click_parameters)

	user.setClickCooldown(user.get_attack_speed(W))

	if (!user.IsAdvancedToolUser())
		to_chat(user, span_warning("You don't have the dexterity to do this!"))
		return

	//get the user's location
	if(!istype(user.loc, /turf))
		return	//can't do this stuff whilst inside objects and such

	if(W)
		radiate()
		if(is_hot(W))
			burn(is_hot(W))

	if(istype(W, /obj/item/electronic_assembly/wallmount))
		var/obj/item/electronic_assembly/wallmount/IC = W
		IC.mount_assembly(src, user)
		return

	if(istype(W, /obj/item/stack/tile/roofing))
		var/expended_tile = FALSE // To track the case. If a ceiling is built in a multiz zlevel, it also necessarily roofs it against weather
		var/turf/T = GetAbove(src)
		var/obj/item/stack/tile/roofing/R = W

		// Place plating over a wall
		if(T)
			if(isopenturf(T))
				if(R.use(1)) // Cost of roofing tiles is 1:1 with cost to place lattice and plating
					T.ReplaceWithLattice()
					T.ChangeTurf(/turf/simulated/floor, preserve_outdoors = TRUE)
					playsound(src, 'sound/weapons/genhit.ogg', 50, 1)
					user.visible_message(span_notice("[user] patches a hole in the ceiling."), span_notice("You patch a hole in the ceiling."))
					expended_tile = TRUE
			else
				to_chat(user, span_warning("There aren't any holes in the ceiling to patch here."))
				return

		// Create a ceiling to shield from the weather
		if(is_outdoors())
			if(expended_tile || R.use(1)) // Don't need to check adjacent turfs for a wall, we're building on one
				make_indoors()
				if(!expended_tile) // Would've already played a sound
					playsound(src, 'sound/weapons/genhit.ogg', 50, 1)
				user.visible_message(span_notice("[user] roofs \the [src], shielding it from the elements."), span_notice("You roof \the [src] tile, shielding it from the elements."))
		return

	// Welders reach the wall's interactions (wall_construction.dm) before attackby.
	if(locate(/obj/effect/overlay/wallrot) in src)
		if(!is_sharp(W) && W.force >= 10 || W.force >= 20)
			to_chat(user, span_notice("\The [src] crumbles away under the force of your [W.name]."))
			src.dismantle_wall(1)
			return

	//THERMITE related stuff. Calls src.thermitemelt() which handles melting simulated walls and the relevant effects
	if(thermite)
		if(istype(W, /obj/item/pickaxe/plasmacutter))
			thermitemelt(user)
			return

		else if( istype(W, /obj/item/melee/energy/blade) )
			var/obj/item/melee/energy/blade/EB = W

			EB.spark_system.start()
			to_chat(user, span_notice("You slash \the [src] with \the [EB]; the thermite ignites!"))
			playsound(src, "sparks", 50, 1)
			playsound(src, 'sound/weapons/blade1.ogg', 50, 1)

			thermitemelt(user)
			return

	// Plasma cutters, energy blades and pickaxes stand in for the welder on the graph's cutting steps.
	if(try_construction_alt(user, src, W))
		return

	if(istype(W,/obj/item/frame))
		var/obj/item/frame/F = W
		F.try_build(src, user)
		return

	else if(!istype(W,/obj/item/rcd) && !istype(W, /obj/item/reagent_containers))
		return attack_hand(user)
