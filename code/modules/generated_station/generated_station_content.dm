/// Cosmetic filler options used after a room definition's functional features.
/// Infrastructure machinery is excluded because the topology pass owns it.
/proc/generated_room_cosmetic_palette(department_id, module_role)
	switch(department_id)
		if("command")
			return list(/obj/structure/filingcabinet, /obj/structure/flora/pottedplant, /obj/structure/closet/crate/internals)
		if("ai")
			return list(/obj/structure/closet/crate/engineering/electrical, /obj/structure/filingcabinet, /obj/structure/closet/crate/internals)
		if("security")
			return list(/obj/structure/closet/secure_closet/security, /obj/structure/filingcabinet/security, /obj/structure/closet/crate/internals)
		if("medical")
			return list(/obj/structure/closet/secure_closet/medical1, /obj/structure/filingcabinet, /obj/structure/closet/crate/medical)
		if("engineering")
			return list(/obj/structure/closet/secure_closet/engineering_electrical, /obj/structure/filingcabinet, /obj/structure/closet/crate/engineering/electrical, /obj/structure/closet/crate/engineering)
		if("logistics")
			return list(/obj/structure/closet/secure_closet/cargotech, /obj/structure/closet/crate, /obj/structure/filingcabinet, /obj/structure/closet/crate/engineering)
		if("docking")
			return list(/obj/structure/closet/crate/internals, /obj/structure/flora/pottedplant, /obj/structure/filingcabinet)
	return list(/obj/structure/filingcabinet, /obj/structure/closet/crate)

/datum/generated_station_materializer/proc/department_id_for_module(datum/generated_station_module/module)
	if(!nodes_by_id || !module)
		return null
	var/datum/generated_station_layout_node/node = nodes_by_id[module.department_node_id]
	if(!node)
		return null
	var/datum/generated_station_department_instance/department = department_for_node(node)
	return department?.definition?.id
