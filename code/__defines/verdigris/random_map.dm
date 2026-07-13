/proc/verdigris_generate_automata(limit_x, limit_y, iterations, initial_wall_cell) as /list
	RETURN_TYPE(/list)
	// byondapi #[bind] suffixes the exported symbol with "_ffi".
	return VERDIGRIS_CALL("generate_automata_ffi", limit_x, limit_y, iterations, initial_wall_cell)
