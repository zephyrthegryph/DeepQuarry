// The slot capability (doc/rewrite/dx_conventions.md §2): a holder var holding at most one item.
//
//	/obj/item/flashlight/capabilities()
//		. = ..()
//		. += cap_slot(nameof(cell), /obj/item/cell/device, eject_via = SLOT_VIA_HAND, eject_needs = PROC_REF(in_other_hand))
//
//	/obj/machinery/power/apc/capabilities()
//		. = ..()
//		. += cap_slot(nameof(cell), /obj/item/cell, needs = req_set(COVER), part = LOOK_CELL)
//
// It supplies: an Insert op for the accepted types (a full slot refuses "%T% already holds
// %I%.", passes to the next entry, or swaps), an Eject op per eject_via input (offered
// while the var is set), the examine line, an appearance overlay while filled (layer = "state"; the
// holder is then marked when its item changes, through draws_var), and UI data
// (data["caps"][ui_key]["item"] = {name, ref} or null). Insert and eject run through cap_dispatch(),
// so an ask_*() inside a slot hook re-validates and the dispatcher records the action once. The item
// moves with one ownership transfer: out of the hand, slot or container it is in, into the holder,
// adopted with rel_set() (own_take() on the way out). The slot owns its var (owned():
// owns(var, policy = OWN_CONTAINED)): the holder type declares nothing for it in ownership(). Hooks: procs of the slot
// capability that take the holder (refusal(), inserted(), ejected()); a holder that reacts declares a slot subtype
// overriding them and passes it as cap_slot(..., slot_type = /datum/capability/slot/<x>). From code:
// slot_insert(nameof(var), item, user) and slot_eject(nameof(var), user).

/datum/capability/slot
	layer_name = CAP_NO_LAYER
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
	/// Key of the UI data entry under data["caps"] (default: the var name); null for none.
	var/ui_key_name


/**
 * The slot capability for holder var `var_name` (nameof(var)) holding one `accepts` (a type or a
 * list of types). Named options, all defaulted: the standard gating (behind, blocked_by, locked_by,
 * needs + else_say, works_broken, works_unpowered, log; they gate insert and eject alike),
 * eject_needs + eject_else_say (the eject only), name, eject_name, insert_msg, eject_msg, full_msg,
 * swap_msg (templates or /datum/msg types; null for silence), eject_via, eject_drop, ungated,
 * when_full, no_insert, examine_held, examine_empty, part (the look part drawn while filled, resolved by the
 * naming convention: "<base>-<part>", else "<part>"; null: none), ui_key; slot_type: a /datum/capability/slot subtype for a library capability built on
 * the slot (cap_cell_holder()).
 */
/proc/cap_slot(var_name, accepts = /obj/item, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, eject_needs, eject_else_say = "you can't do that right now", name, eject_name, insert_msg = "You insert %I% into %T%.", eject_msg = "You remove %I% from %T%.", full_msg = "%T% already holds %I%.", swap_msg = "You swap %I% out of %T%.", eject_via = SLOT_VIA_ALT, eject_drop = FALSE, ungated = FALSE, when_full = SLOT_FULL_REFUSE, no_insert = FALSE, examine_held = null, examine_empty = null, ui_key = "", slot_type = /datum/capability/slot, at, part)
	var/datum/capability/slot/cap = new slot_type
	cap.slot_var = var_name
	cap.key = "slot:[var_name]"
	cap.accepts = accepts
	cap_gating(cap, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log, at = at)
	cap.layer_name = part || CAP_NO_LAYER
	if(part)
		cap.draws_var = var_name // it draws its item: a change to the item marks the holder
	cap.eject_needs = eject_needs
	cap.eject_else_say = eject_else_say
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
	cap.ui_key_name = ui_key == "" ? var_name : ui_key
	return cap

/**
 * The slot's ops, keyed by its var: "insert_<var>" (a click with an accepted item, ACT_USE) and one eject per eject_via
 * input: "eject_<var>" by hand (a click with an empty hand, ACT_USE at OP_PRIORITY_TAKE_OUT, so it goes ahead of the
 * holder's own empty-hand use: the APC's cell over its interface), "eject_<var>_alt" (ACT_EJECT, an alt-click),
 * "eject_<var>_self" (a self-use of an item holder, ACT_USE offering req_self_held()) and "eject_<var>_menu" (ACT_NONE:
 * the Menu, radial or command bar only).
 */
