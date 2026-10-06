// Physiology: how oxygen gets from the air to the tissues, and what happens
// when it doesn't. See doc/body_architecture.md §10 and
// doc/health_system_review.md §5.4-5.5.
//
//   ventilation  = supported(BF_RESP_DRIVE) × BF_LUNG_MECHANICS × BF_AIRWAY
//   oxygenation  = saturate(ventilation × BF_GAS_EXCHANGE × lungs × breath quality)
//   output       = supported(BF_PUMP × heart condition)
//   perfusion    = output × volume factor(blood volume) × BF_CIRCULATION
//   delivery     = oxygenation × perfusion × BF_O2_CARRIAGE × BF_TISSUE_UPTAKE
//   shortfall    = max(0, PHYSIOLOGY_CRITICAL_RATIO × BF_DEMAND − delivery)
//   oxygen debt += shortfall × PHYSIOLOGY_DEBT_RATE per second, repaid while
//                  delivery exceeds the critical ratio.
//
// Every cause of suffocation is a mechanism feeding one of those terms:
// vital-system afflictions (airway, respiratory arrest, pneumothorax, cardiac
// rhythm) contribute factors, the Breathing system reports breath quality,
// the Blood system reports blood volume, reagents contribute factors, and
// equipment and hands add supports. The debt grows tissue hypoxia (which costs
// consciousness) and ischemic brain lesions; death comes through the brain
// (is_brain_dead()), the body's single decision point.
//
// Event-driven: the derived values are recomputed only when BODY_DIRTY_PHYSIOLOGY
// is set (factors, organs, supports, breath quality or blood volume changed).
// The per-tick work (the Physiology life system) is a no-op while the body is
// settled: no shortfall, no debt and no supports.

// --- Supports -------------------------------------------------------------------------------

/// A temporary floor (or multiplier) on one factor, owned by a source: a
/// bag-valve mask holding the breathing drive up, CPR holding cardiac output
/// up, a chokehold squeezing the airway shut.
/datum/body_support
	/// BF_* id this support acts on.
	var/factor_id
	/// value = max(value, floor), applied after the product. Null = none.
	var/floor
	/// value *= multiplier (a restriction). Null = none.
	var/multiplier
	/// What provides it: a relation view. The support lapses when the source is deleted (the
	/// view reads null; every support is created with a source).
	var/datum/source
	/// Readable source name, for logs and diagnosis.
	var/source_name
	/// When the support lapses (a cooldown; 0 = until removed).
	COOLDOWN_DECLARE(expires_at)
	/// Optional validity check (performer adjacent, machine powered...): an om_callable() spec.
	var/list/still_valid


/datum/body_support/proc/is_valid()
	if(COOLDOWN_STARTED(src, expires_at) && COOLDOWN_FINISHED(src, expires_at))
		return FALSE
	if(!source)
		return FALSE
	if(still_valid && !om_run(still_valid))
		return FALSE
	return TRUE

/// `value` after this support.
/datum/body_support/proc/apply(value)
	if(!isnull(multiplier))
		value *= multiplier
	if(!isnull(floor))
		value = max(value, floor)
	return value

/datum/body
	/// Active /datum/body_support instances. Lazy.
	var/list/supports
	/// Plan-specific physiology type, or null for plans without one.
	var/physiology_type
	/// The physiology, or null (simple and machine plans).
	var/datum/physiology/physiology

CAPABILITIES(/datum/body)
	owns_one(nameof(physiology), /datum/physiology)
	owns_many(nameof(afflictions))
	owns_many(nameof(supports))


/// A floor on `factor_id` from `source` for `duration` (0 = until removed or
/// `still_valid` fails). Re-adding from the same source refreshes it.
/datum/body/proc/add_support(datum/source, factor_id, floor, duration = 0, list/still_valid)
	return set_support(source, factor_id, floor, null, duration, still_valid)

/// A multiplier below 1 on `factor_id` from `source`: a restriction (a
/// chokehold on the airway, a crushing grip on the chest).
/datum/body/proc/add_restriction(datum/source, factor_id, multiplier, duration = 0, list/still_valid)
	return set_support(source, factor_id, null, multiplier, duration, still_valid)

