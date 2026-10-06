// cap_two_handed(): the item can be wielded in both hands for more force. Wielding is a self-use toggle
// (Z / attack_self, named "Wield" or "Unwield") that needs the other hand free and usable
// (is_held_twohanded(), can_wield_item()). The wielded state is the CAP_WIELDED bit; the force the
// item had before wielding is kept in its capability data and restored on unwield, so material
// weapons that derive their force keep it. Dropping the item, moving it out of the hands, or putting
// something in the other hand unwields it.
//
// Draw: with `icon_base`, the icon_state (and the in-hand item_state) is "[icon_base]1" wielded and
// "[icon_base]0" otherwise, the convention the existing twohanded weapons use.
//
//	/obj/item/material/twohanded/fireaxe/capabilities()
//		. = ..()
//		. += cap_two_handed(force_wielded = 30, icon_base = "fireaxe")
//		. += cap_block(chance = 15, needs_wielded = TRUE, verb = "parries")

/datum/capability/two_handed
	data_type = /datum/cap_two_handed_data
	works_broken = TRUE
	works_unpowered = TRUE
	/// Force while wielded; null derives it from the one-handed force times `multiplier`.
	var/force_wielded
	var/multiplier = 2
	/// The icon_state stem ("[icon_base]0"/"[icon_base]1"), or null to leave the icon alone.
	var/icon_base
	var/wield_sound
	var/unwield_sound

/datum/cap_two_handed_data
	/// The item's force before it was wielded.
	var/force_unwielded

/proc/cap_two_handed(force_wielded, multiplier = 2, icon_base, wield_sound, unwield_sound, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/two_handed/C = new
	C.force_wielded = force_wielded
	C.multiplier = multiplier
	C.icon_base = icon_base
	C.wield_sound = wield_sound
	C.unwield_sound = unwield_sound
	cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	return C

/datum/capability/two_handed/proc/wielded_force(one_handed)
	return isnull(force_wielded) ? round(one_handed * multiplier) : force_wielded

/datum/capability/two_handed/interactions(atom/holder)
	// The op "wield": the self-use (Z) wields and unwields.
	var/datum/capability/entry/wrapper = cap_use_self("Wield", GLOBAL_PROC_REF(cap_two_handed_toggle), works_broken = TRUE, works_unpowered = TRUE, needs = GLOBAL_PROC_REF(cap_two_handed_can_wield), name_proc = GLOBAL_PROC_REF(cap_two_handed_name), key = "wield")
	return list(adopt_entry(wrapper))

/datum/capability/two_handed/legacy_holder_init(atom/holder, mapload)
	if(!isitem(holder))
		return
	observe(holder, /datum/notice/item_dropped, holder, then(TYPE_PROC_REF(/obj/item, cap_two_handed_dropped)))
	observe(holder, /datum/notice/item_equipped, holder, then(TYPE_PROC_REF(/obj/item, cap_two_handed_equipped)))

/datum/capability/two_handed/draw(atom/holder, datum/look/look)
	if(icon_base)
		look.state("[icon_base][cap_has(holder, CAP_WIELDED) ? 1 : 0]")

GLOBAL_LIST_INIT(cap_examine_wielded, list("It is held in both hands."))
GLOBAL_LIST_INIT(cap_examine_unwielded, list("It can be wielded in both hands."))

/datum/capability/two_handed/examine(atom/holder, mob/user)
	if(cap_has(holder, CAP_WIELDED))
		return GLOB.cap_examine_wielded
	return GLOB.cap_examine_unwielded

/datum/capability/two_handed/legacy_ui_data(atom/holder, mob/user, list/data)
	data["wielded"] = cap_has(holder, CAP_WIELDED)

/proc/cap_two_handed_name(obj/item/holder, mob/user)
	return cap_has(holder, CAP_WIELDED) ? "Unwield" : "Wield"

/// needs: unwielding always works; wielding wants the other hand free and a body big enough.
/proc/cap_two_handed_can_wield(mob/user, obj/item/holder, obj/item/held)
	if(cap_has(holder, CAP_WIELDED))
		return TRUE
	var/mob/living/L = user
	if(!istype(L))
		return "you have no hands"
	if(!L.can_wield_item(holder))
		return "it's too big for you to wield"
	if(!holder.is_held_twohanded(L))
		return "you need your other hand free"
	return TRUE

/proc/cap_two_handed_toggle(obj/item/holder, mob/user, obj/item/held)
	if(cap_has(holder, CAP_WIELDED))
		cap_two_handed_set(holder, FALSE, user)
		act_message(user, holder, self = span_notice("You are now carrying %T% with one hand."), others = span_notice("%U% lets go of %T% with one hand."))
	else
		cap_two_handed_set(holder, TRUE, user)
		act_message(user, holder, self = span_notice("You grab %T% with both hands."), others = span_notice("%U% grabs %T% with both hands."))
	return TRUE

/// Wields (on) or unwields the item for user: force, the CAP_WIELDED bit, the in-hand sprite, and the
/// hook that unwields it when user fills the other hand. TRUE when the state changed.
/proc/cap_two_handed_set(obj/item/holder, on, mob/user)
	var/datum/capability/two_handed/C = cap_of(holder, /datum/capability/two_handed)
	if(!C || cap_has(holder, CAP_WIELDED) == !!on)
		return FALSE
	var/datum/cap_two_handed_data/D = cap_data(holder, C)
	if(on)
		D.force_unwielded = holder.force
		holder.force = C.wielded_force(holder.force)
		if(user)
			observe(user, /datum/notice/mob_equipped_item, holder, then(TYPE_PROC_REF(/obj/item, cap_two_handed_other_hand)))
	else
		if(!isnull(D.force_unwielded))
			holder.force = D.force_unwielded
		D.force_unwielded = null
		if(user)
			unobserve(user, /datum/notice/mob_equipped_item, holder)
	cap_set(holder, CAP_WIELDED, on)
	if(C.icon_base)
		holder.item_state = "[C.icon_base][on ? 1 : 0]"
	var/sound = on ? C.wield_sound : C.unwield_sound
	if(sound)
		playsound(holder, sound, 50, TRUE)
	holder.update_held_icon()
	return TRUE

/obj/item/proc/cap_two_handed_dropped(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/item_dropped/event = A
	cap_two_handed_set(src, FALSE, event.user)

/// Equipped into a slot that isn't a hand (a back, a belt): unwielded.
/obj/item/proc/cap_two_handed_equipped(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/item_equipped/event = A
	if(event.slot != SLOT_ID_HAND_L && event.slot != SLOT_ID_HAND_R)
		cap_two_handed_set(src, FALSE, event.equipper)

/// The wielder put something else in a hand: the other hand is no longer free.
/obj/item/proc/cap_two_handed_other_hand(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = A.target
	var/datum/notice/mob_equipped_item/event = A
	if(event.equipped_item == src)
		return
	if(event.slot == SLOT_ID_HAND_L || event.slot == SLOT_ID_HAND_R)
		cap_two_handed_set(src, FALSE, source)
