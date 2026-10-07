//Hyper pads, kinda a fusion between quantum pads and gateways. 3x3 teleporter with slow recharge.

/obj/machinery/hyperpad
	name = "quantum leap pad"
	desc = "A high scale quantum entangled teleportation device for secure short distance travel."
	icon = 'icons/obj/telescience_ch.dmi'
	icon_state = "hpad"
	density = 0
	anchored = 1
	var/tmp/obj/machinery/hyperpad/centre/primary

/obj/machinery/hyperpad/centre
	var/teleport_cooldown = 400 //30 seconds
	var/teleport_speed = 60
	COOLDOWN_DECLARE(teleport_cooldown_until) //to handle the cooldown
	var/teleporting = 0 //if it's in the process of teleporting
	var/tmp/obj/machinery/hyperpad/centre/linked_pad
	icon_state = "hpad_centre"
	var/newcolor = "#00FFFF" //used for colouring the overlays

	//mapping: map_pad_link_id names the partner centre's map_pad_id (REL_KEYED below)
	var/map_pad_id = null as text //what's my name
	var/map_pad_link_id = null as text //who's my friend
	var/ready = 0
	var/list/linked
	var/max_item_teleport = 30

CAPABILITIES(/obj/machinery/hyperpad/centre)
	owns_many(nameof(linked))

/obj/machinery/hyperpad/centre/Initialize(mapload)
	. = ..()
	if(map_pad_id)
		detect()
	set_light(3, 1, newcolor)

// Its linked pads go with it.

// Mapped links: linked_pad auto-links to the centre whose map_pad_id equals our map_pad_link_id.
/obj/machinery/hyperpad/centre/relations()
	. = ..()
	. += rel_one(nameof(linked_pad), keyed = nameof(map_pad_link_id), keyed_target = /obj/machinery/hyperpad/centre)
	. += rel_key(nameof(map_pad_id))

/// Always usable, powered or not.
/obj/machinery/hyperpad/operable(additional_flags = 0)
	return TRUE

/// Old attack_ghost: ran the parent pad's first (the ghost default, then the primary pad's),
/// then drifts the ghost to the linked pad.
/obj/machinery/hyperpad/centre/proc/hyperpad_centre_ghost_travel(mob/observer/dead/ghost, obj/item/held, datum/interaction/interaction)
	hyperpad_ghost_use(ghost, held, interaction)
	if(linked_pad() && !QDELETED(linked_pad()))
		ghost.forceMove(get_turf(linked_pad()))
	return TRUE

/// Old attack_ghost: ran the ghost default first, then the primary pad's ghost Use.
/obj/machinery/hyperpad/proc/hyperpad_ghost_use(mob/observer/dead/ghost, obj/item/held, datum/interaction/interaction)
	actor_use_default(/datum/input_adapter/ghost, ghost, src)
	if(primary())
		actor_use(/datum/input_adapter/ghost, ghost, primary())
	return TRUE

/obj/machinery/hyperpad/centre/declare_interactions(list/into)
	var/static/list/actor_specs = list(
		INTERACT_OBSERVER("Travel", PROC_REF(hyperpad_centre_ghost_travel)),
	)
	for(var/actor_spec in actor_specs)
		into += dq_interaction_from_spec(type, actor_spec)
	into += list(
		/datum/interaction/machine_hand/hyperpad_centre_teleport,
	)
	..()

/datum/interaction/machine_hand/hyperpad_centre_teleport
	id = "hyperpad_centre_teleport"
	name = "Activate"
	effect = /obj/machinery/hyperpad/centre/proc/interaction_teleport

/obj/machinery/hyperpad/centre/proc/interaction_teleport(mob/user, obj/item/held, datum/interaction/interaction)
	detect(user)
	if(!linked_pad() || QDELETED(linked_pad()))
		if(!map_pad_link_id || !initMappedLink())
			to_chat(user, span_warning("There is no linked pad!"))
			return TRUE
	if(teleporting)
		to_chat(user, span_warning("[src] is charging up. Please wait."))
		return TRUE
	if(!COOLDOWN_FINISHED(src, teleport_cooldown_until))
		to_chat(user, span_warning("[src] is recharging power. Please wait [round(COOLDOWN_TIMELEFT(src, teleport_cooldown_until)/10)] seconds."))
		return TRUE
	if(linked_pad().teleporting)
		to_chat(user, span_warning("Linked pad is busy. Please wait."))
		return TRUE
	src.add_fingerprint(user)
	startteleport(user)
	return TRUE

/obj/machinery/hyperpad/declare_interactions(list/into)
	var/static/list/actor_specs = list(
		INTERACT_OBSERVER("View", PROC_REF(hyperpad_ghost_use)),
	)
	for(var/actor_spec in actor_specs)
		into += dq_interaction_from_spec(type, actor_spec)
	into += list(
		/datum/interaction/machine_hand/hyperpad_delegate,
	)
	..()

/datum/interaction/machine_hand/hyperpad_delegate
	id = "hyperpad_delegate"
	name = "Activate"
	effect = /obj/machinery/hyperpad/proc/interaction_delegate

