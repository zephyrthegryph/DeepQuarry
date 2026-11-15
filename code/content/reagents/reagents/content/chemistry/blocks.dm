// The building blocks, the intermediates and the process chemicals of the chemistry (doc/rewrite/proposals/chemistry_recipes.md sections 0 and 0b): what the stocked
// bottles hold and what a route passes through. Each has a block structure (code/content/reagents/blocks/structures.dm) and a boiling point (boiling_points.dm).

/// A chemistry building block with no effect of its own worth the name.
/datum/reagent/chem_block
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/acid/chem_hydrochloric
	name = REAGENT_HYDROCHLORIC
	id = REAGENT_ID_HYDROCHLORIC
	description = "Hydrochloric acid. It is what a halogenation gives off, and what a chlorine and a hydrogen make; lye neutralises it into table salt."
	taste_description = "sharp acid"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#E8EFB0"
	power = 4
	meltdose = 15
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/acid/chem_nitricacid
	name = REAGENT_NITRICACID
	id = REAGENT_ID_NITRICACID
	description = "Nitric acid: the nitrating half of a nitration, and a strong oxidiser. It eats flesh and most metals."
	taste_description = "acrid acid"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#E3C05A"
	power = 7
	meltdose = 6
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/acid/chem_phosphoricacid
	name = REAGENT_PHOSPHORICACID
	id = REAGENT_ID_PHOSPHORICACID
	description = "Phosphoric acid: a mild mineral acid, the phosphate behind fertiliser and the phosphorylation of a hydroxyl."
	taste_description = "sour acid"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#D8E0D0"
	power = 2
	meltdose = 25
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/acid/chem_aceticacid
	name = REAGENT_ACETICACID
	id = REAGENT_ID_ACETICACID
	description = "Acetic acid, vinegar at full strength: a short chain with a carboxyl. It joins with an amine or a hydroxyl in a condensation."
	taste_description = "vinegar"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#F0F0E0"
	power = 0.6
	meltdose = 40
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/acid/chem_nitratingmix
	name = REAGENT_NITRATINGMIX
	id = REAGENT_ID_NITRATINGMIX
	description = "Nitric and sulphuric acid mixed: a nitration in a bottle. It needs no other acid, leaves acid residue, and makes nitrosamine of an amine."
	taste_description = "burning acid"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#E0A040"
	power = 9
	meltdose = 3
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/chem_block/woodaldehyde
	name = REAGENT_WOODALDEHYDE
	id = REAGENT_ID_WOODALDEHYDE
	description = "The aldehyde of wood: a ring with a hydroxyl and a carbonyl, from the lignin of pulp. It smells of vanilla."
	taste_description = "vanilla"
	reagent_state = LIQUID
	color = "#F4E6C8"

/datum/reagent/chem_block/salicylicacid
	name = REAGENT_SALICYLICACID
	id = REAGENT_ID_SALICYLICACID
	description = "Salicylic acid: a ring with a hydroxyl and a carboxyl, from willow bark and aloe. The base of the trauma drugs and of the aspirin family."
	taste_description = "bitter"
	reagent_state = SOLID
	color = "#F2F2F2"

/datum/reagent/chem_block/fattyacid
	name = REAGENT_FATTYACID
	id = REAGENT_ID_FATTYACID
	description = "A long chain with a carboxyl: what fat and oil give when lye splits them. Soap is its sodium salt."
	taste_description = "waxy"
	reagent_state = LIQUID
	color = "#F2E8B8"

/datum/reagent/chem_block/aminoacid
	name = REAGENT_AMINOACID
	id = REAGENT_ID_AMINOACID
	description = "An amino acid: a core with an amine and a carboxyl. What protein, collagen and venom give when they are hydrolysed."
	taste_description = "savoury"
	reagent_state = SOLID
	color = "#EAD8C0"

/datum/reagent/chem_block/sterol
	name = REAGENT_STEROL
	id = REAGENT_ID_STEROL
	description = "A sterol: a steroid with a hydroxyl, from organs, blood, eggs and mushrooms."
	taste_description = "fatty"
	reagent_state = SOLID
	color = "#F0E8D0"

