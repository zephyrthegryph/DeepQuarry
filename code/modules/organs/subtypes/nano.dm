// // // External Organs
/obj/item/organ/external/chest/unbreakable/nano
	robotic = ORGAN_NANOFORM
	encased = FALSE
	max_damage = 70 // <-- This is different from the rest
	min_broken_damage = 1000
	vital = TRUE
	model = "protean"
/obj/item/organ/external/groin/unbreakable/nano
	robotic = ORGAN_NANOFORM
	encased = FALSE
	max_damage = 70
	min_broken_damage = 1000 //Multiple
	vital = FALSE
	model = "protean"
/obj/item/organ/external/head/unbreakable/nano
	robotic = ORGAN_NANOFORM
	encased = FALSE
	max_damage = 70
	min_broken_damage = 1000 //Inheritance
	vital = FALSE
	model = "protean"
/obj/item/organ/external/arm/unbreakable/nano
	robotic = ORGAN_NANOFORM
	encased = FALSE
	max_damage = 40
	min_broken_damage = 1000 //Please
	vital = FALSE
	model = "protean"
/obj/item/organ/external/arm/right/unbreakable/nano
	robotic = ORGAN_NANOFORM
	encased = FALSE
	max_damage = 40
	min_broken_damage = 1000
	vital = FALSE
	model = "protean"
/obj/item/organ/external/leg/unbreakable/nano
	robotic = ORGAN_NANOFORM
	encased = FALSE
	max_damage = 40
	min_broken_damage = 1000
	vital = FALSE
	model = "protean"
/obj/item/organ/external/leg/right/unbreakable/nano
	robotic = ORGAN_NANOFORM
	encased = FALSE
	max_damage = 40
	min_broken_damage = 1000
	vital = FALSE
	model = "protean"
/obj/item/organ/external/hand/unbreakable/nano
	robotic = ORGAN_NANOFORM
	encased = FALSE
	max_damage = 40
	min_broken_damage = 1000
	vital = FALSE
	model = "protean"
/obj/item/organ/external/hand/right/unbreakable/nano
	robotic = ORGAN_NANOFORM
	encased = FALSE
	max_damage = 40
	min_broken_damage = 1000
	vital = FALSE
	model = "protean"
/obj/item/organ/external/foot/unbreakable/nano
	robotic = ORGAN_NANOFORM
	encased = FALSE
	max_damage = 40
	min_broken_damage = 1000
	vital = FALSE
	model = "protean"
/obj/item/organ/external/foot/right/unbreakable/nano
	robotic = ORGAN_NANOFORM
	encased = FALSE
	max_damage = 40
	min_broken_damage = 1000
	vital = FALSE
	model = "protean"

/obj/item/organ/external/head/unbreakable/nano/disfigure()
	return //No way to repair disfigured prots

// // // Internal Organs
// The swarm's own organs are nanite, not prosthetics: BIOLOGY_NANOFORM on any
// body plan, so only the nanite mechanisms reach them.
/obj/item/organ/internal/nano
	robotic = ORGAN_NANOFORM

/obj/item/organ/internal/nano/robotize()
	. = ..()
	robotic = ORGAN_NANOFORM

/obj/item/organ/internal/nano/mechassist()
	. = ..()
	robotic = ORGAN_NANOFORM

/// Control: coordinates the swarm. Its damage (orchestrator_damage) degrades
/// fine control and the swarm's hold on a form.
/obj/item/organ/internal/nano/orchestrator
	name = "orchestrator module"
	desc = "A small computer, designed for highly parallel workloads."
	icon = 'icons/mob/species/protean/protean.dmi'
	icon_state = "orchestrator"
	organ_tag = O_ORCH
	parent_organ = BP_TORSO
	vital = TRUE
	organ_verbs = list(
		/mob/living/carbon/human/proc/self_diagnostics
	)

/obj/item/organ/internal/nano/orchestrator/robotize()
	. = ..()
	icon_state = "orchestrator"

/obj/item/organ/internal/nano/orchestrator/mechassist()
	. = ..()
	icon_state = "orchestrator"

/// Supply and contamination: stores the steel the swarm repairs itself with
/// (refactory_depletion when it runs dry) and filters out what it can't use
/// (contamination).
/obj/item/organ/internal/nano/refactory
	name = "refactory module"
	desc = "A miniature metal processing unit and nanite factory."
	icon = 'icons/mob/species/protean/protean.dmi'
	icon_state = "refactory"
	organ_tag = O_FACT
	parent_organ = BP_TORSO

	var/list/materials = list(MAT_STEEL = 0)
	var/max_storage = 10000
	organ_verbs = list(
		/mob/living/carbon/human/proc/reagent_purge
	)

/obj/item/organ/internal/nano/refactory/robotize()
	. = ..()
	icon_state = "refactory"

/obj/item/organ/internal/nano/refactory/mechassist()
	. = ..()
	icon_state = "refactory"

/obj/item/organ/internal/nano/refactory/proc/get_stored_material(material)
	if(status & ORGAN_DEAD)
		return 0
	return materials[material] || 0

