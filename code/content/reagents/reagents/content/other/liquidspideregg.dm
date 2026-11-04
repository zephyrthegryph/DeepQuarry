// === merged from other_ch.dm during hard-fork de-suffix (verified no override-order change) ===
//Misc stuff.

//LIQUID EGG
/datum/reagent/liquidspideregg
	name = REAGENT_SPIDEREGG
	id = REAGENT_ID_SPIDEREGG
	description = "These are eggs, spiders crawl out of these.. probably not healthy inside of a person."
	taste_description = "SO MANY LEGS"
	reagent_state = LIQUID
	color = "#FFFFFF"
	overdose = REAGENTS_OVERDOSE * 100
	metabolism = REM * 0.1
	scannable = 1
	var/amount_grown = 0
	var/min_growth = 0
	var/max_growth = 2
	var/spiders_min = 6
	var/spiders_max = 24
	var/spider_type = /obj/effect/spider/spiderling
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

/datum/reagent/liquidspideregg/affect_blood(mob/living/carbon/M, alien, removed)
	if(prob(1))
		M.custom_pain("You can feel movement within your body!",45)
	amount_grown += rand(min_growth,max_growth)
	if(amount_grown >= 100)
		min_growth++
		max_growth++
		amount_grown = 0
		var/num = rand(spiders_min, spiders_max)
		var/obj/item/organ/external/O = null
		if(istype(M.loc, /obj/item/organ/external))
			O = M.loc

		for(var/i=0, i<num, i++)
			var/spiderling = new spider_type(M.loc, M)
			if(O)
				rel_add(O, nameof(O.implants), spiderling)
