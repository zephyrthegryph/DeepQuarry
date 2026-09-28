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
	var/t = rerun_ask(user, "beacon_signal", PROC_REF(alter_signal_effect), args, /datum/om/prompt/text, message = "Enter the beacon's new signal code.", title = "Alter Beacon's Signal", default = code, max_length = MAX_NAME_LEN)
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
		to_chat(user, span_notice("Locked In"))
		new /obj/machinery/power/singularity_beacon/syndicate( user.loc )
		playsound(src, 'sound/effects/pop.ogg', 100, 1, 1)
		consume(src, user)
	return

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/item/radio/beacon, \
	INTERACT_VERB("Alter Beacon's Signal", PROC_REF(alter_signal_effect), REQ_IN_INVENTORY), \
)
