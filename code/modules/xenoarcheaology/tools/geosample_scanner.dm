#define RPM_FRICTION 15
#define IDEAL_RPM 600
#define RPM_OKAY_RANGE 200
#define RPM_MAX_DELTA RPM_FRICTION * 4
#define RPM_MIN 0
#define RPM_MAX 1200
#define COMPLETION_DELTA_MODIFIER 4 // Make it go faster, 25 ticks at peak efficiency
#define RADIATION_INJECTION_AMT 5
#define RADIATION_MAX 50
#define TARGET_RADIATION 20
#define RADIATION_OK_RANGE 7.5
#define RADIATION_LOSS 1
#define HEAT_GAIN 0.5
#define HEAT_FAILURE_THRESHOLD 10
#define HEAT_MAX 12
#define COOLANT_USAGE 2
#define COOLANT_MAX 100

/obj/machinery/radiocarbon_spectrometer
	name = "radiocarbon spectrometer"
	desc = "A specialised, complex scanner for gleaning information on all manner of small things."
	anchored = TRUE
	density = TRUE
	icon = 'icons/obj/virology.dmi'
	icon_state = "analyser"

	use_power = USE_POWER_IDLE
	idle_power_usage = 20
	active_power_usage = 300

	flags = OPENCONTAINER

	var/report_num = 0
	var/tmp/obj/item/scanned_item
	var/last_scan_data = "No scans on record."
	var/scan_progress = 0

	// Mechanics:tm:
	var/scanner_rpm = 0
	var/scanner_rpm_delta = 0

	var/radiation = 0

	var/heat = 0


/obj/machinery/radiocarbon_spectrometer/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/radiocarbon_spectrometer_use_item,
		/datum/interaction/machine_hand/ungated/radiocarbon_spectrometer_use,
	)
	..()

/// The old attackby: never called ..(), handled reagent containers or loaded a scan sample.
/datum/interaction/machine_item/radiocarbon_spectrometer_use_item
	id = "radiocarbon_spectrometer_use_item"
	name = "Use"
	held_type = /obj/item
	effect = /obj/machinery/radiocarbon_spectrometer/proc/interaction_use_item
	also_requires = list(REQ_FIELD_NOT("scanning", "you can't do that while it's scanning"))

/obj/machinery/radiocarbon_spectrometer/proc/interaction_use_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I, /obj/item/reagent_containers/glass))
		var/obj/item/reagent_containers/glass/G = I
		if(!G.is_open_container())
			return TRUE
		var/choice = rerun_ask(user, "k74", PROC_REF(interaction_use_item), args, /datum/om/prompt/choice/alert, message = "What do you want to do with the container?", title = "Radiometric Scanner", choices = list("Add water","Empty water","Scan container"))
		if(isnull(choice))
			return
		if(!choice)
			return TRUE
		if(choice == "Add water")
			if(!G.reagents.has_reagent(REAGENT_ID_WATER))
				to_chat(user, span_danger("No water found in beaker."))
				return TRUE
			var/trans = G.reagents.trans_id_to(src, REAGENT_ID_WATER, reagent_transfer_amount(G))
			to_chat(user, span_info("You transfer [trans ? trans : 0]u of water into [src]."))
			return TRUE
		else if(choice == "Empty water")
			var/amount_transferred = min(G.reagents.maximum_volume - G.reagents.total_volume, reagents.total_volume)
			var/trans = reagents.trans_to(G, amount_transferred)
			to_chat(user, span_info("You remove [trans ? trans : 0]u of water from [src]."))
			return TRUE
		// fall through

	if(scanned_item())
		to_chat(user, span_warning("[src] already has \a [scanned_item()] inside!"))
		return TRUE

	if(!user.unEquip(I, target = src))
		return TRUE

	rel_set(src, nameof(scanned_item), I)
	to_chat(user, span_notice("You put [I] into [src]."))
	return TRUE

/// The old attack_hand: never called ..(), just opened the UI.
/datum/interaction/machine_hand/ungated/radiocarbon_spectrometer_use
	id = "radiocarbon_spectrometer_use"
	name = "Use"
	effect = /obj/machinery/radiocarbon_spectrometer/proc/interaction_use

/obj/machinery/radiocarbon_spectrometer/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	tgui_interact(user)
	return TRUE

CAPABILITIES(/obj/machinery/radiocarbon_spectrometer)
	reagents(100) // COOLANT_MAX (a file-local define the generated table cannot see)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(scanning), wakes_on = list(nameof(scanning)))
	interface("XenoarchSpectrometer")
	op("scanItem", ui_act("scanItem"), then(PROC_REF(ui_act_scanitem)))
	op("ejectItem", ui_act("ejectItem"), then(PROC_REF(ui_act_ejectitem)))
	op("set_scanner_rpm_delta", ui_act("set_scanner_rpm_delta", arg("delta", num())), then(PROC_REF(ui_act_set_scanner_rpm_delta)))
	op("inject_radiation", ui_act("inject_radiation"), then(PROC_REF(ui_act_inject_radiation)))

