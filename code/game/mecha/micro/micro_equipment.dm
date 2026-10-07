//DO NOT ADD MECHA PARTS TO THE GAME WITH THE DEFAULT "SPRITE ME" SPRITE!

/////////////////////////////
////    WEAPONS BELOW    ////
/////////////////////////////
/obj/item/mecha_parts/mecha_equipment/weapon/energy/microlaser
	w_class = ITEMSIZE_LARGE
	desc = "A mounted micro laser-carbine for micro mechs."
	equip_cooldown = 10 // same as the laser carbine
	name = "\improper WS-19 \"Torch\" micro laser carbine"
	icon = 'icons/mecha/mecha_equipment_vr.dmi'
	icon_state = "micromech_laser"
	energy_drain = 50
	projectile = /obj/item/projectile/beam
	fire_sound = SFX_WEAPONS_LASER
	equip_type = EQUIP_MICRO_WEAPON
	required_type = list(/obj/mecha/micro/sec)

/obj/item/mecha_parts/mecha_equipment/weapon/energy/laser/microheavy
	w_class = ITEMSIZE_LARGE
	desc = "A mounted micro laser cannon for micro mechs."
	equip_cooldown = 30 // same as portable
	name = "\improper PC-20 \"Lance\" micro light laser cannon"
	icon = 'icons/mecha/mecha_equipment_vr.dmi'
	icon_state = "micromech_lasercannon"
	energy_drain = 120
	projectile = /obj/item/projectile/beam/heavylaser
	fire_sound = SFX_WEAPONS_LASERCANNONFIRE
	equip_type = EQUIP_MICRO_WEAPON
	required_type = list(/obj/mecha/micro/sec)

/obj/item/mecha_parts/mecha_equipment/weapon/energy/microtaser
	w_class = ITEMSIZE_LARGE
	desc = "A mounted micro taser for micro mechs."
	name = "\improper TS-12 \"Suppressor\" integrated micro taser"
	icon = 'icons/mecha/mecha_equipment_vr.dmi'
	icon_state = "micromech_taser"
	energy_drain = 40
	equip_cooldown = 10
	projectile = /obj/item/projectile/beam/stun
	fire_sound = SFX_WEAPONS_TASER
	equip_type = EQUIP_MICRO_WEAPON
	required_type = list(/obj/mecha/micro/sec)

/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/microshotgun
	w_class = ITEMSIZE_LARGE
	desc = "A mounted micro combat shotgun with integrated ammo-lathe."
	name = "\improper Remington C-12 \"Micro-Boomstick\""
	icon = 'icons/mecha/mecha_equipment_vr.dmi'
	icon_state = "micromech_shotgun"
	equip_cooldown = 15
	var/mode = 0 //0 - buckshot, 1 - beanbag, 2 - slug.
	projectile = /obj/item/projectile/scatter/shotgun
	fire_sound = SFX_WEAPONS_GUNSHOT_SHOTGUN
	fire_volume = 80
	projectiles = 6
	projectiles_per_shot = 1
	deviation = 0.7
	projectile_energy_cost = 100
	equip_type = EQUIP_MICRO_WEAPON
	required_type = list(/obj/mecha/micro/sec)

TOPIC_ACTION(/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/microshotgun, "mode", PROC_REF(topic_mode), TOPIC_NUM("mode"))

/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/microshotgun/proc/topic_mode(mob/user, list/args)
	if(isnum(args["mode"]))
		mode = args["mode"]
		switch(mode)
			if(0)
				occupant_message("Now firing buckshot.")
				projectile = /obj/item/projectile/scatter/shotgun
			if(1)
				occupant_message("Now firing beanbags.")
				projectile = /obj/item/projectile/bullet/shotgun/beanbag
			if(2)
				occupant_message("Now firing slugs.")
				projectile = /obj/item/projectile/bullet/shotgun

	return

/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/microshotgun/get_equip_info()
	return "[..()] \[<a href='byond://?src=\ref[src];mode=0'>BS</a>|<a href='byond://?src=\ref[src];mode=1'>BB</a>|<a href='byond://?src=\ref[src];mode=2'>S</a>\]"


/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/missile_rack/grenade/microflashbang
	w_class = ITEMSIZE_LARGE
	desc = "A mounted micro flashbang launcher for micro mechs."
	name = "\improper FP-20 mounted micro flashbang launcher"
	icon = 'icons/mecha/mecha_equipment_vr.dmi'
	icon_state = "micromech_launcher"
	projectiles = 1
	missile_speed = 1.5
	projectile_energy_cost = 800
	equip_cooldown = 30
	det_time = 15
	equip_type = EQUIP_MICRO_WEAPON
	required_type = list(/obj/mecha/micro/sec)


/////////////////////////////
//// UTILITY TOOLS BELOW ////
/////////////////////////////

/obj/item/mecha_parts/mecha_equipment/tool/drill/micro
	w_class = ITEMSIZE_LARGE
	name = "Micro Drill"
	desc = "This is the micro drill that'll sorta poke holes in the heavens!"
	icon = 'icons/mecha/mecha_equipment_vr.dmi'
	icon_state = "microdrill"
	equip_cooldown = 30
	energy_drain = 10
	force = 15
	equip_type = EQUIP_MICRO_UTILITY
	required_type = list(/obj/mecha/micro/utility)

