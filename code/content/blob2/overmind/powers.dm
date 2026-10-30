/mob/observer/blob/proc/can_buy(cost = 15)
	if(blob_points < cost)
		to_chat(src, span_warning("You cannot afford this, you need at least [cost] resources!"))
		return FALSE
	add_points(-cost)
	return TRUE

/mob/observer/blob/proc/transport_core()
	if(blob_core())
		forceMove(blob_core().loc)

/mob/observer/blob/proc/transport_core_op(datum/act/op/A)
	transport_core()

/mob/observer/blob/proc/createSpecial(price, blobType, nearEquals, needsNode, turf/T)
	if(!T)
		T = get_turf(src)
	var/obj/structure/blob/B = (locate_on(T, /obj/structure/blob))

	if(!B)
		to_chat(src, span_warning("There is no blob here!"))
		return

	if(B.overmind != src)
		to_chat(src, span_warning("This blob isn't controlled by you."))
		return

	if(!istype(B, /obj/structure/blob/normal))
		to_chat(src, span_warning("Unable to use this blob, find a normal one."))
		return

	if(nearEquals)
		for(var/obj/structure/blob/L in orange(nearEquals, T))
			if(L.type == blobType)
				to_chat(src, span_warning("There is a similar blob nearby, move more than [nearEquals] tiles away from it!"))
				return

	if(!can_buy(price))
		return

	var/obj/structure/blob/N = B.change_to(blobType, src)
	return N

/mob/observer/blob/proc/create_shield_power()
	create_shield()

/mob/observer/blob/proc/create_shield_power_op(datum/act/op/A)
	create_shield_power()

/mob/observer/blob/proc/create_shield(turf/T)
	createSpecial(15, blob_type.shield_type, 0, 0, T)

/mob/observer/blob/proc/create_resource_ready(datum/act/op/A)
	if(!blob_type.can_build_resources)
		return MSG(req_silent)
	return null

/mob/observer/blob/proc/create_resource()
	createSpecial(40, blob_type.resource_type, 4, 1)

/mob/observer/blob/proc/create_resource_op(datum/act/op/A)
	create_resource()

/mob/observer/blob/proc/auto_resource_ready(datum/act/op/A)
	if(!blob_type.can_build_resources)
		return MSG(req_silent)
	return null

/mob/observer/blob/proc/auto_resource()
	var/obj/structure/blob/B = null
	var/list/potential_blobs = REGISTRY_COPY(REGISTRY_BLOBS)
	while(potential_blobs.len)
		var/obj/structure/blob/temp = pick(potential_blobs)
		if(!(locate_in_list(range(temp, BLOB_NODE_PULSE_RANGE), /obj/structure/blob/node) ) && !(locate_in_list(range(temp, BLOB_CORE_PULSE_RANGE), /obj/structure/blob/core) ))
			potential_blobs -= temp // Can't be pulsed.
		else if(locate_in_list(range(temp, 4), /obj/structure/blob/resource) )
			potential_blobs -= temp // Too close to another resource blob.
		else if(locate_in_list(range(temp, 1), /obj/structure/blob/core) )
			potential_blobs -= temp // Don't take up the core's shield spot.
		else if(!istype(temp, /obj/structure/blob/normal))
			potential_blobs -= temp // Not a normal blob.
		else if(temp.overmind != src || temp.overmind.blob_type.faction != blob_type.faction)
			potential_blobs -= temp // Not our blob, or even an ally.
		else
			B = temp
			break

		CHECK_TICK // Iterating over a list containing hundreds of blobs can get taxing.

	if(B)
		forceMove(B.loc)
		return createSpecial(40, blob_type.resource_type, 4, 1, B.loc)

/mob/observer/blob/proc/auto_resource_op(datum/act/op/A)
	auto_resource()

/mob/observer/blob/proc/create_factory_ready(datum/act/op/A)
	if(!blob_type.can_build_factories)
		return MSG(req_silent)
	return null

/mob/observer/blob/proc/create_factory()
	createSpecial(60, blob_type.factory_type, 7, 1)

/mob/observer/blob/proc/create_factory_op(datum/act/op/A)
	create_factory()

/mob/observer/blob/proc/auto_factory_ready(datum/act/op/A)
	if(!blob_type.can_build_factories)
		return MSG(req_silent)
	return null

