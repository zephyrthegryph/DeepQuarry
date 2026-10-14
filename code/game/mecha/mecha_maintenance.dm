// ---- maintenance, declared ----
//
// Once maintenance protocols are started (the ID card dialog puts `state` at MECHA_BOLTS_SECURED), the securing bolts, the power unit hatch and
// the cell are steps: wrench, crowbar, screwdriver, each reversible. With the cell out, the crowbar pries components out. The mech's `state` var is
// the state (MECHA_OPERATING offers no step), so the steps are ops that read it: mecha_maintenance() is listed in the mech's CAPABILITIES block
// (mecha.dm). Welder repair and fixing the temperature controller are ops above the steps.

MSG_DEF_SELF(mecha/undo_bolts, "You undo the securing bolts.")
MSG_DEF_SELF(mecha/tighten_bolts, "You tighten the securing bolts.")
MSG_DEF_SELF(mecha/open_hatch, "You open the hatch to the power unit")
MSG_DEF_SELF(mecha/close_hatch, "You close the hatch to the power unit")
MSG_DEF_SELF(mecha/remove_cell, "You unscrew and pry out the powercell.")
MSG_DEF_SELF(mecha/secure_cell, "You screw the cell in place")
MSG_DEF_SELF(mecha/no_cell, "There's no power cell.")
MSG_DEF_SELF(mecha/hatch_closed, "The power unit hatch is closed.")
MSG_DEF_SELF(mecha/panel_shut, "You can't reach the internal components.")
MSG_DEF_SELF(mecha/extinguisher_empty, "The extinguisher is empty.")
MSG_DEF_SELF(mecha/fix_temperature, "You repair the damaged temperature controller.")
MSG_DEF_SELF(mecha/seal_tank, "You repair the damaged gas tank.")
MSG_DEF_SELF(mecha/fix_wiring, "You replace the fused wires.")

/// Foam used per extinguishing.
#define MECHA_EXTINGUISH_FOAM 10

