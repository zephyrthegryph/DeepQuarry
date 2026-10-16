/obj/item/uv_light
	name = "\improper UV light"
	desc = "A small handheld black light."
	icon = 'icons/obj/device.dmi'
	icon_state = "uv_off"
	w_class = ITEMSIZE_SMALL
	item_state = "electronic"
	actions_types = list(/datum/action/item_action/toggle_uv_light)
	MATERIAL_BULK(MAT_STEEL, 150)

	/// Scanned atom handle (entity_handle) -> the invisibility it had before the scan.
	var/list/scanned
	/// Scanned atom handle (entity_handle) -> the alpha it had before the scan.
	var/list/stored_alpha
	var/list/reset_objects

	var/range = 3
	var/step_alpha = 50

/obj/item/uv_light/var/on = FALSE

CAPABILITIES(/obj/item/uv_light)
	configure(item_worn(slots = SLOT_BELT))
	configure(item_sounds(pickup = SFX_ITEMS_PICKUP_DEVICE, drop = SFX_ITEMS_DROP_DEVICE))
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	every(2 SECONDS, then(PROC_REF(uv_light_step)), when = nameof(on))

/// Old attack_self.
/obj/item/uv_light/proc/interaction_self(datum/act/op/A)
	set_on(!on)
	if(on)
		set_glow(src, GLOW(range, 2, "#007fff"))
		set_icon_state("uv_on")
	else
		set_glow(src, GLOW(0, null, null))
		clear_last_scan()
		set_icon_state("uv_off")
	return TRUE

/obj/item/uv_light/proc/clear_last_scan()
	if(length(scanned))
		for(var/object_handle in scanned)
			var/atom/O = resolve_handle(object_handle) // a deleted atom stops resolving
			if(!O)
				continue
			O.set_invisibility(LAZYACCESS(scanned, object_handle))
			if(dq_get_fluorescent(O) == 2) dq_set_fluorescent(O, 1)
		clear_scanned()
	if(length(stored_alpha))
		for(var/object_handle in stored_alpha)
			var/atom/O = resolve_handle(object_handle)
			if(!O)
				continue
			O.set_alpha(LAZYACCESS(stored_alpha, object_handle))
			if(dq_get_fluorescent(O) == 2) dq_set_fluorescent(O, 1)
		LAZYCLEARLIST(stored_alpha)
	if(length(reset_objects))
		for(var/obj/item/I in reset_objects)
			I.cut_overlay(I.blood_overlay)
			if(dq_get_fluorescent(I) == 2) dq_set_fluorescent(I, 1)
		rel_clear(src, nameof(reset_objects))

/obj/item/uv_light/proc/uv_light_step(datum/act/timer/tick)
	clear_last_scan()
	if(on)
		step_alpha = round(255/range)
		var/turf/origin = get_turf(src)
		if(!origin)
			return
		for(var/turf/T in range(range, origin))
			var/use_alpha = 255 - (step_alpha * get_dist(origin, T))
			for(var/atom/A in contents_of(T))
				if(dq_get_fluorescent(A) == 1)
					dq_set_fluorescent(A, 2) //To prevent light crosstalk.
					if(A.invisibility)
						set_scanned_at(entity_handle(A), A.invisibility)
						A.set_invisibility(INVISIBILITY_NONE)
						LAZYSET(stored_alpha, entity_handle(A), A.alpha)
						A.set_alpha(use_alpha)
					if(istype(A, /obj/item))
						var/obj/item/O = A
						if(dq_get_was_bloodied(O) && !(O.blood_overlay in O.overlays))
							O.add_overlay(O.blood_overlay)
							rel_add(src, nameof(reset_objects), O)
