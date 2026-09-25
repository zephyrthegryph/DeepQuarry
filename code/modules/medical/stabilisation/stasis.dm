// Stasis: buying time by suspending life processes (doc/health_system_review.md §5.5).
//
// Every stasis source (stasis bags, sleepers, cryopods, the mech sleeper, NIF
// emergency stasis, stasis cages, admin) is a /datum/modifier/stasis subtype that
// contributes BF_STASIS, a 0..1 share of life processes suspended (max rule).
//
// Stasis is the biology clock (doc/rewrite/life_on_om.md §8). While applied, each stasis
// modifier holds EFFECT_CLOCK_BIO_INHIBIT = its depth on the mob (the deepest wins), so the
// mob's CLOCK_BIO rate is 1 - stasis. The body reads that rate in ONE place,
// advance_stasis(), which life_frame() calls once per frame before any life system runs. It
// runs a fractional counter: each frame adds the rate, and the frame runs biology only when
// the counter fills. Every other frame is "paused". A paused frame skips:
//   - affliction ticks (progression, treatment, symptoms)     body.life_tick()
//   - metabolism and hunger                                    the chemicals system
//   - breathing (so oxygen debt stops accumulating)            the breathing system
//   - blood loss and regeneration                              the blood system
//   - the human live/dead segments (organs, defib timer, ...)  gate: human vitals
// Those read the paused flag through inStasisNow() / ctx.in_stasis(), never the clock.
// So at stasis 0.9 everything runs at 10% speed; at 1 it stops. BF_STASIS stays a factor
// for diagnosis readouts; nothing in the life pipeline reads it.

/datum/body
	/// Fractional biology counter: + the CLOCK_BIO rate per frame.
	var/tmp/stasis_clock = 0
	/// TRUE when stasis paused the current frame.
	var/tmp/stasis_paused = FALSE

/// Advance the biology counter by one frame. Returns TRUE if this frame is paused. The only
/// reader of the biology clock in the life pipeline.
/datum/body/proc/advance_stasis()
	// No contributions on the mob: nothing can slow its biology clock (the common case).
	var/datum/om/rec/rec = owner?.om_rec
	var/rate = 1
	if(rec?.contribs)
		var/static/bio_idx
		if(!bio_idx)
			var/datum/om/clock_def/C = om_registry().clock_by_id[CLOCK_BIO]
			bio_idx = C.idx
		rate = om_clock_rate(rec, bio_idx)
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

/// A stasis field. Subtypes set the depth through BF_STASIS. Several sources
/// may hold one mob at once (a bag inside a sleeper); the deepest wins.
/datum/modifier/stasis
	name = "stasis"
	desc = "Your bodily functions are slowed to a crawl."
	hidden = TRUE
	stacks = MODIFIER_STACK_ALLOWED
	factors = alist(BF_STASIS = 0.5)
	/// Weakref to what holds the mob in stasis (bag, pod, NIF), or null.
	var/datum/weakref/stasis_source

/datum/modifier/stasis/Destroy(force)
	stasis_source = null
	return ..()

/// Holds the biology clock back by this modifier's depth while it is applied. The hold's
/// source is the modifier, so it also ends when the modifier is deleted.
/datum/modifier/stasis/on_applied()
	. = ..()
	om_hold(holder, EFFECT_CLOCK_BIO_INHIBIT, src, stasis_depth())

/datum/modifier/stasis/on_expire()
	om_release(holder, EFFECT_CLOCK_BIO_INHIBIT, src)
	return ..()

/// This modifier's stasis depth (its BF_STASIS factor), 0..1.
/datum/modifier/stasis/proc/stasis_depth()
	return clamp(factors?[BF_STASIS] || 0, 0, 1)

/// Life at half speed.
/datum/modifier/stasis/light
	name = "light stasis"
	factors = alist(BF_STASIS = 0.5)

/// Life at a fifth of normal speed.
/datum/modifier/stasis/moderate
	name = "moderate stasis"
	factors = alist(BF_STASIS = 0.8)

/// Life at a tenth of normal speed (stasis bags).
/datum/modifier/stasis/deep
	name = "deep stasis"
	factors = alist(BF_STASIS = 0.9)

/// Life at a hundredth of normal speed.
/datum/modifier/stasis/complete
	name = "complete stasis"
	factors = alist(BF_STASIS = 0.99)

/// Life stopped outright (cryopods, stasis cages, admin).
/datum/modifier/stasis/total
	name = "total stasis"
	factors = alist(BF_STASIS = 1)

/// Put this mob in stasis `stasis_type` (a /datum/modifier/stasis path) held by
/// `source`, replacing whatever stasis that source applied before. A null type
/// releases the source's stasis. Other sources are untouched. Returns TRUE if
/// anything changed.
/mob/living/proc/set_stasis(stasis_type, datum/source)
	if(stasis_type && !ispath(stasis_type, /datum/modifier/stasis))
		stack_trace("set_stasis() given [stasis_type], not a /datum/modifier/stasis")
		return FALSE
	var/datum/modifier/stasis/current = stasis_modifier_from(source)
	if(current?.type == stasis_type)
		return FALSE
	if(current)
		remove_specific_modifier(current, TRUE)
	var/datum/modifier/stasis/added
	if(stasis_type)
		added = add_modifier(stasis_type, suppress_failure = TRUE)
		if(added)
			added.stasis_source = source ? WEAKREF(source) : null
	log_game("STASIS: [key_name(src)] [current ? "left [current.name]" : ""][current && added ? " and " : ""][added ? "entered [added.name]" : ""] from [source ? "[source] ([source.type])" : "no source"] at [AREACOORD(src)]; BF_STASIS now [factor(BF_STASIS)].")
	return TRUE

/// The stasis modifier `source` applied to this mob, or null. A null source
/// matches stasis applied without one (admin).
/mob/living/proc/stasis_modifier_from(datum/source)
	for(var/datum/modifier/stasis/S in modifiers)
		var/datum/held_by = S.stasis_source?.resolve()
		if(held_by == source)
			return S
	return null

/mob/living/proc/has_stasis_from(datum/source)
	return stasis_modifier_from(source) ? TRUE : FALSE
