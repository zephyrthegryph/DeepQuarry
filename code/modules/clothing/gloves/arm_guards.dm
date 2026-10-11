/obj/item/clothing/gloves/arm_guard
	name = DEVELOPER_WARNING_NAME // "arm guards"
	desc = "These arm guards will protect your hands and arms."
	body_parts_covered = HANDS|ARMS
	overgloves = 1
	punch_force = 3
	w_class = ITEMSIZE_NORMAL
	resistance_flags = FIRE_PROOF

CAPABILITIES(/obj/item/clothing/gloves/arm_guard)
	acceptance("equip", req_acceptance_arm_clearance(), mode = ACCEPTANCE_APPEND)
	configure(item_sounds(drop = SFX_ITEMS_DROP_METALSHIELD, pickup = SFX_ITEMS_PICKUP_AXE))



/obj/item/clothing/gloves/arm_guard/proc/suit_clearance(datum/act/op/A)
	var/mob/living/carbon/human/H = A.wearer
	if(!istype(H) || !H.get_equipped_item(SLOT_ID_SUIT))
		return null
	if(H.get_equipped_item(SLOT_ID_SUIT).body_parts_covered & ARMS)
		return "\the [H.get_equipped_item(SLOT_ID_SUIT)] is in the way"
	for(var/obj/item/clothing/accessory/W in H.get_equipped_item(SLOT_ID_SUIT))
		if(W.body_parts_covered & ARMS)
			return "\the [H.get_equipped_item(SLOT_ID_SUIT)]'s [W] is in the way"
	return null

/obj/item/clothing/gloves/arm_guard/laserproof
	name = "ablative arm guards"
	desc = "These arm guards will protect your hands and arms from energy weapons."
	icon_state = "arm_guards_laser"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	armor_spec = "melee=10;bullet=10;laser=80;energy=50"

CAPABILITIES(/obj/item/clothing/gloves/arm_guard/laserproof)
	configure(item_protection(siemens = 0.4))

/obj/item/clothing/gloves/arm_guard/bulletproof
	name = "bullet resistant arm guards"
	desc = "These arm guards will protect your hands and arms from ballistic weapons."
	icon_state = "arm_guards_bullet"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	armor_spec = "melee=10;bullet=80;laser=10;energy=10"

CAPABILITIES(/obj/item/clothing/gloves/arm_guard/bulletproof)
	configure(item_protection(siemens = 0.7))

/obj/item/clothing/gloves/arm_guard/riot
	name = "riot arm guards"
	desc = "These arm guards will protect your hands and arms from close combat weapons."
	icon_state = "arm_guards_riot"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	armor_spec = "melee=80;bullet=10;laser=10;energy=10"

CAPABILITIES(/obj/item/clothing/gloves/arm_guard/riot)
	configure(item_protection(siemens = 0.5))

/obj/item/clothing/gloves/arm_guard/combat
	name = "combat arm guards"
	desc = "These arm guards will protect your hands and arms from a variety of weapons."
	icon_state = "arm_guards_combat"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	armor_spec = "melee=50;bullet=50;laser=50;energy=30;bomb=30"

CAPABILITIES(/obj/item/clothing/gloves/arm_guard/combat)
	configure(item_protection(siemens = 0.6))

/obj/item/clothing/gloves/arm_guard/flexitac
	name = "tactical arm guards"
	desc = "These arm guards will protect your hands and arms from a variety of weapons while still allowing mobility."
	icon_state = "arm_guards_flexitac"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	armor_spec = "melee=40;bullet=40;laser=60;energy=35;bomb=30"

CAPABILITIES(/obj/item/clothing/gloves/arm_guard/flexitac)
	configure(item_protection(siemens = 0.6, min_cold = T0C - 20, cold_parts = ARMS))


/obj/item/clothing/gloves/arm_guard/combat/imperial
	name = "imperial gauntlets"
	desc = "Made of some exotic metal, and crafted by space elves. Elves have delicate hands."
	icon_state = "ge_gloves"
	icon = 'icons/inventory/hands/item.dmi'
	icon = 'icons/inventory/hands/mob.dmi'

/proc/req_acceptance_arm_clearance()
	return part_make(/datum/entry/part/req/acceptance_leaf/arm_clearance, list())


/datum/entry/part/req/acceptance_leaf/arm_clearance/acceptance_reason(datum/act/op/A)
	var/obj/item/clothing/gloves/arm_guard/I = A.target
	return I.suit_clearance(A)



/datum/entry/part/req/acceptance_leaf/arm_clearance/read_keys(datum/act/op/A)
	return suit_clearance_reads(A)
