/*
 * Inflation subtype, Big and round!
 */
/datum/hose_connector/inflation
	flow_direction = HOSE_NEUTRAL
	var/connection_mode = CHEM_INGEST

/datum/hose_connector/inflation/attach(atom/movable/new_carrier, set_unique_name = null)
	if(!ishuman(new_carrier))
		return FALSE
	. = ..()
	revoke(human_owner(), granted_verb(/atom/proc/disconnect_hose), src)

/datum/hose_connector/inflation/on_examine(datum/act/notice/N)
	return

/datum/hose_connector/inflation/proc/get_destination_name()
	switch(connection_mode)
		if(CHEM_INGEST)
			return "mouth"
		if(CHEM_VORE)
			return human_owner()?.vore_selected?.name ? sanitize(human_owner().vore_selected.name) : "belly"
		if(CHEM_BLOOD)
			return "bloodstream"
	return "something"

/datum/hose_connector/inflation/get_id()
	return "\The [human_owner()]'s [get_destination_name()]"

// Adding and removing the verb is more complex on humans... This code also expects only ONE hose connector
/datum/hose_connector/inflation/connect(datum/hose/H)
	. = ..()
	grant(human_owner(), granted_verb(/atom/proc/disconnect_hose), src)

/datum/hose_connector/inflation/remove_hose()
	revoke(human_owner(), granted_verb(/atom/proc/disconnect_hose), src)
	. = ..()

// Succ command center
/// Chooses where the hose goes into the owner, then (a timed action) connects it and calls
/// origin.setup_hoses_finish(target, distancetonode, user, tubing).
/datum/hose_connector/inflation/proc/inflation_setup(mob/user,datum/hose_connector/other, datum/hose_connector/origin, datum/hose_connector/target, distancetonode, obj/item/stack/tubing)
	if(!other || QDELETED(other))
		to_chat(user,span_danger("You couldn't connect the hose, as the connection stopped existing! Ohno!"))
		return FALSE

	// Check for destinations
	var/list/options = list("Mouth")
	if(human_owner().vore_selected)
		options.Add("Belly ([sanitize(human_owner().vore_selected.name)])")
	if(!HAS_SYNTHETIC_BIOLOGY(human_owner())) // Results in a lot of bad behaviors...
		options.Add("Bloodstream")

	// Choose destination
	var/choice = rerun_ask(user, "a1", PROC_REF(inflation_setup), args, /datum/prompt/choice, question = "Select where this hose connects.", title = "Hose Connection", choices = options, buttons = TRUE)
	if(isnull(choice))
		return
	if(!user.Adjacent(human_owner()) || !choice)
		to_chat(user,span_notice("You decide not to connect \the [human_owner()] to the hose."))
		return FALSE

	// Setup the connection to mouth, vore, or blood
	var/feedback = ""
	switch(choice)
		if("Mouth")
			connection_mode = CHEM_INGEST
			feedback = "mouth"
		if("Bloodstream")
			connection_mode = CHEM_BLOOD
			feedback = span_danger("bloodstream")
		else
			connection_mode = CHEM_VORE // Anything else is a vore belly name
			if(human_owner().vore_selected)
				feedback = sanitize(human_owner().vore_selected.name)

	// Display action
	name = "[human_owner()]'s [feedback]"
	act_message(user, null, others = "%U% starts to connect the hose to \the [human_owner()]'s [feedback]...")
	var/started = task_start(/datum/task/timed/inflation_inflation_connected, user, human_owner(), other = other, origin = origin, target_arg = target, distancetonode = distancetonode, tubing = tubing, feedback = feedback)
	return !istext(started)

/datum/task/timed/inflation_inflation_connected
	duration = 7 SECONDS
	complete_proc = /datum/hose_connector/inflation/proc/inflation_connected
	fail_message = span_warning("You couldn't connect the hose!")
	var/datum/hose_connector/other
	var/datum/hose_connector/origin
	var/datum/hose_connector/target_arg
	var/distancetonode
	var/obj/item/stack/tubing
	var/feedback

/datum/hose_connector/inflation/proc/inflation_connected(datum/task/timed/inflation_inflation_connected/task)
	var/mob/user = task.actor
	var/datum/hose_connector/other = task.other
	var/datum/hose_connector/origin = task.origin
	var/datum/hose_connector/target = task.target_arg
	var/distancetonode = task.distancetonode
	var/obj/item/stack/tubing = task.tubing
	var/feedback = task.feedback
	if(other.get_hose() || get_hose()) // SHouldn't be connected to anything yet!
		to_chat(user,span_warning("You couldn't connect the hose, another hose is already connected!"))
		return
	if(connection_mode == CHEM_BLOOD) //OWCH!
		human_owner().injure(INJURY_PIERCE, 10, BP_TORSO, src)
		if(human_owner().can_pain_emote) // Doing this probably doesn't feel too good
			human_owner().emote("pain")
	to_chat(user, span_notice("You connect the hose to \the [human_owner()]'s [feedback]..."))
	origin.setup_hoses_finish(target, distancetonode, user, tubing)

