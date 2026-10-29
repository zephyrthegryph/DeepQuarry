/transformation/chem/instant/virus_food_mutagen

CAPABILITIES(/transformation/chem/instant/virus_food_mutagen)
	configure(transformation(name = REAGENT_MUTAGENVIRUSFOOD, id = REAGENT_ID_MUTAGENVIRUSFOOD,
		takes = list(reagent(REAGENT_ID_MUTAGEN, 1), reagent(REAGENT_ID_VIRUSFOOD, 1)),
		makes = list(reagent(REAGENT_ID_MUTAGENVIRUSFOOD, 1))))

/transformation/chem/instant/virus_food_adranol

CAPABILITIES(/transformation/chem/instant/virus_food_adranol)
	configure(transformation(name = REAGENT_ADRANOLVIRUSFOOD, id = REAGENT_ID_ADRANOLVIRUSFOOD,
		takes = list(reagent(REAGENT_ID_ADRANOL, 1), reagent(REAGENT_ID_VIRUSFOOD, 1)),
		makes = list(reagent(REAGENT_ID_ADRANOLVIRUSFOOD, 1))))

/transformation/chem/instant/virus_food_phoron

CAPABILITIES(/transformation/chem/instant/virus_food_phoron)
	configure(transformation(name = REAGENT_PHORONVIRUSFOOD, id = REAGENT_ID_PHORONVIRUSFOOD,
		takes = list(reagent(REAGENT_ID_PHORON, 1), reagent(REAGENT_ID_VIRUSFOOD, 1)),
		makes = list(reagent(REAGENT_ID_PHORONVIRUSFOOD, 1))))

/transformation/chem/instant/virus_food_phoron_adranol

CAPABILITIES(/transformation/chem/instant/virus_food_phoron_adranol)
	configure(transformation(name = REAGENT_WEAKPHORONVIRUSFOOD, id = REAGENT_ID_WEAKPHORONVIRUSFOOD,
		takes = list(reagent(REAGENT_ID_ADRANOL, 1), reagent(REAGENT_ID_PHORONVIRUSFOOD, 1)),
		makes = list(reagent(REAGENT_ID_WEAKPHORONVIRUSFOOD, 2))))

/transformation/chem/instant/virus_food_mutagen_sugar

CAPABILITIES(/transformation/chem/instant/virus_food_mutagen_sugar)
	configure(transformation(name = REAGENT_SUGARVIRUSFOOD, id = REAGENT_ID_SUGARVIRUSFOOD,
		takes = list(reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_MUTAGENVIRUSFOOD, 1)),
		makes = list(reagent(REAGENT_ID_SUGARVIRUSFOOD, 2))))

/transformation/chem/instant/virus_food_mutagen_inaprovaline

CAPABILITIES(/transformation/chem/instant/virus_food_mutagen_inaprovaline)
	configure(transformation(name = REAGENT_SUGARVIRUSFOOD, id = "inaprovalinevirusfood",
		takes = list(reagent(REAGENT_ID_INAPROVALINE, 1), reagent(REAGENT_ID_MUTAGENVIRUSFOOD, 1)),
		makes = list(reagent(REAGENT_ID_SUGARVIRUSFOOD, 2))))

/transformation/chem/instant/virus_food_uranium

CAPABILITIES(/transformation/chem/instant/virus_food_uranium)
	configure(transformation(name = REAGENT_URANIUMVIRUSFOOD, id = REAGENT_ID_URANIUMVIRUSFOOD,
		takes = list(reagent(REAGENT_ID_URANIUM, 1), reagent(REAGENT_ID_VIRUSFOOD, 1)),
		makes = list(reagent(REAGENT_ID_URANIUMVIRUSFOOD, 1))))

/transformation/chem/instant/virus_food_uranium_unstable

