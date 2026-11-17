/datum/reagent/glamour
	name = REAGENT_GLAMOUR
	id = REAGENT_ID_GLAMOUR
	description = "This material is from somewhere else, just being near produces changes."
	taste_description = "change"
	dermal_absorption = 1 //Magic liquid stuff. It immediately clears itself in your system the moment it touches you, so whatever.
	reagent_state = LIQUID
	color = "#ffffff"
	scannable = SCANNABLE_SECRETIVE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_COSMETIC

/datum/reagent/glamour/affect_blood(mob/living/carbon/target, removed)
	grant(target, granted_verb(/mob/living/carbon/human/proc/enter_cocoon), target)
	target.bloodstr.clear_reagents() //instantly clears reagents afterwards
	target.ingested.clear_reagents()
	target.touching.clear_reagents()

/datum/reagent/glamour_transparent
	name = REAGENT_GLAMOUR_INVIS
	id = REAGENT_ID_GLAMOUR_INVIS
	description = "This material is from somewhere else, it can barely be seen by the naked eye."
	taste_description = "nothingness"
	reagent_state = LIQUID
	color = "#ffffff"
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/glamour_transparent/affect_blood(mob/living/carbon/target, removed)
	if(!dq_get_cloaked(target))
		act_message(target, null, others = span_infoplain(span_bold("%U%") + " vanishes from sight."))
		target.cloak()
	target.bloodstr.clear_reagents() //instantly clears reagents afterwards
	target.ingested.clear_reagents()
	target.touching.clear_reagents()
	after(target, 1 MINUTE, TYPE_PROC_REF(/mob/living, glamour_cloak_expires))

/datum/reagent/glamour_scaling
	name = REAGENT_GLAMOUR_SCALE
	id = REAGENT_ID_GLAMOUR_SCALE
	description = "This material is from somewhere else, it appears to change volumes readily at a glance."
	taste_description = "difficult to discern"
	reagent_state = LIQUID
	color = "#ffffff"
	scannable = SCANNABLE_ADVANCED
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/glamour_scaling/affect_blood(mob/living/carbon/target, removed)
	if(!(/mob/living/proc/set_size in target.verbs))
		to_chat(target, span_warning("You feel as though you could change size at any moment."))
		grant(target, granted_verb(/mob/living/proc/set_size), target)
	target.bloodstr.clear_reagents() //instantly clears reagents afterwards
	target.ingested.clear_reagents()
	target.touching.clear_reagents()

/datum/reagent/glamour_twinkling
	name = REAGENT_GLAMOUR_TWINKLING
	id = REAGENT_ID_GLAMOUR_TWINKLING
	description = "This material is from somewhere else, it appears to be twinkling."
	taste_description = "bright"
	reagent_state = LIQUID
	color = "#ffffff"
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/glamour_twinkling/affect_blood(mob/living/carbon/human/target, removed)
	if(target.species.darksight < 10)
		to_chat(target, span_warning("You can suddenly see much better than before."))
		rel_private(target, nameof(target.species)) // per-mob change: never mutate the shared species
		target.species.darksight = 10
	if(target.disabilities() & NEARSIGHTED)
		target.remove_disabilities(NEARSIGHTED)
		to_chat(target, span_warning("Everything is much less blurry."))
	target.bloodstr.clear_reagents() //instantly clears reagents afterwards
	target.ingested.clear_reagents()
	target.touching.clear_reagents()
