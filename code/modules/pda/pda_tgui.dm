// Self contained file for all things TGUI

/obj/item/pda/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["owner"] = owner
	data["ownjob"] = ownjob
	data["useRetro"] = retro_mode
	data["touch_silent"] = touch_silent
	var/list/merged_1 = ui_data_obj_item_pda(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/pda's window data.
/obj/item/pda/proc/ui_data_obj_item_pda(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()


	// update list of shortcuts, only if they changed
	if(!length(shortcut_cache))
		shortcut_cache = list()
		shortcut_cat_order = list()
		var/prog_list = programs.Copy()
		if(cartridge)
			if(length(cartridge.programs)) prog_list |= cartridge.programs

		for(var/datum/data/pda/P as anything in prog_list)

			if(P.hidden)
				continue
			var/list/cat
			if(P.category in shortcut_cache)
				cat = LAZYACCESS(shortcut_cache, P.category)
			else
				cat = list()
				LAZYSET(shortcut_cache, P.category, cat)
				LAZYADD(shortcut_cat_order, P.category)
			cat |= list(list(name = P.name, icon = P.icon, notify_icon = P.notify_icon, ref = "\ref[P]"))

		// force the order of a few core categories
		shortcut_cat_order = list("General") \
			+ sortList((shortcut_cat_order || list()) - list("General", "Scanners", "Utilities")) \
			+ list("Scanners", "Utilities")

	data["idInserted"] = (id ? 1 : 0)
	data["idLink"] = (id ? text("[id.registered_name], [id.assignment]") : "--------")


	data["cartridge_name"] = cartridge ? cartridge.name : ""
	data["stationTime"] = stationtime2text() //worldtime2stationtime(world.time) // Aaa which fucking one is canonical there's SO MANY

	data["app"] = list(
		"name" = current_app().title,
		"icon" = current_app().icon,
		"template" = current_app().template,
		"has_back" = current_app().has_back)

	current_app().update_ui(user, data)

	return data

/// Every button pressed in the PDA's window, its own and its apps': the touch leaves a print and clicks (interface(pressed =)).
/obj/item/pda/proc/pda_pressed(mob/actor, action)
	add_fingerprint(actor)
	if(!touch_silent)
		play_sfx(src, SFX_MACHINES_PDA_CLICK)
	if((honkamt > 0) && (prob(60)))//For clown virus.
		honkamt--
		play_sfx(loc, SFX_ITEMS_BIKEHORN, 0.6)

/obj/item/pda/proc/ui_act_home(datum/act/op/A)
	. = TRUE
	var/datum/data/pda/app/main_menu/A2 = find_program(/datum/data/pda/app/main_menu)
	if(A2)
		start_program(A2)

/obj/item/pda/proc/ui_act_startprogram(datum/act/op/A, program)
	. = TRUE
	if(program)
		var/datum/data/pda/app/A2 = program
		if(A2)
			start_program(A2)

/obj/item/pda/proc/ui_act_eject(datum/act/op/A)
	. = TRUE
	if(!isnull(cartridge))
		var/turf/T = loc
		if(ismob(T))
			T = T.loc
		var/obj/item/cartridge/C = cartridge
		C.forceMove(T)
		if(scanmode() in C.programs)
			rel_clear(src, nameof(/obj/item/pda::scanmode))
		if(current_app() in C.programs)
			start_program(find_program(/datum/data/pda/app/main_menu))
		if(C.radio)
			rel_clear(C.radio, nameof(/obj/item/radio/integrated::hostpda))
		for(var/datum/data/pda/P in notifying_programs)
			if(P in C.programs)
				P.unnotify()
		own_take(src, nameof(/obj/item/pda::cartridge))
		update_shortcuts()

/obj/item/pda/proc/ui_act_authenticate(datum/act/op/A)
	var/mob/user = A.actor
	. = TRUE
	id_check(user, 1)

/obj/item/pda/proc/ui_act_retro(datum/act/op/A)
	. = TRUE
	retro_mode = !retro_mode

/obj/item/pda/proc/ui_act_touchsounds(datum/act/op/A)
	. = TRUE
	touch_silent = !touch_silent

/obj/item/pda/proc/ui_act_ringtone(datum/act/op/A)
	var/mob/user = A.actor
	. = TRUE
	return set_ringtone(user)
