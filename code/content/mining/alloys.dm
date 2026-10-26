// Smelting's alloys as transformations (doc/rewrite/proposals/transformations.md, wave 3). An alloy is a type under /transformation/smelting with a
// transformation(...) entry: the ores it takes from a processor's stock, and the sheets it makes. `id` is the material it makes (the wiki and the
// processor's once-per-tick guard read it). The processor walks xform_rules_in(MEDIUM_ORE_STOCK, REGIME_SMELTING) in declaration order
// (/obj/machinery/mineral/processing_unit/proc/smelt_alloys()), so an alloy whose ores contain another's comes first: durasteel and plasteel before steel.
//
// The sheets made are the old max(1, round(ores taken * product_mod)) (round() of one argument floors), written out.

/transformation/smelting

CAPABILITIES(/transformation/smelting)
	transformation(medium = MEDIUM_ORE_STOCK, regime = REGIME_SMELTING)

/transformation/smelting/durasteel
CAPABILITIES(/transformation/smelting/durasteel)
	configure(transformation(id = MAT_DURASTEEL,
		takes = list(ore_term(ORE_DIAMOND, 1), ore_term(ORE_PLATINUM, 1), ore_term(ORE_CARBON, 2), ore_term(ORE_HEMATITE, 2)),
		makes = list(stack_term(/obj/item/stack/material/durasteel, 1))))

/transformation/smelting/plasteel
CAPABILITIES(/transformation/smelting/plasteel)
	configure(transformation(id = MAT_PLASTEEL,
		takes = list(ore_term(ORE_PLATINUM, 1), ore_term(ORE_CARBON, 2), ore_term(ORE_HEMATITE, 2)),
		makes = list(stack_term(/obj/item/stack/material/plasteel, 1))))

/transformation/smelting/steel
CAPABILITIES(/transformation/smelting/steel)
	configure(transformation(id = MAT_STEEL,
		takes = list(ore_term(ORE_CARBON, 1), ore_term(ORE_HEMATITE, 1)),
		makes = list(stack_term(/obj/item/stack/material/steel, 2))))

/transformation/smelting/borosilicate
CAPABILITIES(/transformation/smelting/borosilicate)
	configure(transformation(id = MAT_PGLASS,
		takes = list(ore_term(ORE_PLATINUM, 1), ore_term(ORE_SAND, 2)),
		makes = list(stack_term(/obj/item/stack/material/glass/phoronglass, 3))))

/transformation/smelting/bronze
CAPABILITIES(/transformation/smelting/bronze)
	configure(transformation(id = MAT_BRONZE,
		takes = list(ore_term(ORE_COPPER, 2), ore_term(ORE_TIN, 1)),
		makes = list(stack_term(/obj/item/stack/material/bronze, 3))))

/transformation/smelting/plastitanium
CAPABILITIES(/transformation/smelting/plastitanium)
	configure(transformation(id = MAT_PLASTITANIUM,
		takes = list(ore_term(ORE_RUTILE, 1), ore_term(ORE_PLATINUM, 1), ore_term(ORE_CARBON, 2)),
		makes = list(stack_term(/obj/item/stack/material/plastitanium, 1))))

/transformation/smelting/tiglass
CAPABILITIES(/transformation/smelting/tiglass)
	configure(transformation(id = MAT_TITANIUMGLASS,
		takes = list(ore_term(ORE_RUTILE, 1), ore_term(ORE_SAND, 2)),
		makes = list(stack_term(/obj/item/stack/material/glass/titanium, 3))))

/transformation/smelting/plastiglass
CAPABILITIES(/transformation/smelting/plastiglass)
	configure(transformation(id = MAT_PLASTITANIUMGLASS,
		takes = list(ore_term(ORE_RUTILE, 1), ore_term(ORE_SAND, 2), ore_term(ORE_PLATINUM, 1), ore_term(ORE_CARBON, 2)),
		makes = list(stack_term(/obj/item/stack/material/glass/plastitanium, 6))))
