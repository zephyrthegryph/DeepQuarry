// toggle_state(): a two-state clothing (or any item) toggle: a hood up or down, a jacket buttoned or
// open, a mask up or hanging, sensors on or off. The state is one CAP_TOGGLE_* bit (`bit`, so an item
// can carry up to three toggles). It is reached three ways, all through the same entry: self-use (Z,
// in hand), the Menu, and a native verb named `verb_name` while the item is carried (verbs()).
//
// Per-instance effects stay the item's own procs: `apply` is a proc on the holder, (on, mob/user),
// called before the bit flips; it returns TRUE to go ahead, or FALSE/a reason text to refuse (a hood
// that can't go up over a helmet). `available` is a pure proc on the holder, () -> TRUE/FALSE: while
// FALSE the entry refuses with `else_say` and the verb is hidden (a jacket with no buttons).
//
// Draw: `on_state`/`off_state` are icon_states; with only `on_suffix`, on is
// "[initial icon_state][on_suffix]" and off the initial icon_state. Worn sprites update at once.
//
//	/obj/item/clothing/suit/storage/toggle/capabilities()
//		. = ..()
//		. += toggle_state("buttons", on_suffix = "_open", verb_name = "Toggle Coat Buttons", self_on = "You unbutton %T%.", self_off = "You button up %T%.")

/datum/capability/toggle_state
	works_broken = TRUE
	works_unpowered = TRUE
	/// The toggle's name: its UI data key, toggle_is_on()'s key and the default verb name.
	var/name
	var/bit = CAP_TOGGLE_1
	var/on_state
	var/off_state
	var/on_suffix
	/// The Menu, self-use and verb name.
	var/verb_name
	/// Proc on the holder, (on, mob/user): TRUE, or FALSE/reason text to refuse.
	var/apply
	/// Pure proc on the holder, (): FALSE hides the verb and refuses the entry.
	var/available
	var/self_on
	var/self_off
	var/others_on
	var/others_off
	var/examine_on
	var/examine_off
	/// The renamed native verb, made once per capability.
	var/tmp/verb_ref

/proc/toggle_state(name, on_state, off_state, on_suffix, verb_name, bit = CAP_TOGGLE_1, apply, available, needs, else_say, self_on, self_off, others_on, others_off, examine_on, examine_off, log)
	var/datum/capability/toggle_state/C = new
	C.name = name
	C.key = "toggle_state:[bit]"
	C.bit = bit
	C.on_state = on_state
	C.off_state = off_state
	C.on_suffix = on_suffix
	C.verb_name = verb_name || "Toggle [name]"
	C.apply = apply
	C.available = available
	C.needs = needs
	C.else_say = else_say
	C.self_on = self_on
	C.self_off = self_off
	C.others_on = others_on
	C.others_off = others_off
	C.examine_on = examine_on
	C.examine_off = examine_off
	C.log = log
	var/verb_path = cap_toggle_verb_path(bit)
	C.verb_ref = new verb_path(null, C.verb_name)
	return C

/// The generic verb proc for a toggle bit (renamed per capability by toggle_state()).
/proc/cap_toggle_verb_path(bit)
	switch(bit)
		if(CAP_TOGGLE_1)
			return /obj/item/proc/cap_toggle_verb_1
		if(CAP_TOGGLE_2)
			return /obj/item/proc/cap_toggle_verb_2
		if(CAP_TOGGLE_3)
			return /obj/item/proc/cap_toggle_verb_3
	CRASH("toggle_state(): bit [bit] is not a CAP_TOGGLE_* bit")

/// The toggle's entry: refuses while the toggle is unavailable, and knows its capability when it runs.
/datum/interaction/capability/toggle

/datum/interaction/capability/toggle/why_not(mob/actor, atom/target, obj/item/held)
	. = ..()
	if(.)
		return
	var/datum/capability/toggle_state/C = cap
	if(!C.is_available(target))
		return else_say || "you can't do that right now"

/datum/capability/toggle_state/interactions(atom/holder)
	var/datum/interaction/capability/toggle/E = new
	E.name = verb_name
	E.id = "self:toggle:[bit]"
	E.handler = TYPE_PROC_REF(/obj/item, cap_toggle_run)
	E.needs = needs
	E.else_say = else_say
	E.works_broken = TRUE
	E.works_unpowered = TRUE
	E.log = log
	E.entry = INTERACTION_ENTRY_SELF
	E.category = INTERACTION_CAT_TOGGLE
	E.default_action = INPUT_ACTION_USE
	E.requires = list(REQ_IN_INVENTORY)
	E.cap = src
	return list(E)