/datum/reagent/chem_block/sand
	name = REAGENT_SAND
	id = REAGENT_ID_SAND
	description = "Fine silica. In hot lye it goes into solution as silicate."
	taste_description = "grit"
	reagent_state = SOLID
	color = "#E6D3A0"

/datum/reagent/chem_block/alkaloidacid
	name = REAGENT_ALKALOIDACID
	id = REAGENT_ID_ALKALOIDACID
	description = "The acid of a plant alkaloid: a double ring with an amine and a carboxyl. A step on the way to the mind drugs."
	taste_description = "bitter"
	reagent_state = SOLID
	color = "#D8C8E0"

/datum/reagent/chem_block/scavengerresin
	name = REAGENT_SCAVENGERRESIN
	id = REAGENT_ID_SCAVENGERRESIN
	description = "Scavenger resin: ground sorbent. It takes one contaminant out of a mixture for each unit of resin, and leaves inert filler."
	taste_description = "chalk"
	reagent_state = SOLID
	color = "#B8A890"

/datum/reagent/toxin/chem_phenol
	name = REAGENT_PHENOL
	id = REAGENT_ID_PHENOL
	description = "Phenol: a ring with a hydroxyl, from wood tar and coal. It burns skin and is the start of the antiseptics."
	taste_description = "medicinal"
	reagent_state = LIQUID
	color = "#E8D8D0"
	strength = 3

/datum/reagent/toxin/chem_bleach
	name = REAGENT_BLEACH
	id = REAGENT_ID_BLEACH
	description = "Bleach: sodium hypochlorite. It oxidises and chlorinates in one step, and leaves a halide; warm, on a ring, it leaves dioxin."
	taste_description = "chlorine"
	reagent_state = LIQUID
	color = "#F0F4D0"
	strength = 3

/datum/reagent/toxin/chem_sodaash
	name = REAGENT_SODAASH
	id = REAGENT_ID_SODAASH
	description = "Soda ash: sodium carbonate, from wood ash or lye and carbon dioxide. A base that neutralises acid."
	taste_description = "alkaline"
	reagent_state = SOLID
	color = "#F4F4F4"
	strength = 1.5

/datum/reagent/toxin/chem_pyridine
	name = REAGENT_PYRIDINE
	id = REAGENT_ID_PYRIDINE
	description = "Pyridine base: a nitrogen ring, from tobacco, coffee and bone tar."
	taste_description = "fish"
	reagent_state = LIQUID
	color = "#E0DCC8"
	strength = 2

/datum/reagent/toxin/chem_alkaloid
	name = REAGENT_ALKALOID
	id = REAGENT_ID_ALKALOID
	description = "Plant alkaloid base: a double ring with an amine, from poppy, ambrosia and mould."
	taste_description = "bitter"
	reagent_state = LIQUID
	color = "#C8B8D8"
	strength = 2

/datum/reagent/toxin/chem_ironsalt
	name = REAGENT_IRONSALT
	id = REAGENT_ID_IRONSALT
	description = "Iron salt: iron sulfate, what iron and sulphuric acid make. Iron on a molecule comes out of it."
	taste_description = "metallic"
	reagent_state = SOLID
	color = "#9AB08A"
	strength = 1

/datum/reagent/toxin/chem_coppersalt
	name = REAGENT_COPPERSALT
	id = REAGENT_ID_COPPERSALT
	description = "Copper salt: copper sulfate. Copper on a molecule comes out of it, and so does a poisoning."
	taste_description = "metallic"
	reagent_state = SOLID
	color = "#3A8FB0"
	strength = 3

/datum/reagent/toxin/chem_lithiumsalt
	name = REAGENT_LITHIUMSALT
	id = REAGENT_ID_LITHIUMSALT
	description = "Lithium salt: lithium chloride. Lithium on a molecule comes out of it."
	taste_description = "salty"
	reagent_state = SOLID
	color = "#E8E8EC"
	strength = 1

