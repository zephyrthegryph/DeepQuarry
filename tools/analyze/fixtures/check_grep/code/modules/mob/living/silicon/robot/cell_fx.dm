/proc/robot_cell_fx(cell)
	cell.charge -= 5
	cell.use(1)
	cell.give(1)
	cell.checked_use(1)
	cell.charge = 5
	cell.charge == 5
	cell.charge*=2
	cell.use(2) // ALLOW(check_grep): x
