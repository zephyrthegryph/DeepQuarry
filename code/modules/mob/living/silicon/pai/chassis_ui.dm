// Pai chassis selection
/datum/tgui_module/pai_chassis
	name = "PAI Chassis Configurator"
	tgui_id = "PaiChoose"
	var/selected_chassis
	var/selected_color

/datum/tgui_module/pai_chassis/tgui_state(mob/user)
	return GLOB.tgui_self_state

/datum/tgui_module/pai_chassis/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet_batched/pai_icons),
	)

/datum/tgui_module/pai_chassis/tgui_static_data(mob/user)
	var/list/data = ..()
	var/list/available_sprites = list()
	var/mob/living/silicon/pai/pai_host = host()
	for(var/key, value in GLOB.pai_service.get_chassis_list())
		var/datum/pai_sprite/current_sprite = value
		var/model_type = "def"
		if(istype(current_sprite, /datum/pai_sprite/large))
			model_type = "big"
		if(current_sprite.emagged && (!pai_host.card.emagged || !pai_host.card.has_emag_toolkit))
			continue
		UNTYPED_LIST_ADD(available_sprites, list("sprite" = current_sprite.name, "belly" = current_sprite.belly_states, "type" = model_type))
	data["pai_chassises"] = available_sprites

	return data

/datum/tgui_module/pai_chassis/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	var/mob/living/silicon/pai/pai_host = host()
	data["pai_color"] = selected_color ? selected_color : pai_host.eye_color

	var/datum/pai_sprite/sprite_datum = GLOB.pai_service.chassis_data(selected_chassis || pai_host.chassis_name)
	if(sprite_datum)
		var/datum/asset/spritesheet_batched/pai_icons/spritesheet = get_asset_datum(/datum/asset/spritesheet_batched/pai_icons)
		data["pai_chassis"] = sprite_datum.name
		data["selected_chassis"] = selected_chassis
		data["sprite_datum_class"] = sanitize_css_class_name("[sprite_datum.type]")
		data["sprite_datum_size"] = spritesheet.icon_size_id(data["sprite_datum_class"] + "S") // just get the south icon's size, the rest will be the same

	return data

UI_ACT(/datum/tgui_module/pai_chassis, "pick_icon", ui_act_pick_icon, UI_ARG_VALUE("value"))
UI_ACT_PROC(/datum/tgui_module/pai_chassis, ui_act_pick_icon)
	var/new_chassis = params["value"]
	if(new_chassis && (new_chassis in GLOB.pai_service.get_chassis_list()))
		selected_chassis = new_chassis
	return TRUE

UI_ACT(/datum/tgui_module/pai_chassis, "confirm", ui_act_confirm)
UI_ACT_PROC(/datum/tgui_module/pai_chassis, ui_act_confirm)
	if(!selected_chassis)
		return FALSE
	var/mob/living/silicon/pai/pai_host = host()
	if(selected_color)
		pai_host.eye_color = selected_color
	pai_host.change_chassis(selected_chassis)
	return TRUE

UI_ACT(/datum/tgui_module/pai_chassis, "change_color", ui_act_change_color, UI_ARG_TEXT("color"))
UI_ACT_PROC(/datum/tgui_module/pai_chassis, ui_act_change_color)
	var/new_color = sanitize_hexcolor(params["color"])
	if(!new_color)
		return FALSE
	selected_color = new_color
	return TRUE
