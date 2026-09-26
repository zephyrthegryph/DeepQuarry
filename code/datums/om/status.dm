// Object-model core: timed statuses (doc/rewrite/object_model_core.md section E.1).
//
// A status is an effect row with `"kind" = OM_EFFECT_STATUS`: a timed contribution with a
// duration in units, an immunity, a wear rate, presentation (alert, indicator), a veto signal and
// hooks, all declared as fields. Nothing counts a status down: its expiry is a deadline, and
// starting or ending it raises its channel once.
//
// Amounts are units. One unit lasts `unit` deciseconds at rate 1; `rate` units wear off per unit
// of time (the entity may change the rate: status_rate()). An entity's own dose is the timed
// contribution it holds on itself with no key; anything else (a hold with its own key, another
// source's timed apply) also keeps the status on, but the API below reads and writes the dose.
// A dose's contribution value is the rate its expiry was computed with, so a rate change can
// rescale what is left (status_rate_check()).

/datum/om/effect/status
	kind = OM_EFFECT_STATUS
	/// Deciseconds one unit lasts at rate 1.
	var/unit = 1 SECONDS
	/// Units that wear off per `unit` of time.
	var/rate = 1
	/// Rate while the entity rests (status_resting()); 0: no difference.
	var/rate_resting = 0
	/// Most units the status can hold (0: no cap).
	var/max_units = 0
	/// Effect id that blocks increases and, gained, ends the status.
	var/immunity
	var/immunity_idx = 0
	/// Increases pass through the entity's status_scale() (resistances).
	var/scaled = FALSE
	/// Sent before an increase (amount); COMPONENT_NO_STUN in the result vetoes it.
	var/signal
	/// Screen alert while active (category and type), and a status indicator (icon state).
	var/alert
	var/alert_type
	var/indicator
	/// The entity type the hooks and presentation are for (the status still works on others).
	var/entity_type
	/// Procs called on the entity when the status starts, ends, or is increased.
	var/on_start
	var/on_end
	var/on_increase

/datum/om/effect/status/proc/parse_row(list/row, datum/om/registry/reg)
	for(var/key in list("unit", "rate", "rate_resting", "max_units"))
		if(!isnull(row[key]))
			if(!isnum(row[key]) || row[key] < 0)
				reg.error("status [id]: [key] must be a number >= 0")
				continue
			vars[key] = row[key]
	if(unit <= 0 || rate <= 0)
		reg.error("status [id]: unit and rate must be above 0")
		unit = max(unit, 1)
		rate = max(rate, 1)
	immunity = row["immunity"]
	scaled = !!row["scaled"]
	signal = row["signal"]
	alert = row["alert"]
	alert_type = row["alert_type"]
	indicator = row["indicator"]
	if(alert && !ispath(alert_type))
		reg.error("status [id]: alert needs an alert_type")
		alert = null
	entity_type = row["entity_type"]
	on_start = row["on_start"]
	on_end = row["on_end"]
	on_increase = row["on_increase"]

/datum/om/effect/status/on_changed(datum/E, old_value, new_value)
	if(QDELETED(E) || (entity_type && !istype(E, entity_type)))
		return
	var/active = !!new_value
	var/hook = active ? on_start : on_end
	if(hook)
		call(E, hook)()
	if(alert || indicator)
		E.status_shown(src, active)

/// The status def for `id`. One registry lookup; everything after it works on the def.
/proc/om_status_def(id)
	RETURN_TYPE(/datum/om/effect/status)
	var/datum/om/effect/status/def = om_registry().effect_by_id[id]
	if(!istype(def))
		CRASH("om: [id] is not a status")
	return def

// ---------------------------------------------------------------- reading

/// TRUE while `id` is in effect (any source, timed or held).
/datum/proc/has_status(id)
	return om_has(src, id)

/// TRUE while this entity holds the immunity that blocks `id`.
/datum/proc/status_immune(id)
	var/datum/om/effect/status/def = om_status_def(id)
	var/datum/om/rec/rec = om_rec
	return def.immunity_idx && rec?.contribs && om_effect_value(rec, om_registry().effects[def.immunity_idx])

/// Deciseconds until the last timed contribution to `id` expires (0 when there is none). A hold
/// has no duration and doesn't count: read has_status() for "in effect at all".
/datum/proc/status_remaining(id)
	var/datum/om/rec/rec = om_rec
	if(!rec?.contribs)
		return 0
	return om_status_remaining(rec, om_status_def(id))

/// status_remaining() in units at the current rate, rounded up.
/datum/proc/status_units(id)
	var/datum/om/rec/rec = om_rec
	if(!rec?.contribs)
		return 0
	var/datum/om/effect/status/def = om_status_def(id)
	var/left = om_status_remaining(rec, def)
	return left ? CEILING(left * status_rate(def) / def.unit, 1) : 0

/proc/om_status_remaining(datum/om/rec/rec, datum/om/effect/status/def)
	var/latest = om_contrib_latest_expiry(rec, def.idx)
	return latest ? max(latest - rec.sched.now(), 0) : 0

