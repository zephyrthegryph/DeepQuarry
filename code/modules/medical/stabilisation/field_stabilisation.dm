// Field stabilisation kit (doc/health_system_review.md §5.5): what a medic
// uses to keep a patient alive until definitive care.
//
// Every item here is a treatment-tag or body-factor source, never a special
// case:
//   hemostatic gauze   TREAT_HEMOSTATIC (runs down the bleed) + TREAT_WOUND_PACKING
//   pressure bandage   TREAT_WOUND_PACKING over several wounds + a little TREAT_HEMOSTATIC
//   chest seal         TREAT_OCCLUSIVE_SEAL on the chest (open chest wounds; the
//                      breathing side belongs to the physiology model)
//   splints            the fracture's factors drop while splinted (untreated_fracture stages)
//   stabiliser pen     norepinephrine: BF_CIRCULATION / BF_PUMP support + TREAT_VASOPRESSOR
// Tourniquets live in tourniquet.dm, stasis in stasis.dm.

/// A single-use field dressing: applying it delivers `treatments` to the
/// chosen limb through mend().
/obj/item/stack/medical/field
	name = "field dressing"
	singular_name = "field dressing"
	icon_state = "gauze"
	no_variants = TRUE
	amount = 5
	max_amount = 5
	apply_sounds = list('sound/effects/rip1.ogg', 'sound/effects/rip2.ogg')
	/// TREAT_* -> amount delivered to the limb per use.
	var/list/treatments
	/// Organ tags this goes on; null = any limb.
	var/list/allowed_zones
	/// How long one application takes.
	var/apply_time = 3 SECONDS