/datum/body/proc/set_support(datum/source, factor_id, floor, multiplier, duration, list/still_valid)
	if(!physiology || !source)
		return null
	var/datum/body_support/S
	for(var/datum/body_support/existing as anything in supports)
		if(existing.factor_id == factor_id && existing.source == source)
			S = existing
			break
	var/fresh = !S
	if(fresh)
		S = new
		S.factor_id = factor_id
		rel_set(S, nameof(S.source), source)
		S.source_name = "[source]"
		rel_add(src, nameof(supports), S)
	var/changed = fresh || S.floor != floor || S.multiplier != multiplier
	S.floor = floor
	S.multiplier = multiplier
	if(duration)
		COOLDOWN_START(S, expires_at, duration)
	else
		COOLDOWN_RESET(S, expires_at)
	S.still_valid = still_valid
	if(changed)
		invalidate(BODY_DIRTY_PHYSIOLOGY)
	if(fresh)
		log_runtime("PHYSIOLOGY: [key_name(owner)] gained a [isnull(floor) ? "restriction x[multiplier]" : "support floor [floor]"] on factor [factor_id] from [S.source_name] for [duration ? "[duration / (1 SECONDS)]s" : "as long as it lasts"]")
	return S

/// Remove every support `source` provides.
/datum/body/proc/remove_supports(datum/source)
	for(var/datum/body_support/S as anything in supports?.Copy())
		if(S.source == source)
			drop_support(S, "removed")

/datum/body/proc/drop_support(datum/body_support/S, reason)
	log_runtime("PHYSIOLOGY: [key_name(owner)] lost the [S.source_name] support on factor [S.factor_id] ([reason])")
	own_remove(src, nameof(supports), S)
	invalidate(BODY_DIRTY_PHYSIOLOGY)

/// Drop lapsed supports.
/datum/body/proc/prune_supports()
	for(var/datum/body_support/S as anything in supports?.Copy())
		if(!S.is_valid())
			drop_support(S, "lapsed")

/// Factor `id` (or `value`, when a caller folds more into it first) after
/// every support on it.
/datum/body/proc/supported_factor(id, value = null)
	if(isnull(value))
		value = get_factor(id)
	for(var/datum/body_support/S as anything in supports)
		if(S.factor_id == id)
			value = S.apply(value)
	return value

/// Is a support (not a restriction) holding `id` above what the body manages alone?
/datum/body/proc/is_supported(id)
	for(var/datum/body_support/S as anything in supports)
		if(S.factor_id == id && !isnull(S.floor))
			return TRUE
	return FALSE

// --- Queries (the physio -> diag contract) ----------------------------------------------------
// Each returns null when the body plan (or this species) has no such system.

/// Recompute the physiology if something dirtied it.
/datum/body/proc/ensure_physiology()
	if(physiology && (dirty & BODY_DIRTY_PHYSIOLOGY))
		dirty &= ~BODY_DIRTY_PHYSIOLOGY
		if(!physiology.recompute())
			dirty |= BODY_DIRTY_PHYSIOLOGY // the owner isn't set up yet

/// Fraction of normal ventilation (0..1): air actually moved.
/datum/body/proc/ventilation()
	ensure_physiology()
	return physiology?.ventilation

/// Oxygen saturation, SpO2 0..100. Carbon monoxide doesn't show here.
/datum/body/proc/oxygenation()
	ensure_physiology()
	if(isnull(physiology?.oxygenation))
		return null
	return clamp(round(physiology.oxygenation * 100 + get_factor(BF_O2_SAT)), 0, 100)

/// Fraction of normal tissue perfusion (0..1).
/datum/body/proc/perfusion()
	ensure_physiology()
	return physiology?.perfusion

/// Oxygen debt in points: consciousness fails around 50, the brain dies past
/// DQ_HYPOXIA_BRAIN_DAMAGE. Null for bodies that don't need oxygen.
/datum/body/proc/oxygen_debt()
	return physiology?.oxygen_debt

/// Heart rate in bpm (0 = no output).
/datum/body/proc/heart_rate()
	ensure_physiology()
	return physiology?.heart_rate()

/// The heart's rhythm as an ECG shows it (RHYTHM_*), or null for bodies
/// without a heart.
/datum/body/proc/heart_rhythm()
	ensure_physiology()
	return physiology?.heart_rhythm()

/// list(systolic, diastolic) in mmHg.
/datum/body/proc/blood_pressure()
	ensure_physiology()
	return physiology?.blood_pressure()

/// Breaths per minute (0 = apneic).
/datum/body/proc/respiratory_rate()
	ensure_physiology()
	return physiology?.respiratory_rate()

