/*
//////////////////////////////////////
Viral evolution

	Moderate stealth reduction.
	Major decreases to resistance.
	increases stage speed.
	increase to transmission
	Critical Level.

BONUS
	Extremely useful for buffing viruses

//////////////////////////////////////
*/
/datum/viral_trait/viralevolution
	name = "Viral Evolutionary Acceleration"
	desc = "The virus quickly adapts to spread as fast as possible both outside and inside a host. This, however, makes the virus easier to spot, and les able to fight off a cure."
	stealth = -2
	resistance = -3
	stage_speed = 5
	transmission = 3
	level = 4

	prefixes = list("Unstable ")
