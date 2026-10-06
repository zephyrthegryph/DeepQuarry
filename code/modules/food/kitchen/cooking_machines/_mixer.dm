/*
The mixer subtype is used for  the candymaker and cereal maker. They are similar to cookers but with a few
fundamental differences
1. They have a single container which cant be removed. it will eject multiple contents
2. Items can't be added or removed once the process starts
3. Items are all placed in the same container when added directly
4. They do combining mode only. And will always combine the entire contents of the container into an output
*/

/obj/machinery/appliance/mixer
	max_contents = 1
	stat = POWEROFF
	cooking_coeff = 0.75 // Original value 0.4
	active_power_usage = 3000
	idle_power_usage = 50
	var/datum/looping_sound/mixer/mixer_loop
	tgui_id = "KitchenMixer"

CAPABILITIES(/obj/machinery/appliance/mixer)
	owns_one(nameof(mixer_loop), /datum/looping_sound/mixer)

/obj/machinery/appliance/mixer/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += span_notice("It is currently set to make a [selected_option]")

/obj/machinery/appliance/mixer/Initialize(mapload)
	. = ..()
	rel_add(src, nameof(cooking_objs), new /datum/cooking_item(new /obj/item/reagent_containers/cooking_container(src)))
	set_cooking(FALSE)
	selected_option = DEFAULTPICK(output_options, null)
	var/datum/cooking_item/CI = LAZYACCESS(cooking_objs, 1)
	CI.combine_target = selected_option

	rel_set(src, nameof(mixer_loop), new /datum/looping_sound/mixer(list(src), FALSE))

//Mixers cannot-not do combining mode. So the default option is removed from this. A combine target must be chosen
/obj/machinery/appliance/mixer/choose_output(mob/user, new_output)
	if (!user.IsAdvancedToolUser())
		to_chat(user, span_notice("You can't operate [src]."))
		return

	if(!LAZYACCESS(output_options, new_output))
		return

	selected_option = new_output
	to_chat(user, span_notice("You prepare \the [src] to make \a [selected_option]."))
	var/datum/cooking_item/CI = LAZYACCESS(cooking_objs, 1)
	CI.combine_target = selected_option

/obj/machinery/appliance/mixer/has_space(obj/item/I)
	var/datum/cooking_item/CI = LAZYACCESS(cooking_objs, 1)
	if (!CI || !CI.container())
		return 0

	if (CI.container().can_fit(I))
		return CI

	return 0

/obj/machinery/appliance/mixer/can_remove_items(mob/user, show_warning = TRUE)
	if(has_stat(MACHINE_STAT_ANY))
		return 1
	else
		if(show_warning)
			to_chat(user, span_warning("You can't remove ingredients while it's turned on! Turn it off first or wait for it to finish."))
		return 0

//Container is not removable
/obj/machinery/appliance/mixer/removal_menu(mob/user)
	if (can_remove_items(user))
		var/list/menuoptions = list()
		for(var/datum/cooking_item/CI as anything in cooking_objs)
			if (CI.container())
				if (!CI.container().check_contents())
					to_chat(user, span_filter_notice("There's nothing in [src] you can remove!"))
					return

				for (var/obj/item/I in CI.container())
					menuoptions[I.name] = I

		var/selection = rerun_ask(user, "k86", PROC_REF(removal_menu), args, /datum/prompt/choice, question = "Which item would you like to remove? If you want to remove chemicals, use an empty beaker.", title = "Remove ingredients", choices = menuoptions)
		if(isnull(selection))
			return
		if (selection)
			var/obj/item/I = menuoptions[selection]
			if (!user || !user.put_in_hands(I))
				I.forceMove(get_turf(src))
			update_icon()
		return 1
	return 0

/obj/machinery/appliance/mixer/ui_data(datum/act/eval/A)
	var/list/data = ..()
	data["icon_used"] = off_icon
	return data

/// Requirement: something in the bowl to mix.
/obj/machinery/appliance/mixer/can_toggle_power_verb(mob/user, atom/target, obj/item/held)
	var/datum/cooking_item/CI = LAZYACCESS(cooking_objs, 1)
	if(!CI.container().check_contents())
		return "there's nothing in it, add ingredients before turning [src] on"
	return ..()

/obj/machinery/appliance/mixer/appliance_toggle_power_effect(datum/act/op/A)
	var/mob/user = A.actor

	var/datum/cooking_item/CI = LAZYACCESS(cooking_objs, 1)

	if(has_stat(POWEROFF))//Its turned off
		stat_remove(POWEROFF)
		if(user)
			act_message(user, src, MSG_SELF(span_filter_notice("You turn on %T%.")), MSG_OTHERS(span_filter_notice("%U% turns %T% on.")))
			get_cooking_work(CI)
			set_use_power(2)
	else //Its on, turn it off
		stat_add(POWEROFF)
		set_use_power(0)
		if(user)
			act_message(user, src, MSG_SELF(span_filter_notice("You turn off %T%.")), MSG_OTHERS(span_filter_notice("%U% turns %T% off.")))
	play_sfx(src, SFX_MACHINES_CLICK, 0.8)
	update_icon()

/obj/machinery/appliance/mixer/can_insert(obj/item/I, mob/user)
	if(!has_stat(MACHINE_STAT_ANY))
		to_chat(user, span_warning(",You can't add items while \the [src] is running. Wait for it to finish or turn the power off to abort."))
		return 0
	else
		return ..()

/obj/machinery/appliance/mixer/finish_cooking(datum/cooking_item/CI)
	..()
	stat_add(POWEROFF)
	play_sfx(src, SFX_MACHINES_CLICK, 0.8)
	set_use_power(0)
	CI.reset()
	update_icon()

APPEARANCE_NONE(/obj/machinery/appliance/mixer)
DECLARE_APPEARANCE_PROC(/obj/machinery/appliance/mixer, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/appliance/mixer/appearance_overlays()
	. = list()
	if (!has_stat(MACHINE_STAT_ANY))
		icon_state = on_icon
		if(mixer_loop)
			mixer_loop.start(src)
	else
		icon_state = off_icon
		if(mixer_loop)
			mixer_loop.stop(src)

/obj/machinery/appliance/mixer/work_step(datum/act/timer/A)
	if(has_stat(MACHINE_STAT_ANY) || !cooking || !length(cooking_objs))
		return PROCESS_KILL
	for(var/i in cooking_objs)
		do_cooking_tick(i)
