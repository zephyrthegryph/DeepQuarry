// These reactions happen instantaneously, when added to a container that has all other necessary reagents
// They are a subtype of chemical_reaction so that such containers can iterate over only these reactions, and not have to skip other reaction types

/* Common reactions */

/transformation/chem/instant

/transformation/chem/instant/inaprovaline

CAPABILITIES(/transformation/chem/instant/inaprovaline)
	configure(transformation(name = REAGENT_INAPROVALINE, id = REAGENT_ID_INAPROVALINE,
		takes = list(reagent(REAGENT_ID_OXYGEN, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_SUGAR, 1)),
		blocked_by = list(reagent(REAGENT_ID_WATER, 1)), makes = list(reagent(REAGENT_ID_INAPROVALINE, 3))))

/transformation/chem/instant/dylovene

CAPABILITIES(/transformation/chem/instant/dylovene)
	configure(transformation(name = REAGENT_ANTITOXIN, id = REAGENT_ID_ANTITOXIN,
		takes = list(reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_POTASSIUM, 1), reagent(REAGENT_ID_NITROGEN, 1)),
		makes = list(reagent(REAGENT_ID_ANTITOXIN, 3))))

/transformation/chem/instant/carthatoline

CAPABILITIES(/transformation/chem/instant/carthatoline)
	configure(transformation(name = REAGENT_CARTHATOLINE, id = REAGENT_ID_CARTHATOLINE,
		takes = list(reagent(REAGENT_ID_ANTITOXIN, 1), reagent(REAGENT_ID_CARBON, 2), reagent(REAGENT_ID_PHORON, 0.1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 1)), makes = list(reagent(REAGENT_ID_CARTHATOLINE, 2))))

/transformation/chem/instant/paracetamol

CAPABILITIES(/transformation/chem/instant/paracetamol)
	configure(transformation(name = REAGENT_PARACETAMOL, id = REAGENT_ID_PARACETAMOL,
		takes = list(reagent(REAGENT_ID_INAPROVALINE, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_WATER, 1)),
		makes = list(reagent(REAGENT_ID_PARACETAMOL, 2))))

/transformation/chem/instant/tramadol

CAPABILITIES(/transformation/chem/instant/tramadol)
	configure(transformation(name = REAGENT_TRAMADOL, id = REAGENT_ID_TRAMADOL,
		takes = list(reagent(REAGENT_ID_PARACETAMOL, 1), reagent(REAGENT_ID_ETHANOL, 1), reagent(REAGENT_ID_OXYGEN, 1)),
		makes = list(reagent(REAGENT_ID_TRAMADOL, 3))))

/transformation/chem/instant/oxycodone

CAPABILITIES(/transformation/chem/instant/oxycodone)
	configure(transformation(name = REAGENT_OXYCODONE, id = REAGENT_ID_OXYCODONE,
		takes = list(reagent(REAGENT_ID_ETHANOL, 1), reagent(REAGENT_ID_TRAMADOL, 1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), makes = list(reagent(REAGENT_ID_OXYCODONE, 1))))

/transformation/chem/instant/sterilizine

CAPABILITIES(/transformation/chem/instant/sterilizine)
	configure(transformation(name = REAGENT_STERILIZINE, id = REAGENT_ID_STERILIZINE,
		takes = list(reagent(REAGENT_ID_ETHANOL, 1), reagent(REAGENT_ID_ANTITOXIN, 1), reagent(REAGENT_ID_CHLORINE, 1)),
		makes = list(reagent(REAGENT_ID_STERILIZINE, 3))))

/transformation/chem/instant/silicate

CAPABILITIES(/transformation/chem/instant/silicate)
	configure(transformation(name = REAGENT_SILICATE, id = REAGENT_ID_SILICATE,
		takes = list(reagent(REAGENT_ID_ALUMINIUM, 1), reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_OXYGEN, 1)),
		makes = list(reagent(REAGENT_ID_SILICATE, 3))))

/transformation/chem/instant/mutagen

CAPABILITIES(/transformation/chem/instant/mutagen)
	configure(transformation(name = REAGENT_MUTAGEN, id = REAGENT_ID_MUTAGEN,
		takes = list(reagent(REAGENT_ID_RADIUM, 1), reagent(REAGENT_ID_PHOSPHORUS, 1), reagent(REAGENT_ID_CHLORINE, 1)),
		makes = list(reagent(REAGENT_ID_MUTAGEN, 3))))

/transformation/chem/instant/water

CAPABILITIES(/transformation/chem/instant/water)
	configure(transformation(name = REAGENT_WATER, id = REAGENT_ID_WATER, takes = list(reagent(REAGENT_ID_OXYGEN, 1), reagent(REAGENT_ID_HYDROGEN, 2)),
		blocked_by = list(reagent(REAGENT_ID_SODIUM, 1), reagent(REAGENT_ID_CARBON, 1)),
		makes = list(reagent(REAGENT_ID_WATER, 1))))

/transformation/chem/instant/thermite

CAPABILITIES(/transformation/chem/instant/thermite)
	configure(transformation(name = REAGENT_THERMITE, id = REAGENT_ID_THERMITE,
		takes = list(reagent(REAGENT_ID_ALUMINIUM, 1), reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_OXYGEN, 1)),
		makes = list(reagent(REAGENT_ID_THERMITE, 3))))

/transformation/chem/instant/bliss

CAPABILITIES(/transformation/chem/instant/bliss)
	configure(transformation(name = REAGENT_BLISS, id = REAGENT_ID_BLISS,
		takes = list(reagent(REAGENT_ID_MERCURY, 1), reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_LITHIUM, 1)),
		makes = list(reagent(REAGENT_ID_BLISS, 3))))

/transformation/chem/instant/lube

CAPABILITIES(/transformation/chem/instant/lube)
	configure(transformation(name = REAGENT_LUBE, id = REAGENT_ID_LUBE,
		takes = list(reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_OXYGEN, 1)),
		makes = list(reagent(REAGENT_ID_LUBE, 4))))

/transformation/chem/instant/pacid

CAPABILITIES(/transformation/chem/instant/pacid)
	configure(transformation(name = REAGENT_PACID, id = REAGENT_ID_PACID,
		takes = list(reagent(REAGENT_ID_SACID, 1), reagent(REAGENT_ID_CHLORINE, 1), reagent(REAGENT_ID_POTASSIUM, 1)),
		makes = list(reagent(REAGENT_ID_PACID, 3))))

/transformation/chem/instant/synaptizine

CAPABILITIES(/transformation/chem/instant/synaptizine)
	configure(transformation(name = REAGENT_SYNAPTIZINE, id = REAGENT_ID_SYNAPTIZINE,
		takes = list(reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_LITHIUM, 1), reagent(REAGENT_ID_WATER, 1)),
		makes = list(reagent(REAGENT_ID_SYNAPTIZINE, 3))))

/transformation/chem/instant/hyronalin

CAPABILITIES(/transformation/chem/instant/hyronalin)
	configure(transformation(name = REAGENT_HYRONALIN, id = REAGENT_ID_HYRONALIN,
		takes = list(reagent(REAGENT_ID_RADIUM, 1), reagent(REAGENT_ID_ANTITOXIN, 1)),
		makes = list(reagent(REAGENT_ID_HYRONALIN, 2))))

/transformation/chem/instant/arithrazine

CAPABILITIES(/transformation/chem/instant/arithrazine)
	configure(transformation(name = REAGENT_ARITHRAZINE, id = REAGENT_ID_ARITHRAZINE,
		takes = list(reagent(REAGENT_ID_HYRONALIN, 1), reagent(REAGENT_ID_HYDROGEN, 1)),
		makes = list(reagent(REAGENT_ID_ARITHRAZINE, 2))))

/transformation/chem/instant/impedrezene

CAPABILITIES(/transformation/chem/instant/impedrezene)
	configure(transformation(name = REAGENT_IMPEDREZENE, id = REAGENT_ID_IMPEDREZENE,
		takes = list(reagent(REAGENT_ID_MERCURY, 1), reagent(REAGENT_ID_OXYGEN, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_IMPEDREZENE, 2))))

/transformation/chem/instant/kelotane

CAPABILITIES(/transformation/chem/instant/kelotane)
	configure(transformation(name = REAGENT_KELOTANE, id = REAGENT_ID_KELOTANE,
		takes = list(reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_CARBON, 1)),
		blocked_by = list(reagent(REAGENT_ID_WATER, 1)), makes = list(reagent(REAGENT_ID_KELOTANE, 2)), important = TRUE))

/transformation/chem/instant/peridaxon

CAPABILITIES(/transformation/chem/instant/peridaxon)
	configure(transformation(name = REAGENT_PERIDAXON, id = REAGENT_ID_PERIDAXON,
		takes = list(reagent(REAGENT_ID_BICARIDINE, 2), reagent(REAGENT_ID_CLONEXADONE, 2)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), makes = list(reagent(REAGENT_ID_PERIDAXON, 2))))

/transformation/chem/instant/osteodaxon

CAPABILITIES(/transformation/chem/instant/osteodaxon)
	configure(transformation(name = REAGENT_OSTEODAXON, id = REAGENT_ID_OSTEODAXON,
		takes = list(reagent(REAGENT_ID_BICARIDINE, 2), reagent(REAGENT_ID_PHORON, 0.1), reagent(REAGENT_ID_CARPOTOXIN, 1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), blocked_by = list(reagent(REAGENT_ID_CLONEXADONE, 1)),
		makes = list(reagent(REAGENT_ID_OSTEODAXON, 2))))

/transformation/chem/instant/respirodaxon

CAPABILITIES(/transformation/chem/instant/respirodaxon)
	configure(transformation(name = REAGENT_RESPIRODAXON, id = REAGENT_ID_RESPIRODAXON,
		takes = list(reagent(REAGENT_ID_DEXALINP, 2), reagent(REAGENT_ID_BIOMASS, 2), reagent(REAGENT_ID_PHORON, 1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), blocked_by = list(reagent(REAGENT_ID_DEXALIN, 1)),
		makes = list(reagent(REAGENT_ID_RESPIRODAXON, 2))))

/transformation/chem/instant/gastirodaxon

CAPABILITIES(/transformation/chem/instant/gastirodaxon)
	configure(transformation(name = REAGENT_GASTIRODAXON, id = REAGENT_ID_GASTIRODAXON,
		takes = list(reagent(REAGENT_ID_CARTHATOLINE, 1), reagent(REAGENT_ID_BIOMASS, 2), reagent(REAGENT_ID_TUNGSTEN, 2)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), blocked_by = list(reagent(REAGENT_ID_LITHIUM, 1)),
		makes = list(reagent(REAGENT_ID_GASTIRODAXON, 3))))

/transformation/chem/instant/hepanephrodaxon

CAPABILITIES(/transformation/chem/instant/hepanephrodaxon)
	configure(transformation(name = REAGENT_HEPANEPHRODAXON, id = REAGENT_ID_HEPANEPHRODAXON,
		takes = list(reagent(REAGENT_ID_CARTHATOLINE, 2), reagent(REAGENT_ID_BIOMASS, 2), reagent(REAGENT_ID_LITHIUM, 1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), blocked_by = list(reagent(REAGENT_ID_TUNGSTEN, 1)),
		makes = list(reagent(REAGENT_ID_HEPANEPHRODAXON, 2))))

/transformation/chem/instant/cordradaxon

CAPABILITIES(/transformation/chem/instant/cordradaxon)
	configure(transformation(name = REAGENT_CORDRADAXON, id = REAGENT_ID_CORDRADAXON,
		takes = list(reagent(REAGENT_ID_POTASSIUMCHLOROPHORIDE, 1), reagent(REAGENT_ID_BIOMASS, 2), reagent(REAGENT_ID_BICARIDINE, 2)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), blocked_by = list(reagent(REAGENT_ID_CLONEXADONE, 1)),
		makes = list(reagent(REAGENT_ID_CORDRADAXON, 2))))

/transformation/chem/instant/virus_food

CAPABILITIES(/transformation/chem/instant/virus_food)
	configure(transformation(name = REAGENT_VIRUSFOOD, id = REAGENT_ID_VIRUSFOOD,
		takes = list(reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_MILK, 1)), makes = list(reagent(REAGENT_ID_VIRUSFOOD, 5))))

/transformation/chem/instant/leporazine

CAPABILITIES(/transformation/chem/instant/leporazine)
	configure(transformation(name = REAGENT_LEPORAZINE, id = REAGENT_ID_LEPORAZINE,
		takes = list(reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_COPPER, 1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), makes = list(reagent(REAGENT_ID_LEPORAZINE, 2))))

/transformation/chem/instant/cryptobiolin

CAPABILITIES(/transformation/chem/instant/cryptobiolin)
	configure(transformation(name = REAGENT_CRYPTOBIOLIN, id = REAGENT_ID_CRYPTOBIOLIN,
		takes = list(reagent(REAGENT_ID_POTASSIUM, 1), reagent(REAGENT_ID_OXYGEN, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_CRYPTOBIOLIN, 3))))

/transformation/chem/instant/tricordrazine

CAPABILITIES(/transformation/chem/instant/tricordrazine)
	configure(transformation(name = REAGENT_TRICORDRAZINE, id = REAGENT_ID_TRICORDRAZINE,
		takes = list(reagent(REAGENT_ID_INAPROVALINE, 1), reagent(REAGENT_ID_ANTITOXIN, 1)),
		makes = list(reagent(REAGENT_ID_TRICORDRAZINE, 2))))

/transformation/chem/instant/alkysine

CAPABILITIES(/transformation/chem/instant/alkysine)
	configure(transformation(name = REAGENT_ALKYSINE, id = REAGENT_ID_ALKYSINE,
		takes = list(reagent(REAGENT_ID_CHLORINE, 1), reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_ANTITOXIN, 1)),
		makes = list(reagent(REAGENT_ID_ALKYSINE, 2))))

/transformation/chem/instant/dexalin

CAPABILITIES(/transformation/chem/instant/dexalin)
	configure(transformation(name = REAGENT_DEXALIN, id = REAGENT_ID_DEXALIN,
		takes = list(reagent(REAGENT_ID_OXYGEN, 2), reagent(REAGENT_ID_PHORON, 0.1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 1)),
		blocked_by = list(reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_TIN, 1)), makes = list(reagent(REAGENT_ID_DEXALIN, 1))))

