/obj/item/mmi
	name = "man-machine interface"
	desc = "The Warrior's bland acronym, MMI, obscures the true horror of this monstrosity."
	icon = 'icons/obj/assemblies.dmi'
	icon_state = "mmi_empty"
	w_class = ITEMSIZE_NORMAL
	can_speak = 1

	req_access = list(ACCESS_ROBOTICS)

	// The occupant (the mind's view mob) belongs to this MMI's mind host
	// component (code/datums/components/mind_host.dm); its status is read from
	// `brainobj` when there is one.

	var/locked = 0
	var/obj/item/organ/internal/brain/brainobj = null	//The current brain organ.
	var/obj/mecha = null//This does not appear to be used outside of reference in mecha.dm.
	var/obj/item/radio/headset/mmi_radio/radio = null//Let's give it a radio.
	var/mob/living/body_backup = null //add reforming

	///Var for attack_self chain
	var/special_handling = FALSE

/obj/item/mmi/Initialize(mapload)
	. = ..()
	radio = new(src)//Spawns a radio inside the MMI.
	AddComponent(/datum/component/mind_host)

/// The occupant view mob (the hosted mind lives there), if any.
/obj/item/mmi/proc/get_occupant()
	return hosted_view()

/// Seat `B` as this MMI's brain tissue: the occupant's status reads it.
/obj/item/mmi/proc/set_brain(obj/item/organ/internal/brain/B)
	brainobj = B
	if(B)
		B.preserved = TRUE
		if(B.loc != src)
			B.forceMove(src)
	var/datum/component/mind_host/host = get_mind_host(src)
	host?.set_tissue(B)

/// Make this MMI hold `L`'s character (by reference). With `move_mind`, `L`'s
/// mind comes along too; otherwise the mind is expected elsewhere (a borg).
/obj/item/mmi/proc/take_identity(mob/living/L, move_mind = FALSE)
	var/datum/component/mind_host/host = get_mind_host(src)
	var/mob/living/carbon/brain/view = host.receive_mind(move_mind ? L.mind : null, "[L] placed into [src]")
	view.bind_identity(L.mind ? L.mind.get_identity() : L.identity)
	update_occupied_state()
	return view

/// Name and icon for the MMI's current occupancy.
/obj/item/mmi/proc/update_occupied_state()
	var/mob/living/carbon/brain/view = get_occupant()
	if(!view)
		name = initial(name)
		icon_state = "mmi_empty"
		return
	name = "[initial(name)] ([view.real_name])"
	icon_state = "mmi_full"
	locked = 1

/obj/item/mmi/verb/toggle_radio()
	set name = "Toggle Brain Radio"
	set desc = "Enables or disables the integrated brain radio, which is only usable outside of a body."
	set category = "Object"
	set src in usr
	set popup_menu = 1
	if(!usr.canmove || usr.stat || usr.restrained())
		return 0

	if (radio.radio_enabled == 1)
		radio.radio_enabled = 0
		to_chat (usr, "You have disabled the [src]'s radio.")
		to_chat (get_occupant(), "Your radio has been disabled.")
	else if (radio.radio_enabled == 0)
		radio.radio_enabled = 1
		to_chat (usr, "You have enabled the [src]'s radio.")
		to_chat (get_occupant(), "Your radio has been enabled.")
	else
		to_chat (usr, "You were unable to toggle the [src]'s radio.")

/obj/item/mmi/attackby(obj/item/O as obj, mob/user as mob)
	var/mob/living/carbon/brain/occupant = get_occupant()
	// An empty view with no brain behind it (left after its mind was released) doesn't block a new brain.
	if(istype(O,/obj/item/organ/internal/brain) && (!occupant || (!occupant.mind && !brainobj))) //Time to stick a brain in it --NEO
		var/obj/item/organ/internal/brain/B = O
		if(B.is_brain_dead())
			to_chat(user, span_warning("That brain is well and truly dead."))
			return
		var/mob/living/carbon/brain/view = B.hosted_view()
		if(!view)
			to_chat(user, span_warning("You aren't sure where this brain came from, but you're pretty sure it's useless."))
			return
		if(view.identity.has_genetic_modifier(/datum/modifier/no_borg))	//Can't be shoved in an MMI.
			to_chat(user, span_warning("\The [src] appears to reject this brain.  It is incompatible."))
			return

		user.visible_message(span_infoplain(span_bold("\The [user]") + " sticks \a [O] into \the [src]."))
		user.drop_item()
		insert_brain(B, "brain placed in [src] by [key_name(user)]")

		feedback_inc("cyborg_mmis_filled",1)

		return

	if((istype(O,/obj/item/card/id)||istype(O,/obj/item/pda)) && occupant)
		if(allowed(user))
			locked = !locked
			to_chat(user, span_notice("You [locked ? "lock" : "unlock"] the brain holder."))
		else
			to_chat(user, span_warning("Access denied."))
		return
	if(occupant)
		O.attack(occupant, user)//Oh noooeeeee
		return
	..()

