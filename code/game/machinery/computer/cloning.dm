#define MENU_MAIN 1
#define MENU_RECORDS 2

/obj/machinery/computer/cloning
	name = "cloning console"
	icon = 'icons/obj/computer.dmi'
	icon_keyboard = "med_key"
	icon_screen = "dna"
	circuit = /obj/item/circuitboard/cloning
	req_access = list(ACCESS_HEADS) //Only used for record deletion right now.
	var/obj/machinery/dna_scannernew/scanner //Linked scanner. For scanning.
	var/list/pods = null //Linked cloning pods.
	var/list/temp = null
	var/list/scantemp = null
	var/menu = MENU_MAIN //Which menu screen to display
	var/list/records = null
	var/datum/transhuman/body_record/active_BR
	/// A record loaded from a disk: the console is its only holder, so it owns it (active_BR is a handle).
	var/datum/transhuman/body_record/loaded_BR
	var/obj/item/disk/body_record/diskette = null // Traitgenes - Storing the entire body record
	var/loading = 0 // Nice loading text
	var/obj/machinery/clonepod/selected_pod
	// 0: Standard body scan
	// 1: The "Best" scan available
	var/scan_mode = 1

	light_color = "#315ab4"

CAPABILITIES(/obj/machinery/computer/cloning)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(autoprocess), wakes_on = list(nameof(autoprocess)))
	owns_one(nameof(loaded_BR), /datum/transhuman/body_record)
	owns_many(nameof(records))
	interface("CloningConsole", title = "Cloning Console")
	op("scan", ui_act("scan"), then(PROC_REF(ui_act_scan)))
	op("autoprocess", ui_act("autoprocess", arg("on", num())), then(PROC_REF(ui_act_autoprocess)))
	op("lock", ui_act("lock"), then(PROC_REF(ui_act_lock)))
	op("view_rec", ui_act("view_rec", arg("ref")), then(PROC_REF(ui_act_view_rec)))
	// deleting a record asks first, in the window (the old boolean modal), and needs the ID in hand when answered
	op("del_rec", ui_act("del_rec"), needs(req(PROC_REF(has_active_record), silent = TRUE)),
		asks(/datum/prompt/yes_no, fields = list("question" = "Please confirm that you want to delete the record by holding your ID and pressing Delete:", "yes_text" = "Delete", "no_text" = "Cancel", "inline" = TRUE, "timeout" = 0), step = "confirm"),
		then(PROC_REF(ui_act_del_rec)))
	op("disk", ui_act("disk", arg("option", schema_text(4096))), then(PROC_REF(ui_act_disk)))
	op("refresh", ui_act("refresh"), then(PROC_REF(ui_act_refresh)))
	op("selectpod", ui_act("selectpod", arg("ref")), then(PROC_REF(ui_act_selectpod)))
	op("clone", ui_act("clone", arg("ref")), then(PROC_REF(ui_act_clone)))
	op("menu", ui_act("menu", arg("num", num(1, 2))), then(PROC_REF(ui_act_menu)))
	op("toggle_mode", ui_act("toggle_mode"), then(PROC_REF(ui_act_toggle_mode)))
	op("eject", ui_act("eject"), then(PROC_REF(ui_act_eject)))
	op("cleartemp", ui_act("cleartemp"), then(PROC_REF(ui_act_cleartemp)))
	op("cloning_console_interaction_item", item(/obj/item), then(PROC_REF(cloning_console_interaction_item)))
	op("cloning_console_interaction_hand", hand(), then(PROC_REF(cloning_console_interaction_hand)))
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(multitool_used)))

// Linked pods (two-sided with each pod's connected; a pod leaves when either end dies).
/obj/machinery/computer/cloning/ownership()
	. = ..()
	. += owns(nameof(diskette), policy = OWN_CONTAINED)

/obj/machinery/computer/cloning/relations()
	. = ..()
	. += rel_many(nameof(pods), back = nameof(/obj/machinery/clonepod::connected))

/obj/machinery/computer/cloning/Initialize(mapload)
	. = ..()
	set_scan_temp("Scanner ready.", "good")
	updatemodules()

/obj/machinery/computer/cloning/var/autoprocess = 0
TRACKED_BRIDGED(/obj/machinery/computer/cloning, autoprocess, CHANGE_MACHINE_SETTINGS)
// its linked cloners are released.
/obj/machinery/computer/cloning/on_destroy(force)
	releasecloner()
	..()

