// Stasis: buying time by suspending life processes (doc/health_system_review.md §5.5).
//
// Every stasis source (stasis bags, sleepers, cryopods, the mech sleeper, NIF
// emergency stasis, stasis cages, admin) holds the mob at a /datum/body_effect/stasis level
// (set_stasis(level, source)), which contributes BF_STASIS, a 0..1 share of life processes
// suspended (max rule).
//
// Stasis is the biology clock (doc/rewrite/final_api.html section 3). While applied, each stasis
// source holds the stat clock_rate_bio (MIN, base 1) at 1 - its depth on the mob (the deepest wins),
// so the mob's CLOCK_BIO rate is 1 - stasis. The body reads that rate in ONE place,
// advance_stasis(), which the Life frame calls once at its start (/datum/seq_frame/life/begin()).
// It runs a fractional counter: each frame adds the rate, and the frame runs biology only when
// the counter fills. Every other frame is "paused". A paused frame skips:
//   - affliction ticks (progression, treatment, symptoms)     body.life_tick()
//   - metabolism and hunger                                    the chemicals stage
//   - breathing (so oxygen debt stops accumulating)            the breathing stage
//   - blood loss and regeneration                              the blood stage
//   - the human live/dead stages (organs, defib timer, ...)    run_if NOT_OF(FACT("in_stasis"))
// P2-S6: every one of those declares run_if NOT_OF(FACT("in_stasis")), so the pipeline skips
// paused frames and no system asks. inStasisNow() remains for code outside the life pipeline.
// So at stasis 0.9 everything runs at 10% speed; at 1 it stops. BF_STASIS stays a factor
// for diagnosis readouts; nothing in the life pipeline reads it.

/datum/body
	/// Fractional biology counter: + the clock_rate_bio rate per frame.
	var/tmp/stasis_clock = 0
	/// TRUE when stasis paused the current frame.
	var/tmp/stasis_paused = FALSE

/// Advance the biology counter by one frame. Returns TRUE if this frame is paused. The only
/// reader of the biology clock in the life pipeline.
/datum/body/proc/advance_stasis()
	var/mob/living/L = owner
	var/rate = istype(L) ? L.clock_rate_bio : 1
	if(rate >= 1)
		stasis_clock = 0
		stasis_paused = FALSE
		return FALSE
	stasis_clock += rate
	if(stasis_clock >= 1)
		stasis_clock -= 1
		stasis_paused = FALSE
	else
		stasis_paused = TRUE
	return stasis_paused

/// Is this mob's current Life() cycle paused by stasis?
/mob/proc/inStasisNow()
	return FALSE

/mob/living/inStasisNow()
	return body ? body.stasis_paused : FALSE

// --- Sources ---------------------------------------------------------------------

/// A stasis depth. Subtypes set the depth through BF_STASIS. These are body effect definitions,
/// but stasis is applied per SOURCE with set_stasis() (a bag inside a sleeper is two sources);
/// the deepest wins. Applying one directly with apply_body_effect() also works (a sourceless
/// hold keyed by its type).
/datum/body_effect/stasis
	name = "stasis"
	desc = "Your bodily functions are slowed to a crawl."
	hidden = TRUE
	stacks = MODIFIER_STACK_FORBID
	factors = alist(BF_STASIS = 0.5)

/// This level's stasis depth (its BF_STASIS factor), 0..1.
/datum/body_effect/stasis/proc/stasis_depth()
	return clamp(factors?[BF_STASIS] || 0, 0, 1)

/datum/body_effect/stasis/on_start(mob/living/L)
	hold(L, STAT_CLOCK_RATE_BIO, 1 - stasis_depth(), src, clock = HOLD_CLOCK_WORLD)

/datum/body_effect/stasis/on_end(mob/living/L, expired)
	release(L, STAT_CLOCK_RATE_BIO, src)

/// Life at half speed.
/datum/body_effect/stasis/light
	name = "light stasis"
	factors = alist(BF_STASIS = 0.5)

/// Life at a fifth of normal speed.
/datum/body_effect/stasis/moderate
	name = "moderate stasis"
	factors = alist(BF_STASIS = 0.8)

/// Life at a tenth of normal speed (stasis bags).
/datum/body_effect/stasis/deep
	name = "deep stasis"
	factors = alist(BF_STASIS = 0.9)

/// Life at a hundredth of normal speed.
/datum/body_effect/stasis/complete
	name = "complete stasis"
	factors = alist(BF_STASIS = 0.99)

/// Life stopped outright (cryopods, stasis cages, admin).
/datum/body_effect/stasis/total
	name = "total stasis"
	factors = alist(BF_STASIS = 1)

/// Key in stasis_sources for stasis applied without a source (admin).
#define STASIS_NO_SOURCE "none"

/mob/living
	/// Stasis by source: a per-hold key (STASIS_NO_SOURCE without a source) -> an owned
	/// /datum/stasis_hold naming the source and the /datum/body_effect/stasis level it holds
	/// the mob in. Each holds clock_rate_bio at 1 - its depth, with itself as the source. Lazy.
	var/list/stasis_sources

/// One source's stasis on a mob, owned by the mob's stasis_sources.
/datum/stasis_hold
	/// The /datum/body_effect/stasis path.
	var/stasis_type
	/// What applies it: a relation view, null once the source is deleted (the hold is then
	/// sourceless) or when applied without one.
	var/datum/source

