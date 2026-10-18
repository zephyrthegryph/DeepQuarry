// The curse of hot_water reagent lives on!
/transformation/chem/distilling/drinks

CAPABILITIES(/transformation/chem/distilling/drinks)
	configure(transformation(wiki = WIKI_DRINK, holds = temperature_in(T0C + 100, T0C + 500)))

// These all imply a boiled drink anyway

/transformation/chem/distilling/drinks/coffee

CAPABILITIES(/transformation/chem/distilling/drinks/coffee)
	configure(transformation(name = REAGENT_COFFEE, id = REAGENT_ID_COFFEE,
		takes = list(reagent(REAGENT_ID_WATER, 5), reagent(REAGENT_ID_COFFEEPOWDER, 1)),
		makes = list(reagent(REAGENT_ID_COFFEE, 5)), holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/tea

CAPABILITIES(/transformation/chem/distilling/drinks/tea)
	configure(transformation(name = "Black tea", id = REAGENT_ID_TEA, takes = list(reagent(REAGENT_ID_WATER, 5), reagent(REAGENT_ID_TEAPOWDER, 1)),
		makes = list(reagent(REAGENT_ID_TEA, 5)), holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/decaftea

CAPABILITIES(/transformation/chem/distilling/drinks/decaftea)
	configure(transformation(name = REAGENT_TEADECAF, id = REAGENT_ID_TEADECAF,
		takes = list(reagent(REAGENT_ID_WATER, 5), reagent(REAGENT_ID_DECAFTEAPOWDER, 1)),
		makes = list(reagent(REAGENT_ID_TEADECAF, 5)), holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/hot_coco

CAPABILITIES(/transformation/chem/distilling/drinks/hot_coco)
	configure(transformation(name = "Hot Coco", id = REAGENT_ID_HOTCOCO, takes = list(reagent(REAGENT_ID_WATER, 5), reagent(REAGENT_ID_COCO, 1)),
		makes = list(reagent(REAGENT_ID_HOTCOCO, 5)), holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/minttea

CAPABILITIES(/transformation/chem/distilling/drinks/minttea)
	configure(transformation(name = REAGENT_MINTTEA, id = REAGENT_ID_MINTTEA, takes = list(reagent(REAGENT_ID_TEA, 5), reagent(REAGENT_ID_MINT, 1)),
		makes = list(reagent(REAGENT_ID_MINTTEA, 6)), holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/minttea_decaf

CAPABILITIES(/transformation/chem/distilling/drinks/minttea_decaf)
	configure(transformation(name = REAGENT_MINTTEADECAF, id = REAGENT_ID_MINTTEADECAF,
		takes = list(reagent(REAGENT_ID_TEADECAF, 5), reagent(REAGENT_ID_MINT, 1)),
		makes = list(reagent(REAGENT_ID_MINTTEADECAF, 6)), holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/lemontea

CAPABILITIES(/transformation/chem/distilling/drinks/lemontea)
	configure(transformation(name = REAGENT_LEMONTEA, id = REAGENT_ID_LEMONTEA,
		takes = list(reagent(REAGENT_ID_TEA, 5), reagent(REAGENT_ID_LEMONJUICE, 1)), makes = list(reagent(REAGENT_ID_LEMONTEA, 6)),
		holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/lemontea_decaf

CAPABILITIES(/transformation/chem/distilling/drinks/lemontea_decaf)
	configure(transformation(name = REAGENT_LEMONTEADECAF, id = REAGENT_ID_LEMONTEADECAF,
		takes = list(reagent(REAGENT_ID_TEADECAF, 5), reagent(REAGENT_ID_LEMONJUICE, 1)),
		makes = list(reagent(REAGENT_ID_LEMONTEADECAF, 6)), holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/limetea

CAPABILITIES(/transformation/chem/distilling/drinks/limetea)
	configure(transformation(name = REAGENT_LIMETEA, id = REAGENT_ID_LIMETEA,
		takes = list(reagent(REAGENT_ID_TEA, 5), reagent(REAGENT_ID_LIMEJUICE, 1)), makes = list(reagent(REAGENT_ID_LIMETEA, 6)),
		holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/limetea_decaf

CAPABILITIES(/transformation/chem/distilling/drinks/limetea_decaf)
	configure(transformation(name = REAGENT_LIMETEADECAF, id = REAGENT_ID_LIMETEADECAF,
		takes = list(reagent(REAGENT_ID_TEADECAF, 5), reagent(REAGENT_ID_LIMEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_LIMETEADECAF, 6)), holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/orangetea

CAPABILITIES(/transformation/chem/distilling/drinks/orangetea)
	configure(transformation(name = REAGENT_ORANGETEA, id = REAGENT_ID_ORANGETEA,
		takes = list(reagent(REAGENT_ID_TEA, 5), reagent(REAGENT_ID_ORANGEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_ORANGETEA, 6)), holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/orangetea_decaf

CAPABILITIES(/transformation/chem/distilling/drinks/orangetea_decaf)
	configure(transformation(name = "Decaf Orange Tea", id = REAGENT_ID_ORANGETEADECAF,
		takes = list(reagent(REAGENT_ID_TEADECAF, 5), reagent(REAGENT_ID_ORANGEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_ORANGETEADECAF, 6)), holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/berrytea

CAPABILITIES(/transformation/chem/distilling/drinks/berrytea)
	configure(transformation(name = REAGENT_BERRYTEA, id = REAGENT_ID_BERRYTEA,
		takes = list(reagent(REAGENT_ID_TEA, 5), reagent(REAGENT_ID_BERRYJUICE, 1)), makes = list(reagent(REAGENT_ID_BERRYTEA, 6)),
		holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/berrytea_decaf

CAPABILITIES(/transformation/chem/distilling/drinks/berrytea_decaf)
	configure(transformation(name = REAGENT_BERRYTEADECAF, id = REAGENT_ID_BERRYTEADECAF,
		takes = list(reagent(REAGENT_ID_TEADECAF, 5), reagent(REAGENT_ID_BERRYJUICE, 1)),
		makes = list(reagent(REAGENT_ID_BERRYTEADECAF, 6)), holds = temperature_in(T0C + 100, T0C + 500)))

// Not drinks, but we may as well
/transformation/chem/distilling/drinks/hot_ramen

CAPABILITIES(/transformation/chem/distilling/drinks/hot_ramen)
	configure(transformation(name = REAGENT_HOTRAMEN, id = REAGENT_ID_HOTRAMEN, wiki = WIKI_FOOD,
		takes = list(reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_DRYRAMEN, 3)), makes = list(reagent(REAGENT_ID_HOTRAMEN, 3)),
		holds = temperature_in(T0C + 100, T0C + 500)))


/transformation/chem/distilling/drinks/cherrytea

CAPABILITIES(/transformation/chem/distilling/drinks/cherrytea)
	configure(transformation(name = REAGENT_CHERRYTEA, id = REAGENT_ID_CHERRYTEA,
		takes = list(reagent(REAGENT_ID_TEA, 5), reagent(REAGENT_ID_CHERRYJELLY, 1)),
		makes = list(reagent(REAGENT_ID_CHERRYTEA, 6)), holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/watermelontea

CAPABILITIES(/transformation/chem/distilling/drinks/watermelontea)
	configure(transformation(name = REAGENT_WATERMELONTEA, id = REAGENT_ID_WATERMELONTEA,
		takes = list(reagent(REAGENT_ID_TEA, 5), reagent(REAGENT_ID_WATERMELONJUICE, 1)),
		makes = list(reagent(REAGENT_ID_WATERMELONTEA, 6)), holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/matcha_latte

CAPABILITIES(/transformation/chem/distilling/drinks/matcha_latte)
	configure(transformation(name = REAGENT_MATCHALATTE, id = REAGENT_ID_MATCHALATTE,
		takes = list(reagent(REAGENT_ID_MATCHAPOWDER, 1), reagent(REAGENT_ID_MILK, 5)),
		makes = list(reagent(REAGENT_ID_MATCHALATTE, 5)), holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/greenteafresh

CAPABILITIES(/transformation/chem/distilling/drinks/greenteafresh)
	configure(transformation(id = REAGENT_ID_FRESHTEAGREEN, takes = list(reagent(REAGENT_ID_TEALEAVESGREEN, 1), reagent(REAGENT_ID_WATER, 9)),
		makes = list(reagent(REAGENT_ID_FRESHTEAGREEN, 10)), holds = temperature_in(T0C + 100, T0C + 500)))

/transformation/chem/distilling/drinks/matcha

CAPABILITIES(/transformation/chem/distilling/drinks/matcha)
	configure(transformation(id = REAGENT_ID_MATCHA, takes = list(reagent(REAGENT_ID_MATCHAPOWDER, 1), reagent(REAGENT_ID_WATER, 2)),
		makes = list(reagent(REAGENT_ID_MATCHA, 2)), holds = temperature_in(T0C + 100, T0C + 500)))
