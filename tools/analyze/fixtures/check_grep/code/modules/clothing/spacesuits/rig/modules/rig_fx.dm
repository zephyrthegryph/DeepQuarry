/proc/rig_fx(cell, acell)
	cell.use(5)
	cell.give(2)
	cell.use(units, FALSE)
	cell.give(joules * CELLRATE, FALSE)
	acell.use(3)
	cell.use(1) // ALLOW(check_grep): ok
