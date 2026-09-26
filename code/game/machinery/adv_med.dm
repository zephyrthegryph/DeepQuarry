// Pretty much everything here is stolen from the dna scanner FYI

/obj/machinery/bodyscanner
	maintenance_flags = MACHINE_MAINT_STANDARD
	var/mob/living/carbon/human/occupant
	var/locked
	name = "Body Scanner"
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "body_scanner_0"
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	flags = REMOTEVIEW_ON_ENTER
	circuit = /obj/item/circuitboard/body_scanner
	use_power = USE_POWER_IDLE
	idle_power_usage = 60
	active_power_usage = 10000	//10 kW. It's a big all-body scanner.
	light_color = "#00FF00"
	var/obj/machinery/body_scanconsole/console
	var/printing_text = null
	var/scan_level = SCANNABLE_DIFFICULT //By default, we start with level 2 scanning level.

/obj/machinery/bodyscanner/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/bodyscanner/RefreshParts()
	scan_level = SCANNABLE_DIFFICULT
	for(var/obj/item/stock_parts/scanning_module/P in component_parts)
		scan_level += max(0, (P.rating - 2)) //We require T3 parts or higher to actually increase our scan level.

/obj/machinery/bodyscanner/Destroy()
	if(console)
		console.scanner = null
	return ..()

/// Sealed occupant slot (C8, containment.md §10, OM relations step 3).
/datum/om/relation/slot/occupant/body_scanner
	holder = /obj/machinery/bodyscanner
	slot_id = OCCUPANT_SLOT_BODY_SCANNER
	name = "body scanner"
	// No view fields (OM relations step 3): `occupant` is still an ordinary
	// var every reader here uses, but this slot's own on_link()/on_unlink()
	// are its only writer now -- there is no generic field-link mechanism
	// left to do it for them.

