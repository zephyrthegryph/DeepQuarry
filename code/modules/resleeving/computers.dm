#define MENU_MAIN 1
#define MENU_BODY 2
#define MENU_MIND 3

/obj/machinery/computer/transhuman/resleeving
	name = "resleeving control console"
	catalogue_data = list(/datum/category_item/catalogue/technology/resleeving)
	icon_keyboard = "med_key"
	icon_screen = "dna"
	light_color = "#315ab4"
	bubble_icon = "medical"
	circuit = /obj/item/circuitboard/resleeving_control
	req_access = list(ACCESS_HEADS) //Only used for record deletion right now.
	var/list/pods //Linked grower pods (REL_LIST).
	var/list/spods //Linked synthfabs (REL_LIST).
	var/list/sleevers //Linked resleeving booths (REL_LIST).
	var/list/temp = null
	var/menu = MENU_MAIN //Which menu screen to display
	var/can_grow_active = FALSE
	var/can_sleeve_active = FALSE
	var/organic_capable = 1
	var/synthetic_capable = 1
	var/obj/item/disk/transcore/disk // inserted: owned, spilled with the console
	var/tmp/obj/machinery/clonepod/transhuman/selected_pod
	var/tmp/obj/machinery/transhuman/synthprinter/selected_printer
	var/tmp/obj/machinery/transhuman/resleever/selected_sleever

	var/datum/transhuman/body_record/current_br
	var/datum/transhuman/mind_record/current_mr

	// Resleeving database this machine interacts with. Blank for default database
	// Needs a matching /datum/transcore_db with key defined in code
	var/db_key

	var/gene_sequencing = FALSE // Traitgenes edit - create a dna injector for fixing dna, but don't let it be abusable

/obj/machinery/computer/transhuman/resleeving/Initialize(mapload)
	. = ..()
	updatemodules()

// its pods are released.
/obj/machinery/computer/transhuman/resleeving/on_destroy(force)
	releasepods()
	..()

/obj/machinery/computer/transhuman/resleeving/proc/updatemodules()
	releasepods()
	findpods()

/obj/machinery/computer/transhuman/resleeving/proc/releasepods()
	for(var/obj/machinery/clonepod/transhuman/P in pods)
		rel_clear(P, "connected")
		P.name = initial(P.name)
	rel_clear(src, "pods")
	for(var/obj/machinery/transhuman/synthprinter/P in spods)
		rel_clear(P, "connected")
		P.name = initial(P.name)
	rel_clear(src, "spods")
	for(var/obj/machinery/transhuman/resleever/P in sleevers)
		rel_clear(P, "connected")
		P.name = initial(P.name)
	rel_clear(src, "sleevers")

/obj/machinery/computer/transhuman/resleeving/proc/findpods()
	var/num = 1
	var/area/A = get_area(src)
	for(var/obj/machinery/clonepod/transhuman/P in A.get_contents())
		if(!P.connected())
			rel_add(src, "pods", P)
			rel_set(P, "connected", src)
			P.name = "[initial(P.name)] #[num++]"
	for(var/obj/machinery/transhuman/synthprinter/P in A.get_contents())
		if(!P.connected)
			rel_add(src, "spods", P)
			rel_set(P, "connected", src)
			P.name = "[initial(P.name)] #[num++]"
	for(var/obj/machinery/transhuman/resleever/P in A.get_contents())
		if(!P.connected)
			rel_add(src, "sleevers", P)
			rel_set(P, "connected", src)
			P.name = "[initial(P.name)] #[num++]"

EXTEND_INTERACTIONS(/obj/machinery/computer/transhuman/resleeving, \
	INTERACT_ITEM(null, PROC_REF(resleeving_console_interaction_item)), \
	INTERACT_HAND_UNGATED(null, PROC_REF(resleeving_console_interaction_hand)), \
)

