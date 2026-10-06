// Mob statuses on the stat layer (doc/rewrite/final_api.html section 5 "Statuses"; doc/rewrite/om_retirement.md L3).
//
// Every timed impairment a mob can suffer (stun, sleep, blindness, stutter, dizziness, ...) is a status stat: STAT(..., units =), its value the
// strongest hold. A mob's own dose is its SRC_STATUS hold, timed on the mob's biology clock (stasis pauses it); anything else that keeps a
// status on (voluntary sleep, a disability, a cryo cell) holds it under its own source. Nothing counts a status down per frame: a hold ends at
// its deadline. Its immunity is the companion stat STAT_IMMUNE(STAT_X): held by type declarations (immune_to()), mutations and godmode, it
// zeroes the status while TRUE.
//
// Amounts are units, points of a status: `wear` of them wear off per LIFE_CYCLE (a mob's status_rate() may change that: resting, a
// blindfold, a species' waking speed). A dose's hold value is the wear rate its deadline was computed with, so a rate change rescales what
// is left (status_rate_check()) and has_status() is "the value is above 0".
//
// What else a status does is its policy (status_policies()): a cap, whether increases are scaled by resistances (status_scale()), a veto
// event, a screen alert and an indicator, and hooks when it starts, ends or is increased. The stat layer calls status_flipped() the moment a
// status starts or ends, so canmove and alerts follow at once.

