/obj/item/integrated_electronics/detailer
	name = "assembly detailer"
	desc = "A combination autopainter and flash anodizer designed to give electronic assemblies a colorful, wear-resistant finish."
	icon = 'icons/obj/integrated_electronics/electronic_tools.dmi'
	icon_state = "detailer"
	item_flags = NOBLUDGEON
	w_class = ITEMSIZE_SMALL
	var/detail_color = COLOR_ASSEMBLY_WHITE
	var/static/list/color_list = list(
		"dark gray" = COLOR_ASSEMBLY_BLACK,
		"machine gray" = COLOR_ASSEMBLY_BGRAY,
		"white" = COLOR_ASSEMBLY_WHITE,
		"red" = COLOR_ASSEMBLY_RED,
		"orange" = COLOR_ASSEMBLY_ORANGE,
		"beige" = COLOR_ASSEMBLY_BEIGE,
		"brown" = COLOR_ASSEMBLY_BROWN,
		"gold" = COLOR_ASSEMBLY_GOLD,
		"yellow" = COLOR_ASSEMBLY_YELLOW,
		"gurkha" = COLOR_ASSEMBLY_GURKHA,
		"light green" = COLOR_ASSEMBLY_LGREEN,
		"green" = COLOR_ASSEMBLY_GREEN,
		"light blue" = COLOR_ASSEMBLY_LBLUE,
		"blue" = COLOR_ASSEMBLY_BLUE,
		"purple" = COLOR_ASSEMBLY_PURPLE,
		"hot pink" = COLOR_ASSEMBLY_HOT_PINK
		)

/obj/item/integrated_electronics/detailer/draw(datum/look/look)
	..()
	look.overlay(look_appearance('icons/obj/integrated_electronics/electronic_tools.dmi', "detailer-color", color = detail_color))

/obj/item/integrated_electronics/detailer/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["detail_color"] = detail_color
	data["color_list"] = color_list
	return data

/obj/item/integrated_electronics/detailer/proc/ui_act_change_color(datum/act/op/A, color)
	if(!(color in color_list))
		return // to prevent href exploits causing runtimes
	detail_color = color_list[color]
	return TRUE

CAPABILITIES(/obj/item/integrated_electronics/detailer)
	op("controls", in_hand(), label("Open assembly detailer"), then(PROC_REF(detailer_controls_requested)))
	interface("ICDetailer", state = nameof(GLOB.tgui_inventory_state))
	without("ui_open")
	op("change_color", ui_act("change_color", arg("color", schema_text(4096))), then(PROC_REF(ui_act_change_color)))

/obj/item/integrated_electronics/detailer/proc/detailer_controls_requested(datum/act/op/A)
	tgui_interact(A.actor)
	return OP_OK

