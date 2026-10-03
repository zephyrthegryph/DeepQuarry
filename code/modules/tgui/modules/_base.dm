/*
TGUI MODULES

This allows for datum-based TGUIs that can be hooked into objects.
This is useful for things such as the power monitor, which needs to exist on a physical console in the world, but also as a virtual device the AI can use

Code is pretty much ripped verbatim from nano modules, but with un-needed stuff removed
*/
/datum/tgui_module
	var/name
	var/tmp/datum/host
	var/list/using_access

	var/ntos = FALSE

/datum/tgui_module/New(host)
	rel_set(src, nameof(host), host)
	if(ntos)
		tgui_id = "Ntos" + tgui_id

/datum/tgui_module/tgui_host()
	return host() ? host().tgui_host() : src

/datum/tgui_module/ui_assets(mob/user)
	var/list/data = list()
	var/obj/item/modular_computer/host = tgui_host()
	if(istype(host))
		data += get_asset_datum(/datum/asset/simple/headers)
	return data

/datum/tgui_module/tgui_close(mob/user)
	if(host())
		host().tgui_close(user)

/datum/tgui_module/proc/can_still_topic(mob/user, datum/tgui_state/state)
	return (tgui_status(user, state) == STATUS_INTERACTIVE)

/datum/tgui_module/proc/check_access(mob/user, access)
	if(!access)
		return 1

	if(using_access)
		if(access in using_access)
			return 1
		else
			return 0

	if(!istype(user))
		return 0

	var/obj/item/card/id/I = user.GetIdCard()
	if(!I)
		return 0

	if(access in I.GetAccess())
		return 1

	return 0

/datum/tgui_module/tgui_static_data(mob/user)
	. = ..()

	var/obj/item/modular_computer/host = tgui_host()
	if(istype(host))
		. += host.get_header_data()

// The NTOS header buttons, when the module runs on a modular computer.
UI_ACT(/datum/tgui_module, "PC_exit", ui_act_pc_exit)
UI_ACT(/datum/tgui_module, "PC_shutdown", ui_act_pc_exit)
UI_ACT(/datum/tgui_module, "PC_minimize", ui_act_pc_exit)
UI_ACT_PROC(/datum/tgui_module, ui_act_pc_exit)
	var/obj/item/modular_computer/host = tgui_host()
	if(!istype(host))
		return FALSE
	switch(action)
		if("PC_exit")
			host.kill_program(FALSE, user)
		if("PC_shutdown")
			host.shutdown_computer()
		if("PC_minimize")
			host.minimize_program(user)
	return TRUE

// Each module subtype names its interface in tgui_id.
DECLARE_UI(/datum/tgui_module, UI_FROM_VAR("tgui_id"))

/datum/tgui_module/proc/relaymove(mob/user, direction)
	return FALSE

/datum/tgui_module/proc/close_ui()
	SStgui.close_uis(src)

/// The host this refers to (a relation view: null once that is deleted).
/datum/tgui_module/proc/host() as /datum
	return host