/datum/capability/slot/interactions(atom/holder)
	. = list()
	// By the var alone: ids are unique per target, and the built entries are shared by every type
	// holding this (interned) capability, so the first holder's type must not leak into them.
	var/slug = dq_interaction_slug("_[slot_var]")
	if(!no_insert)
		. += op_attach(new /datum/interaction/capability/slot_insert(src, "slot_insert[slug]"), "insert_[slot_var]")
	var/static/list/via_entries = list("[SLOT_VIA_ALT]" = INTERACTION_ENTRY_ALT, "[SLOT_VIA_HAND]" = INTERACTION_ENTRY_HAND, "[SLOT_VIA_USE]" = INTERACTION_ENTRY_SELF, "[SLOT_VIA_VERB]" = null)
	for(var/flag in list(SLOT_VIA_ALT, SLOT_VIA_HAND, SLOT_VIA_USE, SLOT_VIA_VERB))
		if(!(eject_via & flag))
			continue
		var/datum/interaction/capability/slot_eject/E = new(src, "slot_eject[slug]_[flag]", via_entries["[flag]"], ispath(holder.type, /obj/item))
		switch(flag)
			if(SLOT_VIA_HAND)
				op_attach(E, "eject_[slot_var]", ACT_USE, OP_PRIORITY_TAKE_OUT)
			if(SLOT_VIA_ALT)
				op_attach(E, "eject_[slot_var]_alt", ACT_EJECT)
			if(SLOT_VIA_USE)
				op_attach(E, "eject_[slot_var]_self", ACT_USE, offered = req_self_held())
			if(SLOT_VIA_VERB)
				op_attach(E, "eject_[slot_var]_menu", ACT_NONE)
		. += E

/datum/capability/slot/examine(atom/holder, mob/user)
	var/obj/item/item = holder.vars[slot_var]
	var/text = item ? examine_held : examine_empty
	return text ? msg_fill(text, null, holder, item) : null

/datum/capability/slot/draw(atom/holder, datum/look/look)
	draw_layer(look, when = !!holder.vars[slot_var])

/// The overlay while filled and the UI item both read the slot's var.
/datum/capability/slot/derived_reads(atom/holder)
	. = list(drawn_from(slot_var))
	if(ui_key_name)
		. += ui_from(slot_var)

/datum/capability/slot/ui_key()
	return ui_key_name

/datum/capability/slot/legacy_ui_data(atom/holder, mob/user, list/data)
	if(ui_key_name)
		data["item"] = slot_ui(holder.vars[slot_var])

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

/// The slot owns its var: the item sits in the holder's contents (its ledger slot decides at teardown).
/datum/capability/slot/owned()
	return list(owns(slot_var, policy = OWN_CONTAINED))

/// The one-call transfer in: out of the hand, slot or container it is in, into holder, adopted.
/datum/capability/slot/proc/adopt(atom/holder, obj/item/item, mob/user)
	return move_into(holder, slot_var, item, user)

/// Puts `item` into the slot on `holder`. TRUE when it went in, UI_REFUSED when the input is used but
/// refused, FALSE when the slot declines (SLOT_FULL_PASS, SLOT_REFUSED_PASS, a type it doesn't accept)
/// so the next entry answers.
/datum/capability/slot/proc/insert(atom/holder, obj/item/item, mob/user)
	if(!ismovable(item) || !is_type_in_list(item, islist(accepts) ? accepts : list(accepts)))
		return FALSE
	var/obj/item/current = holder.vars[slot_var]
	if(isdatum(current) && QDELETED(current))
		rel_take(holder, slot_var)
		current = null
	if(current && when_full != SLOT_FULL_SWAP)
		if(when_full == SLOT_FULL_PASS)
			return FALSE
		tell(full_msg, user, holder, current, warning = TRUE)
		return UI_REFUSED
	var/refusal = refusal(holder, item, user)
	if(refusal)
		if(refusal == SLOT_REFUSED_PASS)
			return FALSE
		if(refusal != SLOT_REFUSED_SILENT)
			to_chat(user, span_warning(refusal))
		return UI_REFUSED
	if(current)
		eject(holder, null, TRUE, "")
		if(holder.vars[slot_var])
			return UI_REFUSED // the swap was refused
		tell(swap_msg, user, holder, current)
	if(!adopt(holder, item, user))
		return UI_REFUSED
	tell(insert_msg, user, holder, item)
	inserted(holder, item, user)
	return TRUE

/// Takes the item out of the slot on `holder`, to `user`'s hands (or the floor with `drop`),
/// telling the actor `message` (eject_msg when null, "" for none). Returns the item.
/datum/capability/slot/proc/eject(atom/holder, mob/user, drop = FALSE, message)
	var/obj/item/item = holder.vars[slot_var]
	if(!item)
		return null
	var/refusal = slot_eject_refusal(holder, slot_var, item, user)
	if(refusal)
		if(refusal != SLOT_REFUSED_SILENT)
			to_chat(user, span_warning(refusal))
		return null
	slot_ejecting(holder, slot_var, item, user)
	rel_take(holder, slot_var)
	if(item.loc == holder || isnull(item.loc)) // a holder may keep it out of its contents (in nullspace)
		if(user && !eject_drop && !drop)
			user.put_in_hands(item)
		else
			item.forceMove(holder.drop_location())
	tell(isnull(message) ? eject_msg : message, user, holder, item)
	ejected(holder, item, user)
	return item

/// Generated Insert: runs /atom/proc/cap_slot_do_insert through cap_dispatch() (the base run_effect),
/// with the slot capability's gating merged on by cap_apply_gating().
/datum/interaction/capability/slot_insert
	category = INTERACTION_CAT_INSERT
	entry = INTERACTION_ENTRY_ITEM

