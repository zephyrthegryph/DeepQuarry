// cap_reach(): how many tiles away the item attacks. The item's `reach` stays the truth the click code
// reads (attack_can_reach()); `tiles` is the type default written onto it at init, and a map edit or
// a runtime write (a mech tool that extends it) wins.
//
//	/obj/item/material/twohanded/spear/capabilities()
//		. = ..()
//		. += cap_reach(tiles = 2)

/datum/capability/reach
	works_broken = TRUE
	works_unpowered = TRUE
	var/tiles = 1

/proc/cap_reach(tiles = 2, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/reach/C = new
	C.tiles = max(1, round(tiles))
	cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	return C

/datum/capability/reach/on_holder_init(atom/holder, mapload)
	if(!isitem(holder))
		return
	var/obj/item/I = holder
	cap_default_var(I, nameof(I.reach), tiles)

/datum/capability/reach/examine(atom/holder, mob/user)
	var/obj/item/I = holder
	if(!istype(I) || I.reach <= 1)
		return null
	return list("It can strike from [I.reach] tiles away.")
