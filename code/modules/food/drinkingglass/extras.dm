/// Old attackby. FALSE falls to the drinks handling, as the old ..() did.
/obj/item/reagent_containers/food/drinks/glass2/proc/glass2_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(length(extras) >= 2) return FALSE // max 2 extras, one on each side of the drink

	if(istype(I, /obj/item/glass_extra))
		var/obj/item/glass_extra/GE = I
		if(can_add_extra(GE))
			rel_add(src, nameof(extras), GE)
			user.remove_from_mob(GE)
			GE.forceMove(src)
			to_chat(user, span_notice("You add \the [GE] to \the [src]."))
			update_icon()
		else
			to_chat(user, span_warning("There's no space to put \the [GE] on \the [src]!"))
	else if(istype(I, /obj/item/reagent_containers/food/snacks/fruit_slice))
		if(!rim_pos)
			to_chat(user, span_warning("There's no space to put \the [I] on \the [src]!"))
			return INTERACTION_HANDLED_PASS
		var/obj/item/reagent_containers/food/snacks/fruit_slice/FS = I
		rel_add(src, nameof(extras), FS)
		user.remove_from_mob(FS)
		FS.pixel_x = 0 // Reset its pixel offsets so the icons work!
		FS.pixel_y = 0
		FS.forceMove(src)
		to_chat(user, span_notice("You add \the [FS] to \the [src]."))
		update_icon()
	else
		return FALSE
	return INTERACTION_HANDLED_PASS

EXTEND_INTERACTIONS(/obj/item/reagent_containers/food/drinks/glass2, \
	INTERACT_HAND(null, PROC_REF(interaction_hand), REQ_TARGET_STATE(/obj/item/reagent_containers/food/drinks/glass2/proc/can_remove_extra)), \
	INTERACT_ITEM(null, PROC_REF(glass2_item)), \
)

/// Requirement: something on the glass to remove (only asked while the glass is in the other hand; otherwise the effect falls through).
/obj/item/reagent_containers/food/drinks/glass2/proc/can_remove_extra(mob/user, atom/target, obj/item/held)
	if(src != user.get_inactive_hand())
		return TRUE
	if(!length(extras))
		return "there's nothing on the glass to remove"
	return TRUE

/// Old attack_hand.
/obj/item/reagent_containers/food/drinks/glass2/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(src != user.get_inactive_hand())
		return FALSE

	var/choice = rerun_ask(user, "k37", PROC_REF(interaction_hand), args, /datum/prompt/choice, question = "What would you like to remove from the glass?", title = "Removal Choice", choices = extras)
	if(isnull(choice))
		return TRUE
	if(!choice || !(choice in extras))
		return TRUE

	if(user.put_in_active_hand(choice))
		to_chat(user, span_notice("You remove \the [choice] from \the [src]."))
		rel_remove(src, nameof(extras), choice)
	else
		to_chat(user, span_warning("Something went wrong, please try again."))

	update_icon()
	return TRUE

/obj/item/glass_extra
	name = "generic glass addition"
	desc = "This goes on a glass."
	var/glass_addition
	var/glass_desc
	var/glass_color
	w_class = ITEMSIZE_TINY
	icon = DRINK_ICON_FILE

/obj/item/glass_extra/stick
	name = "stick"
	desc = "This goes in a glass."
	glass_addition = "stick"
	glass_desc = "There is a stick in the glass."
	icon_state = "stick"

/obj/item/glass_extra/straw
	name = "straw"
	desc = "This goes in a glass."
	glass_addition = "straw"
	glass_desc = "There is a straw in the glass."
	icon_state = "straw"

// This isn't great code, so if you're doing something that happens many times or isn't user-initiated
// like this is, where it'll likely happen 0-4 times a shift, then don't copy this pattern.
/obj/item/glass_extra/straw/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	if(ismob(target) && proximity_flag)
		// Clicked protean blob
		var/mob/living/carbon/human/blob_host = target
		if(ishuman(blob_host) && istype(blob_host.current_form(), /datum/form/protean_blob))
			sipp_mob(target, user, REAGENT_ID_LIQUIDPROTEAN)
			return
		// Clicked humanoid
		else if(ishuman(target))
			var/mob/living/carbon/human/H = target
			var/speciesname = H.species?.name
			switch(speciesname)
				if(SPECIES_PROTEAN)
					sipp_mob(target, user, REAGENT_ID_LIQUIDPROTEAN)
					return
				if(SPECIES_PROMETHEAN)
					sipp_mob(target, user, REAGENT_ID_NUTRIMENT)
					return
	return ..()

/obj/item/glass_extra/straw/proc/sipp_mob(mob/living/victim, mob/user, reagent_type = REAGENT_ID_NUTRIMENT)
	if(victim.is_critical())
		to_chat(user, span_warning("There's not enough of [victim] left to sip on!"))
		return

	act_message(user, victim, MSG_SELF(span_info("You start sipping on %T% with [src].")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + " starts sipping on %T% with [src]!")))
	task_start(/datum/task/timed/straw_sipp, user, victim, reagent_type = reagent_type)

/datum/task/timed/straw_sipp
	duration = 3 SECONDS
	complete_proc = /obj/item/glass_extra/straw/proc/sipp_done
	var/reagent_type

/obj/item/glass_extra/straw/proc/sipp_done(datum/task/timed/straw_sipp/task)
	var/mob/living/victim = task.target
	var/mob/user = task.actor
	var/reagent_type = task.reagent_type
	act_message(user, victim, MSG_SELF(span_info("You take a sip of %T% with [src]. Yum!")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + " sips some of %T% with [src]!")))
	if(victim.vore_taste)
		to_chat(user, span_infoplain(span_bold("[victim]") + " tastes like... [victim.vore_taste]!"))

	victim.injure(INJURY_BLUNT, 5, source = src)

	// If you're human you get the reagent
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		H.ingested.add_reagent(reagent_type, 2)
	// Anything else just gets some nutrition
	else if(isliving(user))
		var/mob/living/L = user
		L.adjust_nutrition(30)

#undef DRINK_ICON_FILE