/transformation/chem/instant/dermaline

CAPABILITIES(/transformation/chem/instant/dermaline)
	configure(transformation(name = REAGENT_DERMALINE, id = REAGENT_ID_DERMALINE,
		takes = list(reagent(REAGENT_ID_OXYGEN, 1), reagent(REAGENT_ID_PHOSPHORUS, 1), reagent(REAGENT_ID_KELOTANE, 1)),
		makes = list(reagent(REAGENT_ID_DERMALINE, 3))))

/transformation/chem/instant/dexalinp

CAPABILITIES(/transformation/chem/instant/dexalinp)
	configure(transformation(name = REAGENT_DEXALINP, id = REAGENT_ID_DEXALINP,
		takes = list(reagent(REAGENT_ID_DEXALIN, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_IRON, 1)),
		makes = list(reagent(REAGENT_ID_DEXALINP, 3))))

/transformation/chem/instant/bicaridine

CAPABILITIES(/transformation/chem/instant/bicaridine)
	configure(transformation(name = REAGENT_BICARIDINE, id = REAGENT_ID_BICARIDINE,
		takes = list(reagent(REAGENT_ID_INAPROVALINE, 1), reagent(REAGENT_ID_CARBON, 1)),
		blocked_by = list(reagent(REAGENT_ID_SUGAR, 1)), makes = list(reagent(REAGENT_ID_BICARIDINE, 2))))

/transformation/chem/instant/myelamine

CAPABILITIES(/transformation/chem/instant/myelamine)
	configure(transformation(name = REAGENT_MYELAMINE, id = REAGENT_ID_MYELAMINE,
		takes = list(reagent(REAGENT_ID_BICARIDINE, 1), reagent(REAGENT_ID_IRON, 2), reagent(REAGENT_ID_SPIDERTOXIN, 1)),
		makes = list(reagent(REAGENT_ID_MYELAMINE, 2))))

/transformation/chem/instant/hyperzine

CAPABILITIES(/transformation/chem/instant/hyperzine)
	configure(transformation(name = REAGENT_HYPERZINE, id = REAGENT_ID_HYPERZINE,
		takes = list(reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_PHOSPHORUS, 1), reagent(REAGENT_ID_SULFUR, 1)),
		makes = list(reagent(REAGENT_ID_HYPERZINE, 3))))

/transformation/chem/instant/stimm

CAPABILITIES(/transformation/chem/instant/stimm)
	configure(transformation(name = REAGENT_STIMM, id = REAGENT_ID_STIMM, takes = list(reagent(REAGENT_ID_LEFT4ZED, 1), reagent(REAGENT_ID_FUEL, 1)),
		catalysts = list(reagent(REAGENT_ID_FUEL, 5)), makes = list(reagent(REAGENT_ID_STIMM, 2))))

/transformation/chem/instant/ryetalyn

CAPABILITIES(/transformation/chem/instant/ryetalyn)
	configure(transformation(name = REAGENT_RYETALYN, id = REAGENT_ID_RYETALYN,
		takes = list(reagent(REAGENT_ID_ARITHRAZINE, 1), reagent(REAGENT_ID_CARBON, 1)),
		makes = list(reagent(REAGENT_ID_RYETALYN, 2))))

/transformation/chem/instant/cryoxadone

CAPABILITIES(/transformation/chem/instant/cryoxadone)
	configure(transformation(name = REAGENT_CRYOXADONE, id = REAGENT_ID_CRYOXADONE,
		takes = list(reagent(REAGENT_ID_DEXALIN, 1), reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_OXYGEN, 1)),
		makes = list(reagent(REAGENT_ID_CRYOXADONE, 3))))

/transformation/chem/instant/clonexadone

CAPABILITIES(/transformation/chem/instant/clonexadone)
	configure(transformation(name = REAGENT_CLONEXADONE, id = REAGENT_ID_CLONEXADONE,
		takes = list(reagent(REAGENT_ID_CRYOXADONE, 1), reagent(REAGENT_ID_SODIUM, 1), reagent(REAGENT_ID_PHORON, 0.1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), makes = list(reagent(REAGENT_ID_CLONEXADONE, 2))))

/transformation/chem/instant/mortiferin

CAPABILITIES(/transformation/chem/instant/mortiferin)
	configure(transformation(name = REAGENT_MORTIFERIN, id = REAGENT_ID_MORTIFERIN,
		takes = list(reagent(REAGENT_ID_CRYPTOBIOLIN, 1), reagent(REAGENT_ID_CLONEXADONE, 1), reagent(REAGENT_ID_COROPHIZINE, 1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), makes = list(reagent(REAGENT_ID_MORTIFERIN, 2))))

/transformation/chem/instant/spaceacillin

CAPABILITIES(/transformation/chem/instant/spaceacillin)
	configure(transformation(name = REAGENT_SPACEACILLIN, id = REAGENT_ID_SPACEACILLIN,
		takes = list(reagent(REAGENT_ID_CRYPTOBIOLIN, 1), reagent(REAGENT_ID_INAPROVALINE, 1)),
		makes = list(reagent(REAGENT_ID_SPACEACILLIN, 2))))

/transformation/chem/instant/corophizine

CAPABILITIES(/transformation/chem/instant/corophizine)
	configure(transformation(name = REAGENT_COROPHIZINE, id = REAGENT_ID_COROPHIZINE,
		takes = list(reagent(REAGENT_ID_SPACEACILLIN, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_PHORON, 0.1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), makes = list(reagent(REAGENT_ID_COROPHIZINE, 2))))

/transformation/chem/instant/immunosuprizine

CAPABILITIES(/transformation/chem/instant/immunosuprizine)
	configure(transformation(name = REAGENT_IMMUNOSUPRIZINE, id = REAGENT_ID_IMMUNOSUPRIZINE,
		takes = list(reagent(REAGENT_ID_COROPHIZINE, 1), reagent(REAGENT_ID_TUNGSTEN, 1), reagent(REAGENT_ID_SACID, 1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), makes = list(reagent(REAGENT_ID_IMMUNOSUPRIZINE, 2))))

/transformation/chem/instant/imidazoline

CAPABILITIES(/transformation/chem/instant/imidazoline)
	configure(transformation(name = REAGENT_ID_IMIDAZOLINE, id = REAGENT_ID_IMIDAZOLINE,
		takes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_HYDROGEN, 1), reagent(REAGENT_ID_ANTITOXIN, 1)),
		makes = list(reagent(REAGENT_ID_IMIDAZOLINE, 2))))

/transformation/chem/instant/ethylredoxrazine

CAPABILITIES(/transformation/chem/instant/ethylredoxrazine)
	configure(transformation(name = REAGENT_ETHYLREDOXRAZINE, id = REAGENT_ID_ETHYLREDOXRAZINE,
		takes = list(reagent(REAGENT_ID_OXYGEN, 1), reagent(REAGENT_ID_ANTITOXIN, 1), reagent(REAGENT_ID_CARBON, 1)),
		makes = list(reagent(REAGENT_ID_ETHYLREDOXRAZINE, 3))))

/transformation/chem/instant/calciumcarbonate

CAPABILITIES(/transformation/chem/instant/calciumcarbonate)
	configure(transformation(name = "Calcium Carbonate", id = REAGENT_ID_CALCIUMCARBONATE,
		takes = list(reagent(REAGENT_ID_OXYGEN, 3), reagent(REAGENT_ID_CALCIUM, 1), reagent(REAGENT_ID_CARBON, 1)),
		makes = list(reagent(REAGENT_ID_CALCIUMCARBONATE, 2))))

/transformation/chem/instant/soporific

CAPABILITIES(/transformation/chem/instant/soporific)
	configure(transformation(name = REAGENT_STOXIN, id = REAGENT_ID_STOXIN,
		takes = list(reagent(REAGENT_ID_CHLORALHYDRATE, 1), reagent(REAGENT_ID_SUGAR, 4)),
		blocked_by = list(reagent(REAGENT_ID_PHOSPHORUS, 1)), makes = list(reagent(REAGENT_ID_STOXIN, 5))))

/transformation/chem/instant/chloralhydrate

CAPABILITIES(/transformation/chem/instant/chloralhydrate)
	configure(transformation(name = REAGENT_CHLORALHYDRATE, id = REAGENT_ID_CHLORALHYDRATE,
		takes = list(reagent(REAGENT_ID_ETHANOL, 1), reagent(REAGENT_ID_CHLORINE, 3), reagent(REAGENT_ID_WATER, 1)),
		makes = list(reagent(REAGENT_ID_CHLORALHYDRATE, 1))))

/transformation/chem/instant/potassium_chloride

CAPABILITIES(/transformation/chem/instant/potassium_chloride)
	configure(transformation(name = REAGENT_POTASSIUMCHLORIDE, id = REAGENT_ID_POTASSIUMCHLORIDE,
		takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1), reagent(REAGENT_ID_POTASSIUM, 1)),
		makes = list(reagent(REAGENT_ID_POTASSIUMCHLORIDE, 2))))

/transformation/chem/instant/potassium_chlorophoride

CAPABILITIES(/transformation/chem/instant/potassium_chlorophoride)
	configure(transformation(name = REAGENT_POTASSIUMCHLOROPHORIDE, id = REAGENT_ID_POTASSIUMCHLOROPHORIDE,
		takes = list(reagent(REAGENT_ID_POTASSIUMCHLORIDE, 1), reagent(REAGENT_ID_PHORON, 1), reagent(REAGENT_ID_CHLORALHYDRATE, 1)),
		makes = list(reagent(REAGENT_ID_POTASSIUMCHLOROPHORIDE, 4))))

/transformation/chem/instant/zombiepowder

CAPABILITIES(/transformation/chem/instant/zombiepowder)
	configure(transformation(name = REAGENT_ZOMBIEPOWDER, id = REAGENT_ID_ZOMBIEPOWDER,
		takes = list(reagent(REAGENT_ID_CARPOTOXIN, 5), reagent(REAGENT_ID_STOXIN, 5), reagent(REAGENT_ID_COPPER, 5)),
		makes = list(reagent(REAGENT_ID_ZOMBIEPOWDER, 2))))

/transformation/chem/instant/zombiepowder/alt

CAPABILITIES(/transformation/chem/instant/zombiepowder/alt)
	configure(transformation(name = REAGENT_ZOMBIEPOWDER + "_alternative_mix", id = REAGENT_ID_ZOMBIEPOWDER + "_alternative_mix",
		takes = list(reagent(REAGENT_ID_POTASSIUMCHLOROPHORIDE, 5), reagent(REAGENT_ID_STOXIN, 5), reagent(REAGENT_ID_CHLORALHYDRATE, 5), reagent(REAGENT_ID_MERCURY, 5)),
		makes = list(reagent(REAGENT_ID_ZOMBIEPOWDER, 2))))

/transformation/chem/instant/carpotoxin

CAPABILITIES(/transformation/chem/instant/carpotoxin)
	configure(transformation(name = REAGENT_CARPOTOXIN, id = REAGENT_ID_CARPOTOXIN,
		takes = list(reagent(REAGENT_ID_SPIDERTOXIN, 2), reagent(REAGENT_ID_BIOMASS, 1), reagent(REAGENT_ID_SIFSAP, 2)),
		catalysts = list(reagent(REAGENT_ID_SIFSAP, 10)), blocked_by = list(reagent(REAGENT_ID_RADIUM, 1)),
		makes = list(reagent(REAGENT_ID_CARPOTOXIN, 2))))

/transformation/chem/instant/mindbreaker

CAPABILITIES(/transformation/chem/instant/mindbreaker)
	configure(transformation(name = REAGENT_MINDBREAKER, id = REAGENT_ID_MINDBREAKER,
		takes = list(reagent(REAGENT_ID_SILICON, 1), reagent(REAGENT_ID_HYDROGEN, 1), reagent(REAGENT_ID_ANTITOXIN, 1)),
		makes = list(reagent(REAGENT_ID_MINDBREAKER, 3))))

/transformation/chem/instant/lipozine

CAPABILITIES(/transformation/chem/instant/lipozine)
	configure(transformation(name = REAGENT_LIPOZINE, id = REAGENT_ID_LIPOZINE,
		takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1), reagent(REAGENT_ID_ETHANOL, 1), reagent(REAGENT_ID_RADIUM, 1)),
		makes = list(reagent(REAGENT_ID_LIPOZINE, 3))))

