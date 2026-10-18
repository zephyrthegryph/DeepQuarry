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
	var/level_min = 0
	var/level_max = 2

CAPABILITIES(/transformation/chem/instant/mix_virus)
	configure(transformation(name = "Mix Virus", id = "mixvirus", takes = list(reagent(REAGENT_ID_VIRUSFOOD, 1)),
		catalysts = list(reagent(REAGENT_ID_BLOOD, 1)), then = TYPE_PROC_REF(/transformation/chem/instant/mix_virus, on_reaction)))

/transformation/chem/instant/mix_virus/picky
	var/list/symptoms

CAPABILITIES(/transformation/chem/instant/mix_virus/picky)
	/// /datum/viral_trait type paths the evolution may pick from.
	configure(transformation(id = "mixviruspicky", then = TYPE_PROC_REF(/transformation/chem/instant/mix_virus/picky, on_reaction)))

/transformation/chem/instant/mix_virus/proc/on_reaction(datum/reagents/holder)
	var/datum/reagent/blood/B = locate_in_list(holder.reagent_list, /datum/reagent/blood)
	if(B && B.data)
		var/datum/affliction/contagion/engineered/D = locate_in_list(B.data["viruses"], /datum/affliction/contagion/engineered)
		if(D)
			D.Evolve(level_min, level_max)

/transformation/chem/instant/mix_virus/picky/proc/on_reaction(datum/reagents/holder)
	var/datum/reagent/blood/B = locate_in_list(holder.reagent_list, /datum/reagent/blood)
	if(B && B.data)
		var/datum/affliction/contagion/engineered/D = locate_in_list(B.data["viruses"], /datum/affliction/contagion/engineered)
		if(D)
			D.PickyEvolve(symptoms)

/transformation/chem/instant/mix_virus/mix_virus_2
	level_min = 2
	level_max = 4

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_2)
	configure(transformation(name = "Mix Virus 2", id = "mixvirus2", takes = list(reagent(REAGENT_ID_MUTAGEN, 1))))

/transformation/chem/instant/mix_virus/mix_virus_3
	level_min = 4
	level_max = 6

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_3)
	configure(transformation(name = "Mix Virus 3", id = "mixvirus3", takes = list(reagent(REAGENT_ID_VIRUSFOOD, 1), reagent(REAGENT_ID_PHORON, 1))))

/transformation/chem/instant/mix_virus/mix_virus_4
	level_min = 5
	level_max = 6

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_4)
	configure(transformation(name = "Mix Virus 4", id = "mixvirus4", takes = list(reagent(REAGENT_ID_URANIUM, 1))))

/transformation/chem/instant/mix_virus/mix_virus_5
	level_min = 3
	level_max = 3

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_5)
	configure(transformation(name = "Mix Virus 5", id = "mixvirus5", takes = list(reagent(REAGENT_ID_MUTAGENVIRUSFOOD, 1))))

/transformation/chem/instant/mix_virus/mix_virus_6
	level_min = 4
	level_max = 4

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_6)
	configure(transformation(name = "Mix Virus 6", id = "mixvirus6", takes = list(reagent(REAGENT_ID_SUGARVIRUSFOOD, 1))))

/transformation/chem/instant/mix_virus/mix_virus_7
	level_min = 5
	level_max = 5

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_7)
	configure(transformation(name = "Mix Virus 7", id = "mixvirus7", takes = list(reagent(REAGENT_ID_WEAKPHORONVIRUSFOOD, 1))))

/transformation/chem/instant/mix_virus/mix_virus_8
	level_min = 6
	level_max = 6

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_8)
	configure(transformation(name = "Mix Virus 8", id = "mixvirus8", takes = list(reagent(REAGENT_ID_PHORONVIRUSFOOD, 1))))

/transformation/chem/instant/mix_virus/mix_virus_9
	level_min = 1
	level_max = 1

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_9)
	configure(transformation(name = "Mix Virus 9", id = "mixvirus9", takes = list(reagent(REAGENT_ID_ADRANOLVIRUSFOOD, 1))))

/transformation/chem/instant/mix_virus/mix_virus_10
	level_min = 6
	level_max = 7

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_10)
	configure(transformation(name = "Mix Virus 10", id = "mixvirus10", takes = list(reagent(REAGENT_ID_URANIUMVIRUSFOOD, 1))))

