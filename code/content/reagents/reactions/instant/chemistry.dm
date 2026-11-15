// The recipes the chemistry redesign adds (doc/rewrite/proposals/chemistry_recipes.md): the acids and the process chemicals that are made by mixing, and the dirty
// shortcuts of the staples. A shortcut is one step that always works, with what the process chemicals leave behind: its makes list carries the trace-potent
// contaminants (a nitrosamine, tar, heavy metals), so a batch made the quick way can be traced to it. The clean routes of the staples are generated from the
// block structures (code/content/reagents/blocks/), and the shortcuts that are one process chemical poured in (inaprovaline, dexalin, sterilizine, tricordrazine,
// ethanol) are generated with them; these are the ones that are several steps in one pot.

// ---- acids and the building blocks that are mixed ----

/transformation/chem/instant/hydrochloric

CAPABILITIES(/transformation/chem/instant/hydrochloric)
	configure(transformation(name = REAGENT_HYDROCHLORIC, id = REAGENT_ID_HYDROCHLORIC,
		takes = list(reagent(REAGENT_ID_HYDROGEN, 1), reagent(REAGENT_ID_CHLORINE, 1)),
		makes = list(reagent(REAGENT_ID_HYDROCHLORIC, 2))))

/transformation/chem/instant/nitricacid

CAPABILITIES(/transformation/chem/instant/nitricacid)
	configure(transformation(name = REAGENT_NITRICACID, id = REAGENT_ID_NITRICACID,
		takes = list(reagent(REAGENT_ID_AMMONIA, 1), reagent(REAGENT_ID_OXYGEN, 2)),
		makes = list(reagent(REAGENT_ID_NITRICACID, 1), reagent(REAGENT_ID_WATER, 1))))

/transformation/chem/instant/phosphoricacid

CAPABILITIES(/transformation/chem/instant/phosphoricacid)
	configure(transformation(name = REAGENT_PHOSPHORICACID, id = REAGENT_ID_PHOSPHORICACID,
		takes = list(reagent(REAGENT_ID_PHOSPHORUS, 1), reagent(REAGENT_ID_OXYGEN, 2), reagent(REAGENT_ID_WATER, 1)),
		makes = list(reagent(REAGENT_ID_PHOSPHORICACID, 2))))

/transformation/chem/instant/bleach

CAPABILITIES(/transformation/chem/instant/bleach)
	configure(transformation(name = REAGENT_BLEACH, id = REAGENT_ID_BLEACH,
		takes = list(reagent(REAGENT_ID_CHLORINE, 1), reagent(REAGENT_ID_LYE, 1)),
		makes = list(reagent(REAGENT_ID_BLEACH, 2))))

/transformation/chem/instant/sodaash

CAPABILITIES(/transformation/chem/instant/sodaash)
	configure(transformation(name = REAGENT_SODAASH, id = REAGENT_ID_SODAASH,
		takes = list(reagent(REAGENT_ID_LYE, 2), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_OXYGEN, 2)),
		makes = list(reagent(REAGENT_ID_SODAASH, 2), reagent(REAGENT_ID_WATER, 1))))

// ---- the process chemicals ----

/transformation/chem/instant/nitratingmix

CAPABILITIES(/transformation/chem/instant/nitratingmix)
	configure(transformation(name = REAGENT_NITRATINGMIX, id = REAGENT_ID_NITRATINGMIX,
		takes = list(reagent(REAGENT_ID_NITRICACID, 1), reagent(REAGENT_ID_SACID, 1)),
		makes = list(reagent(REAGENT_ID_NITRATINGMIX, 2)), important = TRUE))

/transformation/chem/instant/hydride

CAPABILITIES(/transformation/chem/instant/hydride)
	configure(transformation(name = REAGENT_HYDRIDE, id = REAGENT_ID_HYDRIDE,
		takes = list(reagent(REAGENT_ID_FOAMINGAGENT, 1), reagent(REAGENT_ID_BORON11, 1)),
		makes = list(reagent(REAGENT_ID_HYDRIDE, 2))))

/transformation/chem/instant/strongoxidiser

CAPABILITIES(/transformation/chem/instant/strongoxidiser)
	configure(transformation(name = REAGENT_STRONGOXIDISER, id = REAGENT_ID_STRONGOXIDISER,
		takes = list(reagent(REAGENT_ID_POTASSIUM, 1), reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_BLEACH, 1)),
		makes = list(reagent(REAGENT_ID_STRONGOXIDISER, 3), reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL, 0.15))))

/transformation/chem/instant/chlorinatingagent

CAPABILITIES(/transformation/chem/instant/chlorinatingagent)
	configure(transformation(name = REAGENT_CHLORINATINGAGENT, id = REAGENT_ID_CHLORINATINGAGENT,
		takes = list(reagent(REAGENT_ID_SULFUR, 1), reagent(REAGENT_ID_CHLORINE, 1), reagent(REAGENT_ID_OXYGEN, 1)),
		blocked_by = list(reagent(REAGENT_ID_CARBON, 1)), makes = list(reagent(REAGENT_ID_CHLORINATINGAGENT, 3))))

