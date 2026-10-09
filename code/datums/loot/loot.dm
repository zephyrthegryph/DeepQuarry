// One declared loot system (doc/rewrite/systems.md §8). Declarations: code/library/loot/loot_entries.dm.
//
// A type's loot(...) entry (or, until the declarations are converted, DECLARE_LOOT) makes the shared /datum/loot_decl that loot_decl_for(path)
// answers. loot_spawn() rolls and creates, with a seeded /datum/loot_rng so map loot is reproducible per round seed. /obj/random is resolved at
// map time through resolve_loot() (its map_resolver entry) and never becomes a live atom. loot_search() is the tiered roll used by searchable piles.

/// The round's loot seed: every map-time roll is seeded from it and the roll's position and type.
GLOBAL_VAR_INIT(loot_seed, rand(0, LOOT_HASH_MOD - 1))
/// Runtime rolls mix this serial in, so two runtime rolls on one tile differ.
GLOBAL_VAR_INIT(loot_roll_serial, 0)
/// How many times each depleting loot source has been searched, by REF.
GLOBAL_LIST_EMPTY(loot_times_searched)

// ---- declarations ----

/datum/loot_decl
	/// FALSE until build() ran.
	var/built = FALSE
	/// The main weighted table, or null.
	var/datum/loot_entry/sub/main_table
	var/count = 1
	/// Percent chance that anything spawns.
	var/chance = 100
	/// Entries that always spawn.
	var/list/all
	var/hook
	/// The table roll is fixed per round (LOOT_PER_ROUND): rolling path -> its pick, once made.
	var/per_round = FALSE
	var/list/round_picks

	// Search tiers (loot_search()).
	var/datum/loot_entry/sub/unlucky
	var/datum/loot_entry/sub/uncommon
	var/datum/loot_entry/sub/rare
	var/uncommon_chance = 0
	var/rare_chance = 0
	var/gamma_chance = 0
	var/loot_left = 0
	var/delete_on_depletion = FALSE
	var/repeat_search = FALSE

CAPABILITIES(/datum/loot_decl)
	owns_one(nameof(main_table), /datum/loot_entry/sub)
	owns_one(nameof(rare), /datum/loot_entry/sub)
	owns_one(nameof(uncommon), /datum/loot_entry/sub)
	owns_one(nameof(unlucky), /datum/loot_entry/sub)


/// The merged spec list (a legacy DECLARE_LOOT overrides this, merging over ..()).
/datum/loot_decl/proc/specs()
	return null

/// Builds the declaration from its loot() entry (loot_entries.dm): the rows the entry names.
/datum/loot_decl/proc/build_entry(datum/entry/E)
	built = TRUE
	var/list/rows = E.args
	var/any = FALSE
	for(var/name in rows)
		if(!isnull(rows[name]))
			any = TRUE
			break
	if(!any)
		return FALSE
	if(rows["table"])
		rel_set(src, nameof(main_table), new /datum/loot_entry/sub(1, rows["table"]))
	if(!isnull(rows["count"]))
		count = rows["count"]
	if(!isnull(rows["chance"]))
		chance = rows["chance"]
	all = rows["all"]
	hook = rows["hook"]
	per_round = !!rows["per_round"]
	if(rows["unlucky"])
		rel_set(src, nameof(unlucky), new /datum/loot_entry/sub(1, rows["unlucky"]))
	var/list/tier = rows["uncommon"]
	if(tier)
		uncommon_chance = tier[1] || 0
		rel_set(src, nameof(uncommon), new /datum/loot_entry/sub(1, tier[2]))
	tier = rows["rare"]
	if(tier)
		rare_chance = tier[1] || 0
		rel_set(src, nameof(rare), new /datum/loot_entry/sub(1, tier[2]))
	gamma_chance = rows["gamma_chance"] || 0
	var/list/depletion = rows["depletion"]
	if(depletion)
		loot_left = depletion[1] || 0
		delete_on_depletion = !!depletion[2]
	repeat_search = !!rows["repeat_search"]
	return TRUE

