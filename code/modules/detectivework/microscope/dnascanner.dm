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

	var/tmp/obj/item/forensics/swab/bloodsamp
	var/scanning = 0
	var/scanner_progress = 0
	var/scanner_rate = 5
	EXPIRY_DECLARE(last_process_worldtime)
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
	return !bloodsamp()

/obj/machinery/dnaforensics/proc/not_currently_scanning(mob/actor, atom/target, obj/item/held)
	return !scanning

/obj/machinery/dnaforensics/proc/interaction_insert_swab(mob/user, obj/item/W, datum/interaction/interaction)
	var/obj/item/forensics/swab/swab = W
	if(istype(swab) && swab.is_used())
		user.unEquip(W)
		rel_set(src, "bloodsamp", swab)
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
	effect = /atom/proc/interaction_open_ui

DECLARE_UI(/obj/machinery/dnaforensics, "DNAForensics", UI_TITLE("QuikScan DNA Analyzer"))

/obj/machinery/dnaforensics/ui_prepare(mob/user, datum/tgui/ui)
	if(has_stat(NOPOWER))
		return FALSE
	return TRUE

UI_DATA(/obj/machinery/dnaforensics, "scanning:num", "merge:ui_data_obj_machinery_dnaforensics{scan_progress:num,bloodsamp:unknown,bloodsamp_desc:unknown}")

/// The computed part of /obj/machinery/dnaforensics's window data (declared on its UI_DATA row).
/obj/machinery/dnaforensics/proc/ui_data_obj_machinery_dnaforensics(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["scan_progress"] = round(scanner_progress)
	data["bloodsamp"] = (bloodsamp() ? bloodsamp().name : "")
	data["bloodsamp_desc"] = (bloodsamp() ? (bloodsamp().desc ? bloodsamp().desc : "No information on record.") : "")
	return data

/obj/machinery/dnaforensics/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(has_stat(NOPOWER))
		return FALSE
	return TRUE

UI_ACT(/obj/machinery/dnaforensics, "scanItem", ui_act_scanitem)
UI_ACT_PROC(/obj/machinery/dnaforensics, ui_act_scanitem)
	. = TRUE
	if(scanning)
		scanning = FALSE
		update_icon()
	else
		if(bloodsamp())
			scanner_progress = 0
			scanning = TRUE
			EXPIRY_STAMP(src, last_process_worldtime, CLOCK_WORLD)
			MACHINE_WAKE(src)
			to_chat(ui.user, span_notice("Scan initiated."))
			update_icon()
		else
			to_chat(ui.user, span_warning("Insert an item to scan."))
	. = TRUE

UI_ACT(/obj/machinery/dnaforensics, "ejectItem", ui_act_ejectitem)
UI_ACT_PROC(/obj/machinery/dnaforensics, ui_act_ejectitem)
	. = TRUE
	if(bloodsamp())
		bloodsamp().forceMove(loc)
		rel_clear(src, "bloodsamp")
		scanning = FALSE
		update_icon()

/// Scans while scanning (started from its UI); otherwise it sleeps.
/obj/machinery/dnaforensics/machine_step()
	if(!scanning)
		return PROCESS_KILL
	if(scanning)
		if(!bloodsamp() || bloodsamp().loc != src)
			rel_clear(src, "bloodsamp")
			scanning = 0
		else if(scanner_progress >= 100)
			complete_scan()
			return
		else
			//calculate time difference
			var/deltaT = (world.time - last_process_worldtime) * 0.1
			scanner_progress = min(100, scanner_progress + scanner_rate * deltaT)
	EXPIRY_STAMP(src, last_process_worldtime, CLOCK_WORLD)

/obj/machinery/dnaforensics/proc/complete_scan()
	visible_message(span_notice("[icon2html(src,viewers(src))] makes an insistent chime."), 2)
	update_icon()
	if(bloodsamp())
		var/obj/item/paper/P = new(src)
		P.name = "[src] report #[++report_num]: [bloodsamp().name]"
		P.stamped = list(/obj/item/stamp)
		P.cut_overlays()
		P.add_overlay("paper_stamped")
		//dna data itself
		var/data = "No scan information available."
		if(bloodsamp().dna != null)
			data = "Spectometric analysis on provided sample has determined the presence of [bloodsamp().dna.len] strings of DNA.<br><br>"
			for(var/blood in bloodsamp().dna)
				data += span_blue("Blood type: [bloodsamp().dna[blood]]<br>\nDNA: [blood]<br><br>")
		else
			data += "No DNA found.<br>"
		P.info = span_bold("[src] analysis report #[report_num]") + "<br>"
		P.info += span_bold("Scanned item:") + "<br>[bloodsamp().name]<br>[bloodsamp().desc]<br><br>" + data
		P.forceMove(loc)
		P.update_icon()
		scanning = FALSE
		update_icon()
	return

/obj/machinery/dnaforensics
	silicon_use = SILICON_USE_UI

APPEARANCE_TEMPLATE(/obj/machinery/dnaforensics, "dna{appearance_mode}")

/obj/machinery/dnaforensics/proc/appearance_mode()
	if(!has_stat(NOPOWER) && scanning)
		return "working"
	return bloodsamp() ? "closed" : "open"

/// the bloodsamp this refers to (a relation view: null once it is deleted).
/obj/machinery/dnaforensics/proc/bloodsamp() as /obj/item/forensics/swab
	return bloodsamp
