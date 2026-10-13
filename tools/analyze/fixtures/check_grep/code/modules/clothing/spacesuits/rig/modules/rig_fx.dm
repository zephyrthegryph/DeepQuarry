/proc/rig_fx(cell, acell)
	cell.use(5)
	cell.give(2)
	cell.use(units)
	cell.give(joules * CELLRATE)
	acell.use(3)
	cell.use(1) // ALLOW(check_grep): ok
