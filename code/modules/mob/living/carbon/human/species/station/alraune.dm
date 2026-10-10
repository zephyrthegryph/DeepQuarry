/datum/species/alraune
	name = SPECIES_ALRAUNE
	breath_profile_type = /datum/breath_profile/skin
	name_plural = "Alraunes"
	unarmed_types = list(/datum/unarmed_attack/stomp, /datum/unarmed_attack/kick, /datum/unarmed_attack/punch, /datum/unarmed_attack/bite)
	species_language = LANGUAGE_ENOCHIAN
	num_alternate_languages = 3
	// slow, they're plants. Not as slow as full diona.
	// slow metabolism
	factor_baseline = alist(BF_METABOLISM = 0.75, BF_SLOWDOWN = 1, BF_INCOMING_THERMAL = 1.5)
	total_health = 100 //standard
	//nothing special (brute)
	//plants don't like fire (burn)
	item_slowdown_mod = 0.25 //while they start slow, they don't get much slower
	bloodloss_rate = 0.1 //While they do bleed, they bleed out VERY slowly
	min_age = 18
	max_age = 250
	health_hud_intensity = 1.5
	base_species = SPECIES_ALRAUNE
	selects_bodytype = SELECTS_BODYTYPE_CUSTOM

	wikilink="https://wiki.chompstation13.net/index.php?title=Alraune" // add wiki link

	body_temperature = T20C
	breath_type = GAS_O2
	poison_type = GAS_PHORON
	exhale_type = GAS_O2
	water_breather = TRUE  //eh, why not? Aquatic plants are a thing.

	// Heat and cold resistances are 20 degrees broader on the level 1 range, level 2 is default, level 3 is much weaker, halfway between L2 and normal L3.
	// Essentially, they can tolerate a broader range of comfortable temperatures, but suffer more at extremes.
	cold_level_1 = 240 //Default 260 - Lower is better
	cold_level_2 = 200 //Default 200
	cold_level_3 = 160 //Default 120
	cold_discomfort_level = 260	//they start feeling uncomfortable around the point where humans take damage

	heat_level_1 = 380 //Default 360 - Higher is better
	heat_level_2 = 400 //Default 400
	heat_level_3 = 700 //Default 1000
	heat_discomfort_level = 360

	breath_cold_level_1 = 240 //They don't have lungs, they breathe through their skin
	breath_cold_level_2 = 180 //sadly for them, their breath tolerance is no better than anyone else's.
	breath_cold_level_3 = 140 //mainly 'cause breath tolerance is more generous than body temp tolerance.

	breath_heat_level_1 = 400 //slightly better heat tolerance in air though. Slightly.
	breath_heat_level_2 = 450
	breath_heat_level_3 = 800 //lower incineration threshold though

	spawn_flags = SPECIES_CAN_JOIN
	flags = NO_DNA | NO_SLEEVE | IS_PLANT | NO_MINOR_CUT
	appearance_flags = HAS_HAIR_COLOR | HAS_LIPS | HAS_UNDERWEAR | HAS_SKIN_COLOR | HAS_EYE_COLOR

	genders = list(MALE, FEMALE, NEUTER, PLURAL)

	inherent_verbs = list(/mob/living/carbon/human/proc/alraune_fruit_select, //Give them the voremodes related to wrapping people in vines and sapping their fluids
		/mob/living/carbon/human/proc/tie_hair,
		/mob/living/proc/toggle_thorns)

	color_mult = 1
	icobase = 'icons/mob/human_races/r_human_vr.dmi'
	deform = 'icons/mob/human_races/r_def_human_vr.dmi'
	flesh_color = "#9ee02c"
	blood_color = "#edf4d0" //sap!
	base_color = "#1a5600"

	reagent_tag = IS_ALRAUNE

	blurb = "Alraunes are a rare sight in space. Their bodies are reminiscent of that of plants, and yet they share many\
	traits with other humanoid beings.\
	\
	Most Alraunes are not interested in traversing space, their heavy preference for natural environments and general\
	disinterest in things outside it keeps them as a species at a rather primal stage."
	// removed line referencing Virgo lore which does not apply here.
	catalogue_data = list(/datum/category_item/catalogue/fauna/alraune)

	has_limbs = list(
		BP_TORSO =  list("path" = /obj/item/organ/external/chest),
		BP_GROIN =  list("path" = /obj/item/organ/external/groin),
		BP_HEAD =   list("path" = /obj/item/organ/external/head),
		BP_L_ARM =  list("path" = /obj/item/organ/external/arm),
		BP_R_ARM =  list("path" = /obj/item/organ/external/arm/right),
		BP_L_LEG =  list("path" = /obj/item/organ/external/leg),
		BP_R_LEG =  list("path" = /obj/item/organ/external/leg/right),
		BP_L_HAND = list("path" = /obj/item/organ/external/hand),
		BP_R_HAND = list("path" = /obj/item/organ/external/hand/right),
		BP_L_FOOT = list("path" = /obj/item/organ/external/foot),
		BP_R_FOOT = list("path" = /obj/item/organ/external/foot/right)
		)

	// limited organs, 'cause they're simple
	has_organ = list(
		O_LIVER =    /obj/item/organ/internal/liver/alraune,
		O_KIDNEYS =  /obj/item/organ/internal/kidneys/alraune,
		O_BRAIN =    /obj/item/organ/internal/brain/alraune,
		O_EYES =     /obj/item/organ/internal/eyes/alraune,
		A_FRUIT =    /obj/item/organ/internal/fruitgland,
		)

	// P2-D7: light feeds and (with CO2 from the skin breath) heals; one shared trait.
	species_component = list(/datum/trait_state/photosynth/alraune)


