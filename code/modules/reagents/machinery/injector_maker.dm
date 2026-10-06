#define MAKER_REQUEST_PLASTIC 1
#define MAKER_REQUEST_DRAG 2
#define MAKER_REQUEST_MENU 3
#define MAKER_REQUEST_CREATE 4

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
	clicksound = SFX_BUTTON
	clickvol = 60
	idle_power_usage = 5
	active_power_usage = 100
	circuit = /obj/item/circuitboard/injector_maker
	var/obj/item/reagent_containers/beaker = null
	var/list/beaker_reagents_list


	var/count_large_injector = 0
	var/count_small_injector = 0
	var/capacity_large_injector = 40
	var/capacity_small_injector = 40

	var/count_plastic = 0 //Given in "units", not sheets
	var/value_plastic = 2000 //1 sheet translates to 2000 units
	var/cost_plastic_small = 25
	var/cost_plastic_large = 250
	var/capacity_plastic = 60000 // 30 sheets of plastic


// ALLOW(init/INSTANCE_STATE): takes the parts it was built with
/obj/machinery/injector_maker/Initialize(mapload)
	. = ..()
	default_apply_parts()

DECLARE_APPEARANCE_PROC(/obj/machinery/injector_maker, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/injector_maker/appearance_overlays()
	. = list()
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
	return .


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
	if(!move_into(src, nameof(src.beaker), O, user))
		return TRUE
	update_icon()
	return TRUE

/datum/interaction/machine_item/injector_maker_add_small_injector
	id = "injector_maker_add_small_injector"
	name = "Add injector"
	held_type = /obj/item/reagent_containers/hypospray/autoinjector/empty
	effect = /obj/machinery/injector_maker/proc/interaction_add_small_injector
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/injector_maker/proc/can_take_small_injector))

/// Requirement: TRUE, or why this small injector can't be stored.
/obj/machinery/injector_maker/proc/can_take_small_injector(mob/user, atom/target, obj/item/held)
	if(count_small_injector >= capacity_small_injector)
		return "storage is full; it can only hold [capacity_small_injector]"
	if(held?.reagents?.total_volume > 0)
		return "you cannot put a filled injector into the machine"
	return TRUE

/// Requirement: TRUE, or why this large injector can't be stored.
/obj/machinery/injector_maker/proc/can_take_large_injector(mob/user, atom/target, obj/item/held)
	if(count_large_injector >= capacity_large_injector)
		return "storage is full; it can only hold [capacity_large_injector]"
	if(held?.reagents?.total_volume > 0)
		return "you cannot put a filled injector into the machine"
	return TRUE

/obj/machinery/injector_maker/proc/interaction_add_small_injector(mob/user, obj/item/reagent_containers/hypospray/autoinjector/empty/E, datum/interaction/interaction)
	count_small_injector = count_small_injector + 1
	consume(E, user)
	update_icon()
	return TRUE

/datum/interaction/machine_item/injector_maker_add_large_injector
	id = "injector_maker_add_large_injector"
	name = "Add injector"
	held_type = /obj/item/reagent_containers/hypospray/autoinjector/biginjector/empty
	effect = /obj/machinery/injector_maker/proc/interaction_add_large_injector
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/injector_maker/proc/can_take_large_injector))

/obj/machinery/injector_maker/proc/interaction_add_large_injector(mob/user, obj/item/reagent_containers/hypospray/autoinjector/biginjector/empty/E, datum/interaction/interaction)
	count_large_injector = count_large_injector + 1
	consume(E, user)
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
	return maker_plastic_stage(user, S, interaction, list())

/obj/machinery/injector_maker/proc/maker_plastic_stage(mob/user, obj/item/stack/S, datum/interaction/interaction, list/maker_answers)
	if(!("a1" in maker_answers))
		open_request(src, /datum/prompt/number/injector_maker_review, PROC_REF(maker_request_answered), answerer = user, maker_operator = user, maker_answers = maker_answers, maker_key = "a1", maker_route = MAKER_REQUEST_PLASTIC, maker_stack = S, maker_interaction = interaction, question = "How many sheets would you like to add?", title = "Add plastic", default = 0, maker_max = S.get_amount())
		return TRUE
	var/input_amount = maker_answers["a1"]
	if(isnull(input_amount))
		return TRUE
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
	effect = /atom/proc/interaction_swallow

