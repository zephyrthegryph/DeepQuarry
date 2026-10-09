////////////////////////////////////////////////////////////////////////////////
/// Droppers.
////////////////////////////////////////////////////////////////////////////////
/obj/item/reagent_containers/dropper
	name = "dropper"
	desc = "A dropper. Transfers up to 5 units at a time."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "dropper0"
	amount_per_transfer_from_this = 5
	max_transfer_amount = 5
	min_transfer_amount = 1
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	volume = 5
	drop_sound = SFX_ITEMS_DROP_GLASS
	pickup_sound = SFX_ITEMS_PICKUP_GLASS

// A dropper is a sealed container of its volume that draws from open containers and tanks while it is empty and squirts what it holds into open
// containers, food and cigarettes, or into a person's eyes (two seconds; glasses or a mask over the eyes take the squirt instead). The amount it
// moves is set from 1 to its largest. What it holds is told to two tiles.
CAPABILITIES(/obj/item/reagent_containers/dropper)
	reagent_container(
		volume = nameof(volume),
		needle = TRUE,
		sealed = TRUE,
		transfer_default = nameof(amount_per_transfer_from_this),
		transfer_min = nameof(min_transfer_amount),
		transfer_max = nameof(max_transfer_amount),
		examine_range = 2)
	needle(
		draws_from = list(/obj/structure/reagent_dispensers),
		fills = list(/obj/item/reagent_containers/food, /obj/item/clothing/mask/smokable/cigarette))
	op("squirt", at_target(/mob/living), label("Squirt into eyes"), begins(MSG(dropper/begin)), wait(2 SECONDS),
		needs(req_reagents(1, because = MSG(dropper/empty)), req_reagent_room(because = MSG(needle/target_full))),
		then(PROC_REF(squirted)))

MSG_DEF_SELF(dropper/empty, "The dropper is empty.")
MSG_DEF(dropper/begin, null, "%U% is trying to squirt something into %T%'s eyes!")

/// The squirt: into the eyes of the person it was aimed at.
/obj/item/reagent_containers/dropper/proc/squirted(datum/act/op/A)
	squirt_done(A.actor, A.target)
	return OP_OK

/obj/item/reagent_containers/dropper/proc/squirt_done(mob/user, mob/target)
	if(!reagents.total_volume)
		return
	var/trans = 0
	if(ishuman(target))
		var/mob/living/carbon/human/victim = target

		var/obj/item/safe_thing = null
		if(victim.get_equipped_item(SLOT_ID_MASK))
			if (victim.get_equipped_item(SLOT_ID_MASK).body_parts_covered & EYES)
				safe_thing = victim.get_equipped_item(SLOT_ID_MASK)
		if(victim.get_equipped_item(SLOT_ID_HEAD))
			if (victim.get_equipped_item(SLOT_ID_HEAD).body_parts_covered & EYES)
				safe_thing = victim.get_equipped_item(SLOT_ID_HEAD)
		if(victim.get_equipped_item(SLOT_ID_EYES))
			if (!safe_thing)
				safe_thing = victim.get_equipped_item(SLOT_ID_EYES)

		if(safe_thing)
			trans = reagents.splash(safe_thing, min(amount_per_transfer_from_this, reagents.total_volume), max_spill=30, user = user)
			act_message(user, target, MSG_SELF(span_notice("You transfer [trans] units of the solution.")), \
				MSG_OTHERS(span_warning("%U% tries to squirt something into %T%'s eyes, but fails!")))
			return

	var/contained = reagentlist()
	add_attack_logs(user,target,"Used [src.name] containing [contained]")

	trans += reagents.trans_to_mob(target, min(amount_per_transfer_from_this, reagents.total_volume)/2, CHEM_INGEST, can_dialysis = FALSE) //Half injected, half ingested
	trans += reagents.trans_to_mob(target, min(amount_per_transfer_from_this, reagents.total_volume), CHEM_BLOOD) //I guess it gets into the bloodstream through the eyes or something
	act_message(user, target, MSG_SELF(span_notice("You transfer [trans] units of the solution.")), \
		MSG_OTHERS(span_warning("%U% squirts something into %T%'s eyes!")))

/// Appearance reader: TRUE while the dropper holds reagents.
/obj/item/reagent_containers/dropper/proc/appearance_filled()
	return reagents?.total_volume ? TRUE : FALSE

/// The look (the draw sweep: from its template).
/obj/item/reagent_containers/dropper/draw(datum/look/look)
	..()
	look.watch(reagents)
	look.state("dropper[appearance_filled() ? "1" : "0"]")

/obj/item/reagent_containers/dropper/industrial
	name = "Industrial Dropper"
	desc = "A larger dropper. Transfers up to 10 units at a time."
	amount_per_transfer_from_this = 10
	max_transfer_amount = 10
	min_transfer_amount = 1
	volume = 10

////////////////////////////////////////////////////////////////////////////////
/// Droppers. END
////////////////////////////////////////////////////////////////////////////////