/mob/observer/blob/proc/auto_factory()
	var/obj/structure/blob/B = null
	var/list/potential_blobs = REGISTRY_COPY(REGISTRY_BLOBS)
	while(potential_blobs.len)
		var/obj/structure/blob/temp = pick(potential_blobs)
		if(!(locate_in_list(range(temp, BLOB_NODE_PULSE_RANGE), /obj/structure/blob/node) ) && !(locate_in_list(range(temp, BLOB_CORE_PULSE_RANGE), /obj/structure/blob/core) ))
			potential_blobs -= temp // Can't be pulsed.
		else if(locate_in_list(range(temp, 7), /obj/structure/blob/factory) )
			potential_blobs -= temp // Too close to another factory blob.
		else if(locate_in_list(range(temp, 1), /obj/structure/blob/core) )
			potential_blobs -= temp // Don't take up the core's shield spot.
		else if(!istype(temp, /obj/structure/blob/normal))
			potential_blobs -= temp // Not a normal blob.
		else if(temp.overmind != src || temp.overmind.blob_type.faction != blob_type.faction)
			potential_blobs -= temp // Not our blob, or even an ally
		else
			B = temp
			break

		CHECK_TICK

	if(B)
		forceMove(B.loc)
		return createSpecial(60, blob_type.factory_type, 7, 1, B.loc)

/mob/observer/blob/proc/auto_factory_op(datum/act/op/A)
	auto_factory()

/mob/observer/blob/proc/create_node_ready(datum/act/op/A)
	if(!blob_type.can_build_nodes)
		return MSG(req_silent)
	return null

/mob/observer/blob/proc/create_node()
	createSpecial(100, blob_type.node_type, 5, 0)

/mob/observer/blob/proc/create_node_op(datum/act/op/A)
	create_node()

/mob/observer/blob/proc/auto_node_ready(datum/act/op/A)
	if(!blob_type.can_build_nodes)
		return MSG(req_silent)
	return null

/mob/observer/blob/proc/auto_node()
	var/obj/structure/blob/B = null
	var/list/potential_blobs = REGISTRY_COPY(REGISTRY_BLOBS)
	while(potential_blobs.len)
		var/obj/structure/blob/temp = pick(potential_blobs)
		if(locate_in_list(range(temp, 5), /obj/structure/blob/node) )
			potential_blobs -= temp
		else if(locate_in_list(range(temp, 5), /obj/structure/blob/core) )
			potential_blobs -= temp
		else if(!istype(temp, /obj/structure/blob/normal))
			potential_blobs -= temp
		else if(temp.overmind != src || temp.overmind.blob_type.faction != blob_type.faction)
			potential_blobs -= temp // Not our blob, or even our ally.
		else
			B = temp
			break

		CHECK_TICK

	if(B)
		forceMove(B.loc)
		return createSpecial(100, blob_type.node_type, 5, 0, B.loc)

/mob/observer/blob/proc/auto_node_op(datum/act/op/A)
	auto_node()

/mob/observer/blob/proc/expand_blob_power()
	var/turf/T = get_turf(src)
	expand_blob(T)

/mob/observer/blob/proc/expand_blob_power_op(datum/act/op/A)
	expand_blob_power()

/mob/observer/blob/proc/expand_blob(turf/T)
	var/obj/structure/blob/B = null
	var/turf/other_T = null
	for(var/direction in GLOB.cardinal)
		other_T = get_step(T, direction)
		if(other_T)
			B = locate_on(other_T, /obj/structure/blob)
			if(B && B.overmind == src)
				break

	if(!B)
		to_chat(src, span_warning("There is no blob cardinally adjacent to the target tile!"))
		return

	if(!can_buy(4))
		return

	B.expand(T)

/mob/observer/blob/proc/auto_attack()
	transport_core() // In-case the overmind wandered off somewhere else.

	var/list/potential_targets = list()
	for(var/mob/living/L in view(src))
		if(L.stat == DEAD)
			continue // Already dying or dead.
		if(can_attack(L))
			potential_targets += L

	for(var/obj/mecha/M in view(src))
		if(!M?.slot_item(MECHA_SLOT_PILOT))
			continue // Just a hunk of metal
		if(can_attack(M?.slot_item(MECHA_SLOT_PILOT)))
			potential_targets += M

	if(potential_targets.len)
		var/mob/living/victim = pick(potential_targets)
		var/turf/T = get_turf(victim)
		expand_blob(T)

/mob/observer/blob/proc/auto_attack_op(datum/act/op/A)
	auto_attack()

/mob/observer/blob/proc/can_attack(mob/living/L)
	if(!istype(L))
		return FALSE
	if(mob_rules_of(L).faction == blob_type.faction)
		return FALSE // No friendly fire.
	if(locate_within(get_turf(L), /obj/structure/blob))
		return FALSE // Already has a blob over them.

	for(var/direction in GLOB.cardinal)
		var/turf/T = get_step(L, direction)
		var/obj/structure/blob/B = locate_on(T, /obj/structure/blob)
		if(B && B.overmind == src)
			return TRUE
	return FALSE
