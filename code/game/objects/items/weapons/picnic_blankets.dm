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

/obj/item/picnic_blankets_carried/proc/picnic_blankets_carried_fold_out_effect(mob/user, obj/item/held, datum/interaction/interaction)
	var/obj/structure/picnic_blanket_deployed/P = new /obj/structure/picnic_blanket_deployed(user.loc)
	P.name = name
	P.desc = unfolded_desc
	P.unfold()
	replace_with(src, P)

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

/obj/structure/picnic_blanket_deployed/proc/picnic_blanket_deployed_fold_up_effect(mob/user, obj/item/held, datum/interaction/interaction)

	for(var/obj/structure/picnic_blanket_deployed/side in attached_blankets)
		qdel(side)
	var/obj/item/picnic_blankets_carried/P = new /obj/item/picnic_blankets_carried(user.loc)
	P.name = name
	P.desc = folded_desc
	replace_with(src, P)

/// Requirement for "Fold up" (old: the verb was removed from edge pieces and locked mapped blankets).
/obj/structure/picnic_blanket_deployed/proc/pred_can_fold_up(mob/actor, atom/target, obj/item/held)
	return blanket_type == CENTER

/obj/structure/picnic_blanket_deployed/proc/unfold()
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
					to_chat(usr, span_notice("Too many items! Couldn't fully unfold the blanket!"))
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
			own_add(src, "attached_blankets", side)
			side.blanket_type = SIDE
			side.name = name //Making sure side blankets inherit our vars if they got edited at runtime
			side.desc = desc
			side.set_dir(dir)
			if(isTableTop)
				side.layer = TABLE_LAYER + 0.01 //We should be just above tables.
			side.update_icon()

// Keys are blanket_type: "1" is CENTER, "2" is SIDE (8 directional icon).
DECLARE_APPEARANCE(/obj/structure/picnic_blanket_deployed, "blanket_type", list( \
	"1" = list(APPEARANCE_ICON_STATE = "picnic_central"), \
	"2" = list(APPEARANCE_ICON_STATE = "picnic_sides") \
))

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

/obj/structure/picnic_blanket_deployed/for_mapping_use/pred_can_fold_up(mob/actor, atom/target, obj/item/held)
	return !unfoldable && ..()

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/structure/picnic_blanket_deployed, \
	INTERACT_VERB("Fold up", PROC_REF(picnic_blanket_deployed_fold_up_effect), REQ_ON(PRED_TARGET, /obj/structure/picnic_blanket_deployed/proc/pred_can_fold_up, "fold it up from the center")), \
)

#undef CENTER
#undef SIDE

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/item/picnic_blankets_carried, \
	INTERACT_VERB("Fold out", PROC_REF(picnic_blankets_carried_fold_out_effect), REQ_IN_INVENTORY), \
)
