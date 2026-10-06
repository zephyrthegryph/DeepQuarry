// Holowarrant viewer — structured TGUI panel for arrest/search warrants.

CAPABILITIES(/obj/item/holowarrant)
	interface("Holowarrant", title = "Holographic Warrant", state = nameof(GLOB.tgui_default_state))
	without("ui_open")
	ui_shape(loaded = bool(), kind = schema_text(), name = schema_text(), charges = schema_text(), auth = schema_text(), jurisdiction = schema_text(), station = schema_text())

/// /obj/item/holowarrant's window data.
/obj/item/holowarrant/ui_data(datum/act/eval/A)
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
