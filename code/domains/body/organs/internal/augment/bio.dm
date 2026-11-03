// The base organic-targeting augment.

/obj/item/organ/internal/augment/bioaugment
	name = "bioaugmenting implant"

	icon_state = "augment_hybrid"
	dead_icon = "augment_hybrid_dead"

	target_parent_classes = list(ORGAN_FLESH)

/* Jensen Shades. Your vision can be augmented.
 * This, technically, no longer needs its unique organ verb, however I have chosen to leave it for posterity
 * in the event it needs to be referenced, while still remaining perfectly functional with either system.
 */

/obj/item/organ/internal/augment/bioaugment/thermalshades
	name = "integrated thermolensing implant"
	desc = "A miniscule implant that houses a pair of thermolensed sunglasses. Don't ask how they deploy, you don't want to know."
	icon_state = "augment_shades"
	dead_icon = "augment_shades_dead"

	w_class = ITEMSIZE_TINY

	organ_tag = O_AUG_EYES

	parent_organ = BP_HEAD

	organ_verbs = list(
		/mob/living/carbon/human/proc/augment_menu,
		/mob/living/carbon/human/proc/toggle_shades)

	integrated_object_type = /obj/item/clothing/glasses/hud/security/jensenshades

/obj/item/organ/internal/augment/bioaugment/thermalshades/augment_action()
	if(!owner)
		return

	owner.toggle_shades()

// Here for posterity and example.
/mob/living/carbon/human/proc/toggle_shades()
	set name = "Toggle Integrated Thermoshades"
	set desc = "Toggle your flash-proof, thermal-integrated sunglasses."
	set category = VERB_CAT_AUGMENTS

	var/obj/item/organ/internal/augment/aug = organ_in(O_AUG_EYES)

	if(get_equipped_item(SLOT_ID_EYES))
		if(aug && aug.integrated_object == get_equipped_item(SLOT_ID_EYES))
			drop_from_inventory(get_equipped_item(SLOT_ID_EYES))
			aug.integrated_object.forceMove(aug)
			if(!get_equipped_item(SLOT_ID_EYES))
				to_chat(src, span_alien("Your [aug.integrated_object] retract into your skull."))
		else if(!istype(get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/hud/security/jensenshades))
			to_chat(src, span_notice("\The [get_equipped_item(SLOT_ID_EYES)] block your shades from deploying."))
		else if(istype(get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/hud/security/jensenshades))
			var/obj/item/G = get_equipped_item(SLOT_ID_EYES)
			if(G.canremove)
				to_chat(src, span_notice("\The [G] are not your integrated shades."))
			else
				drop_from_inventory(G)
				to_chat(src, span_notice("\The [G] retract into your skull."))
				spent(G)

	else
		if(aug && aug.integrated_object)
			to_chat(src, span_alien("Your [aug.integrated_object] deploy."))
			equip_to_slot(aug.integrated_object, SLOT_ID_EYES, 0, 1)
			if(!get_equipped_item(SLOT_ID_EYES) || get_equipped_item(SLOT_ID_EYES) != aug.integrated_object)
				aug.integrated_object.forceMove(aug)
		else
			var/obj/item/clothing/glasses/hud/security/jensenshades/J = new(get_turf(src))
			equip_to_slot(J, SLOT_ID_EYES, 1, 1)
			to_chat(src, span_notice("Your [aug.integrated_object] deploy."))

/obj/item/organ/internal/augment/bioaugment/sprint_enhance
	name = "locomotive optimization implant"
	desc = "A chunk of meat and metal that can manage an individual's leg musculature."

	organ_tag = O_AUG_PELVIC

	parent_organ = BP_GROIN

	robotic = ORGAN_ASSISTED //'chunk of meat'

	target_parent_classes = list(ORGAN_FLESH, ORGAN_ROBOT)

	aug_cooldown = 2 MINUTES

/obj/item/organ/internal/augment/bioaugment/sprint_enhance/augment_action()
	if(!owner)
		return

	if(aug_cooldown)
		if(COOLDOWN_FINISHED(src, cooldown))
			COOLDOWN_START(src, cooldown, aug_cooldown)
		else
			return

	if(ishuman(owner))
		var/mob/living/carbon/human/H = owner
		H.apply_body_effect(/datum/body_effect/sprinting, 1 MINUTES)

/obj/item/organ/internal/augment/bioaugment/health_scan
	name = "health scanner implant"
	desc = "A small, rounded metallic implant with a passive spectrometer, meant to scan blood passing it by."

	organ_tag = O_AUG_PELVIC

	parent_organ = BP_GROIN

	target_parent_classes = list(ORGAN_FLESH, ORGAN_ROBOT)
	var/obj/item/healthanalyzer/med_analyzer = null

CAPABILITIES(/obj/item/organ/internal/augment/bioaugment/health_scan)
	owns_one(nameof(med_analyzer), /obj/item/healthanalyzer, starts = /obj/item/healthanalyzer/advanced)


/obj/item/organ/internal/augment/bioaugment/health_scan/augment_action()
	if(!owner)
		return
	med_analyzer.scan_mob(owner,owner)
