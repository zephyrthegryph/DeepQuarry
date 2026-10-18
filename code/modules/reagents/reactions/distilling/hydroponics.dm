// Hydroponics refinery fun
/transformation/chem/distilling/fertilizer

CAPABILITIES(/transformation/chem/distilling/fertilizer)
	configure(transformation(name = REAGENT_FERTILIZER, id = "distill_fertilizer",
		takes = list(reagent(REAGENT_ID_WATER, 5), reagent(REAGENT_ID_NUTRIMENT, 1), reagent(REAGENT_ID_PHOSPHORUS, 1), reagent(REAGENT_ID_SULFUR, 1)),
		makes = list(reagent(REAGENT_ID_FERTILIZER, 3)),
		holds = xform_all(temperature_in(T20C + 40, T20C + 60), ambient_gas_over(GAS_CO2, 10), ambient_gas_under(GAS_N2, 1))))


/transformation/chem/distilling/eznutrient

CAPABILITIES(/transformation/chem/distilling/eznutrient)
	configure(transformation(name = REAGENT_EZNUTRIENT, id = "distill_eznutriment",
		takes = list(reagent(REAGENT_ID_FERTILIZER, 1), reagent(REAGENT_ID_CALCIUM, 1), reagent(REAGENT_ID_CARBON, 2)),
		makes = list(reagent(REAGENT_ID_EZNUTRIENT, 1)),
		holds = xform_all(temperature_in(T0C + 10, T0C + 50), ambient_gas_over(GAS_O2, 10), ambient_gas_under(GAS_PHORON, 1))))


/transformation/chem/distilling/leftforzed

CAPABILITIES(/transformation/chem/distilling/leftforzed)
	configure(transformation(name = REAGENT_LEFT4ZED, id = "distill_leftforzed",
		takes = list(reagent(REAGENT_ID_FERTILIZER, 1), reagent(REAGENT_ID_RADIUM, 2), reagent(REAGENT_ID_CALCIUM, 2)),
		makes = list(reagent(REAGENT_ID_LEFT4ZED, 1)), energy = per_step(2 * 1000),
		holds = xform_all(temperature_in(T0C + 40, T0C + 80), ambient_gas_over(GAS_PHORON, 10), ambient_gas_under(GAS_N2, 1))))


/transformation/chem/distilling/robustharvest

CAPABILITIES(/transformation/chem/distilling/robustharvest)
	configure(transformation(name = REAGENT_ROBUSTHARVEST, id = "distill_robustharvest",
		takes = list(reagent(REAGENT_ID_FERTILIZER, 1), reagent(REAGENT_ID_CARBON, 2), reagent(REAGENT_ID_BICARIDINE, 1)),
		makes = list(reagent(REAGENT_ID_ROBUSTHARVEST, 1)), energy = per_step(2 * 1000),
		holds = xform_all(temperature_in(T0C + 40, T0C + 80), ambient_gas_over(GAS_PHORON, 10), ambient_gas_under(GAS_N2, 1))))

