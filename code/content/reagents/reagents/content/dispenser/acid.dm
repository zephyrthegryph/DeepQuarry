/datum/reagent/acid
	name = REAGENT_SACID
	id = REAGENT_ID_SACID
	description = "A very corrosive mineral acid with the molecular formula H2SO4."
	taste_description = "acid"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#DB5008"
	metabolism = REM * 2
	dermal_absorption = 0
	touch_met = 50 // It's acid!
	var/power = 5
	var/meltdose = 10 // How much is needed to melt
	affects_robots = TRUE // it's acid! Still eats metal!
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/acid
	immune_species_blood = SPECIES_TAG_BIT(IS_GREY) // P2-S13

/datum/reagent/acid/affect_blood(mob/living/carbon/M, alien, removed)
	if(issmall(M)) removed *= 2
	M.injure(INJURY_CORROSIVE, removed * power * 2, source = src)

/datum/reagent/acid
	immune_species_touch = SPECIES_TAG_BIT(IS_GREY) // P2-S13

/datum/reagent/acid/affect_touch(mob/living/carbon/M, alien, removed) // This is the most interesting
	if(ishuman(M) && !isbelly(M.loc))
		var/mob/living/carbon/human/H = M
		if(H.get_equipped_item(SLOT_ID_HEAD))
			if(motion_of(H.get_equipped_item(SLOT_ID_HEAD)).unacidable || is_type_in_list(H.get_equipped_item(SLOT_ID_HEAD), GLOB.item_digestion_blacklist))
				to_chat(H, span_danger("Your [H.get_equipped_item(SLOT_ID_HEAD)] protects you from the acid."))
				remove_self(volume)
				return
			else if(removed > meltdose)
				to_chat(H, span_danger("Your [H.get_equipped_item(SLOT_ID_HEAD)] melts away!"))
				H.slot_clear(SLOT_ID_HEAD)
				removed -= meltdose
		if(removed <= 0)
			return

		if(H.get_equipped_item(SLOT_ID_MASK))
			if(motion_of(H.get_equipped_item(SLOT_ID_MASK)).unacidable || is_type_in_list(H.get_equipped_item(SLOT_ID_MASK), GLOB.item_digestion_blacklist))
				to_chat(H, span_danger("Your [H.get_equipped_item(SLOT_ID_MASK)] protects you from the acid."))
				remove_self(volume)
				return
			else if(removed > meltdose)
				to_chat(H, span_danger("Your [H.get_equipped_item(SLOT_ID_MASK)] melts away!"))
				H.slot_clear(SLOT_ID_MASK)
				removed -= meltdose
		if(removed <= 0)
			return

		if(H.get_equipped_item(SLOT_ID_EYES))
			if(motion_of(H.get_equipped_item(SLOT_ID_EYES)).unacidable || is_type_in_list(H.get_equipped_item(SLOT_ID_EYES), GLOB.item_digestion_blacklist))
				to_chat(H, span_danger("Your [H.get_equipped_item(SLOT_ID_EYES)] partially protect you from the acid!"))
				removed /= 2
			else if(removed > meltdose)
				to_chat(H, span_danger("Your [H.get_equipped_item(SLOT_ID_EYES)] melt away!"))
				H.slot_clear(SLOT_ID_EYES)
				removed -= meltdose / 2
		if(removed <= 0)
			return
	if(isbelly(M.loc))
		var/obj/belly/B = M.loc
		if(!M.vore_prefs.digestable || B.digest_mode != DM_DIGEST)
			remove_self(volume)
			return
		if(B.owner)
			if(B.show_liquids && B.reagent_mode_flags & DM_FLAG_REAGENTSDIGEST && B.reagents.total_volume < B.custom_max_volume)
				B.owner_adjust_nutrition(removed * (B.nutrition_percent / 100) * power)
				B.digest_nutri_gain += removed * (B.nutrition_percent / 100) + 0.5
				B.GenerateBellyReagents_digesting()
			else
				B.owner_adjust_nutrition(removed * (B.nutrition_percent / 100) * power)

	// In a belly the acid is digestion; anywhere else it's a chemical burn.
	var/injury_kind = isbelly(M.loc) ? INJURY_DIGESTION : INJURY_CORROSIVE
	if(volume < meltdose) // Not enough to melt anything
		M.injure(injury_kind, removed * power * 0.2, source = src) //Chemical burns. Acid doesn't make bones shatter, like brute trauma would.
		return
	if(!motion_of(M).unacidable && removed > 0)
		if(ishuman(M) && volume >= meltdose)
			var/mob/living/carbon/human/H = M
			var/obj/item/organ/external/affecting = H.get_organ(BP_HEAD)
			if(affecting)
				H.injure(injury_kind, removed * power * 0.1, BP_HEAD, source = src)
				if(prob(100 * removed / meltdose)) // Applies disfigurement
					if (affecting.organ_can_feel_pain() && !isbelly(H.loc))
						H.emote("scream")
					H.set_status_flags(H.status_flags | DISFIGURED)
		else
			M.injure(injury_kind, removed * power * 0.1, source = src) // Balance. The damage is instant, so it's weaker. 10 units -> 5 damage, double for pacid. 120 units beaker could deal 60, but a) it's burn, which is not as dangerous, b) it's a one-use weapon, c) missing with it will splash it over the ground and d) clothes give some protection, so not everything will hit

/datum/reagent/acid/touch_obj(obj/O, amount)
	if(istype(O, /obj/item) && O.loc)
		if(isbelly(O.loc) || isbelly(O.loc.loc))
			var/obj/belly/B = (isbelly(O.loc) ? O.loc : O.loc.loc)
			if(B.item_digest_mode == IM_HOLD)
				return
			var/obj/item/I = O
			var/spent_amt = I.digest_act(B, 1, amount / (meltdose / 3))
			remove_self(spent_amt) //10u stomacid per w_class, less if stronger acid.
			if(B.owner)
				B.owner_adjust_nutrition((B.nutrition_percent / 100) * 5 * spent_amt)
			return
	..()
	if(motion_of(O).unacidable || is_type_in_list(O, GLOB.item_digestion_blacklist))
		return
	if((istype(O, /obj/item) || istype(O, /obj/effect/plant)) && (volume > meltdose))
		var/obj/effect/decal/cleanable/molten_item/I = new/obj/effect/decal/cleanable/molten_item(O.loc)
		I.desc = "Looks like this was \an [O] some time ago."
		for(var/mob/M in viewers(5, O))
			to_chat(M, span_warning("\The [O] melts."))
		dissolved(O)
		remove_self(meltdose) // 10 units of acid will not melt EVERYTHING on the tile

/datum/reagent/acid/touch_mob(mob/living/L)
	if(!isliving(L))
		return
	if(isbelly(L.loc))
		var/obj/belly/B = L.loc
		if(B.digest_mode != DM_DIGEST || !L.vore_prefs.digestable)
			remove_self(volume)
			return
		if(B.owner)
			if(B.show_liquids && B.reagent_mode_flags & DM_FLAG_REAGENTSDIGEST && B.reagents.total_volume < B.custom_max_volume)
				B.owner_adjust_nutrition(volume * (B.nutrition_percent / 100) * power)
				B.digest_nutri_gain += volume * (B.nutrition_percent / 100) + 0.5
				B.GenerateBellyReagents_digesting()
			else
				B.owner_adjust_nutrition(volume * (B.nutrition_percent / 100) * power)
	L.injure(isbelly(L.loc) ? INJURY_DIGESTION : INJURY_CORROSIVE, volume * power * 0.2, source = src)
	remove_self(volume)
