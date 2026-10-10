/**
 * The Maintainable behaviour (doc/rewrite/interactions.md §6): open the maintenance panel, secure or unsecure, deconstruct and weld-repair.
 *
 * Ops of every machine (the `maintenance` section of CAPABILITIES(/obj/machinery), machinery.dm); `maintenance_flags` (MACHINE_MAINT_*) says
 * which of them a machine type offers. They answer after a type's own tool ops (OP_PRIORITY_DEFAULT: what a subtype's *_act override did before
 * its ..()) and before its catch-alls for any item (the same tier as those, OP_PRIORITY_DEFAULT - 1, where a tool binding is the more specific).
 * A type's tool op that hands the click on (OP_DECLINE) lets these answer, as its old *_act's ..() did.
 */

MSG_DEF_SELF(interaction/maintenance_panel/open, "You open the maintenance hatch of %T%.")
MSG_DEF_SELF(interaction/maintenance_panel/close, "You close the maintenance hatch of %T%.")
MSG_DEF_SELF(interaction/maintenance_panel/closed, "the maintenance panel is closed")
MSG_DEF_SELF(interaction/maintenance_panel/opened, "the maintenance panel is open")
MSG_DEF(start/interaction/machine_anchor/secure, "You start securing %T%.", "%U% begins securing %T%.")
MSG_DEF(start/interaction/machine_anchor/unsecure, "You start unsecuring %T%.", "%U% begins unsecuring %T%.")
MSG_DEF(interaction/machine_anchor/secure, "You secure %T%.", "%U% has secured %T%.")
MSG_DEF(interaction/machine_anchor/unsecure, "You unsecure %T%.", "%U% has unsecured %T%.")
MSG_DEF(interaction/machine_repair, "You repair %T%.", "%U% repairs %T%.")
MSG_DEF_SELF(interaction/machine_repair/intact, "it isn't damaged")

// ---- which of them the machine offers ----

/obj/machinery/proc/maint_offers_panel(datum/act/op/A)
	return !!(maintenance_flags & MACHINE_MAINT_PANEL)

/obj/machinery/proc/maint_offers_frame(datum/act/op/A)
	return !!(maintenance_flags & MACHINE_MAINT_FRAME)

/obj/machinery/proc/maint_offers_wrench(datum/act/op/A)
	return !!(maintenance_flags & MACHINE_MAINT_WRENCH)

/obj/machinery/proc/maint_offers_repair(datum/act/op/A)
	return !!(maintenance_flags & MACHINE_MAINT_WELDER_REPAIR)

// ---- the panel ----

/// Opens or closes the maintenance panel (the panel's two ops, one per state).
/obj/machinery/proc/toggle_maintenance_panel(datum/act/op/A)
	set_panel_open(!panel_open)
	update_icon()
	return OP_OK

// ---- deconstruct ----

/// Takes the machine apart; a machine that would not come apart hands the click on.
/obj/machinery/proc/maintenance_deconstruct(datum/act/op/A)
	return dismantle() ? OP_OK : OP_DECLINE

// ---- secure or unsecure ----

/// The wrench's wait: the machine's own time (the op scales it by the tool's speed).
/obj/machinery/proc/maintenance_wrench_wait(datum/act/op/A)
	return maintenance_wrench_time

/obj/machinery/proc/toggle_maintenance_anchor(datum/act/op/A)
	set_anchored(!anchored)
	power_change()
	update_icon()
	return OP_OK

// ---- weld repair ----

/// The welder's wait: the machine's own time (the op scales it by the tool's speed).
/obj/machinery/proc/maintenance_weld_wait(datum/act/op/A)
	return maintenance_weld_time

/// Requirement of the repair: the machine is damaged.
/obj/machinery/proc/maintenance_is_damaged(datum/act/op/A)
	return (uses_integrity && get_integrity_damage() > 0) ? null : MSG(interaction/machine_repair/intact)

/obj/machinery/proc/maintenance_repair(datum/act/op/A)
	repair_damage(max_integrity)
	return OP_OK

/// Predicate clause: the held item is (or contains) a lit welding tool (the legacy REQ_PROC form, for the interactions that still use it).
/proc/dq_held_welder_lit(mob/actor, atom/target, obj/item/held)
	var/obj/item/weldingtool/welder = held?.get_welder()
	return welder?.isOn() ? TRUE : FALSE
