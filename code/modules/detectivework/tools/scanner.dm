/obj/item/detective_scanner
	icon = 'icons/obj/device.dmi'
	name = "forensic scanner"
	desc = "Used to scan objects for DNA and fingerprints."
	icon_state = "forensic"
	var/list/stored
	w_class = ITEMSIZE_SMALL
	item_state = "electronic"
	flags = NOBLUDGEON
	slot_flags = SLOT_BELT

	var/reveal_fingerprints = TRUE
	var/reveal_incompletes = FALSE
	var/reveal_blood = TRUE
	var/reveal_fibers = FALSE

	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

CAPABILITIES(/obj/item/detective_scanner)
	owns_many(nameof(stored))
	op("examine_data_effect", menu(), label("Examine Forensic Data"), then(PROC_REF(examine_data_effect)))
	op("detective_scanner_wipe_effect", menu(), label("Wipe Forensic Data"), asks(/datum/prompt/choice, fields = list("question" = computed(PROC_REF(detective_scanner_wipe_effect_k217_question)), "title" = "Wipe Data", "choices" = list("Yes","No"), "buttons" = TRUE, "timeout" = 0), step = "k217"), then(PROC_REF(detective_scanner_wipe_effect)))

/obj/item/detective_scanner/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if (!ishuman(M))
		to_chat(user, span_warning("\The [M] does not seem to be compatible with this device."))
		flick("[icon_state]0",src)
		return ITEM_INTERACT_FAILURE
	var/mob/living/carbon/human/target = M

	if(reveal_fingerprints)
		if((!( istype(target.dna, /datum/dna) ) || target.get_equipped_item(SLOT_ID_GLOVES)))
			to_chat(user, span_notice("No fingerprints found on [target]"))
			flick("[icon_state]0",src)
			return ITEM_INTERACT_FAILURE
		else if(user.zone_sel.selecting == BP_R_HAND || user.zone_sel.selecting == BP_L_HAND)
			var/obj/item/sample/print/P = new /obj/item/sample/print(user.loc)
			P.attack(target, user)
			to_chat(user, span_notice("Done printing."))

	if(reveal_blood && target.forensic_data?.has_blooddna())
		to_chat(user, span_notice("Blood found on [target]. Analysing..."))
		after(user, 1.5 SECONDS, /proc/detective_scanner_blood_report, with = list(user, target))
	return ITEM_INTERACT_SUCCESS

/obj/item/detective_scanner/afterattack(atom/A as obj|turf, mob/user, proximity)
	if(!proximity) return
	if(ismob(A))
		return

	if(istype(A,/obj/item/sample/print))
		to_chat(user, "The scanner displays on the screen: \"ERROR 43: Object on Excluded Object List.\"")
		flick("[icon_state]0",src)
		return

	add_fingerprint(user)

	task_start(/datum/task/timed/detective_scanner_scan, user, src, A = A)
	return 0

/datum/task/timed/detective_scanner_scan
	duration = 1 SECOND
	complete_proc = /obj/item/detective_scanner/proc/scan_done
	fail_message = span_warning("You must remain still for the device to complete its work.")
	var/atom/A

