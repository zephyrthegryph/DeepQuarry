// The access lock (doc/rewrite/final_api.html, section 11 "The library": lock(credentials)).
//
// An ID lock over the holder's controls. State key LOCK_LOCKED. Swiping an ID (or a PDA carrying one) on the holder, or alt-clicking it, toggles the
// lock for whoever the holder's own req_access / req_one_access lets in (a mapper's variation of them wins, as it does for doors); a silicon
// carries its own access. Declaring a lock gates the controls: every op with a ui_act() binding and every TAG_CONTROL op needs the lock open,
// except for a silicon or an admin ghost, who work a locked machine as they always did. An op that must work whatever the lock says
// (the night-shift setting) relaxes it by id: extend("nightshift", drop = "lock").
//
//   lock()                                       cards and PDAs; starts open
//   lock(starts_locked = nameof(lock_at_start))  starts locked while the holder's lock_at_start var says so (a map may clear it per instance)

MSG_DEF(lock/locked, "You lock %T%.", "%U% locks %T%.")
MSG_DEF(lock/unlocked, "You unlock %T%.", "%U% unlocks %T%.")
MSG_DEF_SELF(lock/is_locked, "It is locked.")
MSG_DEF_SELF(lock/is_unlocked, "It is unlocked.")
MSG_DEF_SELF(lock/denied, "Access denied.")
MSG_DEF_SELF(lock/engaged, "It is locked.")

CAPABILITY_TYPE(lock, CAP_LOCK, /datum/capability/lib/lock, key = NONE, id_types = null, starts_locked = FALSE)
cap_keys(CAP_LOCK, LOCKED = MSG(lock/is_unlocked))

/datum/capability/lib/lock
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/lock/entries()
	var/list/cards = id_types || list(/obj/item/card/id, /obj/item/pda)
	var/list/swipe = list()
	for(var/card_type in cards)
		swipe += item(card_type)
	return list(
		// A card (or PDA) on the holder: the card in hand is the credential.
		op("toggle", inputs(swipe), needs(req_credential_in_hand(cards, because = MSG(lock/denied))), toggles(LOCK_LOCKED), says(CAP_PROC(toggled_message)), wait(0), logs(LOG_GAME)),
		// An alt-click, with or without something in hand: what the actor carries is the credential.
		op("toggle_worn", inputs(hand(), item(/obj/item)), gesture(GESTURE_ALT), needs(req_credential_worn(cards, because = MSG(lock/denied))), toggles(LOCK_LOCKED), says(CAP_PROC(toggled_message)), wait(0), logs(LOG_GAME)),
		extend(TAG_UI, needs(req_unlocked_for_actor(id = "lock"))),
		extend(TAG_CONTROL, needs(req_unlocked_for_actor(id = "lock"))),
		examine_line(MSG(lock/is_locked), when = LOCK_LOCKED),
		examine_line(MSG(lock/is_unlocked), when = cond_not(LOCK_LOCKED)))

/// What the lock toggle just did.
/datum/capability/lib/lock/proc/toggled_message(datum/act/A)
	return lock_locked(A.holder) ? /datum/msg/lock/locked : /datum/msg/lock/unlocked

/// A lock that starts locked is locked from the moment its holder initializes (`starts_locked` is TRUE, or the name of a holder var that says).
/datum/capability/lib/lock/on_holder_init_ctx(datum/act/eval/A)
	var/wanted = starts_locked
	if(istext(wanted))
		wanted = A.holder.vars[wanted]
	if(wanted)
		cap_key_set(A.holder, LOCK_LOCKED, TRUE, null)

// ---- credentials ----

/// req_credential_in_hand(types): the card in the actor's hand is one of `types` and grants the holder's access (nothing required: anyone).
/proc/req_credential_in_hand(list/types, because = null)
	return part_make(/datum/entry/part/req/credential, list("types" = types, "in_hand" = TRUE, "because" = because))

/// req_credential_worn(types): the actor carries (worn ID or PDA, a silicon's own access) what grants the holder's access.
/proc/req_credential_worn(list/types, because = null)
	return part_make(/datum/entry/part/req/credential, list("types" = types, "in_hand" = FALSE, "because" = because))

/datum/entry/part/req/credential
	part_name = "req_credential"
	default_reason = /datum/msg/lock/denied

/datum/entry/part/req/credential/holds(datum/act/op/A)
	var/atom/holder = A.holder
	if(!istype(holder) || !A.actor)
		return FALSE
	if(A.authority & AUTH_ADMIN)
		return TRUE
	var/list/needs = access_needs(holder, null, null)
	return !!access_credential(holder, A.actor, src.args["in_hand"] ? A.held : null, needs[1], needs[2], src.args["types"])

/// req_unlocked_for_actor(): the holder's lock is open, or the actor works a locked machine anyway (a silicon, an admin ghost).
/proc/req_unlocked_for_actor(id = null)
	return part_make(/datum/entry/part/req/unlocked_for_actor, list("id" = id))

/datum/entry/part/req/unlocked_for_actor
	part_name = "req_unlocked"
	default_reason = /datum/msg/lock/engaged

/datum/entry/part/req/unlocked_for_actor/holds(datum/act/op/A)
	if(!lock_locked(A.holder))
		return TRUE
	return lock_exempt(A.holder, A.actor)

/datum/entry/part/req/unlocked_for_actor/read_keys(datum/act/op/A)
	return A.holder ? list(list(A.holder, "capkey:[LOCK_LOCKED]")) : list()

/// Does this actor work a locked holder regardless: a silicon with access to it (its own ID card), or an admin ghost that may interact?
/proc/lock_exempt(obj/holder, mob/user)
	if(!user)
		return FALSE
	if(istype(holder) && holder.siliconaccess(user))
		return TRUE
	if(isobserver(user))
		var/mob/observer/dead/D = user
		return D.can_admin_interact()
	return FALSE
