// Capabilities (doc/rewrite/dx_conventions.md §2). A capability is a complete feature of an atom:
// its interactions, state, examine lines, appearance layers, UI data, gating of other entries,
// refusals, logging and verbs.
//
//	/obj/machinery/power/apc/capabilities()
//		. = ..()
//		. += wall_machine(board = /obj/item/circuitboard/apc)
//		. += slot(nameof(cell), /obj/item/cell, behind = COVER)
//
// capabilities() is built once per type (type_list) and the datums in it are SHARED by every
// instance of the type: configuration lives in the datum's vars (set by its constructor proc),
// per-instance state lives on the holder, in the `cap_state` bitfield (one CAP_* bit per boolean)
// or in a lazily created datum from cap_data(holder, capability). List order is the order of the
// menu, of examine lines and of appearance layers.

/datum/capability
	/// Identity for without(): defaults to the type. Two entries with one key cannot coexist.
	var/key
	/// This capability's entries need these CAP_* bits SET (behind = COVER|PANEL: reachable only with
	/// the cover / panel open). Merged onto its entries by cap_apply_gating().
	var/behind = NONE
	/// Entries refused while this lock bit is set (LOCK).
	var/locked_by = NONE
	/// PROC_REF on the holder, (mob/user, obj/item/held): TRUE, FALSE (else_say) or a reason text.
	var/needs
	var/else_say
	/// Capability-level: FALSE makes every entry this capability builds refuse while the holder is
	/// broken / unpowered (merged onto the entries by cap_apply_gating()). TRUE (the default) leaves
	/// each entry's own works_broken / works_unpowered in charge.
	var/works_broken = TRUE
	var/works_unpowered = TRUE
	/// LOG_GAME, LOG_ADMIN or null: the dispatcher logs each successful entry at this level.
	var/log

/// The interactions this capability offers on holder: /datum/interaction flyweights, built once
/// per (type, capability) and cached. Each carries its gating (behind/locked_by/needs/works_*).
/datum/capability/proc/interactions(atom/holder)
	return null

/// Examine lines for user, in list order.
/datum/capability/proc/examine(atom/holder, mob/user)
	return null

/// Adds this capability's layers to look (look.state/overlay/gauge/glow). Called before the
/// holder's own draw() body runs past ..() (DM reserves the name appearance).
/datum/capability/proc/draw(atom/holder, datum/look/look)
	return

/// Adds keys to the holder's tgui_data().
/datum/capability/proc/ui_data(atom/holder, mob/user, list/data)
	return

/// Gates ANOTHER entry: null lets it through, text refuses with that reason. The cover gates
/// every entry whose `behind` includes COVER while it is closed; the lock does the same for
/// `locked_by`.
/datum/capability/proc/gate(atom/holder, mob/user, datum/interaction/entry)
	return null

/// Verbs to hide on holder right now (re-evaluated on change).
/datum/capability/proc/hidden_verbs(atom/holder)
	return null

/// Native verbs this capability adds to its holder type.
/datum/capability/proc/verbs()
	return null

/// Init / teardown hooks for per-instance state (default children, lazily created data).
/datum/capability/proc/on_holder_init(atom/holder, mapload)
	return
/datum/capability/proc/on_holder_destroy(atom/holder)
	return

// ---- periodic work (until the core's systems() hook lands) ----

/datum/capability
	/// The periodic pipeline (PERIODIC_*) this capability steps on, or null for none. The holder
	/// takes it as its periodic_cadence at init when it declares none of its own.
	var/cadence

/// TRUE while this capability has periodic work on holder. Pure: re-evaluated on change through
/// the holder's should_run().
/datum/capability/proc/cap_should_run(atom/holder)
	return FALSE

/// One periodic step on holder (delta: the pipeline's step, as periodic_step() gets it).
/datum/capability/proc/cap_periodic_step(atom/holder, delta)
	return
