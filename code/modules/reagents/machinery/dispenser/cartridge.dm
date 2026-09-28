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
		reagents.add_reagent(spawn_reagent, volume)
		var/datum/reagent/R = chemistry_service().chemical_reagents[spawn_reagent]
		setLabel(R.name)

/obj/item/reagent_containers/chem_disp_cartridge/examine(mob/user)
	. = ..()
	. += "It has a capacity of [volume] units."
	if(reagents.total_volume <= 0)
		. += "It is empty."
	else
		. += "It contains [reagents.total_volume] units of liquid."
	if(!is_open_container())
		. += "The cap is sealed."

/// Old verb "Set Cartridge Label" (it took the label as a verb argument; now a text prompt).
/obj/item/reagent_containers/chem_disp_cartridge/proc/cartridge_set_label(mob/user, obj/item/held, datum/interaction/interaction)
	var/L = rerun_ask(user, "label", PROC_REF(cartridge_set_label), args, /datum/om/prompt/text, message = "Label for \the [src]:", title = "Set Cartridge Label", default = label, max_length = MAX_NAME_LEN)
	if(isnull(L))
		return
	setLabel(L, user)

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

DECLARE_INTERACTIONS(/obj/item/reagent_containers/chem_disp_cartridge, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_VERB("Set Cartridge Label", PROC_REF(cartridge_set_label)), \
)

/// Old attack_self.
/obj/item/reagent_containers/chem_disp_cartridge/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(is_open_container())
		to_chat(user, span_notice("You put the cap on \the [src]."))
		flags ^= OPENCONTAINER
	else
		to_chat(user, span_notice("You take the cap off \the [src]."))
		flags |= OPENCONTAINER
	return TRUE

/obj/item/reagent_containers/chem_disp_cartridge/afterattack(obj/target, mob/user , flag)
	if (!is_open_container() || !flag)
		return

	else if(istype(target, /obj/structure/reagent_dispensers)) //A dispenser. Transfer FROM it TO us.
		target.add_fingerprint(user)

		if(!target.reagents || !target.reagents.total_volume)
			to_chat(user, span_warning("\The [target] is empty."))
			return

		if(reagents.total_volume >= reagents.maximum_volume)
			to_chat(user, span_warning("\The [src] is full."))
			return

		var/obj/structure/reagent_dispensers/dispenser = target
		var/trans = target.reagents.trans_to(src, dispenser.amount_per_transfer_from_this)
		to_chat(user, span_notice("You fill \the [src] with [trans] units of the contents of \the [target]."))

	else if(target.is_open_container() && target.reagents) //Something like a glass. Player probably wants to transfer TO it.

		if(!reagents.total_volume)
			to_chat(user, span_warning("\The [src] is empty."))
			return

		if(target.reagents.total_volume >= target.reagents.maximum_volume)
			to_chat(user, span_warning("\The [target] is full."))
			return

		var/trans = src.reagents.trans_to(target, amount_per_transfer_from_this)
		to_chat(user, span_notice("You transfer [trans] units of the solution to \the [target]."))

	else
		return ..()
