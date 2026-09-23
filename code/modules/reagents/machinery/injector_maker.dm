/obj/machinery/injector_maker
	name = "Ready-to-Use Medicine 3000"
	desc = "Fills plastic autoinjectors with chemicals! Molds new injectors if needed!  \n Add a beaker or a bottle filled with chemicals and an autoinjector of appropriate size or sheets of plastic to use! \n Plastic can be drag-dropped into the machine."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "injector"
	use_power = USE_POWER_IDLE
	anchored = TRUE
	density = FALSE
	layer = ABOVE_WINDOW_LAYER
	vis_flags = VIS_HIDE
	unacidable = TRUE
	clicksound = "button"
	clickvol = 60
	idle_power_usage = 5
	active_power_usage = 100
	circuit = /obj/item/circuitboard/injector_maker
	var/obj/item/reagent_containers/beaker = null
	var/list/beaker_reagents_list = list()


	var/count_large_injector = 0
	var/count_small_injector = 0
	var/capacity_large_injector = 40
	var/capacity_small_injector = 40

	var/count_plastic = 0 //Given in "units", not sheets
	var/value_plastic = 2000 //1 sheet translates to 2000 units
	var/cost_plastic_small = 25
	var/cost_plastic_large = 250
	var/capacity_plastic = 60000 // 30 sheets of plastic


/obj/machinery/injector_maker/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/injector_maker/update_icon()
	if(!beaker && !count_plastic && !count_small_injector && !count_large_injector) //Empty
		icon_state = "injector"
	else if(beaker != null && !count_plastic && !count_small_injector  && !count_large_injector ) //Has just beaker
		icon_state = "injector_b"
	else if(!beaker && !count_plastic && (count_large_injector > 0 || count_small_injector > 0)) //Has just injectors
		icon_state = "injector_i"
	else if(!beaker && count_plastic > 0 && !count_large_injector && !count_small_injector) //Has just plastic
		icon_state = "injector_p"
	else if(beaker != null && !count_plastic && (count_large_injector > 0 || count_small_injector > 0)) //beaker + injectors
		icon_state = "injector_ib"
	else if(beaker != null && count_plastic > 0 && !count_large_injector && !count_small_injector) //beaker + plastic
		icon_state = "injector_pb"
	else if(beaker != null && count_plastic > 0 && (count_large_injector > 0 || count_small_injector > 0)) //Has everything
		icon_state = "injector_ipb"
	return


/obj/machinery/injector_maker/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/injector_maker_add_beaker,
		/datum/interaction/machine_item/injector_maker_add_small_injector,
		/datum/interaction/machine_item/injector_maker_add_large_injector,
		/datum/interaction/machine_item/injector_maker_add_plastic,
		/datum/interaction/machine_item/injector_maker_swallow,
		/datum/interaction/machine_drag/injector_maker_add_plastic,
		/datum/interaction/machine_alt/injector_maker_eject_beaker,
		/datum/interaction/machine_hand/ungated/injector_maker_use,
	)
	..()

/datum/interaction/machine_item/injector_maker_add_beaker
	id = "injector_maker_add_beaker"
	name = "Add container"
	held_type = list(/obj/item/reagent_containers/glass, /obj/item/reagent_containers/food/drinks/glass2, /obj/item/reagent_containers/food/drinks/shaker)
	effect = /obj/machinery/injector_maker/proc/interaction_add_beaker

/obj/machinery/injector_maker/proc/interaction_add_beaker(mob/user, obj/item/O, datum/interaction/interaction)
	if (beaker)
		return TRUE
	beaker = O
	user.drop_item()
	O.loc = src
	update_icon()
	return TRUE

/datum/interaction/machine_item/injector_maker_add_small_injector
	id = "injector_maker_add_small_injector"
	name = "Add injector"
	held_type = /obj/item/reagent_containers/hypospray/autoinjector/empty
	effect = /obj/machinery/injector_maker/proc/interaction_add_small_injector

