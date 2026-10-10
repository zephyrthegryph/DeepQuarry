// cap_state, capability data and the legacy capability declarations (doc/rewrite/dx_conventions.md §2). The datum
// interface is in _capability.dm.

/// The one-line declarations of this type (CAPABILITY(T, entry), code/__defines/capabilities.dm): each line adds
/// one entry after ..(). Collected when the type's table is built (caps_build()).
/atom/proc/declared_capabilities(list/into)
	SHOULD_CALL_PARENT(TRUE)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// The capability of A with this key (a type, or an explicit key), or null.
/proc/legacy_cap_of(atom/A, key)
	return capability_lookup(A, key)

/// L without the entries whose key is `key`, or which are of type `key`. Returns a new list.
/proc/legacy_without(list/L, key)
	return capability_list_without(L, key)

// ---- state ----

/// TRUE when every bit in `bits` is set on A.
/proc/cap_has(atom/A, bits)
	return (capability_bits(A) & bits) == bits

/// Sets or clears `bits` on A through the change path. TRUE when the state changed.
/proc/cap_set(atom/A, bits, on)
	if(isnull(on))
		CRASH("cap_set: `on` is required (TRUE to set, FALSE to clear) for [A?.type]")
	var/was = capability_bits(A)
	var/now = on ? (was | bits) : (was & ~bits)
	if(was == now)
		return FALSE
	capability_runtime(A).bits = now
	changed(A, CHANGE_CAPABILITY)
	// Waiting operations watch cap_state through their requirements' reads (operations/op_ctx.dm).
	engine_key_changed(A, OP_KEY_CAP_STATE)
	return TRUE

/// The per-instance data datum of capability C on A, created on first use (C.data_type).
/proc/legacy_cap_data(atom/A, datum/capability/C)
	return capability_instance_data(A, C)

// The accessors, written once per capability.
/proc/cover_is_open(atom/A)
	return !!(capability_bits(A) & CAP_COVER_OPEN)
/proc/panel_is_open(atom/A)
	READS_FROM(A)
	return !!(capability_bits(A) & CAP_PANEL_OPEN) || !!(cap_of(A, CAP_PANEL) && panel_open(A, null)) // a converted holder keeps it as a capability key (a boolean: a null `when` draws unconditionally)
/proc/is_locked(atom/A)
	return !!(capability_bits(A) & CAP_LOCKED)
/proc/is_broken(atom/A)
	if(capability_bits(A) & CAP_BROKEN)
		return TRUE
	var/obj/machinery/M = A // a converted machine's breakable() reads the machine's own BROKEN bit
	return istype(M) && M.broken_now() && cap_of(A, CAP_BREAKABLE)
/**
 * Whether A's screen or lamps show: it has power, isn't broken and nothing overrides its display
 * (screen_override()). What a lamp or glow draws behind, so every machine answers it the same way.
 */
/proc/is_lit(atom/A)
	return A.cap_powered() && !is_broken(A) && !A.screen_override()

/// TRUE while something other than power or damage keeps the screen from showing its normal display: a
/// bluescreen from a hack or an emag, unsecured electronics. Types with such a state override it; is_lit() reads it.
/atom/proc/screen_override()
	return FALSE

/**
 * Verbs this type has by what it is, beyond the /type/verb/ procs it inherits: a per-type list
 * (built once, no per-instance entry), read by the verb store. For a difference between types that
 * never changes per instance (an advanced scanner has the toggle, a basic one doesn't); state that
 * changes uses hidden_verbs(). Pure: read only initial() values here.
 *	/obj/item/healthanalyzer/type_verbs()
 *		. = ..()
 *		if(initial(profile_type) != /datum/diagnostic_profile/health_analyzer)
 *			. += /obj/item/healthanalyzer/proc/toggle_adv
 */
/// Whether A has power for its entries. Machines answer through their power state; anything else
/// is always powered. The powered capability overrides nothing: it reads this.
/atom/proc/cap_powered()
	return TRUE

/obj/machinery/cap_powered()
	return !power_lost()

// ---- lifecycle hooks ----