/transformation/chem/instant/surfactant

CAPABILITIES(/transformation/chem/instant/surfactant)
	configure(transformation(name = "Foam surfactant", id = "foam surfactant",
		takes = list(reagent(REAGENT_ID_FLUORINE, 2), reagent(REAGENT_ID_CARBON, 2), reagent(REAGENT_ID_SACID, 1)),
		makes = list(reagent(REAGENT_ID_FLUOROSURFACTANT, 5))))

/transformation/chem/instant/ammonia

CAPABILITIES(/transformation/chem/instant/ammonia)
	configure(transformation(name = REAGENT_AMMONIA, id = REAGENT_ID_AMMONIA,
		takes = list(reagent(REAGENT_ID_HYDROGEN, 3), reagent(REAGENT_ID_NITROGEN, 1)),
		blocked_by = list(reagent(REAGENT_ID_PHORON, 1)), makes = list(reagent(REAGENT_ID_AMMONIA, 3))))

/transformation/chem/instant/diethylamine

CAPABILITIES(/transformation/chem/instant/diethylamine)
	configure(transformation(name = REAGENT_DIETHYLAMINE, id = REAGENT_ID_DIETHYLAMINE,
		takes = list(reagent(REAGENT_ID_AMMONIA, 1), reagent(REAGENT_ID_ETHANOL, 1)),
		makes = list(reagent(REAGENT_ID_DIETHYLAMINE, 2))))

/transformation/chem/instant/lye

CAPABILITIES(/transformation/chem/instant/lye)
	configure(transformation(name = REAGENT_LYE, id = REAGENT_ID_LYE,
		takes = list(reagent(REAGENT_ID_SODIUM, 1), reagent(REAGENT_ID_HYDROGEN, 1), reagent(REAGENT_ID_OXYGEN, 1)),
		blocked_by = list(reagent(REAGENT_ID_CARBON, 1)), makes = list(reagent(REAGENT_ID_LYE, 3))))

/transformation/chem/instant/left4zed

CAPABILITIES(/transformation/chem/instant/left4zed)
	configure(transformation(name = "Left4Zed", id = REAGENT_ID_LEFT4ZED,
		takes = list(reagent(REAGENT_ID_DIETHYLAMINE, 2), reagent(REAGENT_ID_MUTAGEN, 1)),
		makes = list(reagent(REAGENT_ID_LEFT4ZED, 3))))

/transformation/chem/instant/robustharvest

CAPABILITIES(/transformation/chem/instant/robustharvest)
	configure(transformation(name = "RobustHarvest", id = REAGENT_ID_ROBUSTHARVEST,
		takes = list(reagent(REAGENT_ID_AMMONIA, 1), reagent(REAGENT_ID_CALCIUM, 1), reagent(REAGENT_ID_NEUROTOXIC_PROTEIN, 1)),
		makes = list(reagent(REAGENT_ID_ROBUSTHARVEST, 3))))

/transformation/chem/instant/space_cleaner

CAPABILITIES(/transformation/chem/instant/space_cleaner)
	configure(transformation(name = REAGENT_CLEANER, id = REAGENT_ID_CLEANER,
		takes = list(reagent(REAGENT_ID_AMMONIA, 1), reagent(REAGENT_ID_WATER, 1)), makes = list(reagent(REAGENT_ID_CLEANER, 2))))

/transformation/chem/instant/plantbgone

CAPABILITIES(/transformation/chem/instant/plantbgone)
	configure(transformation(name = REAGENT_PLANTBGONE, id = REAGENT_ID_PLANTBGONE,
		takes = list(reagent(REAGENT_ID_TOXIN, 1), reagent(REAGENT_ID_WATER, 4)), makes = list(reagent(REAGENT_ID_PLANTBGONE, 5))))

/transformation/chem/instant/foaming_agent

CAPABILITIES(/transformation/chem/instant/foaming_agent)
	configure(transformation(name = "Foaming Agent", id = REAGENT_ID_FOAMINGAGENT,
		takes = list(reagent(REAGENT_ID_LITHIUM, 1), reagent(REAGENT_ID_HYDROGEN, 1)),
		makes = list(reagent(REAGENT_ID_FOAMINGAGENT, 1))))

/transformation/chem/instant/glycerol

CAPABILITIES(/transformation/chem/instant/glycerol)
	configure(transformation(name = REAGENT_GLYCEROL, id = REAGENT_ID_GLYCEROL,
		takes = list(reagent(REAGENT_ID_CORNOIL, 3), reagent(REAGENT_ID_SACID, 1)), makes = list(reagent(REAGENT_ID_GLYCEROL, 1))))

/transformation/chem/instant/sodiumchloride

CAPABILITIES(/transformation/chem/instant/sodiumchloride)
	configure(transformation(name = "Sodium Chloride", id = REAGENT_ID_SODIUMCHLORIDE,
		takes = list(reagent(REAGENT_ID_SODIUM, 1), reagent(REAGENT_ID_CHLORINE, 1)),
		blocked_by = list(reagent(REAGENT_ID_COPPER, 1)), makes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 2))))

/transformation/chem/instant/condensedcapsaicin

CAPABILITIES(/transformation/chem/instant/condensedcapsaicin)
	configure(transformation(name = REAGENT_CONDENSEDCAPSAICIN, id = REAGENT_ID_CONDENSEDCAPSAICIN, takes = list(reagent(REAGENT_ID_CAPSAICIN, 2)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), makes = list(reagent(REAGENT_ID_CONDENSEDCAPSAICIN, 1))))

/transformation/chem/instant/coolant

CAPABILITIES(/transformation/chem/instant/coolant)
	configure(transformation(name = REAGENT_COOLANT, id = REAGENT_ID_COOLANT,
		takes = list(reagent(REAGENT_ID_TUNGSTEN, 1), reagent(REAGENT_ID_OXYGEN, 1), reagent(REAGENT_ID_WATER, 1)),
		makes = list(reagent(REAGENT_ID_COOLANT, 3)), important = TRUE))

/transformation/chem/instant/rezadone

CAPABILITIES(/transformation/chem/instant/rezadone)
	configure(transformation(name = REAGENT_REZADONE, id = REAGENT_ID_REZADONE,
		takes = list(reagent(REAGENT_ID_CARPOTOXIN, 1), reagent(REAGENT_ID_CRYPTOBIOLIN, 1), reagent(REAGENT_ID_COPPER, 1)),
		makes = list(reagent(REAGENT_ID_REZADONE, 3))))

/transformation/chem/instant/lexorin

CAPABILITIES(/transformation/chem/instant/lexorin)
	configure(transformation(name = REAGENT_LEXORIN, id = REAGENT_ID_LEXORIN,
		takes = list(reagent(REAGENT_ID_PHORON, 1), reagent(REAGENT_ID_HYDROGEN, 1), reagent(REAGENT_ID_NITROGEN, 1)),
		blocked_by = list(reagent(REAGENT_ID_COPPER, 1)), makes = list(reagent(REAGENT_ID_LEXORIN, 3))))

/transformation/chem/instant/methylphenidate

CAPABILITIES(/transformation/chem/instant/methylphenidate)
	configure(transformation(name = REAGENT_METHYLPHENIDATE, id = REAGENT_ID_METHYLPHENIDATE,
		takes = list(reagent(REAGENT_ID_MINDBREAKER, 1), reagent(REAGENT_ID_HYDROGEN, 1)),
		makes = list(reagent(REAGENT_ID_METHYLPHENIDATE, 3))))

/transformation/chem/instant/citalopram

CAPABILITIES(/transformation/chem/instant/citalopram)
	configure(transformation(name = REAGENT_CITALOPRAM, id = REAGENT_ID_CITALOPRAM,
		takes = list(reagent(REAGENT_ID_MINDBREAKER, 1), reagent(REAGENT_ID_CARBON, 1)),
		makes = list(reagent(REAGENT_ID_CITALOPRAM, 3))))

/transformation/chem/instant/paroxetine

CAPABILITIES(/transformation/chem/instant/paroxetine)
	configure(transformation(name = REAGENT_PAROXETINE, id = REAGENT_ID_PAROXETINE,
		takes = list(reagent(REAGENT_ID_MINDBREAKER, 1), reagent(REAGENT_ID_OXYGEN, 1), reagent(REAGENT_ID_INAPROVALINE, 1)),
		makes = list(reagent(REAGENT_ID_PAROXETINE, 3))))

/transformation/chem/instant/neurotoxin

CAPABILITIES(/transformation/chem/instant/neurotoxin)
	configure(transformation(name = REAGENT_NEUROTOXIN, id = REAGENT_ID_NEUROTOXIN,
		takes = list(reagent(REAGENT_ID_GARGLEBLASTER, 1), reagent(REAGENT_ID_STOXIN, 1)),
		makes = list(reagent(REAGENT_ID_NEUROTOXIN, 2))))

/transformation/chem/instant/luminol

CAPABILITIES(/transformation/chem/instant/luminol)
	configure(transformation(name = REAGENT_LUMINOL, id = REAGENT_ID_LUMINOL,
		takes = list(reagent(REAGENT_ID_HYDROGEN, 2), reagent(REAGENT_ID_CARBON, 2), reagent(REAGENT_ID_AMMONIA, 2)),
		makes = list(reagent(REAGENT_ID_LUMINOL, 6))))

/* Solidification */

/transformation/chem/instant/solidification
	var/sheet_to_give = /obj/item/stack/material/iron

CAPABILITIES(/transformation/chem/instant/solidification)
	configure(transformation(name = "Solid Iron", id = "solidiron",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_IRON, REAGENTS_PER_SHEET)), made = 1,
		then = TYPE_PROC_REF(/transformation/chem/instant/solidification, on_reaction)))

/transformation/chem/instant/solidification/proc/on_reaction(datum/reagents/holder, created_volume)
	var/sheets = FLOOR(created_volume,1)
	if(sheets)
		new sheet_to_give(get_turf(holder.my_atom), sheets)

/transformation/chem/instant/solidification/phoron
	sheet_to_give = /obj/item/stack/material/phoron

CAPABILITIES(/transformation/chem/instant/solidification/phoron)
	configure(transformation(name = "Solid Phoron", id = "solidphoron",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_PHORON, REAGENTS_PER_SHEET))))

/transformation/chem/instant/solidification/silver
	sheet_to_give = /obj/item/stack/material/silver

CAPABILITIES(/transformation/chem/instant/solidification/silver)
	configure(transformation(name = "Solid Silver", id = "solidsilver",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_SILVER, REAGENTS_PER_SHEET))))

/transformation/chem/instant/solidification/gold
	sheet_to_give = /obj/item/stack/material/gold

CAPABILITIES(/transformation/chem/instant/solidification/gold)
	configure(transformation(name = "Solid Gold", id = "solidgold",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_GOLD, REAGENTS_PER_SHEET))))

/transformation/chem/instant/solidification/platinum
	sheet_to_give = /obj/item/stack/material/platinum

CAPABILITIES(/transformation/chem/instant/solidification/platinum)
	configure(transformation(name = "Solid Platinum", id = "solidplatinum",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_PLATINUM, REAGENTS_PER_SHEET))))

/transformation/chem/instant/solidification/uranium
	sheet_to_give = /obj/item/stack/material/uranium

CAPABILITIES(/transformation/chem/instant/solidification/uranium)
	configure(transformation(name = "Solid Uranium", id = "soliduranium",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_URANIUM, REAGENTS_PER_SHEET))))

/transformation/chem/instant/solidification/hydrogen
	sheet_to_give = /obj/item/stack/material/mhydrogen

CAPABILITIES(/transformation/chem/instant/solidification/hydrogen)
	configure(transformation(name = "Solid Hydrogen", id = "solidhydrogen",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 100), reagent(REAGENT_ID_HYDROGEN, REAGENTS_PER_SHEET))))


// These are from Xenobio.
/transformation/chem/instant/solidification/steel
	sheet_to_give = /obj/item/stack/material/steel

CAPABILITIES(/transformation/chem/instant/solidification/steel)
	configure(transformation(name = "Solid Steel", id = "solidsteel",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 10), reagent(REAGENT_ID_IRON, REAGENTS_PER_SHEET), reagent(REAGENT_ID_CARBON, REAGENTS_PER_SHEET)),
		blocked_by = list(reagent(REAGENT_ID_PLATINUM, 1))))

/transformation/chem/instant/solidification/plasteel
	sheet_to_give = /obj/item/stack/material/plasteel

CAPABILITIES(/transformation/chem/instant/solidification/plasteel)
	configure(transformation(name = "Solid Plasteel", id = "solidplasteel",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 10), reagent(REAGENT_ID_IRON, REAGENTS_PER_SHEET), reagent(REAGENT_ID_CARBON, REAGENTS_PER_SHEET), reagent(REAGENT_ID_PLATINUM, REAGENTS_PER_SHEET))))

/transformation/chem/instant/plastication

CAPABILITIES(/transformation/chem/instant/plastication)
	configure(transformation(name = "Plastic", id = "solidplastic", takes = list(reagent(REAGENT_ID_PACID, 1), reagent(REAGENT_ID_PLASTICIDE, 2)),
		made = 1, then = TYPE_PROC_REF(/transformation/chem/instant/plastication, on_reaction)))

