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
TRACKED(/obj/machinery/injector_maker, count_large_injector)
TRACKED(/obj/machinery/injector_maker, count_plastic)
TRACKED(/obj/machinery/injector_maker, count_small_injector)


MSG_DEF_SELF(injector_maker/rack_full, "Storage is full.")
MSG_DEF_SELF(injector_maker/filled, "You cannot put a filled injector into the machine.")

CAPABILITIES(/obj/machinery/injector_maker)
	owns_one(nameof(beaker), /obj/item/reagent_containers)
	op("add_beaker", item(/obj/item/reagent_containers), when(req(list(/obj/item/reagent_containers/glass, /obj/item/reagent_containers/food/drinks/glass2, /obj/item/reagent_containers/food/drinks/shaker))),
		label("Add container"), then(PROC_REF(beaker_added)))
	op("add_small_injector", item(/obj/item/reagent_containers/hypospray/autoinjector/empty), label("Add injector"),
		needs(req(PROC_REF(small_rack_free)), req(PROC_REF(injector_empty))),
		then(PROC_REF(small_injector_added)))
	op("add_large_injector", item(/obj/item/reagent_containers/hypospray/autoinjector/biginjector/empty), label("Add injector"),
		needs(req(PROC_REF(large_rack_free)), req(PROC_REF(injector_empty))),
		then(PROC_REF(large_injector_added)))
	op("add_plastic", item(/obj/item/stack/material), label("Add plastic"), then(PROC_REF(plastic_added)))
	op("drag_plastic", item(/obj/item/stack/material/plastic), gesture(GESTURE_DRAG), label("Add plastic"), then(PROC_REF(plastic_dragged)))
	op("eject_beaker", hand(), ungated(), gesture(GESTURE_ALT), when(PROC_REF(has_beaker)), label("Eject beaker"), then(PROC_REF(beaker_ejected)))
	op("use", hand(), ungated(), label("Use"), then(PROC_REF(touched)))
	default_parts()

/// What it holds: a beaker, injectors, plastic, in every combination.
/obj/machinery/injector_maker/draw(datum/look/look)
	..()
	if(!beaker && !count_plastic && !count_small_injector && !count_large_injector) //Empty
		look.state("injector")
	else if(beaker != null && !count_plastic && !count_small_injector  && !count_large_injector ) //Has just beaker
		look.state("injector_b")
	else if(!beaker && !count_plastic && (count_large_injector > 0 || count_small_injector > 0)) //Has just injectors
		look.state("injector_i")
	else if(!beaker && count_plastic > 0 && !count_large_injector && !count_small_injector) //Has just plastic
		look.state("injector_p")
	else if(beaker != null && !count_plastic && (count_large_injector > 0 || count_small_injector > 0)) //beaker + injectors
		look.state("injector_ib")
	else if(beaker != null && count_plastic > 0 && !count_large_injector && !count_small_injector) //beaker + plastic
		look.state("injector_pb")
	else if(beaker != null && count_plastic > 0 && (count_large_injector > 0 || count_small_injector > 0)) //Has everything
		look.state("injector_ipb")


