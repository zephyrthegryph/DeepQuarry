// EYE
//
// A mob that another mob controls to look around the station with.
// It streams chunks as it moves around, which will show it what the controller can and cannot see.

/mob/observer/eye
	name = "Eye"
	icon = 'icons/mob/eye.dmi'
	icon_state = "default-eye"
	alpha = 127

	var/sprint = 10
	var/cooldown = 0
	var/acceleration = 1
	var/owner_follows_eye = 0

	see_in_dark = 7
	plane = PLANE_AI_EYE
	invisibility = INVISIBILITY_EYE

	var/list/visibleChunks = list() // ALLOW(instance_list): mob: 15 mobs at boot; per-instance state, see audit

	var/ghostimage = null
	var/datum/visualnet/visualnet
	var/use_static = TRUE
	var/static_visibility_range = 16

/mob/observer/eye/Initialize(mapload)
	. = ..()
	enable_godmode()

// ---------------------------------------------------------------- relations
//
// An eye's link to the mob looking through it is state held only as edges:
// eye_of (eye -> owner; EYE_OWNER()/EYES_OF()) and active_eye (owner -> the
// eye it moves and sees with; ACTIVE_EYE()). Deleting either end drops both.

/// eye -> the mob looking through it.
/datum/om/relation/eye_of
	name = "eye"
	source_single = TRUE

/datum/om/relation/eye_of/on_unlink(mob/observer/eye/source, mob/target, datum/om/edge/edge)
	if(target?.active_eye() == source)
		om_unlink(target, source, /datum/om/relation/active_eye)

/// mob -> the eye it currently moves and sees with. Implies eye_of.
/datum/om/relation/active_eye
	name = "active eye"
	source_single = TRUE
	target_single = TRUE

/// Look through `E` as this mob's active eye (replacing any other).
/mob/proc/take_eye(mob/observer/eye/E)
	if(!istype(E) || QDELETED(E))
		return FALSE
	if(!istype(om_link(E, src, /datum/om/relation/eye_of), /datum/om/edge))
		return FALSE
	return istype(om_link(src, E, /datum/om/relation/active_eye), /datum/om/edge)

/// Stop looking through the active eye (it stays alive; the caller deletes it if needed).
/mob/proc/drop_eye()
	var/mob/observer/eye/E = src?.active_eye()
	if(E)
		om_unlink(E, src, /datum/om/relation/eye_of)
	return E

/mob/observer/eye/Move(n, direct)
	var/mob/owner = src?.eye_owner()
	if(owner == src)
		return EyeMove(n, direct)
	return 0

// ZAS airflow_hit / airflow_speed / airflow_dest are dead under LINDA;
// /tg/'s spacewind operates on /atom/movable.experience_pressure_difference
// directly (and observer eyes are anchored so they don't move). Removed.

/mob/observer/eye/examinate()
	set popup_menu = 0
	set src = usr.contents
	return 0

/mob/observer/eye/pointed()
	set popup_menu = 0
	set src = usr.contents
	return 0

// Use this when setting the eye's location.
// It will also stream the chunk that the new loc is in.
/mob/observer/eye/proc/setLoc(T)
	var/mob/owner = src?.eye_owner()
	if(owner)
		T = get_turf(T)
		if(T != loc)
			loc = T // ALLOW(containment): camera eye abstract move: must not trigger Entered/Crossed

			owner.reset_perspective(src)
			if(owner_follows_eye)
				visualnet.updateVisibility(owner, 0)
				owner.forceMove(loc)
				visualnet.updateVisibility(owner, 0)
			if(use_static)
				visualnet.visibility(src, owner.client)
			return 1
	return 0

/mob/observer/eye/proc/getLoc()
	var/mob/owner = src?.eye_owner()
	if(owner)
		if(!isturf(owner.loc) || !owner.client)
			return
		return loc

/mob/proc/EyeMove(n, direct)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(!eyeobj)
		return

	return eyeobj.EyeMove(n, direct)

/mob/observer/eye/proc/GetViewerClient()
	var/mob/owner = src?.eye_owner()
	if(owner)
		return owner.client
	return null

/mob/observer/eye/EyeMove(n, direct)
	var/initial = initial(sprint)
	var/max_sprint = 50

	if(cooldown && cooldown < world.timeofday)
		sprint = initial

	for(var/i = 0; i < max(sprint, initial); i += 20)
		var/turf/step = get_turf(get_step(src, direct))
		if(step)
			setLoc(step)

	cooldown = world.timeofday + 5
	if(acceleration)
		sprint = min(sprint + 0.5, max_sprint)
	else
		sprint = initial
	return 1

DECLARE_REF(/mob/observer/eye, "visualnet", STATIC, null)
