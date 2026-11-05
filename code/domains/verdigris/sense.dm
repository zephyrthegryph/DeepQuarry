// Sensing: a holder reacts to a Rust-owned value moving to another band, and hears only the band (S5; verdigris/ffi/src/sense.rs).
//
//   sensed(id = "pressure", reading = CH_GAS_PRESSURE, bands = list(20, 100), changed = PROC_REF(pressure_band), air = nameof(air_contents))
//   sensed(id = "temperature", reading = CH_GAS_TEMPERATURE, bands_from = PROC_REF(temperature_limits), changed = PROC_REF(temperature_band))   // limits a player can edit
//
// `reading` is a channel of the sensed cell (a CH_GAS_* of the mixture the holder holds in var `air`, or of the air of the turf it stands on when
// `air` is null). `bands` are the increasing levels; the band is how many of them the value is at or over (0 below the first). `strict` counts every
// level only once the value is past it (`value > level`): Rust compares that way, DM does not nudge levels. `bands_from` is a holder proc x(reading)
// returning the levels, `limits_from` one returning list(levels, stricts) where stricts is a list parallel to the levels (a level may be strict or not
// one by one); both are read again whenever the holder calls sensed_relevel() (a limit was edited). `id` names the declaration on the holder (the key of sensed_band() and sensed_relevel()): a holder that senses several airs or readings gives each its own. The handler is x(band, was): it runs the frame
// Rust finds the band changed, and reads whatever else it needs itself. The band the holder is in now is sensed_band().
//
// Nothing is sent per change. Rust keeps one threshold set per (cell, channel) and this holder's levels are entries on it; DM queues
// add/remove/forget commands and sends the whole queue once per frame (vg_sense_commit). Each add carries the band DM read, so a change between
// the read and the arming still reaches the holder. The holder follows its mixture (atmos_air_set() calls sensed_rearm_all()) and is forgotten
// when it is destroyed.

CAPABILITY_TYPE(sensed, CAP_SENSED, /datum/capability/lib/sensed, key = id, id = null, reading = CH_GAS_PRESSURE, bands = null, bands_from = null, limits_from = null, strict = FALSE, air = null, changed = null)

/datum/capability/lib/sensed
	holder_hooks = HOLDER_HOOK_INIT | HOLDER_HOOK_DESTROY

/datum/capability/lib/sensed/cap_data_type()
	return /datum/cap_data/sensed

/// One holder's sensing of one value.
/datum/cap_data/sensed
	/// The key Rust reports this subscriber under (SSsense numbers them).
	var/key
	/// The cell armed: arena id of the mixture, null while unarmed.
	var/armed_cell
	/// The levels armed, and which of them are strict.
	var/list/armed_levels
	var/list/armed_stricts
	/// The band the holder is told it is in.
	var/band = 0
	/// The holder (a plain reference, cleared when it dies) and the handler key of its declaration.
	var/atom/holder
	var/handler
	/// The declaration's id (its key on the holder) and the reading it senses.
	var/id
	var/reading

CAPABILITIES(/datum/cap_data/sensed)
	ref_one(nameof(holder), /atom)

/datum/capability/lib/sensed/on_holder_init(datum/act/eval/A)
	sensed_arm(A.holder, src)

/datum/capability/lib/sensed/on_holder_destroy(datum/act/eval/A)
	var/datum/cap_data/sensed/data = sensed_data(A.holder, src, FALSE)
	if(!data)
		return
	SSsense.forget(data)
	rel_clear(data, nameof(data.holder))

/// The sensing record of `holder`'s declaration `def`, or null.
/proc/sensed_data(datum/holder, datum/capability/lib/sensed/def, create = TRUE)
	RETURN_TYPE(/datum/cap_data/sensed)
	var/datum/activation/act = cap_activation(holder, CAP_SENSED, def.id, create)
	return act ? activation_data(act) : null

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
/datum/capability/lib/sensed/proc/band_of(value, list/levels, list/stricts)
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
	rel_set(data, nameof(data.holder), holder)
	data.handler = def.changed
	data.id = def.id
	data.reading = def.reading
	var/list/limits = def.limits_of(holder)
	var/list/levels = limits[1]
	var/list/stricts = limits[2]
	var/datum/gas_mixture/mixture = gas_air_of(holder, def.air)
	var/cell = mixture?.arena_id()
	if(!length(levels) || isnull(cell))
		SSsense.disarm(data, def)
		data.band = 0
		return
	var/value = gas_level_read(mixture, def.reading)
	data.band = def.band_of(value, levels, stricts)
	SSsense.arm(data, def, cell, levels, stricts)

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
	return data ? data.band : 0

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

