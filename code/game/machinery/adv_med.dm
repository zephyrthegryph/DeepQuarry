// The body scanner and its console (doc/rewrite/final_api.html section 16, doc/rewrite/conversion_guide.md).
//
// ONE CAPABILITIES list each. The scanner is a machine (machine_basics(): STAT_OPERABLE's bridge, the claws, controls that need it working), an
// occupant pod (occupant_pod(): a person dragged or grabbed in at once, "Move Inside", "Eject", the occupant moving out, tools refused while someone
// is inside; nobody goes in through an open maintenance panel), the link to its console, and its window (the scan, the eject button, the printer),
// which the console's window forwards to. The console is a machine that pairs with the scanner beside it and turns to face it (paired_console()), and
// whose window is the scanner's panel.
//
// What the scan shows is the scanner's own state, scan_ratio, worked out when someone gets in or out and when the scanner's power changes; the console
// mirrors it. What the machine core still keeps until the machine track (phase 4): the stat bits read through machine_basics()'s bridge,
// set_use_power(), RefreshParts() with the board and its parts, and maintenance_flags (the panel and the crowbar).

MSG_DEF_SELF(body_scanner/close_scanner_panel, "Close the scanner's maintenance panel first.")
MSG_DEF(body_scanner/linked, "You link %T% to the scanner in your multitool's buffer.", "")
MSG_DEF(body_scanner/buffered, "You store %T% in your multitool's buffer.", "")

/// The scan's reading of an occupant: dead, critical, or the vitality between (BODY_SCAN_EMPTY with nobody inside).
#define BODY_SCAN_EMPTY null
#define BODY_SCAN_DEAD -1
#define BODY_SCAN_CRITICAL 0
#define BODY_SCAN_HEALTHY 1
/// The glow of the scanner and the console while they show a scan.
#define BODY_SCAN_LIGHT_RANGE 1.5
#define BODY_SCAN_LIGHT_POWER 2

/obj/machinery/bodyscanner
	maintenance_flags = MACHINE_MAINT_STANDARD
	locked = null
	name = "Body Scanner"
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "scanner_open"
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
	/// What the scan shows: BODY_SCAN_EMPTY, BODY_SCAN_DEAD, BODY_SCAN_CRITICAL or the occupant's vitality. Worked out when someone gets in or out and
	/// when the power changes (scan()), so the look reads a tracked var and redraws when it moves.
	var/scan_ratio = BODY_SCAN_EMPTY

TRACKED(/obj/machinery/bodyscanner, scan_ratio)

CAPABILITIES(/obj/machinery/bodyscanner)
	blast_contents() // the patient takes the full blast
	machine_basics(repair = NONE)
	occupant_pod(OCCUPANT_SLOT_BODY_SCANNER, bare = TRUE)
	space(SPACE_PANEL, door = nameof(panel_open))
	extend(TAG_POD_ENTER, needs(req_closed(SPACE_PANEL)))
	links(/obj/machinery/bodyscanner::console, /obj/machinery/body_scanconsole::scanner)
	on_notice(/datum/notice/pod_entered, then(PROC_REF(occupant_entered)))
	on_notice(/datum/notice/pod_left, then(PROC_REF(scan)))
	on_change(STAT_OPERABLE, ANY, then(PROC_REF(scan)))
	interface("BodyScanner", title = "Body Scanner")
	op("ejectify", ui_act("ejectify"), then(PROC_REF(eject_from_window)), logs(LOG_GAME))
	op("print_p", ui_act("print_p"), then(PROC_REF(print_report)))
	default_parts()

/obj/machinery/bodyscanner/RefreshParts()
	scan_level = SCANNABLE_DIFFICULT
	for(var/obj/item/stock_parts/scanning_module/P in component_parts)
		scan_level += max(0, (P.rating - 2)) //We require T3 parts or higher to actually increase our scan level.

/// Someone got in: the scan beeps and reads them.
/obj/machinery/bodyscanner/proc/occupant_entered(datum/act/A)
	play_sfx(src, SFX_MACHINES_MEDBAYSCANNER1, vary = FALSE) // Beepboop you're being scanned. <3
	scan(A)

/// Reads the occupant (or nobody) into scan_ratio, and the console's screen follows.
/obj/machinery/bodyscanner/proc/scan(datum/act/A)
	var/mob/living/carbon/human/occupant = occupant_of(src)
	var/ratio = BODY_SCAN_EMPTY
	if(occupant)
		ratio = occupant.is_critical() ? BODY_SCAN_CRITICAL : occupant.vitality()
		if(occupant.stat == DEAD || (occupant.status_flags & FAKEDEATH))
			ratio = BODY_SCAN_DEAD //shows up dead
	set_scan_ratio(ratio)
	console?.set_scan_ratio(ratio)

