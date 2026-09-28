/datum/hud_data
	var/icon              // If set, overrides ui_style.
	var/has_a_intent = 1  // Set to draw intent box.
	var/has_m_intent = 1  // Set to draw move intent box.
	var/has_warnings = 1  // Set to draw environment warnings.
	var/has_pressure = 1  // Draw the pressure indicator.
	var/has_nutrition = 1 // Draw the nutrition indicator.
	var/has_bodytemp = 1  // Draw the bodytemp indicator.
	var/has_hands = 1     // Set to draw hands.
	var/has_drop = 1      // Set to draw drop button.
	var/has_throw = 1     // Set to draw throw button.
	var/has_resist = 1    // Set to draw resist button.
	var/has_internals = 1 // Set to draw the internals toggle button.
	var/list/equip_slots // Checked by mob_can_equip(). Shared by every hud_data of this type; read-only.

	// Contains information on the position and tag for all inventory slots
	// to be drawn for the mob. This is fairly delicate, try to avoid messing with it
	// unless you know exactly what it does.
	var/list/gear = list( // ALLOW(instance_list): kept: nested table shared per type in New(); the eager copy is dropped
		"i_clothing" =   list("loc" = ui_iclothing, "name" = "Uniform",      "slot" = SLOT_ID_UNIFORM, "state" = "center", "toggle" = 1),
		"o_clothing" =   list("loc" = ui_oclothing, "name" = "Suit",         "slot" = SLOT_ID_SUIT, "state" = "suit",   "toggle" = 1),
		"mask" =         list("loc" = ui_mask,      "name" = "Mask",         "slot" = SLOT_ID_MASK, "state" = "mask",   "toggle" = 1),
		"gloves" =       list("loc" = ui_gloves,    "name" = "Gloves",       "slot" = SLOT_ID_GLOVES,    "state" = "gloves", "toggle" = 1),
		"eyes" =         list("loc" = ui_glasses,   "name" = "Glasses",      "slot" = SLOT_ID_EYES,   "state" = "glasses","toggle" = 1),
		"l_ear" =        list("loc" = ui_l_ear,     "name" = "Left Ear",     "slot" = SLOT_ID_EAR_L,     "state" = "ears",   "toggle" = 1),
		"r_ear" =        list("loc" = ui_r_ear,     "name" = "Right Ear",    "slot" = SLOT_ID_EAR_R,     "state" = "ears",   "toggle" = 1),
		"head" =         list("loc" = ui_head,      "name" = "Hat",          "slot" = SLOT_ID_HEAD,      "state" = "hair",   "toggle" = 1),
		"shoes" =        list("loc" = ui_shoes,     "name" = "Shoes",        "slot" = SLOT_ID_SHOES,     "state" = "shoes",  "toggle" = 1),
		"suit storage" = list("loc" = ui_sstore1,   "name" = "Suit Storage", "slot" = SLOT_ID_SUIT_STORAGE,   "state" = "suitstore"),
		"back" =         list("loc" = ui_back,      "name" = "Back",         "slot" = SLOT_ID_BACK,      "state" = "back"),
		"id" =           list("loc" = ui_id,        "name" = "ID",           "slot" = SLOT_ID_ID,   "state" = "id"),
		"storage1" =     list("loc" = ui_storage1,  "name" = "Left Pocket",  "slot" = SLOT_ID_POCKET_L,   "state" = "pocket"),
		"storage2" =     list("loc" = ui_storage2,  "name" = "Right Pocket", "slot" = SLOT_ID_POCKET_R,   "state" = "pocket"),
		"belt" =         list("loc" = ui_belt,      "name" = "Belt",         "slot" = SLOT_ID_BELT,      "state" = "belt")
		)

/datum/hud_data/New()
	..()
	// gear (a table of 15 nested lists) and the equip_slots derived from it are
	// the same for every instance of a type, so each type builds them once.
	var/static/list/shared_gear = list()
	var/static/list/shared_slots = list()
	if(shared_gear[type])
		gear = shared_gear[type]
		equip_slots = shared_slots[type]
		return

	var/list/slots = list()
	for(var/slot in gear)
		slots |= gear[slot]["slot"]

	if(has_hands)
		slots |= SLOT_ID_HAND_L
		slots |= SLOT_ID_HAND_R
		slots |= SLOT_ID_HANDCUFFED

	if(SLOT_ID_BACK in slots)
		slots |= SLOT_ID_IN_BACKPACK

	if(SLOT_ID_UNIFORM in slots)
		slots |= SLOT_ID_TIE

	slots |= SLOT_ID_LEGCUFFED
	equip_slots = slots
	shared_gear[type] = gear
	shared_slots[type] = slots

/datum/hud_data/diona
	has_internals = 0
	gear = list(
		"i_clothing" =   list("loc" = ui_iclothing, "name" = "Uniform",      "slot" = SLOT_ID_UNIFORM, "state" = "center", "toggle" = 1),
		"o_clothing" =   list("loc" = ui_shoes,     "name" = "Suit",         "slot" = SLOT_ID_SUIT, "state" = "suit",   "toggle" = 1),
		"l_ear" =        list("loc" = ui_gloves,    "name" = "Ear",          "slot" = SLOT_ID_EAR_L,     "state" = "ears",   "toggle" = 1),
		"head" =         list("loc" = ui_oclothing, "name" = "Hat",          "slot" = SLOT_ID_HEAD,      "state" = "hair",   "toggle" = 1),
		"suit storage" = list("loc" = ui_sstore1,   "name" = "Suit Storage", "slot" = SLOT_ID_SUIT_STORAGE,   "state" = "suitstore"),
		"back" =         list("loc" = ui_back,      "name" = "Back",         "slot" = SLOT_ID_BACK,      "state" = "back"),
		"id" =           list("loc" = ui_id,        "name" = "ID",           "slot" = SLOT_ID_ID,   "state" = "id"),
		"storage1" =     list("loc" = ui_storage1,  "name" = "Left Pocket",  "slot" = SLOT_ID_POCKET_L,   "state" = "pocket"),
		"storage2" =     list("loc" = ui_storage2,  "name" = "Right Pocket", "slot" = SLOT_ID_POCKET_R,   "state" = "pocket"),
		"belt" =         list("loc" = ui_belt,      "name" = "Belt",         "slot" = SLOT_ID_BELT,      "state" = "belt")
		)

/datum/hud_data/monkey
	gear = list(
		"mask" =         list("loc" = ui_shoes,     "name" = "Mask", "slot" = SLOT_ID_MASK, "state" = "mask",  "toggle" = 1),
		"back" =         list("loc" = ui_sstore1,   "name" = "Back", "slot" = SLOT_ID_BACK,      "state" = "back"),
		"eyes" =         list("loc" = ui_glasses,   "name" = "Glasses",      "slot" = SLOT_ID_EYES,   "state" = "glasses","toggle" = 1),
		"l_ear" =        list("loc" = ui_l_ear,     "name" = "Left Ear",     "slot" = SLOT_ID_EAR_L,     "state" = "ears",   "toggle" = 1),
		"r_ear" =        list("loc" = ui_r_ear,     "name" = "Right Ear",    "slot" = SLOT_ID_EAR_R,     "state" = "ears",   "toggle" = 1),
		"head" =         list("loc" = ui_head,      "name" = "Hat",          "slot" = SLOT_ID_HEAD,      "state" = "hair",   "toggle" = 1),
		"id" =           list("loc" = ui_id,        "name" = "ID",           "slot" = SLOT_ID_ID,   "state" = "id")
		)
