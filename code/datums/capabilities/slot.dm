// The slot capability (doc/rewrite/dx_conventions.md §2): a holder var holding at most one item.
//
//	/obj/item/flashlight/capabilities()
//		. = ..()
//		. += slot(nameof(cell), /obj/item/cell/device, eject_via = SLOT_VIA_HAND, eject_needs = PROC_REF(in_other_hand))
//
//	/obj/machinery/power/apc/capabilities()
//		. = ..()
//		. += slot(nameof(cell), /obj/item/cell, behind = COVER)
//
// It supplies: an Insert interaction for the accepted types (a full slot refuses "%T% already holds
// %I%.", passes to the next entry, or swaps), an Eject interaction on the eject_via inputs (offered
// while the var is set), the examine line, an appearance overlay while filled (layer = "state"),
// and UI data (data[var] = {name, ref} or null). The item moves with one ownership transfer: out of
// the hand, slot or container it is in, into the holder, adopted with own_set() (own_take() on the
// way out). Holder hooks, compared with nameof(var): slot_refusal(), slot_inserted(),
// slot_eject_refusal(), slot_ejecting(), slot_ejected(). From code: slot_insert(nameof(var), item,
// user) and slot_eject(nameof(var), user).

/datum/capability/slot
	/// The holder var holding the item, from nameof(). Also the slot's key (one slot per var).
	var/slot_var
	/// Accepted type or list of types.
	var/accepts
	var/name
	var/eject_name
	var/insert_msg
	var/eject_msg
	var/full_msg
	var/swap_msg
	/// Holder proc (mob/user): TRUE, FALSE (eject_else_say) or reason text, for the eject.
	var/eject_needs
	var/eject_else_say
	/// SLOT_VIA_* flags.
	var/eject_via = SLOT_VIA_ALT
	/// SLOT_FULL_REFUSE / SLOT_FULL_PASS / SLOT_FULL_SWAP.
	var/when_full = SLOT_FULL_REFUSE
	/// No generated insert: the item goes in through a step of the holder's own (slot_insert()).
	var/no_insert = FALSE
	var/eject_drop = FALSE
	/// The hand eject runs before the holder's hand gate.
	var/ungated = FALSE
	/// Examine texts (%I% item, %T% holder); null for no line.
	var/examine_held
	var/examine_empty
	/// Overlay state drawn while the slot is filled, or null.
	var/layer
	/// Key of the UI data entry (default: the var name); null for none.
	var/ui_key


/**
 * The slot capability for holder var `var_name` (nameof(var)) holding one `accepts` (a type or a
 * list of types). Named options, all defaulted: behind, locked_by, needs + else_say (insert),
 * eject_needs + eject_else_say, works_broken, works_unpowered, log, name, eject_name, insert_msg,
 * eject_msg, full_msg, swap_msg (templates or /datum/msg types; null for silence), eject_via,
 * eject_drop, ungated, when_full, no_insert, examine_held, examine_empty, layer, ui_key.
 */
/proc/cap_slot(var_name, accepts = /obj/item, behind = NONE, locked_by = NONE, needs, else_say = "you can't do that right now", \
		eject_needs, eject_else_say = "you can't do that right now", works_broken = TRUE, works_unpowered = TRUE, log, \
		name, eject_name, insert_msg = "You insert %I% into %T%.", eject_msg = "You remove %I% from %T%.", \
		full_msg = "%T% already holds %I%.", swap_msg = "You swap %I% out of %T%.", eject_via = SLOT_VIA_ALT, eject_drop = FALSE, \
		ungated = FALSE, when_full = SLOT_FULL_REFUSE, no_insert = FALSE, examine_held = null, examine_empty = null, layer = null, ui_key = "")
	var/datum/capability/slot/cap = new
	cap.slot_var = var_name
	cap.key = "slot:[var_name]"
	cap.accepts = accepts
	cap.behind = behind
	cap.locked_by = locked_by
	cap.needs = needs
	cap.else_say = else_say
	cap.eject_needs = eject_needs
	cap.eject_else_say = eject_else_say
	cap.works_broken = works_broken
	cap.works_unpowered = works_unpowered
	cap.log = log
	cap.name = name || dq_interaction_insert_name(accepts)
	if(!eject_name)
		var/list/types = islist(accepts) ? accepts : list(accepts)
		var/atom/first = types[1]
		eject_name = "Remove [initial(first.name)]"
	cap.eject_name = eject_name
	cap.insert_msg = insert_msg
	cap.eject_msg = eject_msg
	cap.full_msg = full_msg
	cap.swap_msg = swap_msg
	cap.eject_via = eject_via
	cap.eject_drop = eject_drop
	cap.ungated = ungated
	cap.when_full = when_full
	cap.no_insert = no_insert
	cap.examine_held = examine_held
	cap.examine_empty = examine_empty
	cap.layer = layer
	cap.ui_key = ui_key == "" ? var_name : ui_key
	return cap

