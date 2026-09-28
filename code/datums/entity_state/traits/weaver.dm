
/datum/trait_state/weaver
	life_stage = /datum/om/stage/life/trait/weaver
	var/silk_reserve = 100
	var/silk_max_reserve = 500
	var/silk_color = "#FFFFFF"
	var/silk_production = FALSE
	var/silk_generation_amount = 2
	var/nutrtion_per_silk = 0.2

/datum/trait_state/weaver/setup()
	if (!isliving(owner))
		return FALSE

	add_verb(owner, /mob/living/proc/weaver_control_panel)
	if(ishuman(owner))
		add_verb(owner, /mob/living/carbon/human/proc/enter_cocoon)
	return TRUE

	//Processing
/datum/trait_state/weaver/life_tick()
	if (QDELETED(owner))
		return
	process_weaver_silk()

/// The owner loses the weaver verbs.
/datum/trait_state/weaver/detach()
	remove_verb(owner, /mob/living/proc/weaver_control_panel)
	if(ishuman(owner))
		remove_verb(owner, /mob/living/carbon/human/proc/enter_cocoon)
	..()

/datum/trait_state/weaver/proc/process_weaver_silk()
	if(silk_reserve < silk_max_reserve && silk_production == TRUE && owner.nutrition > 100)
		silk_reserve = min(silk_reserve + silk_generation_amount, silk_max_reserve)
		owner.adjust_nutrition(-(nutrtion_per_silk*silk_generation_amount))

/// Pick a recipe, then confirm it; "No" goes back to the list.
/datum/trait_state/weaver/proc/weave_item()
	if(!owner?.client)
		return
	om_ask(owner, /datum/om/prompt/choice/weave, PROC_REF(weave_choice_made), choices = GLOB.all_weavable)

/// Picking a weaver recipe. Re-checked on the answer: conscious, and a real recipe.
/datum/om/prompt/choice/weave
	title = "Weave Choice"
	message = "What would you like to weave?"
	ask_flags = ASK_CONSCIOUS

/datum/om/prompt/choice/weave/valid()
	return istype(GLOB.all_weavable[choice], /datum/weaver_recipe/item) ? null : "not a recipe"

/// "Weave this?"; a no goes back to the recipe list.
/datum/om/prompt/confirm/weave
	title = "Confirmation"
	ask_flags = ASK_CONSCIOUS
	answer_on_no = TRUE
	var/datum/weaver_recipe/item/recipe

/datum/om/prompt/confirm/weave/prepare()
	message = "Are you sure you want to weave [recipe.title]? It will cost you [recipe.cost] silk."
	return TRUE

/datum/trait_state/weaver/proc/weave_choice_made(datum/om/prompt/choice/weave/ask)
	om_ask(owner, /datum/om/prompt/confirm/weave, PROC_REF(weave_confirmed), recipe = GLOB.all_weavable[ask.choice])

/datum/trait_state/weaver/proc/weave_confirmed(datum/om/prompt/confirm/weave/ask)
	if(!ask.yes)
		weave_item()
		return
	weave_check(ask.recipe.cost, ask.recipe.result_type)

/datum/trait_state/weaver/proc/silk_color_picked(datum/om/prompt/color/ask)
	if(!ask.picked_color)
		return
	silk_color = ask.picked_color

//TGUI Weaver Panel
/datum/trait_state/weaver/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "WeaverConfig", "Weaver Config")
		ui.open()

/mob/living/proc/weaver_control_panel()
	set name = "Weaver Control Panel"
	set desc = "Allows you to adjust the settings of various weaver settings!"
	set category = "Abilities.Weaver"

	var/datum/trait_state/weaver/weave = get_weaver_state()
	if(!weave)
		to_chat(src, span_warning("Only a weaver can use that!"))
		return FALSE

	weave.tgui_interact(src)

/mob/living/proc/get_weaver_state()
	RETURN_TYPE(/datum/trait_state/weaver)
	return get_trait_state(/datum/trait_state/weaver)

/datum/trait_state/weaver/tgui_data(mob/user)
	var/data = list(
		"silk_reserve" = silk_reserve,
		"silk_max_reserve" = silk_max_reserve,
		"silk_color" = silk_color,
		"silk_production" = silk_production,
		"savefile_selected" = correct_savefile_selected()
	)

	return data

/datum/trait_state/weaver/tgui_close(mob/user)
	GLOB.character_setup_service.queue_preferences_save(user?.client?.prefs)
	. = ..()

/datum/trait_state/weaver/proc/correct_savefile_selected()
	if(owner.client.prefs.default_slot == owner.mind.loaded_from_slot)
		return TRUE
	return FALSE

/datum/trait_state/weaver/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	switch(action)
		if("new_silk_color")
			om_ask(ui.user, /datum/om/prompt/color, PROC_REF(silk_color_picked), message = "Select a color you wish your silk to be!", default = silk_color, ui_refresh = src, title = "Color Selector")
			return FALSE
		if("toggle_silk_production")
			silk_production = !(silk_production)
			to_chat(owner, span_info("You are [silk_production ? "now" : "no longer"] producing silk."))
			return FALSE
		if("check_silk_amount")
			to_chat(owner, span_info("Your silk reserves are at [silk_reserve]/[silk_max_reserve]."))
			return FALSE
		if("weave_binding")
			weave_check(50, /obj/item/clothing/suit/weaversilk_bindings)
			return TRUE
		if("weave_floor")
			weave_check(25, /obj/effect/weaversilk/floor)
			return TRUE
		if("weave_wall")
			weave_check(100, /obj/effect/weaversilk/wall)
			return TRUE
		if("weave_nest")
			weave_check(100, /obj/structure/bed/double/weaversilk_nest)
			return TRUE
		if("weave_trap")
			weave_check(250, /obj/effect/weaversilk/trap)
			return TRUE
/*
 * Checks to see if we can create the object
*/
/datum/trait_state/weaver/proc/weave_check(cost, weaved_object)
	if(cost > silk_reserve)
		to_chat(owner, span_warning("You don't have enough silk to weave that!"))
		return

	if(owner.stat)
		to_chat(owner, span_warning("You can't do that in your current state!"))
		return

	if(!isturf(owner.loc))
		to_chat(owner, span_warning("You can't weave here!"))
		return

	if(locate_within(owner.loc, weaved_object))
		to_chat(owner, span_warning("You can't create another one in the same tile here!"))
		return

	om_do_after(owner, ((cost/25) SECONDS), owner, src, PROC_REF(weave_done), list(cost, weaved_object))

/datum/trait_state/weaver/proc/weave_done(cost, weaved_object)
	if(cost > silk_reserve)
		to_chat(owner, span_warning("You don't have enough silk to weave that!"))
		return

	if(!isturf(owner.loc))
		to_chat(owner, span_warning("You can't weave here!"))
		return

	if(locate_within(owner.loc, weaved_object))
		to_chat(owner, span_warning("You can't create another one in the same tile!"))
		return

	silk_reserve = max(silk_reserve - cost, 0)
	var/atom/object = new weaved_object(owner.loc)
	object.color = silk_color
	return

/// Trait system: silk production. Was a COMSIG_LIVING_LIFE listener.
/datum/om/stage/life/trait/weaver
	name = "weaver"
	state_type = /datum/trait_state/weaver
