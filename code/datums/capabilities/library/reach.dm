// reach(): how many tiles away the item attacks. The item's `reach` stays the truth the click code
// reads (attack_can_reach()); `tiles` is the type default written onto it at init, and a map edit or
// a runtime write (a mech tool that extends it) wins.
//
//	/obj/item/material/twohanded/spear/capabilities()
//		. = ..()
//		. += reach(tiles = 2)

/datum/capability/reach
	works_broken = TRUE
	works_unpowered = TRUE
	var/tiles = 1

/proc/reach(tiles = 2)
	var/datum/capability/reach/C = new
	C.tiles = max(1, round(tiles))
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
