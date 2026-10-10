/// Old attackby. FALSE falls to the drinks handling, as the old ..() did.
/obj/item/reagent_containers/food/drinks/glass2/proc/glass2_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(length(extras) >= 2) return OP_DECLINE // max 2 extras, one on each side of the drink

	if(istype(I, /obj/item/glass_extra))
		var/obj/item/glass_extra/GE = I
		if(can_add_extra(GE))
			rel_add(src, nameof(extras), GE)
			user.remove_from_mob(GE)
			GE.forceMove(src)
			to_chat(user, span_notice("You add \the [GE] to \the [src]."))
		else
			to_chat(user, span_warning("There's no space to put \the [GE] on \the [src]!"))
	else if(istype(I, /obj/item/reagent_containers/food/snacks/fruit_slice))
		if(!rim_pos)
			to_chat(user, span_warning("There's no space to put \the [I] on \the [src]!"))
			return OP_PASS
		var/obj/item/reagent_containers/food/snacks/fruit_slice/FS = I
		rel_add(src, nameof(extras), FS)
		user.remove_from_mob(FS)
		FS.pixel_x = 0 // Reset its pixel offsets so the icons work!
		FS.pixel_y = 0
		FS.forceMove(src)
		to_chat(user, span_notice("You add \the [FS] to \the [src]."))
	else
		return OP_DECLINE
	return OP_PASS

/// Requirement: something on the glass to remove (only asked while the glass is in the other hand; otherwise the effect falls through).
/obj/item/reagent_containers/food/drinks/glass2/proc/can_remove_extra(mob/user, atom/target, obj/item/held)
	if(src != user.get_inactive_hand())
		return TRUE
	if(!length(extras))
		return "there's nothing on the glass to remove"
	return TRUE

/// Old attack_hand.
/obj/item/reagent_containers/food/drinks/glass2/proc/interaction_hand(datum/act/op/A)
	var/refusal = can_remove_extra(A.actor, src, A.held)
	if(refusal != TRUE)
		if(istext(refusal))
			to_chat(A.actor, span_warning(refusal))
		return OP_DECLINE
	var/mob/user = A.actor
	if(src != user.get_inactive_hand())
		return OP_DECLINE

	var/choice = rerun_ask(user, "k37", PROC_REF(interaction_hand), args, /datum/prompt/choice, question = "What would you like to remove from the glass?", title = "Removal Choice", choices = extras)
	if(isnull(choice))
		return OP_OK
	if(!choice || !(choice in extras))
		return OP_OK

	if(user.put_in_active_hand(choice))
		to_chat(user, span_notice("You remove \the [choice] from \the [src]."))
		rel_remove(src, nameof(extras), choice)
	else
		to_chat(user, span_warning("Something went wrong, please try again."))

	return OP_OK

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

CAPABILITIES(/obj/item/glass_extra/straw)
	// Sipping a protean or a promethean (the reagent it gives depends on what they are): three seconds next to them.
	op("sip", at_target(/mob/living/carbon/human), when(req(PROC_REF(sip_reagent_known))), needs(req(PROC_REF(sip_victim_whole), because = MSG(straw/too_little))),
		begins(MSG(straw/sipping)), wait(3 SECONDS), then(PROC_REF(sipp_done)))

MSG_DEF(straw/sipping, span_info("You start sipping on %T% with %I%."), span_infoplain(span_bold("%U%") + " starts sipping on %T% with %I%!"))
MSG_DEF_SELF(straw/too_little, span_warning("There's not enough of %T% left to sip on!"))

/// The reagent a sip of this person gives, or null when they are not something to sip on.
/obj/item/glass_extra/straw/proc/sip_reagent_of(mob/living/carbon/human/H)
	if(!ishuman(H))
		return null
	// Clicked protean blob
	if(istype(H.current_form(), /datum/form/protean_blob))
		return REAGENT_ID_LIQUIDPROTEAN
	// Clicked humanoid
	switch(H.species?.name)
		if(SPECIES_PROTEAN)
			return REAGENT_ID_LIQUIDPROTEAN
		if(SPECIES_PROMETHEAN)
			return REAGENT_ID_NUTRIMENT
	return null

/obj/item/glass_extra/straw/proc/sip_reagent_known(datum/act/op/A)
	return read_once(!isnull(sip_reagent_of(A.target)))

/obj/item/glass_extra/straw/proc/sip_victim_whole(datum/act/op/A)
	var/mob/living/victim = A.target
	return !victim.is_critical()

/obj/item/glass_extra/straw/proc/sipp_done(datum/act/op/A)
	var/mob/living/carbon/human/victim = A.target
	var/mob/user = A.actor
	var/reagent_type = sip_reagent_of(victim) || REAGENT_ID_NUTRIMENT
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