/obj/machinery/computer/cloning/proc/work_step(datum/act/timer/A)
	if(!scanner() || !length(pods) || power_lost())
		return

	if(scanner().get_occupant() && can_autoprocess())
		scan_mob(scanner().get_occupant())

	if(!LAZYLEN(records))
		return

	for(var/obj/machinery/clonepod/pod in pods)
		if(!(pod.get_occupant() || pod.mess) && (pod.efficiency > 5))
			for(var/datum/transhuman/body_record/BR in records)
				if(!(pod.get_occupant() || pod.mess))
					if(pod.growclone(BR))
						own_move(BR, pod, nameof(pod.growing_record))

/obj/machinery/computer/cloning/proc/updatemodules()
	rel_set(src, nameof(scanner), findscanner())
	releasecloner()
	findcloner()
	if(!selected_pod() && length(pods))
		rel_set(src, nameof(selected_pod), pods[1])

/obj/machinery/computer/cloning/proc/findscanner()
	var/obj/machinery/dna_scannernew/scannerf = null

	//Try to find scanner on adjacent tiles first
	for(var/scan_dir in list(NORTH,EAST,SOUTH,WEST))
		scannerf = locate(/obj/machinery/dna_scannernew, get_step(src, scan_dir))
		if(scannerf)
			return scannerf

	//Then look for a free one in the area
	if(!scannerf)
		for(var/obj/machinery/dna_scannernew/S in get_area(src))
			return S

	return 0

/obj/machinery/computer/cloning/proc/releasecloner()
	for(var/obj/machinery/clonepod/P in pods)
		P.name = initial(P.name)
	rel_clear(src, nameof(pods))

/obj/machinery/computer/cloning/proc/findcloner()
	var/num = 1
	for(var/obj/machinery/clonepod/P in get_area(src))
		if(!P.connected())
			rel_add(src, nameof(pods), P)
			P.name = "[initial(P.name)] #[num++]"

/// Old attackby.
/obj/machinery/computer/cloning/proc/cloning_console_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!istype(W, /obj/item/disk/body_record)) //Traitgenes Storing the entire body record
		return OP_DECLINE
	if(!diskette)
		if(!move_into(src, nameof(src.diskette), W, user))
			return OP_DECLINE
		to_chat(user, "You insert [W].")
		SStgui.update_uis(src)
	return TRUE

/obj/machinery/computer/cloning/proc/multitool_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!istype(tool, /obj/item/multitool))
		return OP_OK
	var/obj/item/multitool/multitool = tool
	var/obj/machinery/clonepod/pod = multitool.connecting()
	if(pod && !(pod in pods))
		rel_add(src, nameof(pods), pod)
		pod.name = "[initial(pod.name)] #[length(pods)]"
		to_chat(user, span_notice("You connect [pod] to [src]."))
	return OP_OK

/// Old attack_hand (it never reached the machinery gate).
/obj/machinery/computer/cloning/proc/cloning_console_interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)

	if(!operable())
		return TRUE

	updatemodules()
	tgui_interact(user)
	return TRUE

/obj/machinery/computer/cloning/resleeving/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/simple/cloning)
	)

/obj/machinery/computer/cloning/ui_prepare(mob/user, datum/tgui/ui)
	if(!operable())
		return FALSE

	return TRUE

/obj/machinery/computer/cloning/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["menu"] = menu
	data["loading"] = loading
	data["autoprocess"] = autoprocess
	data["scan_mode"] = scan_mode
	data["temp"] = temp
	data["scantemp"] = scantemp
	data["disk"] = diskette
	data["scanner"] = sanitize("[scanner()]")

	var/canpodautoprocess = 0
	if(length(pods))
		data["numberofpods"] = length(pods)

		var/list/tempods = list()
		for(var/obj/machinery/clonepod/pod in pods)
			if(pod.efficiency > 5)
				canpodautoprocess = 1

			var/mob/living/occupant = pod.get_occupant()
			var/status = "idle"
			if(pod.mess)
				status = "mess"
			else if(occupant && !pod.power_lost())
				status = "cloning"
			tempods.Add(list(list(
				"pod" = "\ref[pod]",
				"name" = sanitize(capitalize(pod.name)),
				"biomass" = pod.get_biomass(),
				"status" = status,
				"progress" = (occupant && occupant.stat != DEAD) ? pod.get_completion() : 0
			)))
			data["pods"] = tempods

	data["can_brainscan"] = can_brainscan() // You'll need tier 4s for this

	if(scanner() && length(pods) && ((scanner().scan_level > 2) || canpodautoprocess))
		data["autoallowed"] = 1
	else
		data["autoallowed"] = 0
	if(scanner())
		data["occupant"] = scanner().get_occupant()
		data["locked"] = scanner().locked
	data["selected_pod"] = "\ref[selected_pod()]"
	var/list/temprecords = list()
	for(var/datum/transhuman/body_record/BR in records)
		var tempRealName = BR.mydna.dna.real_name
		temprecords.Add(list(list("record" = "\ref[BR]", "realname" = sanitize(tempRealName))))
	data["records"] = temprecords

	if(selected_pod() && (selected_pod() in pods) && selected_pod().get_biomass() >= CLONE_BIOMASS)
		data["podready"] = 1
	else
		data["podready"] = 0

	data["modal"] = tgui_modal_data(src)

	return data