/// The maintenance steps and the repairs of an exosuit.
/proc/mecha_maintenance()
	return list(
		op("undo_bolts", tool(TOOL_WRENCH), when(TYPE_PROC_REF(/obj/mecha, maint_bolts_secured)), priority(OP_PRIORITY_PART), label("Undo the securing bolts"), wait(0), says(MSG(mecha/undo_bolts)), then(TYPE_PROC_REF(/obj/mecha, bolts_undone))),
		op("tighten_bolts", tool(TOOL_WRENCH), when(TYPE_PROC_REF(/obj/mecha, maint_panel_loose)), priority(OP_PRIORITY_PART + 1), label("Tighten the securing bolts"), wait(0), says(MSG(mecha/tighten_bolts)), then(TYPE_PROC_REF(/obj/mecha, bolts_tightened))),
		op("open_hatch", tool(TOOL_CROWBAR), when(TYPE_PROC_REF(/obj/mecha, maint_panel_loose)), priority(OP_PRIORITY_PART), label("Open the hatch to the power unit"), wait(0), says(MSG(mecha/open_hatch)), then(TYPE_PROC_REF(/obj/mecha, hatch_opened))),
		op("close_hatch", tool(TOOL_CROWBAR), when(TYPE_PROC_REF(/obj/mecha, maint_cell_open)), priority(OP_PRIORITY_PART + 1), label("Close the hatch to the power unit"), wait(0), says(MSG(mecha/close_hatch)), then(TYPE_PROC_REF(/obj/mecha, hatch_closed))),
		op("remove_cell", tool(TOOL_SCREWDRIVER), when(TYPE_PROC_REF(/obj/mecha, maint_cell_open)), needs(req(TYPE_PROC_REF(/obj/mecha, maintenance_has_cell), because = MSG(mecha/no_cell))), priority(OP_PRIORITY_PART), label("Unscrew and pry out the power cell"), wait(0), says(MSG(mecha/remove_cell)), then(TYPE_PROC_REF(/obj/mecha, cell_removed))),
		op("secure_cell", tool(TOOL_SCREWDRIVER), when(TYPE_PROC_REF(/obj/mecha, maint_cell_out)), needs(req(TYPE_PROC_REF(/obj/mecha, maintenance_has_cell), because = MSG(mecha/no_cell))), priority(OP_PRIORITY_PART + 1), label("Screw the power cell in place"), wait(0), says(MSG(mecha/secure_cell)), then(TYPE_PROC_REF(/obj/mecha, cell_secured))),
		// with the cell out, the crowbar pries out a component; the state doesn't change
		op("pry_component", tool(TOOL_CROWBAR), when(TYPE_PROC_REF(/obj/mecha, maint_cell_out)), priority(OP_PRIORITY_PART + 2), label("Pry out a component"), wait(0), asks(/datum/prompt/choice/mecha_pry_component, fields = list("subject" = computed(TYPE_PROC_REF(/obj/mecha, pry_subject)), "choices" = computed(TYPE_PROC_REF(/obj/mecha, pry_choices))), step = "component"), then(TYPE_PROC_REF(/obj/mecha, component_pry_chosen))),

		// repairs, above the steps: each is offered only while the mech has the affliction it treats
		op("fix_temperature", tool(TOOL_SCREWDRIVER), when(TYPE_PROC_REF(/obj/mecha, temp_control_broken)), priority(OP_PRIORITY_PART + 11), label("Repair the temperature controller"), wait(0), says(MSG(mecha/fix_temperature)), then(TYPE_PROC_REF(/obj/mecha, fix_temperature_control))),
		op("seal_tank", lit_welder(fuel = 0), when(TYPE_PROC_REF(/obj/mecha, tank_breached)), priority(OP_PRIORITY_PART + 12), label("Seal the gas tank"), wait(0), says(MSG(mecha/seal_tank)), then(TYPE_PROC_REF(/obj/mecha, seal_tank))),
		// fused wiring behind the power unit hatch takes two lengths of cable
		op("fix_wiring", stack(/obj/item/stack/cable_coil, 2), when(TYPE_PROC_REF(/obj/mecha, wiring_fused)), needs(req(TYPE_PROC_REF(/obj/mecha, maintenance_hatch_open), because = MSG(mecha/hatch_closed))), priority(OP_PRIORITY_PART + 11), label("Replace the fused wires"), wait(0), says(MSG(mecha/fix_wiring)), then(TYPE_PROC_REF(/obj/mecha, fix_wiring))),
		op("extinguish", item(/obj/item/extinguisher), when(TYPE_PROC_REF(/obj/mecha, internal_fire)), needs(req(TYPE_PROC_REF(/obj/mecha, extinguisher_has_foam), because = MSG(mecha/extinguisher_empty))), priority(OP_PRIORITY_PART + 11), label("Extinguish the internal fire"), wait(0), then(TYPE_PROC_REF(/obj/mecha, extinguish_internal_fire))),
		// weld repairs, outside combat mode (one op per stance); in combat mode the welder strikes instead
		op("weld_repair", lit_welder(fuel = 0), stance(I_HELP, I_DISARM, I_GRAB), priority(OP_PRIORITY_PART + 11), label("Weld repairs"), wait(0), then(TYPE_PROC_REF(/obj/mecha, weld_repair))),
		// a strike, not a tool job: no lit-welder check, no fuel, no sound
		op("weld_strike", tool(TOOL_WELDER), stance(I_HURT), priority(OP_PRIORITY_PART + 11), label("Strike"), wait(0), costs(RES_FUEL, 0), then(TYPE_PROC_REF(/obj/mecha, weld_strike))),
		// nanopaste repairs every damaged component once the securing bolts are undone
		op("paste_repair", item(/obj/item/stack/nanopaste), needs(req(TYPE_PROC_REF(/obj/mecha, maintenance_panel_loose), because = MSG(mecha/panel_shut))), priority(OP_PRIORITY_PART + 11), label("Repair components with nanopaste"), wait(0), then(TYPE_PROC_REF(/obj/mecha, paste_repair))))

// ---- the state a step leaves from ----

/obj/mecha/proc/maint_bolts_secured(datum/act/A)
	return state == MECHA_BOLTS_SECURED

/obj/mecha/proc/maint_panel_loose(datum/act/A)
	return state == MECHA_PANEL_LOOSE

/obj/mecha/proc/maint_cell_open(datum/act/A)
	return state == MECHA_CELL_OPEN

/obj/mecha/proc/maint_cell_out(datum/act/A)
	return state == MECHA_CELL_OUT

/// The mech has a power cell to take out or screw in.
/obj/mecha/proc/maintenance_has_cell(datum/act/A)
	return cell ? null : MSG(mecha/no_cell)

/// The power unit hatch is open (short-circuit wiring is behind it).
/obj/mecha/proc/maintenance_hatch_open(datum/act/A)
	return state >= MECHA_CELL_OPEN ? null : MSG(mecha/hatch_closed)

/// The securing bolts are undone (components are reachable).
/obj/mecha/proc/maintenance_panel_loose(datum/act/A)
	return state >= MECHA_PANEL_LOOSE ? null : MSG(mecha/panel_shut)

// ---- the steps ----

/obj/mecha/proc/bolts_undone(datum/act/op/A)
	set_state(MECHA_PANEL_LOOSE)
	return OP_OK

/obj/mecha/proc/bolts_tightened(datum/act/op/A)
	set_state(MECHA_BOLTS_SECURED)
	return OP_OK

/obj/mecha/proc/hatch_opened(datum/act/op/A)
	set_state(MECHA_CELL_OPEN)
	return OP_OK

/obj/mecha/proc/hatch_closed(datum/act/op/A)
	set_state(MECHA_PANEL_LOOSE)
	return OP_OK