/datum/capability/toggle_state/verbs()
	return list(verb_ref)

/datum/capability/toggle_state/on_holder_init(atom/holder, mapload)
	holder.verbs += verb_ref

/datum/capability/toggle_state/hidden_verbs(atom/holder)
	return is_available(holder) ? null : list(verb_ref)

/datum/capability/toggle_state/proc/is_available(atom/holder)
	return !available || call(holder, available)()

/datum/capability/toggle_state/proc/state_for(atom/holder, on)
	if(on)
		if(on_state)
			return on_state
		return on_suffix ? "[initial(holder.icon_state)][on_suffix]" : null
	if(off_state)
		return off_state
	return (on_state || on_suffix) ? initial(holder.icon_state) : null

/datum/capability/toggle_state/draw(atom/holder, datum/look/look)
	var/state = state_for(holder, cap_has(holder, bit))
	if(state)
		look.state(state)

/datum/capability/toggle_state/examine(atom/holder, mob/user)
	var/text = cap_has(holder, bit) ? examine_on : examine_off
	return text ? list(text) : null

/datum/capability/toggle_state/ui_data(atom/holder, mob/user, list/data)
	data[name] = cap_has(holder, bit)

/// The toggle state named `name` on A: TRUE on, FALSE off, null when A has no such toggle.
/proc/toggle_is_on(atom/A, name)
	for(var/datum/capability/toggle_state/C in caps_of(A))
		if(C.name == name)
			return cap_has(A, C.bit)
	return null

/// The toggle capability of A named `name`, or null.
/proc/toggle_of(atom/A, name)
	for(var/datum/capability/toggle_state/C in caps_of(A))
		if(C.name == name)
			return C
	return null

/// The entry handler: flips the toggle the running entry belongs to.
/obj/item/proc/cap_toggle_run(mob/user, obj/item/held)
	var/datum/interaction/capability/E = GLOB.dispatch_context_now?.entry
	var/datum/capability/toggle_state/C = E?.cap
	if(!istype(C))
		return FALSE
	return cap_toggle_set(C, !cap_has(src, C.bit), user)

/// Turns toggle C on or off for user: apply() may refuse, then the bit flips, the look and worn
/// sprite update, and the message goes out. TRUE when it changed.
/obj/item/proc/cap_toggle_set(datum/capability/toggle_state/C, on, mob/user)
	on = !!on
	if(cap_has(src, C.bit) == on)
		return FALSE
	if(C.apply)
		var/result = call(src, C.apply)(on, user)
		if(istext(result))
			return refuse(user, result)
		if(!result)
			return UI_REFUSED
	cap_set(src, C.bit, on)
	refresh_look(src) // the worn sprite below reads icon_state now, not at the end of the frame
	if(istype(src, /obj/item/clothing))
		var/obj/item/clothing/worn = src
		worn.update_clothing_icon()
	else
		update_held_icon()
	if(user)
		var/self = on ? C.self_on : C.self_off
		var/others = on ? C.others_on : C.others_off
		if(self || others)
			act_message(user, src, self = self ? span_notice(self) : null, others = others ? span_notice(others) : null)
	return TRUE

// The native verbs, renamed per toggle by toggle_state(). Each runs the toggle's entry.
/obj/item/proc/cap_toggle_verb_1()
	set name = "Toggle"
	set category = "Object"
	set src in usr
	cap_toggle_verb_run(usr, CAP_TOGGLE_1)

/obj/item/proc/cap_toggle_verb_2()
	set name = "Toggle"
	set category = "Object"
	set src in usr
	cap_toggle_verb_run(usr, CAP_TOGGLE_2)

/obj/item/proc/cap_toggle_verb_3()
	set name = "Toggle"
	set category = "Object"
	set src in usr
	cap_toggle_verb_run(usr, CAP_TOGGLE_3)

/// Runs the toggle entry for `bit` as user, through the interaction pipeline (gating, refusals, log).
/obj/item/proc/cap_toggle_verb_run(mob/user, bit)
	for(var/datum/interaction/capability/toggle/E in cap_interactions(src))
		var/datum/capability/toggle_state/C = E.cap
		if(C.bit == bit)
			return E.attempt(user, src, src)
	return FALSE