/transformation/chem/instant/plastication/proc/on_reaction(datum/reagents/holder, created_volume)
	var/sheets = FLOOR(created_volume,1)
	if(sheets)
		new /obj/item/stack/material/plastic(get_turf(holder.my_atom), sheets)

/transformation/chem/instant/soapification

CAPABILITIES(/transformation/chem/instant/soapification)
	configure(transformation(name = "Soapification", id = "soapification", takes = list(reagent(REAGENT_ID_COOKINGOIL, 10), reagent(REAGENT_ID_LYE, 2)),
		made = 1, then = TYPE_PROC_REF(/transformation/chem/instant/soapification, on_reaction)))

/transformation/chem/instant/soapification/proc/on_reaction(datum/reagents/holder, created_volume)
	for(var/i = 1, i <= created_volume, i++)
		new /obj/item/soap(get_turf(holder.my_atom))

/transformation/chem/instant/soapification/alt

CAPABILITIES(/transformation/chem/instant/soapification/alt)
	configure(transformation(name = "Soapification2", id = "soapification2", takes = list(reagent(REAGENT_ID_CORNOIL, 10), reagent(REAGENT_ID_LYE, 2))))

/transformation/chem/instant/soapification/gibs // a bit less convinient and grosser, but it makes more potent soap.

CAPABILITIES(/transformation/chem/instant/soapification/gibs)
	configure(transformation(name = "Soapification Gibs", id = "soapificationgibs",
		takes = list(reagent(REAGENT_ID_PROTEIN, 10), reagent(REAGENT_ID_LYE, 10)),
		then = TYPE_PROC_REF(/transformation/chem/instant/soapification/gibs, on_reaction)))

/transformation/chem/instant/soapification/gibs/on_reaction(datum/reagents/holder, created_volume)
	for(var/i = 1, i <= created_volume, i++)
		new /obj/item/soap/homemade(get_turf(holder.my_atom))

/*Carpet Creation*/

/transformation/chem/instant/carpetify
	var/carpet_type = /obj/item/stack/tile/carpet

CAPABILITIES(/transformation/chem/instant/carpetify)
	configure(transformation(name = "Carpet", id = "redcarpet", takes = list(reagent(REAGENT_ID_LIQUIDCARPET, 2), reagent(REAGENT_ID_PLASTICIDE, 1)),
		made = 2, then = TYPE_PROC_REF(/transformation/chem/instant/carpetify, on_reaction)))

/transformation/chem/instant/carpetify/proc/on_reaction(datum/reagents/holder, created_volume)
	var/sheets = FLOOR(created_volume,1)
	if(sheets)
		new carpet_type(get_turf(holder.my_atom), sheets)

/transformation/chem/instant/carpetify/bcarpet
	carpet_type = /obj/item/stack/tile/carpet/bcarpet

CAPABILITIES(/transformation/chem/instant/carpetify/bcarpet)
	configure(transformation(name = "Black Carpet", id = "blackcarpet",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPETB, 2), reagent(REAGENT_ID_PLASTICIDE, 1))))

/transformation/chem/instant/carpetify/blucarpet
	carpet_type = /obj/item/stack/tile/carpet/blucarpet

CAPABILITIES(/transformation/chem/instant/carpetify/blucarpet)
	configure(transformation(name = "Blue Carpet", id = "bluecarpet",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPETBLU, 2), reagent(REAGENT_ID_PLASTICIDE, 1))))

/transformation/chem/instant/carpetify/turcarpet
	carpet_type = /obj/item/stack/tile/carpet/turcarpet

CAPABILITIES(/transformation/chem/instant/carpetify/turcarpet)
	configure(transformation(name = "Turquise Carpet", id = "turcarpet",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPETTUR, 2), reagent(REAGENT_ID_PLASTICIDE, 1))))

/transformation/chem/instant/carpetify/sblucarpet
	carpet_type = /obj/item/stack/tile/carpet/sblucarpet

CAPABILITIES(/transformation/chem/instant/carpetify/sblucarpet)
	configure(transformation(name = "Silver Blue Carpet", id = "sblucarpet",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPETSBLU, 2), reagent(REAGENT_ID_PLASTICIDE, 1))))

/transformation/chem/instant/carpetify/clowncarpet
	carpet_type = /obj/item/stack/tile/carpet/gaycarpet

CAPABILITIES(/transformation/chem/instant/carpetify/clowncarpet)
	configure(transformation(name = "Clown Carpet", id = "clowncarpet",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPETC, 2), reagent(REAGENT_ID_PLASTICIDE, 1))))

/transformation/chem/instant/carpetify/pcarpet
	carpet_type = /obj/item/stack/tile/carpet/purcarpet

CAPABILITIES(/transformation/chem/instant/carpetify/pcarpet)
	configure(transformation(name = "Purple Carpet", id = "purplecarpet",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPETP, 2), reagent(REAGENT_ID_PLASTICIDE, 1))))

/transformation/chem/instant/carpetify/ocarpet
	carpet_type = /obj/item/stack/tile/carpet/oracarpet

CAPABILITIES(/transformation/chem/instant/carpetify/ocarpet)
	configure(transformation(name = "Orange Carpet", id = "orangecarpet",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPETO, 2), reagent(REAGENT_ID_PLASTICIDE, 1))))

/transformation/chem/instant/concrete

CAPABILITIES(/transformation/chem/instant/concrete)
	configure(transformation(name = "Concrete", id = "concretereagent",
		takes = list(reagent(REAGENT_ID_CALCIUM, 2), reagent(REAGENT_ID_SILICATE, 2), reagent(REAGENT_ID_WATER, 2)), made = 1,
		then = TYPE_PROC_REF(/transformation/chem/instant/concrete, on_reaction)))

/transformation/chem/instant/concrete/proc/on_reaction(datum/reagents/holder, created_volume)
	var/sheets = FLOOR(created_volume,1)
	if(sheets)
		new /obj/item/stack/material/concrete(get_turf(holder.my_atom), sheets)

/* Grenade reactions */

/transformation/chem/instant/explosion_potassium

CAPABILITIES(/transformation/chem/instant/explosion_potassium)
	configure(transformation(name = "Explosion", id = "explosion_potassium",
		takes = list(reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_POTASSIUM, 1)), made = 2, says = "",
		then = TYPE_PROC_REF(/transformation/chem/instant/explosion_potassium, on_reaction)))

/transformation/chem/instant/explosion_potassium/proc/on_reaction(datum/reagents/holder, created_volume)
	var/datum/effect/effect/system/reagents_explosion/e = new()
	e.set_up(round (created_volume/10, 1), holder.my_atom, 0, 0)
	if(isliving(holder.my_atom))
		e.amount *= 0.5
		var/mob/living/L = holder.my_atom
		if(L.stat != DEAD)
			e.amount *= 0.5
	else
		holder.clear_reagents() //No more powergaming by creating a tiny amount of this
	//VORESTation Add End
	e.start()
	// holder.clear_reagents() // Removal
	return

/transformation/chem/instant/flash_powder

CAPABILITIES(/transformation/chem/instant/flash_powder)
	configure(transformation(name = "Flash powder", id = "flash_powder",
		takes = list(reagent(REAGENT_ID_ALUMINIUM, 1), reagent(REAGENT_ID_POTASSIUM, 1), reagent(REAGENT_ID_SULFUR, 1)),
		then = TYPE_PROC_REF(/transformation/chem/instant/flash_powder, on_reaction)))

/transformation/chem/instant/flash_powder/proc/on_reaction(datum/reagents/holder, created_volume)
	var/location = get_turf(holder.my_atom)
	fx_sparks(location, 2)
	for(var/mob/living/carbon/M in viewers(world.view, location))
		switch(get_dist(M, location))
			if(0 to 3)
				if(ishuman(M))
					var/mob/living/carbon/human/target = M
					if(istype(target.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/sunglasses))
						continue

				M.flash_eyes()
				M.status_at_least(STAT_WEAKENED, 15)

			if(4 to 5)
				if(ishuman(M))
					var/mob/living/carbon/human/target = M
					if(istype(target.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/sunglasses))
						continue

				M.flash_eyes()
				M.status_at_least(STAT_STUNNED, 5)

/transformation/chem/instant/emp_pulse

CAPABILITIES(/transformation/chem/instant/emp_pulse)
	configure(transformation(name = "EMP Pulse", id = "emp_pulse", takes = list(reagent(REAGENT_ID_URANIUM, 1), reagent(REAGENT_ID_IRON, 1)), made = 2,
		then = TYPE_PROC_REF(/transformation/chem/instant/emp_pulse, on_reaction)))

/transformation/chem/instant/emp_pulse/proc/on_reaction(datum/reagents/holder, created_volume)
	var/location = get_turf(holder.my_atom)
	// 100 created volume = 4 heavy range & 7 light range. A few tiles smaller than traitor EMP grandes.
	// 200 created volume = 8 heavy range & 14 light range. 4 tiles larger than traitor EMP grenades.
	empulse(location, round(created_volume / 24), round(created_volume / 20), round(created_volume / 18), round(created_volume / 14), 1)
	if(!isliving(holder.my_atom)) //No more powergaming by creating a tiny amount of this
		holder.clear_reagents()
	return

/transformation/chem/instant/nitroglycerin

CAPABILITIES(/transformation/chem/instant/nitroglycerin)
	configure(transformation(name = REAGENT_NITROGLYCERIN, id = REAGENT_ID_NITROGLYCERIN,
		takes = list(reagent(REAGENT_ID_GLYCEROL, 1), reagent(REAGENT_ID_PACID, 1), reagent(REAGENT_ID_SACID, 1)),
		makes = list(reagent(REAGENT_ID_NITROGLYCERIN, 2)), important = TRUE,
		then = TYPE_PROC_REF(/transformation/chem/instant/nitroglycerin, on_reaction)))

// If it becomes possible to make this without exploding and clearing reagents, remove the UNIT_TESTS wrapper
/transformation/chem/instant/nitroglycerin/proc/on_reaction(datum/reagents/holder, created_volume)
#ifndef UNIT_TESTS
	var/datum/effect/effect/system/reagents_explosion/e = new()
	e.set_up(round (created_volume/2, 1), holder.my_atom, 0, 0)
	if(isliving(holder.my_atom))
		e.amount *= 0.5
		var/mob/living/L = holder.my_atom
		if(L.stat!=DEAD)
			e.amount *= 0.5
	else
		holder.clear_reagents() //No more powergaming by creating a tiny amount of this
	e.start()

	// holder.clear_reagents() // Removal
#endif
	return

/transformation/chem/instant/napalm

CAPABILITIES(/transformation/chem/instant/napalm)
	configure(transformation(name = "Napalm", id = "napalm",
		takes = list(reagent(REAGENT_ID_ALUMINIUM, 1), reagent(REAGENT_ID_PHORON, 1), reagent(REAGENT_ID_SACID, 1)), made = 1,
		then = TYPE_PROC_REF(/transformation/chem/instant/napalm, on_reaction)))

/transformation/chem/instant/napalm/proc/on_reaction(datum/reagents/holder, created_volume)
	var/turf/location = get_turf(holder.my_atom.loc)
	for(var/turf/simulated/floor/target_tile in range(0,location))
		target_tile.assume_gas(GAS_VOLATILE_FUEL, created_volume, 400+T0C)
		target_tile.hotspot_expose(700, 400)
	holder.del_reagent("napalm")
	return

/transformation/chem/instant/chemsmoke

CAPABILITIES(/transformation/chem/instant/chemsmoke)
	configure(transformation(name = "Chemsmoke", id = "chemsmoke",
		takes = list(reagent(REAGENT_ID_POTASSIUM, 1), reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_PHOSPHORUS, 1)),
		made = 0.4, then = TYPE_PROC_REF(/transformation/chem/instant/chemsmoke, on_reaction)))

/transformation/chem/instant/chemsmoke/proc/on_reaction(datum/reagents/holder, created_volume)
	var/location = get_turf(holder.my_atom)
	var/datum/effect/effect/system/smoke_spread/chem/S = new /datum/effect/effect/system/smoke_spread/chem
	S.attach(location)
	S.set_up(holder, created_volume, 0, location)
	play_sfx(location, SFX_EFFECTS_SMOKE)
	S.start()
	if(!isliving(holder.my_atom)) //No more powergaming by creating a tiny amount of this
		holder.clear_reagents()
	return

/transformation/chem/instant/foam

CAPABILITIES(/transformation/chem/instant/foam)
	configure(transformation(name = "Foam", id = "foam", takes = list(reagent(REAGENT_ID_FLUOROSURFACTANT, 1), reagent(REAGENT_ID_WATER, 1)), made = 2,
		says = "The solution violently bubbles!", then = TYPE_PROC_REF(/transformation/chem/instant/foam, on_reaction)))

/transformation/chem/instant/foam/proc/on_reaction(datum/reagents/holder, created_volume)
	var/location = get_turf(holder.my_atom)

	for(var/mob/M in viewers(5, location))
		to_chat(M, span_warning("The solution spews out foam!"))

	var/datum/effect/effect/system/foam_spread/s = new()
	s.set_up(created_volume, location, holder, 0)
	s.start()
	if(!isliving(holder.my_atom)) //No more powergaming by creating a tiny amount of this
		holder.clear_reagents()
	return

/transformation/chem/instant/metalfoam

