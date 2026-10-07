//Hyper pads, kinda a fusion between quantum pads and gateways. 3x3 teleporter with slow recharge.

/obj/machinery/hyperpad
	name = "quantum leap pad"
	desc = "A high scale quantum entangled teleportation device for secure short distance travel."
	icon = 'icons/obj/telescience_ch.dmi'
	icon_state = "hpad"
	density = 0
	anchored = 1
	var/tmp/obj/machinery/hyperpad/centre/primary

CAPABILITIES(/obj/machinery/hyperpad)
	op("hyperpad_ghost_use", observer(), priority(OP_PRIORITY_DEFAULT - 2), label("View"), then(PROC_REF(hyperpad_ghost_use)))
	op("hyperpad_delegate", hand(), priority(OP_PRIORITY_DEFAULT - 2), label("Activate"), then(PROC_REF(interaction_delegate)))

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
	op("hyperpad_centre_ghost_travel", observer(), priority(OP_PRIORITY_DEFAULT - 1), label("Travel"), then(PROC_REF(hyperpad_centre_ghost_travel)))
	op("hyperpad_centre_teleport", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Activate"), then(PROC_REF(interaction_teleport)))

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
/obj/machinery/hyperpad/centre/proc/hyperpad_centre_ghost_travel(datum/act/op/A)
	var/mob/observer/dead/ghost = A.actor
	hyperpad_ghost_view(ghost)
	if(linked_pad() && !QDELETED(linked_pad()))
		ghost.forceMove(get_turf(linked_pad()))
	return OP_OK

/// Old attack_ghost: ran the ghost default first, then the primary pad's ghost Use.
/obj/machinery/hyperpad/proc/hyperpad_ghost_view(mob/observer/dead/ghost)
	actor_use_default(/datum/input_adapter/ghost, ghost, src)
	if(primary())
		actor_use(/datum/input_adapter/ghost, ghost, primary())

/obj/machinery/hyperpad/proc/hyperpad_ghost_use(datum/act/op/A)
	hyperpad_ghost_view(A.actor)
	return OP_OK

/obj/machinery/hyperpad/centre/proc/interaction_teleport(datum/act/op/A)
	var/mob/user = A.actor
	detect(user)
	if(!linked_pad() || QDELETED(linked_pad()))
		if(!map_pad_link_id || !initMappedLink())
			to_chat(user, span_warning("There is no linked pad!"))
			return OP_OK
	if(teleporting)
		to_chat(user, span_warning("[src] is charging up. Please wait."))
		return OP_OK
	if(!COOLDOWN_FINISHED(src, teleport_cooldown_until))
		to_chat(user, span_warning("[src] is recharging power. Please wait [round(COOLDOWN_TIMELEFT(src, teleport_cooldown_until)/10)] seconds."))
		return OP_OK
	if(linked_pad().teleporting)
		to_chat(user, span_warning("Linked pad is busy. Please wait."))
		return OP_OK
	src.add_fingerprint(user)
	startteleport(user)
	return OP_OK

/obj/machinery/hyperpad/proc/interaction_delegate

/obj/machinery/hyperpad/proc/interaction_delegate(datum/act/op/A)
	if(primary())
		primary().attack_hand(A.actor)
	return OP_OK

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
