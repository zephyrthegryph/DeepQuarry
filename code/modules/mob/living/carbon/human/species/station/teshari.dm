// allow teshari to always be scooped, as long as pref is enabled
/mob/living/MouseDrop(atom/over_object)
	// make sure src (The dragged) is human
	if(!istype(src, /mob/living/carbon/human))
		return ..()

	var/mob/living/carbon/human/DraggedH = src

	//make sure src (the dragged) is a teshari (or shaped like one)
	if(DraggedH.species.is_micro_carry(DraggedH))
		var/mob/living/M = over_object
		// only perform the grab if; grabber and grabbed adjacent, caller is grabbed OR grabber, and the grabbed's grab preference is true.
		if(holder_type && istype(M) && Adjacent(M) && (usr == M || usr == DraggedH) && DraggedH != M && !M.incapacitated() && DraggedH.pickup_pref && (M != usr || (M == usr && M.pickup_active)) && (!DraggedH.combat_mode && !M.combat_mode))
			get_scooped(M, (usr == DraggedH))
			return
	return ..()


//allow teshari permission to pass plastic flaps.
/obj/structure/plasticflaps/CanPass(atom/A, turf/T)
	var/mob/living/carbon/human/H = A
	if(istype(H))
		if(H.species?.is_micro_carry(H))
			return 1

	return ..()
