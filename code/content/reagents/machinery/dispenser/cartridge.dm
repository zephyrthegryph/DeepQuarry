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

/// Puts `amount` units of the stock `reagent_id` in, with the contaminants its source comes with (chem_source_profile(): units of each per unit of stock;
/// nothing for a reagent that cannot carry impurities). As much as fits. Returns the units of stock added. The starting fill and the recharge of a
/// dispenser or synthesizer both come through here, so they add contaminants in the same proportions and a recharge never raises purity.
/obj/item/reagent_containers/chem_disp_cartridge/proc/add_stock(reagent_id, amount)
	if(!reagents)
		return 0
	return reagents.add_sourced_reagent(reagent_id, amount, chem_source_profile(reagent_id, source_key, source_grade))

/// The starting stock: full, as stock and the contaminants of its source.
/obj/item/reagent_containers/chem_disp_cartridge/proc/fill_stock()
	if(spawn_reagent)
		add_stock(spawn_reagent, volume)

/// Units of stock held: everything that is not contaminant.
/obj/item/reagent_containers/chem_disp_cartridge/proc/stock_volume()
	return reagents.total_volume - reagents.contaminant_volume()

/// Units the cartridge holds, traces included: what its fill gauge and the dispenser's grid show. A starting cartridge is full: its volume, whatever
/// share of it is the source's trace impurities (the stock itself is stock_volume()).
/obj/item/reagent_containers/chem_disp_cartridge/proc/fill_volume()
	return round(reagents.total_volume, 0.01)

/// The mixture that holds `stock_units` of stock: the stock and the contaminants that sit with it.
/obj/item/reagent_containers/chem_disp_cartridge/proc/draw_amount(stock_units)
	return stock_units * reagents.stock_scale()

/// Dispenses `stock_units` of stock, with its contaminants, into `target` (an atom: a beaker). Returns the units of stock moved.
/obj/item/reagent_containers/chem_disp_cartridge/proc/dispense_to(atom/target, stock_units)
	var/scale = reagents.stock_scale()
	var/moved = reagents.trans_to(target, stock_units * scale) || 0
	if(GLOB.chem_trace)
		log_world("CHEM: [src] dispensed [round(moved, 0.001)]u of mixture ([round(moved / scale, 0.001)]u of stock) into [target]")
	return moved / scale

/// Dispenses `stock_units` of stock, with its contaminants, into the holder `target`. Returns the units of stock moved.
/obj/item/reagent_containers/chem_disp_cartridge/proc/dispense_to_holder(datum/reagents/target, stock_units)
	var/scale = reagents.stock_scale()
	var/moved = reagents.trans_to_holder(target, stock_units * scale) || 0
	if(GLOB.chem_trace)
		log_world("CHEM: [src] dispensed [round(moved, 0.001)]u of mixture ([round(moved / scale, 0.001)]u of stock) into a holder")
	return moved / scale

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
	setup(PROC_REF(fill_stock))
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

/// The cartridge's fill gauge follows its contents: a dispenser's recharge adds stock with no other change to the cartridge, so the look watches the holder
/// (without it the cached look kept the old fill level: a REFRESH DRIFT / STALE draw).
/obj/item/reagent_containers/chem_disp_cartridge/draw(datum/look/look)
	..()
	look.watch(reagents)
