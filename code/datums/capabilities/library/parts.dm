// cap_parts(): a machine's component parts as the source of its derived stats (doc/rewrite/migration_guide.md A4,
// archive/framework_fixes.md §9.5). It replaces a RefreshParts() override that recomputed ratings by hand.
//
//	/obj/machinery/cell_charger/capabilities()
//		. = ..()
//		. += cap_parts(list(
//			part_stat(nameof(efficiency), /obj/item/stock_parts/capacitor, base = 1, per = 0.5, scale = nameof(active_power_usage)),
//		))
//
// The parts are the machine's owned `component_parts` relation (plus latent entries that are still data, roadmap C6):
// nothing about them is copied. Each part_stat() is a DERIVED value: the holder var it names is written from the parts,
// never by hand, whenever the parts change: the owned relation publishes `component_parts` (an on_change reaction of
// this capability) and every legacy RefreshParts() caller (default_apply_parts(), frame construction, the RPED) reaches
// /obj/machinery/RefreshParts(), which recomputes them. A stat:
//	value = base + per * (aggregate - offset)            aggregate: PART_RATING_SUM (default) / _AVG / _MIN / _MAX / _COUNT
//	value *= holder.vars[scale]                          when `scale` names a holder var (a type default such as active_power_usage)
//	value = call(holder, derive)()                       when `derive` is a PROC_REF of the holder (anything the formula can't say;
//	                                                     read the parts with part_rating(src, type, mode))
// The RPED (a part replacer) is this capability's op, "replace_parts" (it upgrades through default_part_replacement()).
// A derived stat changing publishes its var like a TRACKED setter, so draw()/UI/reactions that read it follow.

/// part_stat() aggregates over the matching installed parts.
#define PART_RATING_SUM 1
#define PART_RATING_AVG 2
#define PART_RATING_MIN 3
#define PART_RATING_MAX 4
#define PART_RATING_COUNT 5

/datum/capability/parts
	/// /datum/part_stat flyweights, in declaration order.
	var/list/stats
	/// TRUE: a part replacer (RPED) upgrades the parts through the "replace_parts" op.
	var/rped = TRUE

/// One derived stat of cap_parts(). Shared, never written after part_stat() returns it.
/datum/part_stat
	/// The holder var it writes.
	var/var_name
	var/part_type
	var/mode = PART_RATING_SUM
	var/base = 0
	var/per = 1
	var/offset = 1
	/// A holder var multiplying the result, or null.
	var/scale
	/// A PROC_REF of the holder computing the value instead, or null.
	var/derive

/**
 * A derived stat for cap_parts(): holder var `var_name` = (base + per * (aggregate - offset)) [* holder.vars[scale]], the
 * aggregate (mode PART_RATING_*) taken over the installed parts of `part_type`. With `derive` (a PROC_REF of the holder,
 * no arguments), the holder computes the value itself.
 */
/proc/part_stat(var_name, part_type, base = 0, per = 1, offset = 1, mode = PART_RATING_SUM, scale, derive)
	var/datum/part_stat/S = new
	S.var_name = var_name
	S.part_type = part_type
	S.base = base
	S.per = per
	S.offset = offset
	S.mode = mode
	S.scale = scale
	S.derive = derive
	return S

/// The parts capability: `stats` (part_stat() entries) derived from the installed parts; rped: the RPED op.
/proc/cap_parts(list/stats, rped = TRUE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/parts/C = new
	C.stats = stats || list()
	C.rped = rped
	return cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/// The RPED op, "replace_parts": a part replacer's click upgrades the parts (refused while the machine isn't working).
/datum/capability/parts/interactions(atom/holder)
	if(!rped)
		return null
	return list(adopt_entry(lib_op("Replace parts", GLOBAL_PROC_REF(cap_parts_replace), OP_SHAPE_USE_ON, using = /obj/item/storage/part_replacer, key = "replace_parts", priority = OP_PRIORITY_PART, needs = req_working()), id = "parts:rped"))

/// The parts relation changing re-derives the stats (a part moved in or out by any path that writes the relation).
/datum/capability/parts/reactions()
	. = ..()
	. += cap_rx(src, on_change(list(nameof(/obj/machinery::component_parts)), PROC_REF(parts_changed)))

/datum/capability/parts/proc/parts_changed(atom/holder, list/keys)
	refresh(holder)

/datum/capability/parts/on_holder_init(atom/holder, mapload)
	refresh(holder)

/// Writes every derived stat on holder from its installed parts. A value that changed publishes its var.
/datum/capability/parts/proc/refresh(atom/holder)
	if(QDELETED(holder))
		return
	for(var/datum/part_stat/S as anything in stats)
		var/value = value_of(holder, S)
		if(holder.vars[S.var_name] == value)
			continue
		holder.vars[S.var_name] = value // ALLOW(api): a derived stat's one writer is its capability: the var is declared by part_stat()
		tracked_changed(holder, S.var_name)

/// The value stat S derives on holder now. Pure.
/datum/capability/parts/proc/value_of(atom/holder, datum/part_stat/S)
	if(S.derive)
		return call(holder, S.derive)()
	. = S.base + S.per * (part_rating(holder, S.part_type, S.mode) - S.offset)
	if(S.scale)
		. *= holder.vars[S.scale]

/**
 * The aggregate (PART_RATING_*) of holder's installed parts of `part_type`: real parts and, on a machine, latent ones
 * still held as data (roadmap C6), read without materializing them. 0 when it has none (MIN / AVG too).
 */
/proc/part_rating(atom/holder, part_type, mode = PART_RATING_SUM)
	var/count = 0
	var/total = 0
	var/low
	var/high
	var/list/real = ismachinery(holder) ? holder.slot_contents(CONTAINER_SLOT_INTERNALS) : holder.contents
	for(var/obj/item/stock_parts/P in real)
		if(!istype(P, part_type))
			continue
		count++
		total += P.rating
		low = isnull(low) ? P.rating : min(low, P.rating)
		high = isnull(high) ? P.rating : max(high, P.rating)
	if(ismachinery(holder))
		for(var/datum/latent_entry/entry as anything in holder.latent_entries(CONTAINER_SLOT_INTERNALS))
			if(!ispath(entry.path, part_type))
				continue
			var/rating = dq_type_var(entry.path, "rating")
			count += entry.count
			total += rating * entry.count
			low = isnull(low) ? rating : min(low, rating)
			high = isnull(high) ? rating : max(high, rating)
	if(!count)
		return 0
	switch(mode)
		if(PART_RATING_AVG)
			return total / count
		if(PART_RATING_MIN)
			return low
		if(PART_RATING_MAX)
			return high
		if(PART_RATING_COUNT)
			return count
	return total

/// Re-derives holder's cap_parts() stats now (nothing without the capability).
/proc/parts_refresh(atom/holder)
	var/datum/capability/parts/C = cap_of(holder, /datum/capability/parts)
	C?.refresh(holder)

/// The RPED op's handler: the machine's part replacement, then the stats follow the relation.
/proc/cap_parts_replace(atom/holder, mob/user, obj/item/held)
	var/obj/machinery/M = holder
	if(!istype(M))
		return FALSE
	M.default_part_replacement(user, held)
	parts_refresh(M)
	return TRUE
