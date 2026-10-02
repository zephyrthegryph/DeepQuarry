/proc/body_fx(M)
	add_chemical_effect(1)
	remove_chemical_effect(2)
	M.chem_effects
	isSynthetic(M)
	isSyntheticX(M)
	// ALLOW(check_grep): above-line does not count
	isSynthetic(M)
	isSynthetic(M) // ALLOW(other, check_grep): ok
	isSynthetic(M) // ALLOW(check_grep)
	isSynthetic(M) // ALLOW(check_grep): reason here
	robotic >= ORGAN_ROBOT
	robotic<ORGAN_ASSISTED
	robotic > ORGAN_ASSISTED
	robotic <= ORGAN_ASSISTED
	robotic == ORGAN_ROBOT
	M.nutrition += 5
	M.nutrition = 5
	M.nutrition == 5
	nutrition += 1
	nutrition = 1
	INJURY_ASPHYXIA
	INJURY_CATEGORY_ASPHYXIA
	BF_INCOMING_ASPHYXIA
	INJURY_ASPHYXIAX
	mechanical_effects
	od_boost
	incoming_brute_percent
	foo_injury_resistance
	M.slowdown
	mod.accuracy
	Mod.slowdown
	bodytemperature = 5
	M.bodytemperature += 3
	bodytemperature++
	bodytemp = 5
	bodytemperature == 3
	var/bodytemperature = 300
	// bodytemperature = 3
