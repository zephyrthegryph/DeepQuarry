/obj/item/clothing/mask/breath
	desc = "A close-fitting mask that can be connected to an air supply."
	name = "breath mask"
	icon_state = "breath"
	item_state_slots = list(slot_r_hand_str = "breath", slot_l_hand_str = "breath")
	item_flags = AIRTIGHT|FLEXIBLEMATERIAL
	body_parts_covered = FACE
	w_class = ITEMSIZE_SMALL
	gas_transfer_coefficient = 0.10
	permeability_coefficient = 0.50
	var/hanging = 0
	actions_types = list(/datum/action/item_action/adjust_breath_mask)
	pickup_sound = SFX_ITEMS_PICKUP_COMPONENT
	drop_sound = SFX_ITEMS_DROP_COMPONENT
	special_handling = TRUE
	resistance_flags = FIRE_PROOF


/obj/item/clothing/mask/breath/proc/adjust_mask(mob/user)
	if(user.canmove && !user.stat)
		src.hanging = !src.hanging
		if (src.hanging)
			gas_transfer_coefficient = 1
			body_parts_covered = body_parts_covered & ~FACE
			item_flags = item_flags & ~AIRTIGHT
			icon_state = "breathdown"
			to_chat(user, "Your mask is now hanging on your neck.")
		else
			gas_transfer_coefficient = initial(gas_transfer_coefficient)
			body_parts_covered = initial(body_parts_covered)
			item_flags = initial(item_flags)
			icon_state = initial(icon_state)
			to_chat(user, "You pull the mask up to cover your face.")
		update_clothing_icon()

EXTEND_INTERACTIONS(/obj/item/clothing/mask/breath, \
	INTERACT_USE("Adjust", PROC_REF(breath_mask_adjust_self)), \
	INTERACT_VERB("Adjust mask", PROC_REF(breath_toggle_verb), REQ_IN_INVENTORY), \
)

/// Old attack_self.
/obj/item/clothing/mask/breath/proc/breath_mask_adjust_self(mob/user, obj/item/held, datum/interaction/interaction)
	adjust_mask(user)

/// Old verb "Adjust mask".
/obj/item/clothing/mask/breath/proc/breath_toggle_verb(mob/user, obj/item/held, datum/interaction/interaction)
	adjust_mask(user)

/obj/item/clothing/mask/breath/medical
	desc = "A close-fitting sterile mask that can be connected to an air supply."
	name = "medical mask"
	icon_state = "medical"
	item_state_slots = list(slot_r_hand_str = "medical", slot_l_hand_str = "medical")
	permeability_coefficient = 0.01

/obj/item/clothing/mask/breath/emergency
	desc = "A close-fitting  mask that is used by the wallmounted emergency oxygen pump."
	name = "emergency mask"
	icon_state = "breath"
	item_state = "breath"
	permeability_coefficient = 0.50

/obj/item/clothing/mask/breath/anesthetic
	desc = "A close-fitting sterile mask that is used by the anesthetic wallmounted pump."
	name = "anesthetic mask"
	icon_state = "medical"
	item_state = "medical"
	permeability_coefficient = 0.01


/obj/item/clothing/mask/breath/transparent
	name = "transparent breath mask"
	item_state = "golem"  //This is dumb and hacky but was here when I got here.
	sprite_sheets = null

/obj/item/clothing/mask/altevian_breath
	name = "Spacer Tuned Mask"
	desc = "A mask designed for long-term use in areas where breathing comes at a premium."
	icon_state = "altevian-mask"
	sprite_sheets = null
	item_state_slots = list(slot_r_hand_str = "breath", slot_l_hand_str = "breath")
	item_flags = AIRTIGHT|FLEXIBLEMATERIAL
	body_parts_covered = FACE
	w_class = ITEMSIZE_SMALL
	gas_transfer_coefficient = 0.10
	permeability_coefficient = 0.50
	pickup_sound = SFX_ITEMS_PICKUP_COMPONENT
	drop_sound = SFX_ITEMS_DROP_COMPONENT

/obj/item/clothing/mask/altevian_breath/fit_constraint()
	var/list/bodytypes = list(SPECIES_ALTEVIAN)
	return list(REQ_FITS_BODYTYPES(bodytypes))
