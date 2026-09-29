// Holowarrant viewer — structured TGUI panel for arrest/search warrants.

DECLARE_UI_STATE(/obj/item/holowarrant, GLOB.tgui_default_state)

DECLARE_UI(/obj/item/holowarrant, "Holowarrant", UI_TITLE("Holographic Warrant"))

UI_DATA_REPLACE(/obj/item/holowarrant, "merge:ui_data_obj_item_holowarrant{loaded:bool,kind:text,name:text,charges:text,auth:text,jurisdiction:text,station:text}")

/// The computed part of /obj/item/holowarrant's window data (declared on its UI_DATA row).
/obj/item/holowarrant/proc/ui_data_obj_item_holowarrant(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	if(!active())
		data["loaded"] = FALSE
		return data
	data["loaded"] = TRUE
	data["kind"] = "[active().fields["arrestsearch"]]"
	data["name"] = "[active().fields["namewarrant"]]"
	data["charges"] = "[active().fields["charges"]]"
	data["auth"] = "[active().fields["auth"]]"
	data["jurisdiction"] = "[using_map.boss_name]"
	data["station"] = "[using_map.station_name]"
	return data

/obj/item/holowarrant/proc/show_content(mob/user)
	if(!active())
		return
	tgui_interact(user)
