/obj/machinery/power/quantumpad
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "quantum pad"
	desc = "A bluespace quantum-linked telepad used for teleporting objects to other quantum pads."
	icon = 'icons/obj/telescience.dmi'
	icon_state = "qpad"
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 200
	active_power_usage = 5000
	circuit = /obj/item/circuitboard/quantumpad
	var/teleport_cooldown = 400 //30 seconds base due to base parts
	var/teleport_speed = 50
	COOLDOWN_DECLARE(teleport_cooldown_until) //to handle the cooldown
	var/teleporting = 0 //if it's in the process of teleporting
	var/power_efficiency = 1
	var/boosted = 0 // do we teleport mecha?
	var/tmp/obj/machinery/power/quantumpad/linked_pad

	//mapping: a pad whose map_pad_link_id names another pad's map_pad_id links to it (REL_KEYED below)
	var/map_pad_id = null as text //what's my name
	var/map_pad_link_id = null as text //who's my friend

// Mapped links: linked_pad auto-links to the pad whose map_pad_id equals our map_pad_link_id,
// whichever of the two materializes first (replaces the static id map).
/obj/machinery/power/quantumpad/examine(mob/user)
	. = ..()
	. += span_notice("It is [linked_pad() ? "currently" : "not"] linked to another pad.")
	if(!COOLDOWN_FINISHED(src, teleport_cooldown_until))
		. += span_warning("[src] is recharging power. A timer on the side reads <b>[round(COOLDOWN_TIMELEFT(src, teleport_cooldown_until)/10)]</b> seconds.")
	if(boosted)
		. += span_notice("There appears to be a booster haphazardly jammed into the side of [src]. That looks unsafe.")
	if(!panel_open)
		. += span_notice("The panel is <i>screwed</i> in, obstructing the linking device.")
	else
		. += span_notice("The <i>linking</i> device is now able to be <i>scanned</i> with a multitool.")

/obj/machinery/power/quantumpad/RefreshParts()
	var/E = get_part_rating(/obj/item/stock_parts/manipulator)
	power_efficiency = E

	E = get_part_rating(/obj/item/stock_parts/capacitor)

	teleport_speed = initial(teleport_speed)
	teleport_speed = max(15, (teleport_speed - (E * 10)))
	teleport_cooldown = initial(teleport_cooldown)
	teleport_cooldown = max(50, (teleport_cooldown - (E * 100)))


/obj/machinery/power/quantumpad/proc/interaction_boost(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/quantum_pad_booster/booster = A.held
	act_message(src, user, others = "%T% violently jams [booster] into the side of %U%. \The [src] beeps, quietly.", \
	blind = "You hear the sound of a device being improperly installed in sensitive machinery, then subsequent beeping.", runemessage = "beep!")
	play_sfx(src, SFX_ITEMS_RPED)
	boosted = TRUE
	consume(booster, user)
	return OP_OK

CAPABILITIES(/obj/machinery/power/quantumpad)
	ref_one(nameof(linked_pad), /obj/machinery/power/quantumpad, by = nameof(map_pad_link_id), target_key = nameof(map_pad_id))
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(multitool_used)))
	op("quantumpad_ghost_travel", observer(), priority(OP_PRIORITY_DEFAULT - 1), label("Travel"), then(PROC_REF(quantumpad_ghost_travel)))
	op("quantumpad_boost", item(/obj/item/quantum_pad_booster), priority(OP_PRIORITY_DEFAULT - 1), label("Install booster"), then(PROC_REF(interaction_boost)))
	op("part_replacement", item(/obj/item/storage/part_replacer), priority(OP_PRIORITY_DEFAULT - 2), label("Replace parts"), then(TYPE_PROC_REF(/obj/machinery, op_part_replacement)))
	op("quantumpad_use", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req_bool(PROC_REF(panel_closed_holds), because = MSG(quantumpad/panel_open))), then(PROC_REF(interaction_use)))
	extend("machine_panel", then(PROC_REF(panel_worked)))
	extend("machine_panel_close", then(PROC_REF(panel_worked)))
	default_parts()

