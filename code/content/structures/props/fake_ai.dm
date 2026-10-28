// A fluff structure to visually look like an AI core.
// Unlike the decoy AI mob, this won't explode if someone tries to card it.
/obj/structure/prop/fake_ai
	name = "AI"
	desc = ""
	icon = 'icons/mob/AI.dmi'
	icon_state = "ai"

CAPABILITIES(/obj/structure/prop/fake_ai)
	op("item", item(/obj/item/aicard), label("Use"), then(PROC_REF(interaction_item)))

/obj/structure/prop/fake_ai/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	to_chat(user, span_warning("This core does not appear to have a suitable port to use \the [O] on..."))
	return TRUE

/obj/structure/prop/fake_ai/dead
	icon_state = "ai-crash"

/obj/structure/prop/fake_ai/dead/crashed_med_shuttle
	name = "V.I.T.A."
	icon_state = "ai-heartline-crash"
