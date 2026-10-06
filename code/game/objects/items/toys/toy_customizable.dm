/obj/item/toy/plushie/customizable
	name = "You shouldn't be seeing this..."
	desc = "Allan, please add details!"
	icon = 'icons/obj/customizable_toys/durg.dmi'
	icon_state = "blankdurg"
	pokephrase = "Squeaky!"

	var/base_color = "#FFFFFF"
	var/list/possible_overlays
	var/list/added_overlays

DECLARE_APPEARANCE_PROC(/obj/item/toy/plushie/customizable, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/toy/plushie/customizable/appearance_overlays()
	. = list()
	var/mutable_appearance/B = mutable_appearance(icon, icon_state)
	B.color = base_color
	. += B
	if(added_overlays)
		for(var/key, value in added_overlays)
			var/mutable_appearance/our_image = mutable_appearance(icon, key)
			our_image.color = value["color"]
			our_image.alpha = value["alpha"]
			. += our_image

/obj/item/toy/plushie/customizable/Initialize(mapload)
	. = ..()
	update_icon()

/// /obj/item/toy/plushie/customizable's window data.
/obj/item/toy/plushie/customizable/ui_data(datum/act/eval/A)
	var/list/possible_overlay_data = list()
	if(possible_overlays)
		for(var/overlay_state,name in possible_overlays)
			UNTYPED_LIST_ADD(possible_overlay_data, list(
				"name" = name,
				"icon_state" = overlay_state
			))

	var/list/our_overlays = list()
	if(added_overlays)
		for(var/overlay_state,overlay in added_overlays)
			UNTYPED_LIST_ADD(our_overlays, list(
				"icon_state" = overlay_state,
				"name" = possible_overlays[overlay_state],
				"color" = overlay["color"],
				"alpha" = overlay["alpha"]
			))

	var/list/data = list(
		"base_color" = base_color,
		"name" = name,
		"icon" = icon,
		"preview" = icon2base64(get_flat_icon(src)),
		"possible_overlays" = possible_overlay_data,
		"overlays" = our_overlays
	)
	return data

/// A plushie colour: its base or one added overlay, asked by the window's op (the window re-checks who may still use it).
/datum/prompt/color/plushie
	question = "Choose a color:"
	timeout = 0

/// The overlay a colour button names is on the plushie: only then is its colour asked.
/obj/item/toy/plushie/customizable/proc/overlay_added(datum/act/op/A)
	return !!LAZYACCESS(added_overlays, A.args["icon_state"]) // ALLOW(reads): asked once, when the button is pressed, to decide whether its question opens

/obj/item/toy/plushie/customizable/proc/overlay_color_title(datum/act/op/A)
	return LAZYACCESS(possible_overlays, A.args["icon_state"])

/obj/item/toy/plushie/customizable/proc/plushie_base_color(datum/act/op/A)
	return base_color

/obj/item/toy/plushie/customizable/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(!added_overlays)
		added_overlays = list()
	return TRUE

/obj/item/toy/plushie/customizable/proc/ui_act_add_overlay(datum/act/op/A, new_overlay_arg)
	if(!ui_gate(A))
		return FALSE
	if(!possible_overlays)
		return FALSE
	var/new_overlay = new_overlay_arg
	if(!(new_overlay in possible_overlays))
		return FALSE
	. = TRUE
	added_overlays[new_overlay] = list(color = "#FFFFFF", alpha = 255)
	update_icon()

/obj/item/toy/plushie/customizable/proc/ui_act_remove_overlay(datum/act/op/A, removed_overlay_arg)
	if(!ui_gate(A))
		return FALSE
	if(!added_overlays)
		return FALSE
	var/removed_overlay = removed_overlay_arg
	if(!(removed_overlay in added_overlays))
		return FALSE
	. = TRUE
	added_overlays.Remove(removed_overlay)
	update_icon()

/obj/item/toy/plushie/customizable/proc/ui_act_change_overlay_color(datum/act/op/A, icon_state)
	if(!ui_gate(A))
		return FALSE
	if(!possible_overlays)
		return FALSE
	var/selected_icon_state = icon_state
	if(!(selected_icon_state in possible_overlays))
		return FALSE
	. = TRUE
	var/list/target = added_overlays[selected_icon_state]
	if(!target)
		return FALSE
	target["color"] = A.step_value("color")
	update_icon()

/obj/item/toy/plushie/customizable/proc/ui_act_move_overlay_up(datum/act/op/A, icon)
	if(!ui_gate(A))
		return FALSE
	var/target = icon
	var/idx = added_overlays.Find(target)
	if(!idx)
		return FALSE
	. = TRUE
	if (idx < added_overlays.len)
		added_overlays.Swap(idx, idx + 1)
	update_icon()

/obj/item/toy/plushie/customizable/proc/ui_act_move_overlay_down(datum/act/op/A, icon)
	if(!ui_gate(A))
		return FALSE
	var/target = icon
	var/idx = added_overlays.Find(target)
	if(!idx)
		return FALSE
	. = TRUE
	if (idx > 1)
		added_overlays.Swap(idx, idx - 1)
	update_icon()

/obj/item/toy/plushie/customizable/proc/ui_act_change_base_color(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	. = TRUE
	base_color = A.step_value("color")
	update_icon()

/obj/item/toy/plushie/customizable/proc/ui_act_set_overlay_alpha(datum/act/op/A, alpha, icon_state)
	if(!ui_gate(A))
		return FALSE
	var/target = added_overlays[icon_state]
	if(!target)
		return FALSE
	. = TRUE
	var/new_alpha = alpha
	target["alpha"] = new_alpha
	update_icon()

/obj/item/toy/plushie/customizable/proc/ui_act_import_config(datum/act/op/A, config)
	if(!ui_gate(A))
		return FALSE
	if(!isnull(config) && !islist(config))
		return FALSE
	. = TRUE
	var/our_data = config
	base_color = sanitize_hexcolor(our_data["base_color"])
	var/new_name = sanitize_name(our_data["name"])
	if(new_name)
		set_new_name(new_name)
	added_overlays.Cut()
	if(!possible_overlays)
		return
	for(var/overlay in our_data["overlays"])
		if(possible_overlays.Find(overlay["icon_state"]))
			var/new_color = sanitize_hexcolor(overlay["color"])
			var/new_alpha = CLAMP(text2num(overlay["alpha"]), 0, 255)
			added_overlays[overlay["icon_state"]] = list(color = new_color, alpha = new_alpha)
	update_icon()

CAPABILITIES(/obj/item/toy/plushie/customizable)
	op("clear", ui_act(), then(PROC_REF(ui_act_clear)))
	interface("PlushieEditor", state = nameof(GLOB.tgui_conscious_state))
	without("ui_open")
	op("add_overlay", ui_act("add_overlay", arg("new_overlay", schema_text(4096))), then(PROC_REF(ui_act_add_overlay)))
	op("remove_overlay", ui_act("remove_overlay", arg("removed_overlay", schema_text(4096))), then(PROC_REF(ui_act_remove_overlay)))
	op("change_overlay_color", ui_act("change_overlay_color", arg("icon_state", schema_text(4096))),
		asks(/datum/prompt/color/plushie, fields = list("title" = computed(PROC_REF(overlay_color_title)), "default" = computed(PROC_REF(plushie_base_color))), step = "color", when = PROC_REF(overlay_added)),
		then(PROC_REF(ui_act_change_overlay_color)))
	op("move_overlay_up", ui_act("move_overlay_up", arg("icon", schema_text(4096))), then(PROC_REF(ui_act_move_overlay_up)))
	op("move_overlay_down", ui_act("move_overlay_down", arg("icon", schema_text(4096))), then(PROC_REF(ui_act_move_overlay_down)))
	op("change_base_color", ui_act("change_base_color"),
		asks(/datum/prompt/color/plushie, fields = list("title" = "Plushie base color", "default" = computed(PROC_REF(plushie_base_color))), step = "color"),
		then(PROC_REF(ui_act_change_base_color)))
	op("set_overlay_alpha", ui_act("set_overlay_alpha", arg("alpha", num()), arg("icon_state", schema_text(4096))), then(PROC_REF(ui_act_set_overlay_alpha)))
	op("import_config", ui_act("import_config", arg("config")), then(PROC_REF(ui_act_import_config)))
	op("rename", ui_act("rename", arg("name", schema_text(4096))), then(PROC_REF(ui_act_rename)))
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), label("Alternate use"), then(PROC_REF(interaction_alt)))

