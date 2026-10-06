// Implant chair — structured TGUI.

/obj/machinery/implantchair/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/implantchair_open_ui,
	)
	..()

/// Old attack_hand (never called ..()): set_machine() then open the interface.
/datum/interaction/machine_hand/ungated/implantchair_open_ui
	id = "implantchair_open_ui"
	name = "Use"
	effect = /obj/machinery/implantchair/proc/interaction_open_ui_impl

/obj/machinery/implantchair/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	user.set_machine(src)
	tgui_interact(user)
	return TRUE

/// /obj/machinery/implantchair's window data.
/obj/machinery/implantchair/ui_data(datum/act/eval/A)
	var/list/data = list()
	var/mob/living/carbon/occupant = slot_item_real(OCCUPANT_SLOT_IMPLANT_CHAIR)
	data["has_occupant"] = !!occupant
	if(occupant)
		data["occupant_name"] = "[occupant]"
		var/health_text = "[round(occupant.vitality() * 100, 0.1)]%"
		data["health_text"] = health_text
		data["dead"] = occupant.stat == DEAD
		data["damaged"] = occupant.is_critical()
	data["implants_left"] = implant_list ? implant_list.len : 0
	data["ready"] = !!ready
	return data

/obj/machinery/implantchair/proc/ui_act_implant(datum/act/op/A)
	var/mob/user = A.actor
	start_implant(user)
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/implantchair/proc/ui_act_replenish(datum/act/op/A)
	var/mob/user = A.actor
	start_replenish(user)
	SStgui.update_uis(src)
	return TRUE