CAPABILITIES(/transformation/chem/instant/metalfoam)
	configure(transformation(name = "Metal Foam", id = "metalfoam",
		takes = list(reagent(REAGENT_ID_ALUMINIUM, 3), reagent(REAGENT_ID_FOAMINGAGENT, 1), reagent(REAGENT_ID_PACID, 1)),
		made = 5, then = TYPE_PROC_REF(/transformation/chem/instant/metalfoam, on_reaction)))

/transformation/chem/instant/metalfoam/proc/on_reaction(datum/reagents/holder, created_volume)
	var/location = get_turf(holder.my_atom)

	for(var/mob/M in viewers(5, location))
		to_chat(M, span_warning("The solution spews out a metalic foam!"))

	var/datum/effect/effect/system/foam_spread/s = new()
	s.set_up(created_volume, location, holder, 1)
	s.start()
	return

/transformation/chem/instant/ironfoam

CAPABILITIES(/transformation/chem/instant/ironfoam)
	configure(transformation(name = "Iron Foam", id = "ironlfoam",
		takes = list(reagent(REAGENT_ID_IRON, 3), reagent(REAGENT_ID_FOAMINGAGENT, 1), reagent(REAGENT_ID_PACID, 1)), made = 5,
		then = TYPE_PROC_REF(/transformation/chem/instant/ironfoam, on_reaction)))

/transformation/chem/instant/ironfoam/proc/on_reaction(datum/reagents/holder, created_volume)
	var/location = get_turf(holder.my_atom)

	for(var/mob/M in viewers(5, location))
		to_chat(M, span_warning("The solution spews out a metalic foam!"))

	var/datum/effect/effect/system/foam_spread/s = new()
	s.set_up(created_volume, location, holder, 2)
	s.start()
	return

/* Paint */

/transformation/chem/instant/red_paint

CAPABILITIES(/transformation/chem/instant/red_paint)
	configure(transformation(name = "Red paint", id = "red_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKRED, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#FE191A"))

/transformation/chem/instant/orange_paint

CAPABILITIES(/transformation/chem/instant/orange_paint)
	configure(transformation(name = "Orange paint", id = "orange_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKORANGE, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#FFBE4F"))

/transformation/chem/instant/yellow_paint

CAPABILITIES(/transformation/chem/instant/yellow_paint)
	configure(transformation(name = "Yellow paint", id = "yellow_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKYELLOW, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#FDFE7D"))

/transformation/chem/instant/green_paint

CAPABILITIES(/transformation/chem/instant/green_paint)
	configure(transformation(name = "Green paint", id = "green_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKGREEN, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#18A31A"))

/transformation/chem/instant/blue_paint

CAPABILITIES(/transformation/chem/instant/blue_paint)
	configure(transformation(name = "Blue paint", id = "blue_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKBLUE, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#247CFF"))

/transformation/chem/instant/purple_paint

CAPABILITIES(/transformation/chem/instant/purple_paint)
	configure(transformation(name = "Purple paint", id = "purple_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKPURPLE, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#CC0099"))

/transformation/chem/instant/grey_paint //mime

CAPABILITIES(/transformation/chem/instant/grey_paint)
	configure(transformation(name = "Grey paint", id = "grey_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKGREY, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#808080"))

/transformation/chem/instant/brown_paint

CAPABILITIES(/transformation/chem/instant/brown_paint)
	configure(transformation(name = "Brown paint", id = "brown_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKBROWN, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#846F35"))

/transformation/chem/instant/blood_paint

CAPABILITIES(/transformation/chem/instant/blood_paint)
	configure(transformation(name = "Blood paint", id = "blood_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_BLOOD, 2)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), data_from = data_from_reagent(REAGENT_ID_BLOOD, "blood_colour", "#FE191A")))

/transformation/chem/instant/milk_paint

CAPABILITIES(/transformation/chem/instant/milk_paint)
	configure(transformation(name = "Milk paint", id = "milk_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MILK, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#F0F8FF"))

/transformation/chem/instant/orange_juice_paint

CAPABILITIES(/transformation/chem/instant/orange_juice_paint)
	configure(transformation(name = "Orange juice paint", id = "orange_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_ORANGEJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#E78108"))

/transformation/chem/instant/tomato_juice_paint

CAPABILITIES(/transformation/chem/instant/tomato_juice_paint)
	configure(transformation(name = "Tomato juice paint", id = "tomato_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_TOMATOJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#731008"))

/transformation/chem/instant/lime_juice_paint

CAPABILITIES(/transformation/chem/instant/lime_juice_paint)
	configure(transformation(name = "Lime juice paint", id = "lime_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_LIMEJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#365E30"))

/transformation/chem/instant/carrot_juice_paint

CAPABILITIES(/transformation/chem/instant/carrot_juice_paint)
	configure(transformation(name = "Carrot juice paint", id = "carrot_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_CARROTJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#973800"))

/transformation/chem/instant/berry_juice_paint

CAPABILITIES(/transformation/chem/instant/berry_juice_paint)
	configure(transformation(name = "Berry juice paint", id = "berry_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_BERRYJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#990066"))

/transformation/chem/instant/grape_juice_paint

CAPABILITIES(/transformation/chem/instant/grape_juice_paint)
	configure(transformation(name = "Grape juice paint", id = "grape_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_GRAPEJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#863333"))

/transformation/chem/instant/poisonberry_juice_paint

CAPABILITIES(/transformation/chem/instant/poisonberry_juice_paint)
	configure(transformation(name = "Poison berry juice paint", id = "poisonberry_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_POISONBERRYJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#863353"))

/transformation/chem/instant/watermelon_juice_paint

CAPABILITIES(/transformation/chem/instant/watermelon_juice_paint)
	configure(transformation(name = "Watermelon juice paint", id = "watermelon_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_WATERMELONJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#B83333"))

/transformation/chem/instant/lemon_juice_paint

CAPABILITIES(/transformation/chem/instant/lemon_juice_paint)
	configure(transformation(name = "Lemon juice paint", id = "lemon_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_LEMONJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#AFAF00"))

/transformation/chem/instant/banana_juice_paint

CAPABILITIES(/transformation/chem/instant/banana_juice_paint)
	configure(transformation(name = "Banana juice paint", id = "banana_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_BANANA, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#C3AF00"))

/transformation/chem/instant/potato_juice_paint

CAPABILITIES(/transformation/chem/instant/potato_juice_paint)
	configure(transformation(name = "Potato juice paint", id = "potato_juice_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_POTATOJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#302000"))

/transformation/chem/instant/carbon_paint

CAPABILITIES(/transformation/chem/instant/carbon_paint)
	configure(transformation(name = "Carbon paint", id = "carbon_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_CARBON, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#333333"))

/transformation/chem/instant/aluminum_paint

CAPABILITIES(/transformation/chem/instant/aluminum_paint)
	configure(transformation(name = "Aluminum paint", id = "aluminum_paint",
		takes = list(reagent(REAGENT_ID_PLASTICIDE, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_ALUMINIUM, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#F0F8FF"))


/*Carpet Recoloring*/
/transformation/chem/instant/carpetdye

CAPABILITIES(/transformation/chem/instant/carpetdye)
	configure(transformation(name = "Black Carpet Dyeing", id = "carpetdyeblack",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPET, 5), reagent(REAGENT_ID_CARBON, 1)),
		makes = list(reagent(REAGENT_ID_LIQUIDCARPETB, 5))))

/transformation/chem/instant/carpetdye/blue

CAPABILITIES(/transformation/chem/instant/carpetdye/blue)
	configure(transformation(name = "Blue Carpet Dyeing", id = "carpetdyeblue",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPET, 5), reagent(REAGENT_ID_FROSTOIL, 1)),
		makes = list(reagent(REAGENT_ID_LIQUIDCARPETBLU, 5))))

/transformation/chem/instant/carpetdye/tur

CAPABILITIES(/transformation/chem/instant/carpetdye/tur)
	configure(transformation(name = "Turqouise Carpet Dyeing", id = "carpetdyetur",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPET, 5), reagent(REAGENT_ID_WATER, 1)),
		makes = list(reagent(REAGENT_ID_LIQUIDCARPETTUR, 5))))

/transformation/chem/instant/carpetdye/sblu

CAPABILITIES(/transformation/chem/instant/carpetdye/sblu)
	configure(transformation(name = "Silver Blue Carpet Dyeing", id = "carpetdyesblu",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPET, 5), reagent(REAGENT_ID_ICE, 1)),
		makes = list(reagent(REAGENT_ID_LIQUIDCARPETSBLU, 5))))

/transformation/chem/instant/carpetdye/clown

CAPABILITIES(/transformation/chem/instant/carpetdye/clown)
	configure(transformation(name = "Clown Carpet Dyeing", id = "carpetdyeclown",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPET, 5), reagent(REAGENT_ID_BANANA, 1)),
		makes = list(reagent(REAGENT_ID_LIQUIDCARPETC, 5))))

/transformation/chem/instant/carpetdye/purple

CAPABILITIES(/transformation/chem/instant/carpetdye/purple)
	configure(transformation(name = "Purple Carpet Dyeing", id = "carpetdyepurple",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPET, 5), reagent(REAGENT_ID_BERRYJUICE, 1)),
		makes = list(reagent(REAGENT_ID_LIQUIDCARPETP, 5))))

/transformation/chem/instant/carpetdye/orange

CAPABILITIES(/transformation/chem/instant/carpetdye/orange)
	configure(transformation(name = "Orange Carpet Dyeing", id = "carpetdyeorange",
		takes = list(reagent(REAGENT_ID_LIQUIDCARPET, 5), reagent(REAGENT_ID_ORANGEJUICE, 1)),
		makes = list(reagent(REAGENT_ID_LIQUIDCARPETO, 5))))


//R-UST Port
/transformation/chem/instant/hydrophoron

CAPABILITIES(/transformation/chem/instant/hydrophoron)
	configure(transformation(name = REAGENT_HYDROPHORON, id = REAGENT_ID_HYDROPHORON,
		takes = list(reagent(REAGENT_ID_HYDROGEN, 1), reagent(REAGENT_ID_PHORON, 1)),
		blocked_by = list(reagent(REAGENT_ID_NITROGEN, 1), reagent(REAGENT_ID_COPPER, 1)),
		makes = list(reagent(REAGENT_ID_HYDROPHORON, 2))))

/transformation/chem/instant/deuterium

CAPABILITIES(/transformation/chem/instant/deuterium)
	configure(transformation(name = REAGENT_DEUTERIUM, id = REAGENT_ID_DEUTERIUM,
		takes = list(reagent(REAGENT_ID_HYDROPHORON, 1), reagent(REAGENT_ID_WATER, 2)),
		makes = list(reagent(REAGENT_ID_DEUTERIUM, 3))))

//Skrellian crap.
/transformation/chem/instant/talum_quem

CAPABILITIES(/transformation/chem/instant/talum_quem)
	configure(transformation(name = REAGENT_TALUMQUEM, id = REAGENT_ID_TALUMQUEM,
		takes = list(reagent(REAGENT_ID_BLISS, 2), reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_AMATOXIN, 1)),
		makes = list(reagent(REAGENT_ID_TALUMQUEM, 4))))

/transformation/chem/instant/qerr_quem

CAPABILITIES(/transformation/chem/instant/qerr_quem)
	configure(transformation(name = REAGENT_QERRQUEM, id = REAGENT_ID_QERRQUEM,
		takes = list(reagent(REAGENT_ID_NICOTINE, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_SUGAR, 2)),
		makes = list(reagent(REAGENT_ID_QERRQUEM, 4))))

/transformation/chem/instant/malish_qualem

CAPABILITIES(/transformation/chem/instant/malish_qualem)
	configure(transformation(name = REAGENT_MALISHQUALEM, id = REAGENT_ID_MALISHQUALEM,
		takes = list(reagent(REAGENT_ID_IMMUNOSUPRIZINE, 1), reagent(REAGENT_ID_QERRQUEM, 1), reagent(REAGENT_ID_INAPROVALINE, 1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), makes = list(reagent(REAGENT_ID_MALISHQUALEM, 2))))

// Biomass, for cloning and bioprinters
/transformation/chem/instant/biomass

CAPABILITIES(/transformation/chem/instant/biomass)
	configure(transformation(name = REAGENT_BIOMASS, id = REAGENT_ID_BIOMASS,
		takes = list(reagent(REAGENT_ID_PROTEIN, 1), reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_PHORON, 1)),
		makes = list(reagent(REAGENT_ID_BIOMASS, 6))))

// Neutralization.

/transformation/chem/instant/neutralize_neurotoxic_protein

CAPABILITIES(/transformation/chem/instant/neutralize_neurotoxic_protein)
	configure(transformation(name = "Neutralize Toxic Proteins", id = "neurotoxic_protein_neutral",
		takes = list(reagent(REAGENT_ID_ANTITOXIN, 1), reagent(REAGENT_ID_NEUROTOXIC_PROTEIN, 2)),
		makes = list(reagent(REAGENT_ID_PROTEIN, 2))))

/transformation/chem/instant/neutralize_carpotoxin

CAPABILITIES(/transformation/chem/instant/neutralize_carpotoxin)
	configure(transformation(name = "Neutralize Carpotoxin", id = "carpotoxin_neutral",
		takes = list(reagent(REAGENT_ID_ENZYME, 1), reagent(REAGENT_ID_CARPOTOXIN, 1), reagent(REAGENT_ID_SIFSAP, 1)),
		makes = list(reagent(REAGENT_ID_PROTEIN, 1))))