/// Seat a removed brain: the organ becomes the tissue and its view (with the
/// mind) moves into this MMI. Nothing is copied.
/obj/item/mmi/proc/insert_brain(obj/item/organ/internal/brain/B, reason = "brain inserted")
	var/datum/component/mind_host/host = get_mind_host(src)
	if(host.occupant && !host.occupant.mind && !brainobj)
		log_game("MIND: [src] discarded its empty view to seat [B]: [reason]")
		host.discard_occupant()
	set_brain(B)
	host.adopt_occupant(get_mind_host(B), reason)
	update_occupied_state()

/obj/item/mmi/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(special_handling)
		return FALSE
	if(!get_occupant())
		to_chat(user, span_warning("You upend the MMI, but there's nothing in it."))
	else if(locked)
		to_chat(user, span_warning("You upend the MMI, but the brain is clamped into place."))
	else
		to_chat(user, span_notice("You upend the MMI, spilling the brain onto the floor."))
		eject_brain(get_turf(user), "spilled from [src] by [key_name(user)]")

/// Take the brain organ out; the occupant (and its mind) goes with it. The
/// organ keeps its lesions, so damage and treatment carry on.
/obj/item/mmi/proc/eject_brain(atom/destination, reason = "ejected")
	var/obj/item/organ/internal/brain/brain = brainobj
	if(!brain)	// An MMI filled without an organ (borging) grows one to carry the mind.
		brain = new(destination)
	brain.preserved = FALSE
	if(!destination)
		destination = drop_location()
	if(destination)
		brain.forceMove(destination)
	else
		brain.moveToNullspace()
	// The view moves to the organ before the MMI lets go of its tissue, so it is never tissue-less.
	var/datum/component/mind_host/brain_host = get_mind_host(brain)
	brain_host.adopt_occupant(get_mind_host(src), reason)
	set_brain(null)
	update_occupied_state()
	return brain

/obj/item/mmi/relaymove(mob/user, direction)
	if(user.stat || user.get_stunned())
		return
	var/obj/item/rig/rig = src.get_rig()
	if(rig)
		if(istype(rig,/obj/item/rig))
			rig.forced_move(direction, user)

/obj/item/mmi/Destroy()
	if(body_backup)
		qdel(body_backup)
	if(isrobot(loc))
		var/mob/living/silicon/robot/borg = loc
		borg.mmi = null
	QDEL_NULL(radio)
	// The occupant goes first: deleting the tissue under a live view would kill it for nothing.
	var/datum/component/mind_host/host = get_mind_host(src)
	host?.discard_occupant()
	if(brainobj)
		QDEL_NULL(brainobj)
	return ..()

/obj/item/mmi/radio_enabled
	name = "radio-enabled man-machine interface"
	desc = "The Warrior's bland acronym, MMI, obscures the true horror of this monstrosity. This one comes with a built-in radio. Wait, don't they all?"

/obj/item/mmi/emp_act(severity, recursive)
	. = ..()
	var/mob/living/carbon/brain/occupant = get_occupant()
	if (. & EMP_PROTECT_SELF || !occupant)
		return
	switch(severity)
		if(EMP_HEAVY)
			occupant.emp_damage += rand(20,30)
		if(EMP_MEDIUM)
			occupant.emp_damage += rand(10,20)
		if(EMP_LIGHT)
			occupant.emp_damage += rand(5,10)
		if(EMP_HARMLESS)
			occupant.emp_damage += rand(0,5)

