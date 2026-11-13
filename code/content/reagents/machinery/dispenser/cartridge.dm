/obj/item/reagent_containers/chem_disp_cartridge
	name = "chemical dispenser cartridge"
	desc = "This goes in a chemical dispenser."
	icon_state = "cartridge"

	w_class = ITEMSIZE_NORMAL

	volume = CARTRIDGE_VOLUME_LARGE
	amount_per_transfer_from_this = 50
	// Large, but inaccurate. Use a chem dispenser or beaker for small volumes.
	max_transfer_amount = 500
	min_transfer_amount = 50

	var/spawn_reagent = null
	var/label = ""
	/// The grade of the stock this cartridge comes filled with (GRADE_*): Standard from the chemical supply, Pharma for the medicine cartridges.
	var/source_grade = GRADE_STANDARD
	/// Names the source in chem_source_profile(): cartridges with the same key and reagent hold the same per-round impurities.
	var/source_key = "chemical supply"

/// The starting stock takes its source's contaminant profile for the round (nothing for a reagent that cannot carry impurities).
/obj/item/reagent_containers/chem_disp_cartridge/proc/stamp_source_contaminants()
	if(!spawn_reagent || !reagents)
		return
	chem_stamp_source(reagents, spawn_reagent, source_key, source_grade)

/obj/item/reagent_containers/chem_disp_cartridge/proc/label_initial_chemical()
	if(spawn_reagent)
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[spawn_reagent]
		setLabel(R.name)

/obj/item/reagent_containers/chem_disp_cartridge/proc/setLabel(L, mob/user = null)
	if(L)
		if(user)
			to_chat(user, span_notice("You set the label on \the [src] to '[L]'."))

		label = L
		name = "[initial(name)] - '[L]'"
	else
		if(user)
			to_chat(user, span_notice("You clear the label on \the [src]."))
		label = ""
		name = initial(name)

// A cartridge is a capped holder of its volume: the cap is worked in hand, with it off it pours into an open container and fills from a tank by the
// tank's own amount. It moves a large amount at a time (set from 50 to 500). Its label is set from the menu.
CAPABILITIES(/obj/item/reagent_containers/chem_disp_cartridge)
	variants(nameof(variant), PROC_REF(variant_table))
	configure(movable_motion(unacidable = TRUE))
	setup(PROC_REF(label_initial_chemical))
	configure(reagents(starts_from = list(nameof(spawn_reagent) = nameof(volume))))
	setup(PROC_REF(stamp_source_contaminants))
	reagent_container(
		volume = nameof(volume),
		lid = TRUE,
		transfer_default = nameof(amount_per_transfer_from_this),
		transfer_min = nameof(min_transfer_amount),
		transfer_max = nameof(max_transfer_amount),
		taps = list(/obj/structure/reagent_dispensers))
	op("label", menu(), label("Set Cartridge Label"), asks(/datum/prompt/text, fields = list("question" = "Label for it:")), then(PROC_REF(label_set)))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/reagent_containers/chem_disp_cartridge/proc/variant_table()
	return GLOB.dq_variants_chem_cartridges

/// The label the question was answered with.
/obj/item/reagent_containers/chem_disp_cartridge/proc/label_set(datum/act/op/A)
	var/datum/prompt/R = A.answer
	setLabel(R?.value, A.actor)
	return OP_OK
