/**
 * # The native system
 *
 * The one place Rust-owned change enters DM. Once per tick `frame()` makes the single call into the
 * simulation, `vg_frame()` (verdigris/ffi/src/frame.rs), which steps the Rust world, its pipe devices,
 * heat and timers and returns one outbox page of records:
 *
 * | record | meaning | delivered as |
 * |---|---|---|
 * | NATIVE_REC_CHANGED (entity, key) | a value changed | native_publish_change(), or the watch that asked |
 * | NATIVE_REC_NOTICE (entity, kind, args) | something happened | the generated `on_<component>_<event>()`, `native_publish_notice()` |
 * | NATIVE_REC_CROSSED (watch, band, detail) | a watch crossed a band | native_crossed() |
 *
 * Nothing else drains the simulation: the old `vg_world_tick`, `vg_drain_events`, `vg_world_step`,
 * `vg_heat_take_wakes` and the gas observation drain are internal to Rust now.
 *
 * `native_read(E, key)` reads a Rust-owned value through a per-frame cache: the first read of an
 * (entity, key) crosses the FFI, later reads of it in the same frame (and until a CHANGED record for
 * the entity) do not.
 *
 * The three `native_*` delivery procs are the seam to the reaction framework (`publish_change`,
 * `PUBLISH` and `on_cross`): today they raise the OM's channels/events and call the watch's own
 * callback; integration points them at the new machinery.
 */
/datum/system/native
	name = "native"
	/// Frames run, and the outbox of the last one, for the profiler.
	var/frames = 0
	var/last_records = 0
	var/last_changed = 0
	var/last_notices = 0
	var/last_crossed = 0
	var/last_frame_ms = 0
	/// world.tick_lag as last sent to Rust.
	var/tick_lag_sent = 0
	/// The wheel tick of the last frame (elapsed ticks are measured from it).
	var/last_tick = 0
	/// "[entity]" -> ("[key]:[index]" -> value) read once this frame; cleared every frame and per entity by CHANGED.
	var/list/read_cache
	/// Reads answered from the cache and reads that crossed the FFI, since boot.
	var/cache_hits = 0
	var/cache_misses = 0
	/// Gas dependency observations waiting for the machine service, in the observation stride
	/// (watch handle first): filled by CHANGED records of gas watches.
	var/list/gas_changes
	/// "[watch handle]" -> its record's index in gas_changes (num2text keys: a number would index the list).
	var/list/gas_change_at
	/// Pipe devices stepped in the last frame.
	var/pipe_devices_last = 0

/datum/system/native/initialize()
	. = ..()
	send_tick_lag()

/// Tells Rust how long a wheel tick is (boot, and whenever world.tick_lag changes).
/datum/system/native/proc/send_tick_lag()
	tick_lag_sent = world.tick_lag
	vg_frame_set_tick_lag(world.tick_lag)

/// The singleton, cached.
/proc/native_system()
	RETURN_TYPE(/datum/system/native)
	var/static/datum/system/native/native
	if(!native)
		native = system(/datum/system/native)
	return native

/// One tick's frame: `tick` is the wheel tick now (om_world_tick_of(world.time)); `budget` the
/// normal/background wakes to take. Returns TRUE when a frame ran.
/datum/system/native/proc/frame(tick, budget = NATIVE_WAKE_BUDGET)
	if(tick_lag_sent != world.tick_lag)
		send_tick_lag()
	var/elapsed = max(tick - last_tick, 0)
	last_tick = tick
	return run_frame(elapsed, budget)

/// Runs a frame for `elapsed` wheel ticks (0: no pacing, only drain: tests that stepped Rust by hand).
/datum/system/native/proc/run_frame(elapsed, budget = NATIVE_WAKE_BUDGET)
	var/start = TICK_USAGE_REAL
	frames++
	read_cache = null
	var/list/box = vg_frame(elapsed, budget)
	deliver(box)
	last_frame_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	return TRUE

/// Test hook: drains what Rust holds now without pacing it (after vg_world_run_steps()).
/datum/system/native/proc/drain()
	return run_frame(0, NATIVE_WAKE_BUDGET * 4)

/// Hands every record of `box` to its consumer, in emission order.
/datum/system/native/proc/deliver(list/box)
	var/n = length(box)
	last_records = 0
	last_changed = 0
	last_notices = 0
	last_crossed = 0
	pipe_devices_last = 0
	var/i = 1
	while(i + 3 <= n)
		var/kind = box[i]
		var/a = box[i + 1]
		var/b = box[i + 2]
		var/count = box[i + 3]
		var/p = i + 4
		i = p + count
		last_records++
		switch(kind)
			if(NATIVE_REC_CHANGED)
				last_changed++
				on_changed(a, b, box, p, count)
			if(NATIVE_REC_NOTICE)
				last_notices++
				on_notice(a, b, box, p, count)
			if(NATIVE_REC_CROSSED)
				last_crossed++
				on_crossed(a, b, box, p, count)

/// CHANGED (`a`, `key`): the gas watch's observation goes to the machine service's queue, a world watch's
/// change wake to its lane, anything else is a change of the entity's datum.
/datum/system/native/proc/on_changed(a, key, list/box, p, count)
	if(read_cache)
		read_cache -= num2text(a, 12)
	var/datum/target = SSvg.entity_lookup(a)
	if(istype(target, /datum/native_watch/gas))
		var/datum/native_watch/gas/G = target
		if(G.handle != a || QDELETED(G))
			GLOB.machine_service.gas_dead_last++
			return
		if(!gas_changes)
			gas_changes = list()
			gas_change_at = list()
		// One record per watch: a later frame's observation of the same watch before the machine
		// service takes the batch replaces the values and ORs the masks (what one drain gave).
		var/watch_key = num2text(a, 12)
		var/at = gas_change_at[watch_key]
		if(at)
			gas_changes[at + 2] |= box[p + 1]
			for(var/j in 2 to count - 1)
				gas_changes[at + 1 + j] = box[p + j]
			return
		gas_change_at[watch_key] = length(gas_changes) + 1
		gas_changes += a
		gas_changes += box.Copy(p, p + count)
		return
	if(istype(target, /datum/native_watch/world))
		var/datum/native_watch/world/W = target
		if(W.handle == a && !QDELETED(W))
			native_crossed(W, 0, list(box[p], key, box[p + 1], 0))
		return
	if(target && !QDELETED(target))
		native_publish_change(target, key)

