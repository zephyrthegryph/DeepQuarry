/datum/reagent/lipozine // The anti-nutriment.
	name = REAGENT_LIPOZINE
	id = REAGENT_ID_LIPOZINE
	description = "A chemical compound that causes a powerful fat-burning reaction."
	taste_description = "mothballs"
	reagent_state = LIQUID
	color = "#BBEDA4"
	overdose = REAGENTS_OVERDOSE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DIET

/datum/reagent/blackpepper
	name = REAGENT_BLACKPEPPER
	id = REAGENT_ID_BLACKPEPPER
	description = "A powder ground from peppercorns. *AAAACHOOO*"
	taste_description = "pepper"
	reagent_state = SOLID
	ingest_met = REM
	color = "#000000"
	cup_prefix = "peppery"
	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/mustardpods
	name = REAGENT_MUSTARDPODS
	id = REAGENT_ID_MUSTARDPODS
	description = "Densely-packed seed pods from a mustard plant. Good for making mustard. Not much use for anything else."
	taste_description = "sharp, bitter, dry mustard"
	reagent_state = SOLID
	ingest_met = REM
	color = "#B2A00D"
	cup_prefix = "mustardy"
	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/enzyme
	name = REAGENT_ENZYME
	id = REAGENT_ID_ENZYME
	description = "A universal enzyme used in the preperation of certain chemicals and foods."
	taste_description = "sweetness"
	taste_mult = 0.7
	reagent_state = LIQUID
	color = "#365E30"
	overdose = REAGENTS_OVERDOSE
	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/spacespice
	name = REAGENT_SPACESPICE
	id = REAGENT_ID_SPACESPICE
	description = "An exotic blend of spices for cooking. Definitely not worms."
	reagent_state = SOLID
	color = "#e08702"
	cup_prefix = "spicy"
	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/browniemix
	name = REAGENT_BROWNIEMIX
	id = REAGENT_ID_BROWNIEMIX
	description = "A dry mix for making delicious brownies."
	reagent_state = SOLID
	color = "#441a03"
	allergen_type = ALLERGEN_CHOCOLATE
	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/cakebatter
	name = REAGENT_CAKEBATTER
	id = REAGENT_ID_CAKEBATTER
	description = "A batter for making delicious cakes."
	reagent_state = LIQUID
	color = "#F0EDDA"
	wiki_flag = WIKI_FOOD
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD
