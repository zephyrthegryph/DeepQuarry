// This folder contains code that was originally ported from Apollo Station and then refactored/optimized/changed.

// Root type for cooking machines. See following files for specific implementations.
/obj/machinery/appliance
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "cooker"
	desc = "You shouldn't be seeing this!"
	icon = 'icons/obj/cooking_machines.dmi'
	var/appliancetype = 0
	density = TRUE
	anchored = TRUE

	use_power = USE_POWER_IDLE
	idle_power_usage = 5			// Power used when turned on, but not processing anything
	active_power_usage = 1000		// Power used when turned on and actively cooking something

	var/cooking_power = 0			// Effectiveness/speed at cooking
	var/cooking_coeff = 0			// Optimal power * proximity to optimal temp; used to calc. cooking power.
	var/heating_power = 1000		// Effectiveness at heating up; not used for mixers, should be equal to active_power_usage
	var/max_contents = 1			// Maximum number of things this appliance can simultaneously cook
	var/on_icon						// Icon state used when cooking.
	var/off_icon					// Icon state used when not cooking.
	var/cook_type					// A string value used to track what kind of food this machine makes.
	var/can_cook_mobs				// Whether or not this machine accepts grabbed mobs.
	var/mob_injury_kind = INJURY_BLUNT	// What a mob stuffed inside suffers: burns for cooking appliances, bruising for cereal/candy
	var/food_color					// Colour of resulting food item.
	var/cooked_sound = SFX_MACHINES_DING				// Sound played when cooking completes.
	var/can_burn_food = FALSE		// Can the object burn food that is left inside?
	var/burn_chance = 10			// How likely is the food to burn?
	var/list/cooking_objs	// List of things being cooked

	// If the machine has multiple output modes, define them here.
	var/selected_option
	var/list/output_options

	var/container_type = null

	var/combine_first = FALSE // If TRUE, this appliance will do combination cooking before checking recipes
	var/food_safety = FALSE	// If true, the appliance automatically ejects food instead of burning it

	var/static/radial_eject = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_eject")
	var/static/radial_power = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_power")
	var/static/radial_safety = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_safety")
	var/static/radial_output = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_change_output")

CAPABILITIES(/obj/machinery/appliance)
	started_work(step = PROC_REF(work_step), starts = TRUE, gate = PROC_REF(needs_step), wakes_on = list(nameof(cooking), nameof(stat)))
	owns_many(nameof(cooking_objs))
	// the AI's ctrl-click switches it on or off over its link
	op("remote_power", remote(), gesture(GESTURE_CTRL), when(req_actor_kind(/mob/living/silicon/ai)), label("Toggle power"),
		wait(0), then(PROC_REF(remote_power)))
	interface(null, window_var = nameof(tgui_id))
	without("ui_open")
	op("toggle_power", ui_act("toggle_power"), then(PROC_REF(ui_act_toggle_power)))
	op("toggle_safety", ui_act("toggle_safety"), then(PROC_REF(ui_act_toggle_safety)))
	op("change_output", ui_act("change_output", arg("value")), then(PROC_REF(ui_act_change_output)))
	op("slot", ui_act("slot", arg("slot", num())), then(PROC_REF(ui_act_slot)))
	op("remove_menu", ui_act("remove_menu"), then(PROC_REF(ui_act_remove_menu)))
	op("appliance_interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req(PROC_REF(can_take_item_holds), because = PROC_REF(can_take_item_refusal))), then(PROC_REF(appliance_interaction_item)))
	op("appliance_interaction_hand", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(appliance_interaction_hand)))
	op("appliance_toggle_power_effect", menu(), label("Toggle Power"), needs(req_adjacent(), req_capable(), req(PROC_REF(can_toggle_power_verb_holds), because = PROC_REF(can_toggle_power_verb_refusal))), then(PROC_REF(appliance_toggle_power_effect)))
	default_parts()

/// Whether or not the machine is currently operating (cooking its contents).
OM_FIELD(/obj/machinery/appliance, cooking, FALSE, CHANGE_MACHINE_SETTINGS)

// cooking food and its containers go with the machine.
/obj/machinery/appliance/on_destroy(force)
	for(var/datum/cooking_item/CI as anything in cooking_objs?.Copy())
		destroyed(CI.container(), src)//Food is fragile, it probably doesnt survive the destruction of the machine
		own_take_member(src, nameof(cooking_objs), CI)
		ended_with(CI, src)
	..()

/obj/machinery/appliance/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += list_contents(user)

/obj/machinery/appliance/proc/list_contents(mob/user)
	if (length(cooking_objs))
		var/string = "Contains..."
		for(var/datum/cooking_item/CI as anything in cooking_objs)
			string += "-\a [CI.container().label(null, CI.combine_target)], [report_progress(CI)]</br>"
		return string
	else
		to_chat(user, span_notice("It is empty."))

