/obj/item/mecha_parts/mecha_equipment/gravcatapult
	name = "gravitational catapult"
	desc = "An exosuit mounted gravitational catapult."
	icon_state = "mecha_teleport"
	equip_cooldown = 10
	energy_drain = 100
	range = MECH_MELEE|RANGED
	var/atom/movable/locked
	var/mode = 1 //1 - gravsling 2 - gravpush

	COOLDOWN_DECLARE(catapult_fire_cooldown)  //Concept stolen from guns.
	var/fire_delay = 10 //Used to prevent spam-brute against humans.

	equip_type = EQUIP_UTILITY

/// Pushes `A` away from `target` once every 0.2 s, `left` more times.
/obj/item/mecha_parts/mecha_equipment/gravcatapult/proc/catapult_push(atom/movable/A, atom/target, left)
	step_away(A,target)
	if(left > 0)
		after(src, 0.2 SECONDS, PROC_REF(catapult_push), with = list(A, target, left - 1))

/obj/item/mecha_parts/mecha_equipment/gravcatapult/action(atom/movable/target)

	if(COOLDOWN_FINISHED(src, catapult_fire_cooldown))
		COOLDOWN_START(src, catapult_fire_cooldown, fire_delay)
	else
		if (world.time % 3)
			occupant_message(span_warning("[src] is not ready to fire again!"))
		return 0

	switch(mode)
		if(1)
			if(!action_checks(target) && !locked()) return
			if(!locked())
				if(!istype(target) || target.anchored)
					occupant_message("Unable to lock on [target]")
					return
				rel_set(src, nameof(locked), target)
				occupant_message("Locked on [target]")
				send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"exosuit.browser","\ref[src]",src.get_equip_info())
				return
			else if(target!=locked())
				if(locked() in view(chassis))
					locked().throw_at(target, 14, 1.5, chassis)
					rel_clear(src, nameof(locked))
					send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"exosuit.browser","\ref[src]",src.get_equip_info())
					set_ready_state(FALSE)
					chassis.use_power(energy_drain)
					do_after_cooldown()
				else
					rel_clear(src, nameof(locked))
					occupant_message("Lock on [locked()] disengaged.")
					send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"exosuit.browser","\ref[src]",src.get_equip_info())
		if(2)
			if(!action_checks(target)) return
			var/list/atoms = list()
			if(isturf(target))
				atoms = range(target,3)
			else
				atoms = orange(target,3)
			for(var/atom/movable/A in atoms)
				if(A.anchored) continue
				catapult_push(A, target, 5-get_dist(A,target))
			set_ready_state(FALSE)
			chassis.use_power(energy_drain)
			do_after_cooldown()
	return

/obj/item/mecha_parts/mecha_equipment/gravcatapult/get_equip_info()
	return "[..()] [mode==1?"([locked()||"Nothing"])":null] \[<a href='byond://?src=\ref[src];mode=1'>S</a>|<a href='byond://?src=\ref[src];mode=2'>P</a>\]"

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/gravcatapult)
	op("mode", topic("mode", arg("mode", num(), optional = TRUE)), then(PROC_REF(topic_mode)))

/obj/item/mecha_parts/mecha_equipment/gravcatapult/proc/topic_mode(datum/act/op/A, href_mode)
	if(isnum(href_mode))
		mode = href_mode
		send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"exosuit.browser","\ref[src]",src.get_equip_info())
	return

/// locked
/obj/item/mecha_parts/mecha_equipment/gravcatapult/proc/locked() as /atom/movable
	return locked
