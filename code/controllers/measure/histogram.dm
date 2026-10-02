// Kernel measurement: fixed log-spaced histograms.
//
// KM_HIST_BINS bins of milliseconds (KM_HIST_MIN_MS, KM_HIST_RATIO in code/__defines/kernel_measure.dm) give
// p50 / p95 / p99 with no sort and no copy, by the same rank walk Kernel.performance_window() uses over its
// 1%-wide tick histogram. Adding a sample is one bin lookup and no allocation.
//
// Within a bin the percentile is interpolated linearly and clamped to the exact min and max seen, so a bin
// full of identical samples reads back as that value instead of its lower edge.

/// Lower edge of histogram bin `bin` in ms (bin 1 starts at 0).
/proc/km_hist_lower(bin)
	var/static/list/edges
	if(!edges)
		var/list/built = new /list(KM_HIST_BINS)
		built[1] = 0
		for(var/i in 2 to KM_HIST_BINS)
			built[i] = KM_HIST_MIN_MS * (KM_HIST_RATIO ** (i - 2))
		edges = built
	return edges[bin]

/// Upper edge of bin `bin` in ms; the last bin has none (callers use the max seen).
/proc/km_hist_upper(bin)
	return bin >= KM_HIST_BINS ? INFINITY : km_hist_lower(bin + 1)

/// A histogram of milliseconds.
/datum/km_hist
	var/list/bins
	var/count = 0
	var/min_seen = 0
	var/max_seen = 0

/datum/km_hist/New()
	bins = new /list(KM_HIST_BINS)
	for(var/i in 1 to KM_HIST_BINS)
		bins[i] = 0

/datum/km_hist/proc/add(value)
	var/bin = KM_HIST_BIN(value)
	bins[bin] = bins[bin] + 1
	if(!count || value < min_seen)
		min_seen = value
	if(value > max_seen)
		max_seen = value
	count++

/datum/km_hist/proc/reset()
	for(var/i in 1 to KM_HIST_BINS)
		bins[i] = 0
	count = 0
	min_seen = 0
	max_seen = 0

/// The value at fraction `p` (0..1) of the samples, in ms. 0 when empty.
/datum/km_hist/proc/percentile(p)
	if(!count)
		return 0
	// Rounded first: 100 * 0.99 is 99.0000009 in single precision and would otherwise ceil to rank 100.
	var/rank = max(ceil(round(count * p, 0.0001)), 1)
	var/cumulative = 0
	for(var/bin in 1 to KM_HIST_BINS)
		var/n = bins[bin]
		if(!n)
			continue
		if(cumulative + n >= rank)
			var/lower = km_hist_lower(bin)
			var/upper = bin >= KM_HIST_BINS ? max(max_seen, lower) : km_hist_upper(bin)
			return clamp(lower + (upper - lower) * ((rank - cumulative) / n), min_seen, max_seen)
		cumulative += n
	return max_seen

/// A small linear histogram for "how far into the tick did this run": KM_DEPTH_BINS bins of
/// KM_DEPTH_BIN_WIDTH percent, the last open ended.
/datum/km_depth_hist
	var/list/bins
	var/count = 0

/datum/km_depth_hist/New()
	bins = new /list(KM_DEPTH_BINS)
	for(var/i in 1 to KM_DEPTH_BINS)
		bins[i] = 0

/datum/km_depth_hist/proc/add(usage_percent)
	var/bin = clamp(floor(usage_percent / KM_DEPTH_BIN_WIDTH), 0, KM_DEPTH_BINS - 1) + 1
	bins[bin] = bins[bin] + 1
	count++

/datum/km_depth_hist/proc/reset()
	for(var/i in 1 to KM_DEPTH_BINS)
		bins[i] = 0
	count = 0

/// The upper edge, in percent of a tick, of the bin holding fraction `p` of the samples.
/datum/km_depth_hist/proc/percentile(p)
	if(!count)
		return 0
	var/rank = max(ceil(round(count * p, 0.0001)), 1)
	var/cumulative = 0
	for(var/bin in 1 to KM_DEPTH_BINS)
		cumulative += bins[bin]
		if(cumulative >= rank)
			return bin * KM_DEPTH_BIN_WIDTH
	return KM_DEPTH_BINS * KM_DEPTH_BIN_WIDTH

/// Everything one set of accumulators records about one system.
/datum/system_stats
	var/key
	var/kind = KM_KIND_OM
	/// ms charged per tick, over the ticks the system was charged in (an idle tick is not a 0 sample).
	var/datum/km_hist/hist
	/// Ticks the system was charged in.
	var/ticks = 0
	/// Total ms as a low part plus a high part in whole KM_FLUSH_MS steps (single precision cannot add 0.05 to 1e6).
	var/ms_lo = 0
	var/ms_hi = 0
	/// Total ms charged on ticks with usage over KM_OVERRUN_USAGE.
	var/overrun_ms = 0
	/// Ticks the system was among the top KM_TOP_N of an overrun tick.
	var/overrun_top_ticks = 0
	/// Worst lateness (ds) any of its OM slots started with.
	var/late_max = 0

/datum/system_stats/New(key, kind)
	src.key = key
	src.kind = kind
	hist = new

/// Folds one tick's charge in.
/datum/system_stats/proc/record(ms, overrun, late)
	hist.add(ms)
	ticks++
	ms_lo += ms
	if(ms_lo >= KM_FLUSH_MS)
		ms_lo -= KM_FLUSH_MS
		ms_hi += KM_FLUSH_MS
	if(overrun)
		overrun_ms += ms
	if(late > late_max)
		late_max = late

/datum/system_stats/proc/ms_total()
	return ms_hi + ms_lo

/datum/system_stats/on_destroy(force)
	QDEL_NULL(hist)
	..()
