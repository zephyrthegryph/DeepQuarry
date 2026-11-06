// Orange juice's mild oxygenation is its treatment_tags profile.

/datum/reagent/toxin/poisonberryjuice // It has more in common with toxins than drinks... but it's a juice
	name = REAGENT_POISONBERRYJUICE
	id = REAGENT_ID_POISONBERRYJUICE
	description = "A tasty juice blended from various kinds of very deadly and toxic berries."
	taste_description = "berries"
	color = "#863353"
	strength = 5

	glass_name = "poison berry juice"
	glass_desc = "A glass of deadly juice."
	cup_prefix = "poison"
	supply_conversion_value = REFINERYEXPORT_VALUE_UNWANTED
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD
