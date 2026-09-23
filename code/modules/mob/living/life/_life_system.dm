// Life systems (doc/mob_life_architecture.md §4.2). One concern of a living mob's upkeep.
//
// A system is a singleton per type (flyweight): per-mob state lives on the mob, its body or a
// component, never on the system. Every call receives the mob as `self`.
//
// Families and variants. A family is one concern (breathing, environment, HUD, ...). Its root
// is a direct child of /datum/life_system (or of a `category` type). A family may have
// variants for particular mob types: the variant path mirrors the mob path under the family
// root, and its `mob_type` names the mob type it serves, for example
//	/datum/life_system/environment               mob_type = /mob/living
//	/datum/life_system/environment/carbon/human  mob_type = /mob/living/carbon/human
// A mob gets the variant with the most derived matching mob_type, and a variant's `..()`
// reaches the variant of the nearest ancestor mob type, exactly as the old handle_* override
// chains did.

/datum/life_system
	/// Readable name for logs and the profiler.
	var/name = "life system"
	/// Wake category (LIFE_SYS_*): the /mob/living/var/life_awake bit this system runs under.
	var/bit = LIFE_SYS_UPKEEP
	/// LIFE_PHASE_*: coarse position in the cycle.
	var/phase = LIFE_PHASE_BODY
	/// Position within the phase; lower runs first.
	var/order = 0
	/// Run every Nth cycle while awake.
	var/period = 1
	/// LIFE_SEG_* flags. If an earlier gate blocked any of them this cycle, the system is skipped.
	var/segment = NONE
	/// LIFE_SET_* flags of the Life sequences that include this family. Read from the family root.
	var/life_sets = LIFE_SET_LIVING
	/// The mob type this variant serves. The most derived match wins inside a family.
	var/mob_type = /mob/living
	/// TRUE on grouping types whose direct children are the family roots.
	var/category = FALSE
	/// TRUE for systems a mob gains only when something adds them (component systems).
	var/extra = FALSE
	/// Family root type. Filled by the registry.
	var/family
	/// What wakes this system once it sleeps (for logs and the audit). A system that can
	/// sleep says here which producers call life_wake() with its `bit`.
	var/woken_by

/// Does this mob get this system at all? Evaluated only when composing, so it may depend
/// only on what the composition key covers (the mob type and its extras).
/datum/life_system/proc/applies(mob/living/self)
	return TRUE

/// Register the signals, gas dependencies and timers that wake this system for this mob.
/// Called when a mob gains the system through composition.
/datum/life_system/proc/attach(mob/living/self)
	return

/// Undo attach(). Called when a mob loses the system (recomposition or deletion).
/datum/life_system/proc/detach(mob/living/self)
	return

/// Sleep rule (doc/mob_life_architecture.md §4.9). TRUE when this system has nothing to do
/// until something wakes its `bit`. Evaluated after every tick and by the hibernation
/// audit, so it must be cheap, read-only and correct for a mob that is not ticking: the
/// audit treats a FALSE on a sleeping system as a missed wake. The default never sleeps.
/datum/life_system/proc/idle(mob/living/self)
	return FALSE

/// For an idle system that still drifts slowly (ambience, AFK, darksight): deciseconds
/// until it should be woken anyway, or 0 to wait for an event.
/datum/life_system/proc/rewake_delay(mob/living/self)
	return 0

/// Do the work. Return LIFE_SLEEP when nothing is left to do until woken, LIFE_HALT to end
/// the cycle. `ctx` is null when the system runs outside the schedule (run_life_system()).
/datum/life_system/proc/tick(mob/living/self, datum/life_context/ctx)
	return

// --- Context ----------------------------------------------------------------------------------

/// Per-cycle facts shared by the systems of one mob's Life() call. Built once per cycle.
/datum/life_context
	/// Seconds since this mob's previous Life() (SSmobs passes it; nominal 2).
	var/seconds = LIFE_NOMINAL_SECONDS
	/// LIFE_SEG_* flags blocked by gates this cycle.
	var/blocked = NONE
	/// TRUE when SSmobs sampled this call for the per-system profiler.
	var/profile = FALSE
	/// The /mob/living core's legacy return value: 1 once the living-alive gate passed.
	var/living_result
	/// A subtype core's legacy return value (simple mobs: TRUE alive / FALSE dead).
	var/core_result
	/// The air this mob sits in (turf air, belly air or null), captured at the placed gate.
	var/datum/gas_mixture/environment
	/// TRUE when the body's stasis clock paused this cycle. Set once by Life()
	/// from /datum/body/proc/advance_stasis().
	var/stasis = FALSE
	/// Set by a gate that stopped the cycle for a reason no wake covers (transforming,
	/// nullspace): nothing goes to sleep this cycle.
	var/no_sleep = FALSE

/datum/life_context/New(seconds, profile)
	src.seconds = seconds
	src.profile = profile

/// Did stasis pause this cycle?
/datum/life_context/proc/in_stasis(mob/living/self)
	return stasis

// --- Registry ---------------------------------------------------------------------------------

