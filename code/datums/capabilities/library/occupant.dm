// cap_occupant(): a machine that holds a mob (doc/rewrite/migration_guide.md A4, archive/framework_fixes.md §9.5).
//
//	/obj/machinery/transportpod/capabilities()
//		. = ..()
//		. += cap_occupant(OCCUPANT_SLOT_TRANSPORTPOD, types = /mob/living/carbon/human, on_enter = PROC_REF(occupant_entered))
//
// The occupant relation is the holder's sealed occupant slot on the containment ledger (a /datum/om/relation/slot/occupant
// subtype declares its id and shares, containment.md §10): nothing is copied into a var, and destroying the holder
// spills the occupant by the slot's drop policy. The capability adds what every occupant machine wrote by hand:
//	ops       "enter_<slot>"      drag a mob onto the holder (ACT_DROP_ONTO, the dragged mob is `held`), after enter_delay
//	          "enter_<slot>_self" climb in yourself (ACT_NONE: the Menu, radial or command bar)
//	          "eject_<slot>"      let the occupant out (ACT_NONE, offered while occupied; the occupant uses it from inside)
//	reads     occupants(holder)   never null: the mobs in the slot, in entry order; occupant_of(holder): the first or null
//	state     the change key OCCUPANTS_KEY, published (with a full refresh of the holder: draw, UI, should_run) whenever the
//	          slot gains or loses a mob, by whatever path moved it (an op, occupant_enter()/occupant_eject() from code,
//	          a raw slot_remove(), the destroy spill): /obj/machinery/on_slot_changed() forwards to the capability.
//	hooks     on_enter / on_exit: PROC_REFs of the holder, (mob/living/M), run after the move.
// From code: occupant_enter(holder, M, user) and occupant_eject(holder, M = null, destination = null).

/// The change key published when an occupant machine's occupants change (reactions read it with on_change()).
#define OCCUPANTS_KEY "occupants"

/// slot id -> TRUE for every slot an occupant capability manages (a fast test in on_slot_changed()).
GLOBAL_LIST_EMPTY(occupant_slot_ids)

/datum/capability/occupant
	/// The holder's ledger slot (OCCUPANT_SLOT_*).
	var/slot_id
	/// At most this many occupants (the slot's own capacity also holds).
	var/max = 1
	/// Accepted mob types (a type or a list).
	var/types = /mob/living
	/// Wait before a dragged mob goes in (0: at once).
	var/enter_delay = 0
	var/enter_name = "Put inside"
	var/self_name = "Climb in"
	var/eject_name = "Eject"
	/// Holder PROC_REFs, (mob/living/M), after a mob entered / left.
	var/on_enter
	var/on_exit

/**
 * A holder of up to `max` mobs of `types` in ledger slot `slot_id`. enter_delay: the wait before a dragged mob goes in.
 * on_enter / on_exit: holder PROC_REFs (mob/living/M) run after the move. Standard gating (needs, works_broken, ...)
 * gates the enter ops; the eject always works (nobody is trapped by a broken machine).
 */