/transformation/chem/instant/neutralize_spidertoxin

CAPABILITIES(/transformation/chem/instant/neutralize_spidertoxin)
	configure(transformation(name = "Neutralize Spidertoxin", id = "spidertoxin_neutral",
		takes = list(reagent(REAGENT_ID_ENZYME, 1), reagent(REAGENT_ID_SPIDERTOXIN, 1), reagent(REAGENT_ID_SIFSAP, 1)),
		makes = list(reagent(REAGENT_ID_PROTEIN, 1))))

/transformation/chem/instant/artificial_sustenance

CAPABILITIES(/transformation/chem/instant/artificial_sustenance)
	configure(transformation(name = REAGENT_ASUSTENANCE, id = REAGENT_ID_ASUSTENANCE,
		takes = list(reagent(REAGENT_ID_NUTRIMENT, 1), reagent(REAGENT_ID_MUTAGEN, 1), reagent(REAGENT_ID_PHORON, 1)),
		makes = list(reagent(REAGENT_ID_ASUSTENANCE, 1))))

/transformation/chem/instant/titanium_oxidation

CAPABILITIES(/transformation/chem/instant/titanium_oxidation)
	configure(transformation(name = REAGENT_TITANIUMDIOX, id = "oxidize_titanium",
		takes = list(reagent(REAGENT_ID_TITANIUM, 1), reagent(REAGENT_ID_OXYGEN, 2)),
		makes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1))))

/* Metallic paints */
/transformation/chem/instant/metal_paint

CAPABILITIES(/transformation/chem/instant/metal_paint)
	configure(transformation(name = "Metallic white paint", id = "metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINK, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#b2d1da"))

/transformation/chem/instant/red_metal_paint

CAPABILITIES(/transformation/chem/instant/red_metal_paint)
	configure(transformation(name = "Metallic red paint", id = "red_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKRED, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#ff7a7a"))

/transformation/chem/instant/orange_metal_paint

CAPABILITIES(/transformation/chem/instant/orange_metal_paint)
	configure(transformation(name = "Metallic orange paint", id = "orange_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKORANGE, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#ffd690"))

/transformation/chem/instant/yellow_metal_paint

CAPABILITIES(/transformation/chem/instant/yellow_metal_paint)
	configure(transformation(name = "Metallic yellow paint", id = "yellow_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKYELLOW, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#ffffab"))

/transformation/chem/instant/green_metal_paint

CAPABILITIES(/transformation/chem/instant/green_metal_paint)
	configure(transformation(name = "Metallic green paint", id = "green_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKGREEN, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#69d76b"))

/transformation/chem/instant/blue_metal_paint

CAPABILITIES(/transformation/chem/instant/blue_metal_paint)
	configure(transformation(name = "Metallic blue paint", id = "blue_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKBLUE, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)), with_data = "#81aff5"))

/transformation/chem/instant/purple_metal_paint

CAPABILITIES(/transformation/chem/instant/purple_metal_paint)
	configure(transformation(name = "Metallic purple paint", id = "purple_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKPURPLE, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#e77acc"))

/transformation/chem/instant/brown_metal_paint

CAPABILITIES(/transformation/chem/instant/brown_metal_paint)
	configure(transformation(name = "Metallic brown paint", id = "brown_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_MARKERINKBROWN, 1)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#827655"))

/transformation/chem/instant/orange_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/orange_juice_metal_paint)
	configure(transformation(name = "Metallic orange juice paint", id = "orange_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_ORANGEJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#e2a254"))

/transformation/chem/instant/tomato_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/tomato_juice_metal_paint)
	configure(transformation(name = "Metallic tomato juice paint", id = "tomato_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_TOMATOJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#934e49"))

/transformation/chem/instant/lime_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/lime_juice_metal_paint)
	configure(transformation(name = "Metallic lime juice paint", id = "lime_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_LIMEJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#556c51"))

/transformation/chem/instant/carrot_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/carrot_juice_metal_paint)
	configure(transformation(name = "Metallic carrot juice paint", id = "carrot_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_CARROTJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#a06a4b"))

/transformation/chem/instant/berry_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/berry_juice_metal_paint)
	configure(transformation(name = "Metallic berry juice paint", id = "berry_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_BERRYJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#ae5892"))

/transformation/chem/instant/grape_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/grape_juice_metal_paint)
	configure(transformation(name = "Metallic grape juice paint", id = "grape_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_GRAPEJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#925e5e"))

/transformation/chem/instant/poisonberry_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/poisonberry_juice_metal_paint)
	configure(transformation(name = "Metallic poison berry juice paint", id = "poisonberry_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_POISONBERRYJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#683c4d"))

/transformation/chem/instant/watermelon_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/watermelon_juice_metal_paint)
	configure(transformation(name = "Metallic watermelon juice paint", id = "watermelon_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_WATERMELONJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#a47a7a"))

/transformation/chem/instant/lemon_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/lemon_juice_metal_paint)
	configure(transformation(name = "Metallic lemon juice paint", id = "lemon_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_LEMONJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#8f8f5c"))

/transformation/chem/instant/banana_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/banana_juice_metal_paint)
	configure(transformation(name = "Metallic banana juice paint", id = "banana_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_BANANA, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#9c9129"))

/transformation/chem/instant/potato_juice_metal_paint

CAPABILITIES(/transformation/chem/instant/potato_juice_metal_paint)
	configure(transformation(name = "Metallic potato juice paint", id = "potato_juice_metal_paint",
		takes = list(reagent(REAGENT_ID_TITANIUMDIOX, 1), reagent(REAGENT_ID_WATER, 3), reagent(REAGENT_ID_POTATOJUICE, 5)),
		makes = list(reagent(REAGENT_ID_PAINT, 5)),
		with_data = "#2e2a21"))

/transformation/chem/instant/aphrodisiac

CAPABILITIES(/transformation/chem/instant/aphrodisiac)
	configure(transformation(name = REAGENT_APHRODISIAC, id = REAGENT_ID_APHRODISIAC,
		takes = list(reagent(REAGENT_ID_CARBON, 2), reagent(REAGENT_ID_HYDROGEN, 2), reagent(REAGENT_ID_OXYGEN, 2), reagent(REAGENT_ID_WATER, 1)),
		makes = list(reagent(REAGENT_ID_APHRODISIAC, 6))))

/transformation/chem/instant/tercozolam

CAPABILITIES(/transformation/chem/instant/tercozolam)
	configure(transformation(id = REAGENT_ID_TERCOZOLAM,
		takes = list(reagent(REAGENT_ID_ANTITOXIN, 1), reagent(REAGENT_ID_ETHANOL, 1), reagent(REAGENT_ID_LITHIUM, 1)),
		makes = list(reagent(REAGENT_ID_TERCOZOLAM, 3))))


// === merged from instant_ch.dm during hard-fork de-suffix (verified no override-order change) ===
/transformation/chem/instant/claridyl

CAPABILITIES(/transformation/chem/instant/claridyl)
	configure(transformation(name = REAGENT_CLARIDYL, id = REAGENT_ID_CLARIDYL,
		takes = list(reagent(REAGENT_ID_LITHIUM, 1), reagent(REAGENT_ID_RADIUM, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_CLARIDYL, 1))))

/transformation/chem/instant/dyloteane

CAPABILITIES(/transformation/chem/instant/dyloteane)
	configure(transformation(name = REAGENT_DYLOTEANE, id = REAGENT_ID_DYLOTEANE,
		takes = list(reagent(REAGENT_ID_ANTITOXIN, 1), reagent(REAGENT_ID_TEA, 1)), makes = list(reagent(REAGENT_ID_DYLOTEANE, 1))))

/transformation/chem/instant/dyloteane/super

CAPABILITIES(/transformation/chem/instant/dyloteane/super)
	configure(transformation(name = "dyloteanesuper", id = "dyloteanesuper",
		takes = list(reagent(REAGENT_ID_ANTITOXIN, 1), reagent(REAGENT_ID_TEA, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_DYLOTEANE, 10))))

/transformation/chem/instant/eden

CAPABILITIES(/transformation/chem/instant/eden)
	configure(transformation(name = REAGENT_EDEN, id = REAGENT_ID_EDEN, takes = list(reagent(REAGENT_ID_ANTITOXIN, 60), reagent(REAGENT_ID_PHORON, 60)),
		makes = list(reagent(REAGENT_ID_EDEN, 1))))

/transformation/chem/instant/eden/snake

CAPABILITIES(/transformation/chem/instant/eden/snake)
	configure(transformation(id = REAGENT_ID_EDENSNAKE, takes = list(reagent(REAGENT_ID_EDEN, 1), reagent(REAGENT_ID_ETHANOL, 1)),
		makes = list(reagent(REAGENT_ID_EDENSNAKE, 1))))

/transformation/chem/instant/peridaxon_ch

CAPABILITIES(/transformation/chem/instant/peridaxon_ch)
	configure(transformation(name = REAGENT_PERIDAXON, id = "peridaxon_ch",
		takes = list(reagent(REAGENT_ID_CORDRADAXON, 1), reagent(REAGENT_ID_GASTIRODAXON, 1), reagent(REAGENT_ID_HEPANEPHRODAXON, 1), reagent(REAGENT_ID_RESPIRODAXON, 1)),
		makes = list(reagent(REAGENT_ID_PERIDAXON, 12))))

/transformation/chem/instant/sorbitol

CAPABILITIES(/transformation/chem/instant/sorbitol)
	configure(transformation(name = REAGENT_SORBITOL, id = REAGENT_ID_SORBITOL,
		takes = list(reagent(REAGENT_ID_UNSORBITOL, 1), reagent(REAGENT_ID_PHORON, 1)),
		makes = list(reagent(REAGENT_ID_SORBITOL, 2))))

/transformation/chem/instant/glucose

CAPABILITIES(/transformation/chem/instant/glucose)
	configure(transformation(name = REAGENT_GLUCOSE, id = REAGENT_ID_GLUCOSE,
		takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1), reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_GLUCOSE, 1))))
///SAP RECIPES//////

/transformation/chem/instant/myelamine_sap //This is the clotting agent used by clotting packs.

CAPABILITIES(/transformation/chem/instant/myelamine_sap)
	configure(transformation(name = REAGENT_MYELAMINE, id = REAGENT_ID_MYELAMINE + "sap",
		takes = list(reagent(REAGENT_ID_BICARIDINE, 1), reagent(REAGENT_ID_IRON, 2), reagent(REAGENT_ID_KELOTANE, 1), reagent(REAGENT_ID_BLUESAP, 1)),
		makes = list(reagent(REAGENT_ID_MYELAMINE, 1))))

/transformation/chem/instant/hannoa

CAPABILITIES(/transformation/chem/instant/hannoa)
	configure(transformation(name = REAGENT_HANNOA, id = REAGENT_ID_HANNOA,
		takes = list(reagent(REAGENT_PURPLESAP, 1), reagent(REAGENT_ID_IRON, 2), reagent(REAGENT_ID_KELOTANE, 1), reagent(REAGENT_ID_CARBON, 1)),
		makes = list(reagent(REAGENT_ID_HANNOA, 1))))

/transformation/chem/instant/bullvalene

CAPABILITIES(/transformation/chem/instant/bullvalene)
	configure(transformation(name = REAGENT_BULLVALENE, id = REAGENT_ID_BULLVALENE,
		takes = list(reagent(REAGENT_ID_DERMALINE, 1), reagent(REAGENT_ID_ORANGESAP, 1), reagent(REAGENT_ID_COPPER, 1)),
		makes = list(reagent(REAGENT_ID_BULLVALENE, 1))))

/transformation/chem/instant/nutrient

CAPABILITIES(/transformation/chem/instant/nutrient)
	configure(transformation(name = REAGENT_NUTRIMENT, id = REAGENT_ID_NUTRIMENT,
		takes = list(reagent(REAGENT_PURPLESAP, 1), reagent(REAGENT_ID_ORANGESAP, 1), reagent(REAGENT_ID_BLUESAP, 1)),
		catalysts = list(reagent(REAGENT_ID_WATER, 5)), makes = list(reagent(REAGENT_ID_NUTRIMENT, 3))))

/////SERAZINE RECIPES//////

/transformation/chem/instant/alizene

CAPABILITIES(/transformation/chem/instant/alizene)
	configure(transformation(name = REAGENT_ALIZENE, id = REAGENT_ID_ALIZENE,
		takes = list(reagent(REAGENT_ID_BICARIDINE, 1), reagent(REAGENT_ID_SERAZINE, 1), reagent(REAGENT_ID_TUNGSTEN, 1)),
		makes = list(reagent(REAGENT_ID_ALIZENE, 3))))

// Frost oil reactions for material sheets
/transformation/chem/instant/solidification/aluminium
	sheet_to_give = /obj/item/stack/material/aluminium

CAPABILITIES(/transformation/chem/instant/solidification/aluminium)
	configure(transformation(name = "Solid Aluminium", id = "solidaluminium",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_ALUMINIUM, REAGENTS_PER_SHEET))))

/transformation/chem/instant/solidification/copper
	sheet_to_give = /obj/item/stack/material/copper

