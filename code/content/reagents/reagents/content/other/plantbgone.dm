//New reagent definitions/overrides. If some of these get added upstream and cause a conflict later they might need deleting.
/datum/reagent/toxin/plantbgone/touch_mob(mob/living/L, amount) //Plantbgone override to damage plant mobs. Part of pitcher plants, touch_mob doesn't exist for plantbgone at the time of writing.
	if(istype(L) && mob_rules_of(L).faction)
		if(mob_rules_of(L).faction == "plants") //This would be better with a variable but I'm not adding that because upstream conflicts. If you send this upstream please do this.
			L.injure(INJURY_TOXIN, 15 * amount, source = src)
			act_message(L, null, MSG_SELF(span_danger("The chemical burns you!")), MSG_OTHERS(span_warning("%U% withers rapidly!")))