/// Runs every capability's on_init, then queues the first refresh when the type may derive something.
/// Called from /atom/Initialize() and table_initialize() after the declarations. Nothing derived is
/// probed here (review 2 H9: a draw() may read what the subtype's Initialize() sets up after ..()):
/// the first instance of each type is always queued, and its refresh records what the type derives.
/proc/caps_init(atom/holder, mapload)
	if(own_table_of(holder).engine_hooks & ENGINE_HOOK_INIT)
		engine_holder_init(holder, mapload)
	var/flags = type_derive_flags(holder)
	if(flags & TYPE_DERIVES_TYPE_VERBS)
		verb_store_refresh(holder, type_verbs_always(holder)) // login entries wait for Login (type_verbs.dm)
	if(flags & TYPE_DERIVES_CAPS)
		for(var/datum/capability/C as anything in caps_of(holder))
			C.legacy_holder_init(holder, mapload)
			cap_join_systems(holder, C)
		refresh_granted_verbs(holder) // capability verbs are there from init, not a frame later
	if(flags & TYPE_DERIVES_DEPS)
		derived_attach(holder)
	if(rx_type_enrols(holder))
		rx_enrol(holder) // per-instance every() work (reactions/work.dm)
	if(flags || holder.periodic_cadence || holder.periodic_interval)
		// The first refresh is queued, nothing changed: changed() would raise CHANGE_EXPLICIT, which every machine's
		// pipeline wakes on (wake_all), so declaring a capability or a membership woke its holder at init.
		refresh_mark(holder, DEP_ALL)

/// Runs every capability's on_destroy and drops the data. Called from /atom/Destroy().
/proc/caps_destroy(atom/holder)
	if(holder.timed_until)
		timed_cancel_all(holder)
	var/flags = GLOB.type_derives_cache[holder.type]
	if(!isnull(flags) && !(flags & TYPE_DERIVES_CAPS) && !capability_data(holder) && !capability_extras(holder))
		return
	var/list/caps = caps_all(holder)
	for(var/datum/capability/C as anything in caps)
		C.legacy_holder_destroy(holder)
		cap_leave_systems(holder, C)
	var/datum/capability_runtime/runtime = capability_runtime_peek(holder)
	if(runtime)
		runtime.extras = null
		for(var/key in runtime.data)
			var/datum/D = runtime.data[key]
			if(isdatum(D))
				ended_with(D, holder)
		runtime.data = null


/// Examine lines from every capability, in list order (appended by /atom/examine()).
/proc/caps_examine(atom/holder, mob/user)
	. = list()
	for(var/datum/capability/C as anything in caps_ordered(holder, CAP_ORDER_EXAMINE))
		var/list/lines = C.examine(holder, user)
		if(lines)
			. += lines
	. += present_examine(holder, user) // the lines the engine's capabilities declare (code/engine/present/outputs.dm)

/// Adds every capability's UI data under data["caps"][C.ui_key()], one list per capability, so no
/// capability key collides with the holder's own (M11). /datum/tgui_data() callers merge it through ..().
/proc/caps_ui_data(atom/holder, mob/user, list/data)
	var/list/caps
	for(var/datum/capability/C as anything in caps_all(holder))
		var/list/mine = list()
		C.legacy_ui_data(holder, user, mine)
		if(!length(mine))
			continue
		caps ||= list()
		caps[C.ui_key()] = mine
	if(caps)
		data["caps"] = caps

// ---- periodic work from capabilities (cadence / cap_should_run / cap_periodic_step) ----

/// Any capability with periodic work that wants to run keeps the holder stepping.
/atom/should_run()
	. = ..()
	if(. || !(type_derive_flags(src) & TYPE_DERIVES_CAPS))
		return
	for(var/datum/capability/C as anything in caps_all(src))
		if(C.cadence && C.cap_should_run(src))
			return TRUE
	return FALSE

/// Steps every capability whose periodic work wants to run. A type with its own periodic_step()
/// calls ..() to keep its capabilities stepping.
/atom/periodic_step(delta)
	if(!(type_derive_flags(src) & TYPE_DERIVES_CAPS))
		return PROCESS_KILL
	var/stepped = FALSE
	for(var/datum/capability/C as anything in caps_all(src))
		if(C.cadence && C.cap_should_run(src))
			C.cap_periodic_step(src, delta)
			stepped = TRUE
	if(!stepped)
		return PROCESS_KILL

/// The type's capability declarations: its CAPABILITY() lines (parents first). type_list()'s builder: built once per
/// type, interned by caps_intern_list().
/atom/capability_declarations()
	. = list()
	declared_capabilities(.)
