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
	unacidable = TRUE

	var/spawn_reagent = null
	var/label = ""

/obj/item/reagent_containers/chem_disp_cartridge/Initialize(mapload)
	. = ..()
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
	configure(reagents(starts_from = list(nameof(spawn_reagent) = nameof(volume))))
	reagent_container(
		volume = nameof(volume),
		lid = TRUE,
		transfer_default = nameof(amount_per_transfer_from_this),
		transfer_min = nameof(min_transfer_amount),
		transfer_max = nameof(max_transfer_amount),
		taps = list(/obj/structure/reagent_dispensers))
	op("label", menu(), label("Set Cartridge Label"), asks(/datum/prompt/text, fields = list("question" = "Label for it:")), then(PROC_REF(label_set)))

/// The label the question was answered with.
/obj/item/reagent_containers/chem_disp_cartridge/proc/label_set(datum/act/op/A)
	var/datum/prompt/R = A.answer
	setLabel(R?.value, A.actor)
	return OP_OK
