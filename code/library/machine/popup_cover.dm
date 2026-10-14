// popup_cover(raised_while =, transition =, on_move =): a cover the holder raises and lowers by itself (doc/rewrite/final_api.html, section 11
// "The library": popup_cover(raised_while =); section 16.3).
//
// The cover follows a condition: while `raised_while` holds it rises, when it stops it lowers, each move taking `transition`. State keys
// POPUP_COVER_RAISED and POPUP_COVER_MOVING; while either holds the holder is solid (a contribution to STAT_DENSITY). A move that is under way
// finishes before the next starts, so a condition that flickers ends with the cover where the condition says. `on_move` names a holder proc,
// x(datum/act/A, raising), run as a move starts (its animation and sound). What the raised cover means (armour, aim) the holder reads through
// popup_cover_raised(holder) and popup_cover_moving(holder).
//
//   popup_cover(raised_while = PROC_REF(engaging), on_move = PROC_REF(cover_moves))      a turret's cover: up while it engages

MSG_DEF_SELF(popup_cover/lowered, "Its cover is down.")
MSG_DEF_SELF(popup_cover/still, "Its cover is still.")

CAPABILITY_TYPE(popup_cover, CAP_POPUP_COVER, /datum/capability/lib/popup_cover, key = NONE, raised_while = null, transition = 1 SECOND, on_move = null)
cap_keys(CAP_POPUP_COVER, RAISED = MSG(popup_cover/lowered), MOVING = MSG(popup_cover/still))

/datum/capability/lib/popup_cover

/datum/capability/lib/popup_cover/entries()
	return list(
		on_change(raised_while, ANY, then(CAP_PROC(condition_moved))),
		when(cond_any(POPUP_COVER_RAISED, POPUP_COVER_MOVING), contributes(STAT_DENSITY, TRUE, priority = PRIORITY_FORCE)))

/// The condition changed: the cover starts toward it, unless it is already moving (the move ends by looking again).
/datum/capability/lib/popup_cover/proc/condition_moved(datum/act/A)
	follow(A.holder)

/// Starts the cover toward what `raised_while` says now, when it is not there and not already moving.
/datum/capability/lib/popup_cover/proc/follow(datum/holder)
	if(!holder || QDELETED(holder) || popup_cover_moving(holder))
		return
	var/wanted = !!change_condition(holder, raised_while)
	if(popup_cover_raised(holder) == wanted)
		return
	cap_key_set(holder, POPUP_COVER_MOVING, TRUE, null)
	if(on_move)
		var/datum/act/eval/E = take(/datum/act/eval)
		E.holder = holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
		E.cap = src
		call(holder, on_move)(E, wanted)
		E.release()
	after(holder, transition, GLOBAL_PROC_REF(popup_cover_settled), key = "popup_cover", with = list(holder, wanted))

/// A move ended: the cover is where it went, and starts again if the condition changed meanwhile.
/proc/popup_cover_settled(datum/holder, raised)
	if(!holder || QDELETED(holder))
		return
	cap_key_set(holder, POPUP_COVER_RAISED, raised, null)
	cap_key_set(holder, POPUP_COVER_MOVING, FALSE, null)
	var/datum/capability/lib/popup_cover/C = cap_of(holder, CAP_POPUP_COVER)
	C?.follow(holder)
