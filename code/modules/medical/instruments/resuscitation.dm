// Resuscitation kit: the hand tools of the vital-systems afflictions
// (code/modules/medical/conditions/vital_systems.dm). The mask is a physiology
// support; the others deliver a treatment mechanism through mend(), so the
// affliction decides what it does.
//
//   bag-valve mask       drive support       breathes for an apneic patient
//   airway kit           TREAT_AIRWAY        clears an obstruction / holds a swollen airway open
//   decompression needle TREAT_DECOMPRESSION vents a (tension) pneumothorax

/// Seconds of assisted breathing one squeeze cycle delivers.
#define BVM_BREATH_SECONDS 12

// --- Bag-valve mask -------------------------------------------------------------------

/obj/item/bag_valve_mask
	name = "bag-valve mask"
	desc = "A mask on a self-inflating bag. Seal it over a patient's face and squeeze to breathe for someone who has stopped breathing on their own. It can't push air past a blocked airway."
	icon = 'icons/inventory/face/item.dmi'
	icon_state = "medical"
	w_class = ITEMSIZE_SMALL

/obj/item/bag_valve_mask/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	var/mob/living/carbon/human/H = M
	if(!istype(H) || user.a_intent == I_HURT)
		return ..()
	if(!H.check_has_mouth() || (H.wear_mask && (H.wear_mask.body_parts_covered & FACE)) || (H.head && (H.head.body_parts_covered & FACE)))
		to_chat(user, span_warning("You can't get a seal over [H]'s face."))
		return ITEM_INTERACT_SUCCESS
	user.visible_message(span_notice("[user] seals \the [src] over [H]'s face and starts squeezing."), span_notice("You seal \the [src] over [H]'s face and start squeezing."))
	if(!do_after(user, 2 SECONDS, target = H))
		return ITEM_INTERACT_SUCCESS
	if(!apply_ventilation(H))
		to_chat(user, span_warning("The bag won't empty - air isn't getting into [H]'s lungs!"))
	return ITEM_INTERACT_SUCCESS

/// Deliver a cycle of breaths: a floor under the breathing drive. It can't
/// push past a closed airway (the airway factor still multiplies it), so the
/// bag tells the rescuer when it won't empty.
/obj/item/bag_valve_mask/proc/apply_ventilation(mob/living/carbon/human/H)
	if(!H.body)
		return FALSE
	H.body.add_support(src, BF_RESP_DRIVE, SUPPORT_BVM_DRIVE, BVM_BREATH_SECONDS SECONDS)
	return !H.airway_obstructed()

// --- Airway kit ---------------------------------------------------------------------------

/obj/item/airway_kit
	name = "airway kit"
	desc = "Magill forceps, a suction bulb and an oropharyngeal airway. Clears whatever is choking a patient and holds a swelling airway open. Aim at the mouth."
	icon = 'icons/obj/surgery.dmi'
	icon_state = "hemostat"
	w_class = ITEMSIZE_SMALL
	/// Airway treatment delivered per use.
	var/airway_amount = 60

/obj/item/airway_kit/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	var/mob/living/carbon/human/H = M
	if(!istype(H) || user.a_intent == I_HURT)
		return ..()
	if(target_zone != O_MOUTH && target_zone != BP_HEAD)
		to_chat(user, span_warning("Aim for [H]'s mouth."))
		return ITEM_INTERACT_SUCCESS
	if(!H.check_has_mouth() || (H.wear_mask && (H.wear_mask.body_parts_covered & FACE)))
		to_chat(user, span_warning("You can't get into [H]'s mouth."))
		return ITEM_INTERACT_SUCCESS
	user.visible_message(span_notice("[user] starts working \the [src] into [H]'s airway."), span_notice("You start working \the [src] into [H]'s airway."))
	if(!do_after(user, 4 SECONDS, target = H))
		return ITEM_INTERACT_SUCCESS
	if(clear_airway(H))
		user.visible_message(span_notice("[user] clears [H]'s airway."), span_notice("You clear [H]'s airway."))
	else
		to_chat(user, span_notice("[H]'s airway is already clear."))
	return ITEM_INTERACT_SUCCESS

/obj/item/airway_kit/proc/clear_airway(mob/living/carbon/human/H)
	return H.mend(TREAT_AIRWAY, airway_amount) > 0

// --- Decompression needle ------------------------------------------------------------------

/obj/item/decompression_needle
	name = "decompression needle"
	desc = "A long, wide-bore catheter over a needle. Driven between the ribs it vents air trapped in the chest - a stopgap until a chest tube is placed and any hole in the lung is repaired. Single use. Aim at the chest."
	icon = 'icons/goonstation/objects/syringe_vr.dmi'
	icon_state = "0"
	w_class = ITEMSIZE_TINY
	/// Decompression delivered.
	var/decompression_amount = 70
	var/used = FALSE

/obj/item/decompression_needle/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	var/mob/living/carbon/human/H = M
	if(!istype(H) || user.a_intent == I_HURT)
		return ..()
	if(used)
		to_chat(user, span_warning("\The [src] has already been used."))
		return ITEM_INTERACT_SUCCESS
	if(target_zone != BP_TORSO)
		to_chat(user, span_warning("Aim for [H]'s chest."))
		return ITEM_INTERACT_SUCCESS
	user.visible_message(span_warning("[user] lines \the [src] up between [H]'s ribs."), span_notice("You line \the [src] up between [H]'s ribs."))
	if(!do_after(user, 3 SECONDS, target = H))
		return ITEM_INTERACT_SUCCESS
	used = TRUE
	name = "used [initial(name)]"
	H.custom_pain("Something sharp punches between your ribs!", 30)
	if(decompress(H))
		user.visible_message(span_notice("Air hisses out of \the [src] as [user] drives it into [H]'s chest."), span_notice("Air hisses out of \the [src]. The chest is decompressed."))
	else
		user.visible_message(span_warning("[user] drives \the [src] into [H]'s chest. Nothing comes out."), span_warning("Nothing comes out. There was no trapped air."))
		H.injure(INJURY_PIERCE, 3, BP_TORSO, src, flags = INJURE_SILENT)
	return ITEM_INTERACT_SUCCESS

/obj/item/decompression_needle/proc/decompress(mob/living/carbon/human/H)
	return H.mend(TREAT_DECOMPRESSION, decompression_amount) > 0

#undef BVM_BREATH_SECONDS