/transformation/chem/instant/mix_virus/mix_virus_11
	level_min = 7
	level_max = 7

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_11)
	configure(transformation(name = "Mix Virus 11", id = "mixvirus11", takes = list(reagent(REAGENT_ID_UNSTABLEURANIUMVIRUSFOOD, 1))))

/transformation/chem/instant/mix_virus/mix_virus_12
	level_min = 8
	level_max = 8

CAPABILITIES(/transformation/chem/instant/mix_virus/mix_virus_12)
	configure(transformation(name = "Mix Virus 12", id = "mixvirus12", takes = list(reagent(REAGENT_ID_STABLEURANIUMVIRUSFOOD, 1))))

/transformation/chem/instant/mix_virus/picky/size
	symptoms = list(
		/datum/viral_trait/size,
		/datum/viral_trait/size/grow,
		/datum/viral_trait/size/shrink
	)

CAPABILITIES(/transformation/chem/instant/mix_virus/picky/size)
	configure(transformation(name = "Mix Virus Size", id = "mixvirussize", takes = list(reagent(REAGENT_ID_SIZEVIRUSFOOD, 1))))

/transformation/chem/instant/mix_virus/rem_virus

CAPABILITIES(/transformation/chem/instant/mix_virus/rem_virus)
	configure(transformation(name = "Devolve Virus", id = "remvirus", takes = list(reagent(REAGENT_ID_ADRANOL, 1)),
		catalysts = list(reagent(REAGENT_ID_BLOOD, 1)),
		then = TYPE_PROC_REF(/transformation/chem/instant/mix_virus/rem_virus, on_reaction)))

/transformation/chem/instant/mix_virus/rem_virus/proc/on_reaction(datum/reagents/holder)
	var/datum/reagent/blood/B = locate_in_list(holder.reagent_list, /datum/reagent/blood)
	if(B && B.data)
		var/datum/affliction/contagion/engineered/D = locate_in_list(B.data["viruses"], /datum/affliction/contagion/engineered)
		if(D)
			D.Devolve()

/transformation/chem/instant/antibodies

CAPABILITIES(/transformation/chem/instant/antibodies)
	configure(transformation(name = REAGENT_ANTIBODIES, id = "antibodiesmix", takes = list(reagent(REAGENT_ID_VACCINE, 1)),
		catalysts = list(reagent(REAGENT_ID_INAPROVALINE, 0.1)), makes = list(reagent(REAGENT_ID_ANTIBODIES, 0.5))))

/transformation/chem/instant/neuter_virus

CAPABILITIES(/transformation/chem/instant/neuter_virus)
	configure(transformation(name = "Neuter Virus", id = "neutervirus", takes = list(reagent(REAGENT_ID_IMMUNOSUPRIZINE, 1)),
		catalysts = list(reagent(REAGENT_ID_BLOOD, 1)),
		then = TYPE_PROC_REF(/transformation/chem/instant/neuter_virus, on_reaction)))

/transformation/chem/instant/neuter_virus/proc/on_reaction(datum/reagents/holder)
	var/datum/reagent/blood/B = locate_in_list(holder.reagent_list, /datum/reagent/blood)
	if(B && B.data)
		var/datum/affliction/contagion/engineered/D = locate_in_list(B.data["viruses"], /datum/affliction/contagion/engineered)
		if(D)
			D.Neuter()

/transformation/chem/instant/falter_virus

CAPABILITIES(/transformation/chem/instant/falter_virus)
	configure(transformation(name = "Falter Virus", id = "faltervirus", takes = list(reagent(REAGENT_ID_SPACEACILLIN, 1)),
		catalysts = list(reagent(REAGENT_ID_BLOOD, 1)),
		then = TYPE_PROC_REF(/transformation/chem/instant/falter_virus, on_reaction)))

/transformation/chem/instant/falter_virus/proc/on_reaction(datum/reagents/holder)
	var/datum/reagent/blood/B = locate_in_list(holder.reagent_list, /datum/reagent/blood)
	if(B && B.data)
		var/datum/affliction/contagion/engineered/D = locate_in_list(B.data["viruses"], /datum/affliction/contagion/engineered)
		if(D)
			D.Falter()
