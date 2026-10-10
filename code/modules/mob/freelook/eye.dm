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

	var/list/visibleChunks = list() // ALLOW(instance_list): d: per-mob visibleChunks, filled at runtime; mobs are few

	var/ghostimage = null
	var/datum/visualnet/visualnet
	var/use_static = TRUE
	var/static_visibility_range = 16

/mob/observer/eye/proc/eye_godmode_ready(datum/act/timer/A)
	enable_godmode()

// ---------------------------------------------------------------- relations
//
// An eye's link to the mob looking through it is state held only as links:
// eye_looker / own_eyes (eye -> the mob looking through it; eye_owner()/eyes_list()) and active_eye_obj / active_looker (the eye a mob
// moves and sees with; active_eye()). Deleting either end drops both.

/// The names of the eye's looker vars (the reverse-index keys eyes_list() and active_eye() read).
#define EYE_LOOKER_VAR "eye_looker"
#define EYE_ACTIVE_LOOKER_VAR "active_looker"

/mob/observer/eye
	/// The mob looking through this eye (a reference, cleared when the mob is deleted). Read with eye_owner(); the mob's eyes_list() is the reverse.
	var/mob/eye_looker
	/// The mob this eye is the active eye of. Read with active_eye() on the mob.
	var/mob/active_looker

CAPABILITIES(/mob/observer/eye)
	after_init(0, then(PROC_REF(eye_godmode_ready)))
	ref_one(nameof(eye_looker), /mob, on_unlink = PROC_REF(looker_lost))
	ref_one(nameof(active_looker), /mob)

/// The mob looking through this eye.
/mob/observer/eye/proc/eye_owner() as /mob
	return eye_looker

/// The eyes this mob looks through.
/mob/living/proc/eyes_list() as /list
	return rel_sources_via(src, EYE_LOOKER_VAR)

/// The eye this mob moves and sees with, or null.
/mob/proc/active_eye() as /mob/observer/eye
	var/list/active = rel_sources_via(src, EYE_ACTIVE_LOOKER_VAR)
	return length(active) ? active[1] : null

/// The looker went (or let the eye go): the eye stops being its active eye too.
/mob/observer/eye/proc/looker_lost(mob/old_looker)
	if(active_looker == old_looker)
		rel_set(src, nameof(active_looker), null)

/// Look through `E` as this mob's active eye (replacing any other).
/mob/proc/take_eye(mob/observer/eye/E)
	if(!istype(E) || QDELETED(E))
		return FALSE
	rel_set(E, nameof(E.eye_looker), src)
	var/mob/observer/eye/previous = active_eye()
	if(previous && previous != E)
		rel_set(previous, nameof(previous.active_looker), null)
	rel_set(E, nameof(E.active_looker), src)
	return E.eye_looker == src && E.active_looker == src

/// Stop looking through the active eye (it stays alive; the caller deletes it if needed).
/mob/proc/drop_eye()
	var/mob/observer/eye/E = src?.active_eye()
	if(E)
		rel_set(E, nameof(E.eye_looker), null)
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

