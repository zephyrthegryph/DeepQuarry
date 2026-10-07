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

/// The state is a tracked var: written through its setter so the guards that read it see the change.
/datum/construction_graph/mecha_maintenance/set_state(atom/target, state)
	var/obj/mecha/mech = target
	if(istype(mech) && state != CONSTRUCTION_DONE)
		mech.set_state(state)

/datum/construction_graph/mecha_maintenance/on_traversed(atom/target, mob/actor, datum/interaction/construction/edge, before, after)
	return

/datum/interaction/construction/mecha
	tool_volume = 0

/datum/interaction/construction/mecha/undo_bolts
	feedback = /datum/msg/interaction/construction/mecha/undo_bolts
	from_state = MECHA_BOLTS_SECURED
	to_state = MECHA_PANEL_LOOSE
	step_text = "undo the securing bolts"
	tool = TOOL_WRENCH

/datum/msg/interaction/construction/mecha/undo_bolts
	self = "You undo the securing bolts."

/datum/interaction/construction/mecha/tighten_bolts
	feedback = /datum/msg/interaction/construction/mecha/tighten_bolts
	from_state = MECHA_PANEL_LOOSE
	to_state = MECHA_BOLTS_SECURED
	step_text = "tighten the securing bolts"
	tool = TOOL_WRENCH

/datum/msg/interaction/construction/mecha/tighten_bolts
	self = "You tighten the securing bolts."

/datum/interaction/construction/mecha/open_hatch
	feedback = /datum/msg/interaction/construction/mecha/open_hatch
	from_state = MECHA_PANEL_LOOSE
	to_state = MECHA_CELL_OPEN
	step_text = "open the hatch to the power unit"
	tool = TOOL_CROWBAR

/datum/msg/interaction/construction/mecha/open_hatch
	self = "You open the hatch to the power unit"

/datum/interaction/construction/mecha/close_hatch
	feedback = /datum/msg/interaction/construction/mecha/close_hatch
	from_state = MECHA_CELL_OPEN
	to_state = MECHA_PANEL_LOOSE
	step_text = "close the hatch to the power unit"
	tool = TOOL_CROWBAR

/datum/msg/interaction/construction/mecha/close_hatch
	self = "You close the hatch to the power unit"

/datum/interaction/construction/mecha/remove_cell
	feedback = /datum/msg/interaction/construction/mecha/remove_cell
	from_state = MECHA_CELL_OPEN
	to_state = MECHA_CELL_OUT
	step_text = "unscrew and pry out the power cell"
	tool = TOOL_SCREWDRIVER
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/mecha/proc/maintenance_has_cell, "there's no power cell"))

/datum/msg/interaction/construction/mecha/remove_cell
	self = "You unscrew and pry out the powercell."

/datum/interaction/construction/mecha/remove_cell/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/mecha/mech = target
	mech.cell.forceMove(mech.loc)
	rel_take(mech, nameof(mech.cell))
	mech.mecha_log_message("Powercell removed")
	return TRUE

/datum/interaction/construction/mecha/secure_cell
	feedback = /datum/msg/interaction/construction/mecha/secure_cell
	from_state = MECHA_CELL_OUT
	to_state = MECHA_CELL_OPEN
	step_text = "screw the power cell in place"
	tool = TOOL_SCREWDRIVER
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/mecha/proc/maintenance_has_cell, "there's no power cell"))

/datum/msg/interaction/construction/mecha/secure_cell
	self = "You screw the cell in place"

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
	open_request(mech, /datum/prompt/choice/mecha_pry_component, TYPE_PROC_REF(/obj/mecha, component_pry_chosen), answerer = actor, subject = mech, choices = removable_components)
	return TRUE

/// Re-checked on the answer: still next to the mech, its cell still out.
/datum/prompt/choice/mecha_pry_component
	title = "Remove Component"
	question = "Which component do you want to pry out?"
	timeout = 0
	ask_flags = ASK_ADJACENT | ASK_CAPABLE

/datum/prompt/choice/mecha_pry_component/recheck_extra()
	. = ..()
	if(.)
		return
	var/obj/mecha/mech = subject
	return mech.state == MECHA_CELL_OUT ? null : "cell not out"

/obj/mecha/proc/component_pry_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return component_pry_apply(A)

/obj/mecha/proc/component_pry_apply(datum/act/request/A)
	var/datum/prompt/choice/mecha_pry_component/ask = A.answer
	var/obj/item/mecha_parts/component/RmC = ask.choices[ask.value]
	RmC.detach()
	return TRUE

/obj/mecha/proc/maintenance_has_cell(mob/actor, atom/target, obj/item/held)
	return cell ? TRUE : FALSE
// ---------------------------------------------------------------------------
// Repairs ahead of the graph. Each one treats a body part or an affliction of the
// mech body plan (code/modules/body/mech_body.dm).