/// The window's eject button.
/obj/machinery/bodyscanner/proc/eject_from_window(datum/act/op/A)
	if(!length(occupant_eject(src)))
		return OP_FAILED
	add_fingerprint(A.actor)
	return OP_OK

/obj/machinery/bodyscanner/ui_data(datum/act/eval/A)
	// qualitative scanner output. The old block dumped exact
	// damage numbers and every affliction's name; the new builder
	// returns qualitative bands plus DQ scanner-audience findings.
	// Implementation lives in code/modules/medical/bodyscanner/.
	return dq_build_tgui_data()

/// The window's print button: a sheet with the scan, registered as contract evidence when a person was scanned.
/obj/machinery/bodyscanner/proc/print_report(datum/act/op/A)
	var/mob/living/carbon/human/occupant = occupant_of(src)
	var/atom/target = console ? console : src
	visible_message(span_notice("[target] rattles and prints out a sheet of paper."))
	play_sfx(src, SFX_MACHINES_PRINTER)
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
		var/datum/money_account/operator_account = medical_trial_account_for_mob(A.actor)
		var/datum/contract_subject_identity/identity = SScontracts.subject_identity(scanned_human)
		P.medical_scan_evidence = list(
			"subject_ref" = identity.id,
			"subject_id" = identity.id,
			"subject_name" = scanned_human.real_name,
			"scan_time" = EXPIRY_AT(src, CLOCK_WORLD, 0),
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
			"scan_time" = EXPIRY_AT(src, CLOCK_WORLD, 0),
			"detail" = "Authenticated body scan printed",
		), "medical-scan:[evidence_id]", src, A.actor, scanned_human)
	return OP_OK

/// The printed report: the body scanner diagnosis (paper renderer) plus the
/// patient details a printout carries (species, reagents, allergens, implants).
/obj/machinery/bodyscanner/proc/generate_printing_text()
	var/mob/living/carbon/human/occupant = occupant_of(src)
	if(!istype(occupant))
		return span_blue(span_bold("Occupant Statistics:")) + "<br>\The [src] is empty."
	var/list/dat = list(span_blue(span_bold("Occupant Statistics:")))
	if(occupant.custom_species)
		if(occupant.species.name == SPECIES_CUSTOM)
			dat += span_blue("Sapient Species: [occupant.custom_species]")
		else
			dat += span_blue("Sapient Species: [occupant.custom_species] \[Similar biology to [occupant.species.name]\]")
	var/datum/diagnosis/D = occupant.diagnose(/datum/diagnostic_profile/body_scanner, src, TRUE) // D9: a printed scan is an explicit scan
	dat += D.render_chat()
	spent(D)
	dat += "<hr>"
	if(occupant.has_status(STAT_PARALYZED) && !(occupant.status_flags & FAKEDEATH))
		dat += "Paralysis: [round(occupant.status_seconds(STAT_PARALYZED))] seconds left."
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
	for(var/obj/item/organ/internal/malignant/M in occupant.internal_organ_list())
		var/obj/item/organ/external/parent = LAZYACCESS(occupant.organs_by_name, M.parent_organ)
		dat += span_red("Unknown anatomy detected[parent ? " in the [parent.name]" : ""]!")
	for(var/organ_tag in occupant.species.has_organ)
		if(!occupant.organ_in(organ_tag))
			var/obj/item/organ/O = occupant.species.has_organ[organ_tag]
			dat += span_red("[capitalize(initial(O.name))]: MISSING")
	if(occupant.sdisabilities & BLIND)
		dat += span_red("Cataracts detected.")
	if(occupant.is_nearsighted())
		dat += span_red("Retinal misalignment detected.")
	for(var/addic in occupant.get_all_addictions())
		var/level = occupant.get_addiction_to_reagent(addic)
		if(level > 0 && level < 80)
			var/datum/reagent/R = SSchemistry.ready().chemical_reagents[addic]
			dat += span_red("Experiencing withdrawal symptoms: [R.name]")
			break
	return dat.Join("<br>")

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

/// The scanner's look: open and empty, or closed over its occupant with the scan beam and a gradient by the scan's reading, glowing while it works.
/obj/machinery/bodyscanner/draw(datum/look/look)
	..()
	var/mob/living/carbon/human/occupant = occupant_of(src)
	if(!occupant)
		look.state("scanner_open")
		return
	look.state("new_scanner_off")
	var/working = operable()
	// First, the occupant, laid along the bed and masked to its glass
	look.overlay(look_overlay_image(layer = layer + 0.1, plane = plane, dir = SOUTH, transform = turn(matrix(), dir == EAST ? 90 : -90), of = occupant, filters = list(
		filter("type" = "alpha", "icon" = icon(icon, "alpha_mask", dir = dir == EAST ? EAST : WEST)),
		filter("type" = "color", "color" = "#000000"))))
	// Second, the scan beam, then the tint over everything
	if(working)
		look.overlay(look_overlay_image(icon, "scan_beam", layer = layer + 0.2, plane = plane))
	look.overlay(look_overlay_image(icon, working ? body_scan_gradient(scan_ratio) : "gradient_gray", layer = layer + 0.3, plane = plane))
	if(working)
		look.light(BODY_SCAN_LIGHT_RANGE, BODY_SCAN_LIGHT_POWER, body_scan_color(scan_ratio))