/obj/machinery/power/quantumpad/proc/multitool_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(istype(get_area(src), /area/shuttle))
		to_chat(user, span_warning("This is too unstable a platform for \the [src] to operate on!"))
		return OP_OK
	var/obj/item/multitool/multitool = tool
	if(panel_open)
		rel_set(multitool, nameof(multitool.connectable), src)
		to_chat(user, span_notice("You save the data in [tool]'s buffer."))
		return OP_OK
	if(!istype(multitool.connectable(), /obj/machinery/power/quantumpad))
		return OP_OK
	rel_set(src, nameof(linked_pad), multitool.connectable())
	to_chat(user, span_notice("You link [src] to the one in [tool]'s buffer."))
	return OP_OK

/obj/machinery/power/quantumpad/draw(datum/look/look)
	..()

	if(panel_open)
		look.overlay("qpad-panel")

	if(!operable() || panel_open || !power_region)
		look.state("[initial(icon_state)]-o")
	else if (!linked_pad())
		look.state("[initial(icon_state)]-b")
	else
		look.state(initial(icon_state))

// Panel flips retry power cable connections so you don't have to decon the whole thing.

MSG_DEF_SELF(quantumpad/panel_open, "the panel must be closed before operating this machine")

/// Requirement: the panel is closed.
/obj/machinery/power/quantumpad/proc/panel_closed_holds(datum/act/op/A)
	return !panel_open

/// Old attack_hand: standard gated pattern (`. = ..(); if(.) return`).
/obj/machinery/power/quantumpad/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	if(istype(get_area(src), /area/shuttle))
		to_chat(user, span_warning("This is too unstable a platform for \the [src] to operate on!"))
		// ition Start
		if(linked_pad())
			rel_clear(linked_pad(), nameof(/obj/machinery/hyperpad/centre::linked_pad))
		// ition End
		return OP_OK

	if(!power_region)
		to_chat(user, span_warning("[src] is not attached to a powernet!"))
		return OP_OK

	if(!linked_pad() || QDELETED(linked_pad()))
		if(!map_pad_link_id || !initMappedLink())
			to_chat(user, span_warning("There is no linked pad!"))
			return OP_OK

	if(!COOLDOWN_FINISHED(src, teleport_cooldown_until))
		to_chat(user, span_warning("[src] is recharging power. Please wait [round(COOLDOWN_TIMELEFT(src, teleport_cooldown_until)/10)] seconds."))
		return OP_OK

	if(teleporting)
		to_chat(user, span_warning("[src] is charging up. Please wait."))
		return OP_OK

	if(linked_pad().teleporting)
		to_chat(user, span_warning("Linked pad is busy. Please wait."))
		return OP_OK

	if(!linked_pad().operable())
		to_chat(user, span_warning("Linked pad is not responding to ping."))
		return OP_OK
	src.add_fingerprint(user)
	doteleport(user)
	return OP_OK

/// Old attack_ghost: ran the ghost default first, then drifts the ghost to the linked pad.
/obj/machinery/power/quantumpad/proc/quantumpad_ghost_travel(datum/act/op/A)
	var/mob/observer/dead/ghost = A.actor
	. = OP_OK
	if(actor_use_default(/datum/input_adapter/ghost, ghost, src))
		return
	if(!linked_pad() && map_pad_link_id)
		initMappedLink()
	if(linked_pad() && !QDELETED(linked_pad()))
		ghost.forceMove(get_turf(linked_pad()))

/obj/machinery/power/quantumpad/proc/doteleport(mob/user)
	if(!linked_pad())
		return
	// ition Start
	if(istype(get_area(src), /area/shuttle))
		to_chat(user, span_warning("This is too unstable a platform for \the [src] to operate on!"))
		return
	// ition End
	play_sfx(src, SFX_WEAPONS_FLASH, 0.25)
	teleporting = 1

	after(src, teleport_speed, PROC_REF(finish_teleport), with = list(user))

