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
//   lock(id_types = list(/obj/item/card/id), alt = FALSE)   only an ID in hand works it, and an alt-click is left to the holder (a lockbox opens on one)
//   lock(wire = WIRE_IDSCAN)                     brings the ID scan wire (on a holder with wires()): the lock works only while it is intact, and a
//                                                pulse opens the lock for 30 seconds

MSG_DEF(lock/locked, "You lock %T%.", "%U% locks %T%.")
MSG_DEF(lock/unlocked, "You unlock %T%.", "%U% unlocks %T%.")
MSG_DEF_SELF(lock/is_locked, "It is locked.")
MSG_DEF_SELF(lock/is_unlocked, "It is unlocked.")
MSG_DEF_SELF(lock/denied, "Access denied.")
MSG_DEF_SELF(lock/engaged, "It is locked.")

CAPABILITY_TYPE(lock, CAP_LOCK, /datum/capability/lib/lock, key = NONE, id_types = null, starts_locked = FALSE, alt = TRUE, powered = TRUE, guarded = TRUE, wire = null)
cap_keys(CAP_LOCK, LOCKED = MSG(lock/is_unlocked))

/datum/capability/lib/lock
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/lock/entries()
	var/list/cards = id_types || list(/obj/item/card/id, /obj/item/pda)
	var/list/swipe = list()
	for(var/card_type in cards)
		swipe += item(card_type)
	// The library default: an electronic lock works only on a holder that has power and nobody subverted (powered = FALSE, guarded = FALSE: a
	// mechanical one, or one whose subversion leaves it working).
	var/list/guards = list(powered ? req_operable() : null, guarded ? req_not_subverted() : null, wire ? req_wire(wire) : null)
	return list(
		// A card (or PDA) on the holder: the card in hand is the credential.
		op("toggle", inputs(swipe), needs(guards, req_credential_in_hand(cards, because = MSG(lock/denied))), toggles(LOCK_LOCKED), says(CAP_PROC(toggled_message)), wait(0), logs(LOG_GAME)),
		// An alt-click, with or without something in hand: what the actor carries is the credential.
		alt ? op("toggle_worn", inputs(hand()), priority(OP_PRIORITY_PART), when(CAP_PROC(worn_credential_offered)), needs(guards), toggles(LOCK_LOCKED), says(CAP_PROC(toggled_message)), wait(0), logs(LOG_GAME)) : null,
		extend(TAG_UI, needs(req_unlocked_for_actor(id = "lock"))),
		extend(TAG_CONTROL, needs(req_unlocked_for_actor(id = "lock"))),
		examine_line(MSG(lock/is_locked), when = LOCK_LOCKED),
		examine_line(MSG(lock/is_unlocked), when = cond_not(LOCK_LOCKED)))

/datum/capability/lib/lock/brings_wires()
	return wire ? list(wire) : null

/// The ID scan wire pulsed (WIRE_DEF in code/library/machine/wires.dm): the lock lets go, and locks again 30 seconds later.
/datum/capability/lib/lock/proc/id_wire_pulsed(datum/holder, pulsed_wire, mob/user)
	cap_key_set(holder, LOCK_LOCKED, FALSE, null)
	after(holder, 30 SECONDS, GLOBAL_PROC_REF(lock_wire_relocks), key = "id_scan_relock", with = list(holder), keeps_dead = TRUE)

/proc/lock_wire_relocks(datum/holder)
	if(holder && !QDELETED(holder))
		cap_key_set(holder, LOCK_LOCKED, TRUE, null)

/// The empty hand's touch is the lock's only where what the actor carries opens it (anything else the touch means is left alone).
/datum/capability/lib/lock/proc/worn_credential_offered(datum/act/op/A)
	return isnull(A.held) && req_credential_worn(id_types || list(/obj/item/card/id, /obj/item/pda)).holds(A)

/datum/capability/lib/lock/proc/toggled_message(datum/act/A)
	return lock_locked(A.holder) ? /datum/msg/lock/locked : /datum/msg/lock/unlocked

/// A lock that starts locked is locked from the moment its holder initializes (`starts_locked` is TRUE, or the name of a holder var that says).
/datum/capability/lib/lock/on_holder_init(datum/act/eval/A)
	var/wanted = starts_locked
	if(istext(wanted))
		wanted = A.holder.vars[wanted]
	if(wanted)
		key_set(A.holder, LOCK_LOCKED, TRUE)

// ---- credentials ----

/// req_credential_in_hand(types): the card in the actor's hand is one of `types` and grants the holder's access (nothing required: anyone).
/proc/req_credential_in_hand(list/types, because = null)
	return part_make(/datum/entry/part/req/credential, list("types" = types, "in_hand" = TRUE, "because" = because))

/// req_credential_worn(types): the actor carries (worn ID or PDA, a silicon's own access) what grants the holder's access.
/proc/req_credential_worn(list/types, because = null)
	RETURN_TYPE(/datum/entry/part/req/credential)
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
	return silicon_or_admin(A) || window_vouched(A) // a silicon over a link the holder lets in, an admin ghost, or a window that vouches (code/library/access/window_access.dm)

/datum/entry/part/req/unlocked_for_actor/read_keys(datum/act/op/A)
	return A.holder ? list(list(A.holder, "capkey:[LOCK_LOCKED]")) : list()
