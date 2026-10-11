/obj/item/clothing/shoes/leg_guard
	name = DEVELOPER_WARNING_NAME // "leg guards"
	desc = "These will protect your legs and feet."
	slowdown = SHOES_SLOWDOWN+0.5
	w_class = ITEMSIZE_NORMAL
	step_volume_mod = 1.3
	can_hold_knife = TRUE
	resistance_flags = FIRE_PROOF

CAPABILITIES(/obj/item/clothing/shoes/leg_guard)
	acceptance("fit", mode = ACCEPTANCE_EMPTY)
	acceptance("equip", req_acceptance_leg_clearance(), mode = ACCEPTANCE_APPEND)
	configure(item_worn(covers = LEGS|FEET))
	configure(item_sounds(drop = SFX_ITEMS_DROP_BOOTS, pickup = SFX_ITEMS_PICKUP_BOOTS))





/obj/item/clothing/shoes/leg_guard/proc/suit_clearance(datum/act/op/A)
	var/mob/living/carbon/human/H = A.wearer
	if(!istype(H) || !H.get_equipped_item(SLOT_ID_SUIT))
		return null
	if(worn_of(H.get_equipped_item(SLOT_ID_SUIT)).covers & LEGS)
		return "\the [H.get_equipped_item(SLOT_ID_SUIT)] is in the way"
	for(var/obj/item/clothing/accessory/W in H.get_equipped_item(SLOT_ID_SUIT))
		if(worn_of(W).covers & LEGS)
			return "\the [H.get_equipped_item(SLOT_ID_SUIT)]'s [W] is in the way"
	return null

/obj/item/clothing/shoes/leg_guard/laserproof
	name = "ablative leg guards"
	desc = "These will protect your legs and feet from energy weapons."
	icon_state = "leg_guards_laser"
	item_state_slots = list(slot_r_hand_str = "jackboots", slot_l_hand_str = "jackboots")
	armor_spec = "melee=10;bullet=10;laser=80;energy=50"

CAPABILITIES(/obj/item/clothing/shoes/leg_guard/laserproof)
	configure(item_protection(siemens = 0.1))

/obj/item/clothing/shoes/leg_guard/bulletproof
	name = "bullet resistant leg guards"
	desc = "These will protect your legs and feet from ballistic weapons."
	icon_state = "leg_guards_bullet"
	item_state_slots = list(slot_r_hand_str = "jackboots", slot_l_hand_str = "jackboots")
	armor_spec = "melee=10;bullet=80;laser=10;energy=10"

CAPABILITIES(/obj/item/clothing/shoes/leg_guard/bulletproof)
	configure(item_protection(siemens = 0.7))

/obj/item/clothing/shoes/leg_guard/riot
	name = "riot leg guards"
	desc = "These will protect your legs and feet from close combat weapons."
	icon_state = "leg_guards_riot"
	item_state_slots = list(slot_r_hand_str = "jackboots", slot_l_hand_str = "jackboots")
	armor_spec = "melee=80;bullet=10;laser=10;energy=10"

CAPABILITIES(/obj/item/clothing/shoes/leg_guard/riot)
	configure(item_protection(siemens = 0.5))

/obj/item/clothing/shoes/leg_guard/combat
	name = "combat leg guards"
	desc = "These will protect your legs and feet from a variety of weapons."
	icon_state = "leg_guards_combat"
	item_state_slots = list(slot_r_hand_str = "jackboots", slot_l_hand_str = "jackboots")
	armor_spec = "melee=50;bullet=50;laser=50;energy=30;bomb=30"

CAPABILITIES(/obj/item/clothing/shoes/leg_guard/combat)
	configure(item_protection(siemens = 0.6))

/obj/item/clothing/shoes/leg_guard/flexitac
	name = "tactical leg guards"
	desc = "These will protect your legs and feet from a variety of weapons while still allowing mobility."
	icon_state = "leg_guards_flexitac"
	item_state_slots = list(slot_r_hand_str = "jackboots", slot_l_hand_str = "jackboots")
	slowdown = SHOES_SLOWDOWN+0.5
	armor_spec = "melee=40;bullet=40;laser=60;energy=35;bomb=30"

CAPABILITIES(/obj/item/clothing/shoes/leg_guard/flexitac)
	configure(item_protection(siemens = 0.6, min_cold = T0C - 20, cold_parts = LEGS))


/obj/item/clothing/shoes/leg_guard/combat/imperial
	name = "imperial leg guards"
	desc = "Good for Roman around."
	icon_state = "ge_boots"

/proc/req_acceptance_leg_clearance()
	return part_make(/datum/entry/part/req/acceptance_leaf/leg_clearance, list())


/datum/entry/part/req/acceptance_leaf/leg_clearance/acceptance_reason(datum/act/op/A)
	var/obj/item/clothing/shoes/leg_guard/I = A.target
	return I.suit_clearance(A)


/datum/entry/part/req/acceptance_leaf/leg_clearance/read_keys(datum/act/op/A)
	return suit_clearance_reads(A)