CAPABILITIES(/transformation/chem/instant/virus_food_uranium_unstable)
	configure(transformation(name = REAGENT_UNSTABLEURANIUMVIRUSFOOD, id = REAGENT_ID_UNSTABLEURANIUMVIRUSFOOD,
		takes = list(reagent(REAGENT_ID_URANIUM, 1), reagent(REAGENT_ID_PHORONVIRUSFOOD, 1)),
		makes = list(reagent(REAGENT_ID_UNSTABLEURANIUMVIRUSFOOD, 1))))

/transformation/chem/instant/virus_food_uranium_stable

CAPABILITIES(/transformation/chem/instant/virus_food_uranium_stable)
	configure(transformation(name = REAGENT_STABLEURANIUMVIRUSFOOD, id = REAGENT_ID_STABLEURANIUMVIRUSFOOD,
		takes = list(reagent(REAGENT_ID_PHORON, 5), reagent(REAGENT_ID_URANIUM, 5), reagent(REAGENT_ID_SILVER, 5)),
		makes = list(reagent(REAGENT_ID_STABLEURANIUMVIRUSFOOD, 1))))

/transformation/chem/instant/virus_food_uranium_stable_alt

CAPABILITIES(/transformation/chem/instant/virus_food_uranium_stable_alt)
	configure(transformation(name = REAGENT_STABLEURANIUMVIRUSFOOD_ALT, id = REAGENT_ID_STABLEURANIUMVIRUSFOOD_ALT,
		takes = list(reagent(REAGENT_ID_PHORON, 5), reagent(REAGENT_ID_URANIUM, 5), reagent(REAGENT_ID_GOLD, 5)),
		makes = list(reagent(REAGENT_ID_STABLEURANIUMVIRUSFOOD, 1))))

/transformation/chem/instant/virus_food_size

CAPABILITIES(/transformation/chem/instant/virus_food_size)
	configure(transformation(name = REAGENT_SIZEVIRUSFOOD, id = REAGENT_ID_SIZEVIRUSFOOD,
		takes = list(reagent(REAGENT_ID_SIZEOXADONE, 1), reagent(REAGENT_ID_PHORONVIRUSFOOD, 1)),
		makes = list(reagent(REAGENT_ID_SIZEVIRUSFOOD, 2))))

/transformation/chem/instant/mix_virus

CAPABILITIES(/transformation/chem/instant/mix_virus)
	configure(transformation(name = "Mix Virus", id = "mixvirus", takes = list(reagent(REAGENT_ID_VIRUSFOOD, 1)),
		catalysts = list(reagent(REAGENT_ID_BLOOD, 1)), effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_EVOLVE, levels = list(0, 2))))

/transformation/chem/instant/mix_virus/picky

CAPABILITIES(/transformation/chem/instant/mix_virus/picky)
	configure(transformation(id = "mixviruspicky", effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_PICKY)))

/transformation/chem/instant/mix_virus/mix_virus_2

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_2)
	configure(transformation(name = "Mix Virus 2", id = "mixvirus2", takes = list(reagent(REAGENT_ID_MUTAGEN, 1)), effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_EVOLVE, levels = list(2, 4))))

/transformation/chem/instant/mix_virus/mix_virus_3

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_3)
	configure(transformation(name = "Mix Virus 3", id = "mixvirus3", takes = list(reagent(REAGENT_ID_VIRUSFOOD, 1), reagent(REAGENT_ID_PHORON, 1)), effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_EVOLVE, levels = list(4, 6))))

/transformation/chem/instant/mix_virus/mix_virus_4

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_4)
	configure(transformation(name = "Mix Virus 4", id = "mixvirus4", takes = list(reagent(REAGENT_ID_URANIUM, 1)), effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_EVOLVE, levels = list(5, 6))))

/transformation/chem/instant/mix_virus/mix_virus_5

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_5)
	configure(transformation(name = "Mix Virus 5", id = "mixvirus5", takes = list(reagent(REAGENT_ID_MUTAGENVIRUSFOOD, 1)), effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_EVOLVE, levels = list(3, 3))))

/transformation/chem/instant/mix_virus/mix_virus_6

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_6)
	configure(transformation(name = "Mix Virus 6", id = "mixvirus6", takes = list(reagent(REAGENT_ID_SUGARVIRUSFOOD, 1)), effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_EVOLVE, levels = list(4, 4))))