/// Builds the declaration from a legacy DECLARE_LOOT spec list (removed with DECLARE_LOOT).
/datum/loot_decl/proc/build()
	built = TRUE
	var/list/S = specs()
	if(!length(S))
		return FALSE
	if(S["table"])
		rel_set(src, nameof(main_table), new /datum/loot_entry/sub(1, S["table"]))
	if(!isnull(S["count"]))
		count = S["count"]
	if(!isnull(S["chance"]))
		chance = S["chance"]
	all = S["all"]
	hook = S["hook"]
	per_round = !!S["per_round"]
	if(S["unlucky"])
		rel_set(src, nameof(unlucky), new /datum/loot_entry/sub(1, S["unlucky"]))
	if(S["uncommon"])
		rel_set(src, nameof(uncommon), new /datum/loot_entry/sub(1, S["uncommon"]))
	if(S["rare"])
		rel_set(src, nameof(rare), new /datum/loot_entry/sub(1, S["rare"]))
	uncommon_chance = S["uncommon_chance"] || 0
	rare_chance = S["rare_chance"] || 0
	gamma_chance = S["gamma_chance"] || 0
	loot_left = S["loot_left"] || 0
	delete_on_depletion = !!S["delete_on_depletion"]
	repeat_search = !!S["repeat_search"]
	return TRUE

/// DECLARE_LOOT plumbing: `mine` replaces the keys it names in the parent's specs. What spawns
/// (table, all, per_round) is one unit: a declaration naming any of it replaces all of it.
/proc/loot_merge_specs(list/parent, list/mine)
	if(!length(parent))
		return mine
	var/list/merged = parent.Copy()
	if(("table" in mine) || ("all" in mine) || ("per_round" in mine))
		merged -= list("table", "all", "per_round")
	for(var/key in mine)
		merged[key] = mine[key]
	return merged

/// type => its /datum/loot_decl, for every type under one that declares loot(...): built at world setup (loot_entries.dm), never after.
GLOBAL_LIST_EMPTY(loot_decls)

/// The loot declaration for `path`: a type with a loot entry or under one, or (until the declarations are converted) a /datum/loot_decl path, or a
/// type with a DECLARE_LOOT on it or an ancestor. Null when there is none.
/proc/loot_decl_for(path)
	RETURN_TYPE(/datum/loot_decl)
	if(isnull(path))
		return null
	static_entries_ensure("loot_decl_for([path])")
	var/datum/loot_decl/decl = GLOB.loot_decls[path]
	if(decl)
		return decl
	return CACHED(legacy_loot_decls, path) || null

DECLARE_SHARED_CACHE(legacy_loot_decls, GLOBAL_PROC_REF(build_loot_decl), SC_NEVER)

/// Builds the legacy DECLARE_LOOT declaration for `path` (the legacy cache's builder), or null.
/proc/build_loot_decl(path)
	var/datum/loot_decl/decl
	var/decl_type
	if(ispath(path, /datum/loot_decl))
		decl_type = path
	else
		// The declaration types mirror the target paths, so DM inheritance already resolves
		// undeclared intermediates; walk up only past types that have no declaration node at all.
		var/text = "[path]"
		while(length(text) > 1)
			decl_type = text2path("/datum/loot_decl[text]")
			if(decl_type)
				break
			var/cut = findlasttext(text, "/")
			if(cut <= 1)
				break
			text = copytext(text, 1, cut)
	if(decl_type)
		decl = new decl_type
		if(!decl.build())
			decl = null
	return decl

// ---- table entries ----

/// One non-path table entry. Weighted by `weight` in the table that holds it.
/datum/loot_entry
	var/weight = 1

/datum/loot_entry/New(weight)
	src.weight = weight

/// Creates this entry's atoms (see loot_emit()).
/datum/loot_entry/proc/emit(atom/loc, datum/loot_rng/rng, list/direct, list/nested)
	return

/// Every entry spawns.
/datum/loot_entry/group
	var/list/entries

/datum/loot_entry/group/New(weight, list/entries)
	..()
	src.entries = entries

/datum/loot_entry/group/emit(atom/loc, datum/loot_rng/rng, list/direct, list/nested)
	for(var/entry in entries)
		loot_emit(entry, loc, rng, direct, nested)

/// A weighted pick among entries (paths weighted by their assoc value, default 1, or entry datums).
/datum/loot_entry/sub
	var/list/entries
	var/list/weights
	var/total = 0

/datum/loot_entry/sub/New(weight, list/source)
	..()
	entries = list()
	weights = list()
	for(var/entry in source)
		var/entry_weight
		if(istype(entry, /datum/loot_entry))
			var/datum/loot_entry/E = entry
			entry_weight = E.weight
		else
			entry_weight = source[entry]
			if(!isnum(entry_weight))
				entry_weight = 1
		if(entry_weight <= 0)
			continue
		entries += entry
		weights += entry_weight
		total += entry_weight