/obj/item/organ/internal/brain/alraune
	icon = 'icons/mob/species/alraune/organs.dmi'
	icon_state = "neurostroma"
	name = "neuro-stroma"
	desc = "A knot of fibrous plant matter."
	parent_organ = BP_TORSO // brains in their core

/obj/item/organ/internal/eyes/alraune
	icon = 'icons/mob/species/alraune/organs.dmi'
	icon_state = "photoreceptors"
	name = "photoreceptors"
	desc = "Bulbous and fleshy plant matter."

/obj/item/organ/internal/kidneys/alraune
	icon = 'icons/mob/species/alraune/organs.dmi'
	icon_state = "rhyzofilter"
	name = "rhyzofilter"
	desc = "A tangle of root nodules."

/obj/item/organ/internal/liver/alraune
	icon = 'icons/mob/species/alraune/organs.dmi'
	icon_state = "phytoextractor"
	name = "enzoretector"
	desc = "A bulbous gourd-like structure."

//Begin fruit gland and its code.
/obj/item/organ/internal/fruitgland //Amazing name, I know.
	icon = 'icons/mob/species/alraune/organs.dmi'
	icon_state = "phytoextractor"
	name = "fruit gland"
	desc = "A bulbous gourd-like structure."
	organ_tag = A_FRUIT
	var/generated_reagents = list(REAGENT_ID_SUGAR = 2) //This actually allows them. This could be anything, but sugar seems most fitting.
	var/usable_volume = 250 //Five fruit.
	var/transfer_amount = 50
	var/empty_message = list("Your have no fruit on you.", "You have a distinct lack of fruit..")
	var/full_message = list("You have a multitude of fruit that is ready for harvest!", "You have fruit that is ready to be picked!")
	var/emote_descriptor = list("fruit right off of the Alraune!", "a fruit from the Alraune!")
	var/verb_descriptor = list("grabs", "snatches", "picks")
	var/self_verb_descriptor = list("grab", "snatch", "pick")
	var/short_emote_descriptor = list("picks", "grabs")
	var/self_emote_descriptor = list("grab", "pick", "snatch")
	var/fruit_type = PLANT_APPLE
	var/mob/living/organ_owner = null
	var/gen_cost = 0.5
	var/poison_reagent

/// Reagents the gland can lace its fruit with (constant).
TYPE_TABLE_DECLARE(/obj/item/organ/internal/fruitgland, poison_options, list( \
								REAGENT_ID_MICROCILLIN, \
								REAGENT_ID_MACROCILLIN, \
								REAGENT_ID_NORMALCILLIN, \
								REAGENT_ID_NUMBENZYME, \
								REAGENT_ID_ANDROROVIR, \
								REAGENT_ID_GYNOROVIR, \
								REAGENT_ID_ANDROGYNOROVIR, \
								REAGENT_ID_STOXIN, \
								REAGENT_ID_RAINBOWTOXIN, \
								REAGENT_ID_PARALYSISTOXIN, \
								REAGENT_ID_PAINENZYME \
	))

