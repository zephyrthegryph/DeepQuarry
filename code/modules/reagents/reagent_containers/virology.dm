/obj/item/reagent_containers/glass/beaker/vial/culture
	name = "virus culture"
	desc = "A bottle with a virus culture"
	var/list/data = list("donor" = null, "viruses" = null, "blood_DNA" = null, "blood_type" = null, "resistances" = null, "trace_chems" = null, "changeling"=FALSE) // ALLOW(instance_list): d: edited in place per instance (191 writers)
	var/list/diseases

	/// The disease the culture is grown from: one is made per vial when its init is complete, and the vial gets 10 units of blood carrying it.
	var/culture_disease

CAPABILITIES(/obj/item/reagent_containers/glass/beaker/vial/culture)
	owns_many(nameof(diseases))
	// After init, not in the reagents() preinit: the vial's ownership of its diseases is set up by then, so they go with it.
	after_init(0, then(PROC_REF(grow_culture)))

/// The culture's disease and the blood that carries it (its own `data`).
/obj/item/reagent_containers/glass/beaker/vial/culture/proc/grow_culture(datum/act/timer/A)
	if(!culture_disease)
		return
	rel_add(src, nameof(diseases), new culture_disease)
	data["viruses"] = (diseases || list())
	reagents.add_reagent(REAGENT_ID_BLOOD, 10, data)

/obj/item/reagent_containers/glass/beaker/vial/culture/cold
	name = "cold virus culture"
	desc = "A bottle with the common cold culture"
	culture_disease = /datum/affliction/contagion/engineered/cold

/obj/item/reagent_containers/glass/beaker/vial/culture/flu
	name = "flu virus culture"
	desc = "A bottle with the flu culture"
	culture_disease = /datum/affliction/contagion/engineered/flu

/obj/item/reagent_containers/glass/beaker/vial/culture/blobspores
	name = "blob spores culture"
	desc = "A bottle with blob spores"
	culture_disease = /datum/affliction/contagion/engineered/blobspores

/obj/item/reagent_containers/glass/beaker/vial/culture/macrophages
	name = "macrophages culture"
	desc = "A bottle with giant viruses"
	culture_disease = /datum/affliction/contagion/engineered/macrophage

/obj/item/reagent_containers/glass/beaker/vial/culture/random_virus
	name = "experimental disease culture bottle"
	desc = "A small bottle. Contains an untested viral culture."
	culture_disease = /datum/affliction/contagion/engineered/random

/obj/item/reagent_containers/glass/beaker/vial/culture/random_virus/minor
	name = "minor experimental disease culture bottle"
	desc = "A small bottle. Contains a weak version of an untested viral culture."
	culture_disease = /datum/affliction/contagion/engineered/random/minor
