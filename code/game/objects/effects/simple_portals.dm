
/obj/effect/simple_portal
	name = "Portal"
	desc = "It looks like a portal that leads to somewhere, although you can't quite see through it."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "portal"
	density = 1
	unacidable = TRUE
	anchored = TRUE
	var/atom/destination
	var/teleport_sound = SFX_EFFECTS_PORTAL_EFFECT

REGISTRY_MEMBERSHIP(/obj/effect/simple_portal, REGISTRY_SIMPLE_PORTALS)

CAPABILITIES(/obj/effect/simple_portal/linked)
	after_init(0, then(PROC_REF(link_on_init)))

/// Links its partner portal, once both exist.
/obj/effect/simple_portal/linked/proc/link_on_init(datum/act/timer/A)
	if(portal_id)
		link_portal()

CAPABILITIES(/obj/effect/simple_portal)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))
	op("enter", observer(), label("Enter"), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(simple_portal_observer_use)))

/// Something walked into it (the bump action's notice).
/obj/effect/simple_portal/proc/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	var/atom/movable/AM = N.bumper
	handle_teleport(AM)

/obj/effect/simple_portal/Crossed(atom/movable/AM)
	. = ..()
	handle_teleport(AM)

/obj/effect/simple_portal/proc/handle_teleport(atom/movable/AM)
	if(destination())
		AM.forceMove(destination())
		if(!AM.is_incorporeal() && !istype(AM,/mob/observer))
			playsound(get_turf(src),teleport_sound,60,1)
			playsound(get_turf(destination()),teleport_sound,60,1)

/// Old attack_ghost: the ghost's default (examine), then through the portal.
/obj/effect/simple_portal/proc/simple_portal_observer_use(datum/act/op/A)
	var/mob/observer/dead/user = A.actor
	actor_use_default(/datum/input_adapter/ghost, user, src)
	handle_teleport(user)
	return OP_OK

/obj/effect/simple_portal/coords
	var/tele_x
	var/tele_y
	var/tele_z

/obj/effect/simple_portal/coords/handle_teleport(atom/movable/AM)
	rel_clear(src, nameof(destination))
	if(!isnull(tele_x) && !isnull(tele_y) && !isnull(tele_z))
		rel_set(src, nameof(destination), locate(tele_x,tele_y,tele_z))
	. = ..()

/obj/effect/simple_portal/linked
	icon_state = "portal1"
	var/obj/effect/simple_portal/linked/linked_portal
	var/portal_id

/obj/effect/simple_portal/linked/handle_teleport(atom/movable/AM)
	rel_clear(src, nameof(destination))
	if(linked_portal() && icon_state == "portal")
		var/rel_x = round(rand(-1,1))
		var/rel_y = round(rand(-1,1))
		var/movingdir = get_dir(AM,src)
		if(!isnull(movingdir))
			rel_set(src, nameof(destination), get_step(get_turf(linked_portal()),movingdir))
		else
			while(rel_x == 0 && rel_y == 0)
				rel_x = round(rand(-1,1))
				rel_y = round(rand(-1,1))
			rel_set(src, nameof(destination), locate(linked_portal().loc.x + rel_x, linked_portal().loc.y + rel_y, linked_portal().loc.z))
		if(!valid_destination(destination()))
			var/list/possible_x = shuffle(list(-1,0,1))
			var/list/possible_y = shuffle(list(-1,0,1))
			for(rel_x in possible_x)
				for(rel_y in possible_y)
					if(rel_x == 0 && rel_y == 0)
						continue
					rel_set(src, nameof(destination), locate(linked_portal().loc.x + rel_x, linked_portal().loc.y + rel_y, linked_portal().loc.z))
					if(valid_destination(destination()))
						break
	. = ..()

/obj/effect/simple_portal/linked/proc/valid_destination(turf/dest,atom/movable/AM)
	if(!dest)
		return FALSE
	if(dest.density)
		return FALSE
	if(dest == get_turf(linked_portal()))
		return FALSE
	var/windows = 0
	for(var/obj/struct in turf_contents_of_type(dest, /obj))
		var/obj/structure/window/window = struct
		if(istype(window))
			windows++
			if(window.fulltile)
				return FALSE
		else
			if(!struct.density)
				continue
			if(struct.throwpass || struct.flags & ON_BORDER)
				continue
			else
				return FALSE
	if(windows>2)
		return FALSE
	return TRUE

/obj/effect/simple_portal/linked/proc/link_portal()
	if(!portal_id)
		return "SET PORTAL ID FIRST"
	for(var/obj/effect/simple_portal/linked/candidate in REGISTRY_MEMBERS(REGISTRY_SIMPLE_PORTALS))
		if(istype(candidate) && portal_id == candidate.portal_id && candidate != src)
			rel_set(src, nameof(linked_portal), candidate)
			break

/obj/effect/simple_portal/linked/draw(datum/look/look)
	..()
	if(linked_portal() && !QDELETED(linked_portal()))
		look.state("portal")
	else
		look.state("portal1")

/// Relation view: destination (reads null once it is gone).
/obj/effect/simple_portal/proc/destination() as /atom
	return destination

/// Relation view: linked portal (reads null once it is gone).
/obj/effect/simple_portal/linked/proc/linked_portal() as /obj/effect/simple_portal/linked
	return linked_portal
