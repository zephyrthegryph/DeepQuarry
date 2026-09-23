/obj/item/clothing/shoes/leg_guard
	name = DEVELOPER_WARNING_NAME // "leg guards"
	desc = "These will protect your legs and feet."
	body_parts_covered = LEGS|FEET
	slowdown = SHOES_SLOWDOWN+0.5
	w_class = ITEMSIZE_NORMAL
	step_volume_mod = 1.3
	can_hold_knife = TRUE
	drop_sound = 'sound/items/drop/boots.ogg'
	pickup_sound = 'sound/items/pickup/boots.ogg'
	resistance_flags = FIRE_PROOF

/obj/item/clothing/shoes/leg_guard/fit_constraint()
	return null

/obj/item/clothing/shoes/leg_guard/equip_constraint()
	return dq_spec_join(..(), list(REQ_ON(PRED_TARGET, /obj/item/clothing/shoes/leg_guard/proc/suit_clearance, null)))

/obj/item/clothing/shoes/leg_guard/proc/suit_clearance(mob/living/carbon/human/H)
	if(!istype(H) || !H.get_equipped_item(SLOT_ID_SUIT))
		return TRUE
	if(H.get_equipped_item(SLOT_ID_SUIT).body_parts_covered & LEGS)
		return "\the [H.get_equipped_item(SLOT_ID_SUIT)] is in the way"
	for(var/obj/item/clothing/accessory/A in H.get_equipped_item(SLOT_ID_SUIT))
		if(A.body_parts_covered & LEGS)
			return "\the [H.get_equipped_item(SLOT_ID_SUIT)]'s [A] is in the way"
	return TRUE

/obj/item/clothing/shoes/leg_guard/laserproof
	name = "ablative leg guards"
	desc = "These will protect your legs and feet from energy weapons."
	icon_state = "leg_guards_laser"
	item_state_slots = list(slot_r_hand_str = "jackboots", slot_l_hand_str = "jackboots")
	siemens_coefficient = 0.1
	armor_spec = "melee=10;bullet=10;laser=80;energy=50"

/obj/item/clothing/shoes/leg_guard/bulletproof
	name = "bullet resistant leg guards"
	desc = "These will protect your legs and feet from ballistic weapons."
	icon_state = "leg_guards_bullet"
	item_state_slots = list(slot_r_hand_str = "jackboots", slot_l_hand_str = "jackboots")
	siemens_coefficient = 0.7
	armor_spec = "melee=10;bullet=80;laser=10;energy=10"

/obj/item/clothing/shoes/leg_guard/riot
	name = "riot leg guards"
	desc = "These will protect your legs and feet from close combat weapons."
	icon_state = "leg_guards_riot"
	item_state_slots = list(slot_r_hand_str = "jackboots", slot_l_hand_str = "jackboots")
	siemens_coefficient = 0.5
	armor_spec = "melee=80;bullet=10;laser=10;energy=10"

/obj/item/clothing/shoes/leg_guard/combat
	name = "combat leg guards"
	desc = "These will protect your legs and feet from a variety of weapons."
	icon_state = "leg_guards_combat"
	item_state_slots = list(slot_r_hand_str = "jackboots", slot_l_hand_str = "jackboots")
	siemens_coefficient = 0.6
	armor_spec = "melee=50;bullet=50;laser=50;energy=30;bomb=30"

/obj/item/clothing/shoes/leg_guard/flexitac
	name = "tactical leg guards"
	desc = "These will protect your legs and feet from a variety of weapons while still allowing mobility."
	icon_state = "leg_guards_flexitac"
	item_state_slots = list(slot_r_hand_str = "jackboots", slot_l_hand_str = "jackboots")
	siemens_coefficient = 0.6
	slowdown = SHOES_SLOWDOWN+0.5
	armor_spec = "melee=40;bullet=40;laser=60;energy=35;bomb=30"
	min_cold_protection_temperature = T0C - 20
	cold_protection = LEGS


/obj/item/clothing/shoes/leg_guard/combat/imperial
	name = "imperial leg guards"
	desc = "Good for Roman around."
	icon_state = "ge_boots"
