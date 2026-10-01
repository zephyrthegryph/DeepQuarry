// The storage capability (doc/rewrite/dx_conventions.md §2): the holder keeps items in a storage
// slot of the containment ledger (code/datums/containment/), the capability equivalent of
// /obj/item/storage and its TYPE_TABLE hold specs.
//
//	/obj/item/belt/utility/capabilities()
//		. = ..()
//		. += cap_storage(holds = HOLDS_TOOLS | HOLDS_ENGINEERING, slots = 7, max_w_class = ITEMSIZE_NORMAL)
//
// What fits is a category rule, not a type list (final design §0.1): the holder `holds` a mask of
// HOLDS_* bits; an item fits when (holds & HOLDS_TOOLS) and it has tool qualities, or its
// `storage_class` shares a bit with holds. HOLDS_ANY takes anything that fits by size. A real
// exception is a can_hold_proc on the holder, (obj/item/I, mob/user): TRUE takes it, FALSE or a
// reason refuses, null falls back to the category rule.
//
// Everything moves through the ledger: the holder gets the capability storage slot
// (/datum/om/relation/slot/cap_storage, slot id CONTAINER_SLOT_STORAGE), whose refusal and
// capacity are this capability's rules, so dq_ledger_refusal()/move_into()/slot_remove() apply it.
//
// Entries: Put in (any held item), Take out (a form choosing one item, into the hand), Empty out
// (onto the floor, when quick_empty). Examine: how many things it holds. UI: storage_count and
// storage_space. Per-instance overrides (H1): the holder's `hold_mask`, `hold_slots`,
// `hold_max_w_class` and `hold_max_total` vars, when set, replace the constructor defaults.
// From code: storage_insert(I, user), storage_remove(I, destination, user), storage_items().

/obj
	/// cap_storage(): this instance's HOLDS_* mask, or null for the capability's `holds`.
	var/hold_mask
	/// cap_storage(): this instance's item count limit, or null for the capability's.
	var/hold_slots
	/// cap_storage(): this instance's largest w_class, or null for the capability's.
	var/hold_max_w_class
	/// cap_storage(): this instance's space in storage-cost units, or null for the capability's.
	var/hold_max_total

/obj/item
	/// The HOLDS_* categories this item counts as for cap_storage() holders (tools need none).
	var/storage_class = NONE

/datum/capability/storage
	/// HOLDS_* mask of what fits (HOLDS_ANY: anything, by size).
	var/holds = HOLDS_ANY
	/// Most things it holds, or null for no count limit.
	var/slots
	/// Largest w_class that fits.
	var/max_w_class = ITEMSIZE_SMALL
	/// Space in storage-cost units (get_storage_cost()).
	var/max_total = ITEMSIZE_COST_SMALL * 4
	/// PROC_REF on the holder, (obj/item/I, mob/user): TRUE, FALSE, a reason, or null (the rule).
	var/can_hold_proc
	/// Offers Empty out.
	var/quick_empty = TRUE
	/// Played on insert and removal; FALSE for silence (DM turns an explicit null into the default).
	var/use_sound = SFX_RUSTLE

/**
 * The storage capability. holds: HOLDS_* mask; slots: item count limit (null: none); max_w_class;
 * max_total: space in storage-cost units; can_hold_proc: the holder's exception proc. behind /
 * locked_by gate every entry (a lockbox: locked_by = LOCK).
 */
/proc/cap_storage(holds = HOLDS_ANY, slots = null, max_w_class = ITEMSIZE_SMALL, max_total = ITEMSIZE_COST_SMALL * 4, can_hold_proc = null, quick_empty = TRUE, use_sound = SFX_RUSTLE, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, layer = CAP_NO_LAYER)
	var/datum/capability/storage/C = new
	C.layer_name = layer
	C.holds = holds
	C.slots = slots
	C.max_w_class = max_w_class
	C.max_total = max_total
	C.can_hold_proc = can_hold_proc
	C.quick_empty = quick_empty
	C.use_sound = use_sound
	return cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/storage/interactions(atom/holder)
	. = list()
	. += adopt_entry(cap_insert("Put in", /obj/item, GLOBAL_PROC_REF(cap_storage_put_in), needs = GLOBAL_PROC_REF(cap_storage_insert_reason), works_broken = TRUE, works_unpowered = TRUE, priority = 1), id = "storage:put_in", pass_cap = TRUE)
	. += adopt_entry(cap_hand("Take out", GLOBAL_PROC_REF(cap_storage_take_out), needs = GLOBAL_PROC_REF(cap_storage_has_items), else_say = "it's empty", works_broken = TRUE, works_unpowered = TRUE, form = list(choice_field("choice", GLOBAL_PROC_REF(cap_storage_choices), message = "Take out what?"))), id = "storage:take_out", category = INTERACTION_CAT_OPEN, empty_handed = TRUE, pass_cap = TRUE)
	if(quick_empty)
		. += adopt_entry(cap_hand("Empty out", GLOBAL_PROC_REF(cap_storage_empty_out), needs = GLOBAL_PROC_REF(cap_storage_has_items), else_say = "it's empty", works_broken = TRUE, works_unpowered = TRUE), id = "storage:empty_out", category = INTERACTION_CAT_EJECT, empty_handed = TRUE, pass_cap = TRUE)