/// The stasis_sources key for `source`: the source's own entry, or for a null source the
/// sourceless entry or one whose source has since been deleted.
/mob/living/proc/stasis_key_of(datum/source)
	if(source)
		for(var/key in stasis_sources)
			var/datum/stasis_hold/hold = stasis_sources[key]
			if(hold.source == source)
				return key
		return null
	if(stasis_sources?[STASIS_NO_SOURCE])
		return STASIS_NO_SOURCE
	for(var/key in stasis_sources)
		var/datum/stasis_hold/hold = stasis_sources[key]
		if(key != STASIS_NO_SOURCE && !hold.source)
			return key // the source was deleted: it is sourceless now
	return null

/// The stasis type held under `key`, or null.
/mob/living/proc/stasis_type_at(key)
	var/datum/stasis_hold/hold = key ? stasis_sources?[key] : null
	return hold?.stasis_type

/// Put this mob in stasis `stasis_type` (a /datum/body_effect/stasis path) held by
/// `source`, replacing whatever stasis that source applied before. A null type
/// releases the source's stasis. Other sources are untouched. Returns TRUE if
/// anything changed. `holds_rate` FALSE records the level without holding clock_rate_bio: the
/// stat's own bridge (clock_rate_bio_changed()), whose level follows the rate rather than setting it.
/mob/living/proc/set_stasis(stasis_type, datum/source, holds_rate = TRUE)
	if(stasis_type && !ispath(stasis_type, /datum/body_effect/stasis))
		stack_trace("set_stasis() given [stasis_type], not a /datum/body_effect/stasis")
		return FALSE
	var/key = stasis_key_of(source)
	var/current = stasis_type_at(key)
	if(current == stasis_type)
		return FALSE
	if(key)
		var/datum/stasis_hold/old_hold = stasis_sources[key]
		release(src, STAT_CLOCK_RATE_BIO, old_hold)
		rel_add(src, nameof(stasis_sources), null, key)
		if(!length(stasis_sources))
			own_clear(src, nameof(stasis_sources), OWN_DELETE)
	if(stasis_type)
		var/static/hold_serial = 0
		key = source ? "stasis_[++hold_serial]" : STASIS_NO_SOURCE
		var/datum/body_effect/stasis/level = body_effect_def(stasis_type)
		var/datum/stasis_hold/hold = new
		hold.stasis_type = stasis_type
		if(source)
			rel_set(hold, nameof(hold.source), source)
		rel_add(src, nameof(stasis_sources), hold, key)
		if(holds_rate)
			hold(src, STAT_CLOCK_RATE_BIO, 1 - level.stasis_depth(), hold, clock = HOLD_CLOCK_WORLD)
	invalidate_factors()
	changed(src, CHANGE_MOB_CONDITIONS)
	PUBLISH_CHANGE(src, MOB_KEY_CONDITIONS)
	var/datum/body_effect/old_level = current ? body_effect_def(current) : null
	var/datum/body_effect/new_level = stasis_type ? body_effect_def(stasis_type) : null
	log_game("STASIS: [key_name(src)] [old_level ? "left [old_level.name]" : ""][old_level && new_level ? " and " : ""][new_level ? "entered [new_level.name]" : ""] from [source ? "[source] ([source.type])" : "no source"] at [AREACOORD(src)]; BF_STASIS now [factor(BF_STASIS)].")
	return TRUE

/// The stasis level `source` holds this mob in, or null. A null source matches stasis applied
/// without one (admin), or whose source has been deleted.
/mob/living/proc/stasis_type_from(datum/source)
	return stasis_type_at(stasis_key_of(source))

/mob/living/proc/has_stasis_from(datum/source)
	return !!stasis_type_from(source)

/// Accumulates the stasis levels held by sources (BF_STASIS, max rule) into `acc`.
/mob/living/proc/accumulate_stasis_factors(list/acc)
	for(var/key in stasis_sources)
		acc = body_factor_accumulate(acc, body_effect_def(stasis_type_at(key)).factors)
	return acc

// --- The stat ------------------------------------------------------------------------------------------------------------------

/// The source the stat clock_rate_bio holds its stasis under (one per mob, shared): a stasis bed's or a sleeper's hold on STAT_CLOCK_RATE_BIO
/// (doc/rewrite/final_api.html section 16.4) reaches the body through it.
/datum/stasis_rate_source
	var/name = "biological clock rate"

GLOBAL_DATUM_INIT(stasis_rate_source, /datum/stasis_rate_source, new)

/// The stat clock_rate_bio (STAT_CLOCK_RATE_BIO, rule MIN, base 1) is the share of normal speed the mob's biology runs at; whatever holds it lower
/// (a working sleeper's occupant slot, a stasis bed) puts the mob in the stasis level of that depth, as one source: the deepest level whose depth
/// does not exceed 1 - rate. A rate of 1 releases it. The on_change hook in the /mob/living block (code/modules/combat_ai/integration/mob_living.dm)
/// runs this at the drain after the stat moved.
/mob/living/proc/clock_rate_bio_changed(datum/act/A)
	set_stasis(stasis_type_for_rate(clock_rate_bio), GLOB.stasis_rate_source, holds_rate = FALSE)

/// The stasis level a biological clock rate stands for: the deepest whose depth is at most 1 - rate, or null for a rate of 1 or more.
/proc/stasis_type_for_rate(rate)
	if(!isnum(rate) || rate >= 1)
		return null
	var/wanted = 1 - max(rate, 0)
	var/best = null
	var/best_depth = 0
	for(var/level_type in subtypesof(/datum/body_effect/stasis))
		var/datum/body_effect/stasis/level = body_effect_def(level_type)
		var/depth = level.stasis_depth()
		if(depth <= wanted + 0.0001 && depth > best_depth)
			best = level_type
			best_depth = depth
	return best

#undef STASIS_NO_SOURCE
