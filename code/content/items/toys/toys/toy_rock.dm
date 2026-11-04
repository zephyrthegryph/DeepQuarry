/*
 * Pet rocks
 */
/obj/item/toy/rock
	name = "pet rock"
	desc = "A stuffed version of the classic pet. \
	The soft ones were made after kids kept throwing \
	them at each other. It has a small piece of soft \
	plastic that you can draw on if you wanted."
	icon = 'icons/obj/toy.dmi'
	icon_state = "rock"

CAPABILITIES(/obj/item/toy/rock)
	configure(item_combat(attack_verbs = list("grug'd", "unga'd")))
	op("draw_face", item(/obj/item/pen), label("Draw a face"), passes(),
		asks(/datum/prompt/choice, fields = list("title" = "Faces", "question" = "Choose what you'd like to draw.", "choices" = list("fred","roxie","rock","Cancel"), "buttons" = TRUE, "subject" = computed(PROC_REF(face_subject)), "ask_flags" = ASK_HELD | ASK_CAPABLE, "timeout" = 0), step = "face"),
		then(PROC_REF(interaction_draw_face)))

/// The question is about the pen in the hand.
/obj/item/toy/rock/proc/face_subject(datum/act/op/A)
	return A.held

/// Old attackby: the face the question was answered with.
/obj/item/toy/rock/proc/interaction_draw_face(datum/act/op/A)
	var/mob/living/user = A.actor
	var/datum/prompt/answer = A.answer
	if(!answer)
		return OP_OK
	switch(answer.value)
		if("fred")
			set_icon_state("fred")
			to_chat(user, "You draw a face on the rock.")
		if("rock")
			set_icon_state("rock")
			to_chat(user, "You wipe the plastic clean.")
		if("roxie")
			set_icon_state("roxie")
			to_chat(user, "You draw a face on the rock and pull aside the plastic slightly, revealing a small pink bow.")
	return OP_OK
