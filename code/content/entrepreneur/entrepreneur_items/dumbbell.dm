/obj/item/entrepreneur/dumbbell
	name = "dumbbell"
	desc = "A small but heavy pair of weights connected by a bar, desgined to be held in one hand."
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "dumbbell"

CAPABILITIES(/obj/item/entrepreneur/dumbbell)
	op("self", in_hand(), label("Use"), needs(req(PROC_REF(can_exercise_holds))), wait(3 SECONDS), then(PROC_REF(exercise_done)))

/// Requirement: the user isn't too hungry to exercise.
/obj/item/entrepreneur/dumbbell/proc/can_exercise(mob/user, atom/target, obj/item/held)
	var/mob/living/M = user
	if(istype(M) && nutrition_of(M) <= 100)
		return "you are too hungry to exercise right now"
	return TRUE

/// Old attack_self.
/// Requirement: answers null to allow or a reason.
/obj/item/entrepreneur/dumbbell/proc/can_exercise_holds(datum/act/op/A)
	var/answer = can_exercise(A.actor, src, A.held)
	if(!istext(answer) && answer)
		return null
	return req_refusal_value(answer, /datum/msg/req_failed)

/// Why can_exercise_holds refuses: the legacy check's text, else the clause's own reason.
/obj/item/entrepreneur/dumbbell/proc/exercise_done(datum/act/op/A)
	var/mob/living/M = A.actor
	var/mob/user = M
	M.adjust_nutrition(-10)
	to_chat(user, span_notice("You successfully perform a [src] exercise!"))
	if(STATE_GET(M, bodyweight, weight) > 50)
		STATE_SET(M, bodyweight, weight, STATE_GET(M, bodyweight, weight) - (0.5))
