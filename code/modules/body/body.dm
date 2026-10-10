// /datum/body — every /mob/living has exactly one. It owns the mob's
// afflictions, turns injuries into afflictions, applies treatment, computes
// vitals and decides consciousness and death.
//
// Subtypes are body PLANS (humanoid / simple / robot / ai); see
// doc/body_architecture.md. The mob picks its plan with `body_type`.
//
// Invalidation: one bitfield, `dirty` (BODY_DIRTY_*). Anything that changes
// what the body would compute calls invalidate(); the work runs once, on the
// next tick or the next query.

/mob/living
	/// The mob's body. Created in Initialize(); never null on a live mob.
	var/datum/body/body
	/// Body plan used for this mob type.
	var/body_type = /datum/body/simple
	/// Toughness: how much injury load this mob can carry (simple plan), or
	/// the reference scale for its vitality readouts (other plans). Tuned per
	/// subtype. Body factors adjust it (BF_ENDURANCE_FLAT / BF_ENDURANCE_MULT).
	var/endurance = DEFAULT_ENDURANCE
	/// What the mob's body is made of when it has no per-part biology (simple
	/// mobs, bots). Humanoids resolve biology per organ instead.
	var/biology = BIOLOGY_ORGANIC

/mob/living/Initialize(mapload)
	// A human builds its body in set_species(), before this, so its organs
	// have part slots to attach into.
	if(!body)
		rel_set(src, nameof(body), new body_type(src))
	return ..()


/// Systemic biology (BIOLOGY_* flags). Non-living mobs have no body: organic.
/mob/proc/biology()
	return BIOLOGY_ORGANIC

/// Systemic biology, read from the body: the ONLY answer to "is this mob a
/// machine?" (P2-S1). Simple plans answer from the `biology` var; the humanoid
/// plan answers from the torso.
/mob/living/biology()
	return body ? body.biology_of(null) : biology // ALLOW(reads): biology is fixed when the body is made; a reader asks it, nothing caches it

/// Any reagent holder owned by this mob changed: the treatment snapshot and
/// the chem-caused afflictions are stale. The factors are NOT dirtied here
/// (C12): the snapshot rebuild dirties them only when a factor reagent crosses
/// a dose band, appears or leaves (update_reagent_factor_bands()).
/mob/living/on_reagent_change(changetype)
	. = ..()
	if(!body)
		return
	body.reagent_bands_pending = TRUE
	body.invalidate(BODY_DIRTY_TREATMENT | BODY_DIRTY_CHEMS)

/datum/body
	/// The mob this body belongs to.
	var/mob/living/owner
	/// Every affliction on this body, flat. Lazy.
	var/list/afflictions
	/// Affliction type -> list of instances. Lazy; kept in sync with `afflictions`.
	var/list/afflictions_by_type
	/// Part (organ / robot component) -> list of afflictions located on it.
	/// Lazy; systemic afflictions (null location) are not indexed.
	var/list/afflictions_by_location

	// --- Cached vitals (recomputed by recompute_vitals, read by queries) ---
	/// Pain after analgesia.
	var/pain = 0
	/// 100 = fully alert; <= CONSCIOUSNESS_THRESHOLD = unconscious.
	var/consciousness = 100
	/// 0..1 fraction of wellness left.
	var/vitality = 1
	/// BODY_DIRTY_* domains awaiting recomputation.
	var/dirty = BODY_DIRTY_ALL
	/// BODY_PLAN_* flag for this plan (see /datum/affliction/var/body_plans).
	var/plan_flag = BODY_PLAN_SIMPLE
	/// Re-evaluate every tick even with no afflictions (humanoids: limb and
	/// organ state changes outside the body, and brainless bodies must die).
	var/always_evaluate = FALSE

	// --- Treatment snapshot (rebuilt when BODY_DIRTY_TREATMENT is set) ---
	/// TREAT_* -> level this tick. Null when nothing treats the body.
	var/list/treatment_snapshot
	/// Reagent ID -> total volume across the mob's holders. Null when empty.
	var/list/reagent_volumes
	/// Reagent ID -> product of every affliction's interferes_with factor for
	/// it (drug-interaction markers). Null when nothing interferes.
	var/list/reagent_interference
	/// clock_now(CLOCK_BIO) when regeneration was last read into the snapshot, or null.
	var/tmp/regeneration_read_at

/datum/body/New(mob/living/new_owner)
	..()
	rel_set(src, nameof(owner), new_owner)
	if(physiology_type)
		rel_set(src, nameof(physiology), new physiology_type(src))

