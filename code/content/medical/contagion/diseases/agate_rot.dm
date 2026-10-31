/datum/affliction/contagion/engineered/agate_rot/New(process = 1, datum/affliction/contagion/engineered/D, copy = 0)
	if(!D)
		name = "Agate Corruption"
		rel_add(src, nameof(symptoms), new /datum/viral_trait/blobspores/agate)
		rel_add(src, nameof(symptoms), new /datum/viral_trait/confusion)
		rel_add(src, nameof(symptoms), new /datum/viral_trait/stimulant)
		rel_add(src, nameof(symptoms), new /datum/viral_trait/heal/water)
	..(process, D, copy)
