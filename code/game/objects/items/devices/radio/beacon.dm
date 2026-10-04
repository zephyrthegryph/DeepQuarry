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


CAPABILITIES(/obj/item/radio/beacon)
	op("alter_signal", menu(), label("Alter Beacon's Signal"), needs(carried()), wait(0),
		asks(/datum/prompt/text, fields = list("question" = "Enter the beacon's new signal code.", "title" = "Alter Beacon's Signal", "default" = computed(PROC_REF(signal_default)), "max_len" = MAX_NAME_LEN, "name_text" = TRUE)),
		then(PROC_REF(alter_signal_effect)))

/// What the question starts with: the beacon's code now.
/obj/item/radio/beacon/proc/signal_default(datum/act/A)
	return code

/obj/item/radio/beacon/proc/alter_signal_effect(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/prompt/text/answer = A.answer
	var/t = answer?.value
	if(isnull(t))
		return OP_REFUSED
	if(loc != user)
		return OP_REFUSED
	if ((user.canmove && !( user.restrained() )))
		src.code = t
	if (!( src.code ))
		src.code = "beacon"
	src.add_fingerprint(user)
	return OP_OK

// SINGULO BEACON SPAWNER

/obj/item/radio/beacon/syndicate
	name = "suspicious beacon"
	desc = "A label on it reads: <i>Activate to have a singularity beacon teleported to your location</i>."
	beacon = TRUE

CAPABILITIES(/obj/item/radio/beacon/syndicate)
	without("uplink_use")
	op("deploy", in_hand(), label("Use"), then(PROC_REF(deployed)))

/// Using it in hand has a singularity beacon teleported to the user.
/obj/item/radio/beacon/syndicate/proc/deployed(datum/act/op/A)
	var/mob/user = A.actor
	var/turf/sound_origin = get_turf(src)
	if(!consume(src, user))
		return OP_OK
	to_chat(user, span_notice("Locked In"))
	new /obj/machinery/power/singularity_beacon/syndicate( user.loc )
	play_sfx(sound_origin, SFX_EFFECTS_POP, 2, vary = TRUE, extrarange = 1)
	return OP_OK