/// The gradient state a reading tints the scanner with.
/proc/body_scan_gradient(ratio)
	if(ratio == BODY_SCAN_HEALTHY)
		return "gradient_green"
	if(isnum(ratio) && ratio > BODY_SCAN_CRITICAL && ratio < BODY_SCAN_HEALTHY)
		return "gradient_yellow"
	return "gradient_red"

/// The colour of the scanner's glow for a reading.
/proc/body_scan_color(ratio)
	if(ratio == BODY_SCAN_HEALTHY)
		return COLOR_LIME
	if(isnum(ratio) && ratio > BODY_SCAN_CRITICAL && ratio < BODY_SCAN_HEALTHY)
		return COLOR_YELLOW
	return COLOR_RED

//Body Scan Console
/obj/machinery/body_scanconsole
	name = "Body Scanner Console"
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "scanner_terminal_off"
	dir = 8
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	circuit = /obj/item/circuitboard/scanner_console
	var/obj/machinery/bodyscanner/scanner
	/// The reading its scanner last showed (the scanner's scan_ratio, mirrored by scan()).
	var/scan_ratio = BODY_SCAN_EMPTY

TRACKED(/obj/machinery/body_scanconsole, scan_ratio)

CAPABILITIES(/obj/machinery/body_scanconsole)
	machine_basics(repair = NONE)
	paired_console(/obj/machinery/bodyscanner, nameof(scanner), faces = TRUE)
	interface("BodyScanner", title = "Body Scanner", forwards = nameof(scanner))
	extend("ui_open", binds(item(/obj/item)), needs(req_paired(nameof(scanner)), req(PROC_REF(scanner_panel_closed), because = MSG(body_scanner/close_scanner_panel))))
	op("link_scanner", tool(TOOL_MULTITOOL), label("Link"), wait(0), then(PROC_REF(multitool_link)))

/// The scanner it works is closed up (an open maintenance panel keeps the console's window shut).
/obj/machinery/body_scanconsole/proc/scanner_panel_closed(datum/act/op/A)
	return !scanner?.panel_open

/// A multitool links the console to the scanner in its buffer, or stores the console in the buffer for the scanner to come.
/obj/machinery/body_scanconsole/proc/multitool_link(datum/act/op/A)
	var/obj/item/multitool/multitool = A.held
	if(!istype(multitool))
		return OP_REFUSED
	var/obj/machinery/bodyscanner/body_scanner = multitool.connectable()
	if(istype(body_scanner))
		rel_set(src, nameof(scanner), body_scanner)
		act_message_t(A.actor, src, /datum/msg/body_scanner/linked)
	else
		rel_set(multitool, nameof(multitool.connectable), src)
		act_message_t(A.actor, src, /datum/msg/body_scanner/buffered)
	return OP_OK

/// The console's screen: off without power or a scanner, blue while the scanner is empty, green for a healthy occupant, red for a hurt or critical
/// one, and its dead screen for the dead.
/obj/machinery/body_scanconsole/draw(datum/look/look)
	..()
	if(!operable() || !scanner)
		look.state("scanner_terminal_off")
		return
	if(isnull(scan_ratio))
		look.state("scanner_terminal_blue")
		look.light(BODY_SCAN_LIGHT_RANGE, BODY_SCAN_LIGHT_POWER, COLOR_BLUE)
		return
	if(scan_ratio == BODY_SCAN_HEALTHY)
		look.state("scanner_terminal_green")
		look.light(BODY_SCAN_LIGHT_RANGE, BODY_SCAN_LIGHT_POWER, COLOR_LIME)
		return
	look.state(scan_ratio == BODY_SCAN_DEAD ? "scanner_terminal_dead" : "scanner_terminal_red")
	look.light(BODY_SCAN_LIGHT_RANGE, BODY_SCAN_LIGHT_POWER, COLOR_RED)

#undef BODY_SCAN_EMPTY
#undef BODY_SCAN_DEAD
#undef BODY_SCAN_CRITICAL
#undef BODY_SCAN_HEALTHY
#undef BODY_SCAN_LIGHT_RANGE
#undef BODY_SCAN_LIGHT_POWER
