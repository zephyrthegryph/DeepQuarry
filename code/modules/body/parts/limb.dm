// Limb side of the humanoid body plan.
//
// A limb's integrity is the load of the wound afflictions located on it,
// read through get_trauma() / get_burn(). Located injuries reach the limb
// through receive_injury() (from the humanoid plan, i.e. injure()); nothing
// else writes limb damage. apply_wound_damage() and heal_wound_damage() are
// body-internal: code outside code/modules/body uses
// injure() / mend() (enforced by tools/ci/check_grep.sh).
//
// When a limb or organ leaves the body its afflictions travel with it
// (detached, ticking offline) and rejoin whichever body it is attached to.

/obj/item/organ
	/// Afflictions carried while this organ is outside a body.
	var/list/detached_afflictions

CAPABILITIES(/obj/item/organ)
	loose_organ_clock()
	owns_many(nameof(detached_afflictions))
	owns_many(nameof(autopsy_data))

/obj/item/organ/external
	/// Cached sum of non-internal physical wound damage. Read via get_trauma().
	var/tmp/trauma_cache = 0
	/// Cached sum of non-internal burn wound damage. Read via get_burn().
	var/tmp/burn_cache = 0
	/// Number of wounds (merged wounds count individually). Cached with the above.
	var/tmp/number_wounds = 0
	/// A wound changed since the caches were built.
	var/tmp/integrity_dirty = FALSE
	/// D24: cached wound view, rebuilt with the integrity caches. Replaced (never
	/// mutated) on rebuild, so a caller iterating it survives wounds closing.
	var/tmp/list/wound_view

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
	var/list/view = list()
	var/list/source = owner?.body ? owner.body.afflictions_by_location?[src] : detached_afflictions
	for(var/datum/affliction/wound/W in source)
		if(W.location == src)
			view += W
	wound_view = view
	for(var/datum/affliction/wound/W as anything in view)
		number_wounds += W.amount
		if(W.internal)
			continue // arterial bleeds don't count toward limb integrity
		if(W.damage_type == BURN)
			burn_cache += W.damage
		else
			trauma_cache += W.damage
	set_damage(min(max_damage, trauma_cache + burn_cache))

/// Wound afflictions located on this limb, attached or detached. D24: a cached
/// read-only view rebuilt only when a wound changed; `.Copy()` it before mutating.
/obj/item/organ/external/proc/get_wounds()
	RETURN_TYPE(/list)
	if(integrity_dirty || !wound_view)
		recalc_integrity()
	return wound_view

/// Put a wound affliction on this limb.
/obj/item/organ/external/proc/add_wound(datum/affliction/wound/W)
	if(owner?.body)
		owner.body.add_affliction(W, src)
	else
		rel_set(W, nameof(W.location), src)
		rel_add(src, nameof(detached_afflictions), W)
	W.sync()
	integrity_dirty = TRUE

/// Take a wound affliction off this limb and delete it.
/obj/item/organ/external/proc/remove_wound(datum/affliction/wound/W)
	if(W.body)
		W.body.remove_affliction(W)
	integrity_dirty = TRUE
	if(!own_remove(src, nameof(detached_afflictions), W))
		spent(W)

/// Apply a located injury to this limb. Returns the amount applied.
/// Organic limbs grow cuts/punctures/bruises/burns; synthetic limbs dents,
/// breaches and scorching (see code/modules/medical/conditions/wounds.dm).
/obj/item/organ/external/proc/receive_injury(kind, amount, atom/source, flags)
	var/synthetic = (is_robotic())
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
	if(flags & INJURE_CONTINUOUS)
		var/wound_kind = burn ? BURN : (sharp ? (edge ? CUT : PIERCE) : BRUISE)
		if(accumulate_wound_damage(wound_kind, amount))
			owner?.UpdateDamageIcon()
	else if(apply_wound_damage(trauma, burn, sharp, edge, source, projectile = (flags & INJURE_PROJECTILE)))
		owner?.UpdateDamageIcon()
	return max(0, get_trauma() + get_burn() - before)

