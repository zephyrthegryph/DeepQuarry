/*
 * Cryogenic refrigeration unit. Basically a despawner.
 * Stealing a lot of concepts/code from sleepers due to massive laziness.
 * The despawn tick will only fire if it's been more than time_till_despawned ticks
 * since time_entered, which is world.time when the occupant moves in.
 * ~ Zuhayr
 */

//Main cryopod console.

/obj/machinery/computer/cryopod
	name = "cryogenic oversight console"
	desc = "An interface between crew and the cryogenic storage oversight systems."
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "cellconsole"
	circuit = /obj/item/circuitboard/cryopodcontrol
	density = FALSE
	interact_offline = 1
	mode = null

	//Used for logging people entering cryosleep and important items they are carrying.
	var/list/frozen_crew
	var/list/frozen_items
	var/list/_admin_logs // _ so it shows first in VV

	var/storage_type = "crewmembers"
	var/storage_name = "Cryogenic Oversight Control"
	var/allow_items = 1

	req_one_access = list(ACCESS_HEADS)

/obj/machinery/computer/cryopod/draw(datum/look/look)
	..()
	if((power_lost()) || (broken_now()))
		look.state("[initial(icon_state)]-p")
	else
		look.state(initial(icon_state))

/obj/machinery/computer/cryopod/robot
	name = "robotic storage console"
	desc = "An interface between crew and the robotic storage systems"
	icon = 'icons/obj/robot_storage.dmi'
	icon_state = "console"
	circuit = /obj/item/circuitboard/robotstoragecontrol

	storage_type = "cyborgs"
	storage_name = "Robotic Storage Control"
	allow_items = 0

/obj/machinery/computer/cryopod/dorms
	name = "residential oversight console"
	desc = "An interface between visitors and the residential oversight systems tasked with keeping track of all visitors in the deeper section of the colony."
	circuit = /obj/item/circuitboard/dormscontrol

	storage_type = "visitors"
	storage_name = "Residential Oversight Control"
	allow_items = 1

/obj/machinery/computer/cryopod/travel
	name = "docking oversight console"
	desc = "An interface between visitors and the docking oversight systems tasked with keeping track of all visitors who enter or exit from the docks."
	circuit = /obj/item/circuitboard/travelcontrol

	storage_type = "visitors"
	storage_name = "Travel Oversight Control"
	allow_items = 1

/obj/machinery/computer/cryopod/gateway
	circuit = /obj/item/circuitboard/gatewaycontrol

	storage_type = "visitors"
	storage_name = "Travel Oversight Control"
	allow_items = 1

/obj/machinery/computer/cryopod/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	if(!operable())
		return TRUE
	tgui_interact(user)
	return TRUE

CAPABILITIES(/obj/machinery/computer/cryopod)
	interface("CryoStorage")
	ui_shape(allow_items = bool(), real_name = schema_text(), crew = list_of(schema_text()), items = list_of(schema_text()))
	op("open_ui_impl", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_open_ui_impl)))

/obj/machinery/computer/cryopod/ui_title(mob/user)
	return storage_name

/obj/machinery/computer/cryopod/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()

	data["real_name"] = user.real_name
	data["crew"] = (frozen_crew || list())

	var/list/items = list()
	if(allow_items)
		for(var/F in frozen_items)
			items.Add(F)
			/* 
			items.Add(list(list(
				"name" = "[F]",
				"ref" = REF(F),
			)))
			*/
	data["items"] = items

	data["allow_items"] = allow_items
	return data

/obj/item/circuitboard/cryopodcontrol
	name = T_BOARD("Cryogenic Oversight Console")
	build_path = /obj/machinery/computer/cryopod
	hidden = TRUE // todo - Make properly constructable in round

/obj/item/circuitboard/robotstoragecontrol
	name = T_BOARD("Robotic Storage Console")
	build_path = /obj/machinery/computer/cryopod/robot
	hidden = TRUE // todo - Make properly constructable in round

/obj/item/circuitboard/dormscontrol
	name = T_BOARD("Residential Oversight Console")
	build_path = /obj/machinery/computer/cryopod/dorms
	hidden = TRUE // todo - Make properly constructable in round

/obj/item/circuitboard/travelcontrol
	name = T_BOARD("Travel Oversight Console - Docks")
	build_path = /obj/machinery/computer/cryopod/travel
	hidden = TRUE // todo - Make properly constructable in round

