/obj/machinery/computer/telescience
	name = "\improper Telepad Control Console"
	desc = "Used to teleport objects to and from the telescience telepad."
	icon_screen = "teleport"
	icon_keyboard = "teleport_key"
	circuit = /obj/item/circuitboard/telesci_console
	var/sending = 1
	var/tmp/obj/machinery/telepad/telepad
	var/temp_msg = "Telescience control console initialized. Welcome."

	// VARIABLES //
	var/teles_left	// How many teleports left until it becomes uncalibrated
	var/datum/projectile_data/last_tele_data = null
	var/z_co = 1
	var/distance_off
	var/rotation_off
	var/tmp/turf/last_target

	var/rotation = 0
	var/distance = 5

	// Based on the distance used
	COOLDOWN_DECLARE(teleport_cooldown)
	var/teleporting = 0
	var/starting_crystals = 0
	var/max_crystals = 4
	// Used to adjust OP-ness: (4 crystals * 6 efficiency * 12.5 coefficient) = 300 range.
	var/powerCoefficient = 12.5
	var/list/crystals
	var/obj/item/gps/inserted_gps
	var/overmap_range = 3

CAPABILITIES(/obj/machinery/computer/telescience)
	owns_one(nameof(inserted_gps), on_destroy = ON_DESTROY_SPILL)
	owns_one(nameof(last_tele_data), /datum/projectile_data)
	interface("TelesciConsole")
	without("ui_open")
	op("setrotation", ui_act("setrotation", arg("val", num())), then(PROC_REF(ui_act_setrotation)))
	op("setdistance", ui_act("setdistance", arg("val", num())), then(PROC_REF(ui_act_setdistance)))
	op("setz", ui_act("setz", arg("setz", num())), then(PROC_REF(ui_act_setz)))
	op("ejectGPS", ui_act("ejectGPS"), then(PROC_REF(ui_act_ejectgps)))
	op("setMemory", ui_act("setMemory"), then(PROC_REF(ui_act_setmemory)))
	op("send", ui_act("send"), then(PROC_REF(ui_act_send)))
	op("receive", ui_act("receive"), then(PROC_REF(ui_act_receive)))
	op("recal", ui_act("recal"), then(PROC_REF(ui_act_recal)))
	op("eject", ui_act("eject"), then(PROC_REF(ui_act_eject)))
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(multitool_used)))
	op("insert_crystal", item(/obj/item/bluespace_crystal), priority(OP_PRIORITY_DEFAULT - 1), label("Insert crystal"), needs(req(PROC_REF(has_crystal_slot_holds), because = PROC_REF(has_crystal_slot_refusal))), then(PROC_REF(interaction_insert_crystal)))
	op("insert_gps", item(/obj/item/gps), priority(OP_PRIORITY_DEFAULT - 1), label("Insert GPS"), then(PROC_REF(interaction_insert_gps)))

/obj/machinery/computer/telescience/ownership()
	. = ..()
	. += owns(nameof(crystals), policy = OWN_SPILL)

// its crystals are ejected.
/obj/machinery/computer/telescience/on_destroy(force)
	eject()
	..()

/obj/machinery/computer/telescience/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "There are [length(crystals) ? length(crystals) : "no"] bluespace crystal\s in the crystal slots."

/obj/machinery/computer/telescience/Initialize(mapload)
	. = ..()
	recalibrate()
	for(var/i = 1; i <= starting_crystals; i++)
		rel_add(src, nameof(crystals), new /obj/item/bluespace_crystal/artificial(src)) // starting crystals

/// Requirement: a free crystal slot.
/obj/machinery/computer/telescience/proc/has_crystal_slot(mob/user, atom/target, obj/item/held)
	return length(crystals) >= max_crystals ? "there are not enough crystal slots" : TRUE