/// Old attackby.
/obj/machinery/computer/transhuman/resleeving/proc/resleeving_console_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/disk/transcore) && !our_db().core_dumped)
		user.unEquip(W)
		W.forceMove(src)
		own_set(src, "disk", W)
		to_chat(user, span_notice("You insert \the [W] into \the [src]."))
	if(istype(W, /obj/item/disk/body_record))
		var/obj/item/disk/body_record/brDisk = W
		if(!brDisk.stored)
			to_chat(user, span_warning("\The [W] does not contain a stored body record."))
			return INTERACTION_HANDLED_PASS
		user.unEquip(W)
		W.forceMove(get_turf(src)) // Drop on top of us
		rel_set(src, "current_br", brDisk.stored)
		to_chat(user, span_notice("\The [src] loads the body record from \the [W] before ejecting it."))
		attack_hand(user)
		view_b_rec(REF(brDisk.stored))
		return INTERACTION_HANDLED_PASS
	return FALSE

/obj/machinery/computer/transhuman/resleeving/multitool_act(mob/user, obj/item/tool)
	var/obj/item/multitool/multitool = tool
	var/obj/machinery/clonepod/transhuman/pod = multitool.connecting()
	if(!istype(pod) || (pod in pods))
		return ITEM_INTERACT_BLOCKING
	rel_add(src, "pods", pod)
	rel_set(pod, "connected", src)
	pod.name = "[initial(pod.name)] #[LAZYLEN(pods)]"
	to_chat(user, span_notice("You connect [pod] to [src]."))
	return ITEM_INTERACT_SUCCESS

/// Old attack_hand.
/obj/machinery/computer/transhuman/resleeving/proc/resleeving_console_interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)

	if(!operable())
		return TRUE

	updatemodules()
	tgui_interact(user)
	return TRUE

/obj/machinery/computer/transhuman/resleeving/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/simple/cloning),
		get_asset_datum(/datum/asset/simple/cloning/resleeving),
	)

DECLARE_UI(/obj/machinery/computer/transhuman/resleeving, "ResleevingConsole", UI_TITLE("Resleeving Console"))

/obj/machinery/computer/transhuman/resleeving/ui_prepare(mob/user, datum/tgui/ui)
	if(!operable())
		return FALSE

	return TRUE

UI_DATA_REPLACE(/obj/machinery/computer/transhuman/resleeving, "merge:ui_data_obj_machinery_computer_transhuman_resleeving{menu:unknown,pods:list,spods:list,sleevers:list,coredumped:unknown,emergency:unknown,temp:unknown,selected_pod:text,selected_printer:text,selected_sleever:text,bodyrecords:list,mindrecords:list,active_b_rec:map,active_m_rec:map}")

