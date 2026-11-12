// Capabilities (doc/rewrite/dx_conventions.md §2). A capability is a complete feature of an atom:
// its state, examine lines, appearance layers, UI data, logging and verbs.
//
//	CAPABILITY(/mob/living/simple_mob/slime/xenobio/silver, reflects(list(/obj/item/projectile/beam), 100))
//
// A type's capability list is built once per type (type_list) and the datums in it are SHARED by every
// instance of the type: configuration lives in the datum's vars (set by its constructor proc),
// per-instance state lives on the holder, in the `cap_state` bitfield (one CAP_* bit per boolean)
// or in a lazily created datum from cap_data(holder, capability). List order is the order of the
// menu, of examine lines and of appearance layers.

/// Examine lines for user, in list order.
/datum/capability/proc/examine(atom/holder, mob/user)
	return null

/// Adds this capability's layers to look (look.state/overlay/gauge/glow). Called before the
/// holder's own draw() body runs past ..() (DM reserves the name appearance).

/// A capability's window buttons are ops in its entries with a ui_act() binding (code/engine/parts/inputs.dm).

/// Adds keys to this capability's own UI list: the holder's tgui_data() carries it as
/// data["caps"][ui_key()] (caps_ui_data()).
/datum/capability/proc/legacy_ui_data(atom/holder, mob/user, list/data)
	return

/// This capability's key under data["caps"]: its layer name, else its key.
/datum/capability/proc/ui_key()
	if(layer_name && layer_name != CAP_NO_LAYER)
		return layer_name
	return "[key]"

/// Verbs to hide on holder right now (re-evaluated on change).

/// Native verbs this capability gives its holder: the holder has them while it has the capability
/// (atom/granted_verbs() collects them; hidden_verbs() still wins).

/// Ownership entries (owns(...)) this capability contributes to its holder type's ownership table
/// (doc/rewrite/ownership.md §1.2): a slot owns its var, so the type declares nothing for it. Per
/// type and pure: read only the capability's own settings.
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
