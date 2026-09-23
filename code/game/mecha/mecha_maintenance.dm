/**
 * Exosuit maintenance graph (doc/rewrite/interactions.md §10).
 *
 * Once maintenance protocols are started (the ID card dialog puts `state` at
 * MECHA_BOLTS_SECURED), the securing bolts, the power unit hatch and the cell
 * are construction steps: wrench, crowbar, screwdriver, each reversible. With
 * the cell out, the crowbar pries components out. Welder repair and fixing the
 * temperature controller are ordinary interactions ahead of the graph.
 */
/obj/mecha
	construction_graph = /datum/construction_graph/mecha_maintenance

/datum/construction_graph/mecha_maintenance
	id = "mecha_maintenance"
	state_var = "state"
	states = list(MECHA_BOLTS_SECURED, MECHA_PANEL_LOOSE, MECHA_CELL_OPEN, MECHA_CELL_OUT)
	initial_states = list(MECHA_BOLTS_SECURED)
	edge_types = list(
		/datum/interaction/construction/mecha/undo_bolts,
		/datum/interaction/construction/mecha/tighten_bolts,
		/datum/interaction/construction/mecha/open_hatch,
		/datum/interaction/construction/mecha/close_hatch,
		/datum/interaction/construction/mecha/remove_cell,
		/datum/interaction/construction/mecha/secure_cell,
		/datum/interaction/construction/mecha/pry_component,
	)

/datum/construction_graph/mecha_maintenance/state_of(atom/target)
	var/obj/mecha/mech = target
	if(!istype(mech) || mech.state == MECHA_OPERATING)
		return null
	return mech.state

/datum/construction_graph/mecha_maintenance/on_traversed(atom/target, mob/actor, datum/interaction/construction/edge, before, after)
	return

/// A welder on harm intent attacks the exosuit instead of repairing it.
/obj/mecha/interaction_tool_act(mob/user, obj/item/tool, quality)
	if(quality == TOOL_WELDER && IS_HARMING(user))
		return ITEM_INTERACT_SKIP_TO_ATTACK
	return ..()

/datum/interaction/construction/mecha
	tool_volume = 0

/datum/interaction/construction/mecha/undo_bolts
	from_state = MECHA_BOLTS_SECURED
	to_state = MECHA_PANEL_LOOSE
	step_text = "undo the securing bolts"
	tool = TOOL_WRENCH
	message_self = "You undo the securing bolts."

/datum/interaction/construction/mecha/tighten_bolts
	from_state = MECHA_PANEL_LOOSE
	to_state = MECHA_BOLTS_SECURED
	step_text = "tighten the securing bolts"
	tool = TOOL_WRENCH
	message_self = "You tighten the securing bolts."

/datum/interaction/construction/mecha/open_hatch
	from_state = MECHA_PANEL_LOOSE
	to_state = MECHA_CELL_OPEN
	step_text = "open the hatch to the power unit"
	tool = TOOL_CROWBAR
	message_self = "You open the hatch to the power unit"

/datum/interaction/construction/mecha/close_hatch
	from_state = MECHA_CELL_OPEN
	to_state = MECHA_PANEL_LOOSE
	step_text = "close the hatch to the power unit"
	tool = TOOL_CROWBAR
	message_self = "You close the hatch to the power unit"

/datum/interaction/construction/mecha/remove_cell
	from_state = MECHA_CELL_OPEN
	to_state = MECHA_CELL_OUT
	step_text = "unscrew and pry out the power cell"
	tool = TOOL_SCREWDRIVER
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/mecha/proc/maintenance_has_cell, "there's no power cell"))
	message_self = "You unscrew and pry out the powercell."

/datum/interaction/construction/mecha/remove_cell/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/mecha/mech = target
	mech.cell.forceMove(mech.loc)
	mech.cell = null
	mech.mecha_log_message("Powercell removed")
	return TRUE

/datum/interaction/construction/mecha/secure_cell
	from_state = MECHA_CELL_OUT
	to_state = MECHA_CELL_OPEN
	step_text = "screw the power cell in place"
	tool = TOOL_SCREWDRIVER
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/mecha/proc/maintenance_has_cell, "there's no power cell"))
	message_self = "You screw the cell in place"