/// The scan: prints now, then fibres and blood (each a further timed action when analysed).
/obj/item/detective_scanner/proc/scan_done(datum/task/timed/detective_scanner_scan/task)
	var/atom/A = task.A
	var/mob/user = task.actor
	// Contract evidence is authenticated by its ordinary paper/shipment
	// metadata, not by a bespoke scanner mode. This runs before the traditional
	// fingerprint early return so a clean document remains investigable.
	process_agent_forensic_scan(A, user)

	//General
	if (!A.forensic_data?.has_prints() && !A.forensic_data?.has_fibres() && !A.forensic_data?.has_blooddna())
		act_message(user, A, MSG_SELF(span_warning("Unable to locate any fingerprints, materials, fibers, or blood on %T%!")), \
			MSG_OTHERS("%U% scans %T% with \a [src], the air around [user.gender == MALE ? "him" : "her"] humming[prob(70) ? " gently." : "."]"), \
			MSG_BLIND("You hear a faint hum of electrical equipment."))
		flick("[icon_state]0",src)
		return 0

	if(add_data(A))
		to_chat(user,span_notice("Object already in internal memory. Consolidating data..."))
		flick("[icon_state]1",src)
		return

	//PRINTS
	if(A.forensic_data?.has_prints())
		to_chat(user, span_notice("Isolated [A.forensic_data?.get_prints().len] fingerprints:"))
		if(!reveal_incompletes)
			to_chat(user, span_warning("Rapid Analysis Imperfect: Scan samples with H.R.F.S. equipment to determine nature of incomplete prints."))
		var/list/complete_prints = list()
		var/list/incomplete_prints = list()
		var/list/print_data = A.forensic_data?.get_prints()
		for(var/i in print_data)
			var/print = print_data[i]
			if(stringpercent(print) <= FINGERPRINT_COMPLETE)
				complete_prints += print
			else
				incomplete_prints += print
		if(complete_prints.len < 1)
			to_chat(user, span_notice("No intact prints found"))
		else
			to_chat(user, span_notice("Found [complete_prints.len] intact prints"))
			if(reveal_fingerprints)
				for(var/i in complete_prints)
					to_chat(user, span_notice("&nbsp;&nbsp;&nbsp;&nbsp;[i]"))

		to_chat(user, span_notice("Found [incomplete_prints.len] incomplete prints"))
		if(reveal_incompletes)
			for(var/i in incomplete_prints)
				to_chat(user, span_notice("&nbsp;&nbsp;&nbsp;&nbsp;[i]"))

	scan_fibers(A, user)

/obj/item/detective_scanner/proc/scan_fibers(atom/A, mob/user)
	if(A.forensic_data?.has_fibres())
		to_chat(user,span_notice("Fibers/Materials detected.[reveal_fibers ? " Analysing..." : " Acquisition of fibers for H.R.F.S. analysis advised."]"))
		flick("[icon_state]1",src)
		if(reveal_fibers)
			task_start(/datum/task/timed/forensic_scan, user, src, scanned = A, stage = "fibers")
			return
	scan_blood(A, user)

/// One five-second stage of a forensic scan (fibers, then blood). Interrupted, the scan skips
/// to the next stage.
/datum/task/timed/forensic_scan
	duration = 5 SECONDS
	complete_proc = /obj/item/detective_scanner/proc/scan_stage_done
	cancel_proc = /obj/item/detective_scanner/proc/scan_stage_skipped
	var/atom/scanned
	var/stage

/obj/item/detective_scanner/proc/scan_stage_done(datum/task/timed/forensic_scan/task)
	var/atom/A = task.scanned
	var/mob/user = task.actor
	if(task.stage == "fibers")
		to_chat(user, span_notice("Apparel samples scanned:"))
		for(var/sample in A.forensic_data?.get_fibres())
			to_chat(user, " - " + span_notice("[sample]"))
		scan_blood(A, user)
		return
	flick("[icon_state]1",src)
	var/list/blood_data = A.forensic_data?.get_blooddna()
	for(var/blood in blood_data)
		to_chat(user, "Blood type: " + span_warning("[blood_data[blood]]") + " DNA: " + span_warning("[blood]"))
	scan_finish(A, user)

/obj/item/detective_scanner/proc/scan_stage_skipped(datum/task/timed/forensic_scan/task)
	if(task.stage == "fibers")
		scan_blood(task.scanned, task.actor)
	else
		scan_finish(task.scanned, task.actor)

/obj/item/detective_scanner/proc/scan_blood(atom/A, mob/user)
	if(!A || !user)
		return
	if (A.forensic_data?.has_blooddna())
		to_chat(user, span_notice("Blood detected.[reveal_blood ? " Analysing..." : " Acquisition of swab for H.R.F.S. analysis advised."]"))
		if(reveal_blood)
			task_start(/datum/task/timed/forensic_scan, user, src, scanned = A, stage = "blood")
			return
	scan_finish(A, user)

