/obj/effect/decal/remains
	name = "remains"
	gender = PLURAL
	icon = 'icons/effects/blood.dmi'
	icon_state = "remains"
	anchored = FALSE
	/// What touching the remains says they crumble into.
	var/crumble_message = "sinks together into a pile of ash"
	/// What they leave behind on a floor when touched.
	var/crumble_into = /obj/effect/decal/cleanable/ash

/obj/effect/decal/remains/human
	desc = "They look like human remains. They have a strange aura about them."

/obj/effect/decal/remains/xeno
	desc = "They look like the remains of something... alien. They have a strange aura about them."
	icon_state = "remainsxeno"

/obj/effect/decal/remains/robot
	desc = "They look like the remains of something mechanical. They have a strange aura about them."
	icon = 'icons/mob/robots.dmi'
	icon_state = "remainsrobot"
	crumble_message = "crumbles down into a pile of debris"
	crumble_into = /obj/effect/decal/cleanable/blood/gibs/robot

/obj/effect/decal/remains/mouse
	desc = "They look like the remains of a small rodent."
	icon_state = "mouse"

/obj/effect/decal/remains/lizard
	desc = "They look like the remains of a small lizard."
	icon_state = "lizard"

/obj/effect/decal/remains/unathi
	desc = "They look like Unathi remains. Pointy."
	icon_state = "remainsunathi"

/obj/effect/decal/remains/tajaran
	desc = "They look like Tajaran remains. They're surprisingly small."
	icon_state = "remainstajaran"

/obj/effect/decal/remains/ribcage
	desc = "They look like animal remains of some sort... You hope."
	icon_state = "remainsribcage"

/obj/effect/decal/remains/deer
	desc = "They look like the remains of a large herbivore, picked clean."
	icon_state = "remainsdeer"

/obj/effect/decal/remains/posi
	desc = "This looks like part of an old FBP. Hopefully it was empty."
	icon_state = "remainsposi"

/obj/effect/decal/remains/mummy1
	name = "mummified remains"
	desc = "They look like human remains. They've been here a long time."
	icon_state = "mummified1"

/obj/effect/decal/remains/mummy2
	name = "mummified remains"
	desc = "They look like human remains. They've been here a long time."
	icon_state = "mummified2"

CAPABILITIES(/obj/effect/decal/remains)
	op("crumble_remains", hand(), stance(I_HURT), then(PROC_REF(interaction_crumble_remains)))

/// Old attack_hand: harm intent crumbles the remains away.
/obj/effect/decal/remains/proc/interaction_crumble_remains(datum/act/op/A)
	var/mob/user = A.actor
	if(loc?.release_refusal(src, user))
		return TRUE
	to_chat(user, span_notice("[src] [crumble_message]."))
	var/turf/simulated/floor/F = get_turf(src)
	if(istype(F))
		var/atom/movable/debris = new crumble_into(F)
		// A floor transform has no holder slot to inherit. Contained remains
		// still leave debris on the floor when destroyed.
		if(loc == F)
			replace_with(src, debris)
			return TRUE
	consume(src, user)
	return TRUE
