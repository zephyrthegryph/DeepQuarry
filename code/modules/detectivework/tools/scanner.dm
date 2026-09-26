/obj/item/detective_scanner
	icon = 'icons/obj/device.dmi'
	name = "forensic scanner"
	desc = "Used to scan objects for DNA and fingerprints."
	icon_state = "forensic"
	var/list/stored = list()
	w_class = ITEMSIZE_SMALL
	item_state = "electronic"
	flags = NOBLUDGEON
	slot_flags = SLOT_BELT

	var/reveal_fingerprints = TRUE
	var/reveal_incompletes = FALSE
	var/reveal_blood = TRUE
	var/reveal_fibers = FALSE

	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

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
	//		to_chat(user, span_notice("[M]'s Fingerprints: [md5(M.dna.uni_identity)]"))

	if(reveal_blood && target.forensic_data?.has_blooddna())
		to_chat(user, span_notice("Blood found on [target]. Analysing..."))
		spawn(15)
			var/list/blooddna = target.forensic_data.get_blooddna()
			for(var/blood in blooddna)
				to_chat(user, span_notice("Blood type: [blooddna[blood]]\nDNA: [blood]"))
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

	om_do_after(user, 1 SECOND, src, src, PROC_REF(scan_done), list(A, user), on_fail = GLOBAL_PROC_REF(to_chat), fail_args = list(user, span_warning("You must remain still for the device to complete its work.")))
	return 0

/// The scan: prints now, then fibres and blood (each a further timed action when analysed).
/obj/item/detective_scanner/proc/scan_done(atom/A, mob/user)
	// Contract evidence is authenticated by its ordinary paper/shipment
	// metadata, not by a bespoke scanner mode. This runs before the traditional
	// fingerprint early return so a clean document remains investigable.
	process_agent_forensic_scan(A, user)

	//General
	if (!A.forensic_data?.has_prints() && !A.forensic_data?.has_fibres() && !A.forensic_data?.has_blooddna())
		user.visible_message("\The [user] scans \the [A] with \a [src], the air around [user.gender == MALE ? "him" : "her"] humming[prob(70) ? " gently." : "."]" ,\
		span_warning("Unable to locate any fingerprints, materials, fibers, or blood on [A]!"),\
		"You hear a faint hum of electrical equipment.")
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
			om_do_after(user, 5 SECONDS, src, src, PROC_REF(fibers_done), list(A, user), on_fail = PROC_REF(scan_blood), fail_args = list(A, user))
			return
	scan_blood(A, user)

/obj/item/detective_scanner/proc/fibers_done(atom/A, mob/user)
	to_chat(user, span_notice("Apparel samples scanned:"))
	for(var/sample in A.forensic_data?.get_fibres())
		to_chat(user, " - " + span_notice("[sample]"))
	scan_blood(A, user)

/obj/item/detective_scanner/proc/scan_blood(atom/A, mob/user)
	if(!A || !user)
		return
	if (A.forensic_data?.has_blooddna())
		to_chat(user, span_notice("Blood detected.[reveal_blood ? " Analysing..." : " Acquisition of swab for H.R.F.S. analysis advised."]"))
		if(reveal_blood)
			om_do_after(user, 5 SECONDS, src, src, PROC_REF(blood_done), list(A, user), on_fail = PROC_REF(scan_finish), fail_args = list(A, user))
			return
	scan_finish(A, user)

/obj/item/detective_scanner/proc/blood_done(atom/A, mob/user)
	flick("[icon_state]1",src)
	var/list/blood_data = A.forensic_data?.get_blooddna()
	for(var/blood in blood_data)
		to_chat(user, "Blood type: " + span_warning("[blood_data[blood]]") + " DNA: " + span_warning("[blood]"))
	scan_finish(A, user)

/obj/item/detective_scanner/proc/scan_finish(atom/A, mob/user)
	if(!A || !user)
		return
	user.visible_message("\The [user] scans \the [A] with \a [src], the air around [user.gender == MALE ? "him" : "her"] humming[prob(70) ? " gently." : "."]" ,\
	span_notice("You finish scanning \the [A]."),\
	"You hear a faint hum of electrical equipment.")
	flick("[icon_state]1",src)
	return 0

/obj/item/detective_scanner/proc/add_data(atom/A as mob|obj|turf|area)
	var/datum/data/record/forensic/old = stored["\ref [A]"]
	var/datum/data/record/forensic/fresh = new(A)

	if(old)
		fresh.merge(old)
		. = 1
	stored["\ref [A]"] = fresh

/obj/item/detective_scanner/verb/examine_data()
	set name = "Examine Forensic Data"
	set category = "Object"
	set src in view(1)

	//to_world("usr is [usr]") //why was this a thing? -KK.
	display_data(usr)

/// Shows the stored records one per second (a timed action each, so moving stops the spam).
/obj/item/detective_scanner/proc/display_data(mob/user)
	if(user && stored && stored.len)
		om_do_after(user, 1 SECOND, src, src, PROC_REF(display_record), list(user, 1))

/obj/item/detective_scanner/proc/display_record(mob/user, index)
	if(index > length(stored))
		return
	if(index < length(stored))
		om_do_after(user, 1 SECOND, src, src, PROC_REF(display_record), list(user, index + 1))
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

/obj/item/detective_scanner/verb/wipe()
	set name = "Wipe Forensic Data"
	set category = "Object"
	set src in view(1)

	if (tgui_alert(usr, "Are you sure you want to wipe all data from [src]?","Wipe Data",list("Yes","No")) == "Yes")
		stored = list()
		to_chat(usr, span_notice("Forensic data erase complete."))

/obj/item/detective_scanner/advanced
	name = "advanced forensic scanner"
	icon_state = "forensic_neo"
	reveal_fibers = TRUE
	reveal_incompletes = TRUE
