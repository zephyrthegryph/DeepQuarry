// survives_container() overrides (doc/rewrite/proposals/relations.md D17): what must outlive its container whatever the slot policy says.
// The default (FALSE) and the check are in code/engine/refs/containment/lifecycle.dm.

/// A mob with a mind or a client: the player is in it, so it is never deleted with whatever held it.
/mob/survives_container()
	return !!mind || !!client

/// A holder of a mob with a mind or client (a brain, an MMI, a soulcatcher shell) survives with it.
/proc/dq_holds_player(atom/movable/holder)
	for(var/mob/inside in contents_of(holder))
		if(inside.survives_container())
			return TRUE
	return FALSE

/obj/item/mmi/survives_container()
	return dq_holds_player(src)

/obj/item/organ/internal/brain/survives_container()
	return dq_holds_player(src)

/obj/item/disk/nuclear/survives_container()
	return TRUE