/// Explicit oxygen debt, for causes with no mechanism (magic, admin, spawn-in
/// injuries). Returns the debt added.
/datum/body/proc/add_oxygen_debt(amount, source)
	if(!physiology || amount <= 0)
		return 0
	return physiology.add_debt(amount, source)

/// Pay debt down (TREAT_OXYGENATION). Returns the amount paid.
/datum/body/proc/pay_oxygen_debt(amount)
	if(!physiology || amount <= 0)
		return 0
	return physiology.pay_debt(amount)

/// The Breathing system's report of the last breath (0 = nothing usable,
/// 1 = normal air). Where the owner is breathing can spoil it further
/// (/atom/proc/breath_quality_for(): a belly's stale air).
/datum/body/proc/set_breath_quality(quality)
	if(!physiology)
		return
	var/atom/where = owner?.loc
	if(where)
		quality *= where.breath_quality_for(owner)
	quality = clamp(quality, 0, 1)
	if(quality == physiology.breath_quality)
		return
	// Small drifts in ordinary air don't dirty anything; reaching 0 or 1 always does.
	if(abs(quality - physiology.breath_quality) < PHYSIOLOGY_BREATH_EPSILON && quality > 0 && quality < 1)
		return
	physiology.breath_quality = quality
	invalidate(BODY_DIRTY_PHYSIOLOGY)

/// The Blood system's report of circulating blood volume (fraction of normal).
/datum/body/proc/note_blood_fraction(fraction)
	if(!physiology || abs(fraction - physiology.blood_fraction) < PHYSIOLOGY_BLOOD_EPSILON)
		return
	physiology.blood_fraction = fraction
	invalidate(BODY_DIRTY_PHYSIOLOGY)

/// Circulation was just restored (cardioversion, revival). See
/// /datum/physiology/proc/begin_revival_grace().
/datum/body/proc/begin_revival_grace(source)
	physiology?.begin_revival_grace(source)

/// One physiology step of `seconds` (the Physiology life system).
/datum/body/proc/physiology_tick(seconds)
	if(!physiology)
		return
	if(supports)
		prune_supports()
	ensure_physiology()
	physiology.tick(seconds)

/// How much of a normal breath the air here offers `L`, 0..1. Most places
/// don't change it; the air is judged by the Breathing system itself.
/atom/proc/breath_quality_for(mob/living/L)
	return 1

/mob/living/proc/oxygen_debt()
	return body?.oxygen_debt() || 0

/mob/living/proc/add_oxygen_debt(amount, source)
	return body ? body.add_oxygen_debt(amount, source) : 0

// --- Physiology -----------------------------------------------------------------------------

/datum/physiology
	var/datum/body/body
	/// Fraction of normal ventilation, or null when the body doesn't breathe.
	var/ventilation
	/// Haemoglobin saturation 0..1, or null when the body doesn't breathe.
	var/oxygenation
	/// Fraction of normal cardiac output, or null when there's no heart.
	var/output
	/// Fraction of normal perfusion, or null when there's no circulation.
	var/perfusion
	/// Oxygen used by the tissues relative to a healthy body.
	var/delivery = 1
	/// BF_DEMAND.
	var/demand = 1
	/// How far delivery falls below the critical ratio of demand.
	var/shortfall = 0
	/// Accumulated oxygen debt, points.
	var/oxygen_debt = 0
	/// Breath quality of the last breath, 0..1 (Breathing system).
	var/breath_quality = 1
	/// Circulating blood volume, fraction of normal (Blood system).
	var/blood_fraction = 1
	/// Debt band last logged.
	var/debt_band = 0
	/// When the post-revival grace ends (a cooldown; 0 = none).
	COOLDOWN_DECLARE(revival_grace_until)


/datum/physiology/New(datum/body/new_body)
	..()
	rel_set(src, nameof(body), new_body)

/// Recompute the derived values. Plans override. FALSE if the owner can't be
/// evaluated yet (still being set up).
/datum/physiology/proc/recompute()
	return TRUE

/// A plateau: mild loss barely moves saturation, severe loss collapses it.
/datum/physiology/proc/saturate(x)
	x = clamp(x, 0, 1)
	return x * (2 - x)