/// One entry, rolled with rng.
/datum/loot_entry/sub/proc/pick_entry(datum/loot_rng/rng)
	if(!total)
		return null
	var/roll = rng.next() * total
	for(var/i in 1 to length(entries))
		roll -= weights[i]
		if(roll < 0)
			return entries[i]
	return entries[length(entries)]

/datum/loot_entry/sub/emit(atom/loc, datum/loot_rng/rng, list/direct, list/nested)
	loot_emit(pick_entry(rng), loc, rng, direct, nested)

/// A computed list of paths, each weighing the entry's weight.
/datum/loot_entry/sub/types

/datum/loot_entry/sub/types/New(weight, list/source)
	..(weight, source)
	src.weight = weight * length(entries)

/// A stack with an amount.
/datum/loot_entry/stack
	var/path
	var/amount

/datum/loot_entry/stack/New(weight, path, amount)
	..()
	src.path = path
	src.amount = amount

/datum/loot_entry/stack/emit(atom/loc, datum/loot_rng/rng, list/direct, list/nested)
	direct += new path(loc, amount)

// ---- seeded rng ----

/// Wichmann-Hill: three small LCGs whose products stay exact in BYOND's floats.
/datum/loot_rng
	var/s1 = 1
	var/s2 = 1
	var/s3 = 1

/datum/loot_rng/New(seed)
	seed = abs(round(seed))
	s1 = (seed % 30268) + 1
	s2 = (round(seed / 7) % 30306) + 1
	s3 = (round(seed / 13) % 30322) + 1
	next()
	next()

/// A float in [0, 1).
/datum/loot_rng/proc/next()
	s1 = (171 * s1) % 30269
	s2 = (172 * s2) % 30307
	s3 = (170 * s3) % 30323
	var/sum = s1 / 30269 + s2 / 30307 + s3 / 30323
	return sum - round(sum)

/// TRUE with `percent` percent probability.
/datum/loot_rng/proc/chance(percent)
	return next() * 100 < percent

/// A stable hash of a type path (djb2-style, kept under LOOT_HASH_MOD so it stays exact).
/proc/loot_type_hash(path)
	return CACHED(loot_type_hashes, path)

DECLARE_SHARED_CACHE(loot_type_hashes, GLOBAL_PROC_REF(build_loot_type_hash), SC_NEVER)

/// Computes loot_type_hash()'s value for `path` (its cache builder). A pure table (/loot/...) keeps the text its declaration type had before the tables
/// became types of their own (/datum/loot_decl/loot/...), so the rolls a round's seed gives are the same as they were.
/proc/build_loot_type_hash(path)
	var/text = "[path]"
	if(ispath(path, /loot))
		text = "/datum/loot_decl[text]"
	var/h = 5381 % LOOT_HASH_MOD
	for(var/i in 1 to length(text))
		h = (h * 31 + text2ascii(text, i)) % LOOT_HASH_MOD
	return h

/// The rng for a roll of `path` at `loc`: seeded from the round seed, the position and the type,
/// plus a serial when the roll happens after map load.
/proc/loot_rng_at(atom/loc, path)
	var/turf/T = get_turf(loc)
	var/h = GLOB.loot_seed % LOOT_HASH_MOD
	h = (h * 31 + (T ? T.x : 0)) % LOOT_HASH_MOD
	h = (h * 31 + (T ? T.y : 0)) % LOOT_HASH_MOD
	h = (h * 31 + (T ? T.z : 0)) % LOOT_HASH_MOD
	h = (h * 31 + loot_type_hash(path)) % LOOT_HASH_MOD
	if(SSatoms.atom_initialized == INITIALIZATION_INNEW_REGULAR)
		GLOB.loot_roll_serial = (GLOB.loot_roll_serial + 1) % LOOT_HASH_MOD
		h = (h * 31 + GLOB.loot_roll_serial) % LOOT_HASH_MOD
	return new /datum/loot_rng(h)

// ---- rolling and spawning ----