/datum/hose_connector/inflation/connected_reagents()
	if(!human_owner())
		return null
	switch(connection_mode)
		if(CHEM_INGEST)
			return human_owner().ingested
		if(CHEM_VORE)
			return human_owner().vore_selected?.reagents
		if(CHEM_BLOOD)
			// Inflating
			var/datum/hose_connector/other = get_pairing()
			if(!other || other.flow_direction == HOSE_OUTPUT)
				return human_owner().bloodstr // Pump into blood reagents
			// Draining
			if(prob(30) && my_hose) // NEVER put normal reagents into the vessel...
				return human_owner().vessel // Suck blood
			return human_owner().bloodstr // Suck reagents from blood

/datum/hose_connector/inflation/handle_pump(datum/reagents/connected_to)
	ASSERT(connected_to)
	var/datum/hose_connector/other = get_pairing()
	var/rate = reagents.maximum_volume * 0.5
	if(connection_mode == CHEM_BLOOD)
		rate = 10 // SLOW here
	else
		if(other.flow_direction == HOSE_OUTPUT || other.flow_direction == HOSE_NEUTRAL) // If filling mouth check prefs for belly fluid consumption.
			if(connection_mode == CHEM_INGEST)
				if(!human_owner().consume_liquid_belly)
					for(var/datum/reagent/R in reagents.reagent_list)
						if(R.from_belly)
							to_chat(human_owner(), span_warning("You can't consume that, it contains something produced from a belly!"))
							my_hose.disconnect() // Pop!
							return
			if(connection_mode == CHEM_VORE)
				if(!human_owner().receive_reagents)
					to_chat(human_owner(), span_warning("You can't transfer reagents into your [sanitize(human_owner().vore_selected.name)], your prefs dont allow it!"))
					my_hose.disconnect() // Pop!
					return
		if(other.flow_direction == HOSE_INPUT || other.flow_direction == HOSE_NEUTRAL) // If filling mouth check prefs for belly fluid consumption.
			if(connection_mode == CHEM_VORE)
				if(!human_owner().give_reagents)
					to_chat(human_owner(), span_warning("You can't transfer reagents from your [sanitize(human_owner().vore_selected.name)], your prefs dont allow it!"))
					my_hose.disconnect() // Pop!
					return

	// Inflation station
	switch(other.flow_direction)
		if(HOSE_OUTPUT)
			// inflating us
			if(reagents.total_volume > 0)
				reagents.vore_trans_to_mob(human_owner(), rate, connection_mode, 1, 0, human_owner().vore_selected)
		if(HOSE_INPUT)
			// draining us
			if(connected_to.total_volume > 0)
				connected_to.trans_to_holder(reagents,rate)
		if(HOSE_NEUTRAL)
			// Sharing with us
			reagents.trans_to_holder(connected_to, reagents.maximum_volume) // Load our current reagents back into tank, it's mixed!
			connected_to.trans_to_holder(reagents, rand(1,reagents.maximum_volume) ) // Fill back up to a random amount

	if(connection_mode == CHEM_VORE && human_owner().vore_selected.count_liquid_for_sprite)
		PUBLISH(human_owner(), belly_change)

	if(prob(5) && (reagents.total_volume > 0 || connected_to.total_volume > 0))
		var/atom/pumper = other.get_carrier()
		pumper.visible_message(span_infoplain(span_bold("\The [pumper]") + " gurgles."))

/*
 * Inflation subtype, Borg edition. Geewiz janihound how come the AI lets you have two?
 */

/// Pumps reagents out of carrier
/datum/hose_connector/input/borg

/datum/hose_connector/input/borg/attach(atom/movable/new_carrier, set_unique_name = null)
	if(!isrobot(new_carrier))
		return FALSE
	return ..()

/datum/hose_connector/input/borg/proc/borg_owner() as /mob/living/silicon/robot
	return carrier

/datum/hose_connector/input/borg/connected_reagents()
	var/mob/living/silicon/robot/R = borg_owner()
	return R?.vore_selected?.reagents

/datum/hose_connector/input/borg/on_examine(datum/act/notice/N)
	return

/// Pumps reagents into carrier
/datum/hose_connector/output/borg

/datum/hose_connector/output/borg/attach(atom/movable/new_carrier, set_unique_name = null)
	if(!isrobot(new_carrier))
		return FALSE
	return ..()

/datum/hose_connector/output/borg/proc/borg_owner() as /mob/living/silicon/robot
	return carrier

/datum/hose_connector/output/borg/connected_reagents()
	var/mob/living/silicon/robot/R = borg_owner()
	return R?.vore_selected?.reagents

/datum/hose_connector/output/borg/on_examine(datum/act/notice/N)
	return

/// The human the hose connects to (our carrier).
/datum/hose_connector/inflation/proc/human_owner() as /mob/living/carbon/human
	return carrier