/obj/item/toy/plushie/customizable/proc/ui_act_clear(datum/act/op/A)
	add_fingerprint(A.actor)
	if(!added_overlays)
		added_overlays = list()
	added_overlays.Cut()
	base_color = "#FFFFFF"
	update_icon()
	return OP_OK

/obj/item/toy/plushie/customizable/proc/ui_act_rename(datum/act/op/A, name)
	if(!ui_gate(A))
		return FALSE
	return set_new_name(name)

/obj/item/toy/plushie/customizable/proc/set_new_name(new_name)
	var/sane_name = sanitize_name(new_name)
	if(!sane_name)
		return FALSE
	name = sane_name
	adjusted_name = sane_name
	return TRUE

/// Old click_alt.
/obj/item/toy/plushie/customizable/proc/interaction_alt(datum/act/op/A)
	var/mob/user = A.actor
	tgui_interact(user)
	return TRUE

/obj/item/toy/plushie/customizable/dragon
	name = "custom dragon plushie"
	desc = "A customizable, modular plushie in the shape of a dragon. How cute!"
	pokephrase = "Gawr!"
	possible_overlays = list(
		"durg_underbelly" = "Underbelly",
		"durg_fur" = "Fur",
		"durg_spines" = "Spines",
		"classic_w_1" = "Wings, Western, L",
		"classic_w_2" = "Wings, Western, R",
		"classic_w_misc" = "Wings, Western, Underside",
		"fairy_w_1" = "Wings, Fairy, L",
		"fairy_w_2" = "Wings, Fairy, R",
		"fairy_w_misc" = "Wings, Fairy, L Extra",
		"angular_w_1" = "Wings, Angular, L",
		"angular_w_2" = "Wings, Angular, R",
		"angular_w_misc" = "Wings, Angular, L Extra",
		"double_h_1" = "Horns, Double, L",
		"double_h_2" = "Horns, Double, R",
		"classic_h_1" = "Horns, Classic, L",
		"classic_h_2" = "Horns, Classic, R",
		"thick_h_1" = "Horns, Thick, L",
		"thick_h_2" = "Horns, Thick, R"
	)
