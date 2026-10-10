/// A reagent hose socket on an atom. Plain datum owned by its carrier's `hose_connectors` list
/// (several per carrier). Create with carrier.add_hose_connector(type, name).
/datum/hose_connector
	var/name = ""
	VAR_PROTECTED/force_name = FALSE // If it gets doesn't do automatic naming
	VAR_PROTECTED/atom/movable/carrier = null
	VAR_PROTECTED/flow_direction = HOSE_NEUTRAL
	VAR_PROTECTED/datum/hose/my_hose = null
	VAR_PROTECTED/connector_number = 0
	// Atom reagent code piggyback
	var/flags = NOREACT // Prevent reagent explosions runtiming because no turf or by deleting the hose datum
	var/datum/reagents/reagents = null
	var/makes_gurgles = TRUE

/// The hose plugged into this socket (a relation view). It pumps every 2 s while one is: the gate is the relation var, so the every() polls.
CAPABILITIES(/datum/hose_connector)
	ref_one(nameof(my_hose))
	owns_one(nameof(reagents), /datum/reagents)
	every(2 SECONDS, then(PROC_REF(connector_step)), when = nameof(my_hose))

/// Carrier's hose sockets (/datum/hose_connector), owned: deleted with the carrier.
/atom/movable/var/list/hose_connectors

/// Adds a hose connector of `connector_type` to src. Returns it, or null when src can't carry that type.
/atom/movable/proc/add_hose_connector(connector_type, set_unique_name = null)
	RETURN_TYPE(/datum/hose_connector)
	var/datum/hose_connector/HC = new connector_type()
	if(!HC.attach(src, set_unique_name))
		log_world("hose_connector: [connector_type] refused carrier [src] ([type])")
		spent(HC)
		return null
	return HC

/// Src's hose connectors that are `connector_type` (or subtypes). Always a list.
/atom/movable/proc/get_hose_connectors(connector_type = /datum/hose_connector)
	. = list()
	for(var/datum/hose_connector/HC as anything in hose_connectors)
		if(istype(HC, connector_type))
			. += HC

/// Binds to `new_carrier`. FALSE when the carrier is incompatible.
/datum/hose_connector/proc/attach(atom/movable/new_carrier, set_unique_name = null)
	rel_set(src, nameof(carrier), new_carrier)
	rel_set(src, nameof(reagents), new /datum/reagents(60, src))
	// Handle uniquely named connectors
	if(set_unique_name)
		name = set_unique_name
		force_name = TRUE
	else if(!force_name)
		name = "[flow_direction] hose connector"
	var/list/CL = carrier.get_hose_connectors(type)
	var/same = 0
	for(var/datum/hose_connector/other as anything in CL)
		if(other.type == type)
			same++
	connector_number = same + 1
	rel_add(carrier, nameof(carrier.hose_connectors), src)
	observe(carrier, /datum/notice/examine, src, then(PROC_REF(on_examine)))
	observe(carrier, /datum/notice/moved, src, then(PROC_REF(move_react)))
	observe(carrier, /datum/notice/hose_forcepump, src, then(PROC_REF(on_force_pump)))
	grant(carrier, granted_verb(/atom/proc/disconnect_hose), src)
	return TRUE

// A hose is shared by its two connectors, so neither owns it: it lives while both
// ends do, and a dying connector deletes it (the hose disconnects both ends).

// the carrier loses its disconnect verb (before phase 4 nulls carrier).
/datum/hose_connector/lifecycle_prerelease()
	..()
	if(my_hose)
		spent(my_hose)
	if(carrier)
		revoke(carrier, granted_verb(/atom/proc/disconnect_hose), src)
		// carrier.hose_connectors owns us: a dying connector leaves it in phase 2.

/datum/hose_connector/proc/get_carrier()
	RETURN_TYPE(/atom)
	return carrier

/datum/hose_connector/proc/get_hose()
	RETURN_TYPE(/datum/hose)
	return my_hose

/datum/hose_connector/proc/get_flow_direction()
	return flow_direction

/datum/hose_connector/proc/get_id()
	return "[name] #[connector_number]"

/datum/hose_connector/proc/connected_reagents()
	return carrier.reagents

/datum/hose_connector/proc/connector_step(datum/act/timer/A)
	var/datum/reagents/connected_to = connected_reagents()
	if(!connected_to) // Emergency. the vorebelly was deleted or something. Lets just hard lock that out from maintaining state by disconnecting the tube.
		reagents.clear_reagents()
		my_hose.disconnect()
		return
	handle_pump(connected_to)

/datum/hose_connector/proc/handle_pump(datum/reagents/connected_to)
	PROTECTED_PROC(TRUE)
	ASSERT(connected_to)
	// Drain our connector back into tank, and then fill it randomly. The hose handles swapping.
	reagents.trans_to_holder(connected_to, reagents.maximum_volume)
	connected_to.trans_to_holder(reagents, rand(1,reagents.maximum_volume))

