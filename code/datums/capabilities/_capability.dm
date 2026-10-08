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

/// The interactions this capability offers on holder: /datum/interaction flyweights, built once
/// per (type, capability) and cached. Each carries its gating (behind/locked_by/needs/works_*).
/datum/capability/proc/interactions(atom/holder)
	return null

/// Examine lines for user, in list order.
/datum/capability/proc/examine(atom/holder, mob/user)
	return null

/// Adds this capability's layers to look (look.state/overlay/gauge/glow). Called before the
/// holder's own draw() body runs past ..() (DM reserves the name appearance).

/// A capability owns UI actions by defining `/datum/capability/<x>/proc/act_<action>(mob/user, atom/holder, ...args)`:
/// the dispatcher finds it on the holder's capabilities when the holder has no act_<action> itself. The
/// actions it logs (action -> LOG_GAME / LOG_ADMIN) are its type table, read through ui_logged():
/// TYPE_TABLE(/datum/capability/<x>, ui_logged_actions, list("<action>" = LOG_GAME)).

/// Adds keys to this capability's own UI list: the holder's tgui_data() carries it as
/// data["caps"][ui_key()] (caps_ui_data()).
/datum/capability/proc/legacy_ui_data(atom/holder, mob/user, list/data)
	return

/// This capability's key under data["caps"]: its layer name, else its key.
/datum/capability/proc/ui_key()
	if(layer_name && layer_name != CAP_NO_LAYER)
		return layer_name
	return "[key]"

/// Gates ANOTHER entry: null lets it through, text refuses with that reason. The cover gates
/// every entry whose `behind` includes COVER while it is closed; the lock does the same for
/// `locked_by`.
/datum/capability/proc/gate(atom/holder, mob/user, datum/interaction/entry)
	return null

/// Verbs to hide on holder right now (re-evaluated on change).

/// Native verbs this capability gives its holder: the holder has them while it has the capability
/// (atom/granted_verbs() collects them; hidden_verbs() still wins).

/// Ownership entries (owns(...)) this capability contributes to its holder type's ownership table
/// (doc/rewrite/ownership.md §1.2): a slot owns its var, so the type declares nothing for it. Per
/// type and pure, like capabilities(): read only the capability's own settings.
/// An entry of holder (this capability's or another's) is about to run its handler for user:
/// TRUE stops it there (this capability already told the user why, e.g. an electrified door
/// zapped them). Side effects are allowed: it runs once per dispatch, never while resolving.
/datum/capability/proc/before_entry(atom/holder, mob/user, obj/item/held, datum/interaction/capability/entry)
	return FALSE

/// refine(key, ...) on this capability (not an op): a new capability with `overrides` (refine()'s named fields,
/// field -> value) applied, or null when it has nothing refinable. The default refuses (a stack_trace names the key).
/// Init / teardown hooks for per-instance state (default children, lazily created data).
/datum/capability/proc/legacy_holder_init(atom/holder, mapload)
	return
/datum/capability/proc/legacy_holder_destroy(atom/holder)
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
