// Kernel measurement: the systems every measured cost is charged to.
//
// A "system" is a named owner of work. There are three kinds:
//  - KM_KIND_OM: an object-model behaviour family (life, machines, ai_brain, lighting, ...). Every
//    /datum/om/behaviour and /datum/om/pipeline maps to one, bound once at boot by km_bind_behaviours().
//  - KM_KIND_MC: a firing MC subsystem ("mc_air", "mc_lighting"), bound when it first fires. SSbehaviours is
//    not one: its cost is decomposed into the OM systems it runs (its remainder is "om_core").
//  - KM_KIND_PSEUDO: work no behaviour or subsystem owns (om_core, om_native, input, other).
//
// HOW A BEHAVIOUR GETS ITS SYSTEM (the whole rule; nothing else decides):
//  1. `system_key` on the behaviour type, when set. Inline behaviours (rows of a bundle's reacts / ticks /
//     events tables) get the bundle's name, e.g. `/datum/om/bundle/powered_machine` -> "powered_machine".
//  2. The first row of KM_SYSTEM_ROWS whose type-path prefix matches "[type]". This is where a code folder's
//     ownership is written down: the row for a folder lists that folder's behaviour types, so a new behaviour
//     joins its folder's system by adding its type to the row (or by setting `system_key`).
//  3. Otherwise the family rule: `/datum/om/behaviour/world/<x>` and `/datum/om/behaviour/sleeper/<x>` -> "<x>",
//     `/datum/om/behaviour/internal/<x>` -> "om_core", any other `/datum/om/behaviour/<x>[/...]` or
//     `/datum/om/pipeline/<x>[/...]` -> "<x>". A behaviour therefore always has a system, and a system nobody
//     named shows up under the behaviour's own name, which is what an overrun report needs to point at.
// A unit test (dq_km_*) checks every registered behaviour resolves and that the folder rows name real types.
//
// The table is static and built once. The registry below only ever grows and is shared by every meter, so a
// system's index means the same thing in a test meter and the live one.

// The two singletons (the systems table and the live meter) are made on first use through km_systems() and
// km_meter(), not as GLOBAL_DATUM_INIT: the OM registry builds inside the global variable controller's New(),
// before any global initialiser has run, and binds every behaviour to a system as it goes.

/// Holds the singletons. Tests replace `meter` with a probe for a few statements.
/datum/km_holder
	var/datum/km_systems/systems
	var/datum/tick_meter/meter
	/// km_system_prefixes(), built on first use.
	var/list/prefixes

/proc/km_holder()
	RETURN_TYPE(/datum/km_holder)
	var/static/datum/km_holder/holder
	if(!holder)
		holder = new
	return holder

/// The systems table.
/proc/km_systems()
	RETURN_TYPE(/datum/km_systems)
	var/datum/km_holder/holder = km_holder()
	if(!holder.systems)
		holder.systems = new
	return holder.systems

/// The live tick meter.
/proc/km_meter()
	RETURN_TYPE(/datum/tick_meter)
	var/datum/km_holder/holder = km_holder()
	if(!holder.meter)
		holder.meter = new
	return holder.meter

/datum/km_systems
	/// Index -> key. Indices are stable for the life of the world.
	var/list/keys
	var/list/index_by_key
	/// Index -> KM_KIND_*.
	var/list/kinds
	/// Index -> bitmask of (1 << lane) for the OM lanes the system's behaviours run in.
	var/list/lane_masks

/datum/km_systems/New()
	keys = list()
	index_by_key = list()
	kinds = list()
	lane_masks = list()
	// The pseudo systems take fixed indices: hot paths charge them by constant.
	index_for(KM_KEY_OM_CORE, KM_KIND_PSEUDO)
	index_for(KM_KEY_OM_NATIVE, KM_KIND_PSEUDO)
	index_for(KM_KEY_INPUT, KM_KIND_PSEUDO)
	index_for(KM_KEY_OTHER, KM_KIND_PSEUDO)
	index_for(KM_KEY_OM_APPEARANCE, KM_KIND_PSEUDO)
	if(length(keys) != KM_SYS_PSEUDO_COUNT || keys[KM_SYS_OM_CORE] != KM_KEY_OM_CORE || keys[KM_SYS_OM_NATIVE] != KM_KEY_OM_NATIVE || keys[KM_SYS_INPUT] != KM_KEY_INPUT || keys[KM_SYS_OTHER] != KM_KEY_OTHER || keys[KM_SYS_OM_APPEARANCE] != KM_KEY_OM_APPEARANCE)
		CRASH("km: the pseudo system indices no longer match their KM_SYS_* constants")