/datum/om/relation/slot/occupant/body_scanner/on_link(mob/living/source, obj/machinery/bodyscanner/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(istype(target))
		target.occupant = source

/datum/om/relation/slot/occupant/body_scanner/on_unlink(mob/living/source, obj/machinery/bodyscanner/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(istype(target) && target.occupant == source)
		target.occupant = null

/obj/machinery/bodyscanner/power_change()
	..()
	if(!(stat & (BROKEN|NOPOWER)))
		set_light(2)
	else
		set_light(0)

/obj/machinery/bodyscanner/attackby(obj/item/G, user as mob)
	if(istype(G, /obj/item/grab))
		var/obj/item/grab/H = G
		var/mob/M = GRAB_TARGET(H)
		if(panel_open)
			to_chat(user, span_notice("Close the maintenance panel first."))
			return
		if(!ismob(M))
			return
		if(!ishuman(M))
			to_chat(user, span_warning("\The [src] is not designed for that organism!"))
			return
		if(occupant)
			to_chat(user, span_notice("\The [src] is already occupied!"))
			return
		if(M.has_buckled_mobs())
			to_chat(user, span_warning("\The [M] has other entities attached to it. Remove them first."))
			return
		if(M.abiotic())
			to_chat(user, span_notice("Subject cannot have abiotic items on."))
			return
		if(!M.move_into(src, OCCUPANT_SLOT_BODY_SCANNER))
			return
		update_icon()
		playsound(src, 'sound/machines/medbayscanner1.ogg', 50) // Beepboop you're being scanned. <3
		add_fingerprint(user)
		qdel(G)
		SStgui.update_uis(src)

/obj/machinery/bodyscanner/screwdriver_act(mob/user, obj/item/tool)
	return occupant ? ITEM_INTERACT_BLOCKING : ..()

/obj/machinery/bodyscanner/crowbar_act(mob/user, obj/item/tool)
	return occupant ? ITEM_INTERACT_BLOCKING : ..()

/obj/machinery/bodyscanner/MouseDrop_T(mob/living/carbon/human/O, mob/user as mob)
	if(!istype(O))
		return 0 //not a mob
	if(user.incapacitated())
		return 0 //user shouldn't be doing things
	if(O.anchored)
		return 0 //mob is anchored???
	if(get_dist(user, src) > 1 || get_dist(user, O) > 1)
		return 0 //doesn't use adjacent() to allow for non-GLOB.cardinal (fuck my life)
	if(!ishuman(user) && !isrobot(user))
		return 0 //not a borg or human
	if(panel_open)
		to_chat(user, span_notice("Close the maintenance panel first."))
		return 0 //panel open
	if(occupant)
		to_chat(user, span_notice("\The [src] is already occupied."))
		return 0 //occupied

	if(O.buckled)
		return 0
	if(O.abiotic())
		to_chat(user, span_notice("Subject cannot have abiotic items on."))
		return 0
	if(O.has_buckled_mobs())
		to_chat(user, span_warning("\The [O] has other entities attached to it. Remove them first."))
		return

	if(O == user)
		visible_message("[user] climbs into \the [src].")
	else
		visible_message("[user] puts [O] into the body scanner.")

	if(!O.move_into(src, OCCUPANT_SLOT_BODY_SCANNER))
		return
	update_icon()
	playsound(src, 'sound/machines/medbayscanner1.ogg', 50) // Beepboop you're being scanned. <3
	add_fingerprint(user)
	SStgui.update_uis(src)

/obj/machinery/bodyscanner/relaymove(mob/user as mob)
	if(user.incapacitated())
		return 0 //maybe they should be able to get out with cuffs, but whatever
	go_out()

/obj/machinery/bodyscanner/verb/eject()
	set src in oview(1)
	set category = "Object"
	set name = "Eject Body Scanner"

	if(usr.incapacitated())
		return
	go_out()
	add_fingerprint(usr)

/obj/machinery/bodyscanner/proc/go_out()
	if ((!(occupant) || src.locked))
		return
	slot_remove(occupant, get_turf(src))
	update_icon() // icon_state = "body_scanner_1" // Health display for consoles with light and such.
	SStgui.update_uis(src)
	return

/obj/machinery/bodyscanner/explosion_contents_severity(severity)
	return severity

/obj/machinery/bodyscanner/tgui_host(mob/user)
	if(user == occupant)
		return src
	return console ? console : src

/obj/machinery/bodyscanner/tgui_interact(mob/user, datum/tgui/ui = null)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "BodyScanner", "Body Scanner")
		ui.open()

/obj/machinery/bodyscanner/tgui_data(mob/user)
	// qualitative scanner output. The old block dumped exact
	// damage numbers and every affliction's name; the new builder
	// returns qualitative bands plus DQ scanner-audience findings.
	// Implementation lives in code/modules/medical/bodyscanner/.
	return dq_build_tgui_data()

/obj/machinery/bodyscanner/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE

	. = TRUE
	switch(action)
		if("ejectify")
			eject()
		if("print_p")
			var/atom/target = console ? console : src
			visible_message(span_notice("[target] rattles and prints out a sheet of paper."))
			playsound(src, 'sound/machines/printer.ogg', 50, 1)
			var/obj/item/paper/P = new /obj/item/paper(get_turf(target))
			var/name = occupant ? occupant.name : "Unknown"
			P.info = "<CENTER>" + span_bold("Body Scan - [name]") + "</CENTER><BR>"
			P.info += span_bold("Time of scan:") + " [stationtime2text()]<br><br>"
			P.info += "[generate_printing_text()]"
			var/mob/living/carbon/human/scanned_human = occupant
			if(istype(scanned_human))
				P.info += scanned_human.clinical_exposure_printout()
			P.info += "<br><br>" + span_bold("Notes:") + "<br>"
			P.name = "Body Scan - [name] ([stationtime2text()])"
			if(istype(scanned_human))
				var/datum/money_account/operator_account = medical_trial_account_for_mob(ui?.user)
				var/datum/contract_subject_identity/identity = SScontracts.subject_identity(scanned_human)
				P.medical_scan_evidence = list(
					"subject_ref" = identity.id,
					"subject_id" = identity.id,
					"subject_name" = scanned_human.real_name,
					"scan_time" = world.time,
					"snapshot" = medical_trial_snapshot(scanned_human),
					"trial_markers" = scanned_human.medical_trial_marker_snapshot(),
					"operator_account" = operator_account?.account_number,
				)
				var/evidence_id = SScontracts.register_evidence(CONTRACT_EVIDENCE_MEDICAL_SCAN, identity.id, operator_account?.account_number, P, P.medical_scan_evidence)
				P.attach_contract_evidence(evidence_id)
				emit_contract_event(CONTRACT_EVENT_MEDICAL_SCAN_CREATED, list(
					"subject_id" = identity.id,
					"subject_name" = scanned_human.real_name,
					"actor_account" = operator_account?.account_number,
					"department" = DEPARTMENT_MEDICAL,
					"evidence_ids" = list(evidence_id),
					"scan_time" = world.time,
					"detail" = "Authenticated body scan printed",
				), "medical-scan:[evidence_id]", src, ui?.user, scanned_human)
		else
			return FALSE

/// The printed report: the body scanner diagnosis (paper renderer) plus the
/// patient details a printout carries (species, reagents, allergens, implants).
/obj/machinery/bodyscanner/proc/generate_printing_text()
	if(!istype(occupant))
		return span_blue(span_bold("Occupant Statistics:")) + "<br>\The [src] is empty."
	var/list/dat = list(span_blue(span_bold("Occupant Statistics:")))
	if(occupant.custom_species)
		if(occupant.species.name == SPECIES_CUSTOM)
			dat += span_blue("Sapient Species: [occupant.custom_species]")
		else
			dat += span_blue("Sapient Species: [occupant.custom_species] \[Similar biology to [occupant.species.name]\]")
	var/datum/diagnosis/D = occupant.diagnose(/datum/diagnostic_profile/body_scanner)
	dat += D.render_chat()
	qdel(D)
	dat += "<hr>"
	if(occupant.has_status(EFFECT_PARALYZED) && !(occupant.status_flags & FAKEDEATH))
		dat += "Paralysis: [round(occupant.status_seconds(EFFECT_PARALYZED))] seconds left."
	var/list/allergen_list = assembly_allergy_list(occupant.species.allergens, occupant.species.medallergens)
	if(length(allergen_list))
		dat += "Allergens: [english_list(allergen_list)]"
	if(occupant.has_brain_worms())
		dat += "Large growth detected in frontal lobe, possibly cancerous. Surgical removal is recommended."
	for(var/datum/reagent/R as anything in occupant.reagents?.reagent_list)
		if(R.scannable > scan_level)
			continue
		dat += "Reagent: [R.name], Amount: [R.volume]"
	for(var/datum/reagent/R as anything in occupant.ingested?.reagent_list)
		if(R.scannable > scan_level)
			continue
		dat += "Stomach: [R.name], Amount: [R.volume]"
	for(var/obj/item/organ/external/E as anything in occupant.organs)
		var/unknown_body = 0
		for(var/obj/thing in E.implants)
			var/obj/item/implant/I = thing
			var/obj/item/nif/N = thing
			if(istype(I) && I.known_implant)
				dat += "[capitalize(E.name)]: [I] implanted."
			else if(istype(N) && N.known_implant)
				dat += "[capitalize(E.name)]: [N] implanted."
			else
				unknown_body++
		if(unknown_body)
			dat += "[capitalize(E.name)]: unknown body present."
	for(var/obj/item/organ/internal/malignant/M in occupant.internal_organs)
		var/obj/item/organ/external/parent = occupant.organs_by_name[M.parent_organ]
		dat += span_red("Unknown anatomy detected[parent ? " in the [parent.name]" : ""]!")
	for(var/organ_tag in occupant.species.has_organ)
		if(!occupant.internal_organs_by_name[organ_tag])
			var/obj/item/organ/O = occupant.species.has_organ[organ_tag]
			dat += span_red("[capitalize(initial(O.name))]: MISSING")
	if(occupant.sdisabilities & BLIND)
		dat += span_red("Cataracts detected.")
	if(occupant.disabilities & NEARSIGHTED)
		dat += span_red("Retinal misalignment detected.")
	for(var/addic in occupant.get_all_addictions())
		var/level = occupant.get_addiction_to_reagent(addic)
		if(level > 0 && level < 80)
			var/datum/reagent/R = SSchemistry.chemical_reagents[addic]
			dat += span_red("Experiencing withdrawal symptoms: [R.name]")
			break
	return dat.Join("<br>")

//Body Scan Console
/obj/machinery/body_scanconsole
	var/obj/machinery/bodyscanner/scanner
	var/delete
	var/temphtml
	name = "Body Scanner Console"
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "body_scannerconsole"
	dir = 8
	density = FALSE
	anchored = TRUE
	unacidable = TRUE
	circuit = /obj/item/circuitboard/scanner_console
	var/printing = null

/obj/machinery/body_scanconsole/Initialize(mapload)
	. = ..()
	findscanner()

/obj/machinery/body_scanconsole/Destroy()
	if(scanner)
		scanner.console = null
	return ..()

/obj/machinery/body_scanconsole/attackby(obj/item/I, mob/user)
	return attack_hand(user)

/obj/machinery/body_scanconsole/multitool_act(mob/user, obj/item/tool)
	if(!istype(tool, /obj/item/multitool))
		return ITEM_INTERACT_BLOCKING
	var/obj/item/multitool/multitool = tool
	if(istype(multitool.connectable, /obj/machinery/bodyscanner))
		var/obj/machinery/bodyscanner/body_scanner = multitool.connectable
		scanner = body_scanner
		body_scanner.console = src
		to_chat(user, span_warning("You link [src] to [body_scanner]!"))
	else
		to_chat(user, span_warning("You store [src] in [multitool]'s buffer!"))
		multitool.connectable = src
	return ITEM_INTERACT_SUCCESS

/obj/machinery/body_scanconsole/power_change()
	update_icon()

/obj/machinery/body_scanconsole/proc/findscanner()
	spawn(5)
		var/obj/machinery/bodyscanner/bodyscannernew = null
		// Loop through every direction
		for(dir in list(NORTH, EAST, SOUTH, WEST)) // Loop through every direction
			bodyscannernew = locate(/obj/machinery/bodyscanner, get_step(src, dir)) // Try to find a scanner in that direction
			if(bodyscannernew)
				scanner = bodyscannernew
				bodyscannernew.console = src
				set_dir(get_dir(src, bodyscannernew))
				return
		return

/obj/machinery/body_scanconsole/attack_ai(user as mob)
	return attack_hand(user)

/obj/machinery/body_scanconsole/attack_ghost(user as mob)
	return attack_hand(user)

/obj/machinery/body_scanconsole/attack_hand(user as mob)
	if(stat & (NOPOWER|BROKEN))
		return

	if(!scanner)
		findscanner()
		if(!scanner)
			to_chat(user, span_notice("Scanner not found!"))
			return

	if(scanner.panel_open)
		to_chat(user, span_notice("Close the maintenance panel first."))
		return

	if(scanner)
		return scanner.tgui_interact(user)


// === merged from adv_med_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/machinery/bodyscanner
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "scanner_open"

/obj/machinery/body_scanconsole
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "scanner_terminal_off"
	density = TRUE

/obj/machinery/bodyscanner/proc/get_vored_occupant_data(list/incoming, mob/living/carbon/human/H)
	var/humanprey = 0
	var/livingprey = 0
	var/objectprey = 0

	for(var/obj/belly/B as anything in H.vore_organs)
		for(var/C in B)
			if(ishuman(C))
				humanprey++
			else if(isliving(C))
				livingprey++
			else
				objectprey++

	incoming["livingPrey"] = livingprey
	incoming["humanPrey"] = humanprey
	incoming["objectPrey"] = objectprey
	incoming["weight"] = H.weight

	return incoming

/obj/machinery/bodyscanner/update_icon()
	cut_overlays()

	if(!occupant)
		icon_state = "scanner_open"
		set_light(0)
		if(console)
			console.update_icon(0)
		return

	// base image
	icon_state = "new_scanner_off"

	// Determine gradient state
	var/state
	var/scan = TRUE
	var/h_ratio = occupant.is_critical() ? 0 : occupant.vitality()
	if(occupant.stat == DEAD || (occupant.status_flags & FAKEDEATH))
		h_ratio = -1 //shows up dead
	if(console)
		console.update_icon(h_ratio)

	if(stat & (NOPOWER|BROKEN))
		state = "gradient_gray"
		scan = FALSE
		set_light(0)
	else
		switch(h_ratio)
			if(1.000)
				state = "gradient_green"
				set_light(l_range = 1.5, l_power = 2, l_color = COLOR_LIME)
			if(0.001 to 0.999)
				state = "gradient_yellow"
				set_light(l_range = 1.5, l_power = 2, l_color = COLOR_YELLOW)
			else
				state = "gradient_red"
				set_light(l_range = 1.5, l_power = 2, l_color = COLOR_RED)

	// First, we render the occupant
	var/image/occ = image(occupant)
	occ.dir = SOUTH
	var/matrix/M = matrix()
	M.Turn(dir == EAST ? 90 : -90)
	occ.transform = M
	occ.plane = plane
	occ.layer = layer + 0.1
	occ.filters = list(
		filter("type" = "alpha", "icon" = icon(icon, "alpha_mask", dir = dir == EAST ? EAST : WEST)),
		filter("type" = "color", "color" = "#000000")
	)
	add_overlay(occ)

	if(scan)
		// Second, we render the scan beam
		var/image/scan_beam = image(icon(icon, "scan_beam"))
		scan_beam.plane = plane
		scan_beam.layer = layer + 0.2
		add_overlay(scan_beam)

	if(state)
		// Third, we tint everything
		var/image/gradient = image(icon(icon, state))
		gradient.plane = plane
		gradient.layer = layer + 0.3
		add_overlay(gradient)


/obj/machinery/body_scanconsole/update_icon(h_ratio)
	if(stat & (NOPOWER|BROKEN))
		icon_state = "scanner_terminal_off"
		set_light(0)
	else
		if(scanner)
			if(h_ratio)
				switch(h_ratio)
					if(1.000)
						icon_state = "scanner_terminal_green"
						set_light(l_range = 1.5, l_power = 2, l_color = COLOR_LIME)
					if(-0.999 to 0.000)
						icon_state = "scanner_terminal_red"
						set_light(l_range = 1.5, l_power = 2, l_color = COLOR_RED)
					else
						icon_state = "scanner_terminal_dead"
						set_light(l_range = 1.5, l_power = 2, l_color = COLOR_RED)
			else
				icon_state = "scanner_terminal_blue"
				set_light(l_range = 1.5, l_power = 2, l_color = COLOR_BLUE)
		else
			icon_state = "scanner_terminal_off"
			set_light(0)