/datum/capability/slot/interactions(atom/holder)
	. = list()
	var/slug = dq_interaction_slug("[holder.type]_[slot_var]")
	if(!no_insert)
		. += new /datum/interaction/capability/slot_insert(src, "slot_insert[slug]")
	var/static/list/via_entries = list("[SLOT_VIA_ALT]" = INTERACTION_ENTRY_ALT, "[SLOT_VIA_HAND]" = INTERACTION_ENTRY_HAND, "[SLOT_VIA_USE]" = INTERACTION_ENTRY_SELF, "[SLOT_VIA_VERB]" = null)
	for(var/flag in list(SLOT_VIA_ALT, SLOT_VIA_HAND, SLOT_VIA_USE, SLOT_VIA_VERB))
		if(eject_via & flag)
			. += new /datum/interaction/capability/slot_eject(src, "slot_eject[slug]_[flag]", via_entries["[flag]"], ispath(holder.type, /obj/item))

/datum/capability/slot/examine(atom/holder, mob/user)
	var/obj/item/item = holder.vars[slot_var]
	var/text = item ? examine_held : examine_empty
	return text ? msg_fill(text, null, holder, item) : null

/datum/capability/slot/draw(atom/holder, datum/look/look)
	if(layer && holder.vars[slot_var])
		look.overlay(layer)

/datum/capability/slot/ui_data(atom/holder, mob/user, list/data)
	if(ui_key)
		data[ui_key] = slot_ui(holder.vars[slot_var])

/// Sends a slot message: a #15 template through msg_fill(), or a /datum/msg type through
/// act_message_t().
/datum/capability/slot/proc/tell(message, mob/user, atom/holder, obj/item/item, warning = FALSE)
	if(!message || !user)
		return
	if(ispath(message, /datum/msg))
		act_message_t(user, holder, message, item)
		return
	var/text = msg_fill(message, user, holder, item)
	to_chat(user, warning ? span_warning(text) : span_notice(text))

/// The one-call transfer in: out of the hand, slot or container it is in, into holder, adopted.
/datum/capability/slot/proc/adopt(atom/holder, obj/item/item, mob/user)
	if(ismob(item.loc))
		var/mob/carrier = item.loc
		if(!carrier.unEquip(item, target = holder))
			to_chat(user, span_warning("\The [item] is stuck to your hand!"))
			return FALSE
	if(item.loc != holder)
		item.forceMove(holder)
	own_set(holder, slot_var, item)
	return holder.vars[slot_var] == item

/// Puts `item` into the slot on `holder`. TRUE when the input is used (inserted or refused), FALSE
/// when the slot declines (SLOT_FULL_PASS, SLOT_REFUSED_PASS, a type it doesn't accept).
/datum/capability/slot/proc/insert(atom/holder, obj/item/item, mob/user)
	if(!ismovable(item) || !is_type_in_list(item, islist(accepts) ? accepts : list(accepts)))
		return FALSE
	var/obj/item/current = holder.vars[slot_var]
	if(isdatum(current) && QDELETED(current))
		own_take(holder, slot_var)
		current = null
	if(current && when_full != SLOT_FULL_SWAP)
		if(when_full == SLOT_FULL_PASS)
			return FALSE
		tell(full_msg, user, holder, current, warning = TRUE)
		return TRUE
	var/refusal = holder.slot_refusal(slot_var, item, user)
	if(refusal)
		if(refusal == SLOT_REFUSED_PASS)
			return FALSE
		if(refusal != SLOT_REFUSED_SILENT)
			to_chat(user, span_warning(refusal))
		return TRUE
	if(current)
		eject(holder, null, TRUE, "")
		if(holder.vars[slot_var])
			return TRUE // the swap was refused
		tell(swap_msg, user, holder, current)
	if(!adopt(holder, item, user))
		return TRUE
	tell(insert_msg, user, holder, item)
	holder.slot_inserted(slot_var, item, user)
	return TRUE

/// Takes the item out of the slot on `holder`, to `user`'s hands (or the floor with `drop`),
/// telling the actor `message` (eject_msg when null, "" for none). Returns the item.
/datum/capability/slot/proc/eject(atom/holder, mob/user, drop = FALSE, message)
	var/obj/item/item = holder.vars[slot_var]
	if(!item)
		return null
	var/refusal = holder.slot_eject_refusal(slot_var, item, user)
	if(refusal)
		if(refusal != SLOT_REFUSED_SILENT)
			to_chat(user, span_warning(refusal))
		return null
	holder.slot_ejecting(slot_var, item, user)
	own_take(holder, slot_var)
	if(item.loc == holder || isnull(item.loc)) // a holder may keep it out of its contents (in nullspace)
		if(user && !eject_drop && !drop)
			user.put_in_hands(item)
		else
			item.forceMove(holder.drop_location())
	tell(isnull(message) ? eject_msg : message, user, holder, item)
	holder.slot_ejected(slot_var, item, user)
	return item

