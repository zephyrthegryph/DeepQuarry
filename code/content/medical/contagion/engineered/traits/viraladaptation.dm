/*
//////////////////////////////////////
Viral adaptation

	Moderate stealth boost.
	Major Increases to resistance.
	Reduces stage speed.
	No change to transmission
	Critical Level.

BONUS
	Extremely useful for buffing viruses

//////////////////////////////////////
*/
/datum/viral_trait/viraladaptation
	name = "Viral Self-Adaptation"
	desc = "The virus mimics the function of normal body cells, becoming harder to spot and to eradicate, but reducing it's speed."
	stealth = 3
	resistance = 5
	stage_speed = -3
	transmission = 0
	level = 4
	threat = 0

	prefixes = list("Chronic ")
