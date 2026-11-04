/*
CONTAINS:
MATCHES
CIGARETTES
CIGARS
SMOKING PIPES
CUSTOM CIGS
CHEAP LIGHTERS
ZIPPO

CIGARETTE PACKETS ARE IN FANCY.DM
*/

//For anything that can light stuff on fire
/obj/item/flame

/// Burns (flame_step) every 2 s while lit.
/obj/item/flame/var/lit = 0

CAPABILITIES(/obj/item/flame)
	every(2 SECONDS, then(PROC_REF(flame_step)), when = nameof(lit))

/// One burn step of a lit flame; each kind of flame overrides it with what it burns.
/obj/item/flame/proc/flame_step(datum/act/timer/A)
	return

/obj/item/flame/is_hot()
	return lit
