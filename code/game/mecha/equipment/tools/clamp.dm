/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp
	name = "hydraulic clamp"
	icon_state = "mecha_clamp"
	equip_cooldown = 15
	energy_drain = 10
	var/dam_force = 20
	var/obj/mecha/working/ripley/cargo_holder
	required_type = list(/obj/mecha/working)
	ready_sound = SFX_MECHA_GASDISCONNECTED

/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp/attach(obj/mecha/M as obj)
	..()
	rel_set(src, nameof(cargo_holder), M)

	return

/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp/proc/pry_firedoor(obj/machinery/door/firedoor/FD, unblock)
	play_sfx(FD, SFX_MACHINES_DOOR_AIRLOCK_CREAKING)
	if(unblock)
		FD.set_blocked(0)
		FD.force_open_by(chassis?.slot_item(MECHA_SLOT_PILOT))
		FD.visible_message(span_warning("\The [chassis] tears \the [FD] open!"))
	else
		FD.visible_message(span_danger("\The [chassis] forces \the [FD] open!"))
		FD.force_open_by(chassis?.slot_item(MECHA_SLOT_PILOT))

/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp/proc/pry_airlock(obj/machinery/door/airlock/AD)
	if(!chassis?.Adjacent(AD))
		return
	set_welded(AD, FALSE)
	play_sfx(AD, SFX_MACHINES_DOOR_AIRLOCK_CREAKING)
	AD.visible_message(span_danger("\The [chassis] tears \the [AD] open!"))
	toggle_airlock(AD)

/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp/proc/toggle_airlock(obj/machinery/door/airlock/AD)
	if(is_welded(AD))
		return
	if(AD.density)
		AD.open(1)
	else
		AD.close(1)

/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp/action(atom/target)
	if(!action_checks(target)) return
	if(!cargo_holder()) return

	//loading
	if(istype(target,/obj))
		var/obj/O = target
		if(O.has_buckled_mobs())
			return
		if(locate_within(O, /mob/living))
			occupant_message(span_warning("You can't load living things into the cargo compartment."))
			return
		if(O.anchored)
			if(enable_special)
				if(istype(O, /obj/machinery/door/firedoor))	// I love doors.
					var/obj/machinery/door/firedoor/FD = O
					if(FD.blocked)
						FD.visible_message(span_danger("\The [chassis] begins prying on \the [FD]!"))
						task_timed(chassis?.slot_item(MECHA_SLOT_PILOT), 10 SECONDS, FD, src, PROC_REF(pry_firedoor), list(FD, TRUE), IGNORE_HELD_ITEM)
					else if(FD.density)
						FD.visible_message(span_warning("\The [chassis] begins forcing \the [FD] open!"))
						task_timed(chassis?.slot_item(MECHA_SLOT_PILOT), 5 SECONDS, FD, src, PROC_REF(pry_firedoor), list(FD, FALSE), IGNORE_HELD_ITEM)
					else
						FD.visible_message(span_danger("\The [chassis] forces \the [FD] closed!"))
						FD.close(1)
				else if(istype(O, /obj/machinery/door/airlock))	// D o o r s.
					var/obj/machinery/door/airlock/AD = O
					if(is_bolted(AD))
						occupant_message(span_notice("The airlock's bolts prevent it from being forced."))
					else if(!AD.operating)
						if(is_welded(AD))
							AD.visible_message(span_warning("\The [chassis] begins prying on \the [AD]!"))
							task_timed(chassis?.slot_item(MECHA_SLOT_PILOT), 15 SECONDS, AD, src, PROC_REF(pry_airlock), list(AD), IGNORE_HELD_ITEM)
						else
							toggle_airlock(AD)
				return
			else
				occupant_message(span_warning("[target] is firmly secured."))
			return
		if(length(cargo_holder().cargo) >= cargo_holder().cargo_capacity)
			occupant_message(span_warning("Not enough room in cargo compartment."))
			return

		occupant_message("You lift [target] and start to load it into cargo compartment.")
		chassis.visible_message("[chassis] lifts [target] and starts to load it into cargo compartment.")
		set_ready_state(FALSE)
		chassis.use_power(energy_drain)
		O.set_anchored(TRUE)
		var/T = chassis.loc
		if(do_after_cooldown(target))
			if(T == chassis.loc && src == chassis.selected)
				var/obj/mecha/working/ripley/holder = cargo_holder()
				LAZYADD(holder.cargo, O)
				if(!move_into(holder, MECHA_SLOT_CARGO, O))
					O.forceMove(holder)
				O.set_anchored(FALSE)
				occupant_message(span_notice("[target] succesfully loaded."))
				src.mecha_log_message("Loaded [O]. Cargo compartment capacity: [cargo_holder().cargo_capacity - length(cargo_holder().cargo)]")
			else
				occupant_message(span_warning("You must hold still while handling objects."))
				O.set_anchored(initial(O.anchored))

	//attacking
	else if(isliving(target))
		var/mob/living/M = target
		if(M.stat>1) return
		if(chassis?.pilot_is_harming() || istype(chassis?.slot_item(MECHA_SLOT_PILOT),/mob/living/carbon/brain)) //No tactile feedback for brains
			M.injure(INJURY_BLUNT, dam_force, null, chassis)
			M.body?.add_restriction(chassis, BF_LUNG_MECHANICS, 0.2, 6 SECONDS) // the chest can't expand in the grip
			occupant_message(span_warning("You squeeze [target] with [src.name]. Something cracks."))
			play_sfx(src, SFX_FRACTURE, volume = 5) //CRACK
			chassis.visible_message(span_warning("[chassis] squeezes [target]."))
		else if(chassis?.pilot_is_disarming() && enable_special)
			play_sfx(src, SFX_MECHA_HYDRAULIC)
			M.injure(INJURY_BLUNT, dam_force/2, null, chassis)
			M.body?.add_restriction(chassis, BF_LUNG_MECHANICS, 0.4, 4 SECONDS) // winded by the slam
			occupant_message(span_warning("You slam [target] with [src.name]. Something cracks."))
			play_sfx(src, SFX_FRACTURE, volume = 3) //CRACK 2
			chassis.visible_message(span_warning("[chassis] slams [target]."))
			M.throw_at(get_step(M,get_dir(src, M)), 14, 1.5, chassis)
		else
			step_away(M,chassis)
			occupant_message("You push [target] out of the way.")
			chassis.visible_message("[chassis] pushes [target] out of the way.")
		set_ready_state(FALSE)
		chassis.use_power(energy_drain)
		do_after_cooldown()
	return 1


