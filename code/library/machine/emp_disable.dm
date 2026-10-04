// emp_disable(lasts, resist =, extends =): an electromagnetic pulse takes the holder out of operation for a while (doc/rewrite/final_api.html,
// section 11 "The library": emp_disable(lasts, resist); section 16.1, 16.3).
//
// A pulse that reaches the holder (the hit/emp action got through: shielding refused it before) places a timed hold on STAT_OPERABLE, source
// SRC_EMP, for `lasts` over the pulse's severity; the hold ends by itself and the holder works again. Nothing is set by hand and nothing reverts
// by hand: what the outage does to the holder is what its operability does (its contributions, its on_change hooks).
//
//   emp_disable(5 MINUTES)                                     a fixed outage over severity
//   emp_disable(list(8 MINUTES, 12 MINUTES), extends = TRUE)   a roll between the two; a harder pulse while down lengthens the outage
//   emp_disable(PROC_REF(emp_outage))                          a holder proc x(severity) answers the outage (0: shrugged off)
//   emp_disable(30 SECONDS, resist = 75)                       three pulses in four do nothing
//
// `extends` = FALSE (the default): a pulse while the holder is down changes nothing. TRUE: the longer of the running outage and the new one is kept.
// The holder must declare STAT_OPERABLE (every machine does; an item or a vehicle that can be knocked out declares it beside its type).
// emp_disabled(E) says whether a pulse holds E down now, for code that tells a pulse apart from the other reasons it may not work.

SOURCE_DEF(emp)

MSG_DEF_SELF(emp_disable/down, "It has been knocked out by an electromagnetic pulse.")

CAPABILITY_TYPE(emp_disable, CAP_EMP_DISABLE, /datum/capability/lib/emp_disable, key = NONE, lasts = 0, resist = 0, extends = FALSE)

/datum/capability/lib/emp_disable

/datum/capability/lib/emp_disable/entries()
	return list(on_notice(/datum/notice/hit/emp, then(CAP_PROC(pulsed))))

/// A pulse got through: the holder goes down for its outage (or keeps the longer one when `extends`).
/datum/capability/lib/emp_disable/proc/pulsed(datum/act/A)
	var/datum/notice/hit/emp/N = A
	var/datum/holder = A.holder
	if(resist && prob(resist))
		return
	var/severity = max(N.packet?.severity, 1)
	var/outage = outage_for(holder, severity)
	if(outage <= 0)
		return
	if(held_by_source(holder, STAT_OPERABLE, SRC_EMP) && (!extends || outage <= hold_left(holder, STAT_OPERABLE, SRC_EMP)))
		return
	log_world("EMP_DISABLE: [holder.type] down for [outage / (1 SECOND)] s (severity [severity])")
	hold(holder, STAT_OPERABLE, FALSE, SRC_EMP, outage, reason = /datum/msg/emp_disable/down) // a re-hold keeps the later end (REAPPLY_MAX)

/// How long a pulse of `severity` keeps the holder down: the holder's proc, a roll between two durations, or a duration, over the severity.
/datum/capability/lib/emp_disable/proc/outage_for(datum/holder, severity)
	if(istext(lasts))
		return call(holder, lasts)(severity)
	if(islist(lasts))
		var/list/span = lasts
		return round(rand(span[1], span[2]) / severity)
	return round(lasts / severity)

/// A pulse holds E down now (its emp_disable() outage is running).
/proc/emp_disabled(datum/E)
	READS_FROM(E)
	return held_by_source(E, STAT_OPERABLE, SRC_EMP)

/// Time left on E's pulse outage (deciseconds), 0 when none runs.
/proc/emp_disabled_left(datum/E)
	READS_FROM(E)
	return hold_left(E, STAT_OPERABLE, SRC_EMP) || 0
