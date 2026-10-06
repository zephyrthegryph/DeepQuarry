// Lazy: most living mobs (simple mobs, silicons) have no organs. Humans always
// do and keep them eager (human_defines.dm); butchery animals set theirs per type.
/mob/living
	var/list/organs
	var/list/organs_by_name // map organ names to organs

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
TYPE_TABLE_DECLARE(/mob/living, butchery_organ_types, null)

/// Create the butchery organs inside the mob, once. Each lands in the mob's
/// interior slot, where it belongs to the mob (organ_in(), code/modules/body/parts/queries.dm)
/// (code/modules/body/parts/attach.dm).
/mob/living/proc/spawn_butchery_organs()
	if(length(internal_organ_list()))
		return
	for(var/path in TYPE_TABLE_GET(src, butchery_organ_types))
		var/obj/item/organ/neworg = new path(src, TRUE)
		neworg.name = "[name] [neworg.name]"
		neworg.meat_type = meat_type

/mob/living/gib()
	if(butchery_drops_organs)
		spawn_butchery_organs()

		for(var/obj/item/organ/I in internal_organ_list()) // a fresh list: removed() empties the slot
			I.removed()
			if(!QDELETED(I) && isturf(I.loc)) // Some organs qdel themselves or other things when removed
				I.throw_at(get_edge_target_turf(src,pick(GLOB.alldirs)),rand(1,3),30)

		for(var/obj/item/organ/external/E in src.organs?.Copy())
			E.droplimb(0,DROPLIMB_EDGE,1)

	// ition Start
	if(tf_mob_holder && tf_mob_holder.loc == src)
		tf_mob_holder.revert_mob_tf()
		tf_mob_holder.gib()
	// ition End

	..()
