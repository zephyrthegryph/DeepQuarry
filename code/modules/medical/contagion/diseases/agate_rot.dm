/datum/affliction/contagion/engineered/agate_rot/New(process = 1, datum/affliction/contagion/engineered/D, copy = 0)
	if(!D)
		name = "Agate Corruption"
		own_add(src, nameof(symptoms), new /datum/viral_trait/blobspores/agate)
		own_add(src, nameof(symptoms), new /datum/viral_trait/confusion)
		own_add(src, nameof(symptoms), new /datum/viral_trait/stimulant)
		own_add(src, nameof(symptoms), new /datum/viral_trait/heal/water)
	..(process, D, copy)
