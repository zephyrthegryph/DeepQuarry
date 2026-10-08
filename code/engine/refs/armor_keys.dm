/proc/injury_armor_key(kind)
	switch(kind)
		if(INJURY_BLUNT, INJURY_CUT)
			return "melee"
		if(INJURY_PIERCE)
			return "bullet"
		if(INJURY_BURN)
			return "laser"
		if(INJURY_ELECTRIC, INJURY_PAIN)
			return "energy"
		if(ARMOR_BLAST)
			return "bomb"
		if(INJURY_TOXIN, INJURY_CORROSIVE)
			return "bio"
		if(INJURY_RADIATION)
			return "rad"
	return null