CAPABILITIES(/obj/item/organ/internal/fruitgland)
	configure(reagents(volume = nameof(usable_volume)))


/obj/item/organ/internal/fruitgland/organ_tick(cycles)
	if(!owner) return
	var/obj/item/organ/external/parent = owner.get_organ(parent_organ)
	var/before_gen
	if(parent && generated_reagents && organ_owner) //Is it in the chest/an organ, has reagents, and is 'activated'
		before_gen = reagents.total_volume
		if(reagents.total_volume < reagents.maximum_volume)
			if(organ_owner.nutrition >= gen_cost)
				do_generation()

	if(reagents)
		if(reagents.total_volume >= reagents.maximum_volume * 0.05 && before_gen < reagents.maximum_volume * 0.05)
			to_chat(organ_owner, span_notice("[pick(empty_message)]"))
		else if(reagents.total_volume >= reagents.maximum_volume && before_gen < reagents.maximum_volume)
			to_chat(organ_owner, span_warning("[pick(full_message)]"))

/obj/item/organ/internal/fruitgland/proc/do_generation()
	organ_owner.adjust_nutrition(-gen_cost)
	for(var/reagent in generated_reagents)
		reagents.add_reagent(reagent, generated_reagents[reagent])


/mob/living/carbon/human/proc/alraune_fruit_select() //So if someone doesn't want fruit/vegetables, they don't have to select one.
	set name = "Select fruit"
	set desc = "Select what fruit/vegetable you wish to grow."
	set category = VERB_CAT_ABILITIES_ALRAUNE
	var/obj/item/organ/internal/fruitgland/fruit_gland
	for(var/F in contents)
		if(istype(F, /obj/item/organ/internal/fruitgland))
			fruit_gland = F
			break

	if(!fruit_gland)
		to_chat(src, span_notice("You lack the organ required to produce fruit."))
		return
	open_request(src, /datum/prompt/choice/fruit_gland, PROC_REF(alraune_fruit_chosen), answerer = src, question = "Choose your character's fruit type. Choosing nothing will result in a default of apples.", title = "Fruit Type", choices = GLOB.acceptable_fruit_types, gland = fruit_gland)

/// A fruit gland setting. Re-checked on the answer: the gland is still in the answerer.
/datum/prompt/choice/fruit_gland
	timeout = 0
	var/obj/item/organ/internal/fruitgland/gland

CAPABILITIES(/datum/prompt/choice/fruit_gland)
	ref_one(nameof(gland), /obj/item/organ/internal/fruitgland)

/datum/prompt/choice/fruit_gland/prepare(datum/act/context)
	. = ..()
	var/obj/item/organ/internal/fruitgland/captured = gland
	rel_clear(src, nameof(gland))
	rel_set(src, nameof(gland), captured)

/datum/prompt/choice/fruit_gland/recheck_extra()
	. = ..()
	if(.)
		return
	return !QDELETED(gland) && gland.loc == answerer ? null : "gland gone"

/mob/living/carbon/human/proc/alraune_fruit_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/fruit_gland/ask = A.request
	var/obj/item/organ/internal/fruitgland/fruit_gland = ask.gland
	fruit_gland.fruit_type = ask.value
	grant(src, granted_verb(/mob/living/carbon/human/proc/alraune_fruit_pick), src)
	grant(src, granted_verb(/mob/living/carbon/human/proc/alraune_fruit_reagent), src)
	rel_set(fruit_gland, nameof(fruit_gland.organ_owner), src)
	fruit_gland.emote_descriptor = list("fruit right off of [fruit_gland.organ_owner]!", "a fruit from [fruit_gland.organ_owner]!")