/// The old attackby: a beaker, a drinking glass or a shaker goes in.
/obj/machinery/injector_maker/proc/beaker_added(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if (beaker)
		return TRUE
	if(!move_into(src, nameof(src.beaker), O, user))
		return TRUE
	return TRUE

/// The small injector rack has room.
/obj/machinery/injector_maker/proc/small_rack_free(datum/act/op/A)
	return (count_small_injector < capacity_small_injector) ? null : MSG(injector_maker/rack_full)

/// The large injector rack has room.
/obj/machinery/injector_maker/proc/large_rack_free(datum/act/op/A)
	return (count_large_injector < capacity_large_injector) ? null : MSG(injector_maker/rack_full)

/// The held injector is empty.
/obj/machinery/injector_maker/proc/injector_empty(datum/act/op/A)
	return (!(A.held?.reagents?.total_volume > 0)) ? null : MSG(injector_maker/filled)

/// An empty small injector goes on its rack.
/obj/machinery/injector_maker/proc/small_injector_added(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/E = A.held
	set_count_small_injector(count_small_injector + 1)
	consume(E, user)
	return TRUE

/// An empty large injector goes on its rack.
/obj/machinery/injector_maker/proc/large_injector_added(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/E = A.held
	set_count_large_injector(count_large_injector + 1)
	consume(E, user)
	return TRUE

/// Plastic sheets in hand: asks how many go in. Any other material is not taken: the click goes on (to the swallow below), as before.
/obj/machinery/injector_maker/proc/plastic_added(datum/act/op/A)
	var/obj/item/stack/S = A.held
	if(S.get_material_name() != MAT_PLASTIC)
		return OP_DECLINE
	return maker_plastic_stage(A.actor, S, list())

/obj/machinery/injector_maker/proc/maker_plastic_stage(mob/user, obj/item/stack/S, list/maker_answers)
	if(!("a1" in maker_answers))
		open_request(src, /datum/prompt/number/injector_maker_review, PROC_REF(maker_request_answered), answerer = user, maker_operator = user, maker_answers = maker_answers, maker_key = "a1", maker_route = MAKER_REQUEST_PLASTIC, maker_stack = S, question = "How many sheets would you like to add?", title = "Add plastic", default = 0, maker_max = S.get_amount())
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
		set_count_plastic(count_plastic + plastic_input)
	return TRUE

/// The old adjacency/consciousness checks were silent (no message), so they stay in the effect.
/obj/machinery/injector_maker/proc/plastic_dragged(datum/act/op/A)
	return maker_drag_stage(A.actor, A.held, list())

/obj/machinery/injector_maker/proc/maker_drag_stage(mob/user, obj/item/stack/material/plastic/plastic_stack, list/maker_answers)
	if(!isliving(user) || user.stat || !Adjacent(user) || !Adjacent(plastic_stack))
		return TRUE
	if(!("a2" in maker_answers))
		open_request(src, /datum/prompt/number/injector_maker_review, PROC_REF(maker_request_answered), answerer = user, maker_operator = user, maker_answers = maker_answers, maker_key = "a2", maker_route = MAKER_REQUEST_DRAG, maker_stack = plastic_stack, question = "How many sheets would you like to add?", title = "Add plastic", default = 0, maker_max = plastic_stack.get_amount())
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
		set_count_plastic(count_plastic + plastic_input)
	return TRUE

/// A beaker is in.
/obj/machinery/injector_maker/proc/has_beaker(datum/act/op/A)
	return !!beaker

/// The old click_alt ran the base first, then ejected the beaker: the alt-click goes on after this (OP_PASS).
/obj/machinery/injector_maker/proc/beaker_ejected(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.incapacitated() && Adjacent(user))
		user.put_in_hands(beaker)
	else
		beaker.forceMove(drop_location())
	rel_take(src, nameof(beaker))
	return OP_PASS

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

/// The old attack_hand (it had no gate at all): the menu.
/obj/machinery/injector_maker/proc/touched(datum/act/op/A)
	interact(A.actor)
	return OP_OK

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
			rel_take(src, nameof(beaker))


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
							set_count_plastic(src.count_plastic - cost_plastic_small)
					if("use injectors")
						if(!src.count_small_injector)
							return
						else
							set_count_small_injector(src.count_small_injector - 1)
				var/obj/item/reagent_containers/hypospray/autoinjector/empty/P = new(loc)
				beaker.reagents.trans_to_obj(P, amount_per_injector)
				if(new_name)
					P.name = new_name


			if("large injector")
				switch(material)
					if("mold plastic")
						if(src.count_plastic < cost_plastic_large)
							return
						else
							set_count_plastic(src.count_plastic - cost_plastic_large)
					if("use injectors")
						if(!src.count_large_injector)
							return
						else
							set_count_large_injector(src.count_large_injector - 1)
				var/obj/item/reagent_containers/hypospray/autoinjector/biginjector/empty/P = new(loc)
				beaker.reagents.trans_to_obj(P, amount_per_injector)
				if(new_name)
					P.name = new_name

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
		maker_size = ask_number.maker_size
		maker_amount = ask_number.maker_amount
		maker_name = ask_number.maker_name
		maker_material = ask_number.maker_material

	maker_answers[maker_key] = context.answer.value
	switch(maker_route)
		if(MAKER_REQUEST_PLASTIC)
			return maker_plastic_stage(maker_operator, maker_stack, maker_answers)
		if(MAKER_REQUEST_DRAG)
			return maker_drag_stage(maker_operator, maker_stack, maker_answers)
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
	var/maker_size
	var/maker_amount
	var/maker_name
	var/maker_material

CAPABILITIES(/datum/prompt/text/injector_maker_review)
	ref_one(nameof(maker_operator), /mob)
	ref_one(nameof(maker_stack), /obj/item/stack)

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

/datum/prompt/text/injector_maker_review/recheck_extra()
	if((maker_operator_expected && QDELETED(maker_operator)) || (maker_stack_expected && QDELETED(maker_stack)))
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
	var/maker_size
	var/maker_amount
	var/maker_name
	var/maker_material

CAPABILITIES(/datum/prompt/choice/injector_maker_review)
	ref_one(nameof(maker_operator), /mob)
	ref_one(nameof(maker_stack), /obj/item/stack)

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

/datum/prompt/choice/injector_maker_review/recheck_extra()
	if((maker_operator_expected && QDELETED(maker_operator)) || (maker_stack_expected && QDELETED(maker_stack)))
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
	var/maker_size
	var/maker_amount
	var/maker_name
	var/maker_material
	var/maker_min = 0
	var/maker_max = INFINITY

CAPABILITIES(/datum/prompt/number/injector_maker_review)
	ref_one(nameof(maker_operator), /mob)
	ref_one(nameof(maker_stack), /obj/item/stack)

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

/datum/prompt/number/injector_maker_review/recheck_extra()
	if((maker_operator_expected && QDELETED(maker_operator)) || (maker_stack_expected && QDELETED(maker_stack)))
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
