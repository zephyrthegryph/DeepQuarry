
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
	// The repair itself: every component being mended is worked on each lap, until none is damaged or power runs short. The borg stays still for it.
	op("self_repair", ai(), needs(req_capable()), takes("components"), starts(PROC_REF(self_repair_started)), wait(PROC_REF(self_repair_interval), repeats = PROC_REF(self_repair_more), after_step = PROC_REF(self_repair_lap)), on_interrupt(PROC_REF(self_repair_finished)), then(PROC_REF(self_repair_finished)))

MSG_DEF_SELF(self_repair/nothing, "The repair system has nothing it can mend.")

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
	for(var/datum/robot_component/C as anything in repairable_components)
		to_chat(R, span_notice("Repair system initializated. Repairing plating and wiring of [C]."))
	perform_op(R, src, "self_repair", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("components" = repairable_components))
	return TRUE

/// Whether `C` can go on being mended for another lap: it is still there, the cell holds up, there is damage left and the power was paid. Says why not.
/obj/item/self_repair_system/proc/self_repair_gate(mob/living/silicon/robot/R, datum/robot_component/C)
	if(!C || !R.cell)
		return FALSE
	if(C.get_total_damage() <= 0)
		to_chat(R, span_notice("Repair of [C] completed."))
		return FALSE
	if(!R.draw_power(ROBOT_CELL_JOULES(power_tick), src, ROBOT_CELL_JOULES(500))) //We don't want to drain ourselves too far down during exploration
		to_chat(R, span_warning("Not enough power to initialize the repair system."))
		return FALSE
	return TRUE

/// The first lap's power is paid as the repair starts; a component that fails the gate is dropped, and with none left nothing starts.
/obj/item/self_repair_system/proc/self_repair_started(datum/act/op/A)
	var/mob/living/silicon/robot/R = A.actor
	var/list/components = A.arg("components")
	for(var/datum/robot_component/C as anything in components.Copy())
		if(!self_repair_gate(R, C))
			components -= C
	if(!length(components))
		return /datum/msg/self_repair/nothing
	icon_state = active_icon
	repairing = TRUE

/obj/item/self_repair_system/proc/self_repair_interval(datum/act/op/A)
	return repair_time

/// A lap is over: everything still being mended heals a little, and pays for the next lap.
/obj/item/self_repair_system/proc/self_repair_lap(datum/act/op/A)
	var/mob/living/silicon/robot/R = A.actor
	var/list/components = A.arg("components")
	for(var/datum/robot_component/C as anything in components.Copy())
		if(C)
			R.mend(TREAT_PLATING_REPAIR, repair_amount, C)
			R.mend(TREAT_WIRING_REPAIR, repair_amount, C)
		if(!self_repair_gate(R, C))
			components -= C

/// Another lap while any component is still being mended.
/obj/item/self_repair_system/proc/self_repair_more(datum/act/op/A)
	return length(A.arg("components")) > 0

/// However it ended, the system is idle again.
/obj/item/self_repair_system/proc/self_repair_finished(datum/act/op/A)
	repairing = FALSE
	icon_state = disabled_icon

// To repair multiple modules
/obj/item/self_repair_system/advanced
	name = "self repair system"
	desc = "A nanite control system to repair damaged components while not moving. Destroyed components can't be restored."
	target_components = list(ROBOT_SLOT_ACTUATOR, ROBOT_SLOT_RADIO, ROBOT_SLOT_POWER, ROBOT_SLOT_DIAGNOSIS, ROBOT_SLOT_CAMERA, ROBOT_SLOT_COMMS, ROBOT_SLOT_ARMOUR)
	power_tick = 10
	repair_time = 15
	repair_amount = 3
