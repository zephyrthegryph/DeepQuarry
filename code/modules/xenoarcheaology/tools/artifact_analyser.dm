/obj/machinery/artifact_analyser
	name = "Anomaly Analyser"
	desc = "Studies the emissions of anomalous materials to discover their uses."
	icon = 'icons/obj/virology.dmi'
	icon_state = "isolator"
	anchored = TRUE
	density = TRUE
	bubble_icon = "science"
	var/scan_in_progress = 0
	var/tmp/obj/machinery/artifact_scanpad/owned_scanner
	EXPIRY_DECLARE(scan_completion_time)
	var/scan_duration = 50
	var/tmp/obj/scanned_object
	var/report_num = 0
	var/static/list/priority_objects = list(/obj/machinery/artifact,
										/obj/machinery/auto_cloner,
										/obj/machinery/power/supermatter,
										/obj/structure/constructshell,
										/obj/machinery/giga_drill,
										/obj/structure/cult/pylon,
										/obj/machinery/replicator,
										/obj/structure/crystal
									)

CAPABILITIES(/obj/machinery/artifact_analyser)
	started_work(step = PROC_REF(work_step))
	ref_one(nameof(owned_scanner), /obj/machinery/artifact_scanpad)
	ref_one(nameof(scanned_object), /obj)
	interface("XenoarchArtifactAnalyzer")
	without("ui_open")
	op("scan", ui_act("scan"), then(PROC_REF(ui_act_scan)))
	op("artifact_analyser_use", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_artifact_analyser_use)))

/obj/machinery/artifact_analyser/Initialize(mapload)
	. = ..()
	reconnect_scanner()

/obj/machinery/artifact_analyser/proc/reconnect_scanner()
	//connect to a nearby scanner pad
	rel_set(src, nameof(owned_scanner), locate_within(get_step(src, dir), /obj/machinery/artifact_scanpad))
	if(!owned_scanner())
		rel_set(src, nameof(owned_scanner), locate_in_list(orange(1, src), /obj/machinery/artifact_scanpad))

