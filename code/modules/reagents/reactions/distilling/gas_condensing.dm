// Condensing atmo gasses into reagents
// If there is ever work done converting atmogas back and forth from reagent to gas then this should be tuned to avoid creating something from nothing!
// The condensing constants are in code/__defines/transformations.dm: the generated declarations are read before this file.

/transformation/chem/distilling/condense_oxygen

CAPABILITIES(/transformation/chem/distilling/condense_oxygen)
	configure(transformation(name = "Condensing Oxygen", id = "condense_oxygen", takes = list(reagent(REAGENT_ID_COOLANT, COOLANT_CONSUMPTION_RATE)),
		blocked_by = list(reagent(REAGENT_ID_OXYGEN, 0.1)), makes = list(reagent(REAGENT_ID_OXYGEN, CONDENSING_RESULT)),
		energy = per_step(CONDENSING_HEAT * 1000), takes_ambient = list(gas(GAS_O2, CONDENSING_RATE)),
		holds = xform_all(temperature_in(54.36, 90.19), ambient_gas_over(GAS_O2, 10), ambient_gas_under(GAS_PHORON, 1))))

// kelvin

/transformation/chem/distilling/condense_nitrogen

CAPABILITIES(/transformation/chem/distilling/condense_nitrogen)
	configure(transformation(name = "Condensing Nitrogen", id = "condense_nitrogen",
		takes = list(reagent(REAGENT_ID_COOLANT, COOLANT_CONSUMPTION_RATE)), blocked_by = list(reagent(REAGENT_ID_NITROGEN, 0.1)),
		makes = list(reagent(REAGENT_ID_NITROGEN, CONDENSING_RESULT)), energy = per_step(CONDENSING_HEAT * 1000),
		takes_ambient = list(gas(GAS_N2, CONDENSING_RATE)),
		holds = xform_all(temperature_in(63.15, 77.36), ambient_gas_over(GAS_N2, 10), ambient_gas_under(GAS_PHORON, 1))))

// kelvin

/transformation/chem/distilling/condense_nitrox

CAPABILITIES(/transformation/chem/distilling/condense_nitrox)
	configure(transformation(name = "Condensing Nitrous Oxide", id = "condense_nitro",
		takes = list(reagent(REAGENT_ID_COOLANT, COOLANT_CONSUMPTION_RATE)), blocked_by = list(reagent(REAGENT_ID_NITROGEN, 0.1)),
		makes = list(reagent(REAGENT_ID_NITROGEN, CONDENSING_RESULT)), energy = per_step(CONDENSING_HEAT * 1000),
		takes_ambient = list(gas(GAS_N2O, CONDENSING_RATE)),
		holds = xform_all(temperature_in(0, 182.3), ambient_gas_over(GAS_N2O, 10), ambient_gas_under(GAS_PHORON, 1))))

// kelvin

/transformation/chem/distilling/condense_carbon

CAPABILITIES(/transformation/chem/distilling/condense_carbon)
	configure(transformation(name = "Condensing Carbon Dioxide", id = "condense_carbon",
		takes = list(reagent(REAGENT_ID_COOLANT, COOLANT_CONSUMPTION_RATE)), blocked_by = list(reagent(REAGENT_ID_CARBON, 0.1)),
		makes = list(reagent(REAGENT_ID_CARBON, CONDENSING_RESULT)), energy = per_step(CONDENSING_HEAT * 1000),
		takes_ambient = list(gas(GAS_CO2, CONDENSING_RATE)),
		holds = xform_all(temperature_in(54.36, 90.19), ambient_gas_over(GAS_CO2, 10), ambient_gas_under(GAS_PHORON, 1))))

// kelvin

/transformation/chem/distilling/condense_phoron

CAPABILITIES(/transformation/chem/distilling/condense_phoron)
	configure(transformation(name = "Condensing Phoron", id = "condense_phoron", takes = list(reagent(REAGENT_ID_COOLANT, COOLANT_CONSUMPTION_RATE)),
		blocked_by = list(reagent(REAGENT_ID_PHORON, 0.1)), makes = list(reagent(REAGENT_ID_PHORON, CONDENSING_RESULT)),
		energy = per_step(CONDENSING_HEAT * 1000), takes_ambient = list(gas(GAS_PHORON, CONDENSING_RATE)),
		holds = xform_all(temperature_in(14.60, 52.99), ambient_gas_over(GAS_PHORON, 10), ambient_gas_under(GAS_O2, 1))))

// kelvin

/transformation/chem/distilling/condense_fuel

CAPABILITIES(/transformation/chem/distilling/condense_fuel)
	configure(transformation(name = "Condensing Volatiles", id = "condense_fuel", takes = list(reagent(REAGENT_ID_COOLANT, COOLANT_CONSUMPTION_RATE)),
		blocked_by = list(reagent(REAGENT_ID_FUEL, 0.1)), makes = list(reagent(REAGENT_ID_FUEL, CONDENSING_RESULT)),
		energy = per_step(CONDENSING_HEAT * 1000), takes_ambient = list(gas(GAS_VOLATILE_FUEL, CONDENSING_RATE)),
		holds = xform_all(temperature_in(91.60, 120.19), ambient_gas_over(GAS_VOLATILE_FUEL, 10), ambient_gas_under(GAS_O2, 1))))

// kelvin

/transformation/chem/distilling/condense_methane

CAPABILITIES(/transformation/chem/distilling/condense_methane)
	configure(transformation(name = "Condensing Methane", id = "condense_methane", takes = list(reagent(REAGENT_ID_COOLANT, COOLANT_CONSUMPTION_RATE)),
		blocked_by = list(reagent(REAGENT_ID_TOXIN, 0.1)), makes = list(reagent(REAGENT_ID_TOXIN, CONDENSING_RESULT)),
		energy = per_step(CONDENSING_HEAT * 1000), takes_ambient = list(gas(GAS_CH4, CONDENSING_RATE)),
		holds = xform_all(temperature_in(90.7, 111.65), ambient_gas_over(GAS_CH4, 10), ambient_gas_under(GAS_O2, 1))))

// kelvin