/obj/item/stack/medical/field/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(..() == ITEM_INTERACT_FAILURE)
		return ITEM_INTERACT_FAILURE
	if(!ishuman(M))
		return ITEM_INTERACT_SUCCESS
	var/mob/living/carbon/human/H = M
	var/obj/item/organ/external/affecting = H.get_organ(user.zone_sel?.selecting)
	if(!affecting)
		return ITEM_INTERACT_FAILURE
	if(allowed_zones && !(affecting.organ_tag in allowed_zones))
		balloon_alert(user, "\the [src] doesn't go on the [affecting.name]!")
		return ITEM_INTERACT_FAILURE
	user.balloon_alert_visible("[user] starts applying \the [src] to [H == user ? "their" : "[H]'s"] [affecting.name].", "applying \the [src] to the [affecting.name].")
	if(!do_after(user, apply_time, affecting))
		balloon_alert(user, "stand still to apply \the [src]!")
		return ITEM_INTERACT_FAILURE
	// Re-validate after the delay.
	if(QDELETED(src) || !get_amount() || affecting.owner != H || !user.Adjacent(H))
		return ITEM_INTERACT_FAILURE
	if(!apply_to_limb(H, affecting, user))
		balloon_alert(user, "\the [src] does nothing for the [affecting.name].")
		return ITEM_INTERACT_FAILURE
	user.balloon_alert_visible("[user] applies \the [src] to [H == user ? "their" : "[H]'s"] [affecting.name].", "applied \the [src] to the [affecting.name].")
	if(length(apply_sounds))
		playsound(src, pick(apply_sounds), 25)
	use(1)
	return ITEM_INTERACT_SUCCESS

/// Deliver every treatment to `limb`. Returns the total amount treated.
/obj/item/stack/medical/field/proc/apply_to_limb(mob/living/carbon/human/H, obj/item/organ/external/limb, mob/user)
	. = 0
	for(var/tag in treatments)
		. += H.mend(tag, treatments[tag], limb.organ_tag)
	limb.update_damages()
	H.UpdateDamageIcon()
	log_game("FIELD_STAB: [key_name(user)] applied [src] to [key_name(H)]'s [limb.name] at [AREACOORD(H)]: treated [round(., 0.1)] ([json_encode(treatments)]).")
	if(user && user != H)
		add_attack_logs(user, H, "Applied [src] to [limb.name]")

/obj/item/stack/medical/field/hemostatic_gauze
	name = "hemostatic gauze"
	singular_name = "hemostatic gauze pack"
	desc = "Gauze impregnated with a clotting agent, packed hard into a bleeding wound. Stops most bleeds on one wound; it doesn't close the wound."
	icon_state = "gauze"
	treatments = list(TREAT_HEMOSTATIC = 60, TREAT_WOUND_PACKING = 1)

/obj/item/stack/medical/field/pressure_bandage
	name = "pressure bandage"
	singular_name = "pressure bandage"
	desc = "An elastic bandage with a built-in pressure pad. Wraps and compresses the bleeding wounds on a limb."
	icon = 'icons/obj/stacks_ch.dmi'
	icon_state = "pgauze"
	treatments = list(TREAT_WOUND_PACKING = 3, TREAT_HEMOSTATIC = 15)

/obj/item/stack/medical/field/chest_seal
	name = "chest seal"
	singular_name = "chest seal"
	desc = "An adhesive, airtight dressing with a one-way vent, for open wounds to the chest."
	icon_state = "brutepack"
	amount = 2
	max_amount = 2
	apply_time = 2 SECONDS
	allowed_zones = list(BP_TORSO)
	apply_sounds = list('sound/effects/tape.ogg')
	treatments = list(TREAT_OCCLUSIVE_SEAL = 2)

// --- Splints ----------------------------------------------------------------------------
// Splints are the existing /obj/item/stack/medical/splint and limb.apply_splint().
// What a splint does is a factor change: untreated_fracture picks its splinted
// stage (less pain, less slowdown) from limb.splinted.

/// A splint went on or came off: fractures on this limb re-pick their stage now.
/obj/item/organ/external/proc/refresh_fracture_support()
	if(!owner?.body)
		return
	for(var/datum/affliction/untreated_fracture/F in owner.body.afflictions_at(src))
		F.recompute_stage_from_severity()
	log_game("FIELD_STAB: [key_name(owner)]'s [name] is [splinted ? "now splinted" : "no longer splinted"].")

// --- Stabiliser autoinjector ------------------------------------------------------------

/// A vasopressor that holds up blood pressure and cardiac output while the
/// cause is fixed. It supports perfusion; it treats nothing.
/datum/reagent/norepinephrine
	name = REAGENT_NOREPINEPHRINE
	id = REAGENT_ID_NOREPINEPHRINE
	description = REAGENT_NOREPINEPHRINE + " is a vasopressor. It tightens the blood vessels and drives the heart, holding up blood pressure in shock until the cause is dealt with."
	taste_description = "metal"
	reagent_state = LIQUID
	color = "#E05050"
	overdose = REAGENTS_OVERDOSE
	metabolism = REM * 0.5
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_DRUG
	factors = alist(BF_CIRCULATION = 1.3, BF_PUMP = 1.1, BF_STABILIZATION = 10, BF_HEART_RATE = 20, BF_BP_SYSTOLIC = 20, BF_BP_DIASTOLIC = 10)
	species_factors = alist(IS_DIONA = null)
	treatment_tags = list(TREAT_VASOPRESSOR = 0.6, TREAT_CIRCULATORY = 0.4)

/obj/item/reagent_containers/hypospray/autoinjector/stabiliser
	name = "stabiliser autoinjector"
	desc = "An emergency autoinjector of inaprovaline and norepinephrine, for a patient in shock. It holds up the circulation; it doesn't stop the bleeding."
	icon_state = "purple"
	filled_reagents = list(REAGENT_ID_INAPROVALINE = 2, REAGENT_ID_NOREPINEPHRINE = 3)

// --- Kit --------------------------------------------------------------------------------

/obj/item/storage/firstaid/stabilisation
	name = "field stabilisation kit"
	desc = "Everything a medic needs to keep a casualty alive until they reach a doctor: tourniquets, hemostatic gauze, pressure bandages, a chest seal, splints and stabiliser pens."
	icon_state = "firstaid"
	starts_with = list(
		/obj/item/tourniquet = 2,
		/obj/item/stack/medical/field/hemostatic_gauze = 1,
		/obj/item/stack/medical/field/pressure_bandage = 1,
		/obj/item/stack/medical/field/chest_seal = 1,
		/obj/item/stack/medical/splint = 1,
		/obj/item/reagent_containers/hypospray/autoinjector/stabiliser = 1,
	)