/// The gating a slot entry carries (cap_gate_reason() reads it off the entry).
/datum/interaction/capability/proc/take_gating(datum/capability/slot/slot, need_proc, need_else)
	cap = slot
	behind = slot.behind
	locked_by = slot.locked_by
	needs = need_proc
	else_say = need_else
	works_broken = slot.works_broken
	works_unpowered = slot.works_unpowered
	log = slot.log

/// Generated Insert.
/datum/interaction/capability/slot_insert
	category = INTERACTION_CAT_INSERT
	entry = INTERACTION_ENTRY_ITEM

/datum/interaction/capability/slot_insert/New(datum/capability/slot/slot, id)
	src.id = id
	name = slot.name
	held_type = slot.accepts
	requires = list(REQ_INTERACTION_REACH)
	default_action = INPUT_ACTION_USE
	take_gating(slot, slot.needs, slot.else_say)
	..()

/datum/interaction/capability/slot_insert/run_effect(mob/actor, atom/target, obj/item/held)
	var/datum/capability/slot/slot = cap
	. = slot.insert(target, held, actor)
	if(.)
		dispatch_record(actor, target, name, log, null)

/// Generated Eject, one per SLOT_VIA_* input.
/datum/interaction/capability/slot_eject
	category = INTERACTION_CAT_EJECT

/datum/interaction/capability/slot_eject/New(datum/capability/slot/slot, id, entry, item_holder)
	src.id = id
	src.entry = entry
	name = slot.eject_name
	switch(entry)
		if(INTERACTION_ENTRY_ALT)
			default_action = INPUT_ACTION_ALTERNATE
			requires = list(REQ_INTERACTION_REACH)
		if(INTERACTION_ENTRY_SELF)
			default_action = INPUT_ACTION_USE
			requires = item_holder ? list(REQ_SELF_USE_REACH) : list()
		if(null)
			default_action = null // chosen from the Menu
			requires = list(REQ_INTERACTION_REACH)
		else
			default_action = INPUT_ACTION_USE
			requires = list(REQ_INTERACTION_REACH)
			offered_when = list(REQ_EMPTY_HANDED)
			behind_gate = !slot.ungated
	take_gating(slot, slot.eject_needs, slot.eject_else_say)
	..()

/datum/interaction/capability/slot_eject/applies_to(atom/target)
	var/datum/capability/slot/slot = cap
	return target.vars[slot.slot_var] && ..()

/datum/interaction/capability/slot_eject/run_effect(mob/actor, atom/target, obj/item/held)
	var/datum/capability/slot/slot = cap
	if(slot.eject(target, actor))
		dispatch_record(actor, target, name, log, null)
	return TRUE // a refusal uses the input too

/// The slot capability of this atom for var `slot_var` (nameof()), or null.
/atom/proc/slot_capability(slot_var)
	for(var/datum/capability/slot/cap in caps_of(src))
		if(cap.slot_var == slot_var)
			return cap
	return null

/// Why `item` can't go into slot `slot` right now (text), SLOT_REFUSED_SILENT, SLOT_REFUSED_PASS,
/// or null. Compare `slot` with nameof(var).
/atom/proc/slot_refusal(slot, obj/item/item, mob/user)
	return null

/// `item` went into slot `slot`.
/atom/proc/slot_inserted(slot, obj/item/item, mob/user)
	return

/// Why `item` can't come out of slot `slot` right now (text), SLOT_REFUSED_SILENT, or null.
/atom/proc/slot_eject_refusal(slot, obj/item/item, mob/user)
	return null

/// `item` is about to come out of slot `slot` (still in, the var still set).
/atom/proc/slot_ejecting(slot, obj/item/item, mob/user)
	return

/// `item` came out of slot `slot` (already in the actor's hands or on the floor).
/atom/proc/slot_ejected(slot, obj/item/item, mob/user)
	return

/// Ejects slot `slot_var` (nameof()) from code. Returns the item or null.
/atom/proc/slot_eject(slot_var, mob/user, drop = FALSE, message)
	var/datum/capability/slot/cap = slot_capability(slot_var)
	return cap?.eject(src, user, drop, message)

/// Inserts `item` into slot `slot_var` (nameof()) from code. TRUE when it went in.
/atom/proc/slot_insert(slot_var, obj/item/item, mob/user)
	var/datum/capability/slot/cap = slot_capability(slot_var)
	if(!cap)
		return FALSE
	cap.insert(src, item, user)
	return vars[slot_var] == item

/// A held item for tgui data: {name, ref}, or null.
/proc/slot_ui(obj/item/item)
	return istype(item) ? list("name" = item.name, "ref" = REF(item)) : null
