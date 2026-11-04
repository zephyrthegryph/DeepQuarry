///////////////////////////////////////////////////////////////////////
//Under clothing
/obj/item/clothing/under
	icon = 'icons/inventory/uniform/item.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_uniforms.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_uniforms.dmi',
		)
	name = "under"
	w_class = ITEMSIZE_NORMAL
	blood_sprite_state = "uniformblood"

	var/has_sensor = 1 //For the crew computer 2 = unable to change mode
	var/sensor_mode = 3
	var/sensorpref = 5
		/*
		1 = Report living/dead
		2 = Report detailed damages
		3 = Report location
		*/
	var/displays_id = 1
	var/rolled_down = -1 //0 = unrolled, 1 = rolled, -1 = cannot be toggled
	var/rolled_down_icon_override = TRUE
	var/rolled_sleeves = -1 //0 = unrolled, 1 = rolled, -1 = cannot be toggled
	var/rolled_sleeves_icon_override = TRUE
	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/uniform/mob_teshari.dmi',
		SPECIES_VOX = 'icons/inventory/uniform/mob_vox.dmi',
		SPECIES_WEREBEAST = 'icons/inventory/uniform/mob_werebeast.dmi'
		)

	//convenience var for defining the icon state for the overlay used when the clothing is worn.
	//Also used by rolling/unrolling.
	var/worn_state = null
	valid_accessory_slots = (\
		ACCESSORY_SLOT_UTILITY\
		|ACCESSORY_SLOT_WEAPON\
		|ACCESSORY_SLOT_ARMBAND\
		|ACCESSORY_SLOT_DECOR\
		|ACCESSORY_SLOT_MEDAL\
		|ACCESSORY_SLOT_INSIGNIA\
		|ACCESSORY_SLOT_TIE\
		|ACCESSORY_SLOT_RANK\
		|ACCESSORY_SLOT_DEPT\
		|ACCESSORY_SLOT_OVER\
		|ACCESSORY_SLOT_RING\
		|ACCESSORY_SLOT_WRIST)
	restricted_accessory_slots = (\
		ACCESSORY_SLOT_UTILITY\
		|ACCESSORY_SLOT_WEAPON\
		|ACCESSORY_SLOT_ARMBAND\
		|ACCESSORY_SLOT_TIE\
		|ACCESSORY_SLOT_RANK\
		|ACCESSORY_SLOT_DEPT\
		|ACCESSORY_SLOT_OVER)

	var/tmp/icon/rolled_down_icon = 'icons/inventory/uniform/mob_rolled_down.dmi' // an icon file resource ('*.dmi'), not an object reference
	var/tmp/icon/rolled_down_sleeves_icon = 'icons/inventory/uniform/mob_sleeves_rolled.dmi' // an icon file resource ('*.dmi'), not an object reference

	update_icon_define_digi = 'icons/inventory/uniform/mob_digi.dmi'

MSG_DEF_SELF(under/no_roll_down, "It can't be rolled down.")
MSG_DEF_SELF(under/no_roll_sleeves, "Its sleeves can't be rolled.")