STAT(/mob, stunned, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
STAT(/mob, weakened, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
STAT(/mob, paralyzed, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
STAT(/mob, sleeping, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
STAT(/mob, confused, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
STAT(/mob, blinded, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
STAT(/mob, blurry, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
STAT(/mob, nearsighted, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
STAT(/mob, deafened, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
STAT(/mob, stuttering, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
STAT(/mob, muted, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
STAT(/mob, drugged, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
STAT(/mob, slurring, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
STAT(/mob, drowsy, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
STAT(/mob, hallucinating, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
STAT(/mob, dizzy, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
STAT(/mob, jittery, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
/// Godmode: no harm reaches the mob, and it holds the incapacitation immunities while on.
STAT(/mob, godmode, ANY, virtual = TRUE)

SOURCE_DEF(godmode)
SOURCE_DEF(voluntary_sleep)
SOURCE_DEF(disability_blind)
SOURCE_DEF(disability_deaf)
SOURCE_DEF(mutation_hulk)

/// Godmode's incapacitation immunities, for /mob's CAPABILITIES block (mob_defines.dm).
/proc/godmode_immunities()
	return list(immune_to(STAT_STUNNED, when = STAT_GODMODE), immune_to(STAT_WEAKENED, when = STAT_GODMODE), immune_to(STAT_PARALYZED, when = STAT_GODMODE))

/// The incapacitation immunities, for a type's CAPABILITIES block: mob types immune by nature.
/proc/immune_to_incapacitation()
	return list(immune_to(STAT_STUNNED), immune_to(STAT_WEAKENED), immune_to(STAT_PARALYZED))

// ---------------------------------------------------------------- policies

/// What a status does beyond its timed holds. One per status, built once.
/datum/status_policy
	var/id
	/// Units that wear off per LIFE_CYCLE (a mob's status_rate() may change it).
	var/wear = 1
	/// The rate while the mob rests (status_resting()); 0: no difference.
	var/wear_resting = 0
	/// Most units the status can hold; 0: no cap.
	var/max_units = 0
	/// Increases pass through the mob's status_scale() (resistances).
	var/scaled = FALSE
	/// A refusable event sent before an increase (amount): COMPONENT_NO_STUN in its result refuses it.
	var/veto
	/// A screen alert while active (category and type), and a status indicator (icon state).
	var/alert
	var/alert_type
	var/indicator
	/// Procs on the mob called when the status starts, ends, or is increased.
	var/on_start
	var/on_end
	var/on_increase

/// Status id -> /datum/status_policy, built once at global init from status_policy_rows().

/// The policy table's source rows: list(STAT_X, field = value, ...).
GLOBAL_LIST_INIT(status_policy_rows, list(
		list(STAT_STUNNED, "scaled" = TRUE, "veto" = /datum/om/event/living_status_stun, "alert" = "stunned", "alert_type" = /atom/movable/screen/alert/stunned, "indicator" = "stunned",
			"on_increase" = /mob/proc/status_clear_facing, "on_start" = /mob/proc/status_incapacitation_changed, "on_end" = /mob/proc/status_incapacitation_changed),
		list(STAT_WEAKENED, "scaled" = TRUE, "veto" = /datum/om/event/living_status_weaken, "alert" = "weakened", "alert_type" = /atom/movable/screen/alert/weakened, "indicator" = "weakened",
			"on_increase" = /mob/proc/status_clear_facing, "on_start" = /mob/proc/status_knocked_down, "on_end" = /mob/proc/status_incapacitation_changed),
		list(STAT_PARALYZED, "scaled" = TRUE, "veto" = /datum/om/event/living_status_paralyze, "alert" = "paralyzed", "alert_type" = /atom/movable/screen/alert/paralyzed, "indicator" = "paralysis",
			"on_increase" = /mob/proc/status_clear_facing, "on_start" = /mob/proc/status_passed_out, "on_end" = /mob/proc/status_incapacitation_changed),
		list(STAT_SLEEPING, "scaled" = TRUE, "veto" = /datum/om/event/before/living_status_sleep, "alert" = "asleep", "alert_type" = /atom/movable/screen/alert/asleep, "indicator" = "sleeping",
			"on_increase" = /mob/proc/status_clear_facing, "on_start" = /mob/proc/status_incapacitation_changed, "on_end" = /mob/proc/status_incapacitation_changed),
		list(STAT_CONFUSED, "scaled" = TRUE, "alert" = "confused", "alert_type" = /atom/movable/screen/alert/confused, "indicator" = "confused"),
		list(STAT_BLINDED, "scaled" = TRUE, "veto" = /datum/om/event/living_status_blind, "indicator" = "blinded", "on_end" = /mob/proc/status_sight_returned),
		list(STAT_BLURRY),
		list(STAT_NEARSIGHTED),
		list(STAT_DEAFENED, "on_start" = /mob/proc/status_deafness_started, "on_end" = /mob/proc/status_deafness_ended),
		list(STAT_STUTTERING),
		list(STAT_MUTED),
		list(STAT_DRUGGED, "alert" = "high", "alert_type" = /atom/movable/screen/alert/high),
		list(STAT_SLURRING),
		list(STAT_DROWSY),
		list(STAT_HALLUCINATING, "wear" = 2),
		// Dizziness and jitters are 0-1000 points: 3 wear off per cycle, 15 while resting.
		list(STAT_DIZZY, "wear" = 3, "wear_resting" = 15, "max_units" = 1000, "on_start" = /mob/proc/status_dizzy_started, "on_end" = /mob/proc/status_dizzy_ended),
		list(STAT_JITTERY, "wear" = 3, "wear_resting" = 15, "max_units" = 1000, "on_start" = /mob/proc/status_jittery_started, "on_end" = /mob/proc/status_jittery_ended),
))

GLOBAL_LIST(status_policies)

/proc/status_policies_build()
	. = list()
	for(var/list/row as anything in GLOB.status_policy_rows)
		var/datum/status_policy/P = new
		P.id = row[1]
		for(var/key in row)
			if(istext(key))
				P.vars[key] = row[key] // ALLOW(api): a policy row's named fields copied onto its policy datum, once at build
		.["[P.id]"] = P

/// Status id -> /datum/status_policy.
/proc/status_policies()
	// Built on first use: GLOB init order is not declaration order, so the rows may not exist yet at global init.
	if(!GLOB.status_policies)
		GLOB.status_policies = status_policies_build()
	return GLOB.status_policies

/// The policy of status `id`.
/proc/status_policy(id)
	RETURN_TYPE(/datum/status_policy)
	var/datum/status_policy/P = status_policies()["[id]"]
	if(!P)
		CRASH("[id] is not a status")
	return P

// ---------------------------------------------------------------- reading

/// TRUE while status `id` is in effect (any source, timed or held), and no immunity zeroes it. A status starting or ending publishes
/// MOB_KEY_STATUS (status_flipped()), which a reader of has_status() subscribes to.
READS_AS(/datum/proc/has_status, MOB_KEY_STATUS)
/datum/proc/has_status(id)
	var/value = stat_value(src, id)
	return isnum(value) && value > 0

/// TRUE while this entity is immune to status `id`.
/datum/proc/status_immune(id)
	return !!stat_value(src, STAT_IMMUNE(id))

/// The own dose's hold row of `id`, or null.
/datum/proc/status_dose(id)
	var/datum/stat_record/rec = rx?.stats
	return rec ? stat_hold_find(rec, id, SRC_STATUS, null) : null

/// Deciseconds of biological time until the own dose of `id` ends (0 when there is none). A hold from another source has no duration and
/// doesn't count: read has_status() for "in effect at all".
/datum/proc/status_remaining(id)
	var/list/row = status_dose(id)
	if(!row || !row[H_EXPIRES])
		return 0
	return max(row[H_EXPIRES] - stat_clock_now(src, HOLD_CLOCK_BIO), 0)

/// status_remaining() in units at the current rate, rounded up.
/datum/proc/status_units(id)
	var/left = status_remaining(id)
	return left ? CEILING(left * status_rate(id) / LIFE_CYCLE, 1) : 0

/// status_remaining() in seconds, for readouts.
/datum/proc/status_seconds(id)
	return status_remaining(id) / (1 SECONDS)

// ---------------------------------------------------------------- writing

/// "Can't go below": the own dose lasts at least `amount` units from now. Never shortens.
/datum/proc/status_at_least(id, amount)
	var/datum/status_policy/P = status_policy(id)
	amount = status_increase(P, amount)
	if(amount <= 0)
		return FALSE
	if(P.max_units)
		amount = min(amount, P.max_units)
	var/rate = status_rate(id)
	var/now = stat_clock_now(src, HOLD_CLOCK_BIO)
	var/until = now + amount * LIFE_CYCLE / rate
	var/list/row = status_dose(id)
	if(row && row[H_EXPIRES] >= until)
		return TRUE
	hold_until(src, id, rate, SRC_STATUS, until, clock = HOLD_CLOCK_BIO)
	return TRUE

/// Exactly `amount` units from now for the own dose; 0 ends it (other sources' holds stay).
/datum/proc/status_set(id, amount)
	var/datum/status_policy/P = status_policy(id)
	if(amount <= 0)
		release(src, id, SRC_STATUS)
		return TRUE
	if(!status_admit(P, amount))
		return FALSE
	if(P.max_units)
		amount = min(amount, P.max_units)
	status_increased(P)
	var/rate = status_rate(id)
	hold_until(src, id, rate, SRC_STATUS, stat_clock_now(src, HOLD_CLOCK_BIO) + amount * LIFE_CYCLE / rate, clock = HOLD_CLOCK_BIO)
	return TRUE

/// Adds `amount` units to the own dose; negative shortens it, and at or below now ends it. An increase is admitted and scaled like
/// status_at_least(); a capped status never exceeds its cap.
/datum/proc/status_adjust(id, amount)
	var/datum/status_policy/P = status_policy(id)
	if(amount > 0)
		amount = status_increase(P, amount)
		if(amount <= 0)
			return FALSE
	var/rate = status_rate(id)
	var/now = stat_clock_now(src, HOLD_CLOCK_BIO)
	var/list/row = status_dose(id)
	var/until = max(row ? row[H_EXPIRES] : now, now) + amount * LIFE_CYCLE / rate
	if(P.max_units)
		until = min(until, now + P.max_units * LIFE_CYCLE / rate)
	if(until <= now)
		release(src, id, SRC_STATUS)
		return TRUE
	hold_until(src, id, rate, SRC_STATUS, until, clock = HOLD_CLOCK_BIO)
	return TRUE

/// Ends the own dose (other sources' holds stay).
/datum/proc/status_end(id)
	release(src, id, SRC_STATUS)

/// The rate of `id` may have changed (resting, a blindfold): what is left of the own dose is rescaled so the same number of units remains,
/// worn off at the new rate from now on.
/datum/proc/status_rate_check(id)
	var/list/row = status_dose(id)
	if(!row || !row[H_EXPIRES])
		return
	var/used = row[H_VALUE]
	var/rate = status_rate(id)
	if(!used || used == rate)
		return
	var/now = stat_clock_now(src, HOLD_CLOCK_BIO)
	hold_until(src, id, rate, SRC_STATUS, now + (row[H_EXPIRES] - now) * used / rate, clock = HOLD_CLOCK_BIO)

// ---------------------------------------------------------------- admission, rates and hooks

/// An increase: admitted, then scaled. Returns the units to add, 0 when refused.
/datum/proc/status_increase(datum/status_policy/P, amount)
	if(amount <= 0 || !status_admit(P, amount))
		return 0
	if(P.scaled)
		amount = status_scale(P.id, amount)
	if(amount > 0)
		status_increased(P)
	return amount

/datum/proc/status_increased(datum/status_policy/P)
	if(P.on_increase && ismob(src))
		call(src, P.on_increase)()

/// Admission of an increase: the immunity, then the status's veto event.
/datum/proc/status_admit(datum/status_policy/P, amount)
	if(status_immune(P.id))
		return FALSE
	var/event_path = P.veto
	if(!event_path || !om_wants(src, event_path))
		return TRUE
	return !(om_emit(src, new event_path(amount)) & COMPONENT_NO_STUN)

/// Units of status `id` that wear off per LIFE_CYCLE on this entity.
/datum/proc/status_rate(id)
	var/datum/status_policy/P = status_policy(id)
	if(P.wear_resting && status_resting())
		return P.wear_resting
	return P.wear

/// TRUE while this entity rests (statuses with a wear_resting wear off at it).
/datum/proc/status_resting()
	return FALSE

/// Scales an increase of a `scaled` status (resistances).
/datum/proc/status_scale(id, amount)
	return amount

/// The stat layer: status `id` started (`active`) or ended on this entity. Its hooks run, its presentation follows, and the mob's status
/// change is announced (CHANGE_MOB_STATUS, MOB_KEY_STATUS).
/datum/proc/status_flipped(id, active)
	var/datum/status_policy/P = status_policies()["[id]"]
	if(!P)
		return
	if(ismob(src))
		var/hook = active ? P.on_start : P.on_end
		if(hook)
			call(src, hook)()
		if(P.alert || P.indicator)
			status_shown(P, active)
	// ALLOW(sys_manual_push): the legacy status channel the OM consumers and Life step reads still wake on, raised once per start or end as the OM status rows did
	changed(src, CHANGE_MOB_STATUS)
	PUBLISH_CHANGE(src, MOB_KEY_STATUS)

/// A status with an alert or indicator started (`active`) or ended.
/datum/proc/status_shown(datum/status_policy/P, active)
	return

// ---------------------------------------------------------------- godmode and immunity sources

/// TRUE while `M` is in godmode.
/proc/in_godmode(datum/M)
	return !!stat_value(M, STAT_GODMODE)

/// Puts the mob in godmode. FALSE if it already was.
/mob/proc/enable_godmode()
	if(in_godmode(src))
		return FALSE
	hold(src, STAT_GODMODE, source = SRC_GODMODE)
	return TRUE

/// Takes the mob out of godmode.
/mob/proc/disable_godmode()
	release(src, STAT_GODMODE, SRC_GODMODE)

/// Holds every incapacitation immunity on `M` with `source` as the source.
/proc/hold_incapacitation_immunity(mob/M, source)
	hold(M, STAT_IMMUNE(STAT_STUNNED), source = source)
	hold(M, STAT_IMMUNE(STAT_WEAKENED), source = source)
	hold(M, STAT_IMMUNE(STAT_PARALYZED), source = source)

/proc/release_incapacitation_immunity(mob/M, source)
	release(M, STAT_IMMUNE(STAT_STUNNED), source)
	release(M, STAT_IMMUNE(STAT_WEAKENED), source)
	release(M, STAT_IMMUNE(STAT_PARALYZED), source)

/// Mutation -> list(the source its immunities are held under, the statuses it makes the mob immune to while it has it).
GLOBAL_LIST_INIT(mutation_immunities, list(
	"[HULK]" = list(SRC_MUTATION_HULK, STAT_STUNNED, STAT_WEAKENED, STAT_PARALYZED),
))

/// Holds (or releases) the status immunities mutation `mut` grants. Called by add_mutation() and remove_mutation(); each mutation has its
/// own source, so two sources never release each other.
/mob/proc/update_mutation_immunities(mut)
	var/list/row = GLOB.mutation_immunities["[mut]"]
	if(!row)
		return
	var/source = row[1]
	var/held = has_mutation(mut)
	for(var/i in 2 to length(row))
		if(held)
			hold(src, STAT_IMMUNE(row[i]), source = source)
		else
			release(src, STAT_IMMUNE(row[i]), source)
