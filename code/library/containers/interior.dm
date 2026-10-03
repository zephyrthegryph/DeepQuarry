// interior(escape_wait, escape_chance) (doc/rewrite/final_api.html, section 11 "Containers and slots"; section 16.6): something that holds living things
// inside it, and the one op they have from the inside: "interior.escape".
//
//   CAPABILITIES(/obj/belly, interior(escape_wait = 30 SECONDS, escape_chance = nameof(escapechance)))
//
// The capability declares the slot SLOT_BELLY_INTERIOR (accepts /mob/living). escape is an inside() op (a hand from inside: the click, the context
// menu's pick and an AI all reach it): the actor waits escape_wait (the wait stops if the actor dies or the container goes), the roll is
// escape_chance (a percent, or the name of a var of the holder: the belly's own `escapechance`), and on success the actor is put on the holder's tile.
// A failed roll ends committed with rolled FALSE and the struggle message: the wait was spent and nothing moved.
//
// Not wired yet (the slots engine is eng-slots'): the slot has no containment-ledger relation here, so "inside" is the engine's own test (the actor's
// loc chain reaches the holder, REACH_INSIDE) and the exit is a direct forceMove. When the ledger slot lands, release_actor() becomes the slot's move out.

CAPABILITY_TYPE(interior, CAP_INTERIOR, /datum/capability/lib/interior, key = NONE, escape_wait = 30 SECONDS, escape_chance = 100)

MSG_DEF(interior/escape, "You escape from %T%.", "%U% escapes from %T%.")
MSG_DEF(interior/struggle, "You struggle inside %T% but stay put.", "%U% struggles inside %T%.")

/datum/capability/lib/interior/entries()
	return list(
		slot(SLOT_BELLY_INTERIOR, accepts = list(/mob/living)),
		op("escape", inside(), label("Escape"),
			wait(escape_wait, keeps = TARGET_PRESENT | ALIVE),
			chance(escape_chance, otherwise = list(says(MSG(interior/struggle)))),
			then(CAP_PROC(release_actor)), says(MSG(interior/escape)), logs(LOG_GAME)))

/// Puts the escaping actor on the holder's tile.
/datum/capability/lib/interior/proc/release_actor(datum/act/op/A)
	var/mob/escaper = A.actor
	var/atom/movable/holder = A.holder
	var/atom/where = get_turf(holder) || holder.loc
	if(!escaper || !where)
		return OP_FAILED
	escaper.forceMove(where)
	return OP_OK
