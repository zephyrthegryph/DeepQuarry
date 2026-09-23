/obj/item/clothing/gloves/arm_guard
	name = DEVELOPER_WARNING_NAME // "arm guards"
	desc = "These arm guards will protect your hands and arms."
	body_parts_covered = HANDS|ARMS
	overgloves = 1
	punch_force = 3
	w_class = ITEMSIZE_NORMAL
	drop_sound = 'sound/items/drop/metalshield.ogg'
	pickup_sound = 'sound/items/pickup/axe.ogg'
	resistance_flags = FIRE_PROOF

/obj/item/clothing/gloves/arm_guard/equip_constraint()
	return dq_spec_join(..(), list(REQ_ON(PRED_TARGET, /obj/item/clothing/gloves/arm_guard/proc/suit_clearance, null)))

/obj/item/clothing/gloves/arm_guard/proc/suit_clearance(mob/living/carbon/human/H)
	if(!istype(H) || !H.get_equipped_item(SLOT_ID_SUIT))
		return TRUE
	if(H.get_equipped_item(SLOT_ID_SUIT).body_parts_covered & ARMS)
		return "\the [H.get_equipped_item(SLOT_ID_SUIT)] is in the way"
	for(var/obj/item/clothing/accessory/A in H.get_equipped_item(SLOT_ID_SUIT))
		if(A.body_parts_covered & ARMS)
			return "\the [H.get_equipped_item(SLOT_ID_SUIT)]'s [A] is in the way"
	return TRUE

/obj/item/clothing/gloves/arm_guard/laserproof
	name = "ablative arm guards"
	desc = "These arm guards will protect your hands and arms from energy weapons."
	icon_state = "arm_guards_laser"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	siemens_coefficient = 0.4 //This is worse than the other ablative pieces, to avoid this from becoming the poor warden's insulated gloves.
	armor = list(melee = 10, bullet = 10, laser = 80, energy = 50, bomb = 0, bio = 0, rad = 0)

/obj/item/clothing/gloves/arm_guard/bulletproof
	name = "bullet resistant arm guards"
	desc = "These arm guards will protect your hands and arms from ballistic weapons."
	icon_state = "arm_guards_bullet"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	siemens_coefficient = 0.7
	armor = list(melee = 10, bullet = 80, laser = 10, energy = 10, bomb = 0, bio = 0, rad = 0)

/obj/item/clothing/gloves/arm_guard/riot
	name = "riot arm guards"
	desc = "These arm guards will protect your hands and arms from close combat weapons."
	icon_state = "arm_guards_riot"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	siemens_coefficient = 0.5
	armor = list(melee = 80, bullet = 10, laser = 10, energy = 10, bomb = 0, bio = 0, rad = 0)

/obj/item/clothing/gloves/arm_guard/combat
	name = "combat arm guards"
	desc = "These arm guards will protect your hands and arms from a variety of weapons."
	icon_state = "arm_guards_combat"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	siemens_coefficient = 0.6
	armor = list(melee = 50, bullet = 50, laser = 50, energy = 30, bomb = 30, bio = 0, rad = 0)

/obj/item/clothing/gloves/arm_guard/flexitac
	name = "tactical arm guards"
	desc = "These arm guards will protect your hands and arms from a variety of weapons while still allowing mobility."
	icon_state = "arm_guards_flexitac"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	siemens_coefficient = 0.6
	armor = list(melee = 40, bullet = 40, laser = 60, energy = 35, bomb = 30, bio = 0, rad = 0)
	min_cold_protection_temperature = T0C - 20
	cold_protection = ARMS


/obj/item/clothing/gloves/arm_guard/combat/imperial
	name = "imperial gauntlets"
	desc = "Made of some exotic metal, and crafted by space elves. Elves have delicate hands."
	icon_state = "ge_gloves"
	icon = 'icons/inventory/hands/item.dmi'
	icon = 'icons/inventory/hands/mob.dmi'
