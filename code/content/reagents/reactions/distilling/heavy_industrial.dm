// Heavy chemicals
/transformation/chem/distilling/titanium_refine

CAPABILITIES(/transformation/chem/distilling/titanium_refine)
	configure(transformation(name = REAGENT_TITANIUM, id = "distill_titanium",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_CHLORINE, 4), reagent(REAGENT_ID_SODIUM, 1)),
		makes = list(reagent(REAGENT_ID_TITANIUM, 1)), energy = per_step(-1 * 1000),
		holds = xform_all(temperature_in(T20C + 900, T20C + 1100), ambient_gas_over(GAS_N2, 10), ambient_gas_under(GAS_O2, 1))))


/transformation/chem/distilling/concentrate_radium

CAPABILITIES(/transformation/chem/distilling/concentrate_radium)
	configure(transformation(name = REAGENT_CONCENTRATEDRADIUM, id = "distill_conrad",
		takes = list(reagent(REAGENT_ID_RADIUM, 5), reagent(REAGENT_ID_LEAD, 1)), catalysts = list(reagent(REAGENT_ID_URANIUM, 1)),
		makes = list(reagent(REAGENT_ID_CONCENTRATEDRADIUM, 1)), energy = per_step(-1 * 1000),
		holds = xform_all(temperature_in(T20C + 1500, T20C + 2000), ambient_gas_over(GAS_PHORON, 10), ambient_gas_under(GAS_N2, 1))))


/transformation/chem/distilling/cyanide

CAPABILITIES(/transformation/chem/distilling/cyanide)
	configure(transformation(name = REAGENT_CYANIDE, id = "distill_cyanide",
		takes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_WATER, 2)),
		makes = list(reagent(REAGENT_ID_CYANIDE, 1)),
		holds = xform_all(temperature_in(T0C + 150, T0C + 170), ambient_gas_over(GAS_N2, 10), ambient_gas_under(GAS_O2, 1))))


/transformation/chem/distilling/sacid

CAPABILITIES(/transformation/chem/distilling/sacid)
	configure(transformation(name = REAGENT_SACID, id = "distill_sacid", takes = list(reagent(REAGENT_ID_HYDROGEN, 2), reagent(REAGENT_ID_SULFUR, 1)),
		makes = list(reagent(REAGENT_ID_SACID, 1)), energy = per_step(5 * 1000),
		holds = xform_all(temperature_in(T0C + 200, T0C + 300), ambient_gas_over(GAS_O2, 10), ambient_gas_under(GAS_N2, 1))))


/transformation/chem/distilling/toxin

CAPABILITIES(/transformation/chem/distilling/toxin)
	configure(transformation(name = REAGENT_TOXIN, id = "distill_rawtoxin", takes = list(reagent(REAGENT_ID_SACID, 2), reagent(REAGENT_ID_CYANIDE, 1)),
		makes = list(reagent(REAGENT_ID_TOXIN, 1)), energy = per_step(2 * 1000),
		holds = xform_all(temperature_in(T0C + 120, T0C + 580), ambient_gas_over(GAS_PHORON, 10), ambient_gas_under(GAS_N2, 1))))



// Marker ink for paint production
/transformation/chem/distilling/marker_ink_black

CAPABILITIES(/transformation/chem/distilling/marker_ink_black)
	configure(transformation(name = REAGENT_MARKERINKBLACK, id = "distill_marker_black",
		takes = list(reagent(REAGENT_ID_LUBE, 1), reagent(REAGENT_ID_ETHANOL, 1), reagent(REAGENT_ID_CARBON, 1)),
		makes = list(reagent(REAGENT_ID_MARKERINKBLACK, 1)), energy = per_step(-1 * 1000),
		holds = xform_all(temperature_in(T20C + 90, T20C + 160), ambient_gas_over(GAS_O2, 10), ambient_gas_under(GAS_PHORON, 1))))


/transformation/chem/distilling/marker_ink_red

CAPABILITIES(/transformation/chem/distilling/marker_ink_red)
	configure(transformation(name = REAGENT_MARKERINKRED, id = "distill_marker_red",
		takes = list(reagent(REAGENT_ID_LUBE, 1), reagent(REAGENT_ID_ETHANOL, 1), reagent(REAGENT_ID_IRON, 1)),
		makes = list(reagent(REAGENT_ID_MARKERINKRED, 1)), energy = per_step(-1 * 1000),
		holds = xform_all(temperature_in(T20C + 90, T20C + 160), ambient_gas_over(GAS_O2, 10), ambient_gas_under(GAS_PHORON, 1))))


/transformation/chem/distilling/marker_ink_yellow