/// Rolls `path`'s declared loot at `loc` and creates it. `varedits` are the map edits of the
/// spawner (read by hooks). Returns every atom created (nested tables included), or null; the
/// ones this declaration created itself (not nested tables) are also added to `direct_out`.
/// A path with no declaration is simply created.
/proc/loot_spawn(path, atom/loc, list/varedits, datum/loot_rng/rng, list/direct_out)
	var/datum/loot_decl/decl = loot_decl_for(path)
	if(!rng)
		rng = loot_rng_at(loc, path)
	var/list/direct = list()
	var/list/nested = list()
	if(!decl)
		loot_emit(path, loc, rng, direct, nested)
	else
		if(decl.chance < 100 && !rng.chance(decl.chance))
			return null
		if(decl.main_table)
			for(var/i in 1 to decl.count)
				var/entry
				if(decl.per_round)
					entry = LAZYACCESS(decl.round_picks, path)
					if(!entry)
						entry = decl.main_table.pick_entry(new /datum/loot_rng(GLOB.loot_seed + loot_type_hash(path)))
						LAZYSET(decl.round_picks, path, entry)
				else
					entry = decl.main_table.pick_entry(rng)
				loot_emit(entry, loc, rng, direct, nested)
		for(var/entry in decl.all)
			loot_emit(entry, loc, rng, direct, nested)
		if(decl.hook)
			for(var/atom/A as anything in direct)
				if(!QDELETED(A))
					call(decl.hook)(A, path, varedits, rng)
	if(direct_out)
		direct_out += direct
	if(!length(direct) && !length(nested))
		return null
	return direct + nested

/// Creates one table entry at `loc`: what it creates itself goes to `direct`; entries with a loot
/// declaration or a map resolver of their own roll through it, and what they create goes to `nested`.
/proc/loot_emit(entry, atom/loc, datum/loot_rng/rng, list/direct, list/nested)
	if(isnull(entry))
		return
	if(istype(entry, /datum/loot_entry))
		var/datum/loot_entry/E = entry
		E.emit(loc, rng, direct, nested)
		return
	if(!ispath(entry))
		CRASH("loot_emit: bad loot entry [entry]")
	if(ispath(entry, /datum/loot_decl) || ispath(entry, /loot))
		nested += loot_spawn(entry, loc, null, rng)
		return
	if(ispath(entry, /turf))
		var/turf/T = get_turf(loc)
		if(T)
			direct += T.ChangeTurf(entry, 1, 1, FALSE)
		return
	var/resolver = map_resolver_proc(entry)
	if(resolver == GLOBAL_PROC_REF(resolve_loot))
		nested += resolve_loot(loc, entry, null, rng)
		return
	if(resolver)
		call(resolver)(loc, entry, null)
		return
	direct += new entry(loc)

// ---- /obj/random ----

CAPABILITIES(/obj/random)
	map_resolver(GLOBAL_PROC_REF(resolve_loot), vars = list("drop_get_turf"))

/// MAP_RESOLVER for /obj/random: rolls its declaration where the spawner stands and applies the
/// spawner's mapped offset and direction to what it made. Returns what it created (TRUE-ish for
/// the map loader even when the roll made nothing: the spawner is resolved either way).
/proc/resolve_loot(atom/loc, path, list/varedits, datum/loot_rng/rng)
	var/atom/where = loc
	if(ispath(path, /obj/random))
		var/obj/random/P = path
		if(where && MAP_VAR(P, varedits, drop_get_turf))
			where = get_turf(where)
	var/list/direct = list()
	var/list/made = loot_spawn(path, where, varedits, rng, direct)
	if(length(varedits) && length(direct))
		var/has_px = ("pixel_x" in varedits)
		var/has_py = ("pixel_y" in varedits)
		var/has_dir = ("dir" in varedits)
		for(var/atom/A as anything in direct)
			if(QDELETED(A) || isturf(A))
				continue
			if(has_px)
				A.pixel_x = varedits["pixel_x"]
			if(has_py)
				A.pixel_y = varedits["pixel_y"]
			if(has_dir)
				A.set_dir(varedits["dir"])
	return made || list()

// ---- searchable loot ----

/obj/structure
	/// The loot declaration searching this drops from (LOOT_REF(/loot/...)), or null.
	var/loot_decl

