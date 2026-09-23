/datum/modifier/medbeameffect
	name = "medgunffect"
	desc = "You're being stabilized"
	mob_overlay_state = "medigun_effect"
	stacks = MODIFIER_STACK_EXTEND
	// only a little
	factors = alist(BF_BLEEDING = 0.1, BF_DEMAND = 0)
