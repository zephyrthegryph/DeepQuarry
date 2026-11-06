//////////////////////////////////////////////////////
//				Magic 8-Ball / Conch				//
//////////////////////////////////////////////////////

/obj/item/toy/eight_ball
	name = "\improper Magic 8-Ball"
	desc = "Mystical! Magical! Ages 8+!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "eight-ball"
	var/use_action = "shakes the ball"
	COOLDOWN_DECLARE(cooldown)

TYPE_TABLE_DECLARE(/obj/item/toy/eight_ball, eight_ball_answers, list("Definitely.", "All signs point to yes.", "Most likely.", "Yes.", "Ask again later.", "Better not tell you now.", "Future unclear.", "Maybe.", "Doubtful.", "No.", "Don't count on it.", "Never."))

CAPABILITIES(/obj/item/toy/eight_ball)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/eight_ball/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 3 SECONDS)
		var/answer = pick(TYPE_TABLE_GET(src, eight_ball_answers))
		act_message(user, null, others = span_notice("%U% focuses on their question and [use_action]..."))
		user.visible_message(span_notice("The [src] says \"[answer]\""))
		return TRUE
	return TRUE

/obj/item/toy/eight_ball/conch
	name = "Magic Conch shell"
	desc = "All hail the Magic Conch!"
	icon_state = "conch"
	use_action = "pulls the string"

// DND Character minis. Use the naming convention (type)character for the icon states.

TYPE_TABLE(/obj/item/toy/eight_ball/conch, eight_ball_answers, list("Yes.", "No.", "Try asking again.", "Nothing.", "I don't think so.", "Neither.", "Maybe someday."))