/// The index of `key`, registering it first if it is new. Past KM_MAX_SYSTEMS the overflow is KM_SYS_OTHER.
/datum/km_systems/proc/index_for(key, kind = KM_KIND_OM, lane = 0)
	var/idx = index_by_key[key]
	if(!idx)
		if(length(keys) >= KM_MAX_SYSTEMS)
			return KM_SYS_OTHER
		keys += key
		kinds += kind
		lane_masks += 0
		idx = length(keys)
		index_by_key[key] = idx
	if(lane)
		lane_masks[idx] |= (1 << lane)
	return idx

/// The key of system `idx`, or "?" when it does not exist.
/datum/km_systems/proc/key_of(idx)
	return (idx >= 1 && idx <= length(keys)) ? keys[idx] : "?"

/datum/km_systems/proc/count()
	return length(keys)

/// "urgent+sim" style label of the OM lanes a system runs in; the kind name for MC and pseudo systems.
/datum/km_systems/proc/lane_label(idx)
	var/kind = kinds[idx]
	if(kind == KM_KIND_MC)
		return "mc"
	if(kind == KM_KIND_PSEUDO)
		return idx == KM_SYS_INPUT ? "input" : "om"
	var/static/list/lane_names = list("urgent", "sim", "derived", "present", "bg", "world")
	var/list/parts = list()
	var/mask = lane_masks[idx]
	for(var/lane in 1 to OM_LANE_COUNT)
		if(mask & (1 << lane))
			parts += lane_names[lane]
	return length(parts) ? jointext(parts, "+") : "om"

// ---------------------------------------------------------------- the rule

/// Code-folder ownership of behaviour types: key -> the type paths (prefixes) whose behaviours it owns.
/// First match wins, so list a specific type before a broader prefix. Keep a row's comment naming its folder.
/proc/km_system_rows()
	// Not a static: this runs while the OM registry builds inside the global variable controller's New(), before
	// proc statics holding type paths are set up (a static here read as null and the table came out empty).
	var/list/rows = list(
		// code/datums/om/: the scheduler's own behaviours (expiry, rates, timers, tasks, io, ui pushes, edges) and
		// the sleeper/timed bases in pipeline.dm.
		"om_core" = list(/datum/om/behaviour/internal, /datum/om/behaviour/sleeper/timed),
	)
	return rows

/// The prefix -> key list km_system_rows() flattens to: "/datum/om/behaviour/observer_upkeep" = "life", ... in row order.
/proc/km_system_prefixes()
	var/datum/km_holder/holder = km_holder()
	if(!length(holder.prefixes))
		var/list/built = list()
		var/list/rows = km_system_rows()
		for(var/key in rows)
			for(var/path in rows[key])
				built["[path]"] = key
		holder.prefixes = built
	return holder.prefixes

/// The system key of a behaviour type path (rules 2 and 3 above). Matching is by path prefix at a "/" boundary,
/// so a `life` row owns `life_derive` too (life*) but not `/datum/om/pipeline/lifeboat/x`.
/proc/km_system_key_for_path(path)
	var/text = "[path]"
	var/list/prefixes = km_system_prefixes()
	for(var/prefix in prefixes)
		if(findtext(text, prefix) != 1)
			continue
		// Family-name prefixes (life -> life_derive) match on the bare prefix; anything else must end at a segment.
		var/rest = copytext(text, length(prefix) + 1)
		if(!length(rest) || copytext(rest, 1, 2) == "/" || copytext(rest, 1, 2) == "_")
			return prefixes[prefix]
	return km_family_key(text)

/// Rule 3: the family fallback.
/proc/km_family_key(text)
	var/rest = text
	if(findtext(text, "/datum/om/behaviour/") == 1)
		rest = copytext(text, length("/datum/om/behaviour/") + 1)
	else if(findtext(text, "/datum/om/pipeline/") == 1)
		rest = copytext(text, length("/datum/om/pipeline/") + 1)
	var/list/segments = splittext(rest, "/")
	if(!length(segments) || !length(segments[1]))
		return KM_KEY_OTHER
	var/first = segments[1]
	if(first == "internal")
		return KM_KEY_OM_CORE
	if((first == "world" || first == "sleeper") && length(segments) >= 2)
		return segments[2]
	return first

/// The system key of the inline behaviours a bundle or decl declares: the bundle's own name
/// (`/datum/om/bundle/powered_machine` -> "powered_machine").
/proc/km_bundle_key(datum/om/bundle/bundle)
	var/list/segments = splittext("[bundle.type]", "/")
	return segments[length(segments)]

/// Binds every behaviour of a freshly built OM registry to its system (called at the end of build_behaviours()).
/proc/km_bind_behaviours(list/behaviours)
	var/datum/km_systems/systems = km_systems()
	for(var/datum/om/behaviour/B as anything in behaviours)
		B.system_idx = systems.index_for(B.system_key || km_system_key_for_path(B.type), KM_KIND_OM, B.lane)
