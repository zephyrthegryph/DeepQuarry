// Internal organ side of the humanoid body plan.
//
// An internal organ's integrity (`damage`) is DERIVED from the lesion
// afflictions located on it (code/modules/medical/conditions/lesions.dm),
// recomputed by recalc_integrity() whenever a lesion changes: one pass over
// the lesions on this organ (the body's location index), never a scan of the
// whole body. Nothing writes `damage` directly.
//
// Harm arrives through injure() with the organ as the target (the humanoid
// plan turns the injury kind into a lesion and calls apply_lesion_damage());
// healing through mend(tag, amount, organ). apply_lesion_damage() and
// restore_lesions() are body-internal: only code/modules/body and
// code/modules/organs call them (enforced by tools/ci/check_grep.sh).
//
// Detached organs carry their lesions in detached_afflictions (see limb.dm).

/// Base hook; internal organs rebuild `damage` from their lesions, limbs from
/// their wounds.
/obj/item/organ/proc/recalc_integrity()
	return

/// Hollow organs can be perforated; solid organs are lacerated instead.
/obj/item/organ/internal/proc/is_hollow()
	switch(organ_tag)
		if(O_STOMACH, O_INTESTINE, O_LUNGS)
			return TRUE
	return FALSE

/// The treatment mechanism that repairs this organ's tissue.
/obj/item/organ/internal/proc/lesion_repair_tag()
	switch(organ_tag)
		if(O_LIVER, O_KIDNEYS, O_ACID, O_HIVE)
			return TREAT_HEPATORENAL
		if(O_HEART, O_SPLEEN, O_RESPONSE, O_ANCHOR, O_EGG)
			return TREAT_CARDIAC
		if(O_LUNGS, O_VOICE, O_GBLADDER)
			return TREAT_RESPIRATORY
		if(O_STOMACH, O_INTESTINE, O_APPENDIX, O_NUTRIENT, O_PLASMA, O_POLYP)
			return TREAT_DIGESTIVE
		if(O_BRAIN)
			return TREAT_NEURAL_REPAIR
		if(O_EYES)
			return TREAT_OCULAR
	return TREAT_TISSUE_REPAIR

/// Lesion kind for untyped damage.
/obj/item/organ/internal/proc/default_lesion_type()
	return /datum/affliction/lesion/contusion

/// Damage below which natural regeneration (TREAT_REGENERATION) still
/// repairs this organ. Above it the organ needs treatment.
/obj/item/organ/internal/proc/natural_heal_ceiling()
	return min_bruised_damage

/// Is this organ past any repair (surgery, drugs, mend(), regeneration)? A
/// dead brain is: brain death needs a resleeve, not a repair.
/obj/item/organ/proc/is_beyond_repair()
	return FALSE

/// Clear ORGAN_DEAD (and the organ's other status flags) on a successful
/// repair, unless the organ is beyond repair. Returns TRUE if it was cleared.
/obj/item/organ/proc/restore_status()
	if(is_beyond_repair())
		return FALSE
	status = 0
	return TRUE

/// Lesion afflictions on this organ, attached or detached.
/obj/item/organ/internal/proc/get_lesions()
	. = list()
	var/list/source = owner?.body ? owner.body.afflictions_by_location?[src] : detached_afflictions
	for(var/datum/affliction/lesion/L in source)
		if(L.location == src)
			. += L

/// First lesion of exactly `lesion_type` on this organ.
/obj/item/organ/internal/proc/find_lesion(lesion_type)
	var/list/source = owner?.body ? owner.body.afflictions_by_location?[src] : detached_afflictions
	for(var/datum/affliction/lesion/L in source)
		if(L.type == lesion_type && L.location == src)
			return L
	return null

/// Rebuild `damage` from the lesions on this organ.
/obj/item/organ/internal/recalc_integrity()
	var/total = 0
	var/list/source = owner?.body ? owner.body.afflictions_by_location?[src] : detached_afflictions
	for(var/datum/affliction/lesion/L in source)
		if(L.location == src)
			total += L.damage
	damage = max_damage ? min(max_damage, total) : total
	owner?.body?.invalidate(BODY_DIRTY_VITALS | BODY_DIRTY_ORGANS)

/// Put `amount` of `lesion_type` on this organ, merging into an existing
/// lesion of the same kind. Returns the lesion.
/obj/item/organ/internal/proc/add_lesion(lesion_type, amount)
	var/datum/affliction/lesion/L = find_lesion(lesion_type)
	if(L)
		L.add_damage(amount)
		return L
	L = new lesion_type(src)
	if(owner?.body)
		owner.body.add_affliction(L, src)
	else
		LAZYADD(detached_afflictions, L)
	L.add_damage(amount)
	return L

/// Take a lesion off this organ and delete it. One integrity recompute.
/obj/item/organ/internal/proc/remove_lesion(datum/affliction/lesion/L)
	if(L.body)
		L.body.remove_affliction(L) // on_removed() recomputes integrity
	else
		LAZYREMOVE(detached_afflictions, L)
		recalc_integrity()
	qdel(L)