/obj/item/circuitboard/gatewaycontrol
	name = T_BOARD("Travel Oversight Console - Gateway")
	build_path = /obj/machinery/computer/cryopod/gateway
	hidden = TRUE // todo - Make properly constructable in round

//Decorative structures to go alongside cryopods.
/obj/structure/cryofeed

	name = "cryogenic feed"
	desc = "A bewildering tangle of machinery and pipes."
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "cryo_rear"
	anchored = TRUE
	dir = WEST
	density = TRUE

//Cryopods themselves.
/// Derived field: the pod holds someone. The occupant slot's link/unlink raises
/// CHANGE_RELATION_ADDED/REMOVED on the pod (the occupant slot link).
/obj/machinery/cryopod/proc/cryopod_occupied()
	return slot_item(OCCUPANT_SLOT_CRYOPOD) ? TRUE : FALSE

/obj/machinery/cryopod
	name = "cryogenic freezer"
	desc = "A man-sized pod for entering suspended animation."
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "cryopod_0"
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	dir = WEST
	flags = REMOTEVIEW_ON_ENTER

	var/base_icon_state = "cryopod_0" // New Icon
	var/occupied_icon_state = "cryopod_1" // New Icon
	var/on_store_message = "has entered long-term storage."
	var/on_store_name = "Cryogenic Oversight"
	var/on_enter_visible_message = "starts climbing into the"
	var/on_enter_occupant_message = "You feel cool air surround you. You go numb as your senses turn inward."
	var/on_store_visible_message_1 = "hums and hisses as it moves" //We need two variables because byond doesn't let us have variables inside strings at compile-time.
	var/on_store_visible_message_2 = "into storage."
	var/announce_channel = "Common"
	var/allow_occupant_types = list(/mob/living/carbon/human)
	var/list/disallow_occupant_types

	var/time_till_despawn = 60 // Down to 1 minute to reflect respawn times. //Now 6 seconds. Mind the deciseconds.
	EXPIRY_DECLARE(time_entered) // Used to keep track of the safe period.
	var/obj/item/radio/intercom/announce //

	var/obj/machinery/computer/cryopod/control_computer
	COOLDOWN_DECLARE(no_computer_message_cooldown)
	var/applies_stasis = 0 // allow people to change their mind

	var/quiet = FALSE // No announcement.
/obj/machinery/cryopod/robot
	name = "robotic storage unit"
	desc = "A storage unit for robots."
	icon = 'icons/obj/robot_storage.dmi'
	icon_state = "pod_0"
	base_icon_state = "pod_0"
	occupied_icon_state = "pod_1"
	on_store_message = "has entered robotic storage."
	on_store_name = "Robotic Storage Oversight"
	on_enter_occupant_message = "The storage unit broadcasts a sleep signal to you. Your systems start to shut down, and you enter low-power mode."
	allow_occupant_types = list(/mob/living/silicon/robot)
	// disallow_occupant_types = list(/mob/living/silicon/robot/drone) // Removal - Why? How else do they leave?
	applies_stasis = 0

/obj/machinery/cryopod/robot/door
	//This inherits from the robot cryo, so synths can be properly cryo'd.  If a non-synth enters and is cryo'd, ..() is called and it'll still work.
	name = "Airlock of Wonders"
	desc = "An airlock that isn't an airlock, and shouldn't exist.  Yell at a coder/mapper."
	icon = 'icons/obj/doors/doorint.dmi'
	icon_state = "door_open"
	base_icon_state = "door_open"
	occupied_icon_state = "door_closed"
	on_enter_visible_message = "steps into the"

	time_till_despawn = 600 //1 minute. We want to be much faster then normal cryo, since waiting in an elevator for half an hour is a special kind of hell.

	allow_occupant_types = list(/mob/living/silicon/robot,/mob/living/carbon/human)
	disallow_occupant_types = list(/mob/living/silicon/robot/drone)

/obj/machinery/cryopod/robot/door/dorms
	name = "Residential District Elevator"
	desc = "A small elevator that goes down to the deeper section of the colony."
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "lift_closed"
	base_icon_state = "lift_open"
	occupied_icon_state = "lift_closed"
	on_store_message = "has departed for the residential district."
	on_store_name = "Residential Oversight"
	on_enter_occupant_message = "The elevator door closes slowly, ready to bring you down to the residential district."
	on_store_visible_message_1 = "makes a ding as it moves"
	on_store_visible_message_2 = "to the residential district."