/datum/physiology/proc/tick(seconds)
	if(!shortfall && !oxygen_debt)
		return
	if(shortfall)
		set_debt(oxygen_debt + shortfall * PHYSIOLOGY_DEBT_RATE * seconds)
	else
		var/surplus = delivery - PHYSIOLOGY_CRITICAL_RATIO * demand
		if(surplus > 0)
			set_debt(oxygen_debt - surplus * PHYSIOLOGY_REPAY_RATE * (in_revival_grace() ? PHYSIOLOGY_REVIVAL_REPAY_MULT : 1) * seconds)
	debt_consequences(seconds)

// Post-revival policy. A body whose circulation has just been restored
// (cardioversion, a defibrillator revival) still carries the debt it ran up
// while it had none. For PHYSIOLOGY_REVIVAL_GRACE afterwards:
//  - the debt is repaid PHYSIOLOGY_REVIVAL_REPAY_MULT times faster, and
//  - while it is being repaid (no shortfall), it grows no new ischemic
//    lesions: the brain damage done before the revival stays, but a timely
//    revival doesn't die anyway from the debt it is already paying off.
// If delivery fails again during the grace (a new shortfall), the debt grows
// and harms the brain as usual. The grace is not renewed by the passage of
// time, only by another restoration of circulation.

/// Start (or restart) the post-revival grace.
/datum/physiology/proc/begin_revival_grace(source)
	COOLDOWN_START(src, revival_grace_until, PHYSIOLOGY_REVIVAL_GRACE)
	log_runtime("PHYSIOLOGY: [key_name(body?.owner)] circulation restored by [source]; post-revival grace for [PHYSIOLOGY_REVIVAL_GRACE / (1 SECONDS)]s with [round(oxygen_debt)] debt outstanding")

/datum/physiology/proc/in_revival_grace()
	return COOLDOWN_STARTED(src, revival_grace_until) && !COOLDOWN_FINISHED(src, revival_grace_until)

/datum/physiology/proc/add_debt(amount, source)
	var/before = oxygen_debt
	set_debt(oxygen_debt + amount * demand)
	if(source)
		log_runtime("PHYSIOLOGY: [key_name(body.owner)] took [round(oxygen_debt - before, 0.1)] explicit oxygen debt from [source]")
	return oxygen_debt - before

/datum/physiology/proc/pay_debt(amount)
	var/before = oxygen_debt
	set_debt(oxygen_debt - amount)
	return before - oxygen_debt

/datum/physiology/proc/set_debt(value)
	oxygen_debt = clamp(value, 0, PHYSIOLOGY_DEBT_MAX)
	var/band = round(oxygen_debt / PHYSIOLOGY_DEBT_LOG_BAND)
	if(band != debt_band)
		log_runtime("PHYSIOLOGY: [key_name(body.owner)] oxygen debt [debt_band > band ? "fell" : "rose"] to [round(oxygen_debt)] (delivery [round(delivery, 0.01)], demand [round(demand, 0.01)], ventilation [isnull(ventilation) ? "n/a" : round(ventilation, 0.01)], perfusion [isnull(perfusion) ? "n/a" : round(perfusion, 0.01)], breath [round(breath_quality, 0.01)])")
		debt_band = band
	sync_debt()

/// Reflect the debt on the body (plans override).
/datum/physiology/proc/sync_debt()
	return

/// Per-tick consequences of the debt (plans override).
/datum/physiology/proc/debt_consequences(seconds)
	return

/datum/physiology/proc/heart_rate()
	return null

/datum/physiology/proc/blood_pressure()
	return null

/datum/physiology/proc/heart_rhythm()
	return null

/datum/physiology/proc/respiratory_rate()
	return null

// --- Humanoid physiology -----------------------------------------------------------------------

/datum/species
	/// P2-S7/D8: a /datum/breath_profile subtype when this species doesn't breathe through
	/// lungs (alraunes: /datum/breath_profile/skin). Null: lungs, if the species has them.
	var/breath_profile_type

/datum/physiology/humanoid
	/// Does this body breathe at all (lungs, and a species that needs them)?
	var/breathes = TRUE
	/// Does this body circulate blood (a heart)?
	var/circulates = TRUE

