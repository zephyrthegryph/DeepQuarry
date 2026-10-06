// liquid belly procs
/datum/vore_look/proc/liq_b_show_liq(mob/user, list/params, extra)
	if(!host().vore_selected.show_liquids)
		host().vore_selected.show_liquids = 1
		to_chat(user,span_warning("Your [lowertext(host().vore_selected.name)] now has liquid options."))
	else
		host().vore_selected.show_liquids = 0
		to_chat(user,span_warning("Your [lowertext(host().vore_selected.name)] no longer has liquid options."))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_liq_reagent_gen_cost_limit(mob/user, list/params, extra)
	var/new_limit = params["val"]
	if(!isnum(new_limit))
		return FALSE
	host().vore_selected.reagent_gen_cost_limit = CLAMP(new_limit, 0, 100)
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_liq_reagent_gen(mob/user, list/params, extra)
	if(!host().vore_selected.reagentbellymode) //liquid container adjustments and interactions.
		host().vore_selected.reagentbellymode = 1
		to_chat(user,span_warning("Your [lowertext(host().vore_selected.name)] now has interactions which can produce liquids."))
	else //Doesnt produce liquids
		host().vore_selected.reagentbellymode = 0
		to_chat(user,span_warning("Your [lowertext(host().vore_selected.name)] wont produce liquids, liquids already in your [lowertext(host().vore_selected.name)] must be emptied out or removed with purge."))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_liq_reagent_type(mob/user, list/params, extra)
	var/new_reagent = params["val"]
	if(!(new_reagent in host().vore_selected.reagent_choices))
		return FALSE

	host().vore_selected.reagent_chosen = new_reagent
	host().vore_selected.ReagentSwitch() // For changing variables when a new reagent is chosen
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_liq_reagent_name(mob/user, list/params, extra)
	var/new_name = params["val"]

	if(length(new_name) > BELLIES_NAME_MAX || length(new_name) < BELLIES_NAME_MIN)
		tgui_alert_async(user, "Entered name length invalid (must be longer than [BELLIES_NAME_MIN], no longer than [BELLIES_NAME_MAX]).","Error")
		return FALSE

	host().vore_selected.reagent_name = new_name
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_liq_reagent_transfer_verb(mob/user, list/params, extra)
	var/new_verb = params["val"]

	if(length(new_verb) > BELLIES_NAME_MAX || length(new_verb) < BELLIES_NAME_MIN)
		tgui_alert_async(user, "Entered verb length invalid (must be longer than [BELLIES_NAME_MIN], no longer than [BELLIES_NAME_MAX]).","Error")
		return FALSE

	host().vore_selected.reagent_transfer_verb = new_verb
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_liq_reagent_nutri_rate(mob/user, list/params, extra)
	host().vore_selected.gen_time_display = params["val"]
	switch(host().vore_selected.gen_time_display)
		if("10 minutes")
			host().vore_selected.gen_time = 0
		if("30 minutes")
			host().vore_selected.gen_time = 2
		if("1 hour")
			host().vore_selected.gen_time = 5
		if("3 hours")
			host().vore_selected.gen_time = 17
		if("6 hours")
			host().vore_selected.gen_time = 35
		if("12 hours")
			host().vore_selected.gen_time = 71
		if("24 hours")
			host().vore_selected.gen_time = 143
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_liq_reagent_capacity(mob/user, list/params, extra)
	var/new_custom_vol = params["val"]
	if(!isnum(new_custom_vol))
		return FALSE
	host().vore_selected.custom_max_volume = CLAMP(new_custom_vol, 10, 300)
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_liq_sloshing(mob/user, list/params, extra)
	if(!host().vore_selected.vorefootsteps_sounds)
		host().vore_selected.vorefootsteps_sounds = 1
		to_chat(user,span_warning("Your [lowertext(host().vore_selected.name)] can now make sounds when you walk around depending on how full you are."))
	else
		host().vore_selected.vorefootsteps_sounds = 0
		to_chat(user,span_warning("Your [lowertext(host().vore_selected.name)] wont make any liquid sounds no matter how full it is."))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_liq_reagent_addons(mob/user, list/params, extra)
	var/reagent_toggle_addon = params["val"]
	if(!reagent_toggle_addon)
		return FALSE
	host().vore_selected.reagent_mode_flags ^= host().vore_selected.reagent_mode_flag_list[reagent_toggle_addon]
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_liquid_overlay(mob/user, list/params, extra)
	if(!host().vore_selected.liquid_overlay)
		host().vore_selected.liquid_overlay = 1
		to_chat(user,span_warning("Your [lowertext(host().vore_selected.name)] now has liquid overlay enabled."))
	else
		host().vore_selected.liquid_overlay = 0
		to_chat(user,span_warning("Your [lowertext(host().vore_selected.name)] no longer has liquid overlay enabled."))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_max_liquid_level(mob/user, list/params, extra)
	var/new_max_liquid_level = params["val"]
	if(!isnum(new_max_liquid_level))
		return FALSE
	host().vore_selected.max_liquid_level = CLAMP(new_max_liquid_level, 0, 100)
	host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_custom_reagentcolor(mob/user, list/params, extra)
	var/newcolor = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor)
		host().vore_selected.custom_reagentcolor = newcolor
	else
		host().vore_selected.custom_reagentcolor = null
	host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_custom_reagentalpha(mob/user, list/params, extra)
	var/newalpha = params["val"]
	if(!isnum(newalpha))
		return FALSE
	if(newalpha)
		host().vore_selected.custom_reagentalpha = CLAMP(newalpha, 0, 255)
	else
		host().vore_selected.custom_reagentalpha = null
	host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_reagent_touches(mob/user, list/params, extra)
	if(!host().vore_selected.reagent_touches)
		host().vore_selected.reagent_touches = 1
		to_chat(user,span_warning("Your [lowertext(host().vore_selected.name)] will now apply reagents to creatures when digesting."))
	else
		host().vore_selected.reagent_touches = 0
		to_chat(user,span_warning("Your [lowertext(host().vore_selected.name)] will no longer apply reagents to creatures when digesting."))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_mush_overlay(mob/user, list/params, extra)
	if(!host().vore_selected.mush_overlay)
		host().vore_selected.mush_overlay = 1
		to_chat(user,span_warning("Your [lowertext(host().vore_selected.name)] now has fullness overlay enabled."))
	else
		host().vore_selected.mush_overlay = 0
		to_chat(user,span_warning("Your [lowertext(host().vore_selected.name)] no longer has fullness overlay enabled."))
	host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_mush_color(mob/user, list/params, extra)
	var/newcolor = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor)
		host().vore_selected.mush_color = newcolor
		host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_mush_alpha(mob/user, list/params, extra)
	var/newalpha = params["val"]
	if(!isnum(newalpha))
		return FALSE
	host().vore_selected.mush_alpha = CLAMP(newalpha, 0, 255)
	host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_max_mush(mob/user, list/params, extra)
	var/new_max_mush = params["val"]
	if(!isnum(new_max_mush))
		return FALSE
	host().vore_selected.max_mush = CLAMP(new_max_mush, 0, 6000)
	host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_min_mush(mob/user, list/params, extra)
	var/new_min_mush = params["val"]
	if(!isnum(new_min_mush))
		return FALSE
	host().vore_selected.min_mush = CLAMP(new_min_mush, 0, 100)
	host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_item_mush_val(mob/user, list/params, extra)
	var/new_item_mush_val = params["val"]
	if(!isnum(new_item_mush_val))
		return FALSE
	host().vore_selected.item_mush_val = CLAMP(new_item_mush_val, 0, 1000)
	host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_metabolism_overlay(mob/user, list/params, extra)
	if(!host().vore_selected.metabolism_overlay)
		host().vore_selected.metabolism_overlay = 1
		to_chat(user,span_warning("Your [lowertext(host().vore_selected.name)] now has ingested metabolism overlay enabled."))
	else
		host().vore_selected.metabolism_overlay = 0
		to_chat(user,span_warning("Your [lowertext(host().vore_selected.name)] no longer has ingested metabolism overlay enabled."))
	host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_metabolism_mush_ratio(mob/user, list/params, extra)
	var/new_metabolism_mush_ratio = params["val"]
	if(!isnum(new_metabolism_mush_ratio))
		return FALSE
	host().vore_selected.metabolism_mush_ratio = CLAMP(new_metabolism_mush_ratio, 0, 500)
	host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_max_ingested(mob/user, list/params, extra)
	var/new_max_ingested = params["val"]
	if(!isnum(new_max_ingested))
		return FALSE
	host().vore_selected.max_ingested = CLAMP(new_max_ingested, 0, 6000)
	host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_custom_ingested_color(mob/user, list/params, extra)
	var/newcolor = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor)
		host().vore_selected.custom_ingested_color = newcolor
	else
		host().vore_selected.custom_ingested_color = null
	host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_custom_ingested_alpha(mob/user, list/params, extra)
	var/newalpha = params["val"]
	if(!isnum(newalpha))
		return FALSE
	host().vore_selected.custom_ingested_alpha = newalpha
	host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/liq_b_liq_purge(mob/user, list/params, extra)
	host().vore_selected.reagents.clear_reagents()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/// /datum/vore_look's "liq" sub-actions (a nested message its window op routes): each one's arguments go through their schemas first.