/// Afflictions leave through remove_affliction(), so their on_removed()
/// hooks and signals run, then are deleted.

// each affliction is removed (symptoms end) before it is deleted. When the owner itself is being
// deleted there is nobody to resolve symptoms on, wake or signal (audit C24): the afflictions are
// only unlinked.
/datum/body/on_destroy(force)
	var/owner_leaving = !owner || QDELETED(owner)
	for(var/datum/affliction/A as anything in afflictions?.Copy())
		if(owner_leaving)
			unlink_affliction(A)
		else
			remove_affliction(A)
		destroyed(A)
	..()

/// Mark `domains` (BODY_DIRTY_*) stale.
/datum/body/proc/invalidate(domains)
	// The physiology reads factors and organs.
	if(domains & (BODY_DIRTY_FACTORS | BODY_DIRTY_ORGANS))
		domains |= BODY_DIRTY_PHYSIOLOGY
	var/gained = domains & ~dirty
	dirty |= domains
	// Only a newly dirtied domain wakes the owner: bits already dirty have woken it and are
	// still waiting to be consumed.
	if(gained && owner)
		PUBLISH_CHANGE(owner, MOB_KEY_HEALTH)

// --- Affliction bookkeeping -------------------------------------------------

/// The only way an affliction joins a body. `location` is the part it sits
/// on (organ / robot component) or null for systemic afflictions.
/datum/body/proc/add_affliction(datum/affliction/A, location = null)
	if(!A || A.body == src)
		return FALSE
	rel_set(A, nameof(A.body), src)
	rel_set(A, nameof(A.owner), owner)
	rel_set(A, nameof(A.location), location)
	// The body owns its afflictions. One carried in from elsewhere (an organ's
	// detached_afflictions) is detached from that holder first.
	var/datum/previous_holder = owner_of(A)
	if(previous_holder && previous_holder != src)
		own_take_member(previous_holder, A.own_slot, A)
	rel_add(src, nameof(afflictions), A)
	LAZYADDASSOCLIST(afflictions_by_type, A.type, A)
	if(location)
		LAZYADDASSOCLIST(afflictions_by_location, location, A)
	// Interference markers live on afflictions: the snapshot folds them in.
	invalidate(BODY_DIRTY_VITALS | BODY_DIRTY_TREATMENT | BODY_DIRTY_FACTORS)
	A.on_added()
	PUBLISH_LEGACY(owner, /datum/notice/body_afflictions_changed, A, TRUE)
	return TRUE

/// The only way an affliction leaves a body (cure, organ removal, heal-all).
/datum/body/proc/remove_affliction(datum/affliction/A)
	if(!A || A.body != src)
		return FALSE
	// Detached, not deleted: the caller deletes it or hands it on (detach_part()).
	own_take_member(src, nameof(afflictions), A)
	LAZYREMOVEASSOC(afflictions_by_type, A.type, A)
	if(A.location)
		LAZYREMOVEASSOC(afflictions_by_location, A.location, A)
	invalidate(BODY_DIRTY_VITALS | BODY_DIRTY_TREATMENT | BODY_DIRTY_FACTORS)
	A.on_removed()
	rel_clear(A, nameof(A.body))
	rel_clear(A, nameof(A.owner))
	PUBLISH_LEGACY(owner, /datum/notice/body_afflictions_changed, A, FALSE)
	return TRUE

/// Teardown only: drop `A` from the indexes with no hooks, invalidation, wake or signal. For a
/// body whose owner is being deleted (on_destroy()).
/datum/body/proc/unlink_affliction(datum/affliction/A)
	if(!A || A.body != src)
		return FALSE
	own_take_member(src, nameof(afflictions), A)
	LAZYREMOVEASSOC(afflictions_by_type, A.type, A)
	if(A.location)
		LAZYREMOVEASSOC(afflictions_by_location, A.location, A)
	A.active_symptoms = null
	rel_clear(A, nameof(A.body))
	rel_clear(A, nameof(A.owner))
	return TRUE

/// First affliction of exactly `affliction_type` (optionally at `location`).
/datum/body/proc/find_affliction(affliction_type, location = null)
	for(var/datum/affliction/A as anything in afflictions_by_type?[affliction_type])
		if(!location || A.location == location)
			return A
	return null

/datum/body/proc/has_affliction(affliction_type)
	return length(afflictions_by_type?[affliction_type]) > 0

