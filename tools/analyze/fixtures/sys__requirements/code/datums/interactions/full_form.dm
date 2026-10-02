/datum/interaction/machine_item/fit_material
	id = "fit"
	effect = /obj/machinery/pipe/proc/interaction_fit
	also_requires = list(REQ_FIELD_NOT("x", "y"))

/datum/interaction/machine_item/paint
	effect = /obj/machinery/pipe/interaction_paint // trailing comment

/datum/interaction/other/not_an_interaction_datum
	effect = /obj/machinery/pipe/proc/interaction_none

/datum/not_interaction
	effect = /obj/machinery/pipe/proc/interaction_none2

/obj/machinery/pipe/proc/interaction_fit(mob/user)
	if(locked)
		to_chat(user, "full form effect")
		return
	fit()

/obj/machinery/pipe/proc/interaction_paint(mob/user)
	if(sealed) return to_chat(user, "sealed")
	paint()

/obj/machinery/pipe/proc/interaction_none(mob/user)
	if(sealed) return to_chat(user, "sealed")

/obj/machinery/pipe/proc/interaction_none2(mob/user)
	if(sealed) return to_chat(user, "sealed")

/obj/machinery/pipe/subtype/proc/interaction_fit(mob/user)
	if(sealed) return to_chat(user, "subtype of the declaring type")

/obj/machinery/unrelated/proc/interaction_fit(mob/user)
	if(sealed) return to_chat(user, "unrelated type")

/obj/machinery/proc/interaction_fit(mob/user)
	if(sealed) return to_chat(user, "ancestor of the declaring type")