/datum/vore_look/proc/liq_subaction(action, list/data, mob/user, extra)
	switch(action)
		if("b_show_liq")
			return liq_b_show_liq(user, list(), extra)
		if("b_liq_reagent_gen_cost_limit")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? liq_b_liq_reagent_gen_cost_limit(user, typed, extra) : FALSE
		if("b_liq_reagent_gen")
			return liq_b_liq_reagent_gen(user, list(), extra)
		if("b_liq_reagent_type")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? liq_b_liq_reagent_type(user, typed, extra) : FALSE
		if("b_liq_reagent_name")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? liq_b_liq_reagent_name(user, typed, extra) : FALSE
		if("b_liq_reagent_transfer_verb")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? liq_b_liq_reagent_transfer_verb(user, typed, extra) : FALSE
		if("b_liq_reagent_nutri_rate")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? liq_b_liq_reagent_nutri_rate(user, typed, extra) : FALSE
		if("b_liq_reagent_capacity")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? liq_b_liq_reagent_capacity(user, typed, extra) : FALSE
		if("b_liq_sloshing")
			return liq_b_liq_sloshing(user, list(), extra)
		if("b_liq_reagent_addons")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? liq_b_liq_reagent_addons(user, typed, extra) : FALSE
		if("b_liquid_overlay")
			return liq_b_liquid_overlay(user, list(), extra)
		if("b_max_liquid_level")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? liq_b_max_liquid_level(user, typed, extra) : FALSE
		if("b_custom_reagentcolor")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? liq_b_custom_reagentcolor(user, typed, extra) : FALSE
		if("b_custom_reagentalpha")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? liq_b_custom_reagentalpha(user, typed, extra) : FALSE
		if("b_reagent_touches")
			return liq_b_reagent_touches(user, list(), extra)
		if("b_mush_overlay")
			return liq_b_mush_overlay(user, list(), extra)
		if("b_mush_color")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? liq_b_mush_color(user, typed, extra) : FALSE
		if("b_mush_alpha")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? liq_b_mush_alpha(user, typed, extra) : FALSE
		if("b_max_mush")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? liq_b_max_mush(user, typed, extra) : FALSE
		if("b_min_mush")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? liq_b_min_mush(user, typed, extra) : FALSE
		if("b_item_mush_val")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? liq_b_item_mush_val(user, typed, extra) : FALSE
		if("b_metabolism_overlay")
			return liq_b_metabolism_overlay(user, list(), extra)
		if("b_metabolism_mush_ratio")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? liq_b_metabolism_mush_ratio(user, typed, extra) : FALSE
		if("b_max_ingested")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? liq_b_max_ingested(user, typed, extra) : FALSE
		if("b_custom_ingested_color")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? liq_b_custom_ingested_color(user, typed, extra) : FALSE
		if("b_custom_ingested_alpha")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? liq_b_custom_ingested_alpha(user, typed, extra) : FALSE
		if("b_liq_purge")
			return liq_b_liq_purge(user, list(), extra)
	return null
