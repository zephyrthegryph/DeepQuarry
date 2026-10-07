//////
//////  Teleporter computer
//////
/obj/machinery/computer/teleporter
	name = "teleporter control console"
	desc = "Used to control a linked teleportation Hub and Station."
	icon_keyboard = "teleport_key"
	icon_screen = "teleport"
	circuit = /obj/item/circuitboard/teleporter
	dir = 4
	var/id = null
	var/one_time_use = 0	//Used for one-time-use teleport cards (such as clown planet coordinates.)
							//Setting this to 1 will set locked to null after a player enters the portal and will not allow hand-teles to open portals to that location.
	var/datum/tgui_module/teleport_control/teleport_control

CAPABILITIES(/obj/machinery/computer/teleporter)
	owns_one(nameof(teleport_control), /datum/tgui_module/teleport_control, starts = /datum/tgui_module/teleport_control)

/obj/machinery/computer/teleporter/Initialize(mapload)
	id = "[rand(1000, 9999)]"
	. = ..()
	underlays.Cut()
	underlays += image('icons/obj/stationobjs.dmi', icon_state = "telecomp-wires")
	var/obj/machinery/teleport/station/station = null
	var/obj/machinery/teleport/hub/hub = null

	// Search surrounding turfs for the station, and then search the station's surrounding turfs for the hub.
	for(var/direction in GLOB.cardinal)
		station = locate(/obj/machinery/teleport/station, get_step(src, direction))
		if(station)
			for(direction in GLOB.cardinal)
				hub = locate(/obj/machinery/teleport/hub, get_step(station, direction))
				if(hub)
					break
			break

	if(istype(station))
		rel_set(station, nameof(station.com), hub)
		rel_set(teleport_control, nameof(teleport_control.hub), hub)

	if(istype(hub))
		rel_set(hub, nameof(hub.com), src)
		rel_set(teleport_control, nameof(teleport_control.station), station)


/obj/machinery/computer/teleporter/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/teleporter_computer_insert_card,
		/datum/interaction/machine_hand/ungated/teleporter_computer_use,
		/datum/interaction/machine_verb/teleporter_computer_set_id,
	)
	into += dq_interaction_from_spec(type, INTERACT_SILICON("Use", PROC_REF(teleporter_computer_silicon_use)))
	..()

/datum/interaction/machine_item/teleporter_computer_insert_card
	id = "teleporter_computer_insert_card"
	name = "Insert data card"
	held_type = /obj/item/card/data
	effect = /obj/machinery/computer/teleporter/proc/interaction_insert_card

/obj/machinery/computer/teleporter/proc/interaction_insert_card(mob/user, obj/item/card/data/C, datum/interaction/interaction)
	if(!operable() && C.function != "teleporter")
		attack_hand()

	var/obj/L = null

	for(var/obj/effect/landmark/sloc in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
		if(sloc.name != C.data) continue
		if(locate_within(sloc.loc, /mob/living)) continue
		L = sloc
		break

	if(!L)
		L = locate("landmark*[C.data]") // use old stype

	if(istype(L, /obj/effect/landmark/) && istype(L.loc, /turf))
		var/destination_name = C.data
		if(!consume(C, user))
			return TRUE
		to_chat(user, "You insert the coordinates into the machine.")
		to_chat(user, "A message flashes across the screen, reminding the user that the nuclear authentication disk is not transportable via insecure means.")

		if(destination_name == "Clown Land")
			//whoops
			for(var/mob/O in hearers(src, null))
				O.show_message(span_warning("Incoming bluespace portal detected, unable to lock in."), 2)

			for(var/obj/machinery/teleport/hub/H in range(1))
				var/amount = rand(2,5)
				for(var/i=0;i<amount;i++)
					new /mob/living/simple_mob/animal/space/carp(get_turf(H))
			//
		else
			for(var/mob/O in hearers(src, null))
				O.show_message(span_notice("Locked In"), 2)
			rel_set(teleport_control, nameof(teleport_control.locked), L)
			one_time_use = 1

		add_fingerprint(user)
	return TRUE

/// Old attack_ai: open the teleporter control UI.
/obj/machinery/computer/teleporter/proc/teleporter_computer_silicon_use(mob/user, obj/item/held, datum/interaction/interaction)
	teleport_control.tgui_interact(user)
	return TRUE

/datum/interaction/machine_hand/ungated/teleporter_computer_use
	id = "teleporter_computer_use"
	name = "Use"
	effect = /obj/machinery/computer/teleporter/proc/interaction_use

/obj/machinery/computer/teleporter/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	if(!operable())
		return TRUE
	teleport_control.tgui_interact(user)
	return TRUE

/datum/interaction/machine_verb/teleporter_computer_set_id
	id = "teleporter_computer_set_id"
	name = "Set teleporter ID"
	effect = /obj/machinery/computer/teleporter/proc/interaction_set_id

/obj/machinery/computer/teleporter/proc/interaction_set_id(mob/user, obj/item/held, datum/interaction/interaction)
	if(!operable() || !isliving(user))
		return TRUE
	open_request(src, /datum/prompt/text, PROC_REF(teleporter_id_entered), answerer = user, title = "Set teleporter ID", question = "ID Tag:", ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)
	return TRUE

/obj/machinery/computer/teleporter/proc/teleporter_id_entered(datum/act/request/A)
	if(!A.answer)
		return
	if(A.answer.value)
		id = A.answer.value
	return TRUE

//////
//////  Root of all the machinery
//////
/obj/machinery/teleport
	name = "teleport"
	icon = 'icons/obj/stationobjs.dmi'
	density = TRUE
	anchored = TRUE
	var/lockeddown = 0

//////
//////  The part you step into
//////
/obj/machinery/teleport/hub
	name = "teleporter hub"
	desc = "It's the hub of a teleporting machine."
	icon_state = "tele0"
	dir = 4
	var/accurate = 0
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 2000
	circuit = /obj/item/circuitboard/teleporter_hub
	var/obj/machinery/computer/teleporter/com

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with and draws its wiring
/obj/machinery/teleport/hub/Initialize(mapload)
	. = ..()
	underlays += image('icons/obj/stationobjs.dmi', icon_state = "tele-wires")
	default_apply_parts()

// the teleporter console forgets its hub.

CAPABILITIES(/obj/machinery/teleport/hub)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))