/obj/machinery/computer/cloning/proc/ui_act_scan(datum/act/op/A)
	. = TRUE
	var/mob/living/carbon/human/scanner_occupant = scanner()?.get_occupant()
	if(!scanner() || !scanner_occupant || loading)
		return
	set_scan_temp("Scanner ready.", "good")
	loading = TRUE

	after(src, 2 SECONDS, PROC_REF(delayed_scan), with = list(scanner_occupant))
	add_fingerprint(A.actor)

/obj/machinery/computer/cloning/proc/ui_act_autoprocess(datum/act/op/A, on)
	. = TRUE
	set_autoprocess(on > 0)
	add_fingerprint(A.actor)

/obj/machinery/computer/cloning/proc/ui_act_lock(datum/act/op/A)
	. = TRUE
	var/mob/living/carbon/human/scanner_occupant = scanner()?.get_occupant()
	if(isnull(scanner()) || !scanner_occupant) //No locking an open scanner.
		return
	scanner().locked = !scanner().locked
	add_fingerprint(A.actor)

/obj/machinery/computer/cloning/proc/ui_act_view_rec(datum/act/op/A, ref)
	. = TRUE
	var/datum/transhuman/body_record/record = ui_ref(ref, null, /datum/transhuman/body_record)
	if(!record)
		return
	rel_set(src, nameof(/obj/machinery/computer/cloning::active_BR), record)
	if(istype(active_BR(), /datum/transhuman/body_record))
		if(isnull(active_BR().ckey))
			spent(active_BR())
			set_temp("Error: Record corrupt.", "danger")
		else
			var/obj/item/implant/health/H = null
			if(active_BR().mydna.implant)
				H = locate(active_BR().mydna.implant)
			var/list/payload = list(
				activerecord = "\ref[active_BR()]",
				health = (H && istype(H)) ? H.sensehealth() : "",
				realname = sanitize(active_BR().mydna.dna.real_name),
				unidentity = active_BR().mydna.dna.GetUniIdentity(),
				strucenzymes = active_BR().mydna.dna.GetStrucEnzymes(),
			)
			tgui_modal_message(src, "view_rec", "", null, payload)
	else
		rel_clear(src, nameof(/obj/machinery/computer/cloning::active_BR))
		set_temp("Error: Record missing.", "danger")
	add_fingerprint(A.actor)

/obj/machinery/computer/cloning/proc/has_active_record(datum/act/op/A)
	return !QDELETED(active_BR) // ALLOW(reads): the selected record is read when the button is pressed and again when it is answered, never cached

/// The record is deleted when the confirmation is answered with Delete by someone holding an ID with access.
/obj/machinery/computer/cloning/proc/ui_act_del_rec(datum/act/op/A)
	var/mob/user = A.actor
	. = TRUE
	add_fingerprint(user)
	if(!A.step_value("confirm") || !active_BR())
		return
	var/obj/item/card/id/C = user.get_active_hand()
	if(!istype(C) && !istype(C, /obj/item/pda))
		set_temp("ID not in hand.", "danger")
		return
	if(check_access(C))
		var/datum/transhuman/body_record/doomed = active_BR()
		if(doomed in records)
			rel_remove(src, nameof(records), doomed) // Already deletes dna in destroy()
		else
			spent(doomed)
		set_temp("Record deleted.", "success")
		menu = MENU_RECORDS
	else
		set_temp("Access denied.", "danger")