/// Every affliction that is `affliction_type` or a subtype of it.
/datum/body/proc/afflictions_of(affliction_type)
	. = list()
	for(var/datum/affliction/A as anything in afflictions)
		if(istype(A, affliction_type))
			. += A

/// Afflictions located on `location` (a copy: safe to modify the body while
/// iterating it). O(1) lookup through afflictions_by_location.
/datum/body/proc/afflictions_at(location)
	if(!location)
		. = list()
		for(var/datum/affliction/A as anything in afflictions)
			if(!A.location)
				. += A
		return
	var/list/here = afflictions_by_location?[location]
	return here ? here.Copy() : list()

/// Find-or-create: the canonical way code gives a body an affliction.
/// Idempotent per (type, location). Returns the affliction.
/datum/body/proc/afflict(affliction_type, location = null, severity = 0)
	RETURN_TYPE(/datum/affliction)
	if(!ispath(affliction_type, /datum/affliction))
		return null
	var/datum/affliction/proto = dq_proto(affliction_type)
	// C9: a whole-body condition exists once, wherever its causes put it.
	var/list/same_type = afflictions_by_type?[affliction_type]
	var/datum/affliction/A = proto.systemic_singleton ? (length(same_type) ? same_type[1] : null) : find_affliction(affliction_type, location)
	if(A)
		if(severity)
			A.adjust_severity(severity)
		return A
	if(!proto.can_afflict(src, location))
		return null
	A = new affliction_type(location)
	add_affliction(A, location)
	// C22: an explicit severity wins; otherwise the type's initial_severity, through the setter.
	if(severity)
		A.set_severity(severity)
	else if(A.initial_severity)
		A.set_severity(A.initial_severity)
	return A

/// Remove every affliction: admin heal, resleeve, rejuvenate.
/datum/body/proc/clear_afflictions()
	physiology?.set_debt(0)
	for(var/datum/affliction/A as anything in afflictions?.Copy())
		A.cure()

// --- Biology ----------------------------------------------------------------

/// Biology of a part (or of the whole body when `location` is null).
/datum/body/proc/biology_of(location)
	return owner.biology // ALLOW(reads): biology is fixed when the body is made; a reader asks it, nothing caches it

// --- Injury / treatment entry points (overridden per plan) ----------------------

/// Multiplier applied to an injury of `kind` at `location` before armour:
/// species / biology immunities and the part's own multiplier. 0 = immune.
/datum/body/proc/injury_multiplier(kind, location)
	return 1

/// Resolve a mitigated injury into afflictions. Returns the amount applied.
/// `target` is a zone, a limb, an internal organ or a robot component.
/datum/body/proc/receive_injury(kind, amount, target, atom/source, affliction_type, flags)
	return 0

/// Resolve the part a target (zone / organ / component) refers to on this plan.
/datum/body/proc/resolve_zone(zone)
	return null

/// Instant treatment by mechanism: the ONLY heal path. Every affliction (at
/// `target`, if given) whose treatment_rate(tag) is non-zero receives
/// `amount` × rate through receive_tagged_treatment(). Budgeted afflictions
/// (limb wounds) share one `amount` between them. Returns the amount treated.
/datum/body/proc/mend(tag, amount, target = null)
	if(amount <= 0 || !LAZYLEN(afflictions))
		return 0
	var/list/candidates = afflictions
	if(target)
		var/location = resolve_zone(target)
		if(!location)
			return 0
		candidates = afflictions_by_location?[location]
		if(!candidates)
			return 0
	var/tag_biology = treatment_tag_biology(tag)
	var/budget = amount
	. = 0
	for(var/datum/affliction/A as anything in candidates.Copy())
		if(A.body != src)
			continue // cured by an earlier treatment's cascade
		var/rate = A.treatment_rate(tag)
		if(!rate || !(biology_of(A.location) & tag_biology))
			continue
		if(!A.shares_mend_budget)
			. += A.receive_tagged_treatment(tag, amount * rate, FALSE)
			continue
		if(budget <= 0)
			continue
		var/treated = A.receive_tagged_treatment(tag, budget * rate, FALSE)
		budget -= treated / rate
		. += treated
	if(.)
		on_status_changed()

// --- Treatment snapshot ------------------------------------------------------------

/// Continuous treatment levels this tick, TREAT_* -> level (null = none).
/// Built once per tick (and again only if reagents change): reagents at their
/// dose scale × drug interference × species chem strength, plus natural
/// regeneration.
/datum/body/proc/treatment_levels()
	if(dirty & BODY_DIRTY_TREATMENT)
		build_treatment_snapshot()
	refresh_regeneration()
	return treatment_snapshot

