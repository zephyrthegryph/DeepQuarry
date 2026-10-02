// The library capabilities of bays (doc/rewrite/final_api.html, section 11 "The library", section 8 "Compartments"; section 19 "E2" and the E0 proof 7):
// cover(), a compartment and a cell bay, with telekinesis as the provider that reaches them.
//
//   cover(name, tool, removable, starts_open)    ops cover.open (toggles COVER_OPEN, by hand or with `tool`) and, when removable, cover.remove
//                                                (a crowbar on harm intent: open for good, COVER_REMOVED). State keys COVER_OPEN, COVER_REMOVED.
//   bay_compartment(bay, door, applies_to)       a bay of the holder whose DOOR is another capability (CAP_COVER): the bay is exposed only while the
//                                                door's bay_exposed() says so, for the authorities in `applies_to` (default AUTH_PHYSICAL, so a hand and
//                                                telekinesis stop at a closed cover and a remote-access reach never sees physical bays).
//   bay_cell(slot_var, bay, accepts, starts)     a one-item slot over a holder var, behind `bay`: cell_bay.<var>.insert (item(accepts) + put_in) and
//                                                cell_bay.<var>.take (hand + when(var) + take_out), each refused with the compartment's reason while the
//                                                bay is closed. `starts` (a type, or nameof(var) holding one) fills the bay when the holder initializes.
//   telekinesis()                                a provider: AFF_MANIPULATE at TK_RANGE with line_of_sight. Granted at runtime, so the actor's provider
//                                                set generation bumps and cached menus follow.
//
// bay_compartment() and bay_cell() are the final cell_bay() and compartment() of section 11 under working names: the live names belong to the
// legacy library (code/datums/operations/routes.dm, code/datums/capabilities/library/cell_bay.dm) until phase 2 deletes it; `prefix =` keeps the op
// keys the doc's, so nothing that names an op changes when the constructors are renamed. A bay's door is a capability that answers bay_exposed().

/// Today's TK_MAXRANGE, in tiles (section 8).
#define TK_RANGE TK_MAXRANGE

/// The entry kinds of the bay library.
#define ENTRY_COMPARTMENT "compartment"
#define ENTRY_BAY_SLOT "bay_slot"

MSG_DEF_SELF(cover/closed, "Its cover is closed.")
MSG_DEF_SELF(cover/still_on, "Its cover is still on.")
MSG_DEF_SELF(cover/removed, "Its cover has been removed.")
MSG_DEF_SELF(bay/closed, "It is closed.")
MSG_DEF_SELF(bay/full, "There is already something in there.")

// ---- cover ----

CAPABILITY_TYPE(cover, CAP_COVER, /datum/capability/bay_cover, key = name, name = "cover", tool = BY_HAND, removable = FALSE, starts_open = FALSE)
cap_keys(CAP_COVER, OPEN = MSG(cover/closed), REMOVED = MSG(cover/still_on))

/datum/capability/bay_cover
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/bay_cover/entries()
	var/list/entries = list()
	var/opener = (tool == BY_HAND) ? hand() : tool(tool)
	entries += op("open", opener, \
		needs(req_is(COVER_REMOVED, FALSE, because = MSG(cover/removed))), \
		toggles(COVER_OPEN))
	if(removable)
		entries += op("remove", tool(TOOL_CROWBAR), hostile(), \
			needs(req_is(COVER_REMOVED, FALSE, because = MSG(cover/removed))), \
			sets(COVER_OPEN, TRUE), sets(COVER_REMOVED, TRUE))
	return entries

/// A cover that starts open is open from the moment its holder initializes.
/datum/capability/bay_cover/on_holder_init_ctx(datum/act/eval/A)
	if(starts_open)
		cap_key_set(A.holder, COVER_OPEN, TRUE, selector)

/// An open or removed cover leaves its bay exposed.
/datum/capability/bay_cover/bay_exposed(datum/holder)
	return cover_open(holder, null) || cover_removed(holder, null)

/// A capability that can be a bay's door answers whether the bay it closes is exposed now. The default is not a door: nothing is closed.
/datum/capability/proc/bay_exposed(datum/holder)
	return TRUE

/// The reason shown while this door keeps its bay closed.
/datum/capability/proc/bay_closed_reason()
	return /datum/msg/bay/closed

/datum/capability/bay_cover/bay_closed_reason()
	return /datum/msg/cover/closed

// ---- compartment ----

CAPABILITY_TYPE(bay_compartment, CAP_COMPARTMENT, /datum/capability/bay_compartment, key = bay, prefix = "compartment", bay = null, door = null, applies_to = AUTH_PHYSICAL)

/datum/capability/bay_compartment/entries()
	return list(entry_make(ENTRY_COMPARTMENT, null, list("bay" = bay, "door" = door, "applies_to" = applies_to)))

