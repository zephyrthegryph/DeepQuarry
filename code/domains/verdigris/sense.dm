// Sensing: a holder reacts to a Rust-owned value moving to another band, and hears only the band (S5; verdigris/ffi/src/sense.rs).
//
//   sensed(id = "pressure", reading = CH_GAS_PRESSURE, bands = list(20, 100), changed = PROC_REF(pressure_band), air = nameof(air_contents))
//   sensed(id = "temperature", reading = CH_GAS_TEMPERATURE, bands_from = PROC_REF(temperature_limits), changed = PROC_REF(temperature_band))   // limits a player can edit
//
// `source` is what is sensed (SENSE_SOURCE_GAS, the default, or SENSE_SOURCE_CHARGE, a SMES's stored charge); `reading` is a channel of the sensed cell (a CH_GAS_* of the mixture the holder holds in var `air`, or of the air of the turf it stands on when
// `air` is null). `bands` are the increasing levels; the band is how many of them the value is at or over (0 below the first). `strict` counts every
// level only once the value is past it (`value > level`): Rust compares that way, DM does not nudge levels. `bands_from` is a holder proc x(reading)
// returning the levels, `limits_from` one returning list(levels, stricts) where stricts is a list parallel to the levels (a level may be strict or not
// one by one); `hysteresis` is the distance back past a level the value must travel to leave it (-1: the channel's); both are read again whenever the holder calls sensed_relevel() (a limit was edited). `id` names the declaration on the holder (the key of sensed_band() and sensed_relevel()): a holder that senses several airs or readings gives each its own. The handler is x(band, was): it runs the frame
// Rust finds the band changed, and reads whatever else it needs itself. The band the holder is in now is sensed_band().
//
// Nothing is sent per change. Rust keeps one threshold set per (cell, channel) and this holder's levels are entries on it; DM queues
// add/remove/forget commands and sends the whole queue once per frame (vg_sense_commit). Each add carries the band DM read, so a change between
// the read and the arming still reaches the holder. The holder follows its mixture (atmos_air_set() calls sensed_rearm_all()) and is forgotten
// when it is destroyed.

CAPABILITY_TYPE(sensed, CAP_SENSED, /datum/capability/lib/sensed, key = id, id = null, reading = CH_GAS_PRESSURE, bands = null, bands_from = null, limits_from = null, strict = FALSE, hysteresis = -1, source = SENSE_SOURCE_GAS, air = null, changed = null)

/datum/capability/lib/sensed
	holder_hooks = HOLDER_HOOK_INIT | HOLDER_HOOK_DESTROY

/datum/capability/lib/sensed/cap_data_type()
	return /datum/cap_data/sensed

/// One holder's sensing of one value: the declaration's id and the subscription that is registered with Rust.
/datum/cap_data/sensed
	var/id
	var/datum/sense_sub/sub

CAPABILITIES(/datum/cap_data/sensed)
	owns_one(nameof(sub), /datum/sense_sub)

/// One subscriber of Rust's sensing: the levels of one value of one cell, and who hears the band. A declared sensed() holds one; code that
/// senses cells it picks as it goes (a mob's air, whatever it stands next to) makes them with sense_gas() and owns them.
/datum/sense_sub
	/// The key Rust reports this subscriber under (SSsense numbers them).
	var/key
	/// The cell armed (a Rust handle: the mixture's arena id, the SMES's entity), null while unarmed, and the watch code and channel it is on.
	var/armed_cell
	var/armed_code
	var/armed_channel
	/// The levels armed, and which of them are strict.
	var/list/armed_levels
	var/list/armed_stricts
	/// The band the owner is told it is in.
	var/band = 0
	/// Who hears the band (a plain reference, cleared when it dies) and the proc of it that runs, x(band, was).
	var/datum/owner
	var/handler
	/// The distance back past a level the value must travel to leave it (-1: the channel's).
	var/hysteresis = -1
	/// A declared sensing: its id on the owner. A made one (sense_gas()): the mixture and the channel read.
	var/id
	var/datum/gas_mixture/gas
	var/reading

CAPABILITIES(/datum/sense_sub)
	ref_one(nameof(owner), /datum)
	ref_one(nameof(gas), /datum/gas_mixture, weak = TRUE)

