#define TRACKING_POSSIBLE 0
#define TRACKING_NO_COVERAGE 1
#define TRACKING_TERMINATE 2

/mob/living/silicon/ai/var/max_locations = 30
/mob/living/silicon/ai/var/stored_locations[0]

/proc/InvalidPlayerTurf(turf/T as turf)
	return !(T?.z in using_map.player_levels)

/mob/living/silicon/ai/proc/get_camera_list()
	if(src.stat == 2)
		return

	GLOB.cameranet.process_sort()

	var/list/T = list()
	for (var/obj/machinery/camera/C in REGISTRY_MEMBERS(REGISTRY_CAMERAS))
		var/list/tempnetwork = C.network&src.network
		if (tempnetwork.len)
			T[text("[][]", C.c_tag, (C.can_use() ? null : " (Deactivated)"))] = C

	rel_set(src, nameof(track), new /datum/trackable())
	track.cameras = T
	return T


/mob/living/silicon/ai/proc/ai_camera_list(camera in get_camera_list())
	var/mob/observer/eye/eyeobj = src?.active_eye()
	set category = VERB_CAT_AI_CAMERA_CONTROL
	set name = "Show Camera List"

	if(check_unable())
		return

	if (!camera)
		return 0

	var/obj/machinery/camera/C = track.cameras[camera]
	eyeobj.setLoc(C)

	return

/mob/living/silicon/ai/proc/ai_store_location(location_name as text)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	set category = VERB_CAT_AI_CAMERA_CONTROL
	set name = "Store Camera Location"
	set desc = "Stores your current camera location by the given name"

	location_name = sanitize(location_name)
	if(!location_name)
		to_chat(src, span_warning("Must supply a location name"))
		return

	if(stored_locations.len >= max_locations)
		to_chat(src, span_warning("Cannot store additional locations. Remove one first"))
		return

	if(location_name in stored_locations)
		to_chat(src, span_warning("There is already a stored location by this name"))
		return

	var/L = eyeobj.getLoc()
	if (InvalidPlayerTurf(get_turf(L)))
		to_chat(src, span_warning("Unable to store this location"))
		return

	stored_locations[location_name] = L
	to_chat(src, "Location '[location_name]' stored")

/mob/living/silicon/ai/proc/sorted_stored_locations()
	return sortList(stored_locations)

/mob/living/silicon/ai/proc/ai_goto_location(loc in sorted_stored_locations())
	var/mob/observer/eye/eyeobj = src?.active_eye()
	set category = VERB_CAT_AI_CAMERA_CONTROL
	set name = "Goto Camera Location"
	set desc = "Returns to the selected camera location"

	if (!(loc in stored_locations))
		to_chat(src, span_warning("Location [loc] not found"))
		return

	var/L = stored_locations[loc]
	eyeobj.setLoc(L)

/mob/living/silicon/ai/proc/ai_remove_location(loc in sorted_stored_locations())
	set category = VERB_CAT_AI_CAMERA_CONTROL
	set name = "Delete Camera Location"
	set desc = "Deletes the selected camera location"

	if (!(loc in stored_locations))
		to_chat(src, span_warning("Location [loc] not found"))
		return

	stored_locations.Remove(loc)
	to_chat(src, "Location [loc] removed")

// Used to allow the AI is write in mob names/camera name from the CMD line.
/datum/trackable
	var/list/names = list() // ALLOW(instance_list): d: tracking scratch state rebuilt on every search
	var/list/namecounts
	var/list/humans // name -> REF(mob) text; resolve through `tracked`
	var/list/others // name -> REF(mob) text; resolve through `tracked`
	var/list/tracked // relation: every mob listed above (cleared by the framework when one dies)
	var/list/cameras = list() // ALLOW(instance_list): d: tracking scratch state rebuilt on every search