/obj/item/mecha_parts/mecha_equipment/tool/drill/micro/action(atom/target)
	if(!action_checks(target)) return
	if(isobj(target))
		var/obj/target_obj = target
		if(!target_obj.vars.Find("unacidable") || target_obj.unacidable)	return
	set_ready_state(0)
	chassis.use_power(energy_drain)
	chassis.visible_message(span_danger("[chassis] starts to drill [target]"), span_warning("You hear the drill."))
	occupant_message(span_danger("You start to drill [target]"))
	var/T = chassis.loc
	var/C = target.loc	//why are these backwards? we may never know -Pete
	if(do_after_cooldown(target))
		if(T == chassis.loc && src == chassis.selected)
			if(istype(target, /turf/simulated/wall))
				var/turf/simulated/wall/W = target
				if(W.reinf_material)
					occupant_message(span_warning("[target] is too durable to drill through."))
				else
					src.mecha_log_message("Drilled through [target]")
					target.ex_act(2)
			else if(ismineralturf(target))
				for(var/turf/simulated/mineral/M in range(chassis,1))
					if(get_dir(chassis,M)&chassis.dir)
						M.GetDrilled()
				src.mecha_log_message("Drilled through [target]")
				var/obj/item/mecha_parts/mecha_equipment/tool/micro/orescoop/ore_box = (locate_in_list(chassis.equipment, /obj/item/mecha_parts/mecha_equipment/tool/micro/orescoop))
				if(ore_box)
					for(var/obj/item/ore/ore in range(chassis,1))
						if(get_dir(chassis,ore)&chassis.dir)
							if (contents_count(ore_box) >= ore_box.orecapacity)
								occupant_message(span_warning("The ore compartment is full."))
								return 1
							else
								ore.forceMove(ore_box)
			else if(target.loc == C)
				src.mecha_log_message("Drilled through [target]")
				target.ex_act(2)
	return 1


/obj/item/mecha_parts/mecha_equipment/tool/micro/orescoop
	w_class = ITEMSIZE_LARGE
	name = "Mounted micro ore box"
	desc = "A small mounted ore scoop and hopper, for gathering ores in a micro mech."
	icon = 'icons/mecha/mecha_equipment_vr.dmi'
	icon_state = "microscoop"
	equip_cooldown = 5
	energy_drain = 0
	equip_type = EQUIP_MICRO_UTILITY
	required_type = list(/obj/mecha/micro/utility)
	var/orecapacity = 500

/obj/item/mecha_parts/mecha_equipment/tool/micro/orescoop/action(atom/target)
	if(!action_checks(target)) return
	set_ready_state(0)
	chassis.use_power(energy_drain)
	chassis.visible_message(span_info("[chassis] sweeps around with its ore scoop."))
	occupant_message(span_info("You sweep around the area with the scoop."))
	var/T = chassis.loc
	if(do_after_cooldown(target))
		if(T == chassis.loc && src == chassis.selected)
			for(var/obj/item/ore/ore in range(chassis,1))
				if(get_dir(chassis,ore)&chassis.dir)
					if (contents_count(src) >= orecapacity)
						occupant_message(span_warning("The ore compartment is full."))
						return 1
					else
						ore.Move(src)
	return 1

TOPIC_ACTION(/obj/item/mecha_parts/mecha_equipment/tool/micro/orescoop, "empty_box", PROC_REF(topic_empty_box))

/obj/item/mecha_parts/mecha_equipment/tool/micro/orescoop/proc/topic_empty_box(mob/user, list/args)
	if(contents_count(src) < 1)
		occupant_message("The ore compartment is empty.")
		return
	for (var/obj/item/ore/O in contents)
		O.forceMove(chassis.loc)
	occupant_message("Ore compartment emptied.")

/obj/item/mecha_parts/mecha_equipment/tool/micro/orescoop/get_equip_info()
	return "[..()] <br /><a href='byond://?src=\ref[src];empty_box=1'>Empty ore compartment</a>"

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/tool/micro/orescoop)
	op("orescoop_empty_box", menu(), label("Empty Ore compartment"), needs(req_adjacent(), req_capable()), then(PROC_REF(orescoop_empty_box)))

/// Old verb "Empty Ore compartment": so you can still get the ore out if someone detaches it from the mech.
/// Requirement: TRUE, or why the user can't empty the ore box.
/obj/item/mecha_parts/mecha_equipment/tool/micro/orescoop/proc/can_empty_box(mob/user, atom/target, obj/item/held)
	if(!ishuman(user)) //Only living, intelligent creatures with hands can empty ore boxes.
		return "you are physically incapable of emptying the ore box"
	if(user.stat || user.restrained())
		return TRUE // the effect declines silently
	if(!Adjacent(user)) //You can only empty the box if you can physically reach it
		return "you cannot reach the ore box"
	return TRUE

/obj/item/mecha_parts/mecha_equipment/tool/micro/orescoop/proc/orescoop_empty_box(datum/act/op/A)
	var/refusal = can_empty_box(A.actor, src, A.held)
	if(refusal != TRUE)
		if(istext(refusal))
			to_chat(A.actor, span_warning(refusal))
		return OP_DECLINE
	var/mob/user = A.actor
	if(user.stat || user.restrained())
		return

	add_fingerprint(user)

	if(contents_count(src) < 1)
		to_chat(user, span_warning("The ore box is empty"))
		return

	for (var/obj/item/ore/O in contents)
		O.forceMove(src.loc)
	to_chat(user, span_info("You empty the ore box"))

	return
