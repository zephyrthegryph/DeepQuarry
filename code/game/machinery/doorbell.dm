////////////////////DOORBELL CHIME///////////////////////////////////////
/obj/machinery/doorbell_chime
	maintenance_flags = MACHINE_MAINT_PANEL
	name = "doorbell chime"
	desc = "Small wall-mounted chime triggered by a doorbell"
	icon = 'icons/obj/machines/doorbell_vr.dmi'
	icon_state = "dbchime-standby"
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 200
	anchored = TRUE
	flags = WALL_ITEM
	var/id_tag = null
	var/chime_sound = 'sound/machines/doorbell.ogg'

/obj/machinery/doorbell_chime/Initialize(mapload)
	. = ..()
	update_icon()

/obj/machinery/doorbell_chime/proc/chime()
	set waitfor = FALSE
	if(inoperable())
		return
	use_power(active_power_usage)
	playsound(src, chime_sound, 75)
	icon_state = "dbchime-active"
	set_light(2, 0.5, "#33FF33")
	visible_message("\The [src]'s light flashes.")
	sleep(30)
	set_light(0)
	update_icon()

/obj/machinery/doorbell_chime/power_change()
	..()
	update_icon()

/obj/machinery/doorbell_chime/update_icon()
	cut_overlays()
	if(panel_open)
		add_overlay("dbchime-open")
	if(inoperable())
		icon_state = "dbchime-off"
	if(!id_tag)
		icon_state = "dbchime-red"
	else
		icon_state = "dbchime-standby"

/obj/machinery/doorbell_chime/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/doorbell_chime_fingerprint,
		/datum/interaction/machine_item/part_replacement,
	)
	..()

/// Old attackby: added a fingerprint for any item before trying the part replacer.
/datum/interaction/machine_item/doorbell_chime_fingerprint
	id = "doorbell_chime_fingerprint"
	name = "Touch"
	held_type = /obj/item
	effect = /obj/machinery/doorbell_chime/proc/interaction_fingerprint

/obj/machinery/doorbell_chime/proc/interaction_fingerprint(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	return FALSE

/obj/machinery/doorbell_chime/multitool_act(mob/user, obj/item/tool)
	if(!panel_open)
		return ITEM_INTERACT_BLOCKING
	var/obj/item/multitool/multitool = tool
	if(multitool.connectable && istype(multitool.connectable, /obj/machinery/button/doorbell))
		var/obj/machinery/button/doorbell/button = multitool.connectable
		id_tag = button.id
		to_chat(user, span_notice("You upload the data from \the [tool]'s buffer."))
	return ITEM_INTERACT_SUCCESS

////////////////////DOORBELL CHIME CONSTRUCTION///////////////////////////////////////
// We want these to be constructable so more chimes can be added in departments.
/datum/frame/frame_types/doorbell_chime
	name = "Doorbell Chime"
	frame_class = "alarm"  // It isn't an alarm, but thats the construction flow we want.
	frame_size = 3
	frame_style = "wall"
	circuit = /obj/item/circuitboard/doorbell_chime
	icon_override = 'icons/obj/machines/doorbell_vr.dmi'
	x_offset = 32
	y_offset = 32

// Annoyingly we need to provide a circuit board even if never seen by players.
// Makes some sense, its how the frame code knows what to actually build. Alternative
// is to make building it a single-step process which is too quick I say.
// This links up the frame_type to the acutal machine to build. Never seen by players.
/obj/item/circuitboard/doorbell_chime
	build_path = /obj/machinery/doorbell_chime
	board_type = new /datum/frame/frame_types/doorbell_chime
	req_components = list()

////////////////////DOORBELL SWITCH///////////////////////////////////////

/obj/machinery/button/doorbell
	maintenance_flags = MACHINE_MAINT_PANEL
	name = "doorbell switch"
	desc = "A doorbell, press to chime."
	icon = 'icons/obj/machines/doorbell_vr.dmi'
	icon_state = "doorbell-standby"
	use_power = USE_POWER_OFF
	flags = WALL_ITEM

/obj/machinery/button/doorbell/Initialize(mapload, dir, building = FALSE)
	. = ..()
	if(building)
		pixel_x = (dir & 3)? 0 : (dir == 4 ? -32 : 32)
		pixel_y = (dir & 3)? (dir ==1 ? -27 : 27) : 0
	if (!id)
		assign_uid()
		id = num2text(uid)
	update_icon()

/obj/machinery/button/doorbell/power_change()
	..()
	update_icon()

/obj/machinery/button/doorbell/update_icon()
	if(stat & (NOPOWER|BROKEN))
		icon_state = "doorbell-off"
	else
		icon_state = "doorbell-standby"

/obj/machinery/button/doorbell/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/doorbell_press,
		/datum/interaction/machine_item/doorbell_rename,
	)
	..()

/// Old attack_hand: press the button, chime the linked chimes.
/datum/interaction/machine_hand/doorbell_press
	id = "doorbell_press"
	name = "Press"
	effect = /obj/machinery/button/doorbell/proc/interaction_press

/obj/machinery/button/doorbell/interaction_press(mob/user, obj/item/held, datum/interaction/interaction)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	use_power(5)
	flick("doorbell-active", src)

	for(var/obj/machinery/doorbell_chime/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id_tag == id)
			M.chime()
	return TRUE

/// Old attackby: fingerprint any item, and rename with a pen when the panel is open.
/datum/interaction/machine_item/doorbell_rename
	id = "doorbell_rename"
	name = "Touch"
	held_type = /obj/item
	effect = /obj/machinery/button/doorbell/proc/interaction_rename

/obj/machinery/button/doorbell/proc/interaction_rename(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	if(panel_open && istype(held, /obj/item/pen))
		var/t = sanitizeSafe(tgui_input_text(user, "Enter the name for \the [src].", name, initial(name), MAX_NAME_LEN, encode = FALSE), MAX_NAME_LEN)
		if(t && in_range(src, user))
			name = t
	return TRUE

/obj/machinery/button/doorbell/multitool_act(mob/user, obj/item/tool)
	if(!panel_open)
		return ITEM_INTERACT_BLOCKING
	var/obj/item/multitool/M = tool
	M.connectable = src
	to_chat(user, span_notice("You save the data in \the [M]'s buffer."))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/button/doorbell/wrench_act(mob/user, obj/item/tool)
	to_chat(user, span_notice("You start to unwrench \the [src]."))
	playsound(src, 'sound/items/Ratchet.ogg', 50, TRUE)
	if(!do_after(user, 15, target = src) || QDELETED(src))
		return ITEM_INTERACT_BLOCKING
	to_chat(user, span_notice("You unwrench \the [src]."))
	new /obj/item/frame/doorbell(loc)
	qdel(src)
	return ITEM_INTERACT_SUCCESS

////////////////////DOORBELL SWITCH CONSTRUCTION///////////////////////////////////////
// Right now they are very simple to construct, just throw them up on the wall

/obj/item/frame/doorbell
	name = "doorbell switch frame"
	desc = "Used for building doorbell switches."
	icon = 'icons/obj/machines/doorbell_vr.dmi'
	icon_state = "doorbell-off"
	refund_amt = 4
	refund_type = /obj/item/stack/material/wood
	build_machine_type = /obj/machinery/button/doorbell