/datum/reagent/toxin/chem_chlorohydrin
	name = REAGENT_CHLOROHYDRIN
	id = REAGENT_ID_CHLOROHYDRIN
	description = "Chlorohydrin: a short chain with two hydroxyls and a halide, what a halogenated glycerol is. An intermediate: ammonia makes an amine of it, sulfur a thiol."
	taste_description = "sweet"
	reagent_state = LIQUID
	color = "#E4E0B0"
	strength = 4

/datum/reagent/toxin/chem_nitrosalicylic
	name = REAGENT_NITROSALICYLIC
	id = REAGENT_ID_NITROSALICYLIC
	description = "Nitrosalicylic acid: salicylic acid with a nitro. An intermediate: hydrogen turns the nitro into an amine."
	taste_description = "bitter"
	reagent_state = SOLID
	color = "#E8D060"
	strength = 2

/datum/reagent/toxin/chem_chlorophoron
	name = REAGENT_CHLOROPHORON
	id = REAGENT_ID_CHLOROPHORON
	description = "Chlorophoron: a phoron lattice with a halide. An intermediate: ammonia makes an amine of it, potassium chloride a metal-bound salt."
	taste_description = "metallic"
	reagent_state = LIQUID
	color = "#B070D0"
	strength = 6

/datum/reagent/toxin/chem_pyridone
	name = REAGENT_PYRIDONE
	id = REAGENT_ID_PYRIDONE
	description = "Pyridone: a nitrogen ring with a carbonyl. An intermediate: ammonia and hydrogen make an amine of it."
	taste_description = "fish"
	reagent_state = SOLID
	color = "#E4E0C8"
	strength = 1.5

/datum/reagent/toxin/chem_halospaceacillin
	name = REAGENT_HALOSPACEACILLIN
	id = REAGENT_ID_HALOSPACEACILLIN
	description = "Spaceacillin with a halide hung on it. An intermediate: sulfur makes a thiol of it."
	taste_description = "medicinal"
	reagent_state = LIQUID
	color = "#D8E8C0"
	strength = 2

/datum/reagent/toxin/chem_hydride
	name = REAGENT_HYDRIDE
	id = REAGENT_ID_HYDRIDE
	description = "Hydride: a strong reducer. Poured in, it reduces every group it can reach with no hydrogen and no metal sheet, and leaves base residue and boron salts. It burns."
	taste_description = "caustic"
	reagent_state = SOLID
	color = "#C8C8D8"
	strength = 5

/datum/reagent/toxin/chem_strongoxidiser
	name = REAGENT_STRONGOXIDISER
	id = REAGENT_ID_STRONGOXIDISER
	description = "A permanganate-type oxidiser: it takes a hydroxyl all the way to a carboxyl and burns what else it finds. It leaves heavy metals."
	taste_description = "metallic"
	reagent_state = SOLID
	color = "#7A1A6A"
	strength = 6

/datum/reagent/toxin/chem_chlorinatingagent
	name = REAGENT_CHLORINATINGAGENT
	id = REAGENT_ID_CHLORINATINGAGENT
	description = "A chlorinating agent: it takes a hydroxyl for a halide without chlorine gas. It leaves hydrochloric acid and sulfur."
	taste_description = "sulfurous"
	reagent_state = LIQUID
	color = "#E0E090"
	strength = 5

/datum/reagent/toxin/chem_couplingagent
	name = REAGENT_COUPLINGAGENT
	id = REAGENT_ID_COUPLINGAGENT
	description = "A coupling agent: it joins a carboxyl to a hydroxyl or an amine at a warm bath, with no drying. It leaves organic residue."
	taste_description = "bitter"
	reagent_state = LIQUID
	color = "#D0D8E0"
	strength = 3

/datum/reagent/toxin/chem_causticdigest
	name = REAGENT_CAUSTICDIGEST
	id = REAGENT_ID_CAUSTICDIGEST
	description = "Caustic digest: hot lye. It hydrolyses any ester or amide, polymers included, and leaves base residue and tar."
	taste_description = "soapy"
	reagent_state = LIQUID
	color = "#D0D0D0"
	strength = 6

