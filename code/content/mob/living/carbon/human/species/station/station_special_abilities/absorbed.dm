/// An absorbed prey picking a victim for its pred's belly. Re-checked on the answer: still
/// absorbed in that belly, inside a living pred. (No consciousness check.)
/datum/prompt/choice/victim/absorbed
	ask_flags = NONE
	var/obj/belly/belly

CAPABILITIES(/datum/prompt/choice/victim/absorbed)
	ref_one(nameof(belly), /obj/belly)

/datum/prompt/choice/victim/absorbed/prepare(datum/act/A)
	..()
	var/obj/belly/captured = belly
	rel_clear(src, nameof(belly))
	rel_set(src, nameof(belly), captured)

/datum/prompt/choice/victim/absorbed/begin()
	if(QDELETED(belly))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/prompt/choice/victim/absorbed/recheck_extra()
	. = ..()
	if(.)
		return
	var/mob/living/L = answerer
	if(QDELETED(belly) || !L.absorbed || L.loc != belly || !isliving(belly.loc))
		return "not absorbed"
	return null