/datum/sense_sub/on_destroy(force)
	SSsense.forget(src)

/// Whether the cells this subscriber senses exist in Rust now (a gas cell or a SMES entity only once the turfs are registered).
/datum/sense_sub/proc/armable()
	return air_turfs_registered()

/// Registers this subscriber again on the cell its source is in now, with the levels it armed (the turfs registered, or its cell moved).
/datum/sense_sub/proc/rearm(list/levels, list/stricts)
	var/datum/gas_mixture/mixture = gas()
	if(mixture)
		sense_gas_arm(src, mixture, levels, stricts)
	else
		sensed_arm_by_id(owner, id)

/datum/capability/lib/sensed/on_holder_init(datum/act/eval/A)
	sensed_arm(A.holder, src)

/datum/capability/lib/sensed/on_holder_destroy(datum/act/eval/A)
	var/datum/cap_data/sensed/data = sensed_data(A.holder, src, FALSE)
	if(!data?.sub)
		return
	SSsense.forget(data.sub)
	rel_clear(data.sub, nameof(data.sub.owner))

/// A holder is being destroyed (engine_forget()): Rust drops every entry of each of its sensings, also when its destroy hook did not run (forgetting twice is nothing).
/proc/sense_forget(datum/D)
	for(var/datum/capability/lib/sensed/def as anything in table_cap_defs(table_of(D), CAP_SENSED))
		var/datum/cap_data/sensed/data = sensed_data(D, def, FALSE)
		if(data?.sub)
			SSsense.forget(data.sub)

/// The sensing record of `holder`'s declaration `def`, or null.
/proc/sensed_data(datum/holder, datum/capability/lib/sensed/def, create = TRUE)
	RETURN_TYPE(/datum/cap_data/sensed)
	var/datum/activation/act = cap_activation(holder, CAP_SENSED, def.id, create)
	return act ? activation_data(act) : null

/// What `def` senses on `holder` now, as list(watch code, cell, channel, value), or null when there is nothing to sense (no mixture, a SMES not yet in Rust).
/datum/capability/lib/sensed/proc/target_of(atom/holder)
	if(source == SENSE_SOURCE_CHARGE)
		var/obj/machinery/power/smes/S = holder
		if(!istype(S) || !S.vg_entity)
			return null
		return list(VG_KIND_SMES, S.vg_entity, smes_charge_channel(), S.stored_charge())
	var/datum/gas_mixture/mixture = gas_air_of(holder, air)
	var/cell = mixture?.arena_id()
	if(isnull(cell))
		return null
	return list(VG_GAS_HANDLES, cell, reading, gas_reading(mixture, reading))

/// The levels `def` senses on `holder` now and which of them count only once the value is past them: list(levels, stricts).
/datum/capability/lib/sensed/proc/limits_of(atom/holder)
	if(limits_from)
		return call(holder, limits_from)(reading)
	var/list/levels = bands_from ? call(holder, bands_from)(reading) : bands
	var/list/stricts = list()
	for(var/level in levels)
		stricts += strict ? TRUE : FALSE
	return list(levels, stricts)

/// The band `value` is in among `levels` (how many it is at or over, or past it where `stricts` says so).
/proc/sense_band(value, list/levels, list/stricts)
	. = 0
	for(var/i in 1 to length(levels))
		if(stricts[i] ? value <= levels[i] : value < levels[i])
			break
		.++

/// Points `holder`'s sensing `def` at its cell and levels now: nothing is sent when it is already armed on them.
/proc/sensed_arm(atom/holder, datum/capability/lib/sensed/def)
	if(!def.changed || (!isnull(def.bands) + !isnull(def.bands_from) + !isnull(def.limits_from)) != 1)
		declare_report("sensed on [holder.type]: it needs a handler `changed` and exactly one of bands, bands_from and limits_from")
		return
	var/datum/cap_data/sensed/data = sensed_data(holder, def)
	if(!data)
		return
	data.id = def.id
	var/datum/sense_sub/sub = data.sub
	if(!sub)
		sub = new
		rel_set(data, nameof(data.sub), sub)
	rel_set(sub, nameof(sub.owner), holder)
	sub.handler = def.changed
	sub.id = def.id
	sub.reading = def.reading
	sub.hysteresis = def.hysteresis
	var/list/limits = def.limits_of(holder)
	var/list/levels = limits[1]
	var/list/stricts = limits[2]
	var/list/target = def.target_of(holder)
	if(!length(levels) || !target)
		SSsense.disarm(sub)
		sub.band = 0
		return
	sub.band = sense_band(target[4], levels, stricts)
	SSsense.arm(sub, target[1], target[2], target[3], levels, stricts)