/// Registers (or replaces) `data`'s levels on `cell`.
/datum/system/sense/proc/arm(datum/cap_data/sensed/data, datum/capability/lib/sensed/def, cell, list/levels, list/stricts)
	if(isnull(data.key))
		data.key = ++next_key
		if(next_key >= 16000000)
			next_key = 0
		subs[key_text(data.key)] = ref_token(data)
	else if(data.armed_cell == cell && data.armed_levels ~= levels && data.armed_stricts ~= stricts)
		return
	else if(!isnull(data.armed_cell) && data.armed_cell != cell)
		queue += list(SENSE_OP_REMOVE, VG_GAS_HANDLES, data.armed_cell, def.reading, data.key)
	data.armed_cell = cell
	data.armed_levels = levels.Copy()
	data.armed_stricts = stricts.Copy()
	var/strict_mask = 0
	for(var/i in 1 to length(stricts))
		if(stricts[i])
			strict_mask |= 1 << (i - 1)
	if(air_turfs_registered())
		queue += list(SENSE_OP_ADD, VG_GAS_HANDLES, cell, def.reading, data.key, data.band, strict_mask, length(levels))
		queue += levels
		wake_work_item(PROC_REF(flush))

/// `data` senses nothing now (no mixture, or no levels).
/datum/system/sense/proc/disarm(datum/cap_data/sensed/data, datum/capability/lib/sensed/def)
	if(isnull(data.key) || isnull(data.armed_cell))
		return
	queue += list(SENSE_OP_REMOVE, VG_GAS_HANDLES, data.armed_cell, def.reading, data.key)
	data.armed_cell = null
	data.armed_levels = null
	data.armed_stricts = null
	wake_work_item(PROC_REF(flush))

/// `data`'s holder is gone: Rust drops every entry of its key.
/datum/system/sense/proc/forget(datum/cap_data/sensed/data)
	if(isnull(data.key))
		return
	subs -= key_text(data.key)
	queue += list(SENSE_OP_FORGET, data.key)
	data.key = null
	data.armed_cell = null
	data.armed_levels = null
	data.armed_stricts = null
	wake_work_item(PROC_REF(flush))

/// The turfs are registered (their air moved into Rust cells): every subscriber is armed again on the cell its mixture is in now.
/datum/system/sense/proc/air_ready()
	for(var/key in subs)
		var/datum/cap_data/sensed/data = resolve_token(subs[key])
		var/atom/holder = data?.holder
		if(!holder || QDELETED(holder))
			continue
		data.armed_cell = null
		data.armed_levels = null
		data.armed_stricts = null
		sensed_arm_by_id(holder, data.id)

/proc/sensed_arm_by_id(atom/holder, id)
	var/datum/capability/lib/sensed/def = cap_of(holder, CAP_SENSED, id)
	if(def)
		sensed_arm(holder, def)

/// Sends the queued commands: one call, however many subscribers changed this frame.
/datum/system/sense/proc/flush(dt)
	if(!length(queue) || !air_turfs_registered())
		return STEP_PARK
	var/list/batch = queue
	queue = list()
	commits++
	commands_sent += length(batch)
	var/list/refused = vg_sense_commit(batch)
	if(length(refused))
		log_world("SENSE_REFUSED: [length(refused)] sensing(s) refused: [vg_sense_refused()]")
	return STEP_PARK

/// Rust reported subscriber `key` in `band` (it was in `was`): its holder's handler runs.
/datum/system/sense/proc/heard(key, band, was)
	records_heard++
	var/datum/cap_data/sensed/data = resolve_token(subs[key_text(key)])
	var/atom/target = data?.holder
	if(!target || QDELETED(target))
		return
	data.band = band
	handled++
	holder_call(target, data.handler, list(band, was))
