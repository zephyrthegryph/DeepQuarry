// AI EYE
//
// A mob that the AI controls to look around the station with.
// It streams chunks as it moves around, which will show it what the AI can and cannot see.

/mob/observer/eye/aiEye
	name = "Inactive AI Eye"
	icon_state = "AI-eye"

/mob/observer/eye/aiEye/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(visualnet), GLOB.cameranet)

/// Phase 2: the eye leaves its visualnet.
/mob/observer/eye/aiEye/lifecycle_dematerialize()
	. = ..()
	visualnet?.clear_references(src, src.client)
	rel_clear(src, nameof(visualnet))

/mob/observer/eye/aiEye/setLoc(T, cancel_tracking = 1)
	var/mob/owner = src?.eye_owner()
	if(owner)
		T = get_turf(T)
		loc = T // ALLOW(containment): camera eye abstract move: must not trigger Entered/Crossed

		var/mob/living/silicon/ai/ai = owner
		if(cancel_tracking)
			ai.ai_cancel_tracking()

		if(use_static)
			ai.camera_visibility(src)

		if(ai.client && !ai.multicam_on)
			ai.reset_perspective(src)

		if(ai.master_multicam)
			ai.master_multicam.refresh_view()

		if(ai.holo)
			if(ai.hologram_follow)
				ai.holo.move_hologram(ai)

		return 1

// AI MOVEMENT

// The AI's "eye". Described on the top of the page.

/mob/living/silicon/ai
	var/obj/machinery/hologram/holopad/holo = null

/mob/living/silicon/ai/proc/destroy_eyeobj(atom/new_eye)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(!eyeobj) return
	if(!new_eye)
		new_eye = src
	ended_with(eyeobj, src) // No AI, no Eye
	eyeobj = null
	reset_perspective(new_eye)

/mob/living/silicon/ai/proc/create_eyeobj(newloc)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(eyeobj)
		destroy_eyeobj()
	if(!newloc)
		newloc = src.loc
	eyeobj = new /mob/observer/eye/aiEye(newloc)
	take_eye(eyeobj)
	eyeobj.name = "[src.name] (AI Eye)" // Give it a name
	reset_perspective(eyeobj)
	SetName(src.name)

/atom/proc/move_camera_by_click(mob/user)
	if(isAI(user))
		var/mob/living/silicon/ai/AI = user
		var/mob/observer/eye/eyeobj = AI?.active_eye()
		if(eyeobj && (AI.multicam_on || (AI.client.eye == eyeobj)))
			var/turf/T = get_turf(src)
			if(T)
				eyeobj.setLoc(T)

/mob/living/silicon/ai/proc/view_core()
	var/mob/observer/eye/eyeobj = src?.active_eye()
	rel_clear(src, nameof(camera))
	unset_machine()

	if(!eyeobj)
		return
	if(client && client.eye)
		reset_perspective(src)

	for(var/datum/chunk/c in eyeobj.visibleChunks)
		c.remove(eyeobj)
	eyeobj.setLoc(src)

/mob/living/silicon/ai/proc/toggle_acceleration()
	var/mob/observer/eye/eyeobj = src?.active_eye()
	set category = VERB_CAT_AI_SETTINGS
	set name = "Toggle Camera Acceleration"

	if(!eyeobj)
		return

	eyeobj.acceleration = !eyeobj.acceleration
	to_chat(usr, "Camera acceleration has been toggled [eyeobj.acceleration ? "on" : "off"].")

