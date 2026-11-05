// A heat body as a sensed source (code/domains/verdigris/sense.dm): a subscriber that hears an atom's temperature move to another band.
//
//   sense_heat(owner, PROC_REF(x), atom, list(levels), stricts, hysteresis, keep_body)   x(band, was)
//
// The band is how many of the increasing `levels` the temperature is at or over (a strict level: past it). The subscription follows the atom's
// heat body: an atom at rest has none and reads its surroundings, so the subscription waits and is armed on the body when one is created
// (heat_body_created()). With `keep_body` the atom gets a body now and keeps it while it is sensed, so the band is followed at rest too.
// The subscription is the caller's to hold (owns_one / owns_many) and to qdel.

/// One subscriber of a heat body's temperature.
/datum/sense_sub/heat
	/// The atom whose temperature is sensed (it lists its subscribers in heat_subs, to hand them each new body).
	var/atom/heat_target
	/// The target keeps a heat body while this subscription lives.
	var/keep_body = TRUE
	/// The levels (and which are strict) sensed: kept here because the subscription waits for a body while its target is at rest.
	var/list/levels
	var/list/stricts
	/// The temperature has been read once (`band` is then what the owner was told, and arming a new body closes any gap).
	var/read = FALSE

/// `target` and the atom's heat_subs name each other (setting `heat_target` lists the subscriber there).
CAPABILITIES(/datum/sense_sub/heat)
	links(/datum/sense_sub/heat::heat_target, /atom::heat_subs, b_many = TRUE)

/// Sensing subscribers of this atom's heat body (handed each body it gets).
/atom/var/tmp/list/heat_subs

/datum/sense_sub/heat/armable()
	return TRUE

/datum/sense_sub/heat/rearm(list/ignored_levels, list/ignored_stricts)
	if(QDELETED(heat_target) || !length(levels))
		SSsense.disarm(src)
		return
	var/atom/target = heat_target
	if(keep_body)
		if(!target.create_heat_body(TRUE))
			SSsense.disarm(src)
			return
		vg_heat_body_keep(target.heat_body, TRUE)
	else
		HEAT_BODY_RESOLVE(target)
		if(!isnull(target.heat_body) && isnull(vg_heat_body_temperature(target.heat_body)))
			target.set_heat_body(null)
	if(!read)
		read = TRUE
		band = sense_band(target.get_temperature(), levels, stricts)
	var/body = target.heat_body
	if(isnull(body))
		SSsense.disarm(src)
		return
	var/code = VG_KIND_HEATBODY
	SSsense.arm(src, code, body, heat_temperature_channel(code), levels, stricts)

/// Senses `target`'s temperature against the increasing `levels` (`stricts`: parallel to them, TRUE for a level counted only once the temperature is
/// past it): `owner`'s `handler` runs as x(band, was) when the band changes. Returns the subscription (null when `keep_body` could not give the target a body).
/proc/sense_heat(datum/owner, handler, atom/target, list/levels, list/stricts, hysteresis = -1, keep_body = TRUE)
	RETURN_TYPE(/datum/sense_sub/heat)
	if(!stricts)
		stricts = list()
		for(var/level in levels)
			stricts += FALSE
	var/datum/sense_sub/heat/sub = new
	rel_set(sub, nameof(sub.owner), owner)
	sub.handler = handler
	sub.hysteresis = hysteresis
	sub.keep_body = keep_body
	sub.levels = levels.Copy()
	sub.stricts = stricts.Copy()
	rel_set(sub, nameof(sub.heat_target), target)
	sub.rearm()
	if(keep_body && isnull(target.heat_body))
		qdel(sub)
		return null
	return sub
