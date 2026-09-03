///SCI TELEPAD///
/obj/machinery/telepad
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "telepad"
	desc = "A bluespace telepad used for teleporting objects to and from a location."
	icon = 'icons/obj/telescience.dmi'
	icon_state = "pad-idle"
	anchored = TRUE
	use_power = USE_POWER_IDLE
	circuit = /obj/item/circuitboard/telesci_pad
	idle_power_usage = 200
	active_power_usage = 5000
	var/efficiency

/obj/machinery/telepad/Initialize(mapload)
	. = ..()
	component_parts = list()
	component_parts += new /obj/item/bluespace_crystal(src)
	component_parts += new /obj/item/stock_parts/capacitor(src)
	component_parts += new /obj/item/stock_parts/capacitor(src)
	component_parts += new /obj/item/stock_parts/console_screen(src)
	component_parts += new /obj/item/stack/cable_coil(src, 5)
	RefreshParts()
	update_icon()

/obj/machinery/telepad/RefreshParts()
	var/E
	for(var/obj/item/stock_parts/capacitor/C in component_parts)
		E += C.rating
	efficiency = E

/obj/machinery/telepad/attackby(obj/item/W as obj, mob/user as mob)
	src.add_fingerprint(user)

	if(default_part_replacement(user, W))
		return
	return ..()

/obj/machinery/telepad/multitool_act(mob/user, obj/item/tool)
	if(!panel_open)
		return ITEM_INTERACT_BLOCKING
	var/obj/item/multitool/multitool = tool
	multitool.connectable = src
	to_chat(user, span_warning("You save the data in the [multitool.name]'s buffer."))
	return ITEM_INTERACT_SUCCESS
