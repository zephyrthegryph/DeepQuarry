/obj/item/entrepreneur/spirit_board
	name = "spirit board"
	desc = "A wooden board with an alphabet at numbers on it, used to contact the dead. You need to use a glass to contact the spirit world. (It can be alt-clicked to decide the next letter in the sequence. This item does not canonise ghosts/souls in this setting, it's just a bit of fun!)"
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "spirit_board"
	var/static/list/possible_results = list("A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z","Yes","No","1","2","3","4","5","6","7","8","9","0","Nothing")
	///What the next letter/number will be.
	var/next_result = 0
	///If ghosts can interact with it.
	var/ghost_enabled = 1
	///If the board will always display what ghosts put
	var/accurate = FALSE

CAPABILITIES(/obj/item/entrepreneur/spirit_board)
	op("item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), needs(req(PROC_REF(can_slide_holds))), wait(3 SECONDS), then(PROC_REF(spirit_slide_done)))
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), priority(OP_PRIORITY_DEFAULT - 1), asks(/datum/prompt/choice, fields = list("question" = "What should it land on next?", "title" = "Next result", "choices" = nameof(possible_results), "timeout" = 0), step = "k451", when = PROC_REF(alt_asks)), then(PROC_REF(interaction_alt)))
	op("spirit_board_ghost_guide", observer(), label("Guide"), needs(req(PROC_REF(can_ghost_guide_holds))), asks(/datum/prompt/choice, fields = list("question" = "What should it land on next?", "title" = "Next result", "choices" = nameof(possible_results), "timeout" = 0), step = "k459", when = PROC_REF(ghost_asks)), then(PROC_REF(spirit_board_ghost_guide)))

/// Requirement: a drink container to slide across the board (a non-living user is ignored silently by the effect).
/obj/item/entrepreneur/spirit_board/proc/can_slide_holds(datum/act/op/A)
	if(!isliving(A.actor))
		return null
	return (istype(A.held, /obj/item/reagent_containers/food/drinks)) ? null : "you need some sort of glass, bottle or cup to contact the spirit world"

/// Why can_slide_holds refuses.
/// Requirement: the guiding ghost isn't ghost-role banned (a board with ghosts disabled ignores them silently).
/obj/item/entrepreneur/spirit_board/proc/can_ghost_guide_holds(datum/act/op/A)
	if(!ghost_enabled)
		return null
	return (!jobban_isbanned(A.actor, JOB_GHOSTROLES)) ? null : "you cannot interact with this board because you are banned from playing ghost roles"

/// Why can_ghost_guide_holds refuses.
/obj/item/entrepreneur/spirit_board/proc/spirit_slide_done(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/reagent_containers/food/drinks/W = A.held
	if(!istype(user))
		return OP_OK
	var/result = 0
	if(next_result)
		result = next_result
	else
		result = pick(possible_results)
	act_message(user, src, others = span_notice("%U% slides the [W] over to [result]!"))
	next_result = 0

/// The question is asked only of a carbon (admins can be cheeky).
/obj/item/entrepreneur/spirit_board/proc/alt_asks(datum/act/op/A)
	return istype(A.actor, /mob/living/carbon)

/// Old click_alt.
/obj/item/entrepreneur/spirit_board/proc/interaction_alt(datum/act/op/A)
	if(!istype(A.actor, /mob/living/carbon)) //admins can be cheeky
		return OP_OK
	var/_answer_k451 = A.step_value("k451")
	if(isnull(_answer_k451))
		return OP_OK
	next_result = text_or_null(_answer_k451)
	return OP_OK

/// A board with ghosts disabled asks nothing.
/obj/item/entrepreneur/spirit_board/proc/ghost_asks(datum/act/op/A)
	return ghost_enabled

/// Old attack_ghost: choose the board's next result. Never fell through to the default.
/obj/item/entrepreneur/spirit_board/proc/spirit_board_ghost_guide(datum/act/op/A)
	var/mob/observer/dead/user = A.actor
	if(!ghost_enabled)
		return OP_OK
	var/_answer_k459 = A.step_value("k459")
	if(isnull(_answer_k459))
		return OP_OK
	next_result = text_or_null(_answer_k459)
	if(!is_admin(user) || !accurate) //admins can bypass this for event stuff
		if(prob(25))
			next_result = 0 //25% chance for the ghost to fail to manipulate the board
	return OP_OK
