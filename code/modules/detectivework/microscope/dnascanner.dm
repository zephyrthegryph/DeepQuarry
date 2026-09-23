//DNA machine
/obj/machinery/dnaforensics
	name = "DNA analyzer"
	desc = "A high tech machine that is designed to read DNA samples properly."
	icon = 'icons/obj/forensics.dmi'
	icon_state = "dnaopen"
	anchored = TRUE
	maintenance_flags = MACHINE_MAINT_STANDARD
	density = TRUE
	circuit = /obj/item/circuitboard/dna_analyzer

	var/obj/item/forensics/swab/bloodsamp = null
	var/scanning = 0
	var/scanner_progress = 0
	var/scanner_rate = 5
	var/last_process_worldtime = 0
	var/report_num = 0

/obj/machinery/dnaforensics/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/dnaforensics/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/dnaforensics_insert_swab,
		/datum/interaction/machine_hand/ungated/dnaforensics_open_ui,
	)
	..()

/// Old attackby: insert a used blood swab for analysis.
/datum/interaction/machine_item/dnaforensics_insert_swab
	id = "dnaforensics_insert_swab"
	name = "Insert swab"
	requires = list(REQ_INTERACTION_REACH,
		REQ_ON(PRED_TARGET, /obj/machinery/dnaforensics/proc/no_sample_loaded, "there is a sample in the machine"),
		REQ_ON(PRED_TARGET, /obj/machinery/dnaforensics/proc/not_currently_scanning, "it is busy scanning right now"))
	effect = /obj/machinery/dnaforensics/proc/interaction_insert_swab

/obj/machinery/dnaforensics/proc/no_sample_loaded(mob/actor, atom/target, obj/item/held)
	return !bloodsamp

/obj/machinery/dnaforensics/proc/not_currently_scanning(mob/actor, atom/target, obj/item/held)
	return !scanning

/obj/machinery/dnaforensics/proc/interaction_insert_swab(mob/user, obj/item/W, datum/interaction/interaction)
	var/obj/item/forensics/swab/swab = W
	if(istype(swab) && swab.is_used())
		user.unEquip(W)
		bloodsamp = swab
		swab.forceMove(src)
		to_chat(user, span_notice("You insert [W] into [src]."))
		update_icon()
	else
		to_chat(user, span_warning("\The [src] only accepts used swabs."))
	return TRUE

/// Old attack_hand: `tgui_interact(user)`, no gate (never called ..()).
/datum/interaction/machine_hand/ungated/dnaforensics_open_ui
	id = "dnaforensics_open_ui"
	name = "Use"
	effect = /obj/machinery/proc/interaction_open_ui

/obj/machinery/dnaforensics/tgui_interact(mob/user, datum/tgui/ui)
	if(stat & (NOPOWER))
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "DNAForensics", "QuikScan DNA Analyzer") // 540, 326
		ui.open()

/obj/machinery/dnaforensics/tgui_data(mob/user)
	var/list/data = ..()
	data["scan_progress"] = round(scanner_progress)
	data["scanning"] = scanning
	data["bloodsamp"] = (bloodsamp ? bloodsamp.name : "")
	data["bloodsamp_desc"] = (bloodsamp ? (bloodsamp.desc ? bloodsamp.desc : "No information on record.") : "")
	return data

/obj/machinery/dnaforensics/tgui_act(action, list/params, datum/tgui/ui)
	if(..())
		return TRUE

	if(stat & (NOPOWER))
		return FALSE // don't update UIs attached to this object

	. = TRUE
	switch(action)
		if("scanItem")
			if(scanning)
				scanning = FALSE
				update_icon()
			else
				if(bloodsamp)
					scanner_progress = 0
					scanning = TRUE
					to_chat(ui.user, span_notice("Scan initiated."))
					update_icon()
				else
					to_chat(ui.user, span_warning("Insert an item to scan."))
			. = TRUE

		if("ejectItem")
			if(bloodsamp)
				bloodsamp.forceMove(loc)
				bloodsamp = null
				scanning = FALSE
				update_icon()

/obj/machinery/dnaforensics/process()
	if(scanning)
		if(!bloodsamp || bloodsamp.loc != src)
			bloodsamp = null
			scanning = 0
		else if(scanner_progress >= 100)
			complete_scan()
			return
		else
			//calculate time difference
			var/deltaT = (world.time - last_process_worldtime) * 0.1
			scanner_progress = min(100, scanner_progress + scanner_rate * deltaT)
	last_process_worldtime = world.time

/obj/machinery/dnaforensics/proc/complete_scan()
	visible_message(span_notice("[icon2html(src,viewers(src))] makes an insistent chime."), 2)
	update_icon()
	if(bloodsamp)
		var/obj/item/paper/P = new(src)
		P.name = "[src] report #[++report_num]: [bloodsamp.name]"
		P.stamped = list(/obj/item/stamp)
		P.cut_overlays()
		P.add_overlay("paper_stamped")
		//dna data itself
		var/data = "No scan information available."
		if(bloodsamp.dna != null)
			data = "Spectometric analysis on provided sample has determined the presence of [bloodsamp.dna.len] strings of DNA.<br><br>"
			for(var/blood in bloodsamp.dna)
				data += span_blue("Blood type: [bloodsamp.dna[blood]]<br>\nDNA: [blood]<br><br>")
		else
			data += "No DNA found.<br>"
		P.info = span_bold("[src] analysis report #[report_num]") + "<br>"
		P.info += span_bold("Scanned item:") + "<br>[bloodsamp.name]<br>[bloodsamp.desc]<br><br>" + data
		P.forceMove(loc)
		P.update_icon()
		scanning = FALSE
		update_icon()
	return

/obj/machinery/dnaforensics
	silicon_use = SILICON_USE_UI

/obj/machinery/dnaforensics/update_icon()
	..()
	if(!(stat & NOPOWER) && scanning)
		icon_state = "dnaworking"
	else if(bloodsamp)
		icon_state = "dnaclosed"
	else
		icon_state = "dnaopen"