/datum/physiology/humanoid/recompute()
	var/mob/living/carbon/human/H = body.owner
	if(!istype(H) || !H.species)
		return FALSE
	demand = body.get_factor(BF_DEMAND)
	var/datum/breath_profile/profile = body.breath_profile()
	breathes = !!profile
	var/skin = profile && !profile.uses_lungs
	circulates = H.should_have_organ(O_HEART)

	var/o2 = 1
	if(breathes)
		ventilation = clamp(body.supported_factor(BF_RESP_DRIVE) * body.supported_factor(BF_LUNG_MECHANICS) * body.supported_factor(BF_AIRWAY), 0, 1)
		var/exchange = body.supported_factor(BF_GAS_EXCHANGE) * (skin ? 1 : lung_condition(H))
		oxygenation = saturate(ventilation * exchange * breath_quality)
		o2 = oxygenation
	else
		ventilation = null
		oxygenation = null

	var/flow = 1
	if(circulates)
		output = clamp(body.supported_factor(BF_PUMP, body.get_factor(BF_PUMP) * heart_condition(H)), 0, 2)
		perfusion = clamp(output * volume_factor(H) * body.supported_factor(BF_CIRCULATION), 0, 2)
		flow = perfusion
	else
		output = null
		perfusion = null

	delivery = o2 * flow * body.supported_factor(BF_O2_CARRIAGE) * body.supported_factor(BF_TISSUE_UPTAKE)
	shortfall = max(0, PHYSIOLOGY_CRITICAL_RATIO * demand - delivery)
	return TRUE

/// Gas exchange the lungs themselves manage.
/datum/physiology/humanoid/proc/lung_condition(mob/living/carbon/human/H)
	var/obj/item/organ/internal/lungs/L = H.organ_in(O_LUNGS)
	if(!L || (L.status & ORGAN_DEAD))
		return 0
	if(L.is_broken())
		return 0.5
	if(L.is_bruised())
		return 0.8
	return 1

/// Pumping the heart itself manages (rhythm is BF_PUMP, from the arrhythmia).
/datum/physiology/humanoid/proc/heart_condition(mob/living/carbon/human/H)
	var/obj/item/organ/internal/heart/heart = H.organ_in(O_HEART)
	if(!heart || (heart.status & ORGAN_DEAD))
		return 0
	if(heart.is_broken())
		return 0.3
	if(heart.is_bruised())
		return 0.7
	if(heart.damage > 5)
		return 0.9
	return 1

/// Perfusion left at the current blood volume: full above the species' safe
/// level, none at three quarters of its fatal level.
/datum/physiology/humanoid/proc/volume_factor(mob/living/carbon/human/H)
	if(H.species.flags & NO_BLOOD)
		return 1
	var/safe = H.species.blood_level_safe
	var/zero = H.species.blood_level_fatal * 0.75
	if(safe <= zero)
		return 1
	return clamp((blood_fraction - zero) / (safe - zero), 0, 1)

/// Tissue hypoxia mirrors the debt: its severity is the debt, capped at 100.
/datum/physiology/humanoid/sync_debt()
	var/datum/affliction/tissue_hypoxia/T = body.find_affliction(/datum/affliction/tissue_hypoxia)
	if(oxygen_debt <= 0)
		if(T)
			T.cure()
		return
	if(!T)
		T = body.afflict(/datum/affliction/tissue_hypoxia)
		if(!T)
			return
	T.set_severity(min(oxygen_debt, AFFLICTION_SEVERITY_TERMINAL))

/// Past DQ_HYPOXIA_BRAIN_DAMAGE the brain grows ischemic lesions, faster the
/// deeper the debt; stabilisers halve it.
/datum/physiology/humanoid/debt_consequences(seconds)
	if(oxygen_debt < DQ_HYPOXIA_BRAIN_DAMAGE)
		return
	if(!shortfall && in_revival_grace())
		return
	var/mob/living/carbon/human/H = body.owner
	if(!H.should_have_organ(O_BRAIN))
		return
	var/obj/item/organ/internal/brain/B = H.organ_in(O_BRAIN)
	if(!istype(B) || B.is_robotic())
		return
	var/rate = DQ_HYPOXIA_BRAIN_RATE * clamp((oxygen_debt - DQ_HYPOXIA_BRAIN_DAMAGE) / (AFFLICTION_SEVERITY_TERMINAL - DQ_HYPOXIA_BRAIN_DAMAGE), 0, 1)
	if(body.get_factor(BF_STABILIZATION))
		rate *= 0.5
	B.apply_lesion_damage(rate * seconds, /datum/affliction/lesion/ischemic_injury, TRUE)