/obj/machinery/cryopod/robot/door/travel
	name = "Passenger Elevator"
	desc = "A small elevator that goes down to the passenger section of the vessel."
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "lift_closed"
	base_icon_state = "lift_open"
	occupied_icon_state = "lift_closed"
	on_store_message = "is slated to depart from the colony."
	on_store_name = "Travel Oversight"
	on_enter_occupant_message = "The elevator door closes slowly, ready to bring you down to the hell that is economy class travel."
	on_store_visible_message_1 = "makes a ding as it moves"
	on_store_visible_message_2 = "to the passenger deck."

/obj/machinery/cryopod/robot/door/gateway
	on_store_name = "Travel Oversight"
	on_store_visible_message_1 = "'s portal disappears just after"
	on_store_visible_message_2 = "finishes walking across it."

	time_till_despawn = 60 //1 second, because gateway.

// C8a: the occupant's a sealed slot (containment.md §10); phase 3 spills it
// through the ledger's drop policy, so this (phase 2, while the slot still
// holds them) keeps the pre-eject "let them fall asleep, not collapse" behaviour.
/obj/machinery/cryopod/lifecycle_dematerialize()
	var/mob/occupant = slot_item(OCCUPANT_SLOT_CRYOPOD)
	if(occupant)
		occupant.set_resting(1)
	..()

/// Sealed: cryosleep is its own environment, same as before (a mob whose loc
/// became the pod took no heat or damage path either way).
/datum/om/relation/slot/occupant/cryopod
	holder = /obj/machinery/cryopod
	slot_id = OCCUPANT_SLOT_CRYOPOD
	name = "cryopod"
	// The slot IS the occupant: read it with SLOT_ITEM(holder, slot_id).

/obj/machinery/cryopod/Initialize(mapload)
	. = ..()

	find_control_computer()

/obj/machinery/cryopod/proc/find_control_computer(urgent=0)
	rel_clear(src, nameof(control_computer))

	var/area/my_area = get_area(src)
	rel_set(src, nameof(control_computer), locate_in_area(my_area, /obj/machinery/computer/cryopod))
	if(!control_computer()) //Fallback to old method.
		rel_set(src, nameof(control_computer), locate_in_list(range(6,src), /obj/machinery/computer/cryopod))

	// Don't send messages unless we *need* the computer, and less than five minutes have passed since last time we messaged
	if(!control_computer() && urgent && COOLDOWN_FINISHED(src, no_computer_message_cooldown))
		log_admin("Cryopod in [my_area] could not find control computer!")
		message_admins("Cryopod in [my_area] could not find control computer!")
		COOLDOWN_START(src, no_computer_message_cooldown, 5 MINUTES)

	return control_computer() != null

/obj/machinery/cryopod/proc/check_occupant_allowed(mob/M)
	var/correct_type = 0
	for(var/type in allow_occupant_types)
		if(istype(M, type))
			correct_type = 1
			break

	if(!correct_type) return 0

	for(var/type in disallow_occupant_types)
		if(istype(M, type))
			return 0

	return 1

//Lifted from Unity stasis.dm and refactored. ~Zuhayr
// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/cryopod)
	started_work(step = PROC_REF(work_step), starts = TRUE, gate = PROC_REF(cryopod_occupied))
	op("cryopod_insert_grab", item(/obj/item/grab), priority(OP_PRIORITY_DEFAULT - 1), label("Put grabbed victim in"), needs(req(PROC_REF(can_take_occupant_holds), because = PROC_REF(can_take_occupant_refusal))), then(PROC_REF(interaction_insert_grab)))
	op("cryopod_eject", menu(), label("Eject Pod"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_eject)))
	op("cryopod_enter", menu(), label("Enter Pod"), needs(req_adjacent(), req_capable(), req(PROC_REF(self_entry_allowed), silent = TRUE), req(PROC_REF(can_enter_holds), because = PROC_REF(can_enter_refusal))), starts(PROC_REF(self_entry_started)), wait(2 SECONDS), then(PROC_REF(interaction_enter)))
	op("cryopod_drag_in", item(/mob), gesture(GESTURE_DRAG), priority(OP_PRIORITY_DEFAULT - 1), label("Put in pod"), then(PROC_REF(interaction_drag_in)))
	// The loader's two seconds with somebody, started once the passenger has consented (finish_go_in).
	op("cryopod_load", ai(), takes("passenger"), wait(2 SECONDS), then(PROC_REF(loaded)))

