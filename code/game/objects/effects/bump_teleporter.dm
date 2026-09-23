
/obj/effect/bump_teleporter
	name = "bump-teleporter"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x2"
	var/id = null			//id of this bump_teleporter.
	var/id_target = null	//id of bump_teleporter which this moves you to.
	invisibility = INVISIBILITY_ABSTRACT 		//nope, can't see this
	anchored = TRUE
	density = TRUE
	opacity = 0

REGISTRY_MEMBERSHIP(/obj/effect/bump_teleporter, REGISTRY_BUMP_TELEPORTERS)

/obj/effect/bump_teleporter/Initialize(mapload)
	. = ..()

/obj/effect/bump_teleporter/Destroy()
	return ..()

/obj/effect/bump_teleporter/Bumped(atom/user)
	if(!ismob(user))
		//user.loc = src.loc	//Stop at teleporter location
		return
	var/mob/M = user
	if(!id_target)
		//user.loc = src.loc	//Stop at teleporter location, there is nowhere to teleport to.
		return

	for(var/obj/effect/bump_teleporter/BT in REGISTRY_MEMBERS(REGISTRY_BUMP_TELEPORTERS))
		if(BT.id == src.id_target)
			M.forceMove(BT.loc) // Teleport to location with correct id. //
			return