CAPABILITIES(/transformation/chem/instant/solidification/copper)
	configure(transformation(name = "Solid Copper", id = "solidcopper",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_COPPER, REAGENTS_PER_SHEET))))

//YW stuff
/transformation/chem/instant/benzilate

CAPABILITIES(/transformation/chem/instant/benzilate)
	configure(transformation(name = "Benzilate", id = REAGENT_ID_BENZILATE,
		takes = list(reagent(REAGENT_ID_PARACETAMOL, 1), reagent(REAGENT_ID_MINDBREAKER, 1)),
		makes = list(reagent(REAGENT_ID_BENZILATE, 2))))

/transformation/chem/instant/phenethylamine

CAPABILITIES(/transformation/chem/instant/phenethylamine)
	configure(transformation(name = REAGENT_PHENETHYLAMINE, id = REAGENT_ID_PHENETHYLAMINE,
		takes = list(reagent(REAGENT_ID_PAROXETINE, 1), reagent(REAGENT_ID_BENZILATE, 1)),
		makes = list(reagent(REAGENT_ID_PHENETHYLAMINE, 2))))

// Xenochem stuff
/transformation/chem/instant/xenolazarus // Moved here because upstream axed it and this file cannot conflict

CAPABILITIES(/transformation/chem/instant/xenolazarus)
	configure(transformation(name = "Discount Lazarus", id = "discountlazarus",
		takes = list(reagent(REAGENT_ID_MONSTERTAMER, 5), reagent(REAGENT_ID_CLONEXADONE, 5)),
		then = TYPE_PROC_REF(/transformation/chem/instant/xenolazarus, on_reaction)))

/transformation/chem/instant/xenolazarus/proc/on_reaction(datum/reagents/holder, created_volume) //literally all this does is mash the regenerate button
	if(ishuman(holder.my_atom))
		var/mob/living/carbon/human/H = holder.my_atom
		var/datum/xenochimera/comp = H.get_xenochimera_state()
		if(!comp)
			return
		else
			if(H.stat == DEAD)
				if(H.hasnutriment()) // make sure it actually has the conditions to revive
					if(comp.revive_ready >= 1) // if it's not reviving, start doing so
						comp.revive_ready = REVIVING_READY
						COOLDOWN_RESET(comp, revive_cooldown) // overrides the normal cooldown
						act_message(H, null, others = span_info("%U% shudders briefly, then relaxes, faint movements stirring within."))
						comp.chimera_regenerate()
					else if(comp.revive_ready == REVIVING_DONE)// already reviving, check if they're ready to hatch
						comp.chimera_hatch()
						act_message(H, null, others = span_danger(span_huge("%U% violently convulses and then bursts open, revealing a new, intact copy in the pool of viscera."))) // Hope you were wearing waterproofs, doc...
						H.injure(INJURY_NEURAL, 10, source = holder.my_atom) // they're reviving from dead, so take 10 brain damage
					else //they're already reviving but haven't hatched. Give a little message to tell them to wait.
						act_message(H, null, others = span_info("%U% stirs faintly, but doesn't appear to be ready to wake up yet."))
				else
					act_message(H, null, others = span_info("%U% twitches for a moment, but remains still.")) // no nutriment


// === merged from instant_vr.dm during hard-fork de-suffix (verified no override-order change) ===
///////////////////////////////////////////////////////////////////////////////////
/// Micro/Macro chemicals

/transformation/chem/instant/sizeoxadone

