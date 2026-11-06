/// Re-checked on the answer: conscious, and still holding the target by the neck.
/datum/prompt/choice/succubus_bite
	timeout = 0
	title = "Reagent"
	question = "What do you wish to inject?"
	choices = list(REAGENT_APHRODISIAC, "Numbing", "Paralyzing")
	ask_flags = ASK_CONSCIOUS
	var/obj/item/grab/grab
	var/mob/living/carbon/human/target

CAPABILITIES(/datum/prompt/choice/succubus_bite)
	ref_one(nameof(grab), /obj/item/grab)
	ref_one(nameof(target), /mob/living/carbon/human)

/datum/prompt/choice/succubus_bite/prepare(datum/act/A)
	..()
	var/obj/item/grab/captured_grab = grab
	var/mob/living/carbon/human/captured_target = target
	rel_clear(src, nameof(grab))
	rel_clear(src, nameof(target))
	rel_set(src, nameof(grab), captured_grab)
	rel_set(src, nameof(target), captured_target)

/datum/prompt/choice/succubus_bite/begin()
	if(QDELETED(grab) || QDELETED(target))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/prompt/choice/succubus_bite/recheck_extra()
	. = ..()
	if(.)
		return
	if(QDELETED(grab) || QDELETED(target))
		return "gone"
	return answerer.get_active_hand() != grab || grab.grab_target() != target || grab.state != GRAB_NECK ? "lost grip" : null
