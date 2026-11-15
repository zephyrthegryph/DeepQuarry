// Hand-written feedstock rows for ordinary items (doc/rewrite/proposals/chemistry_recipes.md section 11): the items worth a row of their own. Any other item grinds into the
// feedstock of what it is made of (item_feedstock(), code/content/refinery/grinding.dm).
//
// A row is a type under /transformation/grinding that takes one item (item_term) and names, as terms, the reagents it grinds into: the amount of each term is its WEIGHT in
// the item's feedstock (a reagent is a share of it, not a volume), and a contaminant the item carries is a term with a small weight. The row covers the type it names and
// every type below it (grinding_item_rule_for()). How much the item grinds into is not the row's to say: it is what the item's materials are worth (so an item never
// grinds into more than it cost to make), or a point of size when it records none (GRIND_ITEM_UNITS_PER_SIZE).


// ---- electronics and parts ----

// /obj/item/circuitboard: gold, copper, tin, glass fibre; a brominated flame retardant
/transformation/grinding/item_circuitboard
CAPABILITIES(/transformation/grinding/item_circuitboard)
	configure(transformation(takes = list(item_term(/obj/item/circuitboard, 1)),
		makes = list(reagent(REAGENT_ID_GOLD, 1), reagent(REAGENT_ID_COPPER, 2), reagent(REAGENT_ID_TIN, 1), reagent(REAGENT_ID_SILICON, 2), reagent(REAGENT_ID_CONTAMINANT_SALTS, 0.3))))

// /obj/item/light/tube: glass and the tungsten of the filament; mercury
/transformation/grinding/item_light_tube
CAPABILITIES(/transformation/grinding/item_light_tube)
	configure(transformation(takes = list(item_term(/obj/item/light/tube, 1)),
		makes = list(reagent(REAGENT_ID_SILICON, 4), reagent(REAGENT_ID_TUNGSTEN, 1), reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL, 0.3))))

// /obj/item/light/bulb: glass and the tungsten of the filament; mercury
/transformation/grinding/item_light_bulb
CAPABILITIES(/transformation/grinding/item_light_bulb)
	configure(transformation(takes = list(item_term(/obj/item/light/bulb, 1)),
		makes = list(reagent(REAGENT_ID_SILICON, 4), reagent(REAGENT_ID_TUNGSTEN, 1), reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL, 0.3))))

// /obj/item/cell: lithium, sulphuric acid and carbon; heavy metals
/transformation/grinding/item_cell
CAPABILITIES(/transformation/grinding/item_cell)
	configure(transformation(takes = list(item_term(/obj/item/cell, 1)),
		makes = list(reagent(REAGENT_ID_LITHIUM, 3), reagent(REAGENT_ID_SACID, 2), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL, 0.4))))

// /obj/item/stack/cable_coil: copper and its plastic insulation; plasticiser
/transformation/grinding/item_cable_coil
CAPABILITIES(/transformation/grinding/item_cable_coil)
	configure(transformation(takes = list(item_term(/obj/item/stack/cable_coil, 1)),
		makes = list(reagent(REAGENT_ID_COPPER, 4), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CHLORINE, 1), reagent(REAGENT_ID_CONTAMINANT_PLASTICISER, 0.4))))

// /obj/item/stock_parts: copper, glass and a little gold; salts
/transformation/grinding/item_stock_parts
CAPABILITIES(/transformation/grinding/item_stock_parts)
	configure(transformation(takes = list(item_term(/obj/item/stock_parts, 1)),
		makes = list(reagent(REAGENT_ID_COPPER, 1), reagent(REAGENT_ID_SILICON, 2), reagent(REAGENT_ID_GOLD, 0.5), reagent(REAGENT_ID_CONTAMINANT_SALTS, 0.2))))


// ---- gloves and rubber ----

// /obj/item/clothing/gloves/sterile/latex: rubber: chains and the sulfur that cross-links them
/transformation/grinding/item_gloves_latex
CAPABILITIES(/transformation/grinding/item_gloves_latex)
	configure(transformation(takes = list(item_term(/obj/item/clothing/gloves/sterile/latex, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 3), reagent(REAGENT_ID_SULFUR, 1), reagent(REAGENT_ID_CONTAMINANT_SULFUR, 0.3))))