CAPABILITIES(/transformation/chem/instant/sizeoxadone)
	configure(transformation(name = REAGENT_SIZEOXADONE, id = REAGENT_ID_SIZEOXADONE,
		takes = list(reagent(REAGENT_ID_SODIUM, 1), reagent(REAGENT_ID_TRAMADOL, 1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), makes = list(reagent(REAGENT_ID_SIZEOXADONE, 2))))

/transformation/chem/instant/macrocillin

CAPABILITIES(/transformation/chem/instant/macrocillin)
	// POLARISTODO requires_heating = 1
	configure(transformation(name = REAGENT_MACROCILLIN, id = REAGENT_ID_MACROCILLIN,
		takes = list(reagent(REAGENT_ID_SIZEOXADONE, 20), reagent(REAGENT_ID_DIETHYLAMINE, 20)),
		makes = list(reagent(REAGENT_ID_MACROCILLIN, 1))))

/transformation/chem/instant/microcillin

CAPABILITIES(/transformation/chem/instant/microcillin)
	// POLARISTODO requires_heating = 1
	configure(transformation(name = REAGENT_MICROCILLIN, id = REAGENT_ID_MICROCILLIN,
		takes = list(reagent(REAGENT_ID_SIZEOXADONE, 20), reagent(REAGENT_ID_SODIUMCHLORIDE, 20)),
		makes = list(reagent(REAGENT_ID_MICROCILLIN, 1))))

/transformation/chem/instant/normalcillin

CAPABILITIES(/transformation/chem/instant/normalcillin)
	// POLARISTODO requires_heating = 1
	configure(transformation(name = REAGENT_NORMALCILLIN, id = REAGENT_ID_NORMALCILLIN,
		takes = list(reagent(REAGENT_ID_SIZEOXADONE, 20), reagent(REAGENT_ID_LEPORAZINE, 20)),
		makes = list(reagent(REAGENT_ID_NORMALCILLIN, 1))))

/transformation/chem/instant/dontcrossthebeams

CAPABILITIES(/transformation/chem/instant/dontcrossthebeams)
	configure(transformation(name = "Don't Cross The Beams", id = "dontcrossthebeams",
		takes = list(reagent(REAGENT_ID_MICROCILLIN, 1), reagent(REAGENT_ID_MACROCILLIN, 1)),
		then = TYPE_PROC_REF(/transformation/chem/instant/dontcrossthebeams, on_reaction)))

/transformation/chem/instant/dontcrossthebeams/proc/on_reaction(datum/reagents/holder, created_volume)
	var/location = get_turf(holder.my_atom)
	play_sfx(location, SFX_WEAPONS_GAUSS_SHOOT)
#ifndef UNIT_TESTS
	// The pull keeps its timers and its record after it ends, which the end-of-run ownership audit reports as a leak: the pins settle this rule in a test world.
	var/datum/effect/effect/system/grav_pull/s = new /datum/effect/effect/system/grav_pull
	s.set_up(3, 3, location)
	s.start()
#endif
	holder.clear_reagents()

///////////////////////////////////////////////////////////////////////////////////
/// TF chemicals
/transformation/chem/instant/amorphorovir

CAPABILITIES(/transformation/chem/instant/amorphorovir)
	configure(transformation(name = REAGENT_AMORPHOROVIR, id = REAGENT_ID_AMORPHOROVIR,
		takes = list(reagent(REAGENT_ID_CRYPTOBIOLIN, 30), reagent(REAGENT_ID_BIOMASS, 30), reagent(REAGENT_ID_HYPERZINE, 20)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), makes = list(reagent(REAGENT_ID_AMORPHOROVIR, 1))))

/transformation/chem/instant/androrovir

CAPABILITIES(/transformation/chem/instant/androrovir)
	configure(transformation(name = REAGENT_ANDROROVIR, id = REAGENT_ID_ANDROROVIR,
		takes = list(reagent(REAGENT_ID_AMORPHOROVIR, 1), reagent(REAGENT_ID_BICARIDINE, 20), reagent(REAGENT_ID_IRON, 20), reagent(REAGENT_ID_ETHANOL, 20)),
		makes = list(reagent(REAGENT_ID_ANDROROVIR, 1))))

/transformation/chem/instant/gynorovir

CAPABILITIES(/transformation/chem/instant/gynorovir)
	configure(transformation(name = REAGENT_GYNOROVIR, id = REAGENT_ID_GYNOROVIR,
		takes = list(reagent(REAGENT_ID_AMORPHOROVIR, 1), reagent(REAGENT_ID_INAPROVALINE, 20), reagent(REAGENT_ID_SILICON, 20), reagent(REAGENT_ID_SUGAR, 20)),
		makes = list(reagent(REAGENT_ID_GYNOROVIR, 1))))

/transformation/chem/instant/androgynorovir

CAPABILITIES(/transformation/chem/instant/androgynorovir)
	configure(transformation(name = REAGENT_ANDROGYNOROVIR, id = REAGENT_ID_ANDROGYNOROVIR,
		takes = list(reagent(REAGENT_ID_AMORPHOROVIR, 1), reagent(REAGENT_ID_ANTITOXIN, 20), reagent(REAGENT_ID_FLUORINE, 20), reagent(REAGENT_ID_TUNGSTEN, 20)),
		makes = list(reagent(REAGENT_ID_ANDROGYNOROVIR, 1))))

/transformation/chem/instant/androrovir_bootleg

CAPABILITIES(/transformation/chem/instant/androrovir_bootleg)
	configure(transformation(name = "Bootleg Androrovir", id = "androrovir_bootleg",
		takes = list(reagent(REAGENT_ID_AMORPHOROVIR, 1), reagent(REAGENT_ID_PROTEIN, 10), reagent(REAGENT_ID_CAPSAICIN, 10)),
		makes = list(reagent(REAGENT_ID_ANDROROVIR, 1))))

/transformation/chem/instant/gynorovir_bootleg

CAPABILITIES(/transformation/chem/instant/gynorovir_bootleg)
	configure(transformation(name = "Bootleg Gynorovir", id = "gynorovir_bootleg",
		takes = list(reagent(REAGENT_ID_AMORPHOROVIR, 1), reagent(REAGENT_ID_SOYMILK, 10), reagent(REAGENT_ID_SUGAR, 10)),
		makes = list(reagent(REAGENT_ID_GYNOROVIR, 1))))

/transformation/chem/instant/androgynorovir_bootleg

CAPABILITIES(/transformation/chem/instant/androgynorovir_bootleg)
	configure(transformation(name = "Bootleg Androgynorovir", id = "androgynorovir_bootleg",
		takes = list(reagent(REAGENT_ID_AMORPHOROVIR, 1), reagent(REAGENT_ID_COLA, 10), reagent(REAGENT_ID_BERRYJUICE, 10)),
		makes = list(reagent(REAGENT_ID_ANDROGYNOROVIR, 1))))

///////////////////////////////////////////////////////////////////////////////////
/// Miscellaneous Reactions

/transformation/chem/instant/foam/softdrink

CAPABILITIES(/transformation/chem/instant/foam/softdrink)
	configure(transformation(name = "Decarbonated Drink", id = "soda_fizz", takes = list(reagent(REAGENT_ID_COLA, 1), reagent(REAGENT_ID_MINT, 1))))

/transformation/chem/instant/firefightingfoam //TODO: Make it so we can add this to the foam tanks to refill them

CAPABILITIES(/transformation/chem/instant/firefightingfoam)
	configure(transformation(name = REAGENT_FIREFOAM, id = "firefighting foam", takes = list(reagent(REAGENT_ID_WATER, 1)),
		catalysts = list(reagent(REAGENT_ID_FLUORINE, 10)), makes = list(reagent(REAGENT_ID_FIREFOAM, 1))))

/transformation/chem/instant/firefightingfoamqol //Please don't abuse this and make us remove it. Seriously.

CAPABILITIES(/transformation/chem/instant/firefightingfoamqol)
	configure(transformation(name = "Firefighting Foam EZ", id = "firefighting foam ez", takes = list(reagent(REAGENT_ID_WATER, 1)),
		catalysts = list(reagent(REAGENT_ID_FIREFOAM, 5)), blocked_by = list(reagent(REAGENT_ID_FLUORINE, 0.01)),
		makes = list(reagent(REAGENT_ID_FIREFOAM, 1))))

///////////////////////////////////////////////////////////////////////////////////
/// Vore Drugs

/transformation/chem/instant/ickypak

CAPABILITIES(/transformation/chem/instant/ickypak)
	configure(transformation(name = REAGENT_ICKYPAK, id = REAGENT_ID_ICKYPAK,
		takes = list(reagent(REAGENT_ID_HYPERZINE, 4), reagent(REAGENT_ID_FLUOROSURFACTANT, 1)),
		makes = list(reagent(REAGENT_ID_ICKYPAK, 5))))

/transformation/chem/instant/unsorbitol

CAPABILITIES(/transformation/chem/instant/unsorbitol)
	configure(transformation(name = REAGENT_UNSORBITOL, id = REAGENT_ID_UNSORBITOL,
		takes = list(reagent(REAGENT_ID_MUTAGEN, 3), reagent(REAGENT_ID_LIPOZINE, 2)),
		makes = list(reagent(REAGENT_ID_UNSORBITOL, 5))))

///////////////////////////////////////////////////////////////////////////////////
/// Other Drugs
/transformation/chem/instant/adranol

CAPABILITIES(/transformation/chem/instant/adranol)
	configure(transformation(name = REAGENT_ADRANOL, id = REAGENT_ID_ADRANOL,
		takes = list(reagent(REAGENT_ID_MILK, 2), reagent(REAGENT_ID_HYDROGEN, 1), reagent(REAGENT_ID_POTASSIUM, 1)),
		makes = list(reagent(REAGENT_ID_ADRANOL, 3))))

/transformation/chem/instant/vermicetol

CAPABILITIES(/transformation/chem/instant/vermicetol)
	configure(transformation(name = REAGENT_VERMICETOL, id = REAGENT_ID_VERMICETOL,
		takes = list(reagent(REAGENT_ID_KELOTANE, 1), reagent(REAGENT_ID_DERMALINE, 1), reagent(REAGENT_ID_SHOCKCHEM, 1), reagent(REAGENT_ID_PHORON, 0.1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), makes = list(reagent(REAGENT_ID_VERMICETOL, 3))))

/transformation/chem/instant/prussian_blue

CAPABILITIES(/transformation/chem/instant/prussian_blue)
	configure(transformation(name = REAGENT_PRUSSIANBLUE, id = REAGENT_ID_PRUSSIANBLUE,
		takes = list(reagent(REAGENT_ID_CARBON, 3), reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_NITROGEN, 3)),
		makes = list(reagent(REAGENT_ID_PRUSSIANBLUE, 7))))

/transformation/chem/instant/lipozilase

CAPABILITIES(/transformation/chem/instant/lipozilase)
	configure(transformation(name = REAGENT_LIPOZILASE, id = REAGENT_ID_LIPOZILASE,
		takes = list(reagent(REAGENT_ID_LIPOZINE, 1), reagent(REAGENT_ID_DIETHYLAMINE, 1)),
		makes = list(reagent(REAGENT_ID_LIPOZILASE, 2))))

/transformation/chem/instant/lipostipo

CAPABILITIES(/transformation/chem/instant/lipostipo)
	configure(transformation(name = REAGENT_LIPOSTIPO, id = REAGENT_ID_LIPOSTIPO,
		takes = list(reagent(REAGENT_ID_LIPOZINE, 1), reagent(REAGENT_ID_NUTRIMENT, 1), reagent(REAGENT_ID_FLUORINE, 1)),
		makes = list(reagent(REAGENT_ID_LIPOSTIPO, 3))))

///////////////////////////////////////////////////////////////////////////////////
/// Reagent colonies.
/transformation/chem/instant/meatcolony

CAPABILITIES(/transformation/chem/instant/meatcolony)
	configure(transformation(name = REAGENT_ID_PROTEIN, id = REAGENT_ID_MEATCOLONY,
		takes = list(reagent(REAGENT_ID_MEATCOLONY, 5), reagent(REAGENT_ID_VIRUSFOOD, 5)),
		makes = list(reagent(REAGENT_ID_PROTEIN, 60))))

/transformation/chem/instant/plantcolony

CAPABILITIES(/transformation/chem/instant/plantcolony)
	configure(transformation(name = REAGENT_ID_NUTRIMENT, id = REAGENT_ID_PLANTCOLONY,
		takes = list(reagent(REAGENT_ID_PLANTCOLONY, 5), reagent(REAGENT_ID_VIRUSFOOD, 5)),
		makes = list(reagent(REAGENT_ID_NUTRIMENT, 60))))

///////////////////////////////////////////////////////////////////////////////////
/// Upstream Adjustments
///////////////////////////////
//SLIME-RELATED BELOW HERE///////
///////////////////////////////
/transformation/chem/instant/slimeify

CAPABILITIES(/transformation/chem/instant/slimeify)
	configure(transformation(name = REAGENT_ADVMUTATIONTOXIN, id = "advmutationtoxin2",
		takes = list(reagent(REAGENT_ID_PHORON, 15), reagent(REAGENT_ID_SLIMEJELLY, 15), reagent(REAGENT_ID_MUTATIONTOXIN, 15)),
		makes = list(reagent(REAGENT_ID_ADVMUTATIONTOXIN, 1))))


// === merged from instant_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
//Chemist update
/transformation/chem/instant/livingagent

CAPABILITIES(/transformation/chem/instant/livingagent)
	configure(transformation(name = REAGENT_LIVINGAGENT, id = REAGENT_ID_LIVINGAGENT,
		takes = list(reagent(REAGENT_ID_TRICORDRAZINE, 1), reagent(REAGENT_ID_LIQUIDLIFE, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_LIVINGAGENT, 2))))

/transformation/chem/instant/performancepeaker

CAPABILITIES(/transformation/chem/instant/performancepeaker)
	configure(transformation(name = REAGENT_PERFORMANCEPEAKER, id = REAGENT_ID_PERFORMANCEPEAKER,
		takes = list(reagent(REAGENT_ID_HYPERZINE, 1), reagent(REAGENT_ID_LIQUIDLIFE, 1), reagent(REAGENT_ID_INAPROVALINE, 1)),
		makes = list(reagent(REAGENT_ID_PERFORMANCEPEAKER, 2))))

/transformation/chem/instant/burncard

CAPABILITIES(/transformation/chem/instant/burncard)
	configure(transformation(name = "Burning Bicard", id = REAGENT_ID_BURNCARD,
		takes = list(reagent(REAGENT_ID_LIQUIDFIRE, 1), reagent(REAGENT_ID_BICARIDINE, 1), reagent(REAGENT_ID_OXYGEN, 1)),
		makes = list(reagent(REAGENT_ID_BURNCARD, 2))))

/transformation/chem/instant/flamecure

CAPABILITIES(/transformation/chem/instant/flamecure)
	configure(transformation(name = REAGENT_FLAMECURE, id = REAGENT_ID_FLAMECURE,
		takes = list(reagent(REAGENT_ID_LIQUIDFIRE, 1), reagent(REAGENT_ID_MYELAMINE, 1), reagent(REAGENT_ID_KELOTANE, 1)),
		makes = list(reagent(REAGENT_ID_FLAMECURE, 2))))

/transformation/chem/instant/neotane

CAPABILITIES(/transformation/chem/instant/neotane)
	configure(transformation(name = REAGENT_NEOTANE, id = REAGENT_ID_NEOTANE,
		takes = list(reagent(REAGENT_ID_LIQUIDFIRE, 1), reagent(REAGENT_ID_KELOTANE, 1), reagent(REAGENT_ID_IRON, 1)),
		makes = list(reagent(REAGENT_ID_NEOTANE, 2))))

/transformation/chem/instant/bloodsealer

CAPABILITIES(/transformation/chem/instant/bloodsealer)
	configure(transformation(name = REAGENT_BLOODSEALER, id = REAGENT_ID_BLOODSEALER,
		takes = list(reagent(REAGENT_ID_NEOLIQUIDFIRE, 1), reagent(REAGENT_ID_GLUCOSE, 1), reagent(REAGENT_ID_HYDROGEN, 1)),
		makes = list(reagent(REAGENT_ID_BLOODSEALER, 2))))

/transformation/chem/instant/purifyingagent

CAPABILITIES(/transformation/chem/instant/purifyingagent)
	configure(transformation(name = REAGENT_PURIFYINGAGENT, id = REAGENT_ID_PURIFYINGAGENT,
		takes = list(reagent(REAGENT_ID_DEATHBLOOD, 1), reagent(REAGENT_ID_CARTHATOLINE, 1), reagent(REAGENT_ID_HYRONALIN, 1)),
		makes = list(reagent(REAGENT_ID_PURIFYINGAGENT, 2))))

/transformation/chem/instant/cleansingagent

CAPABILITIES(/transformation/chem/instant/cleansingagent)
	configure(transformation(name = REAGENT_CLEANSINGAGENT, id = REAGENT_ID_CLEANSINGAGENT,
		takes = list(reagent(REAGENT_ID_DEATHBLOOD, 1), reagent(REAGENT_ID_HYRONALIN, 1), reagent(REAGENT_ID_ANTITOXIN, 1)),
		makes = list(reagent(REAGENT_ID_CLEANSINGAGENT, 2))))

//tier 1
/transformation/chem/instant/souldew

CAPABILITIES(/transformation/chem/instant/souldew)
	configure(transformation(name = REAGENT_ID_SOULDEW, id = REAGENT_ID_SOULDEW,
		takes = list(reagent(REAGENT_ID_ALKYSINE, 1), reagent(REAGENT_ID_TRICORDRAZINE, 1), reagent(REAGENT_ID_SULFUR, 1)),
		makes = list(reagent(REAGENT_ID_SOULDEW, 3))))

/transformation/chem/instant/quadcord

CAPABILITIES(/transformation/chem/instant/quadcord)
	configure(transformation(name = REAGENT_QUADCORD, id = REAGENT_ID_QUADCORD,
		takes = list(reagent(REAGENT_ID_TRICORDRAZINE, 1), reagent(REAGENT_ID_PHORON, 1), reagent(REAGENT_ID_SACID, 1)),
		makes = list(reagent(REAGENT_ID_QUADCORD, 3))))

//tier 2
/*
/transformation/chem/instant/juggernog

CAPABILITIES(/transformation/chem/instant/juggernog)
	configure(transformation(name = REAGENT_JUGGERNOG, id = REAGENT_ID_JUGGERNOG,
		takes = list(reagent(REAGENT_ID_PARACETAMOL, 1), reagent(REAGENT_ID_TRAMADOL, 1), reagent(REAGENT_ID_SYNAPTIZINE, 1), reagent(REAGENT_ID_MERCURY, 1)),
		makes = list(reagent(REAGENT_ID_JUGGERNOG, 4))))
*/

/transformation/chem/instant/curea

CAPABILITIES(/transformation/chem/instant/curea)
	configure(transformation(name = REAGENT_CUREA, id = REAGENT_ID_CUREA,
		takes = list(reagent(REAGENT_ID_SPACEACILLIN, 1), reagent(REAGENT_ID_ADRANOL, 1), reagent(REAGENT_ID_INAPROVALINE, 1), reagent(REAGENT_ID_IRON, 1)),
		makes = list(reagent(REAGENT_ID_CUREA, 4))))

//tier 3
/transformation/chem/instant/liquidhealer

CAPABILITIES(/transformation/chem/instant/liquidhealer)
	configure(transformation(name = REAGENT_LIQUIDHEALER, id = REAGENT_ID_LIQUIDHEALER,
		takes = list(reagent(REAGENT_ID_BICARIDINE, 1), reagent(REAGENT_ID_KELOTANE, 1), reagent(REAGENT_ID_LIQUIDLIFE, 1), reagent(REAGENT_ID_CARPOTOXIN, 1), reagent(REAGENT_ID_QUADCORD, 1), reagent(REAGENT_ID_CRYPTOBIOLIN, 1)),
		makes = list(reagent(REAGENT_ID_LIQUIDHEALER, 6))))
/*
/transformation/chem/instant/phoenixbreath

CAPABILITIES(/transformation/chem/instant/phoenixbreath)
	configure(transformation(name = REAGENT_PHOENIXBREATH, id = REAGENT_ID_PHOENIXBREATH,
		takes = list(reagent(REAGENT_ID_VERMICETOL, 1), reagent(REAGENT_ID_LIQUIDLIFE, 1), reagent(REAGENT_ID_NEOLIQUIDFIRE, 1), reagent(REAGENT_ID_SOULDEW, 1), reagent(REAGENT_ID_PHORON, 1), reagent(REAGENT_ID_DERMALINE, 1)),
		makes = list(reagent(REAGENT_ID_PHOENIXBREATH, 6))))
*/
/transformation/chem/instant/dryagent

CAPABILITIES(/transformation/chem/instant/dryagent)
	configure(transformation(name = REAGENT_DRYAGENT, id = REAGENT_ID_DRYAGENT,
		takes = list(reagent(REAGENT_ID_ETHANOL, 2), reagent(REAGENT_ID_SODIUM, 2), reagent(REAGENT_ID_PHORON, 0.1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), makes = list(reagent(REAGENT_ID_DRYAGENT, 4))))

//Xenobotany update
/transformation/chem/instant/neoliquidfire

CAPABILITIES(/transformation/chem/instant/neoliquidfire)
	configure(transformation(name = REAGENT_ID_NEOLIQUIDFIRE, id = REAGENT_ID_NEOLIQUIDFIRE,
		takes = list(reagent(REAGENT_ID_LIQUIDFIRE, 1), reagent(REAGENT_ID_SULFUR, 1), reagent(REAGENT_ID_PHORON, 0.1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), makes = list(reagent(REAGENT_ID_NEOLIQUIDFIRE, 1))))

//Some extra metal solidification reactions
/transformation/chem/instant/solidification/deuterium
	sheet_to_give = /obj/item/stack/material/deuterium

CAPABILITIES(/transformation/chem/instant/solidification/deuterium)
	configure(transformation(name = "Solid Deuterium", id = "soliddeuterium",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 5), reagent(REAGENT_ID_DEUTERIUM, REAGENTS_PER_SHEET))))

//Injectable toxin reactions
/transformation/chem/instant/succubi_paralize

CAPABILITIES(/transformation/chem/instant/succubi_paralize)
	configure(transformation(name = "paralyzingfluid", id = "paralyzingfluid",
		takes = list(reagent(REAGENT_ID_BENZILATE, 1), reagent(REAGENT_ID_CRYPTOBIOLIN, 1)),
		makes = list(reagent("succubi_paralize", 2))))

/transformation/chem/instant/numbingenzyme

CAPABILITIES(/transformation/chem/instant/numbingenzyme)
	configure(transformation(name = "numbingenzyme", id = "numbingenzyme",
		takes = list(reagent(REAGENT_ID_TRAMADOL, 1), reagent(REAGENT_ID_PROTEIN, 2), reagent(REAGENT_ID_ADRANOL, 1)),
		makes = list(reagent(REAGENT_ID_NUMBENZYME, 4))))
