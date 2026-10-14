// The door capability (doc/rewrite/final_api.html, section 11 "The library": doors(...); section 16.2 "Airlock").
//
// A powered door that opens and closes for whoever its access lets through. Two ops, doors.open and doors.close, each reached by an empty hand or any
// held item (an ID card, a bottle: touching a door tries it, as it always has). Both need the door to be still (not mid-swing), a person with a hand
// to do it (a cyborg works a door through its interface, not by clicking it), the door's own access (req_access() asks the door's allowed(), so
// emergency access and bolts live in the door type) and a door that works; a refused one flashes the denial and says why. The mechanism (the
// animation, the density flip, the tiles, the timers) is the door's own, named by the params:
//
//   doors()                                     open() and close()
//   doors(open = "airlock_open", close = ...)   other proc names, procs of the door taking (forced)
//
// What each kind of door adds is declared beside it: bolts and electrification are stats of the airlock, a firedoor opens through a prompt, a blast
// door answers a button. The bump (a mob, a mech, a bot, a wheelchair walking into the door) is movement, not an op: Bumped() asks the same access
// and calls the same mechanism.

MSG_DEF_SELF(door/denied, "Access denied.")
MSG_DEF_SELF(door/unpowered, "It has no power.")

CAPABILITY_TYPE(doors, CAP_DOORS, /datum/capability/lib/doors, key = NONE, open = "open", close = "close")

/datum/capability/lib/doors

/datum/capability/lib/doors/entries()
	var/list/by_touch = list(inputs(hand(), item(/obj/item)), \
		when(cond_not(nameof(/obj/machinery/door::operating))), \
		when(req_actor_kind(/mob/living/silicon/robot, not = TRUE)), \
		needs(req_access(), req_is(STAT_OPERABLE, because = MSG(door/unpowered))), \
		wait(0))
	return list(
		op("open", by_touch, priority(OP_PRIORITY_NORMAL), when(nameof(/obj/machinery/door::density)), then(CAP_PROC(open_door))),
		op("close", by_touch, priority(OP_PRIORITY_NORMAL), when(cond_not(nameof(/obj/machinery/door::density))), then(CAP_PROC(close_door))),
		on_op("doors.open", then(CAP_PROC(denied)), outcome = ACT_REFUSED))

/// The touch worked: the door's own mechanism opens it.
/datum/capability/lib/doors/proc/open_door(datum/act/op/A)
	var/obj/machinery/door/D = A.holder
	D.add_fingerprint(A.actor)
	call(D, open)(FALSE)
	return OP_OK

/datum/capability/lib/doors/proc/close_door(datum/act/op/A)
	var/obj/machinery/door/D = A.holder
	D.add_fingerprint(A.actor)
	call(D, close)(FALSE)
	return OP_OK

/// The touch was refused (no access, no power): a closed door flashes its denial.
/datum/capability/lib/doors/proc/denied(datum/act/A)
	var/obj/machinery/door/D = A.holder
	if(istype(D) && D.density)
		D.do_animate("deny")
