// Format a power value in W, kW, MW, or GW.
/proc/DisplayPower(powerused)
	if(powerused < 1000) //Less than a kW
		return "[powerused] W"
	else if(powerused < 1000000) //Less than a MW
		return "[round((powerused * 0.001),0.01)] kW"
	else if(powerused < 1000000000) //Less than a GW
		return "[round((powerused * 0.000001),0.001)] MW"
	return "[round((powerused * 0.000000001),0.0001)] GW"

/proc/split_into_3(total)
	if(!total || !isnum(total))
		return

	var/part1 = rand(0,total)
	var/part2 = rand(0,total)
	var/part3 = total-(part1+part2)

	if(part3<0)
		part1 = total-part1
		part2 = total-part2
		part3 = -part3

	return list(part1, part2, part3)