/mob/living/silicon/ai/proc/trackable_mobs()
	if(src.stat == 2)
		return list()

	var/datum/trackable/TB = new()
	for(var/mob/living/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(M == src)
			continue
		if(M.tracking_status() != TRACKING_POSSIBLE)
			continue

		var/name = M.name
		if (name in TB.names)
			LAZYADDASSOC(TB.namecounts, name, 1)
			name = text("[] ([])", name, LAZYACCESS(TB.namecounts, name))
		else
			TB.names.Add(name)
			LAZYSET(TB.namecounts, name, 1)
		rel_add(TB, nameof(TB.tracked), M)
		var/mob_ref = REF(M)
		if(ishuman(M))
			LAZYSET(TB.humans, name, mob_ref)
		else
			LAZYSET(TB.others, name, mob_ref)

	var/list/targets = sortList(TB.humans || list()) + sortList(TB.others || list())
	rel_set(src, nameof(track), TB)
	return targets

/mob/living/silicon/ai/proc/ai_camera_track(target_name in trackable_mobs())
	set category = VERB_CAT_AI_CAMERA_CONTROL
	set name = "Follow With Camera"
	set desc = "Select who you would like to track."

	if(src.stat == 2)
		to_chat(src, "You can't follow [target_name] with cameras because you are dead!")
		return
	if(!target_name)
		rel_clear(src, nameof(cameraFollow))

	var/target_ref = LAZYACCESS(track?.humans, target_name) || LAZYACCESS(track?.others, target_name)
	var/mob/target = target_ref ? locate_in_list(track.tracked, target_ref) : null
	own_clear(src, nameof(track), OWN_DELETE)
	ai_actual_track(target)

/mob/living/silicon/ai/proc/ai_cancel_tracking(forced = 0)
	if(!cameraFollow)
		return

	to_chat(src, "Follow camera mode [forced ? "terminated" : "ended"].")
	cameraFollow.tracking_cancelled()
	rel_clear(src, nameof(cameraFollow))

/mob/living/silicon/ai/proc/ai_actual_track(mob/living/target as mob)
	if(!istype(target))	return FALSE
	var/mob/living/silicon/ai/U = src // usr --> src

	if(target == U.cameraFollow)
		return TRUE

	if(U.cameraFollow)
		U.ai_cancel_tracking()
	U.track_delay = 1 SECOND
	rel_set(U, nameof(U.cameraFollow), target)
	to_chat(U, "Now tracking [target.name] on camera.")
	target.tracking_initiated()

	ai_track_step() // the first look is immediate; the every() follows from here

	return TRUE

/// Delay until the next follow-camera step: a second, or ten while the target is out of coverage.
/mob/living/silicon/ai/var/track_delay = 1 SECOND

/// The every() interval of ai_track_step(): track_delay.
/mob/living/silicon/ai/proc/track_interval(datum/act/A)
	return track_delay

/// Follow camera mode: keeps the eye on `cameraFollow` every second (every ten while it is out of
/// camera coverage) while tracking (its every() in CAPABILITIES(/mob/living/silicon/ai)).
/mob/living/silicon/ai/proc/ai_track_step(datum/act/A)
	var/mob/living/target = cameraFollow
	if(QDELETED(target))
		return
	switch(target.tracking_status())
		if(TRACKING_NO_COVERAGE)
			to_chat(src, "Target is not near any active cameras.")
			track_delay = 10 SECONDS
			return
		if(TRACKING_TERMINATE)
			ai_cancel_tracking(1)
			return

	track_delay = 1 SECOND
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(!eyeobj)
		view_core()
		ai_cancel_tracking(1)
		return
	eyeobj.setLoc(get_turf(target), 0)

// camera.dm declares the camera's other interactions.
EXTEND_INTERACTIONS(/obj/machinery/camera, INTERACT_SILICON("Look through", PROC_REF(camera_silicon_look)))

/// Old attack_ai: the AI moves its eye to the camera. Nothing for cyborgs.
/obj/machinery/camera/proc/camera_silicon_look(mob/living/silicon/ai/user, obj/item/held, datum/interaction/interaction)
	if(!istype(user))
		return TRUE
	if(!can_use())
		return TRUE
	var/mob/observer/eye/eyeobj = user.active_eye()
	eyeobj?.setLoc(get_turf(src))
	return TRUE

// ai.dm declares the AI's other interactions.
EXTEND_INTERACTIONS(/mob/living/silicon/ai, INTERACT_SILICON("Camera list", PROC_REF(ai_silicon_camera_list)))

/// Old attack_ai: an AI clicking an AI gets the camera list.
/mob/living/silicon/ai/proc/ai_silicon_camera_list(mob/user, obj/item/held, datum/interaction/interaction)
	ai_camera_list()
	return TRUE

/proc/camera_sort(list/L)
	var/obj/machinery/camera/a
	var/obj/machinery/camera/b

	for (var/i = L.len, i > 0, i--)
		for (var/j = 1 to i - 1)
			a = L[j]
			b = L[j + 1]
			if (a.c_tag_order != b.c_tag_order)
				if (a.c_tag_order > b.c_tag_order)
					L.Swap(j, j + 1)
			else
				if (sorttext(a.c_tag, b.c_tag) < 0)
					L.Swap(j, j + 1)
	return L


/mob/living/proc/near_camera()
	if (!isturf(loc))
		return 0
	else if(!GLOB.cameranet.checkVis(src))
		return 0
	return 1

/mob/living/proc/tracking_status()
	// Easy checks first.
	// Don't detect mobs on CentCom. Since the wizard den is on CentCom, we only need this.
	var/obj/item/card/id/id = GetIdCard()
	if(id && id.prevent_tracking())
		return TRACKING_TERMINATE
	var/turf/pos = get_turf(src)
	var/area/B = pos?.loc // No cam tracking in dorms!
	if(InvalidPlayerTurf(pos) || B?.flag_check(AREA_BLOCK_TRACKING))
		return TRACKING_TERMINATE
	if(invisibility >= INVISIBILITY_LEVEL_ONE) //cloaked
		return TRACKING_TERMINATE
	if(digitalcamo)
		return TRACKING_TERMINATE
	if(alpha < 127) // For lings and possible future alpha-based cloaks.
		return TRACKING_TERMINATE
	if(istype(loc,/obj/effect/dummy))
		return TRACKING_TERMINATE

	// Now, are they viewable by a camera? (This is last because it's the most intensive check)
	return near_camera() ? TRACKING_POSSIBLE : TRACKING_NO_COVERAGE

/mob/living/silicon/robot/tracking_status()
	. = ..()
	if(. == TRACKING_NO_COVERAGE)
		return camera && camera.can_use() ? TRACKING_POSSIBLE : TRACKING_NO_COVERAGE

/mob/living/carbon/human/tracking_status()
	//Cameras can't track people wearing an agent card or a ninja hood.
	if(istype(get_equipped_item(SLOT_ID_HEAD), /obj/item/clothing/head/helmet/space/rig))
		var/obj/item/clothing/head/helmet/space/rig/helmet = get_equipped_item(SLOT_ID_HEAD)
		if(helmet.prevent_track())
			return TRACKING_TERMINATE

	. = ..()
	if(. == TRACKING_TERMINATE)
		return

	if(. == TRACKING_NO_COVERAGE)
		var/turf/T = get_turf(src)
		if(T && (T.z in using_map.station_levels) && hassensorlevel(src, SUIT_SENSOR_TRACKING))
			return TRACKING_POSSIBLE

/mob/living/proc/tracking_initiated()

/mob/living/silicon/robot/tracking_initiated()
	tracking_entities++
	if(tracking_entities == 1 && has_zeroth_law())
		to_chat(src, span_warning("Internal camera is currently being accessed."))

/mob/living/proc/tracking_cancelled()

/mob/living/silicon/robot/tracking_cancelled()
	tracking_entities--
	if(!tracking_entities && has_zeroth_law())
		to_chat(src, span_notice("Internal camera is no longer being accessed."))


#undef TRACKING_POSSIBLE
#undef TRACKING_NO_COVERAGE
#undef TRACKING_TERMINATE
