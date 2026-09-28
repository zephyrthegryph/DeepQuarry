GLOBAL_DATUM_INIT(ammo_repository, /datum/repository/ammomaterial, new)

/datum/repository/ammomaterial
	var/list/ammotypes

/datum/repository/ammomaterial/New()
	ammotypes = list()
	..()

/// `ammo_type`: an /obj/item/ammo_casing type path (the table is keyed by type).
/datum/repository/ammomaterial/proc/get_materials_from_object(ammo_type)

	if(!(ammo_type in ammotypes))
		ammotypes += ammo_type
		var/obj/item/ammo_casing/temp = new ammo_type
		ammotypes[ammo_type] = temp.material_totals()
		qdel(temp)

	return ammotypes[ammo_type]