// /obj/item/clothing/gloves/sterile/nitrile: a chain with a nitrile group
/transformation/grinding/item_gloves_nitrile
CAPABILITIES(/transformation/grinding/item_gloves_nitrile)
	configure(transformation(takes = list(item_term(/obj/item/clothing/gloves/sterile/nitrile, 1)),
		makes = list(reagent(REAGENT_ID_FATTYACID, 2), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CYANIDE, 0.1), reagent(REAGENT_ID_CONTAMINANT_SULFUR, 0.3))))

// /obj/item/clothing/gloves/yellow: rubber
/transformation/grinding/item_gloves_insulated
CAPABILITIES(/transformation/grinding/item_gloves_insulated)
	configure(transformation(takes = list(item_term(/obj/item/clothing/gloves/yellow, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 3), reagent(REAGENT_ID_SULFUR, 1), reagent(REAGENT_ID_CONTAMINANT_SULFUR, 0.3))))

// /obj/item/clothing/mask/gas: rubber
/transformation/grinding/item_gas_mask
CAPABILITIES(/transformation/grinding/item_gas_mask)
	configure(transformation(takes = list(item_term(/obj/item/clothing/mask/gas, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 3), reagent(REAGENT_ID_SULFUR, 1), reagent(REAGENT_ID_CONTAMINANT_SULFUR, 0.2))))

// /obj/item/toy/balloon: rubber; plasticiser
/transformation/grinding/item_balloon
CAPABILITIES(/transformation/grinding/item_balloon)
	configure(transformation(takes = list(item_term(/obj/item/toy/balloon, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 3), reagent(REAGENT_ID_SULFUR, 1), reagent(REAGENT_ID_CONTAMINANT_PLASTICISER, 0.3))))

// /obj/item/bikehorn/rubberducky: rubber; plasticiser
/transformation/grinding/item_rubber_duck
CAPABILITIES(/transformation/grinding/item_rubber_duck)
	configure(transformation(takes = list(item_term(/obj/item/bikehorn/rubberducky, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 3), reagent(REAGENT_ID_SULFUR, 1), reagent(REAGENT_ID_CONTAMINANT_PLASTICISER, 0.3))))


// ---- smoking ----

// /obj/item/clothing/mask/smokable/cigarette: nicotine and ash; tar (a cigar is one too)
/transformation/grinding/item_cigarette
CAPABILITIES(/transformation/grinding/item_cigarette)
	configure(transformation(takes = list(item_term(/obj/item/clothing/mask/smokable/cigarette, 1)),
		makes = list(reagent(REAGENT_ID_NICOTINE, 2), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CONTAMINANT_TAR, 0.5))))

// /obj/item/trash/cigbutt: what was left of it; tar and heavy metals
/transformation/grinding/item_cigarette_butt
CAPABILITIES(/transformation/grinding/item_cigarette_butt)
	configure(transformation(takes = list(item_term(/obj/item/trash/cigbutt, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 2), reagent(REAGENT_ID_NICOTINE, 1), reagent(REAGENT_ID_CONTAMINANT_TAR, 0.5), reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL, 0.2))))


// ---- household ----

// /obj/item/soap: soap: a fatty acid and its lye; more lye gives glycerol; perfume oils
/transformation/grinding/item_soap
CAPABILITIES(/transformation/grinding/item_soap)
	configure(transformation(takes = list(item_term(/obj/item/soap, 1)),
		makes = list(reagent(REAGENT_ID_FATTYACID, 3), reagent(REAGENT_ID_LYE, 1), reagent(REAGENT_ID_GLYCEROL, 1), reagent(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE, 0.2))))

// /obj/item/flame/candle: wax and a cotton wick of cellulose; oily residue
/transformation/grinding/item_candle
CAPABILITIES(/transformation/grinding/item_candle)
	configure(transformation(takes = list(item_term(/obj/item/flame/candle, 1)),
		makes = list(reagent(REAGENT_ID_TRIGLYCERIDE, 3), reagent(REAGENT_ID_WOODPULP, 1), reagent(REAGENT_ID_CONTAMINANT_OILY_RESIDUE, 0.4))))