/obj/mecha/proc/cell_removed(datum/act/op/A)
	set_state(MECHA_CELL_OUT)
	cell.forceMove(loc)
	rel_take(src, nameof(cell))
	mecha_log_message("Powercell removed")
	return OP_OK

/obj/mecha/proc/cell_secured(datum/act/op/A)
	set_state(MECHA_CELL_OPEN)
	return OP_OK

/// Which mech the pry question is about.
/obj/mecha/proc/pry_subject(datum/act/op/A)
	return src

/// The components that can come out: name -> component.
/obj/mecha/proc/pry_choices(datum/act/op/A)
	var/list/removable_components = list()
	for(var/slot in internal_components)
		var/obj/item/mecha_parts/component/MC = internal_components[slot]
		if(istype(MC))
			removable_components[MC.name] = MC
	return removable_components

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
	var/obj/mecha/mech = subject || owner
	return mech.state == MECHA_CELL_OUT ? null : "cell not out"

/obj/mecha/proc/component_pry_chosen(datum/act/op/A)
	for(var/slot in internal_components)
		if(!istype(internal_components[slot], /obj/item/mecha_parts/component))
			to_chat(A.actor, span_notice("\The [src] appears to be missing \the [slot]."))
	var/obj/item/mecha_parts/component/RmC = pry_choices(A)[A.step_value("component")]
	if(!RmC)
		log_world("MECHA: pry_component on [src] by [A.actor]: the chosen component is gone")
		return OP_FAILED
	RmC.detach()
	return OP_OK

// ---- repairs ----

/// The mech has the affliction `treats`.
/obj/mecha/proc/afflicted_with(treats)
	return mech_body_plan().has_affliction(src, treats)

/obj/mecha/proc/temp_control_broken(datum/act/A)
	return afflicted_with(MECHA_INT_TEMP_CONTROL)

/obj/mecha/proc/tank_breached(datum/act/A)
	return afflicted_with(MECHA_INT_TANK_BREACH)

/obj/mecha/proc/wiring_fused(datum/act/A)
	return afflicted_with(MECHA_INT_SHORT_CIRCUIT)

/obj/mecha/proc/internal_fire(datum/act/A)
	return afflicted_with(MECHA_INT_FIRE)

/obj/mecha/proc/control_lost(datum/act/A)
	return afflicted_with(MECHA_INT_CONTROL_LOST)

/obj/mecha/proc/fix_temperature_control(datum/act/op/A)
	mech_body_plan().cure(src, MECHA_INT_TEMP_CONTROL)
	return OP_OK

/obj/mecha/proc/seal_tank(datum/act/op/A)
	mech_body_plan().cure(src, MECHA_INT_TANK_BREACH)
	return OP_OK

/obj/mecha/proc/fix_wiring(datum/act/op/A)
	mech_body_plan().cure(src, MECHA_INT_SHORT_CIRCUIT)
	return OP_OK

/// The extinguisher has enough foam left.
/obj/mecha/proc/extinguisher_has_foam(datum/act/op/A)
	var/obj/item/extinguisher/held = A.held
	return (istype(held) && held.reagents && held.reagents.total_volume >= MECHA_EXTINGUISH_FOAM) ? null : MSG(mecha/extinguisher_empty)

/obj/mecha/proc/extinguish_internal_fire(datum/act/op/A)
	var/obj/item/extinguisher/held = A.held
	held.reagents.remove_any(MECHA_EXTINGUISH_FOAM)
	play_sfx(src, SFX_EFFECTS_EXTINGUISH, volume = 50, extrarange = 0)
	to_chat(A.actor, span_notice("You flood \the [src]'s internals with foam."))
	mech_body_plan().cure(src, MECHA_INT_FIRE)
	return OP_OK

#undef MECHA_EXTINGUISH_FOAM

/obj/mecha/proc/weld_strike(datum/act/op/A)
	dynattackby(A.held, A.actor)
	return OP_OK

/// Patches 10 integrity: the frame first, then the hull, then the armour plates.
/obj/mecha/proc/weld_repair(datum/act/op/A)
	var/mob/actor = A.actor
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
	return OP_OK

/// Nanopaste repairs every damaged component once the securing bolts are undone.
/obj/mecha/proc/paste_repair(datum/act/op/A)
	var/mob/actor = A.actor
	var/obj/item/stack/nanopaste/held = A.held
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
	return OP_OK

/// The pilot recalibrates the coordination system (control damage) from the cockpit. Recalibration takes 10 seconds and fails if the mech moves
/// meanwhile (recalibration_done()).
/obj/mecha/proc/start_recalibration(datum/act/op/A)
	occupant_message("Recalibrating coordination system.")
	mecha_log_message("Recalibration of coordination system started.")
	after(src, 10 SECONDS, PROC_REF(recalibration_done), with = list(loc))
	return OP_OK
