// Aggregators (doc/rewrite/rules.md §1). One combine rule per PROP_AGG_*,
// consistent with the body factor rules in code/modules/body/factors.dm:
// PRODUCT is BF_RULE_MULT at full scale, SUM is BF_RULE_ADD, and MAX, MIN and
// OR are BF_RULE_MAX, BF_RULE_MIN and BF_RULE_FLAGS. Null means "no value"
// and is the identity for every rule.

/proc/dq_property_valid_aggregator(agg)
	return agg == PROP_AGG_NONE || agg == PROP_AGG_PRODUCT || agg == PROP_AGG_SUM || agg == PROP_AGG_MAX || agg == PROP_AGG_MIN || agg == PROP_AGG_OR

/// Combine two values under `agg`.
/proc/dq_property_combine(agg, a, b)
	if(isnull(a))
		return b
	if(isnull(b))
		return a
	switch(agg)
		if(PROP_AGG_SUM)
			return a + b
		if(PROP_AGG_PRODUCT)
			return a * b
		if(PROP_AGG_MAX)
			return max(a, b)
		if(PROP_AGG_MIN)
			return min(a, b)
		if(PROP_AGG_OR)
			return a | b
	CRASH("property aggregator [agg] cannot combine values")

/// Aggregate property `id` over `things` (datums) with its aggregator.
/proc/dq_property_aggregate(id, list/things)
	var/datum/property_def/def = dq_property_registry().defs[id]
	if(!def)
		CRASH("unknown property [id]")
	. = null
	for(var/datum/D as anything in things)
		. = dq_property_combine(def.aggregator, ., dq_property(D, id))

/// Keeps an aggregate current as values are added and removed, without
/// rescanning. MIN and MAX keep a count per value, so a removal rescans the
/// distinct values only when the last copy of the extreme leaves. OR keeps a
/// count per bit. This is what the ledger (track C) uses per container.
/datum/property_accumulator
	var/aggregator
	/// SUM and PRODUCT: the running total. MIN, MAX and OR: the cached result.
	var/total
	/// PRODUCT: zeros added so far (they can't be divided back out).
	var/zeros = 0
	/// MIN and MAX: value -> count. OR: bit -> count.
	var/alist/counts
	var/entries = 0

/datum/property_accumulator/New(aggregator)
	..()
	if(aggregator == PROP_AGG_NONE || !dq_property_valid_aggregator(aggregator))
		CRASH("a property accumulator needs an aggregator, got [aggregator]")
	src.aggregator = aggregator
	if(aggregator == PROP_AGG_MIN || aggregator == PROP_AGG_MAX || aggregator == PROP_AGG_OR)
		counts = alist()

/datum/property_accumulator/proc/add(value)
	if(isnull(value))
		return
	entries++
	switch(aggregator)
		if(PROP_AGG_SUM)
			total = (total || 0) + value
		if(PROP_AGG_PRODUCT)
			if(value == 0)
				zeros++
			else
				total = (isnull(total) ? 1 : total) * value
		if(PROP_AGG_MIN, PROP_AGG_MAX)
			counts[value] = (counts[value] || 0) + 1
			total = dq_property_combine(aggregator, total, value)
		if(PROP_AGG_OR)
			for(var/bit in 0 to PROP_TAG_WORD_BITS - 1)
				if(value & (1 << bit))
					counts[bit] = (counts[bit] || 0) + 1
			total = (total || 0) | value

/datum/property_accumulator/proc/remove(value)
	if(isnull(value))
		return
	entries--
	switch(aggregator)
		if(PROP_AGG_SUM)
			total -= value
		if(PROP_AGG_PRODUCT)
			if(value == 0)
				zeros--
			else
				total /= value
		if(PROP_AGG_MIN, PROP_AGG_MAX)
			var/count = counts[value]
			if(!count)
				CRASH("removed [value] from a property accumulator that does not hold it")
			if(count > 1)
				counts[value] = count - 1
				return
			counts -= value
			if(value != total)
				return
			total = null
			for(var/v in counts)
				total = dq_property_combine(aggregator, total, v)
		if(PROP_AGG_OR)
			for(var/bit in 0 to PROP_TAG_WORD_BITS - 1)
				if(!(value & (1 << bit)))
					continue
				counts[bit] = counts[bit] - 1
				if(counts[bit] <= 0)
					counts -= bit
					total &= ~(1 << bit)

/// The aggregate, or null when empty.
/datum/property_accumulator/proc/value()
	if(entries <= 0)
		return null
	if(aggregator == PROP_AGG_PRODUCT)
		if(zeros)
			return 0
		return isnull(total) ? 1 : total
	return total