/obj/mecha/declare_interactions(list/into)
	..()
	into += list(
		/datum/interaction/mecha_treat/fix_temperature,
		/datum/interaction/mecha_treat/seal_tank,
		/datum/interaction/mecha_weld_repair/help,
		/datum/interaction/mecha_weld_repair/disarm,
		/datum/interaction/mecha_weld_repair/grab,
		/datum/interaction/mecha_weld_strike,
		/datum/interaction/mecha_treat/fix_wiring,
		/datum/interaction/mecha_treat/extinguish,
		/datum/interaction/mecha_paste_repair,
		/datum/interaction/mecha_treat/recalibrate,
	)

/// The power unit hatch is open (short-circuit wiring is behind it).
/obj/mecha/proc/maintenance_hatch_open(mob/actor, atom/target, obj/item/held)
	return state >= MECHA_CELL_OPEN

/// The securing bolts are undone (components are reachable).
/obj/mecha/proc/maintenance_panel_loose(mob/actor, atom/target, obj/item/held)
	return state >= MECHA_PANEL_LOOSE

/// Base for repairs that treat one affliction: offered only while the mech has it.
/datum/interaction/mecha_treat
	category = INTERACTION_CAT_REPAIR
	priority = 20
	default_action = INPUT_ACTION_USE
	tool_volume = 0
	requires = list(REQ_REACH_ADJACENT)
	/// MECHA_INT_* affliction this repair treats.
	var/treats

/datum/interaction/mecha_treat/applies_to(atom/target)
	var/obj/mecha/mech = target
	return istype(mech) && mech_body_plan().has_affliction(mech, treats)

/datum/interaction/mecha_treat/fix_temperature
	feedback = /datum/msg/interaction/mecha_treat/fix_temperature
	id = "mecha_fix_temperature"
	name = "Repair the temperature controller"
	tool = TOOL_SCREWDRIVER
	treats = MECHA_INT_TEMP_CONTROL
	effect = /obj/mecha/proc/fix_temperature_control

/datum/msg/interaction/mecha_treat/fix_temperature
	self = "You repair the damaged temperature controller."

/obj/mecha/proc/fix_temperature_control(mob/actor, obj/item/held, datum/interaction/interaction)
	return mech_body_plan().cure(src, MECHA_INT_TEMP_CONTROL)

/// A welder seals a breached tank before it patches anything else.
/datum/interaction/mecha_treat/seal_tank
	feedback = /datum/msg/interaction/mecha_treat/seal_tank
	id = "mecha_seal_tank"
	name = "Seal the gas tank"
	priority = 25
	tool = TOOL_WELDER
	treats = MECHA_INT_TANK_BREACH
	effect = /obj/mecha/proc/seal_tank

/datum/msg/interaction/mecha_treat/seal_tank
	self = "You repair the damaged gas tank."

/obj/mecha/proc/seal_tank(mob/actor, obj/item/held, datum/interaction/interaction)
	return mech_body_plan().cure(src, MECHA_INT_TANK_BREACH)

/// Fused wiring behind the power unit hatch takes two lengths of cable.
/datum/interaction/mecha_treat/fix_wiring
	feedback = /datum/msg/interaction/mecha_treat/fix_wiring
	id = "mecha_fix_wiring"
	name = "Replace the fused wires"
	tool = TOOL_CABLE_COIL
	tool_amount = 2
	treats = MECHA_INT_SHORT_CIRCUIT
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/mecha/proc/maintenance_hatch_open, "the power unit hatch is closed"))
	effect = /obj/mecha/proc/fix_wiring

/datum/msg/interaction/mecha_treat/fix_wiring
	self = "You replace the fused wires."

/obj/mecha/proc/fix_wiring(mob/actor, obj/item/held, datum/interaction/interaction)
	return mech_body_plan().cure(src, MECHA_INT_SHORT_CIRCUIT)

/// An extinguisher puts out an internal fire.
/datum/interaction/mecha_treat/extinguish
	id = "mecha_extinguish"
	name = "Extinguish the internal fire"
	held_type = /obj/item/extinguisher
	treats = MECHA_INT_FIRE
	also_requires = list(REQ_TARGET_STATE(/obj/mecha/proc/can_extinguish_internal_fire))
	effect = /obj/mecha/proc/extinguish_internal_fire

/// Foam used per extinguishing.
#define MECHA_EXTINGUISH_FOAM 10

/// Requirement: the extinguisher needs enough foam left.
/obj/mecha/proc/can_extinguish_internal_fire(mob/actor, atom/target, obj/item/extinguisher/held)
	if(!istype(held) || !held.reagents || held.reagents.total_volume < MECHA_EXTINGUISH_FOAM)
		return "[held] is empty"
	return TRUE

