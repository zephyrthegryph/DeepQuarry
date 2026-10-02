/proc/organ_fx(organ, affecting, liver, E, heart)
	organ.take_damage(5)
	affecting.damage += 3
	liver.damage = 1
	E.heal_damage(2)
	my_organ.take_damage(1)
	take_damage(5, LESION_HEAL)
	take_damage(5, /datum/affliction/lesion)
	x.apply_lesion_damage(1)
	LESION_HEAL_X
	organ.take_damage(1) // ALLOW(check_grep)
	organ.take_damage(2) // ALLOW(check_grep): reason
	heart.damage == 3
	organ?.heal_damage(1)
	brain.damage++
	lungs.damage--
	internal_organs_by_name[BP_LIVER]?.heal_damage(1)