/transformation/chem/instant/mix_virus/mix_virus_7

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_7)
	configure(transformation(name = "Mix Virus 7", id = "mixvirus7", takes = list(reagent(REAGENT_ID_WEAKPHORONVIRUSFOOD, 1)), effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_EVOLVE, levels = list(5, 5))))

/transformation/chem/instant/mix_virus/mix_virus_8

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_8)
	configure(transformation(name = "Mix Virus 8", id = "mixvirus8", takes = list(reagent(REAGENT_ID_PHORONVIRUSFOOD, 1)), effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_EVOLVE, levels = list(6, 6))))

/transformation/chem/instant/mix_virus/mix_virus_9

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_9)
	configure(transformation(name = "Mix Virus 9", id = "mixvirus9", takes = list(reagent(REAGENT_ID_ADRANOLVIRUSFOOD, 1)), effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_EVOLVE, levels = list(1, 1))))

/transformation/chem/instant/mix_virus/mix_virus_10

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_10)
	configure(transformation(name = "Mix Virus 10", id = "mixvirus10", takes = list(reagent(REAGENT_ID_URANIUMVIRUSFOOD, 1)), effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_EVOLVE, levels = list(6, 7))))

/transformation/chem/instant/mix_virus/mix_virus_11

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_11)
	configure(transformation(name = "Mix Virus 11", id = "mixvirus11", takes = list(reagent(REAGENT_ID_UNSTABLEURANIUMVIRUSFOOD, 1)), effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_EVOLVE, levels = list(7, 7))))

/transformation/chem/instant/mix_virus/mix_virus_12

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_12)
	configure(transformation(name = "Mix Virus 12", id = "mixvirus12", takes = list(reagent(REAGENT_ID_STABLEURANIUMVIRUSFOOD, 1)), effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_EVOLVE, levels = list(8, 8))))

/transformation/chem/instant/mix_virus/picky/size

CAPABILITIES(/transformation/chem/instant/mix_virus/picky/size)
	configure(transformation(name = "Mix Virus Size", id = "mixvirussize", takes = list(reagent(REAGENT_ID_SIZEVIRUSFOOD, 1)),
		effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_PICKY, symptoms = list(/datum/viral_trait/size, /datum/viral_trait/size/grow, /datum/viral_trait/size/shrink))))

/transformation/chem/instant/mix_virus/rem_virus

CAPABILITIES(/transformation/chem/instant/mix_virus/rem_virus)
	configure(transformation(name = "Devolve Virus", id = "remvirus", takes = list(reagent(REAGENT_ID_ADRANOL, 1)),
		catalysts = list(reagent(REAGENT_ID_BLOOD, 1)),
		effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_DEVOLVE)))

/transformation/chem/instant/antibodies

CAPABILITIES(/transformation/chem/instant/antibodies)
	configure(transformation(name = REAGENT_ANTIBODIES, id = "antibodiesmix", takes = list(reagent(REAGENT_ID_VACCINE, 1)),
		catalysts = list(reagent(REAGENT_ID_INAPROVALINE, 0.1)), makes = list(reagent(REAGENT_ID_ANTIBODIES, 0.5))))

/transformation/chem/instant/neuter_virus

CAPABILITIES(/transformation/chem/instant/neuter_virus)
	configure(transformation(name = "Neuter Virus", id = "neutervirus", takes = list(reagent(REAGENT_ID_IMMUNOSUPRIZINE, 1)),
		catalysts = list(reagent(REAGENT_ID_BLOOD, 1)),
		effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_NEUTER)))

/transformation/chem/instant/falter_virus

CAPABILITIES(/transformation/chem/instant/falter_virus)
	configure(transformation(name = "Falter Virus", id = "faltervirus", takes = list(reagent(REAGENT_ID_SPACEACILLIN, 1)),
		catalysts = list(reagent(REAGENT_ID_BLOOD, 1)),
		effects = sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_FALTER)))
