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

DECLARE_UI_STATE(/obj/machinery/implantchair, GLOB.tgui_default_state)

DECLARE_UI(/obj/machinery/implantchair, "ImplantChair", UI_TITLE("Implanter Status"))

UI_DATA_REPLACE(/obj/machinery/implantchair, "merge:ui_data_obj_machinery_implantchair{has_occupant:bool,occupant_name:text,health_text:text,dead:bool,damaged:unknown,implants_left:num,ready:bool}")

/// The computed part of /obj/machinery/implantchair's window data (declared on its UI_DATA row).
/obj/machinery/implantchair/proc/ui_data_obj_machinery_implantchair(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

UI_ACT(/obj/machinery/implantchair, "implant", ui_act_implant)
UI_ACT_PROC(/obj/machinery/implantchair, ui_act_implant)
	start_implant(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/implantchair, "replenish", ui_act_replenish)
UI_ACT_PROC(/obj/machinery/implantchair, ui_act_replenish)
	start_replenish(ui.user)
	SStgui.update_uis(src)
	return TRUE
