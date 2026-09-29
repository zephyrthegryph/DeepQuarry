// Holowarrant viewer — structured TGUI panel for arrest/search warrants.

/obj/item/holowarrant/tgui_state(mob/user)
	return GLOB.tgui_default_state

DECLARE_UI(/obj/item/holowarrant, "Holowarrant", UI_TITLE("Holographic Warrant"))

/obj/item/holowarrant/tgui_data(mob/user)
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
