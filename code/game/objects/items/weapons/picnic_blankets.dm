#define CENTER 1
#define SIDE 2

/obj/item/picnic_blankets_carried
	name = "picnic blanket"
	desc = "A neatly folded picnic blanket!"
	var/unfolded_desc = "Separates your meal from the dirty floor. Or table."
	icon = 'icons/obj/picnic_vr.dmi'
	icon_state = "picnic_carried"
	w_class = ITEMSIZE_NORMAL
	attack_verb = list("flicked", "whipped", "swooshed")
	force = 0.5
	hitsound = SFX_WEAPONS_TOWELWHIP
	drop_sound = SFX_ITEMS_DROP_CLOTH
	pickup_sound = SFX_ITEMS_PICKUP_CLOTH

CAPABILITIES(/obj/item/picnic_blankets_carried)
	// the old object verb: spread it out where the carrier stands
	op("fold_out", menu(), label("Fold out"), needs(carried(), req_bool(PROC_REF(can_unfold), because = PROC_REF(unfold_refusal))), then(PROC_REF(picnic_blankets_carried_fold_out_effect)))

/// A refused carried blanket must stay folded without allocating floor structures.
/obj/item/picnic_blankets_carried/proc/can_unfold(datum/act/op/A)
	return isnull(unfold_refusal(A))

/obj/item/picnic_blankets_carried/proc/unfold_refusal(datum/act/op/A)
	return A.actor.release_refusal(src, A.actor)

/obj/item/picnic_blankets_carried/proc/picnic_blankets_carried_fold_out_effect(datum/act/op/A)
	var/mob/user = A.actor
	if(unfold_refusal(A) || !loc.release_to(src, user.loc, null, user))
		return OP_OK
	var/obj/structure/picnic_blanket_deployed/P = new /obj/structure/picnic_blanket_deployed(user.loc)
	P.name = name
	P.desc = unfolded_desc
	P.unfold(user)
	replace_with(src, P)
	return OP_OK

/obj/structure/picnic_blanket_deployed
	name = "picnic blanket"
	desc = "Separates your meal from the dirty floor. Or table."
	var/folded_desc = "A neatly folded picnic blanket!"
	icon = 'icons/obj/picnic_vr.dmi'
	icon_state = "picnic_central"
	var/blanket_type = CENTER
	layer = HIDING_LAYER - 0.01 //Stuff shouldn't be able to hide under the blanket on the ground
	var/list/attached_blankets
	anchored = TRUE

TRACKED(/obj/structure/picnic_blanket_deployed, blanket_type)

CAPABILITIES(/obj/structure/picnic_blanket_deployed)
	owns_many(nameof(attached_blankets))
	// the old object verb: pack it up from the center
	op("fold_up", menu(), label("Fold up"), needs(req_bool(PROC_REF(pred_can_fold_up), because = MSG(picnic_blanket/center))), then(PROC_REF(picnic_blanket_deployed_fold_up_effect)))

MSG_DEF_SELF(picnic_blanket/center, "Fold it up from the center.")

/obj/structure/picnic_blanket_deployed/proc/picnic_blanket_deployed_fold_up_effect(datum/act/op/A)
	var/mob/user = A.actor

	rel_clear(src, nameof(attached_blankets))
	var/obj/item/picnic_blankets_carried/P = new /obj/item/picnic_blankets_carried(user.loc)
	P.name = name
	P.desc = folded_desc
	replace_with(src, P)
	return OP_OK

/// Requirement for "Fold up" (old: the verb was removed from edge pieces and locked mapped blankets).
/obj/structure/picnic_blanket_deployed/proc/pred_can_fold_up(datum/act/op/A)
	return blanket_type == CENTER

/obj/structure/picnic_blanket_deployed/proc/unfold(mob/user)
	var/dirs = GLOB.alldirs
	var/isTableTop //Controls whether to spawn things across tables, or on ground
	var/doWeHaveTable //Helper var set to true if ANY obj is a table
	var/anti_spam = FALSE //Helper var to avoid spamming people if they are mired in trash.
	for(var/obj/O in get_turf(src)) //Center element determines behaviour
		if(istype(O, /obj/structure/table))
			isTableTop = TRUE
			layer = TABLE_LAYER + 0.01 //We should be just a bit over tables!

	populate_blankets:
		for(var/dir in dirs)
			var/turf/T = get_step(get_turf(src), dir)
			doWeHaveTable = FALSE //Resetting to False each loop
			if(T.density)
				continue
			if(LAZYLEN(T.contents) > 20) //Avoiding potential perf issues by not iterating over large piles of objs
				if(!anti_spam)
					to_chat(user, span_notice("Too many items! Couldn't fully unfold the blanket!"))
					anti_spam = TRUE
				continue
			for(var/obj/O in turf_contents_of_type(T, /obj))
				if(O.density) //Cables & Atmos machinery dont bother us.
					if(isTableTop && istype(O, /obj/structure/table)) //We expand to the table if the center is a table
						doWeHaveTable = TRUE
						break
					else
						continue populate_blankets
			if(isTableTop && !doWeHaveTable) //However, if center is a table, we don't expand if we havn't found any.
				continue //If center is on table, we only allow the rest to appear on tables as well.

			//Actually spawning
			var/obj/structure/picnic_blanket_deployed/side = new /obj/structure/picnic_blanket_deployed(T)
			rel_add(src, nameof(attached_blankets), side)
			side.set_blanket_type(SIDE)
			side.name = name //Making sure side blankets inherit our vars if they got edited at runtime
			side.desc = desc
			side.set_dir(dir)
			if(isTableTop)
				side.layer = TABLE_LAYER + 0.01 //We should be just above tables.

// Keys are blanket_type: "1" is CENTER, "2" is SIDE (8 directional icon).
/// The look (the draw sweep: from its layers).
/obj/structure/picnic_blanket_deployed/draw(datum/look/look)
	..()
	switch("[blanket_type]")
		if("1")
			look.state("picnic_central")
		if("2")
			look.state("picnic_sides")

/obj/structure/picnic_blanket_deployed/examine(mob/user)
	. = ..()
	if(blanket_type == CENTER)
		. += span_notice("This is the center of a folded out picnic blanket. You can use this to start packing it up!")
	if(blanket_type == SIDE)
		. += span_notice("This is one of the edges. Look for the center to start packing!")

//For Mapping use only.
//If player folds it back up, it reverts to normal type so the Initialize() won't cause issues
//Should be added last to any maps made, to ensure it initializes after all other relevant objs.
//Set unfoldable to TRUE if want to prevent players from picking it up
/obj/structure/picnic_blanket_deployed/for_mapping_use
	name = "RENAME ME"
	var/unfoldable = FALSE


/obj/structure/picnic_blanket_deployed/for_mapping_use/Initialize(mapload)
	. = ..()
	unfold()

TRACKED(/obj/structure/picnic_blanket_deployed/for_mapping_use, unfoldable)

/obj/structure/picnic_blanket_deployed/for_mapping_use/pred_can_fold_up(datum/act/op/A)
	return !unfoldable && ..()

#undef CENTER
#undef SIDE