/obj/machinery/computer/cloning/proc/ui_act_disk(datum/act/op/A, option)
	. = TRUE
	if(!length(option))
		return
	switch(option)
		if("load")
			if(isnull(diskette) || isnull(diskette.stored)) // Traitgenes Storing the entire body record
				set_temp("Error: The disk's data could not be read.", "danger")
				return
			else if(isnull(active_BR()))
				set_temp("Error: No active record was found.", "danger")
				menu = MENU_MAIN
				return

			rel_set(src, nameof(/obj/machinery/computer/cloning::loaded_BR), new /datum/transhuman/body_record(diskette.stored))
			rel_set(src, nameof(/obj/machinery/computer/cloning::active_BR), loaded_BR) // Traitgenes Storing the entire body record
			set_temp("Successfully loaded from disk.", "success")
		if("save")
			if(isnull(diskette) || isnull(active_BR())) // Traitgenes Removed readonly
				set_temp("Error: The data could not be saved.", "danger")
				return

			rel_set(diskette, nameof(diskette.stored), new /datum/transhuman/body_record(active_BR())) // Traitgenes Storing the entire body record
			diskette.name = "data disk - '[active_BR().mydna.dna.real_name]'"
			set_temp("Successfully saved to disk.", "success")
		if("eject")
			if(!isnull(diskette))
				diskette.forceMove(get_turf(src))
				rel_take(src, nameof(/obj/machinery/computer/cloning::diskette))
	add_fingerprint(A.actor)

/obj/machinery/computer/cloning/proc/ui_act_refresh(datum/act/op/A)
	. = TRUE
	SStgui.update_uis(src)
	add_fingerprint(A.actor)

/obj/machinery/computer/cloning/proc/ui_act_selectpod(datum/act/op/A, ref)
	. = TRUE
	var/obj/machinery/clonepod/selected = ui_ref(ref, null, /obj/machinery/clonepod)
	if(!selected)
		return
	if(istype(selected) && (selected in pods))
		rel_set(src, nameof(/obj/machinery/computer/cloning::selected_pod), selected)
	add_fingerprint(A.actor)

/obj/machinery/computer/cloning/proc/ui_act_clone(datum/act/op/A, ref)
	. = TRUE
	var/datum/transhuman/body_record/C = ui_ref(ref, null, /datum/transhuman/body_record)
	if(!C)
		return
	//Look for that player! They better be dead!
	if(istype(C))
		tgui_modal_clear(src)
		//Can't clone without someone to clone.  Or a pod.  Or if the pod is busy. Or full of gibs.
		if(!length(pods))
			set_temp("Error: No cloning pod detected.", "danger")
		else
			var/obj/machinery/clonepod/pod = selected_pod()
			var/cloneresult
			if(!selected_pod())
				set_temp("Error: No cloning pod selected.", "danger")
			else if(pod.get_occupant())
				set_temp("Error: The cloning pod is currently occupied.", "danger")
			else if(pod.get_biomass() < CLONE_BIOMASS)
				set_temp("Error: Not enough biomass.", "danger")
			else if(pod.mess)
				set_temp("Error: The cloning pod is malfunctioning.", "danger")
			else if(!CONFIG_GET(flag/revival_cloning))
				set_temp("Error: Unable to initiate cloning cycle.", "danger")
			else
				cloneresult = pod.growclone(C)
				if(cloneresult)
					set_temp("Initiating cloning cycle...", "success")
					play_sfx(src, SFX_MACHINES_MEDBAYSCANNER1, 2)
					own_move(C, pod, nameof(/obj/machinery/clonepod::growing_record))
					menu = MENU_MAIN
				else
					set_temp("Error: Initialisation failure.", "danger")
	else
		set_temp("Error: Data corruption.", "danger")
	add_fingerprint(A.actor)

/obj/machinery/computer/cloning/proc/ui_act_menu(datum/act/op/A, num_arg)
	. = TRUE
	menu = num_arg
	add_fingerprint(A.actor)

/obj/machinery/computer/cloning/proc/ui_act_toggle_mode(datum/act/op/A)
	. = TRUE
	if(loading)
		return
	if(can_brainscan())
		scan_mode = !scan_mode
	else
		scan_mode = FALSE
	add_fingerprint(A.actor)

/obj/machinery/computer/cloning/proc/ui_act_eject(datum/act/op/A)
	. = TRUE
	if(A.actor.incapacitated() || !scanner() || loading)
		return
	scanner().eject_occupant(A.actor)
	scanner().add_fingerprint(A.actor)
	add_fingerprint(A.actor)

/obj/machinery/computer/cloning/proc/ui_act_cleartemp(datum/act/op/A)
	. = TRUE
	temp = null
	add_fingerprint(A.actor)