/// status_remaining() in seconds, for readouts.
/datum/proc/status_seconds(id)
	return status_remaining(id) / (1 SECONDS)

// ---------------------------------------------------------------- writing

/// "Can't go below": the own dose lasts at least `amount` units from now. Never shortens.
/datum/proc/status_at_least(id, amount)
	var/datum/om/effect/status/def = om_status_def(id)
	amount = status_increase(def, amount)
	if(amount <= 0)
		return FALSE
	if(def.max_units)
		amount = min(amount, def.max_units)
	var/datum/om/rec/rec = om_rec_of(src)
	if(!rec)
		return FALSE
	var/now = rec.sched.now()
	var/rate = status_rate(def)
	var/until = now + amount * def.unit / rate
	var/own = om_contrib_expiry(rec, def.idx, src, null)
	if(own == 0)
		return TRUE // a keyless hold by the entity itself already outlasts any dose
	if(until > (own || now))
		om_contrib_until(rec, def, src, until, rate, null)
	return TRUE

/// Exactly `amount` units from now for the own dose; 0 ends it (other sources' contributions stay).
/datum/proc/status_set(id, amount)
	var/datum/om/effect/status/def = om_status_def(id)
	if(amount > 0)
		if(!status_admit(def, amount))
			return FALSE
		if(def.max_units)
			amount = min(amount, def.max_units)
		if(def.on_increase && (!def.entity_type || istype(src, def.entity_type)))
			call(src, def.on_increase)()
	var/datum/om/rec/rec = om_rec_of(src)
	if(!rec)
		return FALSE
	var/rate = status_rate(def)
	om_contrib_until(rec, def, src, rec.sched.now() + max(amount, 0) * def.unit / rate, rate, null)
	return TRUE

/// Adds `amount` units to the own dose; negative shortens it, never below now. An increase is
/// admitted and scaled like status_at_least(); a capped status never exceeds its cap.
/datum/proc/status_adjust(id, amount)
	var/datum/om/effect/status/def = om_status_def(id)
	if(amount > 0)
		amount = status_increase(def, amount)
		if(amount <= 0)
			return FALSE
	var/datum/om/rec/rec = om_rec_of(src)
	if(!rec)
		return FALSE
	var/now = rec.sched.now()
	var/rate = status_rate(def)
	var/own = om_contrib_expiry(rec, def.idx, src, null)
	var/until = max(own || now, now) + amount * def.unit / rate
	if(def.max_units)
		until = min(until, now + def.max_units * def.unit / rate)
	om_contrib_until(rec, def, src, until, rate, null)
	return TRUE

/// Ends the own dose (other sources' contributions stay).
/datum/proc/status_end(id)
	var/datum/om/rec/rec = om_rec
	if(rec)
		om_contrib_release(rec, om_status_def(id), src, null)

/// The rate of `id` may have changed (resting, a blindfold): what is left of the own dose is
/// rescaled so the same number of units remains, worn off at the new rate from now on.
/datum/proc/status_rate_check(id)
	var/datum/om/rec/rec = om_rec
	if(!rec?.contribs)
		return
	var/datum/om/effect/status/def = om_status_def(id)
	var/used = om_contrib_value(rec, def.idx, src, null)
	var/expires = om_contrib_expiry(rec, def.idx, src, null)
	var/rate = status_rate(def)
	if(!expires || !used || used == rate)
		return
	var/now = rec.sched.now()
	om_contrib_until(rec, def, src, now + (expires - now) * used / rate, rate, null)

// ---------------------------------------------------------------- admission and hooks

/// An increase: admitted, then scaled. Returns the units to add, 0 when blocked.
/datum/proc/status_increase(datum/om/effect/status/def, amount)
	if(amount <= 0 || !status_admit(def, amount))
		return 0
	if(def.scaled)
		amount = status_scale(def, amount)
	if(amount > 0 && def.on_increase && (!def.entity_type || istype(src, def.entity_type)))
		call(src, def.on_increase)()
	return amount

/// Admission of an increase: the immunity, then the status's veto signal.
/datum/proc/status_admit(datum/om/effect/status/def, amount)
	var/datum/om/rec/rec = om_rec
	if(def.immunity_idx && rec?.contribs && om_effect_value(rec, om_registry().effects[def.immunity_idx]))
		return FALSE
	return !(def.signal && (SEND_SIGNAL(src, def.signal, amount) & COMPONENT_NO_STUN))

/// Units of `def` that wear off per unit of time on this entity.
/datum/proc/status_rate(datum/om/effect/status/def)
	if(def.rate_resting && status_resting())
		return def.rate_resting
	return def.rate

/// TRUE while this entity rests (statuses with a rate_resting wear off at it).
/datum/proc/status_resting()
	return FALSE

/// Scales an increase of a `scaled` status (resistances).
/datum/proc/status_scale(datum/om/effect/status/def, amount)
	return amount

/// A status with an alert or indicator started (`active`) or ended.
/datum/proc/status_shown(datum/om/effect/status/def, active)
	return
