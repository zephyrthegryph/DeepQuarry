#define DNA_BLOCK_SIZE 3

#define PAGE_SE "se"
#define PAGE_BUFFER "buffer"
#define PAGE_REJUVENATORS "rejuvenators"

//list("data" = null, "owner" = null, "label" = null, "type" = null, "ue" = 0),
/datum/dna2/record
	var/datum/dna/dna = null
	var/types=0
	var/name="Empty"

	// Stuff for cloners
	var/id=null
	var/implant=null
	var/ckey=null
	var/mind=null
	var/gender = null

CAPABILITIES(/datum/dna2/record)
	owns_one(nameof(dna), /datum/dna)

/datum/dna2/record/proc/GetData()
	var/list/ser=list("data" = null, "owner" = null, "label" = null, "type" = null, "ue" = 0)
	if(dna)
		ser["ue"] = (types & DNA2_BUF_UE) == DNA2_BUF_UE
		if(types & DNA2_BUF_SE)
			ser["data"] = dna.SE
		else
			ser["data"] = dna.UI
		ser["owner"] = src.dna.real_name
		ser["label"] = name
		if(types & DNA2_BUF_UI)
			ser["type"] = "ui"
		else
			ser["type"] = "se"
	return ser

/datum/dna2/record/proc/copy()
	var/datum/dna2/record/newrecord = new /datum/dna2/record
	for(var/A in vars)
		switch(A)
			if(BLACKLISTED_COPY_VARS)
				continue
			if("id")
				newrecord.id = copytext(md5(dna.real_name), 2, 6) // update this specially
				continue
			if("dna")
				own_clear(newrecord, nameof(newrecord.dna), OWN_DELETE)
				rel_set(newrecord, nameof(newrecord.dna), dna.Clone())
				continue
		if(islist(vars[A]))
			var/list/L = vars[A]
			newrecord.vars[A] = L.Copy() // ALLOW(api): DNA record copy: every var of the record
			continue
		newrecord.vars[A] = vars[A] // ALLOW(api): DNA record copy: every var of the record
	return newrecord

/////////////////////////// DNA MACHINES
/obj/machinery/dna_scannernew
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "\improper DNA modifier"
	desc = "It scans DNA structures."
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "scanner_0"
	density = TRUE
	anchored = TRUE
	flags = REMOTEVIEW_ON_ENTER
	use_power = USE_POWER_IDLE
	idle_power_usage = 50
	active_power_usage = 300
	interact_offline = 1
	circuit = /obj/item/circuitboard/clonescanner
	locked = 0
	VAR_PRIVATE/mob/living/occupant = null
	var/obj/item/reagent_containers/glass/beaker = null
	var/opened = 0
	var/damage_coeff
	var/scan_level
	var/precision_coeff

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with and sizes itself from them
/obj/machinery/dna_scannernew/Initialize(mapload)
	. = ..()
	default_apply_parts()
	RefreshParts()

/// Sealed occupant slot (C8a, containment.md §10). Full blast share: the
/// scanner declares blast_contents(), so its occupant takes the whole blast.
///
/// L1 audit (doc/rewrite/lifecycle.md §3): HOLDER, not the SLOT_DROP_SPILL
/// default. Destroy() calls eject_occupant() -> go_out(), whose cleanup
/// (closing the TGUI, clearing alerts, occupant = null, ...) is gated on its
/// own slot_remove() reporting a move -- which the destroy transaction's
/// contents phase, now running before any Destroy() code, would already
/// have done, silently skipping all of it. Same finding as mecha_pilot
/// above; same follow-up (an on_unslotted() hook migration, not this pass).
/datum/om/relation/slot/occupant/dna_scanner
	holder = /obj/machinery/dna_scannernew
	slot_id = OCCUPANT_SLOT_DNA_SCANNER
	name = "DNA scanner"
	damage_transmission = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0)
	drop_policy = SLOT_DROP_HOLDER

