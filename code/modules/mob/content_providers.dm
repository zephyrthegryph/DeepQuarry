// Typed content providers: the actor supplies actual equipment, HUD access and forensic identity.

/mob/proc/receive_loose_hat(obj/item/clothing/head/head)
	return 0

/mob/living/silicon/robot/drone/receive_loose_hat(obj/item/clothing/head/head)
	if(hat)
		return 2
	place_on_head(head)
	return 1

/mob/living/carbon/alien/diona/receive_loose_hat(obj/item/clothing/head/head)
	if(hat)
		return 2
	wear_hat(head)
	return 1

/mob/proc/records_hud_access(hudtype)
	return null

/mob/living/carbon/human/records_hud_access(hudtype)
	var/mob/living/carbon/human/H = src
	if(hasHUD_vr(H,hudtype)) return 1 //Added records access for certain modes of omni-hud glasses
	switch(hudtype)
		if("security")
			return istype(H.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/hud/security) || istype(H.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/sunglasses/sechud)
		if("medical")
			return istype(H.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/hud/health)

/mob/living/silicon/robot/records_hud_access(hudtype)
	return sensor_type //Borgo sensors are now binary so just have them on or off

/mob/proc/fingerprint_identity()
	return key

/mob/living/silicon/ai/fingerprint_identity()
	return null

/// A written view is supplied by the reader, not by the device guessing its actor kind.
/mob/proc/written_text_view(text)
	return stars(text)

/mob/living/carbon/human/written_text_view(text)
	return text

/mob/observer/dead/written_text_view(text)
	return text

/mob/living/silicon/written_text_view(text)
	return text

/// Each body's contact response owns its actual injury consequences.
/mob/living/proc/receive_supermatter_contact(obj/item/stack/material/supermatter/stack)
	injure(INJURY_BURN, stack.amount, null, stack)

/mob/living/silicon/robot/receive_supermatter_contact(obj/item/stack/material/supermatter/stack)
	return

/mob/living/carbon/human/receive_supermatter_contact(obj/item/stack/material/supermatter/stack)
	var/burn_user = TRUE
	var/mob/living/carbon/human/H = src
	var/obj/item/clothing/gloves/G = H.get_equipped_item(SLOT_ID_GLOVES)
	if(istype(G) && ((G.flags & THICKMATERIAL && prob(70)) || istype(G, /obj/item/clothing/gloves/gauntlets)))
		burn_user = FALSE

	if(burn_user)
		act_message(stack, H, others = span_danger("%U% flashes as it scorches %T%'s hands!"))
		H.injure(INJURY_BURN, stack.amount / 2 + 5, BP_R_HAND, stack)
		H.injure(INJURY_BURN, stack.amount / 2 + 5, BP_L_HAND, stack)
		H.drop_from_inventory(stack, get_turf(H))
		return

/// Audit identity is the actor's actual name and role-specific label; carbon ID precedence stays in the console.
/mob/proc/research_audit_identity()
	return "Unknown"
/mob/living/silicon/ai/research_audit_identity()
	return "AI [name]"
/mob/living/silicon/robot/research_audit_identity()
	return "CYBORG [name]"

/// A wall attachment releases the carrier's item through its own physical storage contract.
/mob/proc/release_wall_assembly(obj/item/electronic_assembly/wallmount/assembly, turf/destination)
	drop_item(destination)
/mob/living/silicon/robot/release_wall_assembly(obj/item/electronic_assembly/wallmount/assembly, turf/destination)
	assembly.forceMove(destination) // Robots cannot unequip/drop items, for Safety Reasons.
	drop_item(destination)

/// Spawn-in-hand still tries the normal hands first, then the robot's real module holder.
/mob/living/proc/accept_admin_hand_item(obj/item/item)
	put_in_hands(item)
/mob/living/silicon/robot/accept_admin_hand_item(obj/item/item)
	..()
	if(module)
		module.add_item(item, src)
		activate_module(item)

/// An actor's own subversion may override the mind-based round role.
/mob/proc/antagonist_override_rank()
	return 0
/mob/living/silicon/robot/antagonist_override_rank()
	return emagged ? 1 : 0
