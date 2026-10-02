/proc/gas_fx(air, air_contents, air1, cabin_air, environment, my_air_contents)
	air.temperature = 5
	air_contents.volume += 1
	air1.temperature *= 2
	cabin_air.volume=3
	environment.temperature = 4
	air.temperature = T.return_temperature()
	air.temperature == 5
	my_air.temperature = 3
	my_air_contents.volume = 1
	xair.temperature = 9
	air.volume = vol.return_volume()
	air.volume = 3 // ALLOW(check_grep): ok
