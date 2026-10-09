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

/// A module's window is its type's interface(); on a modular computer the window is the NTOS skin of it.
/datum/tgui_module/ui_interface(mob/user)
	. = ..()
	if(ntos && istext(.))
		return "Ntos[.]"

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

CAPABILITIES(/datum/tgui_module)
	// The NTOS header buttons, when the module runs on a modular computer.
	op("pc_exit", ui_act("PC_exit"), then(PROC_REF(ui_act_pc_exit)))
	op("pc_shutdown", ui_act("PC_shutdown"), then(PROC_REF(ui_act_pc_shutdown)))
	op("pc_minimize", ui_act("PC_minimize"), then(PROC_REF(ui_act_pc_minimize)))
	// A button works while its window does: checked when it is pressed and again when the answer to its question arrives.
	extend(TAG_UI, needs(req_bool(PROC_REF(ui_usable), silent = TRUE)))

/// The window the viewer works this module through is still interactive. A button press arrives from that window; the answer to a question it
/// asked needs the window to be still open (a question is dropped once the window is gone, as the re-run of the old handler was).
/datum/tgui_module/proc/ui_usable(datum/act/op/A)
	var/mob/user = A.actor
	if(QDELETED(src) || !istype(user))
		return FALSE
	var/datum/tgui/ui = SStgui.get_open_ui(user, src)
	if(!ui)
		return !A.answer
	return ui.status == STATUS_INTERACTIVE

/// The answer to a question a button asked still counts: its window is still open and interactive for the one who answers.
/datum/tgui_module/proc/request_usable(datum/request/R)
	return window_request_usable(src, R)

/datum/tgui_module/proc/ui_act_pc_exit(datum/act/op/A)
	var/obj/item/modular_computer/host = tgui_host()
	if(!istype(host))
		return FALSE
	host.kill_program(FALSE, A.actor)
	return TRUE

/datum/tgui_module/proc/ui_act_pc_shutdown(datum/act/op/A)
	var/obj/item/modular_computer/host = tgui_host()
	if(!istype(host))
		return FALSE
	host.shutdown_computer()
	return TRUE

/datum/tgui_module/proc/ui_act_pc_minimize(datum/act/op/A)
	var/obj/item/modular_computer/host = tgui_host()
	if(!istype(host))
		return FALSE
	host.minimize_program(A.actor)
	return TRUE

/datum/tgui_module/proc/relaymove(mob/user, direction)
	return FALSE

/datum/tgui_module/proc/close_ui()
	SStgui.close_uis(src)

/// The host this refers to (a relation view: null once that is deleted).
/datum/tgui_module/proc/host() as /datum
	return host