/// type -> flyweight instance, for every /datum/life_system type.
GLOBAL_LIST_EMPTY(life_system_instances)
/// Family root types of the non-extra families, in type order.
GLOBAL_LIST_EMPTY(life_system_family_roots)
/// family root -> list of variant types in the family (root included).
GLOBAL_LIST_EMPTY(life_system_family_members)
/// family root -> (mob type -> resolved variant instance, or FALSE for none).
GLOBAL_LIST_EMPTY(life_system_variant_cache)
/// composition key -> /datum/life_composition shared by every mob with that key.
GLOBAL_LIST_EMPTY(life_system_compositions)
GLOBAL_VAR_INIT(life_system_registry_built, FALSE)

/// Builds the flyweights and family tables once.
/proc/build_life_system_registry()
	if(GLOB.life_system_registry_built)
		return
	GLOB.life_system_registry_built = TRUE
	var/list/instances = GLOB.life_system_instances
	for(var/path in subtypesof(/datum/life_system))
		instances[path] = new path
	for(var/path in instances)
		if(is_life_system_category(path))
			continue
		var/datum/life_system/S = instances[path]
		var/root = path
		while(TRUE)
			var/parent = type2parent(root)
			if(parent == /datum/life_system || is_life_system_category(parent))
				break
			root = parent
		S.family = root
		LAZYADD(GLOB.life_system_family_members[root], path)
		if(root == path && !S.extra)
			GLOB.life_system_family_roots += root
	log_world("LIFE_SYSTEMS: registry built: [length(instances)] system types, [length(GLOB.life_system_family_roots)] families")

/// TRUE for grouping types (`category = TRUE` directly under /datum/life_system). Their
/// subtypes inherit the var but are family roots, not categories.
/proc/is_life_system_category(path)
	if(type2parent(path) != /datum/life_system)
		return FALSE
	var/datum/life_system/S = GLOB.life_system_instances[path]
	return S.category

/// The flyweight for a system type.
/proc/get_life_system(path)
	if(!GLOB.life_system_registry_built)
		build_life_system_registry()
	return GLOB.life_system_instances[path]

/// The variant of `family` that serves mob type `mob_path`, or null.
/proc/resolve_life_system(family, mob_path)
	if(!GLOB.life_system_registry_built)
		build_life_system_registry()
	var/list/by_type = GLOB.life_system_variant_cache[family]
	if(!by_type)
		by_type = list()
		GLOB.life_system_variant_cache[family] = by_type
	var/datum/life_system/found = by_type[mob_path]
	if(!isnull(found))
		return found || null
	found = null
	var/best_depth = -1
	for(var/path in GLOB.life_system_family_members[family])
		var/datum/life_system/S = GLOB.life_system_instances[path]
		if(!ispath(mob_path, S.mob_type))
			continue
		// Implicit intermediate types (a path segment with no declaration, such as
		// breathing/silicon above breathing/silicon/robot) inherit their parent's mob_type;
		// only the family root and variants that declare their own mob_type count.
		if(path != family)
			var/datum/life_system/parent = GLOB.life_system_instances[type2parent(path)]
			if(parent.mob_type == S.mob_type)
				continue
		var/depth = length("[S.mob_type]")
		if(depth > best_depth)
			found = S
			best_depth = depth
	by_type[mob_path] = found || FALSE
	return found

/// One shared, ordered system list for every mob with the same composition key.
/datum/life_composition
	var/key
	/// Systems in run order. Never mutated after composition.
	var/list/ordered
	/// Union of the systems' bits. A bit no system has can never go to sleep.
	var/bits = NONE

/datum/life_composition/New(key, list/ordered)
	src.key = key
	src.ordered = ordered
	for(var/datum/life_system/S as anything in ordered)
		bits |= S.bit

/// Sort key: phase, then order. Stable insertion sort; compositions are small and built once.
/proc/sort_life_systems(list/systems)
	for(var/i in 2 to length(systems))
		var/datum/life_system/S = systems[i]
		var/key = S.phase * 100000 + S.order
		var/j = i - 1
		while(j >= 1)
			var/datum/life_system/prev = systems[j]
			if(prev.phase * 100000 + prev.order <= key)
				break
			systems[j + 1] = prev
			j--
		systems[j + 1] = S
	return systems

/// Composes (or reuses) the system list for a mob.
/proc/compose_life_systems(mob/living/L)
	if(!GLOB.life_system_registry_built)
		build_life_system_registry()
	var/key = "[L.type]"
	if(LAZYLEN(L.life_extra_systems))
		var/list/extras = list()
		for(var/path in L.life_extra_systems)
			extras += "[path]"
		sortTim(extras, GLOBAL_PROC_REF(cmp_text_asc))
		key += "|[jointext(extras, ",")]"
	var/datum/life_composition/comp = GLOB.life_system_compositions[key]
	if(comp)
		return comp
	var/list/systems = list()
	for(var/family in GLOB.life_system_family_roots)
		var/datum/life_system/root = GLOB.life_system_instances[family]
		if(!(root.life_sets & L.life_set))
			continue
		var/datum/life_system/S = resolve_life_system(family, L.type)
		if(S && S.applies(L))
			systems += S
	for(var/path in L.life_extra_systems)
		var/datum/life_system/S = GLOB.life_system_instances[path]
		if(S && (S.life_sets & L.life_set) && S.applies(L))
			systems += S
	sort_life_systems(systems)
	comp = new(key, systems)
	GLOB.life_system_compositions[key] = comp
	var/list/names = list()
	for(var/datum/life_system/S as anything in systems)
		names += S.name
	log_runtime("LIFE_SYSTEMS: composed [key] ([length(systems)] systems): [jointext(names, ", ")]")
	return comp
