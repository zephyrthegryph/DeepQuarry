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
	var/scanner_progress = 0
	var/scanner_rate = 5
	EXPIRY_DECLARE(last_process_worldtime)
	var/report_num = 0

/obj/machinery/dnaforensics/var/scanning = FALSE
TRACKED_BRIDGED(/obj/machinery/dnaforensics, scanning, CHANGE_MACHINE_SETTINGS)

/// A used forensic swab must be releasable before the analyzer accepts it.
/obj/machinery/dnaforensics/proc/can_insert_swab(mob/user, atom/target, obj/item/held)
	var/obj/item/forensics/swab/swab = held
	if(istype(swab) && swab.is_used())
		var/reason = swab.loc?.release_refusal(swab, user)
		if(reason)
			return reason
	return TRUE

/obj/machinery/dnaforensics/proc/interaction_insert_swab(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	var/obj/item/forensics/swab/swab = W
	if(istype(swab) && swab.is_used())
		if(can_insert_swab(user, src, swab) != TRUE)
			return OP_DECLINE
		if(!swab.loc.release_to(swab, src, null, user))
			return OP_DECLINE
		rel_set(src, nameof(bloodsamp), swab)
		to_chat(user, span_notice("You insert [W] into [src]."))
	else
		to_chat(user, span_warning("\The [src] only accepts used swabs."))
	return OP_OK

CAPABILITIES(/obj/machinery/dnaforensics)
	ref_one(nameof(bloodsamp), /obj/item/forensics/swab)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(scanning), wakes_on = list(nameof(scanning)))
	interface("DNAForensics", title = "QuikScan DNA Analyzer")
	without("ui_open")
	op("scanItem", ui_act("scanItem"), then(PROC_REF(ui_act_scanitem)))
	op("ejectItem", ui_act("ejectItem"), then(PROC_REF(ui_act_ejectitem)))
	op("insert_swab", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Insert swab"), needs(req_empty(nameof(bloodsamp), because = MSG(dnaforensics/sample_loaded)), req_is(nameof(scanning), FALSE, because = MSG(dnaforensics/scanning)), req_held_releasable()), then(PROC_REF(interaction_insert_swab)))
	default_parts()

/obj/machinery/dnaforensics/ui_prepare(mob/user, datum/tgui/ui)
	if(power_lost())
		return FALSE
	return TRUE

/obj/machinery/dnaforensics/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["scanning"] = scanning
	var/list/merged_1 = ui_data_obj_machinery_dnaforensics(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/dnaforensics's window data.
/obj/machinery/dnaforensics/proc/ui_data_obj_machinery_dnaforensics(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["scan_progress"] = round(scanner_progress)
	data["bloodsamp"] = (bloodsamp() ? bloodsamp().name : "")
	data["bloodsamp_desc"] = (bloodsamp() ? (bloodsamp().desc ? bloodsamp().desc : "No information on record.") : "")
	return data

/obj/machinery/dnaforensics/proc/ui_gate(datum/act/op/A)
	if(power_lost())
		return FALSE
	return TRUE

/obj/machinery/dnaforensics/proc/ui_act_scanitem(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	. = TRUE
	if(scanning)
		set_scanning(FALSE)
	else
		if(bloodsamp())
			scanner_progress = 0
			set_scanning(TRUE)
			EXPIRY_STAMP(src, last_process_worldtime, CLOCK_WORLD)
			to_chat(user, span_notice("Scan initiated."))
		else
			to_chat(user, span_warning("Insert an item to scan."))
	. = TRUE

/obj/machinery/dnaforensics/proc/ui_act_ejectitem(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	. = TRUE
	if(bloodsamp())
		bloodsamp().forceMove(loc)
		rel_clear(src, nameof(/obj/machinery/dnaforensics::bloodsamp))
		set_scanning(FALSE)

/// Scans while scanning (started from its UI); otherwise it sleeps.
/obj/machinery/dnaforensics/proc/work_step(datum/act/timer/A)
	if(!bloodsamp() || bloodsamp().loc != src)
		rel_clear(src, nameof(bloodsamp))
		set_scanning(FALSE)
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
		set_scanning(FALSE)
	return

/obj/machinery/dnaforensics
	silicon_use = SILICON_USE_UI

MSG_DEF_SELF(dnaforensics/sample_loaded, "there is a sample in the machine")
MSG_DEF_SELF(dnaforensics/scanning, "it is busy scanning right now")

/// The look (the draw sweep: from its template).
/obj/machinery/dnaforensics/draw(datum/look/look)
	..()
	look.state("dna[appearance_mode()]")

/obj/machinery/dnaforensics/proc/appearance_mode()
	if(!power_lost() && scanning)
		return "working"
	return bloodsamp() ? "closed" : "open"

/// the bloodsamp this refers to (a relation view: null once it is deleted).
/obj/machinery/dnaforensics/proc/bloodsamp() as /obj/item/forensics/swab
	return bloodsamp