/// NOTICE (`entity`, `header`, fields at box[p]): a pipe device's step, else a generated typed event.
/datum/system/native/proc/on_notice(entity, header, list/box, p, count)
	if(header == NATIVE_NOTICE_PIPE_DEVICE)
		pipe_devices_last++
		var/obj/machinery/atmospherics/device = SSvg.entity_lookup(entity)
		if(istype(device) && device.rust_owns_device(entity))
			device.rust_device_stepped(box[p], box[p + 1], box[p + 2])
		return
	vg_dispatch_notice(header, entity, box, p)
	if(!entity)
		return
	var/datum/target = SSvg.entity_lookup(entity)
	if(target?.om_rec)
		native_publish_notice(target, header, box.Copy(p, p + count))

/// CROSSED (`watch`, `band`): the watch's own delivery.
/datum/system/native/proc/on_crossed(handle, band, list/box, p, count)
	var/datum/native_watch/W = om_native_watch_of(handle)
	if(!W)
		om_world_dropped()
		return
	native_crossed(W, band, box.Copy(p, p + count))

/// Takes the gas observations gathered since the last take, for the machine service.
/datum/system/native/proc/take_gas_changes()
	. = gas_changes
	gas_changes = null
	gas_change_at = null

/datum/system/native/metrics()
	return alist("name" = name, "members" = 0, "initialized" = initialized, "cost" = last_frame_ms, "tick_usage" = last_frame_ms, "overran" = 0, \
		"frames" = frames, "records" = last_records, "changed" = last_changed, "notices" = last_notices, "crossed" = last_crossed, \
		"cache_hits" = cache_hits, "cache_misses" = cache_misses)

// ---------------------------------------------------------------- delivery seam

/// `E`'s value under `key` (a Rust channel mask, or a DM CHANGE_* channel) changed.
/// Today: raises the OM channel. Integration: publish_change(E, key).
/proc/native_publish_change(datum/E, key)
	if(QDELETED(E) || !key)
		return FALSE
	GLOB.native_deliveries[NATIVE_SRC_OTHER]++
	om_changed(E, key)
	return TRUE

/// Something of `kind` (an event header) happened to `E`, with `args`.
/// Today: an OM event; integration: PUBLISH(E, notice_type, args...).
/proc/native_publish_notice(datum/E, kind, list/args)
	if(QDELETED(E))
		return FALSE
	om_emit(E, new /datum/om/event/native_notice(kind, args))
	return TRUE

/// A native watch crossed `band` with `detail` (the record's numbers): a world watch queues on its lane,
/// a heat watch calls its owner, a threshold-set crossing calls it per entry.
/// Today: the watch's own callback. Integration: on_cross(watch, band, ...).
/proc/native_crossed(datum/native_watch/watch, band, list/detail)
	if(QDELETED(watch) || !watch.handle)
		return FALSE
	return watch.crossed(band, detail)

/// An OM event carrying a native notice, for entities with a record.
/datum/om/event/native_notice
	coalesce = FALSE
	var/kind
	var/list/args

/datum/om/event/native_notice/New(kind, list/args)
	..()
	src.kind = kind
	src.args = args

// ---------------------------------------------------------------- declared pushes

/// A generated setter of a Rust config field (`set_<field>()` in _bindings_types.dm) ran: the type's declared
/// push. Override where the field also feeds Rust state the binding does not own (a device law, a network's
/// share): the override re-publishes it, so no caller pushes by hand after a setter.
/atom/movable/proc/rust_pushed()
	return

// ---------------------------------------------------------------- reads

/// The Rust-owned value of `key` (NATIVE_KEY) on `E` (a bound atom or an entity number), read through the
/// frame's cache. `index` selects an element of an array field.
/proc/native_read(E, key, index = 0)
	var/entity = isnum(E) ? E : native_entity_of(E)
	if(!entity)
		return null
	var/datum/system/native/N = native_system()
	// Text keys (num2text with full digits: "[entity]" rounds a large handle to six): a number would index the list.
	var/entity_key = num2text(entity, 12)
	var/list/cached = N.read_cache?[entity_key]
	var/slot = "[num2text(key, 12)]:[num2text(index, 12)]"
	if(cached && (slot in cached))
		N.cache_hits++
		return cached[slot]
	N.cache_misses++
	var/value = vg_component_get(entity, NATIVE_KEY_CODE(key), NATIVE_KEY_FIELD(key), index)
	if(!N.read_cache)
		N.read_cache = list()
	if(!cached)
		cached = list()
		N.read_cache[entity_key] = cached
	cached[slot] = value
	return value

/// `E`'s entity handle (its vg_entity), or 0.
/proc/native_entity_of(datum/E)
	if(istype(E, /atom/movable))
		var/atom/movable/mover = E
		return mover.vg_entity
	return 0

/// Forgets what native_read() cached for `E` (a write through DM that Rust does not report back).
/proc/native_read_invalidate(E)
	var/entity = isnum(E) ? E : native_entity_of(E)
	var/datum/system/native/N = native_system()
	if(entity && N.read_cache)
		N.read_cache -= num2text(entity, 12)
