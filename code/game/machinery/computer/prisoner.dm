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

CAPABILITIES(/obj/machinery/computer/prisoner)
	interface("PrisonerManagement")
	op("inject", ui_act("inject", arg("imp"), arg("val", num())), then(PROC_REF(ui_act_inject)))
	op("lock", ui_act("lock"), then(PROC_REF(ui_act_lock)))
	op("warn", ui_act("warn", arg("imp", schema_text(4096))), asks(/datum/prompt/text, fields = list("title" = "Enter your message here!", "question" = "Message:")), then(PROC_REF(ui_act_warn)))

/obj/machinery/computer/prisoner/ui_data(datum/act/eval/A)
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

/obj/machinery/computer/prisoner/proc/ui_act_inject(datum/act/op/A, imp, val)
	var/obj/item/implant/I = ui_ref(imp, null, /obj/item/implant)
	if(I)
		I.activate(clamp(val, 0, 10))
	. = TRUE
	add_fingerprint(A.actor)

/obj/machinery/computer/prisoner/proc/ui_act_lock(datum/act/op/A)
	if(allowed(A.actor))
		screen = !screen
	else
		to_chat(A.actor, "Unauthorized Access.")
	. = TRUE
	add_fingerprint(A.actor)

/obj/machinery/computer/prisoner/proc/ui_act_warn(datum/act/op/A, imp)
	add_fingerprint(A.actor)
	var/datum/prompt/R = A.answer
	var/message = R?.value
	if(!message)
		return OP_OK
	var/obj/item/implant/I = ui_ref(imp, null, /obj/item/implant)
	if(I && I.imp_in())
		to_chat(I.imp_in(), span_notice("You hear a voice in your head saying: '[message]'"))
	return OP_OK
