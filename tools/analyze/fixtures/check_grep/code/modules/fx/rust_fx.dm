/proc/rust_fx(T)
	x = T.atmos_adjacent_turfs
	y = current_cycle
	z = immediate_calculate_adjacent_turfs(T)
	// atmos_adjacent_turfs
	 * current_cycle doc
	w = atmos_supeconductivity
	vg_foo(x, "[y]")
	vg_foo(x)
	vg_bar(x, "[y]") // ALLOW(check_grep): ok
	// vg_baz(x, "[y]")
