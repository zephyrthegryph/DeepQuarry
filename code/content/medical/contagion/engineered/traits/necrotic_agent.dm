/*
//////////////////////////////////////

Necrotic Agent

	Very Noticable.
	Lowers resistance resistance considerably.
	Decreases stage speed.
	Reduced transmittable.
	Critical Level.

Bonus
	Makes the disease work on corpses

//////////////////////////////////////
*/

/datum/viral_trait/necrotic_agent
	name = "Necrotic Agent"
	desc = "Allows the virus to infect corpses, and work on the dead."
	stealth = 2
	resistance = -2
	stage_speed = -1
	transmission = 0
	level = 6
	threat = 3

/datum/viral_trait/necrotic_agent/OnAdd(datum/affliction/contagion/engineered/A)
	A.set_virus_modifiers(A.virus_modifiers | SPREAD_DEAD)

/datum/viral_trait/necrotic_agent/OnRemove(datum/affliction/contagion/engineered/A)
	A.set_virus_modifiers(A.virus_modifiers & ~SPREAD_DEAD)