/datum/hose_connector/proc/on_force_pump(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	force_pump()

/datum/hose_connector/proc/force_pump()
	if(!my_hose)
		return
	connector_step()
	if(makes_gurgles && prob(5))
		carrier.visible_message(span_infoplain(span_bold("\The [carrier]") + " gurgles as it pumps fluid."))

/datum/hose_connector/proc/valid_connection(datum/hose_connector/C)
	if(istype(C))
		if(C.my_hose)
			return FALSE
		if(C.flow_direction == HOSE_NEUTRAL || flow_direction == HOSE_NEUTRAL) // Always allowed
			return TRUE
		if(C.flow_direction in (list(HOSE_INPUT, HOSE_OUTPUT) - flow_direction))
			return TRUE
	return FALSE

/datum/hose_connector/proc/disconnect_action(user)
	if(carrier.Adjacent(user))
		act_message(user, carrier, others = "%U% disconnects \the hose from %T%.")
		my_hose.disconnect(user)
		spent(my_hose, user) // the hose is shared by both ends; its death clears both views

/datum/hose_connector/proc/connect(datum/hose/H = null)
	rel_set(src, nameof(my_hose), H)

/// Connects a hose to `target`, using `distancetonode` of `tubing` when done. An inflation end
/// is a timed action first (inflation_setup()); either way setup_hoses_finish() connects.
/datum/hose_connector/proc/setup_hoses(datum/hose_connector/target, distancetonode, mob/user, obj/item/stack/tubing)
	if(!target || QDELETED(target))
		to_chat(user,span_danger("What you were connecting to has stopped existing! Ohno!"))
		return FALSE

	// Logic for handling two mobs at once would be a mess of option selections and prefs...
	if(istype(src,/datum/hose_connector/inflation) && istype(target,/datum/hose_connector/inflation))
		to_chat(user,span_notice("Nothing would flow between \the [get_carrier()] and \the [target.get_carrier()] without anything to pump it!"))
		return FALSE

	// Check for vore inflation connectors.
	if(istype(src,/datum/hose_connector/inflation) || istype(target,/datum/hose_connector/inflation))
		// Handle the connection target once we setup the hose. Needs to be done like this as either ends can be the inflation connector
		// Also has to be done on finalize, as players would be able to click one then the other, then potentially drop or do other stuff with the hose!
		var/datum/hose_connector/inflation/I = src
		if(istype(I))
			return I.inflation_setup(user, target, src, target, distancetonode, tubing)
		I = target
		if(istype(I))
			return I.inflation_setup(user, src, src, target, distancetonode, tubing)
		// Good going, you broke it
		to_chat(user,span_notice("You're not sure what happened, but you couldn't connect the hose..."))
		return FALSE
	to_chat(user, span_notice("You connect the [src] to \the [target]."))
	return setup_hoses_finish(target, distancetonode, user, tubing)

/datum/hose_connector/proc/setup_hoses_finish(datum/hose_connector/target, distancetonode, mob/user, obj/item/stack/tubing)
	// Handle invalid vorebellies, has to be done after inflation_setup()
	if(!src.connected_reagents())
		to_chat(user,span_warning("\The [get_carrier()] doesn't seem ready to connect yet."))
		return FALSE
	if(!target.connected_reagents())
		to_chat(user,span_warning("\The [target.get_carrier()] doesn't seem ready to connect yet."))
		return FALSE

	// Hose prepared!
	var/datum/hose/H = new()
	H.set_hose(src, target, distancetonode, user)
	tubing?.use(distancetonode)
	return TRUE

/// The hose on this connector, if one is attached: a look that draws it watches it.
/datum/hose_connector/proc/hose()
	RETURN_TYPE(/datum/hose)
	return my_hose

/datum/hose_connector/proc/get_pairing()
	RETURN_TYPE(/datum/hose_connector)
	if(my_hose)
		return my_hose.get_pairing(src)
	return null

/datum/hose_connector/proc/remove_hose()
	rel_clear(src, nameof(my_hose))
	// Return reagents to source now that there is no hose, lossy to avoid exploits.
	if(reagents.total_volume)
		reagents.trans_to_holder(connected_reagents(), reagents.maximum_volume)
		reagents.clear_reagents() // Wipe it to avoid exploits

/datum/hose_connector/proc/on_examine(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/examine/event = N
	var/list/examine_texts = event.texts
	var/datum/hose_connector/hose_pair = my_hose?.get_pairing(src)
	if(istype(hose_pair,/datum/hose_connector/inflation))
		hose_pair = "\the [hose_pair.name]" // Slightly different, so it shows the belly attached
	else if(hose_pair)
		hose_pair = "\the [hose_pair.get_carrier()]"
	else
		hose_pair = "nothing"
	examine_texts += span_notice("[name] #[connector_number] is [my_hose ? "connected to [hose_pair]" : "disconnected"].")

/datum/hose_connector/proc/move_react(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	update_hose_beam()

/datum/hose_connector/proc/update_hose_beam()
	if(!my_hose || !my_hose.has_pairing(src))
		return
	// Handle distance check if too far
	my_hose.update_beam()

/*
 * Support procs/verbs
 */

/atom/proc/disconnect_hose()
	set src in oview(1)
	set name = "Disconnect Hose"
	set desc = "Quickly disconnect a hose from all machines it is attached to."
	set category = VERB_CAT_OBJECT

	var/list/available_sockets = list()
	var/atom/movable/AM = src
	if(!istype(AM))
		return
	for(var/datum/hose_connector/HC as anything in AM.get_hose_connectors())
		if(HC.get_hose())
			available_sockets[HC.get_id()] = HC
	if(!LAZYLEN(available_sockets))
		return

	if(available_sockets.len == 1)
		var/key = available_sockets[1]
		var/datum/hose_connector/AC = available_sockets[key]
		AC.disconnect_action(usr)
	else
		var/choice = rerun_ask(usr, "a1", PROC_REF(disconnect_hose), args, /datum/prompt/choice, question = "Select a target hose connector.", title = "Socket Disconnect", choices = available_sockets)
		if(isnull(choice))
			return
		if(choice)
			var/datum/hose_connector/AC = available_sockets[choice]
			AC.disconnect_action(usr)

/*
 * Standard subtypes
 */

/// Pumps reagents out of carrier
/datum/hose_connector/input
	name = "hose input"
	flow_direction = HOSE_INPUT

/datum/hose_connector/input/handle_pump(datum/reagents/connected_to)
	ASSERT(connected_to)
	reagents.trans_to_holder(connected_to, reagents.maximum_volume)

/// Pumps reagents into carrier
/datum/hose_connector/output
	name = "hose output"
	flow_direction = HOSE_OUTPUT

/datum/hose_connector/output/handle_pump(datum/reagents/connected_to)
	ASSERT(connected_to)
	connected_to.trans_to_holder(reagents, reagents.maximum_volume)

/// Endless source, produces a reagent and pumps it out forever. Does not require attached object to have reagents.
/datum/hose_connector/endless_source
	name = "source connector"
	force_name = TRUE
	flow_direction = HOSE_OUTPUT
	var/reagent_id = null

/datum/hose_connector/endless_source/connected_reagents()
	if(!carrier)
		return null
	return reagents // Ourselves, not our carrier

/datum/hose_connector/endless_source/handle_pump(datum/reagents/connected_to)
	ASSERT(connected_to)
	connected_to.add_reagent(reagent_id,5)

/datum/hose_connector/endless_source/water
	reagent_id = REAGENT_ID_WATER

/// Endless drain, removes reagents from existance
/datum/hose_connector/endless_drain
	name = "drain connector"
	force_name = TRUE
	flow_direction = HOSE_INPUT

/datum/hose_connector/endless_drain/connected_reagents()
	if(!carrier)
		return null
	return reagents // Ourselves, not our carrier

/datum/hose_connector/endless_drain/handle_pump(datum/reagents/connected_to)
	ASSERT(connected_to)
	connected_to.clear_reagents()

/// Moo, needed because it has a seperate reagent container as udder.
/datum/hose_connector/output/cow
	name = "Udder"
	force_name = TRUE
	makes_gurgles = FALSE

/datum/hose_connector/output/cow/connected_reagents()
	var/mob/living/simple_mob/animal/passive/cow/C = carrier
	return C.udder

/// Only allows oil to be inserted
/datum/hose_connector/input/fryer
	name = "Oil Storage"
	force_name = TRUE

/datum/hose_connector/input/fryer/handle_pump(datum/reagents/oil_reagents/connected_to)
	ASSERT(connected_to)
	if(connected_to.total_volume >= connected_to.optimal_oil) //Don't overfill it.
		return
	for(var/datum/reagent/reagent_to_add in reagents.reagent_list)
		if(istype(reagent_to_add, /datum/reagent/nutriment/triglyceride/oil)) //So we can transfer ALL oil types.
			var/old_oil_amount = connected_to.total_volume
			connected_to.add_reagent(reagent_to_add.id, rand(1,reagent_to_add.volume))
			reagents.remove_reagent(reagent_to_add.id, connected_to.total_volume - old_oil_amount, 1) //Ex: Old was 100. We added 10u. Total_volume is now 110u. 110u-100u = 10u
			if(connected_to.total_volume >= connected_to.optimal_oil)
				break

/datum/hose_connector/input/fryer/connected_reagents()
	var/obj/machinery/appliance/cooker/fryer/our_fryer = carrier
	return our_fryer.oil

// hose_sockets(list(connector types...)): the carrier's hose sockets, made when it initializes (on_holder_init), in order. It replaces the
// Initialize() overrides that only called add_hose_connector() (doc/rewrite/framework_gaps.md, "hose_sockets()").
//
//	CAPABILITIES(/obj/machinery/pump)
//		hose_sockets(list(/datum/hose_connector/output))
CAPABILITY_TYPE(hose_sockets, CAP_HOSE_SOCKETS, /datum/capability/lib/hose_sockets, key = NONE, types = null)

/datum/capability/lib/hose_sockets
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/hose_sockets/on_holder_init(datum/act/eval/A)
	var/atom/movable/carrier = A.holder
	if(!istype(carrier))
		stack_trace("hose_sockets(): [A.holder] ([A.holder?.type]) is not a movable atom")
		return
	for(var/connector_type in types)
		carrier.add_hose_connector(connector_type)
