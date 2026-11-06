/datum/reagent/aluminum
	name = REAGENT_ALUMINIUM
	id = REAGENT_ID_ALUMINIUM
	description = "A silvery white and ductile member of the boron group of chemical elements."
	taste_description = "metal"
	taste_mult = 1.1
	reagent_state = SOLID
	color = "#A8A8A8"
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = 1  // has sheet value
	industrial_use = REFINERYEXPORT_REASON_RAW

/datum/reagent/copper
	name = REAGENT_COPPER
	id = REAGENT_ID_COPPER
	description = "A highly ductile metal."
	taste_description = "pennies"
	color = "#6E3B08"
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = 0.5 SHEET_TO_REAGENT_EQUIVILENT // has sheet value
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/hydrogen
	name = REAGENT_HYDROGEN
	id = REAGENT_ID_HYDROGEN
	description = "A colorless, odorless, nonmetallic, tasteless, highly combustible diatomic gas."
	taste_mult = 0 //no taste
	reagent_state = GAS
	scannable = SCANNABLE_ADVANCED
	color = "#808080"
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/iron
	treatment_tags = list(TREAT_BLOOD_RESTORE = 1.0)
	name = REAGENT_IRON
	id = REAGENT_ID_IRON
	// explain the clinical role rather than the materials-science
	// one. Iron supplements support hemoglobin synthesis, which lets the
	// body produce red blood cells faster. Used as a supportive treatment
	// for anemia from sustained blood loss and as a secondary cure for
	// renal failure (where the kidneys' erythropoietin production fails).
	description = "Pure iron, a metal also essential for the body's blood production. Oral or IV iron supports hemoglobin synthesis, helping a patient who has lost significant blood — or whose kidneys have failed — rebuild their red cell count."
	taste_description = "metal"
	reagent_state = SOLID
	scannable = SCANNABLE_BENEFICIAL
	color = "#353535"
	supply_conversion_value = 1 SHEET_TO_REAGENT_EQUIVILENT // has sheet value
	industrial_use = REFINERYEXPORT_REASON_RAW

/datum/reagent/nitrogen
	name = REAGENT_NITROGEN
	id = REAGENT_ID_NITROGEN
	description = "A colorless, odorless, tasteless gas."
	taste_mult = 0 //no taste
	reagent_state = GAS
	scannable = SCANNABLE_ADVANCED
	color = "#808080"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW
	coolant_modifier = 0.25

/datum/reagent/oxygen
	name = REAGENT_OXYGEN
	id = REAGENT_ID_OXYGEN
	description = "A colorless, odorless gas."
	taste_mult = 0
	reagent_state = GAS
	scannable = SCANNABLE_BENEFICIAL
	color = "#808080"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW
	coolant_modifier = 0.25
	species_injuries_blood = alist(IS_VOX = alist(INJURY_TOXIN = 3))

/datum/reagent/phosphorus
	name = REAGENT_PHOSPHORUS
	id = REAGENT_ID_PHOSPHORUS
	description = "A chemical element, the backbone of biological energy carriers."
	taste_description = "vinegar"
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#832828"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW

/datum/reagent/potassium
	name = REAGENT_POTASSIUM
	id = REAGENT_ID_POTASSIUM
	description = "A soft, low-melting solid that can easily be cut with a knife. Reacts violently with water."
	taste_description = "sweetness" //potassium is bitter in higher doses but sweet in lower ones.
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#A0A0A0"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW

/datum/reagent/silicon
	name = REAGENT_SILICON
	id = REAGENT_ID_SILICON
	description = "A tetravalent metalloid, silicon is less reactive than its chemical analog carbon."
	taste_mult = 0
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#A8A8A8"
	supply_conversion_value = REFINERYEXPORT_VALUE_UNWANTED
	industrial_use = REFINERYEXPORT_REASON_RAW

/datum/reagent/sodium
	name = REAGENT_SODIUM
	id = REAGENT_ID_SODIUM
	description = "A chemical element, readily reacts with water."
	taste_description = "salty metal"
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#808080"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW
	coolant_modifier = 0.25

/datum/reagent/sulfur
	name = REAGENT_SULFUR
	id = REAGENT_ID_SULFUR
	description = "A chemical element with a pungent smell."
	taste_description = "old eggs"
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#BF8C00"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW
	coolant_modifier = -0.25

/datum/reagent/tungsten
	name = REAGENT_TUNGSTEN
	id = REAGENT_ID_TUNGSTEN
	description = "A chemical element, and a strong oxidising agent."
	taste_description = "metal"
	taste_mult = 0 //no taste
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#DCDCDC"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/titanium_dioxide
	name = REAGENT_TITANIUMDIOX
	id = REAGENT_ID_TITANIUMDIOX
	description = "A crumbly white powder, often used in dyes."
	taste_description = "metal"
	taste_mult = 0 //no taste
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#cadcef"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_COSMETIC

/datum/reagent/titanium
	name = REAGENT_TITANIUM
	id = REAGENT_ID_TITANIUM
	description = "A chemical element, lightweight and biologically inert."
	taste_description = "metal"
	taste_mult = 0 //no taste
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#cadcef"
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_INDUSTRY

/datum/reagent/tin
	name = REAGENT_TIN
	id = REAGENT_ID_TIN
	description = "A chemical element, soft and highly flexible."
	taste_description = "metal"
	taste_mult = 0 //no taste
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#efe9ca"
	supply_conversion_value = 0.5 SHEET_TO_REAGENT_EQUIVILENT // has sheet value
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/miasma
	name = REAGENT_MIASMA
	id = REAGENT_ID_MIASMA
	description = "Not necessarily a gas, miasma refers to biological pollutants found in the atmosphere."
	reagent_state = GAS
	scannable = SCANNABLE_ADVANCED
	taste_description = "indescribable"
	color = "#808000"
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD
