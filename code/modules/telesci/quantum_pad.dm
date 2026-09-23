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
	var/last_teleport //to handle the cooldown
	var/teleporting = 0 //if it's in the process of teleporting
	var/power_efficiency = 1
	var/boosted = 0 // do we teleport mecha?
	var/obj/machinery/power/quantumpad/linked_pad

	//mapping
	var/static/list/mapped_quantum_pads = list()
	var/map_pad_id = "" as text //what's my name
	var/map_pad_link_id = "" as text //who's my friend

/obj/machinery/power/quantumpad/Initialize(mapload)
	. = ..()
	default_apply_parts()
	connect_to_network()
	if(map_pad_id)
		mapped_quantum_pads[map_pad_id] = src
	update_icon()

/obj/machinery/power/quantumpad/Destroy()
	mapped_quantum_pads -= map_pad_id
	return ..()

/obj/machinery/power/quantumpad/examine(mob/user)
	. = ..()
	. += span_notice("It is [linked_pad ? "currently" : "not"] linked to another pad.")
	if(world.time < last_teleport + teleport_cooldown)
		. += span_warning("[src] is recharging power. A timer on the side reads <b>[round((last_teleport + teleport_cooldown - world.time)/10)]</b> seconds.")
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

/obj/machinery/power/quantumpad/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/quantumpad_boost,
		/datum/interaction/machine_item/part_replacement,
		/datum/interaction/machine_hand/quantumpad_use,
	)
	..()

/// Old attackby: install a particle booster.
/datum/interaction/machine_item/quantumpad_boost
	id = "quantumpad_boost"
	name = "Install booster"
	category = INTERACTION_CAT_INSERT
	held_type = /obj/item/quantum_pad_booster
	effect = /obj/machinery/power/quantumpad/proc/interaction_boost

/obj/machinery/power/quantumpad/proc/interaction_boost(mob/user, obj/item/quantum_pad_booster/booster, datum/interaction/interaction)
	visible_message("[user] violently jams [booster] into the side of [src]. [src] beeps, quietly.", \
	"You hear the sound of a device being improperly installed in sensitive machinery, then subsequent beeping.", runemessage = "beep!")
	playsound(src, 'sound/items/rped.ogg', 25, 1)
	boosted = TRUE
	qdel(booster)
	return TRUE

/obj/machinery/power/quantumpad/multitool_act(mob/user, obj/item/tool)
	if(istype(get_area(src), /area/shuttle))
		to_chat(user, span_warning("This is too unstable a platform for \the [src] to operate on!"))
		return ITEM_INTERACT_BLOCKING
	var/obj/item/multitool/multitool = tool
	if(panel_open)
		multitool.connectable = src
		to_chat(user, span_notice("You save the data in [tool]'s buffer."))
		return ITEM_INTERACT_SUCCESS
	if(!istype(multitool.connectable, /obj/machinery/power/quantumpad))
		return ITEM_INTERACT_BLOCKING
	linked_pad = multitool.connectable
	to_chat(user, span_notice("You link [src] to the one in [tool]'s buffer."))
	update_icon()
	return ITEM_INTERACT_SUCCESS
/obj/machinery/power/quantumpad/update_icon()
	. = ..()

	cut_overlays()
	if(panel_open)
		add_overlay("qpad-panel")

	if(inoperable() || panel_open || !powernet)
		icon_state = "[initial(icon_state)]-o"
	else if (!linked_pad)
		icon_state = "[initial(icon_state)]-b"
	else
		icon_state = initial(icon_state)

// Panel flips retry power cable connections so you don't have to decon the whole thing.
/obj/machinery/power/quantumpad/screwdriver_act(mob/user, obj/item/tool)
	var/result = ..()
	if(!ITEM_INTERACT_CONSUMED(result))
		return result
	var/original_powernet = powernet
	if(powernet)
		disconnect_from_network()
	connect_to_network()
	if(powernet != original_powernet)
		update_icon()
	return result

/// Old attack_hand: standard gated pattern (`. = ..(); if(.) return`).
/datum/interaction/machine_hand/quantumpad_use
	id = "quantumpad_use"
	name = "Use"
	effect = /obj/machinery/power/quantumpad/proc/interaction_use

/obj/machinery/power/quantumpad/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(panel_open)
		to_chat(user, span_warning("The panel must be closed before operating this machine!"))
		return TRUE

	if(istype(get_area(src), /area/shuttle))
		to_chat(user, span_warning("This is too unstable a platform for \the [src] to operate on!"))
		// ition Start
		if(linked_pad)
			linked_pad.linked_pad = null
		// ition End
		return TRUE

	if(!powernet)
		to_chat(user, span_warning("[src] is not attached to a powernet!"))
		return TRUE

	if(!linked_pad || QDELETED(linked_pad))
		if(!map_pad_link_id || !initMappedLink())
			to_chat(user, span_warning("There is no linked pad!"))
			return TRUE

	if(world.time < last_teleport + teleport_cooldown)
		to_chat(user, span_warning("[src] is recharging power. Please wait [round((last_teleport + teleport_cooldown - world.time)/10)] seconds."))
		return TRUE

	if(teleporting)
		to_chat(user, span_warning("[src] is charging up. Please wait."))
		return TRUE

	if(linked_pad.teleporting)
		to_chat(user, span_warning("Linked pad is busy. Please wait."))
		return TRUE

	if(linked_pad.inoperable())
		to_chat(user, span_warning("Linked pad is not responding to ping."))
		return TRUE
	src.add_fingerprint(user)
	doteleport(user)
	return TRUE

/obj/machinery/power/quantumpad/attack_ghost(mob/observer/dead/ghost)
	. = ..()
	if(.)
		return
	if(!linked_pad && map_pad_link_id)
		initMappedLink()
	if(linked_pad && !QDELETED(linked_pad))
		ghost.forceMove(get_turf(linked_pad))

/obj/machinery/power/quantumpad/proc/doteleport(mob/user)
	update_icon()
	if(!linked_pad)
		return
	// ition Start
	if(istype(get_area(src), /area/shuttle))
		to_chat(user, span_warning("This is too unstable a platform for \the [src] to operate on!"))
		return
	// ition End
	playsound(src, 'sound/weapons/flash.ogg', 25, 1)
	teleporting = 1

	spawn(teleport_speed)
		// We gone
		if(!src || QDELETED(src))
			teleporting = 0
			return
		// Broken or whatever
		if(inoperable())
			to_chat(user, span_warning("[src] is nonfunctional!"))
			teleporting = 0
			return
		// Linked pad or not, we can always re-scatter people
		if(!can_traverse_gateway())
			teleporting = 0
			last_teleport = world.time
			gateway_scatter(user)
			return
		// Nothing to teleport to
		if(!linked_pad || QDELETED(linked_pad) || linked_pad.inoperable())
			to_chat(user, span_warning("Linked pad is not responding to ping. Teleport aborted."))
			teleporting = 0
			return
		// Insufficient power
		if(!use_teleport_power())
			to_chat(user, span_warning("Power is not sufficient to complete a teleport. Teleport aborted."))
			teleporting = 0
			return

		teleporting = 0
		last_teleport = world.time
		/* CHOMP remove
		sparks()
		linked_pad.sparks()
		*/

		flick("qpad-beam-out", src)
		//playsound(src, 'sound/weapons/emitter2.ogg', 25, 1, extrarange = 3, falloff = 5)
		flick("qpad-beam-in", linked_pad)
		//playsound(linked_pad, 'sound/weapons/emitter2.ogg', 25, 1, extrarange = 3, falloff = 5)

		transport_objects(get_turf(linked_pad))

/obj/machinery/power/quantumpad/proc/initMappedLink()
	. = FALSE
	var/obj/machinery/power/quantumpad/link = mapped_quantum_pads[map_pad_link_id]
	if(link)
		linked_pad = link
		update_icon()
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

	//sparks()
	to_chat(user, span_warning("You feel yourself pulled in different directions, before ending up not far from where you started."))
	flick("qpad-beam-out", src)
	transport_objects(get_turf(dest))

/obj/item/quantum_pad_booster
	icon = 'icons/obj/device.dmi'
	name = "quantum pad particle booster"
	desc = "A deceptively simple interface for increasing the mass of objects a quantum pad is capable of teleporting, at the cost of increased power draw."
	description_info = "The three prongs at the base of the tool are not, in fact, for show."
	force = 9
	sharp = TRUE
	injury_kind = INJURY_PIERCE
	item_state = "analyzer"
	icon_state = "hacktool"
