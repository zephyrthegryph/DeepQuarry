// Stasis: buying time by suspending life processes (doc/health_system_review.md §5.5).
//
// Every stasis source (stasis bags, sleepers, cryopods, the mech sleeper, NIF
// emergency stasis, stasis cages, admin) is a /datum/modifier/stasis subtype that
// contributes BF_STASIS, a 0..1 share of life processes suspended (max rule).
//
// The body reads BF_STASIS in ONE place, advance_stasis(), which Life() calls once
// per cycle before any life system runs. It runs a fractional clock: each cycle adds
// (1 - stasis), and the cycle runs normally only when the clock fills. Every other
// cycle is "paused". A paused cycle skips:
//   - affliction ticks (progression, treatment, symptoms)     body.life_tick()
//   - metabolism and hunger                                    the chemicals system
//   - breathing (so oxygen debt stops accumulating)            the breathing system
//   - blood loss and regeneration                              the blood system
//   - the human live/dead segments (organs, defib timer, ...)  gate: human vitals
// Those read the paused flag through inStasisNow() / ctx.in_stasis(), never BF_STASIS.
// So at stasis 0.9 everything runs at 10% speed; at 1 it stops.

/datum/body
	/// Fractional stasis clock: +(1 - BF_STASIS) per Life() cycle.
	var/tmp/stasis_clock = 0
	/// TRUE when stasis paused the current Life() cycle.
	var/tmp/stasis_paused = FALSE

/// Advance the stasis clock by one Life() cycle. Returns TRUE if this cycle is
/// paused. The only reader of BF_STASIS in the life pipeline.
/datum/body/proc/advance_stasis()
	var/level = get_factor(BF_STASIS)
	if(level <= 0)
		stasis_clock = 0
		stasis_paused = FALSE
		return FALSE
	stasis_clock += 1 - level
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