/// Natural regeneration depends on sleep and nutrition, which change without touching the
/// reagent snapshot. It is re-read at most once per biological instant (clock_now(CLOCK_BIO),
/// which stasis stops) and patched into the snapshot, so ticking bodies no longer rebuild the
/// whole treatment snapshot every cycle (audit C11).
/datum/body/proc/refresh_regeneration()
	var/now = owner ? clock_now(owner, CLOCK_BIO) : 0
	if(now == regeneration_read_at)
		return
	regeneration_read_at = now
	var/regeneration = regeneration_level()
	if(regeneration > 0)
		LAZYSET(treatment_snapshot, TREAT_REGENERATION, regeneration)
	else if(treatment_snapshot)
		treatment_snapshot -= TREAT_REGENERATION
		UNSETEMPTY(treatment_snapshot)

/// Total volume of `reagent_id` across the mob's holders (snapshot).
/datum/body/proc/reagent_volume(reagent_id)
	if(dirty & BODY_DIRTY_TREATMENT)
		build_treatment_snapshot()
	return reagent_volumes?[reagent_id] || 0

/// Product of every `interferes_with[reagent_id]` factor on the body's
/// afflictions (drug-interaction markers). 1.0 when nothing interferes.
/datum/body/proc/reagent_cure_modifier(reagent_id)
	if(dirty & BODY_DIRTY_TREATMENT)
		build_treatment_snapshot()
	var/factor = reagent_interference?[reagent_id]
	return isnull(factor) ? 1.0 : factor

/datum/body/proc/build_treatment_snapshot()
	dirty &= ~BODY_DIRTY_TREATMENT
	treatment_snapshot = null
	reagent_interference = null
	reagent_volumes = collect_reagent_volumes(reagent_volumes)

	for(var/datum/affliction/A as anything in afflictions)
		for(var/reagent_id in A.interferes_with)
			LAZYINITLIST(reagent_interference)
			var/current = reagent_interference[reagent_id]
			reagent_interference[reagent_id] = (isnull(current) ? 1 : current) * A.interferes_with[reagent_id]

	if(reagent_volumes)
		var/strength = chem_heal_strength()
		var/list/table = GLOBAL_TABLE_GET(dq_reagent_tag_table)
		for(var/reagent_id in reagent_volumes)
			var/list/tags = table[reagent_id]
			if(!tags)
				continue
			if(!dq_reagent_acts_on(reagent_id, owner))
				continue
			var/scale = dq_chem_dose_scale(reagent_volumes[reagent_id])
			if(scale <= 0)
				continue
			var/interference = reagent_interference?[reagent_id]
			if(!isnull(interference))
				scale *= interference
			scale *= strength
			for(var/tag in tags)
				LAZYINITLIST(treatment_snapshot)
				treatment_snapshot[tag] = min(treatment_snapshot[tag] + tags[tag] * scale, DQ_CHEM_DOSE_CAP)

	// Regeneration is patched in on read (refresh_regeneration()); force a re-read.
	regeneration_read_at = null
	update_reagent_factor_bands()

/// Reagent ID -> volume across every holder the mob metabolises from, or
/// null when there are none. `reuse` (the previous result) is emptied and refilled
/// instead of allocating a new list each metabolism tick.
/datum/body/proc/collect_reagent_volumes(list/reuse)
	reuse?.Cut()
	var/list/volumes = reuse
	if(iscarbon(owner))
		// A carbon's `reagents` IS its bloodstream: count it once.
		var/mob/living/carbon/C = owner
		volumes = add_holder_volumes(volumes, C.bloodstr)
		volumes = add_holder_volumes(volumes, C.ingested)
		// B1: topicals on the skin treat too (a salve works where it sits).
		volumes = add_holder_volumes(volumes, C.touching)
		if(owner.reagents != C.bloodstr)
			volumes = add_holder_volumes(volumes, owner.reagents)
	else
		volumes = add_holder_volumes(volumes, owner.reagents)
	return length(volumes) ? volumes : null

/datum/body/proc/add_holder_volumes(list/volumes, datum/reagents/holder)
	if(!holder?.total_volume)
		return volumes
	for(var/datum/reagent/R as anything in holder.reagent_list)
		LAZYINITLIST(volumes)
		volumes[R.id] += R.volume
	return volumes

/// Species / trait potency of reagent-driven treatment.
/datum/body/proc/chem_heal_strength()
	return 1