/datum/interaction/machine_drag/injector_maker_add_plastic
	id = "injector_maker_drag_add_plastic"
	name = "Add plastic"
	held_type = /obj/item/stack/material/plastic
	effect = /obj/machinery/injector_maker/proc/interaction_drag_add_plastic

/// The old adjacency/consciousness checks were silent (no message), so they stay in the effect.
/obj/machinery/injector_maker/proc/interaction_drag_add_plastic(mob/user, obj/item/stack/material/plastic/plastic_stack, datum/interaction/interaction)
	return maker_drag_stage(user, plastic_stack, interaction, list())

/obj/machinery/injector_maker/proc/maker_drag_stage(mob/user, obj/item/stack/material/plastic/plastic_stack, datum/interaction/interaction, list/maker_answers)
	if(!isliving(user) || user.stat || !Adjacent(user) || !Adjacent(plastic_stack))
		return TRUE
	if(!("a2" in maker_answers))
		open_request(src, /datum/prompt/number/injector_maker_review, PROC_REF(maker_request_answered), answerer = user, maker_operator = user, maker_answers = maker_answers, maker_key = "a2", maker_route = MAKER_REQUEST_DRAG, maker_stack = plastic_stack, maker_interaction = interaction, question = "How many sheets would you like to add?", title = "Add plastic", default = 0, maker_max = plastic_stack.get_amount())
		return TRUE
	var/input_amount = maker_answers["a2"]
	if(isnull(input_amount))
		return TRUE
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
	own_take(src, nameof(beaker))
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

	if(operable())
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
	return maker_menu_stage(user, list())

/obj/machinery/injector_maker/proc/maker_menu_stage(mob/user, list/maker_answers)
	if(user.incapacitated() || !beaker)
		return

	if(!("a3" in maker_answers))
		open_request(src, /datum/prompt/choice/injector_maker_review, PROC_REF(maker_request_answered), answerer = user, maker_operator = user, maker_answers = maker_answers, maker_key = "a3", maker_route = MAKER_REQUEST_MENU, question = "There are [src.count_small_injector] small and [src.count_large_injector]  large injectors left.", title = "Choose what to do", choices = list("large injector", "small injector", "eject beaker", "cancel"))
		return
	var/choice = maker_answers["a3"]
	if(isnull(choice))
		return

	switch(choice)
		if("cancel")
			return
		if("eject beaker")
			if(!user.incapacitated() && Adjacent(user))
				user.put_in_hands(beaker)
			else
				beaker.forceMove(drop_location())
			own_take(src, nameof(beaker))
			update_icon()


		if("small injector")
			if(!("a4" in maker_answers))
				open_request(src, /datum/prompt/choice/injector_maker_review, PROC_REF(maker_request_answered), answerer = user, maker_operator = user, maker_answers = maker_answers, maker_key = "a4", maker_route = MAKER_REQUEST_MENU, question = "Use autoinjector storage, or mold new injectors to fill?", title = "Choose Material", choices = list("mold plastic", "use injectors"))
				return
			var/material = maker_answers["a4"]
			if(isnull(material))
				return
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
			if(!("a5" in maker_answers))
				open_request(src, /datum/prompt/number/injector_maker_review, PROC_REF(maker_request_answered), answerer = user, maker_operator = user, maker_answers = maker_answers, maker_key = "a5", maker_route = MAKER_REQUEST_MENU, question = "How many injectors would you like?", title = "Make small injectors", default = 0, maker_max = 100)
				return
			var/injector_amount = maker_answers["a5"]
			if(isnull(injector_amount))
				return
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
				if(!("a6" in maker_answers))
					open_request(src, /datum/prompt/text/injector_maker_review, PROC_REF(maker_request_answered), answerer = user, maker_operator = user, maker_answers = maker_answers, maker_key = "a6", maker_route = MAKER_REQUEST_MENU, question = "Name Injector", title = "Naming", max_len = 32, name_text = TRUE)
					return
				var/name = maker_answers["a6"]
				if(isnull(name))
					return
				make_injector("small injector", injector_amount, name, material, user)
				update_icon()


		if("large injector")
			if(!("a7" in maker_answers))
				open_request(src, /datum/prompt/choice/injector_maker_review, PROC_REF(maker_request_answered), answerer = user, maker_operator = user, maker_answers = maker_answers, maker_key = "a7", maker_route = MAKER_REQUEST_MENU, question = "Use autoinjector storage, or mold new injectors to fill?", title = "Choose Material", choices = list("mold plastic", "use injectors"))
				return
			var/material = maker_answers["a7"]
			if(isnull(material))
				return
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
			if(!("a8" in maker_answers))
				open_request(src, /datum/prompt/number/injector_maker_review, PROC_REF(maker_request_answered), answerer = user, maker_operator = user, maker_answers = maker_answers, maker_key = "a8", maker_route = MAKER_REQUEST_MENU, question = "How many injectors would you like?", title = "Make large injectors", default = 0, maker_max = 100)
				return
			var/injector_amount = maker_answers["a8"]
			if(isnull(injector_amount))
				return
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
				if(!("a9" in maker_answers))
					open_request(src, /datum/prompt/text/injector_maker_review, PROC_REF(maker_request_answered), answerer = user, maker_operator = user, maker_answers = maker_answers, maker_key = "a9", maker_route = MAKER_REQUEST_MENU, question = "Name Injector", title = "Naming", max_len = 32, name_text = TRUE)
					return
				var/name = maker_answers["a9"]
				if(isnull(name))
					return
				make_injector("large injector", injector_amount, name, material,user)
				update_icon()


