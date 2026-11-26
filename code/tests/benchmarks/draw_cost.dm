// What one draw costs: a few thousand drawn atoms of the station are drawn again as first draws (their applied look forgotten, so each draw is
// applied), in one window. --profile names where a draw's time goes.
//   tools/build/build.sh bench --scenario=draw_cost [--arg=draws=4000] [--profile]

/datum/benchmark/draw_cost
	id = "draw_cost"
	description = "Cost of a first draw: drawn station atoms redrawn with their applied look forgotten"

/datum/benchmark/draw_cost/Run()
	wait_for_assets()
	var/limit = param("draws", 4000)
	var/list/atom/drawn = list()
	var/list/by_type = list()
	for(var/atom/A in world)
		if(!isnull(A.rx?.look_key) && !QDELETED(A))
			drawn += A
			by_type["[A.type]"]++
			if(length(drawn) >= limit)
				break
		CHECK_TICK
	count_metric("draw_cost_atoms", length(drawn), "atoms", "none")
	by_type = sortTim(by_type, GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
	if(length(by_type) > 15)
		by_type.Cut(16)
	detail("draw_cost_types", by_type)
	var/total_ms = 0
	begin_window()
	for(var/atom/A as anything in drawn)
		if(QDELETED(A))
			continue
		rx_of(A).look_key = null
		var/stamp = TICK_USAGE_REAL
		refresh_look(A)
		total_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp)
		CHECK_TICK
	end_window("draw_cost")
	metric("draw_cost_us_per_draw", length(drawn) ? total_ms * 1000 / length(drawn) : 0, "us")