/// Natural regeneration level (TREAT_REGENERATION). Plans that heal on their
/// own override this; 0 = none.
/datum/body/proc/regeneration_level()
	return 0

// --- Life ---------------------------------------------------------------------------

/// Called once per Life tick. Healthy bodies return immediately.
/datum/body/proc/life_tick()
	if(factors_stale())
		recompute_factors()
	if(factors)
		tick_factor_effects()
	if(!always_evaluate && !LAZYLEN(afflictions) && !(dirty & BODY_DIRTY_VITALS))
		return
	// A cycle the stasis clock paused: afflictions hold still (advance_stasis()).
	if(stasis_paused)
		return
	for(var/datum/affliction/A as anything in afflictions?.Copy())
		if(A.body == src)
			A.tick()
	recompute_vitals()
	evaluate_status()

/// Something changed outside the tick (injury, treatment): mark the vitals
/// stale and run the cheap death check now, so death isn't a tick late. The
/// full recompute runs on the next tick or query.
/datum/body/proc/on_status_changed()
	invalidate(BODY_DIRTY_VITALS)
	check_death()

/// Recompute the cached vitals if something invalidated them.
/datum/body/proc/ensure_vitals()
	if(dirty & BODY_DIRTY_VITALS)
		recompute_vitals()

/datum/body/proc/recompute_vitals()
	dirty &= ~BODY_DIRTY_VITALS
	pain = 0
	consciousness = 100
	vitality = 1

/// TRUE when a hook on the owner takes the status question over: the body is held alive (a dormant nanoform core) and neither death nor
/// unconsciousness is asked. A question, not a change: the action ends refused for whoever listens for that.
/datum/body/proc/status_held()
	var/datum/act/body_status/question = ACT_TRY(owner, body_status)
	if(!question)
		return TRUE
	act_cancel(question)
	return FALSE

/// Apply death / consciousness from the cached vitals.
/datum/body/proc/evaluate_status()
	if(owner.is_dead() || in_godmode(owner))
		return
	if(status_held())
		if(has_trait(owner, TRAIT_CRITICAL_CONDITION))
			remove_trait(owner, TRAIT_CRITICAL_CONDITION, STAT_TRAIT)
		return
	if(is_lethal())
		owner.death()
		return
	update_consciousness()

/// Death only; no consciousness. Returns TRUE if the mob died.
/datum/body/proc/check_death()
	if(owner.is_dead() || in_godmode(owner))
		return FALSE
	if(!is_lethal())
		return FALSE
	if(status_held())
		return FALSE
	owner.death()
	return TRUE

/// Are this body's injuries lethal? A question about damage, not about stat: the mob may still be
/// alive (death is applied on the next status check) or already dead. Ask the mob's vital-state
/// predicates (is_dead(), is_dying(), vital_band(); code/modules/body/vital_state.dm) for stat.
/datum/body/proc/is_lethal()
	return FALSE

/datum/body/proc/is_unconscious()
	if(status_held())
		return FALSE
	ensure_vitals()
	return consciousness <= CONSCIOUSNESS_THRESHOLD

/// Apply unconsciousness from vitals. Plans without consciousness (simple)
/// override to do nothing.
/datum/body/proc/update_consciousness()
	if(is_unconscious())
		if(!has_trait(owner, TRAIT_CRITICAL_CONDITION))
			add_trait(owner, TRAIT_CRITICAL_CONDITION, STAT_TRAIT)
		owner.status_at_least(STAT_PARALYZED, 3)
		owner.status_at_least(STAT_SLEEPING, 3)
		owner.set_stat(UNCONSCIOUS)
	else if(has_trait(owner, TRAIT_CRITICAL_CONDITION))
		remove_trait(owner, TRAIT_CRITICAL_CONDITION, STAT_TRAIT)

// --- Queries ----------------------------------------------------------------------------

/// Total load (points) of afflictions in an injury category. Load plans
/// return points; severity plans return summed severity.
/datum/body/proc/injury_load(category)
	. = 0
	for(var/datum/affliction/A as anything in afflictions)
		if(A.injury_category == category)
			. += A.load_value()

/datum/body/proc/is_injured()
	for(var/datum/affliction/A as anything in afflictions)
		if(A.injury_category)
			return TRUE
	return FALSE

/datum/body/proc/get_vitality()
	ensure_vitals()
	return vitality

/datum/body/proc/get_pain()
	ensure_vitals()
	return pain

/datum/body/proc/get_consciousness()
	ensure_vitals()
	return consciousness