/obj/machinery/injector_maker/proc/make_injector(size, amount, new_name, material, mob/user)
	return maker_create_stage(size, amount, new_name, material, user, list())

/obj/machinery/injector_maker/proc/maker_create_stage(size, amount, new_name, material, mob/user, list/maker_answers)
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
		if(!("a10" in maker_answers))
			open_request(src, /datum/prompt/choice/injector_maker_review, PROC_REF(maker_request_answered), answerer = user, maker_operator = user, maker_answers = maker_answers, maker_key = "a10", maker_route = MAKER_REQUEST_CREATE, maker_size = size, maker_amount = amount, maker_name = new_name, maker_material = material, question = "Heads up! Less than max volume per injector!\n Making [amount] [size](s) filled with [amount_per_injector] total reagent volume each!", title = "Proceed?", choices = list("No","Yes"), buttons = TRUE)
			return
		var/_answer_a10 = maker_answers["a10"]
		if(isnull(_answer_a10))
			return
		proceed = _answer_a10
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

/obj/machinery/injector_maker/ownership()
	. = ..()
	. += owns(nameof(beaker), policy = OWN_CONTAINED)

/obj/machinery/injector_maker/proc/maker_request_answered(datum/act/request/context)
	if(!context.answer)
		return
	. = maker_request_apply(context)
	SStgui.update_uis(src)