/obj/machinery/cryopod/proc/work_step(datum/act/timer/A)
	var/mob/occupant = src?.slot_item(OCCUPANT_SLOT_CRYOPOD)
	if(occupant)
		if(occupant.loc != src)
			go_out(TRUE)
			return
		//Allow a ten minute gap between entering the pod and actually despawning.
		if(ELAPSED(src, time_entered, CLOCK_WORLD) < time_till_despawn)
			return

		if(!occupant.client && occupant.stat<2) //Occupant is living and has no client.
			if(!control_computer())
				if(!find_control_computer(urgent=1))
					return

			despawn_occupant(occupant)

// This function can not be undone; do not call this unless you are sure
// Also make sure there is a valid control computer
/obj/machinery/cryopod/robot/despawn_occupant(mob/to_despawn)
	var/mob/living/silicon/robot/R = to_despawn
	if(!istype(R)) return ..()

	rel_clear(R, nameof(R.mmi), OWN_DELETE)
	for(var/obj/item/I in R.module) // the tools the borg has; metal, glass, guns etc
		for(var/mob/M in I)
			despawn_occupant(M)
		for(var/obj/item/O in I) // the things inside the tools, if anything; mainly for janiborg trash bags
			O.forceMove(R)
		spent(I)
	rel_clear(R, nameof(R.module))

	return ..()

/obj/machinery/cryopod/robot/door/gateway/despawn_occupant()
	for(var/obj/machinery/gateway/G in range(1,src))
		G.icon_state = "off"
	..()