/datum/capability/storage/examine(atom/holder, mob/user)
	var/count = length(storage_items(holder))
	if(!count)
		return list("It is empty.")
	return list("It holds [count] thing\s.")

/datum/capability/storage/ui_data(atom/holder, mob/user, list/data)
	data["storage_count"] = length(storage_items(holder))
	data["storage_space"] = list("used" = holder.slot_used(CONTAINER_SLOT_STORAGE), "max" = total_for(holder))

// ---- the rules (per-instance vars override the constructor defaults, H1) ----

/datum/capability/storage/proc/holds_for(atom/holder)
	var/obj/O = holder
	return (isobj(O) && !isnull(O.hold_mask)) ? O.hold_mask : holds

/datum/capability/storage/proc/slots_for(atom/holder)
	var/obj/O = holder
	return (isobj(O) && !isnull(O.hold_slots)) ? O.hold_slots : slots

/datum/capability/storage/proc/w_class_for(atom/holder)
	var/obj/O = holder
	return (isobj(O) && !isnull(O.hold_max_w_class)) ? O.hold_max_w_class : max_w_class

/datum/capability/storage/proc/total_for(atom/holder)
	var/obj/O = holder
	return (isobj(O) && !isnull(O.hold_max_total)) ? O.hold_max_total : max_total

/// The category rule: whether holder's mask takes I at all (size and space aside).
/datum/capability/storage/proc/accepts_item(atom/holder, obj/item/I)
	var/mask = holds_for(holder)
	if(mask == HOLDS_ANY)
		return TRUE
	if((mask & HOLDS_TOOLS) && length(I.tool_qualities))
		return TRUE
	return (I.storage_class & mask) != 0

/// Why `thing` can't go into holder's storage, capacity aside (the slot checks space), or null.
/datum/capability/storage/proc/refusal(atom/holder, atom/movable/thing, mob/actor)
	if(!isitem(thing))
		return "that can't go in \the [holder]"
	var/obj/item/I = thing
	if(has_trait(I, TRAIT_NODROP))
		return "\the [I] is stuck to your hand"
	if(actor && actor.isEquipped(I) && !actor.canUnEquip(I))
		return "you can't let go of \the [I]"
	var/limit = slots_for(holder)
	if(!isnull(limit) && length(storage_items(holder)) >= limit)
		return "\the [holder] is full"
	if(I.w_class > w_class_for(holder))
		return "\the [I] is too big for \the [holder]"
	if(isitem(holder))
		var/obj/item/bag = holder
		if(I.w_class >= bag.w_class && (istype(I, /obj/item/storage) || cap_of(I, /datum/capability/storage)))
			return "it's a container as big as \the [holder]"
	if(can_hold_proc)
		var/verdict = holder_call(holder, can_hold_proc, I, actor)
		if(istext(verdict))
			return verdict
		if(!isnull(verdict))
			return verdict ? null : "\the [holder] can't hold \the [I]"
	if(!accepts_item(holder, I))
		return "\the [holder] can't hold \the [I]"
	return null

// ---- the ledger slot ----

/// The storage slot a cap_storage() capability gives its holder (added by slot_relation_overrides(),
/// slot_def.dm). Its refusal and capacity are the holder's capability's; contents spill when the
/// holder is destroyed.
/datum/om/relation/slot/cap_storage
	slot_id = CONTAINER_SLOT_STORAGE
	name = "storage"
	exposure = SLOT_EXPOSURE_INTERNAL
	capacity_model = SLOT_CAPACITY_UNITS
	drop_policy = SLOT_DROP_SPILL

/datum/om/relation/slot/cap_storage/capacity_for(atom/holder)
	var/datum/capability/storage/C = cap_of(holder, /datum/capability/storage)
	return C ? C.total_for(holder) : 0

/datum/om/relation/slot/cap_storage/cost(atom/holder, atom/movable/thing)
	if(isitem(thing))
		var/obj/item/I = thing
		return I.get_storage_cost()
	return ITEMSIZE_COST_NO_CONTAINER

