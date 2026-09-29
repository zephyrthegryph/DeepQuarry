/obj/structure/mopbucket
	name = "mop bucket"
	desc = "Fill it with water, but don't forget a mop!"
	icon = 'icons/obj/janitor.dmi'
	icon_state = "mopbucket"
	density = TRUE
	w_class = ITEMSIZE_NORMAL
	pressure_resistance = 5
	flags = OPENCONTAINER
	var/amount_per_transfer_from_this = 5	//shit I dunno, adding this so syringes stop runtime erroring. --NeoFite

REGISTRY_MEMBERSHIP(/obj/structure/mopbucket, REGISTRY_MOP_BUCKETS)

DECLARE_REAGENTS(/obj/structure/mopbucket, 300, null)

/obj/structure/mopbucket/Initialize(mapload, ...)
	. = ..()
	make_climbable()

/obj/structure/mopbucket/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "It contains [reagents.total_volume] unit\s of water!"

/obj/structure/mopbucket/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/mopbucket_item,
	)
	..()

/// Old attackby: wet a mop/soap/rag in the bucket.
/datum/interaction/entry_item/mopbucket_item
	id = "mopbucket_item"
	name = "Use"
	effect = /obj/structure/mopbucket/proc/interaction_item

/obj/structure/mopbucket/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I, /obj/item/mop) || istype(I, /obj/item/soap) || istype(I, /obj/item/reagent_containers/glass/rag)) // "Allows soap and rags to be used on mopbuckets"
		if(reagents.total_volume < 1)
			user.balloon_alert(user, "\the [src] is out of water!")
		else
			reagents.trans_to_obj(I, 5)
			user.balloon_alert(user, "you wet \the [I] in \the [src].")
			play_sfx(src, SFX_EFFECTS_SLOSH)
	return TRUE