/obj/item/mmi/digital
	var/searching = 0
	var/askDelay = 10 * 60 * 1
	req_access = list(ACCESS_ROBOTICS)
	locked = 0
	mecha = null//This does not appear to be used outside of reference in mecha.dm.
	var/ghost_query_type = null
	var/datum/ghost_query/Q //This is used so we can unregister ourself.
	special_handling = TRUE
	///Var for attack_self chain
	var/is_digital_robot = FALSE

/obj/item/mmi/digital/Initialize(mapload)
	. = ..()
	// A synthetic mind host: an empty view waits for a mind, with no tissue.
	var/datum/component/mind_host/host = get_mind_host(src)
	var/mob/living/carbon/brain/view = host.receive_mind(null, "[src] booted")
//	view.add_language(LANGUAGE_ROBOT_TALK)//No binary without a binary communication device
	view.add_language(LANGUAGE_GALCOM)
	view.add_language(LANGUAGE_EAL)
	view.set_stat(CONSCIOUS)
	view.silent = 0
	GLOB.dead_mob_list -= view

/obj/item/mmi/digital/update_occupied_state()
	return

/obj/item/mmi/digital/attackby(obj/item/O as obj, mob/user as mob)
	return	//Doesn't do anything right now because none of the things that can be done to a regular MMI make any sense for these

/obj/item/mmi/digital/examine(mob/user)
	. = ..()

	var/mob/living/carbon/brain/occupant = get_occupant()
	if(occupant?.key)
		switch(occupant.stat)
			if(CONSCIOUS)
				if(!occupant.client)
					. += span_warning("It appears to be in stand-by mode.") //afk
			if(UNCONSCIOUS)
				. += span_warning("It doesn't seem to be responsive.")
			if(DEAD)
				. += span_deadsay("It appears to be completely inactive.")
	else
		. += span_deadsay("It appears to be completely inactive.")

/obj/item/mmi/digital/take_identity(mob/living/L, move_mind = TRUE)
	. = ..()
	var/mob/living/carbon/brain/view = .
	view.set_stat(CONSCIOUS)

/obj/item/mmi/digital/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(is_digital_robot)
		return FALSE
	var/mob/living/carbon/brain/occupant = get_occupant()
	if(occupant && !occupant.key && searching == 0)
		//Start the process of searching for a new user.
		to_chat(user, span_blue("You carefully locate the manual activation switch and start the [src]'s boot process."))
		request_player()

/obj/item/mmi/digital/proc/request_player()
	if(!ghost_query_type)
		return
	searching = 1

	Q = new ghost_query_type()
	RegisterSignal(Q, COMSIG_GHOST_QUERY_COMPLETE, PROC_REF(get_winner))
	Q.query()

/obj/item/mmi/digital/proc/get_winner()
	SIGNAL_HANDLER
	if(Q && Q.candidates.len) //Q should NEVER get deleted but...whatever, sanity.
		var/mob/observer/dead/D = Q.candidates[1]
		transfer_personality(D)
	else
		reset_search()
	UnregisterSignal(Q, COMSIG_GHOST_QUERY_COMPLETE)
	QDEL_NULL(Q) //get rid of the query

/obj/item/mmi/digital/proc/reset_search() //We give the players sixty seconds to decide, then reset the timer.
	if(get_occupant()?.key)
		return

	src.searching = 0

	var/turf/T = get_turf_or_move(src.loc)
	for (var/mob/M in viewers(T))
		M.show_message(span_blue("\The [src] buzzes quietly, and the golden lights fade away. Perhaps you could try again?"))

/// A ghost becomes this synthetic brain: a new IC character, so the player
/// joins the waiting view and gets a fresh mind (see the mind.dm guidelines).
/obj/item/mmi/digital/proc/transfer_personality(mob/candidate)
	announce_ghost_joinleave(candidate, 0, "They are occupying a synthetic brain now.")
	src.searching = 0
	var/mob/living/carbon/brain/view = get_occupant()
	log_game("MIND: [key_name(candidate)] joined [src] as a new synthetic intelligence")
	view.ckey = candidate.ckey
	src.name = "[name] ([view.name])"
	to_chat(view, span_infoplain(span_bold("You are [src.name], brought into existence on [station_name()].")))
	to_chat(view, span_infoplain(span_bold("As a synthetic intelligence, you are designed with organic values in mind.")))
	to_chat(view, span_infoplain(span_bold("However, unless placed in a lawed chassis, you are not obligated to obey any individual crew member."))) //it's not like they can hurt anyone
	if(view.mind)
		view.mind.assigned_role = JOB_SYNTHETIC_BRAIN

	var/turf/T = get_turf_or_move(src.loc)
	for (var/mob/M in viewers(T))
		M.show_message(span_blue("\The [src] chimes quietly."))