/obj/mecha/proc/extinguish_internal_fire(mob/actor, obj/item/extinguisher/held, datum/interaction/interaction)
	held.reagents.remove_any(MECHA_EXTINGUISH_FOAM)
	play_sfx(src, SFX_EFFECTS_EXTINGUISH, volume = 50, extrarange = 0)
	to_chat(actor, span_notice("You flood \the [src]'s internals with foam."))
	mech_body_plan().cure(src, MECHA_INT_FIRE)
	return TRUE

#undef MECHA_EXTINGUISH_FOAM

/// Abstract: weld repairs, outside combat mode (one per stance). In combat mode the welder strikes instead.
/datum/interaction/mecha_weld_repair
	name = "Weld repairs"
	category = INTERACTION_CAT_REPAIR
	priority = 20
	default_action = INPUT_ACTION_USE
	tool = TOOL_WELDER
	tool_volume = 0
	requires = list(REQ_REACH_ADJACENT)
	effect = /obj/mecha/proc/weld_repair

/datum/interaction/mecha_weld_repair/help
	id = "mecha_weld_repair"
	stance = I_HELP

/datum/interaction/mecha_weld_repair/disarm
	id = "mecha_weld_repair_disarm"
	stance = I_DISARM

/datum/interaction/mecha_weld_repair/grab
	id = "mecha_weld_repair_grab"
	stance = I_GRAB

/// Combat mode: a welder attacks the exosuit instead of repairing it (lit or not).
/datum/interaction/mecha_weld_strike
	id = "mecha_weld_strike"
	name = "Strike"
	category = INTERACTION_CAT_ATTACK
	priority = 20
	default_action = INPUT_ACTION_USE
	stance = I_HURT
	tool = TOOL_WELDER
	tool_volume = 0
	requires = list(REQ_REACH_ADJACENT)
	effect = /obj/mecha/proc/weld_strike

/// A strike, not a tool job: no lit-welder check, no fuel, no sound.
/datum/interaction/mecha_weld_strike/pay_cost(mob/actor, atom/target, obj/item/held)
	return TRUE

/obj/mecha/proc/weld_strike(mob/actor, obj/item/held, datum/interaction/interaction)
	dynattackby(held, actor)
	return TRUE

/// Patches 10 integrity: the frame first, then the hull, then the armour plates.
/obj/mecha/proc/weld_repair(mob/actor, obj/item/held, datum/interaction/interaction)
	var/datum/mech_body_plan/plan = mech_body_plan()
	var/obj/item/mecha_parts/component/hull/HC = plan.part(src, MECH_HULL)
	var/obj/item/mecha_parts/component/armor/AC = plan.part(src, MECH_ARMOR)
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

/// Nanopaste repairs every damaged component once the securing bolts are undone.
/datum/interaction/mecha_paste_repair
	id = "mecha_paste_repair"
	name = "Repair components with nanopaste"
	category = INTERACTION_CAT_REPAIR
	priority = 20
	default_action = INPUT_ACTION_USE
	held_type = /obj/item/stack/nanopaste
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/mecha/proc/maintenance_panel_loose, "you can't reach the internal components"))
	effect = /obj/mecha/proc/paste_repair

/obj/mecha/proc/paste_repair(mob/actor, obj/item/stack/nanopaste/held, datum/interaction/interaction)
	var/datum/mech_body_plan/plan = mech_body_plan()
	var/any_part = FALSE
	for(var/slot in TYPE_TABLE_GET(plan, part_order))
		var/obj/item/mecha_parts/component/C = plan.part(src, slot)
		if(!C)
			continue
		any_part = TRUE
		if(C.get_integrity() >= C.max_integrity)
			to_chat(actor, span_notice("\The [C] does not require repairs."))
			continue
		to_chat(actor, span_notice("You start to repair damage to \the [C]."))
		C.paste_repair_step(actor, held, src)
	if(!any_part)
		to_chat(actor, span_notice("There are no components installed!"))
	return TRUE

/// The pilot recalibrates the coordination system (control damage) from the cockpit. The
/// cockpit panel's "Recalibrate" action runs this interaction; it has no click action.
/datum/interaction/mecha_treat/recalibrate
	id = "mecha_recalibrate"
	name = "Recalibrate the coordination system"
	default_action = null
	treats = MECHA_INT_CONTROL_LOST
	requires = list(REQ_ON(PRED_TARGET, /obj/mecha/proc/pred_mecha_pilot, "only the pilot can recalibrate"))
	effect = /obj/mecha/proc/start_recalibration

/// Recalibration takes 10 seconds and fails if the mech moves meanwhile (recalibration_done()).
/obj/mecha/proc/start_recalibration(mob/actor, obj/item/held, datum/interaction/interaction)
	occupant_message("Recalibrating coordination system.")
	mecha_log_message("Recalibration of coordination system started.")
	after(src, 10 SECONDS, PROC_REF(recalibration_done), with = list(loc))
	return TRUE