/obj/machinery/hyperpad/proc/interaction_delegate(mob/user, obj/item/held, datum/interaction/interaction)
	if(primary())
		primary().attack_hand(user)
	return TRUE

/obj/machinery/hyperpad/centre/proc/initMappedLink()
	. = FALSE
	// The keyed relation links mapped centres when they materialize; this only reports it.
	if(linked_pad())
		. = TRUE

/obj/machinery/hyperpad/centre/proc/detect(mob/user)
	if(!ready)
		var/static/list/dirs = list(1,2,4,8,5,9,6,10) //A really dumb way of making a circle of dirs around the centre piece. If there's a better way, tell me.
		var/list/turfs = trange(1, src) - loc
		var/iterate = 1
		for(var/turf/T in turfs)
			var/obj/machinery/hyperpad/new_pad = new /obj/machinery/hyperpad(T)
			rel_add(src, nameof(linked), new_pad) // the centre's pieces go with it
			rel_set(new_pad, nameof(new_pad.primary), src)
			new_pad.dir = dirs[iterate]
			iterate += 1
		if(length(linked) == 8)
			ready = 1
			start_charge()
		else
			to_chat(user, span_warning("Pad detect failed. Are all eight pieces linked?"))

/obj/machinery/hyperpad/centre/proc/startteleport(mob/user)
	if(!linked_pad())
		return
	play_sfx(get_turf(src), SFX_WEAPONS_FLASH, 0.25)
	teleporting = 1
	after(src, teleport_speed, PROC_REF(doteleport), with = list(user))
	var/speed = teleport_speed/8
	for(var/obj/machinery/hyperpad/P in linked)
		after(src, speed, PROC_REF(animate_discharge), with = list(P))
		speed += teleport_speed/8

/obj/machinery/hyperpad/centre/proc/animate_discharge(obj/machinery/hyperpad/Pad)
	if(Pad)
		Pad.cut_overlays()

/obj/machinery/hyperpad/centre/proc/doteleport(mob/user)
	if(!src || QDELETED(src))
		teleporting = 0
		return
	if(!linked_pad() || QDELETED(linked_pad()))
		to_chat(user, span_warning("Linked pad is not responding to ping. Teleport aborted."))
		teleporting = 0
		return

	teleporting = 0
	COOLDOWN_START(src, teleport_cooldown_until, teleport_cooldown)
	var/limit = 0
	var/list/turfs = trange(1, src)
	for(var/turf/T in turfs)
		if(limit >= max_item_teleport)
			break
		var/xadjust = src.x - T.x
		var/yadjust = src.y - T.y
		for(var/atom/movable/ROI in contents_of(T))
			if(ROI.anchored)
				if(isliving(ROI))
					var/mob/living/L = ROI
					if(L?.buckled_to())
						// TP people on office chairs
						var/atom/movable/_tmp_buck_44 = L?.buckled_to()
						if(_tmp_buck_44.anchored)
							continue
					else
						continue
				if(!((istype(ROI,/obj/mecha)) || istype(ROI,/obj/vehicle)))
					continue //TP things that move that are "anchored"
			if(isobserver(ROI))
				continue
			var/datum/effect/effect/system/teleport_greyscale/tele1 = new /datum/effect/effect/system/teleport_greyscale()
			tele1.set_up(newcolor, get_turf(ROI))
			var/datum/effect/effect/system/teleport_greyscale/tele2 = new /datum/effect/effect/system/teleport_greyscale()
			tele2.set_up(linked_pad().newcolor, locate((linked_pad().x - xadjust), (linked_pad().y - yadjust), linked_pad().z))
			limit += 1
			do_teleport(ROI, locate((linked_pad().x - xadjust), (linked_pad().y - yadjust), linked_pad().z), effectin = tele1, effectout = tele2, asoundin = 'sound/weapons/emitter2.ogg', asoundout = 'sound/weapons/emitter2.ogg', channel = TELEPORT_CHANNEL_QUANTUM)

	cut_overlays()
	for(var/obj/machinery/hyperpad/P in linked)
		P.cut_overlays()
	start_charge()

/obj/machinery/hyperpad/centre/proc/start_charge()
	var/mutable_appearance/color_overlay = mutable_appearance('icons/obj/telescience_ch.dmi', "hpad_centre_on")
	color_overlay.color = newcolor
	add_overlay(color_overlay)

	color_overlay = mutable_appearance('icons/obj/telescience_ch.dmi', "hpad_on")
	color_overlay.color = newcolor
	var/timer = teleport_cooldown/8
	for(var/obj/machinery/hyperpad/P in linked)
		after(src, timer, PROC_REF(animate_charge), with = list(P, color_overlay))
		timer += teleport_cooldown/8

/obj/machinery/hyperpad/centre/proc/animate_charge(obj/machinery/hyperpad/Pad, mutable_appearance/color)
	if(Pad && color)
		Pad.add_overlay(color)

/// the primary this refers to (a relation view: it reads null once the target is deleted).
/obj/machinery/hyperpad/proc/primary() as /obj/machinery/hyperpad/centre
	return primary

/// the linked_pad this refers to (a relation view: it reads null once the target is deleted).
/obj/machinery/hyperpad/centre/proc/linked_pad() as /obj/machinery/hyperpad/centre
	return linked_pad