/// Continuous harm (INJURE_CONTINUOUS): `amount` of `wound_kind` (CUT, PIERCE,
/// BRUISE or BURN) grows this limb's existing wound of that kind, or opens one.
/// Unlike apply_wound_damage() there is no rounding and none of the per-hit
/// rolls (organ spill-over, damage cascades, dismemberment), so a rate applied
/// in ticks of any length lands the same total. Past the limb's capacity the
/// excess becomes shock, as in apply_wound_damage(). Returns the amount the
/// wounds took.
/obj/item/organ/external/proc/accumulate_wound_damage(wound_kind, amount)
	if(amount <= 0 || (owner && om_has(owner, EFFECT_GODMODE)))
		return 0
	owner?.body?.invalidate(BODY_DIRTY_ORGANS)
	var/inflict = amount
	if(CONFIG_GET(flag/limbs_can_break) && !is_damageable(amount))
		inflict = clamp(max_damage * CONFIG_GET(number/organ_health_multiplier) - (get_trauma() + get_burn()), 0, amount)
		if(owner && amount > inflict)
			owner.adjust_shock((amount - inflict) * CONFIG_GET(number/organ_damage_spillover_multiplier), "wound spillover")
	if(inflict <= 0)
		return 0
	var/synthetic = (is_robotic())
	var/datum/affliction/wound/wound_type = wound_affliction_type(wound_kind, inflict, synthetic)
	if(!wound_type)
		return 0
	var/wanted_damage_type = initial(wound_type.damage_type)
	var/datum/affliction/wound/target
	for(var/datum/affliction/wound/W as anything in get_wounds())
		if(W.internal || W.damage_type != wanted_damage_type || istype(W, /datum/affliction/wound/lost_limb))
			continue
		target = W
		break
	if(target)
		target.open_wound(inflict)
	else
		add_wound(new wound_type(src, inflict))
	// Not update_damages(): that also runs the bleed clock down once per call,
	// which would make the bleed depend on the tick length.
	recalc_integrity()
	if(CONFIG_GET(flag/bones_can_break) && !synthetic && get_trauma() > min_broken_damage * CONFIG_GET(number/organ_health_multiplier))
		fracture()
	return inflict


// --- Part lifecycle -------------------------------------------------------------------

/// The organ left this body: its located afflictions come with it. Called
/// only by release_part() (attach.dm), which recomputes the organ's integrity
/// once its owner is cleared and invalidates the body once per subtree.
/datum/body/proc/detach_part(obj/item/organ/O)
	for(var/datum/affliction/A as anything in afflictions_at(O))
		remove_affliction(A)
		rel_set(A, nameof(A.location), O)
		rel_add(O, nameof(O.detached_afflictions), A)

/// The organ joined this body: adopt what it carries. Called only by
/// adopt_part() (attach.dm), which invalidates the body once per subtree.
/datum/body/proc/attach_part(obj/item/organ/O)
	for(var/datum/affliction/A as anything in O.detached_afflictions?.Copy())
		// C23: a carried affliction that can't exist on this body (plan or the part's biology
		// here) is dropped, not smuggled in past can_afflict().
		if(!A.can_afflict(src, O))
			own_remove(O, nameof(O.detached_afflictions), A)
			continue
		add_affliction(A, O)
		A.last_reroll_band = -1
	own_take_all(O, nameof(O.detached_afflictions))
	O.recalc_integrity() // lesions / wounds moved: one recompute from the index

/// Offline tick for afflictions riding a detached organ.
/obj/item/organ/proc/tick_detached_afflictions()
	for(var/datum/affliction/A as anything in detached_afflictions?.Copy())
		A.tick_offline()
		if(A.severity <= 0 && !istype(A, /datum/affliction/load))
			own_remove(src, nameof(detached_afflictions), A)

/// Afflictions located on this organ, whether it's in a body or detached.
/obj/item/organ/proc/afflictions_here()
	if(owner?.body)
		return owner.body.afflictions_at(src)
	return detached_afflictions ? detached_afflictions.Copy() : list()