// This function can not be undone; do not call this unless you are sure
// Also make sure there is a valid control computer
/obj/machinery/cryopod/proc/despawn_occupant(mob/to_despawn)

	for(var/mob/M in to_despawn)
		despawn_occupant(M)

	persist_despawned_mob(to_despawn, src)
	if(isliving(to_despawn))
		var/mob/living/L = to_despawn
		for(var/obj/belly/B as anything in L.vore_organs)
			for(var/mob/living/sub_L in B)
				despawn_occupant(sub_L)
			for(var/obj/item/W in B)
				W.forceMove(src)
				if(contents_count(W))
					for(var/obj/item/O in contents_of(W))
						if(istype(O,/obj/item/storage/internal))
							continue
						O.forceMove(src)
		if(ishuman(to_despawn))
			var/mob/living/carbon/human/H = to_despawn
			if(H.nif)
				var/datum/nifsoft/soulcatcher/SC = H.nif.imp_check(NIF_SOULCATCHER)
				if(SC)
					for(var/bm in SC.brainmobs)
						despawn_occupant(bm)

	//Drop all items into the pod.
	for(var/obj/item/W in to_despawn)
		if(istype(W,/obj/item/organ))
			continue
		to_despawn.drop_from_inventory(W)
		W.forceMove(src)

		if(contents_count(W)) //Make sure we catch anything not handled by qdel() on the items.
			for(var/obj/item/O in contents_of(W))
				if(istype(O,/obj/item/storage/internal)) //Stop eating pockets, you fuck!
					continue
				O.forceMove(src)

	//Delete all items not on the preservation list.
	var/list/items = contents.Copy()
	items -= to_despawn // Don't delete the occupant
	items -= announce // or the autosay radio.

	for(var/obj/item/W in items)
		if(islist(W.possessed_voice))
			for(var/mob/living/V in W.possessed_voice) // Revert temporary patch
				// Don't try and despawn, instead just ghost and delete, same as item destruction
				V.ghostize(0)
				spent(V)
		// ition Start
		if(istype(W, /obj/item/pda))
			var/obj/item/pda/found_pda = W
			found_pda.delete_id = TRUE
		else
			var/list/pdas_found = W.search_contents_for(/obj/item/pda)
			if(pdas_found.len)
				for(var/obj/item/pda/found_pda in pdas_found)
					found_pda.delete_id = TRUE
		// ition End

		var/preserve = 0

		if(W.preserve_item)
			preserve = 1

		if(istype(W,/obj/item/implant/health))
			for(var/obj/machinery/computer/cloning/com in REGISTRY_MEMBERS(REGISTRY_MACHINES))
				for(var/datum/dna2/record/R in com.records)
					if(locate(R.implant) == W)
						spent(R)
						spent(W)

		if(!preserve)
			spent(W)
		else
			log_special_item(W,to_despawn)
			/* We do our own thing.
			if(control_computer() && control_computer().allow_items)
				LAZYADD(control_computer().frozen_items, W)
				W.loc = control_computer()
			else
				W.forceMove(src.loc)
			*/
	for(var/obj/structure/B in items)
		if(istype(B,/obj/structure/bed))
			spent(B)

	//Update any existing objectives involving this mob.
	for(var/datum/objective/O in REGISTRY_MEMBERS(REGISTRY_OBJECTIVES))
		// We don't want revs to get objectives that aren't for heads of staff. Letting
		// them win or lose based on cryo is silly so we remove the objective.
		if(O.target == to_despawn.mind)
			if(O.owner && O.owner.current)
				to_chat(O.owner.current, span_warning("You get the feeling your target is no longer within your reach..."))
			spent(O)

	// Resleeving.
	if(to_despawn.mind)
		SStranscore.leave_round(to_despawn)
	// Resleeving.

		// Everything below should only be applicable to a cliented living/carbon/human.
		// All living/carbon/humans should have minds.

		//Handle job slot/tater cleanup.
		var/job = to_despawn.mind.assigned_role
		SSjob.free_role(job)
		to_despawn.mind.assigned_role = null

		if(to_despawn.mind.objectives.len)
			rel_clear(to_despawn.mind, nameof(/datum/mind::objectives))
			to_despawn.mind.special_role = null

		// Delete them from datacore.

		if(GLOB.PDA_Manifest.len)
			GLOB.PDA_Manifest.Cut()
		for(var/datum/data/record/R in GLOB.data_core.medical)
			if((R.fields["name"] == to_despawn.real_name))
				spent(R)
		for(var/datum/data/record/T in GLOB.data_core.security)
			if((T.fields["name"] == to_despawn.real_name))
				spent(T)
		for(var/datum/data/record/G in GLOB.data_core.general)
			if((G.fields["name"] == to_despawn.real_name))
				spent(G)

		// Also check the hidden version of each datacore, if they're an offmap role.
		var/datum/job/J = SSjob.get_job(job)
		if(J?.offmap_spawn)
			for(var/datum/data/record/R in GLOB.data_core.hidden_general)
				if((R.fields["name"] == to_despawn.real_name))
					spent(R)
			for(var/datum/data/record/T in GLOB.data_core.hidden_security)
				if((T.fields["name"] == to_despawn.real_name))
					spent(T)
			for(var/datum/data/record/G in GLOB.data_core.hidden_medical)
				if((G.fields["name"] == to_despawn.real_name))
					spent(G)

		icon_state = base_icon_state

		//TODO: Check objectives/mode, update new targets if this mob is the target, spawn new antags?

		//Make an announcement and log the person entering storage.
		var/obj/machinery/computer/cryopod/log_console = control_computer()
		LAZYADD(log_console.frozen_crew, "[to_despawn.real_name], [to_despawn.mind.role_alt_title] - [stationtime2text()]") // strings
		LAZYADD(log_console._admin_logs, "[key_name(to_despawn)] ([to_despawn.mind.role_alt_title]) at [stationtime2text()]")
		log_and_message_admins("([to_despawn.mind.role_alt_title]) entered cryostorage.", to_despawn)

		var/depart_announce = TRUE
		var/departing_job = to_despawn.mind.role_alt_title

		if(istype(to_despawn, /mob/living/dominated_brain))
			depart_announce = FALSE

		if(src.quiet) // No announcement.
			depart_announce = FALSE

		if(depart_announce)
			announce.autosay("[to_despawn.real_name][departing_job ? ", [departing_job], " : " "][on_store_message]", "[on_store_name]", announce_channel, using_map.get_map_levels(z, TRUE, om_range = DEFAULT_OVERMAP_RANGE))
			visible_message(span_notice("\The [initial(name)] [on_store_visible_message_1] [to_despawn.real_name] [on_store_visible_message_2]"), 3)

	// begin: Dont delete mobs-in-mobs
	if(to_despawn.client && to_despawn.stat<2)
		var/mob/observer/dead/newghost = to_despawn.ghostize()
		EXPIRY_STAMP(newghost, timeofdeath, CLOCK_WORLD)
	// end: Dont delete mobs-in-mobs

	//This should guarantee that ghosts don't spawn.
	to_despawn.ckey = null

	// Delete the mob.
	spent(to_despawn)
	set_occupant(null)

