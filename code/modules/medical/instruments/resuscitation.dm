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

/obj/item/bag_valve_mask/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	var/mob/living/carbon/human/H = M
	if(!istype(H) || stance == I_HURT)
		return ..()
	if(!H.check_has_mouth() || (H.get_equipped_item(SLOT_ID_MASK) && (H.get_equipped_item(SLOT_ID_MASK).body_parts_covered & FACE)) || (H.get_equipped_item(SLOT_ID_HEAD) && (H.get_equipped_item(SLOT_ID_HEAD).body_parts_covered & FACE)))
		to_chat(user, span_warning("You can't get a seal over [H]'s face."))
		return ITEM_INTERACT_SUCCESS
	act_message(user, src, MSG_SELF(span_notice("You seal %T% over [H]'s face and start squeezing.")), \
		MSG_OTHERS(span_notice("%U% seals %T% over [H]'s face and starts squeezing.")))
	task_timed(user, 2 SECONDS, H, src, PROC_REF(squeeze_done), list(user, H))
	return ITEM_INTERACT_SUCCESS

/obj/item/bag_valve_mask/proc/squeeze_done(mob/living/user, mob/living/carbon/human/H)
	if(!apply_ventilation(H))
		to_chat(user, span_warning("The bag won't empty - air isn't getting into [H]'s lungs!"))

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

/obj/item/airway_kit/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	var/mob/living/carbon/human/H = M
	if(!istype(H) || stance == I_HURT)
		return ..()
	if(target_zone != O_MOUTH && target_zone != BP_HEAD)
		to_chat(user, span_warning("Aim for [H]'s mouth."))
		return ITEM_INTERACT_SUCCESS
	if(!H.check_has_mouth() || (H.get_equipped_item(SLOT_ID_MASK) && (H.get_equipped_item(SLOT_ID_MASK).body_parts_covered & FACE)))
		to_chat(user, span_warning("You can't get into [H]'s mouth."))
		return ITEM_INTERACT_SUCCESS
	act_message(user, src, MSG_SELF(span_notice("You start working %T% into [H]'s airway.")), \
		MSG_OTHERS(span_notice("%U% starts working %T% into [H]'s airway.")))
	task_timed(user, 4 SECONDS, H, src, PROC_REF(airway_done), list(user, H))
	return ITEM_INTERACT_SUCCESS

/obj/item/airway_kit/proc/airway_done(mob/living/user, mob/living/carbon/human/H)
	if(clear_airway(H))
		act_message(user, H, MSG_SELF(span_notice("You clear %T%'s airway.")), MSG_OTHERS(span_notice("%U% clears %T%'s airway.")))
	else
		to_chat(user, span_notice("[H]'s airway is already clear."))

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

MSG_DEF(decompression_needle/lining_up, span_notice("You line %I% up between %T%'s ribs."), span_warning("%U% lines %I% up between %T%'s ribs."))

CAPABILITIES(/obj/item/decompression_needle)
	op("decompress", at_target(/mob/living/carbon/human), priority(OP_PRIORITY_PART), answers(INTENT_USE),
		needs(req(PROC_REF(unused), because = PROC_REF(used_text)), req(PROC_REF(aimed_at_chest), because = PROC_REF(aim_text))),
		begins(MSG(decompression_needle/lining_up)), wait(3 SECONDS), then(PROC_REF(needle_done)))

TRACKED(/obj/item/decompression_needle, used)

/// Requirement: the needle has not been used.
/obj/item/decompression_needle/proc/unused(datum/act/op/A)
	return !used

/obj/item/decompression_needle/proc/used_text(datum/act/op/A)
	return span_warning("\The [src] has already been used.")

/// Requirement: the user aims at the chest (what is aimed at is fixed while the click is decided).
/obj/item/decompression_needle/proc/aimed_at_chest(datum/act/op/A)
	return read_once(A.actor.zone_sel?.selecting) == BP_TORSO

/obj/item/decompression_needle/proc/aim_text(datum/act/op/A)
	return span_warning("Aim for [A.target]'s chest.")

/obj/item/decompression_needle/proc/needle_done(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/carbon/human/H = A.target
	if(used)
		return
	set_used(TRUE)
	name = "used [initial(name)]"
	H.custom_pain("Something sharp punches between your ribs!", 30)
	if(decompress(H))
		act_message(user, src, MSG_SELF(span_notice("Air hisses out of %T%. The chest is decompressed.")), \
			MSG_OTHERS(span_notice("Air hisses out of %T% as %U% drives it into [H]'s chest.")))
	else
		act_message(user, src, MSG_SELF(span_warning("Nothing comes out. There was no trapped air.")), \
			MSG_OTHERS(span_warning("%U% drives %T% into [H]'s chest. Nothing comes out.")))
		H.injure(INJURY_PIERCE, 3, BP_TORSO, src, flags = INJURE_SILENT)

/// Vents trapped pleural air (C4/D2): the needle is delivered where each pneumothorax sits, so
/// an untargeted mend no longer "decompresses" a subdural hematoma or a limb's compartment
/// syndrome from the chest.
/obj/item/decompression_needle/proc/decompress(mob/living/carbon/human/H)
	. = FALSE
	var/list/sites = list()
	for(var/datum/affliction/A as anything in H.body?.afflictions_of(/datum/affliction/pneumothorax))
		sites |= A.location || BP_TORSO
	for(var/site in sites)
		if(H.mend(TREAT_DECOMPRESSION, decompression_amount, site) > 0)
			. = TRUE

#undef BVM_BREATH_SECONDS