/proc/cap_occupant(slot_id, max = 1, types = /mob/living, enter_delay = 0, on_enter, on_exit, enter_name = "Put inside", self_name = "Climb in", eject_name = "Eject", needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/occupant/C = new
	C.slot_id = slot_id
	C.key = "occupant:[slot_id]"
	C.max = max
	C.types = types
	C.enter_delay = enter_delay
	C.on_enter = on_enter
	C.on_exit = on_exit
	C.enter_name = enter_name
	C.self_name = self_name
	C.eject_name = eject_name
	GLOB.occupant_slot_ids[slot_id] = TRUE
	return cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/occupant/interactions(atom/holder)
	var/slug = dq_interaction_slug("_[slot_id]")
	var/list/accepted = islist(types) ? types : list(types)
	return list(
		adopt_entry(lib_op(enter_name, GLOBAL_PROC_REF(cap_occupant_enter_dragged), OP_SHAPE_USE_ON, using = accepted, key = "enter_[slot_id]", action = ACT_DROP_ONTO, delay = enter_delay, needs = GLOBAL_PROC_REF(cap_occupant_can_enter_held)), id = "occupant_enter[slug]"),
		adopt_entry(lib_op(self_name, GLOBAL_PROC_REF(cap_occupant_enter_self), OP_SHAPE_HAND, key = "enter_[slot_id]_self", action = ACT_NONE, needs = GLOBAL_PROC_REF(cap_occupant_can_enter_self)), id = "occupant_self[slug]"),
		adopt_entry(lib_op(eject_name, GLOBAL_PROC_REF(cap_occupant_eject_op), OP_SHAPE_HAND, key = "eject_[slot_id]", action = ACT_NONE, offered = req_proc(GLOBAL_PROC_REF(cap_occupant_occupied)), works_broken = TRUE, works_unpowered = TRUE, via = ROUTE_PHYSICAL | ROUTE_INTERFACE | ROUTE_VERB), id = "occupant_eject[slug]"),
	)

/datum/capability/occupant/examine(atom/holder, mob/user)
	var/list/inside = members(holder)
	if(!length(inside))
		return null
	var/mob/M = inside[1]
	return list(length(inside) > 1 ? "There are [length(inside)] people inside." : "[M] is inside.")

/// UI data: the occupants' refs (a window that shows more reads them through its own UI_DATA).
/datum/capability/occupant/ui_data(atom/holder, mob/user, list/data)
	var/list/inside = list()
	for(var/mob/M as anything in members(holder))
		inside += REF(M)
	data["occupants"] = inside

/// The mobs in holder's slot, in entry order. Never null.
/datum/capability/occupant/proc/members(atom/holder)
	. = list()
	for(var/mob/M in holder.slot_contents(slot_id))
		. += M

/// Why `M` can't go in now (text), or null.
/datum/capability/occupant/proc/refusal(atom/holder, mob/M)
	if(!istype(M) || QDELETED(M))
		return "there's nothing to put in"
	if(!is_type_in_list(M, islist(types) ? types : list(types)))
		return "[M] won't fit in [holder]"
	if(M.loc == holder)
		return "[M] is already inside"
	if(M.buckled_to())
		return "[M] is buckled to something"
	if(length(members(holder)) >= max)
		return "[holder] is already occupied"
	return null

/// Moves `M` into the slot. TRUE when it went in.
/datum/capability/occupant/proc/enter(atom/holder, mob/M, mob/user)
	if(refusal(holder, M))
		return FALSE
	if(!M.move_into(holder, slot_id, user))
		return FALSE
	if(user)
		holder.add_fingerprint(user)
	return M.loc == holder

/// Lets `M` (null: everyone) out onto `destination` (null: the holder's drop location). The occupants that left.
/datum/capability/occupant/proc/eject(atom/holder, mob/M, atom/destination)
	. = list()
	var/atom/to_loc = destination || holder.drop_location()
	for(var/mob/inside as anything in members(holder))
		if(M && inside != M)
			continue
		if(holder.slot_remove(inside, to_loc))
			. += inside

/// The ledger moved `thing` in or out of the slot: publish the change and run the holder's hook.
/datum/capability/occupant/proc/slot_changed(atom/holder, mob/thing, inserted)
	PUBLISH_CHANGE(holder, OCCUPANTS_KEY)
	changed(holder, CHANGE_MACHINE_OCCUPANT)
	var/hook = inserted ? on_enter : on_exit
	if(hook && ismob(thing) && !holder_destroying(holder))
		call(holder, hook)(thing)

// ---- reads and code entry points ----

/// The occupant capability of holder (for `slot_id`, or its first), or null.
/proc/occupant_cap(atom/holder, slot_id)
	RETURN_TYPE(/datum/capability/occupant)
	for(var/datum/capability/occupant/C in caps_all(holder))
		if(!slot_id || C.slot_id == slot_id)
			return C
	return null

/// The mobs inside holder (its occupant capability's slot). Never null.
/proc/occupants(atom/holder, slot_id)
	var/datum/capability/occupant/C = occupant_cap(holder, slot_id)
	return C ? C.members(holder) : list()

/// The first mob inside holder, or null.
/proc/occupant_of(atom/holder, slot_id)
	RETURN_TYPE(/mob)
	var/list/inside = occupants(holder, slot_id)
	return length(inside) ? inside[1] : null

/// Puts `M` into holder from code (a bump, a conveyor, a spawn). TRUE when it went in.
/proc/occupant_enter(atom/holder, mob/M, mob/user, slot_id)
	var/datum/capability/occupant/C = occupant_cap(holder, slot_id)
	return C ? C.enter(holder, M, user) : FALSE

/// Lets `M` (null: everyone) out of holder from code. The list of mobs that left (never null).
/proc/occupant_eject(atom/holder, mob/M, atom/destination, slot_id)
	var/datum/capability/occupant/C = occupant_cap(holder, slot_id)
	return C ? C.eject(holder, M, destination) : list()

/// From /obj/machinery/on_slot_changed(): a mob moved in or out of an occupant slot.
/proc/occupant_slot_changed(atom/holder, slot_id, atom/movable/thing, inserted)
	if(!GLOB.occupant_slot_ids[slot_id])
		return
	var/datum/capability/occupant/C = occupant_cap(holder, slot_id)
	C?.slot_changed(holder, thing, inserted)

// ---- op handlers and requirements (global: the capability is found from the holder) ----

/// The op being dispatched now belongs to an occupant capability of holder: that one, else holder's first.
/proc/cap_occupant_dispatched(atom/holder)
	var/datum/dispatch_context/ctx = GLOB.dispatch_context_now
	var/datum/interaction/capability/E = ctx?.entry
	if(istype(E) && istype(E.cap, /datum/capability/occupant))
		return E.cap
	return occupant_cap(holder)

/proc/cap_occupant_occupied(mob/user, atom/holder, obj/item/held)
	return length(occupants(holder)) ? TRUE : FALSE

/proc/cap_occupant_can_enter_held(mob/user, atom/holder, atom/movable/held)
	var/datum/capability/occupant/C = cap_occupant_dispatched(holder)
	return C?.refusal(holder, held) || TRUE

/proc/cap_occupant_can_enter_self(mob/user, atom/holder, obj/item/held)
	var/datum/capability/occupant/C = cap_occupant_dispatched(holder)
	if(user?.incapacitated())
		return "you can't do that right now"
	return C?.refusal(holder, user) || TRUE

/proc/cap_occupant_enter_dragged(atom/holder, mob/user, mob/held)
	var/datum/capability/occupant/C = cap_occupant_dispatched(holder)
	if(!C?.enter(holder, held, user))
		return refuse(user, C?.refusal(holder, held) || "[held] doesn't go in.")
	act_message(user, holder, self = "You put [held] into %T%.", others = "%U% puts [held] into %T%.")
	return TRUE

/proc/cap_occupant_enter_self(atom/holder, mob/user, obj/item/held)
	var/datum/capability/occupant/C = cap_occupant_dispatched(holder)
	if(!C?.enter(holder, user, user))
		return refuse(user, C?.refusal(holder, user) || "You can't get in.")
	act_message(user, holder, self = "You climb into %T%.", others = "%U% climbs into %T%.")
	return TRUE

/proc/cap_occupant_eject_op(atom/holder, mob/user, obj/item/held)
	var/datum/capability/occupant/C = cap_occupant_dispatched(holder)
	if(!length(C?.eject(holder)))
		return refuse(user, "Nobody comes out.")
	holder.add_fingerprint(user)
	return TRUE

/// A machine's ledger slot changed: an occupant capability's slot publishes OCCUPANTS_KEY (cap_occupant()).
/obj/machinery/on_slot_changed(slot_id, atom/movable/thing, inserted)
	..()
	occupant_slot_changed(src, slot_id, thing, inserted)