/// The reason bay `bay` of `holder` is closed to `authority`, or null when it is exposed: each compartment of that bay whose applies_to takes the
/// authority asks its door capability.
/proc/compartment_reason(datum/holder, bay, authority)
	var/datum/type_table/T = table_of(holder)
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_COMPARTMENT))
		var/datum/entry/E = C.item
		if(E.args["bay"] != bay || !(authority & E.args["applies_to"]) || isnull(E.args["door"]))
			continue
		var/datum/capability/door = cap_of(holder, E.args["door"])
		if(door && !door.bay_exposed(holder))
			return door.bay_closed_reason()
	return null

/// Does the atom's bay refuse the actor's reach now? (at(BAY_X): a requirement that a bay is open.) A compartment answers.
/atom/bay_reason(bay, authority)
	return compartment_reason(src, bay, authority)

/// The reason a thing inside this container is not reachable through its bay now (a closed cover), or null: the bay whose slot holds it, asked.
/atom/bay_blocked(atom/inside, authority)
	for(var/datum/centry/C as anything in compiled_entries(table_of(src), ENTRY_BAY_SLOT))
		var/datum/entry/E = C.item
		if(vars[E.args["var"]] == inside)
			return bay_reason(E.args["bay"], authority)
	return null

// ---- cell bay ----

CAPABILITY_TYPE(bay_cell, CAP_CELL_BAY, /datum/capability/bay_cell, key = slot_var, prefix = "cell_bay", slot_var = null, bay = null, accepts = /obj/item/cell, starts = null)

/datum/capability/bay_cell
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/bay_cell/entries()
	var/list/entries = list()
	var/list/at_bay = list()
	if(!isnull(bay))
		entries += entry_make(ENTRY_BAY_SLOT, null, list("var" = slot_var, "bay" = bay))
		at_bay += at(bay)
	entries += op("insert", item(accepts), put_in(slot_var), at_bay)
	entries += op("take", hand(), when(slot_var), take_out(slot_var), at_bay)
	return entries

/// The bay starts with a thing when its holder initializes: `starts` is a type, or nameof(var) of a holder var holding one.
/datum/capability/bay_cell/on_holder_init_ctx(datum/act/eval/A)
	var/atom/holder = A.holder
	if(isnull(starts) || !istype(holder) || !isnull(holder.vars[slot_var]))
		return
	var/start_type = starts
	if(istext(starts) && (starts in holder.vars))
		start_type = holder.vars[starts]
	if(!ispath(start_type, /atom/movable))
		return
	var/atom/movable/thing = new start_type(holder)
	varslot_set(holder, slot_var, thing)

// ---- slots over a holder var ----

/// Is `slot_id` a one-item slot over a var of the holder (a bay_cell()), rather than a slot of the containment ledger?
/proc/op_var_slot(atom/holder, slot_id)
	if(!istext(slot_id) || !(slot_id in holder.vars))
		return FALSE
	for(var/datum/om/relation/slot/def as anything in dq_slot_defs_for(holder))
		if(def.slot_id == slot_id)
			return FALSE
	return TRUE

/// Sets the var of a var-slot to `thing` (which is in the holder) or empties it.
/proc/varslot_set(atom/holder, var_name, atom/movable/thing)
	holder.vars[var_name] = thing // ALLOW(api): the one writer of a one-item slot over a var: the bay capability's own slot
	changed(holder, CHANGE_EXPLICIT, var_name)

/// Why `thing` cannot go into the var-slot, or null.
/proc/varslot_refusal(atom/holder, var_name, atom/movable/thing)
	if(!isnull(holder.vars[var_name]))
		return /datum/msg/bay/full
	return null

/// Puts `thing` into the var-slot of the holder. TRUE when it went in.
/proc/varslot_insert(atom/holder, var_name, atom/movable/thing, mob/actor)
	if(varslot_refusal(holder, var_name, thing))
		return FALSE
	if(!thing.forceMove(holder))
		return FALSE
	varslot_set(holder, var_name, thing)
	return TRUE

/// Takes what the var-slot holds out: into the actor's hand when it can take it, else onto the floor. The thing, or null when the slot is empty.
/proc/varslot_take(atom/holder, var_name, mob/actor)
	var/atom/movable/thing = holder.vars[var_name]
	if(!istype(thing))
		return null
	varslot_set(holder, var_name, null)
	var/obj/item/as_item = thing
	if(actor && istype(as_item) && actor.put_in_hands(as_item))
		return thing
	thing.forceMove(get_turf(actor || holder))
	return thing

// ---- telekinesis ----

CAPABILITY_DEF(telekinesis, CAP_TELEKINESIS, key = NONE)

/// A provider of AFF_MANIPULATE with a reach of TK_RANGE tiles and line_of_sight = TRUE: any hand op on a target it can see in range. No tool or
/// attack affordances; compartments and requirements still apply.
/datum/capability/def/telekinesis/entries()
	return list(provides(AFF_MANIPULATE, reach = TK_RANGE, line_of_sight = TRUE))
