// Per-call cost of a mover's step and of an atom's integrity accessors, now that last_move and atom_integrity are sparse slots.
//   tools/build/build.sh bench --scenario=move_integrity [--arg=steps=50000] [--arg=rounds=5]
// Each figure is the best of `rounds` loops, in microseconds per call. "plain_var_write" and "plain_var_read" are the cost of an
// ordinary var access in the same loop shape, so the sparse figures can be read against them.

/datum/benchmark/move_integrity
	id = "move_integrity"
	description = "Per-step Move() cost and integrity accessor cost with sparse last_move and atom_integrity"

/datum/benchmark/move_integrity/proc/best_us(name, list/best, calls)
	best[name] = min(best[name] || INFINITY, rustg_time_microseconds("move_integrity") / calls)

/datum/benchmark/move_integrity/Run()
	wait_for_assets()
	var/steps = param("steps", 50000)
	var/rounds = param("rounds", 5)
	var/list/turf/open/turfs = build_floor_fixture(6)
	var/turf/A = turfs[1]
	var/turf/B = get_step(A, EAST)
	var/obj/item/mover = new /obj/item(A)
	var/obj/structure/closet/target = new /obj/structure/closet(B)
	var/list/best = list()
	var/plain = 0
	for(var/round in 1 to rounds)
		stoplag()
		rustg_time_reset("move_integrity")
		for(var/i in 1 to steps)
			mover.Move(i & 1 ? B : A, i & 1 ? EAST : WEST)
		best_us("move_step_us", best, steps)
		stoplag()
		rustg_time_reset("move_integrity")
		for(var/i in 1 to steps)
			mover.forceMove(i & 1 ? B : A)
		best_us("force_move_us", best, steps)
		stoplag()
		rustg_time_reset("move_integrity")
		for(var/i in 1 to steps)
			sparse_set_or(mover, last_move, EAST, 0)
		best_us("last_move_set_us", best, steps)
		stoplag()
		rustg_time_reset("move_integrity")
		for(var/i in 1 to steps)
			plain = sparse_get_or(mover, last_move, 0)
		best_us("last_move_get_us", best, steps)
		stoplag()
		rustg_time_reset("move_integrity")
		for(var/i in 1 to steps)
			plain = i
		best_us("plain_var_write_us", best, steps)
		stoplag()
		rustg_time_reset("move_integrity")
		for(var/i in 1 to steps)
			plain = mover.pixel_x
		best_us("plain_var_read_us", best, steps)
		stoplag()
		rustg_time_reset("move_integrity")
		for(var/i in 1 to steps)
			plain = target.get_integrity()
		best_us("get_integrity_intact_us", best, steps)
		stoplag()
		rustg_time_reset("move_integrity")
		for(var/i in 1 to steps)
			target.update_integrity(i & 1 ? target.max_integrity - 1 : target.max_integrity)
		best_us("update_integrity_toggle_us", best, steps)
		stoplag()
		rustg_time_reset("move_integrity")
		for(var/i in 1 to steps / 10)
			target.take_damage(1, BRUTE, "melee", FALSE)
			target.repair_damage(1)
		best_us("damage_repair_pair_us", best, steps / 10)
	for(var/name in best)
		metric(name, best[name], "us/call")
	qdel(mover)
	qdel(target)