//This is pretty much just for the death-ripley so that it is harmless
/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp/safety
	name = "\improper KILL CLAMP"
	equip_cooldown = 15
	energy_drain = 0
	dam_force = 0

/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp/safety/action(atom/target)
	if(!action_checks(target)) return
	if(!cargo_holder()) return
	if(istype(target,/obj))
		var/obj/O = target
		if(!O.anchored)
			if(length(cargo_holder().cargo) < cargo_holder().cargo_capacity)
				chassis.occupant_message("You lift [target] and start to load it into cargo compartment.")
				chassis.visible_message("[chassis] lifts [target] and starts to load it into cargo compartment.")
				set_ready_state(FALSE)
				chassis.use_power(energy_drain)
				O.set_anchored(TRUE)
				var/T = chassis.loc
				if(do_after_cooldown(target))
					if(T == chassis.loc && src == chassis.selected)
						var/obj/mecha/working/ripley/holder = cargo_holder()
						LAZYADD(holder.cargo, O)
						if(!move_into(holder, MECHA_SLOT_CARGO, O))
							O.forceMove(holder)
						O.set_anchored(FALSE)
						chassis.occupant_message(span_notice("[target] succesfully loaded."))
						chassis.mecha_log_message("Loaded [O]. Cargo compartment capacity: [cargo_holder().cargo_capacity - length(cargo_holder().cargo)]")
					else
						chassis.occupant_message(span_warning("You must hold still while handling objects."))
						O.set_anchored(initial(O.anchored))
			else
				chassis.occupant_message(span_warning("Not enough room in cargo compartment."))
		else
			chassis.occupant_message(span_warning("[target] is firmly secured."))

	else if(isliving(target))
		var/mob/living/M = target
		if(M.stat>1) return
		if(chassis?.pilot_is_harming())
			chassis.occupant_message(span_danger("You obliterate [target] with [src.name], leaving blood and guts everywhere."))
			chassis.visible_message(span_danger("[chassis] destroys [target] in an unholy fury."))
		else if(chassis?.pilot_is_disarming())
			chassis.occupant_message(span_danger("You tear [target]'s limbs off with [src.name]."))
			chassis.visible_message(span_danger("[chassis] rips [target]'s arms off."))
		else
			step_away(M,chassis)
			chassis.occupant_message("You smash into [target], sending them flying.")
			chassis.visible_message("[chassis] tosses [target] like a piece of paper.")
		set_ready_state(FALSE)
		chassis.use_power(energy_drain)
		do_after_cooldown()
	return 1

/// cargo holder
/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp/proc/cargo_holder() as /obj/mecha/working/ripley
	return cargo_holder