/// Requirement (was REQ_* has_crystal_slot): the legacy check answers TRUE to pass.
/obj/machinery/computer/telescience/proc/has_crystal_slot_holds(datum/act/op/A)
	var/answer = has_crystal_slot(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why has_crystal_slot_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/computer/telescience/proc/has_crystal_slot_refusal(datum/act/op/A)
	var/answer = has_crystal_slot(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/machinery/computer/telescience/proc/interaction_insert_crystal(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!user.unEquip(W))
		return TRUE
	W.forceMove(src)
	own_move(W, src, nameof(crystals))
	act_message(user, src, MSG_SELF(span_notice("You insert [W] into %T%'s crystal slot.")), MSG_OTHERS("%U% inserts [W] into %T%'s crystal slot."))
	return TRUE

/obj/machinery/computer/telescience/proc/interaction_insert_gps(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!inserted_gps)
		if(!move_into(src, nameof(src.inserted_gps), W, user))
			return TRUE
		act_message(user, src, MSG_SELF(span_notice("You insert [W] into %T%'s GPS device slot.")), MSG_OTHERS("%U% inserts [W] into %T%'s GPS device slot."))
	return TRUE

/obj/machinery/computer/telescience/proc/multitool_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	var/obj/item/multitool/multitool = tool
	if(!istype(multitool.connectable(), /obj/machinery/telepad))
		return OP_OK
	rel_set(src, nameof(telepad), multitool.connectable())
	rel_clear(multitool, nameof(multitool.connectable))
	to_chat(user, span_warning("You upload the data from the [tool.name]'s buffer."))
	return OP_OK

/obj/machinery/computer/telescience/proc/get_max_allowed_distance()
	return FLOOR((length(crystals) * telepad().efficiency * powerCoefficient), 1)

/// /obj/machinery/computer/telescience's window data.
/obj/machinery/computer/telescience/ui_data(datum/act/eval/A)
	var/list/data = list()
	if(!telepad())
		in_use = 0     //Yeah so if you deconstruct teleporter while its in the process of shooting it wont disable the console
		data["noTelepad"] = 1
	else
		data["noTelepad"] = 0
		data["insertedGps"] = inserted_gps
		data["rotation"] = rotation
		data["currentZ"] = z_co
		data["cooldown"] = max(0, min(100, COOLDOWN_TIMELEFT(src, teleport_cooldown) / 10))
		data["crystalCount"] = length(crystals)
		data["maxCrystals"] = max_crystals
		data["maxPossibleDistance"] = FLOOR((max_crystals * powerCoefficient * 6), 1); // max efficiency is 6
		data["maxAllowedDistance"] = get_max_allowed_distance()
		data["distance"] = distance

		data["tempMsg"] = temp_msg
		if(telepad().panel_open)
			data["tempMsg"] = "Telepad undergoing physical maintenance operations."

		//We'll base our options on connected z's or overmap
		data["sectorOptions"] = using_map.get_map_levels(z, TRUE, overmap_range)

		data["lastTeleData"] = null
		if(last_tele_data)
			data["lastTeleData"] = list()
			data["lastTeleData"]["src_x"] = last_tele_data.src_x
			data["lastTeleData"]["src_y"] = last_tele_data.src_y
			data["lastTeleData"]["distance"] = last_tele_data.distance
			data["lastTeleData"]["time"] = last_tele_data.time

	return data

/obj/machinery/computer/telescience/proc/ui_gate(datum/act/op/A)
	if(!telepad() || telepad().panel_open)
		return FALSE
	return TRUE

/obj/machinery/computer/telescience/proc/ui_act_setrotation(datum/act/op/A, val)
	if(!ui_gate(A))
		return FALSE
	rotation = CLAMP(val, -900, 900)
	rotation = round(rotation, 0.01)
	return TRUE

/obj/machinery/computer/telescience/proc/ui_act_setdistance(datum/act/op/A, val)
	if(!ui_gate(A))
		return FALSE
	distance = CLAMP(val, 1, get_max_allowed_distance())
	distance = FLOOR(distance, 1)
	return TRUE

/obj/machinery/computer/telescience/proc/ui_act_setz(datum/act/op/A, setz)
	if(!ui_gate(A))
		return FALSE
	var/new_z = setz
	if(new_z in using_map.player_levels)
		z_co = new_z
	return TRUE

/obj/machinery/computer/telescience/proc/ui_act_ejectgps(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(inserted_gps)
		inserted_gps.forceMove(loc)
		own_take(src, nameof(/obj/machinery/computer/telescience::inserted_gps))
	return TRUE

/obj/machinery/computer/telescience/proc/ui_act_setmemory(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(last_target() && inserted_gps)
		// TODO - What was this even supposed to do??
		//inserted_gps.locked_location = last_target
		temp_msg = "Function Deprecated. No action taken."
	else
		temp_msg = "Function Deprecated. No action taken."
	return TRUE

/obj/machinery/computer/telescience/proc/ui_act_send(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	sending = 1
	teleport(user)
	return TRUE

/obj/machinery/computer/telescience/proc/ui_act_receive(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	sending = 0
	teleport(user)
	return TRUE

/obj/machinery/computer/telescience/proc/ui_act_recal(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	recalibrate()
	sparks()
	temp_msg = "NOTICE: Calibration successful."
	return TRUE

/obj/machinery/computer/telescience/proc/ui_act_eject(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	eject()
	temp_msg = "NOTICE: Bluespace crystals ejected."
	return TRUE

/obj/machinery/computer/telescience/proc/sparks()
	if(telepad())
		fx_sparks(get_turf(telepad()), 5)
	else
		return

/obj/machinery/computer/telescience/proc/telefail()
	COOLDOWN_START(src, teleport_cooldown, (2 SECONDS))
	switch(rand(99))
		if(0 to 85)
			sparks()
			visible_message(span_warning("The telepad weakly fizzles."))
			return
		if(86 to 90)
			// Irradiate everyone in telescience!
			for(var/obj/machinery/telepad/E in REGISTRY_MEMBERS(REGISTRY_MACHINES))
				var/L = get_turf(E)
				sparks()
				for(var/mob/living/carbon/human/M in viewers(L, null))
					M.apply_effect((rand(10, 20)), IRRADIATE, 0)
					to_chat(M, span_warning("You feel strange."))
			return
		if(91 to 98)
			// They did the mash! (They did the monster mash!) The monster mash! (It was a graveyard smash!)
			sparks()
			if(telepad())
				var/L = get_turf(telepad())
				var/blocked = list(/mob/living/simple_mob/vore, /mob/living/simple_mob/vore/ddraig) + typesof(/mob/living/simple_mob/vore/woof) + typesof(/mob/living/simple_mob/vore/overmap)
				var/list/hostiles = typesof(/mob/living/simple_mob/vore) - blocked
				play_sfx(L, SFX_EFFECTS_PHASEIN, extrarange = 3, falloff = 5)
				for(var/i in 1 to rand(1,4))
					var/chosen = pick(hostiles)
					var/mob/living/simple_mob/vore/H = new chosen
					H.ai_brain?.set_hostile(TRUE)
					H.forceMove(L)
			return
		if(99)
			sparks()
			visible_message(span_warning("The telepad changes colors rapidly, and opens a portal, and you see what your mind seems to think is the very threads that hold the pattern of the universe together, and a eerie sense of paranoia creeps into you."))
			spacevine_infestation()
			return

/obj/machinery/computer/telescience/proc/doteleport(mob/user)

	if(!COOLDOWN_FINISHED(src, teleport_cooldown))
		return

	if(telepad())
		var/trueDistance = CLAMP(distance + distance_off, 1, get_max_allowed_distance())
		var/trueRotation = rotation + rotation_off

		var/datum/projectile_data/proj_data = simple_projectile_trajectory(telepad().x, telepad().y, trueRotation, trueDistance)
		rel_set(src, nameof(last_tele_data), proj_data)

		var/trueX = proj_data.dest_x
		var/trueY = proj_data.dest_y
		if(trueX < 1 || trueX > world.maxx || trueY < 1 || trueY > world.maxy)
			telefail()
			temp_msg = "ERROR! Target coordinate is outside known time and space!"
			return

		var/spawn_time = round(proj_data.time) * 10

		var/turf/target = locate(trueX, trueY, z_co)
		rel_set(src, nameof(last_target), target)
		flick("pad-beam", telepad())

		if(spawn_time > 15) // 1.5 seconds
			play_sfx(telepad(), SFX_WEAPONS_FLASH, 0.5)
			// Wait depending on the time the projectile took to get there
			teleporting = 1
			temp_msg = "Powering up bluespace crystals. Please wait."

		after(src, spawn_time, PROC_REF(finish_teleport), with = list(user, trueDistance, spawn_time, target, trueX, trueY)) // in deciseconds

/obj/machinery/computer/telescience/proc/teleport(mob/user)
	if(!COOLDOWN_FINISHED(src, teleport_cooldown))
		temp_msg = "ERROR! Teleportation console is cooling down. Please wait."
		return
	if(teleporting)
		temp_msg = "ERROR! Teleportation in progress. Please wait."
		return
	distance = CLAMP(distance, 0, get_max_allowed_distance())
	if(rotation == null || distance == null || z_co == null)
		temp_msg = "ERROR! Set a distance, rotation and sector."
		return
	if(distance <= 0)
		telefail()
		temp_msg = "ERROR! No distance selected!"
		return
	if(!(z_co in using_map.player_levels))
		telefail()
		temp_msg = "ERROR! Sector is outside known time and space!"
		return
	if(teles_left > 0)
		doteleport(user)
	else
		telefail()
		temp_msg = "ERROR! Calibration required."
		return
	return

/obj/machinery/computer/telescience/proc/eject()
	for(var/obj/item/I as anything in own_take_all(src, nameof(crystals)))
		I.forceMove(src.loc)
	distance = 0

/obj/machinery/computer/telescience/proc/recalibrate()
	teles_left = rand(40, 50)
	distance_off = rand(-4, 4)
	rotation_off = rand(-10, 10)

// Procedure that calculates the actual trajectory taken!
/proc/simple_projectile_trajectory(src_x, src_y, rotation, distance)
	var/time = distance / 10 // 100ms per distance seems fine?
	var/dest_x = src_x + distance*sin(rotation);
	var/dest_y = src_y + distance*cos(rotation);
	return new /datum/projectile_data(src_x, src_y, time, distance, 0, 0, dest_x, dest_y)

/obj/machinery/computer/telescience/proc/finish_teleport(mob/user, trueDistance, spawn_time, turf/target, trueX, trueY)
	var/area/A = get_area(target)
	if(!telepad())
		return
	if(!telepad().operable())
		return
	teleporting = 0
	COOLDOWN_START(src, teleport_cooldown, (spawn_time * 2))
	teles_left -= 1

	// use a lot of power
	use_power(trueDistance * 10000)

	fx_sparks(get_turf(telepad()), 5)

	if(!A || (A.flag_check(BLUE_SHIELDED)) || (target.block_tele)) // consistency smh
		telefail()
		temp_msg = "ERROR! Target is shielded from bluespace intersection!"
		return

	temp_msg = "Teleport successful. "
	if(teles_left < 10)
		temp_msg += "Calibration required soon. "
	temp_msg += "Data printed below."

	var/sparks = get_turf(target)
	fx_sparks(sparks, 5)

	var/turf/source = target
	var/turf/dest = get_turf(telepad())
	var/log_msg = ""
	log_msg += ": [key_name(user)] has teleported "

	if(sending)
		source = dest
		dest = target

	var/list/sent_atoms = list()
	flick("pad-beam", telepad())
	play_sfx(telepad(), SFX_WEAPONS_EMITTER2)
	for(var/atom/movable/ROI in source)
		// if is anchored, don't let through
		if(ROI.anchored)
			if(isliving(ROI))
				var/mob/living/L = ROI
				if(L?.buckled_to())
					// TP people on office chairs
					var/atom/movable/_tmp_buck_45 = L?.buckled_to()
					if(_tmp_buck_45.anchored)
						continue

					log_msg += "[key_name(L)] (on a chair), "
				else
					continue
			else if(!isobserver(ROI))
				continue
		if(ismob(ROI))
			var/mob/T = ROI
			log_msg += "[key_name(T)], "
		else
			log_msg += "[ROI.name]"
			if (istype(ROI, /obj/structure/closet))
				var/obj/structure/closet/C = ROI
				log_msg += " ("
				C.latent_materialize_all() // teleported contents are real (C5)
				for(var/atom/movable/Q as mob|obj in C) // ALLOW(latent): walk reviewed: reads what is materialized on purpose
					if(ismob(Q))
						log_msg += "[key_name(Q)], "
					else
						log_msg += "[Q.name], "
				if (dd_hassuffix(log_msg, "("))
					log_msg += "empty)"
				else
					log_msg += ")"
			log_msg += ", "
		sent_atoms += ROI
		do_teleport(ROI, dest)
	// Either works for the experiment scan, so fire signals on both
	PUBLISH_LEGACY(src, /datum/notice/telesci_teleport, sent_atoms, target, sending)
	PUBLISH_LEGACY(telepad(), /datum/notice/telesci_teleport, sent_atoms, target, sending)

	if (!dd_hassuffix(log_msg, ", "))
		log_msg += "nothing"
	log_msg += " [sending ? "to" : "from"] [trueX], [trueY], [z_co] ([A ? A.name : "null area"])"
	investigate_log(log_msg, "telesci")


/// the telepad this refers to (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/telescience/proc/telepad() as /obj/machinery/telepad
	return telepad

/// the last_target this refers to (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/telescience/proc/last_target() as /turf
	return last_target