/obj/machinery/injector_maker/proc/maker_request_apply(datum/act/request/context)
	var/list/maker_answers
	var/maker_key
	var/maker_route
	var/mob/maker_operator
	var/obj/item/stack/maker_stack
	var/datum/interaction/maker_interaction
	var/maker_size
	var/maker_amount
	var/maker_name
	var/maker_material
	if(istype(context.answer, /datum/prompt/text/injector_maker_review))
		var/datum/prompt/text/injector_maker_review/ask_text = context.answer
		maker_answers = ask_text.maker_answers.Copy()
		maker_key = ask_text.maker_key
		maker_route = ask_text.maker_route
		maker_operator = ask_text.maker_operator
		maker_stack = ask_text.maker_stack
		maker_interaction = ask_text.maker_interaction
		maker_size = ask_text.maker_size
		maker_amount = ask_text.maker_amount
		maker_name = ask_text.maker_name
		maker_material = ask_text.maker_material
	else if(istype(context.answer, /datum/prompt/choice/injector_maker_review))
		var/datum/prompt/choice/injector_maker_review/ask_choice = context.answer
		maker_answers = ask_choice.maker_answers.Copy()
		maker_key = ask_choice.maker_key
		maker_route = ask_choice.maker_route
		maker_operator = ask_choice.maker_operator
		maker_stack = ask_choice.maker_stack
		maker_interaction = ask_choice.maker_interaction
		maker_size = ask_choice.maker_size
		maker_amount = ask_choice.maker_amount
		maker_name = ask_choice.maker_name
		maker_material = ask_choice.maker_material
	else if(istype(context.answer, /datum/prompt/number/injector_maker_review))
		var/datum/prompt/number/injector_maker_review/ask_number = context.answer
		maker_answers = ask_number.maker_answers.Copy()
		maker_key = ask_number.maker_key
		maker_route = ask_number.maker_route
		maker_operator = ask_number.maker_operator
		maker_stack = ask_number.maker_stack
		maker_interaction = ask_number.maker_interaction
		maker_size = ask_number.maker_size
		maker_amount = ask_number.maker_amount
		maker_name = ask_number.maker_name
		maker_material = ask_number.maker_material

	maker_answers[maker_key] = context.answer.value
	switch(maker_route)
		if(MAKER_REQUEST_PLASTIC)
			return maker_plastic_stage(maker_operator, maker_stack, maker_interaction, maker_answers)
		if(MAKER_REQUEST_DRAG)
			return maker_drag_stage(maker_operator, maker_stack, maker_interaction, maker_answers)
		if(MAKER_REQUEST_MENU)
			return maker_menu_stage(maker_operator, maker_answers)
		if(MAKER_REQUEST_CREATE)
			return maker_create_stage(maker_size, maker_amount, maker_name, maker_material, maker_operator, maker_answers)

/datum/prompt/text/injector_maker_review
	timeout = 0
	var/list/maker_answers
	var/maker_key
	var/maker_route
	var/mob/maker_operator
	var/maker_operator_expected = FALSE
	var/obj/item/stack/maker_stack
	var/maker_stack_expected = FALSE
	var/datum/interaction/maker_interaction
	var/maker_interaction_expected = FALSE
	var/maker_size
	var/maker_amount
	var/maker_name
	var/maker_material

CAPABILITIES(/datum/prompt/text/injector_maker_review)
	ref_one(nameof(maker_operator), /mob)
	ref_one(nameof(maker_stack), /obj/item/stack)
	ref_one(nameof(maker_interaction), /datum/interaction)

/datum/prompt/text/injector_maker_review/prepare(datum/act/context)
	. = ..()
	var/mob/captured_operator = maker_operator
	maker_operator_expected = !isnull(captured_operator)
	rel_clear(src, nameof(maker_operator))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(maker_operator), captured_operator)
	var/obj/item/stack/captured_stack = maker_stack
	maker_stack_expected = !isnull(captured_stack)
	rel_clear(src, nameof(maker_stack))
	if(captured_stack && !QDELETED(captured_stack))
		rel_set(src, nameof(maker_stack), captured_stack)
	var/datum/interaction/captured_interaction = maker_interaction
	maker_interaction_expected = !isnull(captured_interaction)
	rel_clear(src, nameof(maker_interaction))
	if(captured_interaction && !QDELETED(captured_interaction))
		rel_set(src, nameof(maker_interaction), captured_interaction)

/datum/prompt/text/injector_maker_review/recheck_extra()
	if((maker_operator_expected && QDELETED(maker_operator)) || (maker_stack_expected && QDELETED(maker_stack)) || (maker_interaction_expected && QDELETED(maker_interaction)))
		return "gone"

