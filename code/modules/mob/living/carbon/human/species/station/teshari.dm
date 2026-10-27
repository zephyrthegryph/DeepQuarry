// allow teshari to always be scooped, as long as pref is enabled
/mob/living/proc/micro_scoop_with_actor(mob/user, atom/over_object)
	// make sure src (The dragged) is human
	if(!istype(src, /mob/living/carbon/human))
		return FALSE

	var/mob/living/carbon/human/DraggedH = src

	//make sure src (the dragged) is a teshari (or shaped like one)
	if(DraggedH.species.is_micro_carry(DraggedH))
		var/mob/living/M = over_object
		// only perform the grab if; grabber and grabbed adjacent, caller is grabbed OR grabber, and the grabbed's grab preference is true.
		if(holder_type && istype(M) && Adjacent(M) && (user == M || user == DraggedH) && DraggedH != M && !M.incapacitated() && DraggedH.vore_prefs.pickup_pref && (M != user || (M == user && sparse_get_or(M, pickup_active, TRUE))) && (!DraggedH.combat_mode && !M.combat_mode))
			get_scooped(M, (user == DraggedH))
			return TRUE
	return FALSE


//allow teshari permission to pass plastic flaps.
/obj/structure/plasticflaps/CanPass(atom/A, turf/T)
	var/mob/living/carbon/human/H = A
	if(istype(H))
		if(H.species?.is_micro_carry(H))
			return 1

	return ..()