/obj/machinery/artifact_analyser/proc/interaction_artifact_analyser_use(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(!operable() || get_dist(src, user) > 1)
		return OP_OK
	tgui_interact(user)
	return OP_OK

/obj/machinery/artifact_analyser/ui_prepare(mob/user, datum/tgui/ui)
	if(!owned_scanner())
		reconnect_scanner()
	return TRUE

/obj/machinery/artifact_analyser/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["scan_in_progress"] = scan_in_progress
	var/list/merged_1 = ui_data_obj_machinery_artifact_analyser(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/artifact_analyser's window data.
/obj/machinery/artifact_analyser/proc/ui_data_obj_machinery_artifact_analyser(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["owned_scanner"] = owned_scanner()

	return data

/obj/machinery/artifact_analyser/proc/ui_act_scan(datum/act/op/A)
	add_fingerprint(A.actor)
	if(scan_in_progress)
		scan_in_progress = FALSE
		atom_say("Scanning halted.")
		return TRUE
	if(!owned_scanner())
		reconnect_scanner()
	if(owned_scanner())
		var/artifact_in_use = 0
		var/obj/secondary_priority
		for(var/obj/O in owned_scanner().loc)
			if(O == owned_scanner())
				continue
			if(O.invisibility)
				continue
			if(istype(O, /obj/machinery/artifact))
				var/obj/machinery/artifact/A2 = O
				if(A2.in_use)
					artifact_in_use = 1
				else
					A2.set_anchored(TRUE)
					A2.in_use = 1

			if(artifact_in_use)
				atom_say("Cannot scan. Too much interference.")
			else
				for(var/otype in priority_objects)
					if(istype(O, otype))
						rel_set(src, nameof(/obj/machinery/artifact_analyser::scanned_object), O)
						break
				if(scanned_object())
					break
				else
					secondary_priority = O
		if(secondary_priority && !scanned_object())
			rel_set(src, nameof(/obj/machinery/artifact_analyser::scanned_object), secondary_priority)
		if(!scanned_object())
			atom_say("Unable to isolate scan target.")
		else
			scan_in_progress = 1
			EXPIRY_SET(src, scan_completion_time, scan_duration, CLOCK_WORLD)
			after(src, scan_duration + 0.1 SECONDS, PROC_REF(scan_timer_fired))
			atom_say("Scanning begun.")
	return TRUE

/// A scan finishes on its timer (after() at the completion time), not by polling.
/obj/machinery/artifact_analyser/proc/scan_timer_fired()
	if(scan_in_progress)
		finish_scan()

/obj/machinery/artifact_analyser/proc/work_step(datum/act/timer/A)
	return PROCESS_KILL

/obj/machinery/artifact_analyser/proc/finish_scan()
	scan_in_progress = 0
	var/results = ""
	if(!owned_scanner())
		reconnect_scanner()
	if(!owned_scanner())
		results = "Error communicating with scanner."
	else if(!scanned_object() || scanned_object().loc != owned_scanner().loc)
		results = "Unable to locate scanned object. Ensure it was not moved in the process."
	else
		results = get_scan_info(scanned_object())

	atom_say("Scanning complete.")
	var/obj/item/paper/P = new(src.loc)
	P.name = "[src] report #[++report_num]"
	P.info = span_bold("[src] analysis report #[report_num]") + "<br>"
	P.info += "<br>"
	P.info += "[bicon(scanned_object())] [results]"
	P.stamped = list(/obj/item/stamp)
	P.add_overlay("paper_stamped")

	if(scanned_object() && istype(scanned_object(), /obj/machinery/artifact))
		var/obj/machinery/artifact/A = scanned_object()
		A.set_anchored(FALSE)
		A.in_use = 0
	rel_clear(src, nameof(scanned_object))

//hardcoded responses, oh well
/obj/machinery/artifact_analyser/proc/get_scan_info(obj/scanned_obj)
	switch(scanned_obj.type)
		if(/obj/machinery/auto_cloner)
			return "Automated cloning pod - appears to rely on an artificial ecosystem formed by semi-organic nanomachines and the contained liquid.<br>The liquid resembles protoplasmic residue supportive of unicellular organism developmental conditions.<br>The structure is composed of a titanium alloy."
		if(/obj/machinery/power/supermatter)
			return "Superdense phoron clump - appears to have been shaped or hewn, structure is composed of matter aproximately 20 times denser than ordinary refined phoron."
		if(/obj/structure/constructshell)
			return "Tribal idol - subject resembles statues/emblems built by superstitious pre-warp civilisations to honour their gods. Material appears to be a rock/plastcrete composite."
		if(/obj/machinery/giga_drill)
			return "Automated mining drill - structure composed of titanium-carbide alloy, with tip and drill lines edged in an alloy of diamond and phoron."
		if(/obj/structure/cult/pylon)
			return "Tribal pylon - subject resembles statues/emblems built by cargo cult civilisations to honour energy systems from post-warp civilisations."
		if(/obj/machinery/replicator)
			return "Automated construction unit - subject appears to be able to synthesize various objects given a material, some with simple internal circuitry. Method unknown."
		if(/obj/structure/crystal)
			return "Crystal formation - pseudo-organic crystalline matrix, unlikely to have formed naturally. No known technology exists to synthesize this exact composition."
		if(/obj/machinery/artifact)
			var/obj/machinery/artifact/A = scanned_obj
			var/out = "Anomalous alien device - composed of an unknown alloy.<br><br>"

			var/datum/artifact_master/AMast = A.artifact_master
			var/datum/artifact_effect/AEff = AMast?.get_primary()

			if(istype(AEff))
				out += AEff.getDescription()

			if(AMast && AMast.my_effects.len > 1)
				out += "<br><br>Internal scans indicate ongoing secondary activity operating independently from primary systems.<br><br>"
				for(var/datum/artifact_effect/my_effect in A.artifact_master.my_effects - AEff)

					if(my_effect)
						out += my_effect.getDescription()

			return out
		else

			var/datum/artifact_master/ScannedMaster = scanned_obj.artifact_master

			if(istype(ScannedMaster))
				var/out = "Anomalous reality warp - Object has been altered to disobey known laws of physics.<br><br>"

				var/datum/artifact_effect/AEff = ScannedMaster.get_primary()

				if(istype(AEff))
					out += AEff.getDescription()

				if(ScannedMaster.my_effects.len > 1)
					out += "<br><br>Resonant scans indicate asynchronous reality modulation:<br><br>"
					for(var/datum/artifact_effect/my_effect in ScannedMaster.my_effects - AEff)

						if(my_effect)
							out += my_effect.getDescription()

				return out

			return "[scanned_obj.name] - mundane application."

/// Accessor for the owned_scanner var.
/obj/machinery/artifact_analyser/proc/owned_scanner() as /obj/machinery/artifact_scanpad
	return owned_scanner

/// Accessor for the scanned_object var.
/obj/machinery/artifact_analyser/proc/scanned_object() as /obj
	return scanned_object
