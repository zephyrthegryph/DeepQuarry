//Picture in picture

/atom/movable/screen/movable/pic_in_pic/ai
	var/mob/living/silicon/ai/ai
	var/mutable_appearance/highlighted_background
	var/highlighted = FALSE
	var/mob/observer/eye/aiEye/pic_in_pic/aiEye

CAPABILITIES(/atom/movable/screen/movable/pic_in_pic/ai)
	owns_one(nameof(aiEye), /mob/observer/eye/aiEye/pic_in_pic)

/atom/movable/screen/movable/pic_in_pic/ai/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(aiEye), new /mob/observer/eye/aiEye/pic_in_pic()) // created in nullspace, owned by the window
	rel_set(aiEye, nameof(aiEye.screen), src)

// No ownership cycle: a pic_in_pic window is never one of its own eye's hud elements.
// The AI names its windows through relations (multicam_screens, master_multicam), cleared when a window dies.

// the AI loses this multicam window.
/atom/movable/screen/movable/pic_in_pic/ai/on_destroy(force)
	..()
	set_ai(null)

/atom/movable/screen/movable/pic_in_pic/ai/Click()
	..()
	if(ai)
		ai.select_main_multicam_window(src)

/atom/movable/screen/movable/pic_in_pic/ai/make_backgrounds()
	..()
	highlighted_background = new /mutable_appearance()
	highlighted_background.icon = 'icons/hud/pic_in_pic.dmi'
	highlighted_background.icon_state = "background_highlight"
	highlighted_background.layer = DISPOSAL_LAYER
	highlighted_background.plane = PLATING_PLANE
	highlighted_background.appearance_flags = PIXEL_SCALE

/atom/movable/screen/movable/pic_in_pic/ai/add_background()
	if((width > 0) && (height > 0))
		var/matrix/M = matrix()
		M.Scale(width + 0.5, height + 0.5)
		M.Translate((width-1)/2 * ICON_SIZE_X, (height-1)/2 * ICON_SIZE_Y)
		highlighted_background.transform = M
		standard_background.transform = M
		add_overlay(highlighted ? highlighted_background : standard_background)

/atom/movable/screen/movable/pic_in_pic/ai/set_view_size(width, height, do_refresh = TRUE)
	if(!aiEye) // Exploit fix
		spent(src)
		return
	aiEye.static_visibility_range =	(round(max(width, height) / 2) + 1)
	if(ai)
		ai.camera_visibility(aiEye)
	..()

/atom/movable/screen/movable/pic_in_pic/ai/set_view_center(atom/target, do_refresh = TRUE)
	..()
	if(!aiEye) // Exploit Fix
		spent(src)
		return
	aiEye.setLoc(get_turf(target))

/atom/movable/screen/movable/pic_in_pic/ai/refresh_view()
	..()
	if(!aiEye) // Exploit Fix
		spent(src)
		return
	aiEye.setLoc(get_turf(center()))

/atom/movable/screen/movable/pic_in_pic/ai/proc/highlight()
	if(highlighted)
		return
	highlighted = TRUE
	cut_overlay(standard_background)
	add_overlay(highlighted_background)

/atom/movable/screen/movable/pic_in_pic/ai/proc/unhighlight()
	if(!highlighted)
		return
	highlighted = FALSE
	cut_overlay(highlighted_background)
	add_overlay(standard_background)

/atom/movable/screen/movable/pic_in_pic/ai/proc/set_ai(mob/living/silicon/ai/new_ai)
	if(!aiEye && !QDELETED(src))
		if(new_ai)
			to_chat(new_ai, span_danger("<h2>You've run into a unfixable bug with AI eye code. \
In order to create a new multicam, you will have to select a different camera first before trying to add one, or ask an admin to fix you. \
Whatever you did that made the last camera window disappear-- don't do that again.</h2>"))
		spent(src)
		return
	if(ai)
		rel_remove(ai, nameof(ai.multicam_screens), src)
		rel_set(aiEye, nameof(aiEye.eye_looker), null)
		rel_remove(ai, nameof(ai.master_multicam), src)
		if(ai.multicam_on)
			unshow_to(ai.client)
	rel_set(src, nameof(ai), new_ai)
	if(new_ai)
		rel_add(new_ai, nameof(new_ai.multicam_screens), src)
		rel_set(aiEye, nameof(aiEye.eye_looker), ai)
		if(new_ai.multicam_on)
			show_to(new_ai.client)

//Turf, area, and landmark for the viewing room

/turf/unsimulated/ai_visible
	name = ""
	icon = 'icons/hud/pic_in_pic.dmi'
	icon_state = "room_background"
	flags = NOJAUNT
	plane = SPACE_PLANE
	layer = AREA_LAYER + 0.1

/area/ai_multicam_room
	name = "AI Multicam Room"
	icon_state = "ai_camera_room"
	dynamic_lighting = FALSE

GLOBAL_DATUM(ai_camera_room_landmark, /obj/effect/landmark/ai_multicam_room)

/obj/effect/landmark/ai_multicam_room
	name = "ai camera room"
	icon_state = "x"

/obj/effect/landmark/ai_multicam_room/Initialize(mapload)
	. = ..()
	spent(GLOB.ai_camera_room_landmark)
	GLOB.ai_camera_room_landmark = src

/// Phase 2: stops being the multicam room.
/obj/effect/landmark/ai_multicam_room/lifecycle_dematerialize()
	. = ..()
	if(GLOB.ai_camera_room_landmark == src)
		GLOB.ai_camera_room_landmark = null