/datum/om/relation/slot/cap_storage/refusal(atom/holder, atom/movable/thing, mob/actor)
	var/datum/capability/storage/C = cap_of(holder, /datum/capability/storage)
	if(!C)
		return "\the [holder] can't hold anything"
	return C.refusal(holder, thing, actor)

// ---- the holder API ----

/// Everything in this atom's storage slot, in order (a copy).
/proc/storage_items(atom/holder)
	return holder.slot_contents(CONTAINER_SLOT_STORAGE)

/// Why I can't go into this atom's storage right now, or null.
/proc/storage_refusal(atom/holder, obj/item/I, mob/user)
	return dq_ledger_refusal(I, holder, CONTAINER_SLOT_STORAGE, user)

/// Puts I into this atom's storage: out of a hand or inventory, off the floor or out of another
/// holder, as one ledger move. TRUE when it went in.
/proc/storage_insert(atom/holder, obj/item/I, mob/user)
	if(storage_refusal(holder, I, user))
		return FALSE
	var/mob/wearer = ismob(I.loc) ? I.loc : null
	if(wearer)
		// Still mob inventory (C3): the mob clears its slot and hands the item over.
		wearer.remove_from_mob(I, holder)
		if(I.loc != holder)
			return FALSE
		I.dropped(wearer)
		var/datum/ledger/L = dq_ledger(holder)
		var/list/entry = L?.entries[I]
		if(entry && entry[LEDGER_E_SLOT] != CONTAINER_SLOT_STORAGE)
			I.move_into(holder, CONTAINER_SLOT_STORAGE, user)
	else if(!I.move_into(holder, CONTAINER_SLOT_STORAGE, user))
		return FALSE
	I.on_enter_storage(holder)
	changed(holder)
	return TRUE

/// Takes I out of this atom's storage to `destination` (null: the floor). TRUE when it came out.
/proc/storage_remove(atom/holder, obj/item/I, atom/destination, mob/user)
	if(!istype(I) || I.loc != holder)
		return FALSE
	destination ||= holder.drop_location()
	if(!destination || !holder.slot_remove(I, destination, user))
		return FALSE
	I.reset_plane_and_layer()
	I.on_exit_storage(holder)
	changed(holder)
	return TRUE

// ---- entry handlers and needs (procs on the holder) ----

/proc/cap_storage_insert_reason(mob/user, atom/holder, obj/item/held)
	if(!held)
		return FALSE
	return storage_refusal(holder, held, user) || TRUE

/proc/cap_storage_has_items(mob/user, atom/holder, obj/item/held)
	return length(storage_items(holder)) > 0

/// Take out choices: name -> item.
/proc/cap_storage_choices(atom/holder, mob/user)
	. = list()
	for(var/obj/item/I as anything in storage_items(holder))
		.[avoid_assoc_duplicate_keys(I.name, .)] = I

/proc/cap_storage_put_in(atom/holder, mob/user, obj/item/held, datum/capability/storage/cap)
	var/datum/capability/storage/C = cap
	if(!storage_insert(holder, held, user))
		return refuse(user, "\The [held] won't go in \the [holder].")
	if(C?.use_sound)
		playsound(holder, C.use_sound, 50, FALSE, -5)
	act_message(user, holder, self = "You put %I% into %T%.", others = "%U% puts %I% into %T%.", item = held)
	return TRUE

/// choice: the name picked from cap_storage_choices(); re-resolved here, since the item may be gone.
/proc/cap_storage_take_out(atom/holder, mob/user, choice, datum/capability/storage/cap)
	var/list/choices = cap_storage_choices(holder, user)
	var/obj/item/I = choices[choice]
	if(!I)
		return refuse(user, "That isn't in \the [holder] any more.")
	if(!storage_remove(holder, I, get_turf(user), user))
		return refuse(user, "You can't take \the [I] out.")
	user.put_in_hands(I)
	var/datum/capability/storage/C = cap
	if(C?.use_sound)
		playsound(holder, C.use_sound, 50, FALSE, -5)
	act_message(user, holder, self = "You take %I% out of %T%.", others = "%U% takes %I% out of %T%.", item = I)
	return TRUE

/proc/cap_storage_empty_out(atom/holder, mob/user, datum/capability/storage/cap)
	var/turf/T = get_turf(holder)
	var/count = 0
	for(var/obj/item/I as anything in storage_items(holder))
		if(storage_remove(holder, I, T, user))
			count++
	if(!count)
		return refuse(user, "Nothing comes out of \the [holder].")
	act_message(user, holder, self = "You empty %T%.", others = "%U% empties %T%.")
	return TRUE
