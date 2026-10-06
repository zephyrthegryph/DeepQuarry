/obj/structure
	icon = 'icons/obj/structures.dmi'
	w_class = ITEMSIZE_NO_CONTAINER
	blocks_emissive = EMISSIVE_BLOCK_GENERIC

	var/breakable
	var/parts
	var/block_turf_edges = FALSE // If true, turf edge icons will not be made on the turf this occupies.

	var/list/connections
	var/list/other_connections
	var/list/blend_objects = null // Objects which to blend with // default null
	var/list/noblend_objects = null // Objects to avoid blending with (such as children of listed blend objects. // default null
	// Structures shrug off a plain telekinetic grab or poke; ones that react declare an INTERACT_TK.
	tk_reach = FALSE

// the base structure: leaves its parts behind.
/obj/structure/on_destroy(force)
	if(parts)
		new parts(loc)
	..()

/obj/structure/hand_gate(mob/user)
	if(breakable)
		if(user.has_mutation(HULK))
			user.say(pick(";RAAAAAAAARGH!", ";HNNNNNNNNNGGGGGGH!", ";GWAAAAAAAARRRHHH!", "NNNNNNNNGGGGGGGGHH!", ";AAAAAAARRRGH!" ))
			generic_hit(src, user, 1, "smashes")
		else if(ishuman(user))
			var/mob/living/carbon/human/H = user
			var/shreddamage = H.species.can_shred(user, FALSE, 11)
			if(shreddamage)
				generic_hit(src, user, shreddamage, "attacks")
	climb_shake_off(src, user)
	return ..()

// Default destruction for integrity-using structures: drop any parts (via Destroy) and delete.
// Subtypes that shatter into shards / drop rods override this and call ..() or qdel themselves.
/obj/structure/atom_destruction(damage_flag)
	. = ..()
	if(!QDELETED(src))
		destroyed(src)

/obj/structure/proc/can_touch(mob/user)
	if (!user)
		return 0
	if(!Adjacent(user))
		return 0
	if (user.restrained() || user?.buckled_to())
		to_chat(user, span_notice("You need your hands and legs free for this."))
		return 0
	if (user.stat || user.has_status(EFFECT_PARALYZED) || user.has_status(EFFECT_SLEEPING) || user.lying || user.has_status(EFFECT_WEAKENED))
		return 0
	if (isAI(user))
		to_chat(user, span_notice("You need hands for this."))
		return 0
	return 1

/obj/structure/attack_generic(mob/user, damage, attack_verb)
	if(!breakable || damage < STRUCTURE_MIN_DAMAGE_THRESHOLD)
		return 0
	act_message(user, src, others = span_danger("%U% [attack_verb] %T% apart!"))
	user.do_attack_animation(src)
	expire(1)
	return 1

/obj/structure/proc/can_visually_connect()
	return anchored

/obj/structure/proc/can_visually_connect_to(obj/structure/S)
	return istype(S, src)

/// The neighbours a smoothing structure joins (its adjacency() mask, code/engine/lifeforms/adjacency.dm): faces and corners.
/obj/structure/var/smooth_mask = 0 // ALLOW(base_vars): the smoothing structures' join mask, written by the adjacency index through smooth_changed()

/// The smoothing entry every structure that joins its neighbours' look declares: one shared kind with walls, each deciding what it joins.
/proc/smoothing()
	return adjacency(ADJ_KIND_SMOOTH, dirs = ADJ_ALL_AROUND, connects = TYPE_PROC_REF(/obj/structure, smooth_joins), when = "anchored", changed = TYPE_PROC_REF(/obj/structure, smooth_changed))

/// adjacency() connects: a structure joins the anchored structures it can visually connect to.
/obj/structure/proc/smooth_joins(atom/other, bit)
	var/obj/structure/S = other
	return istype(S) && can_visually_connect_to(S) && S.can_visually_connect()

/// adjacency() changed: the neighbours around it changed; it redraws against them.
/obj/structure/proc/smooth_changed(mask)
	smooth_mask = mask
	update_connections()
	update_icon()

/obj/structure/proc/update_connections(propagate = 0)
	if(propagate)
		adjacency_refresh(src, TRUE) // a change the index cannot see (a flip, a material): this structure and its neighbours look again
	var/list/dirs = adjacency_mask_dirs(smooth_mask)
	var/list/other_dirs = list()

	if(!can_visually_connect())
		connections = string_list(list("0", "0", "0", "0"))
		other_connections = string_list(list("0", "0", "0", "0"))
		return FALSE

	for(var/direction in GLOB.cardinal)
		var/turf/T = get_step(src, direction)
		var/success = 0
		for(var/b_type in blend_objects)
			if(istype(T, b_type))
				success = 1
				break // breaks inner loop
		if(!success)
			blend_obj_loop:
				for(var/obj/O in turf_contents_of_type(T, /obj))
					for(var/b_type in blend_objects)
						if(istype(O, b_type))
							success = 1
							for(var/obj/structure/S in turf_contents_of_type(T, /obj/structure))
								if(istype(S, src))
									success = 0
							for(var/nb_type in noblend_objects)
								if(istype(O, nb_type))
									success = 0

						if(success)
							break blend_obj_loop // breaks outer loop

		if(success)
			dirs += get_dir(src, T)
			other_dirs += get_dir(src, T)

	refresh_neighbors()

	// Interned: structures with the same shape share one read-only list.
	connections = string_list(dirs_to_corner_states(dirs))
	other_connections = string_list(dirs_to_corner_states(other_dirs))
	return TRUE

/obj/structure/proc/refresh_neighbors()
	for(var/turf/T as anything in RANGE_TURFS(1, src))
		T.update_icon()
