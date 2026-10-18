// Crystalizing (temps under 0)
/transformation/chem/distilling/sugar

CAPABILITIES(/transformation/chem/distilling/sugar)
	configure(transformation(name = "Crystalizing Sugar", id = "distill_sugar", takes = list(reagent(REAGENT_ID_CARBON, 5)),
		catalysts = list(reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_SUGAR, 1)), makes = list(reagent(REAGENT_ID_SUGAR, 0.5)),
		energy = per_step(-1 * 1000),
		holds = xform_all(temperature_in(T0C -10, T0C -5), ambient_gas_over(GAS_PHORON, 10), ambient_gas_under(GAS_O2, 1))))

// crystal growth

/transformation/chem/distilling/fuel_phoron

CAPABILITIES(/transformation/chem/distilling/fuel_phoron)
	configure(transformation(name = "Crystalizing Phoron", id = "distill_phoron_fuel",
		takes = list(reagent(REAGENT_ID_FUEL, 1), reagent(REAGENT_ID_MERCURY, 1)), catalysts = list(reagent(REAGENT_ID_PHORON, 1)),
		makes = list(reagent(REAGENT_ID_PHORON, 0.5)), energy = per_step(1 * 1000),
		holds = xform_all(temperature_in(T0C -70, T0C -25), ambient_gas_over(GAS_N2, 10), ambient_gas_under(GAS_O2, 1))))

// crystal growth
