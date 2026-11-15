// The stocked precursors (doc/rewrite/proposals/chemistry_recipes.md section 0a): sixteen common building blocks, bottled. The chemistry lab starts with a box of each
// kind in its chemical closet, and cargo sells crates. Making them from wood, plastic, fat and so on is the cheaper or cleaner option, never required. (The recipe
// book lists silanol among them; silanol is kelotane, so the bottle holds the silicate it is made from.)

/// A bottle of a precursor: sixty units of one reagent, labelled with its name.
/obj/item/reagent_containers/glass/bottle/precursor
	name = "precursor bottle"
	desc = "A small bottle of a common chemical building block."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "bottle-3"

/obj/item/reagent_containers/glass/bottle/precursor/phenol
	name = "phenol bottle"
	prefill = list(REAGENT_ID_PHENOL = 60)

/obj/item/reagent_containers/glass/bottle/precursor/salicylic_acid
	name = "salicylic acid bottle"
	prefill = list(REAGENT_ID_SALICYLICACID = 60)

/obj/item/reagent_containers/glass/bottle/precursor/wood_aldehyde
	name = "wood aldehyde bottle"
	prefill = list(REAGENT_ID_WOODALDEHYDE = 60)

/obj/item/reagent_containers/glass/bottle/precursor/nitric_acid
	name = "nitric acid bottle"
	prefill = list(REAGENT_ID_NITRICACID = 60)

/obj/item/reagent_containers/glass/bottle/precursor/hydrochloric_acid
	name = "hydrochloric acid bottle"
	prefill = list(REAGENT_ID_HYDROCHLORIC = 60)

/obj/item/reagent_containers/glass/bottle/precursor/phosphoric_acid
	name = "phosphoric acid bottle"
	prefill = list(REAGENT_ID_PHOSPHORICACID = 60)

/obj/item/reagent_containers/glass/bottle/precursor/acetic_acid
	name = "acetic acid bottle"
	prefill = list(REAGENT_ID_ACETICACID = 60)

/obj/item/reagent_containers/glass/bottle/precursor/bleach
	name = "bleach bottle"
	prefill = list(REAGENT_ID_BLEACH = 60)

/obj/item/reagent_containers/glass/bottle/precursor/soda_ash
	name = "soda ash bottle"
	prefill = list(REAGENT_ID_SODAASH = 60)

/obj/item/reagent_containers/glass/bottle/precursor/glycerol
	name = "glycerol bottle"
	prefill = list(REAGENT_ID_GLYCEROL = 60)

/obj/item/reagent_containers/glass/bottle/precursor/silicate
	name = "silicate bottle"
	prefill = list(REAGENT_ID_SILICATE = 60)

/obj/item/reagent_containers/glass/bottle/precursor/fatty_acid
	name = "fatty acid bottle"
	prefill = list(REAGENT_ID_FATTYACID = 60)

/obj/item/reagent_containers/glass/bottle/precursor/pyridine
	name = "pyridine base bottle"
	prefill = list(REAGENT_ID_PYRIDINE = 60)

/obj/item/reagent_containers/glass/bottle/precursor/alkaloid
	name = "plant alkaloid base bottle"
	prefill = list(REAGENT_ID_ALKALOID = 60)

/obj/item/reagent_containers/glass/bottle/precursor/sterol
	name = "sterol bottle"
	prefill = list(REAGENT_ID_STEROL = 60)

/obj/item/reagent_containers/glass/bottle/precursor/amino_acid
	name = "amino acid bottle"
	prefill = list(REAGENT_ID_AMINOACID = 60)

// ---- the boxes: sixteen bottles in three ----

/obj/item/storage/box/precursors_inorganic
	name = "box of inorganic precursors"
	desc = "Bottles of the acids, the bleach, the soda ash and the silicate a chemist starts from."
	icon_state = "beaker"
	starts_with = list(
		/obj/item/reagent_containers/glass/bottle/precursor/nitric_acid,
		/obj/item/reagent_containers/glass/bottle/precursor/hydrochloric_acid,
		/obj/item/reagent_containers/glass/bottle/precursor/phosphoric_acid,
		/obj/item/reagent_containers/glass/bottle/precursor/acetic_acid,
		/obj/item/reagent_containers/glass/bottle/precursor/bleach,
		/obj/item/reagent_containers/glass/bottle/precursor/soda_ash,
		/obj/item/reagent_containers/glass/bottle/precursor/silicate)

/obj/item/storage/box/precursors_ring
	name = "box of ring and chain precursors"
	desc = "Bottles of phenol, salicylic acid, wood aldehyde, glycerol, fatty acid and pyridine base."
	icon_state = "beaker"
	starts_with = list(
		/obj/item/reagent_containers/glass/bottle/precursor/phenol,
		/obj/item/reagent_containers/glass/bottle/precursor/salicylic_acid,
		/obj/item/reagent_containers/glass/bottle/precursor/wood_aldehyde,
		/obj/item/reagent_containers/glass/bottle/precursor/glycerol,
		/obj/item/reagent_containers/glass/bottle/precursor/fatty_acid,
		/obj/item/reagent_containers/glass/bottle/precursor/pyridine)

/obj/item/storage/box/precursors_bio
	name = "box of organic precursors"
	desc = "Bottles of plant alkaloid base, sterol and amino acid."
	icon_state = "beaker"
	starts_with = list(
		/obj/item/reagent_containers/glass/bottle/precursor/alkaloid,
		/obj/item/reagent_containers/glass/bottle/precursor/sterol,
		/obj/item/reagent_containers/glass/bottle/precursor/amino_acid)
