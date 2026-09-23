// A fluff structure to visually look like an AI core.
// Unlike the decoy AI mob, this won't explode if someone tries to card it.
/obj/structure/prop/fake_ai
	name = "AI"
	desc = ""
	icon = 'icons/mob/AI.dmi'
	icon_state = "ai"

/obj/structure/prop/fake_ai/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/fake_ai_item,
	)
	..()

/// Old attackby: an AI card doesn't fit this fake core.
/datum/interaction/entry_item/fake_ai_item
	id = "fake_ai_item"
	name = "Use"
	held_type = /obj/item/aicard
	effect = /obj/structure/prop/fake_ai/proc/interaction_item

/obj/structure/prop/fake_ai/proc/interaction_item(mob/user, obj/item/O, datum/interaction/interaction)
	to_chat(user, span_warning("This core does not appear to have a suitable port to use \the [O] on..."))
	return TRUE

/obj/structure/prop/fake_ai/dead
	icon_state = "ai-crash"

/obj/structure/prop/fake_ai/dead/crashed_med_shuttle
	name = "V.I.T.A."
	icon_state = "ai-heartline-crash"