/obj/machinery/injector_maker/proc/interaction_add_small_injector(mob/user, obj/item/reagent_containers/hypospray/autoinjector/empty/E, datum/interaction/interaction)
	if(count_small_injector >= capacity_small_injector)
		to_chat(user, span_warning("Storage is full! It can only hold [capacity_small_injector]"))
		return TRUE
	if(E.reagents.total_volume > 0)
		to_chat(user, span_warning("You cannot put a filled injector into the machine!"))
		return TRUE
	count_small_injector = count_small_injector + 1
	qdel(E)
	update_icon()
	return TRUE

/datum/interaction/machine_item/injector_maker_add_large_injector
	id = "injector_maker_add_large_injector"
	name = "Add injector"
	held_type = /obj/item/reagent_containers/hypospray/autoinjector/biginjector/empty
	effect = /obj/machinery/injector_maker/proc/interaction_add_large_injector

/obj/machinery/injector_maker/proc/interaction_add_large_injector(mob/user, obj/item/reagent_containers/hypospray/autoinjector/biginjector/empty/E, datum/interaction/interaction)
	if(count_large_injector >= capacity_large_injector)
		to_chat(user, span_warning("Storage is full! It can only hold [capacity_large_injector]"))
		return TRUE
	if(E.reagents.total_volume > 0)
		to_chat(user, span_warning("You cannot put a filled injector into the machine!"))
		return TRUE
	count_large_injector = count_large_injector + 1
	qdel(E)
	update_icon()
	return TRUE

/datum/interaction/machine_item/injector_maker_add_plastic
	id = "injector_maker_add_plastic"
	name = "Add plastic"
	held_type = /obj/item/stack/material
	offered_when = list(REQ_ON(PRED_HELD, /obj/machinery/injector_maker/proc/is_plastic_stack, null))
	effect = /obj/machinery/injector_maker/proc/interaction_add_plastic

/obj/machinery/injector_maker/proc/is_plastic_stack(mob/actor, atom/target, obj/item/held)
	return held.get_material_name() == MAT_PLASTIC

/obj/machinery/injector_maker/proc/interaction_add_plastic(mob/user, obj/item/stack/S, datum/interaction/interaction)
	var/input_amount = tgui_input_number(user, "How many sheets would you like to add?", "Add plastic", 0, S.get_amount())
	if(input_amount == 0)
		return TRUE
	var/plastic_input = input_amount * value_plastic
	var/free_space = capacity_plastic - count_plastic
	if(plastic_input > free_space)
		to_chat(user, span_warning("Storage is full! There is only [free_space] units worth of space left!"))
	else
		S.use(input_amount)
		count_plastic = count_plastic + plastic_input
		update_icon()
	return TRUE

/// Old attackby never called ..(), so any other item (or a non-plastic stack) is swallowed silently.
/datum/interaction/machine_item/injector_maker_swallow
	id = "injector_maker_swallow"
	name = "Use"
	held_type = /obj/item
	effect = /obj/machinery/injector_maker/proc/interaction_swallow

/obj/machinery/injector_maker/proc/interaction_swallow(mob/user, obj/item/held, datum/interaction/interaction)
	return TRUE

/datum/interaction/machine_drag/injector_maker_add_plastic
	id = "injector_maker_drag_add_plastic"
	name = "Add plastic"
	held_type = /obj/item/stack/material/plastic
	effect = /obj/machinery/injector_maker/proc/interaction_drag_add_plastic

/// The old adjacency/consciousness checks were silent (no message), so they stay in the effect.
/obj/machinery/injector_maker/proc/interaction_drag_add_plastic(mob/user, obj/item/stack/material/plastic/plastic_stack, datum/interaction/interaction)
	if(!isliving(user) || user.stat || !Adjacent(user) || !Adjacent(plastic_stack))
		return TRUE
	var/input_amount = tgui_input_number(user, "How many sheets would you like to add?", "Add plastic", 0, plastic_stack.get_amount())
	if(input_amount == 0)
		return TRUE
	if(!isliving(user) || user.stat || !Adjacent(user) || !Adjacent(plastic_stack))
		return TRUE
	var/plastic_input = input_amount * value_plastic
	var/free_space = capacity_plastic - count_plastic
	if(plastic_input > free_space)
		to_chat(user, span_warning("Storage is full! There is only [free_space] units worth of space left!"))
	else
		plastic_stack.use(input_amount)
		count_plastic = count_plastic + plastic_input
		update_icon()
	return TRUE

