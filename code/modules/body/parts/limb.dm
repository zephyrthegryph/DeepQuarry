// Limb side of the humanoid body plan.
//
// A limb's integrity is the load of the wound afflictions located on it,
// read through get_trauma() / get_burn(). Located injuries reach the limb
// through receive_injury() (from the humanoid plan, i.e. injure()); nothing
// else writes limb damage. apply_wound_damage() and heal_wound_damage() are
// body-internal: code outside code/modules/body and code/modules/organs uses
// injure() / mend() (enforced by tools/ci/check_grep.sh).
//
// When a limb or organ leaves the body its afflictions travel with it
// (detached, ticking offline) and rejoin whichever body it is attached to.

/obj/item/organ
	/// Afflictions carried while this organ is outside a body.
	var/list/detached_afflictions

/obj/item/organ/external
	/// Cached sum of non-internal physical wound damage. Read via get_trauma().
	var/tmp/trauma_cache = 0
	/// Cached sum of non-internal burn wound damage. Read via get_burn().
	var/tmp/burn_cache = 0
	/// Number of wounds (merged wounds count individually). Cached with the above.
	var/tmp/number_wounds = 0
	/// A wound changed since the caches were built.
	var/tmp/integrity_dirty = FALSE

/// Physical trauma load on this limb (cuts, bruises, punctures, dents).
/obj/item/organ/external/proc/get_trauma()
	if(integrity_dirty)
		recalc_integrity()
	return trauma_cache

/// Burn load on this limb (burns, frostbite, chemical/electrical burns, scorching).
/obj/item/organ/external/proc/get_burn()
	if(integrity_dirty)
		recalc_integrity()
	return burn_cache

/// Rebuild the integrity caches from the wound afflictions on this limb.
/obj/item/organ/external/recalc_integrity()
	integrity_dirty = FALSE
	trauma_cache = 0
	burn_cache = 0
	number_wounds = 0
	for(var/datum/affliction/wound/W as anything in get_wounds())
		number_wounds += W.amount
		if(W.internal)
			continue // arterial bleeds don't count toward limb integrity
		if(W.damage_type == BURN)
			burn_cache += W.damage
		else
			trauma_cache += W.damage
	damage = min(max_damage, trauma_cache + burn_cache)

/// Wound afflictions located on this limb, attached or detached.
/obj/item/organ/external/proc/get_wounds()
	. = list()
	var/list/source = owner?.body ? owner.body.afflictions_by_location?[src] : detached_afflictions
	for(var/datum/affliction/wound/W in source)
		if(W.location == src)
			. += W

/// Put a wound affliction on this limb.
/obj/item/organ/external/proc/add_wound(datum/affliction/wound/W)
	if(owner?.body)
		owner.body.add_affliction(W, src)
	else
		W.location = src
		LAZYADD(detached_afflictions, W)
	W.sync()
	integrity_dirty = TRUE

/// Take a wound affliction off this limb and delete it.
/obj/item/organ/external/proc/remove_wound(datum/affliction/wound/W)
	if(W.body)
		W.body.remove_affliction(W)
	LAZYREMOVE(detached_afflictions, W)
	integrity_dirty = TRUE
	qdel(W)

/// Apply a located injury to this limb. Returns the amount applied.
/// Organic limbs grow cuts/punctures/bruises/burns; synthetic limbs dents,
/// breaches and scorching (see code/modules/medical/conditions/wounds.dm).
/obj/item/organ/external/proc/receive_injury(kind, amount, atom/source, flags)
	var/synthetic = (robotic >= ORGAN_ROBOT)
	if(synthetic && kind == INJURY_FROSTBITE)
		return 0 // prosthetics don't get frostbite
	var/sharp = (kind == INJURY_CUT || kind == INJURY_PIERCE)
	var/edge = (kind == INJURY_CUT)
	var/trauma = 0
	var/burn = 0
	if(injury_category(kind) == INJURY_CATEGORY_THERMAL)
		burn = amount
	else
		trauma = amount
	var/before = get_trauma() + get_burn()
	if(apply_wound_damage(trauma, burn, sharp, edge, source, projectile = (flags & INJURE_PROJECTILE)))
		owner?.UpdateDamageIcon()
	return max(0, get_trauma() + get_burn() - before)


// --- Part lifecycle -------------------------------------------------------------------

/// The organ left `B`: its located afflictions come with it.
/datum/body/proc/detach_part(obj/item/organ/O)
	for(var/datum/affliction/A as anything in afflictions_at(O))
		remove_affliction(A)
		A.location = O
		LAZYADD(O.detached_afflictions, A)
	// The organ's own integrity is recomputed by removed() once its owner is
	// cleared, so it reads the detached list rather than this body's index.
	on_status_changed()

/// The organ joined this body: adopt what it carries.
/datum/body/proc/attach_part(obj/item/organ/O)
	for(var/datum/affliction/A as anything in O.detached_afflictions)
		add_affliction(A, O)
		A.last_reroll_band = -1
	O.detached_afflictions = null
	O.recalc_integrity() // lesions / wounds moved: one recompute from the index
	invalidate(BODY_DIRTY_VITALS | BODY_DIRTY_ORGANS)

/// Offline tick for afflictions riding a detached organ.
/obj/item/organ/proc/tick_detached_afflictions()
	for(var/datum/affliction/A as anything in detached_afflictions)
		A.tick_offline()
		if(A.severity <= 0 && !istype(A, /datum/affliction/load))
			LAZYREMOVE(detached_afflictions, A)
			qdel(A)

/// Afflictions located on this organ, whether it's in a body or detached.
/obj/item/organ/proc/afflictions_here()
	if(owner?.body)
		return owner.body.afflictions_at(src)
	return detached_afflictions ? detached_afflictions.Copy() : list()