/datum/physiology/humanoid/heart_rate()
	if(!circulates)
		return null
	if(output <= 0 || body.get_factor(BF_PUMP) <= 0)
		return 0
	var/mob/living/carbon/human/H = body.owner
	var/rate = 75
	// Compensation: the heart speeds up as volume and oxygen fall.
	rate += round((1 - clamp(blood_fraction, 0, 1)) * 80)
	rate += round(min(oxygen_debt, 60) / 2)
	rate += body.get_factor(BF_HEART_RATE)
	if(H.is_dead())
		return 0
	return max(0, round(rate))

/// From the heart itself and its cardiac_arrhythmia: no heart (or a dead one)
/// is a flatline; so is a corpse with no arrhythmia left to read.
/datum/physiology/humanoid/heart_rhythm()
	if(!circulates)
		return null
	var/mob/living/carbon/human/H = body.owner
	var/obj/item/organ/internal/heart/heart = H.organ_in(O_HEART)
	if(!heart || (heart.status & ORGAN_DEAD))
		return RHYTHM_ASYSTOLE
	var/datum/affliction/cardiac_arrhythmia/A = body.find_affliction(/datum/affliction/cardiac_arrhythmia)
	if(A)
		switch(A.rhythm)
			if(CARDIAC_RHYTHM_SINUS)
				return RHYTHM_POST_ARREST
			if(CARDIAC_RHYTHM_TACHY)
				return RHYTHM_TACHY
			if(CARDIAC_RHYTHM_VF)
				return RHYTHM_VFIB
		return RHYTHM_ASYSTOLE
	if(H.is_dead())
		return RHYTHM_ASYSTOLE
	return RHYTHM_SINUS

/datum/physiology/humanoid/blood_pressure()
	if(!circulates)
		return null
	if(output <= 0 || body.get_factor(BF_PUMP) <= 0)
		return list(0, 0)
	var/mob/living/carbon/human/H = body.owner
	var/pressure = clamp(output, 0, 1.5) * (0.3 + 0.7 * volume_factor(H)) * body.get_factor(BF_CIRCULATION)
	var/systolic = 120 * pressure + body.get_factor(BF_BP_SYSTOLIC)
	var/diastolic = 80 * pressure + body.get_factor(BF_BP_DIASTOLIC)
	return list(max(0, round(systolic)), max(0, round(diastolic)))

/datum/physiology/humanoid/respiratory_rate()
	if(!breathes)
		return null
	if(ventilation < PHYSIOLOGY_APNEA_VENTILATION)
		return 0
	// A bagged patient breathes at the rescuer's rate.
	if(body.is_supported(BF_RESP_DRIVE) && body.get_factor(BF_RESP_DRIVE) < SUPPORT_BVM_DRIVE)
		return 12
	var/rate = 14 + round(min(oxygen_debt, 60) / 4) + body.get_factor(BF_RESP_RATE)
	return max(0, round(rate))

// --- Life system -------------------------------------------------------------------------------

/// Oxygen debt and its consequences, before the Body's status pass. Cheap while
/// the body is settled; bodies without a physiology never get it.
/mob/living/proc/life_physiology_applies()
	var/datum/body/proto = src.body_type
	return !!initial(proto.physiology_type)

/mob/living/proc/life_physiology(datum/seq_frame/life/F)
	src.body?.physiology_tick(F.dt)

/// Settled: no oxygen debt, no shortfall, nothing stale, and no support that lapses by a
/// validity check. Woken by CHANGE_MOB_HEALTH through the body's invalidate() (factors, organs,
/// breath quality, blood volume, supports); a timed support's expiry is the rewake.
/mob/living/proc/life_physiology_due()
	var/datum/body/B = src.body
	if(!B?.physiology)
		return FALSE
	if(B.dirty & BODY_DIRTY_PHYSIOLOGY)
		return TRUE
	var/datum/physiology/P = B.physiology
	if(P.shortfall || P.oxygen_debt)
		return TRUE
	for(var/datum/body_support/S as anything in B.supports)
		if(S.still_valid)
			return TRUE
	return FALSE

/// The soonest timed support's expiry, so the physiology prunes it on time.
/mob/living/proc/life_physiology_rewake()
	. = 0
	for(var/datum/body_support/S as anything in src.body?.supports)
		if(!COOLDOWN_STARTED(S, expires_at))
			continue
		var/left = max(COOLDOWN_TIMELEFT(S, expires_at), 1)
		if(!. || left < .)
			. = left
