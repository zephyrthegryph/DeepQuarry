// Hydroponics refinery fun

/transformation/chem/distilling/eznutrient

CAPABILITIES(/transformation/chem/distilling/eznutrient)
	configure(transformation(name = REAGENT_EZNUTRIENT, id = "distill_eznutriment",
		takes = list(reagent(REAGENT_ID_FERTILIZER, 1), reagent(REAGENT_ID_CALCIUM, 1), reagent(REAGENT_ID_CARBON, 2)),
		makes = list(reagent(REAGENT_ID_EZNUTRIENT, 1)),
		holds = xform_all(temperature_in(T0C + 10, T0C + 50), ambient_gas_over(GAS_O2, 10), ambient_gas_under(GAS_PHORON, 1))))