/datum/prompt/choice/injector_maker_review
	timeout = 0
	var/list/maker_answers
	var/maker_key
	var/maker_route
	var/mob/maker_operator
	var/maker_operator_expected = FALSE
	var/obj/item/stack/maker_stack
	var/maker_stack_expected = FALSE
	var/datum/interaction/maker_interaction
	var/maker_interaction_expected = FALSE
	var/maker_size
	var/maker_amount
	var/maker_name
	var/maker_material

CAPABILITIES(/datum/prompt/choice/injector_maker_review)
	ref_one(nameof(maker_operator), /mob)
	ref_one(nameof(maker_stack), /obj/item/stack)
	ref_one(nameof(maker_interaction), /datum/interaction)

/datum/prompt/choice/injector_maker_review/prepare(datum/act/context)
	. = ..()
	var/mob/captured_operator = maker_operator
	maker_operator_expected = !isnull(captured_operator)
	rel_clear(src, nameof(maker_operator))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(maker_operator), captured_operator)
	var/obj/item/stack/captured_stack = maker_stack
	maker_stack_expected = !isnull(captured_stack)
	rel_clear(src, nameof(maker_stack))
	if(captured_stack && !QDELETED(captured_stack))
		rel_set(src, nameof(maker_stack), captured_stack)
	var/datum/interaction/captured_interaction = maker_interaction
	maker_interaction_expected = !isnull(captured_interaction)
	rel_clear(src, nameof(maker_interaction))
	if(captured_interaction && !QDELETED(captured_interaction))
		rel_set(src, nameof(maker_interaction), captured_interaction)

/datum/prompt/choice/injector_maker_review/recheck_extra()
	if((maker_operator_expected && QDELETED(maker_operator)) || (maker_stack_expected && QDELETED(maker_stack)) || (maker_interaction_expected && QDELETED(maker_interaction)))
		return "gone"

/datum/prompt/number/injector_maker_review
	timeout = 0
	var/list/maker_answers
	var/maker_key
	var/maker_route
	var/mob/maker_operator
	var/maker_operator_expected = FALSE
	var/obj/item/stack/maker_stack
	var/maker_stack_expected = FALSE
	var/datum/interaction/maker_interaction
	var/maker_interaction_expected = FALSE
	var/maker_size
	var/maker_amount
	var/maker_name
	var/maker_material
	var/maker_min = 0
	var/maker_max = INFINITY

CAPABILITIES(/datum/prompt/number/injector_maker_review)
	ref_one(nameof(maker_operator), /mob)
	ref_one(nameof(maker_stack), /obj/item/stack)
	ref_one(nameof(maker_interaction), /datum/interaction)

/datum/prompt/number/injector_maker_review/prepare(datum/act/context)
	. = ..()
	var/mob/captured_operator = maker_operator
	maker_operator_expected = !isnull(captured_operator)
	rel_clear(src, nameof(maker_operator))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(maker_operator), captured_operator)
	var/obj/item/stack/captured_stack = maker_stack
	maker_stack_expected = !isnull(captured_stack)
	rel_clear(src, nameof(maker_stack))
	if(captured_stack && !QDELETED(captured_stack))
		rel_set(src, nameof(maker_stack), captured_stack)
	var/datum/interaction/captured_interaction = maker_interaction
	maker_interaction_expected = !isnull(captured_interaction)
	rel_clear(src, nameof(maker_interaction))
	if(captured_interaction && !QDELETED(captured_interaction))
		rel_set(src, nameof(maker_interaction), captured_interaction)

/datum/prompt/number/injector_maker_review/recheck_extra()
	if((maker_operator_expected && QDELETED(maker_operator)) || (maker_stack_expected && QDELETED(maker_stack)) || (maker_interaction_expected && QDELETED(maker_interaction)))
		return "gone"

/datum/prompt/number/injector_maker_review/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, maker_max, maker_min, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

#undef MAKER_REQUEST_PLASTIC
#undef MAKER_REQUEST_DRAG
#undef MAKER_REQUEST_MENU
#undef MAKER_REQUEST_CREATE
