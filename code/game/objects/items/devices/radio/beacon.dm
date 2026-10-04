/obj/item/radio/beacon
	name = "tracking beacon"
	desc = "A beacon used by a teleporter."
	icon_state = "beacon"
	item_state = "signaler"
	var/code = "electronic"

REGISTRY_MEMBERSHIP(/obj/item/radio/beacon, REGISTRY_BEACONS)

/obj/item/radio/beacon/hear_talk()
	return


/obj/item/radio/beacon/send_hear()
	return null


/obj/item/radio/beacon/proc/alter_signal_effect(mob/user, obj/item/held, datum/interaction/interaction)
	// The old verb took the text as its argument; ask for it instead.
	open_request(src, /datum/prompt/text/tracking_beacon_signal, PROC_REF(beacon_signal_entered), answerer = user, captured_item = held, captured_interaction = interaction, item_expected = !isnull(held), interaction_expected = !isnull(interaction), question = "Enter the beacon's new signal code.", title = "Alter Beacon's Signal", default = code, max_len = MAX_NAME_LEN, name_text = TRUE, timeout = 0)

/obj/item/radio/beacon/proc/beacon_signal_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/text/tracking_beacon_signal/request = A.request
	if(request.captures_gone())
		return
	var/datum/result/result = safe_call(PROC_REF(apply_beacon_signal), A.request.answerer, A.answer.answer_value)
	if(!result.ok)
		stack_trace("[type] request: [result.error]")
	. = result.value
	SStgui.update_uis(src)

/obj/item/radio/beacon/proc/apply_beacon_signal(mob/user, t)
	if(isnull(t))
		return
	if(loc != user)
		return
	if ((user.canmove && !( user.restrained() )))
		src.code = t
	if (!( src.code ))
		src.code = "beacon"
	src.add_fingerprint(user)

// SINGULO BEACON SPAWNER

/obj/item/radio/beacon/syndicate
	name = "suspicious beacon"
	desc = "A label on it reads: <i>Activate to have a singularity beacon teleported to your location</i>."
	beacon = TRUE

/obj/item/radio/beacon/syndicate/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	. = ..()
	if(.)
		return TRUE
	if(user)
		var/turf/sound_origin = get_turf(src)
		if(!consume(src, user))
			return TRUE
		to_chat(user, span_notice("Locked In"))
		new /obj/machinery/power/singularity_beacon/syndicate( user.loc )
		play_sfx(sound_origin, SFX_EFFECTS_POP, 2, vary = TRUE, extrarange = 1)
	return

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/item/radio/beacon, \
	INTERACT_VERB("Alter Beacon's Signal", PROC_REF(alter_signal_effect), REQ_IN_INVENTORY), \
)

/datum/prompt/text/tracking_beacon_signal
	var/obj/item/captured_item
	var/datum/interaction/captured_interaction
	var/item_expected = FALSE
	var/interaction_expected = FALSE

CAPABILITIES(/datum/prompt/text/tracking_beacon_signal)
	ref_one(nameof(captured_item), /obj/item)
	ref_one(nameof(captured_interaction), /datum/interaction)

/datum/prompt/text/tracking_beacon_signal/prepare(datum/act/A)
	. = ..()
	var/obj/item/item = captured_item
	var/datum/interaction/interaction = captured_interaction
	rel_clear(src, nameof(captured_item))
	rel_clear(src, nameof(captured_interaction))
	rel_set(src, nameof(captured_item), item)
	rel_set(src, nameof(captured_interaction), interaction)

/datum/prompt/text/tracking_beacon_signal/proc/captures_gone()
	return QDELETED(answerer) || (item_expected && QDELETED(captured_item)) || (interaction_expected && QDELETED(captured_interaction))

/datum/prompt/text/tracking_beacon_signal/recheck_extra()
	. = ..()
	if(.)
		return
	if(captures_gone())
		return "gone"
	return null
