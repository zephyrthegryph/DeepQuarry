// The library capabilities of bays (doc/rewrite/final_api.html, section 11 "The library", section 8 "Compartments"; section 19 "E2" and the E0 proof 7):
// a compartment, a cell bay and a telekinesis provider. The cover that closes a bay is code/library/machine/cover.dm.
//
//   compartment(bay, door, applies_to)           a bay of the holder whose DOOR is another capability (CAP_COVER): the bay is exposed only while the
//                                                door's bay_exposed() says so, for the authorities in `applies_to` (default AUTH_PHYSICAL, so a hand and
//                                                telekinesis stop at a closed cover and a remote-access reach never sees physical bays).
//   cell_bay(slot_var, at, accepts, starts)      a one-item slot over a holder var, behind the bay `at`: cell_bay.<var>.insert (item(accepts) + put_in) and
//                                                cell_bay.<var>.take (hand + when(var) + take_out), each refused with the compartment's reason while the
//                                                bay is closed. `starts` (a type, or nameof(var) holding one) fills the bay when the holder initializes.
//   telekinesis()                                a provider: AFF_MANIPULATE at TK_RANGE with line_of_sight. Granted at runtime, so the actor's provider
//                                                set generation bumps and cached menus follow.
//
// A bay's door is a capability that answers bay_exposed().

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

/// A capability that can be a bay's door answers whether the bay it closes is exposed now. The default is not a door: nothing is closed.
/datum/capability/proc/bay_exposed(datum/holder)
	return TRUE

/// The reason shown while this door keeps its bay closed.
/datum/capability/proc/bay_closed_reason()
	return /datum/msg/bay/closed

// ---- compartment ----

CAPABILITY_TYPE(compartment, CAP_COMPARTMENT, /datum/capability/lib/compartment, key = bay, bay = null, door = null, applies_to = AUTH_PHYSICAL)

/datum/capability/lib/compartment/entries()
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

CAPABILITY_TYPE(cell_bay, CAP_CELL_BAY, /datum/capability/lib/cell_bay, key = slot_var, slot_var = null, at = null, accepts = /obj/item/cell, starts = null)

/// A power cell slot over a holder var (`slot_var`, nameof(cell)), behind the bay `at` when given: cell_bay.<var>.insert (a cell in hand goes in) and
/// cell_bay.<var>.take (an empty hand takes it out), each refused with the compartment's reason while the bay is closed. The cell shows through
/// an open cover (a look layer), examine says what it holds, and cell_charge_percent() reads its charge through the bay. `starts` (a type, or
/// nameof(var) of a holder var holding one) fills the bay when the holder initializes.
/datum/capability/lib/cell_bay
	holder_hooks = HOLDER_HOOK_INIT

MSG_DEF_SELF(cell_bay/missing, "The power cell is missing.")

/datum/capability/lib/cell_bay/entries()
	var/list/entries = list()
	var/list/at_bay = list()
	var/visible = slot_var
	if(!isnull(at))
		entries += entry_make(ENTRY_BAY_SLOT, null, list("var" = slot_var, "bay" = at))
		at_bay += global.at(at)
		if(at == BAY_HATCH)
			visible = cond_all(slot_var, COVER_OPEN, cond_not(COVER_REMOVED))
	entries += op("insert", item(accepts), put_in(slot_var), at_bay)
	entries += op("take", hand(), ungated(), when(slot_var), take_out(slot_var), at_bay)
	entries += look_layer(LOOK_CELL, when = visible)
	entries += examine_line(CAP_PROC(examine_cell), reads = list(slot_var))
	return entries

/// The charge meter (or the missing cell, when the bay can be seen into).
/datum/capability/lib/cell_bay/proc/examine_cell(datum/act/A)
	var/obj/item/cell/C = A.holder.vars[slot_var]
	if(!istype(C))
		return (at == BAY_HATCH && cover_open(A.holder, null)) ? "The power cell is missing." : null
	return "The charge meter reads [round(C.percent())]%."

/// The bay starts with a thing when its holder initializes: `starts` is a type, or nameof(var) of a holder var holding one.
/datum/capability/lib/cell_bay/on_holder_init_ctx(datum/act/eval/A)
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

/datum/capability/lib/cell_bay/output_reads(hook)
	return list(slot_var)

/// The charge of A's cell bay in percent: 0 with no cell (never null).
/proc/cell_charge_percent(atom/A)
	READS_FROM()
	var/datum/type_table/T = table_of(A)
	for(var/key in T.caps)
		var/datum/capability/lib/cell_bay/bay = T.caps[key]
		if(istype(bay) && bay.cap_id == CAP_CELL_BAY)
			var/obj/item/cell/cell = A.vars[bay.slot_var]
			return istype(cell) ? cell.percent() : 0
	return 0

// ---- slots over a holder var ----

/// Is `slot_id` a one-item slot over a var of the holder (a cell_bay()), rather than a slot of the containment ledger?
/proc/op_var_slot(atom/holder, slot_id)
	if(!istext(slot_id) || !(slot_id in holder.vars))
		return FALSE
	for(var/datum/om/relation/slot/def as anything in dq_slot_defs_for(holder))
		if(def.slot_id == slot_id)
			return FALSE
	return TRUE

/// Sets the var of a var-slot to `thing` (which is in the holder) or empties it.
/proc/varslot_set(atom/holder, var_name, atom/movable/thing)
	if(rel_kind(holder, var_name) == OWNK_OWN) // a declared owned var: the ownership accessors stamp it and dispose of what it displaces
		if(isnull(thing))
			rel_take(holder, var_name)
		else
			rel_set(holder, var_name, thing)
		return
	holder.vars[var_name] = thing // ALLOW(api): the one writer of a one-item slot over a var: the bay capability's own slot
	changed(holder, CHANGE_EXPLICIT, var_name)

/// Why `thing` cannot go into the var-slot, or null.
/proc/varslot_refusal(atom/holder, var_name, atom/movable/thing, mob/actor)
	if(!isnull(holder.vars[var_name]))
		return /datum/msg/bay/full
	return own_transfer_refusal(holder, thing, null, actor)

/// Puts `thing` into the var-slot of the holder. TRUE when it went in.
/proc/varslot_insert(atom/holder, var_name, atom/movable/thing, mob/actor)
	if(varslot_refusal(holder, var_name, thing, actor))
		return FALSE
	if(rel_kind(holder, var_name) == OWNK_OWN) // a declared owned var: the one transfer moves it in and adopts it
		return move_into(holder, var_name, thing, actor)
	if(!own_bring_in(holder, var_name, thing, null, actor, TRUE, null, FALSE)) // an undeclared var: placed, then the bay writes the var
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
