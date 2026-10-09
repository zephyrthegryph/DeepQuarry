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


/obj/item/radio/beacon/proc/alter_signal_effect(datum/act/op/A)
	var/mob/user = A.actor
	var/t = A.step_value("beacon_signal")
	// The old verb took the text as its argument; ask for it instead.
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

/obj/item/radio/beacon/syndicate/interaction_self(mob/user, obj/item/held)
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
CAPABILITIES(/obj/item/radio/beacon)
	op("alter_signal_effect", menu(), label("Alter Beacon's Signal"), needs(carried()), asks(/datum/prompt/text, fields = list("question" = "Enter the beacon's new signal code.", "title" = "Alter Beacon's Signal", "default" = nameof(code), "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "timeout" = 0), step = "beacon_signal"), then(PROC_REF(alter_signal_effect)))
