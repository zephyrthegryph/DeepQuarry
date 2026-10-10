
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
	var/repair_powered = FALSE
	flags = NOBLUDGEON

MSG_DEF_SELF(self_repair/destroyed_only, "Repair system initialization failed. Can't repair destroyed plating or wiring.")
MSG_DEF_SELF(self_repair/no_damage, "No structural or wiring damage detected.")
MSG_DEF_SELF(self_repair/no_power, "Not enough power to initialize the repair system.")

// Using it starts one repair: every damaged component gets repair_amount per lap of repair_time while the cyborg stands still, one power draw per
// component per lap, until none is damaged or the cell cannot pay. Moving ends it.
CAPABILITIES(/obj/item/self_repair_system)
	op("self", in_hand(), needs(req(PROC_REF(repair_has_work), because = MSG(self_repair/no_damage)), req(PROC_REF(repair_not_only_destroyed), because = MSG(self_repair/destroyed_only))),
		starts(PROC_REF(repair_started)), wait(PROC_REF(repair_lap_time), repeats = PROC_REF(repair_more), after_step = PROC_REF(repair_lap)), on_interrupt(PROC_REF(repair_ended)), then(PROC_REF(repair_ended)))

/// The components of the cyborg that this system can repair and that are damaged.
/obj/item/self_repair_system/proc/repairable_of(mob/living/silicon/robot/R)
	var/list/found = list()
	if(!istype(R))
		return found
	for(var/target_slot in target_components)
		var/datum/robot_component/C = R.get_component(target_slot)
		if(C && C.installed != ROBOT_PART_DESTROYED && C.get_total_damage() > 0)
			found += C
	return found

/obj/item/self_repair_system/proc/repair_has_work(datum/act/op/A)
	return !!length(repairable_of(A.actor))

/// Fails only when everything damaged is a destroyed component (nothing repairable but something destroyed).
/obj/item/self_repair_system/proc/repair_not_only_destroyed(datum/act/op/A)
	var/mob/living/silicon/robot/R = A.actor
	if(!istype(R))
		return FALSE
	if(length(repairable_of(R)))
		return TRUE
	for(var/target_slot in target_components)
		var/datum/robot_component/C = R.get_component(target_slot)
		if(C?.installed == ROBOT_PART_DESTROYED)
			return FALSE
	return TRUE

/obj/item/self_repair_system/proc/repair_lap_time(datum/act/op/A)
	return repair_time

/// Pays the power for the next lap; every component being repaired costs a draw.
/obj/item/self_repair_system/proc/repair_pay(mob/living/silicon/robot/R)
	if(!R.cell)
		return FALSE
	for(var/datum/robot_component/C as anything in repairable_of(R))
		if(!R.draw_power(ROBOT_CELL_JOULES(power_tick), src, ROBOT_CELL_JOULES(500))) //We don't want to drain ourselves too far down during exploration
			to_chat(R, span_warning("Not enough power to initialize the repair system."))
			return FALSE
	return TRUE

/obj/item/self_repair_system/proc/repair_started(datum/act/op/A)
	var/mob/living/silicon/robot/R = A.actor
	for(var/target_slot in target_components)
		var/datum/robot_component/C = R.get_component(target_slot)
		if(C?.installed == ROBOT_PART_DESTROYED)
			to_chat(R, span_warning("WARNING! Destroyed modules detected. Those can not be repaired!"))
			break
	icon_state = active_icon
	repairing = TRUE
	for(var/datum/robot_component/C as anything in repairable_of(R))
		to_chat(R, span_notice("Repair system initializated. Repairing plating and wiring of [C]."))
	if(!repair_pay(R))
		repair_powered = FALSE
		return MSG(self_repair/no_power)
	repair_powered = TRUE

/// Another lap follows while something is damaged and the last payment went through.
/obj/item/self_repair_system/proc/repair_more(datum/act/op/A)
	return repair_powered

/// One lap done: heal every damaged component, then pay for the next lap.
/obj/item/self_repair_system/proc/repair_lap(datum/act/op/A)
	var/mob/living/silicon/robot/R = A.actor
	for(var/datum/robot_component/C as anything in repairable_of(R))
		R.mend(TREAT_PLATING_REPAIR, repair_amount, C)
		R.mend(TREAT_WIRING_REPAIR, repair_amount, C)
		if(C.get_total_damage() <= 0)
			to_chat(R, span_notice("Repair of [C] completed."))
	repair_powered = length(repairable_of(R)) && repair_pay(R)

/obj/item/self_repair_system/proc/repair_ended(datum/act/op/A)
	repairing = FALSE
	repair_powered = FALSE
	icon_state = disabled_icon
	return OP_OK

// To repair multiple modules
/obj/item/self_repair_system/advanced
	name = "self repair system"
	desc = "A nanite control system to repair damaged components while not moving. Destroyed components can't be restored."
	target_components = list(ROBOT_SLOT_ACTUATOR, ROBOT_SLOT_RADIO, ROBOT_SLOT_POWER, ROBOT_SLOT_DIAGNOSIS, ROBOT_SLOT_CAMERA, ROBOT_SLOT_COMMS, ROBOT_SLOT_ARMOUR)
	power_tick = 10
	repair_time = 15
	repair_amount = 3