/// list(colour, text) per cooking stage for the tgui panel, indexed by report_progress_tgui(). Shared, read-only.
GLOBAL_LIST_INIT(appliance_progress_texts, list( 	list("average", "Not Cooking."), 	list("blue", "Cold."), 	list("blue", "It's barely started cooking."), 	list("average", "It's cooking away nicely."), 	list("good", "It's almost ready!"), 	list("good", "It's done!"), 	list("bad", "It looks overcooked, get it out!"), 	list("bad", "It is burning!"), ))

/obj/machinery/appliance/proc/report_progress_tgui(datum/cooking_item/CI)
	var/list/texts = GLOB.appliance_progress_texts
	if(!CI || !CI.max_cookwork)
		return texts[1]

	if(!CI.cookwork)
		return texts[2]

	var/progress = CI.cookwork / CI.max_cookwork

	if (progress < 0.25)
		return texts[3]
	if (progress < 0.75)
		return texts[4]
	if (progress < 1)
		return texts[5]

	var/half_overcook = (CI.overcook_mult - 1)*0.5
	if (progress < 1+half_overcook)
		return texts[6]
	if (progress < CI.overcook_mult)
		return texts[7]
	else
		return texts[8]

/obj/machinery/appliance/proc/report_progress(datum/cooking_item/CI)
	if (!CI || !CI.max_cookwork)
		return null

	if (!CI.cookwork)
		return "It is cold."
	var/progress = CI.cookwork / CI.max_cookwork

	if (progress < 0.25)
		return "It's barely started cooking."
	if (progress < 0.75)
		return span_notice("It's cooking away nicely.")
	if (progress < 1)
		return span_boldnotice("It's almost ready!")

	var/half_overcook = (CI.overcook_mult - 1)*0.5
	if (progress < 1+half_overcook)
		return span_soghun(span_bold("It is done!"))
	if (progress < CI.overcook_mult)
		return span_warning("It looks overcooked, get it out!")
	else
		return span_danger("It is burning!")

/// Appearance reader: powered and holding something to cook.
/obj/machinery/appliance/proc/appearance_cooking()
	return !has_stat(MACHINE_STAT_ANY) && length(cooking_objs)

APPEARANCE_TEMPLATE(/obj/machinery/appliance, "{appearance_cooking?@on_icon:@off_icon}")

/obj/machinery/appliance/proc/appliance_toggle_power_effect(datum/act/op/A)
	var/mob/user = A.actor

	attempt_toggle_power(user)

/obj/machinery/appliance/proc/attempt_toggle_power(mob/user)
	if (!isliving(user))
		return

	if (!user.IsAdvancedToolUser())
		to_chat(user, span_warning("You lack the dexterity to do that!"))
		return

	if (user.stat || user.restrained() || user.incapacitated())
		return

	if (!Adjacent(user) && !issilicon(user))
		to_chat(user, span_warning("You can't reach [src] from here!"))
		return

	if (has_stat(POWEROFF))//Its turned off
		stat_remove(POWEROFF)
		set_use_power(1)
		act_message(user, src, MSG_SELF(span_filter_notice("You turn on %T%.")), MSG_OTHERS(span_filter_notice("%U% turns %T% on.")))

	else //Its on, turn it off
		stat_add(POWEROFF)
		set_use_power(0)
		act_message(user, src, MSG_SELF(span_filter_notice("You turn off %T%.")), MSG_OTHERS(span_filter_notice("%U% turns %T% off.")))
		set_cooking(FALSE) // Stop cooking here, too, just in case.

	play_sfx(src, SFX_MACHINES_CLICK, 0.8)
	update_icon()

/obj/machinery/appliance/proc/remote_power(datum/act/op/A)
	attempt_toggle_power(A.actor)
	return OP_OK

/obj/machinery/appliance/proc/choose_output(mob/user, new_output)
	if (!user.IsAdvancedToolUser())
		to_chat(user, span_filter_notice("You lack the dexterity to do that!"))
		return

	if(!LAZYACCESS(output_options, new_output))
		return

	if(new_output == "Default")
		selected_option = null
		to_chat(user, span_notice("You decide not to make anything specific with \the [src]."))
		return

	selected_option = new_output
	to_chat(user, span_notice("You prepare \the [src] to make \a [selected_option] with the next thing you put in. Try putting several ingredients in a container!"))