/// Remove every lesion (rejuvenate / full heal).
/obj/item/organ/internal/proc/clear_lesions()
	for(var/datum/affliction/lesion/L as anything in get_lesions())
		remove_lesion(L)
	recalc_integrity()

/// Body-internal: harm this organ with `lesion_type` (default: contusion);
/// prosthetic organs always take component faults, at
/// PROSTHETIC_ORGAN_DAMAGE_MULT. Reached from injure() through the humanoid
/// plan. Returns the damage applied. Healing is mend(): a negative amount is
/// a bug.
/obj/item/organ/internal/proc/apply_lesion_damage(amount, lesion_type = null, silent = FALSE)
	if(amount < 0)
		CRASH("apply_lesion_damage() called with a negative amount ([amount]) on [src]; heal through mend().")
	if(!amount || om_has(owner, EFFECT_GODMODE))
		return 0
	if(robotic >= ORGAN_ROBOT)
		amount *= PROSTHETIC_ORGAN_DAMAGE_MULT
		lesion_type = /datum/affliction/lesion/synthetic/component_fault
	else
		if(!ispath(lesion_type, /datum/affliction/lesion) || ispath(lesion_type, /datum/affliction/lesion/synthetic))
			lesion_type = default_lesion_type()
		if(ispath(lesion_type, /datum/affliction/lesion/perforation) && !is_hollow())
			lesion_type = /datum/affliction/lesion/laceration
		if(owner && parent_organ && !silent)
			var/obj/item/organ/external/parent = owner.get_organ(parent_organ)
			if(parent)
				owner.custom_pain("Something inside your [parent.name] hurts a lot.", amount)
	var/before = damage
	amount = min(amount, max(0, max_damage - damage))
	if(amount > 0)
		add_lesion(lesion_type, amount)
	return damage - before

/// Harm to a loose organ outside any body (dropped, mishandled on the
/// surgical tray). An organ in a body is harmed through injure().
/obj/item/organ/internal/proc/bench_damage(amount, lesion_type = null)
	if(owner)
		return owner.injure(INJURY_BLUNT, amount, src, affliction = lesion_type, flags = INJURE_IGNORE_RESISTANCE)
	return apply_lesion_damage(amount, lesion_type, TRUE)

/// Body-internal: repair up to `amount` of lesion damage on an organ that is
/// NOT in a body (an organ in a tray / hand), worst lesion first. Organs in a
/// body heal through mend(). Returns the amount repaired.
/obj/item/organ/internal/proc/restore_lesions(amount)
	. = 0
	if(amount <= 0)
		return
	var/list/lesions = get_lesions()
	sortTim(lesions, GLOBAL_PROC_REF(cmp_lesion_damage_dsc))
	for(var/datum/affliction/lesion/L as anything in lesions)
		if(amount <= 0)
			break
		var/healed = L.heal(amount, TRUE)
		amount -= healed
		. += healed

/proc/cmp_lesion_damage_dsc(datum/affliction/lesion/a, datum/affliction/lesion/b)
	return b.damage - a.damage

/// Raise damage to at least `target` (bruise/break helpers, death).
/obj/item/organ/internal/proc/damage_to_at_least(target, lesion_type = null)
	if(damage >= target)
		return
	var/deficit = target - damage
	if(robotic >= ORGAN_ROBOT)
		lesion_type = /datum/affliction/lesion/synthetic/component_fault
	else if(!lesion_type)
		lesion_type = default_lesion_type()
	add_lesion(lesion_type, deficit)

/obj/item/organ/internal/bruise()
	damage_to_at_least(min_bruised_damage)

/obj/item/organ/internal/break_organ()
	damage_to_at_least(min_broken_damage)

/obj/item/organ/internal/saturate_damage()
	damage_to_at_least(max_damage, /datum/affliction/lesion/necrosis)

/obj/item/organ/internal/rejuvenate(ignore_prosthetic_prefs)
	clear_lesions()
	return ..()

/// Operative repair of an internal organ: surgery provides the structural
/// repair mechanisms through mend() — TREAT_SURGICAL_REPAIR closes tears,
/// contusions and ischemic/toxic damage, then TREAT_RESECTION removes
/// necrotic tissue with whatever budget is left; synthetic organs get a
/// system restore. At most `amount` points in total. Returns the amount
/// repaired.
/mob/living/carbon/human/proc/surgically_repair_organ(obj/item/organ/internal/I, amount = null)
	if(!I || I.owner != src)
		return 0
	if(isnull(amount))
		amount = I.max_damage
	if(I.robotic >= ORGAN_ROBOT)
		return mend(TREAT_SYSTEM_RESTORE, amount, I)
	. = mend(TREAT_SURGICAL_REPAIR, amount, I)
	var/remainder = amount - .
	if(remainder > 0)
		. += mend(TREAT_RESECTION, remainder, I)