// /obj/item/pen/crayon: wax and pigment; heavy metals from the pigment
/transformation/grinding/item_crayon
CAPABILITIES(/transformation/grinding/item_crayon)
	configure(transformation(takes = list(item_term(/obj/item/pen/crayon, 1)),
		makes = list(reagent(REAGENT_ID_TRIGLYCERIDE, 2), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL, 0.2))))

// /obj/item/pen/crayon/marker: solvent and pigment; heavy metals from the pigment
/transformation/grinding/item_marker
CAPABILITIES(/transformation/grinding/item_marker)
	configure(transformation(takes = list(item_term(/obj/item/pen/crayon/marker, 1)),
		makes = list(reagent(REAGENT_ID_ETHANOL, 2), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL, 0.2))))

// /obj/item/pen: ink solvent and carbon black
/transformation/grinding/item_pen
CAPABILITIES(/transformation/grinding/item_pen)
	configure(transformation(takes = list(item_term(/obj/item/pen, 1)),
		makes = list(reagent(REAGENT_ID_ETHANOL, 1), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE, 0.2))))

// /obj/item/lipstick: wax and pigment; heavy metals
/transformation/grinding/item_lipstick
CAPABILITIES(/transformation/grinding/item_lipstick)
	configure(transformation(takes = list(item_term(/obj/item/lipstick, 1)),
		makes = list(reagent(REAGENT_ID_TRIGLYCERIDE, 2), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL, 0.3))))

// /obj/item/flame/lighter: lighter fuel and the flint
/transformation/grinding/item_lighter
CAPABILITIES(/transformation/grinding/item_lighter)
	configure(transformation(takes = list(item_term(/obj/item/flame/lighter, 1)),
		makes = list(reagent(REAGENT_ID_FUEL, 2), reagent(REAGENT_ID_IRON, 1))))

// /obj/item/flame/match: phosphorus, sulfur and an oxidiser salt
/transformation/grinding/item_match
CAPABILITIES(/transformation/grinding/item_match)
	configure(transformation(takes = list(item_term(/obj/item/flame/match, 1)),
		makes = list(reagent(REAGENT_ID_PHOSPHORUS, 2), reagent(REAGENT_ID_SULFUR, 2), reagent(REAGENT_ID_POTASSIUM, 1))))

// /obj/item/flashlight/flare: phosphorus, sulfur, an oxidiser salt and the carbon of the body
/transformation/grinding/item_flare
CAPABILITIES(/transformation/grinding/item_flare)
	configure(transformation(takes = list(item_term(/obj/item/flashlight/flare, 1)),
		makes = list(reagent(REAGENT_ID_PHOSPHORUS, 1), reagent(REAGENT_ID_SULFUR, 1), reagent(REAGENT_ID_POTASSIUM, 1), reagent(REAGENT_ID_CARBON, 1))))

// /obj/item/flashlight/glowstick: a luminol-type dye; peroxide
/transformation/grinding/item_glowstick
CAPABILITIES(/transformation/grinding/item_glowstick)
	configure(transformation(takes = list(item_term(/obj/item/flashlight/glowstick, 1)),
		makes = list(reagent(REAGENT_ID_LUMINOL, 2), reagent(REAGENT_ID_CONTAMINANT_PEROXIDE, 0.3))))

// /obj/item/reagent_containers/glass/rag: cellulose
/transformation/grinding/item_rag
CAPABILITIES(/transformation/grinding/item_rag)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/glass/rag, 1)),
		makes = list(reagent(REAGENT_ID_WOODPULP, 3), reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 0.2))))

// /obj/item/toy/plushie: synthetic cloth: cellulose and chains
/transformation/grinding/item_plushie
CAPABILITIES(/transformation/grinding/item_plushie)
	configure(transformation(takes = list(item_term(/obj/item/toy/plushie, 1)),
		makes = list(reagent(REAGENT_ID_WOODPULP, 2), reagent(REAGENT_ID_CARBON, 2), reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 0.2))))


// ---- paper and cloth ----