/// With the cell out, the crowbar pries out a component. The state doesn't change.
/datum/interaction/construction/mecha/pry_component
	from_state = MECHA_CELL_OUT
	to_state = MECHA_CELL_OUT
	step_text = "pry out a component"
	tool = TOOL_CROWBAR

/datum/interaction/construction/mecha/pry_component/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/mecha/mech = target
	var/list/removable_components = list()
	for(var/slot in mech.internal_components)
		var/obj/item/mecha_parts/component/MC = mech.internal_components[slot]
		if(istype(MC))
			removable_components[MC.name] = MC
		else
			to_chat(actor, span_notice("\The [mech] appears to be missing \the [slot]."))
	var/remove = tgui_input_list(actor, "Which component do you want to pry out?", "Remove Component", removable_components)
	if(!remove || mech.state != MECHA_CELL_OUT)
		return TRUE
	var/obj/item/mecha_parts/component/RmC = removable_components[remove]
	RmC.detach()
	return TRUE

/obj/mecha/proc/maintenance_has_cell(mob/actor, atom/target, obj/item/held)
	return cell ? TRUE : FALSE

// ---------------------------------------------------------------------------
// Repairs ahead of the graph.

/obj/mecha/declare_interactions(list/into)
	..()
	into += list(
		/datum/interaction/mecha_fix_temperature,
		/datum/interaction/mecha_weld_repair,
	)

/datum/interaction/mecha_fix_temperature
	id = "mecha_fix_temperature"
	name = "Repair the temperature controller"
	category = INTERACTION_CAT_REPAIR
	priority = 20
	default_action = INPUT_ACTION_USE
	tool = TOOL_SCREWDRIVER
	tool_volume = 0
	requires = list(REQ_REACH_ADJACENT)
	effect = /obj/mecha/proc/fix_temperature_control
	message_self = "You repair the damaged temperature controller."

/datum/interaction/mecha_fix_temperature/applies_to(atom/target)
	var/obj/mecha/mech = target
	return istype(mech) && mech.hasInternalDamage(MECHA_INT_TEMP_CONTROL)

/obj/mecha/proc/fix_temperature_control(mob/actor, obj/item/held, datum/interaction/interaction)
	clearInternalDamage(MECHA_INT_TEMP_CONTROL)
	return TRUE

/datum/interaction/mecha_weld_repair
	id = "mecha_weld_repair"
	name = "Weld repairs"
	category = INTERACTION_CAT_REPAIR
	priority = 20
	default_action = INPUT_ACTION_USE
	tool = TOOL_WELDER
	tool_volume = 0
	requires = list(REQ_REACH_ADJACENT)
	effect = /obj/mecha/proc/weld_repair

/// Seals a tank breach, then patches 10 integrity: the frame first, then the hull, then the armour.
/obj/mecha/proc/weld_repair(mob/actor, obj/item/held, datum/interaction/interaction)
	var/obj/item/mecha_parts/component/hull/HC = internal_components[MECH_HULL]
	var/obj/item/mecha_parts/component/armor/AC = internal_components[MECH_ARMOR]
	if(hasInternalDamage(MECHA_INT_TANK_BREACH))
		clearInternalDamage(MECHA_INT_TANK_BREACH)
		to_chat(actor, span_notice("You repair the damaged gas tank."))
	if(get_integrity() < max_integrity)
		to_chat(actor, span_notice("You repair some damage to [name]."))
		repair_damage(min(10, max_integrity - get_integrity()))
		update_damage_alerts()
	else if(HC && HC.get_integrity() < HC.max_integrity)
		to_chat(actor, span_notice("You repair some damage to [HC.name]."))
		HC.repair_damage(10)
		update_damage_alerts()
	else if(AC && AC.get_integrity() < AC.max_integrity)
		to_chat(actor, span_notice("You repair some damage to [AC.name]."))
		AC.repair_damage(10)
		update_damage_alerts()
	else
		to_chat(actor, "The [name] is at full integrity")
	return TRUE