CAPABILITIES(/obj/item/clothing/under)
	configure(atom_rules(armor_spec = ""))
	configure(obj_rules(show_messages = 1))
	configure(item_worn(covers = CHEST|ARMS|LEGS, slots = SLOT_ICLOTHING))
	configure(item_protection(permeability = 0.90, heat_parts = ARMS|LEGS|CHEST, cold_parts = ARMS|LEGS|CHEST))
	configure(item_sounds(equip = SFX_ITEMS_JUMPSUIT_EQUIP))
	op("under_worn_hand", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Under worn hand"), then(PROC_REF(under_worn_hand)))
	op("under_toggle_verb", menu(), label("Toggle Suit Sensors"), needs(carried()), then(PROC_REF(under_toggle_verb)))
	op("under_rollsuit_verb", menu(), label("Roll Down Jumpsuit"), needs(carried(), req_not(req_is(nameof(rolled_down), -1), because = MSG(under/no_roll_down))), then(PROC_REF(under_rollsuit_verb)))
	op("under_rollsleeves_verb", menu(), label("Roll Up Sleeves"), needs(carried(), req_not(req_is(nameof(rolled_sleeves), -1), because = MSG(under/no_roll_sleeves))), then(PROC_REF(under_rollsleeves_verb)))
	op("under_holster_verb", menu(), label("Holster"), needs(carried(), req(PROC_REF(pred_has_holster_holds))), then(PROC_REF(under_holster_verb)))
	setup(PROC_REF(configure_worn_state))

/// Native requirement: return null or the component refusal.
/obj/item/clothing/under/proc/pred_has_holster_holds(datum/act/op/A)
	for(var/obj/item/clothing/accessory/holster/H in accessories)
		return null
	return "it has no holster"

/// Old holster verb the holster added to the uniform: holster or draw with the attached holster.
/obj/item/clothing/under/proc/under_holster_verb(datum/act/op/A)
	var/obj/item/clothing/accessory/holster/H = locate_in_list(accessories, /obj/item/clothing/accessory/holster)
	if(H)
		H.holster_quick_holster_verb(A)

/// Old attack_hand: a worn uniform isn't pulled off by a click; its accessories get the touch.
/obj/item/clothing/under/proc/under_worn_hand(datum/act/op/A)
	var/mob/user = A.actor
	if ((ishuman(user) || issmall(user)) && src.loc == user)
		if(LAZYLEN(accessories))
			clothing_accessory_hand(A)
		return OP_OK
	return OP_DECLINE

/// Takes the sensor setting its wearer prefers and checks its rolled sprite.
/obj/item/clothing/under/proc/configure_worn_state()
	if(worn_state)
		LAZYSET(item_state_slots, slot_w_uniform_str, worn_state)
	else
		worn_state = icon_state

	//autodetect rollability
	if(rolled_down < 0)
		if((icon_exists(icon, "[worn_state]_d") || icon_exists(rolled_down_icon, worn_state) || icon_exists(icon_override, "[worn_state]_d")))
			rolled_down = 0

	if(!ishuman(loc))
		return

	var/mob/living/carbon/human/H = loc
	sensorpref = isnull(H) ? 1 : (ishuman(H) ? H.bio.sensorpref : 1)
	switch(sensorpref)
		if(1) sensor_mode = SUIT_SENSOR_OFF			//Sensors off
		if(2) sensor_mode = SUIT_SENSOR_BINARY		//Sensors on binary
		if(3) sensor_mode = SUIT_SENSOR_VITAL		//Sensors display vitals
		if(4) sensor_mode = SUIT_SENSOR_TRACKING	//Sensors display vitals and enables tracking
		if(5) sensor_mode = pick(SUIT_SENSOR_OFF, SUIT_SENSOR_BINARY, SUIT_SENSOR_VITAL, SUIT_SENSOR_TRACKING)	//Select a random setting
		else
			sensor_mode = pick(SUIT_SENSOR_OFF, SUIT_SENSOR_BINARY, SUIT_SENSOR_VITAL, SUIT_SENSOR_TRACKING)
			log_runtime("Invalid switch for suit sensors, defaulting to random. [sensorpref] chosen")

/obj/item/clothing/under/proc/update_rolldown_status()
	var/mob/living/carbon/human/H
	if(ishuman(src.loc))
		H = src.loc

	var/icon/under_icon
	if(icon_override && rolled_down_icon_override)
		under_icon = icon_override
	else if(H && LAZYACCESS(sprite_sheets, H.species.get_bodytype(H)))
		under_icon = sprite_sheets[H.species.get_bodytype(H)]
	else if(LAZYACCESS(item_icons, slot_w_uniform_str))
		under_icon = item_icons[slot_w_uniform_str]
	else if (icon_exists(rolled_down_icon, worn_state))
		under_icon = rolled_down_icon

	// The _s is because the icon update procs append it.
	if((under_icon == rolled_down_icon && (icon_exists(under_icon, worn_state))) || (icon_exists(under_icon, "[worn_state]_d")))
		if(rolled_down != 1)
			set_rolled_down(0)
	else
		set_rolled_down(-1)

/obj/item/clothing/under/proc/update_rollsleeves_status()
	var/mob/living/carbon/human/H
	if(ishuman(src.loc))
		H = src.loc

	var/icon/under_icon
	if(icon_override && rolled_sleeves_icon_override)
		under_icon = icon_override
	else if(H && LAZYACCESS(sprite_sheets, H.species.get_bodytype(H)))
		under_icon = sprite_sheets[H.species.get_bodytype(H)]
	else if(LAZYACCESS(item_icons, slot_w_uniform_str))
		under_icon = item_icons[slot_w_uniform_str]
	else if (icon_exists(rolled_down_sleeves_icon, worn_state))
		under_icon = rolled_down_sleeves_icon
	else
		under_icon = new /icon(INV_W_UNIFORM_DEF_ICON)

	// The _s is because the icon update procs append it.
	if((under_icon == rolled_down_sleeves_icon && (icon_exists(under_icon, worn_state))) || (icon_exists(under_icon, "[worn_state]_r")))
		if(rolled_sleeves != 1)
			set_rolled_sleeves(0)
	else
		set_rolled_sleeves(-1)

/obj/item/clothing/under/examine(mob/user)
	. = ..()
	switch(src.sensor_mode)
		if(0)
			. += "Its sensors appear to be disabled."
		if(1)
			. += "Its binary life sensors appear to be enabled."
		if(2)
			. += "Its vital tracker appears to be enabled."
		if(3)
			. += "Its vital tracker and tracking beacon appear to be enabled."

/obj/item/clothing/under/proc/set_sensors(mob/user)
	if (istype(user, /mob/observer)) return
	if (user.stat || user.restrained()) return
	if(has_sensor >= 2)
		to_chat(user, "The controls are locked.")
		return 0
	if(has_sensor <= 0)
		to_chat(user, "This suit does not have any sensors.")
		return 0

	var/static/list/modes = list(
		"Off" = SUIT_SENSOR_OFF,
		"Binary sensors" = SUIT_SENSOR_BINARY,
		"Vitals tracker" = SUIT_SENSOR_VITAL,
		"Tracking beacon" = SUIT_SENSOR_TRACKING
		)
	var/default_choice
	for(var/key, value in modes)
		if(value == sensor_mode)
			default_choice = key
			break
	open_request(src, /datum/prompt/choice/suit_sensor_mode, PROC_REF(sensor_mode_answered), answerer = user, choices = modes, default = default_choice)

/obj/item/clothing/under/proc/sensor_mode_refusal(mob/user, check_distance)
	if(istype(user, /mob/observer) || user.stat || user.restrained())
		return "sensor user unavailable"
	if(has_sensor >= 2)
		return "sensor controls locked"
	if(has_sensor <= 0)
		return "no suit sensors"
	if(check_distance && get_dist(user, src) > 1)
		return "too far from suit"
	return null

/obj/item/clothing/under/proc/sensor_mode_answered(datum/act/request/context)
	var/datum/prompt/choice/suit_sensor_mode/ask = context.request
	var/mob/user = ask.answerer
	if(QDELETED(user))
		return
	if(!context.answer)
		if(ask.outcome == REQ_CANCELLED && !isnull(ask.value))
			switch(ask.last_error)
				if("sensor controls locked")
					to_chat(user, "The controls are locked.")
				if("no suit sensors")
					to_chat(user, "This suit does not have any sensors.")
				if("too far from suit")
					to_chat(user, "You have moved too far away.")
			SStgui.update_uis(src)
		return
	apply_sensor_mode(user, ask.choices[ask.value])
	SStgui.update_uis(src)

/obj/item/clothing/under/proc/apply_sensor_mode(mob/user, new_mode)
	set_sensor_mode(new_mode)

	if (src.loc == user)
		switch(sensor_mode)
			if(SUIT_SENSOR_OFF)
				act_message(user, null, MSG_SELF("You disable your suit's remote sensing equipment."), MSG_OTHERS("%U% adjusts their sensors."))
			if(SUIT_SENSOR_BINARY)
				act_message(user, null, MSG_SELF("Your suit will now report whether you are live or dead."), MSG_OTHERS("%U% adjusts their sensors."))
			if(SUIT_SENSOR_VITAL)
				act_message(user, null, MSG_SELF("Your suit will now report your vital lifesigns."), MSG_OTHERS("%U% adjusts their sensors."))
			if(SUIT_SENSOR_TRACKING)
				act_message(user, null, MSG_SELF("Your suit will now report your vital lifesigns as well as your coordinate position."), \
					MSG_OTHERS("%U% adjusts their sensors."))

	else if (istype(src.loc, /mob))
		act_message(user, null, MSG_SELF("You adjust [src.loc]'s sensors."), MSG_OTHERS("%U% adjusts [src.loc]'s sensors."))

/// Old verb "Toggle Suit Sensors".
/obj/item/clothing/under/proc/under_toggle_verb(datum/act/op/A)
	var/mob/user = A.actor
	set_sensors(user)

/// Old verb "Roll Down Jumpsuit".
/obj/item/clothing/under/proc/under_rollsuit_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!isliving(user)) return
	if(user.stat) return

	update_rolldown_status()
	if(rolled_down == -1)
		to_chat(user, span_notice("You cannot roll down [src]!"))
		return
	if((rolled_sleeves == 1) && !(rolled_down))
		set_rolled_sleeves(0)

	set_rolled_down(!rolled_down)
	if(rolled_down)
		set_body_parts_covered(worn_of_type(type).covers)
		set_body_parts_covered(worn_of(src).covers & (~(UPPER_TORSO|ARMS)))
		protection_of(src).heat_parts &= ~(UPPER_TORSO|ARMS)
		protection_of(src).cold_parts &= ~(UPPER_TORSO|ARMS)
		if(icon_exists(rolled_down_icon, worn_state))
			set_icon_override(rolled_down_icon)
			set_item_state_slots_at(slot_w_uniform_str, worn_state)
		else
			set_item_state_slots_at(slot_w_uniform_str, "[worn_state]_d")

		to_chat(user, span_notice("You roll down your [src]."))
	else
		set_body_parts_covered(worn_of_type(type).covers)
		set_heat_protection(protection_of_type(type).heat_parts)
		set_cold_protection(protection_of_type(type).cold_parts)
		if(icon_override == rolled_down_icon)
			set_icon_override(initial(icon_override))
		set_item_state_slots_at(slot_w_uniform_str, worn_state)
		to_chat(user, span_notice("You roll up your [src]."))
	worn_protection_changed()