/obj/item/detective_scanner/proc/scan_finish(atom/A, mob/user)
	if(!A || !user)
		return
	act_message(user, A, MSG_SELF(span_notice("You finish scanning %T%.")), \
		MSG_OTHERS("%U% scans %T% with \a [src], the air around [user.gender == MALE ? "him" : "her"] humming[prob(70) ? " gently." : "."]"), \
		MSG_BLIND("You hear a faint hum of electrical equipment."))
	flick("[icon_state]1",src)
	return 0

/obj/item/detective_scanner/proc/add_data(atom/A as mob|obj|turf|area)
	var/datum/data/record/forensic/old = stored?["\ref [A]"]
	var/datum/data/record/forensic/fresh = new(A)

	if(old)
		fresh.merge(old)
		. = 1
	rel_add(src, nameof(stored), fresh, "\ref [A]")

/obj/item/detective_scanner/proc/examine_data_effect(datum/act/op/A)
	var/mob/user = A.actor

	//to_world("user is [user]") //why was this a thing? -KK.
	display_data(user)

/// Shows the stored records one per second (a timed action each, so moving stops the spam).
/obj/item/detective_scanner/proc/display_data(mob/user)
	if(user && stored && stored.len)
		task_timed(user, 1 SECOND, src, src, PROC_REF(display_record), list(user, 1))

/obj/item/detective_scanner/proc/display_record(mob/user, index)
	if(index > length(stored))
		return
	if(index < length(stored))
		task_timed(user, 1 SECOND, src, src, PROC_REF(display_record), list(user, index + 1))
	var/datum/data/record/forensic/F = stored[stored[index]]
	var/list/fprints = F.fields["fprints"]
	var/list/fibers = F.fields["fibers"]
	var/list/bloods = F.fields["blood"]

	to_chat(user, span_notice("Data for: [F.fields["name"]]"))

	if(reveal_fingerprints)
		var/list/complete_prints = list()
		var/list/incomplete_prints = list()
		for(var/i in fprints)
			var/print = fprints[i]
			if(stringpercent(print) <= FINGERPRINT_COMPLETE)
				complete_prints += print
				to_chat(user, " - " + span_notice("[print]"))
			else
				incomplete_prints += print

		if(complete_prints.len < 1)
			to_chat(user, span_notice("No intact prints found."))

		if(reveal_incompletes)
			for(var/print in incomplete_prints)
				to_chat(user, " - " + span_notice("[print]"))

	if(fibers && fibers.len)
		to_chat(user, span_notice("[fibers.len] samples of material were present."))
		if(reveal_fibers)
			for(var/sample in fibers)
				to_chat(user, " - " + span_notice("[sample]"))

	if(bloods && bloods.len)
		to_chat(user, span_notice("[bloods.len] samples of blood were present."))
		if(reveal_blood)
			for(var/bloodsample in bloods)
				to_chat(user, " - " + span_warning("[bloodsample]") + " Type: [bloods[bloodsample]]")

/obj/item/detective_scanner/proc/detective_scanner_wipe_effect_k217_question(datum/act/op/A)
	return "Are you sure you want to wipe all data from [src]?"

/obj/item/detective_scanner/proc/detective_scanner_wipe_effect(datum/act/op/A)
	var/mob/user = A.actor
	var/_answer_k217 = A.step_value("k217")

	if (_answer_k217 == "Yes")
		own_clear(src, nameof(stored), OWN_DELETE)
		to_chat(user, span_notice("Forensic data erase complete."))

/obj/item/detective_scanner/advanced
	name = "advanced forensic scanner"
	icon_state = "forensic_neo"
	reveal_fibers = TRUE
	reveal_incompletes = TRUE

/proc/detective_scanner_blood_report(mob/user, atom/target)
	var/list/blooddna = target.forensic_data.get_blooddna()
	for(var/blood in blooddna)
		to_chat(user, span_notice("Blood type: [blooddna[blood]]\nDNA: [blood]"))


/// Old object verbs.
