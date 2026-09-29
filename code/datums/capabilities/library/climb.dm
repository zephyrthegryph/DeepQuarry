// climb(): mobs can climb onto (or, with `vaulting`, over) the holder. Wraps the climbable behaviour
// (code/datums/behaviours/climbable.dm): at init the holder is made climbable with `kind`, which
// brings the mouse-drag climb, the "Climb structure" verb, the examine line, shaking climbers off
// and the timed climb itself. The holder's `climbable_delay` stays the per-instance truth: `delay` is
// the type default and a map edit wins. The capability adds a Menu entry that starts the same climb.
//
//	/obj/structure/railing/capabilities()
//		. = ..()
//		. += climb(delay = 5 SECONDS, vaulting = TRUE, kind = /datum/om/behaviour/climbable/unanchored_can_break)

/datum/capability/climb
	works_broken = TRUE
	works_unpowered = TRUE
	var/delay = 3.5 SECONDS
	var/vaulting = FALSE
	/// The climbable behaviour type (a /datum/om/behaviour/climbable subtype: tables, cliffs, railings).
	var/kind = /datum/om/behaviour/climbable

/proc/climb(delay = 3.5 SECONDS, vaulting = FALSE, kind = /datum/om/behaviour/climbable, behind = NONE, log)
	var/datum/capability/climb/C = new
	C.delay = delay
	C.vaulting = vaulting
	C.kind = kind
	C.behind = behind
	C.log = log
	return C

/datum/capability/climb/on_holder_init(atom/holder, mapload)
	var/obj/O = holder
	if(!istype(O) || O.climbable_type)
		return // not an obj, or its own Initialize() already made it climbable
	var/instance_delay = O.climbable_delay != initial(O.climbable_delay) ? O.climbable_delay : delay
	O.make_climbable(kind, instance_delay, vaulting)

/datum/capability/climb/interactions(atom/holder)
	var/datum/interaction/capability/E = adopt_entry(hand("Climb", TYPE_PROC_REF(/obj, cap_climb_start), behind = behind, needs = TYPE_PROC_REF(/obj, cap_climb_ok), works_broken = TRUE, works_unpowered = TRUE, log = log))
	E.default_action = null // Menu only: a click keeps doing the holder's own thing, a drag climbs
	return list(E)

/// needs: the holder is still climbable (a table flipped by the flip() capability stays climbable).
/obj/proc/cap_climb_ok(mob/user, obj/item/held)
	if(!climbable_type)
		return "it can't be climbed"
	if(!isliving(user))
		return "you can't climb"
	if(user in climbers)
		return "you're already climbing it"
	return TRUE

/// Starts the climb through the behaviour's own event (its checks, the timed climb, the messages).
/obj/proc/cap_climb_start(mob/user, obj/item/held)
	om_emit(src, new /datum/om/event/climb_start(user))
	return TRUE