//Handles all validity checking and error messages for inserting things
/obj/machinery/appliance/proc/can_insert(obj/item/I, mob/user)
	if(istype(I.loc, /mob/living/silicon))
		return 0
	else if (istype(I.loc, /obj/item/rig_module))
		return 0

	// We are trying to cook a grabbed mob.
	var/obj/item/grab/G = I
	if(istype(G))

		if(!can_cook_mobs)
			to_chat(user, span_warning("That's not going to fit."))
			return 0

		if(!isliving(G?.grab_target()))
			to_chat(user, span_warning("You can't cook that."))
			return 0

		return 2

	if (!has_space(I))
		to_chat(user, span_warning("There's no room in [src] for that!"))
		return 0

	if (container_type && istype(I, container_type))
		return 1

	// We're trying to cook something else. Check if it's valid.
	var/obj/item/reagent_containers/food/snacks/check = I
	if(istype(check, /obj/item/reagent_containers/glass))
		to_chat(user, span_warning("That would probably break [src]."))
		return 0
	else if(istype(check, /obj/item/disk/nuclear))
		to_chat(user, span_warning("You can't cook that."))
		return 0
	else if(I.has_tool_quality(TOOL_CROWBAR) || I.has_tool_quality(TOOL_SCREWDRIVER) || istype(I, /obj/item/storage/part_replacer)) // You can't cook tools, dummy.
		return 0
	else if(!istype(check) &&  !istype(check, /obj/item/holder))
		to_chat(user, span_warning("That's not edible."))
		return 0

	return 1

//This function is overridden by cookers that do stuff with containers
/obj/machinery/appliance/proc/has_space(obj/item/I)
	if(length(cooking_objs) >= max_contents)
		return FALSE

	return TRUE

