/datum/modifier/trait/thickdigits
	name = "Thick Digits"
	desc = "Your hands cannot properly wield weapons."

/datum/modifier/trait/empresist
	name = "Emp Resist"
	desc = "You are resistant to EMPs."
	factors = alist(BF_EMP_SHIFT = 1)

/datum/modifier/trait/empresistb
	name = "Major Emp Resist"
	desc = "You are resistant to EMPs."
	factors = alist(BF_EMP_SHIFT = 2)

/datum/modifier/trait/empweakness
	name = "Emp Weakness"
	desc = "You are weak to EMPs."
	factors = alist(BF_EMP_SHIFT = -1)

/datum/modifier/trait/majorempweakness
	name = "Major Emp Weakness"
	desc = "You are weak to EMPs."
	factors = alist(BF_EMP_SHIFT = -2)
