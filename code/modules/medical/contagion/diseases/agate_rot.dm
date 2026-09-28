/datum/affliction/contagion/engineered/agate_rot/New(process = 1, datum/affliction/contagion/engineered/D, copy = 0)
	if(!D)
		name = "Agate Corruption"
		symptoms = list(new /datum/viral_trait/blobspores/agate, /datum/viral_trait/confusion, /datum/viral_trait/stimulant, /datum/viral_trait/heal/water)
	..(process, D, copy)