/obj/item/mmi/digital/robot
	name = "robotic intelligence circuit"
	desc = "The pinnacle of artifical intelligence which can be achieved using classical computer science."
	catalogue_data = list(/datum/category_item/catalogue/technology/drone/drones)
	icon = 'icons/obj/module.dmi'
	icon_state = "mainboard"
	w_class = ITEMSIZE_NORMAL
	ghost_query_type = /datum/ghost_query/drone_brain
	is_digital_robot = TRUE

/obj/item/mmi/digital/robot/Initialize(mapload)
	. = ..()
	var/mob/living/carbon/brain/view = get_occupant()
	view.real_name = "[pick(list("ADA","DOS","GNU","MAC","WIN","NJS","SKS","DRD","IOS","CRM","IBM","TEX","LVM","BSD",))]-[rand(1000, 9999)]"
	view.name = view.real_name
	view.identity.real_name = view.real_name
	name = "[initial(name)] ([view.name])"

/obj/item/mmi/digital/robot/take_identity(mob/living/L, move_mind = TRUE)
	. = ..()
	var/mob/living/carbon/brain/view = .
	if(view.mind)
		view.mind.assigned_role = JOB_ROBOTIC_INTELLIGENCE
	to_chat(view, span_notify("You feel slightly disoriented. That's normal when you're little more than a complex circuit."))

/obj/item/mmi/digital/posibrain
	name = "positronic brain"
	desc = "A cube of shining metal, four inches to a side and covered in shallow grooves."
	catalogue_data = list(/datum/category_item/catalogue/technology/positronics)
	icon = 'icons/obj/assemblies.dmi'
	icon_state = "posibrain"
	w_class = ITEMSIZE_NORMAL
	ghost_query_type = /datum/ghost_query/posi_brain

/obj/item/mmi/digital/posibrain/request_player()
	icon_state = "posibrain-searching"
	..()

/obj/item/mmi/digital/posibrain/take_identity(mob/living/L, move_mind = TRUE)
	. = ..()
	var/mob/living/carbon/brain/view = .
	if(view.mind)
		view.mind.assigned_role = JOB_POSITRONIC_BRAIN
	to_chat(view, span_notify("You feel slightly disoriented. That's normal when you're just a metal cube."))
	icon_state = "posibrain-occupied"

/obj/item/mmi/digital/posibrain/transfer_personality(mob/candidate)
	..()
	icon_state = "posibrain-occupied"

/obj/item/mmi/digital/posibrain/reset_search() //We give the players sixty seconds to decide, then reset the timer.
	..()
	icon_state = "posibrain"

/obj/item/mmi/digital/posibrain/Initialize(mapload)
	. = ..()
	var/mob/living/carbon/brain/view = get_occupant()
	view.real_name = "[pick(list("PBU","HIU","SINA","ARMA","OSI"))]-[rand(100, 999)]"
	view.name = view.real_name
	view.identity.real_name = view.real_name

// This type hosts no mind.
/obj/item/mmi/inert

/obj/item/mmi/inert/Initialize(mapload)
	. = ..()
	qdel(GetComponent(/datum/component/mind_host))

// This is a 'fake' MMI that is used to let AIs control borg shells directly.
// This doesn't inherit from /digital because all that does is add ghost pulling capabilities, which this thing won't need.
/obj/item/mmi/inert/ai_remote
	name = "\improper AI remote interface"
	desc = "A sophisticated board which allows for an artificial intelligence to remotely control a synthetic chassis."
	icon = 'icons/obj/module.dmi'
	icon_state = "mainboard"
	w_class = ITEMSIZE_NORMAL
