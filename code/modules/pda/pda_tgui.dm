// Self contained file for all things TGUI
/obj/item/pda/tgui_state(mob/user)
	return GLOB.tgui_inventory_state

DECLARE_UI(/obj/item/pda, "Pda", UI_TITLE("Personal Data Assistant"))

/obj/item/pda/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	data["owner"] = owner					// Who is your daddy...
	data["ownjob"] = ownjob					// ...and what does he do?

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

	data["useRetro"] = retro_mode
	data["touch_silent"] = touch_silent

	data["cartridge_name"] = cartridge ? cartridge.name : ""
	data["stationTime"] = stationtime2text() //worldtime2stationtime(world.time) // Aaa which fucking one is canonical there's SO MANY

	data["app"] = list(
		"name" = current_app().title,
		"icon" = current_app().icon,
		"template" = current_app().template,
		"has_back" = current_app().has_back)

	current_app().update_ui(user, data)

	return data

/// Actions the PDA itself has no row for are the running app's.
UI_ACT_FORWARD(/obj/item/pda, ui_forward_to_app)
/obj/item/pda/proc/ui_forward_to_app(mob/user, action)
	return current_app()

/obj/item/pda/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	add_fingerprint(ui.user)
	if(!touch_silent)
		play_sfx(src, SFX_MACHINES_PDA_CLICK)
	if((honkamt > 0) && (prob(60)))//For clown virus.
		honkamt--
		play_sfx(loc, SFX_ITEMS_BIKEHORN, 0.6)
	return TRUE

UI_ACT(/obj/item/pda, "Home", ui_act_home)
UI_ACT_PROC(/obj/item/pda, ui_act_home)
	. = TRUE
	var/datum/data/pda/app/main_menu/A = find_program(/datum/data/pda/app/main_menu)
	if(A)
		start_program(A)

UI_ACT(/obj/item/pda, "StartProgram", ui_act_startprogram, UI_ARG_REF("program", null, /datum/data/pda/app))
UI_ACT_PROC(/obj/item/pda, ui_act_startprogram)
	. = TRUE
	if(params["program"])
		var/datum/data/pda/app/A = params["program"]
		if(A)
			start_program(A)

UI_ACT(/obj/item/pda, "Eject", ui_act_eject)
UI_ACT_PROC(/obj/item/pda, ui_act_eject)
	. = TRUE
	if(!isnull(cartridge))
		var/turf/T = loc
		if(ismob(T))
			T = T.loc
		var/obj/item/cartridge/C = cartridge
		C.forceMove(T)
		if(scanmode() in C.programs)
			scanmode_handle = null
		if(current_app() in C.programs)
			start_program(find_program(/datum/data/pda/app/main_menu))
		if(C.radio)
			C.radio.hostpda_handle = null
		for(var/datum/data/pda/P in notifying_programs)
			if(P in C.programs)
				P.unnotify()
		cartridge = null
		update_shortcuts()

UI_ACT(/obj/item/pda, "Authenticate", ui_act_authenticate)
UI_ACT_PROC(/obj/item/pda, ui_act_authenticate)
	. = TRUE
	id_check(ui.user, 1)

UI_ACT(/obj/item/pda, "Retro", ui_act_retro)
UI_ACT_PROC(/obj/item/pda, ui_act_retro)
	. = TRUE
	retro_mode = !retro_mode

UI_ACT(/obj/item/pda, "TouchSounds", ui_act_touchsounds)
UI_ACT_PROC(/obj/item/pda, ui_act_touchsounds)
	. = TRUE
	touch_silent = !touch_silent

UI_ACT(/obj/item/pda, "Ringtone", ui_act_ringtone)
UI_ACT_PROC(/obj/item/pda, ui_act_ringtone)
	. = TRUE
	return set_ringtone(ui.user)
