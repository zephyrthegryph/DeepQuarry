/// Strategic generated-station objectives bind to real department controls and
/// read authoritative simulation state. They never place arbitrary target props.
/datum/expedition_objective/generated_department
	var/list/department_ids
	var/action = "disable"

/datum/expedition_objective/generated_department/New(_required = TRUE)
	..()
	department_ids = list()

/datum/expedition_objective/generated_department/Destroy()
	department_ids = null
	return ..()

/datum/expedition_objective/generated_department/populate(datum/expedition_site/S)
	..()
	for(var/obj/machinery/generated_station_department_control/control in S.station_controls)
		if(control.department_id in department_ids)
			tracked += control
	target = length(department_ids)

/datum/expedition_objective/generated_department/proc/required_siblings_complete()
	for(var/datum/expedition_objective/objective in site?.mission?.objectives)
		if(objective != src && objective.required && objective.state != EXP_OBJ_COMPLETE)
			return FALSE
	return TRUE

/datum/expedition_objective/generated_department/check()
	if(!site?.station_simulation)
		return state
	var/satisfied = 0
	for(var/department_id in department_ids)
		var/department_state = site.station_simulation.department_state(department_id)
		switch(action)
			if("disable")
				if(department_state == GENERATED_DEPARTMENT_OFFLINE)
					satisfied++
			if("capture")
				for(var/obj/machinery/generated_station_department_control/control in tracked)
					if(control.department_id == department_id && control.captured && department_state != GENERATED_DEPARTMENT_OFFLINE)
						satisfied++
						break
			if("preserve")
				if(department_state == GENERATED_DEPARTMENT_OFFLINE)
					state = EXP_OBJ_FAILED
					return state
				if(required_siblings_complete())
					satisfied++
	progress = satisfied
	if(satisfied >= target)
		state = EXP_OBJ_COMPLETE
	return state

/datum/expedition_objective/generated_department/progress_text()
	return "[clamp(progress, 0, target)] / [target] departments [action == "preserve" ? "preserved" : "secured"]"

/datum/expedition_objective/proc/generated_department_turf(department_id)
	if(!site?.station_spec || !site.station_materialization)
		return null
	for(var/datum/generated_station_department_instance/department in site.station_spec.departments)
		if(department.id != department_id)
			continue
		var/area/generated_station/A = site.station_materialization.department_areas[department.layout_node_id]
		for(var/turf/T in A)
			if(!T.density && !locate(/obj/machinery/door) in T)
				return T
	return null

/obj/machinery/generated_station_upload_terminal
	name = "station director uplink"
	desc = "A hardened uplink into the installation's command network."
	icon = 'icons/obj/machines/research.dmi'
	icon_state = "server"
	density = TRUE
	anchored = TRUE
	var/station_id
	var/uploaded = FALSE

/obj/machinery/generated_station_upload_terminal/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/generated_station_upload,
	)
	..()

/// The old attack_hand: never called ..(), uploaded the control payload.
/datum/interaction/machine_hand/ungated/generated_station_upload
	id = "generated_station_upload"
	name = "Upload payload"
	effect = /obj/machinery/generated_station_upload_terminal/proc/interaction_upload

/obj/machinery/generated_station_upload_terminal/proc/interaction_upload(mob/user, obj/item/held, datum/interaction/interaction)
	if(uploaded)
		to_chat(user, span_notice("The payload is already resident."))
		return TRUE
	user.visible_message(span_notice("[user] begins uploading a control payload."), span_notice("You begin uploading the malware payload."))
	if(!do_after(user, 5 SECONDS, target = src) || QDELETED(src))
		return TRUE
	uploaded = TRUE
	var/datum/generated_station_simulation/simulation = generated_station_runtime(station_id)
	for(var/key in SSexpedition?.sites)
		var/datum/expedition_site/candidate = SSexpedition.sites[key]
		if(candidate.station_simulation == simulation)
			candidate.station_director?.set_department_connected("ai-1", FALSE)
			break
	visible_message(span_warning("[src] reports: DIRECTOR NETWORK OVERRIDE ACCEPTED."))
	return TRUE

/obj/item/generated_station_command_asset
	name = "station command cryptographic core"
	desc = "A portable authority and telemetry core worth recovering intact."
	icon = 'icons/obj/module.dmi'
	icon_state = "id_mod"
	w_class = ITEMSIZE_NORMAL

/mob/living/carbon/human/generated_station_command_officer
	real_name = "Station Command Officer"

/datum/expedition_objective/generated_asset
	name = "Recover the command core"