// /obj/item/stack/medical: gauze: cellulose, and the wax of a salve
/transformation/grinding/item_bandages
CAPABILITIES(/transformation/grinding/item_bandages)
	configure(transformation(takes = list(item_term(/obj/item/stack/medical, 1)),
		makes = list(reagent(REAGENT_ID_WOODPULP, 3), reagent(REAGENT_ID_TRIGLYCERIDE, 1), reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 0.2))))

// /obj/item/paper: cellulose; inert filler
/transformation/grinding/item_paper
CAPABILITIES(/transformation/grinding/item_paper)
	configure(transformation(takes = list(item_term(/obj/item/paper, 1)),
		makes = list(reagent(REAGENT_ID_WOODPULP, 3), reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 0.1))))

// /obj/item/book: cellulose and ink
/transformation/grinding/item_book
CAPABILITIES(/transformation/grinding/item_book)
	configure(transformation(takes = list(item_term(/obj/item/book, 1)),
		makes = list(reagent(REAGENT_ID_WOODPULP, 3), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 0.1))))

// /obj/item/photo: paper and the silver salts of the emulsion
/transformation/grinding/item_photo
CAPABILITIES(/transformation/grinding/item_photo)
	configure(transformation(takes = list(item_term(/obj/item/photo, 1)),
		makes = list(reagent(REAGENT_ID_WOODPULP, 2), reagent(REAGENT_ID_SILVER, 1), reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL, 0.2))))

// /obj/item/paper_bin: cellulose
/transformation/grinding/item_paper_bin
CAPABILITIES(/transformation/grinding/item_paper_bin)
	configure(transformation(takes = list(item_term(/obj/item/paper_bin, 1)),
		makes = list(reagent(REAGENT_ID_WOODPULP, 4), reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 0.1))))

// /obj/item/toner: carbon black and plastic
/transformation/grinding/item_toner
CAPABILITIES(/transformation/grinding/item_toner)
	configure(transformation(takes = list(item_term(/obj/item/toner, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 3), reagent(REAGENT_ID_CONTAMINANT_PLASTICISER, 0.3))))

// /obj/item/clothing/under: cloth: cellulose (synthetic cloth gives chains)
/transformation/grinding/item_clothing_under
CAPABILITIES(/transformation/grinding/item_clothing_under)
	configure(transformation(takes = list(item_term(/obj/item/clothing/under, 1)),
		makes = list(reagent(REAGENT_ID_WOODPULP, 2), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 0.2))))

// /obj/item/clothing/suit: cloth
/transformation/grinding/item_clothing_suit
CAPABILITIES(/transformation/grinding/item_clothing_suit)
	configure(transformation(takes = list(item_term(/obj/item/clothing/suit, 1)),
		makes = list(reagent(REAGENT_ID_WOODPULP, 2), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 0.2))))

// /obj/item/clothing/head: cloth
/transformation/grinding/item_clothing_head
CAPABILITIES(/transformation/grinding/item_clothing_head)
	configure(transformation(takes = list(item_term(/obj/item/clothing/head, 1)),
		makes = list(reagent(REAGENT_ID_WOODPULP, 2), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 0.2))))

// /obj/item/clothing/shoes: leather and rubber
/transformation/grinding/item_clothing_shoes
CAPABILITIES(/transformation/grinding/item_clothing_shoes)
	configure(transformation(takes = list(item_term(/obj/item/clothing/shoes, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 2), reagent(REAGENT_ID_PROTEIN, 1), reagent(REAGENT_ID_SULFUR, 1), reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 0.2))))

// /obj/item/stack/tile/carpet: cloth
/transformation/grinding/item_carpet
CAPABILITIES(/transformation/grinding/item_carpet)
	configure(transformation(takes = list(item_term(/obj/item/stack/tile/carpet, 1)),
		makes = list(reagent(REAGENT_ID_WOODPULP, 2), reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 0.1))))

// /obj/item/seeds: a husk of cellulose and a little sugar
/transformation/grinding/item_seeds
CAPABILITIES(/transformation/grinding/item_seeds)
	configure(transformation(takes = list(item_term(/obj/item/seeds, 1)),
		makes = list(reagent(REAGENT_ID_WOODPULP, 2), reagent(REAGENT_ID_SUGAR, 1))))