/// The computed part of /obj/machinery/computer/transhuman/resleeving's window data (declared on its UI_DATA row).
/obj/machinery/computer/transhuman/resleeving/proc/ui_data_obj_machinery_computer_transhuman_resleeving(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/data[0]
	data["menu"] = menu

	var/list/clonepods = list()
	for(var/obj/machinery/clonepod/transhuman/pod in pods)
		var/status = "idle"
		var/mob/living/occupant = pod.get_occupant()
		if(pod.mess)
			status = "mess"
		else if(occupant && !pod.has_stat(NOPOWER))
			status = "cloning"
		clonepods += list(list(
			"pod" = REF(pod),
			"name" = sanitize(capitalize(pod.name)),
			"biomass" = pod.get_biomass(),
			"status" = status,
			"progress" = (occupant && occupant.stat != DEAD) ? pod.get_completion() : 0
		))
	data["pods"] = clonepods

	var/list/synthpods = list()
	for(var/obj/machinery/transhuman/synthprinter/spod in spods)
		synthpods += list(list(
			"spod" = REF(spod),
			"name" = sanitize(capitalize(spod.name)),
			"busy" = spod.busy,
			"steel" = spod.stored_material[MAT_STEEL],
			"glass" = spod.stored_material[MAT_GLASS]
		))
	data["spods"] = synthpods

	var/list/resleevers = list()
	for(var/obj/machinery/transhuman/resleever/resleever in sleevers)
		resleevers += list(list(
			"sleever" = REF(resleever),
			"name" = sanitize(capitalize(resleever.name)),
			"occupied" = !!resleever.get_occupant(),
			"occupant" = resleever.get_occupant() ? resleever.get_occupant().real_name : "None"
		))
	data["sleevers"] = resleevers

	data["coredumped"] = our_db().core_dumped
	data["emergency"] = disk()
	data["temp"] = temp
	data["selected_pod"] = REF(selected_pod())
	data["selected_printer"] = REF(selected_printer())
	data["selected_sleever"] = REF(selected_sleever())

	var/list/bodyrecords_list_ui = list()
	for(var/N in our_db().body_scans)
		var/datum/transhuman/body_record/BR = our_db().body_scans[N]
		bodyrecords_list_ui += list(list(
			"name" = N,
			"recref" = REF(BR)
		))
	data["bodyrecords"] = bodyrecords_list_ui

	var/list/mindrecords_list_ui = list()
	for(var/N in our_db().backed_up)
		var/datum/transhuman/mind_record/MR = our_db().backed_up[N]
		mindrecords_list_ui += list(list(
			"name" = N,
			"recref" = REF(MR)
		))
	data["mindrecords"] = mindrecords_list_ui

	data["active_b_rec"] = null
	var/datum/transhuman/body_record/active_br = current_br
	if(active_br)
		data["active_b_rec"] = list(
			activerecord = REF(active_br),
			realname = sanitize(active_br.mydna.name),
			species = active_br.speciesname ? active_br.speciesname : active_br.mydna.dna.species,
			sex = active_br.bodygender,
			mind_compat = active_br.locked ? "Low" : "High",
			synthetic = active_br.synthetic,
			oocnotes = active_br.mind_ref?.identity?.ooc_notes || "None",
			can_grow_active = can_grow_active,
		)

	data["active_m_rec"] = null
	var/datum/transhuman/mind_record/active_mr = current_mr
	if(active_mr)
		data["active_m_rec"] = list(
			activerecord = REF(active_mr),
			realname = sanitize(active_mr.mindname),
			obviously_dead = active_mr.dead_state == MR_DEAD ? "Past-due" : "Current",
			oocnotes = active_mr.mind_ref?.identity?.ooc_notes || "None.",
			can_sleeve_active = can_sleeve_active,
		)

	return data

/obj/machinery/computer/transhuman/resleeving/proc/eject_dump_disk()
	if(!disk())
		return
	visible_message(span_warning("\The [src] spits out \the [disk()]."))
	rel_clear(src, "current_br")
	disk().forceMove(get_turf(src))
	own_take(src, "disk")

UI_ACT(/obj/machinery/computer/transhuman/resleeving, "view_b_rec", ui_act_view_b_rec, UI_ARG_VALUE("ref"))
UI_ACT_PROC(/obj/machinery/computer/transhuman/resleeving, ui_act_view_b_rec)
	view_b_rec(params["ref"])
	. = TRUE

UI_ACT(/obj/machinery/computer/transhuman/resleeving, "clear_b_rec", ui_act_clear_b_rec)
UI_ACT_PROC(/obj/machinery/computer/transhuman/resleeving, ui_act_clear_b_rec)
	rel_clear(src, "current_br")
	. = TRUE

UI_ACT(/obj/machinery/computer/transhuman/resleeving, "view_m_rec", ui_act_view_m_rec, UI_ARG_VALUE("ref"))
UI_ACT_PROC(/obj/machinery/computer/transhuman/resleeving, ui_act_view_m_rec)
	view_m_rec(params["ref"])
	. = TRUE

UI_ACT(/obj/machinery/computer/transhuman/resleeving, "clear_m_rec", ui_act_clear_m_rec)
UI_ACT_PROC(/obj/machinery/computer/transhuman/resleeving, ui_act_clear_m_rec)
	rel_clear(src, "current_mr")
	. = TRUE

UI_ACT(/obj/machinery/computer/transhuman/resleeving, "coredump", ui_act_coredump)
UI_ACT_PROC(/obj/machinery/computer/transhuman/resleeving, ui_act_coredump)
	if(disk())
		our_db().core_dump(disk())
		om_after(src, 0.5 SECONDS, PROC_REF(eject_dump_disk))
		. = TRUE

UI_ACT(/obj/machinery/computer/transhuman/resleeving, "ejectdisk", ui_act_ejectdisk)
UI_ACT_PROC(/obj/machinery/computer/transhuman/resleeving, ui_act_ejectdisk)
	rel_clear(src, "current_br")
	if(disk())
		disk().forceMove(get_turf(src))
		own_take(src, "disk")
	. = TRUE

UI_ACT(/obj/machinery/computer/transhuman/resleeving, "create", ui_act_create)
UI_ACT_PROC(/obj/machinery/computer/transhuman/resleeving, ui_act_create)
	resleeve_create_body()
	. = TRUE

UI_ACT(/obj/machinery/computer/transhuman/resleeving, "selectpod", ui_act_selectpod, UI_ARG_REF("ref", "pods", /obj/machinery/clonepod))
UI_ACT_PROC(/obj/machinery/computer/transhuman/resleeving, ui_act_selectpod)
	var/obj/machinery/clonepod/selected = params["ref"]
	if(selected)
		rel_set(src, "selected_pod", selected)
	. = TRUE

UI_ACT(/obj/machinery/computer/transhuman/resleeving, "selectprinter", ui_act_selectprinter, UI_ARG_REF("ref", "spods", /obj/machinery/transhuman/synthprinter))
UI_ACT_PROC(/obj/machinery/computer/transhuman/resleeving, ui_act_selectprinter)
	var/obj/machinery/transhuman/synthprinter/selected = params["ref"]
	if(selected)
		rel_set(src, "selected_printer", selected)
	. = TRUE

UI_ACT(/obj/machinery/computer/transhuman/resleeving, "selectsleever", ui_act_selectsleever, UI_ARG_REF("ref", "sleevers", /obj/machinery/transhuman/resleever))
UI_ACT_PROC(/obj/machinery/computer/transhuman/resleeving, ui_act_selectsleever)
	var/obj/machinery/transhuman/resleever/selected = params["ref"]
	if(selected)
		rel_set(src, "selected_sleever", selected)
	. = TRUE

UI_ACT(/obj/machinery/computer/transhuman/resleeving, "menu", ui_act_menu, UI_ARG_NUM("num", MENU_MAIN, MENU_MIND))
UI_ACT_PROC(/obj/machinery/computer/transhuman/resleeving, ui_act_menu)
	menu = params["num"]
	. = TRUE

UI_ACT(/obj/machinery/computer/transhuman/resleeving, "genereset", ui_act_genereset)
UI_ACT_PROC(/obj/machinery/computer/transhuman/resleeving, ui_act_genereset)
	resleeve_gene_reset()
	. = TRUE

UI_ACT(/obj/machinery/computer/transhuman/resleeving, "cleartemp", ui_act_cleartemp)
UI_ACT_PROC(/obj/machinery/computer/transhuman/resleeving, ui_act_cleartemp)
	temp = null
	. = TRUE

/// "create": grow or print the selected body record on the selected pod.
/obj/machinery/computer/transhuman/resleeving/proc/resleeve_create_body()
	var/datum/transhuman/body_record/active_br = current_br
	if(!istype(active_br))
		set_temp("Error: Data corruption.", "danger")
		rel_clear(src, "current_br")
		return
	if(active_br.synthetic)
		if(!LAZYLEN(spods))
			set_temp("Error: No SynthFabs detected.", "danger")
			return
		print_synthetic_body(active_br)
	else
		if(!LAZYLEN(pods))
			set_temp("Error: No growpods detected.", "danger")
			return
		grow_organic_body(active_br)

/// Why the selected SynthFab can't print a body, or null when it can.
/obj/machinery/computer/transhuman/resleeving/proc/synthprinter_error(obj/machinery/transhuman/synthprinter/spod)
	if(!istype(spod))
		return "Error: No SynthFab selected."
	if(spod.busy)
		return "Error: SynthFab is currently busy."
	if(spod.stored_material[MAT_STEEL] < spod.body_cost)
		return "Error: Not enough [MAT_STEEL] in SynthFab."
	if(spod.stored_material[MAT_GLASS] < spod.body_cost)
		return "Error: Not enough glass in SynthFab."
	if(spod.broken)
		return "Error: SynthFab malfunction."
	return null

/obj/machinery/computer/transhuman/resleeving/proc/print_synthetic_body(datum/transhuman/body_record/active_br)
	var/obj/machinery/transhuman/synthprinter/spod = selected_printer()
	var/error = synthprinter_error(spod)
	if(error)
		set_temp(error, "danger")
	else if(spod.print(active_br))
		set_temp("Initiating printing cycle...", "success")
		menu = 1
	else
		set_temp("Initiating printing cycle... Error: Post-initialisation failed. Printing cycle aborted.", "danger")
	rel_clear(src, "current_br")

/// Why the selected growpod can't grow a body, or null when it can.
/obj/machinery/computer/transhuman/resleeving/proc/growpod_error(obj/machinery/clonepod/transhuman/pod)
	if(!istype(pod))
		return "Error: No clonepod selected."
	if(pod.get_occupant())
		return "Error: Growpod is currently occupied."
	if(pod.get_biomass() < CLONE_BIOMASS)
		return "Error: Not enough biomass."
	if(pod.mess)
		return "Error: Growpod malfunction."
	if(!CONFIG_GET(flag/revival_cloning))
		return "Error: Unable to initiate growing cycle."
	return null

/obj/machinery/computer/transhuman/resleeving/proc/grow_organic_body(datum/transhuman/body_record/active_br)
	var/obj/machinery/clonepod/transhuman/pod = selected_pod()
	var/error = growpod_error(pod)
	if(error)
		set_temp(error, "danger")
	else if(pod.growclone(active_br))
		set_temp("Initiating growing cycle...", "success")
	else
		set_temp("Initiating growing cycle... Error: Post-initialisation failed. Growing cycle aborted.", "danger")
	rel_clear(src, "current_br")

/// "sleeve": put the selected mind record into the selected resleever's body (mode 1) or a card (mode 2).
/// Prompts re-run the action with the same params.
UI_ACT(/obj/machinery/computer/transhuman/resleeving, "sleeve", act_sleeve, UI_ARG_NUM("mode"))
UI_ACT_PROC(/obj/machinery/computer/transhuman/resleeving, act_sleeve)
	. = TRUE
	var/datum/transhuman/mind_record/active_mr = current_mr
	if(!istype(active_mr))
		set_temp("Error: Data corruption.", "danger")
		rel_clear(src, "current_mr")
		return
	if(!LAZYLEN(sleevers))
		set_temp("Error: No sleevers detected.", "danger")
		rel_clear(src, "current_mr")
		return
	var/mode = params["mode"]
	var/override
	var/obj/machinery/transhuman/resleever/sleever = selected_sleever()
	if(!istype(sleever))
		set_temp("Error: No resleeving pod selected.", "danger")
		rel_clear(src, "current_mr")
		return

	switch(mode)
		if(1) //Body resleeving
			var/error = sleeve_body_error(sleever, active_mr)
			if(error)
				set_temp(error, "danger")
				rel_clear(src, "current_mr")
				return
			var/list/subtargets = list()
			for(var/mob/living/carbon/human/H in sleever.get_occupant())
				if(H.resleeve_lock && active_mr.ckey != H.resleeve_lock)
					continue
				subtargets += H
			if(subtargets.len)
				var/oc_sanity = sleever.get_occupant()
				var/_answer_k417 = act_ask(ui.user, action, params, ui, "k417", /datum/om/prompt/choice, message = "Multiple bodies detected. Select target for resleeving of [active_mr.mindname] manually. Sleeving of primary body is unsafe with sub-contents, and is not listed.", title = "Resleeving Target", choices = subtargets)
				if(isnull(_answer_k417))
					return
				override = _answer_k417
				if(!override || oc_sanity != sleever.get_occupant() || !(override in sleever.get_occupant()))
					set_temp("Error: Target selection aborted.", "danger")
					rel_clear(src, "current_mr")
					return

		if(2) //Card resleeving
			if(sleever.sleevecards <= 0)
				set_temp("Error: No available cards in resleever.", "danger")
				rel_clear(src, "current_mr")
				return

	//Body to sleeve into, but mind is in another living body.
	if(active_mr.mind_ref.current && active_mr.mind_ref.current.stat < DEAD) //Mind is in a body already that's alive
		var/answer = act_ask(active_mr.mind_ref.current, action, params, ui, "k431", /datum/om/prompt/choice/alert, message = "Someone is attempting to restore a backup of your mind. Do you want to abandon this body, and move there? You MAY suffer memory loss! (Same rules as CMD apply)", title = "Resleeving", choices = list("No","Yes"))
		if(isnull(answer))
			return
		//They declined to be moved.
		if(answer != "Yes")
			set_temp("Initiating resleeving... Error: Post-initialisation failed. Resleeving cycle aborted.", "danger")
			rel_clear(src, "current_mr")
			return

	//They were dead, or otherwise available.
	sleever.putmind(active_mr, mode, override, db_key = db_key)
	set_temp("Initiating resleeving...")
	rel_clear(src, "current_mr")

/// Why `active_mr` can't be sleeved into the resleever's occupant, or null when it can.
/obj/machinery/computer/transhuman/resleeving/proc/sleeve_body_error(obj/machinery/transhuman/resleever/sleever, datum/transhuman/mind_record/active_mr)
	var/mob/living/carbon/human/occupant = sleever.get_occupant()
	if(!occupant)
		return "Error: Resleeving pod is not occupied."
	if(occupant.resleeve_lock && active_mr.ckey != occupant.resleeve_lock) //OOC body lock thing.
		return "Error: Mind incompatible with body."
	if(occupant.changeling_locked && !is_changeling(active_mr.mind_ref))
		return "Error: Mind incompatible with body"
	return null

/// "genereset": synthesize a DNA injector that resets structural enzymes to the selected body record.
/obj/machinery/computer/transhuman/resleeving/proc/resleeve_gene_reset()
	var/datum/transhuman/body_record/active_br = current_br
	if(gene_sequencing)
		set_temp("Sequencing Record... Please wait.")
		tgui_modal_clear(src)
	else if(istype(active_br))
		set_temp("Sequencing Record...")
		tgui_modal_clear(src)
		gene_sequencing = TRUE
		// Make the injector here, so no desync
		var/obj/item/dnainjector/I = new(src)
		I.name += " ([active_br.mydna.name] - Resequencer)"
		I.desc = "Resequences structural enzymes to match the body record this was created from."
		own_set(I, "buf", active_br.mydna.copy())
		I.buf.types = DNA2_BUF_SE
		I.has_radiation = FALSE // SAFE!
		atom_say("Beginning injector synthesis.")
		om_after(src, 10 SECONDS, PROC_REF(dispense_injector), I)
	rel_clear(src, "current_br")

/obj/machinery/computer/transhuman/resleeving/proc/dispense_injector(obj/item/dnainjector/I)
	I.forceMove(loc)
	gene_sequencing = FALSE
	set_temp("Injector dispensed...")
	visible_message(span_notice("\The [src] ejects \the [I]."))
	play_sfx(src, SFX_MACHINES_DING)

// In here because only relevant to computer
/obj/item/cmo_disk_holder
	name = "cmo emergency packet"
	desc = "A small paper packet with printing on one side. \"Tear open in case of Code Delta or Emergency Evacuation ONLY. Use in any other case is UNLAWFUL.\""
	catalogue_data = list(/datum/category_item/catalogue/technology/resleeving)
	icon = 'icons/vore/custom_items_vr.dmi'
	icon_state = "cmoemergency"
	item_state = "card-id"

EXTEND_INTERACTIONS(/obj/item/cmo_disk_holder, INTERACT_USE("Tear open", PROC_REF(cmo_disk_holder_interaction_tear)))

/// Old attack_self.
/obj/item/cmo_disk_holder/proc/cmo_disk_holder_interaction_tear(mob/user, obj/item/held, datum/interaction/interaction)
	play_sfx(src, SFX_ITEMS_POSTER_RIPPED, 0.5, vary = FALSE)
	to_chat(user, span_warning("You tear open \the [name]."))
	user.unEquip(src)
	var/obj/item/disk/transcore/newdisk = new(get_turf(src))
	user.put_in_any_hand_if_possible(newdisk)
	consume(src, user)

/obj/item/disk/transcore
	name = "TransCore Dump Disk"
	desc = "It has a small label. \n\
	\"1.INSERT DISK INTO RESLEEVING CONSOLE\n\
	2. BEGIN CORE DUMP PROCEDURE\n\
	3. ENSURE DISK SAFETY WHEN EJECTED\""
	catalogue_data = list(/datum/category_item/catalogue/technology/resleeving)
	icon = 'icons/obj/cloning.dmi'
	icon_state = "harddisk"
	item_state = "card-id"
	w_class = ITEMSIZE_SMALL
	var/list/datum/transhuman/mind_record/stored = list() // ALLOW(instance_list): d: the disk's stored records

/**
 * Sets a temporary message to display to the user
 *
 * Arguments:
 * * text - Text to display, null/empty to clear the message from the UI
 * * style - The style of the message: (color name), info, success, warning, danger
 */
/obj/machinery/computer/transhuman/resleeving/proc/set_temp(text = "", style = "info", update_now = FALSE)
	temp = list(text = text, style = style)
	if(update_now)
		SStgui.update_uis(src)

/obj/machinery/computer/transhuman/resleeving/proc/view_b_rec(ref)
	if(!length(ref))
		return

	var/datum/transhuman/body_record/active_br = locate(ref)
	if(istype(active_br))
		if(isnull(active_br.mydna))
			if(!QDELETED(active_br))
				qdel(active_br)
				rel_clear(src, "current_br")
			set_temp("Error: Record corrupt.", "danger")
		else
			can_grow_active = TRUE
			if(!synthetic_capable && active_br.synthetic) //Disqualified due to being synthetic in an organic only.
				can_grow_active = FALSE
				set_temp("Error: Cannot grow [active_br.mydna.name] due to lack of synthfabs.", "danger")
			else if(!organic_capable && !active_br.synthetic) //Disqualified for the opposite.
				can_grow_active = FALSE
				set_temp("Error: Cannot grow [active_br.mydna.name] due to lack of cloners.", "danger")
			else if(!synthetic_capable && !organic_capable) //What have you done??
				can_grow_active = FALSE
				set_temp("Error: Cannot grow [active_br.mydna.name] due to lack of synthfabs and cloners.", "danger")
			else if(active_br.toocomplex)
				can_grow_active = FALSE
				set_temp("Error: Cannot grow [active_br.mydna.name] due to species complexity.", "danger")
			// load it!
			rel_set(src, "current_br", active_br)
	else
		set_temp("Error: Record missing.", "danger")

/obj/machinery/computer/transhuman/resleeving/proc/view_m_rec(ref)
	if(!length(ref))
		return

	var/datum/transhuman/mind_record/active_mr = locate(ref)
	if(istype(active_mr))
		if(isnull(active_mr.ckey))
			if(!QDELETED(active_mr))
				qdel(active_mr)
				rel_clear(src, "current_mr")
			set_temp("Error: Record corrupt.", "danger")
		else
			can_sleeve_active = TRUE
			if(!LAZYLEN(sleevers))
				can_sleeve_active = FALSE
				set_temp("Error: Cannot sleeve due to no sleevers.", "danger")
			if(!selected_sleever())
				can_sleeve_active = FALSE
				set_temp("Error: Cannot sleeve due to no selected sleever.", "danger")
			if(selected_sleever() && !selected_sleever().get_occupant())
				can_sleeve_active = FALSE
				set_temp("Error: Cannot sleeve due to lack of sleever occupant.", "danger")
			// load it!
			rel_set(src, "current_mr", active_mr)
	else
		set_temp("Error: Record missing.", "danger")

#undef MENU_MAIN
#undef MENU_BODY
#undef MENU_MIND

/// LC-refs: the transcore database this uses, looked up by db_key (the databases are a registry).
/obj/machinery/computer/transhuman/resleeving/proc/our_db() as /datum/transcore_db
	return GLOB.transcore_service.db_by_key(db_key)

/// The inserted emergency disk (owned).
/obj/machinery/computer/transhuman/resleeving/proc/disk() as /obj/item/disk/transcore
	return disk

/// The selected_pod (a relation view: null once it is deleted).
/obj/machinery/computer/transhuman/resleeving/proc/selected_pod() as /obj/machinery/clonepod/transhuman
	return selected_pod

/// The selected_printer (a relation view: null once it is deleted).
/obj/machinery/computer/transhuman/resleeving/proc/selected_printer() as /obj/machinery/transhuman/synthprinter
	return selected_printer

/// The selected_sleever (a relation view: null once it is deleted).
/obj/machinery/computer/transhuman/resleeving/proc/selected_sleever() as /obj/machinery/transhuman/resleever
	return selected_sleever

// Linked machines are independent: one-sided relation lists, each machine's `connected` a plain
// back relation. Either end dying drops the link.
REL_LIST(/obj/machinery/computer/transhuman/resleeving, pods)
REL_LIST(/obj/machinery/computer/transhuman/resleeving, spods)
REL_LIST(/obj/machinery/computer/transhuman/resleeving, sleevers)
OWN(/obj/machinery/computer/transhuman/resleeving, disk, OWN_SPILL)