/obj/item/organ/internal/nano/refactory/proc/add_stored_material(material,amt)
	if(status & ORGAN_DEAD)
		return 0
	var/increase = min(amt,max(max_storage-materials[material],0))
	if(isnum(materials[material]))
		materials[material] += increase
	else
		materials[material] = increase
	if(increase > 0 && owner)
		take_in_material(material, increase)
	return increase

/// Stored material reaches the swarm: steel is feedstock (TREAT_FEEDSTOCK),
/// anything else contaminates it.
/obj/item/organ/internal/nano/refactory/proc/take_in_material(material, amount)
	var/points = amount / NANOFORM_STEEL_PER_POINT
	if(material == MAT_STEEL)
		owner.mend(TREAT_FEEDSTOCK, points)
		return
	owner.body?.afflict(/datum/affliction/nanite/contamination, src, points * NANITE_CONTAMINATION_PER_MATERIAL_POINT)
	log_game("NANOFORM: [key_name(owner)] stored [amount] [material]; the swarm is contaminated.")

/obj/item/organ/internal/nano/refactory/proc/use_stored_material(material,amt)
	if(status & ORGAN_DEAD)
		return 0

	var/available = materials[material]

	//Success
	if(available >= amt)
		var/new_amt = available-amt
		if(new_amt == 0)
			materials -= material
		else
			materials[material] = new_amt
		return amt

	//Failure
	return 0

/// Remove up to `amt` of a stored material. Returns the amount removed.
/obj/item/organ/internal/nano/refactory/proc/consume_stored_material(material, amt)
	if(status & ORGAN_DEAD || amt <= 0)
		return 0
	var/available = materials[material] || 0
	. = min(available, amt)
	if(!.)
		return
	if(available - . <= 0)
		materials -= material
	else
		materials[material] = available - .

/// Spend steel on repairing `patient` through treatment `tags`, at most
/// `max_points` of repair. Steel is charged from what mend() actually
/// repaired. Returns the points repaired.
/obj/item/organ/internal/nano/refactory/proc/fund_repair(mob/living/patient, list/tags, max_points)
	if(!patient || (status & ORGAN_DEAD) || !length(tags))
		return 0
	var/budget = min(max_points, get_stored_material(MAT_STEEL) / NANOFORM_STEEL_PER_POINT)
	if(budget <= 0)
		return 0
	var/per_tag = budget / length(tags)
	. = 0
	for(var/tag in tags)
		. += patient.mend(tag, per_tag)
	if(. > 0)
		consume_stored_material(MAT_STEEL, CEILING(. * NANOFORM_STEEL_PER_POINT, 1))

/// The working refactory of a nanoform body, if any.
/mob/living/proc/nano_get_refactory()
	return null

/mob/living/carbon/human/nano_get_refactory()
	var/obj/item/organ/internal/nano/refactory/R = internal_organs_by_name?[O_FACT]
	if(istype(R) && !(R.status & ORGAN_DEAD))
		return R
	return null

/obj/item/organ/internal/mmi_holder/posibrain/nano
	name = "protean posibrain"
	desc = "A more advanced version of the standard posibrain, typically found in protean bodies."
	icon = 'icons/mob/species/protean/protean.dmi'
	icon_state = "posi"
	parent_organ = BP_TORSO

	brain_type = /obj/item/mmi/digital/posibrain/nano

/obj/item/organ/internal/mmi_holder/posibrain/nano/robotize()
	. = ..()
	icon_state = "posi1"

/obj/item/organ/internal/mmi_holder/posibrain/nano/mechassist()
	. = ..()
	icon_state = "posi1"


/obj/item/organ/internal/mmi_holder/posibrain/nano/update_from_mmi()
	. = ..()
	icon = initial(icon)
	icon_state = "posi1"
	stored_mmi.icon_state = "posi1"
// The 'out on the ground' object, not the organ holder
/obj/item/mmi/digital/posibrain/nano
	name = "protean posibrain"
	desc = "A more advanced version of the standard posibrain, typically found in protean bodies."
	icon = 'icons/mob/species/protean/protean.dmi'
	icon_state = "posi"

/obj/item/mmi/digital/posibrain/nano/Initialize(mapload)
	. = ..()
	icon_state = "posi"

/obj/item/mmi/digital/posibrain/nano/request_player()
	icon_state = initial(icon_state)
	return //We don't do this stuff

/obj/item/mmi/digital/posibrain/nano/reset_search()
	icon_state = initial(icon_state)
	return //Don't do this either because of the above

/obj/item/mmi/digital/posibrain/nano/transfer_personality()
	. = ..()
	icon_state = "posi1"

/obj/item/mmi/digital/posibrain/nano/take_identity(mob/living/L, move_mind = TRUE)
	. = ..()
	icon_state = "posi1"

/obj/item/organ/internal/nano/digest_act(atom/movable/item_storage = null)
	return FALSE

/obj/item/protean_reboot
	name = "Protean Reboot Programmer"
	desc = "A small, highly specialized programmer used to form the basis of a Protean swarm. A necessary component in reconstituting a Protean who has lost total body cohesion."
	icon = 'icons/mob/species/protean/protean.dmi'
	icon_state = "reboot"