// ---- medicine and glassware ----

// /obj/item/reagent_containers/pill: the wax or filler base around its medicine (the medicine itself pours out first)
/transformation/grinding/item_pill
CAPABILITIES(/transformation/grinding/item_pill)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/pill, 1)),
		makes = list(reagent(REAGENT_ID_TRIGLYCERIDE, 1), reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 0.4))))

// /obj/item/reagent_containers/glass/beaker: glass
/transformation/grinding/item_beaker
CAPABILITIES(/transformation/grinding/item_beaker)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/glass/beaker, 1)),
		makes = list(reagent(REAGENT_ID_SILICON, 4))))

// /obj/item/reagent_containers/glass/bottle: glass
/transformation/grinding/item_bottle
CAPABILITIES(/transformation/grinding/item_bottle)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/glass/bottle, 1)),
		makes = list(reagent(REAGENT_ID_SILICON, 4))))

// /obj/item/reagent_containers/syringe: plastic
/transformation/grinding/item_syringe
CAPABILITIES(/transformation/grinding/item_syringe)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/syringe, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 2), reagent(REAGENT_ID_CHLORINE, 1), reagent(REAGENT_ID_OXYGEN, 1), reagent(REAGENT_ID_CONTAMINANT_PLASTICISER, 0.2))))

// /obj/item/reagent_containers/food/drinks/bottle: glass
/transformation/grinding/item_drink_bottle
CAPABILITIES(/transformation/grinding/item_drink_bottle)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/drinks/bottle, 1)),
		makes = list(reagent(REAGENT_ID_SILICON, 4))))


// ---- food ----

// /obj/item/reagent_containers/food/snacks/meat: protein, sterol and fat; endotoxin
/transformation/grinding/item_meat
CAPABILITIES(/transformation/grinding/item_meat)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/meat, 1)),
		makes = list(reagent(REAGENT_ID_PROTEIN, 3), reagent(REAGENT_ID_STEROL, 1), reagent(REAGENT_ID_TRIGLYCERIDE, 2), reagent(REAGENT_ID_CONTAMINANT_BIOLOGICAL, 0.3))))

// /obj/item/reagent_containers/food/snacks/egg: protein and sterol, and the calcium carbonate of the shell; endotoxin
/transformation/grinding/item_egg
CAPABILITIES(/transformation/grinding/item_egg)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/egg, 1)),
		makes = list(reagent(REAGENT_ID_PROTEIN, 3), reagent(REAGENT_ID_STEROL, 1), reagent(REAGENT_ID_CALCIUMCARBONATE, 1), reagent(REAGENT_ID_CONTAMINANT_BIOLOGICAL, 0.2))))

// /obj/item/reagent_containers/food/snacks/monkeycube: protein and sterol
/transformation/grinding/item_monkey_cube
CAPABILITIES(/transformation/grinding/item_monkey_cube)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/monkeycube, 1)),
		makes = list(reagent(REAGENT_ID_PROTEIN, 3), reagent(REAGENT_ID_STEROL, 1), reagent(REAGENT_ID_CONTAMINANT_BIOLOGICAL, 0.2))))

// /obj/item/reagent_containers/food/snacks/cheesewedge: casein protein and fat
/transformation/grinding/item_cheese
CAPABILITIES(/transformation/grinding/item_cheese)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/cheesewedge, 1)),
		makes = list(reagent(REAGENT_ID_PROTEIN, 3), reagent(REAGENT_ID_TRIGLYCERIDE, 2))))

// /obj/item/reagent_containers/food/snacks/grown: sugars, cellulose and a fruit acid
/transformation/grinding/item_produce
CAPABILITIES(/transformation/grinding/item_produce)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/grown, 1)),
		makes = list(reagent(REAGENT_ID_SUGAR, 2), reagent(REAGENT_ID_WOODPULP, 1), reagent(REAGENT_ID_ACETICACID, 1), reagent(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE, 0.1))))

