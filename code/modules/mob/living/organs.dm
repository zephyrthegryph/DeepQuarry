// Lazy: most living mobs (simple mobs, silicons) have no organs. Humans always
// do and keep them eager (human_defines.dm); butchery animals set theirs per type.
/mob/living
	var/list/internal_organs
	var/list/organs
	var/list/organs_by_name // map organ names to organs
	var/list/internal_organs_by_name // so internal organs have less ickiness too
	var/list/bad_external_organs // organs we check until they are good.

/mob/living/proc/get_bodypart_name(zone)
	var/obj/item/organ/external/E = get_organ(zone)
	if(E) . = E.name

/mob/living/proc/get_organ(zone)
	if(!zone)
		zone = BP_TORSO
	else if (zone in list( O_EYES, O_MOUTH ))
		zone = BP_HEAD
	return LAZYACCESS(organs_by_name, zone)

/// Organ types a mob without a body plan yields when butchered or gibbed
/// (constant per type). Null for mobs whose organs are real from the start.
/mob/living/proc/butchery_organ_types()
	return null

/// Create the butchery organs inside the mob, once. Each lands in the mob's
/// interior slot, where the attach hook caches it in internal_organs
/// (code/modules/body/parts/attach.dm).
/mob/living/proc/spawn_butchery_organs()
	if(LAZYLEN(internal_organs))
		return
	for(var/path in butchery_organ_types())
		var/obj/item/organ/neworg = new path(src, TRUE)
		neworg.name = "[name] [neworg.name]"
		neworg.meat_type = meat_type

/mob/living/gib()
	if(butchery_drops_organs)
		spawn_butchery_organs()

		for(var/obj/item/organ/I in internal_organs?.Copy()) // removed() shrinks the cache
			I.removed()
			if(isturf(I?.loc)) // Some organs qdel themselves or other things when removed
				I.throw_at(get_edge_target_turf(src,pick(GLOB.alldirs)),rand(1,3),30)

		for(var/obj/item/organ/external/E in src.organs?.Copy())
			E.droplimb(0,DROPLIMB_EDGE,1)

	// ition Start
	if(tf_mob_holder && tf_mob_holder.loc == src)
		tf_mob_holder.revert_mob_tf()
		tf_mob_holder.gib()
	// ition End

	..()
