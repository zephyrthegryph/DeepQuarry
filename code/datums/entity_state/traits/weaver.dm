
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

	grant(owner, granted_verb(/mob/living/proc/weaver_control_panel), src)
	if(ishuman(owner))
		grant(owner, granted_verb(/mob/living/carbon/human/proc/enter_cocoon), src)
	return TRUE

	//Processing
/datum/trait_state/weaver/life_tick()
	if (QDELETED(owner))
		return
	process_weaver_silk()

/// The owner loses the weaver verbs.
/datum/trait_state/weaver/detach()
	revoke(owner, granted_verb(/mob/living/proc/weaver_control_panel), src)
	if(ishuman(owner))
		revoke(owner, granted_verb(/mob/living/carbon/human/proc/enter_cocoon), src)
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
CAPABILITIES(/datum/trait_state/weaver)
	interface("WeaverConfig", title = "Weaver Config")
	op("new_silk_color", ui_act("new_silk_color"), then(PROC_REF(ui_act_new_silk_color)))
	op("toggle_silk_production", ui_act("toggle_silk_production"), then(PROC_REF(ui_act_toggle_silk_production)))
	op("check_silk_amount", ui_act("check_silk_amount"), then(PROC_REF(ui_act_check_silk_amount)))
	op("weave_binding", ui_act("weave_binding"), then(PROC_REF(ui_act_weave_binding)))
	op("weave_floor", ui_act("weave_floor"), then(PROC_REF(ui_act_weave_floor)))
	op("weave_wall", ui_act("weave_wall"), then(PROC_REF(ui_act_weave_wall)))
	op("weave_nest", ui_act("weave_nest"), then(PROC_REF(ui_act_weave_nest)))
	op("weave_trap", ui_act("weave_trap"), then(PROC_REF(ui_act_weave_trap)))

/mob/living/proc/weaver_control_panel()
	set name = "Weaver Control Panel"
	set desc = "Allows you to adjust the settings of various weaver settings!"
	set category = VERB_CAT_ABILITIES_WEAVER

	var/datum/trait_state/weaver/weave = get_weaver_state()
	if(!weave)
		to_chat(src, span_warning("Only a weaver can use that!"))
		return FALSE

	weave.tgui_interact(src)

/mob/living/proc/get_weaver_state()
	RETURN_TYPE(/datum/trait_state/weaver)
	return get_trait_state(/datum/trait_state/weaver)

/// The computed part of /datum/trait_state/weaver's window data (declared on its UI_DATA row).
/datum/trait_state/weaver/ui_data(datum/act/eval/A)
	var/data = list(
		"silk_reserve" = silk_reserve,
		"silk_max_reserve" = silk_max_reserve,
		"silk_color" = silk_color,
		"silk_production" = silk_production,
		"savefile_selected" = correct_savefile_selected()
	)

	return data

/datum/trait_state/weaver/tgui_close(mob/user)
	SScharacter_setup.queue_preferences_save(user?.client?.prefs)
	. = ..()

/datum/trait_state/weaver/proc/correct_savefile_selected()
	if(owner.client.prefs.default_slot == owner.mind.loaded_from_slot)
		return TRUE
	return FALSE

/datum/trait_state/weaver/proc/ui_act_new_silk_color(datum/act/op/A)
	var/mob/user = A.actor
	om_ask(user, /datum/om/prompt/color, PROC_REF(silk_color_picked), message = "Select a color you wish your silk to be!", default = silk_color, ui_refresh = src, title = "Color Selector")
	return FALSE

/datum/trait_state/weaver/proc/ui_act_toggle_silk_production(datum/act/op/A)
	silk_production = !(silk_production)
	to_chat(owner, span_info("You are [silk_production ? "now" : "no longer"] producing silk."))
	return FALSE

/datum/trait_state/weaver/proc/ui_act_check_silk_amount(datum/act/op/A)
	to_chat(owner, span_info("Your silk reserves are at [silk_reserve]/[silk_max_reserve]."))
	return FALSE

/datum/trait_state/weaver/proc/ui_act_weave_binding(datum/act/op/A)
	weave_check(50, /obj/item/clothing/suit/weaversilk_bindings)
	return TRUE

/datum/trait_state/weaver/proc/ui_act_weave_floor(datum/act/op/A)
	weave_check(25, /obj/effect/weaversilk/floor)
	return TRUE

/datum/trait_state/weaver/proc/ui_act_weave_wall(datum/act/op/A)
	weave_check(100, /obj/effect/weaversilk/wall)
	return TRUE

/datum/trait_state/weaver/proc/ui_act_weave_nest(datum/act/op/A)
	weave_check(100, /obj/structure/bed/double/weaversilk_nest)
	return TRUE

/datum/trait_state/weaver/proc/ui_act_weave_trap(datum/act/op/A)
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

	om_task_timed(owner, ((cost/25) SECONDS), owner, src, PROC_REF(weave_done), list(cost, weaved_object))

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

/// Trait system: silk production.
/datum/om/stage/life/trait/weaver
	name = "weaver"
	state_type = /datum/trait_state/weaver
