// Neutralisation: the way to be rid of an acid or base residue (code/content/reagents/reagents/content/contaminants.dm) that a filter will not take is to
// neutralise it. Acid residue and a base reagent make salts and water; base residue and an acid reagent make salts and water. The salts are a contaminant too
// (a much milder one), and the base or acid spent is the chemist's to measure: too little leaves residue, too much leaves the base or acid itself in the mixture.
// A rule makes its first reagent as the product and the rest as by-products (code/library/transformations/transformation_entry.dm, `makes`).

/// Acid residue and a base.
/transformation/chem/instant/neutralise_acid

CAPABILITIES(/transformation/chem/instant/neutralise_acid)
	configure(transformation(says = "The mixture fizzes and settles."))

/transformation/chem/instant/neutralise_acid/lye

CAPABILITIES(/transformation/chem/instant/neutralise_acid/lye)
	configure(transformation(name = "Neutralised acid (lye)", id = "neutralise_acid_lye",
		takes = list(reagent(REAGENT_ID_CONTAMINANT_ACID_RESIDUE, 1), reagent(REAGENT_ID_LYE, 1)),
		makes = list(reagent(REAGENT_ID_CONTAMINANT_SALTS, 1), reagent(REAGENT_ID_WATER, 1))))

/transformation/chem/instant/neutralise_acid/ammonia

CAPABILITIES(/transformation/chem/instant/neutralise_acid/ammonia)
	configure(transformation(name = "Neutralised acid (ammonia)", id = "neutralise_acid_ammonia",
		takes = list(reagent(REAGENT_ID_CONTAMINANT_ACID_RESIDUE, 1), reagent(REAGENT_ID_AMMONIA, 1)),
		makes = list(reagent(REAGENT_ID_CONTAMINANT_SALTS, 1), reagent(REAGENT_ID_WATER, 1))))

/transformation/chem/instant/neutralise_acid/diethylamine

CAPABILITIES(/transformation/chem/instant/neutralise_acid/diethylamine)
	configure(transformation(name = "Neutralised acid (diethylamine)", id = "neutralise_acid_diethylamine",
		takes = list(reagent(REAGENT_ID_CONTAMINANT_ACID_RESIDUE, 1), reagent(REAGENT_ID_DIETHYLAMINE, 1)),
		makes = list(reagent(REAGENT_ID_CONTAMINANT_SALTS, 1), reagent(REAGENT_ID_WATER, 1))))

/// Base residue and an acid.
/transformation/chem/instant/neutralise_base

CAPABILITIES(/transformation/chem/instant/neutralise_base)
	configure(transformation(says = "The mixture fizzes and settles."))

/transformation/chem/instant/neutralise_base/sulphuric

CAPABILITIES(/transformation/chem/instant/neutralise_base/sulphuric)
	configure(transformation(name = "Neutralised base (sulphuric acid)", id = "neutralise_base_sacid",
		takes = list(reagent(REAGENT_ID_CONTAMINANT_BASE_RESIDUE, 1), reagent(REAGENT_ID_SACID, 1)),
		makes = list(reagent(REAGENT_ID_CONTAMINANT_SALTS, 1), reagent(REAGENT_ID_WATER, 1))))

/transformation/chem/instant/neutralise_base/polytrinic

CAPABILITIES(/transformation/chem/instant/neutralise_base/polytrinic)
	configure(transformation(name = "Neutralised base (polytrinic acid)", id = "neutralise_base_pacid",
		takes = list(reagent(REAGENT_ID_CONTAMINANT_BASE_RESIDUE, 1), reagent(REAGENT_ID_PACID, 1)),
		makes = list(reagent(REAGENT_ID_CONTAMINANT_SALTS, 1), reagent(REAGENT_ID_WATER, 1))))