/// Requirement (was REQ_* can_take_occupant): the legacy check answers TRUE to pass.
/obj/machinery/cryopod/proc/can_take_occupant_holds(datum/act/op/A)
	var/answer = can_take_occupant(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_take_occupant_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/cryopod/proc/can_take_occupant_refusal(datum/act/op/A)
	var/answer = can_take_occupant(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/// Requirement (was REQ_* can_enter): the legacy check answers TRUE to pass.
/obj/machinery/cryopod/proc/can_enter_holds(datum/act/op/A)
	var/answer = can_enter(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_enter_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/cryopod/proc/can_enter_refusal(datum/act/op/A)
	var/answer = can_enter(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/// Requirement: the pod must be empty.
/obj/machinery/cryopod/proc/can_take_occupant(mob/user, atom/target, obj/item/held)
	if(slot_occupant(OCCUPANT_SLOT_CRYOPOD))
		return "it's in use"
	return TRUE

/// Requirement for climbing in: TRUE, or why the user can't.
/obj/machinery/cryopod/proc/can_enter(mob/user, atom/target, obj/item/held)
	if(!check_occupant_allowed(user))
		return TRUE // the effect declines silently
	if(slot_occupant(OCCUPANT_SLOT_CRYOPOD))
		return "it's in use"
	if(isliving(user))
		var/mob/living/L = user
		if(L.has_buckled_mobs())
			return "you have other entities attached to yourself, remove them first"
	return TRUE

/obj/machinery/cryopod/proc/interaction_insert_grab(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/grab/grab = A.held
	if(!ismob(grab?.grab_target()))
		return OP_OK
	go_in(grab?.grab_target(), user)
	return OP_OK

/obj/machinery/cryopod/proc/interaction_eject(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/occupant = src?.slot_item(OCCUPANT_SLOT_CRYOPOD)
	icon_state = base_icon_state

	//Eject any items that aren't meant to be in the pod.
	var/list/items = contents
	if(occupant) items -= occupant
	if(announce) items -= announce

	for(var/obj/item/W in items)
		W.forceMove(get_turf(src))

	for(var/obj/structure/bed/S in slot_contents())
		S.forceMove(get_turf(src))

	go_out()
	add_fingerprint(user)

	name = initial(name)
	return TRUE

/obj/machinery/cryopod/proc/self_entry_allowed(datum/act/op/A)
	return read_once(check_occupant_allowed(A.actor))

/obj/machinery/cryopod/proc/self_entry_started(datum/act/op/A)
	act_message(A.actor, src, others = "%U% [on_enter_visible_message] %T%.")

/obj/machinery/cryopod/proc/interaction_enter(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/occupant = src?.slot_item(OCCUPANT_SLOT_CRYOPOD)
	if(!user || !user.client)
		return TRUE

	if(occupant)
		to_chat(user, span_boldnotice("\The [src] is in use."))
		return TRUE

	user.stop_pulling()
	if(!move_into(src, OCCUPANT_SLOT_CRYOPOD, user, user))
		return TRUE
	set_occupant(user)
	if(isliving(user) && applies_stasis)
		var/mob/living/L = user
		L.set_stasis(/datum/body_effect/stasis/total, src)
	if(user?.buckled_to() && istype(user?.buckled_to(), /obj/structure/bed/chair/wheelchair))
		var/atom/movable/_tmp_buck_6 = user?.buckled_to()
		_tmp_buck_6.forceMove(user.loc)

	icon_state = occupied_icon_state

	to_chat(user, span_notice("[on_enter_occupant_message]"))
	to_chat(user, span_boldnotice("If you ghost, log out or close your client now, your character will shortly be permanently removed from the round."))

	EXPIRY_STAMP(src, time_entered, CLOCK_WORLD)

	add_fingerprint(user)
	return TRUE

/obj/machinery/cryopod/proc/interaction_drag_in(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/target = A.held
	if(user.stat || user.lying || !Adjacent(user) || !target.Adjacent(user))
		return OP_OK
	go_in(target, user)
	return OP_OK

/obj/machinery/cryopod/robot/door/gateway/self_entry_started(datum/act/op/A)
	. = ..()
	for(var/obj/machinery/gateway/G in range(1,src))
		G.icon_state = "on"
	return .

/obj/machinery/cryopod/robot/door/gateway/go_out(skip_move = FALSE)
	..(skip_move)
	for(var/obj/machinery/gateway/G in range(1,src))
		G.icon_state = "off"

/obj/machinery/cryopod/proc/go_out(skip_move = FALSE)
	var/mob/occupant = src?.slot_item(OCCUPANT_SLOT_CRYOPOD)

	if(!occupant)
		return

	if(!skip_move)
		slot_remove(occupant, get_turf(src))
	if(isliving(occupant) && applies_stasis)
		var/mob/living/L = occupant
		L.set_stasis(null, src)
	set_occupant(null)

	icon_state = base_icon_state

	return

/obj/machinery/cryopod/proc/set_occupant(mob/new_occupant)
	var/mob/occupant = src?.slot_item(OCCUPANT_SLOT_CRYOPOD)
	name = initial(name)
	if(occupant)
		name = "[name] ([occupant])"

/obj/machinery/cryopod/proc/go_in(mob/M, mob/user)
	var/mob/occupant = src?.slot_item(OCCUPANT_SLOT_CRYOPOD)
	if(!check_occupant_allowed(M))
		return
	if(!M)
		return
	if(occupant)
		to_chat(user, span_warning("\The [src] is already occupied."))
		return

	if(M.client)
		open_request(src, /datum/prompt/yes_no/cryo_consent, PROC_REF(storage_consent_answered), answerer = M, title = "Cryopod", question = "Would you like to enter long-term storage?", loader = user, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)
		return
	finish_go_in(M, user, 1)

/// Consent to long-term storage: whoever loaded the pod is kept on the question.
/datum/prompt/yes_no/cryo_consent
	var/mob/loader

CAPABILITIES(/datum/prompt/yes_no/cryo_consent)
	ref_one(nameof(loader), /mob)

/obj/machinery/cryopod/proc/storage_consent_answered(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/datum/prompt/yes_no/cryo_consent/R = A.request
	finish_go_in(R.answerer, R.loader, TRUE)

/obj/machinery/cryopod/proc/finish_go_in(mob/M, mob/user, willing)

	if(willing)
		if(M == user)
			act_message(user, src, others = "%U% [on_enter_visible_message] %T%.")
		else
			act_message(user, M, others = "%U% starts putting %T% into \the [src].")

		perform_op(user, src, "cryopod_load", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("passenger" = M))

/obj/machinery/cryopod/proc/go_in_finish(mob/M, mob/user)
	icon_state = occupied_icon_state

	to_chat(M, span_notice("[on_enter_occupant_message]"))
	to_chat(M, span_boldnotice("If you ghost, log out or close your client now, your character will shortly be permanently removed from the round."))
	set_occupant(M)
	EXPIRY_STAMP(src, time_entered, CLOCK_WORLD)
	if(isliving(M) && applies_stasis)
		var/mob/living/L = M
		L.set_stasis(/datum/body_effect/stasis/total, src)
	if(M?.buckled_to() && istype(M?.buckled_to(), /obj/structure/bed/chair/wheelchair))
		var/atom/movable/_tmp_buck_7 = M?.buckled_to()
		_tmp_buck_7.forceMove(M.loc)

	// Book keeping!
	var/turf/location = get_turf(src)
	log_admin("[key_name_admin(M)] has entered a stasis pod. (<A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[location.x];Y=[location.y];Z=[location.z]'>JMP</a>)")
	message_admins(span_notice("[key_name_admin(M)] has entered a stasis pod."))

	//Despawning occurs when process() is called with an occupant without a client.
	add_fingerprint(M)

/obj/machinery/cryopod/proc/loaded(datum/act/op/A)
	var/mob/M = A.arg("passenger")
	var/mob/user = A.actor
	if(QDELETED(M))
		return OP_FAILED
	var/mob/occupant = src?.slot_item(OCCUPANT_SLOT_CRYOPOD)
	if(occupant)
		to_chat(user, span_warning("\The [src] is already occupied."))
		return OP_FAILED
	if(!move_into(src, OCCUPANT_SLOT_CRYOPOD, M, user))
		to_chat(user, span_warning("\The [src] won't take [M]."))
		return OP_FAILED
	go_in_finish(M, user)
	return OP_OK

//Overrides!

/obj/machinery/cryopod
	// The corresponding spawn point type that user despawning here will return at next round.
	// Note: We use a type instead of name so that its validity is checked at compile time.
	var/spawnpoint_type = /datum/spawnpoint/cryo

/obj/machinery/cryopod/robot
	spawnpoint_type = /datum/spawnpoint/cyborg

// Used at centcomm for the elevator
/obj/machinery/cryopod/robot/door/dorms
	spawnpoint_type = /datum/spawnpoint/tram

///Door specifically for a site in tether. Or other places that uses a 2x1 glass door.
/obj/machinery/cryopod/robot/door/dorms/tether_glass
	name = "elevator"
	desc = "A small elevator"
	base_icon_state = "door_closed"
	icon = 'icons/obj/doors/Door2x1glass.dmi'
	icon_state = "door_closed"
	on_enter_occupant_message = "The elevator doors close slowly. You can now head off for the residential, commercial, and other floors.";
	on_store_message = "has departed for one of the various colony floors"
	on_store_name = "Colony Oversight"
	on_store_visible_message_2 = "to the colony districts."
	time_till_despawn = 5

/obj/machinery/cryopod/robot/door/gateway
	name = "public teleporter"
	desc = "The short-range teleporter you might've came in from. You could leave easily using this."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "tele0"
	base_icon_state = "tele0"
	occupied_icon_state = "tele1"
	on_store_message = "has departed via short-range teleport."
	on_enter_occupant_message = "The teleporter activates, and you step into the swirling portal."
	spawnpoint_type = /datum/spawnpoint/gateway

/obj/machinery/computer/cryopod/gateway
	name = "teleport oversight console"
	desc = "An interface between visitors and the teleport oversight systems tasked with keeping track of all visitors who enter or exit from the teleporters."
/* 
/obj/machinery/cryopod/robot/door/dorms
	desc = "A small elevator that goes down to the residential district."
	on_enter_occupant_message = "The elevator door closes slowly, ready to bring you down to the residential district."
	spawnpoint_type = /datum/spawnpoint/elevator

/obj/machinery/computer/cryopod/dorms
	name = "residential oversight console"
	desc = "An interface between visitors and the residential oversight systems tasked with keeping track of all visitors in the residential district."
*/

/obj/machinery/cryopod/proc/log_special_item(atom/movable/item,mob/to_despawn)
	ASSERT(item && to_despawn)

	var/loaded_from_key
	var/char_name = to_despawn.name
	var/item_name = item.name

	// Best effort key aquisition
	if(ishuman(to_despawn))
		var/mob/living/carbon/human/H = to_despawn
		if(H.original_player)
			loaded_from_key = H.original_player

	if(!loaded_from_key && to_despawn.mind && to_despawn.mind.loaded_from_ckey)
		loaded_from_key = to_despawn.mind.loaded_from_ckey

	else
		loaded_from_key = "INVALID"

	// Log to harrass them later
	log_game("CRYO [loaded_from_key]/([to_despawn.name]) cryo'd with [item_name] ([item.type])")
	spent(item)

	if(control_computer() && control_computer().allow_items)
		var/obj/machinery/computer/cryopod/log_console = control_computer()
		LAZYADD(log_console.frozen_items, "[item_name] ([char_name])") // strings

/obj/machinery/cryopod/robot/door/gateway/quiet
	name = "departure teleporter"
	desc = "The short-range teleporter you might've came in from. You could leave easily using this."
	quiet = TRUE

/obj/machinery/cryopod/robot/door/dorms/quiet
	name = "departure airlock"
	desc = "A secured airlock you might've come in from. You could leave easily using this."
	quiet = TRUE

/obj/machinery/cryopod/ownership()
	. = ..()
	. += owns(nameof(announce), policy = OWN_CONTAINED, starts = /obj/item/radio/intercom)

/// control computer (a relation view: it reads null once the target is deleted).
/obj/machinery/cryopod/proc/control_computer() as /obj/machinery/computer/cryopod
	return control_computer