/// Something walked into it (the bump action's notice).
/obj/machinery/teleport/hub/proc/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	var/atom/movable/M = N.bumper
	if(icon_state == "tele1")
		teleport(M)
		use_power(5000)
	return

/obj/machinery/teleport/hub/proc/teleport(atom/movable/M as mob|obj)
	if(!com())
		return
	if(!com().teleport_control.locked())
		for(var/mob/O in hearers(src, null))
			O.show_message(span_warning("Failure: Cannot authenticate locked on coordinates. Please reinstate coordinate matrix."))
		return
	if(istype(M, /atom/movable))
		// ition Start: Prevent taurriding abuse
		if(isliving(M))
			var/mob/living/L = M
			if(LAZYLEN(L?.buckled_mob_list()))
				var/datum/riding/R = L.riding_datum
				for(var/rider in L?.buckled_mob_list())
					R.force_dismount(rider)
		// ition End: Prevent taurriding abuse
		if(prob(5) && !accurate) //oh dear a problem, put em in deep space
			do_teleport(M, locate(rand((2*TRANSITIONEDGE), world.maxx - (2*TRANSITIONEDGE)), rand((2*TRANSITIONEDGE), world.maxy - (2*TRANSITIONEDGE)), 3), 2)
		else
			do_teleport(M, com().teleport_control.locked()) //dead-on precision

		if(com().one_time_use) //Make one-time-use cards only usable one time!
			com().one_time_use = 0
			rel_clear(com().teleport_control, nameof(/datum/cinematic::locked))
	else
		fx_sparks(src, 5)
		accurate = 1
		after(src, 5 MINUTES, PROC_REF(calibration_lapses)) //Accurate teleporting for 5 minutes
		for(var/mob/B in hearers(src, null))
			B.show_message(span_notice("Test fire completed."))
	return

//////
//////  The middle part
//////
/obj/machinery/teleport/station
	name = "station"
	desc = "It's the station thingy of a teleport thingy." //seriously, wtf.
	icon_state = "controller"
	dir = 4
	COOLDOWN_DECLARE(teleport_cooldown)
	var/engaged = 0
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 2000
	circuit = /obj/item/circuitboard/teleporter_station
	var/obj/machinery/teleport/hub/com

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with and draws its wiring
/obj/machinery/teleport/station/Initialize(mapload)
	. = ..()
	add_overlay("controller-wires")
	default_apply_parts()

// the teleporter console forgets its station.

/obj/machinery/teleport/station/proc/engage(mob/user)
	if(!operable())
		return

	if(com())
		com().icon_state = "tele1"
		use_power(5000)
		set_use_power(USE_POWER_ACTIVE)
		com().set_use_power(USE_POWER_ACTIVE)
		for(var/mob/O in hearers(src, null))
			O.show_message(span_notice("Teleporter engaged!"), 2)
	if(user)
		add_fingerprint(user)
	engaged = 1
	return

/obj/machinery/teleport/station/proc/disengage(mob/user)
	if(!operable())
		return

	if(com())
		com().icon_state = "tele0"
		com().accurate = 0
		com().set_use_power(USE_POWER_IDLE)
		set_use_power(USE_POWER_IDLE)
		for(var/mob/O in hearers(src, null))
			O.show_message(span_notice("Teleporter disengaged!"), 2)
	if(user)
		add_fingerprint(user)
	engaged = 0
	return

/obj/machinery/teleport/station/proc/testfire()
	if(!com() || !COOLDOWN_FINISHED(src, teleport_cooldown))
		return

	COOLDOWN_START(src, teleport_cooldown, 3 SECONDS)
	visible_message(span_notice("Test firing!"))
	com().teleport()
	use_power(5000)
	flick(src, "controller-c")


/obj/machinery/teleport/station/power_change()
	. = ..()
	if(power_lost())
		icon_state = "controller-p"

		if(com())
			com().icon_state = "tele0"
	else
		icon_state = "controller"

/obj/effect/laser/Bump()
	range--
	return

/obj/effect/laser/Move()
	range--
	return

/// A test fire's calibration lapses.
/obj/machinery/teleport/hub/proc/calibration_lapses()
	accurate = 0

/// com (a relation view: it reads null once the target is deleted).
/obj/machinery/teleport/hub/proc/com() as /obj/machinery/computer/teleporter
	return com

/// com (a relation view: it reads null once the target is deleted).
/obj/machinery/teleport/station/proc/com() as /obj/machinery/teleport/hub
	return com
