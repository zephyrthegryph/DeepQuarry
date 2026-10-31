/obj/item/reagent_containers/glass/beaker/vial/culture
	name = "virus culture"
	desc = "A bottle with a virus culture"
	var/list/data = list("donor" = null, "viruses" = null, "blood_DNA" = null, "blood_type" = null, "resistances" = null, "trace_chems" = null, "changeling"=FALSE) // ALLOW(instance_list): d: edited in place per instance (191 writers)
	var/list/diseases

	/// The disease the culture is grown from: one is made per vial, and the vial starts with 10 units of blood carrying it.
	var/culture_disease

CAPABILITIES(/obj/item/reagent_containers/glass/beaker/vial/culture)
	owns_many(nameof(diseases))
	configure(reagents(add = list(REAGENT_ID_BLOOD = PROC_REF(culture_blood_units)), data = list(REAGENT_ID_BLOOD = PROC_REF(culture_blood_data))))

/// 10 units of blood when the culture names a disease, none otherwise.
/obj/item/reagent_containers/glass/beaker/vial/culture/proc/culture_blood_units()
	return culture_disease ? 10 : 0

/// The culture's blood data: its own `data`, carrying the disease made for this vial.
/obj/item/reagent_containers/glass/beaker/vial/culture/proc/culture_blood_data()
	if(culture_disease)
		rel_add(src, nameof(diseases), new culture_disease)
	data["viruses"] = (diseases || list())
	return data

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
