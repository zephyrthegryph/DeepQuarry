// Cyborg damage lives on the robot body (plans/machine.dm): injuries become
// load afflictions located on a part; a part's damage is the load located on
// it (component.dm). This file keeps the robot-side helpers.

/// Upgraded parts (e.g. armour_platform) make the chassis tougher: every
/// point of max_damage above the stock part adds a point of endurance.
/mob/living/silicon/robot/get_endurance()
	. = ..()
	if(!istype(body, /datum/body/simple/machine/robot))
		return // drones: whole-body load, parts don't add toughness
	for(var/datum/robot_component/C as anything in components)
		. += C.max_damage - initial(C.max_damage)

/// Parts that are damaged, faulted, switched off or unpowered.
/mob/living/silicon/robot/proc/get_faulted_components(include_destroyed = FALSE)
	var/list/datum/robot_component/parts = list()
	for(var/datum/robot_component/C as anything in components)
		if(C.installed == ROBOT_PART_DESTROYED)
			if(include_destroyed)
				parts += C
			continue
		if(C.installed != ROBOT_PART_INSTALLED)
			continue
		if(C.get_total_damage() || !C.toggled || !C.is_powered() || length(C.get_afflictions()))
			parts += C
	return parts

/mob/living/silicon/robot/proc/get_armour()
	var/datum/robot_component/C = get_component(ROBOT_SLOT_ARMOUR)
	if(C?.installed == ROBOT_PART_INSTALLED)
		return C
	return null

/// Combat shielding absorbs a percentage of physical and thermal injury
/// directly into the cell.
/mob/living/silicon/robot/proc/absorb_injury_with_shield(datum/source, kind, list/amount_ref, zone, atom/injury_source, flags)
	SIGNAL_HANDLER
	var/category = injury_category(kind)
	if(category != INJURY_CATEGORY_PHYSICAL && category != INJURY_CATEGORY_THERMAL)
		return NONE
	if(!has_active_type(/obj/item/borg/combat/shield))
		return NONE
	var/obj/item/borg/combat/shield/shield = locate() in src
	if(!shield?.active)
		return NONE
	var/absorbed = amount_ref[1] * shield.shield_level
	if(!draw_power(ROBOT_CELL_JOULES(absorbed * 25), shield, ROBOT_CELL_JOULES(200)))
		to_chat(src, span_filter_warning(span_red("Your shield has overloaded!")))
		return NONE
	amount_ref[1] -= absorbed
	to_chat(src, span_filter_combat(span_red("Your shield absorbs some of the impact!")))
	return NONE

/// One EMP, one pass. Blocking components are asked first; the parent (which
/// pulses contents and applies the power-fault injury) runs exactly once.
/// The cell is shielded from content recursion (set_cell()) and drained here
/// through the ledger instead.
/mob/living/silicon/robot/emp_act(severity, recursive)
	if(SEND_SIGNAL(src, COMSIG_ROBOT_EMP_ACT, severity) & COMPONENT_BLOCK_EMP)
		return EMP_PROTECT_SELF
	. = ..()
	if(. & EMP_PROTECT_SELF)
		return
	uneq_all()
	emp_drain_cell(severity)

/mob/living/silicon/robot/proc/emp_drain_cell(severity)
	if(!cell || severity <= 0)
		return
	var/resistance = 1 - cell.material_emp_resistance / 100
	var/drained_units = cell.charge / (severity * cell_emp_mult) * resistance
	if(drained_units > 0)
		draw_power(ROBOT_CELL_JOULES(drained_units), src, 0, TRUE)
	log_runtime("ROBOT_EMP: [key_name(src)] severity [severity] drained [round(drained_units)] cell units.")

/// EMP surges bypass the armour plating and land on an internal-facing part;
/// the power fault itself goes to the power bus (its home slot).
/mob/living/silicon/robot/emp_injury_zone()
	var/datum/body/simple/machine/robot/B = body
	return istype(B) ? B.pick_damageable_component(TRUE) : null
