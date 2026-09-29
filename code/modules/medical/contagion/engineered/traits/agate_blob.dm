/datum/viral_trait/blobspores/agate
	name = "Agate Infection"
	desc = "This symptom causes the host to produce blob spores, which will leave the host at the later stages, and if the host dies, all of the spores will erupt from the host at the same time, while also producing a blob tile."
	stealth = 6
	resistance = 3
	stage_speed = -3
	transmission = -2
	level = -1
	threat = 3
	naturally_occuring = FALSE
	symptom_delay_min = 20 SECONDS
	symptom_delay_max = 40 SECONDS

/datum/viral_trait/blobspores/agate/pop(datum/affliction/contagion/engineered/A, mob/living/M)
	if(!A || !M)
		return
	var/list/blob_options = list(/obj/structure/blob/normal)
	if(factory_blob)
		blob_options += /obj/structure/blob/factory
	if(strong_blob)
		blob_options += /obj/structure/blob/shield
	if(node_blob)
		blob_options += /obj/structure/blob/node
	new /obj/structure/blob/core/living_agate(M.loc)

	act_message(M, null, others = span_danger("A huge mass of blob and blob spores burst out of %U%!"))