/// Old click_alt always ran the base first (`. = ..()`), then conditionally ejected the
/// beaker without changing the return. The effect declines (FALSE) so the base alt-click
/// still runs; it only does anything extra when a beaker is present.
/datum/interaction/machine_alt/injector_maker_eject_beaker
	id = "injector_maker_eject_beaker"
	name = "Eject beaker"
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/injector_maker/proc/has_beaker, null))
	effect = /obj/machinery/injector_maker/proc/interaction_eject_beaker

/obj/machinery/injector_maker/proc/has_beaker(mob/actor, atom/target, obj/item/held)
	return !!beaker

/obj/machinery/injector_maker/proc/interaction_eject_beaker(mob/user, obj/item/held, datum/interaction/interaction)
	if(!user.incapacitated() && Adjacent(user))
		user.put_in_hands(beaker)
	else
		beaker.forceMove(drop_location())
	beaker = null
	update_icon()
	return FALSE

/obj/machinery/injector_maker/examine(mob/user)
	. = ..()
	if(!in_range(user, src) && !issilicon(user) && !isobserver(user))
		. += span_warning("You're too far away to examine [src]'s contents and display!")
		return

	if(beaker)
		. += span_notice("\The [src] contains:")
		if(beaker)
			. += span_notice("- \A [beaker].")

	. += span_notice("\The [src] contains [src.count_small_injector] small injectors and [src.count_large_injector] large injectors.") + "\n"
	. += span_notice("It can hold [capacity_small_injector] small and [capacity_large_injector] large injectors respectively.") + "\n"
	. += span_notice("\The [src] contains [src.count_plastic] units of plastic. It can hold up to [capacity_plastic] units.") + "\n"

	if(!(stat & (NOPOWER|BROKEN)))
		. += span_notice("The status display reads the following reagents:") + "\n"
		if(beaker)
			for(var/datum/reagent/R in beaker.reagents.reagent_list)
				. += span_notice("- [R.volume] units of [R.name].")

/// Old attack_hand had no gate at all.
/datum/interaction/machine_hand/ungated/injector_maker_use
	id = "injector_maker_use"
	name = "Use"
	effect = /obj/machinery/injector_maker/proc/interaction_use

/obj/machinery/injector_maker/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	interact(user)
	return TRUE