/// Requirement (was REQ_* can_take_item): the legacy check answers TRUE to pass.
/obj/machinery/appliance/proc/can_take_item_holds(datum/act/op/A)
	var/answer = can_take_item(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_take_item_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/appliance/proc/can_take_item_refusal(datum/act/op/A)
	var/answer = can_take_item(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/// Requirement (was REQ_* can_toggle_power_verb): the legacy check answers TRUE to pass.
/obj/machinery/appliance/proc/can_toggle_power_verb_holds(datum/act/op/A)
	var/answer = can_toggle_power_verb(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_toggle_power_verb_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/appliance/proc/can_toggle_power_verb_refusal(datum/act/op/A)
	var/answer = can_toggle_power_verb(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/// Requirement: the appliance works.
/obj/machinery/appliance/proc/can_take_item(mob/user, atom/target, obj/item/held)
	if(!cook_type || has_stat(BROKEN))
		return "\The [src] is not working"
	return TRUE

/// Requirement: TRUE, or why the power verb is refused (subtypes add their own conditions).
/obj/machinery/appliance/proc/can_toggle_power_verb(mob/user, atom/target, obj/item/held)
	return TRUE

/// Old subtype attackby: part replacement first, then the appliance's own item handling.
/obj/machinery/appliance/proc/appliance_interaction_part_replace(datum/act/op/A)
	if(default_part_replacement(A.actor, A.held))
		return OP_PASS
	return OP_DECLINE

/// Old attackby.
/obj/machinery/appliance/proc/appliance_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	var/obj/item/ToCook = I

	if(istype(I, /obj/item/gripper))
		var/obj/item/gripper/GR = I
		var/obj/item/wrap = GR.get_wrapped_item()
		if(wrap)
			var/result = can_insert(wrap, user)
			if(!result)
				default_part_replacement(user, I)
				return OP_OK
			add_content(wrap, user)
			update_icon()
			return OP_PASS

		attack_hand(user)
		return OP_OK

	var/result = can_insert(I, user)
	if(!result)
		default_part_replacement(user, I)
		return OP_PASS

	if(result == 2)
		var/obj/item/grab/G = I
		if (G && istype(G) && G?.grab_target())
			cook_mob(G?.grab_target(), user)
			return OP_PASS

	//From here we can start cooking food
	add_content(ToCook, user)
	update_icon()
	return OP_PASS

//Override for container mechanics
/obj/machinery/appliance/proc/add_content(obj/item/I, mob/user)
	if(!user.unEquip(I) && !isturf(I.loc))
		return

	var/datum/cooking_item/CI = has_space(I)
	if (istype(I, /obj/item/reagent_containers/cooking_container) && CI == 1)
		var/obj/item/reagent_containers/cooking_container/CC = I
		CI = new /datum/cooking_item/(CC)
		I.forceMove(src)
		rel_add(src, nameof(cooking_objs), CI)
		act_message(user, src, others = span_infoplain(span_bold("%U%") + " puts %I% into %T%."), item = I)
		if (CC.check_contents() == 0)//If we're just putting an empty container in, then dont start any processing.
			return TRUE
	else
		if (CI && istype(CI))
			I.forceMove(CI.container())

		else //Something went wrong
			return FALSE

	if (selected_option)
		CI.combine_target = selected_option

	// We can actually start cooking now.
	act_message(user, src, others = span_infoplain(span_bold("%U%") + " puts %I% into %T%."), item = I)

	get_cooking_work(CI)
	set_cooking(TRUE)
	return CI

/obj/machinery/appliance/proc/get_cooking_work(datum/cooking_item/CI)
	for (var/obj/item/J in CI.container())
		cookwork_by_item(J, CI)

	for(var/datum/reagent/R as anything in CI.container().reagents.reagent_list)
		if (istype(R, /datum/reagent/nutriment))
			CI.max_cookwork += R.volume *2//Added reagents contribute less than those in food items due to granular form

			//Nonfat reagents will soak oil
			if (!istype(R, /datum/reagent/nutriment/triglyceride))
				CI.max_oil += R.volume * 0.25
		else
			CI.max_cookwork += R.volume
			CI.max_oil += R.volume * 0.10

	//Rescaling cooking work to avoid insanely long times for large things
	var/buffer = CI.max_cookwork
	CI.max_cookwork = 0
	var/multiplier = 0.35
	var/step = 4
	while (buffer > step)
		buffer -= step
		CI.max_cookwork += step*multiplier
		multiplier *= 0.95

	CI.max_cookwork += buffer*multiplier

//Just a helper to save code duplication in the above
/obj/machinery/appliance/proc/cookwork_by_item(obj/item/I, datum/cooking_item/CI)
	var/obj/item/reagent_containers/food/snacks/S = I
	var/work = 0
	if (istype(S))
		if (S.reagents)
			for(var/datum/reagent/R as anything in S.reagents.reagent_list)
				if (istype(R, /datum/reagent/nutriment))
					work += R.volume *3//Core nutrients contribute much more than peripheral chemicals

					//Nonfat reagents will soak oil
					if (!istype(R, /datum/reagent/nutriment/triglyceride))
						CI.max_oil += R.volume * 0.35
				else
					work += R.volume
					CI.max_oil += R.volume * 0.15

	else if(istype(I, /obj/item/holder))
		var/obj/item/holder/H = I
		if (H.held_mob)
			work += ((H.held_mob.mob_size * H.held_mob.size_multiplier) * (H.held_mob.mob_size * H.held_mob.size_multiplier) * 2)+2

	CI.max_cookwork += work

//Called every tick while we're cooking something
/obj/machinery/appliance/proc/do_cooking_tick(datum/cooking_item/CI)
	if (!istype(CI) || !CI.max_cookwork)
		return FALSE

	var/was_done = FALSE
	if (CI.cookwork >= CI.max_cookwork)
		was_done = TRUE

	CI.cookwork += cooking_power

	if (!was_done && CI.cookwork >= CI.max_cookwork)
		//If cookwork has gone from above to below 0, then this item finished cooking
		finish_cooking(CI)

	else if (!CI.burned && CI.cookwork > min(CI.max_cookwork * CI.overcook_mult, CI.max_cookwork + 30))
		if(!food_safety)
			burn_food(CI)
		else
			eject(CI, null)

	// Gotta hurt.
	for(var/obj/item/holder/H in CI.container().contents)
		var/mob/living/M = H.held_mob
		if(M)
			M.injure(mob_injury_kind, rand(1,3) * (1/M.size_multiplier), pick(BP_ALL), source = src)

	return TRUE

/// Whether its step has work: an appliance steps while it cooks (a cooker also while it keeps its heat).
/obj/machinery/appliance/proc/needs_step(datum/act/A)
	return cooking

/obj/machinery/appliance/proc/work_step(datum/act/timer/A)
	if(cooking_power <= 0 || !cooking)
		return PROCESS_KILL
	var/all_done_cooking = TRUE
	for(var/datum/cooking_item/CI in cooking_objs)
		do_cooking_tick(CI)
		if(CI.max_cookwork > 0)
			all_done_cooking = FALSE
	if(all_done_cooking)
		set_cooking(FALSE)
		update_icon()
		return PROCESS_KILL

/obj/machinery/appliance/proc/predict_cooking(datum/cooking_item/CI)
	var/datum/recipe/recipe = null
	var/atom/C = null
	if(CI.container())
		C = CI.container()
	else
		C = src
	recipe = select_recipe(GLOB.available_recipes[appliancetype], C)

	var/list/results = list()
	if(recipe)
		var/obj/O = recipe.result
		results += initial(O.name)
	else if(CI.combine_target)
		results += predict_combination(CI)
	else
		for(var/obj/item/I in CI.container())
			results += predict_modification(I, CI)

	return jointext(results, ", ")

/obj/machinery/appliance/proc/predict_combination(datum/cooking_item/CI)
	var/obj/cook_path = LAZYACCESS(output_options, CI.combine_target)

	var/list/words = list()

	for(var/obj/item/reagent_containers/food/snacks/S in CI.container())
		words |= splittext(S.name, " ")

	//Set the name.
	words -= list("and", "the", "in", "is", "bar", "raw", "sticks", "boiled", "fried", "deep", "-o-", "warm", "two", "flavored")
	//Remove common connecting words and unsuitable ones from the list. Unsuitable words include those describing
	//the shape, cooked-ness/temperature or other state of an ingredient which doesn't apply to the finished product
	var/name = initial(cook_path.name)
	words.Remove(name)
	shuffle(words)
	var/num = 6 //Maximum number of words
	while (num > 0)
		num--
		if (!words.len)
			break
		//Add prefixes from the ingredients in a random order until we run out or hit limit
		name = "[pop(words)] [name]"

	return name

/obj/machinery/appliance/proc/predict_modification(obj/item/input, datum/cooking_item/CI)
	return "[cook_type] [input.name]"

/obj/machinery/appliance/proc/finish_cooking(datum/cooking_item/CI)
	src.visible_message(span_infoplain(span_bold("\The [src]") + " pings!"))
	if(cooked_sound)
		playsound(get_turf(src), cooked_sound, 50, 1)
	//Check recipes first, a valid recipe overrides other options
	var/datum/recipe/recipe = null
	var/atom/C = null
	if (CI.container())
		C = CI.container()
	else
		C = src
	recipe = select_recipe(GLOB.available_recipes[appliancetype],C)

	if (recipe)
		CI.result_type = 4//Recipe type, a specific recipe will transform the ingredients into a new food
		var/list/results = recipe.make_food(C)

		var/obj/temp = new /obj(src) //To prevent infinite loops, all results will be moved into a temporary location so they're not considered as inputs for other recipes

		for (var/atom/movable/AM in results)
			AM.forceMove(temp)

		//making multiple copies of a recipe from one container. For example, tons of fries
		while (select_recipe(GLOB.available_recipes[appliancetype],C) == recipe)
			var/list/TR = list()
			TR += recipe.make_food(C)
			for (var/atom/movable/AM in TR) //Move results to buffer
				AM.forceMove(temp)
			results += TR

		for(var/obj/item/reagent_containers/food/snacks/R as anything in results)
			R.forceMove(C) //Move everything from the buffer back to the container

		QDEL_NULL(temp) //delete buffer object
		. = 1 //None of the rest of this function is relevant for recipe cooking

	else if(CI.combine_target)
		CI.result_type = 3//Combination type. We're making something out of our ingredients
		. = combination_cook(CI)

	else
		//Otherwise, we're just doing standard modification cooking. change a color + name
		for (var/obj/item/i in CI.container())
			modify_cook(i, CI)

	//Final step. Cook function just cooks batter for now.
	for (var/obj/item/reagent_containers/food/snacks/S in CI.container())
		if(!S.heat_cooked)
			S.heat_cooked = TRUE
			S.cook()

//Combination cooking involves combining the names and reagents of ingredients into a predefined output object
//The ingredients represent flavours or fillings. EG: donut pizza, cheese bread
/obj/machinery/appliance/proc/combination_cook(datum/cooking_item/CI)
	var/cook_path = LAZYACCESS(output_options, CI.combine_target)

	var/list/words = list()
	var/datum/reagents/buffer = new /datum/reagents(1000)
	var/totalcolour
	var/reagents_determine_color

	if(!LAZYLEN(CI.container().contents))	// It's possible to make something, such as a cake in the oven, with only reagents. This stops them from being grey and sad.
		reagents_determine_color = TRUE

	for (var/obj/item/I in CI.container())
		var/obj/item/reagent_containers/food/snacks/S
		if (istype(I, /obj/item/holder))
			S = create_mob_food(I, CI)
		else if (istype(I, /obj/item/reagent_containers/food/snacks))
			S = I

		if (!S)
			continue

		words |= splittext(S.name," ")

		if (S.reagents && S.reagents.total_volume > 0)
			if (S.filling_color)
				if (!totalcolour || !buffer.total_volume)
					totalcolour = S.filling_color
				else
					var/t = buffer.total_volume + S.reagents.total_volume
					t = buffer.total_volume / t
					totalcolour = BlendRGB(totalcolour, S.filling_color, t)
					//Blend colours in order to find a good filling color

			S.reagents.trans_to_holder(buffer, S.reagents.total_volume)
		//Cleanup these empty husk ingredients now
		if (I)
			consumed(I, src)
			CI.container().set_food_items(CI.container().food_items - 1)
		if(S && !QDELETED(S)) //Incase I = S up there.
			consumed(S, src)
			CI.container().set_food_items(CI.container().food_items - 1)

	CI.container().reagents.trans_to_holder(buffer, CI.container().reagents.total_volume)

	var/obj/item/reagent_containers/food/snacks/result = new cook_path(CI.container())
	CI.container().set_food_items(CI.container().food_items + 1)
	buffer.trans_to_holder(result.reagents, buffer.total_volume)	//trans_to doesn't handle food items well, so
																	//just call trans_to_holder instead

	// Reagent-only foods.
	if(reagents_determine_color)
		totalcolour = result.reagents.get_color()

		for(var/datum/reagent/reag in result.reagents.reagent_list)
			words |= text2list(reag.name, " ")

	//Filling overlay
	var/image/I = image(result.icon, "[result.icon_state]_filling")
	I.color = totalcolour
	result.add_overlay(I)
	result.filling_color = totalcolour

	//Set the name.
	words -= list("and", "the", "in", "is", "bar", "raw", "sticks", "boiled", "fried", "deep", "-o-", "warm", "two", "flavored")
	//Remove common connecting words and unsuitable ones from the list. Unsuitable words include those describing
	//the shape, cooked-ness/temperature or other state of an ingredient which doesn't apply to the finished product
	words.Remove(result.name)
	shuffle(words)
	var/num = 6 //Maximum number of words
	while (num > 0)
		num--
		if (!words.len)
			break
		//Add prefixes from the ingredients in a random order until we run out or hit limit
		result.name = "[pop(words)] [result.name]"

	//This proc sets the size of the output result
	result.update_icon()
	return result

//Helper proc for standard modification cooking
/obj/machinery/appliance/proc/modify_cook(obj/item/input, datum/cooking_item/CI)
	var/obj/item/reagent_containers/food/snacks/result
	if (istype(input, /obj/item/holder))
		result = create_mob_food(input, CI)
	else if (istype(input, /obj/item/reagent_containers/food/snacks))
		result = input
	else
		//Nonviable item
		return

	if (!result)
		return

	// Set icon and appearance.
	change_product_appearance(result, CI)

	// Update strings.
	change_product_strings(result, CI)

/obj/machinery/appliance/proc/burn_food(datum/cooking_item/CI)
	// You dun goofed.
	CI.burned = 1
	CI.container().clear()
	new /obj/item/reagent_containers/food/snacks/badrecipe(CI.container())

	// Produce nasty smoke.
	visible_message(span_danger("\The [src] vomits a gout of rancid smoke!"))
	var/datum/effect/effect/system/smoke_spread/bad/burntfood/smoke = new /datum/effect/effect/system/smoke_spread/bad/burntfood
	play_sfx(src, SFX_EFFECTS_SMOKE, 0.4, extrarange = 0)
	smoke.attach(src)
	smoke.set_up(10, 0, get_turf(src), 300)
	smoke.start()

	// Chance to make a terrible fire
	if(prob(70))
		var/turf/T = get_turf(src)
		T.lingering_fire(0.45)

	// Set off fire alarms!
	var/area/area_to_check = get_area(src)
	for(var/obj/machinery/firealarm/FA in area_to_check.get_contents())
		if(FA && FA.detecting)
			FA.alarm()
			break

/// Old attack_hand.
/obj/machinery/appliance/proc/appliance_interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(tgui_id)
		tgui_interact(user)
		return OP_OK
	return OP_DECLINE

/obj/machinery/appliance/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["safety"] = food_safety
	data["selected_option"] = selected_option
	var/list/merged_1 = ui_data_obj_machinery_appliance(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/appliance's window data.
/obj/machinery/appliance/proc/ui_data_obj_machinery_appliance(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["on"] = !has_stat(POWEROFF)
	data["containersRemovable"] = can_remove_items(user, show_warning = FALSE)
	data["output_options"] = (output_options || list())

	var/list/our_contents = list()
	for(var/i in 1 to max_contents)
		UNTYPED_LIST_ADD(our_contents, list("empty" = TRUE))
		if(i <= LAZYLEN(cooking_objs))
			var/datum/cooking_item/CI = LAZYACCESS(cooking_objs, i)
			if(istype(CI))
				our_contents[i] = list()
				our_contents[i]["progress"] = 0
				our_contents[i]["progressText"] = report_progress_tgui(CI)
				our_contents[i]["prediction"] = predict_cooking(CI)
				if(CI.max_cookwork)
					our_contents[i]["progress"] = CI.cookwork / CI.max_cookwork
				if(CI.container())
					our_contents[i]["container"] = CI.container().label(i)
				else
					our_contents[i]["container"] = null
	data["our_contents"] = our_contents

	return data

/obj/machinery/appliance/proc/ui_act_toggle_power(datum/act/op/A)
	var/mob/user = A.actor
	attempt_toggle_power(user)
	return TRUE

/obj/machinery/appliance/proc/ui_act_toggle_safety(datum/act/op/A)
	var/mob/user = A.actor
	toggle_safety(user)
	return TRUE

/obj/machinery/appliance/proc/ui_act_change_output(datum/act/op/A, value)
	var/mob/user = A.actor
	choose_output(user, value)
	return TRUE

/obj/machinery/appliance/proc/ui_act_slot(datum/act/op/A, slot_arg)
	var/mob/user = A.actor
	var/slot = slot_arg
	var/obj/item/I = user.get_active_hand()
	if(slot <= LAZYLEN(cooking_objs)) // Inserting
		var/datum/cooking_item/CI = LAZYACCESS(cooking_objs, slot)

		if(istype(I) && can_insert(I)) // Why do hard work when we can just make them smack us?
			attackby(I, user)
		else if(istype(CI) && can_remove_items(user))
			eject(CI, user)
		return TRUE
	if(istype(I)) // Why do hard work when we can just make them smack us?
		attackby(I, user)
	return TRUE

/obj/machinery/appliance/proc/ui_act_remove_menu(datum/act/op/A)
	var/mob/user = A.actor
	removal_menu(user)
	return TRUE

/obj/machinery/appliance/proc/removal_menu(mob/user)
	if (can_remove_items(user))
		var/list/menuoptions = list()
		for(var/datum/cooking_item/CI as anything in cooking_objs)
			if (CI.container())
				menuoptions[CI.container().label(menuoptions.len)] = CI

		var/selection = rerun_ask(user, "k713", PROC_REF(removal_menu), args, /datum/prompt/choice, question = "Which item would you like to remove?", title = "Remove ingredients", choices = menuoptions)
		if(isnull(selection))
			return
		if (selection)
			var/datum/cooking_item/CI = menuoptions[selection]
			eject(CI, user)
			update_icon()
		return TRUE
	return FALSE

/obj/machinery/appliance/proc/can_remove_items(mob/user, show_warning = TRUE)
	if (!Adjacent(user))
		return FALSE

	if (isanimal(user))
		return FALSE

	return TRUE

/obj/machinery/appliance/proc/eject(datum/cooking_item/CI, mob/user = null)
	var/obj/item/thing
	var/delete = 1
	var/status = CI.container().check_contents()
	var/obj/item/reagent_containers/cooking_container/cook_container

	if (status == 1)//If theres only one object in a container then we extract that
		thing = locate_in_list(CI.container(), /obj/item)
		delete = 0
	else//If the container is empty OR contains more than one thing, then we must extract the container
		thing = CI.container()

	if (user)
		if(!user.put_in_hands(thing))
			thing.forceMove(get_turf(src))
	else if(istype(thing, /obj/item/reagent_containers/cooking_container))
		cook_container = thing
		cook_container.do_empty()
		delete = 0
	else
		thing.forceMove(get_turf(src))

	if (delete)
		own_take_member(src, nameof(cooking_objs), CI)
		spent(CI, user)
	else
		CI.reset()//reset instead of deleting if the container is left inside

	if(user)
		act_message(user, src, others = span_notice("%U% removes %I% from %T%."), item = thing)
		if(cook_container)
			cook_container.set_food_items(cook_container.food_items - 1)
			if(!LAZYLEN(cook_container.food_items)) //Empty.
				cook_container.set_food_items(0)
			changed(cook_container)
	else
		src.visible_message(span_infoplain(span_bold("\The [src]") + " pings as it automatically ejects its contents!"))
		if(cooked_sound)
			playsound(get_turf(src), cooked_sound, 50, 1)

/obj/machinery/appliance/proc/cook_mob(mob/living/victim, mob/user)
	return

/obj/machinery/appliance/proc/change_product_strings(obj/item/reagent_containers/food/snacks/product, datum/cooking_item/CI)
	product.name = "[cook_type] [product.name]"
	product.desc = "[product.desc]\nIt has been [cook_type]."

/obj/machinery/appliance/proc/change_product_appearance(obj/item/reagent_containers/food/snacks/product, datum/cooking_item/CI)
	if (!product.coating()) //Coatings change colour through a new sprite
		product.color = food_color
	product.filling_color = food_color

/mob/living/proc/calculate_composition() // moved from devour.dm on aurora's side
	if (!composition_reagent)//if no reagent has been set, then we'll set one
		if (HAS_SYNTHETIC_BIOLOGY(src))
			src.composition_reagent = REAGENT_ID_IRON
		else
			if(istype(src, /mob/living/carbon/human/diona) || istype(src, /mob/living/carbon/alien/diona))
				src.composition_reagent = REAGENT_ID_NUTRIMENT // diona are plants, not meat
			else
				src.composition_reagent = REAGENT_ID_PROTEIN
				if(ishuman(src))
					var/mob/living/carbon/human/H = src
					if(istype(H.species, /datum/species/diona))
						src.composition_reagent = REAGENT_ID_NUTRIMENT

	//if the mob is a simple animal - MOB NOT ANIMAL - with a defined meat quantity
	if (isanimal(src))
		var/mob/living/simple_mob/SA = src
		if(SA.meat_amount)
			src.composition_reagent_quantity = SA.meat_amount*2*9

		//The quantity of protein is based on the meat_amount, but multiplied by 2

	var/size_reagent = (src.mob_size * src.mob_size) * 3//The quantity of protein is set to 3x mob size squared
	if (size_reagent > src.composition_reagent_quantity)//We take the larger of the two
		src.composition_reagent_quantity = size_reagent

//This function creates a food item which represents a dead mob
/obj/machinery/appliance/proc/create_mob_food(obj/item/holder/H, datum/cooking_item/CI)
	if (!istype(H) || !H.held_mob)
		spent(H)
		return null
	var/mob/living/victim = H.held_mob
	if (victim.stat != DEAD)
		return null //Victim somehow survived the cooking, they do not become food

	victim.calculate_composition()

	var/obj/item/reagent_containers/food/snacks/variable/mob/result = new /obj/item/reagent_containers/food/snacks/variable/mob(CI.container())
	result.w_class = victim.mob_size
	result.reagents.add_reagent(victim.composition_reagent, victim.composition_reagent_quantity)

	if (victim.reagents)
		victim.reagents.trans_to_holder(result.reagents, victim.reagents.total_volume)

	if (isanimal(victim))
		var/mob/living/simple_mob/SA = victim
		result.kitchen_tag = SA.kitchen_tag

	result.appearance = victim

	var/matrix/M = matrix()
	M.Turn(45)
	M.Translate(1,-2)
	result.transform = M

	// all done, now delete the old objects
	rel_clear(H, nameof(H.held_mob))
	consumed(victim, src)
	victim = null
	spent(H)
	H = null

	return result

/datum/cooking_item
	var/max_cookwork
	var/cookwork
	var/overcook_mult = 6 // How long it takes to overcook. This is max_cookwork x overcook mult. If you're changing this, mind that at 3x, a max_cookwork of 30 becomes 90 ticks for the purpose of burning, and a max_cookwork of 4 only has 12 before burning! // doubled to 6
	var/result_type = 0
	var/tmp/obj/item/reagent_containers/cooking_container/container
	var/combine_target = null

	//Result type is one of the following:
		//0 unfinished, no result yet
		//1 Standard modification cooking. eg Fried Donk Pocket, Baked wheat, etc
		//2 Modification but with a new object that's an inert copy of the old. Generally used for deepfried mice
		//3 Combination cooking, EG Donut Bread, Donk pocket pizza, etc
		//4:Specific recipe cooking. EG: Turning raw potato sticks into fries

	var/burned = 0

	var/oil = 0
	var/max_oil = 0//Used for fryers.

/datum/cooking_item/New(obj/item/I)
	rel_set(src, nameof(container), I)

//This is called for containers whose contents are ejected without removing the container
/datum/cooking_item/proc/reset()
	max_cookwork = 0
	cookwork = 0
	result_type = 0
	burned = 0
	max_oil = 0
	oil = 0
	combine_target = null
	//Container is not reset

/obj/machinery/appliance/RefreshParts()
	..()
	// Default parts shouldn't mess with stats, so this reads the sum of (rating - 1).
	var/scan_rating = get_part_rating(/obj/item/stock_parts/scanning_module) - get_part_count(/obj/item/stock_parts/scanning_module)
	var/cap_rating = get_part_rating(/obj/item/stock_parts/capacitor) - get_part_count(/obj/item/stock_parts/capacitor)

	set_active_power_usage(initial(active_power_usage) - scan_rating * 25)
	heating_power = initial(heating_power) + cap_rating * 25
	cooking_power = cooking_coeff * (1 + (scan_rating + cap_rating) / 20) // 100% eff. becomes 120%, 140%, 160% w/ better parts, thus rewarding upgrading the appliances during your shift.
	// to_world("RefreshParts returned cooking power of [cooking_power] during this step.") // Debug lines, uncomment if you need to test.

/obj/machinery/appliance/proc/toggle_safety(mob/user)
	food_safety = !food_safety
	to_chat(user, span_notice("You flip \the [src]'s safe mode switch. Safe mode is now [food_safety ? "on" : "off"]."))

/// the container this refers to (a relation view: null once it is deleted).
/datum/cooking_item/proc/container() as /obj/item/reagent_containers/cooking_container
	return container