/obj/machinery/computer/cloning/proc/scan_mob(mob/living/carbon/human/subject as mob, scan_brain = 0)
	if(power_lost())
		return
	if((scanner().power_lost() || scanner().broken_now()))
		return
	if(scan_brain && !can_brainscan())
		return
	if(isnull(subject) || (!(ishuman(subject))) || (!subject.dna))
		if(isalien(subject))
			set_scan_temp("Genaprawns are not scannable.", "bad")
			SStgui.update_uis(src)
			return
		// can add more conditions for specific non-human messages here
		else
			set_scan_temp("Subject species is not scannable.", "bad")
			SStgui.update_uis(src)
			return
	if(!subject.has_brain())
		if(ishuman(subject))
			var/mob/living/carbon/human/H = subject
			if(H.should_have_organ(O_BRAIN))
				set_scan_temp("No brain detected in subject.", "bad")
		else
			set_scan_temp("No brain detected in subject.", "bad")
		SStgui.update_uis(src)
		return
	if(subject.suiciding)
		set_scan_temp("Subject has committed suicide and is not scannable.", "bad")
		SStgui.update_uis(src)
		return
	if((!subject.ckey) || (!subject.client))
		set_scan_temp("Subject's brain is not responding. Further attempts after a short delay may succeed.", "bad")
		SStgui.update_uis(src)
		return
	if((subject.has_mutation(NOCLONE)))
		set_scan_temp("Subject has incompatible genetic mutations.", "bad")
		SStgui.update_uis(src)
		return
	if(!isnull(find_record(subject.ckey)))
		set_scan_temp("Subject already in database.")
		SStgui.update_uis(src)
		return

	for(var/obj/machinery/clonepod/pod in pods)
		var/mob/living/occupant = pod.get_occupant()
		if(occupant && occupant.mind == subject.mind)
			set_scan_temp("Subject already getting cloned.")
			SStgui.update_uis(src)
			return

	subject.dna.check_integrity()
	var/datum/transhuman/body_record/BR = new(subject)

	//Add an implant if needed
	var/obj/item/implant/health/imp = locate(/obj/item/implant/health, subject)
	if (isnull(imp))
		imp = new /obj/item/implant/health(subject)
		imp.implanted = subject
		BR.mydna.implant = "\ref[imp]"
	//Update it if needed
	else
		BR.mydna.implant = "\ref[imp]"

	if (!isnull(subject.mind)) //Save that mind so traitors can continue traitoring after cloning.
		BR.mydna.mind = "\ref[subject.mind]"

	rel_add(src, nameof(records), BR)
	set_scan_temp("Subject successfully scanned.", "good")
	SStgui.update_uis(src)

//Find a specific record by key.
/obj/machinery/computer/cloning/proc/find_record(find_key)
	var/selected_record = null
	for(var/datum/transhuman/body_record/BR in records)
		if(BR.mydna.ckey == find_key)
			selected_record = BR
			break
	return selected_record

/obj/machinery/computer/cloning/proc/can_autoprocess()
	return (scanner() && scanner().scan_level > 2)

/obj/machinery/computer/cloning/proc/can_brainscan()
	return (scanner() && scanner().scan_level > 3)

/**
 * Sets a temporary message to display to the user
 *
 * Arguments:
 * * text - Text to display, null/empty to clear the message from the UI
 * * style - The style of the message: (color name), info, success, warning, danger
 */
/obj/machinery/computer/cloning/proc/set_temp(text = "", style = "info", update_now = FALSE)
	temp = list(text = text, style = style)
	if(update_now)
		SStgui.update_uis(src)

/**
 * Sets a temporary scan message to display to the user
 *
 * Arguments:
 * * text - Text to display, null/empty to clear the message from the UI
 * * color - The color of the message: (color name)
 */
/obj/machinery/computer/cloning/proc/set_scan_temp(text = "", color = "", update_now = FALSE)
	scantemp = list(text = text, color = color)
	if(update_now)
		SStgui.update_uis(src)

#undef MENU_MAIN
#undef MENU_RECORDS

/obj/machinery/computer/cloning/proc/delayed_scan(mob/living/carbon/human/scanner_occupant)
	if(can_brainscan() && scan_mode)
		scan_mob(scanner_occupant, scan_brain = TRUE)
	else
		scan_mob(scanner_occupant)
	loading = FALSE
	SStgui.update_uis(src)

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/computer/cloning/step_start_condition()
	return autoprocess

/// scanner (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/cloning/proc/scanner() as /obj/machinery/dna_scannernew
	return scanner

/// active BR (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/cloning/proc/active_BR() as /datum/transhuman/body_record
	return active_BR

/// selected pod (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/cloning/proc/selected_pod() as /obj/machinery/clonepod
	return selected_pod