/obj/machinery/injector_maker/interact(mob/user)
	if(user.incapacitated() || !beaker)
		return

	var/choice = tgui_input_list(user, "There are [src.count_small_injector] small and [src.count_large_injector]  large injectors left.", "Choose what to do", list("large injector", "small injector", "eject beaker", "cancel"))

	switch(choice)
		if("cancel")
			return
		if("eject beaker")
			if(!user.incapacitated() && Adjacent(user))
				user.put_in_hands(beaker)
			else
				beaker.forceMove(drop_location())
			src.beaker = null
			update_icon()


		if("small injector")
			var/material = tgui_input_list(user, "Use autoinjector storage, or mold new injectors to fill?", "Choose Material", list("mold plastic", "use injectors"))
			switch(material)
				if("mold plastic")
					if(src.count_plastic < cost_plastic_small)
						to_chat(user, span_warning("Not enough plastic! Need at least [cost_plastic_small] units."))
						return
				if("use injectors")
					if(!src.count_small_injector)
						to_chat(user, span_warning("Small injector rack is empty!"))
						return
			if(!beaker.reagents.total_volume)
				to_chat(user, span_warning("Chemical storage is empty!"))
				return
			var/injector_amount = tgui_input_number(user, "How many injectors would you like?", "Make small injectors", 0, 100)
			if(injector_amount > 0)
				switch(material)
					if("mold plastic")
						var/plastic_cost = cost_plastic_small * injector_amount
						if(src.count_plastic < plastic_cost)
							to_chat(user, span_warning("Not enough plastic! Need at least [plastic_cost] units."))
							return
					if("use injectors")
						if(src.count_small_injector < injector_amount)
							to_chat(user, span_warning("Not enough autoinjectors! You only have [src.count_small_injector]"))
							return
				var/name = tgui_input_text(user, "Name Injector", "Naming", null, 32)
				make_injector("small injector", injector_amount, name, material, user)
				update_icon()


		if("large injector")
			var/material = tgui_input_list(user, "Use autoinjector storage, or mold new injectors to fill?", "Choose Material", list("mold plastic", "use injectors"))
			switch(material)
				if("mold plastic")
					if(src.count_plastic < cost_plastic_large)
						to_chat(user, span_warning("Not enough plastic! Need at least [cost_plastic_large] units."))
						return
				if("use injectors")
					if(!src.count_large_injector)
						to_chat(user, span_warning("Large injector rack is empty!"))
						return
			if(!beaker.reagents.total_volume)
				to_chat(user, span_warning("Chemical storage is empty!"))
				return
			var/injector_amount = tgui_input_number(user, "How many injectors would you like?", "Make large injectors", 0, 100)
			if(injector_amount > 0)
				switch(material)
					if("mold plastic")
						var/plastic_cost = cost_plastic_large * injector_amount
						if(src.count_plastic < plastic_cost)
							to_chat(user, span_warning("Not enough plastic! Need at least [plastic_cost] units."))
							return
					if("use injectors")
						if(src.count_large_injector < injector_amount)
							to_chat(user, span_warning("Not enough autoinjectors! You only have [src.count_large_injector]"))
							return
				var/name = tgui_input_text(user, "Name Injector", "Naming", null, 32)
				make_injector("large injector", injector_amount, name, material,user)
				update_icon()


/obj/machinery/injector_maker/proc/make_injector(size, amount, new_name, material, mob/user)
	if(!beaker)
		return
	var/amount_per_injector = null
	var/proceed = "Yes" //Defaulting to Yes. We only check if the amount/injector gets under max volume
	switch(size)
		if("small injector")
			amount_per_injector = CLAMP(beaker.reagents.total_volume / amount, 0, 5)
		if("large injector")
			amount_per_injector = CLAMP(beaker.reagents.total_volume / amount, 0, 15)
	if((size == "small injector" && amount_per_injector < 5) || size == "large injector" && amount_per_injector < 15)
		proceed = tgui_alert(user, "Heads up! Less than max volume per injector!\n Making [amount] [size](s) filled with [amount_per_injector] total reagent volume each!","Proceed?",list("No","Yes"))
	if(!proceed || proceed == "No" || !amount_per_injector)
		return
	for(var/i, i < amount, i++)
		switch(size)
			if("small injector")
				switch(material)
					if("mold plastic")
						if(src.count_plastic < cost_plastic_small)
							return
						else
							src.count_plastic = src.count_plastic - cost_plastic_small
					if("use injectors")
						if(!src.count_small_injector)
							return
						else
							src.count_small_injector = src.count_small_injector - 1
				var/obj/item/reagent_containers/hypospray/autoinjector/empty/P = new(loc)
				beaker.reagents.trans_to_obj(P, amount_per_injector)
				P.update_icon()
				if(new_name)
					P.name = new_name


			if("large injector")
				switch(material)
					if("mold plastic")
						if(src.count_plastic < cost_plastic_large)
							return
						else
							src.count_plastic = src.count_plastic - cost_plastic_large
					if("use injectors")
						if(!src.count_large_injector)
							return
						else
							src.count_large_injector = src.count_large_injector - 1
				var/obj/item/reagent_containers/hypospray/autoinjector/biginjector/empty/P = new(loc)
				beaker.reagents.trans_to_obj(P, amount_per_injector)
				P.update_icon()
				if(new_name)
					P.name = new_name