/// Re-points every sensing of `holder` (it moved, or its air was pointed at another mixture).
/proc/sensed_rearm_all(atom/holder)
	var/datum/type_table/T = table_of(holder)
	for(var/datum/capability/lib/sensed/def as anything in table_cap_defs(T, CAP_SENSED))
		sensed_arm(holder, def)

/// The holder's limits changed (`bands_from` answers differently): its levels are registered again, replacing the old ones in one batch.
/proc/sensed_relevel(atom/holder, id)
	var/datum/capability/lib/sensed/def = cap_of(holder, CAP_SENSED, id)
	if(def)
		sensed_arm(holder, def)

/// The band `holder` last sensed on its declaration `changed` (0 before the first reading).
/proc/sensed_band(atom/holder, id)
	var/datum/capability/lib/sensed/def = cap_of(holder, CAP_SENSED, id)
	var/datum/cap_data/sensed/data = def ? sensed_data(holder, def, FALSE) : null
	return data?.sub ? data.sub.band : 0

/// The levels `holder`'s declaration `id` is registered with now (null when it senses nothing).
/proc/sensed_levels(atom/holder, id)
	var/datum/capability/lib/sensed/def = cap_of(holder, CAP_SENSED, id)
	var/datum/cap_data/sensed/data = def ? sensed_data(holder, def, FALSE) : null
	return data?.sub?.armed_levels

/// Senses channel `reading` of `mixture` against the increasing `levels` (`stricts`: a list parallel to them, TRUE for a level counted only once the value is
/// past it): `owner`'s `handler` runs as x(band, was) when the band changes. The subscription is the caller's to hold (owns_many) and to qdel; it follows
/// the mixture when the turfs register, and is told the band it is in only when that is not the band read here.
/proc/sense_gas(datum/owner, handler, datum/gas_mixture/mixture, reading, list/levels, list/stricts, hysteresis = -1)
	RETURN_TYPE(/datum/sense_sub)
	var/datum/sense_sub/sub = new
	rel_set(sub, nameof(sub.owner), owner)
	sub.handler = handler
	sub.reading = reading
	sub.hysteresis = hysteresis
	rel_set(sub, nameof(sub.gas), mixture)
	if(!stricts)
		stricts = list()
		for(var/level in levels)
			stricts += FALSE
	sense_gas_arm(sub, mixture, levels, stricts)
	return sub

/// Registers a made subscription on `mixture`'s cell.
/proc/sense_gas_arm(datum/sense_sub/sub, datum/gas_mixture/mixture, list/levels, list/stricts)
	var/cell = mixture?.arena_id()
	if(isnull(cell) || !length(levels))
		SSsense.disarm(sub)
		return
	sub.band = sense_band(gas_reading(mixture, sub.reading), levels, stricts)
	SSsense.arm(sub, VG_GAS_HANDLES, cell, sub.reading, levels, stricts)

/// The charge component's channel (a channel index Rust owns).
/proc/smes_charge_channel()
	var/static/channel
	if(isnull(channel))
		channel = vg_world_channel(VG_KIND_SMES, "charge")
	return channel

/// The sensing system: numbers the subscribers, queues their commands and sends them in one batch per frame.
SYSTEM_DEF(sense)
	name = "Sensing"
	/// The next subscriber key (Rust carries it in a 24-bit float, so it wraps well before it could be reused while live).
	VAR_PRIVATE/next_key = 0
	/// Subscribers: key as text -> the record's token (a weak handle).
	VAR_PRIVATE/list/subs = list()
	/// The commands waiting for the next batch, flat (see sense_commit in sense.rs).
	VAR_PRIVATE/list/queue = list()
	/// Batches sent, commands sent, band records heard and handlers run (a trace for tests and the profiler).
	var/commits = 0
	var/commands_sent = 0
	var/records_heard = 0
	var/handled = 0

