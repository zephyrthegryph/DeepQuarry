// Silicon: the one deliberate exception to "cores come only from feedstock" (doc/rewrite/proposals/chemistry_redesign.md section 2, the stage 4 additions).
//
// Glass and sand grind to silicon, the element, which is not a block: nothing a process does to a structure ends in it. It gets a route of its own to the silicate the burn
// medicines are made from, so the siloxane core can be built from silicate whatever the feedstock was: silicon in hot lye is silicate (and hydrogen), and an acid on silicate
// sets silanol free (the neutralise route of code/content/reagents/blocks/processes.dm, which is kelotane). The route needs the lye and the heat that sand needs.

/transformation/chem/instant/silicate_from_silicon

CAPABILITIES(/transformation/chem/instant/silicate_from_silicon)
	configure(transformation(name = "Silicate from silicon", id = "silicate_from_silicon",
		takes = list(reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_LYE, 1), reagent(REAGENT_ID_WATER, 1)),
		makes = list(reagent(REAGENT_ID_SILICATE, 1), reagent(REAGENT_ID_HYDROGEN, 1))))
