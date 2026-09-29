//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

/obj/machinery/computer/prisoner
	name = "prisoner management console"
	desc = "Used to keep those sneaky prisoners in line, if they have an implant."
	icon_keyboard = "security_key"
	icon_screen = "explosive"
	light_color = "#a91515"
	req_access = list(ACCESS_ARMORY)
	circuit = /obj/item/circuitboard/prisoner
	var/id = 0.0
	var/temp = null
	var/status = 0
	var/timeleft = 60
	var/stop = 0.0
	var/screen = 0 // 0 - No Access Denied, 1 - Access allowed

/obj/machinery/computer/prisoner/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/open_ui,
	)
	..()

DECLARE_UI(/obj/machinery/computer/prisoner, "PrisonerManagement")

/obj/machinery/computer/prisoner/tgui_data(mob/user)
	var/list/chemImplants = list()
	var/list/trackImplants = list()
	if(screen)
		for(var/obj/item/implant/chem/C in REGISTRY_MEMBERS(REGISTRY_CHEM_IMPLANTS))
			var/turf/T = get_turf(C)
			if(!T)
				continue
			if(!C.implanted)
				continue
			chemImplants.Add(list(list(
				"host" = C.imp_in(),
				"units" = C.reagents.total_volume,
				"ref" = "\ref[C]"
			)))
		for(var/obj/item/implant/tracking/track in REGISTRY_MEMBERS(REGISTRY_TRACKING_IMPLANTS))
			var/turf/T = get_turf(track)
			if(!T)
				continue
			if(!track.implanted)
				continue
			var/loc_display = "Unknown"
			var/mob/living/L = track.imp_in()
			if((get_z(L) in using_map.station_levels) && !istype(L.loc, /turf/space))
				loc_display = T.loc
			if(track.malfunction)
				loc_display = pick(GLOB.teleportlocs)
			if(is_vore_jammed(track))
				loc_display = "E4R@4"
			trackImplants.Add(list(list(
				"host" = L,
				"ref" = "\ref[track]",
				"id" = "[track.id]",
				"loc" = "[loc_display]",
			)))

	return list("locked" = !screen, "chemImplants" = chemImplants, "trackImplants" = trackImplants)


UI_ACT(/obj/machinery/computer/prisoner, "inject", ui_act_inject, UI_ARG_REF("imp", null, /obj/item/implant), UI_ARG_NUM("val"))
UI_ACT_PROC(/obj/machinery/computer/prisoner, ui_act_inject)
	var/obj/item/implant/I = params["imp"]
	if(I)
		I.activate(clamp(params["val"], 0, 10))
	. = TRUE
	add_fingerprint(ui.user)

UI_ACT(/obj/machinery/computer/prisoner, "lock", ui_act_lock)
UI_ACT_PROC(/obj/machinery/computer/prisoner, ui_act_lock)
	if(allowed(ui.user))
		screen = !screen
	else
		to_chat(ui.user, "Unauthorized Access.")
	. = TRUE
	add_fingerprint(ui.user)

UI_ACT(/obj/machinery/computer/prisoner, "warn", ui_act_warn, UI_ARG_VALUE("imp"))
UI_ACT_PROC(/obj/machinery/computer/prisoner, ui_act_warn)
	om_ask(ui.user, /datum/om/prompt/text/implant_warning, PROC_REF(warning_entered), imp_ref = params["imp"], ui_refresh = src)
	. = TRUE
	add_fingerprint(ui.user)

/datum/om/prompt/text/implant_warning
	title = "Enter your message here!"
	message = "Message:"
	default = ""
	requires = PROMPT_USABLE
	/// The implant's ref from the UI.
	var/imp_ref

/obj/machinery/computer/prisoner/proc/warning_entered(datum/om/prompt/text/implant_warning/ask)
	var/obj/item/implant/I = locate(ask.imp_ref)
	if(I && I.imp_in())
		to_chat(I.imp_in(), span_notice("You hear a voice in your head saying: '[ask.text]'"))
