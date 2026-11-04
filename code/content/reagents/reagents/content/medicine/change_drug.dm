// === merged from medicine_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
///GENDER CHANGE REAGENTS////

/datum/reagent/change_drug //base chemical
	name = REAGENT_AMORPHOROVIR //always the same name
	id = REAGENT_ID_AMORPHOROVIR
	metabolism = 100 //set high enough that it does not process multiple times(delay implemented below)
	description = "the bloods DNA in this seems aggressive"
	scannable = SCANNABLE_BENEFICIAL
	taste_description = "this shouldn't be here" //unobtainable ingame
	color = "#7F0000"
	var/gender_change = null //set the gender variable here so we can set it to others in varients
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/change_drug/male //inherits base chemical properties listed above
	name = REAGENT_ANDROROVIR
	id = REAGENT_ID_ANDROROVIR //unique ID for each varient
	taste_description = "old spice odor blocker and body wash"
	reagent_state = LIQUID
	description = \
		"A medical concoction, capable of rapidly altering genetic and physical structure of the body. This one seems\
		to realign the target's gender to be male."
	color = "#428AFF"
	gender_change = "male"
	scannable = 1

/datum/reagent/change_drug/female
	name = REAGENT_GYNOROVIR
	id = REAGENT_ID_GYNOROVIR
	description = \
		"A medical concoction, capable of rapidly altering genetic and physical structure of the body. This one seems\
		to realign the target's gender to be female."
	taste_description = "spiced honey"
	reagent_state = LIQUID
	color = "#FFA0FA"
	gender_change = "female"
	scannable = 1

/datum/reagent/change_drug/intersex
	name = REAGENT_ANDROGYNOROVIR
	id = REAGENT_ID_ANDROGYNOROVIR
	description = \
		"A medical concoction, capable of rapidly altering genetic and physical structure of the body. This one seems\
		to realign the target's gender to be mixed."
	taste_description = "something salty and sweet"
	reagent_state = LIQUID
	color = "#CB9EFF"
	gender_change = "plural"
	scannable = 1

/datum/reagent/change_drug
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/change_drug/affect_blood(mob/living/carbon/human/M, alien, removed)
	if (!(M.gender == gender_change || sparse_get_or(M, gender_change_cooldown, 0) == 1) && M.vore_prefs.allow_spontaneous_tf)
		//set not to bug them because the chem is activating
		sparse_set(M, gender_change_cooldown, 1)
		act_message(M, null, MSG_SELF(span_notice("You lose focus as warmth spreads throughout your chest and abdomen.")), \
			MSG_OTHERS(span_notice("%U% suddenly twitches as some of their features seem to contort and reshape.")))
		//wait 30 seconds, growth takes time yo
		after(M, 30 SECONDS, GLOBAL_PROC_REF(change_drug_ask), with = list(M, gender_change))
