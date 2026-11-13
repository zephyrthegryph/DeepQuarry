// Combat stimulant recipes: the reagents live in code/content/reagents/reagents/content/combat_stims/.

/transformation/chem/instant/hyperzine

CAPABILITIES(/transformation/chem/instant/hyperzine)
	configure(transformation(name = REAGENT_HYPERZINE, id = REAGENT_ID_HYPERZINE,
		takes = list(reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_PHOSPHORUS, 1), reagent(REAGENT_ID_SULFUR, 1)),
		makes = list(reagent(REAGENT_ID_HYPERZINE, 3))))

/transformation/chem/instant/claridyl

CAPABILITIES(/transformation/chem/instant/claridyl)
	configure(transformation(name = REAGENT_CLARIDYL, id = REAGENT_ID_CLARIDYL,
		takes = list(reagent(REAGENT_ID_LITHIUM, 1), reagent(REAGENT_ID_RADIUM, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_CLARIDYL, 1))))

/transformation/chem/instant/performancepeaker

CAPABILITIES(/transformation/chem/instant/performancepeaker)
	configure(transformation(name = REAGENT_PERFORMANCEPEAKER, id = REAGENT_ID_PERFORMANCEPEAKER,
		takes = list(reagent(REAGENT_ID_HYPERZINE, 1), reagent(REAGENT_ID_LIQUIDLIFE, 1), reagent(REAGENT_ID_INAPROVALINE, 1)),
		makes = list(reagent(REAGENT_ID_PERFORMANCEPEAKER, 2))))

/transformation/chem/instant/bloodsealer

CAPABILITIES(/transformation/chem/instant/bloodsealer)
	configure(transformation(name = REAGENT_BLOODSEALER, id = REAGENT_ID_BLOODSEALER,
		takes = list(reagent(REAGENT_ID_NEOLIQUIDFIRE, 1), reagent(REAGENT_ID_GLUCOSE, 1), reagent(REAGENT_ID_HYDROGEN, 1)),
		makes = list(reagent(REAGENT_ID_BLOODSEALER, 2))))