/datum/interaction/capability/slot_insert/New(datum/capability/slot/slot, id)
	src.id = id
	cap = slot
	name = slot.name
	held_type = slot.accepts
	default_action = INPUT_ACTION_USE
	handler = GLOBAL_PROC_REF(cap_slot_do_insert)
	needs = GLOBAL_PROC_REF(cap_in_reach)
	..()

/// Generated Eject, one per SLOT_VIA_* input: runs /atom/proc/cap_slot_do_eject through cap_dispatch().
/datum/interaction/capability/slot_eject
	category = INTERACTION_CAT_EJECT
	/// Only meant with an empty hand (the hand eject): anything held falls through to the next entry.
	var/empty_handed = FALSE

/datum/interaction/capability/slot_eject/New(datum/capability/slot/slot, id, entry, item_holder)
	src.id = id
	src.entry = entry
	cap = slot
	name = slot.eject_name
	handler = GLOBAL_PROC_REF(cap_slot_do_eject)
	var/list/need_procs = list()
	switch(entry)
		if(INTERACTION_ENTRY_ALT)
			default_action = INPUT_ACTION_ALTERNATE
			need_procs += GLOBAL_PROC_REF(cap_in_reach)
		if(INTERACTION_ENTRY_SELF)
			default_action = INPUT_ACTION_USE
			if(item_holder)
				need_procs += GLOBAL_PROC_REF(cap_in_hand)
		if(null)
			default_action = null // chosen from the Menu
			need_procs += GLOBAL_PROC_REF(cap_in_reach)
		else
			default_action = INPUT_ACTION_USE
			need_procs += GLOBAL_PROC_REF(cap_in_reach)
			empty_handed = TRUE
			behind_gate = !slot.ungated
	if(slot.eject_needs)
		need_procs += slot.eject_needs
		else_say = slot.eject_else_say
	needs = length(need_procs) ? need_procs : null
	..()

/datum/interaction/capability/slot_eject/is_meant(mob/actor, atom/target, obj/item/held)
	if(empty_handed && held)
		return FALSE
	return ..()

/datum/interaction/capability/slot_eject/applies_to(atom/target)
	var/datum/capability/slot/slot = cap
	return target.vars[slot.slot_var] && ..()

/// The slot capability of the entry being dispatched now (read before anything can sleep).
/proc/cap_slot_dispatched()
	var/datum/dispatch_context/ctx = GLOB.dispatch_context_now
	var/datum/interaction/capability/E = ctx?.entry
	if(!istype(E) || !istype(E.cap, /datum/capability/slot))
		return null
	return E.cap

/// The insert entry's handler (cap_dispatch()).
/proc/cap_slot_do_insert(atom/holder, mob/user, obj/item/held)
	var/datum/capability/slot/slot = cap_slot_dispatched()
	return slot?.insert(holder, held, user)

/// The eject entries' handler (cap_dispatch()). A refusal uses the input too.
/proc/cap_slot_do_eject(atom/holder, mob/user, obj/item/held)
	var/datum/capability/slot/slot = cap_slot_dispatched()
	return slot?.eject(holder, user) ? TRUE : UI_REFUSED

/// The slot capability of this atom for var `slot_var` (nameof()), or null.
/proc/slot_capability(atom/holder, slot_var)
	for(var/datum/capability/slot/cap in caps_of(holder))
		if(cap.slot_var == slot_var)
			return cap
	return null

/// Why `item` can't go into this slot on holder right now (text), SLOT_REFUSED_SILENT, SLOT_REFUSED_PASS, or null.
/// A holder that refuses some items declares a slot subtype overriding it.
/datum/capability/slot/proc/refusal(atom/holder, obj/item/item, mob/user)
	return null

/// `item` went into this slot on holder.
/datum/capability/slot/proc/inserted(atom/holder, obj/item/item, mob/user)
	return

/// Why `item` can't come out of slot `slot` right now (text), SLOT_REFUSED_SILENT, or null.
/proc/slot_eject_refusal(atom/holder, slot, obj/item/item, mob/user)
	return null

/// `item` is about to come out of slot `slot` (still in, the var still set).
/proc/slot_ejecting(atom/holder, slot, obj/item/item, mob/user)
	return

/// `item` came out of this slot on holder (already in the actor's hands or on the floor).
/datum/capability/slot/proc/ejected(atom/holder, obj/item/item, mob/user)
	return

/// Ejects slot `slot_var` (nameof()) from code. Returns the item or null.
/proc/slot_eject(atom/holder, slot_var, mob/user, drop = FALSE, message)
	var/datum/capability/slot/cap = slot_capability(holder, slot_var)
	return cap?.eject(holder, user, drop, message)

/// Inserts `item` into slot `slot_var` (nameof()) from code. TRUE when it went in.
/proc/slot_insert(atom/holder, slot_var, obj/item/item, mob/user)
	var/datum/capability/slot/cap = slot_capability(holder, slot_var)
	if(!cap)
		return FALSE
	cap.insert(holder, item, user)
	return holder.vars[slot_var] == item

/// A held item for tgui data: {name, ref}, or null.
/proc/slot_ui(obj/item/item)
	return istype(item) ? list("name" = item.name, "ref" = REF(item)) : null