/// Searches `source` (a pile with `loot_decl`) for `L`: the tiered roll of loot piles. `searched_by`
/// is the source's list of ckeys that searched it. `wake_chance`: percent chance a raccoon jumps out.
/proc/loot_pile_search(obj/structure/source, mob/living/L, list/searched_by, wake_chance = 0)
	var/datum/loot_decl/decl = loot_decl_for(source.loot_decl)
	if(!decl)
		return
	var/source_ref = REF(source)
	if(decl.loot_left)
		var/looted_count = GLOB.loot_times_searched[source_ref]
		if(looted_count >= decl.loot_left)
			to_chat(L, span_warning("\The [source] has been picked clean."))
			return

	if(decl.chance < 100 && !prob(decl.chance))
		to_chat(L, span_warning("Nothing in \the [source] really catches your eye..."))
		return

	if(L && islist(searched_by))
		if((L.ckey in searched_by) && !decl.repeat_search)
			to_chat(L, span_warning("You can't find anything else vaguely useful in \the [source].  Another set of eyes might, however."))
			return
		searched_by |= L.ckey

	var/datum/loot_rng/rng = loot_rng_at(source, source.loot_decl)
	var/datum/loot_entry/sub/tier = decl.main_table
	var/span = "notice"
	var/obj/item/gamma
	if(has_trait(L, TRAIT_UNLUCKY) && decl.unlucky)
		tier = decl.unlucky
		span = "cult"
		if(prob(1))
			to_chat(L, span_danger("You cut your hand on something in the trash!"))
			L.injure(INJURY_CUT, 2, pick(BP_L_HAND, BP_R_HAND), source)
			var/datum/affliction/contagion/engineered/random/random_disease = new /datum/affliction/contagion/engineered/random()
			random_disease.set_spread_flags(random_disease.spread_flags | DISEASE_SPREAD_NON_CONTAGIOUS)
			L.force_contagion(random_disease)
	else if(decl.uncommon && prob(decl.uncommon_chance))
		tier = decl.uncommon
		span = "alium"
	else if(decl.rare && prob(decl.rare_chance))
		tier = decl.rare
		span = "cult"
	else if(decl.gamma_chance && prob(decl.gamma_chance) && length(GLOB.unique_gamma_loot))
		gamma = loot_produce_gamma(source, decl, rng)
		span = "cult"

	var/atom/movable/loot = gamma
	if(!loot && tier)
		var/list/made = list()
		loot_emit(tier.pick_entry(rng), source, rng, made, made)
		for(var/atom/movable/AM as anything in made)
			if(!loot)
				loot = AM
			AM.forceMove(get_turf(source))
	if(!loot)
		return
	var/final_message = "You found \a [loot]!"
	switch(span)
		if("notice")
			final_message = span_notice(final_message)
		if("cult")
			final_message = span_cult(final_message)
		if("alium")
			final_message = span_alium(final_message)
	to_chat(L, span_info(final_message))
	if(rand(1, 100) <= wake_chance)
		new /mob/living/simple_mob/animal/passive/raccoon(get_turf(source))
		source.visible_message("A raccoon jumps out of the trash!.")

	if(!decl.loot_left)
		return
	GLOB.loot_times_searched[source_ref] = GLOB.loot_times_searched[source_ref] + 1
	if(GLOB.loot_times_searched[source_ref] < decl.loot_left)
		return
	to_chat(L, span_warning("You seem to have gotten the last of the spoils in \the [source]."))
	if(decl.delete_on_depletion)
		source.expire(0)

/// A unique item from GLOB.unique_gamma_loot (reclaiming one whose holder is gone when the pool
/// is empty), or a rare-tier item when none is left.
/proc/loot_produce_gamma(obj/structure/source, datum/loot_decl/decl, datum/loot_rng/rng)
	var/path = pick_n_take(GLOB.unique_gamma_loot)
	if(!path)
		for(var/P in GLOB.allocated_gamma_loot)
			var/obj/item/I = allocated_gamma_item(P)
			if(QDELETED(I) || istype(I.loc, /obj/machinery/computer/cryopod))
				restore_gamma_loot(P)
				path = P
				break
	if(path)
		var/obj/item/I = new path(source)
		GLOB.allocated_gamma_loot |= path
		SSpois.allocate_gamma_item(I)
		return I
	if(decl.rare)
		var/list/made = list()
		loot_emit(decl.rare.pick_entry(rng), source, rng, made, made)
		return length(made) ? made[1] : null
	return null

/// Restores a removed gamma loot item back to the pool.
/proc/restore_gamma_loot(w_type)
	GLOB.allocated_gamma_loot -= w_type
	var/obj/item/I = allocated_gamma_item(w_type)
	if(I)
		SSpois.release_gamma_item(I)
	GLOB.unique_gamma_loot += w_type

/// The live item spawned for gamma loot path `w_type`, or null (it was deleted, or never spawned).
/proc/allocated_gamma_item(w_type)
	for(var/obj/item/I as anything in SSpois.gamma_items())
		if(I.type == w_type)
			return I
	return null
