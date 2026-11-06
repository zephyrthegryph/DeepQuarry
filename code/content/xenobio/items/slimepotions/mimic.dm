/obj/item/slimepotion/mimic/get_mechanics_info(list/additional_information)
	return ..(list("Warning: avoid combining multiple doses of mimic agent.") + additional_information)

/obj/item/slimepotion/mimic
	name = "mimic agent"
	desc = "A potent chemical mix that will mimic effects of other slime-produced agents."
	icon_state = "potsilver"

CAPABILITIES(/obj/item/slimepotion/mimic)
	op("mimic_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(mimic_interaction_item)))

/// Old attackby.
/obj/item/slimepotion/mimic/proc/mimic_interaction_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/M = A.held
	if(istype(M, /obj/item/slimepotion/mimic))
		to_chat(user, span_warning("You apply the mimic to the mimic, resulting a mimic that copies a mimic that copies a mimic that copies a mimic that-"))
		var/location = get_turf(src)
		play_sfx(location, SFX_WEAPONS_GAUSS_SHOOT)
		var/datum/effect/effect/system/grav_pull/s = new /datum/effect/effect/system/grav_pull
		s.set_up(3, 3, location)
		s.start()
		consumed(M, src)
		consume(src, user)
		return OP_OK
	return OP_DECLINE