// the occupant slot is holder-resolved: go_out() ejects and cleans up the occupant.
CAPABILITIES(/obj/machinery/dna_scannernew)
	blast_contents()
	op("dna_scanner_interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(dna_scanner_interaction_item)))
	op("dna_scanner_interaction_drag", item(/atom/movable), priority(OP_PRIORITY_DEFAULT - 1), gesture(GESTURE_DRAG), label("Put inside"), then(PROC_REF(dna_scanner_interaction_drag)))
	op("dna_scannernew_eject_effect", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Eject DNA Scanner"), needs(req_adjacent(), req_capable()), then(PROC_REF(dna_scannernew_eject_effect)))
	op("dna_scannernew_move_inside_effect", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Enter DNA Scanner"), needs(req_adjacent(), req_capable()), then(PROC_REF(dna_scannernew_move_inside_effect)))

/obj/machinery/dna_scannernew/on_destroy(force)
	eject_occupant()
	..()

/obj/machinery/dna_scannernew/proc/set_occupant(mob/living/L)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!L)
		rel_clear(src, nameof(occupant))
		return
	rel_set(src, nameof(occupant), L)

/obj/machinery/dna_scannernew/proc/get_occupant()
	RETURN_TYPE(/mob/living)
	SHOULD_NOT_OVERRIDE(TRUE)
	return occupant

/obj/machinery/dna_scannernew/RefreshParts()
	scan_level = 0
	damage_coeff = 0
	precision_coeff = 0
	scan_level += get_part_rating(/obj/item/stock_parts/scanning_module)
	precision_coeff = get_part_rating(/obj/item/stock_parts/manipulator)
	damage_coeff = get_part_rating(/obj/item/stock_parts/micro_laser)

/obj/machinery/dna_scannernew/relaymove(mob/user as mob)
	if(user.stat)
		return
	src.go_out()
	return

/obj/machinery/dna_scannernew/proc/dna_scannernew_eject_effect(datum/act/op/A)
	var/mob/user = A.actor

	if(user.stat != 0)
		return

	eject_occupant()

	add_fingerprint(user)
	return

/obj/machinery/dna_scannernew/proc/eject_occupant()
	var/mob/living/carbon/WC = get_occupant()
	go_out()
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/O in contents_of(src)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		if((!istype(O,/obj/item/reagent_containers)) && (!istype(O,/obj/item/circuitboard/clonescanner)) && (!istype(O,/obj/item/stock_parts)) && (!istype(O,/obj/item/stack/cable_coil)))
			O.forceMove(get_turf(src)) //Ejects items that manage to get in there (exluding the components)
	if(!WC)
		for(var/mob/M in contents_of(src))//Failsafe so you can get mobs out // ALLOW(latent): mobs are never latent
			M.forceMove(get_turf(src))

/// Old MouseDrop_T: allows borgs to clone people without external assistance.
/obj/machinery/dna_scannernew/proc/dna_scanner_interaction_drag(datum/act/op/A)
	// the legacy check, read when the op runs: its text is the refusal
	var/allowed = can_drag_inside(A.actor, src, A.held)
	if(allowed != TRUE)
		if(istext(allowed))
			to_chat(A.actor, span_warning(allowed))
		return
	var/mob/user = A.actor
	var/atom/movable/dropped = A.held
	var/mob/target = dropped
	var/mob/living/carbon/WC = get_occupant()
	if(!ismob(target) || user.stat || user.lying || !Adjacent(user) || !target.Adjacent(user)|| !ishuman(target) || WC)
		return OP_DECLINE
	// Traitgenes Do not allow buckled or ridden mobs
	if(target.buckled_to())
		return OP_DECLINE
	put_in(target)
	return TRUE

/// Requirement for the drag-in: TRUE, or why the dragged mob can't go in.
/obj/machinery/dna_scannernew/proc/can_drag_inside(mob/user, atom/target, atom/movable/dropped)
	var/mob/M = dropped
	if(!ishuman(M) || get_occupant() || M.buckled_to())
		return TRUE // the effect declines these silently
	if(M.has_buckled_mobs())
		return "[M] has other entities attached to it, remove them first"
	return TRUE

/// Requirement for climbing in: TRUE, or why the user can't.
/obj/machinery/dna_scannernew/proc/can_move_inside(mob/user, atom/target, obj/item/held)
	if(user.stat != CONSCIOUS)
		return TRUE // the effect declines silently
	if(!ishuman(user) && !issmall(user)) //Make sure they're a mob that has dna
		return "try as you might, you can not climb up into the scanner"
	if(get_occupant())
		return "the scanner is already occupied"
	if(user.abiotic())
		return "the subject cannot have abiotic items on"
	return TRUE

/obj/machinery/dna_scannernew/proc/dna_scannernew_move_inside_effect(datum/act/op/A)
	// the legacy check, read when the op runs: its text is the refusal
	var/allowed = can_move_inside(A.actor, src, A.held)
	if(allowed != TRUE)
		if(istext(allowed))
			to_chat(A.actor, span_warning(allowed))
		return
	var/mob/user = A.actor
	if(user.stat != CONSCIOUS)
		return
	user.stop_pulling()
	if(!move_into(src, OCCUPANT_SLOT_DNA_SCANNER, user, user))
		to_chat(user, span_warning("\The [src] won't take you!"))
		return
	set_occupant(user)
	icon_state = "scanner_1"
	add_fingerprint(user)
	SStgui.update_uis(src)

/// Old attackby.
/obj/machinery/dna_scannernew/proc/dna_scanner_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/item = A.held
	if(istype(item, /obj/item/reagent_containers/glass))
		if(beaker)
			to_chat(user, span_warning("A beaker is already loaded into the machine."))
			return TRUE

		if(!move_into(src, nameof(src.beaker), item, user))
			return TRUE
		act_message(user, src, MSG_SELF("You add \a [item] to %T%!"), MSG_OTHERS("%U% adds \a [item] to %T%!"))
		SStgui.update_uis(src)
		return TRUE

	else if(istype(item, /obj/item/organ/internal/brain))
		if(get_occupant())
			to_chat(user, span_warning("The scanner is already occupied!"))
			return TRUE
		var/obj/item/organ/internal/brain/brain = item
		if(brain.clone_source)
			user.drop_item()
			brain.forceMove(src)
			put_in(brain.hosted_view())
			src.add_fingerprint(user)
			act_message(user, src, MSG_SELF("You add \a [item] to %T%!"), MSG_OTHERS("%U% adds \a [item] to %T%!"))
			SStgui.update_uis(src)
			return TRUE
		else
			to_chat(user, "\The [brain] is not acceptable for genetic sampling!")

		return TRUE

	else if(!istype(item, /obj/item/grab))
		return OP_DECLINE
	var/obj/item/grab/G = item
	var/mob/living/grabbed = G?.grab_target()
	if(!ismob(grabbed))
		return OP_DECLINE
	if(get_occupant())
		to_chat(user, span_warning("The scanner is already occupied!"))
		return TRUE
	if(grabbed.abiotic())
		to_chat(user, span_warning("The subject cannot have abiotic items on."))
		return TRUE
	put_in(grabbed)
	src.add_fingerprint(user)
	consume(G, user)
	return TRUE

// Traitgenes Deconstructable dna scanner
/obj/machinery/dna_scannernew/dismantle()
	// release contents
	if(beaker)
		beaker.forceMove(get_turf(src))
		rel_take(src, nameof(beaker))
	var/mob/living/carbon/WC = get_occupant()
	if(WC)
		slot_remove(WC, get_turf(src))
		set_occupant(null)
	// Disconnect from our terminal
	for(var/dirfind in GLOB.cardinal)
		var/obj/machinery/computer/scan_consolenew/console = locate(/obj/machinery/computer/scan_consolenew, get_step(src, dirfind))
		if(console && console.connected() == src)
			rel_clear(console, nameof(console.connected))
			SStgui.close_uis(console)
			break
	. = ..()

/obj/machinery/dna_scannernew/proc/put_in(mob/M)
	if(!move_into(src, OCCUPANT_SLOT_DNA_SCANNER, M))
		return
	set_occupant(M)
	icon_state = "scanner_1"

	// search for ghosts, if the corpse is empty and the scanner is connected to a cloner
	if(locate(/obj/machinery/computer/cloning, get_step(src, NORTH)) \
		|| locate(/obj/machinery/computer/cloning, get_step(src, SOUTH)) \
		|| locate(/obj/machinery/computer/cloning, get_step(src, EAST)) \
		|| locate(/obj/machinery/computer/cloning, get_step(src, WEST)))

		if(!M.client && M.mind)
			for(var/mob/observer/dead/ghost in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
				if(ghost.mind == M.mind)
					to_chat(ghost, span_interface(span_large(span_bold("Your corpse has been placed into a cloning scanner. Return to your body if you want to be resurrected/cloned!") + " (Verbs -> Ghost -> Re-enter corpse)")))
					break
	SStgui.update_uis(src)

/obj/machinery/dna_scannernew/proc/go_out()
	var/mob/living/carbon/WC = get_occupant()
	if((!WC || locked))
		return
	if(istype(WC,/mob/living/carbon/brain))
		latent_materialize_all() // a walk needs real things (C5)
		for(var/obj/O in contents_of(src)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
			if(istype(O,/obj/item/organ/internal/brain))
				O.forceMove(get_turf(src))
				slot_remove(WC, O)
				break
	else
		slot_remove(WC, loc)
	set_occupant(null)
	icon_state = "scanner_0"
	SStgui.update_uis(src)

/obj/machinery/computer/scan_consolenew
	name = "DNA Modifier Access Console"
	desc = "Scan DNA."
	icon_keyboard = "med_key"
	icon_screen = "dna"
	density = TRUE
	circuit = /obj/item/circuitboard/scan_consolenew
	var/selected_ui_block = 1.0
	var/selected_ui_subblock = 1.0
	var/selected_se_block = 1.0
	var/selected_se_subblock = 1.0
	var/selected_ui_target = 1
	var/selected_ui_target_hex = 1
	var/radiation_duration = 2.0
	var/radiation_intensity = 1.0
	// ALLOW(instance_list): d: fixed three buffer slots (list/x[3]) indexed by slot number
	var/list/datum/transhuman/body_record/buffers[3] // Traitgenes Use bodyrecords
	var/irradiating = 0
	var/injector_ready = 0	//Quick fix for issue 286 (screwdriver the screen twice to restore injector)	-Pete
	var/obj/machinery/dna_scannernew/connected
	// Traitgenes body record disks are used instead of a unique disk
	var/obj/item/disk/body_record/disk = null
	var/selected_menu_key = PAGE_SE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 400

/// Old attackby.
TRACKED(/obj/machinery/computer/scan_consolenew, irradiating)
TRACKED(/obj/machinery/computer/scan_consolenew, injector_ready)

MSG_DEF_SELF(dna_console/no_scanner, "The console has no DNA modifier connected.")
MSG_DEF_SELF(dna_console/busy, "The console is busy irradiating its subject.")
MSG_DEF_SELF(dna_console/occupant, "You can't reach the console from inside the scanner.")
MSG_DEF_SELF(dna_console/not_standing, "You need to stand at the console.")

// The window (DNAModifier): its buttons are ops under their old action names, and the two questions a button asks (a buffer's label, the block
// of a block injector) are asks() steps of the bufferOption op, shown as the window's modal. Every button wants the scanner connected, the
// console not irradiating and the user standing on a tile; opening it wants a connected scanner and a user outside it.
CAPABILITIES(/obj/machinery/computer/scan_consolenew)
	after_init(25 SECONDS, then(PROC_REF(injector_cooldown_finish)))
	owns_many(nameof(buffers), /datum/transhuman/body_record)
	ref_one(nameof(connected), /obj/machinery/dna_scannernew)
	interface("DNAModifier")
	extend("ui_open", needs(req_bool(PROC_REF(scanner_connected), because = MSG(dna_console/no_scanner)), req_bool(PROC_REF(not_the_occupant), because = MSG(dna_console/occupant))))
	extend(TAG_UI, needs(req_bool(PROC_REF(scanner_connected), because = MSG(dna_console/no_scanner)), req_bool(PROC_REF(not_irradiating), because = MSG(dna_console/busy))))
	extend(TAG_UI, then(PROC_REF(window_touched), early = TRUE))
	op("selectMenuKey", ui_act("selectMenuKey", arg("key", schema_text(32))), needs(req_bool(PROC_REF(user_standing), because = MSG(dna_console/not_standing))), then(PROC_REF(ui_act_selectmenukey)))
	op("toggleLock", ui_act("toggleLock"), needs(req_bool(PROC_REF(user_standing), because = MSG(dna_console/not_standing))), then(PROC_REF(ui_act_togglelock)))
	op("pulseRadiation", ui_act("pulseRadiation"), needs(req_bool(PROC_REF(user_standing), because = MSG(dna_console/not_standing))), then(PROC_REF(ui_act_pulseradiation)))
	op("radiationDuration", ui_act("radiationDuration", arg("value", num(1, 20))), needs(req_bool(PROC_REF(user_standing), because = MSG(dna_console/not_standing))), then(PROC_REF(ui_act_radiationduration)))
	op("radiationIntensity", ui_act("radiationIntensity", arg("value", num(1, 10))), needs(req_bool(PROC_REF(user_standing), because = MSG(dna_console/not_standing))), then(PROC_REF(ui_act_radiationintensity)))
	op("injectRejuvenators", ui_act("injectRejuvenators", arg("amount", num())), needs(req_bool(PROC_REF(user_standing), because = MSG(dna_console/not_standing))), then(PROC_REF(ui_act_injectrejuvenators)))
	op("selectSEBlock", ui_act("selectSEBlock", arg("block", num()), arg("subblock", num())), needs(req_bool(PROC_REF(user_standing), because = MSG(dna_console/not_standing))), then(PROC_REF(ui_act_selectseblock)))
	op("pulseSERadiation", ui_act("pulseSERadiation"), needs(req_bool(PROC_REF(user_standing), because = MSG(dna_console/not_standing))), then(PROC_REF(ui_act_pulseseradiation)))
	op("ejectBeaker", ui_act("ejectBeaker"), needs(req_bool(PROC_REF(user_standing), because = MSG(dna_console/not_standing))), then(PROC_REF(ui_act_ejectbeaker)))
	op("ejectOccupant", ui_act("ejectOccupant"), needs(req_bool(PROC_REF(user_standing), because = MSG(dna_console/not_standing))), then(PROC_REF(ui_act_ejectoccupant)))
	op("bufferOption", ui_act("bufferOption", arg("block", num(default = 0)), arg("id", num()), arg("option", schema_text(32))), needs(req_bool(PROC_REF(user_standing), because = MSG(dna_console/not_standing))),
		asks(/datum/prompt/text, fields = list("question" = "Please enter the new buffer label:", "default" = computed(PROC_REF(buffer_label_default)), "max_len" = TGUI_MODAL_INPUT_MAX_LENGTH_NAME, "modal_id" = "changeBufferLabel", "inline" = TRUE, "timeout" = 0), step = "label", when = PROC_REF(asks_buffer_label)),
		asks(/datum/prompt/choice, fields = list("question" = "Please select the block to create an injector from:", "choices" = computed(PROC_REF(buffer_block_choices)), "modal_id" = "createInjectorBlock", "inline" = TRUE, "timeout" = 0), step = "block", when = PROC_REF(asks_injector_block)),
		then(PROC_REF(ui_act_bufferoption)))
	op("wipeDisk", ui_act("wipeDisk"), needs(req_bool(PROC_REF(user_standing), because = MSG(dna_console/not_standing))), then(PROC_REF(ui_act_wipedisk)))
	op("ejectDisk", ui_act("ejectDisk"), needs(req_bool(PROC_REF(user_standing), because = MSG(dna_console/not_standing))), then(PROC_REF(ui_act_ejectdisk)))
	op("dna_console_interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT + 1), label("Use"), then(PROC_REF(dna_console_interaction_item)))

/obj/machinery/computer/scan_consolenew/proc/dna_console_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	// Traitgenes body record disks are used instead of a unique disk
	if(!istype(I, /obj/item/disk/body_record)) //INSERT SOME diskS
		return OP_DECLINE
	if(connected())
		if(!disk)
			if(!move_into(src, nameof(src.disk), I, user))
				return OP_DECLINE
			to_chat(user, "You insert [I].")
	else
		to_chat(user, "\The [src] will not accept a disk without a DNA modifier connected.")
	return OP_OK

/obj/machinery/computer/scan_consolenew/Initialize(mapload)
	. = ..()
	for(var/i=0;i<3;i++)
		// Traitgenes Use bodyrecords
		var/datum/transhuman/body_record/R = new /datum/transhuman/body_record()
		rel_set(R, nameof(R.mydna), new /datum/dna2/record)
		R.mydna.dna = new
		R.mydna.dna.ResetUI()
		R.mydna.dna.ResetSE()
		rel_add(src, nameof(buffers), R, i+1)
	// Traitgenes don't alter direction of computer as this scans for neighbour
	for(var/dirfind in GLOB.cardinal)
		rel_set(src, nameof(connected), locate(/obj/machinery/dna_scannernew, get_step(src, dirfind)))
		if(connected())
			break

/obj/machinery/computer/scan_consolenew/proc/all_dna_blocks(list/buffer)
	var/list/arr = list()
	for(var/i = 1, i <= buffer.len, i++)
		arr += "[i]:[EncodeDNABlock(buffer[i])]"
	return arr

/obj/machinery/computer/scan_consolenew/proc/setInjectorBlock(obj/item/dnainjector/I, blk, datum/transhuman/body_record/buffer) // Traitgenes Stores the entire body record
	var/pos = findtext(blk,":")
	if(!pos) return 0
	var/id = text2num(copytext(blk,1,pos))
	if(!id) return 0
	I.block = id
	rel_set(I, nameof(I.buf), buffer)
	return 1

/obj/machinery/computer/scan_consolenew
	silicon_use = SILICON_USE_UI

// ---- the window's requirements ----

/// The scanner beside the console is still there.
/obj/machinery/computer/scan_consolenew/proc/scanner_connected(datum/act/A)
	return !!connected()

/// The one opening the window is not lying in the scanner.
/obj/machinery/computer/scan_consolenew/proc/not_the_occupant(datum/act/op/A)
	return A.actor != connected()?.get_occupant()

/// The console is not in the middle of a pulse (buttons wait until it is done).
/obj/machinery/computer/scan_consolenew/proc/not_irradiating(datum/act/A)
	return !irradiating

/// The user works the console from a tile (not from inside a locker, a mech or the scanner); a silicon works it over its link.
/obj/machinery/computer/scan_consolenew/proc/user_standing(datum/act/op/A)
	return isturf(A.actor?.loc) || (A.authority & AUTH_REMOTE_ACCESS) // ALLOW(reads): where the user stands is read when the button is pressed; a menu shows no buttons of a window

/// Every button leaves a print.
/obj/machinery/computer/scan_consolenew/proc/window_touched(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK

/// The bufferOption asks for a label (changeLabel).
/obj/machinery/computer/scan_consolenew/proc/asks_buffer_label(datum/act/op/A)
	return A.args["option"] == "changeLabel" && !isnull(buffer_of(A))

/// The bufferOption asks for an injector's block (createInjector with a block, while the injector is ready).
/obj/machinery/computer/scan_consolenew/proc/asks_injector_block(datum/act/op/A)
	return A.args["option"] == "createInjector" && injector_ready && A.args["block"] > 0 && !isnull(buffer_of(A))

/// The buffer a bufferOption names, or null for an id out of range.
/obj/machinery/computer/scan_consolenew/proc/buffer_of(datum/act/op/A)
	var/id = A.args["id"]
	if(!isnum(id) || id < 1 || id > length(buffers))
		return null
	return buffers[id]

/obj/machinery/computer/scan_consolenew/proc/buffer_label_default(datum/act/op/A)
	var/datum/transhuman/body_record/buffer = buffer_of(A)
	return buffer?.mydna?.name

/obj/machinery/computer/scan_consolenew/proc/buffer_block_choices(datum/act/op/A)
	var/datum/transhuman/body_record/buffer = buffer_of(A)
	return buffer ? all_dna_blocks(buffer.mydna.dna.SE) : list()

/// The window's data.
/obj/machinery/computer/scan_consolenew/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["selectedMenuKey"] = selected_menu_key
	data["isInjectorReady"] = injector_ready
	data["radiationIntensity"] = radiation_intensity
	data["radiationDuration"] = radiation_duration
	data["irradiating"] = irradiating
	data["selectedUIBlock"] = selected_ui_block
	data["selectedUISubBlock"] = selected_ui_subblock
	data["selectedSEBlock"] = selected_se_block
	data["selectedSESubBlock"] = selected_se_subblock
	data["selectedUITarget"] = selected_ui_target
	data["selectedUITargetHex"] = selected_ui_target_hex
	if(!connected())
		return data
	data["locked"] = src.connected().locked
	data["hasOccupant"] = connected().get_occupant() ? 1 : 0

	data["hasDisk"] = disk ? 1 : 0

	var/list/diskData = list()
	if(!disk || !disk.stored || !disk.stored.mydna) // Traitgenesbody record disks are used instead of a unique disk
		diskData["data"] = null
		diskData["owner"] = null
		diskData["label"] = null
		diskData["type"] = null
		diskData["ue"] = null
	else
		diskData = disk.stored.mydna.GetData() // Traitgenes body record disks are used instead of a unique disk
	data["disk"] = diskData

	// Traitgenes Fixed buffer menu
	var/list/new_buffers[src.buffers.len]
	for(var/i=1;i<=src.buffers.len;i++)
		var/datum/transhuman/body_record/R = buffers[i]
		if(R && R.mydna)
			new_buffers[i]=R.mydna.GetData()
		else
			new_buffers[i]=list("data" = list(), "owner" = null, "label" = null, "type" = DNA2_BUF_SE, "ue" = 0)
	data["buffers"]=new_buffers

	data["dnaBlockSize"] = DNA_BLOCK_SIZE

	var/list/occupantData = list()
	var/mob/living/carbon/WC = connected()?.get_occupant()
	if(!WC || !WC.dna)
		occupantData["name"] = null
		occupantData["stat"] = null
		occupantData["isViableSubject"] = null
		occupantData["health"] = null
		occupantData["maxHealth"] = null
		occupantData["minHealth"] = null
		occupantData["uniqueEnzymes"] = null
		occupantData["uniqueIdentity"] = null
		occupantData["structuralEnzymes"] = null
		occupantData["radiationLevel"] = null
	else
		occupantData["name"] = WC.real_name
		occupantData["stat"] = WC.stat
		occupantData["isViableSubject"] = 1
		// Traitgenes NO_DNA and Synthetics cannot be mutated
		var/allowed = TRUE
		if(HAS_SYNTHETIC_BIOLOGY(WC))
			allowed = FALSE
		if(ishuman(WC))
			var/mob/living/carbon/human/H = WC
			if(!H.species || (H.species.flags & NO_DNA))
				allowed = FALSE
		if(!allowed || (WC.has_mutation(NOCLONE)) || !WC.dna)
			occupantData["isViableSubject"] = 0
		// Vitality is reported as a 0..100 percentage; the UI bar reads health / maxHealth.
		occupantData["health"] = round(WC.vitality() * 100)
		occupantData["maxHealth"] = 100
		occupantData["minHealth"] = 0
		occupantData["uniqueEnzymes"] = WC.dna.unique_enzymes
		occupantData["uniqueIdentity"] = WC.dna.GetUniIdentity()
		occupantData["structuralEnzymes"] = WC.dna.GetStrucEnzymes()
		occupantData["radiationLevel"] = WC.radiation
	data["occupant"] = occupantData;

	data["isBeakerLoaded"] = connected().beaker ? 1 : 0
	data["beakerLabel"] = null
	data["beakerVolume"] = 0
	if(connected().beaker)
		data["beakerLabel"] = connected().beaker.label_text ? connected().beaker.label_text : null
		if(connected().beaker.reagents && connected().beaker.reagents.reagent_list.len)
			for(var/datum/reagent/R in connected().beaker.reagents.reagent_list)
				data["beakerVolume"] += R.volume

	// Transfer modal information if there is one
	data["modal"] = tgui_modal_data(src)

	return data

/obj/machinery/computer/scan_consolenew/proc/ui_act_selectmenukey(datum/act/op/A, key)
	play_sfx(src, SFX_MACHINES_BUTTON)
	if(!(key in list(/*PAGE_UI,*/ PAGE_SE, PAGE_BUFFER, PAGE_REJUVENATORS))) // Traitgenes Body design console is used to edit UIs now
		return TRUE
	selected_menu_key = key
	return TRUE

/obj/machinery/computer/scan_consolenew/proc/ui_act_togglelock(datum/act/op/A)
	play_sfx(src, SFX_MACHINES_BUTTON)
	if(connected() && connected().get_occupant())
		connected().set_locked(!(connected().locked))
	return TRUE

/obj/machinery/computer/scan_consolenew/proc/ui_act_pulseradiation(datum/act/op/A)
	play_sfx(src, SFX_MACHINES_BUTTON)
	set_irradiating(radiation_duration)
	var/lock_state = connected().locked
	connected().set_locked(TRUE) //lock it
	after(src, radiation_duration SECONDS, PROC_REF(do_pulse), with = list(lock_state))
	return TRUE

/obj/machinery/computer/scan_consolenew/proc/ui_act_radiationduration(datum/act/op/A, value)
	radiation_duration = value
	return TRUE

/obj/machinery/computer/scan_consolenew/proc/ui_act_radiationintensity(datum/act/op/A, value)
	radiation_intensity = value
	return TRUE

/obj/machinery/computer/scan_consolenew/proc/ui_act_injectrejuvenators(datum/act/op/A, amount)
	play_sfx(src, SFX_MACHINES_BUTTON)
	if(!connected().get_occupant() || !connected().beaker)
		return TRUE
	var/mob/living/carbon/WC = connected()?.get_occupant()
	var/inject_amount = clamp(round(amount, 5), 0, 50) // round to nearest 5 and clamp to 0-50
	if(!inject_amount)
		return TRUE
	connected().beaker.reagents.trans_to_mob(WC, inject_amount, CHEM_BLOOD)
	return TRUE
	////////////////////////////////////////////////////////

/obj/machinery/computer/scan_consolenew/proc/ui_act_selectseblock(datum/act/op/A, block, subblock)
	play_sfx(src, SFX_KEYBOARD)
	var/select_block = block
	var/select_subblock = subblock
	if(!select_block || !select_subblock)
		return TRUE

	selected_se_block = clamp(select_block, 1, DNA_SE_LENGTH)
	selected_se_subblock = clamp(select_subblock, 1, DNA_BLOCK_SIZE)
	return TRUE

/obj/machinery/computer/scan_consolenew/proc/ui_act_pulseseradiation(datum/act/op/A)
	if(!connected()?.get_occupant())
		return TRUE
	var/mob/living/carbon/WC = connected()?.get_occupant()
	play_sfx(src, SFX_KEYBOARD)
	var/block = WC.dna.GetSESubBlock(selected_se_block,selected_se_subblock)

	set_irradiating(radiation_duration)
	var/lock_state = connected().locked
	connected().set_locked(TRUE) //lock it

	//We call the do_irradiate proc here after radation_duration SECONDS
	after(src, radiation_duration SECONDS, PROC_REF(do_irradiate), with = list(lock_state, block))
	return TRUE

/obj/machinery/computer/scan_consolenew/proc/ui_act_ejectbeaker(datum/act/op/A)
	play_sfx(src, SFX_MACHINES_BUTTON)
	if(connected().beaker)
		var/obj/item/reagent_containers/glass/B = connected().beaker
		B.forceMove(connected().loc)
		connected().beaker = null
	return TRUE

/obj/machinery/computer/scan_consolenew/proc/ui_act_ejectoccupant(datum/act/op/A)
	play_sfx(src, SFX_MACHINES_BUTTON)
	connected().eject_occupant()
	// Eject disk too, because we can't get to the UI otherwise
	if(!disk)
		return TRUE
	disk.forceMove(get_turf(src))
	rel_take(src, nameof(/obj/machinery/computer/scan_consolenew::disk))
// Transfer Buffer Management

/obj/machinery/computer/scan_consolenew/proc/ui_act_bufferoption(datum/act/op/A, block, id, option)
	var/bufferOption = option
	var/bufferId = id
	if(bufferId < 1 || bufferId > 3) // Not a valid buffer id
		return TRUE

	var/datum/transhuman/body_record/buffer = buffers[bufferId] // Traitgenes Use bodyrecords
	switch(bufferOption)
		// Traitgenes Moved SE and UI saves to storing the entire body record
		if("saveDNA")
			play_sfx(src, SFX_KEYBOARD) // into console
			var/mob/living/carbon/WC = connected()?.get_occupant()
			if(WC && WC.dna)
				// Traitgenes Properly clone records
				var/datum/transhuman/body_record/databuf = new /datum/transhuman/body_record()
				databuf.init_from_mob(WC)
				databuf.mydna.types = DNA2_BUF_SE // structurals only
				if(ishuman(WC))
					var/mob/living/carbon/human/H = WC
					databuf.mydna.dna.real_name = H.dna.real_name
					databuf.mydna.gender = H.gender
				rel_add(src, nameof(/obj/machinery/computer/scan_consolenew::buffers), databuf, bufferId)
			return TRUE
		if("clear")
			play_sfx(src, SFX_KEYBOARD)
			// Traitgenes Storing the entire body record
			var/datum/transhuman/body_record/R = new /datum/transhuman/body_record()
			rel_set(R, nameof(/datum/transhuman/body_record::mydna), new /datum/dna2/record)
			R.mydna.dna = new
			R.mydna.dna.ResetUI()
			R.mydna.dna.ResetSE()
			rel_add(src, nameof(/obj/machinery/computer/scan_consolenew::buffers), R, bufferId)
			return TRUE
		if("changeLabel")
			play_sfx(src, SFX_KEYBOARD)
			var/label = A.step_value("label")
			if(!isnull(label))
				buffer.mydna.name = label // Traitgenes Use bodyrecords
			return TRUE
		if("transfer")
			var/mob/living/carbon/WC = connected()?.get_occupant()
			if(!WC || (WC.has_mutation(NOCLONE)) || !WC.dna)
				return TRUE
			set_irradiating(2)
			var/lock_state = connected().locked
			connected().set_locked(1)//lock it
			after(src, 2 SECONDS, PROC_REF(do_transfer), with = list(lock_state, bufferId))
			return TRUE
		if("createInjector")
			if(!injector_ready)
				return TRUE
			if(block > 0)
				var/picked = A.step_value("block")
				if(isnull(picked))
					return TRUE
				var/obj/item/dnainjector/I = create_injector(bufferId)
				setInjectorBlock(I, picked, buffer.mydna.copy()) // Traitgenes Use bodyrecords
				I.name += " - Block [picked]" // Traitgenes By default show the block of a block injector
			else
				create_injector(bufferId, TRUE)
			return TRUE
		// Traitgenes Storing the entire body record
		if("loadDisk")
			play_sfx(src, SFX_KEYBOARD)
			if(isnull(disk) || !disk.stored)
				return
			// Traitgenes Properly clone records
			var/datum/transhuman/body_record/databuf = new /datum/transhuman/body_record()
			databuf.init_from_br(disk.stored)
			databuf.mydna.types = DNA2_BUF_SE // structurals only
			rel_add(src, nameof(/obj/machinery/computer/scan_consolenew::buffers), databuf, bufferId)
		if("saveDisk")
			play_sfx(src, SFX_KEYBOARD)
			if(isnull(disk)) // Traitgenes Removed readonly
				return TRUE
			var/datum/transhuman/body_record/buf = buffers[bufferId]
			// Traitgenes Properly clone records
			rel_set(disk, nameof(disk.stored), new /datum/transhuman/body_record())
			disk.stored.init_from_br(buf)
			disk.stored.mydna.types = DNA2_BUF_UI|DNA2_BUF_UE|DNA2_BUF_SE // DNA disks need to maintain their data
			disk.name = "Body Design Disk ('[buf.mydna.name]')"
			return TRUE
		if("sleeveDisk")
			play_sfx(src, SFX_KEYBOARD)
			var/datum/transhuman/body_record/buf = buffers[bufferId]
			// Send printable record to first sleevepod in area
			print_sleeve(A.actor, buf)
			return TRUE

/obj/machinery/computer/scan_consolenew/proc/ui_act_wipedisk(datum/act/op/A)
	play_sfx(src, SFX_KEYBOARD)
	// Traitgenes Storing the entire body record
	if(isnull(disk))
		return TRUE
	own_clear(disk, nameof(disk.stored), OWN_DELETE)
	return TRUE

/obj/machinery/computer/scan_consolenew/proc/ui_act_ejectdisk(datum/act/op/A)
	play_sfx(src, SFX_MACHINES_BUTTON)
	if(!disk)
		return TRUE
	disk.forceMove(get_turf(src))
	rel_take(src, nameof(/obj/machinery/computer/scan_consolenew::disk))
	return TRUE

/**
 * Creates a blank injector with the name of the buffer at the given buffer_id
 *
 * Arguments:
 * * buffer_id - The ID of the buffer
 * * copy_buffer - Whether the injector should copy the buffer contents
 */
/obj/machinery/computer/scan_consolenew/proc/create_injector(buffer_id, copy_buffer = FALSE)
	if(buffer_id < 1 || buffer_id > length(buffers))
		return

	// Cooldown
	set_injector_ready(FALSE)
	after(src, 5 SECONDS, PROC_REF(injector_cooldown_finish))

	// Create it
	var/datum/transhuman/body_record/buf = buffers[buffer_id] // Traitgenes Use bodyrecords
	var/obj/item/dnainjector/I = new()
	buf.mydna.types = DNA2_BUF_SE // Traitgenes SE only, use the designer for UI and UEs, super broken in this codebase due to years of no one respecting genetics...
	I.forceMove(loc)
	I.name += " ([buf.mydna.name])"
	if(copy_buffer)
		rel_set(I, nameof(I.buf), buf.mydna.copy())
	return I

/**
 * Called when the injector creation cooldown finishes
 */
/obj/machinery/computer/scan_consolenew/proc/injector_cooldown_finish(datum/act/A)
	set_injector_ready(TRUE)

/**
 * Triggers sleeve growing in a clonepod within the area
 *
 * Arguments:
 * * active_br - Body record to print
 */
/obj/machinery/computer/scan_consolenew/proc/print_sleeve(mob/user, datum/transhuman/body_record/active_br)
	//deleted record
	if(!istype(active_br))
		to_chat(user, span_danger( "Error: Data corruption."))
		return
	//Trying to make an fbp
	if(active_br.synthetic )
		to_chat(user, span_danger( "Error: Cannot grow synthetic."))
		return
	//No pods
	var/obj/machinery/clonepod/pod = locate_within(get_area(src), /obj/machinery/clonepod)
	if(!pod)
		to_chat(user, span_danger( "Error: No growpods detected."))
		return
	//Already doing someone.
	if(pod.get_occupant())
		to_chat(user, span_danger( "Error: Growpod is currently occupied."))
		return
	//Not enough materials.
	if(pod.get_biomass() < CLONE_BIOMASS)
		to_chat(user, span_danger( "Error: Not enough biomass."))
		return
	//Gross pod (broke mid-cloning or something).
	if(pod.mess)
		to_chat(user, span_danger( "Error: Growpod malfunction."))
		return
	//Disabled in config.
	if(!CONFIG_GET(flag/revival_cloning))
		to_chat(user, span_danger( "Error: Unable to initiate growing cycle."))
		return
	//Invalid genes!
	if(active_br.mydna.name == "Empty" || active_br.mydna.id == null)
		to_chat(user, span_danger( "Error: Data corruption."))
		return
	//Do the cloning!
	if(!pod.growclone(active_br))
		to_chat(user, span_danger( "Initiating growing cycle... Error: Post-initialisation failed. Growing cycle aborted."))
		return
	to_chat(user, span_notice( "Initiating growing cycle..."))

/obj/machinery/computer/scan_consolenew/proc/do_irradiate(lock_state, block)
	var/mob/living/carbon/WC = connected()?.get_occupant()
	set_irradiating(0)
	connected().set_locked(lock_state)
	if(!WC)
		return

	if(prob((80 + (radiation_duration / 2))))
		// FIXME: Find out what these corresponded to and change them to the WHATEVERBLOCK they need to be.
		//if((selected_se_block != 2 || selected_se_block != 12 || selected_se_block != 8 || selected_se_block || 10) && prob (20))
		var/real_SE_block=selected_se_block
		block = miniscramble(block, radiation_intensity, radiation_duration)
		if(prob(20))
			if(selected_se_block > 1 && selected_se_block < DNA_SE_LENGTH/2)
				real_SE_block++
			else if(selected_se_block > DNA_SE_LENGTH/2 && selected_se_block < DNA_SE_LENGTH)
				real_SE_block--

		WC.dna.SetSESubBlock(real_SE_block,selected_se_subblock,block)
		WC.apply_effect((radiation_intensity+radiation_duration), IRRADIATE, check_protection = 0)
	else
		WC.apply_effect(((radiation_intensity*2)+radiation_duration), IRRADIATE, check_protection = 0)
		if	(prob(80-radiation_duration))
			randmutb(WC)
			domutcheck(WC,null,MUTCHK_FORCED)
			WC.UpdateAppearance()
	// Traitgenes Do gene updates here, and more comprehensively
	if(ishuman(WC))
		var/mob/living/carbon/human/H = WC
		H.sync_dna_traits(FALSE,TRUE)
		H.sync_organ_dna()
	WC.regenerate_icons()

/obj/machinery/computer/scan_consolenew/proc/do_pulse(lock_state)
	var/mob/living/carbon/WC = connected()?.get_occupant()
	set_irradiating(0)
	connected().set_locked(lock_state)

	if(!WC)
		return
	// Traitgenes Make the fullbody irritation more risky
	if(prob((radiation_intensity*2) + (radiation_duration*2)))
		if(prob(95))
			if(prob(75))
				randmutb(WC)
		else
			if(prob(95))
				randmutg(WC)
		domutcheck(WC,null,MUTCHK_FORCED)
		WC.UpdateAppearance()
	// Traitgenes Do gene updates here, and more comprehensively
	if(ishuman(WC))
		var/mob/living/carbon/human/H = WC
		H.sync_dna_traits(FALSE,FALSE)
		H.sync_organ_dna()
	WC.regenerate_icons()

	WC.apply_effect(((radiation_intensity*3)+radiation_duration*3), IRRADIATE, check_protection = 0)

/obj/machinery/computer/scan_consolenew/proc/do_transfer(lock_state, bufferId)
	set_irradiating(0)
	connected().set_locked(lock_state)

	play_sfx(src, SFX_KEYBOARD)

	var/mob/living/carbon/WC = connected()?.get_occupant()
	if(!WC)
		return TRUE
	var/datum/transhuman/body_record/buf = buffers[bufferId] // Traitgenes- Use bodyrecords
	if(buf.mydna.types & DNA2_BUF_SE)
		// Apply SEs only to the current occupant!
		WC.dna.SE = buf.mydna.dna.SE.Copy()
		WC.dna.UpdateSE()
		domutcheck(WC,connected(), MUTCHK_FORCED | MUTCHK_HIDEMSG) // TOO MANY MUTATIONS FOR MESSAGES
		WC.UpdateAppearance()
		to_chat(WC, span_warning("Your body stings as it wildly changes!"))

		// apply genes
		if(ishuman(WC))
			var/mob/living/carbon/human/H = WC
			H.sync_organ_dna()

	WC.apply_effect(rand(20,50), IRRADIATE, check_protection = 0)

#undef DNA_BLOCK_SIZE

#undef PAGE_SE
#undef PAGE_BUFFER
#undef PAGE_REJUVENATORS

/////////////////////////// DNA MACHINES

/obj/machinery/dna_scannernew/ownership()
	. = ..()
	. += owns(nameof(beaker), policy = OWN_CONTAINED)
/obj/machinery/computer/scan_consolenew/ownership()
	. = ..()
	. += owns(nameof(disk), policy = OWN_CONTAINED)

/// connected: a relation view, null once the scanner is deleted.
/obj/machinery/computer/scan_consolenew/proc/connected() as /obj/machinery/dna_scannernew
	return connected