/obj/machinery/radiocarbon_spectrometer/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["last_scan_data"] = last_scan_data
	data["scanning"] = scanning
	data["scan_progress"] = scan_progress
	data["scanner_rpm"] = scanner_rpm
	data["scanner_rpm_delta"] = scanner_rpm_delta
	data["radiation"] = radiation
	data["heat"] = heat
	var/list/merged_1 = ui_data_obj_machinery_radiocarbon_spectrometer(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/radiocarbon_spectrometer's window data.
/obj/machinery/radiocarbon_spectrometer/proc/ui_data_obj_machinery_radiocarbon_spectrometer(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	// this is the data which will be sent to the ui
	data["scanned_item"] = (scanned_item() ? scanned_item().name : "")
	data["scanned_item_desc"] = (scanned_item() ? (scanned_item().desc ? scanned_item().desc : "No information on record.") : "")

	// Mechanics
	data["coolant"] = reagents.total_volume

	return data

/obj/machinery/radiocarbon_spectrometer/tgui_static_data(mob/user)
	var/list/data = ..()

	data["IDEAL_RPM"] = IDEAL_RPM
	data["RPM_MAX_DELTA"] = RPM_MAX_DELTA
	data["RPM_MAX"] = RPM_MAX

	data["TARGET_RADIATION"] = TARGET_RADIATION
	data["RADIATION_MAX"] = RADIATION_MAX

	data["HEAT_FAILURE_THRESHOLD"] = HEAT_FAILURE_THRESHOLD
	data["HEAT_MAX"] = HEAT_MAX
	data["COOLANT_MAX"] = COOLANT_MAX

	return data

/obj/machinery/radiocarbon_spectrometer/proc/ui_act_scanitem(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(A.actor)
	if(scanning)
		stop_scanning()
		return
	if(!scanned_item())
		to_chat(user, span_warning("Insert an item to scan."))
		return
	start_scanning()
	to_chat(user, span_notice("Scan initiated."))
	return TRUE

/obj/machinery/radiocarbon_spectrometer/proc/ui_act_ejectitem(datum/act/op/A)
	add_fingerprint(A.actor)
	if(scanned_item())
		scanned_item().forceMove(loc)
		rel_clear(src, nameof(/obj/machinery/radiocarbon_spectrometer::scanned_item))
	return TRUE

/obj/machinery/radiocarbon_spectrometer/proc/ui_act_set_scanner_rpm_delta(datum/act/op/A, delta)
	add_fingerprint(A.actor)
	scanner_rpm_delta = CLAMP(delta, -RPM_MAX_DELTA, RPM_MAX_DELTA)
	return TRUE

/obj/machinery/radiocarbon_spectrometer/proc/ui_act_inject_radiation(datum/act/op/A)
	add_fingerprint(A.actor)
	if(!scanning)
		radiation = 0
		return
	radiation = CLAMP(radiation + RADIATION_INJECTION_AMT, 0, RADIATION_MAX)
	return TRUE

OM_FIELD(/obj/machinery/radiocarbon_spectrometer, scanning, FALSE, CHANGE_MACHINE_SETTINGS)
/// Runs the scan while scanning (start_scanning() .. stop_scanning()).
/obj/machinery/radiocarbon_spectrometer/proc/work_step(datum/act/timer/A)
	if(!scanned_item() || scanned_item().loc != src)
		rel_clear(src, nameof(scanned_item))
		stop_scanning()
		return

	if(scan_progress >= 100)
		complete_scan()
		return

	// Mechanics time
	/************** HEAT *************/
	if(heat > HEAT_FAILURE_THRESHOLD)
		visible_message(span_danger("[icon2html(src, viewers(src))] buzzes unhappily. It has failed mid-scan!"), range = 2)
		stop_scanning()
		return
	var/heat_gain = reagents.remove_reagent(REAGENT_ID_WATER, COOLANT_USAGE) ? -1 : HEAT_GAIN
	heat += heat_gain
	heat = CLAMP(heat, 0, HEAT_MAX)

	/************** RPM **************/
	// Scanner slows down over time
	scanner_rpm -= RPM_FRICTION + rand(0, RPM_FRICTION) // randomly add more friction
	// Motor speeds it up
	scanner_rpm += scanner_rpm_delta
	// Cap
	scanner_rpm = CLAMP(scanner_rpm, RPM_MIN, RPM_MAX)

	// Factor RPM into completion
	var/diff_from_ideal_rpm = abs(scanner_rpm - IDEAL_RPM)
	var/rpm_factor = CLAMP01(1 - (diff_from_ideal_rpm / RPM_OKAY_RANGE))

	/************** RADIATION *************/
	radiation -= RADIATION_LOSS
	radiation = CLAMP(radiation, 0, RADIATION_MAX)
	var/diff_from_ideal_radiation = abs(radiation - TARGET_RADIATION)
	var/radiation_factor = CLAMP01(1 - (diff_from_ideal_radiation / RADIATION_OK_RANGE))

	/************** COMPLETION *************/
	var/completion_delta = rpm_factor + radiation_factor
	scan_progress = CLAMP(scan_progress + (completion_delta * COMPLETION_DELTA_MODIFIER), 0, 100)

/obj/machinery/radiocarbon_spectrometer/proc/start_scanning()
	icon_state = "analyser_processing"
	set_scanning(TRUE)
	scan_progress = 0
	scanner_rpm_delta = 0
	scanner_rpm = 0
	radiation = 0
	heat = 0

/obj/machinery/radiocarbon_spectrometer/proc/stop_scanning()
	icon_state = "analyser"
	set_scanning(FALSE)
	scan_progress = 0
	scanner_rpm_delta = 0
	scanner_rpm = 0
	radiation = 0
	heat = 0

/obj/machinery/radiocarbon_spectrometer/proc/complete_scan()
	stop_scanning()
	visible_message(span_notice("[icon2html(src, viewers(src))] makes an insistent chime."), range = 2)

	if(!scanned_item())
		return

		//create report
	var/obj/item/paper/P = new(src)
	P.name = "[src] report #[++report_num]: [scanned_item().name]"
	P.stamped = list(/obj/item/stamp)
	P.add_overlay("paper_stamped")

	//work out data
	var/data = " - Mundane object: [scanned_item().desc ? scanned_item().desc : "No information on record."]<br>"
	var/datum/geosample/G
	switch(scanned_item().type)
		if(/obj/item/ore/archeology_debris)
			var/obj/item/ore/archeology_debris/O = scanned_item()
			if(O.geologic_data)
				G = O.geologic_data

		if(/obj/item/rocksliver)
			var/obj/item/rocksliver/O = scanned_item()
			if(O.geological_data())
				G = O.geological_data()

		if(/obj/item/archaeological_find)
			data = " - Mundane object (archaic xenos origins)<br>"

			var/obj/item/archaeological_find/A = scanned_item()
			if(A.talking_atom)
				data = " - Exhibits properties consistent with sonic reproduction and audio capture technologies.<br>"

	var/anom_found = 0
	if(G)
		data = " - Spectometric analysis on mineral sample has determined type [GLOB.finds_as_strings[GLOB.responsive_carriers.Find(G.source_mineral)]]<br>"
		if(G.age_billion > 0)
			data += " - Radiometric dating shows age of [G.age_billion].[G.age_million] billion years<br>"
		else if(G.age_million > 0)
			data += " - Radiometric dating shows age of [G.age_million].[G.age_thousand] million years<br>"
		else
			data += " - Radiometric dating shows age of [G.age_thousand * 1000 + G.age] years<br>"
		data += " - Chromatographic analysis shows the following materials present:<br>"
		for(var/carrier in G.find_presence)
			if(LAZYACCESS(G.find_presence, carrier))
				var/index = GLOB.responsive_carriers.Find(carrier)
				if(index > 0 && index <= LAZYLEN(GLOB.finds_as_strings))
					data += "	> [100 * LAZYACCESS(G.find_presence, carrier)]% [GLOB.finds_as_strings[index]]<br>"

		if(G.artifact_id && G.artifact_distance >= 0)
			anom_found = 1
			data += " - Hyperspectral imaging reveals exotic energy wavelength detected with ID: [G.artifact_id]<br>"
			data += " - Fourier transform analysis on anomalous energy absorption indicates energy source located inside emission radius of [G.artifact_distance]m<br>"

	if(!anom_found)
		data += " - No anomalous data<br>"

	P.info = span_bold("[src] analysis report #[report_num]") + "<br>"
	P.info += span_bold("Scanned item:") + " [scanned_item().name]<br><br>" + data
	last_scan_data = P.info

	P.forceMove(loc)
	scanned_item().forceMove(loc)
	rel_clear(src, nameof(scanned_item))

#undef RPM_FRICTION
#undef IDEAL_RPM
#undef RPM_OKAY_RANGE
#undef RPM_MAX_DELTA
#undef RPM_MIN
#undef RPM_MAX
#undef COMPLETION_DELTA_MODIFIER
#undef RADIATION_INJECTION_AMT
#undef RADIATION_MAX
#undef TARGET_RADIATION
#undef RADIATION_OK_RANGE
#undef RADIATION_LOSS
#undef HEAT_GAIN
#undef HEAT_FAILURE_THRESHOLD
#undef HEAT_MAX
#undef COOLANT_USAGE
#undef COOLANT_MAX

/// Accessor for the scanned_item var.
/obj/machinery/radiocarbon_spectrometer/proc/scanned_item() as /obj/item
	return scanned_item