CAPABILITIES(/transformation/chem/distilling/marker_ink_yellow)
	configure(transformation(name = REAGENT_MARKERINKYELLOW, id = "distill_marker_yellow",
		takes = list(reagent(REAGENT_ID_LUBE, 1), reagent(REAGENT_ID_ETHANOL, 1), reagent(REAGENT_ID_SULFUR, 1)),
		makes = list(reagent(REAGENT_ID_MARKERINKYELLOW, 1)), energy = per_step(-1 * 1000),
		holds = xform_all(temperature_in(T20C + 90, T20C + 160), ambient_gas_over(GAS_O2, 10), ambient_gas_under(GAS_PHORON, 1))))


/transformation/chem/distilling/marker_ink_green

CAPABILITIES(/transformation/chem/distilling/marker_ink_green)
	configure(transformation(name = REAGENT_MARKERINKGREEN, id = "distill_marker_green",
		takes = list(reagent(REAGENT_ID_LUBE, 1), reagent(REAGENT_ID_ETHANOL, 1), reagent(REAGENT_ID_COPPER, 1)),
		makes = list(reagent(REAGENT_ID_MARKERINKGREEN, 1)), energy = per_step(-1 * 1000),
		holds = xform_all(temperature_in(T20C + 90, T20C + 160), ambient_gas_over(GAS_O2, 10), ambient_gas_under(GAS_PHORON, 1))))


/transformation/chem/distilling/marker_ink_blue

CAPABILITIES(/transformation/chem/distilling/marker_ink_blue)
	configure(transformation(name = REAGENT_MARKERINKBLUE, id = "distill_marker_blue",
		takes = list(reagent(REAGENT_ID_LUBE, 1), reagent(REAGENT_ID_ETHANOL, 1), reagent(REAGENT_ID_PRUSSIANBLUE, 1)),
		makes = list(reagent(REAGENT_ID_MARKERINKBLUE, 1)), energy = per_step(-1 * 1000),
		holds = xform_all(temperature_in(T20C + 90, T20C + 160), ambient_gas_over(GAS_O2, 10), ambient_gas_under(GAS_PHORON, 1))))


/transformation/chem/distilling/marker_ink_grey

CAPABILITIES(/transformation/chem/distilling/marker_ink_grey)
	configure(transformation(name = REAGENT_MARKERINKGREY, id = "distill_marker_grey",
		takes = list(reagent(REAGENT_ID_LUBE, 1), reagent(REAGENT_ID_ETHANOL, 1), reagent(REAGENT_ID_TIN, 1)),
		makes = list(reagent(REAGENT_ID_MARKERINKGREY, 1)), energy = per_step(-1 * 1000),
		holds = xform_all(temperature_in(T20C + 90, T20C + 160), ambient_gas_over(GAS_O2, 10), ambient_gas_under(GAS_PHORON, 1))))



// Secondary distillation for markers
/transformation/chem/distilling/marker_ink_orange

CAPABILITIES(/transformation/chem/distilling/marker_ink_orange)
	configure(transformation(name = REAGENT_MARKERINKORANGE, id = "distill_marker_orange",
		takes = list(reagent(REAGENT_ID_MARKERINKRED, 1), reagent(REAGENT_ID_MARKERINKYELLOW, 1)),
		makes = list(reagent(REAGENT_ID_MARKERINKORANGE, 1)), energy = per_step(-1 * 1000),
		holds = xform_all(temperature_in(T20C + 90, T20C + 160), ambient_gas_over(GAS_O2, 10), ambient_gas_under(GAS_PHORON, 1))))


/transformation/chem/distilling/marker_ink_purple

CAPABILITIES(/transformation/chem/distilling/marker_ink_purple)
	configure(transformation(name = REAGENT_MARKERINKPURPLE, id = "distill_marker_purple",
		takes = list(reagent(REAGENT_ID_MARKERINKRED, 1), reagent(REAGENT_ID_MARKERINKBLUE, 1)),
		makes = list(reagent(REAGENT_ID_MARKERINKPURPLE, 1)), energy = per_step(-1 * 1000),
		holds = xform_all(temperature_in(T20C + 90, T20C + 160), ambient_gas_over(GAS_O2, 10), ambient_gas_under(GAS_PHORON, 1))))


/transformation/chem/distilling/marker_ink_brown

CAPABILITIES(/transformation/chem/distilling/marker_ink_brown)
	configure(transformation(name = REAGENT_MARKERINKBROWN, id = "distill_marker_brown",
		takes = list(reagent(REAGENT_ID_MARKERINKRED, 1), reagent(REAGENT_ID_MARKERINKGREY, 1)),
		makes = list(reagent(REAGENT_ID_MARKERINKBROWN, 1)), energy = per_step(-1 * 1000),
		holds = xform_all(temperature_in(T20C + 90, T20C + 160), ambient_gas_over(GAS_O2, 10), ambient_gas_under(GAS_PHORON, 1))))