/transformation/chem/instant/couplingagent

CAPABILITIES(/transformation/chem/instant/couplingagent)
	configure(transformation(name = REAGENT_COUPLINGAGENT, id = REAGENT_ID_COUPLINGAGENT,
		takes = list(reagent(REAGENT_ID_CYANIDE, 1), reagent(REAGENT_ID_DIETHYLAMINE, 1)),
		makes = list(reagent(REAGENT_ID_COUPLINGAGENT, 2))))

/transformation/chem/instant/causticdigest

CAPABILITIES(/transformation/chem/instant/causticdigest)
	configure(transformation(name = REAGENT_CAUSTICDIGEST, id = REAGENT_ID_CAUSTICDIGEST,
		takes = list(reagent(REAGENT_ID_LYE, 2), reagent(REAGENT_ID_WATER, 1)),
		makes = list(reagent(REAGENT_ID_CAUSTICDIGEST, 3))))

/transformation/chem/instant/scavengerresin

CAPABILITIES(/transformation/chem/instant/scavengerresin)
	configure(transformation(name = REAGENT_SCAVENGERRESIN, id = REAGENT_ID_SCAVENGERRESIN,
		takes = list(reagent(REAGENT_ID_CARBON, 2), reagent(REAGENT_ID_CALCIUMCARBONATE, 1)),
		makes = list(reagent(REAGENT_ID_SCAVENGERRESIN, 3))))

// ---- the dirty shortcuts: one step, always works, leaves trace-potent contaminants ----

/transformation/chem/instant/shortcut_bicaridine

CAPABILITIES(/transformation/chem/instant/shortcut_bicaridine)
	configure(transformation(name = "Bicaridine, one pot", id = "shortcut_bicaridine",
		takes = list(reagent(REAGENT_ID_SALICYLICACID, 1), reagent(REAGENT_ID_NITRATINGMIX, 1), reagent(REAGENT_ID_HYDRIDE, 1)),
		makes = list(reagent(REAGENT_ID_BICARIDINE, 1), reagent(REAGENT_ID_CONTAMINANT_NITROSAMINE, 0.08), reagent(REAGENT_ID_CONTAMINANT_ACID_RESIDUE, 0.12), reagent(REAGENT_ID_CONTAMINANT_BASE_RESIDUE, 0.08))))

/transformation/chem/instant/shortcut_kelotane

CAPABILITIES(/transformation/chem/instant/shortcut_kelotane)
	configure(transformation(name = "Kelotane, not neutralised", id = "shortcut_kelotane",
		takes = list(reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_LYE, 1)),
		makes = list(reagent(REAGENT_ID_KELOTANE, 1), reagent(REAGENT_ID_CONTAMINANT_BASE_RESIDUE, 0.3))))

/transformation/chem/instant/shortcut_dylovene

CAPABILITIES(/transformation/chem/instant/shortcut_dylovene)
	configure(transformation(name = "Dylovene, one pot", id = "shortcut_dylovene",
		takes = list(reagent(REAGENT_ID_GLYCEROL, 1), reagent(REAGENT_ID_SULFUR, 1), reagent(REAGENT_ID_CHLORINATINGAGENT, 1)),
		makes = list(reagent(REAGENT_ID_ANTITOXIN, 1), reagent(REAGENT_ID_HYDROCHLORIC, 0.15), reagent(REAGENT_ID_CONTAMINANT_SULFUR, 0.15))))

/transformation/chem/instant/shortcut_paracetamol

CAPABILITIES(/transformation/chem/instant/shortcut_paracetamol)
	configure(transformation(name = "Paracetamol, one pot, hot", id = "shortcut_paracetamol",
		takes = list(reagent(REAGENT_ID_PHENOL, 1), reagent(REAGENT_ID_NITRATINGMIX, 1), reagent(REAGENT_ID_HYDRIDE, 1), reagent(REAGENT_ID_ACETICACID, 1)),
		makes = list(reagent(REAGENT_ID_PARACETAMOL, 1), reagent(REAGENT_ID_CONTAMINANT_NITROSAMINE, 0.1), reagent(REAGENT_ID_CONTAMINANT_TAR, 0.1), reagent(REAGENT_ID_WOODALDEHYDE, 0.1))))

/transformation/chem/instant/shortcut_hyperzine

CAPABILITIES(/transformation/chem/instant/shortcut_hyperzine)
	configure(transformation(name = "Hyperzine, the Stimm route", id = "shortcut_hyperzine",
		takes = list(reagent(REAGENT_ID_FUEL, 1), reagent(REAGENT_ID_FERTILIZER, 1)),
		makes = list(reagent(REAGENT_ID_HYPERZINE, 1), reagent(REAGENT_ID_CONTAMINANT_TAR, 0.1), reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL, 0.08), reagent(REAGENT_ID_CONTAMINANT_SULFUR, 0.08))))