//Dummy camera eyes

/mob/observer/eye/aiEye/pic_in_pic
	name = "Secondary AI Eye"
	var/atom/movable/screen/movable/pic_in_pic/ai/screen
	/// Cameras whose in_use_lights we raised (REL_LIST); disable_camera_telegraphing() lowers them again.
	var/list/cameras_telegraphed
	var/telegraph_cameras = TRUE
	var/telegraph_range = 7

/mob/observer/eye/aiEye/pic_in_pic/GetViewerClient()
	if(screen && screen.ai)
		return screen.ai.client

/mob/observer/eye/aiEye/pic_in_pic/setLoc(turf/T)
	T = get_turf(T)
	forceMove(T)
	if(screen && screen.ai)
		screen.ai.camera_visibility(src)
	else
		GLOB.cameranet.visibility(src)
	update_camera_telegraphing()

/mob/observer/eye/aiEye/pic_in_pic/proc/update_camera_telegraphing()
	if(!telegraph_cameras)
		return
	var/list/obj/machinery/camera/add = list()
	var/list/obj/machinery/camera/remove = list()
	var/list/obj/machinery/camera/visible = list()
	for(var/datum/chunk/camera/CC as anything in visibleChunks)
		for(var/obj/machinery/camera/C as anything in CC.cameras)
			if (!C.can_use() || (get_dist(C, src) > telegraph_range))
				continue
			visible |= C

	add = visible - (cameras_telegraphed || list())
	remove = (cameras_telegraphed || list()) - visible

	for(var/obj/machinery/camera/C as anything in remove)
		if(QDELETED(C))
			continue
		rel_remove(src, nameof(cameras_telegraphed), C)
		C.in_use_lights--
	for(var/obj/machinery/camera/C as anything in add)
		if(QDELETED(C))
			continue
		rel_add(src, nameof(cameras_telegraphed), C)
		C.in_use_lights++

/mob/observer/eye/aiEye/pic_in_pic/proc/disable_camera_telegraphing()
	telegraph_cameras = FALSE
	for(var/obj/machinery/camera/C as anything in cameras_telegraphed)
		if(QDELETED(C))
			continue
		C.in_use_lights--
	rel_clear(src, nameof(cameras_telegraphed))

// The screen owns its eye (implicit OWN aiEye); `screen` is only the way back (a relation),
// so ownership stays a tree (tools/ci/ownership_cycle_lint.py).
CAPABILITIES(/mob/observer/eye/aiEye/pic_in_pic)
	ref_many(nameof(cameras_telegraphed))

// stops telegraphing to the cameras it watched.
/mob/observer/eye/aiEye/pic_in_pic/on_destroy(force)
	disable_camera_telegraphing()
	..()

//AI procs

/mob/living/silicon/ai/proc/drop_new_multicam(silent = FALSE)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(!multicam_allowed)
		if(!silent)
			to_chat(src, span_warning("This action is currently disabled. Contact an administrator to enable this feature."))
		return
	if(!eyeobj)
		return
	if(length(multicam_screens) >= max_multicams)
		if(!silent)
			to_chat(src, span_warning("Cannot place more than [max_multicams] multicamera windows."))
		return
	var/atom/movable/screen/movable/pic_in_pic/ai/C = new /atom/movable/screen/movable/pic_in_pic/ai()
	C.set_view_size(3, 3, FALSE)
	C.set_view_center(get_turf(eyeobj))
	C.set_ai(src)
	if(!silent)
		to_chat(src, span_notice("Added new multicamera window."))
	return C

/mob/living/silicon/ai/proc/toggle_multicam()
	if(!multicam_allowed)
		to_chat(src, span_warning("This action is currently disabled. Contact an administrator to enable this feature."))
		return
	if(multicam_on)
		end_multicam()
	else
		start_multicam()

/mob/living/silicon/ai/proc/start_multicam()
	if(multicam_on || aiRestorePowerRoutine || !isturf(loc))
		return
	if(!GLOB.ai_camera_room_landmark)
		to_chat(src, span_warning("This function is not available at this time."))
		return
	multicam_on = TRUE
	refresh_multicam()
	to_chat(src, span_notice("Multiple-camera viewing mode activated."))

/mob/living/silicon/ai/proc/refresh_multicam()
	reset_perspective(GLOB.ai_camera_room_landmark)
	if(client)
		for(var/atom/movable/screen/movable/pic_in_pic/P as anything in multicam_screens)
			P.show_to(client)

/mob/living/silicon/ai/proc/end_multicam()
	if(!multicam_on)
		return
	multicam_on = FALSE
	select_main_multicam_window(null)
	if(client)
		for(var/atom/movable/screen/movable/pic_in_pic/P as anything in multicam_screens)
			P.unshow_to(client)
	reset_perspective(src)
	to_chat(src, span_notice("Multiple-camera viewing mode deactivated."))

/mob/living/silicon/ai/proc/select_main_multicam_window(atom/movable/screen/movable/pic_in_pic/ai/P)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(master_multicam == P)
		return

	if(master_multicam)
		master_multicam.set_view_center(get_turf(eyeobj), FALSE)
		master_multicam.unhighlight()
		rel_clear(src, nameof(master_multicam))

	if(P)
		P.highlight()
		eyeobj.setLoc(get_turf(P.center()))
		P.set_view_center(eyeobj)
		rel_set(src, nameof(master_multicam), P)