/// Old verb "Roll Up Sleeves".
/obj/item/clothing/under/proc/under_rollsleeves_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!isliving(user)) return
	if(user.stat) return

	update_rollsleeves_status()
	if(rolled_sleeves == -1)
		to_chat(user, span_notice("You cannot roll up your [src]'s sleeves!"))
		return
	if(rolled_down == 1)
		to_chat(user, span_notice("You must roll up your [src] first!"))
		return

	set_rolled_sleeves(!rolled_sleeves)
	if(rolled_sleeves)
		set_body_parts_covered(worn_of(src).covers & (~(ARMS)))
		protection_of(src).heat_parts &= ~(ARMS)
		protection_of(src).cold_parts &= ~(ARMS)
		if(icon_exists(rolled_down_sleeves_icon, worn_state))
			set_icon_override(rolled_down_sleeves_icon)
			set_item_state_slots_at(slot_w_uniform_str, worn_state)
		else
			set_item_state_slots_at(slot_w_uniform_str, "[worn_state]_r")
		to_chat(user, span_notice("You roll up your [src]'s sleeves."))
	else
		set_body_parts_covered(worn_of_type(type).covers)
		set_heat_protection(protection_of_type(type).heat_parts)
		set_cold_protection(protection_of_type(type).cold_parts)
		if(icon_override == rolled_down_sleeves_icon)
			set_icon_override(initial(icon_override))
		set_item_state_slots_at(slot_w_uniform_str, worn_state)
		to_chat(user, span_notice("You roll down your [src]'s sleeves."))
	worn_protection_changed()

CAPABILITIES(/obj/item/clothing/under/rank)
	rolls(nameof(sensor_mode), pick_one(list(0, 1, 2, 3)))

/obj/item/clothing/under/equipped(mob/user, slot)
	. = ..()
	handle_digitigrade(user)