/datum/expedition_objective/generated_asset/populate(datum/expedition_site/S)
	..()
	var/turf/T = generated_department_turf("command-1")
	if(T)
		tracked += new /obj/item/generated_station_command_asset(T)

/datum/expedition_objective/generated_asset/check()
	progress = count_returned(/obj/item/generated_station_command_asset)
	if(progress)
		state = EXP_OBJ_COMPLETE
	return state

/datum/expedition_objective/generated_malware
	name = "Upload director malware"

/datum/expedition_objective/generated_malware/populate(datum/expedition_site/S)
	..()
	var/turf/T = generated_department_turf("ai-1")
	if(T)
		var/obj/machinery/generated_station_upload_terminal/terminal = new(T)
		terminal.station_id = S.station_spec.id
		tracked += terminal

/datum/expedition_objective/generated_malware/check()
	for(var/obj/machinery/generated_station_upload_terminal/terminal in tracked)
		if(!QDELETED(terminal) && terminal.uploaded)
			progress = 1
			state = EXP_OBJ_COMPLETE
	return state

/datum/expedition_objective/generated_rescue_prisoner
	name = "Rescue the brig prisoner"

/datum/expedition_objective/generated_rescue_prisoner/populate(datum/expedition_site/S)
	..()
	var/turf/T = generated_department_turf("security-1")
	if(T)
		tracked += new /obj/structure/expedition_survivor_pod(T)

/datum/expedition_objective/generated_rescue_prisoner/check()
	progress = count_returned(/obj/structure/expedition_survivor_pod)
	if(progress)
		state = EXP_OBJ_COMPLETE
	return state

/datum/expedition_objective/generated_capture_officer
	name = "Capture command personnel"

/datum/expedition_objective/generated_capture_officer/populate(datum/expedition_site/S)
	..()
	var/turf/T = generated_department_turf("command-1")
	if(T)
		tracked += new /mob/living/carbon/human/generated_station_command_officer(T)

/datum/expedition_objective/generated_capture_officer/check()
	var/datum/shuttle/autodock/overmap/shuttle = site?.assigned_shuttle
	if(!shuttle)
		return state
	for(var/area/A in shuttle.shuttle_area)
		for(var/mob/living/carbon/human/generated_station_command_officer/officer in A)
			if(officer.stat != DEAD)
				progress = 1
				state = EXP_OBJ_COMPLETE
				return state
	return state

/datum/expedition_objective/generated_department/disable_command
	name = "Disable Command"

/datum/expedition_objective/generated_department/disable_command/New(_required = TRUE)
	..()
	department_ids = list("command-1")

/datum/expedition_objective/generated_department/disable_security
	name = "Neutralize Security"

/datum/expedition_objective/generated_department/disable_security/New(_required = TRUE)
	..()
	department_ids = list("security-1")

/datum/expedition_objective/generated_department/disable_ai
	name = "Disable the AI core"

/datum/expedition_objective/generated_department/disable_ai/New(_required = TRUE)
	..()
	department_ids = list("ai-1")

/datum/expedition_objective/generated_department/capture_ai
	name = "Capture the AI core"
	action = "capture"

/datum/expedition_objective/generated_department/capture_ai/New(_required = TRUE)
	..()
	department_ids = list("ai-1")

/datum/expedition_objective/generated_department/preserve_engineering
	name = "Preserve Engineering"
	action = "preserve"

/datum/expedition_objective/generated_department/preserve_engineering/New(_required = TRUE)
	..()
	department_ids = list("engineering-1")

/datum/expedition_mission/station_assault
	name = "Station Assault"
	desc = "Breach the generated station, neutralize its command and security control nodes, and preserve useful infrastructure where possible."
	difficulty = EXP_DIFF_MED
	reward_points = 260
	reward_cash = 400

/datum/expedition_mission/station_assault/build_objectives()
	return list(
		required_obj(/datum/expedition_objective/generated_department/disable_command),
		required_obj(/datum/expedition_objective/generated_department/disable_security),
		bonus_obj(/datum/expedition_objective/generated_asset, 120, 150),
		bonus_obj(/datum/expedition_objective/generated_malware, 80, 100),
		bonus_obj(/datum/expedition_objective/generated_rescue_prisoner, 100, 100),
		bonus_obj(/datum/expedition_objective/generated_capture_officer, 120, 150),
		bonus_obj(/datum/expedition_objective/generated_department/capture_ai, 100, 100),
		bonus_obj(/datum/expedition_objective/generated_department/preserve_engineering, 75, 100),
	)
