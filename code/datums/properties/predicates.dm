// Concrete fitting, tool and body-hand predicate adapters.
/datum/pred_node/fits/test(mob/actor, atom/target, obj/item/held)
	if(!ishuman(actor) || !isitem(target))
		return TRUE
	var/mob/living/carbon/human/H = actor
	if(!H.species)
		return TRUE
	var/obj/item/I = target
	return dq_fits_bodytype(bodytypes, exclusive, H.species.get_bodytype(H), I.sprite_sheets)

/datum/pred_node/fits/generate_reason(mob/actor, atom/target, obj/item/held)
	if(negate)
		return "it fits you"
	var/bodytype = "your body"
	if(ishuman(actor))
		var/mob/living/carbon/human/H = actor
		bodytype = H.species?.get_bodytype(H) || bodytype
	if(exclusive)
		return "it doesn't fit a [bodytype]"
	var/list/names = bodytypes.Copy()
	if(length(names) > 3)
		return "it isn't made for a [bodytype]"
	return "it only fits [english_list(names, and_text = " or ")]"

/// Whether clothing restricted to `bodytypes` fits `bodytype`. Custom-fitted
/// Vox, Werebeast and Teshari clothing fits only them, and Teshari and
/// Werebeasts need their own sprites for anything restricted.
/proc/dq_fits_bodytype(list/bodytypes, exclusive, bodytype, list/sprite_sheets)
	if(exclusive)
		return !(bodytype in bodytypes)
	if(bodytype in bodytypes)
		return TRUE
	if(((SPECIES_VOX in bodytypes) && bodytype != SPECIES_VOX) || ((SPECIES_WEREBEAST in bodytypes) && bodytype != SPECIES_WEREBEAST) || ((SPECIES_TESHARI in bodytypes) && bodytype != SPECIES_TESHARI))
		return FALSE
	if((bodytype == SPECIES_TESHARI || bodytype == SPECIES_WEREBEAST) && !LAZYACCESS(sprite_sheets, bodytype))
		return FALSE
	return TRUE


/datum/pred_node/tool/test(mob/actor, atom/target, obj/item/held)
	if(!istype(held) || !held.has_tool_quality(quality))
		return FALSE
	return tier <= 1 || dq_tool_tier(held, quality) >= tier


/// Tier of `quality` on `I`: its value in an associative tool_qualities list, else 1.
/proc/dq_tool_tier(obj/item/I, quality)
	if(!I.has_tool_quality(quality))
		return 0
	var/tier = I.tool_qualities[quality]
	return isnum(tier) ? tier : 1


/mob/living/carbon/human/dq_has_free_hand()
	return !get_equipped_item(SLOT_ID_HAND_L) || !get_equipped_item(SLOT_ID_HAND_R)

/mob/living/simple_mob/dq_has_free_hand()
	return has_hands && (!get_equipped_item(SLOT_ID_HAND_L) || !get_equipped_item(SLOT_ID_HAND_R))


/datum/pred_node/in_hand/test(mob/actor, atom/target)
	if(!actor || !target)
		return FALSE
	return actor.get_active_hand() == target || actor.get_inactive_hand() == target
