GLOBAL_LIST_INIT(gurgled_overlays, list(
								"green" = image('icons/effects/sludgeoverlay_vr.dmi', icon_state = "green"),
								"white" = image('icons/effects/sludgeoverlay_vr.dmi', icon_state = "white"),
								"black" = image('icons/effects/sludgeoverlay_vr.dmi', icon_state = "black"),
								"grey" = image('icons/effects/sludgeoverlay_vr.dmi', icon_state = "grey"),
								"yellow" = image('icons/effects/sludgeoverlay_vr.dmi', icon_state = "yellow"),
								"red" = image('icons/effects/sludgeoverlay_vr.dmi', icon_state = "red"),
								"blue" = image('icons/effects/sludgeoverlay_vr.dmi', icon_state = "blue"),
								"orange" = image('icons/effects/sludgeoverlay_vr.dmi', icon_state = "orange"),
								"purple" = image('icons/effects/sludgeoverlay_vr.dmi', icon_state = "purple"),
								"lime" = image('icons/effects/sludgeoverlay_vr.dmi', icon_state = "lime"),
								"brown" = image('icons/effects/sludgeoverlay_vr.dmi', icon_state = "brown"),
								"darkred" = image('icons/effects/sludgeoverlay_vr.dmi', icon_state = "darkred"),
								"cyan" = image('icons/effects/sludgeoverlay_vr.dmi', icon_state = "cyan"),
								"beige" = image('icons/effects/sludgeoverlay_vr.dmi', icon_state = "beige"),
								"pink" = image('icons/effects/sludgeoverlay_vr.dmi', icon_state = "pink")
								))

/obj/item/proc/gurgle_contaminate(atom/movable/item_storage = null, contamination_flavor = "Generic", contamination_color = "green")
	if(!can_gurgle())
		return FALSE

	if(gurgled && !(gurgled_color == contamination_color))
		wash(CLEAN_WASH)

	if(!gurgled)
		gurgled = TRUE
		gurgled_color = contamination_color
		if(!isbelly(src.loc)) //Moved non-worn overlay stuff to belly_obj_vr.dm Exited proc. No need to add overlays to things that won't make it out.
			add_overlay(GLOB.gurgled_overlays[gurgled_color])
		var/list/pickfrom = GLOB.contamination_flavors[contamination_flavor]
		var/gurgleflavor = pick(pickfrom)
		cleanname = src.name
		cleandesc = src.desc
		name = "[gurgleflavor] [cleanname]"
		desc = "[cleandesc] It seems to be covered in ominously foul residue and needs a wash."
		return TRUE

/obj/item/proc/can_gurgle()
	if(flags & PHORONGUARD)
		return FALSE
	else if(unacidable)
		return FALSE
	else
		return TRUE

// Added ahead of the sink's own ops (its CAPABILITIES block in watercloset.dm).

/// Old attackby: wash the soggy item before it can interact with the sink.
/obj/structure/sink/proc/sink_wash_gurgled_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I) && I.gurgled)
		to_chat(user, span_notice("You start washing [I]."))

		task_timed(user, 4 SECONDS, src, src, PROC_REF(wash_gurgled_done), list(user, I), claims = TRUE) // the wash claims the sink
		return TRUE
	return OP_DECLINE

/obj/structure/sink/proc/wash_gurgled_done(mob/user, obj/item/I)
	I.wash(CLEAN_SCRUB)
	act_message(user, src, MSG_SELF(span_notice("You wash [I] using %T%.")), MSG_OTHERS(span_notice("%U% washes [I] using %T%.")))

//////////////
// Special handling of gurgle_contaminate
//////////////
/obj/item/card/id/gurgle_contaminate(atom/movable/item_storage = null)
	digest_act(item_storage) //Contamination and digestion does same thing to these
	return TRUE

/obj/item/pda/gurgle_contaminate(atom/movable/item_storage = null)
	return FALSE

/obj/item/reagent_containers/food/gurgle_contaminate(atom/movable/item_storage = null)
	return FALSE

/obj/item/storage/vore_egg/gurgle_contaminate(atom/movable/item_storage = null)
	return FALSE

/obj/item/holder/gurgle_contaminate(atom/movable/item_storage = null)
	if(isbelly(loc))
		digest_act(item_storage)
		return TRUE
	return FALSE

/obj/item/organ/gurgle_contaminate(atom/movable/item_storage = null)
	return FALSE

/obj/item/cell/gurgle_contaminate(atom/movable/item_storage = null)
	if(!gurgled)
	//Don't make them wet, just drain
		var/obj/item/cell/C = src
		C.charge = 0
	return TRUE

/obj/item/storage/box/gurgle_contaminate(atom/movable/item_storage = null)
	if((. = ..()))
		name = "soggy [cleanname]"
		desc = "This soggy box is about to fall apart any time."

//Storages that contaminate contents
/obj/item/storage/backpack/gurgle_contaminate(atom/movable/item_storage = null, contamination_flavor = "Generic", contamination_color = "green")
	make_contents_real()
	if(contents)
		for(var/obj/item/O in contents) // ALLOW(latent): walk reviewed: reads what is materialized on purpose
			O.gurgle_contaminate(item_storage, contamination_flavor, contamination_color)
	..()

/obj/item/storage/belt/gurgle_contaminate(atom/movable/item_storage = null, contamination_flavor = "Generic", contamination_color = "green")
	make_contents_real()
	if(contents)
		for(var/obj/item/O in contents) // ALLOW(latent): walk reviewed: reads what is materialized on purpose
			O.gurgle_contaminate(item_storage, contamination_flavor, contamination_color)
	..()

/obj/item/clothing/suit/storage/gurgle_contaminate(atom/movable/item_storage = null, contamination_flavor = "Generic", contamination_color = "green")
	if(pockets)
		if(pockets.contents)
			for(var/obj/item/O in contents_of(pockets))
				O.gurgle_contaminate(item_storage, contamination_flavor, contamination_color)
	..()