/datum/system/sense/reactions()
	. = ..()
	. += every(1, PROC_REF(flush), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/sense/proc/key_text(key)
	return num2text(key, 12)

/// Subscribers alive.
/datum/system/sense/proc/live_count()
	return length(subs)

/// Registers (or replaces) `sub`'s levels on `cell`.
/datum/system/sense/proc/arm(datum/sense_sub/sub, code, cell, channel, list/levels, list/stricts)
	if(isnull(sub.key))
		sub.key = ++next_key
		if(next_key >= 16000000)
			next_key = 0
		subs[key_text(sub.key)] = ref_token(sub)
	else if(sub.armed_code == code && sub.armed_cell == cell && sub.armed_levels ~= levels && sub.armed_stricts ~= stricts)
		return
	else if(!isnull(sub.armed_cell) && (sub.armed_cell != cell || sub.armed_code != code))
		queue += list(SENSE_OP_REMOVE, sub.armed_code, sub.armed_cell, sub.armed_channel, sub.key)
	sub.armed_code = code
	sub.armed_channel = channel
	sub.armed_cell = cell
	sub.armed_levels = levels.Copy()
	sub.armed_stricts = stricts.Copy()
	var/strict_mask = 0
	for(var/i in 1 to length(stricts))
		if(stricts[i])
			strict_mask |= 1 << (i - 1)
	if(sub.armable())
		queue += list(SENSE_OP_ADD, code, cell, channel, sub.key, sub.band, strict_mask, sub.hysteresis, length(levels))
		queue += levels
		wake_work_item(PROC_REF(flush))

/// `sub` senses nothing now (no mixture, or no levels).
/datum/system/sense/proc/disarm(datum/sense_sub/sub)
	if(isnull(sub.key) || isnull(sub.armed_cell))
		return
	queue += list(SENSE_OP_REMOVE, sub.armed_code, sub.armed_cell, sub.armed_channel, sub.key)
	sub.armed_cell = null
	sub.armed_code = null
	sub.armed_channel = null
	sub.armed_levels = null
	sub.armed_stricts = null
	wake_work_item(PROC_REF(flush))

/// `sub`'s owner is gone: Rust drops every entry of its key.
/datum/system/sense/proc/forget(datum/sense_sub/sub)
	if(isnull(sub.key))
		return
	subs -= key_text(sub.key)
	queue += list(SENSE_OP_FORGET, sub.key)
	sub.key = null
	sub.armed_cell = null
	sub.armed_code = null
	sub.armed_channel = null
	sub.armed_levels = null
	sub.armed_stricts = null
	wake_work_item(PROC_REF(flush))

/// The turfs are registered (their air moved into Rust cells): every subscriber is armed again on the cell its mixture is in now.
/datum/system/sense/proc/air_ready()
	for(var/key in subs)
		var/datum/sense_sub/sub = resolve_token(subs[key])
		var/datum/owner = sub?.owner
		if(!owner || QDELETED(owner))
			continue
		var/list/levels = sub.armed_levels
		var/list/stricts = sub.armed_stricts
		sub.armed_cell = null
		sub.armed_code = null
		sub.armed_channel = null
		sub.armed_levels = null
		sub.armed_stricts = null
		sub.rearm(levels, stricts)

/proc/sensed_arm_by_id(atom/holder, id)
	var/datum/capability/lib/sensed/def = cap_of(holder, CAP_SENSED, id)
	if(def)
		sensed_arm(holder, def)

/// Sends the queued commands: one call, however many subscribers changed this frame.
/datum/system/sense/proc/flush(dt)
	if(!length(queue))
		return STEP_PARK
	var/list/batch = queue
	queue = list()
	commits++
	commands_sent += length(batch)
	var/list/refused = vg_sense_commit(batch)
	if(length(refused))
		log_world("SENSE_REFUSED: [length(refused)] sensing(s) refused: [vg_sense_refused()]")
	return STEP_PARK

/// Rust reported subscriber `key` in `band` (it was in `was`): its owner's handler runs.
/datum/system/sense/proc/heard(key, band, was)
	records_heard++
	var/datum/sense_sub/sub = resolve_token(subs[key_text(key)])
	var/datum/target = sub?.owner
	if(!target || QDELETED(target))
		return
	sub.band = band
	handled++
	holder_call(target, sub.handler, list(band, was))
