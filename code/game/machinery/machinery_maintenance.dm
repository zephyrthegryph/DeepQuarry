/**
 * The Maintainable behaviour (doc/rewrite/interactions.md §6): open the
 * maintenance panel, secure or unsecure, deconstruct and weld-repair.
 *
 * Every machine declares these four interactions; `maintenance_flags`
 * (MACHINE_MAINT_*) says which of them a machine type offers. They replace the
 * generic screwdriver/crowbar/wrench/welder *_act procs that used to live on
 * /obj/machinery. Subtype *_act overrides that call ..() still reach them,
 * through the atom-level *_act procs (see interaction_tool_act()).
 */
/obj/machinery/declare_interactions(list/into)
	..()
	into += list(
		/datum/interaction/maintainable/panel,
		/datum/interaction/maintainable/deconstruct,
		/datum/interaction/maintainable/anchor,
		/datum/interaction/maintainable/repair,
	)

/// Abstract: an interaction offered when the machine has `maintenance_flag`.
/datum/interaction/maintainable
	category = INTERACTION_CAT_MAINTAIN
	default_action = INPUT_ACTION_USE
	tags = list(INTERACTION_TAG_MAINTENANCE)
	/// The MACHINE_MAINT_* flag that offers this interaction.
	var/maintenance_flag = NONE

/datum/interaction/maintainable/applies_to(atom/target)
	if(!istype(target, /obj/machinery))
		return FALSE
	var/obj/machinery/machine = target
	return (machine.maintenance_flags & maintenance_flag) ? TRUE : FALSE

// ---- Open or close the maintenance panel ----

/datum/interaction/maintainable/panel
	id = "machine_panel"
	name = "Open maintenance panel"
	priority = 20
	tool = TOOL_SCREWDRIVER
	maintenance_flag = MACHINE_MAINT_PANEL
	requires = list(REQ_REACH_ADJACENT)
	effect = /obj/machinery/proc/toggle_maintenance_panel

/datum/interaction/maintainable/panel/display_name(mob/actor, atom/target)
	var/obj/machinery/machine = target
	return machine.panel_open ? "Close maintenance panel" : "Open maintenance panel"

/datum/interaction/maintainable/panel/feedback_for(mob/actor, atom/target, obj/item/held)
	var/obj/machinery/machine = target
	return machine.panel_open ? /datum/msg/interaction/maintenance_panel/close : /datum/msg/interaction/maintenance_panel/open

MSG_DEF_SELF(interaction/maintenance_panel/open, "You open the maintenance hatch of %T%.")
MSG_DEF_SELF(interaction/maintenance_panel/close, "You close the maintenance hatch of %T%.")

/obj/machinery/proc/toggle_maintenance_panel(mob/actor, obj/item/held, datum/interaction/interaction)
	set_panel_open(!panel_open)
	update_icon()
	return TRUE

// ---- Deconstruct ----

/datum/interaction/maintainable/deconstruct
	id = "machine_deconstruct"
	name = "Deconstruct"
	priority = 15
	tool = TOOL_CROWBAR
	maintenance_flag = MACHINE_MAINT_FRAME
	requires = list(
		REQ_REACH_ADJACENT,
		REQ_ON(PRED_TARGET, /obj/machinery/proc/maintenance_panel_is_open, "the maintenance panel is closed"),
	)
	effect = /obj/machinery/proc/maintenance_deconstruct

/obj/machinery/proc/maintenance_deconstruct(mob/actor, obj/item/held, datum/interaction/interaction)
	return dismantle() ? TRUE : FALSE

// ---- Secure or unsecure ----

/datum/interaction/maintainable/anchor
	id = "machine_anchor"
	name = "Secure"
	priority = 10
	tool = TOOL_WRENCH
	maintenance_flag = MACHINE_MAINT_WRENCH
	requires = list(
		REQ_REACH_ADJACENT,
		REQ_ON(PRED_TARGET, /obj/machinery/proc/maintenance_panel_is_closed, "the maintenance panel is open"),
	)
	effect = /obj/machinery/proc/toggle_maintenance_anchor

/datum/interaction/maintainable/anchor/display_name(mob/actor, atom/target)
	var/obj/machinery/machine = target
	return machine.anchored ? "Unsecure" : "Secure"

/datum/interaction/maintainable/anchor/duration_for(mob/actor, atom/target, obj/item/held)
	var/obj/machinery/machine = target
	return tool_delay(actor, held, machine.maintenance_wrench_time, tool)

/datum/interaction/maintainable/anchor/start_feedback_for(mob/actor, atom/target, obj/item/held)
	var/obj/machinery/machine = target
	return machine.anchored ? /datum/msg/start/interaction/machine_anchor/unsecure : /datum/msg/start/interaction/machine_anchor/secure

/datum/interaction/maintainable/anchor/feedback_for(mob/actor, atom/target, obj/item/held)
	var/obj/machinery/machine = target
	return machine.anchored ? /datum/msg/interaction/machine_anchor/unsecure : /datum/msg/interaction/machine_anchor/secure

MSG_DEF(start/interaction/machine_anchor/secure, "You start securing %T%.", "%U% begins securing %T%.")
MSG_DEF(start/interaction/machine_anchor/unsecure, "You start unsecuring %T%.", "%U% begins unsecuring %T%.")
MSG_DEF(interaction/machine_anchor/secure, "You secure %T%.", "%U% has secured %T%.")
MSG_DEF(interaction/machine_anchor/unsecure, "You unsecure %T%.", "%U% has unsecured %T%.")

/obj/machinery/proc/toggle_maintenance_anchor(mob/actor, obj/item/held, datum/interaction/interaction)
	set_anchored(!anchored)
	power_change()
	update_icon()
	return TRUE

// ---- Weld repair ----

/datum/interaction/maintainable/repair
	id = "machine_repair"
	name = "Repair"
	category = INTERACTION_CAT_REPAIR
	priority = 10
	tool = TOOL_WELDER
	maintenance_flag = MACHINE_MAINT_WELDER_REPAIR
	requires = list(
		REQ_REACH_ADJACENT,
		REQ_ON(PRED_TARGET, /obj/machinery/proc/maintenance_is_damaged, "it isn't damaged"),
		REQ_PROC(/proc/dq_held_welder_lit, "the welding tool must be on"),
	)
	effect = /obj/machinery/proc/maintenance_repair
	feedback = /datum/msg/interaction/machine_repair

/datum/interaction/maintainable/repair/duration_for(mob/actor, atom/target, obj/item/held)
	var/obj/machinery/machine = target
	return tool_delay(actor, held, machine.maintenance_weld_time, tool)

MSG_DEF(interaction/machine_repair, "You repair %T%.", "%U% repairs %T%.")

/obj/machinery/proc/maintenance_repair(mob/actor, obj/item/held, datum/interaction/interaction)
	repair_damage(max_integrity)
	return TRUE

// ---- Target state ----

/obj/machinery/proc/maintenance_panel_is_open(mob/actor, atom/target, obj/item/held)
	return panel_open ? TRUE : FALSE

/obj/machinery/proc/maintenance_panel_is_closed(mob/actor, atom/target, obj/item/held)
	return panel_open ? FALSE : TRUE

/obj/machinery/proc/maintenance_is_damaged(mob/actor, atom/target, obj/item/held)
	return uses_integrity && get_integrity() < max_integrity

/// Predicate clause: the held item is (or contains) a lit welding tool.
/proc/dq_held_welder_lit(mob/actor, atom/target, obj/item/held)
	var/obj/item/weldingtool/welder = held?.get_welder()
	return welder?.isOn() ? TRUE : FALSE
