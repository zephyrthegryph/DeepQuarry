
/obj/item/shield_projector/line/exploborg
	name = "expirmental shield projector"
	max_integrity = 90
	shield_regen_amount = 25
	line_length = 7			// How long the line is.  Recommended to be an odd number.
	offset_from_center = 2	// How far from the projector will the line's center be.

// To repair a single module
/obj/item/self_repair_system
	name = "plating repair system"
	desc = "A nanite control system to repair damaged armour plating and wiring while not moving. Destroyed armour can't be restored."
	icon = 'icons/obj/robot_component.dmi'
	icon_state = "armor"
	var/repair_time = 25
	var/repair_amount = 2.5
	var/power_tick = 25
	var/disabled_icon = "armor"
	var/active_icon = "armor_broken"
	var/list/target_components = list(ROBOT_SLOT_ARMOUR) // ALLOW(instance_list): d: edited in place per instance (4 writers)
	var/repairing = FALSE
	flags = NOBLUDGEON

CAPABILITIES(/obj/item/self_repair_system)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/self_repair_system/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(repairing)
		return TRUE
	var/mob/living/silicon/robot/R = user
	var/destroyed_components = FALSE
	var/list/repairable_components = list()
	for(var/target_slot in target_components)
		var/datum/robot_component/C = R.get_component(target_slot)
		if(!C)
			continue
		if(C.installed == ROBOT_PART_DESTROYED)
			destroyed_components = TRUE
		else if (C.get_total_damage() > 0)
			repairable_components += C
	if(!repairable_components.len && destroyed_components)
		to_chat(R, span_warning("Repair system initialization failed. Can't repair destroyed [target_components.len == 1 ? "[R.get_component(target_components[1])]'s" : "component's"] plating or wiring."))
		return TRUE
	if(!repairable_components.len)
		to_chat(R, span_warning("No structural or wiring damage detected [target_components.len == 1 ? "in [R.get_component(target_components[1])]" : ""]."))
		return TRUE
	if(destroyed_components)
		to_chat(R, span_warning("WARNING! Destroyed modules detected. Those can not be repaired!"))
	icon_state = active_icon
	repairing = TRUE
	for(var/datum/robot_component/C as anything in repairable_components)
		to_chat(R, span_notice("Repair system initializated. Repairing plating and wiring of [C]."))
		src.self_repair(R, C, repair_time, repair_amount)
	repairing = FALSE
	icon_state = disabled_icon
	return TRUE

/obj/item/self_repair_system/proc/self_repair(mob/living/silicon/robot/R, datum/robot_component/C, tick_delay, heal_per_tick)
	if(!C || !R.cell)
		return
	if(C.get_total_damage() <= 0)
		to_chat(R, span_notice("Repair of [C] completed."))
		return
	if(!R.draw_power(ROBOT_CELL_JOULES(power_tick), src, ROBOT_CELL_JOULES(500))) //We don't want to drain ourselves too far down during exploration
		to_chat(R, span_warning("Not enough power to initialize the repair system."))
		return
	om_task_start(/datum/om/task/timed/self_repair_system_self_repair_self_repair_system, R, R, receiver = src, duration = tick_delay, C = C, tick_delay = tick_delay, heal_per_tick = heal_per_tick)

/datum/om/task/timed/self_repair_system_self_repair_self_repair_system
	complete_proc = /obj/item/self_repair_system/proc/self_repair_self_repair_system_done
	var/datum/robot_component/C
	var/tick_delay
	var/heal_per_tick

/obj/item/self_repair_system/proc/self_repair_self_repair_system_done(datum/om/task/timed/self_repair_system_self_repair_self_repair_system/task)
	var/mob/living/silicon/robot/R = task.actor
	var/datum/robot_component/C = task.C
	var/tick_delay = task.tick_delay
	var/heal_per_tick = task.heal_per_tick
	if(!C)
		return
	R.mend(TREAT_PLATING_REPAIR, heal_per_tick, C)
	R.mend(TREAT_WIRING_REPAIR, heal_per_tick, C)
	src.self_repair(R, C, tick_delay, heal_per_tick)

// To repair multiple modules
/obj/item/self_repair_system/advanced
	name = "self repair system"
	desc = "A nanite control system to repair damaged components while not moving. Destroyed components can't be restored."
	target_components = list(ROBOT_SLOT_ACTUATOR, ROBOT_SLOT_RADIO, ROBOT_SLOT_POWER, ROBOT_SLOT_DIAGNOSIS, ROBOT_SLOT_CAMERA, ROBOT_SLOT_COMMS, ROBOT_SLOT_ARMOUR)
	power_tick = 10
	repair_time = 15
	repair_amount = 3