/obj/machinery/power/quantumpad/proc/initMappedLink()
	. = FALSE
	// The keyed relation links mapped pads when they materialize; this only reports it.
	if(linked_pad())
		. = TRUE

/obj/machinery/power/quantumpad/proc/use_teleport_power()
	var/area/A = get_area(src)
	// Well, I guess you can do it!
	if(!A?.requires_power)
		return TRUE

	// Otherwise we'll need a powernet
	var/power_to_use = 10000 / power_efficiency
	if(boosted)
		power_to_use *= 5
	if(draw_power(power_to_use) != power_to_use)
		return FALSE
	return TRUE

/obj/machinery/power/quantumpad/proc/transport_objects(turf/destination)
	for(var/atom/movable/ROI in get_turf(src))
		if(ismecha(ROI) && !boosted)
			continue
		if(ROI.anchored && !ismecha(ROI))
			continue
		else if(isobserver(ROI) && isEye(ROI))
			continue
		do_teleport(ROI, destination, asoundin = 'sound/weapons/emitter2.ogg', asoundout = 'sound/weapons/emitter2.ogg') // Noisy

/obj/machinery/power/quantumpad/proc/can_traverse_gateway()
	return TRUE

/obj/machinery/power/quantumpad/proc/gateway_scatter(mob/user)
	var/obj/effect/landmark/dest = pick(GLOB.awaydestinations)
	if(!dest)
		to_chat(user, span_warning("Nothing happens... maybe there's no signal to the remote pad?"))
		return
	// Insufficient power
	if(!use_teleport_power())
		to_chat(user, span_warning("Power is not sufficient to complete a teleport. Teleport aborted."))
		return

	to_chat(user, span_warning("You feel yourself pulled in different directions, before ending up not far from where you started."))
	flick("qpad-beam-out", src)
	transport_objects(get_turf(dest))

/obj/item/quantum_pad_booster
	icon = 'icons/obj/device.dmi'
	name = "quantum pad particle booster"
	desc = "A deceptively simple interface for increasing the mass of objects a quantum pad is capable of teleporting, at the cost of increased power draw."
	force = 9
	sharp = TRUE
	injury_kind = INJURY_PIERCE
	item_state = "analyzer"
	icon_state = "hacktool"

/obj/machinery/power/quantumpad/proc/finish_teleport(mob/user)
	// We gone
	if(!src || QDELETED(src))
		teleporting = 0
		return
	// Broken or whatever
	if(!operable())
		to_chat(user, span_warning("[src] is nonfunctional!"))
		teleporting = 0
		return
	// Linked pad or not, we can always re-scatter people
	if(!can_traverse_gateway())
		teleporting = 0
		COOLDOWN_START(src, teleport_cooldown_until, teleport_cooldown)
		gateway_scatter(user)
		return
	// Nothing to teleport to
	if(!linked_pad() || QDELETED(linked_pad()) || !linked_pad().operable())
		to_chat(user, span_warning("Linked pad is not responding to ping. Teleport aborted."))
		teleporting = 0
		return
	// Insufficient power
	if(!use_teleport_power())
		to_chat(user, span_warning("Power is not sufficient to complete a teleport. Teleport aborted."))
		teleporting = 0
		return

	teleporting = 0
	COOLDOWN_START(src, teleport_cooldown_until, teleport_cooldown)
	/* CHOMP remove
	sparks()
	linked_pad.sparks()
	*/

	flick("qpad-beam-out", src)
	flick("qpad-beam-in", linked_pad())

	transport_objects(get_turf(linked_pad()))

/// the linked_pad this refers to (a relation view: it reads null once the target is deleted).
/obj/machinery/power/quantumpad/proc/linked_pad() as /obj/machinery/power/quantumpad
	return linked_pad

/// After the base screwdriver: the pad re-joins the power region under it.
/obj/machinery/power/quantumpad/proc/panel_worked(datum/act/op/A)
	var/original_powernet = power_region
	if(power_region)
		disconnect_from_network()
	connect_to_network()
	if(power_region != original_powernet)
		changed(src)