/mob/living/carbon/human/proc/alraune_fruit_pick()
	set name = "Pick Fruit"
	set desc = "Pick fruit off of the fruit gland."
	set category = VERB_CAT_OBJECT
	set src in view(1)

	if(!isliving(usr) || !usr.checkClickCooldown())
		return

	if(usr.incapacitated() || usr.stat > CONSCIOUS)
		return

	var/obj/item/organ/internal/fruitgland/fruit_gland
	for(var/I in contents)
		if(istype(I, /obj/item/organ/internal/fruitgland))
			fruit_gland = I
			break
	if (fruit_gland) //Do they have the gland?
		if(fruit_gland.reagents.total_volume < fruit_gland.transfer_amount)
			to_chat(src, span_notice("[pick(fruit_gland.empty_message)]"))
			return

		var/datum/seed/S = plants_seeds()["[fruit_gland.fruit_type]"]

		if(fruit_gland.poison_reagent)
			S.harvest(usr,0,0,1,fruit_gland.poison_reagent,10)
			log_admin("[src] played by [src.ckey] has produced a fruit containing [fruit_gland.poison_reagent]. It was picked by [usr].")
		else
			S.harvest(usr,0,0,1)

		var/index = rand(1,2)

		if (usr != src)
			var/emote = fruit_gland.emote_descriptor[index]
			var/verb_desc = fruit_gland.verb_descriptor[index]
			var/self_verb_desc = fruit_gland.self_verb_descriptor[index]
			act_message(usr, null, MSG_SELF(span_notice("You [self_verb_desc] [emote]")), MSG_OTHERS(span_notice("%U% [verb_desc] [emote]")))
		else
			act_message(src, null, MSG_SELF(span_notice("You [pick(fruit_gland.self_emote_descriptor)] a fruit.")), \
				MSG_OTHERS(span_notice("%U% [pick(fruit_gland.short_emote_descriptor)] a fruit.")))

		fruit_gland.reagents.remove_any(fruit_gland.transfer_amount)

/mob/living/carbon/human/proc/alraune_fruit_reagent()
	set name = "Poison Fruit"
	set desc = "Select a reagent to be placed in your fruit."
	set category = VERB_CAT_ABILITIES_ALRAUNE

	if(!isliving(usr) || !usr.checkClickCooldown())
		return

	if(usr.incapacitated() || usr.stat > CONSCIOUS)
		return

	var/obj/item/organ/internal/fruitgland/fruit_gland
	for(var/I in contents)
		if(istype(I, /obj/item/organ/internal/fruitgland))
			fruit_gland = I
			break

	if(fruit_gland)
		// A cancel answers "" and clears the poison.
		open_request(src, /datum/prompt/choice/fruit_gland, PROC_REF(alraune_poison_chosen), answerer = src, question = "Choose which reagent to poison your fruit with! Be aware, this option is intended for use in scenes and ERP. This is not for use as pranks or to change the gender of unsuspecting crew, and you must be aware of the preferences of the people who eat it. Do not just leave it out unattended.", title = "Select reagent", choices = TYPE_TABLE_GET(fruit_gland, poison_options), ask_flags = ASK_CONSCIOUS, gland = fruit_gland)

/mob/living/carbon/human/proc/alraune_poison_chosen(datum/act/request/A)
	var/datum/prompt/choice/fruit_gland/ask = A.request
	if(!A.answer && !(ask.outcome == REQ_CANCELLED && isnull(ask.value)))
		return
	var/obj/item/organ/internal/fruitgland/fruit_gland = ask.gland
	if(QDELETED(fruit_gland))
		return
	var/poison_choice = A.answer ? ask.value : ""
	if(!poison_choice)
		to_chat(src, span_notice("You have chosen no poison to add, any previously chosen poisons have been cleared and no poison will be added to produced fruits."))
		fruit_gland.poison_reagent = null
	else
		fruit_gland.poison_reagent = poison_choice
		to_chat(src, span_notice("Fruit that you produce will now contain [poison_choice]. Be aware of out of character consent."))

//End of fruit gland code.

/datum/species/alraune/get_race_key()
	var/datum/species/real = GLOB.all_species[base_species]
	return real.race_key

// This organ has work every organ_tick(), so the body's organ clock stays running for it.
/obj/item/organ/internal/fruitgland/life_step_idle()
	return FALSE