// /obj/item/reagent_containers/food/snacks/sliceable/bread: starch (it hydrolyses to sugar) and cellulose
/transformation/grinding/item_bread
CAPABILITIES(/transformation/grinding/item_bread)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/sliceable/bread, 1)),
		makes = list(reagent(REAGENT_ID_SUGAR, 3), reagent(REAGENT_ID_WOODPULP, 1))))

// /obj/item/reagent_containers/food/snacks/candy: sugar and fat; flavour esters
/transformation/grinding/item_candy
CAPABILITIES(/transformation/grinding/item_candy)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/candy, 1)),
		makes = list(reagent(REAGENT_ID_SUGAR, 3), reagent(REAGENT_ID_TRIGLYCERIDE, 1), reagent(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE, 0.2))))

// /obj/item/reagent_containers/food/snacks/donut: sugar and fat
/transformation/grinding/item_donut
CAPABILITIES(/transformation/grinding/item_donut)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/donut, 1)),
		makes = list(reagent(REAGENT_ID_SUGAR, 2), reagent(REAGENT_ID_TRIGLYCERIDE, 2))))

// /obj/item/reagent_containers/food/snacks/cookie: sugar and fat
/transformation/grinding/item_cookie
CAPABILITIES(/transformation/grinding/item_cookie)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/cookie, 1)),
		makes = list(reagent(REAGENT_ID_SUGAR, 2), reagent(REAGENT_ID_TRIGLYCERIDE, 2))))

// /obj/item/reagent_containers/food/snacks/fries: starch and cooking oil
/transformation/grinding/item_fries
CAPABILITIES(/transformation/grinding/item_fries)
	configure(transformation(takes = list(item_term(/obj/item/reagent_containers/food/snacks/fries, 1)),
		makes = list(reagent(REAGENT_ID_SUGAR, 2), reagent(REAGENT_ID_TRIGLYCERIDE, 1), reagent(REAGENT_ID_CONTAMINANT_OILY_RESIDUE, 0.2))))


// ---- bone and organs ----

// /obj/item/organ/internal: protein, sterol and phosphate fats; endotoxin
/transformation/grinding/item_organ
CAPABILITIES(/transformation/grinding/item_organ)
	configure(transformation(takes = list(item_term(/obj/item/organ/internal, 1)),
		makes = list(reagent(REAGENT_ID_PROTEIN, 3), reagent(REAGENT_ID_STEROL, 1), reagent(REAGENT_ID_PHOSPHORICACID, 1), reagent(REAGENT_ID_CONTAMINANT_BIOLOGICAL, 0.3))))

// /obj/item/organ/internal/brain: protein, sterol and the fats of nerve tissue; endotoxin
/transformation/grinding/item_brain
CAPABILITIES(/transformation/grinding/item_brain)
	configure(transformation(takes = list(item_term(/obj/item/organ/internal/brain, 1)),
		makes = list(reagent(REAGENT_ID_PROTEIN, 3), reagent(REAGENT_ID_STEROL, 2), reagent(REAGENT_ID_TRIGLYCERIDE, 2), reagent(REAGENT_ID_CONTAMINANT_BIOLOGICAL, 0.3))))

// /obj/item/organ/external: protein, the calcium carbonate of bone and some fat; endotoxin
/transformation/grinding/item_limb
CAPABILITIES(/transformation/grinding/item_limb)
	configure(transformation(takes = list(item_term(/obj/item/organ/external, 1)),
		makes = list(reagent(REAGENT_ID_PROTEIN, 3), reagent(REAGENT_ID_CALCIUMCARBONATE, 1), reagent(REAGENT_ID_TRIGLYCERIDE, 1), reagent(REAGENT_ID_CONTAMINANT_BIOLOGICAL, 0.3))))

// /obj/item/bone: calcium carbonate and phosphate, and the collagen
/transformation/grinding/item_bone
CAPABILITIES(/transformation/grinding/item_bone)
	configure(transformation(takes = list(item_term(/obj/item/bone, 1)),
		makes = list(reagent(REAGENT_ID_CALCIUMCARBONATE, 3), reagent(REAGENT_ID_PHOSPHORICACID, 1), reagent(REAGENT_ID_PROTEIN, 1))))
